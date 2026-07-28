@tool
class_name GuitkxScanDiags
extends RefCounted
## Parse-INDEPENDENT unknown-tag diagnostics (the editor-side analogue of the VS Code server's
## scan-window tier). The compiler's own GUITKX0105 lives in its EMIT phase, so any parse error in
## the window (a mismatched close tag is the classic: you typo the OPEN tag and the close no longer
## pairs) masks the very unknown-tag report that would explain the problem. [field capture:
## `<DemoaBox>` ... `</DemoBox>` showed only the close-tag error, never the did-you-mean]
##
## This scan walks raw text with the lexer's string/comment skipper, collects every OPEN tag, and
## flags names that are neither a V factory, a host tag, a module-local declaration in this file,
## nor in the project's known-component universe. Records match the compiler's diagnostic shape
## ({ code, severity, message, offset, length }) so the renderer and Problems panel take them
## unchanged; the view dedupes against compiler diagnostics by (code, offset).

const CODE := "GUITKX0105"
const SEVERITY_ERROR := 0  # RUIGuitkxDiag.ERROR (pinned by test against the real constant)

## `known` is the project universe (Array of class names from project_bindings()["known"]).
static func unknown_tags(text: String, known: Array) -> Array:
	var vocab: Dictionary = RUIGuitkx.vocab()
	var factories: Dictionary = vocab.get("v_factories_set", {})
	if factories.is_empty():
		for f in vocab.get("v_factories", []):
			factories[str(f)] = true
	var hosts: Dictionary = vocab.get("host_tags", {})
	var known_set := {}
	for k in known:
		known_set[str(k)] = true
	for m in _local_decls(text):
		known_set[m] = true

	var out: Array = []
	var i := 0
	var n := text.length()
	while i < n:
		var j: int = RUIGuitkxLexer.skip_noncode(text, i)
		if j > i:
			i = j
			continue
		if text[i] != "<":
			i += 1
			continue
		# Only OPEN tags: `</` mirrors an open we already judged; `<=`/`< ` are comparisons.
		var k := i + 1
		if k < n and text[k] == "/":
			i += 1
			continue
		var s := k
		while k < n and _is_ident(text.unicode_at(k)):
			k += 1
		if k == s:
			i += 1
			continue
		# Boundary guard (same idea as the VS Code scan): a comparison's `<` follows an expression
		# end — identifier, `)`, `]`, quote — while a real tag's `<` follows whitespace-after
		# structure (`(`, `{`, `,`, `>`, newline, start). `x <level` is a comparison, not a tag.
		var p := i - 1
		while p >= 0 and (text[p] == " " or text[p] == "\t"):
			p -= 1
		if p >= 0 and (_is_ident(text.unicode_at(p)) or text[p] == ")" or text[p] == "]" or text[p] == "\"" or text[p] == "'"):
			i = k
			continue
		var tag := text.substr(s, k - s)
		var lower := tag[0] >= "a" and tag[0] <= "z"
		var ok := (factories.has(tag) if lower else (hosts.has(tag) or known_set.has(tag)))
		if not ok:
			var msg := "unknown element <%s>" % tag
			var best := _closest(tag, factories.keys() + hosts.keys() + known_set.keys())
			if best != "":
				msg += " -- did you mean <%s>?" % best
			out.append({ "code": CODE, "severity": SEVERITY_ERROR, "message": msg, "offset": s, "length": tag.length() })
		i = k
	return out

## Declaration names in THIS buffer (buffer-local components are legal tags before any save).
## ES-modules leg: declarations are SIGNATURE-classified — plain forms have no keyword for a
## regex to find, so the whitelist consumes the compiler's own scan (the same swap
## guitkx_workspace.gd got; M1.4: never leave a wrapper-only regex behind). Wrapper module
## MEMBERS still need a member regex — they live inside a module body the top-level scan does
## not enter (window syntax only; the codemod hoists them).
static func _local_decls(text: String) -> Array:
	var out: Array = []
	for dm in (RUIGuitkx.analyzed_decls(text, 0)["decls"] as Array):
		var nm := str(dm["name"])
		if nm != "":
			out.append(nm)
	var mem := RegEx.new()
	mem.compile("(?m)^[ \\t]+(?:export[ \\t]+)?component[ \\t]+([A-Za-z_][A-Za-z0-9_]*)")
	for m in mem.search_all(text):
		out.append(m.get_string(1))
	var cn := RegEx.new()
	cn.compile("(?m)^[ \\t]*@class_name[ \\t]+([A-Za-z_][A-Za-z0-9_]*)")
	var c := cn.search(text)
	if c != null:
		out.append(c.get_string(1))
	return out

static func _closest(word: String, candidates: Array) -> String:
	var best := ""
	var best_d := 3
	var wl := word.to_lower()
	for c in candidates:
		var d := _edit_distance(wl, str(c).to_lower())
		if d < best_d:
			best_d = d
			best = str(c)
	return best

## Bounded Levenshtein (two-row DP), same semantics as the compiler's.
static func _edit_distance(a: String, b: String) -> int:
	if absi(a.length() - b.length()) > 2:
		return 3
	var prev := PackedInt32Array()
	prev.resize(b.length() + 1)
	for j in b.length() + 1:
		prev[j] = j
	var cur := PackedInt32Array()
	cur.resize(b.length() + 1)
	for i in a.length():
		cur[0] = i + 1
		for j in b.length():
			var cost := 0 if a[i] == b[j] else 1
			cur[j + 1] = mini(mini(cur[j] + 1, prev[j + 1] + 1), prev[j] + cost)
		var tmp := prev
		prev = cur
		cur = tmp
	return prev[b.length()]

static func _is_ident(c: int) -> bool:
	return c == 95 or (c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122)
