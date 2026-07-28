class_name RUIGuitkxMarkup
extends RefCounted
## Recursive-descent parser: a markup string (the inside of a `return ( ... )`) -> an AST of
## plain Dictionaries. Port of uitkx's UitkxParser (markup half). Control-flow directives
## (@if/@for/@while/@match) are recognized here and carried as raw body strings for the emitter.
##
## POSITIONS (T0.2): every node carries `at` -- the character offset of its first character in the
## `src` string given to parse(). Extracted-substring fields carry a companion offset into the SAME
## `src`: attr `vat` (value text start; -1 for bool), expr `vat` (code start), control-flow
## `body_at`/`else_body_at`/`default_body_at` (body text start; -1 when absent), attr `end` (one past
## the attribute's last character). Offsets compose: a consumer re-parsing a `body_markup` substring
## rebases the nested offsets by adding the node's `body_at`. Parse errors carry `error_at` the same
## way. This file and the LSP's markup.ts are line-for-line mirrors -- change BOTH or neither.
##
## Node shapes (the "t" tag discriminates):
##   { t="el",   at, tag, attrs:[{name,kind,value,at,vat,end}], children:[], line }   kind: "str"|"expr"|"bool"|"spread"|"comment"
##   { t="frag", at, children:[] }            (+ named, attrs when spelled <Fragment ...> -- T2.2)
##   { t="text", at, value }
##   { t="expr", at, vat, code }
##   { t="comment", at, raw }                 (T2.1: `//`, `/* */`, `<!-- -->` -- emit nothing, formatter preserves)
##   { t="if",   at, branches:[{cond, body_markup, body_at}], else_body, else_body_at }
##   { t="for",  at, header, body_markup, body_at }
##   { t="while",at, header, body_markup, body_at }
##   { t="match",at, subject, cases:[{value, body_markup, body_at}], default_body, default_body_at }
##
## TEXT MODEL (T2.4, Unity parity): a text run stops only at `<` or `@`. `{expr}` interpolation is
## recognized at NODE START only; braces inside an ongoing text run are LITERAL characters (the
## compiler warns GUITKX0150 so migrating authors notice). Comments are recognized at node start
## (`//`, `/*`, `<!--`) and inside attribute lists as `{/* ... */}` only.

const L = preload("res://addons/reactive_ui_toolkit/guitkx/guitkx_lexer.gd")

var _src: String
var _err: String = ""
var _err_code: String = ""
var _err_msg: String = ""
var _err_at: int = -1
# [G-08] Line-start offsets of _src (entry k = index where line k begins; entry 0 = 0), built
# once per parse() so _line_of is a binary search instead of an O(n) prefix copy per element.
var _line_starts: PackedInt32Array = PackedInt32Array()

## Parse the top-level nodes of a markup window [start, end).
## Returns { nodes:[...], error:"", error_code:"", error_msg:"", error_at:-1 } -- `error` is the
## legacy "CODE: message" string ("" when clean); code/msg/at are its structured split.
func parse(src: String, start: int, end: int) -> Dictionary:
	_src = src
	_err = ""
	_err_code = ""
	_err_msg = ""
	_err_at = -1
	_line_starts = PackedInt32Array()
	_line_starts.append(0)
	var nl := src.find("\n", 0)
	while nl != -1:
		_line_starts.append(nl + 1)
		nl = src.find("\n", nl + 1)
	var r := _parse_nodes(start, end)
	return { "nodes": r["nodes"], "error": _err, "error_code": _err_code, "error_msg": _err_msg, "error_at": _err_at }

func _fail(code: String, msg: String, at: int) -> void:
	_err_code = code
	_err_msg = msg
	_err = "%s: %s" % [code, msg]
	_err_at = at

## Parse sibling nodes in [start, end). Returns { nodes, next } where `next` is the index at which
## parsing stopped — sitting on an unconsumed `</` (the close tag belongs to the caller) or at `end`.
## The caller uses `next` to locate the close tag WITHOUT a second weaker walk (which could be fooled
## by a `<`/`>` inside an embedded {expr}).
func _parse_nodes(start: int, end: int) -> Dictionary:
	var nodes: Array = []
	var i := start
	while i < end and _err == "":
		i = _skip_ws(i, end)
		if i >= end:
			break
		var c := _src.unicode_at(i)
		if c == L.C_LT:
			# T2.1: `<!-- ... -->` comment (checked before `</` -- both start with `<`).
			if i + 3 < end and _src.unicode_at(i + 1) == L.C_BANG and _src.unicode_at(i + 2) == L.C_DASH and _src.unicode_at(i + 3) == L.C_DASH:
				var hce := _src.find("-->", i + 4)
				if hce == -1 or hce + 3 > end:
					_fail("GUITKX0304", "unclosed `<!--` comment", i)
					break
				nodes.append({ "t": "comment", "at": i, "raw": _src.substr(i, hce + 3 - i) })
				i = hce + 3
				continue
			if i + 1 < end and _src.unicode_at(i + 1) == L.C_SLASH:
				break   # a closing tag belongs to the caller
			var r := _parse_element(i, end)
			if _err != "":
				break
			nodes.append(r["node"])
			i = r["next"]
		elif c == L.C_SLASH and i + 1 < end and (_src.unicode_at(i + 1) == L.C_SLASH or _src.unicode_at(i + 1) == L.C_STAR):
			# T2.1: `// line` / `/* block */` comments at node-start position only -- a `//` inside an
			# ongoing text run (e.g. a URL) stays text because _parse_text never stops at `/`.
			if _src.unicode_at(i + 1) == L.C_SLASH:
				var le := _src.find("\n", i)
				var stop: int = end if (le == -1 or le > end) else le
				nodes.append({ "t": "comment", "at": i, "raw": _src.substr(i, stop - i) })
				i = stop
			else:
				var bce := _src.find("*/", i + 2)
				if bce == -1 or bce + 2 > end:
					_fail("GUITKX0304", "unclosed `/*` comment", i)
					break
				nodes.append({ "t": "comment", "at": i, "raw": _src.substr(i, bce + 2 - i) })
				i = bce + 2
		elif c == L.C_AT:
			var r := _parse_directive(i, end)
			if _err != "":
				break
			nodes.append(r["node"])
			i = r["next"]
		elif c == L.C_LBRACE:
			var close := L.find_matching(_src, i)
			if close == -1 or close >= end:
				_fail("GUITKX0304", "unclosed `{` expression", i)
				break
			var code := _src.substr(i + 1, close - i - 1).strip_edges()
			nodes.append({ "t": "expr", "at": i, "vat": _skip_ws(i + 1, close), "code": code })
			i = close + 1
		else:
			var r := _parse_text(i, end)
			if r["node"] != null:
				nodes.append(r["node"])
			i = r["next"]
	return { "nodes": nodes, "next": i }

func _parse_element(open_i: int, end: int) -> Dictionary:
	# open_i points at "<"
	var i := open_i + 1
	var line := _line_of(open_i)
	# tag name (empty -> fragment)
	var name_start := i
	while i < end and _is_tag_char_code(_src.unicode_at(i)):
		i += 1
	var tag := _src.substr(name_start, i - name_start)
	# A `<` must be directly followed by a tag name, or `>` for a fragment. Whitespace/other after `<`
	# is an invalid/empty tag name (not a silent fragment). [BUG-V4]
	if tag == "" and (i >= end or _src.unicode_at(i) != L.C_GT):
		_fail("GUITKX0300", "invalid tag name -- `<` must be followed by a tag name, or `<>` for a fragment", open_i)
		return { "node": null, "next": end }
	# T3.5: a tag cannot start with a digit (`<9foo/>` used to parse and emit a nonsense call).
	if tag != "" and tag.unicode_at(0) >= 48 and tag.unicode_at(0) <= 57:
		_fail("GUITKX0300", "tag name cannot start with a digit (<%s>)" % tag, open_i)
		return { "node": null, "next": end }
	# attributes up to ">" or "/>"
	var attrs: Array = []
	while i < end:
		i = _skip_ws(i, end)
		if i >= end:
			_fail("GUITKX0303", "unexpected EOF in <%s>" % tag, open_i)
			return { "node": null, "next": end }
		var c := _src.unicode_at(i)
		if c == L.C_SLASH and i + 1 < end and _src.unicode_at(i + 1) == L.C_GT:
			# self-closing
			var nd := _mk_el(tag, attrs, [], line, open_i)
			return { "node": nd, "next": i + 2 }
		if c == L.C_GT:
			i += 1
			break
		var ar := _parse_attribute(i, end)
		if _err != "":
			return { "node": null, "next": end }
		attrs.append(ar["attr"])
		i = ar["next"]
	# paired: parse children; _parse_nodes consumes every {expr}/nested element through find_matching
	# and stops exactly on the matching "</" (or end), telling us where — no second walk to be fooled.
	var cr := _parse_nodes(i, end)
	if _err != "":
		return { "node": null, "next": end }
	var children: Array = cr["nodes"]
	var j: int = cr["next"]
	# G-04: `j + 1 >= end` must fail on its own -- the old `(j + 1 < end and _src[j + 1] != "/")`
	# short-circuited to false when `<` was the very last character before `end` (no room for a
	# slash), so a truncated `<Box><` at EOF fell through as if `j` pointed at a real "</" and the
	# unbounded `_src.find(">", j)` below could match a `>` from past `end` entirely.
	if j >= end or _src.unicode_at(j) != L.C_LT or j + 1 >= end or _src.unicode_at(j + 1) != L.C_SLASH:
		_fail("GUITKX0301", "unclosed tag <%s>" % tag, open_i)
		return { "node": null, "next": end }
	# j points at "</": read the close name to ">" (a close tag holds no {expr}/strings, so find is safe)
	var ce := _src.find(">", j)
	if ce == -1 or ce >= end:
		_fail("GUITKX0303", "malformed closing tag for <%s>" % tag, j)
		return { "node": null, "next": end }
	var close_name := _src.substr(j + 2, ce - (j + 2)).strip_edges()
	if close_name != tag:
		_fail("GUITKX0302", "mismatched tag </%s> (expected </%s>)" % [close_name, tag], j)
		return { "node": null, "next": end }
	return { "node": _mk_el(tag, attrs, children, line, open_i), "next": ce + 1 }

func _mk_el(tag: String, attrs: Array, children: Array, line: int, at: int) -> Dictionary:
	if tag == "":
		return { "t": "frag", "at": at, "children": children }
	# T2.2 (Unity parity): <Fragment> is a named alias of <>, resolved case-insensitively at the
	# resolver level in Unity (PropsResolver). The author's spelling + attrs are kept so the
	# formatter round-trips and the emitter can honor `key` (V.fragment's second arg).
	if tag.to_lower() == "fragment":
		return { "t": "frag", "at": at, "children": children, "named": tag, "attrs": attrs }
	return { "t": "el", "at": at, "tag": tag, "attrs": attrs, "children": children, "line": line }

func _parse_attribute(start: int, end: int) -> Dictionary:
	var i := start
	# spread attribute `{...expr}` (React `{...obj}`): merged into props at codegen. kind "spread".
	if _src.unicode_at(i) == L.C_LBRACE:
		# T2.1: `{/* comment */}` inside an attribute list (Unity parity). Scanned for `*/` directly
		# (not find_matching -- comment text may hold unbalanced braces), then the closing `}`.
		var probe := _skip_ws(i + 1, end)
		if probe + 1 < end and _src.unicode_at(probe) == L.C_SLASH and _src.unicode_at(probe + 1) == L.C_STAR:
			var ce2 := _src.find("*/", probe + 2)
			if ce2 == -1 or ce2 + 2 > end:
				_fail("GUITKX0304", "unclosed comment in attribute list", i)
				return { "attr": null, "next": end }
			var after := _skip_ws(ce2 + 2, end)
			if after >= end or _src.unicode_at(after) != L.C_RBRACE:
				_fail("GUITKX0303", "attribute comment must close with `*/}`", i)
				return { "attr": null, "next": end }
			return { "attr": { "name": "", "kind": "comment", "value": _src.substr(i, after + 1 - i), "at": i, "vat": -1, "end": after + 1 }, "next": after + 1 }
		var sclose := L.find_matching(_src, i)
		if sclose == -1 or sclose >= end:
			_fail("GUITKX0304", "unclosed `{` in spread attribute", i)
			return { "attr": null, "next": end }
		var inner := _src.substr(i + 1, sclose - i - 1).strip_edges()
		if not inner.begins_with("..."):
			_fail("GUITKX0300", "expected `...spread` or an attribute name", i)
			return { "attr": null, "next": end }
		var svat := _skip_ws(_skip_ws(i + 1, sclose) + 3, sclose)   # first char of the expr after `...`
		return { "attr": { "name": "", "kind": "spread", "value": inner.substr(3).strip_edges(), "at": i, "vat": svat, "end": sclose + 1 }, "next": sclose + 1 }
	var ns := i
	while i < end and _is_attr_name_char_code(_src.unicode_at(i)):
		i += 1
	var name := _src.substr(ns, i - ns)
	var name_end := i
	if name == "":
		_fail("GUITKX0300", "unexpected token in attributes", i)
		return { "attr": null, "next": end }
	# T3.5: `<Foo.Bar/>` used to silently parse as tag Foo + boolean attr `.Bar`.
	if name.begins_with(".") or name.begins_with("-"):
		_fail("GUITKX0300", "unexpected `%s` in attributes -- dotted/namespaced tags are not supported" % name[0], ns)
		return { "attr": null, "next": end }
	i = _skip_ws(i, end)
	if i >= end or _src.unicode_at(i) != L.C_EQ:
		# boolean shorthand
		return { "attr": { "name": name, "kind": "bool", "value": "true", "at": ns, "vat": -1, "end": name_end }, "next": i }
	i += 1   # past "="
	i = _skip_ws(i, end)
	if i >= end:
		_fail("GUITKX0303", "missing attribute value for '%s'" % name, ns)
		return { "attr": null, "next": end }
	var c := _src.unicode_at(i)
	if c == L.C_QUOTE or c == L.C_APOS:
		var se := L._skip_string(_src, i)
		# T3.5: an unterminated string used to truncate silently at the newline.
		if se <= i + 1 or se > end or _src.unicode_at(se - 1) != c:
			_fail("GUITKX0300", "unterminated string in attribute '%s'" % name, i)
			return { "attr": null, "next": end }
		var val := _src.substr(i + 1, se - i - 2)
		return { "attr": { "name": name, "kind": "str", "value": val, "at": ns, "vat": i + 1, "end": se }, "next": se }
	if c == L.C_LBRACE:
		var close := L.find_matching(_src, i)
		if close == -1 or close >= end:
			_fail("GUITKX0304", "unclosed `{` in attribute '%s'" % name, i)
			return { "attr": null, "next": end }
		var code := _src.substr(i + 1, close - i - 1).strip_edges()
		return { "attr": { "name": name, "kind": "expr", "value": code, "at": ns, "vat": _skip_ws(i + 1, close), "end": close + 1 }, "next": close + 1 }
	_fail("GUITKX0300", "attribute '%s' value must be a string or {expr}" % name, i)
	return { "attr": null, "next": end }

func _parse_text(start: int, end: int) -> Dictionary:
	# T2.4 (Unity MT parity): text stops only at `<` or `@`; braces inside a run are LITERAL text
	# ({expr} is a node-start construct -- see _parse_nodes). The compiler warns GUITKX0150 on
	# brace-bearing text so pre-T2.4 interpolation habits surface instead of silently rendering "{n}".
	var i := start
	while i < end:
		var tc := _src.unicode_at(i)
		if tc == L.C_LT or tc == L.C_AT:
			break
		i += 1
	var raw := _src.substr(start, i - start)
	if raw.strip_edges() == "":
		return { "node": null, "next": i }   # whitespace-only collapses to nothing
	return { "node": { "t": "text", "at": start, "value": raw.strip_edges() }, "next": i }

# --- control-flow directives (bodies kept as raw markup strings; emitter lowers them) ---
func _parse_directive(at: int, end: int) -> Dictionary:
	if L.keyword_at(_src, at + 1, "if"):
		return _parse_if(at, end)
	if L.keyword_at(_src, at + 1, "for"):
		return _parse_loop(at, end, "for", 4)
	if L.keyword_at(_src, at + 1, "while"):
		return _parse_loop(at, end, "while", 6)
	if L.keyword_at(_src, at + 1, "match"):
		return _parse_match(at, end)
	_fail("GUITKX0305", "unknown @directive", at)
	return { "node": null, "next": end }

func _read_paren(i: int, end: int) -> Dictionary:
	i = _skip_ws(i, end)
	if i >= end or _src.unicode_at(i) != L.C_LPAREN:
		_fail("GUITKX2506", "directive expects `(...)`", i)
		return { "text": "", "next": end }
	var close := L.find_matching(_src, i)
	if close == -1 or close >= end:
		_fail("GUITKX0304", "unclosed `(` in directive", i)
		return { "text": "", "next": end }
	return { "text": _src.substr(i + 1, close - i - 1).strip_edges(), "next": close + 1 }

func _read_brace_body(i: int, end: int) -> Dictionary:
	i = _skip_ws(i, end)
	if i >= end or _src.unicode_at(i) != L.C_LBRACE:
		_fail("GUITKX0303", "directive expects `{ ... }` body", i)
		return { "text": "", "next": end, "at": -1 }
	# G-01: a directive BODY is markup (child elements/text/nested directives), not a GDScript
	# statement -- find_matching_markup keeps `#` literal and `//`/`/* */`/`<!-- -->` as comments.
	var close := L.find_matching_markup(_src, i)
	if close == -1 or close >= end:
		_fail("GUITKX0304", "unclosed `{` directive body", i)
		return { "text": "", "next": end, "at": -1 }
	return { "text": _src.substr(i + 1, close - i - 1), "next": close + 1, "at": i + 1 }

func _parse_if(at: int, end: int) -> Dictionary:
	var branches: Array = []
	var else_body = null
	var else_body_at := -1
	var i := at + 3   # past "@if"
	var p := _read_paren(i, end)
	if _err != "": return { "node": null, "next": end }
	var b := _read_brace_body(p["next"], end)
	if _err != "": return { "node": null, "next": end }
	branches.append({ "cond": p["text"], "body_markup": b["text"], "body_at": b["at"] })
	i = b["next"]
	while true:
		var k := _skip_ws(i, end)
		# T3.5: the `@` itself must be verified -- a commented `#elif` used to become a real branch.
		if k >= end or _src.unicode_at(k) != L.C_AT:
			break
		if k + 5 <= end and L.keyword_at(_src, k + 1, "elif"):
			var pe := _read_paren(k + 5, end)
			if _err != "": return { "node": null, "next": end }
			var be := _read_brace_body(pe["next"], end)
			if _err != "": return { "node": null, "next": end }
			branches.append({ "cond": pe["text"], "body_markup": be["text"], "body_at": be["at"] })
			i = be["next"]
		elif k + 5 <= end and L.keyword_at(_src, k + 1, "else"):
			var bb := _read_brace_body(k + 5, end)
			if _err != "": return { "node": null, "next": end }
			else_body = bb["text"]
			else_body_at = bb["at"]
			i = bb["next"]
			break
		else:
			break
	return { "node": { "t": "if", "at": at, "branches": branches, "else_body": else_body, "else_body_at": else_body_at }, "next": i }

func _parse_loop(at: int, end: int, kind: String, kwlen: int) -> Dictionary:
	var p := _read_paren(at + kwlen, end)
	if _err != "": return { "node": null, "next": end }
	var b := _read_brace_body(p["next"], end)
	if _err != "": return { "node": null, "next": end }
	return { "node": { "t": kind, "at": at, "header": p["text"], "body_markup": b["text"], "body_at": b["at"] }, "next": b["next"] }

func _parse_match(at: int, end: int) -> Dictionary:
	var p := _read_paren(at + 6, end)   # past "@match"
	if _err != "": return { "node": null, "next": end }
	# locate the `{ ... }` body and walk its @case/@default arms
	var bi := _skip_ws(p["next"], end)
	if bi >= end or _src.unicode_at(bi) != L.C_LBRACE:
		_fail("GUITKX0303", "@match expects `{ ... }` with @case/@default arms", bi)
		return { "node": null, "next": end }
	# G-01: the @match body holds @case/@default arms whose OWN bodies are markup -- see
	# find_matching_markup's docstring for why this needs markup, not GDScript, lexis.
	var bclose := L.find_matching_markup(_src, bi)
	if bclose == -1 or bclose >= end:
		_fail("GUITKX0304", "unclosed @match body", bi)
		return { "node": null, "next": end }
	var cases: Array = []
	var default_body = null
	var default_body_at := -1
	var j := bi + 1
	while j < bclose:
		j = _skip_ws(j, bclose)
		if j >= bclose:
			break
		if _src.unicode_at(j) == L.C_AT and L.keyword_at(_src, j + 1, "case"):
			var cp := _read_paren(j + 5, bclose)
			if _err != "": return { "node": null, "next": end }
			var cb := _read_brace_body(cp["next"], bclose)
			if _err != "": return { "node": null, "next": end }
			cases.append({ "value": cp["text"], "body_markup": cb["text"], "body_at": cb["at"] })
			j = cb["next"]
		elif _src.unicode_at(j) == L.C_AT and L.keyword_at(_src, j + 1, "default"):
			var db := _read_brace_body(j + 8, bclose)
			if _err != "": return { "node": null, "next": end }
			default_body = db["text"]
			default_body_at = db["at"]
			j = db["next"]
		else:
			_fail("GUITKX2506", "@match body expects @case (...) { } or @default { }", j)
			return { "node": null, "next": end }
	return { "node": { "t": "match", "at": at, "subject": p["text"], "cases": cases, "default_body": default_body, "default_body_at": default_body_at }, "next": bclose + 1 }

# --- helpers ---
# [G-10] Per-char reads use unicode_at + int codes (L.C_*) -- `_src[i]` allocates a 1-char String
# per access; these helpers run for every char of every element on every parse.
func _skip_ws(i: int, end: int) -> int:
	while i < end:
		var c := _src.unicode_at(i)
		if c != L.C_SPACE and c != L.C_TAB and c != L.C_NL and c != L.C_CR:
			break
		i += 1
	return i

func _is_tag_char_code(c: int) -> bool:
	return c == 95 or (c >= 97 and c <= 122) or (c >= 65 and c <= 90) or (c >= 48 and c <= 57)

func _is_attr_name_char_code(c: int) -> bool:
	return _is_tag_char_code(c) or c == L.C_DASH or c == L.C_DOT

func _line_of(idx: int) -> int:
	# [G-08] Binary search over _line_starts (built once in parse()) -- returns the count of line
	# starts <= idx, i.e. the 1-based line number. Was `_src.substr(0, idx).count("\n") + 1`, a
	# full prefix COPY per element on element-heavy files. Fallback keeps _line_of usable if a
	# helper is ever called before parse().
	if _line_starts.is_empty():
		return _src.substr(0, idx).count("\n") + 1
	var lo := 0
	var hi := _line_starts.size() - 1
	while lo < hi:
		var mid := (lo + hi + 1) >> 1
		if _line_starts[mid] <= idx:
			lo = mid
		else:
			hi = mid - 1
	return lo + 1
