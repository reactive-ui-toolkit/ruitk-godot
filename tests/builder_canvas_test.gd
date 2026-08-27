extends SceneTree
## Headless test suite for the RUITK Builder's CANVAS (checkpoint C3). Run:
##   godot --headless --path <project> --script res://tests/builder_canvas_test.gd
##
## Three layers, all provable without a renderer:
##
##   metrics -- the LOD bands, the card widths, the height model, the camera transform, the
##              cull, and the edge curve. Pure arithmetic, so pure assertions.
##   layout  -- what is remembered between sessions: positions keyed relative to the tree root,
##              the by-membership lookup, and following a rename.
##   host    -- the surface itself, rendering the DOGFOODED `canvas_view.guitkx` through the real
##              reconciler. Headless Godot has no renderer but it has the whole node tree, so the
##              assertions read real `Control` nodes: the LOD bands are visible as a card that
##              builds 36 nodes at one zoom and 600 at another.
##
## The pixels themselves are covered separately by `tests/builder_canvas_capture.gd`, which needs
## a window and so does not run here.

const Workspace = preload("res://addons/reactive_ui_toolkit_editor/builder/document/builder_workspace.gd")
const Service = preload("res://addons/reactive_ui_toolkit_editor/builder/canvas/builder_graph_service.gd")
const Graph = preload("res://addons/reactive_ui_toolkit_editor/builder/canvas/builder_graph.gd")
const Metrics = preload("res://addons/reactive_ui_toolkit_editor/builder/canvas/builder_canvas_metrics.gd")
const Layout = preload("res://addons/reactive_ui_toolkit_editor/builder/canvas/builder_canvas_layout.gd")
const Host = preload("res://addons/reactive_ui_toolkit_editor/builder/canvas/builder_canvas_host.gd")
const Edges = preload("res://addons/reactive_ui_toolkit_editor/builder/canvas/builder_canvas_edges.gd")
const Module = preload("res://addons/reactive_ui_toolkit_editor/builder/document/builder_module.gd")

const ROOT := "res://tests/__builder_canvas_tmp/app"
const VIEWPORT := Vector2(1280, 720)

var _fails := 0
var _passes := 0
var _graph: Graph = null


func _initialize() -> void:
	_run()


func _run() -> void:
	Layout.clear_all()
	_graph = _build_graph()

	_test_lod_bands()
	_test_camera()
	_test_height_model()
	_test_culling()
	_test_edge_geometry()
	_test_seeded_layout_does_not_overlap()
	_test_layout_round_trip()
	_test_layout_by_membership()
	_test_layout_repath()
	await _test_host_renders_each_lod()
	await _test_host_interaction()
	await _test_edge_overlay()
	_test_cleanup()

	print("")
	if _fails == 0:
		print("builder canvas: ALL PASS (%d assertions)" % _passes)
		quit(0)
	else:
		print("builder canvas: %d FAILURE(S) of %d assertions" % [_fails, _fails + _passes])
		quit(1)


func _check(ok: bool, what: String) -> void:
	if ok:
		_passes += 1
		return
	_fails += 1
	print("  FAIL  %s" % what)


func _eq(got: Variant, want: Variant, what: String) -> void:
	if str(got) == str(want):
		_passes += 1
		return
	_fails += 1
	print("  FAIL  %s\n        got:  %s\n        want: %s" % [what, got, want])


func _close(got: float, want: float, what: String, epsilon := 0.001) -> void:
	if absf(got - want) <= epsilon:
		_passes += 1
		return
	_fails += 1
	print("  FAIL  %s\n        got:  %f\n        want: %f" % [what, got, want])


func _section(title: String) -> void:
	print(title)


# ── Fixture ──────────────────────────────────────────────────────────────────────────

func _build_graph() -> Graph:
	var ws := Workspace.new()
	ws.create_new(ROOT.path_join("app.guitkx"),
		"import { Row } from \"./components/row/row\"\nimport { primary } from \"./app.style\"\nimport { Gone } from \"./nowhere\"\n\nexport App(level: int = 1) -> RuitkVNode {\n\tvar s = useState(0)\n\treturn (\n\t\t<VBoxContainer style={ primary }>\n\t\t\t<Row text=\"one\" />\n\t\t\t@if (level > 1) {\n\t\t\t\treturn (\n\t\t\t\t\t<Label text=\"deep\" />\n\t\t\t\t)\n\t\t\t}\n\t\t</VBoxContainer>\n\t)\n}\n")
	ws.create_new(ROOT.path_join("app.style.guitkx"), "export primary := { \"separation\": 6 }\n")
	ws.create_new(ROOT.path_join("components/row/row.guitkx"),
		"export Row(text: String = \"\") -> RuitkVNode {\n\treturn ( <Label text={ text } /> )\n}\n")
	ws.create_new(ROOT.path_join("loose.guitkx"),
		"export Loose() -> RuitkVNode {\n\treturn ( <Button text=\"loose\" /> )\n}\n")
	return Service.project(ws.modules(), ROOT.path_join("app.guitkx"))


func _card(name: String) -> Graph.Card:
	return _graph.card_of(ROOT.path_join(name))


# ── Metrics ──────────────────────────────────────────────────────────────────────────

func _test_lod_bands() -> void:
	_section("one LOD definition, and every consumer asks it")
	# The Unity leg has two -- the view banding at 0.45/1.05 and the host at 0.32/0.80 -- so
	# between those thresholds the card the view drew and the card the camera measured were
	# different widths.
	_eq(Metrics.lod_of(0.10), Metrics.Lod.PILL, "the smallest zoom is a pill")
	_eq(Metrics.lod_of(0.44), Metrics.Lod.PILL, "just under the first band edge")
	_eq(Metrics.lod_of(0.45), Metrics.Lod.SECTIONS, "at the edge it is sections")
	# The FULL band starts BELOW 1:1: 100% zoom is where a user works and where the layer selector
	# says "Edit", and with the edge above it that was the band showing everything except the
	# markup -- the card at its largest, carrying the least.
	_eq(Metrics.lod_of(0.74), Metrics.Lod.SECTIONS, "just under the second")
	_eq(Metrics.lod_of(0.75), Metrics.Lod.FULL, "at the edge it is full")
	_eq(Metrics.lod_of(1.0), Metrics.Lod.FULL, "and 1:1 -- where the work happens -- is full")
	_eq(Metrics.lod_of(2.2), Metrics.Lod.FULL, "and stays full")

	_eq(Metrics.card_width_for(Metrics.Lod.PILL), 300.0, "a pill is the narrowest")
	_eq(Metrics.card_width_for(Metrics.Lod.SECTIONS), 340.0, "sections are wider")
	_eq(Metrics.card_width_for(Metrics.Lod.FULL), 430.0, "and full is the widest -- it rides the attribute run")

	_check(Metrics.shows_sections(Metrics.Lod.SECTIONS), "sections show at L1")
	_check(not Metrics.shows_sections(Metrics.Lod.PILL), "and not at L0")
	_check(Metrics.shows_detail(Metrics.Lod.FULL), "detail shows only at L2")
	_check(not Metrics.shows_detail(Metrics.Lod.SECTIONS), "not at L1")

	_eq(Metrics.clamp_zoom(0.0), Metrics.ZOOM_MIN, "zoom clamps at the floor")
	_eq(Metrics.clamp_zoom(99.0), Metrics.ZOOM_MAX, "and at the ceiling")


func _test_camera() -> void:
	_section("the camera transform is invertible")
	# A right-click that creates a card places it at the world coordinates of the click, so a
	# disagreement here puts the new card somewhere the user did not point.
	for zoom in [0.25, 1.0, 1.7]:
		var camera := Vector2(-120.0, 64.0)
		var world := Vector2(340.0, 512.0)
		var screen: Vector2 = Metrics.world_to_screen(world, camera, zoom)
		var back: Vector2 = Metrics.screen_to_world(screen, camera, zoom)
		_check(back.is_equal_approx(world), "world -> screen -> world at zoom %.2f" % zoom)

	_section("zooming about a point keeps that point still")
	# Or the canvas slides out from beneath the thing the user was aiming at.
	var camera := Vector2(30.0, -70.0)
	var anchor := Vector2(640.0, 360.0)
	var before: Vector2 = Metrics.screen_to_world(anchor, camera, 1.0)
	var moved: Vector2 = Metrics.zoom_about(camera, 1.0, 1.8, anchor)
	var after: Vector2 = Metrics.screen_to_world(anchor, moved, 1.8)
	_check(after.is_equal_approx(before), "the world point under the cursor does not move")

	_check(Metrics.screen_to_world(anchor, camera, 0.0) == anchor,
		"a zero zoom is not a division -- it answers the input")


func _test_height_model() -> void:
	_section("card height grows with what the card holds")
	var app := _card("app.guitkx")
	var row := _card("components/row/row.guitkx")
	_check(Metrics.card_height(app) > Metrics.card_height(row),
		"a card with imports, hooks and markup is taller than one with a single element")
	_check(Metrics.card_height(row) > Metrics.HEADER_H, "every card is at least its header")
	_eq(Metrics.card_height(null), Metrics.PILL_H, "no card measures as a pill")

	_section("the measurement is memoised, and re-projection resets it")
	var first := Metrics.card_height(app)
	_check(app.cached_height > 0.0, "the height is cached on the card")
	_eq(Metrics.card_height(app), first, "a second call is the same answer")
	app.clear_detail()
	_eq(app.cached_height, 0.0, "clearing the card's detail drops the cache")
	Service.populate_card(app, _fixture_app())
	_close(Metrics.card_height(app), first, "and re-projecting the same text measures the same", 0.5)

	_section("wrapping")
	_eq(Metrics.wrap_lines(0, 100.0, 7.0), 1, "nothing still occupies a line")
	_eq(Metrics.wrap_lines(10, 100.0, 7.0), 1, "a short run fits on one")
	_eq(Metrics.wrap_lines(30, 100.0, 7.0), 3, "a long one wraps")
	_eq(Metrics.wrap_lines(10, 1.0, 7.0), 10, "a width narrower than one character still advances")


func _test_culling() -> void:
	_section("culling keeps one viewport of slack")
	# A card built only when it crosses the edge appears a frame late during a pan, and the edge
	# painter has no anchor to land on until it does.
	var card := Graph.Card.new()
	card.x = 0.0
	card.y = 0.0
	card.cached_height = 200.0
	var width := Metrics.card_width_for(Metrics.Lod.SECTIONS)

	_check(Metrics.is_near_viewport(card, width, Vector2.ZERO, 1.0, VIEWPORT),
		"a card at the origin is on screen")
	_check(Metrics.is_near_viewport(card, width, Vector2(-VIEWPORT.x, 0), 1.0, VIEWPORT),
		"a card one viewport off screen is still built")
	_check(not Metrics.is_near_viewport(card, width, Vector2(-VIEWPORT.x * 4.0, 0), 1.0, VIEWPORT),
		"a card far beyond that is not")
	_check(not Metrics.is_near_viewport(card, width, Vector2(0, VIEWPORT.y * 4.0), 1.0, VIEWPORT),
		"vertically too")
	_check(Metrics.is_near_viewport(card, width, Vector2.ZERO, 1.0, Vector2.ZERO),
		"with no viewport to measure against, nothing is culled")
	_check(Metrics.is_near_viewport(null, width, Vector2.ZERO, 1.0, VIEWPORT),
		"and nothing is not culled either")

	_section("content bounds and fit-to-view")
	var bounds: Rect2 = Metrics.content_bounds(_graph, Metrics.Lod.SECTIONS)
	_check(bounds.size.x > 0.0 and bounds.size.y > 0.0, "the graph occupies a rectangle")
	for c in _graph.cards:
		_check(bounds.encloses(Rect2(c.x, c.y, Metrics.card_width_for(Metrics.Lod.SECTIONS),
				Metrics.card_height(c))),
			"which encloses %s" % c.title)

	var fit: Dictionary = Metrics.fit_to_view(_graph, VIEWPORT)
	var zoom := float(fit["zoom"])
	_check(zoom > 0.0 and zoom <= Metrics.ZOOM_MAX, "the fit zoom is in range")
	var top_left: Vector2 = Metrics.world_to_screen(bounds.position, fit["camera"], zoom)
	var bottom_right: Vector2 = Metrics.world_to_screen(bounds.end, fit["camera"], zoom)
	_check(top_left.x >= -1.0 and top_left.y >= -1.0, "the content starts inside the viewport")
	_check(bottom_right.x <= VIEWPORT.x + 1.0 and bottom_right.y <= VIEWPORT.y + 1.0,
		"and ends inside it")
	_eq(float(Metrics.fit_to_view(Graph.new(), VIEWPORT)["zoom"]), 1.0,
		"an empty graph fits at the identity")


func _test_edge_geometry() -> void:
	_section("edge anchors")
	var card := Graph.Card.new()
	card.x = 100.0
	card.y = 200.0
	var width := 340.0
	var first: Vector2 = Metrics.edge_source_anchor(card, 0, width)
	var second: Vector2 = Metrics.edge_source_anchor(card, 1, width)
	_eq(first.x, 440.0, "an edge leaves from the card's right edge")
	_check(second.y > first.y, "and a second import leaves from its own row, not the same point")
	_close(second.y - first.y, Metrics.ANCHOR_PITCH, "one row apart")
	_eq(Metrics.edge_target_anchor(card).x, 100.0, "an edge arrives at the card's left edge")

	_section("the curve")
	var from := Vector2(0.0, 0.0)
	var to := Vector2(400.0, 100.0)
	_check(Metrics.edge_point(from, to, 1.0, 0.0).is_equal_approx(from), "t=0 is the start")
	_check(Metrics.edge_point(from, to, 1.0, 1.0).is_equal_approx(to), "t=1 is the end")
	var mid: Vector2 = Metrics.edge_point(from, to, 1.0, 0.5)
	_close(mid.x, 200.0, "the midpoint sits between the ends horizontally")
	_close(mid.y, 50.0, "and vertically")

	# The control points are pulled horizontally, so the curve leaves and arrives flat -- which
	# is what makes a graph of them readable rather than a bundle of diagonals.
	var controls: Array = Metrics.edge_control_points(from, to, 1.0)
	_eq((controls[0] as Vector2).y, from.y, "the first control point is level with the start")
	_eq((controls[1] as Vector2).y, to.y, "and the second with the end")
	_check((controls[0] as Vector2).x > from.x, "pulled forward out of the start")
	_check((controls[1] as Vector2).x < to.x, "and back out of the end")

	var short_controls: Array = Metrics.edge_control_points(Vector2.ZERO, Vector2(4.0, 80.0), 1.0)
	_check((short_controls[0] as Vector2).x >= 40.0,
		"a short back-edge still bows out rather than collapsing into the cards it joins")


func _test_seeded_layout_does_not_overlap() -> void:
	_section("no two seeded cards overlap, at any LOD")
	# A pitch narrower than the widest card overlaps adjacent columns at that zoom -- which is a
	# click that selects the card behind the one under the cursor, and only at one zoom level.
	for lod in [Metrics.Lod.PILL, Metrics.Lod.SECTIONS, Metrics.Lod.FULL]:
		var width: float = Metrics.card_width_for(lod)
		for i in range(_graph.cards.size()):
			for j in range(i + 1, _graph.cards.size()):
				var a := _graph.cards[i]
				var b := _graph.cards[j]
				var ra := Rect2(a.x, a.y, width, Metrics.card_height(a))
				var rb := Rect2(b.x, b.y, width, Metrics.card_height(b))
				_check(not ra.intersects(rb),
					"%s and %s are apart at width %.0f" % [a.title, b.title, width])


# ── Layout ───────────────────────────────────────────────────────────────────────────

func _test_layout_round_trip() -> void:
	_section("a layout is remembered")
	var layout := Layout.for_graph(_graph)
	_check(layout.adopt_unplaced(_graph), "a fresh layout writes down every seeded slot")
	_check(not layout.adopt_unplaced(_graph), "and a second pass has nothing new to write")
	_graph.cards[0].x = 1234.0
	_graph.cards[0].y = 5678.0
	layout.capture_from(_graph, Vector2(-40.0, 12.0), 0.7)
	_check(layout.save("2026-08-27T10:00:00Z"), "it saves")

	var back := Layout.load_for_root(_graph.root_path)
	_check(back != null, "and loads again")
	_check(back.camera.is_equal_approx(Vector2(-40.0, 12.0)), "the camera survives")
	_close(back.zoom, 0.7, "so does the zoom")
	_eq(back.members.size(), _graph.cards.size(), "so does the membership")

	_graph.cards[0].x = 0.0
	_graph.cards[0].y = 0.0
	back.apply_to(_graph)
	_eq(_graph.cards[0].x, 1234.0, "and applying it puts the card back where it was")
	_eq(_graph.cards[0].y, 5678.0, "in both axes")

	_section("a layout that recomputes is not a layout")
	# The seeded layout is a walk over the WHOLE graph, so its answer depends on the card set --
	# recomputed on every mount, adding one module moves every card the user never dragged.
	var extra := Graph.Card.new()
	extra.file_path = ROOT.path_join("late.guitkx")
	extra.title = "late"
	_graph.cards.append(extra)
	back.apply_to(_graph)
	_eq(_graph.cards[0].x, 1234.0, "an added card does not move the ones already placed")
	_check(back.adopt_unplaced(_graph), "and the newcomer gets a slot of its own")
	_graph.cards.remove_at(_graph.cards.size() - 1)


func _test_layout_by_membership() -> void:
	_section("a tree is found by WHO IS IN IT")
	# The root is derived, so a save that re-files a folder can resolve a different module as
	# root; addressed by root alone the tree then looks like one nobody has ever laid out.
	var member_paths := PackedStringArray()
	for card in _graph.cards:
		member_paths.append(card.file_path)
	var found := Layout.load_for_members(member_paths)
	_check(found != null, "the saved layout is found from its membership alone")
	_check(found.positions.size() > 0, "with its positions intact")

	_check(Layout.load_for_members(PackedStringArray()) == null, "no members, no match")
	_check(Layout.load_for_members(PackedStringArray(["res://nowhere/x.guitkx"])) == null,
		"and a membership that overlaps nothing matches nothing")

	_section("the newest wins a tie")
	var older := Layout.new()
	older.root_path = "res://tests/__builder_canvas_tmp/other/other.guitkx"
	older.members = member_paths
	older.zoom = 0.11
	older.save("2020-01-01T00:00:00Z")
	var newer := Layout.load_for_members(member_paths)
	_check(newer != null and not is_equal_approx(newer.zoom, 0.11),
		"a stale layout with the same membership does not outrank the live one")


func _test_layout_repath() -> void:
	_section("a rename does not throw the layout away")
	var layout := Layout.new()
	layout.root_path = ROOT.path_join("app.guitkx")
	layout.members = PackedStringArray([
		ROOT.path_join("app.guitkx"), ROOT.path_join("components/row/row.guitkx")])
	layout.set_position(ROOT.path_join("app.guitkx"), Vector2(10.0, 20.0))
	layout.set_position(ROOT.path_join("components/row/row.guitkx"), Vector2(30.0, 40.0))

	layout.repath(ROOT.path_join("components/row/row.guitkx"),
		ROOT.path_join("components/row/renamed.guitkx"), false)
	var moved_graph := Graph.new()
	var moved_card := Graph.Card.new()
	moved_card.file_path = ROOT.path_join("components/row/renamed.guitkx")
	moved_graph.cards.append(moved_card)
	moved_graph.root_path = layout.root_path
	layout.apply_to(moved_graph)
	_eq(moved_card.x, 30.0, "the renamed module keeps its slot")
	_eq(moved_card.y, 40.0, "in both axes")

	_section("renaming the FOLDER-OWNING component carries the whole layout")
	# Every member path changes at once, so neither the by-root lookup nor the by-membership scan
	# can find the file again unless the keys and the file name move together.
	var owner := Layout.new()
	owner.root_path = ROOT.path_join("app.guitkx")
	owner.set_position(ROOT.path_join("app.guitkx"), Vector2(1.0, 2.0))
	owner.set_position(ROOT.path_join("components/row/row.guitkx"), Vector2(3.0, 4.0))
	owner.members = PackedStringArray([
		ROOT.path_join("app.guitkx"), ROOT.path_join("components/row/row.guitkx")])
	var old_file := Layout.file_for(owner.root_path)

	owner.repath(ROOT, "res://tests/__builder_canvas_tmp/renamed", true)
	_check(owner.root_path.begins_with("res://tests/__builder_canvas_tmp/renamed"),
		"the root follows the folder")
	_check(str(owner.members[1]).begins_with("res://tests/__builder_canvas_tmp/renamed"),
		"and so does every member")
	_check(Layout.file_for(owner.root_path) != old_file,
		"which means the layout FILE has a different name now")

	var renamed_graph := Graph.new()
	renamed_graph.root_path = owner.root_path
	var a := Graph.Card.new()
	a.file_path = "res://tests/__builder_canvas_tmp/renamed/app.guitkx"
	var b := Graph.Card.new()
	b.file_path = "res://tests/__builder_canvas_tmp/renamed/components/row/row.guitkx"
	renamed_graph.cards.append(a)
	renamed_graph.cards.append(b)
	owner.apply_to(renamed_graph)
	_eq(a.x, 1.0, "the owner keeps its slot through the folder move")
	_eq(b.x, 3.0, "and so does the child")

	_section("degenerate repaths")
	owner.repath("", "res://x", false)
	owner.repath("res://x", "res://x", false)
	_eq(a.x, 1.0, "moving nowhere, or to where it already is, changes nothing")


# ── Host ─────────────────────────────────────────────────────────────────────────────

func _test_host_renders_each_lod() -> void:
	_section("the canvas renders, and the LOD bands are visible in what it builds")
	var host := Host.new()
	host.size = VIEWPORT
	root.add_child(host)
	host.show_graph(_graph)
	await process_frame
	await process_frame

	var counts := {}
	for zoom in [0.3, 0.6, 1.5]:
		host.set_camera(Vector2(40.0, 40.0), zoom)
		await process_frame
		await process_frame
		counts[zoom] = _count(host.get_node("Cards"))
	_check(int(counts[0.3]) > 0, "the pill LOD builds something")
	_check(int(counts[0.6]) > int(counts[0.3]),
		"the sections LOD builds more of it (%d > %d)" % [counts[0.6], counts[0.3]])
	_check(int(counts[1.5]) > int(counts[0.6]),
		"and the full LOD more again (%d > %d)" % [counts[1.5], counts[0.6]])

	_section("the card layer is rendered by the reconciler, from the dogfooded view")
	_check(host.get_node("Cards").get_child_count() == 1,
		"one root node, mounted once and patched thereafter")
	_check(host.get_node("Edges") is Edges, "with the edge overlay above it")

	_section("a culled card still costs almost nothing")
	host.set_camera(Vector2(-40000.0, -40000.0), 1.5)
	await process_frame
	await process_frame
	_check(_count(host.get_node("Cards")) < int(counts[1.5]),
		"panning the tree off screen collapses the cards to placeholders")

	host.unmount()
	host.queue_free()


func _test_host_interaction() -> void:
	_section("hit-testing, selection and the camera")
	var host := Host.new()
	host.size = VIEWPORT
	root.add_child(host)
	host.show_graph(_graph)
	host.set_camera(Vector2.ZERO, 1.0)
	await process_frame

	# Hit-tested against the MODEL, not the node tree: the cards are re-created as the graph
	# changes, so a hit-test that walked Controls would be asking a tree that has moved on.
	var target := _graph.cards[1]
	var inside: Vector2 = Metrics.world_to_screen(Vector2(target.x + 8.0, target.y + 8.0),
		host.camera, host.zoom)
	_eq(host.card_at(inside), 1, "a point inside a card finds it")
	_eq(host.card_at(Vector2(-9999.0, -9999.0)), -1, "and a point in open canvas finds nothing")

	var selections: Array = []
	host.card_selected.connect(func(index: int): selections.append(index))
	host.select_card(1)
	_eq(host.selected, 1, "selecting sets the selection")
	_eq(selections.size(), 1, "and announces it once")
	host.select_card(1)
	_eq(selections.size(), 1, "selecting the same card again announces nothing")

	_section("zooming happens about the cursor")
	var anchor := Vector2(400.0, 300.0)
	var world_before: Vector2 = Metrics.screen_to_world(anchor, host.camera, host.zoom)
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	wheel.position = anchor
	host._gui_input(wheel)
	_check(host.zoom > 1.0, "the wheel zooms in")
	var world_after: Vector2 = Metrics.screen_to_world(anchor, host.camera, host.zoom)
	_check(world_after.is_equal_approx(world_before),
		"and the world point under the cursor has not moved")

	_section("fit-to-view frames the whole graph")
	var framed: Array = []
	host.camera_changed.connect(func(c: Vector2, z: float): framed.append([c, z]))
	host.fit_to_view()
	_eq(framed.size(), 1, "framing announces the camera")
	var bounds: Rect2 = Metrics.content_bounds(_graph, Metrics.Lod.SECTIONS)
	var corner: Vector2 = Metrics.world_to_screen(bounds.position, host.camera, host.zoom)
	_check(corner.x >= -1.0 and corner.y >= -1.0, "and everything is inside the viewport")

	_section("a right-click asks for a menu at the world point under it")
	var world_requests: Array = []
	var card_requests: Array = []
	host.canvas_context_requested.connect(func(at: Vector2): world_requests.append(at))
	host.card_context_requested.connect(func(i: int, at: Vector2): card_requests.append(i))
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_RIGHT
	click.pressed = true
	click.position = Vector2(4.0, 4.0)
	host._gui_input(click)
	_eq(world_requests.size() + card_requests.size(), 1, "exactly one request per click")

	host.unmount()
	host.queue_free()


func _test_edge_overlay() -> void:
	_section("the edge overlay")
	var overlay := Edges.new()
	overlay.size = VIEWPORT
	root.add_child(overlay)
	overlay.refresh(_graph, Vector2.ZERO, 1.0, -1)
	await process_frame
	_check(overlay.graph == _graph, "it takes the graph it is given")
	_eq(overlay.mouse_filter, Control.MOUSE_FILTER_IGNORE,
		"and never takes a click -- every one has to reach the cards beneath it")

	_section("a broken import still has an edge to draw")
	# An anchor dot with no line says nothing about WHY, and a specifier resolving to nothing is
	# a real authoring problem.
	var broken := 0
	for e in _graph.edges:
		if e.is_broken():
			broken += 1
	_eq(broken, 1, "the fixture's unresolvable import kept its edge")

	overlay.refresh(null, Vector2.ZERO, 1.0, -1)
	await process_frame
	_check(true, "and drawing no graph at all is not a crash")
	overlay.queue_free()


func _test_cleanup() -> void:
	_section("no residue")
	Layout.clear_all()
	var d := DirAccess.open(Layout.LAYOUT_DIR)
	_check(d == null or d.get_files().is_empty(), "every stored layout is cleared")


func _fixture_app() -> String:
	return "import { Row } from \"./components/row/row\"\nimport { primary } from \"./app.style\"\nimport { Gone } from \"./nowhere\"\n\nexport App(level: int = 1) -> RuitkVNode {\n\tvar s = useState(0)\n\treturn (\n\t\t<VBoxContainer style={ primary }>\n\t\t\t<Row text=\"one\" />\n\t\t\t@if (level > 1) {\n\t\t\t\treturn (\n\t\t\t\t\t<Label text=\"deep\" />\n\t\t\t\t)\n\t\t\t}\n\t\t</VBoxContainer>\n\t)\n}\n"


func _count(node: Node) -> int:
	var total := 1
	for child in node.get_children():
		total += _count(child)
	return total
