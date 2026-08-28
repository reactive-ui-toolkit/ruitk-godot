@tool
extends EditorPlugin
## DEV TOOL — screenshots the RUITK Builder in each state the visual gauntlet compares.
##
## Not part of the shipped addon and not enabled by default. `scripts/builder-shots.mjs` turns it
## on, runs the editor once, shoots, and turns it back off. Nothing here is on a user's path.
##
## WHY IT RUNS INSIDE THE EDITOR. The builder is editor UI: it wears the editor theme, and the
## source pane's highlighter deliberately does nothing when `not Engine.is_editor_hint()`. A
## standalone `--script` capture would render the builder in Godot's default project theme with a
## grey source pane -- a picture of something nobody ever sees, and every difference in it a
## finding about nothing.
##
## HOW THE PIXELS COME OUT. A `Window` IS a `Viewport`, so the builder's own window hands over its
## texture directly: one shot of the builder alone, no editor chrome around it, at a size this
## file fixes so shots stay comparable between runs.

const Metrics = preload("res://addons/reactive_ui_toolkit_editor/builder/canvas/builder_canvas_metrics.gd")

const SHOT_DIR := "res://Images/current"

## The fixture tree, mirrored from the Unity leg's screenshots so a comparison is about layout.
const FIXTURE := "res://tests/__builder_shots/NewComponent/NewComponent.guitkx"
const FIXTURE_RIGHT := "res://tests/__builder_shots/NewComponent/components/RightSide/RightSide.guitkx"

## Fixed so two runs are comparable, and 16:10-ish like the references.
const SHOT_SIZE := Vector2i(1920, 1010)

## What to shoot, and how to get there. `zoom` is the camera zoom; `select` names the module whose
## card is selected; `menu` opens a popup over the canvas. One entry per reference image, by the
## same name -- a shot with no reference is a shot nobody compares.
const SHOTS := [
	{ "name": "empty", "tree": false },
	{ "name": "cards", "tree": true, "zoom": 0.34, "select": "" },
	{ "name": "cards_create_menu", "tree": true, "zoom": 0.34, "select": "", "menu": "library" },
	{ "name": "edit", "tree": true, "zoom": 1.00, "select": FIXTURE_RIGHT },
	{ "name": "edit_card_menu", "tree": true, "zoom": 1.00, "select": FIXTURE_RIGHT, "menu": "card" },
	{ "name": "edit_zoomed", "tree": true, "zoom": 1.35, "select": FIXTURE_RIGHT },
	# A REAL FILE, not the fixture. The fixture is five files this harness's author wrote, with
	# no comments and no setup code in them -- so it could not exhibit the bug where a source
	# comment was drawn as a markup row, and six review rounds looked straight past it. Every
	# shot set needs at least one picture of something nobody tidied first.
	{ "name": "real_file", "tree": true, "zoom": 1.00, "select": REAL_FILE, "focus": REAL_FILE },
]

## The builder's own canvas view: a real component, with real comments, real setup and a real
## directive body.
const REAL_FILE := "res://addons/reactive_ui_toolkit_editor/builder/canvas/canvas_view.guitkx"

## How long to let the tree settle before the first shot. The preview round is debounced and the
## canvas measures its cards over a few frames, so a shot taken too early is a picture of a layout
## still moving.
const SETTLE_SECONDS := 4.0

var _armed := false
var _window: Window = null


func _enter_tree() -> void:
	set_process(true)


func _process(_delta: float) -> void:
	if _armed:
		return
	_armed = true
	set_process(false)
	_run()


func _run() -> void:
	# Let the editor finish coming up before anything is asked of it.
	await get_tree().create_timer(2.0).timeout
	print("SHOTS: starting")
	await _verify_gestures()

	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	var written: Array = []

	for entry in SHOTS:
		var shot := entry as Dictionary
		print("SHOTS: shooting %s" % str(shot["name"]))
		var ok: bool = await _shoot(shot)
		if ok:
			written.append(str(shot["name"]))
		else:
			printerr("SHOTS: %s FAILED" % str(shot["name"]))

	print("SHOTS: wrote %d/%d -> %s" % [written.size(), SHOTS.size(), SHOT_DIR])
	for name in written:
		print("SHOTS:   %s" % name)
	print("SHOTS: DONE")
	get_tree().quit(0 if written.size() == SHOTS.size() else 1)


## Drives the builder into one state and saves its window.
##
## The builder is TORN DOWN AND REOPENED for every shot rather than nudged from the last one. A
## state reached by a path is a state that carries whatever the path left behind -- a selection
## that never cleared, a menu still open -- and the whole point of a reference shot is that it
## shows one thing.
## Drives the three gestures the owner reports as broken, THROUGH THE REAL WINDOW.
##
## Every headless check of these passes, because a headless check calls `_gui_input` directly and
## so proves only that the handler is correct -- never that Godot routes an event to it. This
## pushes input at the Window, which is the path a person's mouse takes.
func _verify_gestures() -> void:
	# START FROM NO SAVED LAYOUT. Each run drags a card and the store remembers it, so run after
	# run the fixture creeps across the canvas and eventually off the bottom of it.
	var Layout = preload("res://addons/reactive_ui_toolkit_editor/builder/canvas/builder_canvas_layout.gd")
	Layout.clear_all()
	var builder = _open_builder(FIXTURE)
	if builder == null:
		print("SHOTS: GESTURES: could not open the builder")
		return
	await get_tree().create_timer(SETTLE_SECONDS).timeout
	var canvas = builder.canvas()
	var graph = builder.graph
	if graph == null or graph.cards.is_empty():
		print("SHOTS: GESTURES: no cards")
		_close_builder()
		return

	# EVERY LAYER, because the gestures are hit-tested per LOD and the layer the user lands in by
	# default is not the one a framed card happens to sit at.
	for preset in Metrics.LAYER_PRESETS:
		await _gestures_at(builder, canvas, float(preset))
	_close_builder()


## Drives click / menu / drag on card 0 at one zoom, with the card centred so nothing lands off
## the canvas.
func _gestures_at(builder, canvas, want_zoom: float) -> void:
	var graph = builder.graph
	var card = graph.cards[0]
	var lod = Metrics.lod_of(want_zoom)
	var size := Vector2(Metrics.card_width_for(lod), Metrics.drawn_height(card, lod))
	var centre := Vector2(card.x, card.y) + size * 0.5
	canvas.set_camera(canvas.size * 0.5 - centre * want_zoom, want_zoom)
	await get_tree().process_frame
	await get_tree().process_frame

	var rect: Rect2 = canvas.get_global_rect()
	var title_local := Metrics.world_to_screen(
		Vector2(card.x + 40.0, card.y + 8.0), canvas.camera, canvas.zoom)

	var saw := {"row": 0, "card": 0, "click": 0}
	var c1 := func(_c, _s, _i, _p): saw["row"] += 1
	var c2 := func(_c, _s, _i): saw["click"] += 1
	canvas.row_context_requested.connect(c1)
	canvas.row_clicked.connect(c2)

	var markup := {}
	var top_at := Metrics.HEADER_H
	for entry in Metrics.section_stack(card):
		var e := entry as Dictionary
		if not Metrics.draws_section(int(e["section"]), lod):
			continue
		if int(e["section"]) == int(Metrics.Section.MARKUP):
			markup = { "top": top_at, "lead": e["lead"], "row_height": e["row_height"] }
		top_at += float(e["height"])

	var click_result := "n/a (this layer draws no markup)"
	var menu_result := "n/a"
	if not markup.is_empty():
		var row_local := Metrics.world_to_screen(Vector2(card.x, card.y) + Vector2(20,
			float(markup["top"]) + float(markup["lead"])
				+ float(markup["row_height"]) * 0.5), canvas.camera, canvas.zoom)
		var row_pt: Vector2 = rect.position + row_local
		if not rect.has_point(row_pt):
			click_result = "SKIPPED (row off canvas)"
		else:
			_push(_mb(row_pt, true)); await get_tree().process_frame
			_push(_mb(row_pt, false)); await get_tree().process_frame
			click_result = "OK" if saw["click"] > 0 else "BROKEN"
			_push(_mb(row_pt, true, MOUSE_BUTTON_RIGHT)); await get_tree().process_frame
			_push(_mb(row_pt, false, MOUSE_BUTTON_RIGHT)); await get_tree().process_frame
			menu_result = "OK" if saw["row"] > 0 else "BROKEN"
			_dismiss_popups(builder)
			await get_tree().process_frame

	var before := Vector2(card.x, card.y)
	var at: Vector2 = rect.position + title_local
	_push(_mb(at, true)); await get_tree().process_frame
	for step in [Vector2(25, 15), Vector2(60, 35), Vector2(100, 60)]:
		_push(_mm(at + step)); await get_tree().process_frame
	_push(_mb(at + Vector2(100, 60), false)); await get_tree().process_frame
	var drag_result := "OK" if Vector2(card.x, card.y) != before else "BROKEN"
	card.x = before.x
	card.y = before.y

	canvas.row_context_requested.disconnect(c1)
	canvas.row_clicked.disconnect(c2)
	print("SHOTS: GESTURES: zoom %.2f (%s)  row click=%s  row menu=%s  card drag=%s"
		% [want_zoom, ["Architecture", "Cards", "Edit"][int(lod)],
		   click_result, menu_result, drag_result])


## Hides any popup the previous step opened. An embedded popup grabs input, so the next gesture
## would land on the menu instead of the canvas.
func _dismiss_popups(node: Node) -> void:
	for child in node.get_children():
		if child is PopupMenu and (child as PopupMenu).visible:
			(child as PopupMenu).hide()
		_dismiss_popups(child)


func _push(event: InputEvent) -> void:
	if _window != null:
		_window.push_input(event, true)


func _mb(at: Vector2, down: bool, button := MOUSE_BUTTON_LEFT) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = down
	e.position = at
	e.global_position = at
	return e


func _mm(at: Vector2) -> InputEventMouseMotion:
	var e := InputEventMouseMotion.new()
	e.position = at
	e.global_position = at
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	return e


func _shoot(shot: Dictionary) -> bool:
	_close_builder()
	await get_tree().process_frame

	var want_tree := bool(shot.get("tree", true))
	var focus := str(shot.get("focus", FIXTURE))
	var builder = _open_builder(focus if want_tree else "")
	if builder == null:
		return false
	var win := _window

	if want_tree:
		await get_tree().create_timer(SETTLE_SECONDS).timeout
		var canvas = builder.canvas()
		canvas.fit_to_view()
		await get_tree().process_frame
		# Put the CARD BOUNDING BOX in the middle of the canvas at this shot's zoom.
		#
		# Computed here rather than taken from `fit_to_view`: the fitted camera frames the graph at
		# the zoom it was fitted FOR, and the camera is a screen-space offset, so re-using it at any
		# other zoom slides the graph off to one side. A shot of empty canvas beside two cards is a
		# picture of this harness, not of the builder.
		var want_zoom := float(shot.get("zoom", 1.0))
		canvas.set_camera(_centred_camera(canvas, want_zoom), want_zoom)
		var select := str(shot.get("select", ""))
		if not select.is_empty():
			builder.select_module(select)
			var graph = builder.graph
			if graph != null:
				canvas.select_card(graph.index_of(select))
		await get_tree().create_timer(1.0).timeout

	match str(shot.get("menu", "")):
		"card":
			_open_card_menu(builder, str(shot.get("select", FIXTURE)))
		"library":
			_open_library_create(builder)
	if not str(shot.get("menu", "")).is_empty():
		await get_tree().create_timer(0.6).timeout

	# Three frames for the reconciler to commit and the containers to lay out, then a FORCED draw.
	#
	# Forced, not awaited on `frame_post_draw`: the editor runs in low-processor mode and simply
	# stops redrawing when nothing is happening, so waiting for a draw that idle has no reason to
	# perform waits forever. `force_draw` makes the frame instead of hoping for one.
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	RenderingServer.force_draw()

	var tex := win.get_texture()
	if tex == null:
		return false
	var image := tex.get_image()
	if image == null:
		return false
	var path := SHOT_DIR.path_join(str(shot["name"]) + ".png")
	return image.save_png(path) == OK


## The camera that centres the whole card bounding box on the canvas at `zoom`.
func _centred_camera(canvas, zoom: float) -> Vector2:
	var graph = canvas.graph
	if graph == null or graph.cards.is_empty():
		return Vector2.ZERO
	var lod = Metrics.lod_of(zoom)
	var card_w: float = Metrics.card_width_for(lod)
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for card in graph.cards:
		var height: float = Metrics.card_height(card)
		low.x = minf(low.x, card.x)
		low.y = minf(low.y, card.y)
		high.x = maxf(high.x, card.x + card_w)
		high.y = maxf(high.y, card.y + height)
	var world_centre := (low + high) * 0.5
	return canvas.size * 0.5 - world_centre * zoom


## Builds the builder in a window this harness owns.
##
## NOT through the shipped plugin's menu entry, though that is the path a user takes. Reaching
## into the running plugin means finding it in the editor's node tree, and the editor's node tree
## is tens of thousands of nodes deep in windows that are not this one. The builder is the same
## Control either way -- what a shot is of is the builder, not the menu that opened it, and the
## menu entry has its own coverage.
func _open_builder(focus: String):
	var script := load("res://addons/reactive_ui_toolkit_editor/builder/chrome/builder_window.gd")
	if script == null:
		return null
	var control: Control = script.new()
	_window = Window.new()
	_window.title = "RUITK Builder"
	_window.size = SHOT_SIZE
	_window.wrap_controls = true
	# Popups are sub-windows of their own, and a sub-window is not part of this window's texture.
	# Embedded, they draw INSIDE it and a shot of a menu is a shot of the menu.
	_window.gui_embed_subwindows = true
	_window.add_child(control)
	EditorInterface.get_base_control().add_child(_window)
	_window.popup_centered()
	# An empty `focus` is the "nothing open yet" state: the window stands, the tree does not.
	if not focus.is_empty():
		control.open_tree(focus)
	return control


func _close_builder() -> void:
	if _window != null:
		_window.queue_free()
		_window = null


func _open_card_menu(builder, path: String) -> void:
	var canvas = builder.canvas()
	var at: Vector2 = canvas.global_position + canvas.size * 0.5
	builder.call("_open_card_menu", path, at)


func _open_library_create(builder) -> void:
	# Whatever the library offers for "create". If it offers nothing the shot is of the library as
	# it is, which is the honest picture and exactly what a comparison should catch.
	var library = builder.library_pane()
	for child in library.get_children():
		if child is PopupMenu:
			(child as PopupMenu).position = Vector2i(library.global_position + Vector2(40, 60))
			(child as PopupMenu).popup()
			return
	if library.has_method("open_create_menu"):
		library.call("open_create_menu")


## The shipped editor plugin instance, found by the script it runs.
func _builder_plugin() -> EditorPlugin:
	for child in get_tree().root.get_children():
		var found := _match_plugin(child)
		if found != null:
			return found
	return null


func _match_plugin(node: Node) -> EditorPlugin:
	if node is EditorPlugin:
		var script := (node as EditorPlugin).get_script()
		if script != null and str(script.resource_path).ends_with("reactive_ui_toolkit_editor/plugin.gd"):
			return node as EditorPlugin
	for child in node.get_children():
		var found := _match_plugin(child)
		if found != null:
			return found
	return null
