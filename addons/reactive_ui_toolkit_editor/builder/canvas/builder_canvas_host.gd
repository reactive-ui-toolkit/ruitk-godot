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

var graph: Graph = null
var camera := Vector2.ZERO
var zoom := 1.0
var selected := -1

var _cards: Control = null
var _edges: Edges = null
var _root: RuitkRoot = null
var _panning := false
var _pan_from := Vector2.ZERO


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
	_render()


func set_camera(new_camera: Vector2, new_zoom: float) -> void:
	camera = new_camera
	zoom = Metrics.clamp_zoom(new_zoom)
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
	}
	if _root == null:
		_root = RuitkRoot.create(_cards, V.fc(Callable(CanvasView, "render"), props))
	else:
		_root.set_root(V.fc(Callable(CanvasView, "render"), props))
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

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion and _panning:
		var motion := event as InputEventMouseMotion
		camera += motion.position - _pan_from
		_pan_from = motion.position
		_render()
		accept_event()


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
				var index := card_at(event.position)
				select_card(index)
				var hit := row_at(index, event.position)
				if bool(hit.get("found", false)):
					row_clicked.emit(index, int(hit["section"]), int(hit["index"]))
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
	var width := Metrics.card_width_for(Metrics.lod_of(zoom))
	for i in range(graph.cards.size() - 1, -1, -1):
		var card := graph.cards[i]
		if Rect2(card.x, card.y, width, Metrics.card_height(card)).has_point(world):
			return i
	return -1
