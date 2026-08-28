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
## Where a drop lands relative to the row under the cursor.
##
## FIRST_CHILD exists because the canvas lists markup FLATTENED with indentation, so the row for
## `<VBoxContainer>` is only its OPEN TAG line and the gap drawn under it is visually the gap
## BEFORE ITS FIRST CHILD. AFTER inserts at the row's whole-block end -- past every descendant,
## which on a deep tree is hundreds of lines below where the caret was drawn. The caret and the
## edit were reading one gesture in two coordinate systems.
enum Placement { BEFORE, INSIDE, AFTER, FIRST_CHILD }


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
	if placement == Placement.INSIDE or placement == Placement.FIRST_CHILD:
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
		Placement.FIRST_CHILD:
			# Under the OPEN TAG, which is where the caret was drawn. A self-closing target has no
			# inside to be first in, so it falls back to the append path that rewrites `/>` into
			# an open/close pair.
			if row.self_closing:
				return _insert_inside(source, row, markup)
			var indent := _indent_of(source, row.at)
			return _insert_line_after(source, _open_tag_end(source, row), markup,
				indent + _indent_unit(source))
		_:
			return _insert_inside(source, row, markup)


## The offset just past a row's OPEN TAG -- the `>` that ends it, not the end of its block.
##
## Found by scanning rather than assumed to be the end of `row.at`'s line, because an element
## with a long attribute run is written across several lines and its open tag ends on the last of
## them.
static func _open_tag_end(source: String, row: Graph.Line) -> int:
	var i := row.at
	var limit: int = mini(row.end_at, source.length())
	var in_string := false
	var quote := ""
	while i < limit:
		var ch := source[i]
		if in_string:
			if ch == quote:
				in_string = false
		elif ch == "\"" or ch == "'":
			in_string = true
			quote = ch
		elif ch == ">":
			return i + 1
		i += 1
	return row.at


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
	# A ROW WITH NO SPAN IS AN AFFORDANCE, NOT TEXT. "+ entry" and friends are synthetic rows with
	# `at` and `end_at` at 0, so removing one cut the first line of the file.
	if not has_span(row):
		return source
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

	return _ensure_import_line(source, spec, names, names)


## Puts `entries` on the import line for `spec`, adding the line when there is none.
##
## `remotes` names what the TARGET exports, one per entry, so an entry already imported under any
## local binding is recognised rather than added twice. `entries` is how each should be written --
## `"accent"` or `"accent as brandAccent"`.
##
## The existing line is REWRITTEN FROM THE SCAN'S OWN SPELLING, alias included: each scanned entry
## carries `remote` (the name the target exports) and `name` (what this file binds it to), and
## rebuilding from `name` alone turned `primary as brand` into `brand` -- an import of a name the
## target does not export -- the moment a second name was added to it.
static func _ensure_import_line(source: String, spec: String, entries: PackedStringArray,
		remotes: PackedStringArray) -> String:
	if entries.is_empty():
		return source
	for imp in Compiler.scan_imports(source):
		if str(imp.get("spec", "")) != spec:
			continue
		var have := PackedStringArray()
		var bound := {}
		for scanned in (imp.get("names", []) as Array):
			var pair := scanned as Dictionary
			var local := str(pair.get("name", ""))
			var remote := str(pair.get("remote", ""))
			bound[remote if not remote.is_empty() else local] = true
			have.append(local if remote.is_empty() or remote == local 				else "%s as %s" % [remote, local])
		var missing := PackedStringArray()
		for i in entries.size():
			var remote_name := str(remotes[i]) if i < remotes.size() else str(entries[i])
			if not bound.has(remote_name):
				missing.append(str(entries[i]))
		if missing.is_empty():
			return source
		have.append_array(missing)
		var replacement := "import { %s } from \"%s\"" % [", ".join(have), spec]
		return source.substr(0, int(imp["at"])) + replacement + source.substr(int(imp["end"]))

	var line := "import { %s } from \"%s\"
" % [", ".join(entries), spec]
	return _insert_into_preamble(source, line)


## Imports `export_name` from `target_path` and reports the NAME THIS FILE CAN REFERENCE IT BY.
##
## Returns `{ "text": String, "binding": String }`.
##
## THE BINDING IS NOT ALWAYS THE EXPORT NAME. A style module and the component it belongs to are
## named by two conventions that collapse onto one identifier by construction -- `Card.guitkx`
## exporting `Card`, `card.style.guitkx` exporting `Card` -- so importing the style export into
## the component redeclares the component's own name. An alias is chosen against everything the
## file already means: its own exports and every binding its existing imports introduce.
##
## A module ALREADY imported keeps whatever binding it was given. Styling a second element from
## the same module must reference the name the file actually binds, not a fresh one.
static func bind_export(source: String, from_path: String, target_path: String,
		export_name: String) -> Dictionary:
	var spec := Specifiers.relative(from_path.get_base_dir(), target_path)
	if spec.is_empty():
		return { "text": source, "binding": export_name }

	var taken := {}
	for imp in Compiler.scan_imports(source):
		var same := str(imp.get("spec", "")) == spec
		for entry in (imp.get("names", []) as Array):
			var pair := entry as Dictionary
			var local := str(pair.get("name", ""))
			var remote := str(pair.get("remote", ""))
			if same and (remote == export_name or (remote.is_empty() and local == export_name)):
				return { "text": source, "binding": local }
			taken[local] = true
		var ns := str(imp.get("ns", ""))
		if not ns.is_empty():
			taken[ns] = true
	# The file's OWN declarations are names it already means. `analyzed_decls` hands back a
	# Dictionary whose `decls` is the list -- iterating it directly walks its KEYS.
	for decl in (Compiler.analyzed_decls(source).get("decls", []) as Array):
		taken[str((decl as Dictionary).get("name", ""))] = true

	var binding := export_name
	if taken.has(binding):
		binding = export_name + "Style"
	var counter := 2
	while taken.has(binding):
		binding = "%s%d" % [export_name, counter]
		counter += 1

	var written := PackedStringArray([
		export_name if binding == export_name else "%s as %s" % [export_name, binding]])
	return {
		"text": _ensure_import_line(source, spec, written, PackedStringArray([export_name])),
		"binding": binding,
	}


## Whether `source` imports `spec` at all.
##
## The question that decides whether a module can be deleted. Asked of the COMPILER's import scan,
## not of the text: an import spelled across two lines, or aliased, or with the module among five
## other names, is still an import, and a `contains()` on the specifier would also match one
## inside a comment or a string.
static func imports_specifier(source: String, spec: String) -> bool:
	for imp in Compiler.scan_imports(source):
		if str(imp.get("spec", "")) == spec:
			return true
	return false


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
## Whether an export's dictionary already carries `key`.
##
## The vocabulary menu filters on this, and `insert_style_entry` refuses on it -- a duplicate key
## in a GDScript dictionary literal is a file that will not load, and it took two clicks of the
## same chip to produce one.
static func style_entry_exists(source: String, export_name: String, key: String) -> bool:
	var re := RegEx.create_from_string("(?m)^\\s*[\"']" + key + "[\"']\\s*:")
	var body := _export_body(source, export_name)
	return not body.is_empty() and re.search(body) != null


## The text between an export's braces, or "" when it cannot be found.
static func _export_body(source: String, export_name: String) -> String:
	var head := source.find("export " + export_name)
	if head < 0:
		return ""
	var open := source.find("{", head)
	if open < 0:
		return ""
	var depth := 0
	for i in range(open, source.length()):
		var ch := source[i]
		if ch == "{":
			depth += 1
		elif ch == "}":
			depth -= 1
			if depth == 0:
				return source.substr(open, i - open)
	return source.substr(open)


static func insert_style_entry(source: String, export_name: String, key: String,
		value: String) -> String:
	# A DUPLICATE KEY IS A DICTIONARY THAT WILL NOT LOAD, so the edit refuses one whatever the
	# caller believes.
	if style_entry_exists(source, export_name, key):
		return source
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
## Adds an `@else` / `@else if` clause to an `@if` construct, and returns the new source.
##
## Ported from the Unity leg's `AddIfClause`. The construct's closing brace becomes the SHARED
## HEAD of the new clause -- `} @else {` -- and a fresh `}` closes it. Written any other way the
## file no longer balances, and the parser is strict about it.
## The next unused `@case` label for a `@match`, as an integer.
##
## The arms sit one level deeper than the head, and this language writes them with PARENTHESES --
## `@case (1)` -- not the colon form the Unity leg uses. Their labels arrive on the row as the
## directive text.
static func next_case_label(card: Graph.Card, head: Graph.Line) -> int:
	var used := {}
	for clause in clauses_of(card, head):
		var row := clause as Graph.Line
		if row.badge != Graph.Badge.CASE:
			continue
		var text := row.directive_text.strip_edges()
		if text.is_valid_int():
			used[text.to_int()] = true
	var next := 0
	while used.has(next):
		next += 1
	return next


## Adds a `@case` or the `@default` to a `@match`.
##
## A new `@case` goes ABOVE `@default`, because a default that is not last matches everything
## after it. The `@match` head had no clause operations at all -- its menu offered only edit,
## remove and delete -- so the one construct whose whole purpose is several arms could not be
## given a second one from the canvas.
static func add_match_clause(source: String, card: Graph.Card, head: Graph.Line,
		is_default: bool) -> String:
	if head == null or head.close_line <= 0:
		return source
	var lines := source.split(_lf())
	var close_index := head.close_line - 1
	if close_index < 0 or close_index >= lines.size():
		return source
	if str(lines[close_index]).strip_edges() != "}":
		return source

	# A CASE LANDS ABOVE @default. Asked of the projection, so it is the arm's real line rather
	# than a guess about where the default sits.
	var insert_at := close_index
	if not is_default:
		for clause in clauses_of(card, head):
			var row := clause as Graph.Line
			if row.badge == Graph.Badge.DEFAULT and row.directive_line > 0:
				insert_at = mini(insert_at, row.directive_line - 1)
	if is_default and construct_has_clause(card, head, "@default"):
		return source

	var indent := _indent_of_line(str(lines[close_index])) + _indent_unit(source)
	var header := "@default" if is_default else "@case (%d)" % next_case_label(card, head)
	var unit := _indent_unit(source)
	var out := PackedStringArray()
	for i in range(lines.size()):
		if i == insert_at:
			out.append("%s%s {" % [indent, header])
			out.append(indent + unit + "return (")
			out.append(indent + unit + unit + "<Control />")
			out.append(indent + unit + ")")
			out.append(indent + "}")
		out.append(str(lines[i]))
	return _lf().join(out)


static func add_if_clause(source: String, head: Graph.Line, with_condition: bool) -> String:
	if head == null or head.close_line <= 0:
		return source
	var lines := source.split("
")
	var close_index := head.close_line - 1
	if close_index < 0 or close_index >= lines.size():
		return source
	# Refused rather than guessed at: if the line the row says closes the block is not a closing
	# brace, the row and the buffer disagree, and writing into it on that basis corrupts the file.
	if str(lines[close_index]).strip_edges() != "}":
		return source
	var indent := _indent_of_line(str(lines[close_index]))
	# `@elif`, not `@else if`. The Unity leg spells it the C# way; this language's directive
	# vocabulary is `if` / `elif` / `else`, and `@else if` is two directives with no body between
	# them -- GUITKX0303 on the clause the moment it is written.
	var header := "@elif (true)" if with_condition else "@else"
	# A BODY, not an empty clause. The Unity leg leaves the new clause empty because its language
	# permits that; ours does not -- GUITKX0303 rejects a directive with no `{ ... }` body, so a
	# clause added that way puts the file into an error state the moment it is written. `<Control />`
	# is the closest thing this language has to "renders nothing", and it is one click to replace.
	var unit := _indent_unit(source)
	var out := PackedStringArray()
	for i in range(lines.size()):
		if i == close_index:
			out.append("%s} %s {" % [indent, header])
			out.append(indent + unit + "return (")
			out.append(indent + unit + unit + "<Control />")
			out.append(indent + unit + ")")
			out.append(indent + "}")
			continue
		out.append(str(lines[i]))
	return "
".join(out)


## Removes one clause of a directive construct, and returns the new source.
##
## Ported from the Unity leg's `DeleteClause`, including its brace bookkeeping. A clause's head is
## written one of two legal ways -- SHARED (`} @else {`, the head line carries the previous
## clause's closer) or SEPARATE (`@else {` on its own line, the previous clause already closed
## itself) -- and deleting without accounting for which leaves the file unbalanced.
static func delete_clause(source: String, row: Graph.Line) -> String:
	if row == null or row.directive_line <= 0:
		return source
	var lines := source.split("
")
	var head := row.directive_line - 1
	var close := row.close_line - 1
	if head < 0 or close < head or close >= lines.size():
		return source

	var shared_head := str(lines[head]).strip_edges().begins_with("}")
	# IS THE CLOSING LINE ACTUALLY THE NEXT CLAUSE'S HEAD?
	#
	# For a MIDDLE clause it is: a continuation's close is its body's close, and in the shared form
	# the brace that closes an @elif's body is the `} @else {` line itself. Removing head..close
	# INCLUSIVE therefore deleted the next clause's head along with the clause the user asked to
	# delete, leaving its body orphaned in the middle of the markup. Only a LONE closer may be
	# removed with the range.
	var next_is_head := _line_opens_clause(str(lines[close]))
	var last := close - 1 if next_is_head else close

	var out := PackedStringArray()
	for i in range(lines.size()):
		if i >= head and i <= last:
			continue
		out.append(str(lines[i]))

	if next_is_head:
		# The surviving head keeps the brace balance of the clause it now follows. A SEPARATE
		# clause deleted from in front of a SHARED next head leaves that head's leading `}`
		# closing a body that no longer exists.
		if not shared_head:
			var at := head
			if at < out.size():
				var survivor := str(out[at])
				var trimmed := survivor.strip_edges()
				if trimmed.begins_with("}"):
					out[at] = _indent_of_line(survivor) + trimmed.substr(1).strip_edges()
	elif shared_head:
		# A SHARED head carried the previous clause's closing brace away with it, so one has to go
		# back; a SEPARATE head carried nothing, and adding one would unbalance the file the other
		# way.
		out.insert(head, _indent_of_line(str(lines[head])) + "}")
	return "
".join(out)


## Renames the module's OWN export declaration.
##
## `move_to` rewrites folders, file names and every importer's SPECIFIER, and its caller's comment
## claimed it renamed the export too. It never did -- so a renamed module kept
## `export OldName()` while its file said `NewName.guitkx`, every importer asked for a name
## nothing exported, and nothing said so.
##
## Capped at one substitution: the declaration is the definition, and a later mention of the same
## word is a use that the caller rewrites separately or deliberately leaves alone.
static func rename_export(source: String, old_name: String, new_name: String) -> String:
	if old_name.is_empty() or new_name.is_empty() or old_name == new_name:
		return source
	var re := RegEx.create_from_string("\\bexport\\s+(?:[A-Za-z_][A-Za-z0-9_]*\\s+)*?" \
		+ old_name + "\\b")
	var found := re.search(source)
	if found == null:
		return source
	var head := found.get_string()
	return source.substr(0, found.get_start()) \
		+ head.substr(0, head.length() - old_name.length()) + new_name \
		+ source.substr(found.get_end())


## Rewrites an importer's reference to a module that was renamed: the imported NAME, and -- when
## the file binds it under that same name -- every use of it.
##
## The uses matter as much as the import. A component importing `Card` writes `<Card />`; leaving
## those behind turns a rename into a file that imports one name and uses another.
static func rename_binding(source: String, spec: String, old_name: String,
		new_name: String) -> String:
	if old_name.is_empty() or new_name.is_empty() or old_name == new_name:
		return source
	var binding := ""
	for imp in Compiler.scan_imports(source):
		if str(imp.get("spec", "")) != spec:
			continue
		for entry in (imp.get("names", []) as Array):
			var pair := entry as Dictionary
			var remote := str(pair.get("remote", ""))
			var local := str(pair.get("name", ""))
			if remote == old_name or (remote.is_empty() and local == old_name):
				binding = local
				break
	if binding.is_empty():
		return source

	var out := _ensure_import_line(remove_import(source, spec, PackedStringArray([old_name])),
		spec,
		PackedStringArray([new_name if binding == old_name else "%s as %s" % [new_name, binding]]),
		PackedStringArray([new_name]))
	if binding != old_name:
		# An aliased import already reads under a name the rename does not touch.
		return out
	# The binding WAS the old name, so every use of it moves too.
	var re := RegEx.create_from_string("\\b" + old_name + "\\b")
	return re.sub(out, new_name, true)


## Whether a source line opens a directive clause -- `@else {`, `} @elif (x) {`, `@case (1) {`.
##
## Asked of the line rather than of the projection, because `delete_clause` is a pure text edit
## and must not need a card to be correct.
static func _line_opens_clause(line: String) -> bool:
	var text := line.strip_edges()
	if text.begins_with("}"):
		text = text.substr(1).strip_edges()
	return text.begins_with("@")


## Whether `row`'s construct has exactly one clause.
##
## Unwrapping REMOVES A CONSTRUCT HEAD and splices its body up a level, which assumes the head is
## the only thing holding the braces. On a multi-clause construct the brace walk stops at the
## `} @else {` line, so the head is deleted and a dangling clause is left behind. Unity refuses
## the operation for exactly this reason and says so; this port offered it on every directive row.
##
## The clauses of a construct are the DIRECTIVE rows that follow the head at its own depth with a
## rising `clause_index`; the body sits deeper and is skipped.
static func is_single_clause(card: Graph.Card, row: Graph.Line) -> bool:
	if card == null or row == null:
		return true
	# FOUND BY SOURCE POSITION, not by object identity. A `Line` handed in from an earlier
	# projection is a different object from the one in this card even when it names the same
	# construct, and identity matching would quietly answer "single clause" for every caller
	# holding a row that is one edit old.
	var at := -1
	for i in card.markup.size():
		var candidate: Graph.Line = card.markup[i]
		if candidate == row or (row.directive_line > 0 				and candidate.directive_line == row.directive_line):
			at = i
			break
	if at < 0:
		return true
	for i in range(at + 1, card.markup.size()):
		var other: Graph.Line = card.markup[i]
		if other.depth > row.depth:
			continue          # the clause body
		if other.depth < row.depth:
			return true       # left the construct entirely
		if other.kind == Graph.LineKind.DIRECTIVE and other.clause_index > row.clause_index:
			return false      # a continuation: @elif / @else / another @case
		return true
	return true


## The continuation clauses of a construct, in order. Empty for a row that is not a head.
static func clauses_of(card: Graph.Card, head: Graph.Line) -> Array:
	var out: Array = []
	if card == null or head == null:
		return out
	var at := -1
	for i in card.markup.size():
		var candidate: Graph.Line = card.markup[i]
		if candidate == head or (head.directive_line > 0 \
				and candidate.directive_line == head.directive_line):
			at = i
			break
	if at < 0:
		return out
	# A @match's ARMS SIT ONE LEVEL DEEPER than its head, because the match's body is a container
	# of clauses rather than markup. Every other construct's continuations are siblings of the
	# head. Walking at the head's own depth therefore found nothing for a @match and treated its
	# arms as body.
	var arm_depth := head.depth + 1 if head.badge == Graph.Badge.MATCH else head.depth
	for i in range(at + 1, card.markup.size()):
		var other: Graph.Line = card.markup[i]
		if other.depth < head.depth or (other.depth == head.depth and arm_depth > head.depth):
			break                       # left the match entirely
		if other.depth != arm_depth:
			continue                    # a clause's own body
		if other.kind == Graph.LineKind.DIRECTIVE and other.clause_index > head.clause_index:
			out.append(other)
			continue
		if arm_depth == head.depth:
			break                       # a sibling that is not a continuation ends the construct
	return out


## Whether a construct already carries a clause with this badge text -- `"@else"`, `"@default"`.
##
## "Add @else" was offered on an @if that already had one, and produced a second `} @else {` that
## does not compile. The language has one else; the menu has to know that.
static func construct_has_clause(card: Graph.Card, head: Graph.Line, badge_text: String) -> bool:
	for clause in clauses_of(card, head):
		if (clause as Graph.Line).badge_text == badge_text:
			return true
	return false


## The index of the row that IS the component's return root, or -1.
##
## A component must return exactly one node, so that row cannot be deleted. The guard was
## `row_index > 0` -- literally index zero -- which is the predicate Unity's own comment names as
## the mistake: after wrapping the root in an `@if`, the root element is row 1 and the directive is
## row 0, so "Delete element" was offered on the one row that must stay.
static func first_element_row(card: Graph.Card) -> int:
	if card == null:
		return -1
	for i in card.markup.size():
		if (card.markup[i] as Graph.Line).kind != Graph.LineKind.DIRECTIVE:
			return i
	return -1


## Whether a row is TEXT rather than an affordance.
##
## The card lists "+ entry", "+ hook" and "+ code" as rows, and they are synthetic `Line`s with no
## span -- `at` and `end_at` both 0. Deleting one ran `remove` over the range 0..0, which cuts the
## FIRST LINE OF THE FILE.
static func has_span(row: Graph.Line) -> bool:
	return row != null and row.end_at > row.at


## Whether a row may be unwrapped at all.
##
## Three refusals, all Unity's: never from a CONTINUATION (the unwrap assumes it starts at a
## construct head and corrupts the brace balance from a clause line), never a `@match` (its body
## is clauses, not markup, so splicing it up a level leaves bare `@case`es), and never a
## multi-clause construct.
static func can_unwrap(card: Graph.Card, row: Graph.Line) -> bool:
	if row == null or row.kind != Graph.LineKind.DIRECTIVE:
		return false
	if row.clause_index > 0:
		return false
	if row.badge == Graph.Badge.MATCH or row.badge == Graph.Badge.CASE \
			or row.badge == Graph.Badge.DEFAULT:
		return false
	return is_single_clause(card, row)


## Every directive a row can be wrapped in, and the header each one is seeded with.
##
## The seeds are LITERALS that compile. Ported from the Unity leg's `AddWrapItems`, including its
## reason: a placeholder identifier ("condition", "count") is a name the compiler can only reject,
## so the preview reports an error on a wrap the user has not begun to type. `@while` seeds FALSE
## deliberately -- a true-seeded render loop would not terminate.
## The line separators, built rather than written: an escape in a source literal has to survive
## every layer that touches this file, and one that does not becomes a real newline inside a
## string -- which is a parse error a long way from where it was introduced.
static func _lf() -> String:
	return String.chr(10)


static func _crlf() -> String:
	return String.chr(13) + String.chr(10)

const WRAPS := [
	{ "label": "@if", "header": "@if (true)" },
	# `range(1)`, not `[]`: a seeded wrap has to keep the row it wrapped ON SCREEN. An empty
	# collection iterates zero times, so wrapping an element in @for made it vanish from the
	# preview, and the user's next move was to work out what they had broken.
	{ "label": "@for", "header": "@for (item in range(1))" },
	{ "label": "@while", "header": "@while (false)" },
]


## Wraps a row in a `@match` with one `@case` around it.
##
## Its own operation rather than another `WRAPS` entry: a match's body is a container of clauses,
## not markup, so the row has to land inside a `@case` -- wrapping it the way the others wrap
## produces a match whose body is an element, which the parser refuses.
static func wrap_in_match(source: String, row: Graph.Line) -> String:
	if row == null:
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
			out.append(indent + "@match (0) {")
			out.append(indent + unit + "@case (0) {")
			out.append(indent + unit + unit + "return (")
		if i >= from and i <= to:
			out.append(unit + unit + unit + str(lines[i]))
		else:
			out.append(str(lines[i]))
		if i == to:
			out.append(indent + unit + unit + ")")
			out.append(indent + unit + "}")
			out.append(indent + "}")
	return "
".join(out)


## Replaces a component's SETUP island -- the code between its body open and its markup return.
##
## Ported from the Unity leg's `OnIslandEdited`, including its normalisation: leading and
## trailing blank lines go, the block's common indent is stripped, and one unit is put back. An
## island pasted from somewhere else otherwise carries that file's indentation into this one.
static func set_island(source: String, row_start: int, row_end: int, text: String) -> String:
	if row_start <= 0:
		return source
	var lines := source.split("
")
	var from: int = clampi(row_start - 1, 0, lines.size() - 1)
	var to: int = clampi(row_end - 1, from, lines.size() - 1)
	var unit := _indent_unit(source)

	var replacement := PackedStringArray()
	# CRLF NORMALISED FIRST: pasted text often carries it, and a stray carriage return left on
	# the end of a line survives into the buffer as a character the compiler counts and nobody
	# can see.
	for line in text.replace(_crlf(), _lf()).split(_lf()):
		replacement.append(str(line))
	while replacement.size() > 0 and str(replacement[replacement.size() - 1]).strip_edges().is_empty():
		replacement.remove_at(replacement.size() - 1)
	while replacement.size() > 0 and str(replacement[0]).strip_edges().is_empty():
		replacement.remove_at(0)

	var shallowest := 1 << 30
	for line in replacement:
		if not str(line).strip_edges().is_empty():
			shallowest = mini(shallowest, _indent_of_line(str(line)).length())
	if shallowest == (1 << 30):
		shallowest = 0

	var out := PackedStringArray()
	for i in range(lines.size()):
		if i == from:
			for line in replacement:
				var text_line := str(line)
				out.append("" if text_line.strip_edges().is_empty()
					else unit + text_line.substr(shallowest))
			continue
		if i > from and i <= to:
			continue
		out.append(str(lines[i]))
	return "
".join(out)


## Removes a directive WRAPPER, keeping what it wrapped. The inverse of `wrap_in_directive`.
##
## Ported from the Unity leg's `RemoveDirectiveBlock`. The header, its `return (` / `)`
## scaffolding and the closing brace go, and the block that was inside de-indents to where the
## header used to be.
##
## The block is found by BRACE DEPTH from the header rather than from the row's `close_line`: a
## clause the user has been editing may not agree with the projection yet, and unwrapping to the
## wrong line takes a chunk of unrelated markup with it.
static func unwrap_directive(source: String, row: Graph.Line) -> String:
	# REFUSED FROM A CONTINUATION even when a caller offers it: this walks braces from a construct
	# head, and from an `@else` line the head's own `}` and `{` cancel, so the walk stops on the
	# very next line and takes the body's `return (` with it.
	if row != null and row.clause_index > 0:
		return source
	if row == null or row.directive_line <= 0:
		return source
	var lines := source.split("
")
	var header := row.directive_line - 1
	if header < 0 or header >= lines.size():
		return source

	var depth := 0
	var close := -1
	for i in range(header, lines.size()):
		for c in str(lines[i]):
			if c == "{":
				depth += 1
			elif c == "}":
				depth -= 1
		if depth <= 0 and i > header:
			close = i
			break
	if close < 0:
		return source

	var inner := PackedStringArray()
	for i in range(header + 1, close):
		inner.append(str(lines[i]))

	# The `return (` / `)` pair belonged to the wrapper, not to what it wrapped.
	var open_at := -1
	var close_at := -1
	for i in range(inner.size()):
		var trimmed := str(inner[i]).strip_edges()
		if trimmed == "return (" and open_at < 0:
			open_at = i
		if trimmed == ")":
			close_at = i
	if open_at >= 0 and close_at > open_at:
		inner.remove_at(close_at)
		inner.remove_at(open_at)

	# De-indent by however much the shallowest surviving line is deeper than the header was.
	var header_indent := _indent_of_line(str(lines[header])).length()
	var shallowest := 1 << 30
	for line in inner:
		if not str(line).strip_edges().is_empty():
			shallowest = mini(shallowest, _indent_of_line(str(line)).length())
	var shift: int = 0 if shallowest == (1 << 30) else maxi(0, shallowest - header_indent)

	var out := PackedStringArray()
	for i in range(lines.size()):
		if i == header:
			for line in inner:
				var text := str(line)
				out.append(text.substr(shift) if text.length() >= shift 					and text.substr(0, shift).strip_edges().is_empty() else text)
			continue
		if i > header and i <= close:
			continue
		out.append(str(lines[i]))
	return "
".join(out)


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


