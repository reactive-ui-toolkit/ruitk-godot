@tool
class_name GuitkxVirtualDoc
extends RefCounted
## Build the synthetic GDScript "virtual document" handed to the native analyzer
## (GdscriptAnalyzer), plus a GuitkxSourceMap. Faithful GDScript port of the TS server's
## virtualDoc.ts (ide-extensions/lsp-server) — the parity discipline is per-function provenance:
## every emitter mirrors its TS twin by name, and the shared corpus test pins the emitted shape.
##
## SCOPE-AWARE: emits the REAL control-flow structure (`for x in xs:`, `if cond:`, `match s:`) so
## loop/branch variables are in scope, with each embedded `{expr}` (attribute or child) as a
## `var _eN = (expr)` check INSIDE its block, recursively nested. Hook names are pre-declared as
## class-level static wrapper stubs so `useState(...)` resolves with its real signature.
## Markup/glue is never copied, so the analyzer only ever parses real GDScript. Embedded code is
## spliced VERBATIM (length-preserving), so the offset SourceMap round-trips 1:1.
##
## Reuses the compiler's own primitives (RuitkGuitkxLexer skip_noncode/find_matching/keyword_at,
## RuitkGuitkxJsxScan.find_markup_ranges, RuitkGuitkx._find_decl/_nearest_decl_keyword) — the same
## authorities virtualDoc.ts declares itself a mirror of.

const L := preload("res://addons/reactive_ui_toolkit/guitkx/guitkx_lexer.gd")
const JsxScan := preload("res://addons/reactive_ui_toolkit/guitkx/guitkx_jsx_scan.gd")
const Compiler := preload("res://addons/reactive_ui_toolkit/guitkx/guitkx.gd")
const MapScript := preload("res://addons/reactive_ui_toolkit_editor/lsp/guitkx_source_map.gd")

## One stub per public hook, emitted at CLASS level as a real static wrapper func. `params`/`ret`
## MUST stay byte-identical to the hooks.gd declarations — asserted by the "hook stub signatures
## match hooks.gd" parity test (same discipline as the TS twin's core.test.ts assertion).
const HOOK_STUBS: Array[Dictionary] = [
	{ "name": "useState", "params": "initial = null", "args": "initial", "ret": " -> Array", "tuple": "Variant, Callable" },
	{ "name": "useReducer", "params": "reducer: Callable, initial = null", "args": "reducer, initial", "ret": " -> Array", "tuple": "Variant, Callable" },
	{ "name": "useRef", "params": "initial = null", "args": "initial", "ret": " -> Dictionary" },
	{ "name": "useMemo", "params": "factory: Callable, deps: Array = []", "args": "factory, deps", "ret": " -> Variant" },
	{ "name": "useCallback", "params": "cb: Callable, deps: Array = []", "args": "cb, deps", "ret": " -> Callable" },
	{ "name": "useImperativeHandle", "params": "factory: Callable, deps: Array = []", "args": "factory, deps", "ret": " -> Variant" },
	{ "name": "useEffect", "params": "effect: Callable, deps = null", "args": "effect, deps", "ret": " -> void" },
	{ "name": "useLayoutEffect", "params": "effect: Callable, deps = null", "args": "effect, deps", "ret": " -> void" },
	{ "name": "createContext", "params": "default_value = null, ctx_name: String = \"\"", "args": "default_value, ctx_name", "ret": " -> RuitkContext" },
	{ "name": "useContext", "params": "key", "args": "key", "ret": "" },
	{ "name": "provideContext", "params": "key, value", "args": "key, value", "ret": " -> void" },
	{ "name": "useDeferredValue", "params": "value, deps = null", "args": "value, deps", "ret": "" },
	{ "name": "useTransition", "params": "", "args": "", "ret": " -> Array", "tuple": "bool, Callable" },
	{ "name": "useStableCallback", "params": "cb: Callable", "args": "cb", "ret": " -> Callable" },
	{ "name": "useStableFunc", "params": "cb: Callable", "args": "cb", "ret": " -> Callable" },
	{ "name": "useStableAction", "params": "cb: Callable", "args": "cb", "ret": " -> Callable" },
	{ "name": "useSafeArea", "params": "", "args": "", "ret": " -> Dictionary" },
	{ "name": "useSignal", "params": "sig: RuitkSignal, selector = null, comparer = null", "args": "sig, selector, comparer", "ret": "" },
	{ "name": "useSignalKey", "params": "key: String, initial = null, selector = null, comparer = null", "args": "key, initial, selector, comparer", "ret": "" },
	{ "name": "useTween", "params": "ref: Dictionary, property: String, to, duration: float, deps: Array = []", "args": "ref, property, to, duration, deps", "ret": " -> void" },
	{ "name": "useTweenValue", "params": "from, to, duration: float, on_update: Callable, deps: Array = []", "args": "from, to, duration, on_update, deps", "ret": " -> void" },
	{ "name": "useAnimate", "params": "ref: Dictionary, tracks: Array, autoplay := true, deps: Array = []", "args": "ref, tracks, autoplay, deps", "ret": " -> void" },
	{ "name": "useSfx", "params": "bus := \"Master\"", "args": "bus", "ret": " -> Callable" },
]

# Build state threaded through the emitters (the TS Ctx): src, gen text, map, expr counter.
var _src: String = ""
var _gen: String = ""
var _map: GuitkxSourceMap = null
var _counter: int = 0

## Build the virtual doc for `src`: { "text": String, "map": GuitkxSourceMap }.
## ES-modules leg (mirrors virtualDoc.ts buildVirtualDoc): a file is a SEQUENCE of declarations
## — walk and emit EVERY top-level decl. The FIRST component keeps the bare `render` name;
## later components emit under their decl names (guitkx.gd _compile_mixed); hooks/utils emit
## under their real names; values emit as mapped `static var`s.
static func build(src: String) -> Dictionary:
	var b := GuitkxVirtualDoc.new()
	b._src = src
	b._gen = "extends RefCounted\n"
	b._map = MapScript.new()
	var first: Dictionary = Compiler._find_decl(src, 0)
	if str(first.get("kind", "")) == "":
		return { "text": b._gen, "map": b._map }
	b._declare_hook_stubs()
	b._declare_import_stubs()
	var i := 0
	var first_comp := true
	var n := src.length()
	while i < n:
		var d: Dictionary = Compiler._find_decl(src, i)
		if str(d.get("kind", "")) == "":
			break
		var kind := str(d["kind"])
		var nxt := -1
		var plain: bool = not bool(d.get("deprecated", true))
		if kind == "module":
			b._emit_module_members(int(d["at"]))
			var mb := b._read_decl_body(int(d["at"]))
			nxt = (int(mb["start"]) + str(mb["text"]).length() + 1) if not mb.is_empty() else -1
		elif kind == "component":
			b._emit_decl_func("component", int(d["at"]), "" if first_comp else "_%d" % b._counter, d)
			if not first_comp:
				b._counter += 1
			first_comp = false
			var cb := b._read_decl_body(int(d["body_open"]) if plain else int(d["at"]))
			nxt = (int(cb["start"]) + str(cb["text"]).length() + 1) if not cb.is_empty() else -1
		elif kind == "hook" or kind == "util":
			b._emit_decl_func("hook", int(d["at"]), "_%d" % b._counter, d)
			b._counter += 1
			var hb := b._read_decl_body(int(d["body_open"]) if plain else int(d["at"]))
			nxt = (int(hb["start"]) + str(hb["text"]).length() + 1) if not hb.is_empty() else -1
		elif kind == "value":
			b._emit_value_decl(d)
			nxt = Compiler._value_end(src, int(d["value_start"]))
		elif kind == "export_list" or kind == "export_default":
			nxt = int(d.get("list_end", -1))
		if nxt == -1 or nxt <= i:
			break
		i = nxt
	return { "text": b._gen, "map": b._map }

## E-01 value declaration -> `static var <name>[: Type] = <initializer>`, initializer spliced
## VERBATIM and source-mapped (mirrors virtualDoc.ts emitValueDecl).
func _emit_value_decl(d: Dictionary) -> void:
	var name := str(d.get("name", ""))
	if name == "" or not d.has("value_start"):
		return
	var vs := int(d["value_start"])
	var ve: int = Compiler._value_end(_src, vs)
	if ve == -1:
		return
	var typed := ": %s" % str(d.get("type_text", "")) if (str(d.get("eq_style", "")) == "typed" and str(d.get("type_text", "")) != "") else ""
	var eq := " := " if str(d.get("eq_style", "")) == "infer" else " = "
	var raw := _src.substr(vs, ve - vs)
	var text := raw.strip_edges()
	_gen += "static var %s%s%s" % [name, typed, eq]
	var gs := _gen.length()
	_gen += text
	_map.add_span(vs + (raw.length() - raw.lstrip(" \t\n\r").length()), gs, text.length())
	_gen += "\n"

# One module member = one static func (mirrors emitModuleMembers). Suffixes keep sibling names
# unique; a top-level component/hook keeps the bare `render`/real name.
func _emit_module_members(module_at: int) -> void:
	var body := _read_decl_body(module_at)
	if body.is_empty():
		return
	var to: int = int(body["start"]) + str(body["text"]).length()
	var i: int = int(body["start"])
	while i < to:
		var d: Dictionary = Compiler._find_decl(_src, i)
		if str(d.get("kind", "")) == "" or int(d.get("at", -1)) >= to:
			break
		var b := _read_decl_body(int(d["at"]))
		if str(d["kind"]) == "module":
			_emit_module_members(int(d["at"]))
		else:
			_emit_decl_func(str(d["kind"]), int(d["at"]), "_%d" % _counter)
			_counter += 1
		i = (int(b["start"]) + str(b["text"]).length() + 1) if not b.is_empty() else int(d["at"]) + 1

func _emit_decl_func(kind: String, at: int, suffix: String, d: Dictionary = {}) -> void:
	# Plain (E-01) rows anchor at the NAME and carry their own body_open; the keyword-anchored
	# readers below expect a keyword at `at`, so plain rows feed them their real anchors.
	var plain: bool = not d.is_empty() and not bool(d.get("deprecated", true))
	var body := _read_decl_body(int(d["body_open"]) if plain and d.has("body_open") else at)

	if kind == "hook":
		if body.is_empty():
			return
		# Emitted under its REAL declared name, exactly like the compiler: a sibling module member
		# legally calls it bare. Params are spliced VERBATIM and mapped (a hook body reads its
		# params). The `-> Hint` survives like the compiler's _ret_suffix (tuple hints dropped).
		var name := str(d.get("name", "")) if plain else _read_decl_name(at)
		var params := _read_params_span(at)
		_gen += "static func %s(" % (name if name != "" else "__hook%s" % suffix)
		if not params.is_empty() and str(params["text"]).strip_edges() != "":
			var gs := _gen.length()
			_gen += str(params["text"])
			_map.add_span(int(params["start"]), gs, str(params["text"]).length())
		_gen += ")%s:\n" % _ret_suffix(at)
		_emit_verbatim_block(int(body["start"]), int(body["start"]) + str(body["text"]).length(), 1, "")
		if not _has_statement(str(body["text"])):
			_gen += "\tpass\n"
		return

	# A top-level component compiles to `static func render(...)`; module members keep their
	# real names — mirror both, so a sibling expr referencing a member component resolves.
	var comp_name := "render"
	if suffix != "":
		var declared := str(d.get("name", "")) if plain else _read_decl_name(at)
		comp_name = declared if declared != "" else "render%s" % suffix
	_gen += "static func %s(props: Dictionary, children: Array) -> RuitkVNode:\n" % comp_name
	if body.is_empty():
		_gen += "\tpass\n"
		return
	var prop_vars := _param_names(_read_params(at))
	for pname in prop_vars:
		_gen += "\tvar %s = props.get(\"%s\")\n" % [pname, pname]
	var body_start: int = int(body["start"])
	var body_end: int = body_start + str(body["text"]).length()
	var split := _split_return(body_start, body_end)

	# Setup verbatim (mapped per line). Markup inside setup — an early/demoted markup return —
	# is neutralized first (length+newline-preserving) so the analyzer never parses raw `<Tag>`.
	var setup_end: int = int(split["setup_end"])
	var setup_has_stmt := setup_end > body_start and _has_statement(_src.substr(body_start, setup_end - body_start))
	if setup_end > body_start:
		_emit_verbatim_block(body_start, setup_end, 1,
			_neutralize_setup_markup(_src.substr(body_start, setup_end - body_start)))
	var emitted := _emit_markup(int(split["markup_start"]), int(split["markup_end"]), 1)
	# `pass` when nothing above counts as a statement (a func body of only comments is invalid).
	if not emitted and not setup_has_stmt and prop_vars.is_empty():
		_gen += "\tpass\n"

# True when the block has at least one real statement line (not blank, not a `#` comment).
func _has_statement(block: String) -> bool:
	for l in block.split("\n"):
		var t := (l as String).strip_edges()
		if t != "" and not t.begins_with("#"):
			return true
	return false

## --- scope-aware markup emitter (mirrors emitMarkup/emitTagAttrs/emitControl/emitMatchArms) ---

func _emit_markup(start: int, end: int, indent: int) -> bool:
	var i := start
	var any := false
	while i < end:
		var c := _src[i]
		if c == "\"" or c == "'":
			i = L.skip_noncode(_src, i)  # starting AT a quote == the TS skipString
			continue
		if c == "@":
			var kw := _read_word(i + 1)
			if kw == "if" or kw == "for" or kw == "while" or kw == "match":
				i = _emit_control(i, kw, end, indent)
				any = true
				continue
			i += 1
			continue
		if c == "<":
			if i + 1 < _src.length() and _src[i + 1] == "/":
				var gt := _src.find(">", i)
				i = end if (gt == -1 or gt >= end) else gt + 1
				continue
			if i + 1 < _src.length() and _is_name_start(_src[i + 1]):
				var r := _emit_tag_attrs(i, end, indent)
				if bool(r["emitted"]):
					any = true
				i = int(r["next"])
				continue
			i += 1
			continue
		if c == "{":
			var close := L.find_matching(_src, i)
			if close != -1 and close < end:
				# A `{/* comment */}` hole is markup commentary, not a GDScript expression.
				if _src.substr(i + 1, close - i - 1).strip_edges().begins_with("/*"):
					i = close + 1
					continue
				_emit_expr(i + 1, close, indent)
				any = true
				i = close + 1
				continue
		i += 1
	return any

# Emit a tag's `={expr}` attribute checks at `indent`; return past `>`/`/>` (children are walked
# by the caller's loop, same indent — a `<Tag>` adds no GDScript scope).
func _emit_tag_attrs(lt: int, end: int, indent: int) -> Dictionary:
	var i := lt + 1
	while i < end and _is_name(_src[i]):
		i += 1
	var emitted := false
	while i < end:
		while i < end and _is_ws(_src[i]):
			i += 1
		if i >= end:
			break
		if _src[i] == "/" and i + 1 < end and _src[i + 1] == ">":
			return { "next": i + 2, "emitted": emitted }
		if _src[i] == ">":
			return { "next": i + 1, "emitted": emitted }
		var an := i
		while i < end and (_is_name(_src[i]) or _src[i] == "." or _src[i] == "-"):
			i += 1
		if i == an:
			i += 1
			continue
		while i < end and _is_ws(_src[i]):
			i += 1
		if i < end and _src[i] == "=":
			i += 1
			while i < end and _is_ws(_src[i]):
				i += 1
			if i < end and (_src[i] == "\"" or _src[i] == "'"):
				i = L.skip_noncode(_src, i)
			elif i < end and _src[i] == "{":
				var close := L.find_matching(_src, i)
				if close != -1 and close < end:
					if not _src.substr(i + 1, close - i - 1).strip_edges().begins_with("/*"):
						_emit_expr(i + 1, close, indent)
						emitted = true
					i = close + 1
				else:
					i += 1
	return { "next": end, "emitted": emitted }

# Emit a control-flow block: `for <header>:` / `if <cond>:` / `match <subj>:` with the body's
# exprs nested at indent+1. Returns the index past the directive (including any @elif/@else chain).
func _emit_control(at: int, kw: String, end: int, indent: int) -> int:
	var pad := "\t".repeat(indent)
	var p := at + 1 + kw.length()
	while p < end and _is_ws(_src[p]):
		p += 1
	if p >= end or _src[p] != "(":
		return p
	var pc := L.find_matching(_src, p)
	if pc == -1 or pc >= end:
		return p
	var header_start := p + 1
	var header_text := _src.substr(header_start, pc - header_start).strip_edges()
	var b := pc + 1
	while b < end and _is_ws(_src[b]):
		b += 1
	if b >= end or _src[b] != "{":
		return pc + 1
	var bclose := L.find_matching(_src, b)
	if bclose == -1 or bclose >= end:
		return pc + 1

	if kw == "match":
		_gen += "%smatch %s:\n" % [pad, _map_inline(header_start, header_text)]
		_emit_match_arms(b + 1, bclose, indent + 1)
	else:
		_gen += "%s%s %s:\n" % [pad, kw, _map_inline(header_start, header_text)]
		var inner := _emit_markup(b + 1, bclose, indent + 1)
		if not inner:
			_gen += "%spass\n" % "\t".repeat(indent + 1)
	# @elif / @else chain
	var i := bclose + 1
	while i < end:
		var k := i
		while k < end and _is_ws(_src[k]):
			k += 1
		if k < end and _src[k] == "@" and L.keyword_at(_src, k + 1, "elif"):
			var ep := k + 5
			while ep < end and _is_ws(_src[ep]):
				ep += 1
			if ep >= end or _src[ep] != "(":
				break
			var epc := L.find_matching(_src, ep)
			if epc == -1:
				break
			var cond := _src.substr(ep + 1, epc - ep - 1).strip_edges()
			var eb := epc + 1
			while eb < end and _is_ws(_src[eb]):
				eb += 1
			var ebc := L.find_matching(_src, eb)
			if ebc == -1:
				break
			_gen += "%selif %s:\n" % [pad, _map_inline(ep + 1, cond)]
			if not _emit_markup(eb + 1, ebc, indent + 1):
				_gen += "%spass\n" % "\t".repeat(indent + 1)
			i = ebc + 1
		elif k < end and _src[k] == "@" and L.keyword_at(_src, k + 1, "else"):
			var eb2 := k + 5
			while eb2 < end and _is_ws(_src[eb2]):
				eb2 += 1
			var ebc2 := L.find_matching(_src, eb2)
			if ebc2 == -1:
				break
			_gen += "%selse:\n" % pad
			if not _emit_markup(eb2 + 1, ebc2, indent + 1):
				_gen += "%spass\n" % "\t".repeat(indent + 1)
			i = ebc2 + 1
		else:
			break
	return i

func _emit_match_arms(start: int, end: int, indent: int) -> void:
	var pad := "\t".repeat(indent)
	var i := start
	var emitted_arm := false
	while i < end:
		while i < end and _is_ws(_src[i]):
			i += 1
		if i >= end:
			break
		if _src[i] == "@" and L.keyword_at(_src, i + 1, "case"):
			var p := i + 5
			while p < end and _is_ws(_src[p]):
				p += 1
			if p >= end or _src[p] != "(":
				break
			var pc := L.find_matching(_src, p)
			if pc == -1:
				break
			var val := _src.substr(p + 1, pc - p - 1).strip_edges()
			var b := pc + 1
			while b < end and _is_ws(_src[b]):
				b += 1
			var bclose := L.find_matching(_src, b)
			if bclose == -1:
				break
			_gen += "%s%s:\n" % [pad, _map_inline(p + 1, val)]
			if not _emit_markup(b + 1, bclose, indent + 1):
				_gen += "%spass\n" % "\t".repeat(indent + 1)
			emitted_arm = true
			i = bclose + 1
		elif _src[i] == "@" and L.keyword_at(_src, i + 1, "default"):
			var b2 := i + 8
			while b2 < end and _is_ws(_src[b2]):
				b2 += 1
			var bclose2 := L.find_matching(_src, b2)
			if bclose2 == -1:
				break
			_gen += "%s_:\n" % pad
			if not _emit_markup(b2 + 1, bclose2, indent + 1):
				_gen += "%spass\n" % "\t".repeat(indent + 1)
			emitted_arm = true
			i = bclose2 + 1
		else:
			i += 1
	if not emitted_arm:
		_gen += "%s_:\n%spass\n" % [pad, "\t".repeat(indent + 1)]

# Emit `var _eN = (<expr>)` at `indent`, mapping the expr text verbatim. Markup NESTED inside the
# expression is neutralized (length-preserving `null` padding) so the analyzer never parses `<Tag>`
# as GDScript operators.
func _emit_expr(start: int, end: int, indent: int) -> void:
	var text := _src.substr(start, end - start)
	var trimmed := _lstrip(text)
	var lead := text.length() - trimmed.length()
	if trimmed.strip_edges() == "":
		return
	_gen += "%svar _e%d = (" % ["\t".repeat(indent), _counter]
	_counter += 1
	var gs := _gen.length()
	_gen += _neutralize_markup(trimmed)
	_map.add_span(start + lead, gs, trimmed.length())
	_gen += ")\n"

# Splice an inline expression (a condition/header/match value) into the current line, mapped.
func _map_inline(src_start: int, text: String) -> String:
	_map.add_span(src_start, _gen.length(), text.length())
	return text

# Emit a verbatim source block [start,end) at `indent`, mapping it PER LINE with depth-based
# reindent (tabs normalised; anchored to the first non-blank NON-COMMENT line). `override`, when
# non-empty and length-matching, replaces the emitted CONTENT (length- and newline-preserving,
# e.g. neutralized setup) while offsets keep tracking the real source.
func _emit_verbatim_block(start: int, end: int, indent: int, override: String) -> void:
	var text := override if (override != "" and override.length() == end - start) else _src.substr(start, end - start)
	var raw_lines := text.split("\n")
	var unit := _indent_unit(raw_lines)
	var anchor := -1
	var anchor_any := -1
	var depths: Array[int] = []
	for raw in raw_lines:
		var l := (raw as String).trim_suffix("\r")
		var t := l.strip_edges()
		if t == "":
			depths.append(-1)
			continue
		var d := _indent_depth(l, unit)
		depths.append(d)
		if anchor_any == -1:
			anchor_any = d
		if anchor == -1 and not t.begins_with("#"):
			anchor = d
	if anchor == -1:
		anchor = anchor_any
	var src_off := start
	for k in raw_lines.size():
		var raw := str(raw_lines[k])
		var code := raw.trim_suffix("\r")
		if code.strip_edges() != "":
			var lead_len := code.length() - _lstrip(code).length()
			var level: int = indent + maxi(0, depths[k] - anchor)
			_gen += "\t".repeat(level)
			var gen_code_start := _gen.length()
			_gen += code.substr(lead_len)
			_map.add_span(src_off + lead_len, gen_code_start, code.length() - lead_len)
		if k < raw_lines.size() - 1:
			_gen += "\n"
		src_off += raw.length() + 1
	if not _gen.ends_with("\n"):
		_gen += "\n"

# Inferred space-indent width: the minimum POSITIVE DIFFERENCE between distinct leading-space
# widths (mirrors guitkx.gd _indent_unit / virtualDoc.ts indentUnit).
func _indent_unit(raw_lines: PackedStringArray) -> int:
	var widths := {}
	for raw in raw_lines:
		var l := (raw as String).trim_suffix("\r")
		var sp := 0
		for ci in l.length():
			var c := l[ci]
			if c == " ":
				sp += 1
			elif c != "\t":
				break
		if sp > 0:
			widths[sp] = true
	if widths.is_empty():
		return 1
	var sorted: Array = widths.keys()
	sorted.sort()
	var unit := int(sorted[0])
	for i in range(1, sorted.size()):
		var d := int(sorted[i]) - int(sorted[i - 1])
		if d > 0 and d < unit:
			unit = d
	return maxi(unit, 1)

# Indentation depth of a line in whole levels: tab = `unit` columns, space = 1 column, rounded.
func _indent_depth(l: String, unit: int) -> int:
	var cols := 0
	for ci in l.length():
		var c := l[ci]
		if c == "\t":
			cols += unit
		elif c == " ":
			cols += 1
		else:
			break
	return int(round(float(cols) / float(unit)))

# Class-level static wrapper funcs (see HOOK_STUBS). All stub text is unmapped glue, so an
# analyzer diagnostic inside a stub line is dropped by the to_source() filter — stubs can never
# squiggle user code.
func _declare_hook_stubs() -> void:
	for h in HOOK_STUBS:
		if h.has("tuple"):
			_gen += "## @return-tuple(%s)\n" % str(h["tuple"])
		var call := "Hooks.%s(%s)" % [str(h["name"]), str(h["args"])]
		var body := call if str(h["ret"]) == " -> void" else "return " + call
		_gen += "static func %s(%s)%s: %s\n" % [str(h["name"]), str(h["params"]), str(h["ret"]), body]

# Mirror of virtualDoc.ts declareImportStubs (0.11.1 field wave — the port was missing here, so
# imported names had no declaration in the in-editor analysis): every preamble-imported LOCAL —
# named (rename binds the LOCAL), `* as X` namespace, default, and every part of a COMBINED
# `import Def, { … } / Def, * as X` — is declared as a permissive `static var` so embedded
# references resolve. Consumes the compiler's own scan (no regex twin to drift). Unmapped glue:
# the length-preserving source map is unaffected and stub lines can never squiggle user code.
func _declare_import_stubs() -> void:
	var seen := {}
	for im in Compiler.scan_imports(_src):
		var locals: Array = []
		for nm in (im.get("names", []) as Array):
			locals.append(str((nm as Dictionary)["name"]))
		if str(im.get("ns", "")) != "":
			locals.append(str(im["ns"]))
		if str(im.get("def", "")) != "":
			locals.append(str(im["def"]))
		for lname in locals:
			if lname != "" and Compiler._is_valid_identifier(lname) and not seen.has(lname):
				seen[lname] = true
				_gen += "static var %s\n" % lname

## --- markup neutralizers (mirror jsxScan.ts neutralizeMarkup/neutralizeSetupMarkup) ----------

# Replace each markup range inside an EXPRESSION with `null` + space padding to the same length.
static func _neutralize_markup(expr: String) -> String:
	var ranges: Array = JsxScan.find_markup_ranges(expr, 0, expr.length())
	if ranges.is_empty():
		return expr
	var out := ""
	var prev := 0
	for r in ranges:
		var rs := int((r as Dictionary)["start"])
		if rs < prev:
			continue
		var re := int((r as Dictionary)["end"])
		if re == -1:
			re = expr.length()
		out += expr.substr(prev, rs - prev)
		var pad := "null" + " ".repeat(maxi(0, re - rs - 4))
		out += pad.substr(0, re - rs)
		prev = re
	out += expr.substr(prev)
	return out

# Neutralize markup anywhere in a SETUP block — length- AND newline-preserving (the per-line
# source map depends on every `\n` byte surviving): every non-newline byte in a markup range
# becomes a space, and `null` lands on the first line segment wide enough to hold it.
static func _neutralize_setup_markup(block: String) -> String:
	var ranges: Array = JsxScan.find_markup_ranges(block, 0, block.length())
	if ranges.is_empty():
		return block
	var out := block
	var prev := 0
	for r in ranges:
		var rs := int((r as Dictionary)["start"])
		if rs < prev:
			continue
		var re := int((r as Dictionary)["end"])
		if re == -1:
			re = block.length()
		var placed := false
		var i := rs
		while i < re:
			var seg_end := block.find("\n", i)
			if seg_end == -1 or seg_end > re:
				seg_end = re
			var seg_len := seg_end - i
			var repl := " ".repeat(seg_len)
			if not placed and seg_len >= 4:
				repl = "null" + " ".repeat(seg_len - 4)
				placed = true
			out = out.substr(0, i) + repl + out.substr(seg_end)
			i = seg_end + 1
		prev = re
	return out

## --- declaration / window helpers (mirror virtualDoc.ts, which mirrors guitkx.gd) -------------

func _read_decl_body(decl_at: int) -> Dictionary:
	var n := _src.length()
	var j := decl_at
	while j < n and _src[j] != "{":
		var k := L.skip_noncode(_src, j)
		if k != j:
			j = k
			continue
		if _src[j] == "(":
			var pc := L.find_matching(_src, j)
			if pc == -1:
				return {}
			j = pc + 1
			continue
		j += 1
	if j >= n or _src[j] != "{":
		return {}
	var close := L.find_matching(_src, j)
	if close == -1:
		return {}
	return { "text": _src.substr(j + 1, close - j - 1), "start": j + 1 }

# The window is the LAST top-level markup return (Unity useLastReturn parity — mirrors guitkx.gd
# _split_return / virtualDoc.ts splitReturn): first token on its line, line depth <= the body's
# anchor depth. Statement-level returns (in if:/lambdas) stay in the analyzed setup.
func _split_return(start: int, end: int) -> Dictionary:
	var lines := _src.substr(start, end - start).split("\n")
	var unit := _indent_unit(lines)
	var anchor := -1
	var anchor_any := -1
	for raw in lines:
		var l := (raw as String).trim_suffix("\r")
		var t := l.strip_edges()
		if t == "":
			continue
		var d := _indent_depth(l, unit)
		if anchor_any == -1:
			anchor_any = d
		if not t.begins_with("#"):
			anchor = d
			break
	if anchor == -1:
		anchor = anchor_any
	var chosen := {}
	var i := start
	while i < end:
		var k := L.skip_noncode(_src, i)
		if k != i:
			i = k
			continue
		if L.keyword_at(_src, i, "return"):
			var p := i + 6
			while p < end and _is_ws(_src[p]):
				p += 1
			var ls: int = maxi(start, _src.rfind("\n", maxi(0, i - 1)) + 1)
			var lead := _src.substr(ls, i - ls)
			var top_level := lead.strip_edges() == "" and _indent_depth(lead, unit) <= anchor
			var eol := _src.find("\n", i)
			if eol == -1 or eol > end:
				eol = end
			if p < end and _src[p] == "(":
				var close := L.find_matching(_src, p)
				# A half-typed `return (`: keep analysing the setup ABOVE the return.
				if close == -1 or close >= end:
					return { "setup_end": i, "markup_start": end, "markup_end": end }
				if top_level:
					chosen = { "setup_end": i, "markup_start": p + 1, "markup_end": close }
				i = close + 1
				continue
			if p < end and _src[p] == "<":
				if top_level:
					chosen = { "setup_end": i, "markup_start": p, "markup_end": end }
				i = eol
				continue
			if L.keyword_at(_src, p, "null"):
				i = p + 4
				continue
			i = eol if top_level else i + 6
			continue
		i += 1
	if chosen.is_empty():
		return { "setup_end": end, "markup_start": end, "markup_end": end }
	return chosen

func _read_word(i: int) -> String:
	var j := i
	while j < _src.length() and _is_name_start(_src[j]):
		j += 1
	return _src.substr(i, j - i)

# The declared name following the (possibly misspelled) keyword at `at`, or "" when absent.
func _read_decl_name(at: int) -> String:
	var n := _src.length()
	var i := at
	while i < n and _is_name(_src[i]):
		i += 1
	while i < n and (_src[i] == " " or _src[i] == "\t"):
		i += 1
	var s := i
	while i < n and _is_name(_src[i]):
		i += 1
	return _src.substr(s, i - s)

# The declaration's ` -> Hint` suffix (mirrors guitkx.gd _ret_suffix): empty when there is no
# hint, and a tuple-style `-> (a, b)` is dropped (GDScript has no tuple type).
func _ret_suffix(decl_at: int) -> String:
	var n := _src.length()
	var j := decl_at
	while j < n and _src[j] != "{" and _src[j] != "\n":
		if _src[j] == "(":
			var pc := L.find_matching(_src, j)
			if pc == -1:
				return ""
			j = pc + 1
			continue
		if _src[j] == "-" and j + 1 < n and _src[j + 1] == ">":
			var e := j + 2
			while e < n and _src[e] != "{":
				e += 1
			var hint := _src.substr(j + 2, e - j - 2).strip_edges()
			if hint == "" or hint.begins_with("("):
				return ""
			return " -> %s" % hint
		j += 1
	return ""

# The `(...)` parameter list between the declaration name and the body `{`, with its source
# offset. Stops at a `->` return hint (params always precede it).
func _read_params_span(decl_at: int) -> Dictionary:
	var n := _src.length()
	var j := decl_at
	while j < n and _src[j] != "(" and _src[j] != "{":
		if _src[j] == "-" and j + 1 < n and _src[j + 1] == ">":
			return {}
		var k := L.skip_noncode(_src, j)
		if k != j:
			j = k
			continue
		j += 1
	if j >= n or _src[j] != "(":
		return {}
	var pc := L.find_matching(_src, j)
	if pc == -1:
		return {}
	return { "text": _src.substr(j + 1, pc - j - 1), "start": j + 1 }

func _read_params(decl_at: int) -> String:
	var span := _read_params_span(decl_at)
	return str(span.get("text", ""))

# Parameter names from a params string — split on top-level commas, take the identifier before
# any `:` type-hint or `=` default. NONCODE-AWARE (strings/comments/bracket groups skipped).
static func _param_names(params: String) -> Array[String]:
	var out: Array[String] = []
	if params.strip_edges() == "":
		return out
	var n := params.length()
	var start := 0
	var i := 0
	while i < n:
		var k := L.skip_noncode(params, i)
		if k != i:
			i = k
			continue
		var ch := params[i]
		if ch == "(" or ch == "[" or ch == "{":
			var m := L.find_matching(params, i)
			i = (i + 1) if m == -1 else m + 1
			continue
		if ch == ",":
			_push_param_name(out, params.substr(start, i - start))
			start = i + 1
		i += 1
	_push_param_name(out, params.substr(start))
	return out

static func _push_param_name(out: Array[String], chunk: String) -> void:
	var end_name := chunk.length()
	var j := 0
	while j < chunk.length():
		var k := L.skip_noncode(chunk, j)
		if k != j:
			j = k
			continue
		var cc := chunk[j]
		if cc == "(" or cc == "[" or cc == "{":
			var m := L.find_matching(chunk, j)
			j = chunk.length() if m == -1 else m + 1
			continue
		if cc == "=" or cc == ":":
			end_name = j
			break
		j += 1
	var name := chunk.substr(0, end_name).strip_edges()
	if name != "" and name.is_valid_identifier():
		out.append(name)

## --- small char helpers ------------------------------------------------------------------------

static func _lstrip(s: String) -> String:
	return s.strip_edges(true, false)

static func _is_ws(c: String) -> bool:
	return c == " " or c == "\t" or c == "\n" or c == "\r"

static func _is_name_start(c: String) -> bool:
	var u := c.unicode_at(0)
	return (u >= 65 and u <= 90) or (u >= 97 and u <= 122) or u == 95

static func _is_name(c: String) -> bool:
	var u := c.unicode_at(0)
	return (u >= 65 and u <= 90) or (u >= 97 and u <= 122) or (u >= 48 and u <= 57) or u == 95
