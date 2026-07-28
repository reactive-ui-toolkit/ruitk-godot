@tool
class_name GuitkxCompletion
extends RefCounted
## Pure completion-item provider for `.guitkx` markup: given a caret, returns *what* to offer,
## sourced from GuitkxContext + GuitkxSchema (live ClassDB) + GuitkxWorkspace. Deliberately UI-free
## so it is unit-testable headlessly; GuitkxCodeEdit maps the items onto add_code_completion_option.
## Attribute-value and embedded-GDScript contexts yield nothing here (the analyzer layer owns those,
## Phase 4). [Phase 1 -- plans/GODOT_ANALYZER_INTEGRATION_PLAN.md §7]

# Item kinds (the editor maps these to CodeEdit.KIND_*).
const CLASS := "class"
const MEMBER := "member"
const SIGNAL := "signal"
const KEYWORD := "keyword"

## Common built-in constants for `<Type>.<member>` completion inside expressions — a static
## fallback for the most-used ones (mirrors the VS Code server's BUILTIN_MEMBERS; the embedded
## analyzer tier supplies the full set once M3 lands).
const BUILTIN_MEMBERS := {
	"Color": ["WHITE", "BLACK", "TRANSPARENT", "RED", "GREEN", "BLUE", "YELLOW", "CYAN", "MAGENTA",
		"GRAY", "DARK_GRAY", "LIGHT_GRAY", "ORANGE", "PURPLE", "PINK", "BROWN", "GOLD", "LIME_GREEN",
		"SKY_BLUE", "AQUA", "NAVY_BLUE", "TEAL", "MAROON", "SILVER", "CRIMSON"],
	"Vector2": ["ZERO", "ONE", "INF", "LEFT", "RIGHT", "UP", "DOWN"],
	"Vector2i": ["ZERO", "ONE", "MIN", "MAX", "LEFT", "RIGHT", "UP", "DOWN"],
	"Vector3": ["ZERO", "ONE", "INF", "LEFT", "RIGHT", "UP", "DOWN", "FORWARD", "BACK"],
}

## Array of { kind:String, insert:String, display:String } for the caret at char `offset` in `text`.
## `path` (optional) is the buffer's own .guitkx path -- it lets the embedded tier resolve
## relative import specifiers for namespace-member completion (M7.1).
static func for_caret(text: String, offset: int, path: String = "") -> Array:
	# Import-brace completion (0.11.1 field wave): a caret inside `import { | } from "./x"` —
	# including the COMBINED `import Def, { | } from` — offers the target's exported names.
	# Checked before classify(): an import line is preamble, not markup/embedded code.
	var ib := _import_brace_completion(text, offset, path)
	if ib is Array:
		return ib
	var ctx := GuitkxContext.classify(text, offset)
	match ctx["kind"]:
		GuitkxContext.KIND_TAG:
			return _tags("")
		GuitkxContext.KIND_MARKUP:
			return _tags("<") + _directives(false)
		GuitkxContext.KIND_ATTR:
			return _attributes(str(ctx["tag"]))
		GuitkxContext.KIND_ATTR_VALUE:
			return _attr_values(str(ctx["tag"]), str(ctx.get("attr", "")))
		GuitkxContext.KIND_DIRECTIVE:
			return _directives(true)
		GuitkxContext.KIND_EMBEDDED:
			return _embedded(text, offset, path)
	return []

static func _item(kind: String, insert: String, display := "") -> Dictionary:
	return { "kind": kind, "insert": insert, "display": display if display != "" else insert }

## null when the caret is NOT inside an import brace list; else the items Array (possibly empty —
## the caller must still stop, not fall through to markup/embedded completion on an import line).
## Line-shaped on purpose: while TYPING the list the import is malformed, so the parsed-imports
## channel (scan_imports) cannot see it. The prefix regex allows the optional combined default
## binding (`import Def, { | }`); when present, the default alias AND the target's default-export
## name join the exclusion set (re-suggesting what the default already binds is noise).
static func _import_brace_completion(text: String, offset: int, path: String) -> Variant:
	var line_start := 0 if offset <= 0 else text.rfind("\n", offset - 1) + 1
	var line_end := text.find("\n", line_start)
	if line_end == -1:
		line_end = text.length()
	var line := text.substr(line_start, line_end - line_start)
	var col := offset - line_start
	var bo := line.find("{")
	if bo == -1 or col <= bo:
		return null
	var pre_re := RegEx.new()
	pre_re.compile("^[ \\t]*import[ \\t]*(?:([A-Za-z_][A-Za-z0-9_]*)[ \\t]*,[ \\t]*)?$")
	var pm := pre_re.search(line.substr(0, bo))
	if pm == null:
		return null
	var bc := line.find("}", bo)
	var region_end := line.length() if bc == -1 else bc
	if col > region_end:
		return null
	if path == "":
		return []
	var spec_re := RegEx.new()
	spec_re.compile("from[ \\t]*[\"']([^\"']+)[\"']")
	var sm := spec_re.search(line, region_end)
	if sm == null:
		return []
	var res: Dictionary = RUIGuitkxResolve.resolve_specifier(sm.get_string(1), path, RUIGuitkxConfig.root_for(path))
	if not bool(res.get("ok", false)):
		return []
	var tbl: Dictionary = RUIGuitkxResolve.decl_table(str(res["guitkx"]))
	var already := {}
	for entry in line.substr(bo + 1, region_end - bo - 1).split(","):
		# Each listed entry may be aliased (`a as b`): the imported NAME must not be re-suggested,
		# and the bound ALIAS would collide with a same-named export — track both.
		for tok in str(entry).strip_edges().split(" ", false):
			if str(tok) != "as":
				already[str(tok)] = true
	var defn := pm.get_string(1)
	if defn != "":
		already[defn] = true
		if str(tbl.get("default", "")) != "":
			already[str(tbl["default"])] = true
	var out: Array = []
	for dn in (tbl["decls"] as Dictionary):
		var dd := (tbl["decls"] as Dictionary)[dn] as Dictionary
		if bool(dd["export"]) and not already.has(str(dn)):
			out.append(_item(MEMBER, str(dn), "%s (%s)" % [str(dn), str(dd["kind"])]))
	return out

static func _tags(prefix: String) -> Array:
	var out: Array = []
	for tag in GuitkxSchema.host_tags():
		out.append(_item(CLASS, prefix + tag))
	for comp in GuitkxWorkspace.component_tags():
		out.append(_item(CLASS, prefix + comp))
	return out

static func _attributes(tag: String) -> Array:
	var out: Array = []
	var seen := {}
	# G20 snippet shape: attributes insert their `=` + an empty value pair — `=""` for string-ish
	# properties, `={}` for events and expression values. The editor's confirm steps the caret
	# back INSIDE the pair, and the `"` then arms value completion (enums/bools/style keys).
	for a in GuitkxSchema.structural_attributes():
		var nm := str(a.get("name", ""))
		_push_snippet(out, seen, MEMBER, nm, nm + ("=\"\"" if str(a.get("type", "")) == "String" else "={}"))
	var gclass := GuitkxSchema.godot_class_for(tag)
	for ev in GuitkxSchema.events_for_class(gclass):
		var en := str(ev.get("name", ""))
		_push_snippet(out, seen, SIGNAL, en, en + "={}")
	# The verbatim `on_<signal>` escape hatch (G28): every signal, both spellings offered like the
	# VS Code extension. React aliases stay first; natives dedupe against them by name.
	for s in GuitkxSchema.godot_signals(gclass):
		var sn := "on_" + str(s.get("name", ""))
		_push_snippet(out, seen, SIGNAL, sn, sn + "={}")
	for p in GuitkxSchema.godot_properties(gclass):
		var pn := str(p.get("name", ""))
		_push_snippet(out, seen, MEMBER, pn,
			pn + ("=\"\"" if str(p.get("type", "")) == "String" else "={}"))
	return out

## Value completion inside `attr="|"` or `style={ {"|` (G5/G6): style-dict keys for `style`-family
## attributes; true/false for bool properties; the hint names for enum properties.
static func _attr_values(tag: String, attr: String) -> Array:
	var out: Array = []
	if attr == "style" or attr.ends_with("_style"):
		for k in GuitkxSchema.style_keys():
			out.append(_item(MEMBER, str((k as Dictionary).get("name", "")),
				"%s (%s)" % [str((k as Dictionary).get("name", "")), str((k as Dictionary).get("type", ""))]))
		return out
	var info := GuitkxSchema.property_info(GuitkxSchema.godot_class_for(tag), attr)
	if info.is_empty():
		return out
	match int(info.get("type", TYPE_NIL)):
		TYPE_BOOL:
			out.append(_item(KEYWORD, "true"))
			out.append(_item(KEYWORD, "false"))
		TYPE_INT:
			if int(info.get("hint", 0)) == PROPERTY_HINT_ENUM:
				for part in str(info.get("hint_string", "")).split(",", false):
					# hint_string entries can be "Name" or "Name:value" — offer the name.
					out.append(_item(KEYWORD, str(part).get_slice(":", 0)))
	return out

## Embedded/setup completion without the analyzer (G7/G8): `<Type>.` builtin constants and the
## built-in hook names. The full type-aware layer arrives with the native analyzer (M3).
static func _embedded(text: String, offset: int, path: String = "") -> Array:
	var line_start := 0 if offset <= 0 else text.rfind("\n", offset - 1) + 1
	var before := text.substr(line_start, offset - line_start)
	var re := RegEx.new()
	re.compile("([A-Za-z_][A-Za-z0-9_]*)\\.([A-Za-z_][A-Za-z0-9_]*)?$")
	var m := re.search(before)
	if m != null and BUILTIN_MEMBERS.has(m.get_string(1)):
		var out: Array = []
		for member in BUILTIN_MEMBERS[m.get_string(1)]:
			out.append(_item(MEMBER, str(member)))
		return out
	# M7.1: `X.` where X is an import local bound to a whole FILE (`import * as X` namespace, or
	# a module-style named import) -- offer the target's EXPORTED declaration names, kind-tagged.
	if m != null and path != "":
		var qual := m.get_string(1)
		var root: String = RUIGuitkxConfig.root_for(path)
		for im in RUIGuitkx.scan_imports(text):
			var binds_file := str(im.get("ns", "")) == qual
			if not binds_file:
				for nm2 in (im.get("names", []) as Array):
					if str((nm2 as Dictionary)["name"]) == qual:
						binds_file = true   # module-style named import: qualified access is its shape
			if not binds_file:
				continue
			var res: Dictionary = RUIGuitkxResolve.resolve_specifier(str(im["spec"]), path, root)
			if not bool(res.get("ok", false)):
				continue
			var tbl: Dictionary = RUIGuitkxResolve.decl_table(str(res["guitkx"]))
			var out_ns: Array = []
			for dn in (tbl["decls"] as Dictionary):
				var dd := (tbl["decls"] as Dictionary)[dn] as Dictionary
				if bool(dd["export"]):
					out_ns.append(_item(MEMBER, str(dn), "%s (%s)" % [str(dn), str(dd["kind"])]))
			if not out_ns.is_empty():
				return out_ns
	# Hook names while typing `use…` (Ctrl+Space; letters aren't auto-trigger prefixes).
	var w := ""
	var i := before.length() - 1
	while i >= 0:
		var c := before.unicode_at(i)
		if c == 95 or (c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122):
			w = before[i] + w
			i -= 1
			continue
		break
	if w.begins_with("u"):
		var out2: Array = []
		for hook in GuitkxHover.HOOKS:
			out2.append(_item(MEMBER, str(hook)))
		return out2
	return []

# When `at_symbol` is true the caret already has the leading `@` typed, so the inserted text drops it.
static func _directives(at_symbol: bool) -> Array:
	var out: Array = []
	for d in GuitkxSchema.control_flow():
		var nm := str(d.get("directive", ""))
		var base := nm.substr(1) if at_symbol else nm
		out.append(_item(KEYWORD, base + _directive_tail(str(d.get("form", ""))), nm))
	if at_symbol:
		for d in GuitkxSchema.preamble_directives():
			var nm := str(d.get("name", ""))
			out.append(_item(KEYWORD, nm.substr(1) + _directive_tail(str(d.get("form", ""))), nm))
	return out

# G20: derive the snippet tail from the directive's documented form — parenthesised forms
# (@if/@for/@match) get " ()", quoted forms (@uss "path") get ' ""', bare forms (@else) nothing.
# The editor's confirm places the caret inside the pair.
static func _directive_tail(form: String) -> String:
	if form.contains("("):
		return " ()"
	if form.contains("\""):
		return " \"\""
	return ""

static func _push(out: Array, seen: Dictionary, kind: String, name: String) -> void:
	if name == "" or seen.has(name):
		return
	seen[name] = true
	out.append(_item(kind, name))

# Deduped push with a snippet insert distinct from the displayed name (G20).
static func _push_snippet(out: Array, seen: Dictionary, kind: String, name: String, insert: String) -> void:
	if name == "" or seen.has(name):
		return
	seen[name] = true
	out.append(_item(kind, insert, name))
