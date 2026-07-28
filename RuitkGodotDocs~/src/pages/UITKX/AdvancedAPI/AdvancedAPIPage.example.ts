// Memoization + custom props equality (repurposed slot: PROPTYPES_EXAMPLE)
export const PROPTYPES_EXAMPLE = `# Every function component already bails its re-render when props are unchanged
# (shallow ==). For a custom comparison, pass __memo_eq in props — the reconciler
# consults it to decide whether to skip the child's re-render.

ExpensiveChild(data) -> RuitkVNode {
  # ... heavy render work over 'data' ...
  return (<Label text={ "rows: %d" % data.size() } />)
}

# Parent: only re-render ExpensiveChild when the row COUNT changes, ignoring
# unrelated field edits inside the array.
Parent() -> RuitkVNode {
  var rows = useState([])
  return (
    <VBoxContainer>
      { V.fc(ExpensiveChild.render, {
          "data": rows[0],
          "__memo_eq": func(old_props, new_props):
            return old_props["data"].size() == new_props["data"].size(),
        }) }
    </VBoxContainer>
  )
}

# useMemo memoizes derived values; useCallback memoizes a Callable's identity.
# var filtered = useMemo(func(): return heavy(items[0]), [items[0]])
# var on_pick  = useCallback(func(id): select(id), [])`

// Refs to Godot nodes (repurposed slot: HOSTCONTEXT_EXAMPLE)
export const HOSTCONTEXT_EXAMPLE = `# useRef(null) + the ref prop capture the underlying Godot Control after commit.
# ref["current"] is a real node — call any of its methods / read any property.

ScrollToBottom(lines) -> RuitkVNode {
  var scroll_ref = useRef(null)   # -> ScrollContainer node

  # After each new line, scroll to the bottom imperatively (layout effect = pre-paint).
  var stick = func():
    var sc = scroll_ref["current"]
    if sc != null:
      sc.scroll_vertical = int(sc.get_v_scroll_bar().max_value)
    return Callable()
  useLayoutEffect(stick, [lines.size()])

  return (
    <ScrollContainer ref={ scroll_ref } style={ {"custom_minimum_size": Vector2(320, 200)} }>
      <VBoxContainer>
        @for (line in lines) { <Label text={ line } key={ line } /> }
      </VBoxContainer>
    </ScrollContainer>
  )
}`

// Render scheduler (repurposed slot: SCHEDULER_EXAMPLE)
export const SCHEDULER_EXAMPLE = `# The reconciler batches state updates and commits once per frame via the
# SceneTree's process_frame signal (no manual scheduler API to call).
#
#   set() -> on_state_updated -> schedule_update_on_fiber -> process_frame -> _tick
#
# Multiple setters fired from one event handler coalesce into a SINGLE re-render:
var on_login = func():
  name[1].call("Alice")     # these three updates
  role[1].call("admin")     # are batched into one
  ready[1].call(true)       # commit next frame

# useDeferredValue opts a value into a LOW-priority follow-up frame, so an
# urgent update (typing) paints first and expensive work catches up a frame later:
#   var deferred = useDeferredValue(query[0])`

// useStableCallback (repurposed slot: FLUSHSYNC_EXAMPLE)
export const FLUSHSYNC_EXAMPLE = `SearchForm() -> RuitkVNode {
  var query = useState("")
  var results = useState([])

  # useStableCallback: a wrapper whose identity NEVER changes across renders,
  # but that always calls the latest closure body. Safe to hand to a child or a
  # Godot signal once, without re-subscribing every render.
  var on_search = useStableCallback(func():
    var r := search(query[0])
    results[1].call(r))

  return (
    <VBoxContainer>
      <LineEdit text={ query[0] } onTextChanged={ func(t): query[1].call(t) }
                onTextSubmitted={ func(_t): on_search.call() } />
      <Button text="Search" onPressed={ on_search } />
      @for (row in results[0]) { <Label text={ row } key={ row } /> }
    </VBoxContainer>
  )
}`

// Error boundary patterns (repurposed slot: ERROR_PATTERNS_EXAMPLE)
export const ERROR_PATTERNS_EXAMPLE = `# NOTE: GDScript has no try/catch, so the boundary can't AUTO-catch a render crash.
# It shows 'fallback' when activated imperatively (or by a child) and RESETS when
# 'reset_key' changes. Structural parity with React's ErrorBoundary.

# Pattern 1: fallback + on_error handler
SafeApp() -> RuitkVNode {
  return V.error_boundary({
    "fallback": V.Label({ "text": "Something went wrong" }),
    "on_error": func(err): push_error(err),
  }, [ V.fc(RiskyContent.render) ])
}

# Pattern 2: reset via a changing key
RecoverablePanel() -> RuitkVNode {
  var reset_key = useState("v1")
  return (
    <VBoxContainer>
      <Button text="Retry"
              onPressed={ func(): reset_key[1].call(str(Time.get_ticks_msec())) } />
      { V.error_boundary({
          "reset_key": reset_key[0],
          "fallback": V.Label({ "text": "Error — click Retry" }),
        }, [ V.fc(UnstableContent.render) ]) }
    </VBoxContainer>
  )
}`

// Render depth guard (repurposed slot: DEPTH_GUARD_EXAMPLE)
export const DEPTH_GUARD_EXAMPLE = `# The reconciler guards against runaway re-render loops. If a single render
# restarts more than 25 times in a row — usually because a setter is called
# UNCONDITIONALLY in the component's setup body (not in an effect/handler) —
# the guard stops the loop instead of freezing the editor/game.
#
# BAD — sets state on every render, looping forever:
#   Broken() -> RuitkVNode {
#     var n = useState(0)
#     n[1].call(n[0] + 1)          # <-- runs every render => infinite loop
#     return (<Label text={ str(n[0]) } />)
#   }
#
# FIX — move the update into an effect or an event handler:
#   var bump = func():
#     n[1].call(n[0] + 1)
#     return Callable()
#   useEffect(bump, [])           # runs once, after commit`

// Custom drawing: draw_fn + redraw_key (repurposed slot: SNAPSHOT_EXAMPLE)
export const SNAPSHOT_EXAMPLE = `# The Godot analogue of Unity's OnGenerateVisualContent + RedrawKey.
# 'draw_fn' is a Callable(canvas_item) that issues the node's draw_* calls; it runs
# during the node's 'draw' signal. Bump 'redraw_key' to repaint the SAME callback.

Gauge(value) -> RuitkVNode {
  # Read the latest 'value' inside the closure; redraw_key forces a repaint when it changes.
  var draw = func(ci: CanvasItem):
    var r := 40.0
    ci.draw_arc(Vector2(50, 50), r, 0, TAU * value, 48, Color.SKY_BLUE, 6.0)

  return V.ColorRect({
    "draw_fn": draw,
    "redraw_key": value,          # bump to queue_redraw without re-subscribing
    "style": { "custom_minimum_size": Vector2(100, 100), "bg_color": Color(0, 0, 0, 0) },
  })
}

# Pair a STABLE draw_fn (useStableCallback) with redraw_key so a fresh closure
# each render never re-subscribes the 'draw' signal — it only repaints.`

// Item-model adapters / custom host elements (repurposed slot: ELEMENT_REGISTRY_EXAMPLE)
export const ELEMENT_REGISTRY_EXAMPLE = `# RuitkHost is the only layer that knows concrete Godot node APIs. Item-model
# controls (ItemList, OptionButton, TabBar, Tree, MenuBar) are declarative: pass
# an 'items' prop and the adapter rebuilds the control's model when it changes.

Picker() -> RuitkVNode {
  var choice = useState(0)
  return (
    <OptionButton items={ ["Small", "Medium", "Large"] }
                  selected={ choice[0] }
                  onItemSelected={ func(idx): choice[1].call(idx) } />
  )
}

# Reach any Godot Control not covered by a named V.* factory with the generic host:
#   V.h("GraphEdit", { ... }, [ children ])
#
# Userland can register an adapter for a custom item-model control. match_fn
# selects nodes; apply_fn rebuilds them when props change:
#   RuitkHost.register_item_adapter(
#     func(node): return node is MyList,
#     func(node, old_props, new_props): rebuild(node, new_props["items"]))`

// RuitkVNode / V factory (repurposed slot: VIRTUALNODE_EXAMPLE)
export const VIRTUALNODE_EXAMPLE = `# RuitkVNode is the immutable virtual node produced by V.* and by the .guitkx
# codegen. In markup you never build it by hand — the compiler emits V.* calls.
# In pure GDScript you build trees directly with the V factory:

static func render(props: Dictionary, children: Array) -> RuitkVNode:
  return V.fc(DemoBox.render, { "title": "Hand-built tree" }, [
    V.Label({ "text": "Built with the V factory, no .guitkx" }),
    V.HBoxContainer({ "style": { "separation": 8 } }, [
      V.Button({ "text": "OK", "onPressed": func(): print("ok") }),
      V.Button({ "text": "Cancel" }),
    ]),
  ])

# Node kinds: host elements (V.Button/V.Label/V.h), function components (V.fc/V.memo),
# and structural nodes (V.fragment, V.portal, V.suspense, V.error_boundary).
# A .guitkx <Tag/> compiles to the matching V.* call; children flatten and raw
# Strings auto-wrap into Label text nodes.`
