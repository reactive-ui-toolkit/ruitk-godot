export const UITKX_INSTALL_URL = 'res://addons/reactive_ui_toolkit/'

export const UITKX_HELLO_WORLD_COMPONENT = `HelloWorld() -> RUIVNode {
  var s = useState(0)
  return (
    <VBoxContainer style={ {"separation": 8} }>
      <Label text="Hello, reactive Godot! 👋" />
      <Label text={ "Count: %d" % s[0] } />
      <Button text="Increment" onPressed={ func(): s[1].call(s[0] + 1) } />
    </VBoxContainer>
  )
}`

export const UITKX_HELLO_WORLD_BOOTSTRAP = `extends Control

# Keep the root referenced for the UI's lifetime — it owns the reconciler.
var _app: ReactiveRoot

func _ready() -> void:
    # HelloWorld.render is the source-generated render fn from HelloWorld.guitkx.
    # V.fc wraps it as a function-component vnode (the reconciler's entry point),
    # and ReactiveRoot.create mounts it under this Control.
    _app = ReactiveRoot.create(self, V.fc(HelloWorld.render))

func _exit_tree() -> void:
    # Tear down and run cleanups when this node leaves the tree.
    if _app:
        _app.unmount()`

export const UITKX_EDITOR_BOOTSTRAP = `extends Control

# ReactiveRootNode is a Control-based mount surface. Give it the render fn as a
# Callable via setup(), add it to the tree, and it mounts on _ready and unmounts
# on _exit_tree automatically — no reference to hold yourself.
func _ready() -> void:
    var host := ReactiveRootNode.new().setup(HelloWorld.render)
    add_child(host)`
