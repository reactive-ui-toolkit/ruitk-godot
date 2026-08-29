extends SceneTree
## Gestures, driven through the VIEWPORT.
##
## Every other check in this repo calls a handler or a model function directly -- `_gui_input`,
## `drop_library_entry`, `Metrics.row_hit` -- and that is why a canvas nobody could drag and menus
## that opened two hundred pixels from the pointer both sat behind a green run for days. A handler
## that works proves nothing about whether Godot routes an event to it, or about where the thing
## it opens ends up.
##
## So this pushes real `InputEvent`s at `root.push_input` and asserts the OUTCOME: the card moved,
## the menu opened, the menu opened WHERE THE CLICK WAS.
##
## It cannot replace looking at the thing. It is the floor below which looking is pointless.

const BuilderWindow = preload("res://addons/reactive_ui_toolkit_editor/builder/chrome/builder_window.gd")
const Workspace = preload("res://addons/reactive_ui_toolkit_editor/builder/document/builder_workspace.gd")
const Metrics = preload("res://addons/reactive_ui_toolkit_editor/builder/canvas/builder_canvas_metrics.gd")
const CanvasLayout = preload("res://addons/reactive_ui_toolkit_editor/builder/canvas/builder_canvas_layout.gd")

const ROOT := "res://tests/__builder_gesture_tmp/ui"
const APP := """import { Child } from "./child"

export App() -> RuitkVNode {
	var s = useState(0)
	return (
		<VBoxContainer>
			<Label text="hello" />
			<Child n={ s[0] } />
		</VBoxContainer>
	)
}
"""
const CHILD := """export Child(n: int = 0) -> RuitkVNode {
	return ( <Label text={ "n=%d" % n } /> )
}
"""

const ASSERTION_FLOOR := 71

var _fails := 0
var _passes := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	_test_the_recovery_offer_can_be_built()
	await _test_a_card_can_be_dragged()
	await _test_a_row_menu_opens_where_the_click_was()
	await _test_adding_an_attribute_reaches_the_buffer()
	await _test_a_moved_card_stays_moved()
	await _test_the_drawn_card_actually_moves()
	await _test_every_edit_reaches_the_card()
	await _test_the_header_band_is_what_is_drawn()
	await _test_the_builder_fills_the_window_it_is_in()
	await _test_an_attribute_run_gets_room_to_be_seen()
	await _test_a_card_drags_inside_a_real_window()
	await _test_a_pan_cannot_latch_on()
	await _test_a_foreign_drag_does_not_pan_the_canvas()
	await _test_every_band_of_a_card_moves_it_except_a_markup_row()

	print("")
	if _passes < ASSERTION_FLOOR:
		printerr("builder gestures: only %d of at least %d assertions ran -- something stopped early"
			% [_passes, ASSERTION_FLOOR])
		quit(1)
		return
	if _fails > 0:
		printerr("builder gestures: %d FAILURE(S) of %d assertions" % [_fails, _passes + _fails])
		quit(1)
		return
	print("builder gestures: ALL PASS (%d assertions)" % _passes)
	quit(0)


## A DRAG ON THE TITLE BAR MOVES THE CARD -- from either end of it.
##
## The left quarter of the title bar, which is where the name is and where a person grabs a card,
## was a second drag source claiming the same press: it handed Godot a module payload, Godot took
## the gesture over, and the card stopped after a few pixels while the drop reordered a markup row.
func _test_a_card_can_be_dragged() -> void:
	var w := _window()
	await _settle(w)
	var canvas = w.canvas()
	if w.graph.cards.is_empty():
		_ok(false, "the fixture projected cards")
		return

	var card = w.graph.cards[0]
	var lod := Metrics.lod_of(canvas.zoom)
	var width := Metrics.card_width_for(lod)

	# Bring the card into the middle of the canvas, so a probe cannot land off the viewport and
	# report a routing failure that is really an aiming failure.
	canvas.set_camera(Vector2(400, 200) - Vector2(card.x, card.y) * canvas.zoom, canvas.zoom)
	await _settle(w)

	for fraction in [0.08, 0.5, 0.9]:
		var before := Vector2(card.x, card.y)
		var at := _global_of(canvas, Vector2(card.x + width * fraction, card.y + 8.0))
		_ok(canvas.get_global_rect().has_point(at),
			"the probe at %d%% of the title bar is inside the canvas" % int(fraction * 100))
		await _drag(at, at + Vector2(90, 40))
		var after := Vector2(card.x, card.y)
		_ok(not before.is_equal_approx(after),
			"a drag at %d%% of the title bar MOVES the card (%s -> %s)"
				% [int(fraction * 100), before, after])

	w.queue_free()
	await process_frame


## A RIGHT-CLICK ON A MARKUP ROW OPENS THE ROW MENU, WHERE THE CLICK WAS.
##
## The menu was placed at `builder_screen + _canvas.position + at` -- and `_canvas.position` is the
## canvas's offset inside its immediate parent, which is (0, 0), while the canvas itself sits a
## couple of hundred pixels into the window. So every canvas menu opened that far up and to the
## left of the pointer, over another pane or off the window. It was opening; it was not opening
## anywhere the user was looking, which is the same thing as not opening.
func _test_a_row_menu_opens_where_the_click_was() -> void:
	var w := _window()
	await _settle(w)
	var canvas = w.canvas()
	if w.graph.cards.is_empty():
		_ok(false, "the fixture projected cards")
		return
	var card = w.graph.cards[0]
	var width := Metrics.card_width_for(Metrics.lod_of(canvas.zoom))
	canvas.set_camera(Vector2(300, 60) - Vector2(card.x, card.y) * canvas.zoom, canvas.zoom)
	await _settle(w)

	var markup_y := -1.0
	for entry in Metrics.section_stack(card):
		var spec := entry as Dictionary
		if int(spec["section"]) == int(Metrics.Section.MARKUP):
			markup_y = float(spec["top"]) + float(spec["lead"]) + float(spec["row_height"]) * 0.5
	_ok(markup_y > 0.0, "the card has a markup section to right-click")
	if markup_y <= 0.0:
		w.queue_free()
		return

	var row_local := Vector2(card.x + width * 0.5, card.y + markup_y)
	var canvas_local := Metrics.world_to_screen(row_local, canvas.camera, canvas.zoom)
	var at := canvas.get_global_rect().position + canvas_local
	_ok(canvas.get_global_rect().has_point(at), "the row probe is inside the canvas")

	await _click(at, MOUSE_BUTTON_RIGHT)
	await _settle(w)

	_ok(w._row_menu.visible, "right-clicking a markup row opens the row menu")
	var labels := PackedStringArray()
	for i in w._row_menu.item_count:
		labels.append(w._row_menu.get_item_text(i))
	_ok(labels.has("Add attribute..."), "and it offers Add attribute... (%s)" % ", ".join(labels))

	# WHERE. Asserted on the PLACEMENT the window computes, not on the popup's own position: a
	# Popup is a Window and Godot clamps it to the screen, which headless reports as 64x64, so the
	# read-back says (0, 0) whatever was asked for. The placement is the thing that was wrong.
	var placed := w._canvas_at(canvas_local)
	var old_way: Vector2 = w._screen_at(canvas.position + canvas_local)
	_ok(placed.distance_to(at) < 2.0,
		"the menu is placed AT the click (%s vs the click at %s)" % [placed, at])
	_ok(placed.distance_to(old_way) > 8.0,
		"and NOT where the old placement put it (%s) -- `_canvas.position` is (0, 0) while the "
			% old_way + "canvas sits at %s" % canvas.get_global_rect().position)

	w._row_menu.hide()
	w.queue_free()
	await process_frame


# ── Rig ──────────────────────────────────────────────────────────────────────────────

func _window() -> BuilderWindow:
	# A CARD MOVED IN ONE TEST IS SAVED, and `user://` outlives the window -- so the next test
	# opened on positions the last one dragged to, its probes landed off the canvas, and the
	# assertions behind them SKIPPED rather than failed. A suite that quietly stops checking is
	# the failure this whole file exists to stop happening.
	CanvasLayout.clear_all()
	var w := BuilderWindow.new()
	w.size = Vector2(1400, 800)
	root.add_child(w)
	var ws := Workspace.new()
	ws.create_new(ROOT.path_join("child.guitkx"), CHILD)
	ws.create_new(ROOT.path_join("app.guitkx"), APP)
	w.workspace = ws
	w.preview.workspace = ws
	# THE LEDGER RESOLVES IDENTITY THROUGH THIS. Without it an entry cannot name the module it
	# describes, and undo walks back nothing -- which is a broken FIXTURE that reads exactly like
	# a broken undo.
	w.ledger.id_of = func(path: String) -> String:
		var module = w.workspace.try_get(path)
		return module.id if module != null else ""
	w.reproject()
	w.select_module(ROOT.path_join("app.guitkx"))
	return w


## Enough frames for the layout, a sliced commit and the canvas's settle pass.
func _settle(_w) -> void:
	for i in 10:
		await process_frame


func _global_of(canvas, world: Vector2) -> Vector2:
	return canvas.get_global_rect().position \
		+ Metrics.world_to_screen(world, canvas.camera, canvas.zoom)


func _drag(from: Vector2, to: Vector2) -> void:
	root.push_input(_mb(from, true), true)
	await process_frame
	for i in range(1, 13):
		root.push_input(_mm(from.lerp(to, float(i) / 12.0), MOUSE_BUTTON_MASK_LEFT), true)
		await process_frame
	root.push_input(_mb(to, false), true)
	await process_frame


func _click(at: Vector2, button := MOUSE_BUTTON_LEFT) -> void:
	root.push_input(_mb(at, true, button), true)
	await process_frame
	root.push_input(_mb(at, false, button), true)
	await process_frame


func _mb(at: Vector2, down: bool, button := MOUSE_BUTTON_LEFT) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.position = at
	e.global_position = at
	e.button_index = button
	e.pressed = down
	return e


func _mm(at: Vector2, mask := 0) -> InputEventMouseMotion:
	var e := InputEventMouseMotion.new()
	e.position = at
	e.global_position = at
	e.button_mask = mask
	return e


func _ok(cond: bool, what: String) -> void:
	if cond:
		_passes += 1
	else:
		_fails += 1
		printerr("  FAIL  " + what)


## PICKING AN ATTRIBUTE PUTS IT IN THE BUFFER.
##
## The menu opens, it lists the right properties, and the pick has to arrive somewhere. Every
## check until now stopped at "the menu has items", which is true of a menu wired to nothing.
func _test_adding_an_attribute_reaches_the_buffer() -> void:
	var w := _window()
	await _settle(w)
	var path := ROOT.path_join("app.guitkx")
	var canvas = w.canvas()
	if w.graph.cards.is_empty():
		_ok(false, "the fixture projected cards")
		return
	var card = w.graph.card_of(path)
	_ok(card != null, "the app card is on the canvas")
	if card == null:
		w.queue_free()
		return

	# The row the menu will be about: the component's own return root.
	var row_index: int = Metrics.first_element_row(card)
	_ok(row_index >= 0, "the card has an element row")
	w._on_row_context(w.graph.index_of(path), Metrics.Section.MARKUP, row_index, Vector2(40, 40))
	await _settle(w)
	_ok(w._row_menu.item_count > 0, "the row menu was built")

	# THE MENU ITEM, through the signal a click emits.
	w._row_menu.id_pressed.emit(BuilderWindow.RowMenuId.ADD_ATTRIBUTE)
	await _settle(w)
	_ok(w._search_menu.visible, "Add attribute... opens the attribute menu")

	var before: String = w.workspace.try_get(path).buffer_text
	var pressed := _press_first_row(w._search_menu)
	_ok(not pressed.is_empty(), "the attribute menu has a row to pick (%s)" % pressed)
	await _settle(w)

	var after: String = w.workspace.try_get(path).buffer_text
	_ok(after != before, "picking it CHANGES THE BUFFER (picked %s)" % pressed)
	if after != before:
		_ok(after.contains(pressed), "and the buffer carries the attribute that was picked")
	else:
		_ok(false, "the buffer is untouched -- the pick reached nothing")

	w.queue_free()
	await process_frame


## A MOVED CARD STAYS MOVED, across the reprojection that follows every edit.
##
## A drag that visibly works and then snaps back on the next projection is indistinguishable from
## a drag that never worked, and it is the projection that has the last word.
func _test_a_moved_card_stays_moved() -> void:
	var w := _window()
	await _settle(w)
	var canvas = w.canvas()
	if w.graph.cards.is_empty():
		_ok(false, "the fixture projected cards")
		return
	var card = w.graph.cards[0]
	var width := Metrics.card_width_for(Metrics.lod_of(canvas.zoom))
	canvas.set_camera(Vector2(400, 200) - Vector2(card.x, card.y) * canvas.zoom, canvas.zoom)
	await _settle(w)

	var at := _global_of(canvas, Vector2(card.x + width * 0.5, card.y + 8.0))
	await _drag(at, at + Vector2(120, 70))
	var dropped := Vector2(card.x, card.y)
	_ok(true, "dragged to %s" % dropped)

	w.reproject()
	await _settle(w)
	var again = w.graph.cards[0]
	_ok(Vector2(again.x, again.y).is_equal_approx(dropped),
		"the card is still where it was dropped after a reprojection (%s vs %s)"
			% [Vector2(again.x, again.y), dropped])

	w.queue_free()
	await process_frame


## Presses the first pickable row in a search menu and returns its label.
func _press_first_row(menu) -> String:
	for child in menu._list.get_children():
		if child is Button:
			var label := str((child as Button).text).strip_edges()
			if label.is_empty():
				continue
			(child as Button).pressed.emit()
			# The label carries its detail after a run of spaces; the name is the first word.
			return label.split(" ")[0]
	return ""


## THE TITLE BAR THE MOUSE SEES IS THE HEADER THAT IS DRAWN.
##
## `HEADER_H` is a prediction, and the whole card-drag gesture is derived from it: a press below
## the constant but inside the visible header is not a title-bar press, so it falls through to
## whatever the model thinks is under it and the card does not move. Rows have been measured
## against the view since CANVAS-01; this is the last part of a card that was only predicted.
func _test_the_header_band_is_what_is_drawn() -> void:
	var w := _window()
	await _settle(w)
	var canvas = w.canvas()
	if w.graph.cards.is_empty():
		_ok(false, "the fixture projected cards")
		return

	for preset in [0.75, 1.25]:
		# AT THE CARD. A camera that leaves it outside the cull window renders the PLACEHOLDER,
		# whose header fills the whole card -- which is a measurement of something else.
		canvas.set_camera(Vector2(300, 150) - Vector2(w.graph.cards[0].x, w.graph.cards[0].y) * preset,
			preset)
		await _settle(w)
		var measured := canvas.measured_header(0)
		_ok(measured > 0.0, "the header is measured at zoom %s (%s)" % [preset, measured])
		if measured > 0.0:
			var drift: float = absf(measured - Metrics.HEADER_H)
			_ok(drift < 6.0,
				"and HEADER_H (%s) is within 6 units of it at zoom %s -- drift %s"
					% [Metrics.HEADER_H, preset, drift])

	w.queue_free()
	await process_frame


## THE BUILDER FILLS THE WINDOW THE PLUGIN PUTS IT IN, AND KEEPS FILLING IT.
##
## Every check in this repo builds the builder as a child of the test root with an explicit size.
## The PLUGIN does something else: it adds it to a `Window`. A Control added to a Window with
## default anchors takes its combined minimum size and never follows the window again -- so the
## panes lay out for a rectangle bigger than the window, draw past its edges, and everything
## outside it becomes unclickable while the canvas's rect stops agreeing with what is on screen.
## Nothing exercised the plugin's own path, so nothing could see it.
func _test_the_builder_fills_the_window_it_is_in() -> void:
	CanvasLayout.clear_all()
	var host := Window.new()
	host.size = Vector2i(1200, 700)
	host.wrap_controls = false
	root.add_child(host)

	var w := BuilderWindow.new()
	host.add_child(w)
	w.set_anchors_preset(Control.PRESET_FULL_RECT)
	var ws := Workspace.new()
	ws.create_new(ROOT.path_join("child.guitkx"), CHILD)
	ws.create_new(ROOT.path_join("app.guitkx"), APP)
	w.workspace = ws
	w.preview.workspace = ws
	w.reproject()
	w.select_module(ROOT.path_join("app.guitkx"))
	for i in 10:
		await process_frame

	_ok(w.size.x >= host.size.x - 1 and w.size.y >= host.size.y - 1,
		"the builder fills the window (%s in %s)" % [w.size, host.size])
	var canvas = w.canvas()
	var window_rect := Rect2(Vector2.ZERO, Vector2(host.size))
	_ok(window_rect.encloses(canvas.get_global_rect()),
		"and the canvas is INSIDE it (%s in %s)" % [canvas.get_global_rect(), window_rect])

	# AND IT FOLLOWS A RESIZE -- down to what the CONTENT needs, which is the floor the plugin
	# sets the window minimum from. Below that the panes overflow rather than reflow, which is
	# why the minimum is asked of the layout instead of guessed at.
	var floor_size := w.get_combined_minimum_size()
	host.size = Vector2i(maxi(1000, int(ceil(floor_size.x))), maxi(600, int(ceil(floor_size.y))))
	for i in 8:
		await process_frame
	_ok(w.size.x <= host.size.x + 1 and w.size.y <= host.size.y + 1,
		"the builder followed the window down to %s (it is %s)" % [host.size, w.size])
	# NOT asserted here: that the canvas stays INSIDE a narrowed window. It does not -- the three
	# columns carry fixed minimums (260 left, 380 right) and the middle does not give width back,
	# so below about 1160 the canvas overflows the window's right edge. That is a real defect and
	# a separate one; writing an assertion that passes over it would be worse than leaving it named
	# here. What this test is for is the plugin path: the builder filling its window at all.
	_ok(canvas.get_global_rect().size.x > 0.0 and canvas.get_global_rect().size.y > 0.0,
		"and the canvas still has area to click on")

	w.queue_free()
	host.queue_free()
	await process_frame


## AN ATTRIBUTE THAT WAS WRITTEN IS AN ATTRIBUTE THAT IS SHOWN.
##
## The tag Label was EXPAND_FILL and the attribute run SHRINK_END, and BOTH carried `clip_text`,
## which drops a Label's minimum width to ZERO. The tag claimed the whole row and the attributes
## were allocated ONE PIXEL: built, measured, laid out and invisible. Every attribute the builder
## wrote went into the file correctly and was then missing from the card that wrote it -- so the
## gesture looked broken while the edit had worked perfectly.
##
## Asserted on the WIDTH, because the node existing was always true.
func _test_an_attribute_run_gets_room_to_be_seen() -> void:
	var w := _window_with("export App() -> RuitkVNode {\n\treturn ( <VBoxContainer alignment={ 0 } /> )\n}\n")
	await _settle(w)
	var canvas = w.canvas()
	var card = w.graph.cards[0]
	canvas.set_camera(Vector2(300, 150) - Vector2(card.x, card.y) * 1.25, 1.25)
	await _settle(w)

	_ok(Metrics.shows_attributes(Metrics.lod_of(canvas.zoom)), "Layer 3 draws attribute runs")
	var row = card.markup[Metrics.first_element_row(card)]
	_ok(row.attrs_text != "", "the projection carries the attribute (%s)" % row.attrs_text)

	var node := canvas._find_named(canvas._cards, "row-3-%d" % Metrics.first_element_row(card))
	_ok(node != null, "the row is on the canvas")
	if node == null:
		w.queue_free()
		return
	# RETURNED, not collected through a lambda: GDScript captures by value, so a closure writing
	# to an outer local writes to a copy and every width comes back zero.
	var found := _widths(node, row.attrs_text)
	var tag_width: float = found.y
	var widest: float = found.x
	_ok(tag_width > 8.0, "the tag has width (%s)" % tag_width)
	_ok(widest > 8.0,
		"AND SO DOES THE ATTRIBUTE RUN (%s) -- it used to be allocated one pixel" % widest)

	w.queue_free()
	await process_frame


## The rendered widths inside a markup row, as (attribute run, tag).
func _widths(node: Node, attrs: String) -> Vector2:
	var out := Vector2.ZERO
	for child in node.get_children():
		if child is Label:
			var label := child as Label
			if str(label.text) == attrs:
				out.x = maxf(out.x, label.size.x)
			elif str(label.text).strip_edges().begins_with("<"):
				out.y = maxf(out.y, label.size.x)
		var deeper := _widths(child, attrs)
		out.x = maxf(out.x, deeper.x)
		out.y = maxf(out.y, deeper.y)
	return out


## A CARD DRAGS INSIDE A REAL WINDOW -- the combination the plugin actually ships.
##
## Every drag check until now built the builder as a child of the test root. The plugin puts it in
## a `Window`, which is its own Viewport with its own input routing, and that is the arrangement
## that was broken.
func _test_a_card_drags_inside_a_real_window() -> void:
	CanvasLayout.clear_all()
	var host := Window.new()
	host.size = Vector2i(1500, 900)
	host.wrap_controls = false
	root.add_child(host)

	var w := BuilderWindow.new()
	host.add_child(w)
	w.set_anchors_preset(Control.PRESET_FULL_RECT)
	var ws := Workspace.new()
	ws.create_new(ROOT.path_join("child.guitkx"), CHILD)
	ws.create_new(ROOT.path_join("app.guitkx"), APP)
	w.workspace = ws
	w.preview.workspace = ws
	w.reproject()
	w.select_module(ROOT.path_join("app.guitkx"))
	for i in 12:
		await process_frame

	var canvas = w.canvas()
	var card = w.graph.cards[0]
	var width := Metrics.card_width_for(Metrics.lod_of(canvas.zoom))
	canvas.set_camera(Vector2(360, 180) - Vector2(card.x, card.y) * canvas.zoom, canvas.zoom)
	for i in 10:
		await process_frame

	var at := canvas.get_global_rect().position \
		+ Metrics.world_to_screen(Vector2(card.x + width * 0.5, card.y + 8.0),
			canvas.camera, canvas.zoom)
	_ok(canvas.get_global_rect().has_point(at), "the probe is on the canvas inside the window")

	var before := Vector2(card.x, card.y)
	host.push_input(_mb(at, true), true)
	await process_frame
	for i in range(1, 13):
		host.push_input(_mm(at.lerp(at + Vector2(110, 60), float(i) / 12.0),
			MOUSE_BUTTON_MASK_LEFT), true)
		await process_frame
	host.push_input(_mb(at + Vector2(110, 60), false), true)
	await process_frame

	_ok(not before.is_equal_approx(Vector2(card.x, card.y)),
		"a drag INSIDE THE WINDOW moves the card (%s -> %s)" % [before, Vector2(card.x, card.y)])

	w.queue_free()
	host.queue_free()
	await process_frame


## A builder over one module of the caller's own source.
func _window_with(source: String) -> BuilderWindow:
	CanvasLayout.clear_all()
	var w := BuilderWindow.new()
	w.size = Vector2(1400, 800)
	root.add_child(w)
	var ws := Workspace.new()
	ws.create_new(ROOT.path_join("app.guitkx"), source)
	w.workspace = ws
	w.preview.workspace = ws
	w.reproject()
	w.select_module(ROOT.path_join("app.guitkx"))
	return w


## A PAN CANNOT SURVIVE THE GESTURE THAT STARTED IT.
##
## `_panning` was cleared on the LEFT RELEASE -- and Godot CONSUMES that release to complete a
## drop, so a canvas crossed by any drag never saw it and the flag stayed true FOREVER. From then
## on every mouse motion panned the canvas, including the ones meant to move a card: one gesture
## breaking every gesture after it, which is exactly what it looked like from the outside.
func _test_a_pan_cannot_latch_on() -> void:
	var w := _window()
	await _settle(w)
	var canvas = w.canvas()

	# Put it in the state a consumed release leaves behind.
	canvas._panning = true
	canvas._press_seen = true
	canvas._pan_from = Vector2(10, 10)
	canvas.notification(Control.NOTIFICATION_DRAG_END)
	_ok(not canvas._panning, "a drag ending anywhere cancels a pan the canvas was left holding")

	canvas._panning = true
	canvas.notification(Control.NOTIFICATION_DRAG_BEGIN)
	_ok(not canvas._panning, "and a drag beginning cancels it too")
	_ok(canvas._moving < 0, "with no card left half-moved")
	_ok(not canvas._press_seen, "and no press remembered from before the drag")

	w.queue_free()
	await process_frame


## A DRAG THAT BEGAN SOMEWHERE ELSE DOES NOT PAN THE CANVAS IT CROSSES.
##
## Dragging a library entry onto the canvas delivered motion with the button held and a
## `_press_index` of -1 left over from the last release -- which the arming read as "pressed on
## empty canvas". The canvas scrolled out from under the drop the user was aiming.
func _test_a_foreign_drag_does_not_pan_the_canvas() -> void:
	var w := _window()
	await _settle(w)
	var canvas = w.canvas()
	var before: Vector2 = canvas.camera

	# No press was ever delivered here: this is what a drag from the library looks like.
	canvas._press_seen = false
	canvas._press_index = -1
	for i in range(1, 10):
		canvas._handle_motion(_mm(Vector2(200 + i * 12, 150 + i * 6), MOUSE_BUTTON_MASK_LEFT))
	_ok(canvas.camera.is_equal_approx(before),
		"the camera did not move under a drag the canvas never started (%s -> %s)"
			% [before, canvas.camera])
	_ok(not canvas._panning, "and no pan was armed")

	# A press the canvas DID see, on empty space, still pans -- that is how you move around.
	var empty: Vector2 = canvas.get_global_rect().position + canvas.size - Vector2(12, 12)
	await _drag(empty, empty - Vector2(90, 50))
	_ok(not canvas.camera.is_equal_approx(before),
		"but a drag on empty canvas the canvas DID see still pans it")

	w.queue_free()
	await process_frame


## EVERY PART OF A CARD MOVES IT, EXCEPT A MARKUP ROW.
##
## The motion handler stood down for ANY row under the press, while only a MARKUP row ever
## produced a drag payload. So a press on the signature line, an import row, a hook chip, or the
## part of the header below `HEADER_H` deferred to a drag-and-drop that never started: the card
## did not move, the canvas did not pan, and the press did nothing whatever. Which is precisely
## what "dragging the card does not work" looks like from the outside.
##
## Driven at zoom 2.0, because that is where the drawn header runs past the constant the band was
## derived from -- the case that made the header itself unusable as a handle.
func _test_every_band_of_a_card_moves_it_except_a_markup_row() -> void:
	var w := _window()
	await _settle(w)
	var canvas = w.canvas()
	var card = w.graph.cards[0]
	canvas.set_camera(Vector2(420, 240) - Vector2(card.x, card.y) * 2.0, 2.0)
	await _settle(w)
	var width := Metrics.card_width_for(Metrics.lod_of(canvas.zoom))

	# The header, top and bottom: the bottom is the part below HEADER_H that the measured band
	# has to cover, and the part a person actually grabs.
	for offset in [6.0, Metrics.HEADER_H - 4.0, canvas.measured_header(0) - 2.0]:
		if offset <= 0.0:
			continue
		var before := Vector2(card.x, card.y)
		# RE-CENTRED FIRST. Each probe drags the card, so the next one has to be aimed afresh --
		# otherwise the card walks out of the viewport and the probes land on nothing.
		canvas.set_camera(Vector2(120, 120) - Vector2(card.x, card.y) * canvas.zoom, canvas.zoom)
		await _settle(w)
		var at := _global_of(canvas, Vector2(card.x + width * 0.5, card.y + offset))
		_ok(canvas.get_global_rect().has_point(at),
			"the header probe at %s is on the canvas (%s in %s)"
				% [offset, at, canvas.get_global_rect()])
		if not canvas.get_global_rect().has_point(at):
			continue
		await _drag(at, at + Vector2(70, 45))
		_ok(not before.is_equal_approx(Vector2(card.x, card.y)),
			"a press %s units into the header MOVES the card" % offset)

	# A NON-MARKUP row -- the signature line -- is not a drag payload, so it moves the card too.
	var stack: Array = Metrics.section_stack(card)
	for entry in stack:
		var spec := entry as Dictionary
		var section := int(spec["section"])
		if section == int(Metrics.Section.MARKUP):
			continue
		var y := float(spec["top"]) + float(spec["lead"]) + float(spec["row_height"]) * 0.5
		var before2 := Vector2(card.x, card.y)
		canvas.set_camera(Vector2(120, 120) - Vector2(card.x, card.y) * canvas.zoom, canvas.zoom)
		await _settle(w)
		var at2 := _global_of(canvas, Vector2(card.x + width * 0.5, card.y + y))
		_ok(canvas.get_global_rect().has_point(at2),
			"the section-%d probe is on the canvas" % section)
		if not canvas.get_global_rect().has_point(at2):
			continue
		_ok(not canvas._would_drag_a_row(0, at2 - canvas.get_global_rect().position),
			"section %d is not a row this canvas drags" % section)
		await _drag(at2, at2 + Vector2(60, 35))
		_ok(not before2.is_equal_approx(Vector2(card.x, card.y)),
			"so a press in section %d moves the card" % section)
		break

	# A MARKUP row IS a payload, so it belongs to the drop protocol and must NOT move the card.
	var markup_y := -1.0
	for entry in stack:
		var spec := entry as Dictionary
		if int(spec["section"]) == int(Metrics.Section.MARKUP):
			markup_y = float(spec["top"]) + float(spec["lead"]) + float(spec["row_height"]) * 0.5
	if markup_y > 0.0:
		canvas.set_camera(Vector2(120, 120) - Vector2(card.x, card.y) * canvas.zoom, canvas.zoom)
		await _settle(w)
		var at3 := _global_of(canvas, Vector2(card.x + width * 0.5, card.y + markup_y))
		if canvas.get_global_rect().has_point(at3):
			_ok(canvas._would_drag_a_row(0, at3 - canvas.get_global_rect().position),
				"a markup row IS a row this canvas drags")
			var before3 := Vector2(card.x, card.y)
			await _drag(at3, at3 + Vector2(60, 35))
			_ok(before3.is_equal_approx(Vector2(card.x, card.y)),
				"and dragging one does NOT move the card -- it re-parents the row")

	w.queue_free()
	await process_frame


## THE RECOVERY OFFER CAN ACTUALLY BE BUILT.
##
## `peek()` returns `modules` as a COUNT and the offer read it as a LIST -- an invalid cast that
## threw on every open with work journalled. So the one feature whose whole job is handing back a
## crashed session's work crashed instead, every single time, and the next Save cleared what it
## had been holding. It was never once seen to run.
func _test_the_recovery_offer_can_be_built() -> void:
	var Journal = load("res://addons/reactive_ui_toolkit_editor/builder/document/builder_journal.gd")
	var ws := Workspace.new()
	ws.create_new(ROOT.path_join("app.guitkx"), APP)
	Journal.capture(ws, "just now")
	var pending: Dictionary = Journal.peek()
	_ok(not pending.is_empty(), "a journalled session is offered back")
	_ok(pending.has("paths"), "and the offer can NAME what it is holding")
	var listed: PackedStringArray = pending.get("paths", PackedStringArray())
	_ok(listed.size() > 0 or int(pending.get("modules", 0)) > 0,
		"with something to show (%d path(s), %d module(s))"
			% [listed.size(), int(pending.get("modules", 0))])
	Journal.clear()


## THE CARD ON SCREEN MOVES, not just the number in the model.
##
## Every drag check in this file asserted `card.x` -- the MODEL -- and the model was never the
## problem: the log from a real editor showed `moving=0` and the position updating on every
## motion. The card layer is a RECONCILED tree, `graph` is mutated in place, and with an unchanged
## revision every prop compared equal, so the reconciler correctly bailed out and the card never
## redrew. A drag that works perfectly and is invisible looks exactly like a drag that does
## nothing, and only the rendered node can tell them apart.
func _test_the_drawn_card_actually_moves() -> void:
	var w := _window()
	await _settle(w)
	var canvas = w.canvas()
	var card = w.graph.cards[0]
	var width := Metrics.card_width_for(Metrics.lod_of(canvas.zoom))
	canvas.set_camera(Vector2(200, 140) - Vector2(card.x, card.y) * canvas.zoom, canvas.zoom)
	await _settle(w)

	var node := canvas._find_named(canvas._cards, "card-0")
	_ok(node != null, "the card is a node on the canvas")
	if node == null:
		w.queue_free()
		return
	var drawn_before: Vector2 = node.get_global_rect().position
	var model_before := Vector2(card.x, card.y)

	var at := _global_of(canvas, Vector2(card.x + width * 0.5, card.y + 8.0))
	_ok(canvas.get_global_rect().has_point(at), "the probe is on the canvas")
	await _drag(at, at + Vector2(100, 60))
	await _settle(w)

	_ok(not model_before.is_equal_approx(Vector2(card.x, card.y)), "the model moved")
	var after := canvas._find_named(canvas._cards, "card-0")
	_ok(after != null, "the card is still a node afterwards")
	if after != null:
		_ok(not drawn_before.is_equal_approx(after.get_global_rect().position),
			"AND THE DRAWN CARD MOVED WITH IT (%s -> %s)"
				% [drawn_before, after.get_global_rect().position])

	w.queue_free()
	await process_frame


## EVERY EDIT REACHES THE CARD ON SCREEN.
##
## The card layer is reconciled and `graph` is mutated IN PLACE, so an edit that changes what a
## card should show, without changing any PROP the view is handed, is correctly bailed out of by
## the reconciler and never drawn. That is what hid the card drag for a week, and a drag is only
## one of the things that mutates the graph in place -- adding a row, adding a hook, deleting a
## row and undoing any of them all do.
##
## So each is asserted on the RENDERED TREE, which is the only place the difference shows.
func _test_every_edit_reaches_the_card() -> void:
	var w := _window()
	await _settle(w)
	var canvas = w.canvas()
	var path := ROOT.path_join("app.guitkx")
	var index: int = w.graph.index_of(path)
	_ok(index >= 0, "the app card is on the canvas")
	if index < 0:
		w.queue_free()
		return

	var markup_before := _count_named(canvas._cards, "row-3-")
	var body_before := _count_named(canvas._cards, "row-2-")
	var first_card := canvas._find_named(canvas._cards, "card-%d" % index)
	var card_height_before: float = first_card.size.y if first_card != null else 0.0
	_ok(markup_before > 0, "it draws markup rows to begin with (%d)" % markup_before)

	_section_note("adding an element")
	var card = w.graph.cards[index]
	var root_row: int = Metrics.first_element_row(card)
	w._menu_target = path
	w._menu_card = index
	w._menu_section = int(Metrics.Section.MARKUP)
	w._menu_row_index = root_row
	w._menu_row = card.markup[root_row]
	w._search_purpose = "child"
	w._on_search_picked("Button")
	await _settle(w)
	_ok(_count_named(canvas._cards, "row-3-") > markup_before,
		"the new element is DRAWN on the card (%d -> %d)"
			% [markup_before, _count_named(canvas._cards, "row-3-")])

	_section_note("adding a hook")
	var buffer_before: String = w.workspace.try_get(path).buffer_text
	w._on_card_add(index, "hook")
	await _settle(w)
	var buffer_after: String = w.workspace.try_get(path).buffer_text
	# THE MODEL AND THE VIEW, SEPARATELY. Which of the two failed is the whole question.
	_ok(buffer_after != buffer_before, "the hook reached the BUFFER")
	# MEASURED ON THE DRAWN CARD rather than by counting named nodes: a row created during an
	# update comes out with Godot's default name instead of the one the view gives it, so a name
	# count under-reports what is actually on screen. The card growing is the rendered consequence
	# of a chip appearing, and a model that changed without redrawing cannot fake it.
	var taller := canvas._find_named(canvas._cards, "card-%d" % index)
	_ok(taller != null and taller.size.y > card_height_before,
		"the card GREW when the hook was added (%s -> %s)"
			% [card_height_before, taller.size.y if taller != null else -1.0])

	_section_note("undo puts it back on the card")
	var buffer_before_undo: String = w.workspace.try_get(path).buffer_text
	w.undo()
	await _settle(w)
	_ok(w.workspace.try_get(path).buffer_text != buffer_before_undo,
		"undo reverts the BUFFER")
	_ok(w.graph.cards[index].body.size() < 2, "and the projection follows it")

	# NOT ASSERTED, BECAUSE IT IS NOT TRUE YET: that the card SHRINKS back. Measured on a real
	# render, the drawn card goes 190 -> 204 when a hook is added and stays at 204 when the add is
	# undone -- the growth reaches the view and the removal does not, and a fresh mount of the same
	# graph draws it correctly at 190. So the update path drops the removal somewhere in this
	# nesting (a chip inside an HFlowContainer inside a section). Writing an assertion that passed
	# over that would be the exact habit that hid the card drag for a week; it is named here and
	# in the commit instead, and it is the next thing to chase.

	_section_note("selection is visible")
	canvas.select_card(-1)
	await _settle(w)
	canvas.select_card(index)
	await _settle(w)
	_ok(canvas.selected == index, "the canvas holds the selection")
	var node := canvas._find_named(canvas._cards, "card-%d" % index)
	_ok(node != null, "and the selected card is still drawn")

	w.queue_free()
	await process_frame


## How many nodes under `node` have a name starting with `prefix`.
##
## THIS UNDER-REPORTS AFTER AN EDIT, and that is a finding rather than a flaw in the helper: a row
## node created during an update comes out carrying Godot's default name instead of the one the
## view gives it, so it stops being findable. `_collect_rows` finds rows BY NAME, which means the
## measured hit-test quietly degrades to the modelled one after every structural edit. Filed
## separately; it is why the assertions here measure the drawn CARD instead of counting rows.
func _count_named(node: Node, prefix: String) -> int:
	var found := 0
	for child in node.get_children():
		if child is Control and str(child.name).begins_with(prefix):
			found += 1
		found += _count_named(child, prefix)
	return found


func _names_of(node: Node, out: PackedStringArray) -> void:
	for child in node.get_children():
		if child is Control and str(child.name).begins_with("row-"):
			out.append(str(child.name))
		_names_of(child, out)


func _section_note(what: String) -> void:
	print("  -- ", what)
