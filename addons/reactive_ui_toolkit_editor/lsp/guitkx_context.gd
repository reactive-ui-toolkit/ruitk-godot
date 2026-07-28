@tool
class_name GuitkxContext
extends RefCounted
## Classifies a caret position in a `.guitkx` buffer into a completion/hover context, so the editor
## knows what to offer. Port of ide-extensions/lsp-server/src/context.ts `classifyContext` +
## `enclosingTag`/brace-kind/`looksLikeSetup`. [Phase 1 -- plans/GODOT_ANALYZER_INTEGRATION_PLAN.md §7]
##
## classify(text, offset) -> { kind, tag, word } where kind is one of:
##   "tagName"   -- typing a tag name after `<` (offer host tags + user components)
##   "attrName"  -- inside an open `<Tag ...`, past the name (offer props/events/structural attrs)
##   "attrValue" -- inside a quoted attribute value (offer enum/bool values; suppress tag/attr)
##   "directive" -- typing `@if` / `@for` / ... (offer directives)
##   "markup"    -- a child slot (offer `<Tag` / `<Component` / directive snippets)
##   "embedded"  -- inside `{expr}` / a setup line (GDScript; markup completion suppressed, later
##                  forwarded to the analyzer in Phase 4)
## `offset` is a character offset (codepoint units, matching GDScript String indexing).

const KIND_TAG := "tagName"
const KIND_ATTR := "attrName"
const KIND_ATTR_VALUE := "attrValue"
const KIND_DIRECTIVE := "directive"
const KIND_MARKUP := "markup"
const KIND_EMBEDDED := "embedded"

# Leading tokens that mean "this line is GDScript setup, not markup" (looksLikeSetup, context.ts).
const _SETUP_LEADERS := ["var ", "const ", "return", "if ", "elif ", "else", "for ", "while ",
	"match ", "func ", "await ", "pass", "breakpoint", "assert", "@onready", "@export", "static "]

## Convert an editor (line, column) to a character offset in `text`.
static func offset_of(text: String, line: int, column: int) -> int:
	var lines := text.split("\n")
	var off := 0
	for i in min(line, lines.size()):
		off += (lines[i] as String).length() + 1  # +1 for the newline
	return off + column

static func classify(text: String, offset: int) -> Dictionary:
	offset = clampi(offset, 0, text.length())
	var i := 0
	var in_str := false
	var str_ch := 0
	var str_start := -1
	var in_tag := false
	var tag_lt := -1
	var brace_body: Array[bool] = []   # stack: true = body brace ({ of component/@for/...), false = {expr}
	while i < offset:
		var c := text.unicode_at(i)
		if in_str:
			if c == 92:            # backslash -> skip escaped char
				i += 2
				continue
			if c == str_ch:
				in_str = false
			i += 1
			continue
		if c == 35:                # '#' comment to end of line
			var nl := text.find("\n", i)
			if nl == -1 or nl >= offset:
				i = offset
				break
			i = nl
			continue
		if c == 34 or c == 39:     # '"' or "'"
			in_str = true
			str_ch = c
			str_start = i
			i += 1
			continue
		if c == 123:               # '{'
			brace_body.append(_is_body_brace(text, i))
			i += 1
			continue
		if c == 125:               # '}'
			if not brace_body.is_empty():
				brace_body.pop_back()
			i += 1
			continue
		if not in_tag:
			if c == 60:            # '<'
				var nx := text.unicode_at(i + 1) if i + 1 < text.length() else 0
				if _is_ident_start(nx) or nx == 47:   # '<Name' or '</Name'
					in_tag = true
					tag_lt = i
			i += 1
			continue
		else:
			if c == 62:            # '>' closes the tag
				in_tag = false
				tag_lt = -1
			i += 1
			continue

	# --- classify from the final state at `offset` ---
	var in_expr_brace := not brace_body.is_empty() and not brace_body[brace_body.size() - 1]

	if in_str:
		# Inside a quoted attribute value vs. an embedded string literal. `attr` names the
		# attribute whose value the string belongs to (drives bool/enum/style-key completion) —
		# _attr_name_before skips `{`s, so both `visible="|"` and `style={ {"|` resolve it.
		if in_tag:
			return { "kind": KIND_ATTR_VALUE, "tag": _tag_name_at(text, tag_lt),
				"attr": _attr_name_before(text, str_start), "word": _word_before(text, offset) }
		return { "kind": KIND_EMBEDDED, "tag": "", "word": _word_before(text, offset) }

	if in_tag:
		var after_lt := text.substr(tag_lt + 1, offset - tag_lt - 1)
		if in_expr_brace:
			# inside `attr={ ... }` -> embedded GDScript expression
			return { "kind": KIND_EMBEDDED, "tag": _tag_name_at(text, tag_lt), "word": _word_before(text, offset) }
		if _is_all_tagname_chars(after_lt):
			var w := after_lt.trim_prefix("/")
			return { "kind": KIND_TAG, "tag": "", "word": w }
		return { "kind": KIND_ATTR, "tag": _first_token(after_lt), "word": _word_before(text, offset) }

	if in_expr_brace:
		return { "kind": KIND_EMBEDDED, "tag": "", "word": _word_before(text, offset) }

	# Not in a tag/string/expr-brace: markup child, directive, or setup line.
	var line_start := 0 if offset <= 0 else text.rfind("\n", offset - 1) + 1
	var line_before := text.substr(line_start, offset - line_start)
	var trimmed := line_before.strip_edges(true, false)

	# Just typed '<' at a child slot -> tag name.
	if offset > 0 and text.unicode_at(offset - 1) == 60:
		return { "kind": KIND_TAG, "tag": "", "word": "" }

	# `@directive` being typed.
	var at := trimmed.rfind("@")
	if at != -1 and _is_directive_word(trimmed.substr(at)):
		return { "kind": KIND_DIRECTIVE, "tag": "", "word": trimmed.substr(at) }

	if _looks_like_setup(trimmed):
		return { "kind": KIND_EMBEDDED, "tag": "", "word": _word_before(text, offset) }

	return { "kind": KIND_MARKUP, "tag": "", "word": _word_before(text, offset) }

# --- helpers -----------------------------------------------------------------------------------

## The attribute name owning a value that starts at `from` (a quote or expr position): walks back
## over whitespace and `{` openers to `=`, then reads the identifier. "" when not a value position.
static func _attr_name_before(text: String, from: int) -> String:
	var i := from - 1
	while i >= 0:
		var c := text.unicode_at(i)
		if c == 32 or c == 9 or c == 10 or c == 123:  # space/tab/newline/'{'
			i -= 1
			continue
		break
	if i < 0 or text.unicode_at(i) != 61:  # '='
		return ""
	i -= 1
	while i >= 0 and (text.unicode_at(i) == 32 or text.unicode_at(i) == 9):
		i -= 1
	var e := i
	while i >= 0:
		var c2 := text.unicode_at(i)
		if c2 == 95 or (c2 >= 48 and c2 <= 57) or (c2 >= 65 and c2 <= 90) or (c2 >= 97 and c2 <= 122):
			i -= 1
			continue
		break
	return text.substr(i + 1, e - i)

static func _is_body_brace(text: String, brace_pos: int) -> bool:
	# A body brace ({ of a declaration or @if/@for/@while/@match/@case/@else/@default) is preceded
	# by ')', the words `else`/`default`, `module <ident>` (window wrapper), a `-> Type` return
	# annotation (plain E-01 callable header), or a line-leading bare identifier (paramless plain
	# decl `Name {`). Otherwise it's an {expr}. MIRROR: semanticTokens.ts isBodyBrace.
	var j := brace_pos - 1
	while j >= 0 and _is_ws(text.unicode_at(j)):
		j -= 1
	if j < 0:
		return false
	if text.unicode_at(j) == 41:   # ')'
		return true
	if not _is_ident_char(text.unicode_at(j)):
		return false
	var end := j + 1
	while j >= 0 and _is_ident_char(text.unicode_at(j)):
		j -= 1
	var word := text.substr(j + 1, end - j - 1)
	var word_start := j + 1
	if word == "else" or word == "default":
		return true
	# `-> Type {` -- the plain-decl return annotation (E-01): the word before `{` is the TYPE,
	# preceded (after ws) by `->`.
	var k := word_start - 1
	while k >= 0 and _is_ws(text.unicode_at(k)):
		k -= 1
	if k >= 1 and text.unicode_at(k) == 62 and text.unicode_at(k - 1) == 45:   # '>' after '-'
		return true
	# `component X {` / `hook use_x {` / `module Name {` -- the paren-less wrapper decl headers
	# (window syntax). MIRROR: semanticTokens.ts isBodyBrace checks the same three keywords.
	while j >= 0 and _is_ws(text.unicode_at(j)):
		j -= 1
	var pend := j + 1
	while j >= 0 and _is_ident_char(text.unicode_at(j)):
		j -= 1
	var kw := text.substr(j + 1, pend - j - 1)
	if kw == "component" or kw == "hook" or kw == "module":
		return true
	# Paramless plain decl `Name {` / `export Name {`: the identifier chain before the `{` starts
	# at the beginning of its line (a top-level declaration header).
	var ls := text.rfind("\n", word_start - 1) + 1
	var lead := text.substr(ls, word_start - ls)
	return lead.strip_edges() == "" or lead.strip_edges() == "export"

static func _tag_name_at(text: String, lt_pos: int) -> String:
	if lt_pos < 0:
		return ""
	var i := lt_pos + 1
	if i < text.length() and text.unicode_at(i) == 47:  # closing tag '/'
		i += 1
	var start := i
	while i < text.length() and _is_ident_char(text.unicode_at(i)):
		i += 1
	return text.substr(start, i - start)

static func _first_token(s: String) -> String:
	var t := s.strip_edges()
	var i := 0
	if i < t.length() and t.unicode_at(i) == 47:
		i += 1
	var start := i
	while i < t.length() and _is_ident_char(t.unicode_at(i)):
		i += 1
	return t.substr(start, i - start)

static func _word_before(text: String, offset: int) -> String:
	var i := offset
	while i > 0 and _is_ident_char(text.unicode_at(i - 1)):
		i -= 1
	return text.substr(i, offset - i)

static func _is_all_tagname_chars(s: String) -> bool:
	for i in s.length():
		var c := s.unicode_at(i)
		if i == 0 and c == 47:   # leading '/' for a closing tag is allowed
			continue
		if not _is_ident_char(c):
			return false
	return true

static func _is_directive_word(s: String) -> bool:
	# s starts with '@'; a directive word is '@' followed only by identifier chars (still typing it).
	for i in range(1, s.length()):
		if not _is_ident_char(s.unicode_at(i)):
			return false
	return true

static func _looks_like_setup(trimmed: String) -> bool:
	for lead in _SETUP_LEADERS:
		if trimmed.begins_with(lead) or trimmed == lead.strip_edges():
			return true
	return false

static func _is_ident_start(c: int) -> bool:
	return c == 95 or (c >= 65 and c <= 90) or (c >= 97 and c <= 122)

static func _is_ident_char(c: int) -> bool:
	return _is_ident_start(c) or (c >= 48 and c <= 57)

static func _is_ws(c: int) -> bool:
	return c == 32 or c == 9 or c == 10 or c == 13
