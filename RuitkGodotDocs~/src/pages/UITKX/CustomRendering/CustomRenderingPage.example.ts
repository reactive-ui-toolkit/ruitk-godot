/* ------------------------------------------------------------------ */
/*  Custom Rendering page — draw_fn + redraw_key, real GDScript        */
/* ------------------------------------------------------------------ */

// A helper file holding the draw bodies as plain top-level utils. Keeping them
// out of the markup lets the .guitkx use simple single-expression lambdas. Each
// draw body is a func(canvas: CanvasItem) that issues Godot's draw_* calls.
export const CUSTOM_RENDERING_HELPERS_EXAMPLE = `# draw_helpers.guitkx — a file IS a module; @class_name names its binding.
@class_name DrawHelpers

# Vector drawing: an N-sided polygon outline, centered in the node's rect.
export polygon(canvas: CanvasItem, sides: int) -> void {
  var r: Vector2 = canvas.size
  var cx := r.x * 0.5
  var cy := r.y * 0.5
  var radius := min(cx, cy) - 8.0
  var n := max(3, sides)
  var pts := PackedVector2Array()
  for i in n + 1:
    var a := float(i) / n * TAU - PI * 0.5
    pts.append(Vector2(cx + cos(a) * radius, cy + sin(a) * radius))
  canvas.draw_polyline(pts, Color.CYAN, 3.0)
}

# A solid tinted quad inset 8px from the edges.
export quad(canvas: CanvasItem, tint: Color) -> void {
  var r: Vector2 = canvas.size
  canvas.draw_rect(Rect2(8, 8, r.x - 16, r.y - 16), tint, true)
}

# A stable target that scribbles a fresh random polyline every repaint, so a
# redraw_key bump visibly redraws even though the callback is unchanged.
export scatter(canvas: CanvasItem) -> void {
  var r: Vector2 = canvas.size
  var pts := PackedVector2Array()
  for i in 17:
    pts.append(Vector2(randf() * r.x, randf() * r.y))
  canvas.draw_polyline(pts, Color(0.3, 0.9, 1.0), 2.0)
}`

// Vector drawing driven by component state. A fresh inline lambda each render
// is a new callable, so the node repaints whenever its owner re-renders.
export const CUSTOM_RENDERING_PAINTER_EXAMPLE = `import * as DrawHelpers from "./draw_helpers"

PolygonCanvas() -> RuitkVNode {
  var sides = useState(3)

  return (
    <VBoxContainer style={ {"separation": 8} }>
      // draw_fn runs during the node's "draw" signal. Panel is a CanvasItem.
      <PanelContainer style={ {"custom_minimum_size": Vector2(0, 130), "bg_color": Color(0.12, 0.12, 0.14)} }
             draw_fn={ func(canvas): DrawHelpers.polygon(canvas, sides[0]) } />
      <Button text="Add side" onPressed={ func(): sides[1].call(sides[0] + 1) } />
    </VBoxContainer>
  )
}`

// Drawing that depends on state, toggled by a button.
export const CUSTOM_RENDERING_RAW_MESH_EXAMPLE = `import * as DrawHelpers from "./draw_helpers"

QuadCanvas() -> RuitkVNode {
  var blue = useState(true)

  return (
    <VBoxContainer style={ {"separation": 8} }>
      <PanelContainer style={ {"custom_minimum_size": Vector2(0, 130)} }
             draw_fn={ func(canvas): DrawHelpers.quad(canvas, Color.BLUE if blue[0] else Color(1.0, 0.5, 0.2)) } />
      <Button text="Toggle color" onPressed={ func(): blue[1].call(not blue[0]) } />
    </VBoxContainer>
  )
}`

// Stable callback + redraw_key: repaint on demand WITHOUT changing the callback.
export const CUSTOM_RENDERING_REDRAW_KEY_EXAMPLE = `import * as DrawHelpers from "./draw_helpers"

ScatterCanvas() -> RuitkVNode {
  var tick = useState(0)

  // A stable callable: its identity never changes between renders, so the node
  // does NOT repaint every render. Bumping redraw_key forces the repaint.
  var draw = useStableAction(func(canvas): DrawHelpers.scatter(canvas))

  return (
    <VBoxContainer style={ {"separation": 8} }>
      <PanelContainer style={ {"custom_minimum_size": Vector2(0, 130)} }
             draw_fn={ draw }
             redraw_key={ tick[0] } />
      <Button text="Shuffle" onPressed={ func(): tick[1].call(tick[0] + 1) } />
    </VBoxContainer>
  )
}`

// How the props map onto the host config.
export const CUSTOM_RENDERING_SIGNATURE_EXAMPLE = `# draw_fn is a Callable(canvas_item). The host registers a single trampoline on
# the node's "draw" signal that always reads the LATEST draw_fn from node meta,
# so a fresh closure each render never re-subscribes — it just repaints.
draw_fn={ func(canvas): pass }   # issue canvas.draw_* calls here

# redraw_key is any value. Changing it queues a redraw WITHOUT changing the
# callback reference — pair it with a stable callback (useStableCallback /
# useStableAction):
redraw_key={ some_int_state }

# draw_fn is ignored (with a push_warning) on nodes that are not CanvasItems.`
