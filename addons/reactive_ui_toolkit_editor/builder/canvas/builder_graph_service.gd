@tool
class_name RuitkBuilderGraphService
extends RefCounted
## Projects the builder's tree into the canvas model: a card per module, a row per meaningful
## line, an edge per import.
##
## The TREE is the inventory. Every module in it gets a card, its text comes from its BUFFER,
## and its imports are parsed from that buffer -- so what the canvas shows is what the user has
## typed, always, with no round trip and no file read. Nothing here opens a file.
##
## STRUCTURAL, NOT TEXTUAL. Every fact comes from the compiler's own analysis:
## `analyzed_decls` for declarations and exports, `decl_structure` for a component's parsed
## markup, `scan_imports` for the preamble, `RuitkGuitkxJsxScan.element_end` for tag spans. The
## Unity leg reaches for regular expressions here -- a dozen of them, each with a comment about
## the declaration head it mistook for a call -- because its parser does not surface the shapes.
## Ours does, so none of that guessing is needed and none of it can drift from the compiler.
##
## Cross-file references go through preload CONSTS, never the global `class_name`s -- see
## `builder_module.gd` for why.

const Module = preload("res://addons/reactive_ui_toolkit_editor/builder/document/builder_module.gd")
const Paths = preload("res://addons/reactive_ui_toolkit_editor/builder/document/builder_paths.gd")
## `Metrics.Section` values an edge can leave from. Held as plain ints: the metrics preload the
## canvas view, which projects from this service, and naming the enum here closes that ring.
## A newline, built rather than written: an escape in a source literal has to survive every layer
## between here and the file.
const _LF := "
"

const SECTION_IMPORTS := 1
const SECTION_MARKUP := 3

const Specifiers = preload("res://addons/reactive_ui_toolkit_editor/builder/document/builder_specifiers.gd")
const BuilderTree = preload("res://addons/reactive_ui_toolkit_editor/builder/document/builder_tree.gd")
const Graph = preload("res://addons/reactive_ui_toolkit_editor/builder/canvas/builder_graph.gd")
const Metrics = preload("res://addons/reactive_ui_toolkit_editor/builder/canvas/builder_canvas_metrics.gd")

const Compiler = preload("res://addons/reactive_ui_toolkit/guitkx/guitkx.gd")
const Resolve = preload("res://addons/reactive_ui_toolkit/guitkx/guitkx_resolve.gd")
const Markup = preload("res://addons/reactive_ui_toolkit/guitkx/guitkx_markup.gd")
const JsxScan = preload("res://addons/reactive_ui_toolkit/guitkx/guitkx_jsx_scan.gd")
const L = preload("res://addons/reactive_ui_toolkit/guitkx/guitkx_lexer.gd")


# ── Projection ───────────────────────────────────────────────────────────────────────

## Projects the canvas model from the tree. `focus_path` decides only the ROOT the layout is
## seeded from; membership is the whole tree, so a module whose only import was just broken --
## or that has not been wired up yet -- keeps its card while the user builds it.
static func project(modules: Array, focus_path: String) -> Graph:
	var graph := Graph.new()

	# ORDER MATTERS, and it must not be a hash order: anything keyed on a card INDEX would
	# address a different module every time the membership changed. Sorted by path, the
	# numbering only moves when the tree genuinely does.
	var ordered: Array[Module] = []
	for m in modules:
		if m is Module and not (m as Module).file_path().is_empty():
			ordered.append(m)
	ordered.sort_custom(func(a, b): return Paths.key(a.file_path()) < Paths.key(b.file_path()))

	var index_by_key := {}
	for module in ordered:
		var card := Graph.Card.new()
		card.file_path = module.file_path()
		card.module_id = module.id
		# The file name minus `.guitkx`, NOT the module's bare name: the bare name has the
		# companion infix stripped, so `app`, `app.style` and `app.hooks` all read as "app" and a
		# family of three cards is three cards called the same thing.
		# The module's own name, WITHOUT the companion infix: a style card titled
		# "newComponent.style" spends its widest line repeating what its badge already says, and
		# the name a reader is looking for is the part in front.
		card.title = _card_title(card.file_path)
		card.read_only = module.read_only
		index_by_key[Paths.key(card.file_path)] = graph.cards.size()
		graph.cards.append(card)
		populate_card(card, module.buffer_text)

	for i in range(graph.cards.size()):
		_append_edges_for(graph, i, index_by_key)

	graph.root_path = _resolve_root(ordered, focus_path)
	seed_positions(graph, graph.index_of(graph.root_path))
	return graph


## Rebuilds the import edges that START at one card, after its text changed.
##
## A card re-projection rewrites the card's CONTENT; imports are STRUCTURE. Left alone, an
## import the user just typed gets its row -- and the anchor dot the card paints per import row
## -- while the edge list still knows nothing about it, so the dot has no line until something
## remounts the whole canvas.
static func refresh_edges_for(graph: Graph, card_index: int) -> void:
	if graph == null or card_index < 0 or card_index >= graph.cards.size():
		return
	var kept: Array[Graph.Edge] = []
	for e in graph.edges:
		if e.from_index != card_index:
			kept.append(e)
	graph.edges = kept
	var index_by_key := {}
	for i in range(graph.cards.size()):
		index_by_key[Paths.key(graph.cards[i].file_path)] = i
	_append_edges_for(graph, card_index, index_by_key)


static func _append_edges_for(graph: Graph, card_index: int, index_by_key: Dictionary) -> void:
	var card := graph.cards[card_index]
	# What each imported NAME resolves to, so a usage row can be matched to a card without
	# re-resolving the specifier once per row.
	var target_of_name := {}

	var import_index := 0
	for row in card.imports:
		# A theme or asset directive names a resource, not a module: no node, so no edge.
		if row.badge == Graph.Badge.IMPORT_ASSET:
			continue
		var edge := Graph.Edge.new()
		edge.from_index = card_index
		edge.specifier = row.name
		edge.names = row.attr_pairs
		edge.from_row = import_index
		edge.from_section = SECTION_IMPORTS
		# An unresolved specifier still produces an edge with no target: the import row is real
		# even when what it points at is not there yet, and a broken edge is what tells the
		# canvas to draw the dot as unsatisfied rather than to draw nothing at all.
		var mapped := Specifiers.map(card.file_path, row.name)
		edge.to_index = int(index_by_key.get(Paths.key(mapped), -1)) if not mapped.is_empty() else -1
		edge.target_kind = graph.cards[edge.to_index].kind if edge.to_index >= 0 else Module.Kind.UNKNOWN
		graph.edges.append(edge)
		if edge.to_index >= 0:
			for imported in row.attr_pairs:
				target_of_name[str(imported)] = edge.to_index
		import_index += 1

	# AND ONE PER MARKUP ROW THAT INSTANTIATES ANOTHER MODULE. Only rows whose tag is a name this
	# card actually imported: a `<Button />` is a Godot class, not a module, and an edge to nothing
	# is worse than no edge.
	for row_index in card.markup.size():
		var row: Graph.Line = card.markup[row_index]
		if row.kind != Graph.LineKind.COMPONENT:
			continue
		if not target_of_name.has(row.name):
			continue
		var usage := Graph.Edge.new()
		usage.from_index = card_index
		usage.to_index = int(target_of_name[row.name])
		usage.specifier = row.name
		usage.names = PackedStringArray([row.name])
		usage.from_row = row_index
		usage.from_section = SECTION_MARKUP
		usage.is_usage = true
		usage.target_kind = graph.cards[usage.to_index].kind
		graph.edges.append(usage)


## The card the layout is seeded from: the module the focus belongs to, preferring the component
## that owns the tree root folder. Asked of the MODULES, never of disk -- a tree that has never
## been saved has no files, and a disk answer would move the root every time a nested component
## was created, re-keying the whole saved layout.
static func _resolve_root(ordered: Array[Module], focus_path: String) -> String:
	if ordered.is_empty():
		return ""
	var focus := Paths.canon(focus_path)
	var root_folder := BuilderTree.resolve_root_from(ordered, focus if not focus.is_empty() \
		else ordered[0].file_path())
	for module in ordered:
		if module.owns_folder() and Paths.same(module.folder, root_folder):
			return module.file_path()
	# No component owns the root folder, so the focus is as good an anchor as there is.
	# THE TREE ELECTS ITS OWN ROOT, and only then the focus. Falling straight through to the focus
	# means the same module list re-roots itself every time the user selects a different card --
	# the canvas rearranges because somebody clicked. UB-185's mechanism, one fallback earlier.
	#
	# Unity's order: a module that OWNS the root folder (above); else the ordinally-smallest module
	# that LIVES in the root folder; else the first of the path-sorted inventory; and the focus
	# only when there is no inventory to ask.
	var shallowest := ""
	for module in ordered:
		if not Paths.same(module.folder, root_folder):
			continue
		var candidate: String = module.file_path()
		if shallowest.is_empty() or candidate < shallowest:
			shallowest = candidate
	if not shallowest.is_empty():
		return shallowest
	if not ordered.is_empty():
		return ordered[0].file_path()
	return focus




# ── Card detail ──────────────────────────────────────────────────────────────────────

## Fills a card's sections from a module's BUFFER: exports, signature, import rows, hook chips,
## the code island, the flattened markup tree, and the export detail a style or util module
## shows instead of markup.
##
## A module that does not parse still gets its header card and whatever sections did resolve --
## a half-typed file is the normal state while someone is typing in it.
static func populate_card(card: Graph.Card, text: String) -> void:
	card.clear_detail()
	var source := Module.normalize_lf(text)
	var lines := source.split("\n")

	var analyzed := Compiler.analyzed_decls(source)
	var decls: Array = analyzed["decls"]
	for dm in decls:
		if bool(dm["export"]):
			card.exports.append(str(dm["name"]))

	card.kind = classify(source, card.file_path, decls)
	var binding := _binding_decl(source, decls)
	if not binding.is_empty():
		card.signature = _signature_of(binding)
		card.exposed_signature = _exposed_of(binding)

	_fill_imports(card, source, lines)
	_fill_hook_chips(card, source, lines, decls)

	# A HOOK OR A UTIL HAS SETUP TOO, and hiding it means the card lies about what the module does.
	# `decl_structure` is component-shaped -- it answers `{ok: false}` for anything else -- so the
	# island for those kinds is sliced from the declaration's own body span, which
	# `analyzed_decls` already carries. Unity runs its extraction for Component OR Hook for the
	# same reason.
	if card.kind != Module.Kind.COMPONENT and not binding.is_empty():
		var plain := _plain_body_structure(source, binding)
		if bool(plain.get("ok", false)):
			_fill_island(card, source, plain)

	var projected_markup := false
	if card.kind == Module.Kind.COMPONENT and not binding.is_empty():
		var structure := Compiler.decl_structure(source, binding)
		if bool(structure.get("ok", false)):
			_fill_island(card, source, structure)
			var body_at := int(structure.get("body_at", 0))
			var root: Variant = structure.get("root", {})
			if root is Dictionary and not (root as Dictionary).is_empty():
				_walk_markup(root, 0, card.markup, source, body_at, lines)
			projected_markup = true
	if not projected_markup:
		# A component whose markup will not parse -- mid-edit, which is most of the time someone
		# is typing -- falls back to the export detail every other kind shows. A card with two
		# empty sections says nothing at all, and says it exactly when the user most needs to see
		# which declaration the file still has.
		_fill_export_detail(card, source, decls, lines)


## What a module IS, for the card's badge.
##
## The DECLARATION decides, never the file name: the compiler classifies by signature, and a
## card that read the suffix instead would disagree with the compiler about the same file. The
## one refinement is presentational -- a data module living in a `.style.guitkx` is a STYLE
## module, which is what the user calls it and what the drag gesture treats it as.
##
## The suffix is the fallback only when there is nothing to classify: an empty buffer, or one
## too broken to yield a declaration.
static func classify(text: String, file_path: String, decls: Array = []) -> Module.Kind:
	var rows := decls if not decls.is_empty() else (Compiler.analyzed_decls(text)["decls"] as Array)
	var binding := _binding_decl(text, rows)
	if binding.is_empty():
		return Module.kind_of(file_path) if not file_path.is_empty() else Module.Kind.UNKNOWN
	match str(binding["kind"]):
		"component":
			return Module.Kind.COMPONENT
		"hook":
			return Module.Kind.HOOK
		"util":
			return Module.Kind.UTIL
		"module":
			return Module.Kind.MODULE
		"value":
			return Module.Kind.STYLE if Paths.ends_with_ci(
				file_path, Paths.SUFFIX_STYLE) else Module.Kind.VALUE
	return Module.Kind.UNKNOWN


## The declaration a file is known by -- the compiler's own rule, borrowed rather than repeated:
## the `@class_name` override if there is one, else the first exported declaration, else the
## first declaration at all.
static func _binding_decl(text: String, decls: Array) -> Dictionary:
	if decls.is_empty():
		return {}
	var name := Resolve.binding_of(text)
	for dm in decls:
		if str(dm["name"]) == name:
			return dm
	return decls[0]


static func _signature_of(decl: Dictionary) -> String:
	var name := str(decl["name"])
	match str(decl["kind"]):
		"value":
			var type_text := str(decl.get("type_text", ""))
			return "%s: %s" % [name, type_text] if not type_text.is_empty() else name
		"module":
			return name
	var params := str(decl.get("params", "")).strip_edges()
	var ret := str(decl.get("ret", "")).strip_edges()
	var out := "%s(%s)" % [name, _collapse(params)]
	# A COMPONENT'S return type is not signature, it is ceremony: every component returns markup,
	# so "-> RuitkVNode" on every card in the tree distinguishes nothing and costs the widest row
	# on the card. A hook or a util returns something a caller has to know, and keeps it.
	if not ret.is_empty() and str(decl["kind"]) != "component":
		out += " -> " + ret
	return out


## What a module hands back, when that is worth a row of its own. A component always returns
## markup, so saying so adds nothing; a hook or util's return type is the thing a caller needs.
static func _exposed_of(decl: Dictionary) -> String:
	var kind := str(decl["kind"])
	if kind != "hook" and kind != "util":
		return ""
	return str(decl.get("ret", "")).strip_edges()


# ── Imports ──────────────────────────────────────────────────────────────────────────

## Every preamble row, in source order: the module imports, and the `@uss`/`@theme` directive
## that names a theme resource.
##
## EVERY import line gets a row, because the card is the editing surface -- a row the card
## declined to show would be unselectable and un-right-clickable, and would silently disagree
## with the source pane beside it.
static func _fill_imports(card: Graph.Card, source: String, lines: PackedStringArray) -> void:
	var rows: Array[Graph.Line] = []
	for imp in Compiler.scan_imports(source):
		var spec := str(imp.get("spec", ""))
		var at := int(imp.get("at", 0))
		var row := _line(Graph.LineKind.IMPORT, _import_text(imp), at, int(imp.get("end", at)), source, lines)
		row.name = spec
		row.attrs_text = spec
		row.attr_pairs = _import_names(imp)
		row.badge = _import_badge(spec)
		rows.append(row)

	for hit in _theme_directives(source):
		var trow := _line(Graph.LineKind.IMPORT, str(hit["text"]),
			int(hit["at"]), int(hit["end"]), source, lines)
		trow.name = str(hit["path"])
		trow.attrs_text = str(hit["path"])
		trow.badge = Graph.Badge.IMPORT_ASSET
		rows.append(trow)

	rows.sort_custom(func(a, b): return a.at < b.at)
	card.imports = rows


static func _import_badge(spec: String) -> Graph.Badge:
	if Paths.ends_with_ci(spec, ".style"):
		return Graph.Badge.IMPORT_STYLE
	if Paths.ends_with_ci(spec, ".hooks"):
		return Graph.Badge.IMPORT_HOOKS
	return Graph.Badge.IMPORT_PLAIN


## The LOCAL names an import binds -- what the card shows on the row and what an edge carries.
## An aliased name binds under the alias, so that is the name the rest of the file uses.
static func _import_names(imp: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var ns := str(imp.get("ns", ""))
	if not ns.is_empty():
		out.append(ns)
	var def := str(imp.get("def", ""))
	if not def.is_empty():
		out.append(def)
	for entry in (imp.get("names", []) as Array):
		out.append(str((entry as Dictionary).get("name", "")))
	return out


static func _import_text(imp: Dictionary) -> String:
	var spec := str(imp.get("spec", ""))
	var clauses := PackedStringArray()
	var def := str(imp.get("def", ""))
	if not def.is_empty():
		clauses.append(def)
	var ns := str(imp.get("ns", ""))
	if not ns.is_empty():
		clauses.append("* as " + ns)
	var named := PackedStringArray()
	for entry in (imp.get("names", []) as Array):
		var e := entry as Dictionary
		var local := str(e.get("name", ""))
		var remote := str(e.get("remote", local))
		named.append(local if remote == local else "%s as %s" % [remote, local])
	if not named.is_empty():
		clauses.append("{ %s }" % ", ".join(named))
	var clause := ", ".join(clauses) if not clauses.is_empty() else "{ }"
	return "import %s from \"%s\"" % [clause, spec]


## The `@uss` / `@theme` preamble directive, as { text, path, at, end }. One per file by the
## language's own rule, but the scan does not assume it -- a file with two is a diagnostic the
## compiler raises, and the card should show what is actually written.
static func _theme_directives(source: String) -> Array:
	var out: Array = []
	var i := 0
	var n := source.length()
	while i < n:
		i = Compiler._skip_ws_and_comments(source, i)
		if i >= n:
			break
		if L.keyword_at(source, i, "import"):
			i = Compiler.import_end(source, i)
			continue
		var is_uss := source.substr(i, 4) == "@uss"
		var is_theme := source.substr(i, 6) == "@theme"
		if is_uss or is_theme:
			var line_end := source.find("\n", i)
			if line_end == -1:
				line_end = n
			var raw := source.substr(i, line_end - i)
			out.append({
				"text": raw.strip_edges(),
				"path": _quoted_of(raw),
				"at": i,
				"end": line_end,
			})
			i = line_end
			continue
		if source[i] == "@":   # any other @directive line -- skip it whole
			var le := source.find("\n", i)
			i = n if le == -1 else le
			continue
		break
	return out


static func _quoted_of(text: String) -> String:
	for quote in ["\"", "'"]:
		var open := text.find(quote)
		if open == -1:
			continue
		var close := text.find(quote, open + 1)
		if close != -1:
			return text.substr(open + 1, close - open - 1)
	return ""


# ── Hook chips ───────────────────────────────────────────────────────────────────────

## Every hook CALL in the file, as a chip row.
##
## Declaration heads are excluded by SPAN, taken from the compiler's own enumeration: a hook
## module declares `use_thing(` at the top of itself, and a scan that only looked at the text
## would file that declaration as the first call the body makes.
static func _fill_hook_chips(card: Graph.Card, source: String,
		lines: PackedStringArray, decls: Array) -> void:
	var heads: Array = []
	for dm in decls:
		var head_end := int(dm.get("body_open", int(dm.get("value_start", int(dm["at"])))))
		heads.append({ "from": int(dm["start"]), "to": maxi(head_end, int(dm["at"])) })

	var i := 0
	var n := source.length()
	while i < n:
		var j := L.skip_noncode(source, i)
		if j != i:
			i = j
			continue
		if not L._is_ident_code(source.unicode_at(i)) \
				or (i > 0 and L._is_ident_code(source.unicode_at(i - 1))):
			i += 1
			continue
		var start := i
		while i < n and L._is_ident_code(source.unicode_at(i)):
			i += 1
		var word := source.substr(start, i - start)
		if not _is_hook_name(word) or not _is_call_at(source, i):
			continue
		if _inside_any(heads, start):
			continue
		# A dotted call keeps its qualifier on the chip: a namespace-imported hook reads as
		# `Hooks.use_thing`, and dropping the qualifier would make two different hooks from two
		# different modules render as the same chip.
		var qualifier := _qualifier_before(source, start)
		var display := qualifier + word
		var line1 := _line_of(source, start)
		var lhs := _binding_lhs(lines, line1)
		card.body.append(_hook_line(
			display if lhs.is_empty() else "%s  →  %s" % [display, lhs],
			display, start, i, line1, lines))


static func _hook_line(text: String, name: String, at: int, end_at: int,
		line1: int, lines: PackedStringArray) -> Graph.Line:
	var row := Graph.Line.new()
	row.kind = Graph.LineKind.HOOK
	row.text = text
	row.name = name
	row.at = at
	row.end_at = end_at
	row.source_line = line1
	row.source_text = lines[line1 - 1].strip_edges() if line1 >= 1 and line1 <= lines.size() else ""
	return row


## Whether a name is a hook by the language's rules: one of the runtime's own (`useState`,
## camelCase after React), or a user hook, which the compiler classifies by its `use_` prefix.
static func _is_hook_name(word: String) -> bool:
	if word.begins_with("use_") and word.length() > 4:
		return true
	if word.length() > 3 and word.begins_with("use") \
			and word.unicode_at(3) >= 65 and word.unicode_at(3) <= 90:
		return true
	return word in Compiler.hook_names()


static func _is_call_at(source: String, i: int) -> bool:
	var k := i
	while k < source.length() and (source[k] == " " or source[k] == "\t"):
		k += 1
	return k < source.length() and source[k] == "("


## The `Name.` qualifier immediately before an identifier, or "".
static func _qualifier_before(source: String, at: int) -> String:
	var k := at - 1
	while k >= 0 and (source[k] == " " or source[k] == "\t"):
		k -= 1
	if k < 0 or source[k] != ".":
		return ""
	var dot := k
	k -= 1
	var end := k + 1
	while k >= 0 and L._is_ident_code(source.unicode_at(k)):
		k -= 1
	if k + 1 == end:
		return ""
	return source.substr(k + 1, dot - k)


## The variable a hook call's result is bound to on its line, or "". Read from the LINE rather
## than from the call site because that is where a person looks for it.
static func _binding_lhs(lines: PackedStringArray, line1: int) -> String:
	if line1 < 1 or line1 > lines.size():
		return ""
	var text := lines[line1 - 1].strip_edges()
	if not text.begins_with("var ") and not text.begins_with("const "):
		return ""
	var after := text.substr(4 if text.begins_with("var ") else 6).strip_edges()
	var cut := after.length()
	for token in [":=", "=", ":"]:
		var at := after.find(token)
		if at != -1 and at < cut:
			cut = at
	return after.substr(0, cut).strip_edges()


static func _inside_any(spans: Array, index: int) -> bool:
	for span in spans:
		if index >= int(span["from"]) and index < int(span["to"]):
			return true
	return false


# ── Code island ──────────────────────────────────────────────────────────────────────

## The component's setup lines that are not hook calls -- the card's code island -- with the
## common indent stripped and the 1-based source range they occupy, so an island edit replaces
## exactly that range and nothing around it.
## A `structure`-shaped answer for a declaration that has no markup: a hook, a util, a value.
##
## The same two keys `_fill_island` reads from `decl_structure` -- `setup` and `body_at` -- so the
## island is filtered, indent-stripped and given a write-back range by exactly the code that does
## it for a component, rather than by a second implementation that would drift from it.
##
## The trailing `return` is dropped: it is the declaration's RESULT, which the card shows as the
## exposed signature, not part of its setup.
static func _plain_body_structure(source: String, decl: Dictionary) -> Dictionary:
	var body_open := int(decl.get("body_open", -1))
	var next := int(decl.get("next", -1))
	if body_open < 0 or next <= body_open or next > source.length():
		return { "ok": false }
	var close := source.rfind("}", next)
	if close <= body_open:
		return { "ok": false }
	var body := source.substr(body_open + 1, close - body_open - 1)

	var lines := body.split(_LF)
	var last := lines.size() - 1
	while last >= 0 and str(lines[last]).strip_edges().is_empty():
		last -= 1
	if last >= 0 and str(lines[last]).strip_edges().begins_with("return"):
		lines.remove_at(last)
	return { "ok": true, "setup": _LF.join(lines), "body_at": body_open }


static func _fill_island(card: Graph.Card, source: String, structure: Dictionary) -> void:
	var setup := str(structure.get("setup", ""))
	if setup.strip_edges().is_empty():
		return
	var body_at := int(structure.get("body_at", 0))
	var first_line := _line_of(source, body_at)
	var setup_lines := setup.split("\n")

	var kept := PackedStringArray()
	var start_line := 0
	var end_line := 0
	for k in range(setup_lines.size()):
		var raw := setup_lines[k]
		if raw.strip_edges().is_empty():
			continue
		var line1 := first_line + k
		var is_hook := false
		for chip in card.body:
			if chip.source_line == line1:
				is_hook = true
				break
		if is_hook:
			continue
		kept.append(raw)
		if start_line == 0:
			start_line = line1
		end_line = line1
	if kept.is_empty():
		return
	card.island_lines = _strip_common_indent(kept)
	card.island_start_line = start_line
	card.island_end_line = end_line


## Removes the indentation every line shares, so the island reads as a block rather than as a
## slice of a body. Blank lines do not vote -- an empty line has no indent to speak of, and
## counting it as zero would strip nothing at all.
static func _strip_common_indent(lines: PackedStringArray) -> PackedStringArray:
	var common := -1
	for line in lines:
		if line.strip_edges().is_empty():
			continue
		var indent := 0
		while indent < line.length() and (line[indent] == "\t" or line[indent] == " "):
			indent += 1
		common = indent if common < 0 else mini(common, indent)
	if common <= 0:
		return lines
	var out := PackedStringArray()
	for line in lines:
		out.append(line.substr(common) if line.length() >= common else line.strip_edges())
	return out


# ── Markup ───────────────────────────────────────────────────────────────────────────

## Flattens the parsed markup tree into rows, depth-first, one row per node.
##
## `base` rebases the node's offsets into the module's buffer. Offsets COMPOSE: a directive
## carries its body as a substring plus that substring's own offset, so re-parsing it and adding
## `base + body_at` puts the nested rows in the same coordinate space as everything else.
static func _walk_markup(node: Variant, depth: int, out: Array[Graph.Line],
		source: String, base: int, lines: PackedStringArray) -> void:
	if not (node is Dictionary):
		return
	var nd := node as Dictionary
	var at := base + int(nd.get("at", 0))
	match str(nd.get("t", "")):
		"el":
			var tag := str(nd.get("tag", ""))
			var span := _element_span(source, at)
			var row := _line(_tag_kind(tag), "<%s>" % tag, at, int(span["end"]), source, lines)
			row.name = tag
			row.depth = depth
			row.self_closing = bool(span["self_closing"])
			row.attr_pairs = _attr_pairs(nd, source, base)
			row.attrs_text = " ".join(row.attr_pairs)
			out.append(row)
			for child in (nd.get("children", []) as Array):
				_walk_markup(child, depth + 1, out, source, base, lines)
		"frag":
			var frow := _line(Graph.LineKind.ELEMENT, "<>", at, at + 2, source, lines)
			frow.name = "Fragment"
			frow.depth = depth
			out.append(frow)
			for child in (nd.get("children", []) as Array):
				_walk_markup(child, depth + 1, out, source, base, lines)
		"text":
			# Structure only -- see the note on the directive-body segments above.
			return
		"expr":
			var code := str(nd.get("code", "")).strip_edges()
			# The span is the braces the user wrote, matched -- not the trimmed code's length,
			# which stops short of the closing brace whenever the expression has padding, and
			# would leave a span-exact edit writing over the `}`.
			var brace_end := L.find_matching(source, at) if at < source.length() \
				and source[at] == "{" else -1
			var erow := _line(Graph.LineKind.EXPRESSION, "{%s}" % code, at,
				(brace_end + 1) if brace_end != -1 else at + maxi(2, code.length() + 2),
				source, lines)
			erow.name = code
			erow.depth = depth
			out.append(erow)
		"comment":
			return
		"if":
			_walk_if(nd, depth, out, source, base, lines, at)
		"for", "while":
			_walk_loop(nd, depth, out, source, base, lines, at)
		"match":
			_walk_match(nd, depth, out, source, base, lines, at)


## A directive clause is a ROW OF ITS OWN -- the badge does not ride the clause's first element
## row. A badge that rode its first child could not be selected when the clause was empty, and a
## clause with two children showed one badge for two rows.
static func _walk_if(nd: Dictionary, depth: int, out: Array[Graph.Line],
		source: String, base: int, lines: PackedStringArray, at: int) -> void:
	var branches: Array = nd.get("branches", [])
	# The parser leaves `else_body` NULL when there is no else clause, and `str(null)` is the
	# literal "<null>" -- non-empty, so a naive test grows a phantom `@else` row under every
	# single-branch `@if` in the file.
	var else_body := _opt_string(nd.get("else_body"))
	var has_else := not else_body.strip_edges().is_empty()

	# An `@if` chain has no outer brace: the CONSTRUCT closes where its last clause does. Taken
	# from the head's own brace instead, the construct would appear to end at the first branch,
	# and a move or delete keyed on that range would carry away one clause of three.
	var last_body_at := base + int(nd.get("else_body_at", 0)) if has_else \
		else base + int((branches[branches.size() - 1] as Dictionary).get("body_at", 0))
	var construct_close := _body_close_line(source, last_body_at)
	var construct_close_at := _body_close_at(source, last_body_at)

	for k in range(branches.size()):
		var branch := branches[k] as Dictionary
		var body_at := base + int(branch.get("body_at", 0))
		var label := "@if" if k == 0 else "@elif"
		var badge := Graph.Badge.IF if k == 0 else Graph.Badge.ELIF
		# A continuation clause anchors at its own KEYWORD. The parser hands back only where the
		# clause's BODY starts, and a row anchored there sits inside the block it heads -- so a
		# click on the `@elif` selects nothing and the row's line is wrong by the height of the
		# clause above it.
		var head_at := at if k == 0 else _clause_keyword_at(source, body_at, ["@elif", "@else if"])
		# The head's own close is the whole construct's; a continuation's is its own boundary,
		# which is the range a delete-this-clause operates on.
		var close_line := construct_close if k == 0 else _body_close_line(source, body_at)
		var close_at := construct_close_at if k == 0 else _body_close_at(source, body_at)
		out.append(_directive_head(label, badge, str(branch.get("cond", "")), head_at,
			depth, k, close_line, close_at, source, lines))
		_walk_directive_body(str(branch.get("body_markup", "")), body_at,
			depth + 1, out, source, lines)

	if has_else:
		var else_body_at := base + int(nd.get("else_body_at", 0))
		out.append(_directive_head("@else", Graph.Badge.ELSE, "",
			_clause_keyword_at(source, else_body_at, ["@else"]),
			depth, branches.size(), _body_close_line(source, else_body_at),
			_body_close_at(source, else_body_at), source, lines))
		_walk_directive_body(else_body, else_body_at, depth + 1, out, source, lines)


static func _walk_loop(nd: Dictionary, depth: int, out: Array[Graph.Line],
		source: String, base: int, lines: PackedStringArray, at: int) -> void:
	var is_for := str(nd.get("t", "")) == "for"
	var body_at := base + int(nd.get("body_at", 0))
	out.append(_directive_head(
		"@for" if is_for else "@while",
		Graph.Badge.FOR if is_for else Graph.Badge.WHILE,
		str(nd.get("header", "")), at, depth, 0,
		_body_close_line(source, body_at), _body_close_at(source, body_at), source, lines))
	_walk_directive_body(str(nd.get("body_markup", "")), body_at, depth + 1, out, source, lines)


static func _walk_match(nd: Dictionary, depth: int, out: Array[Graph.Line],
		source: String, base: int, lines: PackedStringArray, at: int) -> void:
	# A `@match` DOES have an outer brace, so its own close is the construct's.
	var construct_close := _line_of(source, _construct_end(source, at))
	out.append(_directive_head("@match", Graph.Badge.MATCH, str(nd.get("subject", "")),
		at, depth, 0, construct_close, _construct_end(source, at) + 1, source, lines))
	var cases: Array = nd.get("cases", [])
	for k in range(cases.size()):
		var c := cases[k] as Dictionary
		var body_at := base + int(c.get("body_at", 0))
		out.append(_directive_head("@case", Graph.Badge.CASE, str(c.get("value", "")),
			_clause_keyword_at(source, body_at, ["@case"]), depth + 1, k + 1,
			_body_close_line(source, body_at), _body_close_at(source, body_at), source, lines))
		_walk_directive_body(str(c.get("body_markup", "")), body_at, depth + 2, out, source, lines)
	var default_body := _opt_string(nd.get("default_body"))
	if not default_body.strip_edges().is_empty():
		var default_at := base + int(nd.get("default_body_at", 0))
		out.append(_directive_head("@default", Graph.Badge.DEFAULT, "",
			_clause_keyword_at(source, default_at, ["@default"]), depth + 1, cases.size() + 1,
			_body_close_line(source, default_at), _body_close_at(source, default_at), source, lines))
		_walk_directive_body(default_body, default_at, depth + 2, out, source, lines)


## The offset of the clause keyword that heads the body starting at `body_at`. Searched BACKWARD
## from the body, because between a clause keyword and its body there is only that clause's own
## header. Falls back to the body itself when the spelling is not one of `labels` -- a row at the
## wrong place is still better than a row at offset zero.
static func _clause_keyword_at(source: String, body_at: int, labels: Array) -> int:
	var best := -1
	for label in labels:
		best = maxi(best, source.rfind(str(label), maxi(0, body_at - 1)))
	return best if best >= 0 else body_at


## The 1-based line of the `}` that closes the body whose text starts at `body_at`.
## The offset just past the `}` that closes the body whose text starts at `body_at`.
static func _body_close_at(source: String, body_at: int) -> int:
	var open := source.rfind("{", maxi(0, body_at))
	if open == -1:
		return body_at
	var close := L.find_matching_markup(source, open)
	return (close + 1) if close != -1 else body_at


## The 1-based line of the `}` that closes the body whose text starts at `body_at`.
static func _body_close_line(source: String, body_at: int) -> int:
	var open := source.rfind("{", maxi(0, body_at))
	if open == -1:
		return _line_of(source, body_at)
	var close := L.find_matching_markup(source, open)
	return _line_of(source, close if close != -1 else body_at)

## Walks a directive's body at the given depth. `body_at` restores the offsets to the buffer's
## own coordinates.
##
## A directive body is a GDScript BLOCK, not a markup fragment: `@if (c) { return ( <X/> ) }`.
## Splitting it the compiler's way is the only way to tell the prep statements from the markup
## returns -- parsing the whole body as markup instead turns `return (` and its closing `)` into
## rows of their own, and the card grows two meaningless lines per clause.
static func _walk_directive_body(body_markup: String, body_at: int, depth: int,
		out: Array[Graph.Line], source: String, lines: PackedStringArray) -> void:
	if body_markup.strip_edges().is_empty():
		return
	var split := Compiler._split_body(body_markup)
	if split.has("error"):
		return
	for part in (split.get("parts", []) as Array):
		var pd := part as Dictionary
		# CODE INSIDE A CLAUSE IS NOT A MARKUP ROW.
		#
		# This emitted one row per non-blank line, reasoning that the code is the user's own and
		# the card is the editing surface. That reasoning is wrong: the markup section shows the
		# STRUCTURE of what a component returns, and a `var` line and a `#` comment are neither.
		# Opened on a real file it put four lines of prose from a source comment into the
		# RETURN -- MARKUP section of that file's own card.
		#
		# The Unity leg's walk handles exactly six node kinds -- element, if, foreach, for, while,
		# switch -- and skips everything else, which is why this cannot happen there. Editing that
		# code is the source pane's job; a component's setup already has the SETUP section.
		if str(pd.get("t", "")) == "gd" or not bool(pd.get("markup", false)):
			continue
		var parser := Markup.new()
		var parsed := parser.parse(body_markup, int(pd["m_start"]), int(pd["m_end"]))
		if str(parsed.get("error", "")) != "":
			continue
		for child in (parsed.get("nodes", []) as Array):
			_walk_markup(child, depth, out, source, body_at, lines)


## One PLAIN row per non-blank line of a GDScript segment inside a directive body.
static func _append_code_rows(body: String, from: int, to: int, body_at: int, depth: int,
		out: Array[Graph.Line], source: String, lines: PackedStringArray) -> void:
	var at := from
	while at < to:
		var nl := body.find("\n", at)
		var stop: int = to if nl == -1 or nl > to else nl
		var text := body.substr(at, stop - at).strip_edges()
		if not text.is_empty():
			var row := _line(Graph.LineKind.PLAIN, text, body_at + at, body_at + stop, source, lines)
			row.depth = depth
			out.append(row)
		at = stop + 1


static func _directive_head(label: String, badge: Graph.Badge, header: String,
		at: int, depth: int, clause_index: int, close_line: int, close_at: int,
		source: String, lines: PackedStringArray) -> Graph.Line:
	var head := header.strip_edges()
	var text := label if head.is_empty() else "%s (%s)" % [label, head]
	# The span is the WHOLE clause, not just the keyword. A row's span is what a delete removes
	# and what a move carries -- sized to the keyword, deleting an `@if` takes its head and leaves
	# the body behind as loose statements in the middle of the markup.
	var row := _line(Graph.LineKind.DIRECTIVE, text, at,
		maxi(close_at, at + label.length()), source, lines)
	row.depth = depth
	row.badge = badge
	row.badge_text = label
	# THE EXPRESSION ALONE, not the rendered header. This feeds the inline editor, and
	# `set_directive_header` replaces only what is INSIDE the parentheses -- so seeding the editor
	# with the full `@if (true)` and committing it unchanged wrote `@if (@if (true))`. The
	# compiler accepted that file, and the generated .gd then failed at load, so nothing warned.
	row.directive_text = head
	row.directive_line = row.source_line
	row.close_line = close_line
	row.clause_index = clause_index
	return row


## Where a directive construct ends. The parser hands back the clause bodies but not the
## construct's own extent, so the closing brace is found by matching from the head's first `{`.
static func _construct_end(source: String, at: int) -> int:
	var open := source.find("{", at)
	if open == -1:
		return at
	var close := L.find_matching_markup(source, open)
	return at if close == -1 else close


## An element's extent, through the COMPILER's own tag scanner -- so a `<` inside an attribute
## expression is never mistaken for a nested tag, and the card's line range agrees with what the
## compiler compiled.
static func _element_span(source: String, at: int) -> Dictionary:
	var open_tag := JsxScan.scan_open_tag(source, at, source.length())
	var self_closing := bool(open_tag.get("self_closing", false))
	if int(open_tag.get("gt", -1)) == -1:
		return { "end": at, "self_closing": false }
	if self_closing:
		return { "end": int(open_tag["gt"]) + 1, "self_closing": true }
	var end := JsxScan.element_end(source, at, source.length())
	return { "end": int(open_tag["gt"]) + 1 if end == -1 else end, "self_closing": false }


## A tag is a COMPONENT when it is not a Godot class the host can instantiate. The open
## vocabulary is the compiler's rule too: any instantiable ClassDB Node class is a valid tag, so
## anything else in a file that compiles is a user component.
static func _tag_kind(tag: String) -> Graph.LineKind:
	if tag.is_empty():
		return Graph.LineKind.ELEMENT
	if ClassDB.class_exists(tag) and ClassDB.can_instantiate(tag):
		return Graph.LineKind.ELEMENT
	if tag in Compiler.host_tags():
		return Graph.LineKind.ELEMENT
	return Graph.LineKind.COMPONENT


## One attribute per entry, spelled as written (`text="hi"`, `style={s}`, `disabled`) -- the
## inline editor edits one value at a time, so they cannot be a single joined string.
static func _attr_pairs(nd: Dictionary, source: String, base: int) -> PackedStringArray:
	var out := PackedStringArray()
	for a in (nd.get("attrs", []) as Array):
		var attr := a as Dictionary
		var kind := str(attr.get("kind", ""))
		if kind == "comment":
			continue
		var name := str(attr.get("name", ""))
		var value := str(attr.get("value", ""))
		match kind:
			"bool":
				out.append(name)
			"str":
				out.append("%s=\"%s\"" % [name, value])
			"spread":
				out.append("{...%s}" % value)
			_:
				out.append("%s={%s}" % [name, value])
	return out


# ── Export detail ────────────────────────────────────────────────────────────────────

## What a non-component card shows where a component shows markup: its exported surface.
##
## A style module lists each export and the entries inside it, so a style can be edited from the
## canvas without opening the source. Everything else lists its declarations with their
## signatures.
static func _fill_export_detail(card: Graph.Card, source: String,
		decls: Array, lines: PackedStringArray) -> void:
	for dm in decls:
		var at := int(dm["at"])
		var end := int(dm["next"])
		var is_style_entry := card.kind == Module.Kind.STYLE and str(dm["kind"]) == "value"
		var header := _line(Graph.LineKind.EXPORT, _signature_of(dm), at, end, source, lines)
		header.name = str(dm["name"])
		header.badge = Graph.Badge.STYLE_HEADER if is_style_entry else Graph.Badge.UTIL_BODY
		card.export_detail.append(header)

		if is_style_entry:
			for entry in _dict_entries(source, int(dm.get("value_start", at)), end):
				var erow := _line(Graph.LineKind.PLAIN, str(entry["text"]),
					int(entry["at"]), int(entry["end"]), source, lines)
				erow.depth = 1
				erow.name = str(entry["key"])
				card.export_detail.append(erow)
			var add := Graph.Line.new()
			add.kind = Graph.LineKind.PLAIN
			add.depth = 1
			add.badge = Graph.Badge.ADD_ENTRY
			add.text = "+ entry"
			add.name = str(dm["name"])
			card.export_detail.append(add)


## The top-level `"key": value` pairs of a dictionary literal starting at or after `from`.
##
## Split at top-level commas only, through the lexer, so a nested dictionary or an array of
## dictionaries stays one entry instead of being torn apart at its own separators.
static func _dict_entries(source: String, from: int, limit: int) -> Array:
	var out: Array = []
	var open := source.find("{", from)
	if open == -1 or open >= limit:
		return out
	var close := L.find_matching(source, open)
	if close == -1 or close > limit:
		return out

	var i := open + 1
	var start := i
	while i < close:
		var j := L.skip_noncode(source, i)
		if j != i:
			i = j
			continue
		var c := source.unicode_at(i)
		# A nested group is skipped WHOLE, so the commas inside it are never seen -- which is
		# what keeps `"nested": { "a": 1, "b": 2 }` one entry rather than two fragments of
		# nothing. Skipping is why no depth counter is needed: at this point there is no depth.
		if c == L.C_LBRACE or c == L.C_LBRACKET or c == L.C_LPAREN:
			var m := L.find_matching(source, i)
			i = close if m == -1 else m + 1
			continue
		if c == 44:   # ','
			_append_entry(out, source, start, i)
			start = i + 1
		i += 1
	_append_entry(out, source, start, close)
	return out


static func _append_entry(out: Array, source: String, from: int, to: int) -> void:
	var raw := source.substr(from, to - from)
	if raw.strip_edges().is_empty():
		return
	var lead := 0
	while lead < raw.length() and (raw[lead] == " " or raw[lead] == "\t" or raw[lead] == "\n"):
		lead += 1
	var text := raw.strip_edges()
	out.append({
		"text": text,
		"key": _quoted_of(text),
		"at": from + lead,
		"end": from + lead + text.length(),
	})


# ── Layout ───────────────────────────────────────────────────────────────────────────

## The gap left between cards by the seeded layout. Only the SEED: once a card has a saved
## position, that position wins.
##
## The column PITCH is the widest a card ever gets plus this gap, not a number of its own. A
## pitch narrower than the widest LOD overlaps adjacent columns at that zoom -- which is a click
## that selects the card behind the one under the cursor, and only at one zoom level.
const LAYOUT_GAP := 48.0


## Seeds a position for every card: the root first, then the cards it reaches, breadth-first, one
## column per level. Deterministic, because the card order is -- two runs over the same tree
## produce the same layout, so nothing moves when the user has changed nothing.
static func seed_positions(graph: Graph, root_index: int) -> void:
	if graph.cards.is_empty():
		return
	var level := {}
	var start: int = root_index if root_index >= 0 else 0
	level[start] = 0
	var queue: Array[int] = [start]
	while not queue.is_empty():
		var current: int = queue.pop_front()
		for e in graph.edges_from(current):
			if e.to_index < 0 or level.has(e.to_index):
				continue
			level[e.to_index] = int(level[current]) + 1
			queue.append(e.to_index)
	# Anything the root cannot reach still gets a home, in a column of its OWN past the deepest
	# reachable one: an unwired module is the normal state of a module created a moment ago, and
	# mixing it into a column of real dependents reads as a dependency it does not have.
	var deepest := 0
	for value in level.values():
		deepest = maxi(deepest, int(value))
	for i in range(graph.cards.size()):
		if not level.has(i):
			level[i] = deepest + 1

	# A STYLE COMPANION IS NOT A CHILD. It is a dependency, so the walk above put it a level down
	# with the components -- but a style module belongs to the component that uses it the way a
	# companion file does, and dropped into the row of children it reads as a fourth sibling.
	# It sits on its owner's own row instead.
	for i in range(graph.cards.size()):
		if graph.cards[i].kind != Module.Kind.STYLE:
			continue
		for e in graph.edges:
			if e.to_index == i and level.has(e.from_index):
				level[i] = int(level[e.from_index])
				break

	# TOP-DOWN: a level is a ROW, and siblings spread along it. Levels used to be columns, which
	# made every tree a left-to-right chain -- and since most trees are one parent with several
	# children, that is one card beside a tall vertical stack of the rest. A parent over its
	# children is the shape the graph actually has.
	var by_level := {}
	for i in range(graph.cards.size()):
		var lv := int(level[i])
		if not by_level.has(lv):
			by_level[lv] = []
		(by_level[lv] as Array).append(i)

	var levels := by_level.keys()
	levels.sort()
	var next_row_y := 0.0
	for lv in levels:
		var row: Array = by_level[lv]
		# Centred on the row above it, so a parent sits over the middle of its children rather
		# than over the leftmost one.
		var span := float(row.size()) * (Metrics.CARD_WIDTH_FULL + LAYOUT_GAP) - LAYOUT_GAP
		var x := -span * 0.5
		var tallest := 0.0
		for i in row:
			var card := graph.cards[i]
			card.x = x
			card.y = next_row_y
			x += Metrics.CARD_WIDTH_FULL + LAYOUT_GAP
			# Measured, not a fixed pitch: a card taller than the pitch overlaps the row below it,
			# and two overlapping cards make a click ambiguous.
			tallest = maxf(tallest, Metrics.card_height(card))
		next_row_y += tallest + LAYOUT_GAP


# ── Row helpers ──────────────────────────────────────────────────────────────────────

static func _line(kind: Graph.LineKind, text: String, at: int, end_at: int,
		source: String, lines: PackedStringArray) -> Graph.Line:
	var row := Graph.Line.new()
	row.kind = kind
	row.text = text
	row.at = at
	row.end_at = end_at
	row.source_line = _line_of(source, at)
	var last := _line_of(source, maxi(at, end_at - 1))
	row.end_line = last if last > row.source_line else 0
	if row.source_line >= 1 and row.source_line <= lines.size():
		row.source_text = lines[row.source_line - 1].strip_edges()
	return row


## The 1-based line an offset falls on.
static func _line_of(source: String, offset: int) -> int:
	if offset <= 0:
		return 1
	return source.substr(0, mini(offset, source.length())).count("\n") + 1


## A parser field that is either a String or null. `str(null)` is the literal "<null>", which
## reads as content everywhere it is tested -- so the null has to be caught before conversion.
static func _opt_string(value: Variant) -> String:
	return str(value) if value is String else ""


## Whitespace collapsed to single spaces. A declaration head may wrap across lines -- a component
## with a dozen defaulted parameters usually does -- and a signature row is one line.
static func _collapse(text: String) -> String:
	var out := ""
	var space := false
	for i in range(text.length()):
		var c := text[i]
		if c == " " or c == "\t" or c == "\n":
			space = true
			continue
		if space and not out.is_empty():
			out += " "
		space = false
		out += c
	return out


## The name a card wears: the file name with the `.guitkx` suffix and any companion infix
## (`.style`, `.hooks`, `.utils`) removed. The badge carries the kind; the title carries the name.
static func _card_title(file_path: String) -> String:
	var stem := file_path.get_file().trim_suffix(Paths.SUFFIX_PLAIN)
	for infix in [".style", ".hooks", ".utils"]:
		if stem.ends_with(infix):
			return stem.trim_suffix(infix)
	return stem
