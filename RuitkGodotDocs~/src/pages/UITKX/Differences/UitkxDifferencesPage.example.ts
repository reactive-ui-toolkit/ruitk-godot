export const UITKX_STATE_COUNTER_EXAMPLE = `StateCounterExample() -> RuitkVNode {
  var s = useState(0)
  var count = s[0]
  var set_count = s[1]
  return (
    <VBoxContainer>
      <Label text={ "Count: %d" % count } />
      <Button text="Increment" onPressed={ func(): set_count.call(func(prev): return prev + 1) } />
      <Button text="Reset" onPressed={ func(): set_count.call(0) } />
    </VBoxContainer>
  )
}`
