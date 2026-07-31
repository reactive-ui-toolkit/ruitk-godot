class_name RuitkReconciler
extends RefCounted
## The fiber reconciler. Ports ReactiveUIToolKit's FiberReconciler:
##
##   render phase   -> begin_work (reconcile children, run components) descending, then
##                     complete_work (create/diff host nodes, build the effect list) on
##                     the way back up. Post-order effect list = children before parents.
##   commit phase   -> deletions -> effect list (placement/update/layout effects) ->
##                     enforce child order -> swap current<->wip -> two-pass passive
##                     effects -> release the old tree -> replay deferred updates.
##
## Update renders are TIME-SLICED by default (family parity): the work loop yields
## after `RuitkConfig.time_slice_ms` (the quantum, checked AFTER each completed unit — no
## preemption) and continues as a self-re-enqueueing RuitkScheduler Normal-lane slice under
## the scheduler's cumulative `frame_budget_ms`; `RuitkConfig.time_slicing = false` opts
## back into the synchronous single-pass render per update. The initial mount (`render()`)
## and HMR flushes are ALWAYS synchronous; the commit is atomic either way. An update
## arriving while a pass is in flight or parked is DEFERRED and replayed after commit,
## coalesced into ONE follow-up render (defer-don't-restart; setState-in-render loops
## terminate via the render-depth-25 guard). A render FAILURE (the `RuitkFail` latch) is
## the only thing that restarts a pass — the boundary fallback lands in the same commit,
## capped at `_MAX_ERROR_RESTARTS` rebuilds.
##
## Updates are coalesced (a hook setter schedules one render pass per frame). Bailout
## skips re-running a component's render fn when its props/state/context/children are
## unchanged (reusing the cached output); fibers are double-buffered — each pass reuses
## the committed tree's ping-pong buddies instead of allocating fresh ones, and same-shape
## host children are reused IN PLACE via the fast-leaf-list path.
##
## GDScript divergences vs the C# original:
##   - No exceptions: a failing render cooperatively CALLS `RuitkFail.render(reason)` (it
##     cannot throw); the latch is consumed after each component render and unwinds to the
##     nearest error boundary (`_handle_render_failure`). A real GDScript crash (bad index,
##     call on null) still cannot be auto-caught — that limitation survives.

const F = preload("res://addons/reactive_ui_toolkit/core/fiber.gd")
const Hmr = preload("res://addons/reactive_ui_toolkit/core/hmr.gd")
const Scheduler = preload("res://addons/reactive_ui_toolkit/core/scheduler.gd")

## --- Fast Refresh registry (Phase H) ---------------------------------------------------------
## Live reconcilers. Registration is unconditional (one WeakRef append per root — negligible,
## and it keeps HMR headless-testable); the debugger-channel hookup in hmr.gd is what gates the
## actual feature to editor-attached runs. WeakRefs: roots are RefCounted-owned by their
## creators and HMR must never extend a lifetime; dead refs are pruned on every use and on
## unmount. hmr.gd walks this list to re-render after an in-place script reload.
static var _hmr_live: Array = []

var _container: Node
var _root_vnode: RuitkVNode = null
var _root_current: RuitkFiber = null

var _wip_root: RuitkFiber = null
var _next_unit: RuitkFiber = null

var _first_effect: RuitkFiber = null
var _last_effect: RuitkFiber = null
var _deletions: Array = []
var _reorder_set: Dictionary = {}        ## host/portal fibers whose child order may have changed
var _pending_passive: Array = []
## Reused across full-keyed reconcile passes (GO-08): cleared+refilled per call instead of a
## fresh Dictionary each frame. Safe because _reconcile_children never re-enters before it
## finishes (_reconcile creates a fiber but does not recurse into _reconcile_children), and
## this member is per-reconciler so concurrent RuitkRoots don't share it.
var _key_map: Dictionary = {}

## GO-05 host-node pool: class-name -> Array[Node] of reset, orphaned Controls available for
## reuse instead of ClassDB.instantiate. Populated by _recycle_node (childless leaf nodes on
## key churn), drained by _acquire_node and by unmount(). Per-reconciler so a torn-down root
## frees exactly its own pool and nothing leaks. Capped per class so a one-off churn spike
## can't retain unbounded orphaned nodes.
var _node_pool: Dictionary = {}
const _POOL_CAP_PER_CLASS := 256

var _has_deletions := false
var _is_committing := false
var _deferred_updates: Array = []
var _work_active := false      ## a render is in progress (possibly parked between frames)
var _restart := false          ## the pass is POISONED: a render failure activated a boundary — the work loop abandons the WIP and rebuilds from root (the render-FAILURE path ONLY; updates DEFER instead — family parity P2/P3, L-05)
var _tick_pending := false     ## a _tick is scheduled (call_deferred or scheduler slice)
var _restart_count := 0        ## consecutive error rebuilds within the current pass (cap _MAX_ERROR_RESTARTS; reset at pass start and on commit)
var _pending_eb_activations: Array = []   ## mount-pass boundary activations recorded by key-path, re-adopted by the rebuilt pass (Unreal PendingEbActivations); stale entries clear at commit/unmount
var _is_replaying_deferred := false   ## _commit_root is draining _deferred_updates — replayed updates must re-mark and schedule, never re-defer (FiberReconciler.cs:23)
var _in_component_render := false     ## a component's render fn is on the stack (setState-in-render discriminator)
var _deferred_render_phase := false   ## the in-flight pass deferred >= 1 update FROM INSIDE a render fn (depth-guard accounting; external updates deferred while parked are legitimate load and never count)
var _render_depth := 0                ## CONSECUTIVE commits whose render fns deferred updates (setState-in-render loops)
var _commit_seq := 0                  ## monotonic commit number for the trace ladder's commit summary ("[Fiber] Commit #n")
const _MAX_RENDER_DEPTH := 25         ## FiberFunctionComponent.cs:18 (MaxRenderDepth)
const _MAX_ERROR_RESTARTS := 25       ## RuitkReconciler.h MaxErrorRestarts (error-boundary rebuild cap)

func _init(container: Node) -> void:
	_container = container
	var root := F.new()
	root.tag = F.Tag.ROOT
	root.type = "__root__"
	root.node = container
	_root_current = root
	_hmr_live.append(weakref(self))   # Fast Refresh (Phase H); ensure_registered self-gates
	Hmr.ensure_registered()

# --------------------------------------------------------------------------
# Scheduling
# --------------------------------------------------------------------------

func render(vnode: RuitkVNode) -> void:
	# Initial / top-level mount is always synchronous (no time-slicing) to avoid an empty
	# first frame. Cancel any parked sliced render first so its continuation (scheduler slice
	# or deferred tick) can't fire after us, and mark `_work_active` so a setState during
	# render defers coherently (replayed after this mount's commit). [M7/M8]
	if _root_current == null:
		return   # torn down by unmount() — a render after teardown is a no-op, not a crash [audit]
	_cancel_pending_tick()
	_root_vnode = vnode
	_root_current.has_pending_update = true
	_work_active = true
	_restart_count = 0
	_begin_render()
	while _next_unit != null:
		_next_unit = _perform_unit(_next_unit)
		if _restart and not _consume_error_restart():
			return   # abandoned at the rebuild cap: nothing commits, the container keeps its prior state
	_work_active = false
	_restart_count = 0
	_commit_root()

## Mark a fiber dirty and (unless a pass or commit is in flight) schedule a coalesced render.
func schedule_update_on_fiber(fiber: RuitkFiber, vnode) -> void:
	if _root_current == null:
		return   # torn down by unmount() — ignore late setState/effect callbacks [audit]
	if vnode != null:
		_root_vnode = vnode
	var target := fiber if fiber != null else _root_current
	target.has_pending_update = true
	# Walk up marking subtree_has_updates and find this fiber's root. A deletion tag anywhere
	# on the walk means the target sits in a subtree already scheduled for removal (the window
	# between reconcile and commit — e.g. a cleanup/effect setting state on its own dying
	# subtree): bail SILENTLY, per the reference (FiberReconciler.cs:215-239) — unlike the
	# detached case below, which warns.
	var top := target
	while true:
		if top.effect_tag & F.EFFECT_DELETION:
			return
		if top.parent == null:
			break
		top.parent.subtree_has_updates = true
		top = top.parent
	if top != _root_current and top != _wip_root:
		if _root_current.alternate != null and top == _root_current.alternate:
			# Superseded-tree redirect (FiberReconciler.cs:254-281): the target belongs to the
			# tree the last commit superseded — the typical case for deferred updates captured
			# mid-pass and replayed after commit. Its flags would be CLOBBERED when the next
			# pass reuses that fiber as the WIP buddy (the `has_pending_update` carry in
			# _reconcile reads from the LIVE fiber), so re-mark the live `alternate` twin and
			# its chain — the render then cannot bail out past the updated component.
			var live: RuitkFiber = target.alternate if target.alternate != null else target
			live.has_pending_update = true
			var wu := live
			while wu.parent != null:
				wu.parent.subtree_has_updates = true
				wu = wu.parent
			target = live
		else:
			# Detached fiber (already-committed deletion — its links were severed by
			# _release): ignore, warning EVERY time — the reference warns unconditionally
			# on each attempt (FiberReconciler.cs:282-289).
			push_warning("[reactive_ui_toolkit] Attempted update on a detached fiber. Ignoring (component unmounted?).")
			return
	if _is_committing:
		# Mid-commit (a layout effect set state): resetting the tree now would corrupt the
		# commit — defer and replay from _commit_root's tail (FiberReconciler.cs:302-309).
		_deferred_updates.append([target, vnode])
		return
	if (_work_active or _next_unit != null) and not _is_replaying_deferred:
		# A pass is in flight (parked between time slices, or a reentrant setState during a
		# synchronous work loop): DEFER instead of discarding the pass. Restarting on every
		# update starves large trees under sustained per-frame updates (signals ticking every
		# frame): the pass never reaches commit, and hosts already created by the aborted
		# walk leak. The deferred update replays from _commit_root's tail, coalescing
		# everything that arrived during the pass into ONE follow-up render.
		# (FiberReconciler.cs:311-325)
		_deferred_updates.append([target, vnode])
		if _in_component_render:
			# Only setState-in-RENDER counts toward the runaway guard; external updates
			# arriving while the pass is parked are exactly the sustained load the defer
			# model exists to serve.
			_deferred_render_phase = true
		return
	_ensure_tick()

func request_update() -> void:
	schedule_update_on_fiber(_root_current, null)

func _ensure_tick() -> void:
	if _tick_pending:
		return
	_tick_pending = true
	if RuitkConfig.time_slicing:
		var tree := _get_tree_safe()
		if tree != null:
			Scheduler.for_tree(tree).enqueue(_scheduled_slice, Scheduler.Priority.NORMAL)
			return
	call_deferred("_tick")

## Scheduler-lane slice action (time-slicing only): the Normal-lane, self-re-enqueueing
## render slice (FiberReconciler.cs ScheduleRootWork/Slice, :405-424). A cancelled tick
## (render()/unmount() pre-empted a parked render) leaves a stale entry in the scheduler
## queue — the `_tick_pending` guard makes it a no-op, mirroring the reference slice's
## early return when `_nextUnitOfWork` is null.
func _scheduled_slice() -> void:
	if not _tick_pending:
		return
	_tick()

## One work pass. Runs the whole render at once unless time-slicing is on, in which case
## it processes until the render quantum (`RuitkConfig.time_slice_ms`) is hit, then
## re-enqueues itself on the scheduler's Normal lane (the scheduler's cumulative
## `frame_budget_ms` decides how many slices fit in one frame). A render FAILURE poisons
## the pass (`_restart`): the loop abandons the WIP and rebuilds from the root immediately,
## so the newly-activated boundary's fallback lands in THIS pass's commit — see
## `_consume_error_restart` (updates arriving mid-render DEFER — see
## schedule_update_on_fiber; the failure rebuild is the restart machinery's ONLY use, L-05).
func _tick() -> void:
	_tick_pending = false
	if _root_vnode == null or not is_instance_valid(_container):
		_work_active = false
		return
	if not _work_active:
		_restart_count = 0
		_begin_render()
		_work_active = true

	# Quantum check AFTER each completed unit — a long single unit overruns (no preemption);
	# FiberReconciler.cs ProcessWorkUntilDeadline (:444-455). usec clock: the 2 ms default
	# quantum is finer than get_ticks_msec's integer grain.
	var sliced: bool = RuitkConfig.time_slicing
	var quantum: float = RuitkConfig.time_slice_ms
	var start_ms: float = float(Time.get_ticks_usec()) / 1000.0
	while _next_unit != null:
		_next_unit = _perform_unit(_next_unit)
		if _restart:
			if not _consume_error_restart():
				return   # abandoned at the rebuild cap; committed UI stays
			continue     # rebuilt: keep working (the quantum check resumes next unit)
		if sliced and (float(Time.get_ticks_usec()) / 1000.0) - start_ms >= quantum:
			break

	if _next_unit == null:
		_work_active = false
		_restart_count = 0
		_commit_root()
	else:
		_park()

## Consume the pass-poison flag set by `_handle_render_failure`: a render failure activated
## an error boundary, so abandon the poisoned WIP (its walk already reconciled the FAILING
## children under the boundary) and rebuild from the root NOW — the fallback then lands in
## THIS commit, mount and update alike (Unreal RuitkReconciler.cpp DoWork's bPassPoisoned
## consume). Bounded: a rebuild only happens when a boundary NEWLY activates (an active one
## can't re-capture — the captured-boundary rule), and `_restart_count` caps the mount-path
## adopt-miss loop. Returns false when the cap is exceeded: the pass is abandoned (committed
## UI stays) after reclaiming the WIP's never-committed nodes.
func _consume_error_restart() -> bool:
	_restart = false
	_restart_count += 1
	_reclaim_abandoned_wip(_wip_root)
	if _restart_count > _MAX_ERROR_RESTARTS:
		push_error("[reactive_ui_toolkit] Too many error-boundary rebuilds (%d). Abandoning the pass." % _MAX_ERROR_RESTARTS)
		_work_active = false
		_next_unit = null
		_restart_count = 0
		return false
	_begin_render()
	return true

## Release what an abandoned (error-poisoned) pass created before the rebuild orphans it —
## the analog of the reference's abandoned-WIP slab reclaim in BeginRender
## (RuitkReconciler.cpp:418-426). Fibers NEWLY allocated by the abandoned walk
## (alternate == null; a reused fiber is the live tree's ping-pong buddy and is left for
## the next pass to re-reuse) sever their links and fresh component state so the RefCounted
## cycles collect, and a fresh host node that never entered the scene is recycled or freed.
func _reclaim_abandoned_wip(fiber: RuitkFiber) -> void:
	var c := fiber.child
	while c != null:
		var nxt := c.sibling
		_reclaim_abandoned_wip(c)
		c = nxt
	if fiber == _wip_root:
		return
	if fiber.alternate == null:
		# CAREFUL: a stable leaf list is reused IN PLACE by _try_fast_leaf_list — its LIVE
		# fibers (committed in-tree nodes, no buddy) sit directly in the WIP child chain and
		# also match `alternate == null`. They are NOT this pass's allocations: severing
		# their sibling/parent links would corrupt the live tree (bughunt P3-1). A node that
		# exists but is invalid is skipped the same way (conservative: never corrupt).
		if fiber.node != null and (not is_instance_valid(fiber.node) or fiber.node.is_inside_tree()):
			return
		# Newly allocated this pass: nothing else references it. Its node (if _complete_work
		# already created one) was never placed — pool it like a deleted leaf, or free it.
		if fiber.node != null:
			if RuitkConfig.host_node_pool and fiber.node.get_child_count() == 0:
				_recycle_node(fiber.node, fiber.props if fiber.props != null else {})
			else:
				fiber.node.queue_free()
		_dispose_fiber_state(fiber)
		fiber.parent = null
		fiber.child = null
		fiber.sibling = null
		fiber.next_effect = null
		fiber.node = null
		fiber.deletions = []
	else:
		# Reused buddy: detach it from the abandoned chain; the rebuilt pass's _reconcile
		# resets every render-scoped field when it re-reuses the fiber.
		fiber.child = null
		fiber.next_effect = null

## Park the sliced render by re-enqueueing the slice action on the scheduler's Normal lane
## (the self-re-enqueueing slice, FiberReconciler.cs:405-424). The scheduler pump keeps
## running queued slices while its cumulative frame budget lasts, so a short quantum can run
## more than one slice per frame; when the budget is spent, the remainder waits for the next
## frame's pump. Fallback when the container is not in a tree: next-idle call_deferred,
## like the sync path.
func _park() -> void:
	if _tick_pending:
		return
	_tick_pending = true
	var tree := _get_tree_safe()
	if tree != null:
		Scheduler.for_tree(tree).enqueue(_scheduled_slice, Scheduler.Priority.NORMAL)
	else:
		call_deferred("_tick")

## Sever a parked continuation (when render()/unmount() pre-empts a sliced render still in
## flight), so a stale tick can't fire on a torn-down/replaced tree. [M7] A slice entry
## already sitting in the scheduler queue cannot be unqueued — clearing `_tick_pending`
## makes it a no-op instead (see _scheduled_slice).
func _cancel_pending_tick() -> void:
	_tick_pending = false

## Get the container's SceneTree, or null — without erroring when it's not in the tree.
func _get_tree_safe() -> SceneTree:
	if is_instance_valid(_container) and _container.is_inside_tree():
		return _container.get_tree()
	return null

# --------------------------------------------------------------------------
# Render phase (work loop)
# --------------------------------------------------------------------------

func _begin_render() -> void:
	_first_effect = null
	_last_effect = null
	_has_deletions = false
	_deletions = []
	_reorder_set = {}
	_pending_passive = []

	# Reuse the root's ping-pong buddy (double-buffer) instead of allocating. [perf #1]
	var wip: RuitkFiber = _root_current.alternate
	if wip == null:
		wip = F.new()
		_root_current.alternate = wip
	wip.alternate = _root_current
	wip.tag = F.Tag.ROOT
	wip.type = "__root__"
	wip.node = _container
	wip.child = null
	wip.sibling = null
	wip.parent = null
	wip.effect_tag = F.EFFECT_NONE
	wip.next_effect = null
	if not wip.deletions.is_empty():
		wip.deletions.clear()
	wip.input_children = [_root_vnode]
	wip.has_pending_update = _root_current.has_pending_update
	wip.subtree_has_updates = _root_current.subtree_has_updates
	_wip_root = wip
	_next_unit = wip

func _perform_unit(fiber: RuitkFiber) -> RuitkFiber:
	# begin-work (inlined — one fewer call per fiber per frame) [perf]
	var next: RuitkFiber
	match fiber.tag:
		F.Tag.FUNCTION:
			next = _begin_function(fiber)
		F.Tag.ERROR_BOUNDARY:
			next = _begin_error_boundary(fiber)
		_:
			# ROOT / HOST / FRAGMENT / PORTAL: reconcile declared children.
			# Leaf fast-path: nothing declared now AND nothing before -> skip the whole
			# _reconcile_children + _normalize_children call chain. fiber.child is already
			# null (reset in _reconcile). Hot: every leaf in a big list hits this. [perf]
			var alt := fiber.alternate
			if fiber.input_children.is_empty() and (alt == null or alt.child == null):
				next = null
			elif _reconcile_children(fiber, _old_first(alt), fiber.input_children):
				next = null   # fast-list handled the children in place; don't descend
			else:
				next = fiber.child
	if not fiber.deletions.is_empty():
		_has_deletions = true
	if next != null:
		return next
	# no child -> complete this fiber, then move to sibling / climb to parent.
	var f := fiber
	while f != null:
		_complete_work(f)
		if f.sibling != null:
			return f.sibling
		f = f.parent
	return null

func _begin_function(fiber: RuitkFiber) -> RuitkFiber:
	if fiber.state != null:
		fiber.state.fiber = fiber
	var alt := fiber.alternate
	# identity fast-path [perf P3]; an optional props.__memo_eq(old,new) custom comparer (V.memo) is
	# consulted only when not identity-equal, so the common path is untouched.
	var props_equal: bool = false
	if fiber.props != null:
		if is_same(fiber.pending_props, fiber.props):
			props_equal = true
		elif fiber.pending_props.has("__memo_eq") and fiber.pending_props["__memo_eq"] is Callable:
			props_equal = fiber.pending_props["__memo_eq"].call(fiber.props, fiber.pending_props)
		else:
			props_equal = fiber.pending_props == fiber.props
	var context_ok: bool = not fiber.reads_context or not _has_context_changed(fiber)
	var children_same: bool = _vnode_list_equal(alt.input_children if alt != null else [], fiber.input_children)
	var can_bail: bool = (not fiber.has_pending_update) and context_ok and props_equal and children_same

	# Diff-decision channel (OR gate — diff_tracing alone or Verbose alone lights it).
	if RuitkDiagnostics.diff_tracing or RuitkDiagnostics.trace_level == RuitkDiagnostics.TraceLevel.VERBOSE:
		RuitkDiagnostics.trace("[Diff] bailout %s '%s'" % ["taken" if (can_bail and fiber.state != null) else "skipped", _trace_desc(fiber)])
	var out: Array
	if can_bail and fiber.state != null:
		out = fiber.state.last_output     # reuse cached output; don't re-run the render fn
	else:
		fiber.has_pending_update = false
		out = _render_component(fiber)
	fiber.subtree_has_updates = false
	fiber.props = fiber.pending_props
	if _reconcile_children(fiber, _old_first(alt), out):
		return null   # fast-list path handled the children
	return fiber.child

func _render_component(fiber: RuitkFiber) -> Array:
	var state: RuitkComponentState = fiber.state
	if RuitkDiagnostics.trace_level == RuitkDiagnostics.TraceLevel.VERBOSE:   # render entry (once per pass, strict double-invoke included)
		RuitkDiagnostics.trace("[Fiber] Render '%s'" % _trace_desc(fiber))
	var result = _invoke_render(fiber, state)
	# Strict mode (family parity P4): double-invoke with the FIRST result discarded — the
	# impure-render flusher (Unreal RuitkReconciler.cpp RenderComponent's second RunOnce).
	# A failure latched by invoke 1 short-circuits invoke 2 (consumed once, below).
	if RuitkConfig.strict_mode_effective() and not RuitkFail._pending():
		result = _invoke_render(fiber, state)
	# Cooperative error latch (family parity P3; Unreal D-10): a failing render CALLED
	# RuitkFail.render(...). Consume per component, immediately — the failed output is
	# discarded and the pass unwinds to the nearest boundary (the WIP is abandoned
	# pre-commit, so the committed tree stays intact until the rebuilt pass commits).
	var failure = RuitkFail._consume()
	if failure != null:
		_handle_render_failure(fiber, failure)
		result = null
	RuitkDiagnostics.on_render()   # ONCE per pass, after both strict invokes (family rule)
	state.last_output = _to_vnode_array(result)
	if not state.effects.is_empty():
		fiber.effect_tag |= F.EFFECT_PASSIVE
	if not state.layout_effects.is_empty():
		fiber.effect_tag |= F.EFFECT_LAYOUT
	return state.last_output

## One render-fn invocation with full hook bracketing. `Hooks._begin`/`_end` wrap EACH
## strict-mode invoke: the second `_begin` resets the cursors, so the invoke re-walks the
## existing hook slots IN PLACE — state persists, effects register once (mount appends on
## invoke 1; invoke 2 sees `i < size` and updates the slot), and `_end`'s hook-order
## validation compares invoke 2 against invoke 1 (impure hook order surfaces on the FIRST
## render when validation is on).
func _invoke_render(fiber: RuitkFiber, state: RuitkComponentState):
	Hooks._begin(state)
	_in_component_render = true
	var result = fiber.component.call(fiber.pending_props, fiber.input_children)
	_in_component_render = false
	Hooks._end()
	return result

func _begin_error_boundary(fiber: RuitkFiber) -> RuitkFiber:
	# A mount-pass failure recorded its activation by key-path (the WIP fiber that carried
	# it was abandoned with that pass) — re-adopt it before deciding what to render.
	if not _pending_eb_activations.is_empty():
		_adopt_pending_eb_activation(fiber)
	# Structural boundary (family shape, Unreal BeginErrorBoundary): renders `fallback`
	# while active; a `reset_key` change clears. Activation is cooperative — a failing
	# descendant render calls RuitkFail.render and _handle_render_failure latches the
	# boundary (GDScript has no exceptions, so a hard crash is still not auto-caught).
	# A missing alternate is a MOUNT, not a reset: there is nothing to clear, and a
	# just-adopted mount-pass activation must survive.
	var alt := fiber.alternate
	var reset_requested: bool = alt != null and alt.eb_reset_key != fiber.eb_reset_key
	if reset_requested:
		fiber.eb_active = false
		fiber.eb_last_error = null
	fiber.eb_showing_fallback = fiber.eb_active and not reset_requested
	var children: Array
	if fiber.eb_showing_fallback:
		children = [fiber.eb_fallback] if fiber.eb_fallback != null else []
	else:
		children = fiber.eb_children
	if _reconcile_children(fiber, _old_first(alt), children):
		return null
	return fiber.child

## Unwind a failed render to the nearest error boundary (Unreal HandleRenderFailure).
## Walks the WIP parent chain — pre-commit, safe. An ALREADY-ACTIVE boundary can't capture
## again this pass (its fallback is what just failed) — skip upward, or the failure loops
## forever (React's captured-boundary rule).
func _handle_render_failure(failed_fiber: RuitkFiber, reason: String) -> void:
	var f := failed_fiber
	while f != null:
		if f.tag == F.Tag.ERROR_BOUNDARY and not f.eb_active:
			f.eb_active = true
			f.eb_last_error = reason
			if f.alternate != null:
				# The committed twin carries the activation into the rebuilt pass (the
				# rebuild's _reconcile reuse copies eb_* from the live fiber).
				f.alternate.eb_active = true
				f.alternate.eb_last_error = reason
			else:
				# Mount-pass boundary: this WIP fiber is abandoned with the pass and has no
				# committed twin, so record the activation by key-path for the rebuilt pass
				# to re-adopt (_begin_error_boundary). If an ancestor renders differently
				# and the path misses, the child just fails again and re-records —
				# self-healing, bounded by the error-restart cap.
				_pending_eb_activations.append({ "path": _eb_key_path(f), "reason": reason })
			if f.eb_handler.is_valid():
				f.eb_handler.call(reason)
			# Poison the pass: the work loop abandons the WIP (never committed) and rebuilds
			# from the root so the boundary renders its fallback — the ERROR path's rebuild
			# only; setState never poisons a pass (defer-don't-restart, L-05).
			_restart = true
			push_error("[reactive_ui_toolkit] render failed: %s (caught by error boundary)" % reason)
			return
		f = f.parent
	push_error("[reactive_ui_toolkit] render failed with no error boundary above: %s" % reason)

## Root-to-boundary identity for a mount-pass activation: the fiber key at each level from
## the boundary up to (excluding) the root — stable across the abandoned and rebuilt passes
## as long as the ancestors render the same shape (Unreal AdoptPendingEbActivation).
func _eb_key_path(fiber: RuitkFiber) -> Array:
	var path: Array = []
	var p := fiber
	while p != null and p.tag != F.Tag.ROOT:
		path.append(_fiber_key(p))
		p = p.parent
	return path

func _adopt_pending_eb_activation(fiber: RuitkFiber) -> void:
	var path := _eb_key_path(fiber)
	for i in _pending_eb_activations.size():
		if _pending_eb_activations[i]["path"] == path:
			fiber.eb_active = true
			fiber.eb_last_error = _pending_eb_activations[i]["reason"]
			_pending_eb_activations.remove_at(i)
			return

# --------------------------------------------------------------------------
# Reconciliation
# --------------------------------------------------------------------------

## Create-or-reuse a fiber for `vnode` matched against `old_fiber`.
## Create-or-reuse a WIP fiber for `vnode`, matched against `old_fiber`. DOUBLE-BUFFERED:
## when the type matches we reuse `old_fiber`'s ping-pong buddy (its alternate) instead of
## allocating — so a stable tree position costs ZERO fiber allocations after first mount.
## Only a true placement / type-change allocates. [perf #1]
func _reconcile(parent_fiber: RuitkFiber, old_fiber: RuitkFiber, vnode: RuitkVNode, idx: int) -> RuitkFiber:
	var reuse: bool = old_fiber != null and old_fiber.matches(vnode)
	var fiber: RuitkFiber
	if reuse:
		if RuitkDiagnostics.diff_tracing or RuitkDiagnostics.trace_level == RuitkDiagnostics.TraceLevel.VERBOSE:
			RuitkDiagnostics.trace("[Diff] reuse '%s'" % _trace_desc(old_fiber))
		fiber = old_fiber.alternate
		if fiber == null:
			fiber = F.new()
		fiber.alternate = old_fiber
		old_fiber.alternate = fiber
	else:
		fiber = F.new()
		fiber.alternate = null
		if old_fiber != null:
			# Node replacement — a STRUCTURAL event (Basic trace) AND a diff decision.
			if RuitkDiagnostics.trace_level != RuitkDiagnostics.TraceLevel.NONE:
				RuitkDiagnostics.trace("[Fiber] Replace %s -> %s" % [_trace_desc(old_fiber), _trace_vnode_desc(vnode)])
			if RuitkDiagnostics.diff_tracing or RuitkDiagnostics.trace_level == RuitkDiagnostics.TraceLevel.VERBOSE:
				RuitkDiagnostics.trace("[Diff] replace '%s' -> '%s'" % [_trace_desc(old_fiber), _trace_vnode_desc(vnode)])
			_delete_fiber(parent_fiber, old_fiber)

	# --- render-scoped fields (reset every render, since the buddy holds stale data) ---
	fiber.parent = parent_fiber
	fiber.child = null
	fiber.sibling = null
	fiber.index = idx
	fiber.effect_tag = F.EFFECT_NONE
	fiber.next_effect = null
	if not fiber.deletions.is_empty():
		fiber.deletions.clear()
	fiber.key = vnode.key
	fiber.pending_props = vnode.props
	fiber.input_children = vnode.children
	# Read vnode.kind once and inline the HOST case (the hot path) — avoids the tag_for_vnode
	# call and four repeated kind comparisons per element. [perf]
	var vk: int = vnode.kind
	if vk == RuitkVNode.Kind.HOST:
		fiber.tag = F.Tag.HOST
		fiber.type = vnode.type
		fiber.component = Callable()
		fiber.portal_target = null
	else:
		fiber.tag = F.tag_for_vnode(vnode)
		fiber.type = ""
		fiber.component = vnode.component if vk == RuitkVNode.Kind.FUNCTION else Callable()
		fiber.portal_target = vnode.portal_target if vk == RuitkVNode.Kind.PORTAL else null
	if vk == RuitkVNode.Kind.ERROR_BOUNDARY:
		fiber.eb_fallback = vnode.props.get("fallback")
		fiber.eb_handler = vnode.props.get("on_error", Callable())
		fiber.eb_reset_key = vnode.props.get("reset_key")
		fiber.eb_children = vnode.children

	if reuse:
		# carry committed baseline + live node/state/context from the current fiber
		fiber.node = old_fiber.node
		fiber.state = old_fiber.state
		fiber.props = old_fiber.props
		fiber.reads_context = old_fiber.reads_context
		fiber.has_pending_update = old_fiber.has_pending_update
		fiber.subtree_has_updates = old_fiber.subtree_has_updates
		# Carry provided context (duplicated so change-detection vs the alternate works, and
		# so a bailed-out provider keeps it). [audit C1]
		fiber.provided_context = old_fiber.provided_context.duplicate() if old_fiber.provided_context != null else null
		if fiber.tag == F.Tag.ERROR_BOUNDARY:   # inlined is_error_boundary() [perf]
			fiber.eb_active = old_fiber.eb_active
			fiber.eb_showing_fallback = old_fiber.eb_showing_fallback
			fiber.eb_last_error = old_fiber.eb_last_error
		# carry the cached apply plan (the size guard rebuilds it if the prop shape changed) [perf]
		fiber.apply_size = old_fiber.apply_size
		fiber.apply_special = old_fiber.apply_special
		fiber.apply_plain = old_fiber.apply_plain
	else:
		fiber.node = null
		fiber.state = null
		fiber.props = null
		fiber.reads_context = false
		fiber.has_pending_update = false
		fiber.subtree_has_updates = false
		fiber.provided_context = null
		fiber.eb_active = false
		fiber.eb_showing_fallback = false
		fiber.apply_size = -1
		fiber.apply_special = false
		fiber.apply_plain = []

	if fiber.tag == F.Tag.FUNCTION and fiber.state == null:   # inlined tag check (hot) [perf P4]
		var st := RuitkComponentState.new()
		st.fiber = fiber
		st.on_state_updated = _make_on_state_updated(st)
		fiber.state = st
	return fiber

func _make_on_state_updated(state: RuitkComponentState) -> Callable:
	return func(): schedule_update_on_fiber(state.fiber, null)

## Reconcile `child_vnodes` against the OLD child linked-list (starting at `old_first`).
## Walks the sibling chain directly — no per-frame Array materialization. [perf P1]
## Returns TRUE if it took the fast-list path and fully handled the children in place — the
## caller must then NOT descend (the children are not on the work queue). Returns FALSE for the
## normal path (caller descends into parent_fiber.child as usual).
func _reconcile_children(parent_fiber: RuitkFiber, old_first: RuitkFiber, child_vnodes: Array) -> bool:
	var vnodes := _normalize_children(child_vnodes)
	# FAST-LIST PATH: a stable list of host LEAVES (same count/keys/order, every child a
	# childless host element) — diff each child's props and effect-list only the CHANGED ones,
	# reusing the fibers in place. Skips the entire per-child fiber traversal (_reconcile +
	# _perform_unit + _complete_work). This is the single biggest reconcile win for big dynamic
	# lists, and the per-row bail-out makes mostly-static lists nearly free. [perf: fast-list]
	#
	# GO-09 `reuse_by_slot`: when the host container opts in, the fast path IGNORES key churn and
	# reuses the node at slot i for whatever leaf lands at slot i (a pure props UPDATE — no add/
	# remove/free). This routes a stateless-leaf list whose KEYS change every frame (but whose
	# COUNT + TYPE per slot stay stable) onto the in-place path instead of the churning keyed path.
	# CONTRACT: only for childless host leaves with NO per-node identity to preserve (no ref/focus/
	# caret/scroll/selection/in-flight animation) — the caller asserts this by setting the prop.
	var reuse_by_slot: bool = parent_fiber.pending_props is Dictionary and bool(parent_fiber.pending_props.get("reuse_by_slot", false))
	if old_first != null and not vnodes.is_empty() and _try_fast_leaf_list(parent_fiber, old_first, vnodes, reuse_by_slot):
		return true
	parent_fiber.child = null
	if vnodes.is_empty():
		var oc0 := old_first
		while oc0 != null:
			var nxt0 := oc0.sibling
			_delete_fiber(parent_fiber, oc0)
			oc0 = nxt0
		return false

	var prev: RuitkFiber = null
	var structural := false   # a child was newly placed or MOVED -> needs reorder [perf #2]
	if _any_keyed(vnodes):
		# FAST PATH: a positionally-stable keyed list (same count, keys, order) — the common
		# update-only case. Reconcile in place with no key_map/matched dicts. [perf P2]
		if _keys_stable(old_first, vnodes):
			var ocs := old_first
			for i in vnodes.size():
				var cf := _reconcile(parent_fiber, ocs, vnodes[i], i)
				if prev == null: parent_fiber.child = cf
				else: prev.sibling = cf
				prev = cf
				ocs = ocs.sibling
			return false   # stable -> no structural change -> skip reorder
		# Full keyed path. Unkeyed children get a NAMESPACED positional key (control-char
		# prefixed) so an integer key can't collide with a positional index. [audit M1]
		# GO-08: reuse the persistent `_key_map` (cleared per call, no per-frame Dictionary
		# alloc) and a per-fiber `matched_pass` flag (no `matched` Dictionary). Mirrors
		# Unity's [ThreadStatic] s_childMap + mark-and-sweep. Behavior is identical, incl.
		# duplicate user keys (the flag is per-fiber, so both duplicates are swept correctly).
		_key_map.clear()
		# Diff-decision channel gate, hoisted once per keyed pass (this path is off the
		# stable/fast routes already; the per-child cost at off is one local bool test).
		var trace_keyed: bool = RuitkDiagnostics.diff_tracing or RuitkDiagnostics.trace_level == RuitkDiagnostics.TraceLevel.VERBOSE
		var ock := old_first
		while ock != null:
			_key_map[_fiber_key(ock)] = ock
			ock.matched_pass = false
			ock = ock.sibling
		for i in vnodes.size():
			var vn: RuitkVNode = vnodes[i]
			var old_match: RuitkFiber = _key_map.get(_vnode_key(vn, i))
			if old_match != null and (old_match.matched_pass or not old_match.matches(vn)):
				old_match = null
			if old_match != null:
				old_match.matched_pass = true
				if old_match.index != i:
					structural = true   # moved
					if trace_keyed:
						RuitkDiagnostics.trace("[Diff] keyed move key=%s %d -> %d" % [str(_vnode_key(vn, i)), old_match.index, i])
			else:
				structural = true       # new placement
				if trace_keyed:
					RuitkDiagnostics.trace("[Diff] keyed place key=%s at %d" % [str(_vnode_key(vn, i)), i])
			var cf := _reconcile(parent_fiber, old_match, vn, i)
			if prev == null: parent_fiber.child = cf
			else: prev.sibling = cf
			prev = cf
		var ocd := old_first
		while ocd != null:
			var nxtd := ocd.sibling
			if not ocd.matched_pass:
				if trace_keyed:
					RuitkDiagnostics.trace("[Diff] keyed remove key=%s" % str(_fiber_key(ocd)))
				_delete_fiber(parent_fiber, ocd)
			ocd = nxtd
		_key_map.clear()
	else:
		# index (positional) path
		var oci := old_first
		for i in vnodes.size():
			var old_match: RuitkFiber = oci
			if old_match == null or not old_match.matches(vnodes[i]):
				structural = true       # new placement / type change
			var cf := _reconcile(parent_fiber, old_match, vnodes[i], i)
			if prev == null: parent_fiber.child = cf
			else: prev.sibling = cf
			prev = cf
			if oci != null:
				oci = oci.sibling
		while oci != null:
			var nxti := oci.sibling
			_delete_fiber(parent_fiber, oci)
			oci = nxti

	# Only re-assert child order when the SET changed (deletions also mark via _delete_fiber).
	# A frame of pure prop-updates skips the whole O(n) reorder pass. [perf #2]
	if structural:
		_mark_reorder(parent_fiber)
	return false

## Did a host fiber's props change since last commit? is_same() is an O(1) identity check
## (memoized props => no change), else a deep value compare. [perf P3]
func _props_changed(pending, props) -> bool:
	if is_same(pending, props):
		return false
	return pending != props

## Fast-path for a STABLE list of HOST LEAVES (same count/keys/order, every child a childless
## host element on BOTH sides). Reuses the child fibers IN PLACE — no buddy swap, no per-child
## _reconcile/_perform_unit/_complete_work — updating render-scoped fields, diffing props, and
## adding only the CHANGED rows to the effect list (per-row bail-out). The host nodes persist;
## changed props are applied in the normal commit pass (two-phase preserved). Returns true iff
## it handled the whole list; falls back (false) for any non-host/non-leaf/reordered list.
func _try_fast_leaf_list(parent_fiber: RuitkFiber, old_first: RuitkFiber, vnodes: Array, ignore_keys: bool = false) -> bool:
	var n := vnodes.size()
	# 1. Eligibility scan (read-only): every position must be a childless HOST with matching
	#    type + key, and the same count. With `ignore_keys` (GO-09 reuse_by_slot) the per-slot
	#    key match is skipped — a stateless leaf is interchangeable by slot — but type + leafness
	#    + count are still required (a slot must hold the same node CLASS to reuse it in place).
	var oc := old_first
	for i in n:
		if oc == null:
			return false
		var vn: RuitkVNode = vnodes[i]
		# (oc.tag == HOST is implied by oc.type == vn.type, since only host fibers carry a type.)
		if vn.kind != RuitkVNode.Kind.HOST or oc.type != vn.type or (not ignore_keys and oc.key != vn.key):
			return false
		if oc.child != null or not vn.children.is_empty():
			return false   # must be leaves on both sides
		oc = oc.sibling
	if oc != null:
		return false   # old list is longer -> count changed
	# 2. Reconcile in place. The sibling chain + parent.child are unchanged (stable order).
	parent_fiber.child = old_first
	oc = old_first
	for i in n:
		var vn: RuitkVNode = vnodes[i]
		if ignore_keys:
			oc.key = vn.key   # adopt the new key so the slot stays on the fast path next frame
		oc.parent = parent_fiber
		oc.index = i
		oc.effect_tag = F.EFFECT_NONE
		oc.next_effect = null
		oc.input_children = vn.children
		var np = vn.props
		oc.pending_props = np
		if _props_changed(np, oc.props):
			oc.effect_tag = F.EFFECT_UPDATE
			if _first_effect == null:
				_first_effect = oc
			else:
				_last_effect.next_effect = oc
			_last_effect = oc
		oc = oc.sibling
	return true

## True if the old child chain matches `vnodes` positionally: same count, same key + type
## at every position. When true, the keyed reconcile can skip the key_map entirely. [perf P2]
func _keys_stable(old_first: RuitkFiber, vnodes: Array) -> bool:
	var oc := old_first
	for i in vnodes.size():
		if oc == null:
			return false
		var vn: RuitkVNode = vnodes[i]
		# Inlined key compare + HOST matches() — this scan runs once per element every frame,
		# so the elided _fiber_key/_vnode_key/matches calls are thousands/frame saved. [perf]
		var ok = oc.key
		var vnk = vn.key
		if ok != null or vnk != null:
			if ok != vnk:
				return false
		elif oc.index != i:        # both unkeyed -> must be the same position
			return false
		if vn.kind == RuitkVNode.Kind.HOST:
			if oc.tag != F.Tag.HOST or oc.type != vn.type:
				return false
		elif not oc.matches(vn):
			return false
		oc = oc.sibling
	return oc == null   # old list must be exactly the same length

func _delete_fiber(parent_fiber: RuitkFiber, old_fiber: RuitkFiber) -> void:
	old_fiber.effect_tag |= F.EFFECT_DELETION
	parent_fiber.deletions.append(old_fiber)
	_deletions.append(old_fiber)
	_mark_reorder(parent_fiber)

## Mark the nearest host (or portal) ancestor so its child order is re-asserted at commit.
func _mark_reorder(parent_fiber: RuitkFiber) -> void:
	var f := parent_fiber
	while f != null:
		if f.tag == F.Tag.PORTAL or f.node != null:   # inlined tag check (hot) [perf P4]
			_reorder_set[f] = true
			return
		f = f.parent

# --------------------------------------------------------------------------
# Complete phase — create/diff host nodes, build the effect list (post-order)
# --------------------------------------------------------------------------

func _complete_work(fiber: RuitkFiber) -> void:
	match fiber.tag:
		F.Tag.HOST:
			if fiber.node == null:
				fiber.node = _acquire_node(fiber.type)
				# GO-05: a pooled node carries its previous life's props under __rui_pool_old.
				# Reuse it via a DIFF (apply_props with those as old) — transitions events, diffs
				# style, sets only changed plain props — plus reset any plain prop it had that the
				# new element doesn't. A fresh node has no such meta -> old = {} = the original path.
				var old_props: Dictionary = {}
				if fiber.node.has_meta("__rui_pool_old"):
					old_props = fiber.node.get_meta("__rui_pool_old")
					fiber.node.remove_meta("__rui_pool_old")
					RuitkHost.reset_removed_plain(fiber.node, old_props, fiber.pending_props)
				RuitkHost.apply_props(fiber.node, old_props, fiber.pending_props)
				fiber.props = fiber.pending_props
				fiber.effect_tag |= F.EFFECT_PLACEMENT
			elif not is_same(fiber.pending_props, fiber.props) and fiber.pending_props != fiber.props:
				# is_same() is an O(1) identity check: when the parent passed the SAME props dict
				# object (memoized), skip the deep value compare entirely. Otherwise fall back to
				# the deep compare so a freshly-built equal dict still bails to no-UPDATE. [perf P3]
				fiber.effect_tag |= F.EFFECT_UPDATE
		F.Tag.PORTAL:
			if fiber.alternate != null and fiber.alternate.portal_target != fiber.portal_target:
				fiber.effect_tag |= F.EFFECT_PORTAL_RETARGET
				_reorder_set[fiber] = true   # re-assert child order at the new target [audit M6]
	if fiber.effect_tag != F.EFFECT_NONE:
		# inlined _append_effect (hot: runs for every changed element) [perf]
		fiber.next_effect = null
		if _first_effect == null:
			_first_effect = fiber
		else:
			_last_effect.next_effect = fiber
		_last_effect = fiber

# --------------------------------------------------------------------------
# Commit phase
# --------------------------------------------------------------------------

func _commit_root() -> void:
	_is_committing = true
	_commit_seq += 1
	RuitkDiagnostics.on_commit()
	# Structural trace: count the effect list BEFORE the commit loop consumes it (next_effect
	# links are nulled below); the summary line itself is emitted commit-end, Unity M5 shape.
	var trace_structural: bool = RuitkDiagnostics.trace_level != RuitkDiagnostics.TraceLevel.NONE
	var trace_effect_count := 0
	if trace_structural:
		var tf := _first_effect
		while tf != null:
			trace_effect_count += 1
			tf = tf.next_effect

	for d in _deletions:
		_commit_deletion(d)

	var f := _first_effect
	while f != null:
		var tag := f.effect_tag
		if tag & F.EFFECT_PLACEMENT: _commit_placement(f)
		if tag & F.EFFECT_UPDATE: _commit_update(f)
		if tag & F.EFFECT_PORTAL_RETARGET: _commit_portal_retarget(f)
		if tag & F.EFFECT_LAYOUT: _commit_layout_effects(f)
		if tag & F.EFFECT_PASSIVE: _pending_passive.append(f)
		var nxt := f.next_effect
		f.effect_tag = F.EFFECT_NONE
		f.next_effect = null
		f = nxt

	for hp in _reorder_set.keys():
		_enforce_child_order(hp)

	if trace_structural:
		RuitkDiagnostics.trace("[Fiber] Commit #%d effects=%d" % [_commit_seq, trace_effect_count])

	_root_current = _wip_root
	_pending_eb_activations.clear()   # activations that never found their boundary are stale now
	_is_committing = false

	_flush_passive()
	# No per-frame tree-sever: the old current tree IS next frame's reusable buddy pool
	# (double-buffering). Only genuinely-deleted subtrees are released (in _commit_deletion). [perf #1]

	# Render-depth runaway guard (FiberFunctionComponent.cs:16-18, :140-155 — adapted to the
	# defer model): count CONSECUTIVE commits whose render FNS deferred further updates
	# (an unconditional setState-in-render loops forever otherwise); any commit that didn't
	# resets the streak. Commit-phase defers (layout effects) and external updates deferred
	# while the pass was parked don't count.
	if _deferred_render_phase:
		_render_depth += 1
	else:
		_render_depth = 0
	_deferred_render_phase = false
	if _render_depth > _MAX_RENDER_DEPTH:
		push_error("[reactive_ui_toolkit] Too many re-renders (setState during render?). Aborting pass.")
		_deferred_updates.clear()
		_render_depth = 0
		return   # drop the queued updates; the committed UI stays
	# Replay updates deferred during the pass/commit: re-mark flags (with re-deferral
	# suppressed), coalescing into ONE follow-up render via _ensure_tick's tick-pending
	# guard (FiberReconciler.cs:884-909 — sync mode restarts the loop once; sliced mode
	# lets the still-queued slice action pick the work up automatically).
	if not _deferred_updates.is_empty():
		_is_replaying_deferred = true
		while not _deferred_updates.is_empty():
			var entry: Array = _deferred_updates.pop_front()
			schedule_update_on_fiber(entry[0], entry[1])
		_is_replaying_deferred = false

func _commit_placement(fiber: RuitkFiber) -> void:
	if fiber.node == null or not is_instance_valid(fiber.node):
		return
	var parent_node := _host_parent_node(fiber)
	if parent_node != null and is_instance_valid(parent_node) and fiber.node.get_parent() != parent_node:
		parent_node.add_child(fiber.node)
		RuitkDiagnostics.on_placement()
		if RuitkDiagnostics.trace_level != RuitkDiagnostics.TraceLevel.NONE:
			RuitkDiagnostics.trace("[Fiber] Place %s" % fiber.type)

func _commit_update(fiber: RuitkFiber) -> void:
	if fiber.node == null or not is_instance_valid(fiber.node):
		return
	var new_props: Dictionary = fiber.pending_props
	# (Re)build the cached apply plan whenever the prop SHAPE (key count) changes. [perf]
	if new_props.size() != fiber.apply_size:
		_build_apply_plan(fiber, new_props)
	if fiber.apply_special:
		# Element has (or ever had) events / ref / style / item-model -> full generic apply.
		RuitkHost.apply_props(fiber.node, fiber.props, new_props)
	else:
		# LEAN apply: a plain element — just diff + write the known plain keys. No per-frame
		# re-classification (event/reserved), no unused-feature checks (has_meta/ref/style/item).
		var node := fiber.node
		var old_props: Dictionary = fiber.props
		var plain: Array = fiber.apply_plain
		for i in plain.size():
			var k = plain[i]
			if not new_props.has(k):
				# a key was swapped without changing the count -> shape changed; rebuild and
				# apply generically this one frame (the rebuild picks up the new shape).
				_build_apply_plan(fiber, new_props)
				RuitkHost.apply_props(node, old_props, new_props)
				break
			var val = new_props[k]
			if not old_props.has(k) or old_props[k] != val:
				RuitkHost._set_prop(node, k, val)
	fiber.props = new_props
	if RuitkDiagnostics.enabled: RuitkDiagnostics.on_update()
	if RuitkDiagnostics.trace_level == RuitkDiagnostics.TraceLevel.VERBOSE:   # per-element detail
		RuitkDiagnostics.trace("[Fiber] Update %s" % fiber.type)

## Classify a host element's props ONCE: plain prop keys (diffed+written each frame) vs
## "special" (events / ref / style / item-model -> needs the generic apply). apply_special is
## STICKY so an element that ever had events/ref/style keeps using the generic path (which
## correctly disconnects/resets them). [perf: inline-cache apply]
func _build_apply_plan(fiber: RuitkFiber, props: Dictionary) -> void:
	fiber.apply_size = props.size()
	var plain: Array = []
	for k in props:
		if k == "ref" or k == "style" or k == "items" or k == "classes":
			fiber.apply_special = true
		elif k == "key" or k == "children":
			pass
		elif RuitkHost._is_event(k):
			fiber.apply_special = true
		else:
			plain.append(k)
	fiber.apply_plain = plain   # skip the call when off [perf]

func _commit_deletion(old_fiber: RuitkFiber) -> void:
	RuitkDiagnostics.on_deletion()
	if RuitkDiagnostics.trace_level != RuitkDiagnostics.TraceLevel.NONE:
		# One line per removed SUBTREE (top-level only) — the legacy [ReplaceNode] granularity.
		RuitkDiagnostics.trace("[Fiber] Delete %s" % _trace_desc(old_fiber))
	_null_refs_recursive(old_fiber)
	_run_cleanups_recursive(old_fiber)
	_free_host_nodes(old_fiber)
	_release(old_fiber)   # break cycles so the removed subtree + its buddies free [perf #1]

## Reset any `ref` prop to null for deleted host fibers, so a useRef box / callback ref
## doesn't dangle to a freed node (React nulls refs on unmount). [audit C2]
func _null_refs_recursive(fiber: RuitkFiber) -> void:
	if fiber.props is Dictionary and fiber.props.has("ref"):
		var r = fiber.props["ref"]
		if r is Callable and r.is_valid():
			r.call(null)
		elif r is Dictionary and r.has("current"):
			r["current"] = null
	var c := fiber.child
	while c != null:
		_null_refs_recursive(c)
		c = c.sibling

func _commit_portal_retarget(fiber: RuitkFiber) -> void:
	if fiber.portal_target == null or not is_instance_valid(fiber.portal_target):
		return
	var ordered: Array = []
	_collect_host_children(fiber, ordered)
	for nd in ordered:
		if is_instance_valid(nd) and nd.get_parent() != fiber.portal_target:
			if nd.get_parent() != null:
				nd.get_parent().remove_child(nd)
			fiber.portal_target.add_child(nd)
	if RuitkDiagnostics.trace_level == RuitkDiagnostics.TraceLevel.VERBOSE:   # per-element detail
		RuitkDiagnostics.trace("[Fiber] PortalRetarget %d node(s) -> %s" % [ordered.size(), fiber.portal_target.name])

# --------------------------------------------------------------------------
# Effects
# --------------------------------------------------------------------------

func _commit_layout_effects(fiber: RuitkFiber) -> void:
	if fiber.state == null:
		return
	for e in fiber.state.layout_effects:
		if e["last_deps"] == null or Hooks._deps_changed(e["last_deps"], e["deps"]):
			if e["cleanup"] is Callable and e["cleanup"].is_valid():
				e["cleanup"].call()
			var ret = e["factory"].call()
			e["cleanup"] = ret if (ret is Callable and ret.is_valid()) else null
			e["last_deps"] = e["deps"].duplicate() if e["deps"] is Array else e["deps"]

## Two passes across all collected fibers: every cleanup first, then every setup.
func _flush_passive() -> void:
	for fiber in _pending_passive:
		if fiber.state == null: continue
		for e in fiber.state.effects:
			if (e["last_deps"] == null or Hooks._deps_changed(e["last_deps"], e["deps"])) \
					and e["cleanup"] is Callable and e["cleanup"].is_valid():
				e["cleanup"].call()
				e["cleanup"] = null
	for fiber in _pending_passive:
		if fiber.state == null: continue
		for e in fiber.state.effects:
			if e["last_deps"] == null or Hooks._deps_changed(e["last_deps"], e["deps"]):
				var ret = e["factory"].call()
				e["cleanup"] = ret if (ret is Callable and ret.is_valid()) else null
				e["last_deps"] = e["deps"].duplicate() if e["deps"] is Array else e["deps"]
	_pending_passive = []

func _run_cleanups(fiber: RuitkFiber) -> void:
	if fiber.state == null:
		return
	for arr in [fiber.state.effects, fiber.state.layout_effects]:
		for e in arr:
			if e["cleanup"] is Callable and e["cleanup"].is_valid():
				e["cleanup"].call()
				e["cleanup"] = null

func _run_cleanups_recursive(fiber: RuitkFiber) -> void:
	_run_cleanups(fiber)
	var c := fiber.child
	while c != null:
		_run_cleanups_recursive(c)
		c = c.sibling
	_dispose_fiber_state(fiber)

## Break a (deleted/unmounted) component's state cycles. The state setter/dispatch/
## on_state_updated lambdas capture `state`, and `state` stores them back → a RefCounted
## cycle that won't free. Only called on teardown, so the state is no longer shared.
func _dispose_fiber_state(fiber: RuitkFiber) -> void:
	if fiber.state == null:
		return
	var st: RuitkComponentState = fiber.state
	for slot in st.hooks:   # release external subscriptions (useSignal) before dropping slots
		if slot is Dictionary and slot.get("unsub") is Callable and slot["unsub"].is_valid():
			slot["unsub"].call()
	st.on_state_updated = Callable()
	st.hooks = []
	st.effects = []
	st.layout_effects = []
	st.context_deps = []
	st.last_output = []
	st.fiber = null
	fiber.state = null

# --------------------------------------------------------------------------
# Context
# --------------------------------------------------------------------------

func _has_context_changed(fiber: RuitkFiber) -> bool:
	if fiber.state == null:
		return false
	for dep in fiber.state.context_deps:
		if not Hooks._equal(Hooks._resolve_context(fiber, dep["key"]), dep["value"]):
			return true
	return false

# --------------------------------------------------------------------------
# Host-tree helpers
# --------------------------------------------------------------------------

## Nearest ancestor host node into which `fiber`'s node should be parented (honoring
## portals and a container's resolved child host).
func _host_parent_node(fiber: RuitkFiber) -> Node:
	var p := fiber.parent
	while p != null:
		if p.is_portal() and p.portal_target != null:
			return p.portal_target
		if p.node != null:
			return RuitkHost.resolve_child_host(p.node)
		p = p.parent
	return null

func _enforce_child_order(parent_fiber: RuitkFiber) -> void:
	var pnode: Node = null
	if parent_fiber.is_portal():
		pnode = parent_fiber.portal_target
	elif parent_fiber.node != null:
		pnode = RuitkHost.resolve_child_host(parent_fiber.node)
	if pnode == null or not is_instance_valid(pnode):
		return
	var ordered: Array = []
	_collect_host_children(parent_fiber, ordered)
	RuitkHost.warn_capacity(pnode, ordered.size())
	for i in ordered.size():
		var nd: Node = ordered[i]
		if is_instance_valid(nd) and nd.get_parent() == pnode and pnode.get_child(i) != nd:
			pnode.move_child(nd, i)

func _collect_host_children(fiber: RuitkFiber, out: Array) -> void:
	var c := fiber.child
	while c != null:
		if c.tag == F.Tag.PORTAL:   # inlined tag check [perf P4]
			pass  # portal children live under portal_target, not here
		elif c.node != null:
			out.append(c.node)
		else:
			_collect_host_children(c, out)
		c = c.sibling

func _free_host_nodes(fiber: RuitkFiber) -> void:
	if fiber.node != null and not fiber.is_root():
		if is_instance_valid(fiber.node):
			# GO-05: recycle a CHILDLESS leaf (the churn-heavy case — Doom bands, list rows) into
			# the pool for reuse; a node WITH children keeps the queue_free cascade (freeing the
			# whole subtree at once, and never pooling a non-childless node). get_child_count()==0
			# also excludes rui_content/custom-scene nodes, which carry internal children.
			if RuitkConfig.host_node_pool and fiber.node.get_child_count() == 0:
				_recycle_node(fiber.node, fiber.props)
			else:
				fiber.node.queue_free()
		return
	var c := fiber.child
	while c != null:
		_free_host_nodes(c)
		c = c.sibling

## GO-05: pull a reset, orphaned node of `type` from the pool, or instantiate one. The pooled
## node is indistinguishable from a fresh instantiate (see RuitkHost.reset_for_pool), so the mount
## path's apply_props(node, {}, new_props) applies cleanly.
func _acquire_node(type: String) -> Node:
	if RuitkConfig.host_node_pool:
		var bucket = _node_pool.get(type)
		if bucket is Array and not bucket.is_empty():
			return bucket.pop_back()
	return RuitkHost.create_node(type)

## GO-05: reset `node` and return it to the pool (capped), or queue_free if it can't be pooled
## (item-model control) or the bucket is full. `props` is the fiber's last-applied props, used to
## undo exactly what was set.
func _recycle_node(node: Node, props) -> void:
	if not RuitkHost.reset_for_pool(node, props):
		node.queue_free()
		return
	var cls := node.get_class()
	var bucket = _node_pool.get(cls)
	if not (bucket is Array):
		bucket = []
		_node_pool[cls] = bucket
	if bucket.size() < _POOL_CAP_PER_CLASS:
		bucket.append(node)
	else:
		node.queue_free()

## The first child of `fiber`'s child list (or null) — the head of the old sibling chain
## that `_reconcile_children` walks. Replaces the old per-frame Array materialization. [perf P1]
func _old_first(fiber: RuitkFiber) -> RuitkFiber:
	return fiber.child if fiber != null else null

func _normalize_children(arr) -> Array:
	if arr == null:
		return []
	# Fast path: already a flat array of vnodes (the common case — component output and
	# explicit child arrays). Skip the flatten + a fresh array allocation. [perf #5]
	for c in arr:
		if not (c is RuitkVNode):
			var out: Array = []
			_flatten_into(arr, out)
			return out
	return arr

func _flatten_into(arr, out: Array) -> void:
	if arr == null:
		return
	for c in arr:
		if c == null:
			continue
		if c is Array:
			_flatten_into(c, out)   # flatten nested arrays of any depth [audit m7]
		elif c is RuitkVNode:
			out.append(c)
		elif c is String:
			out.append(V.text(c))   # auto-wrap a raw String child as a text Label (Phase 7.2)

func _to_vnode_array(result) -> Array:
	if result == null:
		return []
	if result is RuitkVNode:
		return [result]
	if result is String:
		return [V.text(result)]   # a component may return a bare String (Phase 7.2)
	if result is Array:
		return _normalize_children(result)
	return []

func _vnode_list_equal(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if a[i] != b[i]:
			return false
	return true

func _any_keyed(vnodes: Array) -> bool:
	for vn in vnodes:
		if vn.key != null:
			return true
	return false

## Reconciliation key: the user key, or a namespaced positional key (control-char prefixed
## so it can never equal a real user key) for unkeyed children.
func _fiber_key(f: RuitkFiber):
	return f.key if f.key != null else "idx%d" % f.index

func _vnode_key(vn: RuitkVNode, idx: int):
	return vn.key if vn.key != null else "idx%d" % idx

# --------------------------------------------------------------------------
# Trace ladder (RuitkDiagnostics.trace_level / diff_tracing) — describe helpers.
# Called ONLY inside a trace gate; never on the ungated hot path.
# --------------------------------------------------------------------------

## Human label for a fiber in trace output: host class name, component method, or tag name.
func _trace_desc(fiber: RuitkFiber) -> String:
	if fiber.type != "":
		return fiber.type
	if fiber.tag == F.Tag.FUNCTION and fiber.component.is_valid():
		var m := fiber.component.get_method()
		return m if m != "" else "<anonymous>"
	return str(F.Tag.keys()[fiber.tag])

## Same, for a vnode (the incoming side of a replacement).
func _trace_vnode_desc(vnode: RuitkVNode) -> String:
	if vnode.type != "":
		return vnode.type
	if vnode.kind == RuitkVNode.Kind.FUNCTION and vnode.component.is_valid():
		var m := vnode.component.get_method()
		return m if m != "" else "<anonymous>"
	return str(RuitkVNode.Kind.keys()[vnode.kind])

# --------------------------------------------------------------------------
# Tree lifecycle / teardown (break RefCounted cycles; shared state survives)
# --------------------------------------------------------------------------

## Break all RefCounted cycles in a no-longer-referenced subtree AND its double-buffer
## buddies, so it frees. Used on deletion and unmount. With fiber reuse there is no
## per-frame sever — only genuinely-removed subtrees pass through here. Does NOT follow the
## root fiber's `sibling` (that points outside the subtree, into the live tree). [perf #1]
func _release(fiber: RuitkFiber) -> void:
	if fiber == null:
		return
	var c := fiber.child
	while c != null:
		var nxt := c.sibling
		_release(c)
		c = nxt
	var alt := fiber.alternate
	fiber.parent = null
	fiber.child = null
	fiber.sibling = null
	fiber.alternate = null
	fiber.next_effect = null
	fiber.deletions = []
	fiber.node = null
	fiber.state = null
	if alt != null:   # release the buddy too (its children are buddies of ours, already freed)
		alt.parent = null
		alt.child = null
		alt.sibling = null
		alt.alternate = null
		alt.next_effect = null
		alt.deletions = []
		alt.node = null
		alt.state = null

func unmount() -> void:
	_cancel_pending_tick()
	_pending_eb_activations.clear()
	if not _hmr_live.is_empty():   # drop our Fast Refresh registration (and any dead refs with it)
		var kept: Array = []
		for wr in _hmr_live:
			var rec = wr.get_ref()
			if rec != null and rec != self:
				kept.append(wr)
		_hmr_live = kept
	if _root_current == null:
		return
	var c := _root_current.child
	while c != null:
		_null_refs_recursive(c)
		_run_cleanups_recursive(c)
		_free_host_nodes(c)
		c = c.sibling
	_release(_root_current)
	_root_current = null
	_root_vnode = null
	_drain_node_pool()

## GO-05: free every orphaned node still held in the pool. Called on unmount so a torn-down
## root leaks nothing (the pool's whole purpose is transient reuse WITHIN a live root's churn).
func _drain_node_pool() -> void:
	for cls in _node_pool:
		for n in _node_pool[cls]:
			if is_instance_valid(n):
				n.queue_free()
	_node_pool.clear()

# --------------------------------------------------------------------------
# Fast Refresh (Phase H) — see core/hmr.gd for the pipeline overview
# --------------------------------------------------------------------------

## Re-render after an in-place script reload, across every live root. `scripts` are the
## reloaded GDScript resources; `resets` the subset whose hook signature changed (their
## components get a deliberate state reset); `global_rerender` = a hooks/module file changed,
## so EVERY function fiber re-runs (any component may call it). Returns fibers refreshed.
static func hmr_refresh_all(scripts: Array, resets: Array, global_rerender: bool) -> int:
	var total := 0
	var alive: Array = []
	for wr in _hmr_live:
		var rec = wr.get_ref()
		if rec == null:
			continue
		alive.append(wr)
		total += rec.hmr_refresh(scripts, resets, global_rerender)
	_hmr_live = alive
	return total

## One root's refresh: mark the affected fibers dirty (defeating the bailout's cached-output
## reuse — the whole reason a reload alone changes nothing on screen), then FLUSH SYNCHRONOUSLY
## and unsliced. The reload already happened, so any handler still wired to live UI was minted
## by the old script version; committing before control returns to the main loop means no input
## event can ever run in the half-swapped world.
func hmr_refresh(scripts: Array, resets: Array, global_rerender: bool) -> int:
	if _root_current == null:
		return 0
	var marked := _hmr_mark(_root_current, scripts, resets, global_rerender)
	if marked > 0:
		var sliced: bool = RuitkConfig.time_slicing
		RuitkConfig.time_slicing = false
		_tick()
		RuitkConfig.time_slicing = sliced
	return marked

func _hmr_mark(fiber: RuitkFiber, scripts: Array, resets: Array, global_rerender: bool) -> int:
	var n := 0
	if fiber.tag == F.Tag.FUNCTION:
		var obj = fiber.component.get_object()
		if global_rerender or scripts.has(obj):
			if resets.has(obj):
				_hmr_reset_state(fiber)
			schedule_update_on_fiber(fiber, null)
			n += 1
	var c := fiber.child
	while c != null:
		n += _hmr_mark(c, scripts, resets, global_rerender)
		c = c.sibling
	return n

## Deliberate state reset (Unity FullResetComponentState parity): the component's hook SHAPE
## changed, so its slots no longer line up — run its effect cleanups, drop subscriptions, and
## null the state; the next render (scheduled by the caller) primes a fresh RuitkComponentState
## and the hook-order guard re-locks on it. Children keep their own state unless their script
## changed too — reset is strictly per-fiber.
func _hmr_reset_state(fiber: RuitkFiber) -> void:
	if fiber.state == null:
		return
	_run_cleanups(fiber)
	_dispose_fiber_state(fiber)
