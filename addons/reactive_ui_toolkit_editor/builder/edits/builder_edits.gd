@tool
class_name RuitkBuilderEdits
extends RefCounted
## Every structural edit the builder makes to a `.guitkx` buffer, as PURE TEXT TRANSFORMS:
## `(source, where, what) -> new source`. No nodes, no model, no disk.
##
## SPAN-EXACT. Each operation is addressed by a row from the graph projection, and every row
## carries the absolute offsets of what it came from -- so an insert goes exactly between two
## characters and a delete removes exactly one subtree. The Unity leg works in whole LINES,
## because its parser does not surface positions, and pays for it wherever two things share one:
## a self-closing tag on the same line as its parent, an attribute beside a directive head.
##
## PURE, so it is provable. The entire edit surface is assertable as before/after strings with no
## editor, no canvas and no workspace, which is what makes the operation set worth trusting: an
## edit that produces the wrong text is a defect you can see, not one you have to reproduce.
##
## ONE PER CALL. Every offset in the projection is invalidated by any edit, so the caller applies
## one operation, re-projects, and asks again. Batching would mean tracking how each edit shifts
## every later one -- which is the whole class of bug this design exists to avoid.

const Compiler = preload("res://addons/reactive_ui_toolkit/guitkx/guitkx.gd")
const Formatter = preload("res://addons/reactive_ui_toolkit/guitkx/guitkx_formatter.gd")
const Graph = preload("res://addons/reactive_ui_toolkit_editor/builder/canvas/builder_graph.gd")
const Specifiers = preload("res://addons/reactive_ui_toolkit_editor/builder/document/builder_specifiers.gd")
const Paths = preload("res://addons/reactive_ui_toolkit_editor/builder/document/builder_paths.gd")
const Module = preload("res://addons/reactive_ui_toolkit_editor/builder/document/builder_module.gd")
const Lexer = preload("res://addons/reactive_ui_toolkit/guitkx/guitkx_lexer.gd")
const JsxScan = preload("res://addons/reactive_ui_toolkit/guitkx/guitkx_jsx_scan.gd")

## Where a dropped element lands relative to the row it was dropped on. The three bands a drop
## gesture resolves to: the top third of a row is "before", the bottom third "after", and the
## middle is "inside".
enum Placement { BEFORE, INSIDE, AFTER }


# ── Markup structure ─────────────────────────────────────────────────────────────────

## Whether something may be placed relative to `row`, and why not: { ok, reason }.
##
## A SIBLING placement is illegal where the language allows exactly one root. A component's
## `return` holds one element (GUITKX0108) and so does every `return` inside a directive body --
## so dropping beside the only child of either produces a file that does not compile. The
## operation refuses rather than producing it, and hands back the reason so the chrome can say
## what to do instead: wrap them in a fragment.
##
## INSIDE is always legal. An element can always take another child, and a self-closing one is
## re-opened to take it.
static func can_place(card: Graph.Card, row: Graph.Line, placement: Placement) -> Dictionary:
	if row == null:
		return { "ok": false, "reason": "nothing to place it against" }
	if placement == Placement.INSIDE:
		return { "ok": true, "reason": "" }
	if card == null:
		return { "ok": true, "reason": "" }
	if row.depth == 0:
		return { "ok": false, "reason":
			"a component returns exactly one root element -- wrap them in a fragment <>...</>" }
	var parent := parent_of(card, row)
	if parent != null and parent.kind == Graph.LineKind.DIRECTIVE:
		return { "ok": false, "reason":
			"a directive body returns exactly one element -- wrap them in a fragment <>...</>" }
	return { "ok": true, "reason": "" }


## The row one level up from `row`: the SMALLEST row whose span strictly encloses it.
##
## By CONTAINMENT, not by object identity and not by walking depths. The builder re-projects on
## every change, so a row a caller is holding is routinely from an earlier projection than the
## card it is asked about -- an identity comparison silently finds nothing there, and a rule
## built on it silently stops applying.
static func parent_of(card: Graph.Card, row: Graph.Line) -> Graph.Line:
	if card == null or row == null:
		return null
	var best: Graph.Line = null
	for candidate in card.markup:
		if candidate.at >= row.at or candidate.end_at <= row.at:
			continue
		if best == null or candidate.at > best.at:
			best = candidate
	return best


## Inserts `markup` relative to `row`.
##
## INSIDE a self-closing element re-opens it: `<Label />` becomes `<Label>…</Label>`. A tag that
## closes itself has nowhere to put a child, and refusing the drop would make half the elements
## on a card undroppable for a reason the user cannot see.
##
## `card` is what makes the single-root rule checkable; passing null skips the check, which is
## what a caller that has already run `can_place` itself does.
static func insert(source: String, card: Graph.Card, row: Graph.Line, markup: String,
		placement: Placement) -> String:
	if row == null or markup.strip_edges().is_empty():
		return source
	if not bool(can_place(card, row, placement)["ok"]):
		return source
	match placement:
		Placement.BEFORE:
			return _insert_line_before(source, row.at, markup, _indent_of(source, row.at))
		Placement.AFTER:
			return _insert_line_after(source, row.end_at, markup, _indent_of(source, row.at))
		_:
			return _insert_inside(source, row, markup)


static func _insert_inside(source: String, row: Graph.Line, markup: String) -> String:
	var indent := _indent_of(source, row.at)
	var unit := _indent_unit(source)
	if row.self_closing:
		return _reopen_self_closing(source, row, markup, indent, unit)
	# The close tag is the last thing in the span; the child goes on its own line before it.
	var close_at := source.rfind("</", row.end_at)
	if close_at == -1 or close_at < row.at:
		return source
	var line_start := _line_start(source, close_at)
	return source.substr(0, line_start) \
		+ indent + unit + markup.strip_edges() + "\n" \
		+ source.substr(line_start)


## Rewrites `<Tag … />` as `<Tag …>\n\t<child />\n</Tag>`.
static func _reopen_self_closing(source: String, row: Graph.Line, markup: String,
		indent: String, unit: String) -> String:
	var span := source.substr(row.at, row.end_at - row.at)
	var slash := span.rfind("/>")
	if slash == -1:
		return source
	var head := span.substr(0, slash).rstrip(" \t\n")
	var body := "%s>\n%s%s%s\n%s</%s>" % [head, indent, unit, markup.strip_edges(), indent, row.name]
	return source.substr(0, row.at) + body + source.substr(row.end_at)


## Removes the row and everything under it -- an element with its subtree, a directive with its
## whole construct. The blank line the removal would leave goes with it.
static func remove(source: String, row: Graph.Line) -> String:
	if row == null:
		return source
	var from := _line_start(source, row.at)
	var to := _line_end(source, maxi(row.at, row.end_at - 1))
	if to < source.length() and source[to] == "\n":
		to += 1
	return source.substr(0, from) + source.substr(to)


## Moves a row to sit relative to another. Cut, then paste -- and the paste offset is recomputed
## against the CUT text, because removing the source shifts everything after it.
##
## Refused when the target is inside the row being moved: a subtree cannot become its own child,
## and the result of trying is a file that loses the whole subtree.
static func move(source: String, card: Graph.Card, row: Graph.Line, target: Graph.Line,
		placement: Placement) -> String:
	if row == null or target == null:
		return source
	if not bool(can_place(card, target, placement)["ok"]):
		return source
	if target.at >= row.at and target.at < row.end_at:
		return source
	var from := _line_start(source, row.at)
	var to := _line_end(source, maxi(row.at, row.end_at - 1))
	if to < source.length() and source[to] == "\n":
		to += 1
	var moved := source.substr(from, to - from).strip_edges()
	if moved.is_empty():
		return source

	var cut := source.substr(0, from) + source.substr(to)
	# The target only moves if it sat AFTER the cut; anything before it is untouched.
	var shifted: Graph.Line = target.shifted(-(to - from) if target.at >= to else 0)
	# The card is not passed on: the placement has already been checked against the tree as it
	# was, and the cut text no longer matches the card's offsets.
	return insert(cut, null, shifted, moved, placement)


# ── Attributes ───────────────────────────────────────────────────────────────────────

## Sets an attribute on an element row, replacing it if it is already there.
##
## `quoted` picks the spelling: `text="hi"` for a literal, `style={ s }` for an expression. The
## two are different things to the compiler, so the caller says which it means rather than the
## edit guessing from the value's shape -- `{` inside a string literal is a perfectly ordinary
## character.
static func set_attribute(source: String, row: Graph.Line, name: String,
		value: String, quoted: bool) -> String:
	if row == null or name.strip_edges().is_empty():
		return source
	var spelled := "%s=\"%s\"" % [name, value] if quoted else "%s={ %s }" % [name, value]
	var existing := _attribute_span(source, row, name)
	if not existing.is_empty():
		return source.substr(0, int(existing["from"])) + spelled + source.substr(int(existing["to"]))
	var insert_at := _attribute_insert_point(source, row)
	if insert_at < 0:
		return source
	return source.substr(0, insert_at) + " " + spelled + source.substr(insert_at)


static func remove_attribute(source: String, row: Graph.Line, name: String) -> String:
	var existing := _attribute_span(source, row, name)
	if existing.is_empty():
		return source
	var from := int(existing["from"])
	# The separating space goes with the attribute; otherwise every removal leaves a widening gap
	# and the tag drifts apart over an editing session.
	while from > 0 and (source[from - 1] == " " or source[from - 1] == "\t"):
		from -= 1
	return source.substr(0, from) + source.substr(int(existing["to"]))


## The span of one attribute inside an element's open tag, as { from, to }, or {}.
static func _attribute_span(source: String, row: Graph.Line, name: String) -> Dictionary:
	var open_tag := JsxScan.scan_open_tag(source, row.at, source.length())
	var gt := int(open_tag.get("gt", -1))
	if gt == -1:
		return {}
	var i := row.at + 1
	while i < gt and Lexer._is_ident_code(source.unicode_at(i)):
		i += 1
	while i < gt:
		var j := Lexer.skip_noncode_markup(source, i)
		if j != i and j <= gt:
			i = j
			continue
		if not Lexer._is_ident_code(source.unicode_at(i)) \
				or (i > 0 and Lexer._is_ident_code(source.unicode_at(i - 1))):
			i += 1
			continue
		var start := i
		while i < gt and Lexer._is_ident_code(source.unicode_at(i)):
			i += 1
		var found := source.substr(start, i - start)
		var after := _skip_spaces(source, i)
		if after < gt and source[after] == "=":
			var value_at := _skip_spaces(source, after + 1)
			var end := _attribute_value_end(source, value_at, gt)
			if found == name:
				return { "from": start, "to": end }
			i = end
			continue
		# A bare boolean attribute: `disabled`, with no value at all.
		if found == name:
			return { "from": start, "to": i }
	return {}


static func _attribute_value_end(source: String, at: int, limit: int) -> int:
	if at >= limit:
		return at
	var c := source[at]
	if c == "{":
		var close := Lexer.find_matching(source, at)
		return (close + 1) if close != -1 and close < limit else limit
	if c == "\"" or c == "'":
		var end := source.find(c, at + 1)
		return (end + 1) if end != -1 and end < limit else limit
	var i := at
	while i < limit and source[i] != " " and source[i] != "\t" and source[i] != "\n" \
			and source[i] != ">" and source[i] != "/":
		i += 1
	return i


## Where a new attribute goes: just before the tag's terminator, so it reads at the end of the
## list rather than jumping ahead of the ones already there.
static func _attribute_insert_point(source: String, row: Graph.Line) -> int:
	var open_tag := JsxScan.scan_open_tag(source, row.at, source.length())
	var gt := int(open_tag.get("gt", -1))
	if gt == -1:
		return -1
	var at := gt
	if bool(open_tag.get("self_closing", false)):
		at -= 1   # sit before the `/` of `/>`
	while at > row.at and (source[at - 1] == " " or source[at - 1] == "\t" or source[at - 1] == "\n"):
		at -= 1
	return at


# ── Directives ───────────────────────────────────────────────────────────────────────

## Replaces a directive clause's header -- the condition of an `@if`, the loop of a `@for`, the
## subject of a `@match`. The clause KEYWORD stays; only what is in its parentheses moves.
static func set_directive_header(source: String, row: Graph.Line, header: String) -> String:
	if row == null or row.kind != Graph.LineKind.DIRECTIVE:
		return source
	var open := source.find("(", row.at)
	var brace := source.find("{", row.at)
	if open == -1 or (brace != -1 and brace < open):
		# A clause with no header at all -- `@else`, `@default`. There is nothing to replace, and
		# inventing a parenthesis would make it a different construct.
		return source
	var close := Lexer.find_matching(source, open)
	if close == -1:
		return source
	return source.substr(0, open + 1) + header.strip_edges() + source.substr(close)


# ── Imports ──────────────────────────────────────────────────────────────────────────

## Adds an import of `names` from `target_path`, if it is not already there.
##
## The specifier is written by the COMPILER's canonical rule, so a builder-authored import is
## indistinguishable from a hand-written one. An import that already names the target gains the
## missing names rather than being duplicated -- two imports of one module is GUITKX2303.
static func ensure_import(source: String, from_path: String, target_path: String,
		names: PackedStringArray) -> String:
	if names.is_empty():
		return source
	var spec := Specifiers.relative(from_path.get_base_dir(), target_path)
	if spec.is_empty():
		return source

	for imp in Compiler.scan_imports(source):
		if str(imp.get("spec", "")) != spec:
			continue
		var have := PackedStringArray()
		for entry in (imp.get("names", []) as Array):
			have.append(str((entry as Dictionary).get("name", "")))
		var missing := PackedStringArray()
		for wanted in names:
			if not have.has(wanted):
				missing.append(wanted)
		if missing.is_empty():
			return source
		have.append_array(missing)
		var replacement := "import { %s } from \"%s\"" % [", ".join(have), spec]
		return source.substr(0, int(imp["at"])) + replacement + source.substr(int(imp["end"]))

	var line := "import { %s } from \"%s\"\n" % [", ".join(names), spec]
	return _insert_into_preamble(source, line)


## Removes the import naming `spec` entirely, or just some of its names.
static func remove_import(source: String, spec: String, names := PackedStringArray()) -> String:
	for imp in Compiler.scan_imports(source):
		if str(imp.get("spec", "")) != spec:
			continue
		var keep := PackedStringArray()
		for entry in (imp.get("names", []) as Array):
			var entry_name := str((entry as Dictionary).get("name", ""))
			if names.is_empty() or names.has(entry_name):
				continue
			keep.append(entry_name)
		var from := int(imp["at"])
		var to := int(imp["end"])
		if keep.is_empty():
			# The whole line goes, newline included -- an import removed to a blank line leaves a
			# gap that widens every time the user does it.
			if to < source.length() and source[to] == "\n":
				to += 1
			var out := source.substr(0, from) + source.substr(to)
			# And the separator blank line goes too when the import led the file: removing the
			# last one otherwise leaves the file starting on an empty line.
			if from == 0:
				out = out.lstrip("\n")
			return out
		return source.substr(0, from) \
			+ "import { %s } from \"%s\"" % [", ".join(keep), spec] \
			+ source.substr(to)
	return source


## Puts a line at the end of the preamble -- after the last import or `@`-directive, before the
## first declaration. Imports are preamble-only, so anywhere else is a compile error.
static func _insert_into_preamble(source: String, line: String) -> String:
	var at := 0
	var n := source.length()
	var i := 0
	while i < n:
		i = Compiler._skip_ws_and_comments(source, i)
		if i >= n:
			break
		if Lexer.keyword_at(source, i, "import"):
			i = Compiler.import_end(source, i)
			at = _after_line(source, i)
			continue
		if source[i] == "@":
			var le := source.find("\n", i)
			i = n if le == -1 else le
			at = _after_line(source, i)
			continue
		break
	if at == 0:
		# Nothing in the preamble yet: the import leads the file, with a blank line under it so
		# the first declaration is not glued to it.
		return line + "\n" + source
	return source.substr(0, at) + line + source.substr(at)


# ── Hooks and setup ──────────────────────────────────────────────────────────────────

## Adds a setup line at the top of a component's body -- what "+ hook" inserts.
##
## At the TOP, because hooks must run unconditionally and in a stable order: a hook added at the
## end of setup is still legal, but a hook added after an early return is not, and the top is the
## only position that is always right.
static func insert_setup_line(source: String, card: Graph.Card, line: String) -> String:
	if card == null or line.strip_edges().is_empty():
		return source
	var anchor := _body_open_of(source, card)
	if anchor < 0:
		return source
	var body_start := _after_line(source, anchor)
	var unit := _indent_unit(source)
	return source.substr(0, body_start) + unit + line.strip_edges() + "\n" + source.substr(body_start)


## The offset of the `{` that opens the card's binding declaration body.
static func _body_open_of(source: String, card: Graph.Card) -> int:
	for dm in (Compiler.analyzed_decls(source)["decls"] as Array):
		if str(dm["kind"]) != "component":
			continue
		var open := int(dm.get("body_open", -1))
		if open >= 0:
			return open
		# A wrapper declaration carries no `body_open`; its brace is the first one past the name.
		return source.find("{", int(dm["at"]))
	return -1


# ── Style entries ────────────────────────────────────────────────────────────────────

## Adds a `"key": value` pair to a style module's exported dictionary. What `+ entry` does.
static func insert_style_entry(source: String, export_name: String, key: String,
		value: String) -> String:
	for dm in (Compiler.analyzed_decls(source)["decls"] as Array):
		if str(dm["name"]) != export_name or str(dm["kind"]) != "value":
			continue
		var open := source.find("{", int(dm.get("value_start", int(dm["at"]))))
		if open == -1:
			return source
		var close := Lexer.find_matching(source, open)
		if close == -1:
			return source
		var closing_indent := _indent_of(source, open)
		var indent := closing_indent + _indent_unit(source)
		# The end of the existing content, NOT the closing brace: a comma that has to be supplied
		# belongs directly after the last value, and inserted at the brace instead it lands on a
		# line of its own after the newline -- which does not parse.
		var last := close
		while last > open + 1 and _is_space(source[last - 1]):
			last -= 1
		var separator := "" if last == open + 1 or source[last - 1] == "," else ","
		return source.substr(0, last) \
			+ "%s\n%s\"%s\": %s,\n%s" % [separator, indent, key, value, closing_indent] \
			+ source.substr(close)
	return source


static func _is_space(c: String) -> bool:
	return c == " " or c == "\t" or c == "\n" or c == "\r"


# ── Module templates ─────────────────────────────────────────────────────────────────

## The starting text for a new module.
##
## CREATE NEVER ADDS AN IMPORT. A new module is not used by anything yet, and an unused import is
## an error-tier diagnostic on this leg (GUITKX2304) -- so a create that helpfully wired the
## module up would produce a tree that does not compile until the user finishes the thought.
## Creation states PLACEMENT; wiring states USAGE, and they are separate gestures.
## Wraps a row's whole span in a directive, and returns the new source.
##
## Ported from the Unity leg's `WrapRowInDirective`. The scaffolding is the house form every
## sample uses -- header, `return (`, the indented block, `);`, `}` -- and the closer aligns with
## its own `return (` rather than with the body it closes.
##
## The header is seeded with a COMPILABLE literal, never a placeholder identifier: `@if (true)`
## compiles and can then be edited, while `@if (condition)` is a name that does not exist and the
## preview reports it as an error on a wrap the user has not finished typing. `@while` seeds
## `false` deliberately -- a true-seeded render loop would not terminate.
static func wrap_in_directive(source: String, row: Graph.Line, header: String) -> String:
	if row == null or header.strip_edges().is_empty():
		return source
	var lines := source.split("
")
	var from: int = clampi(row.source_line - 1, 0, lines.size() - 1)
	var to: int = clampi((row.end_line if row.end_line > 0 else row.source_line) - 1,
		from, lines.size() - 1)
	var indent := _indent_of_line(str(lines[from]))
	var unit := _indent_unit(source)

	var out := PackedStringArray()
	for i in range(lines.size()):
		if i == from:
			out.append(indent + header + " {")
			out.append(indent + unit + "return (")
		if i >= from and i <= to:
			# TWO units: the block sits inside the `return (`, which is itself one unit inside the
			# header. One unit put the wrapped element level with its own `return (`.
			out.append(unit + unit + str(lines[i]))
		else:
			out.append(str(lines[i]))
		if i == to:
			out.append(indent + unit + ")")
			out.append(indent + "}")
	return "
".join(out)


## The leading whitespace of one line.
static func _indent_of_line(line: String) -> String:
	var i := 0
	while i < line.length() and (line[i] == "	" or line[i] == " "):
		i += 1
	return line.substr(0, i)


static func template_for(kind: int, name: String) -> String:
	match kind:
		Module.Kind.HOOK:
			return "export use_%s() -> Variant {\n%sreturn null\n}\n" % [name, _default_unit()]
		Module.Kind.STYLE, Module.Kind.VALUE:
			return "export %s := {\n%s\"bg_color\": Color(0.2, 0.2, 0.24),\n}\n" % [name, _default_unit()]
		Module.Kind.UTIL:
			return "export %s() -> Variant {\n%sreturn null\n}\n" % [name, _default_unit()]
		_:
			return "export %s() -> RuitkVNode {\n%sreturn (\n%s%s<VBoxContainer />\n%s)\n}\n" % [
				_pascal(name), _default_unit(), _default_unit(), _default_unit(), _default_unit()]


## `snake_case` or `kebab-case` to `PascalCase` -- a component declaration must be PascalCase
## (GUITKX2100) but the FILE it lives in is snake_case by this leg's convention, so the two are
## derived from each other rather than typed twice.
static func _pascal(name: String) -> String:
	var out := ""
	for part in name.replace("-", "_").split("_", false):
		var word := str(part)
		if word.is_empty():
			continue
		out += word.substr(0, 1).to_upper() + word.substr(1)
	return out if not out.is_empty() else "Component"


# ── Text helpers ─────────────────────────────────────────────────────────────────────

static func _insert_line_before(source: String, at: int, markup: String, indent: String) -> String:
	var line_start := _line_start(source, at)
	return source.substr(0, line_start) + indent + markup.strip_edges() + "\n" + source.substr(line_start)


static func _insert_line_after(source: String, end_at: int, markup: String, indent: String) -> String:
	var line_end := _line_end(source, maxi(0, end_at - 1))
	var insert_at: int = line_end + 1 if line_end < source.length() else source.length()
	var lead := "" if source.is_empty() or source.ends_with("\n") or insert_at <= source.length() else "\n"
	return source.substr(0, insert_at) + lead + indent + markup.strip_edges() + "\n" \
		+ source.substr(insert_at)


## The leading whitespace of the line an offset falls on -- what a sibling has to match.
static func _indent_of(source: String, at: int) -> String:
	var start := _line_start(source, at)
	var i := start
	while i < source.length() and (source[i] == " " or source[i] == "\t"):
		i += 1
	return source.substr(start, i - start)


## One level of indentation, as this FILE spells it. Read from the source rather than assumed, so
## an edit to a tab-indented file does not introduce spaces halfway down it; the formatter's own
## default is the fallback for a file with nothing to learn from.
static func _indent_unit(source: String) -> String:
	for line in source.split("\n"):
		var text := str(line)
		if text.is_empty() or not (text[0] == " " or text[0] == "\t"):
			continue
		if text[0] == "\t":
			return "\t"
		var spaces := 0
		while spaces < text.length() and text[spaces] == " ":
			spaces += 1
		return " ".repeat(spaces)
	return _default_unit()


static func _default_unit() -> String:
	var defaults: Dictionary = Formatter.DEFAULTS
	if str(defaults.get("indentStyle", "space")) == "tab":
		return "\t"
	return " ".repeat(int(defaults.get("indentSize", 2)))


static func _line_start(source: String, at: int) -> int:
	var found := source.rfind("\n", clampi(at, 0, source.length()))
	return 0 if found == -1 else found + 1


static func _line_end(source: String, at: int) -> int:
	var found := source.find("\n", clampi(at, 0, source.length()))
	return source.length() if found == -1 else found


static func _after_line(source: String, at: int) -> int:
	var end := _line_end(source, at)
	return end + 1 if end < source.length() else source.length()


static func _skip_spaces(source: String, at: int) -> int:
	var i := at
	while i < source.length() and (source[i] == " " or source[i] == "\t" or source[i] == "\n"):
		i += 1
	return i


