class_name RuitkRoot
extends RefCounted
## Mounts a reactive UI tree under a target Control/Node and owns the reconciler.
## Mirrors ReactiveUIToolKit's `RootRenderer`.
##
## IMPORTANT: keep the returned RuitkRoot referenced for as long as the UI should
## live (store it in a script variable). It owns the reconciler; if it is collected,
## scheduled re-renders stop. Call `unmount()` to tear the UI down and run cleanups.
##
## Example:
##   var _app: RuitkRoot
##   func _ready() -> void:
##       _app = RuitkRoot.create(self, V.fc(_my_app))

var _reconciler: RuitkReconciler

## The scheduler this root OWNS, when it was created isolated. Null for an ordinary root, which
## shares its SceneTree's instance.
var _own_scheduler: RuitkScheduler = null

## Create a root, mount `root_vnode` (usually `V.fc(...)`) under `container`, and do
## the initial render.
static func create(container: Node, root_vnode: RuitkVNode) -> RuitkRoot:
	# Load user-changed reactive_ui_toolkit/* Project Settings onto the RuitkConfig /
	# RuitkDiagnostics statics before the first render. One-shot — free after the first call.
	RuitkSettings.apply()
	var r := RuitkRoot.new()
	r._reconciler = RuitkReconciler.new(container)
	r._reconciler.render(root_vnode)
	return r

## Create a root whose sliced renders run on a SCHEDULER OF ITS OWN, with its own frame budget.
##
## For a surface that shares a SceneTree with surfaces it must not be able to starve. In a game
## that is rarely worth the instance -- the tree belongs to the UI. In the EDITOR it is the whole
## point: one tree runs every addon that mounted anything, so a preview of a component with a
## runaway effect, rendering user code the builder has no say over, would otherwise spend the
## editor's render budget and stall the tool it is a panel of.
##
## Mirrors the reference's per-pane `BuilderRenderScheduler` (TickBudgetMs 4.0). `unmount()`
## detaches it -- an owned scheduler is disposed with the root that made it.
##
## `budget_ms` is the CUMULATIVE per-frame budget across this root's lanes; `quantum_ms` is how
## long one render slice runs before yielding. An isolated root always slices, whatever the
## project's `time_slicing` setting says: being bounded is what it was created for.
static func create_isolated(container: Node, root_vnode: RuitkVNode,
		budget_ms := 4.0, quantum_ms := 2.0) -> RuitkRoot:
	RuitkSettings.apply()
	var r := RuitkRoot.new()
	r._own_scheduler = RuitkScheduler.owned(budget_ms)
	r._reconciler = RuitkReconciler.new(container)
	r._reconciler.scheduler = r._own_scheduler
	r._reconciler.time_slice_ms = quantum_ms
	r._reconciler.force_time_slicing = true
	r._reconciler.render(root_vnode)
	return r

## This root's own scheduler, or null when it shares its tree's. For callers that want to read
## the lane metrics of one surface -- and for the tests that prove the isolation is real.
func scheduler() -> RuitkScheduler:
	return _own_scheduler

## Re-render with a new top-level vnode (e.g. when the host passes new props from
## outside the reactive tree). State updates from inside use hooks and don't need this.
func set_root(root_vnode: RuitkVNode) -> void:
	_reconciler.render(root_vnode)

## Tear down: run all effect cleanups and free mounted nodes (keeps the container).
func unmount() -> void:
	if _reconciler != null:
		_reconciler.unmount()
	# The pump connection outlives the fibers otherwise: a detached scheduler with an empty queue
	# still runs once per frame for the life of the tree, and an editor session opens the builder
	# many times.
	if _own_scheduler != null:
		_own_scheduler.detach()
