export const EVENTS_CLICK_EXAMPLE = `ClickDemo() -> RuitkVNode {
  var msg = useState("Click the button")

  return (
    <VBoxContainer style={ {"separation": 8} }>
      <Label text={ msg[0] } />
      <Button text="Click me"
              onPressed={ func(): msg[1].call("Clicked!") } />
    </VBoxContainer>
  )
}`

export const EVENTS_POINTER_EXAMPLE = `PointerTracker() -> RuitkVNode {
  var inside = useState(false)

  return (
    // onMouseEntered -> mouse_entered, onMouseExited -> mouse_exited.
    // (Godot fires these with no arguments, so the handler takes none.)
    <PanelContainer style={ {"custom_minimum_size": Vector2(240, 120), "content_margin_all": 12} }
           onMouseEntered={ func(): inside[1].call(true) }
           onMouseExited={ func(): inside[1].call(false) }>
      <Label text={ "Pointer inside: %s" % inside[0] } />
    </PanelContainer>
  )
}`

export const EVENTS_KEYBOARD_EXAMPLE = `KeyboardDemo() -> RuitkVNode {
  var last = useState("None")

  // Godot has no per-Control key signals; use the native gui_input escape
  // hatch (on_gui_input -> "gui_input") and inspect the InputEvent yourself.
  var on_key = func(event: InputEvent):
    if event is InputEventKey and event.pressed:
      last[1].call(OS.get_keycode_string(event.keycode))

  return (
    <VBoxContainer style={ {"separation": 8} }>
      <LineEdit placeholder_text="Type here" on_gui_input={ on_key } />
      <Label text={ "Last key: %s" % last[0] } />
    </VBoxContainer>
  )
}`

export const EVENTS_FOCUS_EXAMPLE = `FocusDemo() -> RuitkVNode {
  var focused = useState(false)

  // onFocusEntered -> focus_entered, onFocusExited -> focus_exited.
  return (
    <LineEdit placeholder_text="Name"
              onFocusEntered={ func(): focused[1].call(true) }
              onFocusExited={ func(): focused[1].call(false) }
              style={ {"border_color": Color.CYAN if focused[0] else Color.GRAY} } />
  )
}`

export const EVENTS_GEOMETRY_EXAMPLE = `ResizeWatcher() -> RuitkVNode {
  var size = useState(Vector2.ZERO)
  var box = useRef(null)

  // onResized -> resized. The signal carries no argument, so read the size
  // off the node via a ref.
  var on_resized = func():
    if box["current"] != null:
      size[1].call(box["current"].size)

  return (
    <PanelContainer ref={ box } style={ {"size_flags_horizontal": Control.SIZE_EXPAND_FILL, "custom_minimum_size": Vector2(0, 120)} }
           onResized={ on_resized }>
      <Label text={ "Size: %d x %d" % [size[0].x, size[0].y] } />
    </PanelContainer>
  )
}`

export const EVENTS_CHANGE_EXAMPLE = `// One rule, every control: on + PascalCase(signal name). Each Godot control
// has its own value/selection signal, and the prop names it directly — the
// handler receives exactly the arguments that signal emits.

// CheckButton — "toggled" passes the new bool.
<CheckButton text="Enable" button_pressed={ enabled }
             onToggled={ func(on): set_enabled.call(on) } />

// HSlider — "value_changed" passes the new float.
<HSlider min_value={ 0 } max_value={ 100 } value={ volume }
         onValueChanged={ func(v): set_volume.call(v) } />

// OptionButton — "item_selected" passes the index.
<OptionButton items={ ["Low", "Medium", "High"] } selected={ quality }
              onItemSelected={ func(idx): set_quality.call(idx) } />

// LineEdit — "text_changed" passes the new String.
<LineEdit text={ name } onTextChanged={ func(s): set_name.call(s) } />`

export const EVENTS_SUBMIT_EXAMPLE = `SearchBox() -> RuitkVNode {
  var query = useState("")
  var submitted = useState("")

  return (
    <VBoxContainer style={ {"separation": 8} }>
      // onTextSubmitted -> text_submitted, fired on Enter. It passes the final text.
      <LineEdit text={ query[0] }
                onTextChanged={ func(s): query[1].call(s) }
                onTextSubmitted={ func(s): submitted[1].call(s) } />
      <Label text={ "Searched for: %s" % submitted[0] } />
    </VBoxContainer>
  )
}`

export const EVENTS_NATIVE_EXAMPLE = `NativeEscapeHatch() -> RuitkVNode {
  // The on_<signal> escape hatch binds VERBATIM to any Godot signal on the
  // node — the exact snake_case name, no case transform. It is equivalent to
  // the on + PascalCase spelling; use whichever reads better.
  var menu_items = [
    { "text": "New",  "id": 1 },
    { "text": "Open", "id": 2 },
    { "text": "Quit", "id": 3 },
  ]

  return (
    <VBoxContainer style={ {"separation": 8} }>
      // PopupMenu emits "id_pressed" — bind it natively (or as onIdPressed).
      <PopupMenu items={ menu_items }
                 on_id_pressed={ func(id): print("menu id ", id) } />

      // A Tree emits "item_activated" (double-click / Enter).
      <Tree on_item_activated={ func(): print("row activated") } />

      // Any signal at all: reach the raw InputEvent stream with on_gui_input.
      <ColorRect color={ Color.DARK_SLATE_BLUE }
                 on_gui_input={ func(e): print("gui input: ", e) } />
    </VBoxContainer>
  )
}`
