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
const CanvasLayout = preload("res://addons/reactive_ui_toolkit_editor/builder/canvas/builder_canvas_layout.gd")
const Layout = preload("res://addons/reactive_ui_toolkit_editor/builder/canvas/builder_canvas_layout.gd")
const Host = preload("res://addons/reactive_ui_toolkit_editor/builder/canvas/builder_canvas_host.gd")
const Edges = preload("res://addons/reactive_ui_toolkit_editor/builder/canvas/builder_canvas_edges.gd")
const Module = preload("res://addons/reactive_ui_toolkit_editor/builder/document/builder_module.gd")

const ROOT := "res://tests/__builder_canvas_tmp/app"
const VIEWPORT := Vector2(1280, 720)

## The number of assertions a complete run makes. KEPT EXACT, and raised with the suite.
##
## Left slack, this guard does not work: a script error aborted one test mid-run and the suite
## still printed ALL PASS, because the count it reached was comfortably above a floor set several
## additions ago. The floor only catches a truncated run while it sits AT the real count.
const ASSERTION_FLOOR := 212

var _fails := 0
var _passes := 0
var _graph: Graph = null


func _initialize() -> void:
	_run()


func _run() -> void:
	Layout.clear_all()
	_graph = _build_graph()

	_test_section_predicates_are_shared()
	_test_hit_test_matches_what_is_drawn()
	_test_hook_usage_highlighting()
	_test_section_caps()
	_test_kind_badge_band()
	_test_restored_zoom_is_clamped()
	_test_lod_bands()
	await _test_card_can_be_moved()
	await _test_canvas_can_be_panned()
	await _test_cards_do_not_eat_the_mouse()
	_test_anchors_land_on_the_drawn_card()
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
	# A FLOOR ON THE COUNT. A suite that stops at a broken dependency prints ALL PASS on however
	# few assertions it reached before it stopped -- which is a green line for a run that never
	# arrived at its own subject, and it has now hidden three separate defects in this builder.
	# The number is the tell, so the number is checked.
	if _passes < ASSERTION_FLOOR:
		print("builder canvas: only %d of at least %d assertions ran -- something stopped early"
			% [_passes, ASSERTION_FLOOR])
		quit(1)
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

## HOVERING A HOOK CHIP HIGHLIGHTS EVERY USAGE of what it returns.
## THE HIT-TEST AND THE DRAWN CARD MUST AGREE, AT EVERY LAYER.
##
## This is the defect that made the builder unusable: `drawn_height` stopped the card above its
## markup at the Cards layer, while `row_hit` went on reporting markup rows below that -- so the
## lower half of every card was DEAD TO THE MOUSE. `card_at` answered "no card here", and with it
## went the row click, the row menu and every drop that resolves through a card. Adding an element,
## dragging one onto a card and re-parenting a row all failed together, while dragging the card by
## its title bar kept working, because the title bar is inside the short rect.
##
## Layer 2 is the layer a tree opens at, so this was the first thing anyone met.
## THE VIEW AND THE METRICS MUST AGREE ABOUT WHICH SECTIONS A CARD HAS.
##
## They did not: the model asked "body is non-empty, or the kind is COMPONENT/HOOK"; the view
## asked `card.kind != 2` -- every kind except STYLE. So for a util, a value or a plain module the
## two disagreed about whether the section exists, and the EXPORTS block of those kinds was never
## drawn at any zoom while the metrics reserved height for it and the hit-test addressed rows
## inside that height.
func _test_section_predicates_are_shared() -> void:
	_section("a component and a hook always have a body")
	for kind in [Module.Kind.COMPONENT, Module.Kind.HOOK]:
		var card := Graph.Card.new()
		card.kind = kind
		_check(Metrics.has_body_section(card),
			"kind %d has one even when empty -- the card offers to add the first hook" % int(kind))

	_section("a style module does not, and does not show a signature")
	var style := Graph.Card.new()
	style.kind = Module.Kind.STYLE
	style.signature = "Palette"
	_check(not Metrics.has_body_section(style), "no body")
	_check(not Metrics.has_signature_section(style), "and no signature row")

	_section("a util has a body only when it has one, and exports when it declares them")
	var util := Graph.Card.new()
	util.kind = Module.Kind.UTIL
	_check(not Metrics.has_body_section(util), "an empty util has no body section")
	_check(not Metrics.has_exports_section(util), "and no exports block")
	util.export_detail = [_line(Graph.LineKind.EXPORT, "clamp01")]
	_check(Metrics.has_exports_section(util),
		"but it DOES once it declares one -- gated on STYLE alone, this was never drawn")

	_section("and the stack agrees with the predicates")
	# The stack is what the height estimate and the hit-test both read, so a section the
	# predicates claim must actually be in it.
	var sections := {}
	for entry in Metrics.section_stack(util):
		sections[int((entry as Dictionary)["section"])] = true
	_check(sections.has(int(Metrics.Section.EXPORTS)),
		"the util's exports section is in the stack")


func _test_hit_test_matches_what_is_drawn() -> void:
	_section("every reportable row is inside the card the mouse can hit")
	var card := _card_with_everything()
	for lod in [Metrics.Lod.PILL, Metrics.Lod.SECTIONS, Metrics.Lod.FULL]:
		var height: float = Metrics.drawn_height(card, lod)
		var reported := 0
		var outside := 0
		var undrawn := 0
		# Walk the whole card in one-pixel steps: anything the hit-test claims must lie within
		# the rectangle `card_at` tests against, and must belong to a section this layer draws.
		var y := 0.0
		while y < height + 400.0:
			var hit: Dictionary = Metrics.row_hit(card, Vector2(10.0, y), lod)
			if bool(hit["found"]):
				reported += 1
				if y >= height:
					outside += 1
				if not Metrics.draws_section(int(hit["section"]), lod):
					undrawn += 1
			y += 1.0
		_eq(outside, 0, "at %s no row is reported below the drawn card"
			% ["Architecture", "Cards", "Edit"][int(lod)])
		_eq(undrawn, 0, "at %s no row is reported for a section the layer does not draw"
			% ["Architecture", "Cards", "Edit"][int(lod)])
		if lod != Metrics.Lod.PILL:
			_check(reported > 0, "and at %s there are rows to aim at"
				% ["Architecture", "Cards", "Edit"][int(lod)])

	_section("a pill's rectangle is the height it draws at")
	# At the Architecture band the loop above is VACUOUS -- a pill reports no rows, so "nothing
	# outside" and "nothing undrawn" both pass trivially. The real question there is the card's
	# own rectangle, and it answered 38 against a card that draws 73.
	_eq(Metrics.drawn_height(card, Metrics.Lod.PILL), Metrics.PILL_H,
		"a pill measures PILL_H, not the header alone")
	_check(Metrics.PILL_H > Metrics.HEADER_H, "and a pill is taller than a header")

	_section("framing a card solves the WIDTH")
	# Fitting both axes made a long card frame itself tiny: 40 markup rows solved to the minimum
	# zoom, so "show me this card" answered with a pill.
	var tall := _card_with_everything()
	for i in 40:
		tall.markup.append(_line(Graph.LineKind.ELEMENT, "<Label>"))
	var short_frame: Dictionary = Metrics.frame_card(card, Vector2(900, 600))
	var tall_frame: Dictionary = Metrics.frame_card(tall, Vector2(900, 600))
	_eq(float(short_frame["zoom"]), float(tall_frame["zoom"]),
		"a card's height does not change the zoom it frames at")
	_check(int(Metrics.lod_of(float(tall_frame["zoom"]))) != int(Metrics.Lod.PILL),
		"and a long card does not frame as a pill")
	_check(float(tall_frame["camera"].y) > -tall.y * float(tall_frame["zoom"]) - 1.0,
		"a card taller than the viewport is aligned to its top, not centred off-screen")

	_section("the Cards layer draws markup rows -- that is what makes it the Cards layer")
	# Capability reference §2: Layer 2 shows "signature, imports, hook chips, markup rows"; Layer 3
	# ADDS attributes, code islands and style entry lines.
	_check(Metrics.draws_section(int(Metrics.Section.MARKUP), Metrics.Lod.SECTIONS),
		"markup at Layer 2")
	_check(not Metrics.draws_section(int(Metrics.Section.ISLAND), Metrics.Lod.SECTIONS),
		"but the code island waits for Layer 3")
	# EXPORTS IS GRADED, not withheld. A style module is ALL exports, so hiding the section outright
	# left a style card at Layer 2 as a header over nothing -- no way to see what it offers, and no
	# "+ entry" to add to it. Heads and affordances draw at Layer 2; the entry LINES wait for Layer 3.
	_check(Metrics.draws_section(int(Metrics.Section.EXPORTS), Metrics.Lod.SECTIONS),
		"the exports section itself is part of the Cards layer")
	var head := Graph.Line.new()
	head.badge = Graph.Badge.STYLE_HEADER
	var entry := Graph.Line.new()
	var add := Graph.Line.new()
	add.badge = Graph.Badge.ADD_ENTRY
	_check(Metrics.draws_export_row(head, Metrics.Lod.SECTIONS), "an export HEAD draws at Layer 2")
	_check(Metrics.draws_export_row(add, Metrics.Lod.SECTIONS),
		"and so does the + entry affordance beside it")
	_check(not Metrics.draws_export_row(entry, Metrics.Lod.SECTIONS),
		"but a style ENTRY line waits for Layer 3")
	_check(Metrics.draws_export_row(entry, Metrics.Lod.FULL), "which draws it")
	_check(not Metrics.draws_export_row(head, Metrics.Lod.PILL), "a pill draws none of them")

	# AND THE HIT-TEST ADDRESSES THE MODEL, not the picture. The second row a reader sees at
	# Layer 2 is not `export_detail[1]`, and every consumer downstream -- the row menu, the drop,
	# the source-pane jump -- indexes the model.
	# BUILT HERE rather than fetched: `_card` looks a module up in the fixture graph, and this one
	# is about the grading rule, not about any file in it.
	var graded := Graph.Card.new()
	graded.title = "Graded"
	graded.kind = Module.Kind.STYLE
	var g_head := Graph.Line.new()
	g_head.badge = Graph.Badge.STYLE_HEADER
	g_head.text = "panel"
	var g_e1 := Graph.Line.new()
	g_e1.text = "\"bg_color\": RED"
	var g_e2 := Graph.Line.new()
	g_e2.text = "\"corner_radius_all\": 6"
	var g_add := Graph.Line.new()
	g_add.badge = Graph.Badge.ADD_ENTRY
	g_add.text = "+ entry"
	graded.export_detail = [g_head, g_e1, g_e2, g_add]
	var visible: Array = Metrics.drawn_export_rows(graded, Metrics.Lod.SECTIONS)
	_eq(visible.size(), 2, "two of the four export rows draw at Layer 2")
	_eq(int(visible[0]), 0, "the head")
	_eq(int(visible[1]), 3, "and the add row, which is index THREE in the model")
	_eq(Metrics.drawn_export_rows(graded, Metrics.Lod.FULL).size(), 4,
		"Layer 3 draws all four")
	var stack_l2: Array = Metrics.section_stack(graded, Metrics.Lod.SECTIONS)
	var exports_l2 := {}
	for row in stack_l2:
		if int((row as Dictionary)["section"]) == int(Metrics.Section.EXPORTS):
			exports_l2 = row as Dictionary
	_eq(int(exports_l2.get("rows", -1)), 2,
		"and the height model counts what is drawn, not what exists")
	_check(Metrics.draws_section(int(Metrics.Section.ISLAND), Metrics.Lod.FULL),
		"which draws both")
	_check(not Metrics.draws_section(int(Metrics.Section.MARKUP), Metrics.Lod.PILL),
		"a pill draws no rows at all")

	# ATTRIBUTES ARE A LAYER 3 ELEMENT, not a fourth threshold. This tested `zoom >= 1.2`, which is
	# neither `lod_of` nor anything the capability reference names -- so across the whole window
	# [0.80, 1.20) the toolbar read "Layer 3 -- Edit" and the cards carried no attributes.
	_check(Metrics.shows_attributes(Metrics.Lod.FULL), "attributes are drawn at the Edit layer")
	_check(not Metrics.shows_attributes(Metrics.Lod.SECTIONS), "and not before it")

	# A SIGNATURE IS TWO RUNS, cut at the paren and not before it: a name that stops one character
	# short of its own parenthesis reads as a typo.
	_eq(Metrics.signature_head("Card(title: String = \"\")"), "Card(", "the name half keeps the paren")
	_eq(Metrics.signature_tail("Card(title: String = \"\")"), "title: String = \"\")",
		"and the parameter half is the rest")
	_eq(Metrics.signature_head("bare"), "bare", "a signature with no paren is all name")
	_eq(Metrics.signature_tail("bare"), "", "and has no parameter run")

	_section("a taller layer is a taller card")
	_check(Metrics.drawn_height(card, Metrics.Lod.FULL)
		> Metrics.drawn_height(card, Metrics.Lod.SECTIONS),
		"Edit shows more than Cards")
	_check(Metrics.drawn_height(card, Metrics.Lod.SECTIONS)
		> Metrics.drawn_height(card, Metrics.Lod.PILL),
		"and Cards shows more than Architecture")


## A card carrying one of everything, so every section is present to be hit-tested.
func _card_with_everything() -> Graph.Card:
	var card := Graph.Card.new()
	card.kind = Module.Kind.COMPONENT
	card.title = "Everything"
	card.signature = "Everything(a: int = 1) -> RuitkVNode"
	card.imports = [_line(Graph.LineKind.IMPORT, "import { X } from \"./x\"")]
	card.body = [_line(Graph.LineKind.HOOK, "useState  →  count")]
	card.markup = [
		_line(Graph.LineKind.ELEMENT, "<VBoxContainer>"),
		_line(Graph.LineKind.ELEMENT, "<Label>"),
		_line(Graph.LineKind.COMPONENT, "<X>"),
	]
	card.export_detail = [_line(Graph.LineKind.EXPORT, "container")]
	card.island_lines = PackedStringArray(["var t = 1"])
	card.island_start_line = 1
	card.island_end_line = 1
	return card


## A SECTION HAS A CEILING, AND EVERY CONSUMER READS THE SAME ONE.
##
## UB-23: no card section was capped, so a component with a long markup body grew a card until it
## overlapped its neighbours -- and the overlap was blamed on the layout, which had placed the card
## correctly for the height it was told about.
func _test_section_caps() -> void:
	_section("a long section is capped, and the cap is in the model")
	var tall := Graph.Card.new()
	tall.title = "Tall"
	tall.kind = Module.Kind.COMPONENT
	for i in 60:
		tall.markup.append(_line(Graph.LineKind.ELEMENT, "Label %d" % i))
	var stack: Array = Metrics.section_stack(tall)
	var markup := {}
	for row in stack:
		if int((row as Dictionary)["section"]) == int(Metrics.Section.MARKUP):
			markup = row as Dictionary
	_check(not markup.is_empty(), "the card has a markup section")
	_check(bool(markup["scrolls"]), "60 rows is past the cap, so the section scrolls")
	_eq(int(markup["all_rows"]), 60, "the model still knows how many rows there are")
	_check(int(markup["rows"]) < 60, "but only the ones inside the cap are addressable at rest")
	_eq(float(markup["height"]), Metrics.SECTION_OVERHEAD_H + Metrics.section_cap(
		int(Metrics.Section.MARKUP)), "and the section is its lead plus its cap, no taller")
	_eq(Metrics.section_scroll_h(tall, int(Metrics.Section.MARKUP)),
		Metrics.section_cap(int(Metrics.Section.MARKUP)),
		"which is the height the view gives the scroller")

	var short := Graph.Card.new()
	short.title = "Short"
	short.kind = Module.Kind.COMPONENT
	short.markup.append(_line(Graph.LineKind.ELEMENT, "Label"))
	_eq(Metrics.section_scroll_h(short, int(Metrics.Section.MARKUP)), 0.0,
		"a section that fits gets no scroller -- three rows in a 340px box is not a cap, it is a hole")

	# AND THE CARD IS BOUNDED. This is the whole point: an uncapped card is what overlaps the one
	# below it, and the layout cannot place what it is lied to about.
	_check(Metrics.estimate_card_height(tall) < 60.0 * Metrics.MARKUP_ROW_H,
		"a 60-row card is not 60 rows tall")

	# AN ANCHOR CANNOT FLOAT BELOW ITS OWN SECTION. A scrolled-out row is still a row an edge
	# leaves from, and drawn where the row WOULD be it is a dot past the card's bottom edge.
	var deep := Metrics.edge_source_anchor(tall, 59, Metrics.card_width_for(Metrics.Lod.FULL),
		Metrics.Lod.FULL, Metrics.Section.MARKUP)
	_check(deep.y <= tall.y + Metrics.estimate_card_height(tall),
		"the anchor of a scrolled-out row is clamped inside the card")
	var near_top := Metrics.edge_source_anchor(tall, 0, Metrics.card_width_for(Metrics.Lod.FULL),
		Metrics.Lod.FULL, Metrics.Section.MARKUP)
	_check(deep.y > near_top.y, "and rows above the cap still anchor in order")


## THE KIND CHIP IS A BAND, like the title bar is.
##
## Model-based because the drawn badge is a `Label` inside an IGNORE-filtered `PanelContainer`:
## Godot will never report a press on it, so a hit-test that waited for one would wait forever.
func _test_kind_badge_band() -> void:
	_section("the kind chip is the module's own drag handle")
	var card := Graph.Card.new()
	card.title = "Panelled"
	card.kind = Module.Kind.COMPONENT
	card.x = 100.0
	card.y = 200.0
	var width := Metrics.card_width_for(Metrics.Lod.FULL)
	_check(Metrics.on_kind_badge(card, Vector2(card.x + 10.0, card.y + 8.0), width),
		"a point at the head of the title bar is on the chip")
	_check(not Metrics.on_kind_badge(card, Vector2(card.x + width - 10.0, card.y + 8.0), width),
		"a point at the far end of the same bar is not")
	_check(not Metrics.on_kind_badge(card, Vector2(card.x + 10.0, card.y + 300.0), width),
		"and neither is a point below the title bar -- the chip is not the whole left column")
	_check(Metrics.on_title_bar(card, Vector2(card.x + 10.0, card.y + 8.0), width),
		"the chip is INSIDE the title bar, so dragging the card still works around it")


## A RESTORED ZOOM IS A ZOOM. A layout file is on disk, so an older build, a hand edit or a moved
## band table can put a value in it that no gesture can produce.
func _test_restored_zoom_is_clamped() -> void:
	_section("a layout restores a zoom the canvas can actually be at")
	CanvasLayout.clear_all()
	var layout := CanvasLayout.new()
	layout.root_path = ROOT
	layout.zoom = 99.0
	layout.camera = Vector2(10, 10)
	layout.save("test")
	var back := CanvasLayout.load_for_root(ROOT)
	_check(back != null, "the layout comes back")
	_eq(back.zoom, Metrics.ZOOM_MAX, "and its wild zoom is clamped to the ceiling")
	layout.zoom = 0.0
	layout.save("test")
	back = CanvasLayout.load_for_root(ROOT)
	_eq(back.zoom, Metrics.DEFAULT_ZOOM, "a zero zoom is the sentinel for 'no view saved'")
	CanvasLayout.clear_all()


func _line(kind: int, text: String) -> Graph.Line:
	var row := Graph.Line.new()
	row.kind = kind
	row.text = text
	row.name = text
	return row


func _test_hook_usage_highlighting() -> void:
	_section("a chip's bindings are read off its own text")
	var chip := Graph.Line.new()
	chip.text = "useState  →  count, set_count"
	var bound := Host._bound_names(chip)
	_eq(", ".join(bound), "count, set_count", "everything after the arrow")

	var plain := Graph.Line.new()
	plain.text = "useEffect"
	_eq(Host._bound_names(plain).size(), 0, "a hook that binds nothing highlights nothing")
	_eq(Host._bound_names(null).size(), 0, "and no row at all is not an error")

	_section("a row mentions a name only on WORD BOUNDARIES")
	var row := Graph.Line.new()
	row.text = "<Label"
	row.attrs_text = "text={ count }"
	_check(Metrics.row_mentions(row, PackedStringArray(["count"])), "the row uses count")
	_check(not Metrics.row_mentions(row, PackedStringArray(["oun"])),
		"a fragment inside the word does not count")

	var near := Graph.Line.new()
	near.text = "<Label"
	near.attrs_text = "text={ counter }"
	_check(not Metrics.row_mentions(near, PackedStringArray(["count"])),
		"and `counter` is not a usage of `count`")
	_check(Metrics.row_mentions(near, PackedStringArray(["counter"])), "but `counter` is")

	_section("nothing hovered highlights nothing")
	_check(not Metrics.row_mentions(row, PackedStringArray()), "an empty name list")
	_check(not Metrics.row_mentions(row, null), "and no list at all")
	_check(not Metrics.row_mentions(null, PackedStringArray(["count"])), "and no row at all")


func _test_lod_bands() -> void:
	_section("one LOD definition, and every consumer asks it")
	# The band edges are the capability reference's, not ones chosen here: Architecture below 0.32,
	# Cards below 0.80, Edit at 0.80 and up. This asserted 0.45/0.75 before -- the Unity VIEW's
	# banding rather than its HOST's -- and that is the pair which disagrees with the layer selector,
	# so the layer named in the toolbar was not the layer being drawn.
	_eq(Metrics.lod_of(0.10), Metrics.Lod.PILL, "the smallest zoom is a pill")
	_eq(Metrics.lod_of(0.31), Metrics.Lod.PILL, "just under the first band edge")
	_eq(Metrics.lod_of(0.32), Metrics.Lod.SECTIONS, "at the edge it is sections")
	_eq(Metrics.lod_of(0.79), Metrics.Lod.SECTIONS, "just under the second")
	_eq(Metrics.lod_of(0.80), Metrics.Lod.FULL, "at the edge it is full")
	_eq(Metrics.lod_of(1.0), Metrics.Lod.FULL, "and 1:1 -- where the work happens -- is full")
	_eq(Metrics.lod_of(2.2), Metrics.Lod.FULL, "and stays full")

	# Each layer's preset zoom must land INSIDE the band that layer names. Choosing "Cards" and
	# being shown pills is the defect this pins.
	_eq(Metrics.lod_of(Metrics.LAYER_PRESETS[0]), Metrics.Lod.PILL, "the Architecture preset is Architecture")
	_eq(Metrics.lod_of(Metrics.LAYER_PRESETS[1]), Metrics.Lod.SECTIONS, "the Cards preset is Cards")
	_eq(Metrics.lod_of(Metrics.LAYER_PRESETS[2]), Metrics.Lod.FULL, "the Edit preset is Edit")
	_eq(Metrics.DEFAULT_ZOOM, Metrics.LAYER_PRESETS[1], "a tree with no saved layout opens at Layer 2")

	_eq(Metrics.card_width_for(Metrics.Lod.PILL), 300.0, "a pill is the narrowest")
	_eq(Metrics.card_width_for(Metrics.Lod.SECTIONS), 340.0, "sections are wider")
	_eq(Metrics.card_width_for(Metrics.Lod.FULL), 360.0,
		"and full is the widest -- but only as wide as its content, not as wide as an attribute run")

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

	# The pull follows the DOMINANT DIRECTION. With levels as rows, most children sit below and
	# slightly to one side; pulling horizontally regardless doubled such a curve back through
	# itself, which is a knot rather than an edge.
	var down: Array = Metrics.edge_control_points(Vector2.ZERO, Vector2(4.0, 80.0), 1.0)
	_eq((down[0] as Vector2).x, 0.0, "a mostly-vertical edge is not pulled sideways at all")
	_check((down[0] as Vector2).y >= 40.0,
		"a short back-edge still bows out rather than collapsing into the cards it joins")
	_check((down[1] as Vector2).y <= 80.0 - 40.0, "and arrives bowed from the other side")


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


# ── Moving things ────────────────────────────────────────────────────────────────────

## A mounted canvas over the suite's own graph.
func _mounted_host() -> Host:
	var host := Host.new()
	host.size = VIEWPORT
	root.add_child(host)
	host.show_graph(_graph)
	host.set_camera(Vector2.ZERO, 1.0)
	return host


## A press, a drag past the threshold, a release -- the gesture, not the handler.
func _drag(host, from: Vector2, to: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = from
	host._gui_input(press)
	# TWO moves: the first crosses the threshold and decides what kind of drag this is, the
	# second is the one that actually carries it.
	for at in [from.lerp(to, 0.5), to]:
		var motion := InputEventMouseMotion.new()
		motion.position = at
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		host._gui_input(motion)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = to
	host._gui_input(release)


func _test_card_can_be_moved() -> void:
	_section("a card can be dragged to a new place")
	# It could not. The layout store, its per-tree keying and its "top up rather than re-seed"
	# rule were all written for positions a user chooses, and nothing in the builder could change
	# one -- the canvas was a diagram, not a canvas.
	var host: Host = _mounted_host()
	await process_frame
	var card = host.graph.cards[0]
	var was := Vector2(card.x, card.y)
	var grab := Metrics.world_to_screen(was + Vector2(20, 10), host.camera, host.zoom)

	var moved := [Vector2.ZERO]
	host.card_moved.connect(func(_i: int, to: Vector2): moved[0] = to)
	_drag(host, grab, grab + Vector2(140, 80))

	_check(Vector2(card.x, card.y) != was,
		"the card is somewhere else (%s -> %s)" % [was, Vector2(card.x, card.y)])
	_check(moved[0] != Vector2.ZERO, "and it announced where, so the layout can remember it")

	# PUT IT BACK. The graph is shared with every other section in this suite, and one of them
	# asserts no two cards occupy the same slot -- a test that leaves a card where it dropped it
	# fails a later one about something else entirely.
	card.x = was.x
	card.y = was.y
	host.unmount()


func _test_canvas_can_be_panned() -> void:
	_section("the canvas pans with the left button on empty space")
	# Panning was MIDDLE BUTTON ONLY, which is a gesture a lot of people never try and some mice
	# do not have.
	var host: Host = _mounted_host()
	await process_frame
	var before := host.camera
	# A corner far from any card: dragging ON a card moves the card instead, which is the point.
	var empty := host.size - Vector2(20, 20)
	_drag(host, empty, empty - Vector2(120, 70))

	_check(host.camera != before, "the camera moved (%s -> %s)" % [before, host.camera])
	host.unmount()


# ── The mouse reaches the canvas ─────────────────────────────────────────────────────

func _test_cards_do_not_eat_the_mouse() -> void:
	_section("a card's own Controls are transparent to the mouse")
	# THE BUG THAT BROKE EVERY CANVAS GESTURE AT ONCE. A card is a PanelContainer full of Labels,
	# and Godot's default mouse_filter for those is STOP -- so a press anywhere on a card was
	# consumed by the card and the host never saw it. Card dragging, row clicks and row menus all
	# worked only in the gaps BETWEEN cards, which is to say none of them worked.
	#
	# The earlier drag test missed it entirely because it called `_gui_input` directly, which is
	# the one path that cannot reproduce a filter problem: it IS the handler the filter prevents
	# from being reached.
	var host: Host = _mounted_host()
	await process_frame
	await process_frame

	var cards := host.get_node("Cards")
	var stoppers := PackedStringArray()
	var buttons := 0
	_collect_filters(cards, stoppers, [buttons])
	_check(stoppers.is_empty(),
		"nothing in a card stops the mouse (%s)" % ", ".join(stoppers))

	# And the buttons that SHOULD take a press still do -- the "+ hook" chips are the one thing
	# on a card that handles its own click, and blanket-ignoring would have killed them.
	var takers := _count_buttons(cards)
	_check(takers > 0, "the card's own buttons still take the mouse (%d of them)" % takers)
	host.unmount()


func _collect_filters(node: Node, out: PackedStringArray, _c: Array) -> void:
	for child in node.get_children():
		if child is Control and not (child is BaseButton) 				and (child as Control).mouse_filter == Control.MOUSE_FILTER_STOP:
			out.append(child.get_class())
		_collect_filters(child, out, _c)


func _count_buttons(node: Node) -> int:
	var n := 0
	for child in node.get_children():
		if child is BaseButton and (child as Control).mouse_filter != Control.MOUSE_FILTER_IGNORE:
			n += 1
		n += _count_buttons(child)
	return n


# ── Anchors land on the card you can see ─────────────────────────────────────────────

func _test_anchors_land_on_the_drawn_card() -> void:
	_section("an edge anchor is on the card AS DRAWN, in every band")
	# `card_height` answers with the tallest layout on purpose -- the gutter has to survive every
	# zoom. Anything asking "where is this card on SCREEN" needs the other answer, and asking the
	# wrong one hung the anchors in space below a pill: a dot joined to a curve that appeared to
	# start at nothing, which is exactly what it looked like.
	var card := _card("app.guitkx")
	var width_of := {}
	for lod in [Metrics.Lod.PILL, Metrics.Lod.SECTIONS, Metrics.Lod.FULL]:
		var w: float = Metrics.card_width_for(lod)
		var drawn: float = Metrics.drawn_height(card, lod)
		var anchor: Vector2 = Metrics.edge_source_anchor(card, 0, w, lod)
		_eq(anchor.x, card.x + w, "the anchor is on the right edge at lod %d" % lod)
		_check(anchor.y >= card.y and anchor.y <= card.y + drawn,
			"and within the drawn height at lod %d (%f in %f..%f)"
				% [lod, anchor.y, card.y, card.y + drawn])
		width_of[lod] = drawn

	_check(float(width_of[Metrics.Lod.PILL]) < float(width_of[Metrics.Lod.FULL]),
		"a pill is drawn shorter than a full card, which is the whole point")
