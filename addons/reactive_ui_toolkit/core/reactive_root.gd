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

## Re-render with a new top-level vnode (e.g. when the host passes new props from
## outside the reactive tree). State updates from inside use hooks and don't need this.
func set_root(root_vnode: RuitkVNode) -> void:
	_reconciler.render(root_vnode)

## Tear down: run all effect cleanups and free mounted nodes (keeps the container).
func unmount() -> void:
	if _reconciler != null:
		_reconciler.unmount()
