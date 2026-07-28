class_name RUIGuitkxJsxScan
extends RefCounted
## Finds markup nested INSIDE an embedded GDScript expression — e.g. `cond if c else <A/>`,
## `is_open and <Panel/>`, `{ items.map(func(it): return <Row item={it}/>) }`. Phase 4 §1.
##
## The hard problem is telling a markup `<` from a less-than operator. Like uitkx we DON'T do general
## disambiguation — we use a POSITION-GATED whitelist: a `<` begins markup ONLY when it follows
## (whitespace-skipped) a boundary token that can only be followed by an expression, AND the char
## after `<` is a tag-name start (letter/`_`) or `>` (fragment). Comparisons like `a < b`, `i < n`
## never match because no boundary token precedes them.
##
## All string/comment skipping routes through the byte-identical lexer (L.skip_noncode); this module
## adds NO lexis of its own and never edits the lexer/scanner.

const L = preload("res://addons/reactive_ui_toolkit/guitkx/guitkx_lexer.gd")

## Returns an Array of { start, end, op } ranges (sorted, non-overlapping). `start`/`end` bound the
## markup element (start at `<`, end exclusive past the close). `op` is "" normally, or "and"/"&&"
## for a short-circuit that must desugar to a ternary at emit time.
## UNBALANCED markup (opens but never closes) is reported as { start, end: -1 } and terminates the
## scan -- after a boundary token `<tag` is never valid GDScript either, so the caller must surface
## a diagnostic instead of emitting the text verbatim (T1.2).
static func find_markup_ranges(src: String, start: int, end: int) -> Array:
	var out: Array = []
	var delim: Array = []          # ( [ { stack, for the dict-`:` rule
	var i := start
	# markup at the very start of the expression (e.g. an attr value that IS markup)
	var s0 := _skip_ws(src, start, end)
	if _markup_at(src, s0, end):
		var e0 := _find_element_end(src, s0, end)
		if e0 == -1:
			return [{ "start": s0, "end": -1, "op": "", "op_pos": start }]
		out.append({ "start": s0, "end": e0, "op": "", "op_pos": start })
		i = e0
	while i < end:
		var j := L.skip_noncode(src, i)
		if j != i:
			i = j
			continue
		var c := src.unicode_at(i)
		if c == L.C_LPAREN or c == L.C_LBRACKET:
			delim.append(c)
			i = _try(src, i + 1, end, "", i, out, i + 1)
			continue
		if c == L.C_LBRACE:
			delim.append(c)
			i += 1
			continue
		if c == L.C_RPAREN or c == L.C_RBRACKET or c == L.C_RBRACE:
			if not delim.is_empty():
				delim.pop_back()
			i += 1
			continue
		if c == L.C_COMMA:
			i = _try(src, i + 1, end, "", i, out, i + 1)
			continue
		if c == L.C_EQ and _is_simple_assign(src, i, end):
			i = _try(src, i + 1, end, "", i, out, i + 1)
			continue
		if c == L.C_AMP and i + 1 < end and src.unicode_at(i + 1) == L.C_AMP:
			i = _try(src, i + 2, end, "&&", i, out, i + 2)
			continue
		if c == L.C_COLON and not delim.is_empty() and delim[-1] == L.C_LBRACE and not _is_colon_op(src, i, end):
			i = _try(src, i + 1, end, "", i, out, i + 1)
			continue
		if (c == 114 or c == 101 or c == 97 or c == 111) and _is_ident_boundary(src, i):   # r/e/a/o
			# keyword boundaries: return / else / and / or (T3.5 mirrors Unity's operator set)
			if L.keyword_at(src, i, "return"):
				i = _try(src, i + 6, end, "", i, out, i + 6); continue
			if L.keyword_at(src, i, "else"):
				i = _try(src, i + 4, end, "", i, out, i + 4); continue
			if L.keyword_at(src, i, "and"):
				i = _try(src, i + 3, end, "and", i, out, i + 3); continue
			if L.keyword_at(src, i, "or"):
				i = _try(src, i + 2, end, "or", i, out, i + 2); continue
		i += 1
	return out

# Peek for markup at the next ws-skipped position; if found, record [p, elem_end) (with the boundary
# op + its position for the `and`/`&&` desugar) and return elem_end so the caller jumps past it.
# Markup that never closes is recorded as { end: -1 } and ends the scan (see find_markup_ranges).
# Otherwise return `fallback` (advance by one token).
static func _try(src: String, after: int, end: int, op: String, op_pos: int, out: Array, fallback: int) -> int:
	var p := _skip_ws(src, after, end)
	if _markup_at(src, p, end):
		var e := _find_element_end(src, p, end)
		if e == -1:
			out.append({ "start": p, "end": -1, "op": op, "op_pos": op_pos })
			return end
		out.append({ "start": p, "end": e, "op": op, "op_pos": op_pos })
		return e
	return fallback

static func _markup_at(src: String, i: int, end: int) -> bool:
	if i >= end or src.unicode_at(i) != L.C_LT:
		return false
	if i + 1 >= end:
		return false
	var c := src.unicode_at(i + 1)
	return c == L.C_GT or c == 95 or (c >= 97 and c <= 122) or (c >= 65 and c <= 90)

## From a `<` at `open`, find the index just past the outermost element close. Tracks tag depth,
## routing strings/comments + balanced `{…}` attribute/child holes through the lexer. -1 if unbalanced.
static func _find_element_end(src: String, open: int, end: int) -> int:
	var depth := 0
	var i := open
	while i < end:
		# G-01: this walks tag names/text/attributes -- markup lexis, so `#` in child text (e.g.
		# "Score #3") stays literal and `//`/`/* */`/`<!-- -->` are recognized as comments. `{…}`
		# attr/child holes are still routed through find_matching (GDScript lexis) below.
		var j := L.skip_noncode_markup(src, i)
		if j != i:
			i = j
			continue
		var c := src.unicode_at(i)
		if c == L.C_LBRACE:
			var close := L.find_matching(src, i)   # skip an attr/child {…} hole whole
			if close == -1 or close >= end:
				return -1
			i = close + 1
			continue
		if c == L.C_LT:
			if i + 1 < end and src.unicode_at(i + 1) == L.C_SLASH:
				# closing tag </...> or fragment </>
				depth -= 1
				var gt := src.find(">", i)
				if gt == -1 or gt >= end:
					return -1
				i = gt + 1
				if depth == 0:
					return i
				continue
			if i + 1 < end and src.unicode_at(i + 1) == L.C_GT:
				depth += 1   # fragment open <>
				i += 2
				continue
			if _markup_at(src, i, end):
				# opening tag: scan to its '>' / '/>' skipping attribute {…} holes + strings, so a
				# '<'/'>' inside an attribute expr is never mistaken for the tag terminator.
				var t := _scan_open_tag(src, i, end)
				if t["gt"] == -1:
					return -1
				i = t["gt"] + 1
				if t["self_closing"]:
					if depth == 0:
						return i
				else:
					depth += 1
				continue
		i += 1
	return -1

## Scan an opening tag from its `<` to its terminating `>` / `/>`, treating every attribute `{…}` hole
## (via find_matching) and quoted string (via skip_noncode) as opaque. Returns { gt, self_closing }.
static func _scan_open_tag(src: String, lt: int, end: int) -> Dictionary:
	var i := lt + 1
	while i < end and L._is_ident_code(src.unicode_at(i)):
		i += 1   # tag name
	while i < end:
		# G-01: markup lexis over the attribute list (see _find_element_end).
		var j := L.skip_noncode_markup(src, i)
		if j != i:
			i = j
			continue
		var c := src.unicode_at(i)
		if c == L.C_LBRACE:
			var close := L.find_matching(src, i)
			if close == -1 or close >= end:
				return { "gt": -1, "self_closing": false }
			i = close + 1
			continue
		if c == L.C_SLASH and i + 1 < end and src.unicode_at(i + 1) == L.C_GT:
			return { "gt": i + 1, "self_closing": true }
		if c == L.C_GT:
			return { "gt": i, "self_closing": false }
		i += 1
	return { "gt": -1, "self_closing": false }

# --- token helpers ---
static func _skip_ws(src: String, i: int, end: int) -> int:
	while i < end:
		var c := src.unicode_at(i)
		if c != L.C_SPACE and c != L.C_TAB and c != L.C_NL and c != L.C_CR:
			break
		i += 1
	return i

static func _is_ident_boundary(src: String, i: int) -> bool:
	return i == 0 or not L._is_ident_code(src.unicode_at(i - 1))

# A `=` is a simple assignment (not ==, <=, >=, !=, :=, +=, -=, *=, /=, %=, &=, |=, ^=, <<=, >>=).
static func _is_simple_assign(src: String, i: int, end: int) -> bool:
	if i + 1 < end and src.unicode_at(i + 1) == L.C_EQ:
		return false
	if i == 0:
		return true
	var p := src.unicode_at(i - 1)
	return not (p == L.C_EQ or p == L.C_BANG or p == L.C_LT or p == L.C_GT or p == L.C_COLON or p == L.C_PLUS or p == L.C_DASH \
		or p == L.C_STAR or p == L.C_SLASH or p == L.C_PERCENT or p == L.C_AMP or p == L.C_PIPE or p == L.C_CARET)

# A `:` that is `::` or `:=` is an operator, not a dict separator.
static func _is_colon_op(src: String, i: int, end: int) -> bool:
	if i + 1 < end and (src.unicode_at(i + 1) == L.C_COLON or src.unicode_at(i + 1) == L.C_EQ):
		return true
	if i > 0 and src.unicode_at(i - 1) == L.C_COLON:
		return true
	return false
