class_name ReactiveRootNode
extends Control
## A scene-lifecycle-managed reactive root. Add it to a scene (or instance it), give it a
## root component, and it mounts on `_ready` and unmounts on `_exit_tree` automatically —
## no need to hold a reference yourself (unlike the bare `ReactiveRoot`).
##
## Usage (code):
##   var r := ReactiveRootNode.new().setup(MyApp.render, { "title": "Hi" })
##   add_child(r)
##
## Usage (scene): attach a script `extends ReactiveRootNode` and override `build()`.

var root_component: Callable
var root_props: Dictionary = {}
var _app: ReactiveRoot = null

## Set the root component + props before entering the tree. Returns self for chaining.
func setup(component: Callable, props := {}) -> ReactiveRootNode:
	root_component = component
	root_props = props
	return self

## Override in a subclass to return the root vnode (alternative to `setup`).
func build() -> RUIVNode:
	if root_component.is_valid():
		return V.fc(root_component, root_props)
	return null

func _ready() -> void:
	var vnode := build()
	if vnode != null:
		_app = ReactiveRoot.create(self, vnode)

func _exit_tree() -> void:
	if _app != null:
		_app.unmount()
		_app = null

## Re-render with a new top-level component/props.
func rerender(component: Callable, props := {}) -> void:
	root_component = component
	root_props = props
	if _app != null and component.is_valid():
		_app.set_root(V.fc(component, props))
