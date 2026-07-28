export const SUSPENSE_CALLBACK = `DataView() -> RuitkVNode {
  var data = useState(null)

  // Kick off the async load once. is_ready() below reports readiness.
  useEffect(func():
    _load_data_async(data[1])   # calls data[1].call(result) when done
    return Callable()
  , [])

  var fallback = V.Label({ "text": "Loading…" })
  var content = V.VBoxContainer({ "style": { "separation": 4 } },
    (data[0] if data[0] != null else []).map(func(item):
        return V.Label({ "key": item, "text": str(item) })))

  // Suspense has no markup tag — call V.suspense from an embedded { expr }.
  // is_ready is checked immediately, then polled each frame until true.
  // Pass a STABLE callback (useCallback) so the boundary doesn't re-subscribe
  // every render.
  var boundary = V.suspense(
    { "fallback": fallback, "is_ready": useCallback(func(): return data[0] != null, [data[0]]) },
    [ content ])

  return (
    <VBoxContainer>
      { boundary }
    </VBoxContainer>
  )
}`

export const SUSPENSE_SIGNAL = `AsyncView() -> RuitkVNode {
  var loader = useRef(null)

  // Build the loader once and expose a Godot Signal to await.
  var load = useMemo(func():
    var l := ResourceLoaderThreaded.new()   # your own loader emitting a "loaded" signal
    l.begin("res://big_scene.tscn")
    return l
  , [])

  return (
    <VBoxContainer>
      // ready_signal is a Godot Signal — awaited ONCE; readiness flips when it fires.
      // Suspense has no markup tag — call V.suspense from an embedded { expr }.
      { V.suspense({ "fallback": V.Label({ "text": "Loading…" }), "ready_signal": load.loaded },
                   [ V.Label({ "text": "Data loaded!" }) ]) }
    </VBoxContainer>
  )
}`
