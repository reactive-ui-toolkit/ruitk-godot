@tool
class_name GuitkxSignature
extends RefCounted
## Signature help for event-handler lambdas in markup (parity plan G4): with the caret inside
## `on_<signal>={ func (|` — or a React alias like `onChange={ func (|` — return the bound Godot
## signal's parameter list and which parameter the caret is on. A direct port of the TS server's
## `signatureHelpAt` back-scan (server.ts), against the LIVE ClassDB instead of a bundled dump.
## Pure text -> Dictionary, headless-testable; the popup widget lives in GuitkxCodeEdit.

# Preload (not the global class name): fresh class_names are absent from cold class caches.
const Schema := preload("res://addons/reactive_ui_toolkit_editor/lsp/guitkx_schema.gd")

## {} when the caret is not in an event-lambda param list; else
## { "signal": String, "label": String, "params": Array[String], "active": int }.
static func signature_at(text: String, offset: int) -> Dictionary:
	# 1. Back-scan for the enclosing call '(' — bounded by the {expr}/tag boundary. '>' does NOT
	#    stop the scan, so comparison/shift operators in the tag header can't break the lookup.
	var depth := 0
	var i := offset - 1
	var paren_open := -1
	while i >= 0:
		var c := text[i]
		if c == ")":
			depth += 1
		elif c == "(":
			if depth == 0:
				paren_open = i
				break
			depth -= 1
		elif c == "{" or c == "}" or c == ";" or c == "<":
			break
		i -= 1
	if paren_open == -1:
		return {}
	# 2. Require a `func` lambda immediately before '(' (a method ref like on_pressed={_on_click}
	#    has no parameter list to help with). Word-boundary check: `myfunc(` must not match.
	var j := paren_open - 1
	while j >= 0 and _is_ws(text[j]):
		j -= 1
	if j < 3 or text.substr(j - 3, 4) != "func":
		return {}
	if j - 4 >= 0 and _is_ident(text[j - 4]):
		return {}
	j -= 4
	# 3. Require `{` then `=` then the attribute name.
	while j >= 0 and _is_ws(text[j]):
		j -= 1
	if j < 0 or text[j] != "{":
		return {}
	j -= 1
	while j >= 0 and _is_ws(text[j]):
		j -= 1
	if j < 0 or text[j] != "=":
		return {}
	j -= 1
	while j >= 0 and _is_ws(text[j]):
		j -= 1
	var name_end := j + 1
	while j >= 0 and (_is_ident(text[j]) or text[j] == "." or text[j] == "-"):
		j -= 1
	var attr := text.substr(j + 1, name_end - (j + 1))
	if not _is_event_attr(attr):
		return {}
	# 4. Find the enclosing opening tag's name — back-scan skipping ={...} exprs and quoted values
	#    so a '<' operator inside an earlier attribute doesn't halt the lookup.
	var t := j
	var bdepth := 0
	while t >= 0:
		var ch := text[t]
		if ch == "\"" or ch == "'":
			t -= 1
			while t >= 0 and text[t] != ch:
				t -= 1
			t -= 1
			continue
		if ch == "}":
			bdepth += 1
			t -= 1
			continue
		if ch == "{":
			if bdepth > 0:
				bdepth -= 1
			t -= 1
			continue
		if ch == "<" and bdepth == 0:
			break
		t -= 1
	if t < 0 or text[t] != "<":
		return {}
	var tn := t + 1
	var te := tn
	while te < text.length() and _is_ident(text[te]):
		te += 1
	var tag := text.substr(tn, te - tn)
	if not Schema.is_host_tag(tag):
		return {}  # host elements only — component props have no ClassDB signal table
	var gclass: String = Schema.godot_class_for(tag)
	var signal_name: String = Schema.resolve_event_signal(attr, gclass)
	if signal_name == "":
		return {}
	var sig := {}
	for s in Schema.godot_signals(gclass):
		if str((s as Dictionary).get("name", "")) == signal_name:
			sig = s
			break
	if sig.is_empty():
		return {}
	# 5. active parameter = top-level comma count between '(' and the caret (depth- and string-safe).
	var active := 0
	var d2 := 0
	var p := paren_open + 1
	while p < offset and p < text.length():
		var ch2 := text[p]
		if ch2 == "\"" or ch2 == "'":
			p += 1
			while p < text.length() and text[p] != ch2:
				p += 1
		elif ch2 == "(" or ch2 == "[" or ch2 == "{":
			d2 += 1
		elif ch2 == ")" or ch2 == "]" or ch2 == "}":
			d2 -= 1
		elif ch2 == "," and d2 == 0:
			active += 1
		p += 1
	var params: Array = []
	for a in sig.get("args", []):
		var ad := a as Dictionary
		params.append("%s: %s" % [str(ad.get("name", "")), _arg_type(ad)])
	return {
		"signal": signal_name,
		"label": "%s(%s)" % [signal_name, ", ".join(PackedStringArray(params))],
		"params": params,
		"active": mini(active, maxi(0, params.size() - 1)),
	}

# Event attribute shapes (mirrors events.ts isEventAttr): the on_<signal> escape hatch or a
# camelCase on<Pascal> that lowers to the snake_case signal (resolve_event_signal validates it later).
static func _is_event_attr(name: String) -> bool:
	if name.begins_with("on_") and name.length() > 3:
		return true
	return name.length() > 2 and name.begins_with("on") and name.unicode_at(2) >= 65 and name.unicode_at(2) <= 90

static func _arg_type(arg: Dictionary) -> String:
	var cls := str(arg.get("class_name", ""))
	if cls != "":
		return cls
	var ty := int(arg.get("type", TYPE_NIL))
	return "Variant" if ty == TYPE_NIL else type_string(ty)

static func _is_ws(c: String) -> bool:
	return c == " " or c == "\t" or c == "\n" or c == "\r"

static func _is_ident(c: String) -> bool:
	var u := c.unicode_at(0)
	return (u >= 65 and u <= 90) or (u >= 97 and u <= 122) or (u >= 48 and u <= 57) or u == 95
