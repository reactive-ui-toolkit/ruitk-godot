@tool
class_name RuitkBuilderCanvasHost
extends Control
## The canvas surface: it owns the camera, mounts the dogfooded view through the reconciler, and
## keeps the edge overlay on top of it.
##
## The HOST owns the camera; the VIEW is pure presentation. A view that owned its own camera would
## have to be asked where it was looking before anything else could act on it -- the edge overlay,
## a fit-to-view, a saved layout -- and every one of those readers is a chance for the two to
## disagree about the same number.
##
## The card layer is `canvas_view.guitkx`, compiled by this project's own compiler and rendered by
## its own reconciler. That is deliberate: the canvas is the busiest re-rendered surface here, so
## it is the strongest test the library gets.

const Metrics = preload("res://addons/reactive_ui_toolkit_editor/builder/canvas/builder_canvas_metrics.gd")
const Graph = preload("res://addons/reactive_ui_toolkit_editor/builder/canvas/builder_graph.gd")
const Edges = preload("res://addons/reactive_ui_toolkit_editor/builder/canvas/builder_canvas_edges.gd")
const Palette = preload("res://addons/reactive_ui_toolkit_editor/builder/canvas/canvas_palette.gd")
const CanvasView = preload("res://addons/reactive_ui_toolkit_editor/builder/canvas/canvas_view.gd")
const V = preload("res://addons/reactive_ui_toolkit/core/v.gd")
const RuitkRoot = preload("res://addons/reactive_ui_toolkit/core/reactive_root.gd")

## How much one wheel notch changes the zoom, as a multiplier.
const ZOOM_STEP := 1.12

signal camera_changed(camera: Vector2, zoom: float)
signal card_selected(index: int)
signal canvas_context_requested(world_position: Vector2)
signal card_context_requested(index: int, world_position: Vector2)

## A ROW inside a card was clicked, or right-clicked. `section` is a `Metrics.Section`.
##
## The spine of the whole surface, and it was missing: clicks resolved to a CARD and stopped, so
## every row-level gesture the builder is FOR -- jump the source to this line, add an attribute to
## this element, wrap this row in an @if, delete this element -- had no way to be expressed. The
## hit-test existed and was only ever asked by a drop.
signal row_clicked(card_index: int, section: int, row_index: int)
signal row_context_requested(card_index: int, section: int, row_index: int, at: Vector2)

## A card's own "+" affordance was used: `what` is one of "hook", "code", "style", "entry".
##
## The card is where the user is LOOKING when they want another hook, so it is where the button
## belongs -- a builder whose only way to add state is a menu three levels into the chrome is a
## builder people go back to the text editor to use.
signal card_add_requested(index: int, what: String)

## Something was dropped on the canvas. `data` is whatever the source put in it; `at` is where.
signal dropped(data: Dictionary, at: Vector2)

## A card was dragged to a new place on the canvas. The window persists it to the layout.
signal card_moved(index: int, to: Vector2)

var graph: Graph = null
var camera := Vector2.ZERO
var zoom := 1.0
var selected := -1

var _cards: Control = null
var _edges: Edges = null
var _root: RuitkRoot = null
var _panning := false
var _pan_from := Vector2.ZERO

## A card being dragged: which one, and where in the card the pointer took hold, so it does not
## jump to have its corner under the cursor.
var _moving := -1
var _grab_offset := Vector2.ZERO
## Where the left button went down, to tell a click from the start of a drag.
var _pressed_at := Vector2.ZERO
var _press_index := -1

## Whether the press that may become a drag landed on a card's TITLE BAR. Recorded at press rather
## than asked at motion, because by then the pointer has left the bar it started on.
var _press_on_title := false

## Bumped on every `show_graph`, so an in-place model change cannot be bailed out of.
var _revision := 0


func _init() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)

	_cards = Control.new()
	_cards.name = "Cards"
	_cards.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cards.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_cards)

	_edges = Edges.new()
	_edges.name = "Edges"
	add_child(_edges)


func _exit_tree() -> void:
	unmount()


## Points the canvas at a graph and renders it. Safe to call repeatedly: the reconciler diffs, so
## a re-render after an edit patches what changed rather than rebuilding the tree.
func show_graph(new_graph: Graph) -> void:
	graph = new_graph
	# A NEW REVISION EVERY TIME. The graph is re-populated IN PLACE after an edit -- the same
	# object, with different rows in it -- so the props the view is re-rendered with compare equal
	# to the last ones and the reconciler's bailout correctly decides there is nothing to do.
	# Correct, and wrong for us: the card then keeps showing the rows it had, so adding a hook put
	# a line in the source pane and nothing on the card until some unrelated change forced a
	# render. The revision is the one prop that is never the same twice.
	_revision += 1
	_render()


func set_camera(new_camera: Vector2, new_zoom: float) -> void:
	camera = new_camera
	zoom = Metrics.clamp_zoom(new_zoom)
	queue_redraw()
	_render()
	# ANNOUNCED, like `fit_to_view` does. Only the fit emitted, so everything downstream of the
	# camera -- the saved layout, and the layer selector that is supposed to name the band on
	# screen -- was updated by one of the two ways the camera moves and not by the other. A
	# selector that only follows some camera changes is a selector that is sometimes wrong.
	camera_changed.emit(camera, zoom)


func select_card(index: int) -> void:
	if selected == index:
		return
	selected = index
	card_selected.emit(index)
	_render()


## Frames the whole graph. What "reset view" does, and what a freshly opened tree with no saved
## layout comes up as.
## Brings ONE card up to fill the surface, and selects it.
func frame_card(index: int) -> void:
	if graph == null or index < 0 or index >= graph.cards.size() or size.x <= 0.0:
		return
	var solved := Metrics.frame_card(graph.cards[index], size)
	set_camera(solved["camera"], solved["zoom"])
	select_card(index)


func fit_to_view() -> void:
	if graph == null:
		return
	var fit := Metrics.fit_to_view(graph, size)
	camera = fit["camera"]
	zoom = fit["zoom"]
	_render()
	camera_changed.emit(camera, zoom)


func unmount() -> void:
	if _root != null:
		_root.unmount()
		_root = null


## Makes every card Control transparent to the mouse, except the ones that are buttons.
##
## THE BUG THIS FIXES BROKE EVERY CANVAS GESTURE AT ONCE. A card is a `PanelContainer` full of
## `Label`s, and Godot's default `mouse_filter` for those is STOP -- so a press anywhere on a card
## was consumed by the card's own Control and `_gui_input` on this host never saw it. Dragging a
## card, clicking a row to jump the source, right-clicking a row for its menu: all of them worked
## only in the gaps BETWEEN cards, which is to say none of them worked.
##
## Buttons are left alone: the `+ hook` / `+ code` chips are the one thing on a card that handles
## its own press, and that is why they were the one thing that worked.
##
## Applied on every render rather than set per element in the view: the reconciler rebuilds this
## subtree constantly, and a filter that has to be remembered on every new element in a growing
## markup file is a filter that will be forgotten.
func _pass_mouse_through(node: Node) -> void:
	for child in node.get_children():
		if child is Control and not (child is BaseButton):
			(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		_pass_mouse_through(child)


## Relays a card's "+" to whoever owns the model. The view holds no model and edits nothing; it
## reports that a button was pressed and the window turns that into one `apply_edit`.
func _on_card_add(index: int, what: String) -> void:
	card_add_requested.emit(index, what)


func _render() -> void:
	if graph == null:
		return
	var props := {
		"graph": graph,
		"camera": camera,
		"zoom": zoom,
		"viewport": size,
		"selected": selected,
		"on_add": Callable(self, "_on_card_add"),
		"revision": _revision,
	}
	if _root == null:
		_root = RuitkRoot.create(_cards, V.fc(Callable(CanvasView, "render"), props))
	else:
		_root.set_root(V.fc(Callable(CanvasView, "render"), props))
	_pass_mouse_through(_cards)
	_edges.refresh(graph, camera, zoom, selected)
	_settle_frames = SETTLE_FRAMES
	set_process(true)


## How many frames the fit pass keeps running after a render.
##
## Not one, and not a deferred call. A Control's minimum size is recomputed by Godot's own layout
## pass, which runs on its own schedule after the reconciler has committed -- so the first attempt
## reads the size the card had an edit ago and fits it to that. Running until the fit is a no-op
## costs two idle frames after a change and nothing at all when nothing is changing.
const SETTLE_FRAMES := 3

var _settle_frames := 0


func _process(_delta: float) -> void:
	_fit_cards()
	_settle_frames -= 1
	if _settle_frames <= 0:
		set_process(false)


## Shrinks every card back to its content. Returns true when something actually moved.
##
## A Control in a non-container parent GROWS to its minimum size and then keeps it: nothing ever
## makes it smaller again. So a card that has been seen at the full LOD stays that tall at the
## pill LOD, and the canvas fills with boxes of empty space that used to hold a markup tree.
## `reset_size` is the one call that takes a Control back to what it currently needs.
func _fit_cards() -> bool:
	if _cards == null:
		return false
	var moved := false
	for view_root in _cards.get_children():
		for card in (view_root as Node).get_children():
			if not (card is Control):
				continue
			var control := card as Control
			var wanted := control.get_combined_minimum_size()
			if not control.size.is_equal_approx(wanted):
				control.reset_size()
				moved = true
	return moved


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _root != null:
		# The viewport is what the cull measures against, so a resize is a re-render -- otherwise
		# cards that just came into view stay culled until something else moves.
		_render()


# ── Input ────────────────────────────────────────────────────────────────────────────

## The canvas's own ground and grid, UNDER everything.
##
## On the host rather than on the edge overlay, because a Control draws before its children and
## the overlay is one of them -- painted there, the ground covered every card on the canvas and
## the grid dotted the tops of them.
##
## The palette has defined a dark canvas colour since the first canvas commit and NOTHING EVER
## PAINTED IT, so the canvas showed the editor's own panel grey: the same value as the panes
## beside it and lighter than the cards on top of it. Everything read as one flat sheet, which
## is the single biggest reason this did not look like a canvas.
func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Palette.bg()["bg_color"])

	var spacing := GRID_SPACING * zoom
	if spacing < GRID_MIN_SCREEN_SPACING:
		return
	var alpha: float = clampf((spacing - GRID_MIN_SCREEN_SPACING) / GRID_MIN_SCREEN_SPACING, 0.0, 1.0)
	var tint := Color(GRID_COLOR, GRID_COLOR.a * alpha)
	var first := Vector2(fposmod(camera.x, spacing), fposmod(camera.y, spacing))
	var y := first.y
	while y < size.y:
		var x := first.x
		while x < size.x:
			draw_rect(Rect2(Vector2(x, y), Vector2(GRID_DOT, GRID_DOT)), tint)
			x += spacing
		y += spacing


## The canvas grid: world-space cell size, the screen spacing below which it stops being drawn,
## and the dot itself.
const GRID_SPACING := 64.0
const GRID_MIN_SCREEN_SPACING := 14.0
const GRID_DOT := 2.0
const GRID_COLOR := Color(0.34, 0.34, 0.40, 0.55)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion:
		_handle_motion(event as InputEventMouseMotion)


func _handle_button(event: InputEventMouseButton) -> void:
	match event.button_index:
		MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
			if not event.pressed:
				return
			var factor := ZOOM_STEP if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / ZOOM_STEP
			var target := Metrics.clamp_zoom(zoom * factor)
			if is_equal_approx(target, zoom):
				return
			# Zoomed ABOUT THE CURSOR: the world point under the pointer stays under it, or the
			# canvas slides out from beneath the thing the user was aiming at.
			camera = Metrics.zoom_about(camera, zoom, target, event.position)
			zoom = target
			_render()
			camera_changed.emit(camera, zoom)
			accept_event()
		MOUSE_BUTTON_MIDDLE:
			_panning = event.pressed
			_pan_from = event.position
			if not event.pressed:
				camera_changed.emit(camera, zoom)
			accept_event()
		MOUSE_BUTTON_LEFT:
			if event.pressed:
				_pressed_at = event.position
				_press_index = card_at(event.position)
				# WHETHER THE PRESS LANDED ON THE TITLE BAR decides whether a later drag moves the
				# card or pans the canvas. Recorded at press rather than asked at motion, because
				# by then the pointer has left the bar it started on.
				_press_on_title = _press_index >= 0 and Metrics.on_title_bar(
					graph.cards[_press_index],
					Metrics.screen_to_world(event.position, camera, zoom),
					Metrics.card_width_for(Metrics.lod_of(zoom)), Metrics.lod_of(zoom))
				select_card(_press_index)
				var hit := row_at(_press_index, event.position)
				if bool(hit.get("found", false)):
					row_clicked.emit(_press_index, int(hit["section"]), int(hit["index"]))
			else:
				# A card that was dragged tells the window where it ended up; one that was only
				# clicked has already been handled by the press.
				if _moving >= 0:
					card_moved.emit(_moving, Vector2(graph.cards[_moving].x, graph.cards[_moving].y))
				_moving = -1
				_panning = false
				_press_index = -1
				camera_changed.emit(camera, zoom)
			accept_event()
		MOUSE_BUTTON_RIGHT:
			if not event.pressed:
				return
			var world := Metrics.screen_to_world(event.position, camera, zoom)
			var index := card_at(event.position)
			if index >= 0:
				# A row menu when the pointer is ON a row, the card's menu otherwise. The row is
				# the more specific target and the one the user aimed at.
				var hit := row_at(index, event.position)
				if bool(hit.get("found", false)):
					row_context_requested.emit(
						index, int(hit["section"]), int(hit["index"]), event.position)
				else:
					card_context_requested.emit(index, world)
			else:
				canvas_context_requested.emit(world)
			accept_event()


## Anything can be dropped here; the window decides whether it lands.
##
## Answered `true` for every payload this builder produces rather than resolving the target
## here: the resolve is the window's, it needs the model, and a canvas that said "no" from a
## partial view would refuse drops the window would have accepted.
func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and (data as Dictionary).has("source")


func _drop_data(at_position: Vector2, data: Variant) -> void:
	dropped.emit(data as Dictionary, at_position)


## A markup ROW is draggable, which is how a subtree is re-parented.
func _get_drag_data(at_position: Vector2) -> Variant:
	var index := card_at(at_position)
	if index < 0:
		return null
	var hit := row_at(index, at_position)
	if not bool(hit.get("found", false)):
		return null
	var card := graph.cards[index]
	var rows: Array = card.markup if int(hit["section"]) == int(Metrics.Section.MARKUP) else []
	var row_index := int(hit["index"])
	if row_index < 0 or row_index >= rows.size():
		return null

	var ghost := Label.new()
	ghost.text = str(rows[row_index].text)
	set_drag_preview(ghost)
	return {
		"source": "row",
		"card_id": card.module_id,
		"row_at": int(rows[row_index].at),
		"row_index": row_index,
	}


## Pointer movement: moving a card, panning the canvas, or neither.
##
## BOTH WERE MISSING. A canvas that cannot be panned except by the middle button, and cards that
## cannot be moved at all, is a diagram rather than a canvas -- and the layout store, the
## per-tree persistence and the fit-to-view were all written for positions nobody could change.
func _handle_motion(motion: InputEventMouseMotion) -> void:
	if _moving >= 0:
		var world := Metrics.screen_to_world(motion.position, camera, zoom)
		var card := graph.cards[_moving]
		card.x = world.x - _grab_offset.x
		card.y = world.y - _grab_offset.y
		_render()
		accept_event()
		return

	if _panning:
		camera += motion.position - _pan_from
		_pan_from = motion.position
		queue_redraw()
		_render()
		accept_event()
		return

	# A left button held down becomes a DRAG once it has travelled far enough -- on a card it
	# moves the card, on empty canvas it pans. Below the threshold it is still a click, because
	# treating every click as a one-pixel drag makes selection impossible.
	if not (motion.button_mask & MOUSE_BUTTON_MASK_LEFT):
		return
	if _pressed_at.distance_to(motion.position) < DRAG_THRESHOLD:
		return
	if _press_on_title and _press_index >= 0 and graph != null and _press_index < graph.cards.size():
		var card := graph.cards[_press_index]
		var world := Metrics.screen_to_world(_pressed_at, camera, zoom)
		_grab_offset = world - Vector2(card.x, card.y)
		_moving = _press_index
	else:
		_panning = true
		_pan_from = motion.position
	accept_event()


## How far the pointer travels before a press is a drag rather than a click.
const DRAG_THRESHOLD := 4.0


## The row under a SCREEN point within card `index`, as `Metrics.row_hit` reports it.
func row_at(index: int, screen_position: Vector2) -> Dictionary:
	if graph == null or index < 0 or index >= graph.cards.size():
		return { "found": false }
	if not Metrics.shows_sections(Metrics.lod_of(zoom)):
		return { "found": false }   # a pill has no rows to aim at
	var card := graph.cards[index]
	return Metrics.row_hit(card, Metrics.card_local_of(card, screen_position, camera, zoom))


## The card under a SCREEN point, or -1.
##
## Hit-tested against the model, not against the node tree. The cards are rendered by the
## reconciler and re-created as the graph changes, so a hit-test that walked Controls would be
## asking a tree that has already moved on -- and the answer would be right most of the time,
## which is the worst kind of wrong. Topmost wins, which is the last card drawn.
func card_at(screen_position: Vector2) -> int:
	if graph == null:
		return -1
	var world := Metrics.screen_to_world(screen_position, camera, zoom)
	var lod := Metrics.lod_of(zoom)
	var width := Metrics.card_width_for(lod)
	for i in range(graph.cards.size() - 1, -1, -1):
		var card := graph.cards[i]
		if Rect2(card.x, card.y, width, Metrics.drawn_height(card, lod)).has_point(world):
			return i
	return -1
