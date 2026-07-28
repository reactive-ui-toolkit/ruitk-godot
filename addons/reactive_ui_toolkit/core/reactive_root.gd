class_name ReactiveRoot
extends RefCounted
## Mounts a reactive UI tree under a target Control/Node and owns the reconciler.
## Mirrors ReactiveUIToolKit's `RootRenderer`.
##
## IMPORTANT: keep the returned ReactiveRoot referenced for as long as the UI should
## live (store it in a script variable). It owns the reconciler; if it is collected,
## scheduled re-renders stop. Call `unmount()` to tear the UI down and run cleanups.
##
## Example:
##   var _app: ReactiveRoot
##   func _ready() -> void:
##       _app = ReactiveRoot.create(self, V.fc(_my_app))

var _reconciler: RUIReconciler

## Create a root, mount `root_vnode` (usually `V.fc(...)`) under `container`, and do
## the initial render.
static func create(container: Node, root_vnode: RUIVNode) -> ReactiveRoot:
	var r := ReactiveRoot.new()
	r._reconciler = RUIReconciler.new(container)
	r._reconciler.render(root_vnode)
	return r

## Re-render with a new top-level vnode (e.g. when the host passes new props from
## outside the reactive tree). State updates from inside use hooks and don't need this.
func set_root(root_vnode: RUIVNode) -> void:
	_reconciler.render(root_vnode)

## Tear down: run all effect cleanups and free mounted nodes (keeps the container).
func unmount() -> void:
	if _reconciler != null:
		_reconciler.unmount()
