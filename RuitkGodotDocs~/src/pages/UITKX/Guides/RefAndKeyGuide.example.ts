export const REF_BASIC_EXAMPLE = `MeasureDemo() -> RuitkVNode {
  var label_ref = useRef(null)   # box: { "current": <Control> }
  var width = useState(0.0)

  # After commit, label_ref["current"] is the mounted Label Control.
  var measure = func():
    if label_ref["current"] != null:
      width[1].call(label_ref["current"].size.x)
    return Callable()
  useLayoutEffect(measure, [])

  return (
    <VBoxContainer>
      <Label ref={ label_ref } text="Measure me" />
      <Label text={ "Width: %dpx" % width[0] } />
    </VBoxContainer>
  )
}`

export const REF_MUTABLE_EXAMPLE = `RenderCounter() -> RuitkVNode {
  # Mutating .current never triggers a re-render — the box persists across renders.
  var render_count = useRef(0)
  render_count["current"] += 1

  var tick = useState(0)

  return (
    <VBoxContainer>
      <Label text={ "Rendered %d time(s)" % render_count["current"] } />
      <Button text="Force re-render"
              onPressed={ func(): tick[1].call(func(n): return n + 1) } />
    </VBoxContainer>
  )
}`

export const REF_FOCUS_EXAMPLE = `AutoFocusInput() -> RuitkVNode {
  var input_ref = useRef(null)

  var focus_on_mount = func():
    if input_ref["current"] != null:
      input_ref["current"].grab_focus()
    return Callable()
  useEffect(focus_on_mount, [])   # [] => run once on mount

  return (
    <LineEdit ref={ input_ref } placeholder_text="Auto-focused on mount" />
  )
}`

export const REF_IMPERATIVE_EXAMPLE = `# A child builds an imperative handle over its own node/state.
FancyInput() -> RuitkVNode {
  var input_ref = useRef(null)
  var val = useState("")

  # useImperativeHandle memoizes the handle Dictionary until deps change.
  var handle = useImperativeHandle(func(): return {
    "focus": func():
      if input_ref["current"] != null: input_ref["current"].grab_focus(),
    "clear": func(): val[1].call(""),
    "value": val[0],
  }, [val[0]])

  return (
    <LineEdit ref={ input_ref } text={ val[0] }
              onTextChanged={ func(t): val[1].call(t) } />
  )
}

# A parent gets the handle by passing its own ref box down as a prop.
FormHost() -> RuitkVNode {
  var child = useRef(null)   # will hold FancyInput's handle
  return (
    <VBoxContainer>
      <FancyInput handle_ref={ child } />
      <Button text="Focus child"
              onPressed={ func():
                if child["current"] != null: child["current"]["focus"].call() } />
    </VBoxContainer>
  )
}`

export const KEY_BASIC_EXAMPLE = `TodoList() -> RuitkVNode {
  var items = useState(["Buy milk", "Walk dog"])

  return (
    <VBoxContainer>
      @for (item in items[0]) {
        # key preserves element identity across re-renders
        <Label text={ item } key={ item } />
      }
    </VBoxContainer>
  )
}`

export const KEY_INDEX_ANTIPATTERN = `# BAD — using the loop index as key breaks when list order changes
@for (i in range(items.size())) {
  <Label text={ items[i] } key={ str(i) } />
}

# GOOD — use a stable, unique identifier
@for (todo in todos) {
  <TodoItem todo={ todo } key={ str(todo.id) } />
}`

export const KEY_REORDER_EXAMPLE = `ReorderDemo() -> RuitkVNode {
  var items = useState(["A", "B", "C", "D", "E"])

  var shuffle = func():
    var arr: Array = items[0].duplicate()
    arr.shuffle()
    items[1].call(arr)

  return (
    <VBoxContainer>
      <Button text="Shuffle" onPressed={ shuffle } />
      <HBoxContainer style={ {"separation": 6} }>
        @for (id in items[0]) {
          # Stable key => the reconciler MOVES the node (and its per-node
          # state, like a random color from useRef) instead of recreating it.
          <KeyedTile key={ id } id={ id } />
        }
      </HBoxContainer>
    </VBoxContainer>
  )
}`

export const KEY_RESET_EXAMPLE = `UserProfile(user_id) -> RuitkVNode {
  # Changing key forces a full unmount + remount of the child.
  return (
    <ProfileContent key={ user_id } user_id={ user_id } />
  )
}

ProfileContent(user_id) -> RuitkVNode {
  # All hooks reset when key changes — fresh state for each user.
  var data = useState(null)

  var load = func():
    load_user_async(user_id, data[1])   # calls data[1].call(user_data) when done
    return Callable()
  useEffect(load, [user_id])

  return (
    <VBoxContainer>
      @if (data[0] != null) {
        <Label text={ "Name: %s" % data[0].name } />
      } @else {
        <Label text="Loading..." />
      }
    </VBoxContainer>
  )
}`
