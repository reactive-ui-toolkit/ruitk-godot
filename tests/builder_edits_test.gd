extends SceneTree
## Headless test suite for the RUITK Builder's EDIT OPERATIONS (checkpoint C5). Run:
##   godot --headless --path <project> --script res://tests/builder_edits_test.gd
##
## Every structural edit is a pure text transform, so every assertion is a before/after string.
## That is the whole reason the operations are shaped this way: an edit that produces the wrong
## text is a defect you can read, not one you have to reproduce through a gesture.
##
## Each case ALSO re-compiles the result. A transform that produces plausible-looking text that
## does not compile is the failure mode that matters -- and it is invisible to a string
## comparison, because the string looks right.

const Edits = preload("res://addons/reactive_ui_toolkit_editor/builder/edits/builder_edits.gd")
const Service = preload("res://addons/reactive_ui_toolkit_editor/builder/canvas/builder_graph_service.gd")
const Graph = preload("res://addons/reactive_ui_toolkit_editor/builder/canvas/builder_graph.gd")
const Module = preload("res://addons/reactive_ui_toolkit_editor/builder/document/builder_module.gd")
const Compiler = preload("res://addons/reactive_ui_toolkit/guitkx/guitkx.gd")
const Metrics = preload("res://addons/reactive_ui_toolkit_editor/builder/canvas/builder_canvas_metrics.gd")
const Drag = preload("res://addons/reactive_ui_toolkit_editor/builder/edits/builder_drag.gd")
const Workspace = preload("res://addons/reactive_ui_toolkit_editor/builder/document/builder_workspace.gd")

## The number of assertions a complete run makes. KEPT EXACT, and raised with the suite.
##
## Left slack, this guard does not work: a script error aborted one test mid-run and the suite
## still printed ALL PASS, because the count it reached was comfortably above a floor set several
## additions ago. The floor only catches a truncated run while it sits AT the real count.
const ASSERTION_FLOOR := 185

var _fails := 0
var _passes := 0


func _initialize() -> void:
	_test_insert_placements()
	_test_insert_into_self_closing()
	_test_remove()
	_test_move()
	_test_attributes()
	_test_directive_headers()
	_test_wrap_in_directive()
	_test_clauses()
	_test_unwrap()
	_test_wrap_variants()
	_test_island()
	_test_imports()
	_test_import_bindings()
	_test_setup_lines()
	_test_style_entries()
	_test_templates()
	_test_indent_is_read_from_the_file()
	_test_row_bands()
	_test_drag_survives_a_rerender()

	print("")
	# A FLOOR ON THE COUNT. A suite that stops at a broken dependency prints ALL PASS on however
	# few assertions it reached before it stopped -- which is a green line for a run that never
	# arrived at its own subject, and it has now hidden three separate defects in this builder.
	# The number is the tell, so the number is checked.
	if _passes < ASSERTION_FLOOR:
		print("builder edits: only %d of at least %d assertions ran -- something stopped early"
			% [_passes, ASSERTION_FLOOR])
		quit(1)
	if _fails == 0:
		print("builder edits: ALL PASS (%d assertions)" % _passes)
		quit(0)
	else:
		print("builder edits: %d FAILURE(S) of %d assertions" % [_fails, _fails + _passes])
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
	print("  FAIL  %s\n--- got ---\n%s\n--- want ---\n%s\n---" % [what, got, want])


func _section(title: String) -> void:
	print(title)


# ── Fixture ──────────────────────────────────────────────────────────────────────────

const SRC := """export App(level: int = 1) -> RuitkVNode {
  var s = useState(0)
  return (
    <VBoxContainer>
      <Label text="one" />
      <HBoxContainer>
        <Button text="go" />
      </HBoxContainer>
      @if (level > 1) {
        return (
          <Label text="deep" />
        )
      }
    </VBoxContainer>
  )
}
"""


## The projected card for a buffer -- the rows every operation is addressed by.
func _card(source: String) -> Graph.Card:
	var card := Graph.Card.new()
	card.file_path = "res://tests/__edits/app.guitkx"
	Service.populate_card(card, source)
	return card


func _row(source: String, tag: String) -> Graph.Line:
	for row in _card(source).markup:
		if row.name == tag:
			return row
	return null


func _directive(source: String, label: String) -> Graph.Line:
	for row in _card(source).markup:
		if row.badge_text == label:
			return row
	return null


## Every operation has to leave a file the compiler still accepts. A transform that produces
## plausible text that does not compile is exactly the failure a string comparison misses.
func _compiles(source: String, what: String) -> void:
	var result := Compiler.compile(source, "app")
	if bool(result.get("ok", false)):
		_passes += 1
		return
	_fails += 1
	var reasons := PackedStringArray()
	for d in (result.get("diagnostics", []) as Array):
		if int((d as Dictionary).get("severity", 0)) == 0:
			reasons.append("%s %s" % [(d as Dictionary).get("code", ""), (d as Dictionary).get("message", "")])
	print("  FAIL  %s still compiles\n        %s\n--- source ---\n%s\n---" % [what, ", ".join(reasons), source])


# ── Insert ───────────────────────────────────────────────────────────────────────────

func _test_insert_placements() -> void:
	_section("inserting before, inside and after a row")
	var before := Edits.insert(SRC, _card(SRC), _row(SRC, "HBoxContainer"), "<ColorRect />", Edits.Placement.BEFORE)
	_check(before.contains("      <ColorRect />\n      <HBoxContainer>"),
		"BEFORE puts it on its own line above, at the row's own indent")
	_compiles(before, "an insert before")

	var after := Edits.insert(SRC, _card(SRC), _row(SRC, "HBoxContainer"), "<ColorRect />", Edits.Placement.AFTER)
	_check(after.contains("</HBoxContainer>\n      <ColorRect />"),
		"AFTER puts it below the whole subtree, not below the opening tag")
	_compiles(after, "an insert after")

	var inside := Edits.insert(SRC, _card(SRC), _row(SRC, "HBoxContainer"), "<ColorRect />", Edits.Placement.INSIDE)
	_check(inside.contains("<Button text=\"go\" />\n        <ColorRect />\n      </HBoxContainer>"),
		"INSIDE puts it last among the children, above the close tag")
	_compiles(inside, "an insert inside")

	_section("a directive clause takes a child like anything else")
	var into_if := Edits.insert(SRC, _card(SRC), _row(SRC, "VBoxContainer"), "<Label text=\"tail\" />",
		Edits.Placement.INSIDE)
	_check(into_if.contains("<Label text=\"tail\" />\n    </VBoxContainer>"),
		"the root element's last child lands above its close tag")
	_compiles(into_if, "an insert into the root")

	_section("FIRST_CHILD lands under the OPEN TAG, not past the block")
	# The canvas lists markup FLATTENED, so the row for `<HBoxContainer>` is only its open tag and
	# the gap drawn under it is visually the gap before its first child. AFTER inserts past every
	# descendant -- the same gesture read in two different coordinate systems.
	var first := Edits.insert(SRC, _card(SRC), _row(SRC, "HBoxContainer"), "<ColorRect />",
		Edits.Placement.FIRST_CHILD)
	_check(first.contains("<HBoxContainer>
        <ColorRect />"),
		"it becomes the first child, one indent in")
	_check(not first.contains("</HBoxContainer>
      <ColorRect />"),
		"and NOT below the whole subtree, which is where AFTER puts it")
	_compiles(first, "an insert as first child")

	_section("a self-closing target has no inside to be first in")
	var reopened := Edits.insert(SRC, _card(SRC), _row(SRC, "Label"), "<ColorRect />",
		Edits.Placement.FIRST_CHILD)
	_check(reopened.contains("<ColorRect />"), "so it falls back to re-opening the tag")
	_compiles(reopened, "a first-child insert into a self-closing element")

	_section("refusals")
	_eq(Edits.insert(SRC, _card(SRC), null, "<X />", Edits.Placement.INSIDE), SRC, "no row, no edit")
	_eq(Edits.insert(SRC, _card(SRC), _row(SRC, "Label"), "   ", Edits.Placement.INSIDE), SRC,
		"nothing to insert, no edit")


func _test_insert_into_self_closing() -> void:
	_section("a self-closing element is RE-OPENED to take a child")
	# A tag that closes itself has nowhere to put one, and refusing the drop would make half the
	# elements on a card undroppable for a reason the user cannot see.
	var row := _row(SRC, "Label")
	_check(row.self_closing, "the fixture's Label really is self-closing")
	var opened := Edits.insert(SRC, _card(SRC), row, "<ColorRect />", Edits.Placement.INSIDE)
	_check(opened.contains("<Label text=\"one\">"), "the tag is re-opened")
	_check(opened.contains("</Label>"), "and given a close tag")
	_check(opened.contains("<ColorRect />"), "with the child between them")
	_check(not opened.contains("<Label text=\"one\" />"), "and the self-closing form is gone")
	_compiles(opened, "a re-opened element")

	_section("its attributes survive the re-opening")
	_check(opened.contains("text=\"one\""), "the attribute is still there")


# ── Remove ───────────────────────────────────────────────────────────────────────────

func _test_remove() -> void:
	_section("removing a row takes its whole subtree")
	var without := Edits.remove(SRC, _row(SRC, "HBoxContainer"))
	_check(not without.contains("HBoxContainer"), "the element is gone")
	_check(not without.contains("<Button"), "and so is the child inside it")
	_check(without.contains("<Label text=\"one\" />"), "while its siblings stay")
	_compiles(without, "a removal")

	_section("removing a directive takes the whole construct")
	var no_if := Edits.remove(SRC, _directive(SRC, "@if"))
	_check(not no_if.contains("@if"), "the directive is gone")
	_check(not no_if.contains("deep"), "and so is its body")
	_check(no_if.contains("HBoxContainer"), "while the rest of the tree stays")
	_compiles(no_if, "a directive removal")

	_section("no blank line is left behind")
	_check(not without.contains("\n\n    </VBoxContainer>"),
		"the line the removal emptied goes with it")

	_eq(Edits.remove(SRC, null), SRC, "removing nothing changes nothing")


# ── Move ─────────────────────────────────────────────────────────────────────────────

func _test_move() -> void:
	_section("moving a row re-parents it")
	# The operation the Unity leg lists as unreliable. Cut and paste, with the paste offset
	# recomputed against the CUT text -- removing the source shifts everything after it.
	var card := _card(SRC)
	var label: Graph.Line = null
	var box: Graph.Line = null
	for row in card.markup:
		if row.name == "Label" and label == null:
			label = row
		if row.name == "HBoxContainer":
			box = row
	var moved := Edits.move(SRC, card, label, box, Edits.Placement.INSIDE)
	_check(moved.contains("<Button text=\"go\" />\n        <Label text=\"one\" />"),
		"the label is now inside the box, after its existing child")
	_eq(moved.count("<Label text=\"one\""), 1, "and there is exactly one of it")
	_compiles(moved, "a move")

	_section("a SIBLING drop where the language allows one root is refused")
	# A component's `return` holds one element and so does every `return` inside a directive
	# body, so dropping beside the only child of either produces a file that does not compile.
	var deep: Graph.Line = null
	for row in _card(SRC).markup:
		if row.name == "Label" and row.attrs_text.contains("deep"):
			deep = row
	_check(deep != null, "the fixture has an element inside a directive body")
	var verdict := Edits.can_place(_card(SRC), deep, Edits.Placement.AFTER)
	_check(not bool(verdict["ok"]), "the placement is refused")
	_check(str(verdict["reason"]).contains("fragment"),
		"with a reason that says what to do instead (%s)" % verdict["reason"])
	_eq(Edits.move(SRC, _card(SRC), _row(SRC, "Button"), deep, Edits.Placement.AFTER), SRC,
		"and the move produces nothing rather than an uncompilable file")

	_section("the root element has the same rule")
	var at_root := Edits.can_place(_card(SRC), _row(SRC, "VBoxContainer"), Edits.Placement.BEFORE)
	_check(not bool(at_root["ok"]), "a component returns exactly one root element")

	_section("but INSIDE is always allowed")
	_check(bool(Edits.can_place(_card(SRC), deep, Edits.Placement.INSIDE)["ok"]),
		"an element can always take another child")
	var into_deep := Edits.move(SRC, _card(SRC), _row(SRC, "Button"), deep, Edits.Placement.INSIDE)
	_eq(into_deep.count("<Button"), 1, "the button moved rather than being copied")
	_check(into_deep.contains("<Label text=\"deep\">"), "into the row it was dropped on")
	_compiles(into_deep, "a move into a directive body's element")

	_section("moving DOWNWARD lands where the user pointed")
	# The direction that goes wrong when the paste offset is not recomputed: cutting from above
	# the target shifts the target, so the paste lands one subtree too late.
	var down := Edits.move(SRC, _card(SRC), _row(SRC, "Label"), _row(SRC, "Button"),
		Edits.Placement.AFTER)
	_eq(down.count("<Label text=\"one\""), 1, "the label moved rather than being copied")
	_check(down.contains("<Button text=\"go\" />\n        <Label text=\"one\" />"),
		"and landed directly after the row it was dropped on")
	_compiles(down, "a downward move")

	_section("a subtree cannot become its own child")
	var into_self := Edits.move(SRC, _card(SRC), _row(SRC, "HBoxContainer"), _row(SRC, "Button"),
		Edits.Placement.INSIDE)
	_eq(into_self, SRC, "the move is refused rather than losing the subtree")
	_eq(Edits.move(SRC, _card(SRC), null, _row(SRC, "Button"), Edits.Placement.INSIDE), SRC,
		"moving nothing changes nothing")


# ── Attributes ───────────────────────────────────────────────────────────────────────

func _test_attributes() -> void:
	_section("setting an attribute")
	var replaced := Edits.set_attribute(SRC, _row(SRC, "Label"), "text", "two", true)
	_check(replaced.contains("<Label text=\"two\" />"), "an existing attribute is replaced")
	_eq(replaced.count("<Label text=\"two\""), 1, "and not duplicated")
	_compiles(replaced, "a replaced attribute")

	var added := Edits.set_attribute(SRC, _row(SRC, "Label"), "visible", "true", false)
	_check(added.contains("<Label text=\"one\" visible={ true } />"),
		"a new attribute lands at the end of the list, before the terminator")
	_compiles(added, "an added attribute")

	_section("the caller says whether it means a literal or an expression")
	# The two are different things to the compiler, and `{` inside a string is an ordinary
	# character -- so guessing from the value's shape would be wrong for real content.
	var literal := Edits.set_attribute(SRC, _row(SRC, "Label"), "text", "{ not code }", true)
	_check(literal.contains("text=\"{ not code }\""), "a quoted value stays a string")
	var expr := Edits.set_attribute(SRC, _row(SRC, "Label"), "text", "s[0]", false)
	_check(expr.contains("text={ s[0] }"), "and an expression stays an expression")
	_compiles(expr, "an expression attribute")

	_section("setting one on a NON-self-closing element")
	var on_box := Edits.set_attribute(SRC, _row(SRC, "HBoxContainer"), "name", "row", true)
	_check(on_box.contains("<HBoxContainer name=\"row\">"), "it lands before the `>`")
	_compiles(on_box, "an attribute on an open tag")

	_section("removing an attribute takes its separating space")
	var gone := Edits.remove_attribute(SRC, _row(SRC, "Label"), "text")
	_check(gone.contains("<Label />"), "the tag closes up rather than drifting apart")
	_compiles(gone, "a removed attribute")
	_eq(Edits.remove_attribute(SRC, _row(SRC, "Label"), "nope"), SRC,
		"removing one that is not there changes nothing")

	_section("an attribute whose value contains a `>` is not mistaken for the tag end")
	var tricky := "export A() -> RuitkVNode {\n  return (\n    <Label text={ a > b } visible={ true } />\n  )\n}\n"
	var fixed := Edits.set_attribute(tricky, _row_of(tricky, "Label"), "visible", "false", false)
	_check(fixed.contains("visible={ false }"), "the right attribute is replaced")
	_check(fixed.contains("text={ a > b }"), "and the one holding the `>` is untouched")
	_compiles(fixed, "an attribute beside a `>` in an expression")


func _row_of(source: String, tag: String) -> Graph.Line:
	return _row(source, tag)


# ── Directives ───────────────────────────────────────────────────────────────────────

func _test_directive_headers() -> void:
	_section("editing a directive header")
	var edited := Edits.set_directive_header(SRC, _directive(SRC, "@if"), "level > 3")
	_check(edited.contains("@if (level > 3)"), "the condition is replaced")
	_check(edited.contains("<Label text=\"deep\" />"), "and the body is untouched")
	_compiles(edited, "an edited condition")

	_section("a clause with no header is left alone")
	# There is nothing to replace in an `@else`, and inventing a parenthesis would make it a
	# different construct.
	var with_else := SRC.replace("      }\n", "      } @else {\n        return (\n          <Label text=\"shallow\" />\n        )\n      }\n")
	var else_row := _directive(with_else, "@else")
	_check(else_row != null, "the fixture has an @else")
	_eq(Edits.set_directive_header(with_else, else_row, "anything"), with_else,
		"editing its header changes nothing")

	_eq(Edits.set_directive_header(SRC, _row(SRC, "Label"), "x"), SRC,
		"and an element row is not a directive")


# ── Imports ──────────────────────────────────────────────────────────────────────────

func _test_imports() -> void:
	_section("adding an import")
	var from := "res://ui/app/app.guitkx"
	var target := "res://ui/app/components/row/row.guitkx"
	var added := Edits.ensure_import(SRC, from, target, PackedStringArray(["Row"]))
	_check(added.begins_with("import { Row } from \"~/ui/app/components/row/row\"") \
			or added.begins_with("import { Row } from \"./components/row/row\""),
		"the specifier is the COMPILER's canonical spelling (%s)" % added.split("\n")[0])
	_check(added.contains("export App"), "and the declaration is still there")
	_compiles(added, "an added import")

	_section("an import that is already there is not duplicated")
	# Two imports of one module is GUITKX2303.
	_eq(Edits.ensure_import(added, from, target, PackedStringArray(["Row"])), added,
		"asking again changes nothing")

	_section("a second name joins the import that is already there")
	var both := Edits.ensure_import(added, from, target, PackedStringArray(["Row", "Cell"]))
	_check(both.contains("import { Row, Cell }"), "the names are merged into one import")
	_eq(both.count("from \""), 1, "rather than a second import of the same module")

	_section("removing an import")
	var without := Edits.remove_import(both, _spec_of(both))
	_check(not without.contains("import"), "the whole line goes")
	_check(not without.begins_with("\n"), "with its newline, so no gap is left")
	_compiles(without, "a removed import")

	var partial := Edits.remove_import(both, _spec_of(both), PackedStringArray(["Cell"]))
	_check(partial.contains("import { Row }"), "removing one name keeps the others")
	_eq(Edits.remove_import(SRC, "./nowhere"), SRC, "removing one that is not there changes nothing")

	_section("an import goes after the ones already in the preamble")
	var two := Edits.ensure_import(added, from, "res://ui/app/app.style.guitkx",
		PackedStringArray(["primary"]))
	var lines := two.split("\n")
	_check(str(lines[0]).begins_with("import") and str(lines[1]).begins_with("import"),
		"both imports lead the file")
	_compiles(two, "two imports")


func _spec_of(source: String) -> String:
	var imports := Compiler.scan_imports(source)
	return str((imports[0] as Dictionary)["spec"]) if not imports.is_empty() else ""


# ── Setup ────────────────────────────────────────────────────────────────────────────

## The import writer has to survive the file it is editing already having an ALIAS in it, and has
## to choose a binding that does not collide with what the file already means.
func _test_import_bindings() -> void:
	_section("adding a name to an aliased import keeps the alias")
	# `primary as brand` rebuilt from the local name alone became `brand` -- an import of a name
	# the target does not export -- so adding one style entry silently broke the file.
	var aliased := "import { primary as brand } from \"./app.style\"

" 		+ "export App() -> RuitkVNode {
	return (
		<Label />
	)
}
"
	var grown := Edits.ensure_import(aliased, "res://a/app.guitkx", "res://a/app.style.guitkx",
		PackedStringArray(["accent"]))
	_check(grown.contains("primary as brand"), "the alias survives")
	_check(grown.contains("accent"), "and the new name is there")

	_section("a name already imported is not imported twice")
	_eq(Edits.ensure_import(aliased, "res://a/app.guitkx", "res://a/app.style.guitkx",
		PackedStringArray(["primary"])), aliased,
		"asked for under its REMOTE name, which is what the target exports")

	_section("a binding that would collide with the file's own name is aliased")
	# A style module and the component it belongs to are named by two conventions that collapse
	# onto one identifier: `Card.guitkx` exporting `Card`, `card.style.guitkx` exporting `Card`.
	var component := "export Card() -> RuitkVNode {
	return (
		<Label />
	)
}
"
	var bound := Edits.bind_export(component, "res://a/Card.guitkx", "res://a/card.style.guitkx",
		"Card")
	_eq(str(bound["binding"]), "CardStyle", "so the import binds a name that cannot collide")
	_check(str(bound["text"]).contains("Card as CardStyle"), "written as an alias")

	_section("a module already imported keeps the binding it was given")
	# Styling a second element from the same module must reference the name the file actually
	# binds, not invent a fresh one.
	var again := Edits.bind_export(str(bound["text"]), "res://a/Card.guitkx",
		"res://a/card.style.guitkx", "Card")
	_eq(str(again["binding"]), "CardStyle", "the same binding")
	_eq(str(again["text"]), str(bound["text"]), "and no second import")

	_section("no collision, no alias")
	var plain := Edits.bind_export(component, "res://a/Card.guitkx",
		"res://a/card.style.guitkx", "panel")
	_eq(str(plain["binding"]), "panel", "the export name is used as it is")
	_check(not str(plain["text"]).contains(" as "), "with no alias in the line")


func _test_setup_lines() -> void:
	_section("a hook is inserted at the TOP of setup")
	# Hooks must run unconditionally and in a stable order. The end of setup is still legal, but
	# after an early return it is not -- the top is the only position that is always right.
	var with_hook := Edits.insert_setup_line(SRC, _card(SRC), "var r = useRef(null)")
	var body := with_hook.split("\n")
	_eq(str(body[1]).strip_edges(), "var r = useRef(null)", "it is the body's first line")
	_check(with_hook.contains("var s = useState(0)"), "and what was there is still there")
	_compiles(with_hook, "an inserted hook")

	_eq(Edits.insert_setup_line(SRC, null, "x"), SRC, "no card, no edit")
	_eq(Edits.insert_setup_line(SRC, _card(SRC), "  "), SRC, "nothing to insert, no edit")


# ── Style entries ────────────────────────────────────────────────────────────────────

func _test_style_entries() -> void:
	_section("adding a style entry")
	var style := "export primary := {\n  \"bg_color\": Color(0.2, 0.2, 0.3),\n}\n"
	var added := Edits.insert_style_entry(style, "primary", "corner_radius_all", "8")
	_check(added.contains("\"corner_radius_all\": 8,"), "the entry is added")
	_check(added.contains("\"bg_color\""), "beside the one already there")
	_compiles(added, "an added style entry")

	_section("into an EMPTY dictionary")
	var empty := "export primary := {\n}\n"
	var seeded := Edits.insert_style_entry(empty, "primary", "separation", "4")
	_check(seeded.contains("\"separation\": 4,"), "the first entry lands")
	_compiles(seeded, "a first style entry")

	_section("after an entry with no trailing comma")
	# Every entry ends with one, so the next can always just be appended -- without it the
	# addition runs on from the previous value and the dictionary does not parse.
	var no_comma := "export primary := {\n  \"bg_color\": Color(1, 1, 1)\n}\n"
	var appended := Edits.insert_style_entry(no_comma, "primary", "separation", "2")
	_check(appended.contains("Color(1, 1, 1),"), "the missing comma is supplied")
	_compiles(appended, "an append after a comma-less entry")

	_eq(Edits.insert_style_entry(style, "nope", "k", "1"), style,
		"an export that is not there is not edited")


# ── Templates ────────────────────────────────────────────────────────────────────────

func _test_templates() -> void:
	_section("a new module compiles, and imports nothing")
	# CREATE NEVER ADDS AN IMPORT: an unused import is error-tier on this leg (GUITKX2304), so a
	# create that helpfully wired the module up would produce a tree that does not compile until
	# the user finished the thought.
	for kind in [Module.Kind.COMPONENT, Module.Kind.HOOK, Module.Kind.STYLE,
			Module.Kind.UTIL, Module.Kind.VALUE]:
		var text := Edits.template_for(kind, "thing")
		_compiles(text, "the template for kind %d" % kind)
		_check(not text.contains("import "), "the template for kind %d imports nothing" % kind)
		_check(text.begins_with("export "), "and exports something (kind %d)" % kind)

	_section("a component declaration is PascalCase, from a snake_case file name")
	# GUITKX2100 requires it, and the FILE is snake_case by this leg's convention -- so the two
	# are derived from each other rather than typed twice.
	_check(Edits.template_for(Module.Kind.COMPONENT, "side_panel").contains("export SidePanel("),
		"snake_case becomes PascalCase")
	_check(Edits.template_for(Module.Kind.COMPONENT, "").contains("export Component("),
		"and an empty name still produces a legal declaration")


# ── Indentation ──────────────────────────────────────────────────────────────────────

func _test_indent_is_read_from_the_file() -> void:
	_section("an edit indents the way the FILE does")
	# Assumed instead of read, an edit to a tab-indented file introduces spaces halfway down it.
	var tabbed := SRC.replace("  ", "\t").replace("\t\t\t\t", "\t\t").replace("\t\t\t", "\t\t")
	var row := _row(tabbed, "HBoxContainer")
	_check(row != null, "the tab-indented fixture still projects")
	var edited := Edits.insert(tabbed, _card(tabbed), row, "<ColorRect />", Edits.Placement.BEFORE)
	var inserted := ""
	for line in edited.split("\n"):
		if str(line).contains("ColorRect"):
			inserted = str(line)
	_check(inserted.begins_with("\t"), "the inserted line is tab-indented (%s)" % inserted.replace("\t", "<TAB>"))
	_check(not inserted.begins_with(" "), "and not space-indented")


# ── Row hit-testing and the three bands ──────────────────────────────────────────────

func _test_row_bands() -> void:
	_section("the three bands")
	# A drop resolves by where in a row's height it landed: the top third is "before", the bottom
	# third "after", and the middle -- the widest target, because it is the commonest intent --
	# is "inside".
	var card := _card(SRC)
	var stack := Metrics.section_stack(card)
	var markup: Dictionary = {}
	for entry in stack:
		if int((entry as Dictionary)["section"]) == Metrics.Section.MARKUP:
			markup = entry
	_check(not markup.is_empty(), "the card has a markup section")

	var top := float(markup["top"]) + float(markup["lead"])
	var row_h := float(markup["row_height"])
	_eq(int(Metrics.row_hit(card, Vector2(10, top + row_h * 0.1))["band"]), 0,
		"the top third is BEFORE")
	_eq(int(Metrics.row_hit(card, Vector2(10, top + row_h * 0.5))["band"]), 1,
		"the middle is INSIDE")
	_eq(int(Metrics.row_hit(card, Vector2(10, top + row_h * 0.9))["band"]), 2,
		"the bottom third is AFTER")

	_section("the bottom band's MEANING depends on what is listed next")
	# Same band, same pixel, two different edits -- and both land in the same place on screen,
	# which is the point: the caret is a position in the LISTED tree.
	var deep := Drag._placement_of(2, card, int(Metrics.Section.MARKUP), 0)
	_eq(int(deep), int(Edits.Placement.FIRST_CHILD),
		"under a row whose next listed row is DEEPER, it means become that row's first child")
	var last_index := card.markup.size() - 1
	_eq(int(Drag._placement_of(2, card, int(Metrics.Section.MARKUP), last_index)),
		int(Edits.Placement.AFTER),
		"under the last row there is nothing deeper, so it means after its block")
	_eq(int(Drag._placement_of(0, card, int(Metrics.Section.MARKUP), 0)),
		int(Edits.Placement.BEFORE), "the top band is unaffected")
	_eq(int(Drag._placement_of(1, card, int(Metrics.Section.MARKUP), 0)),
		int(Edits.Placement.INSIDE), "and so is the middle")

	_section("which row")
	_eq(int(Metrics.row_hit(card, Vector2(10, top + row_h * 0.5))["index"]), 0, "the first row")
	_eq(int(Metrics.row_hit(card, Vector2(10, top + row_h * 2.5))["index"]), 2, "and the third")

	_section("a point with no row under it is a MISS, not row zero")
	# Over the header, over a section heading, or past the last row -- all places a drop has no
	# row to attach to, and all different from "the first one".
	_check(not bool(Metrics.row_hit(card, Vector2(10, 4))["found"]), "the header is a miss")
	_check(not bool(Metrics.row_hit(card, Vector2(10, float(markup["top"]) + 2))["found"]),
		"the section's own heading is a miss")
	_check(not bool(Metrics.row_hit(card, Vector2(10, 99999))["found"]), "past the card is a miss")
	_check(not bool(Metrics.row_hit(null, Vector2.ZERO)["found"]), "and so is no card at all")

	_section("the height model and the hit-test read the SAME description")
	# Written twice they drift, and the symptom is a drop landing on the row above the one under
	# the cursor -- which reads as an imprecise drag rather than as two functions disagreeing.
	var summed := Metrics.HEADER_H
	for entry in stack:
		summed += float((entry as Dictionary)["height"])
	_check(absf(summed - Metrics.estimate_card_height(card)) < 0.001,
		"the stack sums to exactly the estimated height")


func _test_drag_survives_a_rerender() -> void:
	_section("a drag resolves from the POINTER, against the graph as it is NOW")
	# This is what the whole drag design is for. The canvas re-renders while a gesture is in
	# flight, because the preview recompiles as the user works -- so a drop resolved from rows
	# captured at press time would be resolving against rows that no longer exist.
	var ws := Workspace.new()
	ws.create_new("res://tests/__edits/app.guitkx", SRC)
	var graph := Service.project(ws.modules(), "res://tests/__edits/app.guitkx")
	var card := graph.cards[0]

	var drag := Drag.new()
	var row: Graph.Line = null
	for r in card.markup:
		if r.name == "Button":
			row = r
	var row_index := Array(card.markup).find(row)
	drag.begin(Drag.Source.ROW, "", card.module_id, row.at, row_index, Vector2.ZERO)
	_check(not drag.is_active(), "a press is not yet a drag")
	_check(not drag.consider(Vector2(1, 1)), "and neither is a one-pixel wobble")
	_check(drag.consider(Vector2(40, 40)), "moving far enough starts it")

	# THE RE-RENDER. Something else edits the module mid-gesture and the whole graph is rebuilt,
	# so every row object the drag could have captured is gone.
	ws.apply_edit("res://tests/__edits/app.guitkx", "## a comment lands\n" + SRC)
	var reprojected := Service.project(ws.modules(), "res://tests/__edits/app.guitkx")
	_check(reprojected.cards[0] != card, "the projection really did replace the card")

	var found := drag.source_row(reprojected)
	_check(found != null,
		"the dragged row is still found afterwards -- by index, since the text change shifted every offset")
	_eq(found.name, "Button", "and it is the same row")

	_section("resolving a drop asks the CURRENT graph by position")
	var target: Graph.Line = null
	for r in reprojected.cards[0].markup:
		if r.name == "HBoxContainer":
			target = r
	var stack := Metrics.section_stack(reprojected.cards[0])
	var markup_section: Dictionary = {}
	for entry in stack:
		if int((entry as Dictionary)["section"]) == Metrics.Section.MARKUP:
			markup_section = entry
	var index := Array(reprojected.cards[0].markup).find(target)
	var y := float(markup_section["top"]) + float(markup_section["lead"]) \
		+ (index + 0.5) * float(markup_section["row_height"])
	var world := Vector2(reprojected.cards[0].x + 10.0, reprojected.cards[0].y + y)
	var hit := Drag.resolve(reprojected, world, Vector2.ZERO, 1.0)
	_check(bool(hit["found"]), "the drop lands on a card")
	_eq((hit["row"] as Graph.Line).name, "HBoxContainer", "and on the row under the pointer")
	_eq(int(hit["placement"]), Edits.Placement.INSIDE, "in the middle band")

	_section("a drop in open canvas finds nothing")
	_check(not bool(Drag.resolve(reprojected, Vector2(-9999, -9999), Vector2.ZERO, 1.0)["found"]),
		"rather than the nearest card")
	_check(not bool(Drag.resolve(null, Vector2.ZERO, Vector2.ZERO, 1.0)["found"]),
		"and no graph resolves to nothing")

	drag.cancel()
	_check(not drag.is_active(), "cancelling ends the gesture")


# ── Wrapping ─────────────────────────────────────────────────────────────────────────

func _test_wrap_in_directive() -> void:
	_section("a row can be wrapped in a directive")
	var src := "export App() -> RuitkVNode {
	return (
		<VBoxContainer>
			<Label text=\"hi\" />
		</VBoxContainer>
	)
}
"
	var label := _row(src, "Label")
	_check(label != null, "the row to wrap is there")

	var wrapped := Edits.wrap_in_directive(src, label, "@if (true)")
	_eq(wrapped,
		"export App() -> RuitkVNode {
	return (
		<VBoxContainer>
			@if (true) {
				return (
					<Label text=\"hi\" />
				)
			}
		</VBoxContainer>
	)
}
",
		"the wrapper is the house form: header, return, the block one deeper, then the closers")

	# THE POINT OF THE SEEDED LITERAL. `@if (condition)` names something that does not exist, so
	# the preview reports an error on a wrap the user has not begun to edit. `true` compiles.
	var compiled: Dictionary = Compiler.compile(wrapped, "App")
	_check(bool(compiled["ok"]),
		"and what it produces COMPILES (got %s)" % str(compiled.get("diagnostics", [])))

	_section("wrapping is refused where there is nothing to wrap")
	_eq(Edits.wrap_in_directive(src, null, "@if (true)"), src, "a null row changes nothing")
	_eq(Edits.wrap_in_directive(src, label, "   "), src, "and neither does an empty header")


# ── Clauses ──────────────────────────────────────────────────────────────────────────

const IF_SRC := "export App(flag: bool = true) -> RuitkVNode {
	return (
		<VBoxContainer>
			@if (flag) {
				return (
					<Label text=\"yes\" />
				)
			}
		</VBoxContainer>
	)
}
"

func _test_clauses() -> void:
	_section("an @if grows an @else, and the file still balances")
	var head := _directive(IF_SRC, "@if")
	_check(head != null, "the @if head is a row")

	var with_else := Edits.add_if_clause(IF_SRC, head, false)
	_check(with_else.contains("} @else {"),
		"the construct's closing brace becomes the SHARED HEAD of the new clause")
	var compiled: Dictionary = Compiler.compile(with_else, "App")
	_check(bool(compiled["ok"]),
		"and what it produces compiles (got %s)" % str(compiled.get("diagnostics", [])))

	var with_elif := Edits.add_if_clause(IF_SRC, head, true)
	# SEEDED WITH A LITERAL, like every other header this builder writes: `condition` names
	# nothing, so the preview would report an error on a clause nobody has finished writing.
	_check(with_elif.contains("@elif (true)"),
		"spelled @elif -- this language's vocabulary, not the Unity leg's @else if")
	_check(bool(Compiler.compile(with_elif, "App")["ok"]), "and it compiles too")

	_section("a clause can be deleted, and the file still balances")
	var clause := _directive(with_else, "@else")
	_check(clause != null, "the @else is a row of its own")
	var without := Edits.delete_clause(with_else, clause)
	_check(not without.contains("@else"), "the clause is gone")
	_check(bool(Compiler.compile(without, "App")["ok"]),
		"and the braces it shared with the clause above it are put back")

	_section("a clause the buffer does not agree with is refused")
	var lying := Graph.Line.new()
	lying.directive_line = 0
	_eq(Edits.delete_clause(IF_SRC, lying), IF_SRC, "a row with no directive line changes nothing")
	_eq(Edits.add_if_clause(IF_SRC, lying, false), IF_SRC, "and neither does one with no close")


# ── Unwrapping ───────────────────────────────────────────────────────────────────────

func _test_unwrap() -> void:
	_section("a directive can be removed, keeping what it wrapped")
	var head := _directive(IF_SRC, "@if")
	var without := Edits.unwrap_directive(IF_SRC, head)

	_check(not without.contains("@if"), "the wrapper is gone")
	_check(without.contains("<Label text=\"yes\" />"), "and what it wrapped survives")
	_check(bool(Compiler.compile(without, "App")["ok"]),
		"and the result compiles -- the return scaffolding went with the wrapper, not without it")

	_section("the block de-indents to where the header was")
	for line in without.split("
"):
		if str(line).strip_edges() == "<Label text=\"yes\" />":
			_eq(str(line), "			<Label text=\"yes\" />",
				"one level in from the container, where the @if used to sit")

	_section("round trip")
	# Wrapping and unwrapping is the same file again. Not asserted for whitespace equality --
	# the wrap re-indents and the unwrap has to guess the unit back -- but for the same MARKUP.
	var wrapped := Edits.wrap_in_directive(IF_SRC, _row(IF_SRC, "Label"), "@if (true)")
	var back := Edits.unwrap_directive(wrapped, _directive(wrapped, "@if"))
	_check(bool(Compiler.compile(back, "App")["ok"]), "the round trip still compiles")

	_section("a row the buffer does not agree with is refused")
	var lying := Graph.Line.new()
	lying.directive_line = 0
	_eq(Edits.unwrap_directive(IF_SRC, lying), IF_SRC, "no directive line, no change")


# ── Every wrap the menu offers ───────────────────────────────────────────────────────

func _test_wrap_variants() -> void:
	_section("every directive the wrap menu offers produces something that COMPILES")
	# The whole reason the headers are seeded with literals. A placeholder identifier is a name
	# the compiler can only reject, so the preview would report an error on a wrap nobody has
	# begun to type.
	var src := "export App() -> RuitkVNode {
	return (
		<VBoxContainer>
			<Label text=\"hi\" />
		</VBoxContainer>
	)
}
"
	for entry in Edits.WRAPS:
		var spec := entry as Dictionary
		var out := Edits.wrap_in_directive(src, _row(src, "Label"), str(spec["header"]))
		var compiled: Dictionary = Compiler.compile(out, "App")
		_check(bool(compiled["ok"]), "%s compiles (got %s)"
			% [str(spec["label"]), str(compiled.get("diagnostics", []))])

	_section("@match wraps the row in a @case, because a match body is clauses")
	var matched := Edits.wrap_in_match(src, _row(src, "Label"))
	_check(matched.contains("@case"), "the row landed inside a case")
	var m: Dictionary = Compiler.compile(matched, "App")
	_check(bool(m["ok"]), "and the match compiles (got %s)" % str(m.get("diagnostics", [])))


# ── The setup island ─────────────────────────────────────────────────────────────────

func _test_island() -> void:
	_section("a component's setup can be replaced wholesale")
	var src := "export App() -> RuitkVNode {
	var a = 1
	var b = 2
	return (
		<Label text=\"hi\" />
	)
}
"
	var out := Edits.set_island(src, 2, 3, "var only = 3")
	_check(out.contains("var only = 3"), "the new text is in")
	_check(not out.contains("var a = 1"), "and the old island is out")
	_check(bool(Compiler.compile(out, "App")["ok"]), "and it still compiles")

	_section("pasted text is normalised, not carried in as it was")
	var messy := Edits.set_island(src, 2, 3, "

        var deep = 1
        var also = 2

")
	# Blank edges gone, the block's OWN common indent stripped, one unit put back -- an island
	# pasted from another file otherwise carries that file's indentation into this one.
	_check(messy.contains("	var deep = 1"), "one unit of this file's indent, not the source's")
	_check(messy.contains("	var also = 2"), "for every line, relative to the block")
	_check(bool(Compiler.compile(messy, "App")["ok"]), "and it compiles")
