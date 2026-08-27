@tool
class_name RuitkBuilderCanvasEdges
extends Control
## The import edges, drawn as one SCREEN-SPACE overlay above the cards.
##
## Screen space, not world space, and that is the whole point: a stroke width, a terminal dot and
## a dash period that live in world space shrink with the zoom, so at the pill LOD the graph's
## connective tissue thins to nothing exactly when the user is looking at the whole tree and needs
## it most. Painted here, they are the same number of pixels at every zoom.
##
## ONE overlay for every edge, rather than a node per edge. A tree of any size has more edges than
## cards, and each is a curve with a dot on each end -- as nodes that is hundreds of Controls
## re-laid-out on every pan. As one `_draw` it is one pass.
##
## The curve is `RuitkBuilderCanvasMetrics.edge_point`, so a hit-test and the painter cannot
## disagree about where the line actually is.

const Metrics = preload("res://addons/reactive_ui_toolkit_editor/builder/canvas/builder_canvas_metrics.gd")
const Graph = preload("res://addons/reactive_ui_toolkit_editor/builder/canvas/builder_graph.gd")
const Module = preload("res://addons/reactive_ui_toolkit_editor/builder/document/builder_module.gd")

## How many segments a curve is sampled into. Enough that the longest edge on a large canvas
## reads as a curve rather than a chain, cheap enough that a few hundred of them cost nothing.
const CURVE_STEPS := 24

const EDGE_WIDTH := 2.0
const ANCHOR_RADIUS := 3.5
const BROKEN_DASH_ON := 6.0
const BROKEN_DASH_OFF := 4.0

const Palette = preload("res://addons/reactive_ui_toolkit_editor/builder/canvas/canvas_palette.gd")

## How long a dash and a gap are on a STYLE edge, in screen pixels.
const STYLE_DASH_ON := 7.0
const STYLE_DASH_OFF := 5.0

## The canvas grid: world-space cell size, the screen spacing below which it stops being drawn,
## and the dot itself.
const GRID_SPACING := 64.0
const GRID_MIN_SCREEN_SPACING := 14.0
const GRID_DOT := 2.0
const GRID_COLOR := Color(0.34, 0.34, 0.40, 0.55)

const EDGE_COLOR := Color(0.482, 0.545, 0.647, 0.85)
const EDGE_COLOR_SELECTED := Color(0.361, 0.588, 0.965, 1.0)
const BROKEN_COLOR := Color(0.902, 0.451, 0.451, 0.9)
const ANCHOR_COLOR := Color(0.635, 0.729, 0.910, 1.0)
const ANCHOR_UNSATISFIED_COLOR := Color(0.902, 0.451, 0.451, 1.0)

var graph: Graph = null
var camera := Vector2.ZERO
var zoom := 1.0

## The card whose edges are highlighted, or -1.
var selected := -1


func _init() -> void:
	# The overlay is decoration over an interactive surface: every click has to reach the cards
	# beneath it, so it never takes one.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


## Re-points the overlay at a new graph or camera. One entry so a caller cannot update the camera
## and forget to redraw -- which shows up as edges that lag the cards by a frame during a pan.
func refresh(new_graph: Graph, new_camera: Vector2, new_zoom: float, new_selected: int) -> void:
	graph = new_graph
	camera = new_camera
	zoom = new_zoom
	selected = new_selected
	queue_redraw()


## The canvas's dot grid, in world space, drawn under everything.
##
## A flat empty field gives a pan no reference and a zoom no scale: the cards move and nothing
## says how far or how much. The grid is the cheapest possible answer -- one dot per world cell,
## culled to the viewport, fading out as the cells collapse past the point of being readable.
func _draw_grid() -> void:
	var spacing := GRID_SPACING * zoom
	if spacing < GRID_MIN_SCREEN_SPACING:
		return
	var alpha: float = clampf((spacing - GRID_MIN_SCREEN_SPACING) / GRID_MIN_SCREEN_SPACING, 0.0, 1.0)
	var tint := Color(GRID_COLOR, GRID_COLOR.a * alpha)
	# Start at the first grid line left of and above the viewport, so panning does not make the
	# pattern crawl.
	var first := Vector2(fposmod(camera.x, spacing), fposmod(camera.y, spacing))
	var y := first.y
	while y < size.y:
		var x := first.x
		while x < size.x:
			draw_rect(Rect2(Vector2(x, y), Vector2(GRID_DOT, GRID_DOT)), tint)
			x += spacing
		y += spacing


func _draw() -> void:
	_draw_grid()
	if graph == null or graph.cards.is_empty():
		return
	var lod := Metrics.lod_of(zoom)
	var card_width := Metrics.card_width_for(lod)

	# The anchor column first, so a curve lands ON its dot rather than under it.
	for i in range(graph.cards.size()):
		_draw_anchors(graph.cards[i], i, card_width)

	var seen_per_card := {}
	for edge in graph.edges:
		if edge.from_index < 0 or edge.from_index >= graph.cards.size():
			continue
		var ordinal := int(seen_per_card.get(edge.from_index, 0))
		seen_per_card[edge.from_index] = ordinal + 1
		_draw_edge(edge, ordinal, card_width)


func _draw_anchors(card: Graph.Card, index: int, card_width: float) -> void:
	if not Metrics.is_near_viewport(card, card_width, camera, zoom, size):
		return
	# One dot per import row, down the card's left column -- so a card with four imports shows
	# four distinct arrival points rather than four lines converging on one.
	var incoming := graph.edges_to(index).size()
	var rows: int = maxi(1, incoming)
	for k in range(rows):
		var world := Metrics.edge_target_anchor(card) + Vector2(0.0, k * Metrics.ANCHOR_PITCH)
		var at := Metrics.world_to_screen(world, camera, zoom)
		draw_circle(at, ANCHOR_RADIUS, ANCHOR_COLOR)


func _draw_edge(edge: Graph.Edge, ordinal: int, card_width: float) -> void:
	var from_card := graph.cards[edge.from_index]
	var from_world := Metrics.edge_source_anchor(from_card, ordinal, card_width)
	var from := Metrics.world_to_screen(from_world, camera, zoom)

	if edge.is_broken():
		# A broken import still gets a line: an anchor dot with no line says nothing about WHY,
		# and a specifier that resolves to nothing is a real authoring problem worth showing.
		var stub := from + Vector2(60.0, 0.0)
		_draw_dashed(from, stub, BROKEN_COLOR)
		draw_circle(stub, ANCHOR_RADIUS, ANCHOR_UNSATISFIED_COLOR)
		return

	var to_card := graph.cards[edge.to_index]
	var to := Metrics.world_to_screen(Metrics.edge_target_anchor(to_card), camera, zoom)
	var highlighted := selected == edge.from_index or selected == edge.to_index
	# A STYLE usage is a different relationship from a component usage — one puts an element in
	# the tree, the other puts a look on one — so it is drawn as a different line, not the same
	# line to a differently-tinted card. Selection still wins: a highlighted edge is a highlighted
	# edge whatever it connects.
	var to_style := int(to_card.kind) == int(Module.Kind.STYLE)
	var color := EDGE_COLOR_SELECTED if highlighted else (Palette.edge_style() if to_style else EDGE_COLOR)

	var points := PackedVector2Array()
	for step in range(CURVE_STEPS + 1):
		# Sampled in SCREEN space, from screen endpoints, so the curve's bow is a constant number
		# of pixels rather than a world distance that collapses as the user zooms out.
		points.append(Metrics.edge_point(from, to, 1.0, float(step) / CURVE_STEPS))
	if to_style:
		_draw_dashed_path(points, color)
	else:
		draw_polyline(points, color, EDGE_WIDTH, true)
	draw_circle(to, ANCHOR_RADIUS, color)


func _draw_dashed(from: Vector2, to: Vector2, color: Color) -> void:
	var span := to - from
	var length := span.length()
	if length <= 0.0:
		return
	var step := span / length
	var at := 0.0
	while at < length:
		var end: float = minf(at + BROKEN_DASH_ON, length)
		draw_line(from + step * at, from + step * end, color, EDGE_WIDTH, true)
		at = end + BROKEN_DASH_OFF


## A dashed run along an arbitrary polyline. `_draw_dashed` walks a straight segment; a style edge is
## a curve, and dashing it segment-by-segment would restart the pattern at every sample and read as
## a solid line with dents in it. This carries the phase across the whole path.
func _draw_dashed_path(points: PackedVector2Array, color: Color) -> void:
	var carried := 0.0
	var drawing := true
	for i in range(points.size() - 1):
		var from := points[i]
		var to := points[i + 1]
		var span := to - from
		var length := span.length()
		if length <= 0.0:
			continue
		var step := span / length
		var at := 0.0
		while at < length:
			var budget := (STYLE_DASH_ON if drawing else STYLE_DASH_OFF) - carried
			var end: float = minf(at + budget, length)
			if drawing:
				draw_line(from + step * at, from + step * end, color, EDGE_WIDTH, true)
			if end - at >= budget:
				drawing = not drawing
				carried = 0.0
			else:
				carried += end - at
			at = end
