@tool
class_name GuitkxTokenizer
extends RefCounted
## A small, line-oriented tokenizer for .guitkx, written for syntax highlighting.
##
## Why this exists: RUIGuitkxLexer is NOT a token producer — it only exposes static scan primitives
## (skip_noncode / find_matching / keyword_at). This class reuses those primitives to classify a
## single line into coloured spans. It is intentionally per-line and self-contained: Godot calls the
## highlighter's _get_line_syntax_highlighting(line) one line at a time with no guaranteed order, so
## carrying state across lines is unreliable. Constructs that span lines (a `{expr}` or a triple-quoted
## string opened on an earlier line) are highlighted best-effort on each line in isolation.
##
## tokenize_line() returns an ordered, non-overlapping Array of { "start": int, "end": int (exclusive),
## "kind": String }. Only classified runs are emitted; anything else is left to the editor's default
## text colour. Pure and FileAccess-free, so it is headlessly unit-testable.
##
## Embedded `{expr}` regions RECURSE (G11): the inner slice re-tokenizes in gd_mode, where `<` is a
## plain operator (never a tag) and `name=` is an assignment (never an attribute) — so GDScript
## inside braces gets real keyword/string/number colouring without the markup rules mis-firing.
##
## [G-10] Per-char reads use unicode_at + int codes (RUIGuitkxLexer.C_*) — this runs per keystroke
## for every visible line, and GDScript `s[i]` allocates a 1-char String per access.

const L = preload("res://addons/reactive_ui_toolkit/guitkx/guitkx_lexer.gd")

# [G-10] LOCAL char-code consts (mirroring RUIGuitkxLexer.C_*): local class constants fold into
# the bytecode, while cross-script `L.C_X` access is a runtime member lookup per access — measured
# 64% SLOWER than the old string compares in this per-char loop. Keep these local.
const C_TAB := 9
const C_NL := 10
const C_CR := 13
const C_SPACE := 32
const C_BANG := 33
const C_QUOTE := 34
const C_HASH := 35
const C_PERCENT := 37
const C_AMP := 38
const C_APOS := 39
const C_LPAREN := 40
const C_RPAREN := 41
const C_STAR := 42
const C_PLUS := 43
const C_COMMA := 44
const C_DASH := 45
const C_DOT := 46
const C_SLASH := 47
const C_COLON := 58
const C_SEMI := 59
const C_LT := 60
const C_EQ := 61
const C_GT := 62
const C_QMARK := 63
const C_AT := 64
const C_LBRACKET := 91
const C_RBRACKET := 93
const C_LBRACE := 123
const C_PIPE := 124
const C_RBRACE := 125

enum { K_COMMENT, K_STRING, K_TAG, K_ATTR, K_EXPR, K_DIRECTIVE, K_KEYWORD, K_NUMBER, K_SYMBOL }

# Kept as strings in the output so callers/tests read clearly; enum above documents the closed set.
const KIND := {
	K_COMMENT: "comment", K_STRING: "string", K_TAG: "tag", K_ATTR: "attr",
	K_EXPR: "expr", K_DIRECTIVE: "directive", K_KEYWORD: "keyword",
	K_NUMBER: "number", K_SYMBOL: "symbol",
}

# GDScript + .guitkx declaration/control keywords (appear in setup blocks and @directives).
# ES-modules leg: `export`/`import`/`default` join the set (deferred export lists, default
# imports/exports); the wrapper trio stays highlighted for the deprecation window.
const KEYWORDS := {
	"component": true, "hook": true, "module": true,
	"export": true, "import": true, "default": true, "from": true,
	"func": true, "var": true, "const": true, "enum": true, "signal": true, "class": true,
	"class_name": true, "extends": true, "static": true, "return": true, "pass": true,
	"break": true, "continue": true, "await": true, "yield": true, "super": true, "self": true,
	"if": true, "elif": true, "else": true, "for": true, "while": true, "match": true,
	"in": true, "as": true, "is": true, "and": true, "or": true, "not": true,
	"true": true, "false": true, "null": true, "void": true, "use": true,
}

func tokenize_line(text: String, gd_mode: bool = false) -> Array:
	var out: Array = []
	var n := text.length()
	var i := 0
	while i < n:
		var c := text.unicode_at(i)
		# 1. Strings and # comments, via the proven lexer primitive (handles r"" &"" ^"" $"" %"" prefixes,
		#    triple quotes, and backslash escapes). skip_noncode returns the index just past the run.
		if c == C_HASH or c == C_QUOTE or c == C_APOS:
			var j: int = RUIGuitkxLexer.skip_noncode(text, i)
			if j > i:
				out.append({"start": i, "end": j, "kind": ("comment" if c == C_HASH else "string")})
				i = j
				continue
		# 2. Embedded-GDScript expression { ... } — braces as symbols, the inside re-tokenized in
		#    gd_mode and remapped to absolute columns (G11). Nested braces recurse naturally.
		if c == C_LBRACE:
			var close: int = RUIGuitkxLexer.find_matching(text, i)
			var end := (close + 1) if close >= 0 else n
			out.append({"start": i, "end": i + 1, "kind": "symbol"})
			var inner_start := i + 1
			var inner_end := close if close >= 0 else n
			if inner_end > inner_start:
				for t in tokenize_line(text.substr(inner_start, inner_end - inner_start), true):
					out.append({
						"start": inner_start + int(t["start"]),
						"end": inner_start + int(t["end"]), "kind": t["kind"],
					})
			if close >= 0:
				out.append({"start": close, "end": close + 1, "kind": "symbol"})
			i = end
			continue
		# 3. Tag: `<Name`, `</Name` — colour the `<` / `</` as symbol and the name as a tag.
		#    Not in gd_mode: inside an expression `<` is the less-than operator (case 7).
		if c == C_LT and not gd_mode:
			var k := i + 1
			if k < n and text.unicode_at(k) == C_SLASH:
				k += 1
			if k < n and _is_name_start_code(text.unicode_at(k)):
				out.append({"start": i, "end": k, "kind": "symbol"})
				var m := k
				while m < n and _is_name_code(text.unicode_at(m)):
					m += 1
				out.append({"start": k, "end": m, "kind": "tag"})
				i = m
				continue
			out.append({"start": i, "end": i + 1, "kind": "symbol"})
			i += 1
			continue
		# 4. @directive (@if, @for, @match, @class_name, ...).
		if c == C_AT:
			var m := i + 1
			while m < n and _is_name_code(text.unicode_at(m)):
				m += 1
			if m > i + 1:
				out.append({"start": i, "end": m, "kind": "directive"})
				i = m
				continue
			out.append({"start": i, "end": i + 1, "kind": "symbol"})
			i += 1
			continue
		# 5. Numbers.
		if _is_digit_code(c):
			var m := i
			while m < n and _is_num_cont_code(text.unicode_at(m)):
				m += 1
			out.append({"start": i, "end": m, "kind": "number"})
			i = m
			continue
		# 6. Identifiers: a keyword, or a .guitkx attribute name (`name=` immediately before a value).
		if _is_name_start_code(c):
			var m := i
			while m < n and _is_name_code(text.unicode_at(m)):
				m += 1
			var word := text.substr(i, m - i)
			if KEYWORDS.has(word):
				out.append({"start": i, "end": m, "kind": "keyword"})
			elif not gd_mode and _is_attr_name(text, m, n):
				# gd_mode: `x = "s"` / `x = {…}` are assignments, not attributes.
				out.append({"start": i, "end": m, "kind": "attr"})
			# else: plain identifier — leave to default colour.
			i = m
			continue
		# 7. Punctuation / operators.
		if _is_symbol_code(c):
			out.append({"start": i, "end": i + 1, "kind": "symbol"})
			i += 1
			continue
		i += 1
	return out

# An identifier is an attribute name only if the next non-space char is `=` AND the value after it is a
# .guitkx attribute value (a string or a `{expr}`). This avoids painting GDScript assignments (`x = 5`)
# inside setup blocks as attributes.
func _is_attr_name(text: String, after: int, n: int) -> bool:
	var j := after
	while j < n and (text.unicode_at(j) == C_SPACE or text.unicode_at(j) == C_TAB):
		j += 1
	if j >= n or text.unicode_at(j) != C_EQ:
		return false
	j += 1
	while j < n and (text.unicode_at(j) == C_SPACE or text.unicode_at(j) == C_TAB):
		j += 1
	if j >= n:
		return false
	var v := text.unicode_at(j)
	return v == C_QUOTE or v == C_APOS or v == C_LBRACE

# Flat single-body char classes (no nested helper calls -- a GDScript call costs more than the
# handful of int compares it would save).
func _is_name_start_code(c: int) -> bool:
	return c == 95 or (c >= 97 and c <= 122) or (c >= 65 and c <= 90)

func _is_name_code(c: int) -> bool:
	return c == 95 or (c >= 97 and c <= 122) or (c >= 65 and c <= 90) or (c >= 48 and c <= 57)

func _is_digit_code(c: int) -> bool:
	return c >= 48 and c <= 57

# Number continuation: digits, `.`, `_`, hex digits a-f/A-F, and base/exponent markers x/X/b/o
# (mirrors the old "abcdefABCDEFxXbo".contains() set, without a per-char String alloc).
func _is_num_cont_code(c: int) -> bool:
	return (c >= 48 and c <= 57) or c == C_DOT or c == 95 \
			or (c >= 97 and c <= 102) or (c >= 65 and c <= 70) \
			or c == 120 or c == 88 or c == 98 or c == 111

# The old `_SYMBOLS` string `<>/={}()[],.:;+-*%&|!?` as an int-keyed set: one C++ hash lookup per
# char instead of a 22-arm interpreted match (measured: the match was the tokenizer's regression).
const _SYMBOL_SET := {
	60: true, 62: true, 47: true, 61: true, 123: true, 125: true, 40: true, 41: true,
	91: true, 93: true, 44: true, 46: true, 58: true, 59: true, 43: true, 45: true,
	42: true, 37: true, 38: true, 124: true, 33: true, 63: true,
}
func _is_symbol_code(c: int) -> bool:
	return _SYMBOL_SET.has(c)
