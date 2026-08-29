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

const ASSERTION_FLOOR := 12

var _fails := 0
var _passes := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	await _test_a_card_can_be_dragged()
	await _test_a_row_menu_opens_where_the_click_was()

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
	var w := BuilderWindow.new()
	w.size = Vector2(1400, 800)
	root.add_child(w)
	var ws := Workspace.new()
	ws.create_new(ROOT.path_join("child.guitkx"), CHILD)
	ws.create_new(ROOT.path_join("app.guitkx"), APP)
	w.workspace = ws
	w.preview.workspace = ws
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
