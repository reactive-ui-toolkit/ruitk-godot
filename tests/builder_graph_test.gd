extends SceneTree
## Headless test suite for the RUITK Builder's GRAPH PROJECTION (checkpoint C1). Run:
##   godot --headless --path <project> --script res://tests/builder_graph_test.gd
##
## The projection turns the document model into what the canvas draws: a card per module, a row
## per meaningful line, an edge per import. It is pure -- it reads buffers, never files -- so all
## of it is provable without an editor.
##
## The markup assertions are GOLDEN: a whole card's rows are rendered to one compact block and
## compared against a literal. A per-field assertion would pass while the tree quietly grew a
## phantom row or lost a clause; a golden fails on either, and prints both sides.
##
## The fixture tree covers every module kind, every directive family, aliased and namespace
## imports, a theme directive, a broken import, and a component whose markup nests four levels.

const Paths = preload("res://addons/reactive_ui_toolkit_editor/builder/document/builder_paths.gd")
const Module = preload("res://addons/reactive_ui_toolkit_editor/builder/document/builder_module.gd")
const Workspace = preload("res://addons/reactive_ui_toolkit_editor/builder/document/builder_workspace.gd")
const Graph = preload("res://addons/reactive_ui_toolkit_editor/builder/canvas/builder_graph.gd")
const Service = preload("res://addons/reactive_ui_toolkit_editor/builder/canvas/builder_graph_service.gd")

const ROOT := "res://tests/__builder_graph_tmp/app"

var _fails := 0
var _passes := 0
var _ws: Workspace = null
var _graph: Graph = null


func _initialize() -> void:
	_build_fixture()
	_graph = Service.project(_ws.modules(), ROOT.path_join("app.guitkx"))

	_test_membership_and_order()
	_test_kinds_and_signatures()
	_test_import_rows()
	_test_edges()
	_test_hook_chips()
	_test_island()
	_test_markup_golden()
	_test_directive_families()
	_test_spans_address_the_source()
	_test_export_detail()
	_test_positions()
	_test_refresh_edges()
	_test_degenerate_buffers()

	print("")
	if _fails == 0:
		print("builder graph: ALL PASS (%d assertions)" % _passes)
		quit(0)
	else:
		print("builder graph: %d FAILURE(S) of %d assertions" % [_fails, _fails + _passes])
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


func _section(title: String) -> void:
	print(title)


# ── Fixture ──────────────────────────────────────────────────────────────────────────

const APP_SRC := """import * as AppHooks from "./app.hooks"
import { primary as brand } from "./app.style"
import { Row } from "./components/row/row"
import { Missing } from "./nowhere"
@uss "res://tests/__builder_graph_tmp/app/theme.tres"

export App(level: int = 1,
	title: String = "hi") -> RuitkVNode {
	var s = useState(0)
	var count = s[0]
	var facts = AppHooks.use_facts(level)
	return (
		<VBoxContainer style={ brand }>
			<Label text={ title } />
			@if (count > 5) {
				return (
					<Label text="high" />
				)
			} @elif (count > 2) {
				return (
					<Label text="mid" />
				)
			} @else {
				return (
					<Label text="low" />
				)
			}
			@for (f in facts) {
				var label = str(f)
				return (
					<Row key={ f } text={ label } />
				)
			}
			@while (count < 0) {
				return (
					<Label text="never" />
				)
			}
			@match (level) {
				@case (1) {
					return (
						<Label text="one" />
					)
				}
				@default {
					return (
						<Label text="rest" />
					)
				}
			}
			<HBoxContainer>
				<Button text="go" onPressed={ func(): s[1].call(0) } />
				{ title }
			</HBoxContainer>
		</VBoxContainer>
	)
}
"""

const STYLE_SRC := """export primary := {
	"bg_color": Color(0.2, 0.5, 0.8),
	"corner_radius": 6,
	"nested": { "a": 1, "b": 2 },
}

export accent := {
	"font_size": 18,
}
"""

const HOOKS_SRC := """export use_facts(level: int) -> Array {
	var out = []
	for i in level:
		out.append(i)
	return out
}
"""

const UTIL_SRC := """export clamp01(v: float) -> float {
	return maxf(0.0, minf(1.0, v))
}
"""

const DATA_SRC := """export LEVELS: Array = [1, 2, 3]
"""

const ROW_SRC := """export Row(text: String = "") -> RuitkVNode {
	return (
		<Label text={ text } />
	)
}
"""


func _build_fixture() -> void:
	_rm_rf(ROOT.get_base_dir())
	_ws = Workspace.new()
	_ws.create_new(ROOT.path_join("app.guitkx"), APP_SRC)
	_ws.create_new(ROOT.path_join("app.style.guitkx"), STYLE_SRC)
	_ws.create_new(ROOT.path_join("app.hooks.guitkx"), HOOKS_SRC)
	_ws.create_new(ROOT.path_join("util.guitkx"), UTIL_SRC)
	_ws.create_new(ROOT.path_join("data.guitkx"), DATA_SRC)
	_ws.create_new(ROOT.path_join("components/row/row.guitkx"), ROW_SRC)


func _rm_rf(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var d := DirAccess.open(path)
	if d == null:
		return
	for file in d.get_files():
		DirAccess.remove_absolute(path.path_join(file))
	for sub in d.get_directories():
		_rm_rf(path.path_join(sub))
	DirAccess.remove_absolute(path)


func _card(name: String) -> Graph.Card:
	return _graph.card_of(ROOT.path_join(name))


# ── Membership ───────────────────────────────────────────────────────────────────────

func _test_membership_and_order() -> void:
	_section("membership is the whole tree, in a stable order")
	_eq(_graph.cards.size(), 6, "every module gets a card")
	var titles := PackedStringArray()
	for c in _graph.cards:
		titles.append(c.file_path.trim_prefix(ROOT + "/"))
	_eq(", ".join(titles),
		"app.guitkx, app.hooks.guitkx, app.style.guitkx, components/row/row.guitkx, data.guitkx, util.guitkx",
		"cards are ordered by path, so a card INDEX addresses the same module across projections")
	_check(_graph.index_of(ROOT.path_join("data.guitkx")) >= 0, "index_of finds a card")
	_check(_graph.index_of("res://nope.guitkx") == -1, "and reports -1 for one it does not hold")

	_section("cards carry the module identity, not just its path")
	var app := _card("app.guitkx")
	var module := _ws.try_get(ROOT.path_join("app.guitkx"))
	_eq(app.module_id, module.id, "the card carries the module's stable id")
	_eq(_graph.index_of_id(module.id), _graph.index_of(app.file_path),
		"so a saved position keyed on the id finds the same card after a rename")
	_check(_graph.index_of_id("") == -1, "an empty id is not-found, not card zero")

	_section("the root is the component that owns the tree folder")
	_eq(_graph.root_path, ROOT.path_join("app.guitkx"), "app owns the app/ folder")


# ── Kinds and signatures ─────────────────────────────────────────────────────────────

func _test_kinds_and_signatures() -> void:
	_section("kinds come from the DECLARATION")
	var K := Module.Kind
	_eq(_card("app.guitkx").kind, K.COMPONENT, "a `-> RuitkVNode` declaration is a component")
	_eq(_card("app.hooks.guitkx").kind, K.HOOK, "a `use_`-prefixed declaration is a hook")
	_eq(_card("util.guitkx").kind, K.UTIL, "a plain callable is a util")
	_eq(_card("data.guitkx").kind, K.VALUE, "a `name: Type = ...` declaration is a value")
	_eq(_card("app.style.guitkx").kind, K.STYLE,
		"a value module in a `.style.guitkx` file reads as a STYLE -- the one presentational refinement")
	_eq(Service.classify(DATA_SRC, "res://x/whatever.style.guitkx"), K.STYLE,
		"the refinement is the SUFFIX's only say")
	_eq(Service.classify("", "res://x/thing.hooks.guitkx"), K.HOOK,
		"and the suffix is the fallback when there is nothing to classify")
	_eq(Service.classify("", ""), K.UNKNOWN, "with no name and no declaration there is nothing to say")

	_section("signatures are structural, and one line")
	_eq(_card("app.guitkx").signature,
		"App(level: int = 1, title: String = \"hi\") -> RuitkVNode",
		"a head that wraps across lines collapses to one row")
	_eq(_card("app.hooks.guitkx").signature, "use_facts(level: int) -> Array", "hook signature")
	_eq(_card("util.guitkx").signature, "clamp01(v: float) -> float", "util signature")
	_eq(_card("data.guitkx").signature, "LEVELS: Array", "a value shows its type, not a parameter list")
	_eq(_card("app.style.guitkx").signature, "primary", "an inferred value shows its name alone")

	_section("what a module hands back")
	_eq(_card("app.hooks.guitkx").exposed_signature, "Array", "a hook's return type is worth a row")
	_eq(_card("app.guitkx").exposed_signature, "",
		"a component always returns markup, so saying so adds nothing")

	_section("exports")
	_eq(", ".join(_card("app.style.guitkx").exports), "primary, accent", "both style exports listed")
	_eq(", ".join(_card("app.guitkx").exports), "App", "the component's single export")


# ── Imports ──────────────────────────────────────────────────────────────────────────

func _test_import_rows() -> void:
	_section("every import line gets a row, in source order")
	var app := _card("app.guitkx")
	var rendered := PackedStringArray()
	for row in app.imports:
		rendered.append("%d|%s|%s" % [row.badge, row.name, row.text])
	_eq("\n".join(rendered), """10|./app.hooks|import * as AppHooks from "./app.hooks"
11|./app.style|import { primary as brand } from "./app.style"
9|./components/row/row|import { Row } from "./components/row/row"
9|./nowhere|import { Missing } from "./nowhere"
12|res://tests/__builder_graph_tmp/app/theme.tres|@uss "res://tests/__builder_graph_tmp/app/theme.tres\"""",
		"import rows: badge, specifier, reconstructed text")

	_eq(app.imports[0].badge, Graph.Badge.IMPORT_HOOKS, "a `.hooks` specifier takes the hooks dot")
	_eq(app.imports[1].badge, Graph.Badge.IMPORT_STYLE, "a `.style` specifier takes the style dot")
	_eq(app.imports[2].badge, Graph.Badge.IMPORT_PLAIN, "anything else takes the plain dot")
	_eq(app.imports[4].badge, Graph.Badge.IMPORT_ASSET,
		"a theme directive names a RESOURCE, so it gets no anchor dot")

	_section("an alias binds under the alias")
	_eq(", ".join(app.imports[1].attr_pairs), "brand",
		"`primary as brand` binds `brand` -- the name the rest of the file uses")
	_eq(", ".join(app.imports[0].attr_pairs), "AppHooks", "a namespace import binds its own name")

	_section("import rows carry their source position")
	_eq(app.imports[0].source_line, 1, "the first import is on line 1")
	_eq(app.imports[4].source_line, 5, "the theme directive is on line 5")


# ── Edges ────────────────────────────────────────────────────────────────────────────

func _test_edges() -> void:
	_section("one edge per resolvable import row")
	var app_index := _graph.index_of(ROOT.path_join("app.guitkx"))
	var out := _graph.edges_from(app_index)
	_eq(out.size(), 4, "four module imports, four edges -- the theme directive is not one")

	var rendered := PackedStringArray()
	for e in out:
		var target := "<broken>" if e.is_broken() else _graph.cards[e.to_index].file_path.trim_prefix(ROOT + "/")
		rendered.append("%s -> %s (%d)" % [e.specifier, target, e.target_kind])
	_eq("\n".join(rendered), """./app.hooks -> app.hooks.guitkx (1)
./app.style -> app.style.guitkx (2)
./components/row/row -> components/row/row.guitkx (0)
./nowhere -> <broken> (6)""",
		"edges resolve to cards and carry the target's kind")

	_section("a broken import keeps its edge")
	# The card paints an anchor dot per import row, so an edge that vanished would leave a dot
	# with no line and nothing to say why.
	var broken := out[3]
	_check(broken.is_broken(), "the unresolvable import is marked broken")
	_eq(broken.specifier, "./nowhere", "and still names what the user typed")

	_section("edges_to answers who depends on a card")
	var row_index := _graph.index_of(ROOT.path_join("components/row/row.guitkx"))
	_eq(_graph.edges_to(row_index).size(), 1, "one importer of the row component")
	_eq(_graph.edges_to(_graph.index_of(ROOT.path_join("util.guitkx"))).size(), 0,
		"and none for a module nothing imports yet")


# ── Body ─────────────────────────────────────────────────────────────────────────────

func _test_hook_chips() -> void:
	_section("hook chips")
	var app := _card("app.guitkx")
	var rendered := PackedStringArray()
	for row in app.body:
		rendered.append("%s @%d" % [row.text, row.source_line])
	_eq("\n".join(rendered), """useState  →  s @9
AppHooks.use_facts  →  facts @11""",
		"every hook call becomes a chip, with what it binds and where it is")
	_eq(app.body[1].name, "AppHooks.use_facts",
		"a namespace-qualified hook keeps its qualifier -- two modules' hooks are not one chip")

	_section("a hook module does not chip its own declaration")
	# `use_facts(` at the top of the file is a DECLARATION, and a scan that only looked at text
	# would file it as the first call the body makes.
	_eq(_card("app.hooks.guitkx").body.size(), 0,
		"the hook module declares a hook and calls none")

	_section("a util module has no chips either")
	_eq(_card("util.guitkx").body.size(), 0, "nothing in it looks like a hook")


func _test_island() -> void:
	_section("the code island is setup minus the hook lines")
	var app := _card("app.guitkx")
	_eq("\n".join(app.island_lines), "var count = s[0]",
		"the hook-call lines are chips, so the island holds what is left")
	_eq(app.island_start_line, 10, "and the range it occupies starts where that line is")
	_eq(app.island_end_line, 10, "and ends there")
	_eq(_card("app.hooks.guitkx").island_lines.size(), 0,
		"a non-component has no island -- its body is its export detail")


# ── Markup ───────────────────────────────────────────────────────────────────────────

func _test_markup_golden() -> void:
	_section("the markup tree, flattened")
	_eq(_render_markup(_card("app.guitkx")), """VBoxContainer  el  style={brand}
  Label  el/  text={title}
  @if  dir(1)  @if (count > 5)
    Label  el/  text="high"
  @elif  dir(2)  @elif (count > 2)
    Label  el/  text="mid"
  @else  dir(3)  @else
    Label  el/  text="low"
  @for  dir(4)  @for (f in facts)
    var label = str(f)  code
    Row  comp/  key={f} text={label}
  @while  dir(5)  @while (count < 0)
    Label  el/  text="never"
  @match  dir(6)  @match (level)
    @case  dir(7)  @case (1)
      Label  el/  text="one"
    @default  dir(8)  @default
      Label  el/  text="rest"
  HBoxContainer  el
    Button  el/  text="go" onPressed={func(): s[1].call(0)}
    {title}  expr""",
		"one row per node, depth-nested, with kind, self-closing and attributes")

	_section("a nested component is a component row, a host class is an element row")
	var app := _card("app.guitkx")
	var row_line := _find_row(app.markup, "Row")
	_check(row_line != null and row_line.kind == Graph.LineKind.COMPONENT,
		"`Row` is not a Godot class, so it is a user component")
	var label := _find_row(app.markup, "Label")
	_check(label != null and label.kind == Graph.LineKind.ELEMENT,
		"`Label` is a Godot class, so it is a host element")

	_section("a single-root component has one root row at depth 0")
	var roots := 0
	for r in app.markup:
		if r.depth == 0:
			roots += 1
	_eq(roots, 1, "exactly one row sits at depth 0")


func _test_directive_families() -> void:
	_section("every directive family projects as its own row")
	var app := _card("app.guitkx")
	var heads: Array = []
	for r in app.markup:
		if r.kind == Graph.LineKind.DIRECTIVE:
			heads.append(r)
	_eq(heads.size(), 8, "@if, @elif, @else, @for, @while, @match, @case, @default")

	_section("a clause is a row of its own, not a badge riding its first child")
	# A badge on the clause's first child cannot be selected when the clause is empty, and shows
	# once for a clause that has two children.
	for h in heads:
		_check(not h.badge_text.is_empty(), "%s carries its own label" % h.text)

	_section("a continuation clause is never draggable on its own")
	_eq(heads[0].clause_index, 0, "@if is the construct head")
	_check(heads[1].clause_index > 0, "@elif is a bound continuation")
	_check(heads[2].clause_index > 0, "@else is a bound continuation")
	_eq(heads[3].clause_index, 0, "@for is a construct head")
	_eq(heads[4].clause_index, 0, "@while is a construct head")
	_eq(heads[5].clause_index, 0, "@match is a construct head")
	_check(heads[6].clause_index > 0, "@case is a bound continuation")
	_check(heads[7].clause_index > 0, "@default is a bound continuation")

	_section("a head knows where its construct closes")
	for h in heads:
		_check(h.close_line >= h.source_line,
			"%s closes at or after it opens (%d >= %d)" % [h.badge_text, h.close_line, h.source_line])

	_section("prep code inside a clause is shown, not swallowed")
	var prep := _find_row(app.markup, "")
	_check(_render_markup(app).contains("var label = str(f)  code"),
		"the loop body's own statement gets a row")


func _test_spans_address_the_source() -> void:
	_section("every row's span addresses exactly what it came from")
	# This is what a span-exact edit depends on: replace [at, end_at) and you have replaced the
	# row, with nothing of its neighbours caught in the range.
	var app := _card("app.guitkx")
	var source := _ws.try_get(app.file_path).buffer_text
	var checked := 0
	for row in app.markup:
		if row.kind != Graph.LineKind.ELEMENT and row.kind != Graph.LineKind.COMPONENT:
			continue
		var span := source.substr(row.at, row.end_at - row.at)
		_check(span.begins_with("<" + row.name),
			"the span of `%s` starts at its own tag (got %s)" % [row.name, span.substr(0, 20)])
		if row.self_closing:
			_check(span.strip_edges().ends_with("/>"),
				"a self-closing `%s` span ends at its own `/>`" % row.name)
		else:
			_check(span.strip_edges().ends_with("</%s>" % row.name),
				"a `%s` span ends at its own closing tag" % row.name)
		checked += 1
	_check(checked >= 8, "the check actually ran over the tree (%d element rows)" % checked)

	_section("a row's line range matches its span")
	for row in app.markup:
		if row.end_line == 0:
			continue
		var start_line := source.substr(0, row.at).count("\n") + 1
		_eq(row.source_line, start_line, "row `%s` starts on the line its offset falls on" % row.text)

	_section("an expression row's span is the braces, matched")
	# Sized from the trimmed code instead, the span stops short of the closing brace whenever the
	# expression has padding -- and a span-exact edit then writes over the `}`.
	var expr := _find_row_of_kind(app.markup, Graph.LineKind.EXPRESSION)
	_check(expr != null, "the `{ title }` child slot has a row")
	if expr != null:
		var span := source.substr(expr.at, expr.end_at - expr.at)
		_eq(span, "{ title }", "and its span is exactly what the user wrote, padding included")

	_section("import spans too")
	for row in app.imports:
		var span := source.substr(row.at, row.end_at - row.at)
		_check(span.begins_with("import") or span.begins_with("@uss") or span.begins_with("@theme"),
			"an import row's span starts at the directive (got %s)" % span.substr(0, 12))


# ── Export detail ────────────────────────────────────────────────────────────────────

func _test_export_detail() -> void:
	_section("a style module lists its entries")
	_eq(_render_detail(_card("app.style.guitkx")), """primary  export  [STYLE_HEADER]
  "bg_color": Color(0.2, 0.5, 0.8)  plain
  "corner_radius": 6  plain
  "nested": { "a": 1, "b": 2 }  plain
  + entry  plain  [ADD_ENTRY]
accent  export  [STYLE_HEADER]
  "font_size": 18  plain
  + entry  plain  [ADD_ENTRY]""",
		"each export, its top-level entries, and the affordance that adds one")

	_section("a nested dictionary stays ONE entry")
	# Split at top-level commas only: a naive split tears `{ \"a\": 1, \"b\": 2 }` into two
	# fragments that are not entries of anything.
	var style := _card("app.style.guitkx")
	var nested := _find_row(style.export_detail, "nested")
	_check(nested != null and nested.text == "\"nested\": { \"a\": 1, \"b\": 2 }",
		"the nested dictionary survives whole")

	_section("a non-style module lists its declarations")
	_eq(_render_detail(_card("util.guitkx")), "clamp01(v: float) -> float  export  [UTIL_BODY]",
		"a util shows its signature")
	_eq(_render_detail(_card("app.hooks.guitkx")), "use_facts(level: int) -> Array  export  [UTIL_BODY]",
		"so does a hook")
	_eq(_render_detail(_card("data.guitkx")), "LEVELS: Array  export  [UTIL_BODY]",
		"and a value")

	_section("a component has no export detail -- it has markup")
	_eq(_card("app.guitkx").export_detail.size(), 0, "the sections are exclusive")


# ── Layout ───────────────────────────────────────────────────────────────────────────

func _test_positions() -> void:
	_section("seeded positions are deterministic")
	var again := Service.project(_ws.modules(), ROOT.path_join("app.guitkx"))
	var drift := 0
	for i in range(_graph.cards.size()):
		if _graph.cards[i].x != again.cards[i].x or _graph.cards[i].y != again.cards[i].y:
			drift += 1
	_eq(drift, 0, "two projections of one tree lay it out identically -- nothing moves on its own")

	_section("the root anchors the first column")
	var app := _card("app.guitkx")
	_eq(app.x, 0.0, "the root sits in column zero")
	var row := _card("components/row/row.guitkx")
	_check(row.x > app.x, "what the root imports sits to its right")

	_section("a module nothing imports gets a column of its own")
	# Mixed into a column of real dependents, an unwired module reads as a dependency it does
	# not have.
	var util := _card("util.guitkx")
	_check(util.x > row.x,
		"the unwired module sits past the deepest reachable column (%f > %f)" % [util.x, row.x])
	_eq(_card("data.guitkx").x, util.x, "and every unwired module shares that column")

	_section("no two cards share a slot")
	var slots := {}
	for c in _graph.cards:
		var slot := "%f,%f" % [c.x, c.y]
		_check(not slots.has(slot), "%s has a slot of its own" % c.title)
		slots[slot] = true


func _test_refresh_edges() -> void:
	_section("re-projecting a card rebuilds what it points at")
	# Imports are STRUCTURE. A card whose content was re-read but whose edges were not would
	# paint an anchor dot for the new import with no line running from it.
	var graph := Service.project(_ws.modules(), ROOT.path_join("app.guitkx"))
	var util_index := graph.index_of(ROOT.path_join("util.guitkx"))
	_eq(graph.edges_from(util_index).size(), 0, "the util imports nothing to begin with")

	var util := graph.cards[util_index]
	Service.populate_card(util, "import { clamp01 as c } from \"./data\"\n\n" + UTIL_SRC)
	_eq(graph.edges_from(util_index).size(), 0,
		"populating the CARD alone does not touch the edges -- they are structure")
	Service.refresh_edges_for(graph, util_index)
	var refreshed := graph.edges_from(util_index)
	_eq(refreshed.size(), 1, "refreshing rebuilds them")
	_eq(refreshed[0].specifier, "./data", "pointing where the new import says")
	_eq(refreshed[0].to_index, graph.index_of(ROOT.path_join("data.guitkx")), "at the right card")

	_section("refreshing one card leaves every other edge alone")
	var app_index := graph.index_of(ROOT.path_join("app.guitkx"))
	_eq(graph.edges_from(app_index).size(), 4, "the app's edges are untouched")
	Service.refresh_edges_for(graph, -1)
	Service.refresh_edges_for(graph, 999)
	Service.refresh_edges_for(null, 0)
	_eq(graph.edges.size(), 5, "an out-of-range refresh is a no-op, not a wipe")


# ── Degenerate input ─────────────────────────────────────────────────────────────────

func _test_degenerate_buffers() -> void:
	_section("a module that does not parse still gets its card")
	var card := Graph.Card.new()
	card.file_path = "res://x/half_typed.guitkx"
	Service.populate_card(card, "export Broken() -> RuitkVNode {\n\treturn ( <Label \n")
	_check(true, "projecting an unterminated buffer does not stop the run")
	_eq(card.markup.size(), 0, "the markup section is empty -- there is no tree to show")
	_eq(_render_detail(card), "Broken() -> RuitkVNode  export  [UTIL_BODY]",
		"but the card falls back to its declaration, so it is not two empty sections")

	_section("an empty buffer")
	var empty := Graph.Card.new()
	empty.file_path = "res://x/empty.guitkx"
	Service.populate_card(empty, "")
	_eq(empty.kind, Module.Kind.COMPONENT, "an empty `.guitkx` falls back to the suffix")
	_eq(empty.signature, "", "with nothing to say about a signature")
	_eq(empty.imports.size(), 0, "and no rows anywhere")
	_eq(empty.body.size(), 0, "none")
	_eq(empty.export_detail.size(), 0, "none")

	_section("an empty tree")
	var none := Service.project([], "")
	_eq(none.cards.size(), 0, "projects to no cards")
	_eq(none.edges.size(), 0, "and no edges")
	_eq(none.root_path, "", "and no root")

	_section("a projection ignores anything that is not a module")
	var mixed := Service.project(["not a module", 42, null], "")
	_eq(mixed.cards.size(), 0, "nothing that is not a module reaches the canvas")

	_section("re-populating a card replaces its sections rather than appending")
	var again := _card("app.guitkx")
	var before := again.markup.size()
	Service.populate_card(again, APP_SRC)
	_eq(again.markup.size(), before, "the second projection is the same size as the first")
	_eq(again.exports.size(), 1, "and the export list did not double")

	_rm_rf(ROOT.get_base_dir())
	_check(not DirAccess.dir_exists_absolute(ROOT.get_base_dir()),
		"the run leaves nothing behind -- the fixture never touched disk in the first place")


# ── Rendering helpers ────────────────────────────────────────────────────────────────

## One compact line per markup row, so a whole tree can be asserted as a literal.
func _render_markup(card: Graph.Card) -> String:
	var out := PackedStringArray()
	for row in card.markup:
		var indent := "  ".repeat(row.depth)
		var tail := ""
		match row.kind:
			Graph.LineKind.ELEMENT:
				tail = "  el/" if row.self_closing else "  el"
			Graph.LineKind.COMPONENT:
				tail = "  comp/" if row.self_closing else "  comp"
			Graph.LineKind.DIRECTIVE:
				tail = "  dir(%d)" % row.badge
			Graph.LineKind.EXPRESSION:
				tail = "  expr"
			Graph.LineKind.TEXT:
				tail = "  text"
			_:
				tail = "  code"
		var head := row.name if not row.name.is_empty() else row.text
		if row.kind == Graph.LineKind.DIRECTIVE:
			head = row.badge_text
			tail += "  " + row.directive_text
		elif row.kind == Graph.LineKind.EXPRESSION:
			head = row.text
		elif row.kind == Graph.LineKind.PLAIN:
			head = row.text
		elif not row.attrs_text.is_empty():
			tail += "  " + row.attrs_text
		out.append(indent + head + tail)
	return "\n".join(out)


func _render_detail(card: Graph.Card) -> String:
	var out := PackedStringArray()
	for row in card.export_detail:
		var indent := "  ".repeat(row.depth)
		var kind := "export" if row.kind == Graph.LineKind.EXPORT else "plain"
		var badge := ""
		match row.badge:
			Graph.Badge.STYLE_HEADER:
				badge = "  [STYLE_HEADER]"
			Graph.Badge.UTIL_BODY:
				badge = "  [UTIL_BODY]"
			Graph.Badge.ADD_ENTRY:
				badge = "  [ADD_ENTRY]"
		out.append("%s%s  %s%s" % [indent, row.text, kind, badge])
	return "\n".join(out)


func _find_row(rows: Array, name: String) -> Graph.Line:
	for row in rows:
		if (row as Graph.Line).name == name:
			return row
	return null


func _find_row_of_kind(rows: Array, kind: Graph.LineKind) -> Graph.Line:
	for row in rows:
		if (row as Graph.Line).kind == kind:
			return row
	return null
