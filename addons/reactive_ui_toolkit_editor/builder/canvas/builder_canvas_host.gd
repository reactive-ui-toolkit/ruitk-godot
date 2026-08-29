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

## A row was DOUBLE-CLICKED: edit it in place.
##
## The reference's primary editing gesture, and it had no route here at all -- the whole builder
## contained one `double_click` read, in the library. So a hook chip, a code island, a style entry
## and an element row could each be looked at and none of them edited without going through a
## context menu or the source pane.
signal row_activated(card_index: int, section: int, row_index: int, at: Vector2)

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

## A card was double-clicked somewhere that is NOT one of its rows.
##
## The reference opens the module's file on this gesture; here the module is already open, so
## what a reader wants from it is to be taken TO the card -- which a single click, which only
## selects, does not do.
signal card_activated(card_index: int)

var graph: Graph = null
var camera := Vector2.ZERO
var zoom := 1.0
var selected := -1

## The selected ROW within `selected`, as (section, index). Both -1 when the selection is the card
## itself rather than something inside it.
var selected_row_section := -1
var selected_row_index := -1

## The identifiers the hovered hook chip binds. Empty when nothing is hovered.
var highlight_names := PackedStringArray()

## WHAT WAS ACTUALLY DRAWN, per card: `{ card_index: { "height": float, "rows": { key: Rect2 } } }`
## in CARD-LOCAL units, where `key` is "section:index".
##
## The section stack is a PREDICTION. It is computed from constants -- a heading block, a row
## pitch, a section origin -- and nothing ever compared it to the Control tree the view lays out.
## It was wrong by 35-60px by the bottom of a card, so `card_at` reported no card over the lower
## half of every card, clicking one row selected its neighbour, and a right-click below a card
## opened that card's row menu. Measurement makes the answer observable; the estimate stays as the
## pre-layout fallback, which is what Unity does and says it does.
var _measured := {}

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

## Where a drag is hovering, in this Control's coordinates, or negative when there is none.
var _drop_at := Vector2(-1.0, -1.0)

## Bumped on every `show_graph`, so an in-place model change cannot be bailed out of.
var _revision := 0


func _init() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	# THE CANVAS TAKES THE KEYBOARD WHEN CLICKED, and that single line answers two defects.
	# Godot only moves focus to the control a press directly hits, and only when that control's
	# `focus_mode` is not FOCUS_NONE -- the Control default, which this was. So a click on the
	# canvas focused nothing, and the inline editor's commit-on-blur, which hangs off the
	# LineEdit's `focus_exited`, could never fire: the editor kept the keyboard while the user
	# clicked away, so "clicking away commits" was dead. It also left the keyboard model with no
	# owner it could see.
	focus_mode = Control.FOCUS_CLICK
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
	if selected == index and selected_row_index < 0:
		return
	selected = index
	# EXACTLY ONE THING IS SELECTED AT A TIME. Selecting a card clears any row selection, so
	# Delete can never be ambiguous about which of the two it means.
	selected_row_section = -1
	selected_row_index = -1
	card_selected.emit(index)
	_render()


## HOVERING A HOOK CHIP HIGHLIGHTS EVERY USAGE of what it returns (capability reference §4).
##
## A hook chip reads `useState  →  count`, and the question it raises is the one the card cannot
## otherwise answer: where does `count` actually get used. Rendering the answer on hover keeps it
## out of the way until it is asked for.
func _track_hover(at: Vector2) -> void:
	var names := PackedStringArray()
	var index := card_at(at)
	if index >= 0:
		var hit := row_at(index, at)
		if bool(hit.get("found", false)) and int(hit["section"]) == int(Metrics.Section.BODY):
			var rows: Array[Graph.Line] = graph.cards[index].body
			var row_index := int(hit["index"])
			if row_index >= 0 and row_index < rows.size():
				names = _bound_names(rows[row_index])
	if names == highlight_names:
		return
	highlight_names = names
	_render()


## The identifiers a hook chip introduces, read off its own text.
##
## The chip is projected as `useState  →  count, set_count`, so the bindings are what follows the
## arrow. Taken from the projected row rather than re-parsed: the row is what the user is pointing
## at, and a second parse of the same line is a second thing to keep in step.
static func _bound_names(row: Graph.Line) -> PackedStringArray:
	var out := PackedStringArray()
	if row == null:
		return out
	var arrow := row.text.find("→")
	if arrow < 0:
		return out
	for part in row.text.substr(arrow + "→".length()).split(","):
		var name := str(part).strip_edges()
		if not name.is_empty():
			out.append(name)
	return out


## Selects one ROW on one card -- a markup row, a hook chip, an import row, a code island line or
## a style entry. Any row the canvas lists is selectable, because each is backed by a line range
## that knows how to remove itself.
func select_row(card_index: int, section: int, row_index: int) -> void:
	if selected == card_index and selected_row_section == section 			and selected_row_index == row_index:
		return
	selected = card_index
	selected_row_section = section
	selected_row_index = row_index
	card_selected.emit(card_index)
	_render()


## Brings ONE card up to fill the surface, and selects it.
func frame_card(index: int) -> void:
	if graph == null or index < 0 or index >= graph.cards.size() or size.x <= 0.0:
		return
	var solved := Metrics.frame_card(graph.cards[index], size)
	set_camera(solved["camera"], solved["zoom"])
	select_card(index)


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
		"highlight_names": highlight_names,
		"selected_row_section": selected_row_section,
		"selected_row_index": selected_row_index,
		"on_add": Callable(self, "_on_card_add"),
		"revision": _revision,
	}
	if _root == null:
		# ISOLATED, like the preview stage: a budget of its own on the editor's shared tree. A tree
		# of a hundred cards is a big render, and it must not be able to eat the frames the preview
		# beside it is also asking for.
		_root = RuitkRoot.create_isolated(_cards, V.fc(Callable(CanvasView, "render"), props))
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
## Enough frames to outlast a SLICED commit, not just Godot's layout pass. A render that spends
## its quantum continues on the scheduler's Normal lane under the frame budget, so on a large tree
## the commit can be several frames behind the `set_root` that asked for it.
const SETTLE_FRAMES := 8

var _settle_frames := 0


func _process(_delta: float) -> void:
	_fit_cards()
	# AND THE MOUSE PASS, EVERY SETTLE FRAME. An UPDATE render is time-sliced: `set_root` returns
	# as soon as the slice quantum is spent, and the commit lands one or more frames later -- so
	# the walk that ran straight after `set_root` saw the tree as it was BEFORE the change, and
	# every node that commit created kept Godot's default `STOP`. On a small tree the whole render
	# finishes inside the first quantum and commits synchronously, which is why this never showed
	# up in a test and always showed up on a real one.
	#
	# The view declares `mouse_filter` on everything it builds, so this is now a safety net rather
	# than the mechanism. It stays because "a Control nobody remembered to annotate" is exactly the
	# failure it catches, and the symptom -- no dragging, no dropping, no row menus -- gives no
	# hint of the cause.
	_pass_mouse_through(_cards)
	_measure_cards()
	_settle_frames -= 1
	if _settle_frames <= 0:
		set_process(false)


## Records every drawn row's rect, in card-local units.
##
## Run from the settle loop, so it re-reads after Godot's layout pass has settled and after a
## sliced commit has landed. Positions are divided by `zoom` because a card node carries the zoom
## as its `scale`, while the section stack -- and therefore every consumer -- speaks card-local
## units.
func _measure_cards() -> void:
	if _cards == null or graph == null:
		return
	var fresh := {}
	# SEARCHED, not iterated. The view's own root `Control` sits between this node and the cards,
	# so the card nodes are grandchildren -- and a component boundary could add another level at
	# any time. Finding them by name is what makes this robust to the tree's shape.
	_collect_cards(_cards, fresh)
	if not fresh.is_empty():
		_measured = fresh


func _collect_cards(node: Node, out: Dictionary) -> void:
	for child in node.get_children():
		if child is Control and str(child.name).begins_with("card-"):
			var index := int(str(child.name).substr(5))
			if index >= 0 and index < graph.cards.size():
				var card_control := child as Control
				var entry := { "height": card_control.size.y, "rows": {} }
				_collect_rows(card_control, card_control.get_global_rect().position,
					maxf(zoom, 0.0001), entry["rows"])
				out[index] = entry
			continue
		_collect_cards(child, out)


## `clip` is the running visible rect in GLOBAL coordinates, empty when nothing clips.
##
## A capped section is a `ScrollContainer`, and its children are laid out in full whether or not
## they are inside the viewport -- so a row scrolled past the bottom still has a rect, one that
## sits over the section BELOW it. Measured unclipped, the hit-test would report a row nobody can
## see for a click on a row they can.
func _collect_rows(node: Node, origin: Vector2, scale: float, out: Dictionary,
		clip := Rect2()) -> void:
	for child in node.get_children():
		var here := clip
		if child is Control:
			var control := child as Control
			var name := str(control.name)
			if control is ScrollContainer:
				var box := control.get_global_rect()
				here = box if here.size == Vector2.ZERO else here.intersection(box)
			if name.begins_with("row-"):
				var parts := name.substr(4).split("-")
				if parts.size() == 2:
					var rect := control.get_global_rect()
					if here.size != Vector2.ZERO:
						rect = here.intersection(rect)
						# Gone, or a sliver at the edge of the viewport. A one-pixel strip is not
						# something a person can aim at, and treating it as hittable makes the row
						# above it unreachable along its own bottom edge.
						if rect.size.y <= 2.0:
							continue
					out["%s:%s" % [parts[0], parts[1]]] = Rect2(
						(rect.position - origin) / scale, rect.size / scale)
		_collect_rows(child, origin, scale, out, here)


## The measured rect of one row, or an empty Rect2 when nothing was measured.
func measured_row(card_index: int, section: int, row_index: int) -> Rect2:
	var entry: Variant = _measured.get(card_index)
	if not (entry is Dictionary):
		return Rect2()
	var rows: Dictionary = (entry as Dictionary)["rows"]
	var key := "%d:%d" % [section, row_index]
	return rows[key] if rows.has(key) else Rect2()


## The measured height of a card, or 0.0 when nothing was measured.
func measured_height(card_index: int) -> float:
	var entry: Variant = _measured.get(card_index)
	return float((entry as Dictionary)["height"]) if entry is Dictionary else 0.0


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

	# THE LATTICE COARSENS, IT DOES NOT VANISH. Below zoom 0.219 the dots used to stop entirely and
	# were already faint at the Architecture layer's 0.30 preset -- so the one layer you PAN in had
	# no ground reference, and a drag of an empty region moved nothing the eye could follow. The
	# world tile doubles until its screen spacing is legible again, which is what the Unreal leg
	# does; the loop is bounded so a pathological zoom cannot spin it.
	var world := GRID_SPACING
	var spacing := world * zoom
	var doublings := 0
	while spacing < GRID_MIN_SCREEN_SPACING and doublings < 24:
		world *= 2.0
		spacing = world * zoom
		doublings += 1
	if spacing < GRID_MIN_SCREEN_SPACING:
		return
	# RAMPED, NEVER TO NOTHING. The old ramp reached zero exactly at the threshold, so the grid
	# faded out just as the doubling brought it back.
	var alpha: float = clampf(spacing / (GRID_MIN_SCREEN_SPACING * 2.0), 0.45, 1.0)
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


## CTRL+WHEEL IS ALWAYS THE ZOOM, even over something that consumes the plain wheel.
##
## A capped card section is a `ScrollContainer`, and a `ScrollContainer` handles the wheel -- so
## over a long markup body the plain wheel scrolls the section and never reaches `_gui_input`.
## That is the behaviour the reference chose ("a scrollable section consumes the plain wheel;
## Ctrl+wheel stays a zoom everywhere"), and it only holds if the zoom has a route that does not
## go through the GUI pick. `_input` runs before the GUI does, so this is that route.
func _input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var button := event as InputEventMouseButton
	if not button.pressed or not button.ctrl_pressed:
		return
	if button.button_index != MOUSE_BUTTON_WHEEL_UP and button.button_index != MOUSE_BUTTON_WHEEL_DOWN:
		return
	if not get_global_rect().has_point(button.global_position):
		return
	_handle_button(button)
	get_viewport().set_input_as_handled()


## THE POINTER SAYS WHAT WILL HAPPEN. Every surface in this builder drew the OS arrow: a card
## title bar you can drag, a kind chip that carries the module, a row you can click and empty
## canvas you can pan all looked identical, so the only way to find out what a press would do was
## to press. The reference has a cursor for each; these are Godot's nearest equivalents.
func _get_cursor_shape(at_position := Vector2.ZERO) -> CursorShape:
	if _panning or _moving >= 0:
		return Control.CURSOR_MOVE
	if graph == null:
		return Control.CURSOR_ARROW
	var index := card_at(at_position)
	if index < 0:
		# Empty canvas is a pannable surface, and a drag here is how you move around it.
		return Control.CURSOR_DRAG
	var lod := Metrics.lod_of(zoom)
	var world := Metrics.screen_to_world(at_position, camera, zoom)
	var width := Metrics.card_width_for(lod)
	if Metrics.on_kind_badge(graph.cards[index], world, width, lod):
		return Control.CURSOR_POINTING_HAND   # the module's own handle
	if Metrics.on_title_bar(graph.cards[index], world, width, lod):
		return Control.CURSOR_MOVE            # drag the card
	if bool(row_at(index, at_position).get("found", false)):
		return Control.CURSOR_POINTING_HAND
	return Control.CURSOR_ARROW


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion:
		_handle_motion(event as InputEventMouseMotion)


## Takes the drop hint down. Called when the drop lands and when the drag leaves the canvas.
func _clear_drop_hint() -> void:
	if _drop_at.x < 0.0:
		return
	_drop_at = Vector2(-1.0, -1.0)
	if _edges != null:
		_edges.set_drop_hint(_drop_at)


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
					if event.double_click:
						row_activated.emit(_press_index, int(hit["section"]),
							int(hit["index"]), event.position)
				elif event.double_click and _press_index >= 0:
					# A DOUBLE-CLICK ON THE CARD ITSELF, not on one of its rows. The reference
					# opens the module's file; here the module is already open -- what a reader
					# wants from the gesture is to be taken TO it, which a single click, which only
					# selects, does not do.
					card_activated.emit(_press_index)
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
func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	# A DROP THAT SHOWS NOTHING is a drop the user has to guess at. The three-band rule was
	# resolved live and correctly here and then drawn NOWHERE, so before / inside / after -- and
	# the first-child case -- were invisible until after the edit had happened. Godot calls this
	# on every motion of a drag, which is exactly the cadence a hint needs.
	var ok: bool = data is Dictionary and (data as Dictionary).has("source")
	_drop_at = at_position if ok else Vector2(-1.0, -1.0)
	if _edges != null:
		_edges.set_drop_hint(_drop_at)
	return ok


func _drop_data(at_position: Vector2, data: Variant) -> void:
	_clear_drop_hint()
	dropped.emit(data as Dictionary, at_position)


## A markup ROW is draggable, which is how a subtree is re-parented.
func _get_drag_data(at_position: Vector2) -> Variant:
	var index := card_at(at_position)
	if index < 0:
		return null
	var card_here := graph.cards[index]
	var lod := Metrics.lod_of(zoom)
	# THE KIND CHIP IS THE MODULE'S OWN HANDLE. Dragging a card by its title bar MOVES it on the
	# canvas; dragging it by its kind chip carries the MODULE -- to a folder row, onto another
	# card, wherever a module payload is accepted. Without it a module could only be re-filed from
	# the folder pane, and the card, which is the thing the user is looking at, was inert.
	if Metrics.on_kind_badge(card_here, Metrics.screen_to_world(at_position, camera, zoom),
			Metrics.card_width_for(lod), lod):
		var chip := Label.new()
		chip.text = card_here.title
		set_drag_preview(chip)
		return {
			"source": "module",
			"path": card_here.file_path,
			"card_id": card_here.module_id,
		}
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

	# A drag that left the canvas takes its hint with it.
	if _drop_at.x >= 0.0 and not (motion.button_mask & MOUSE_BUTTON_MASK_LEFT):
		_clear_drop_hint()
	_track_hover(motion.position)

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
	var local := Metrics.card_local_of(card, screen_position, camera, zoom)
	# THE MEASURED ROWS FIRST. The estimate is only the answer before anything has been laid out.
	var hit := _measured_hit(index, local)
	if bool(hit["found"]):
		return hit
	return Metrics.row_hit(card, local, Metrics.lod_of(zoom))


## Which drawn row a card-local point is in, from the measured rects.
##
## Returns the same shape as `Metrics.row_hit`, bands included, so every consumer is unchanged.
func _measured_hit(card_index: int, local: Vector2) -> Dictionary:
	var entry: Variant = _measured.get(card_index)
	if not (entry is Dictionary):
		return { "found": false }
	for key in ((entry as Dictionary)["rows"] as Dictionary):
		var rect: Rect2 = (entry as Dictionary)["rows"][key]
		if not rect.has_point(local):
			continue
		var parts := str(key).split(":")
		var fraction: float = (local.y - rect.position.y) / maxf(rect.size.y, 0.001)
		var band := 1
		if fraction < Metrics.BAND_EDGE:
			band = 0
		elif fraction > 1.0 - Metrics.BAND_EDGE:
			band = 2
		return { "found": true, "section": int(parts[0]), "index": int(parts[1]), "band": band }
	return { "found": false }


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
		# THE MEASURED HEIGHT when there is one. The estimate over-reported by tens of pixels, so
		# empty canvas below a card answered as that card and opened its row menu.
		var height: float = measured_height(i)
		if height <= 0.0:
			height = Metrics.drawn_height(card, lod)
		if Rect2(card.x, card.y, width, height).has_point(world):
			return i
	return -1
