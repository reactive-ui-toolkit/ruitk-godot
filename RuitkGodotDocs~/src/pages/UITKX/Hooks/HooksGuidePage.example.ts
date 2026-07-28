export const HOOKS_USESTATE_EXAMPLE = `CounterDemo() -> RuitkVNode {
  # useState returns [value, setter]. Destructure by index.
  var count = useState(0)

  # Direct value:            count[1].call(5)
  # Functional updater:      count[1].call(func(c): return c + 1)   # reads latest state

  return (
    <VBoxContainer>
      <Label text={ "Count: %d" % count[0] } />
      <Button text="Increment" onPressed={ func(): count[1].call(count[0] + 1) } />
      <Button text="Double" onPressed={ func(): count[1].call(func(c): return c * 2) } />
    </VBoxContainer>
  )
}`

export const HOOKS_USEREDUCER_EXAMPLE = `ReducerDemo() -> RuitkVNode {
  # reducer(state, action) -> new_state. Actions are just values (here: String).
  var reducer = func(state, action):
    match action:
      "inc": return state + 1
      "dec": return state - 1
      "reset": return 0
    return state

  # useReducer returns [state, dispatch].
  var r = useReducer(reducer, 0)

  return (
    <VBoxContainer>
      <Label text={ "Count: %d" % r[0] } />
      <Button text="+" onPressed={ func(): r[1].call("inc") } />
      <Button text="-" onPressed={ func(): r[1].call("dec") } />
      <Button text="Reset" onPressed={ func(): r[1].call("reset") } />
    </VBoxContainer>
  )
}`

export const HOOKS_USEEFFECT_EXAMPLE = `EffectDemo() -> RuitkVNode {
  var seconds = useState(0)

  # [] => run once on mount. The effect returns a cleanup Callable (run on unmount).
  var tick = func():
    var timer := Engine.get_main_loop().create_timer(1.0)
    var running := [true]
    var loop := func():
      while running[0]:
        await Engine.get_main_loop().create_timer(1.0).timeout
        if running[0]:
          seconds[1].call(func(s): return s + 1)
    loop.call()
    return func(): running[0] = false   # cleanup

  useEffect(tick, [])

  return (<Label text={ "Elapsed: %ds" % seconds[0] } />)
}`

export const HOOKS_USELAYOUTEFFECT_EXAMPLE = `LayoutMeasure() -> RuitkVNode {
  var el_ref = useRef(null)     # Control ref box
  var width = useState(0.0)

  # Runs synchronously during commit, before the frame paints.
  var measure = func():
    if el_ref["current"] != null:
      width[1].call(el_ref["current"].size.x)
    return Callable()
  useLayoutEffect(measure, [])

  return (
    <VBoxContainer ref={ el_ref }>
      <Label text={ "Width: %dpx" % width[0] } />
    </VBoxContainer>
  )
}`

export const HOOKS_USEMEMO_EXAMPLE = `ExpensiveList() -> RuitkVNode {
  var filter = useState("")
  var items = useState(get_all_items())   # an Array

  # Recomputes only when filter or items change (shallow dep compare).
  var filtered = useMemo(func():
    return items[0].filter(func(i): return filter[0] in i),
    [filter[0], items[0]])

  return (
    <VBoxContainer>
      <LineEdit text={ filter[0] } onTextChanged={ func(t): filter[1].call(t) } />
      @for (item in filtered) {
        <Label text={ item } key={ item } />
      }
    </VBoxContainer>
  )
}`

export const HOOKS_USECALLBACK_EXAMPLE = `StableCallback() -> RuitkVNode {
  var count = useState(0)

  # Returns a Callable whose identity is stable while deps are unchanged.
  var get_count = useCallback(func(): return count[0], [count[0]])

  return (
    <VBoxContainer>
      <Label text={ "Count: %d" % get_count.call() } />
      <Button text="Increment" onPressed={ func(): count[1].call(count[0] + 1) } />
    </VBoxContainer>
  )
}`

export const HOOKS_USEREF_EXAMPLE = `RefDemo() -> RuitkVNode {
  # Mutable value ref — persists across renders, no re-render on change.
  var render_count = useRef(0)
  render_count["current"] += 1

  # Control ref — gives access to the underlying Godot node after commit.
  var label_ref = useRef(null)

  var log_name = func():
    if label_ref["current"] != null:
      print("Label node: ", label_ref["current"].name)
    return Callable()
  useEffect(log_name, [])

  return (
    <VBoxContainer>
      <Label ref={ label_ref }
             text={ "This component rendered %d time(s)" % render_count["current"] } />
    </VBoxContainer>
  )
}`

export const HOOKS_CONTEXT_EXAMPLE = `# ============ theme_provider.guitkx ============
# Two files -- the provider imports the card it renders (cross-file refs are explicit since 0.10).
import { ThemedCard } from "./themed_card"

export ThemeProvider() -> RuitkVNode {
  Hooks.provideContext("theme", "dark")

  return (
    <VBoxContainer>
      <ThemedCard />
    </VBoxContainer>
  )
}

# ============ themed_card.guitkx ============
# Consumer component — any depth in the subtree; \`export\` makes it importable
export ThemedCard() -> RuitkVNode {
  var theme = useContext("theme")   # "dark"

  return (
    <PanelContainer style={ {
      "bg_color": Color.BLACK if theme == "dark" else Color.WHITE,
      "content_margin_all": 12,
    } }>
      <Label text={ "Theme: %s" % theme } />
    </PanelContainer>
  )
}`

export const HOOKS_STABLE_EXAMPLE = `EventOptimization() -> RuitkVNode {
  var name = useState("")

  # useStableAction wraps a 1-arg callback with a stable identity that always
  # calls through to the latest closure body.
  var on_name_changed = useStableAction(func(v): name[1].call(v))

  # useStableCallback for 0-arg callbacks.
  var on_reset = useStableCallback(func(): name[1].call(""))

  return (
    <VBoxContainer>
      <LineEdit text={ name[0] } onTextChanged={ on_name_changed } />
      <Button text="Reset" onPressed={ on_reset } />
    </VBoxContainer>
  )
}`

export const HOOKS_DEFERRED_EXAMPLE = `SearchResults() -> RuitkVNode {
  var query = useState("")

  # Deferred value lags one frame behind: the LineEdit updates immediately while
  # the expensive ResultsList catches up at low priority next frame.
  var deferred_query = useDeferredValue(query[0])

  return (
    <VBoxContainer>
      <LineEdit text={ query[0] } onTextChanged={ func(t): query[1].call(t) } />
      <ResultsList filter={ deferred_query } />
    </VBoxContainer>
  )
}`

export const HOOKS_IMPERATIVE_EXAMPLE = `FancyInput(handle_ref) -> RuitkVNode {
  var input_ref = useRef(null)
  var val = useState("")

  # Build a handle Dictionary of imperative methods, memoized until deps change.
  var handle = useImperativeHandle(func(): return {
    "focus": func():
      if input_ref["current"] != null: input_ref["current"].grab_focus(),
    "clear": func(): val[1].call(""),
  }, [])

  # Publish the handle to the parent's ref box.
  var publish = func():
    if handle_ref != null:
      handle_ref["current"] = handle
    return Callable()
  useLayoutEffect(publish, [handle])

  return (<LineEdit ref={ input_ref } text={ val[0] }
                    onTextChanged={ func(t): val[1].call(t) } />)
}`

export const HOOKS_DEPENDENCY_RULES = `# deps == null  ->  runs cleanup + effect EVERY commit
useEffect(func(): ... return cleanup)

# empty array [] -> runs once on mount, cleanup on unmount
useEffect(func(): ... return cleanup, [])

# with deps    ->  runs when any dep changes (shallow, == value comparison)
useEffect(func(): ... return cleanup, [dep1, dep2])

# The effect body may return a Callable cleanup (or Callable() for none).
# Dependency comparison is shallow value-equality (==) per element.`
