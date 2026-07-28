class_name RUIReconciler
extends RefCounted
## The fiber reconciler. Ports ReactiveUIToolKit's FiberReconciler to a synchronous
## (non-time-sliced) work loop:
##
##   render phase   -> begin_work (reconcile children, run components) descending, then
##                     complete_work (create/diff host nodes, build the effect list) on
##                     the way back up. Post-order effect list = children before parents.
##   commit phase   -> deletions -> effect list (placement/update/layout effects) ->
##                     enforce child order -> swap current<->wip -> two-pass passive
##                     effects -> release the old tree -> replay deferred updates.
##
## Updates are coalesced (a hook setter schedules one deferred render per frame). Bailout
## skips re-running a component's render fn when its props/state/context/children are
## unchanged (reusing the cached output); the fiber tree is still rebuilt each pass —
## true O(changed) subtree carry-over is a later perf optimization (see PORTING_PLAN 1.9).
##
## GDScript divergences vs the C# original:
##   - No exceptions: error boundaries render a fallback on demand but cannot auto-catch
##     a render-time crash (GDScript has no try/catch). See `_begin_error_boundary`.
##   - Fresh fibers each pass (no 2-object double-buffer reuse) — simpler lifecycle, GC'd
##     via explicit cycle-severing.

const F = preload("res://addons/reactive_ui_toolkit/core/fiber.gd")
const Hmr = preload("res://addons/reactive_ui_toolkit/core/hmr.gd")

## --- Fast Refresh registry (Phase H) ---------------------------------------------------------
## Live reconcilers. Registration is unconditional (one WeakRef append per root — negligible,
## and it keeps HMR headless-testable); the debugger-channel hookup in hmr.gd is what gates the
## actual feature to editor-attached runs. WeakRefs: roots are RefCounted-owned by their
## creators and HMR must never extend a lifetime; dead refs are pruned on every use and on
## unmount. hmr.gd walks this list to re-render after an in-place script reload.
static var _hmr_live: Array = []

var _container: Node
var _root_vnode: RUIVNode = null
var _root_current: RUIFiber = null

var _wip_root: RUIFiber = null
var _next_unit: RUIFiber = null

var _first_effect: RUIFiber = null
var _last_effect: RUIFiber = null
var _deletions: Array = []
var _reorder_set: Dictionary = {}        ## host/portal fibers whose child order may have changed
var _pending_passive: Array = []
## Reused across full-keyed reconcile passes (GO-08): cleared+refilled per call instead of a
## fresh Dictionary each frame. Safe because _reconcile_children never re-enters before it
## finishes (_reconcile creates a fiber but does not recurse into _reconcile_children), and
## this member is per-reconciler so concurrent ReactiveRoots don't share it.
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
var _restart := false          ## update arrived mid-render -> rebuild from root (clears effect list)
var _tick_pending := false     ## a _tick is scheduled (call_deferred or process_frame)
var _restart_count := 0

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

func render(vnode: RUIVNode) -> void:
	# Initial / top-level mount is always synchronous (no time-slicing) to avoid an empty
	# first frame. Cancel any parked sliced render first so its process_frame tick can't fire
	# after us, and mark `_work_active` so a setState during render restarts coherently. [M7/M8]
	if _root_current == null:
		return   # torn down by unmount() — a render after teardown is a no-op, not a crash [audit]
	_cancel_pending_tick()
	_root_vnode = vnode
	_root_current.has_pending_update = true
	_work_active = true
	_begin_render()
	while _next_unit != null:
		_next_unit = _perform_unit(_next_unit)
	_work_active = false
	_restart = false
	_commit_root()

## Mark a fiber dirty and (unless we're mid-commit) schedule a coalesced render.
func schedule_update_on_fiber(fiber: RUIFiber, vnode) -> void:
	if _root_current == null:
		return   # torn down by unmount() — ignore late setState/effect callbacks [audit]
	if vnode != null:
		_root_vnode = vnode
	var target := fiber if fiber != null else _root_current
	target.has_pending_update = true
	var p := target.parent
	while p != null:
		p.subtree_has_updates = true
		p = p.parent
	if _is_committing:
		_deferred_updates.append([target, vnode])
		return
	if _work_active:
		_restart = true   # update mid-render -> rebuild from root next tick (resets effect list)
	_ensure_tick()

func request_update() -> void:
	schedule_update_on_fiber(_root_current, null)

func _ensure_tick() -> void:
	if _tick_pending:
		return
	_tick_pending = true
	call_deferred("_tick")

## One work pass. Runs the whole render at once unless time-slicing is on, in which case
## it processes until the frame budget is hit, then parks until the next frame. An update
## arriving mid-render sets `_restart`, which rebuilds from the root (clearing the effect
## list) — the invariant that prevents stale Placement effects re-committing.
func _tick() -> void:
	_tick_pending = false
	if _root_vnode == null or not is_instance_valid(_container):
		_work_active = false
		return
	if not _work_active or _restart:
		if _restart:
			_restart_count += 1
			if _restart_count > 25:
				push_error("[reactive_ui_toolkit] Too many re-renders (setState during render?). Aborting pass.")
				_work_active = false
				_restart = false
				_restart_count = 0
				return
		else:
			_restart_count = 0
		_begin_render()
		_restart = false
		_work_active = true

	var start := Time.get_ticks_msec()
	var sliced: bool = RUIConfig.time_slicing
	var budget: float = RUIConfig.frame_budget_ms
	while _next_unit != null:
		_next_unit = _perform_unit(_next_unit)
		if _restart:
			break
		if sliced and float(Time.get_ticks_msec() - start) >= budget:
			break

	if _restart:
		_ensure_tick()
		return
	if _next_unit == null:
		_work_active = false
		_restart_count = 0
		_commit_root()
	else:
		_park()

## Resume the parked render on the next frame (time-slicing only).
func _park() -> void:
	if _tick_pending:
		return
	_tick_pending = true
	var tree := _get_tree_safe()
	if tree != null:
		tree.process_frame.connect(_tick, CONNECT_ONE_SHOT)
	else:
		call_deferred("_tick")

## Sever a parked process_frame continuation (when render()/unmount() pre-empts a sliced
## render still in flight), so a stale tick can't fire on a torn-down/replaced tree. [M7]
func _cancel_pending_tick() -> void:
	_tick_pending = false
	var tree := _get_tree_safe()
	if tree != null and tree.process_frame.is_connected(_tick):
		tree.process_frame.disconnect(_tick)

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
	var wip: RUIFiber = _root_current.alternate
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

func _perform_unit(fiber: RUIFiber) -> RUIFiber:
	# begin-work (inlined — one fewer call per fiber per frame) [perf]
	var next: RUIFiber
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

func _begin_function(fiber: RUIFiber) -> RUIFiber:
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

func _render_component(fiber: RUIFiber) -> Array:
	var state: RUIComponentState = fiber.state
	Hooks._begin(state)
	var result = fiber.component.call(fiber.pending_props, fiber.input_children)
	Hooks._end()
	RUIDiagnostics.on_render()
	state.last_output = _to_vnode_array(result)
	if not state.effects.is_empty():
		fiber.effect_tag |= F.EFFECT_PASSIVE
	if not state.layout_effects.is_empty():
		fiber.effect_tag |= F.EFFECT_LAYOUT
	return state.last_output

func _begin_error_boundary(fiber: RUIFiber) -> RUIFiber:
	# NOTE: GDScript has no try/catch, so this cannot auto-catch a child render crash.
	# It renders the fallback when `eb_active` is set (toggled imperatively) and clears it
	# when `reset_key` changes. Structural parity; auto-catch is a documented limitation.
	var alt := fiber.alternate
	var reset_requested: bool = alt == null or alt.eb_reset_key != fiber.eb_reset_key
	if reset_requested:
		fiber.eb_active = false
		fiber.eb_showing_fallback = false
		fiber.eb_last_error = null
	var children: Array
	if fiber.eb_active and not reset_requested:
		children = [fiber.eb_fallback] if fiber.eb_fallback != null else []
	else:
		children = fiber.eb_children
	if _reconcile_children(fiber, _old_first(alt), children):
		return null
	return fiber.child

# --------------------------------------------------------------------------
# Reconciliation
# --------------------------------------------------------------------------

## Create-or-reuse a fiber for `vnode` matched against `old_fiber`.
## Create-or-reuse a WIP fiber for `vnode`, matched against `old_fiber`. DOUBLE-BUFFERED:
## when the type matches we reuse `old_fiber`'s ping-pong buddy (its alternate) instead of
## allocating — so a stable tree position costs ZERO fiber allocations after first mount.
## Only a true placement / type-change allocates. [perf #1]
func _reconcile(parent_fiber: RUIFiber, old_fiber: RUIFiber, vnode: RUIVNode, idx: int) -> RUIFiber:
	var reuse: bool = old_fiber != null and old_fiber.matches(vnode)
	var fiber: RUIFiber
	if reuse:
		fiber = old_fiber.alternate
		if fiber == null:
			fiber = F.new()
		fiber.alternate = old_fiber
		old_fiber.alternate = fiber
	else:
		fiber = F.new()
		fiber.alternate = null
		if old_fiber != null:
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
	if vk == RUIVNode.Kind.HOST:
		fiber.tag = F.Tag.HOST
		fiber.type = vnode.type
		fiber.component = Callable()
		fiber.portal_target = null
	else:
		fiber.tag = F.tag_for_vnode(vnode)
		fiber.type = ""
		fiber.component = vnode.component if vk == RUIVNode.Kind.FUNCTION else Callable()
		fiber.portal_target = vnode.portal_target if vk == RUIVNode.Kind.PORTAL else null
	if vk == RUIVNode.Kind.ERROR_BOUNDARY:
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
		var st := RUIComponentState.new()
		st.fiber = fiber
		st.on_state_updated = _make_on_state_updated(st)
		fiber.state = st
	return fiber

func _make_on_state_updated(state: RUIComponentState) -> Callable:
	return func(): schedule_update_on_fiber(state.fiber, null)

## Reconcile `child_vnodes` against the OLD child linked-list (starting at `old_first`).
## Walks the sibling chain directly — no per-frame Array materialization. [perf P1]
## Returns TRUE if it took the fast-list path and fully handled the children in place — the
## caller must then NOT descend (the children are not on the work queue). Returns FALSE for the
## normal path (caller descends into parent_fiber.child as usual).
func _reconcile_children(parent_fiber: RUIFiber, old_first: RUIFiber, child_vnodes: Array) -> bool:
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

	var prev: RUIFiber = null
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
		var ock := old_first
		while ock != null:
			_key_map[_fiber_key(ock)] = ock
			ock.matched_pass = false
			ock = ock.sibling
		for i in vnodes.size():
			var vn: RUIVNode = vnodes[i]
			var old_match: RUIFiber = _key_map.get(_vnode_key(vn, i))
			if old_match != null and (old_match.matched_pass or not old_match.matches(vn)):
				old_match = null
			if old_match != null:
				old_match.matched_pass = true
				if old_match.index != i:
					structural = true   # moved
			else:
				structural = true       # new placement
			var cf := _reconcile(parent_fiber, old_match, vn, i)
			if prev == null: parent_fiber.child = cf
			else: prev.sibling = cf
			prev = cf
		var ocd := old_first
		while ocd != null:
			var nxtd := ocd.sibling
			if not ocd.matched_pass:
				_delete_fiber(parent_fiber, ocd)
			ocd = nxtd
		_key_map.clear()
	else:
		# index (positional) path
		var oci := old_first
		for i in vnodes.size():
			var old_match: RUIFiber = oci
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
func _try_fast_leaf_list(parent_fiber: RUIFiber, old_first: RUIFiber, vnodes: Array, ignore_keys: bool = false) -> bool:
	var n := vnodes.size()
	# 1. Eligibility scan (read-only): every position must be a childless HOST with matching
	#    type + key, and the same count. With `ignore_keys` (GO-09 reuse_by_slot) the per-slot
	#    key match is skipped — a stateless leaf is interchangeable by slot — but type + leafness
	#    + count are still required (a slot must hold the same node CLASS to reuse it in place).
	var oc := old_first
	for i in n:
		if oc == null:
			return false
		var vn: RUIVNode = vnodes[i]
		# (oc.tag == HOST is implied by oc.type == vn.type, since only host fibers carry a type.)
		if vn.kind != RUIVNode.Kind.HOST or oc.type != vn.type or (not ignore_keys and oc.key != vn.key):
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
		var vn: RUIVNode = vnodes[i]
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
func _keys_stable(old_first: RUIFiber, vnodes: Array) -> bool:
	var oc := old_first
	for i in vnodes.size():
		if oc == null:
			return false
		var vn: RUIVNode = vnodes[i]
		# Inlined key compare + HOST matches() — this scan runs once per element every frame,
		# so the elided _fiber_key/_vnode_key/matches calls are thousands/frame saved. [perf]
		var ok = oc.key
		var vnk = vn.key
		if ok != null or vnk != null:
			if ok != vnk:
				return false
		elif oc.index != i:        # both unkeyed -> must be the same position
			return false
		if vn.kind == RUIVNode.Kind.HOST:
			if oc.tag != F.Tag.HOST or oc.type != vn.type:
				return false
		elif not oc.matches(vn):
			return false
		oc = oc.sibling
	return oc == null   # old list must be exactly the same length

func _delete_fiber(parent_fiber: RUIFiber, old_fiber: RUIFiber) -> void:
	old_fiber.effect_tag |= F.EFFECT_DELETION
	parent_fiber.deletions.append(old_fiber)
	_deletions.append(old_fiber)
	_mark_reorder(parent_fiber)

## Mark the nearest host (or portal) ancestor so its child order is re-asserted at commit.
func _mark_reorder(parent_fiber: RUIFiber) -> void:
	var f := parent_fiber
	while f != null:
		if f.tag == F.Tag.PORTAL or f.node != null:   # inlined tag check (hot) [perf P4]
			_reorder_set[f] = true
			return
		f = f.parent

# --------------------------------------------------------------------------
# Complete phase — create/diff host nodes, build the effect list (post-order)
# --------------------------------------------------------------------------

func _complete_work(fiber: RUIFiber) -> void:
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
					RUIHost.reset_removed_plain(fiber.node, old_props, fiber.pending_props)
				RUIHost.apply_props(fiber.node, old_props, fiber.pending_props)
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
	RUIDiagnostics.on_commit()

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

	_root_current = _wip_root
	_is_committing = false

	_flush_passive()
	# No per-frame tree-sever: the old current tree IS next frame's reusable buddy pool
	# (double-buffering). Only genuinely-deleted subtrees are released (in _commit_deletion). [perf #1]

	if not _deferred_updates.is_empty():
		var deferred := _deferred_updates
		_deferred_updates = []
		for entry in deferred:
			schedule_update_on_fiber(entry[0], entry[1])

func _commit_placement(fiber: RUIFiber) -> void:
	if fiber.node == null or not is_instance_valid(fiber.node):
		return
	var parent_node := _host_parent_node(fiber)
	if parent_node != null and is_instance_valid(parent_node) and fiber.node.get_parent() != parent_node:
		parent_node.add_child(fiber.node)
		RUIDiagnostics.on_placement()

func _commit_update(fiber: RUIFiber) -> void:
	if fiber.node == null or not is_instance_valid(fiber.node):
		return
	var new_props: Dictionary = fiber.pending_props
	# (Re)build the cached apply plan whenever the prop SHAPE (key count) changes. [perf]
	if new_props.size() != fiber.apply_size:
		_build_apply_plan(fiber, new_props)
	if fiber.apply_special:
		# Element has (or ever had) events / ref / style / item-model -> full generic apply.
		RUIHost.apply_props(fiber.node, fiber.props, new_props)
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
				RUIHost.apply_props(node, old_props, new_props)
				break
			var val = new_props[k]
			if not old_props.has(k) or old_props[k] != val:
				RUIHost._set_prop(node, k, val)
	fiber.props = new_props
	if RUIDiagnostics.enabled: RUIDiagnostics.on_update()

## Classify a host element's props ONCE: plain prop keys (diffed+written each frame) vs
## "special" (events / ref / style / item-model -> needs the generic apply). apply_special is
## STICKY so an element that ever had events/ref/style keeps using the generic path (which
## correctly disconnects/resets them). [perf: inline-cache apply]
func _build_apply_plan(fiber: RUIFiber, props: Dictionary) -> void:
	fiber.apply_size = props.size()
	var plain: Array = []
	for k in props:
		if k == "ref" or k == "style" or k == "items" or k == "classes":
			fiber.apply_special = true
		elif k == "key" or k == "children":
			pass
		elif RUIHost._is_event(k):
			fiber.apply_special = true
		else:
			plain.append(k)
	fiber.apply_plain = plain   # skip the call when off [perf]

func _commit_deletion(old_fiber: RUIFiber) -> void:
	RUIDiagnostics.on_deletion()
	_null_refs_recursive(old_fiber)
	_run_cleanups_recursive(old_fiber)
	_free_host_nodes(old_fiber)
	_release(old_fiber)   # break cycles so the removed subtree + its buddies free [perf #1]

## Reset any `ref` prop to null for deleted host fibers, so a useRef box / callback ref
## doesn't dangle to a freed node (React nulls refs on unmount). [audit C2]
func _null_refs_recursive(fiber: RUIFiber) -> void:
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

func _commit_portal_retarget(fiber: RUIFiber) -> void:
	if fiber.portal_target == null or not is_instance_valid(fiber.portal_target):
		return
	var ordered: Array = []
	_collect_host_children(fiber, ordered)
	for nd in ordered:
		if is_instance_valid(nd) and nd.get_parent() != fiber.portal_target:
			if nd.get_parent() != null:
				nd.get_parent().remove_child(nd)
			fiber.portal_target.add_child(nd)

# --------------------------------------------------------------------------
# Effects
# --------------------------------------------------------------------------

func _commit_layout_effects(fiber: RUIFiber) -> void:
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

func _run_cleanups(fiber: RUIFiber) -> void:
	if fiber.state == null:
		return
	for arr in [fiber.state.effects, fiber.state.layout_effects]:
		for e in arr:
			if e["cleanup"] is Callable and e["cleanup"].is_valid():
				e["cleanup"].call()
				e["cleanup"] = null

func _run_cleanups_recursive(fiber: RUIFiber) -> void:
	_run_cleanups(fiber)
	var c := fiber.child
	while c != null:
		_run_cleanups_recursive(c)
		c = c.sibling
	_dispose_fiber_state(fiber)

## Break a (deleted/unmounted) component's state cycles. The state setter/dispatch/
## on_state_updated lambdas capture `state`, and `state` stores them back → a RefCounted
## cycle that won't free. Only called on teardown, so the state is no longer shared.
func _dispose_fiber_state(fiber: RUIFiber) -> void:
	if fiber.state == null:
		return
	var st: RUIComponentState = fiber.state
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

func _has_context_changed(fiber: RUIFiber) -> bool:
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
func _host_parent_node(fiber: RUIFiber) -> Node:
	var p := fiber.parent
	while p != null:
		if p.is_portal() and p.portal_target != null:
			return p.portal_target
		if p.node != null:
			return RUIHost.resolve_child_host(p.node)
		p = p.parent
	return null

func _enforce_child_order(parent_fiber: RUIFiber) -> void:
	var pnode: Node = null
	if parent_fiber.is_portal():
		pnode = parent_fiber.portal_target
	elif parent_fiber.node != null:
		pnode = RUIHost.resolve_child_host(parent_fiber.node)
	if pnode == null or not is_instance_valid(pnode):
		return
	var ordered: Array = []
	_collect_host_children(parent_fiber, ordered)
	RUIHost.warn_capacity(pnode, ordered.size())
	for i in ordered.size():
		var nd: Node = ordered[i]
		if is_instance_valid(nd) and nd.get_parent() == pnode and pnode.get_child(i) != nd:
			pnode.move_child(nd, i)

func _collect_host_children(fiber: RUIFiber, out: Array) -> void:
	var c := fiber.child
	while c != null:
		if c.tag == F.Tag.PORTAL:   # inlined tag check [perf P4]
			pass  # portal children live under portal_target, not here
		elif c.node != null:
			out.append(c.node)
		else:
			_collect_host_children(c, out)
		c = c.sibling

func _free_host_nodes(fiber: RUIFiber) -> void:
	if fiber.node != null and not fiber.is_root():
		if is_instance_valid(fiber.node):
			# GO-05: recycle a CHILDLESS leaf (the churn-heavy case — Doom bands, list rows) into
			# the pool for reuse; a node WITH children keeps the queue_free cascade (freeing the
			# whole subtree at once, and never pooling a non-childless node). get_child_count()==0
			# also excludes rui_content/custom-scene nodes, which carry internal children.
			if RUIConfig.host_node_pool and fiber.node.get_child_count() == 0:
				_recycle_node(fiber.node, fiber.props)
			else:
				fiber.node.queue_free()
		return
	var c := fiber.child
	while c != null:
		_free_host_nodes(c)
		c = c.sibling

## GO-05: pull a reset, orphaned node of `type` from the pool, or instantiate one. The pooled
## node is indistinguishable from a fresh instantiate (see RUIHost.reset_for_pool), so the mount
## path's apply_props(node, {}, new_props) applies cleanly.
func _acquire_node(type: String) -> Node:
	if RUIConfig.host_node_pool:
		var bucket = _node_pool.get(type)
		if bucket is Array and not bucket.is_empty():
			return bucket.pop_back()
	return RUIHost.create_node(type)

## GO-05: reset `node` and return it to the pool (capped), or queue_free if it can't be pooled
## (item-model control) or the bucket is full. `props` is the fiber's last-applied props, used to
## undo exactly what was set.
func _recycle_node(node: Node, props) -> void:
	if not RUIHost.reset_for_pool(node, props):
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
func _old_first(fiber: RUIFiber) -> RUIFiber:
	return fiber.child if fiber != null else null

func _normalize_children(arr) -> Array:
	if arr == null:
		return []
	# Fast path: already a flat array of vnodes (the common case — component output and
	# explicit child arrays). Skip the flatten + a fresh array allocation. [perf #5]
	for c in arr:
		if not (c is RUIVNode):
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
		elif c is RUIVNode:
			out.append(c)
		elif c is String:
			out.append(V.text(c))   # auto-wrap a raw String child as a text Label (Phase 7.2)

func _to_vnode_array(result) -> Array:
	if result == null:
		return []
	if result is RUIVNode:
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
func _fiber_key(f: RUIFiber):
	return f.key if f.key != null else "idx%d" % f.index

func _vnode_key(vn: RUIVNode, idx: int):
	return vn.key if vn.key != null else "idx%d" % idx

# --------------------------------------------------------------------------
# Tree lifecycle / teardown (break RefCounted cycles; shared state survives)
# --------------------------------------------------------------------------

## Break all RefCounted cycles in a no-longer-referenced subtree AND its double-buffer
## buddies, so it frees. Used on deletion and unmount. With fiber reuse there is no
## per-frame sever — only genuinely-removed subtrees pass through here. Does NOT follow the
## root fiber's `sibling` (that points outside the subtree, into the live tree). [perf #1]
func _release(fiber: RUIFiber) -> void:
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
		var sliced: bool = RUIConfig.time_slicing
		RUIConfig.time_slicing = false
		_tick()
		RUIConfig.time_slicing = sliced
	return marked

func _hmr_mark(fiber: RUIFiber, scripts: Array, resets: Array, global_rerender: bool) -> int:
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
## null the state; the next render (scheduled by the caller) primes a fresh RUIComponentState
## and the hook-order guard re-locks on it. Children keep their own state unless their script
## changed too — reset is strictly per-fiber.
func _hmr_reset_state(fiber: RUIFiber) -> void:
	if fiber.state == null:
		return
	_run_cleanups(fiber)
	_dispose_fiber_state(fiber)
