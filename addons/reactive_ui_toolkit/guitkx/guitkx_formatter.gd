class_name RuitkGuitkxFormatter
extends RefCounted
## Canonical-form formatter for .guitkx (Phase 5). Pure + FileAccess-free so it is headlessly
## unit-testable. AST-driven re-emit (NOT regex post-processing): re-parse via the single parser of
## record (guitkx_markup.gd), then re-emit. On ANY parse error -> return the source VERBATIM (never
## corrupt). Embedded GDScript (setup / control-flow bodies are markup; {expr} text) is left
## byte-identical except base-indent normalization of setup — a from-scratch GDScript re-indenter is
## unsound (no closing token), so we only re-anchor the outer indent and preserve internal structure.
##
## API:  RuitkGuitkxFormatter.format(source: String, opts := {}) -> { ok, text, changed, fell_back }
## `fell_back` (G-06): true when `text == source` because of a parse error, not because the file
## was already canonical -- the two used to be indistinguishable to callers.

const L = preload("res://addons/reactive_ui_toolkit/guitkx/guitkx_lexer.gd")
const Markup = preload("res://addons/reactive_ui_toolkit/guitkx/guitkx_markup.gd")
const Compiler = preload("res://addons/reactive_ui_toolkit/guitkx/guitkx.gd")

const DEFAULTS := {
	"printWidth": 100,
	"indentStyle": "space",      # "tab" | "space" -- Phase D: Unity-exact default ("tab is 2 spaces")
	"indentSize": 2,             # spaces per level when indentStyle == "space"
	"singleAttributePerLine": false,
	"insertSpaceBeforeSelfClose": true,
}

## [G-06 fix] `fell_back` distinguishes "formatted" from "parse error, source returned byte-
## identical" -- both used to look the same (`ok:true`, `text == source` happens either way for an
## already-canonical file), so a caller had no way to tell "nothing changed" from "couldn't even
## try" and warn the user their file has a syntax error. Mirrors formatGuitkx.ts's `fellBack`.
static func format(source: String, opts := {}) -> Dictionary:
	var o := DEFAULTS.duplicate()
	for k in opts:
		o[k] = opts[k]
	var r := _format_or_verbatim(source, o)
	var text: String = r["text"]
	return { "ok": true, "text": text, "changed": text != source, "fell_back": bool(r["fell_back"]) }

static func _format_or_verbatim(source: String, o: Dictionary) -> Dictionary:
	# 1. preamble: an optional `@class_name X` line (the only Godot preamble directive)
	var n := source.length()
	var i := 0
	var class_name_line := ""
	while i < n:
		i = _skip_ws_nl(source, i)
		# T3.5: directive keywords require a token boundary (mirrors compile()).
		if source.substr(i, 11) == "@class_name" and (i + 11 >= n or not L._is_ident(source[i + 11])):
			var le := source.find("\n", i)
			if le == -1: le = n
			class_name_line = source.substr(i, le - i).strip_edges()
			i = le
			continue
		break
	# 2. declaration
	var decl: Dictionary = Compiler._find_decl(source, i)
	if decl["kind"] == "":
		return { "text": source, "fell_back": false }   # nothing to format -- not a syntax error
	var diags: Array = []
	# T1.3: the preamble (everything before the declaration keyword) is canonicalized ONLY when it is
	# nothing but whitespace + the @class_name line. Leading comments or stray text are preserved
	# byte-for-byte -- Format Document must never delete user content (it used to eat file-header
	# comments whole). Mirrors formatGuitkx.ts.
	# 0.10.0 imports leg: `import { ... } from "..."` lines and an `export` decl prefix are NEVER
	# canonical here (they leave real text in `pre_check` below), so they always take the verbatim
	# branch -- imports are preserved byte-for-byte, never reordered or dropped, and the round-trip
	# stays idempotent. (`decl["at"]` is the KEYWORD, so an `export` prefix rides along inside `pre`.)
	# Plain (E-01) rows anchor at the NAME (`at`), with any `export ` prefix BEFORE it -- slice the
	# preamble at `start` for those and re-emit the prefix ourselves; wrapper rows keep the shipped
	# `at`-based slice (the prefix rides inside `pre`), preserving their byte-stable formatting.
	var is_plain: bool = not bool(decl.get("deprecated", true))
	var pre_end: int = int(decl.get("start", decl["at"])) if is_plain else int(decl["at"])
	var pre := source.substr(0, pre_end)
	var pre_check := pre
	var cn_at := pre_check.find("@class_name")
	if cn_at != -1:
		var cn_le := pre_check.find("\n", cn_at)
		if cn_le == -1:
			cn_le = pre_check.length()
		pre_check = pre_check.substr(0, cn_at) + pre_check.substr(cn_le)
	var pre_canonical := pre_check.strip_edges() == ""
	var out := ""
	if not pre_canonical:
		out += pre
	elif class_name_line != "":
		out += class_name_line + "\n\n"
	var decl_end := -1
	var exp_prefix: String = "export " if (is_plain and bool(decl.get("export", false))) else ""
	match decl["kind"]:
		"component":
			if is_plain:
				var ppc: Dictionary = Compiler._parse_plain_component_body(source, str(decl["name"]), int(decl["name_at"]), str(decl.get("params", "")), int(decl.get("params_at", -1)), int(decl["body_open"]), diags)
				if not ppc.get("ok", false):
					return { "text": source, "fell_back": true }
				out += exp_prefix + _fmt_plain_component(ppc["name"], ppc["params"], ppc["setup"], ppc["window_nodes"], o)
				decl_end = int(ppc["next"])
			else:
				var pc: Dictionary = Compiler._parse_component_at(source, decl["at"], diags)
				if not pc["ok"]:
					return { "text": source, "fell_back": true }
				out += _fmt_component(pc["name"], pc["params"], pc["setup"], pc["window_nodes"], o)
				decl_end = int(pc["next"])
		"hook", "util":
			if is_plain:
				var gb: Dictionary = Compiler._parse_plain_gd_body(source, int(decl["body_open"]), diags)
				if not gb.get("ok", false):
					return { "text": source, "fell_back": true }
				out += exp_prefix + _fmt_plain_callable(str(decl["name"]), str(decl.get("params", "")), str(gb["body"]), o, str(decl.get("ret", "")))
				decl_end = int(gb["next"])
			else:
				var ph: Dictionary = Compiler._parse_hook_at(source, decl["at"], diags)
				if not ph["ok"]:
					return { "text": source, "fell_back": true }
				out += _fmt_hook(ph["name"], ph["params"], ph["body"], o, str(ph.get("ret", "")))
				decl_end = int(ph["next"])
		"value":
			# E-01 value decl: canonical `[export ]name<eq> <initializer>`; the initializer slice
			# stays VERBATIM (it is arbitrary GDScript -- a from-scratch re-emit is unsound).
			var vend := Compiler._value_end(source, int(decl["value_start"]))
			if vend == -1:
				return { "text": source, "fell_back": true }
			var vexpr := source.substr(int(decl["value_start"]), vend - int(decl["value_start"])).strip_edges()
			match str(decl.get("eq_style", "plain")):
				"infer":
					out += "%s%s := %s\n" % [exp_prefix, str(decl["name"]), vexpr]
				"typed":
					out += "%s%s: %s = %s\n" % [exp_prefix, str(decl["name"]), str(decl.get("type_text", "")), vexpr]
				_:
					out += "%s%s = %s\n" % [exp_prefix, str(decl["name"]), vexpr]
			decl_end = vend
		"export_list":
			# E-09: canonical one-line list.
			var lns: Array = []
			for le3 in (decl.get("list_names", []) as Array):
				lns.append(str(le3["name"]))
			out += "export { %s }\n" % ", ".join(lns)
			decl_end = int(decl["list_end"])
		"export_default":
			out += "export default %s\n" % str(decl["name"])
			decl_end = int(decl["list_end"])
		"module":
			var m: Variant = _fmt_module(source, decl["at"], o, diags)
			if m == null:
				return { "text": source, "fell_back": true }
			out += (m as Dictionary)["text"]
			decl_end = int((m as Dictionary)["next"])
		_:
			return { "text": source, "fell_back": false }   # nothing to format -- not a syntax error
	# G-05: `_fmt_attr` flagged a `str` attribute value it cannot safely re-escape -- fall back to
	# verbatim rather than risk emitting a corrupted `name="value"`.
	if bool(o.get("_unsafe_str_attr", false)):
		return { "text": source, "fell_back": true }
	# T1.3: content after the declaration (a second component, stray text) is a GUITKX2105 compile
	# error, but it must round-trip the formatter untouched -- emitted verbatim after exactly one
	# canonical blank line (idempotent). Mirrors formatGuitkx.ts.
	if decl_end >= 0 and decl_end < source.length():
		var trailing := source.substr(decl_end)
		if trailing.strip_edges() != "":
			out = out.rstrip(" \t\n") + "\n\n" + trailing.lstrip(" \t\n")
	# normalize trailing whitespace -> exactly one newline
	out = out.rstrip(" \t\n") + "\n"
	return { "text": out, "fell_back": false }

# --- declarations ---

static func _fmt_component(comp_name: String, params: String, setup: String, nodes: Array, o: Dictionary) -> String:
	var out := "component %s%s {\n" % [comp_name, _fmt_params(params)]
	var fs := _fmt_setup(setup, 1, o)
	if fs != "":
		if _has_leading_blank(setup): out += "\n"   # keep an authored blank line after `{`
		out += fs
		if _has_trailing_blank(setup): out += "\n"   # keep an authored blank line before `return (`
	if nodes.is_empty():
		# Null-only component: the whole body is plain GDScript (its own `return null` included) --
		# there is no markup window to re-emit.
		out += "}\n"
		return out
	out += _pad(1, o) + "return (\n"
	# T2.1: every window node in order -- the render root plus any sibling comments.
	for nd in nodes:
		if nd == null:
			continue
		out += _fmt_node(nd, 2, o)
	out += _pad(1, o) + ")\n"
	out += "}\n"
	return out

## E-01 plain component: identical body emission to _fmt_component with the keywordless header
## (`Name(params) -> RuitkVNode {`). The annotation IS the classification -- never dropped.
static func _fmt_plain_component(comp_name: String, params: String, setup: String, nodes: Array, o: Dictionary) -> String:
	var out := "%s%s -> RuitkVNode {\n" % [comp_name, _fmt_params_always(params)]
	var fs := _fmt_setup(setup, 1, o)
	if fs != "":
		if _has_leading_blank(setup): out += "\n"
		out += fs
		if _has_trailing_blank(setup): out += "\n"
	if nodes.is_empty():
		# Null-only component: the whole body is plain GDScript (its own `return null` included) --
		# there is no markup window to re-emit.
		out += "}\n"
		return out
	out += _pad(1, o) + "return (\n"
	for nd in nodes:
		if nd == null:
			continue
		out += _fmt_node(nd, 2, o)
	out += _pad(1, o) + ")\n"
	out += "}\n"
	return out

## E-01 plain hook/util: `name(params)[ -> T] {` + the body (same body handling as _fmt_hook).
static func _fmt_plain_callable(fn_name: String, params: String, body: String, o: Dictionary, ret_hint: String = "") -> String:
	var hint := "" if ret_hint.strip_edges() == "" else " -> %s" % ret_hint.strip_edges()
	var out := "%s%s%s {\n" % [fn_name, _fmt_params_always(params), hint]
	var fb := _fmt_setup(body, 1, o)
	if fb != "":
		if _has_leading_blank(body): out += "\n"
		out += fb
		if _has_trailing_blank(body): out += "\n"
	out += "}\n"
	return out

## A plain decl's `()` is part of its callable signature and always emitted -- a paramless plain
## decl formatted as bare `Name {` would be reclassified as something else on the next parse.
static func _fmt_params_always(params: String) -> String:
	return "(%s)" % params.strip_edges()

static func _fmt_hook(hook_name: String, params: String, body: String, o: Dictionary, ret_hint: String = "") -> String:
	# The `-> Type` return hint is part of the signature -- dropping it turned every `var x := use_x(...)`
	# caller into an inference error once the untyped generated func cascaded (Phase D reformat find).
	var hint := "" if ret_hint.strip_edges() == "" else " -> %s" % ret_hint.strip_edges()
	var out := "hook %s%s%s {\n" % [hook_name, _fmt_params(params), hint]
	var fb := _fmt_setup(body, 1, o)
	if fb != "":
		if _has_leading_blank(body): out += "\n"
		out += fb
		if _has_trailing_blank(body): out += "\n"
	out += "}\n"
	return out

static func _fmt_module(source: String, mi: int, o: Dictionary, diags: Array) -> Variant:
	var n := source.length()
	var j := mi + 6
	j = _skip_ws_only(source, j)
	var ns := j
	while j < n and L._is_ident(source[j]):
		j += 1
	var mod_name := source.substr(ns, j - ns)
	j = _skip_ws_only(source, j)
	if j >= n or source[j] != "{":
		return null
	var bclose := L.find_matching(source, j)
	if bclose == -1:
		return null
	var out := "module %s {\n" % mod_name
	var i := j + 1
	var first := true
	while i < bclose:
		var d: Dictionary = Compiler._find_decl(source, i)
		# T1.3: real content between members that isn't a declaration would be silently DROPPED by the
		# re-emit below (_find_decl skips it). The compiler now errors on it (GUITKX2105); the formatter
		# falls back to verbatim -- it must never delete user text. Mirrors formatGuitkx.ts.
		var scan_to: int = mini(int(d["at"]), bclose) if d["kind"] != "" else bclose
		if Compiler._first_real(source, i, scan_to) != -1:
			return null
		if d["kind"] == "" or d["at"] >= bclose:
			break
		if not first:
			out += "\n"
		first = false
		# `#`/`##` doc comments between members belong to the NEXT member. `_first_real` treats them
		# as non-content, so they hit neither the verbatim fallback nor the re-emit -- the Phase D
		# reformat sweep silently DELETED real module docs. Re-emit them above their member.
		out += _member_comments(source, i, int(d["at"]), o)
		if d["kind"] == "component":
			var c: Dictionary = Compiler._parse_component_at(source, d["at"], diags)
			if not c["ok"]:
				return null
			out += _indent_block(_fmt_component(c["name"], c["params"], c["setup"], c["window_nodes"], o), 1, o)
			i = c["next"]
		elif d["kind"] == "hook":
			var h: Dictionary = Compiler._parse_hook_at(source, d["at"], diags)
			if not h["ok"]:
				return null
			out += _indent_block(_fmt_hook(h["name"], h["params"], h["body"], o, str(h.get("ret", ""))), 1, o)
			i = h["next"]
		else:
			return null
	out += _member_comments(source, i, bclose, o)
	out += "}\n"
	return { "text": out, "next": bclose + 1 }

## The comment lines in [from, to) (a member's leading docs / the module's tail), re-anchored at
## module-member indent.
static func _member_comments(source: String, from: int, to: int, o: Dictionary) -> String:
	if to <= from:
		return ""
	var out := ""
	for l in source.substr(from, to - from).split("\n"):
		var t := (l as String).strip_edges()
		if t.begins_with("#"):
			out += _pad(1, o) + t + "\n"
	return out

# --- markup ---

static func _fmt_node(nd: Dictionary, indent: int, o: Dictionary) -> String:
	match nd["t"]:
		"el":
			return _fmt_element(nd, indent, o)
		"frag":
			var inner := _fmt_children(nd["children"], indent + 1, o)
			# T2.2: the named <Fragment> alias keeps the author's spelling + attrs (key/comments).
			if nd.has("named"):
				var head := "<%s" % nd["named"]
				for a in nd.get("attrs", []):
					head += " " + _fmt_attr(a, o)
				return "%s%s>\n%s%s</%s>\n" % [_pad(indent, o), head, inner, _pad(indent, o), nd["named"]]
			return "%s<>\n%s%s</>\n" % [_pad(indent, o), inner, _pad(indent, o)]
		"comment":
			# T2.1: comments are preserved verbatim (re-anchored to the current indent).
			return "%s%s\n" % [_pad(indent, o), (nd["raw"] as String).strip_edges()]
		"text":
			return "%s%s\n" % [_pad(indent, o), (nd["value"] as String).strip_edges()]
		"expr":
			return "%s{ %s }\n" % [_pad(indent, o), (nd["code"] as String).strip_edges()]
		"if":
			return _fmt_if(nd, indent, o)
		"for":
			return _fmt_loop(nd, indent, o, "for")
		"while":
			return _fmt_loop(nd, indent, o, "while")
		"match":
			return _fmt_match(nd, indent, o)
		_:
			return ""
	return ""

static func _fmt_element(nd: Dictionary, indent: int, o: Dictionary) -> String:
	var pad := _pad(indent, o)
	var tag: String = nd["tag"]
	var attr_strs: Array = []
	for a in nd["attrs"]:
		attr_strs.append(_fmt_attr(a, o))
	var children: Array = (nd["children"] as Array).filter(func(x): return x != null)
	var self_close := children.is_empty()
	var attr_inline := " ".join(attr_strs)
	# single-line candidate
	var head := "<%s" % tag
	if not attr_strs.is_empty():
		head += " " + attr_inline
	var single_close := (" />" if o["insertSpaceBeforeSelfClose"] else "/>") if self_close else ">"
	var single := head + single_close
	var wrap: bool = o["singleAttributePerLine"] and attr_strs.size() > 1
	if not wrap and pad.length() + single.length() > int(o["printWidth"]) and attr_strs.size() > 1:
		wrap = true
	var out := ""
	if not wrap:
		if self_close:
			return pad + single + "\n"
		out += pad + single + "\n"
	else:
		out += pad + "<%s\n" % tag
		var apad := _pad(indent + 1, o)
		for k in attr_strs.size():
			var last := k == attr_strs.size() - 1
			if last and self_close:
				out += apad + attr_strs[k] + (" />" if o["insertSpaceBeforeSelfClose"] else "/>") + "\n"
			elif last:
				out += apad + attr_strs[k] + "\n" + pad + ">\n"
			else:
				out += apad + attr_strs[k] + "\n"
		if self_close:
			return out
	# children + close tag
	out += _fmt_children(children, indent + 1, o)
	out += pad + "</%s>\n" % tag
	return out

static func _fmt_children(children: Array, indent: int, o: Dictionary) -> String:
	var out := ""
	for c in children:
		if c == null:
			continue
		out += _fmt_node(c, indent, o)
	return out

## [G-05 fix] `o` is a shared, by-reference Dictionary threaded through the whole re-emit call tree
## (component/hook/module -> node -> element -> attr) -- setting a key on it here is visible back
## in _format_or_verbatim once the tree walk returns, with no need to thread a return value through
## every intermediate _fmt_* signature. Used ONLY for this one escape hatch: the parser can't
## produce a `str`-kind attribute value containing an embedded `"` today (its string extraction
## stops at the first unescaped quote), so re-emitting `name="value"` unescaped is currently always
## safe -- but a future compiler change adding escape support without teaching this function to
## re-escape would silently corrupt the attribute's value on the next format. Catching it here (and
## falling back to verbatim, like a real parse error) is cheap insurance against that regressing
## silently instead of loudly.
static func _fmt_attr(a: Dictionary, o: Dictionary) -> String:
	match a["kind"]:
		"str":
			if (a["value"] as String).contains("\""):
				o["_unsafe_str_attr"] = true
			return "%s=\"%s\"" % [a["name"], a["value"]]
		"expr":
			return "%s={ %s }" % [a["name"], (a["value"] as String).strip_edges()]
		"spread":
			return "{...%s}" % (a["value"] as String).strip_edges()
		"bool":
			return a["name"]
		"comment":
			return str(a["value"])   # T2.1: `{/* ... */}` preserved verbatim
	return a["name"]

# --- control flow (bodies are raw markup strings; re-parse + format) ---

static func _fmt_if(nd: Dictionary, indent: int, o: Dictionary) -> String:
	var pad := _pad(indent, o)
	var out := ""
	var branches: Array = nd["branches"]
	for k in branches.size():
		var br: Dictionary = branches[k]
		var kw := "@if" if k == 0 else "@elif"
		if k == 0:
			out += "%s%s (%s) {\n" % [pad, kw, (br["cond"] as String).strip_edges()]
		else:
			out = out.rstrip("\n") + " %s (%s) {\n" % [kw, (br["cond"] as String).strip_edges()]
		out += _fmt_body(br["body_markup"], indent + 1, o)
		out += pad + "}\n"
	if nd["else_body"] != null:
		out = out.rstrip("\n") + " @else {\n"
		out += _fmt_body(nd["else_body"], indent + 1, o)
		out += pad + "}\n"
	return out

static func _fmt_loop(nd: Dictionary, indent: int, o: Dictionary, kw: String) -> String:
	var pad := _pad(indent, o)
	var out := "%s@%s (%s) {\n" % [pad, kw, (nd["header"] as String).strip_edges()]
	out += _fmt_body(nd["body_markup"], indent + 1, o)
	out += pad + "}\n"
	return out

static func _fmt_match(nd: Dictionary, indent: int, o: Dictionary) -> String:
	var pad := _pad(indent, o)
	var out := "%s@match (%s) {\n" % [pad, (nd["subject"] as String).strip_edges()]
	for c in nd.get("cases", []):
		out += "%s@case (%s) {\n" % [_pad(indent + 1, o), (c["value"] as String).strip_edges()]
		out += _fmt_body(c["body_markup"], indent + 2, o)
		out += _pad(indent + 1, o) + "}\n"
	if nd.get("default_body") != null:
		out += "%s@default {\n" % _pad(indent + 1, o)
		out += _fmt_body(nd["default_body"], indent + 2, o)
		out += _pad(indent + 1, o) + "}\n"
	out += pad + "}\n"
	return out

# Re-parse a raw control-flow body string and format its nodes; verbatim re-indent fallback on error.
## Phase D: a directive body is CODE (prep statements + directive-level returns). GDScript
## segments re-anchor with the WHOLE body's indent geometry (a segment after a return must not
## re-anchor on its own first line); each markup return re-emits as `return (` + recursively
## formatted markup + `)` at the return's own relative depth. Legacy/unsplittable bodies are
## re-anchored verbatim (never corrupt -- the compiler reports GUITKX2103, not the formatter).
static func _fmt_body(body_src: String, indent: int, o: Dictionary) -> String:
	var sp: Dictionary = Compiler._split_body(body_src)
	if sp.has("error") or int(sp["legacy_at"]) != -1:
		return _reanchor(body_src, indent, o)
	var unit: int = int(sp["unit"])
	var anchor: int = int(sp["anchor"])
	var out := ""
	for part in (sp["parts"] as Array):
		var pd := part as Dictionary
		if pd["t"] == "gd":
			var seg := body_src.substr(int(pd["from"]), int(pd["to"]) - int(pd["from"]))
			if seg.strip_edges() != "":
				out += _reanchor_rel(seg, indent, unit, anchor, o)
			continue
		var lvl: int = indent + maxi(0, int(pd["depth"]) - anchor)
		var pad := _pad(lvl, o)
		var shape := str(pd["shape"])
		if shape == "null":
			out += pad + "return null\n"
			continue
		if shape == "void":
			out += pad + "return\n"
			continue
		var payload := body_src.substr(int(pd["m_start"]), int(pd["m_end"]) - int(pd["m_start"]))
		if not bool(pd.get("markup", false)):
			if shape == "paren":
				out += pad + "return ( %s )\n" % _collapse_spaces(payload.strip_edges())
			else:
				out += pad + "return %s\n" % _collapse_spaces(payload.strip_edges())
			continue
		var parser := Markup.new()
		var pr := parser.parse(body_src, int(pd["m_start"]), int(pd["m_end"]))
		if pr["error"] != "":
			# broken markup in this return: keep the authored span (the compiler reports the error)
			out += pad + body_src.substr(int(pd["at"]), int(pd["end"]) - int(pd["at"])).strip_edges() + "\n"
			continue
		out += pad + "return (\n"
		for nx in (pr["nodes"] as Array).filter(func(x): return x != null):
			out += _fmt_node(nx, lvl + 1, o)
		out += pad + ")\n"
	return out

## [G-02/G-03 fix] Returns a boolean array (one per line of `code.split("\n")`) marking lines whose
## FIRST character sits inside an already-open multi-line string (`"""`/`'''`, optionally
## r/&/^/$/%-prefixed) that began on an EARLIER line -- re-indenting/collapsing such a line would
## corrupt the string's runtime VALUE. The line that OPENS the string (e.g. `var msg := """`) is NOT
## masked -- only its interior/closing lines are; `#` line comments never span a `\n` so they never
## mask anything. Must stay byte-identical with formatGuitkx.ts's stringLineMask.
static func _string_line_mask(code: String) -> Array:
	var n := code.length()
	var line_starts: Array = [0]
	for ci in n:
		if code[ci] == "\n":
			line_starts.append(ci + 1)
	var mask: Array = []
	mask.resize(line_starts.size())
	for k in mask.size():
		mask[k] = false
	var line_idx := 0
	var i := 0
	while i < n:
		while line_idx + 1 < line_starts.size() and int(line_starts[line_idx + 1]) <= i:
			line_idx += 1
		var j := L.skip_noncode(code, i)
		if j != i:
			var end_line := line_idx
			while end_line + 1 < line_starts.size() and int(line_starts[end_line + 1]) <= j:
				end_line += 1
			for m in range(line_idx + 1, end_line + 1):
				mask[m] = true
			i = j
			continue
		i += 1
	return mask

## Re-anchor a body SEGMENT using the whole body's unit/anchor (not its own first line). Leading and
## trailing blank LINES are structural artifacts of how the caller sliced this segment (e.g. the
## line right after a directive's own `{`) and are trimmed, exactly like _reanchor; an INTERIOR
## blank line is real formatting and is preserved (G-03) -- the two must not disagree on this.
static func _reanchor_rel(code: String, indent: int, unit: int, anchor: int, o: Dictionary) -> String:
	var lines: Array = Array(code.split("\n"))
	while not lines.is_empty() and (lines[0] as String).strip_edges() == "":
		lines.pop_front()
	while not lines.is_empty() and (lines[-1] as String).strip_edges() == "":
		lines.pop_back()
	if lines.is_empty():
		return ""
	var mask := _string_line_mask("\n".join(PackedStringArray(lines)))
	var out := ""
	for i in lines.size():
		var l := lines[i] as String
		if bool(mask[i]):
			# G-02: byte-verbatim -- this line sits inside an open multi-line string.
			out += l + "\n"
			continue
		var t := l.strip_edges()
		if t == "":
			# G-03: an interior blank line is real formatting, not nothing.
			out += "\n"
			continue
		var level: int = indent + maxi(0, Compiler._indent_depth(l, unit) - anchor)
		out += _pad(level, o) + _collapse_spaces(Compiler._strip_leading_ws(l)) + "\n"
	return out

# --- embedded GDScript (setup) — structure-preserving base-indent normalization only ---

static func _fmt_setup(setup: String, indent: int, o: Dictionary) -> String:
	var s := setup.strip_edges()
	if s == "":
		return ""
	return _reanchor(setup, indent, o)

# Re-indent an embedded-GDScript block to clean, DEPTH-based indentation anchored at `indent`.
# Depth-based, NOT character-preserving: a tab counts as one unit and the space-unit is inferred (reusing
# the compiler's _indent_unit/_indent_depth for exact parity), so a body indented with mixed tabs+spaces
# -- e.g. a lambda body written `\t    ` (tab + 4 spaces, which RENDERS like two tabs but is byte-
# different) -- is normalized to real tabs instead of emitted verbatim as `\t    ` (the "Format leaves
# 4 spaces in nested code" bug). Mirrors the compiler's _reindent_setup + formatGuitkx.ts reanchor.
static func _reanchor(code: String, indent: int, o: Dictionary) -> String:
	var lines: Array = Array(code.split("\n"))
	while not lines.is_empty() and (lines[0] as String).strip_edges() == "":
		lines.pop_front()
	while not lines.is_empty() and (lines[-1] as String).strip_edges() == "":
		lines.pop_back()
	if lines.is_empty():
		return ""
	# G-02: mask lines that sit inside an open multi-line string -- excluded from both the
	# unit/anchor inference below and the collapse/re-indent at emit time.
	var mask := _string_line_mask("\n".join(PackedStringArray(lines)))
	var unit_lines: Array = []
	for idx in lines.size():
		if not bool(mask[idx]):
			unit_lines.append(lines[idx])
	var unit := Compiler._indent_unit(unit_lines)
	var anchor := -1
	var anchor_any := -1
	var depths: Array = []
	for idx in lines.size():
		if bool(mask[idx]):
			depths.append(-1)
			continue
		var l := lines[idx] as String
		var t := l.strip_edges()
		if t == "":
			depths.append(-1)
			continue
		var d := Compiler._indent_depth(l, unit)
		depths.append(d)
		if anchor_any == -1:
			anchor_any = d
		if anchor == -1 and not t.begins_with("#"):
			anchor = d
	if anchor == -1:
		anchor = anchor_any  # comment-only block
	var out := ""
	for i in lines.size():
		if bool(mask[i]):
			out += (lines[i] as String) + "\n"
		elif int(depths[i]) == -1:
			out += "\n"
		else:
			var level: int = indent + maxi(0, int(depths[i]) - anchor)
			out += _pad(level, o) + _collapse_spaces(Compiler._strip_leading_ws(lines[i] as String)) + "\n"
	return out

# --- helpers ---

static func _fmt_params(params: String) -> String:
	var p := params.strip_edges()
	return "" if p == "" else "(%s)" % p

static func _indent_block(block: String, indent: int, o: Dictionary) -> String:
	var pad := _pad(indent, o)
	var out := ""
	for l in block.split("\n"):
		out += ("" if (l as String) == "" else pad + l) + "\n"
	return out.rstrip("\n") + "\n"

static func _pad(indent: int, o: Dictionary) -> String:
	if o["indentStyle"] == "space":
		return " ".repeat(indent * int(o["indentSize"]))
	return "\t".repeat(indent)

# An authored blank line at the start / end of an embedded block (mirrors formatGuitkx.ts). [audit #1]
static func _has_leading_blank(s: String) -> bool:
	var i := 0
	var n := s.length()
	while i < n and (s[i] == " " or s[i] == "\t"):
		i += 1
	if i >= n or s[i] != "\n":
		return false
	i += 1
	while i < n and (s[i] == " " or s[i] == "\t"):
		i += 1
	return i < n and s[i] == "\n"

static func _has_trailing_blank(s: String) -> bool:
	var i := s.length() - 1
	while i >= 0 and (s[i] == " " or s[i] == "\t"):
		i -= 1
	if i < 0 or s[i] != "\n":
		return false
	i -= 1
	while i >= 0 and (s[i] == " " or s[i] == "\t"):
		i -= 1
	return i >= 0 and s[i] == "\n"

# Collapse runs of 2+ spaces to one outside strings/comments (mirrors formatGuitkx.ts collapseSpaces;
# skip_noncode is the SAME primitive cross-tested via scanner-cases.json). [audit #6]
static func _collapse_spaces(s: String) -> String:
	var out := ""
	var i := 0
	var n := s.length()
	while i < n:
		var j := L.skip_noncode(s, i)
		if j != i:
			out += s.substr(i, j - i)
			i = j
			continue
		if s[i] == " " and i + 1 < n and s[i + 1] == " ":
			out += " "
			while i < n and s[i] == " ":
				i += 1
			continue
		out += s[i]
		i += 1
	return out

static func _skip_ws_only(s: String, i: int) -> int:
	var n := s.length()
	while i < n and (s[i] == " " or s[i] == "\t" or s[i] == "\n" or s[i] == "\r"):
		i += 1
	return i

static func _skip_ws_nl(s: String, i: int) -> int:
	while true:
		i = _skip_ws_only(s, i)
		var k := L.skip_noncode(s, i)
		if k == i:
			return i
		i = k
	return i
