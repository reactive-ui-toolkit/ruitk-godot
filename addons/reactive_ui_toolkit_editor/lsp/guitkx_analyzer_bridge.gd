@tool
class_name GuitkxAnalyzerBridge
extends RefCounted
## The embedded-GDScript intelligence boundary (parity plan M3 / analyzer plan Phase 4): owns ONE
## GdscriptAnalyzer session (the native gdext binding of gdscript-analyzer), the virtual-document
## lifecycle for open .guitkx buffers, and EVERY offset conversion across the boundary —
## guitkx char offset ↔ virtual-doc char offset (GuitkxSourceMap) ↔ virtual-doc UTF-8 byte offset
## (GuitkxLineIndex). Callers speak .guitkx character offsets exclusively.
##
## FEATURE-DETECTED: `available()` is false when the reactive_ui_toolkit_analyzer GDExtension is not
## installed, `instance()` returns null, and every caller degrades to markup-only intelligence —
## the native binary is an optional enhancement, never a requirement.
##
## Queries whose caret does not land inside a mapped embedded span return empty ({} / []) so the
## markup tier keeps owning tags/attributes/directives. Results are remapped back into .guitkx
## coordinates; entries that map into virtual-doc glue (hook stubs, scaffolding) are dropped —
## glue can never squiggle or navigate into user code.

const VirtualDocScript := preload("res://addons/reactive_ui_toolkit_editor/lsp/guitkx_virtual_doc.gd")
const LineIndexScript := preload("res://addons/reactive_ui_toolkit_editor/lsp/guitkx_line_index.gd")

const VIRTUAL_SCHEME := "guitkx-virtual://"

# Typed RefCounted, and self-instantiated via load() of our own path: a script's OWN class_name
# is not resolvable inside its statics on a cold global-class cache (same gotcha as cross-class
# preloads — naming it here failed the whole script's compile on fresh checkouts).
const _SELF_PATH := "res://addons/reactive_ui_toolkit_editor/lsp/guitkx_analyzer_bridge.gd"
static var _singleton: RefCounted = null

var _az: Object = null
# res_path -> { "hash": int, "vtext": String, "map": GuitkxSourceMap, "uri": String }
var _docs: Dictionary = {}

## True when the GdscriptAnalyzer GDExtension is loaded (the reactive_ui_toolkit_analyzer addon).
## class_exists() gates first: can_instantiate() logs a red engine ERROR for unknown classes,
## and the degrade path is supported behaviour, not console-noise-worthy.
static func available() -> bool:
	return ClassDB.class_exists(&"GdscriptAnalyzer") and ClassDB.can_instantiate(&"GdscriptAnalyzer")

## The analyzer library's version string, or "" when unavailable.
static func native_version() -> String:
	if not available():
		return ""
	# Static #[func]s aren't reachable without the registered class name being resolvable at parse
	# time (this addon must load with the extension absent), so read it off a scratch instance.
	var az: Object = ClassDB.instantiate(&"GdscriptAnalyzer")
	return str(az.version())

## The editor-lifetime bridge, or null when the native layer is absent (degrade to markup-only).
static func instance() -> RefCounted:
	if not available():
		return null
	if _singleton == null:
		var self_script: GDScript = load(_SELF_PATH)
		_singleton = self_script.new()
		_singleton._start()
	return _singleton

## Test hook: drop the singleton so a fresh session re-feeds the project.
static func reset() -> void:
	_singleton = null

func _start() -> void:
	_az = ClassDB.instantiate(&"GdscriptAnalyzer")
	# Match Godot's own warning posture in-editor; the compiler tier owns .guitkx-domain checks.
	_az.set_warning_override("engine-defaults")
	var project := FileAccess.get_file_as_string("res://project.godot")
	if project != "":
		_az.set_project_config(project)
	_feed_project_scripts()
	# workspace_complete stays FALSE deliberately: the absence-based UNDEFINED_* family needs a
	# provably-complete file set; the virtual docs make the set structurally incomplete, and false
	# UNDEFINED noise inside user expressions would be worse than missing that diagnostic tier.

## Feed every project .gd (skipping res://.godot) so cross-file types — RUIVNode, Hooks, the
## user's own classes and autoloads — resolve inside embedded expressions. One-time per editor
## session; salsa parses lazily at query time, so the cost here is file IO only.
func _feed_project_scripts() -> void:
	var stack: Array[String] = ["res://"]
	while not stack.is_empty():
		var dir_path: String = stack.pop_back()
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		dir.list_dir_begin()
		var entry := dir.get_next()
		while entry != "":
			var full := dir_path.path_join(entry)
			if dir.current_is_dir():
				if not entry.begins_with(".") and full != "res://.godot":
					stack.append(full)
			elif entry.get_extension() == "gd":
				var text := FileAccess.get_file_as_string(full)
				if text != "":
					_az.open_document(full, text, full)
			entry = dir.get_next()
		dir.list_dir_end()

## Notify the bridge that a real .gd changed on disk (the watcher regenerated a sibling, an
## external edit landed) so cross-file types stay fresh.
func refresh_script(res_path: String) -> void:
	if _az == null:
		return
	var text := FileAccess.get_file_as_string(res_path)
	if text != "":
		_az.open_document(res_path, text, res_path)

## Drop a closed buffer's virtual doc.
func close_doc(path: String) -> void:
	if _docs.has(path):
		_az.close_document(str((_docs[path] as Dictionary)["uri"]))
		_docs.erase(path)

## --- the boundary ------------------------------------------------------------------------------

# Build/refresh the virtual doc for (path, text); returns the cache entry.
func _ensure_doc(path: String, text: String) -> Dictionary:
	var key := path if path != "" else "(scratch)"
	var h := text.hash()
	if _docs.has(key) and int((_docs[key] as Dictionary)["hash"]) == h:
		return _docs[key]
	var built: Dictionary = VirtualDocScript.build(text)
	var uri := VIRTUAL_SCHEME + key
	var entry := {
		"hash": h, "vtext": str(built["text"]), "map": built["map"], "uri": uri,
	}
	if _docs.has(key):
		_az.change_document(uri, str(built["text"]))
	else:
		_az.open_document(uri, str(built["text"]), "")
	_docs[key] = entry
	return entry

# guitkx char offset -> virtual-doc UTF-8 byte offset, or -1 when the caret is not inside a
# mapped embedded span (markup/glue — the markup tier owns it).
func _to_virtual_byte(entry: Dictionary, guitkx_offset: int) -> int:
	var vchar: int = (entry["map"] as GuitkxSourceMap).to_generated(guitkx_offset)
	if vchar < 0:
		return -1
	return LineIndexScript.char_to_byte(str(entry["vtext"]), vchar)

# Analyzer byte range on the virtual doc -> { "offset", "length" } in .guitkx chars, or {} when
# either end lands in glue.
func _range_to_guitkx(entry: Dictionary, rng: Dictionary) -> Dictionary:
	var vtext := str(entry["vtext"])
	var map := entry["map"] as GuitkxSourceMap
	var s := map.to_source(LineIndexScript.byte_to_char(vtext, int(rng.get("start", -1))))
	var e := map.to_source(LineIndexScript.byte_to_char(vtext, int(rng.get("end", -1))))
	if s < 0 or e < 0 or e < s:
		return {}
	return { "offset": s, "length": e - s }

## True when `offset` sits inside a mapped embedded span (map-only: hash-cached virtual doc, no
## analyzer query) — the cheap gate for ctrl+hover symbol validation.
func is_embedded_offset(path: String, text: String, offset: int) -> bool:
	var entry := _ensure_doc(path, text)
	return (entry["map"] as GuitkxSourceMap).to_generated(offset) >= 0

## --- queries (all: .guitkx char offsets in, .guitkx char offsets out) ---------------------------

## Completion items at `offset`, or [] (unmapped caret / no items). Raw analyzer items:
## { label, kind (snake_case), insert_text?, detail? }.
func completions(path: String, text: String, offset: int) -> Array:
	var entry := _ensure_doc(path, text)
	var vbyte := _to_virtual_byte(entry, offset)
	if vbyte < 0:
		return []
	return _az.completions(str(entry["uri"]), vbyte)

## Hover at `offset`: { ty_label, doc, offset, length } (guitkx coords), or {}.
func hover(path: String, text: String, offset: int) -> Dictionary:
	var entry := _ensure_doc(path, text)
	var vbyte := _to_virtual_byte(entry, offset)
	if vbyte < 0:
		return {}
	var h: Variant = _az.hover(str(entry["uri"]), vbyte)
	if not (h is Dictionary):
		return {}
	var hd := h as Dictionary
	var out := { "ty_label": str(hd.get("ty_label", "")), "doc": str(hd.get("doc", "")) }
	var mapped := _range_to_guitkx(entry, hd.get("range", {}) as Dictionary)
	if not mapped.is_empty():
		out["offset"] = mapped["offset"]
		out["length"] = mapped["length"]
	return out

## Signature help at `offset`: the analyzer's { signatures, active_signature, active_parameter }
## passthrough (labels are text — nothing to remap), or {}.
func signature_help(path: String, text: String, offset: int) -> Dictionary:
	var entry := _ensure_doc(path, text)
	var vbyte := _to_virtual_byte(entry, offset)
	if vbyte < 0:
		return {}
	var s: Variant = _az.signature_help(str(entry["uri"]), vbyte)
	return s as Dictionary if s is Dictionary else {}

## Definitions of the symbol at `offset`. Each hit: { "path": String, "offset": int } — `path` is
## the .guitkx itself (virtual hits remapped) or a real res://*.gd (byte offset converted against
## that file's text). Hits into virtual glue (hook stubs) resolve to the REAL hooks.gd when
## possible via the stub's name — else they are dropped.
func goto_definition(path: String, text: String, offset: int) -> Array:
	var entry := _ensure_doc(path, text)
	var vbyte := _to_virtual_byte(entry, offset)
	if vbyte < 0:
		return []
	var out: Array = []
	for t in _az.goto_definition(str(entry["uri"]), vbyte):
		var td := t as Dictionary
		var target_uri := str(td.get("uri", ""))
		var rng := td.get("focus_range", td.get("full_range", {})) as Dictionary
		if target_uri == str(entry["uri"]):
			var mapped := _range_to_guitkx(entry, rng)
			if not mapped.is_empty():
				out.append({ "path": path, "offset": int(mapped["offset"]) })
			continue
		if target_uri.begins_with("res://"):
			var ftext := FileAccess.get_file_as_string(target_uri)
			out.append({
				"path": target_uri,
				"offset": LineIndexScript.byte_to_char(ftext, int(rng.get("start", 0))),
			})
	return out

## References to the symbol at `offset`. Each: { "path", "offset" } in the same shape as
## goto_definition. Virtual-glue references are dropped.
func find_references(path: String, text: String, offset: int) -> Array:
	var entry := _ensure_doc(path, text)
	var vbyte := _to_virtual_byte(entry, offset)
	if vbyte < 0:
		return []
	var out: Array = []
	for r in _az.find_references(str(entry["uri"]), vbyte):
		var rd := r as Dictionary
		var target_uri := str(rd.get("uri", ""))
		var rng := rd.get("range", rd.get("focus_range", {})) as Dictionary
		if target_uri == str(entry["uri"]):
			var mapped := _range_to_guitkx(entry, rng)
			if not mapped.is_empty():
				out.append({ "path": path, "offset": int(mapped["offset"]) })
		elif target_uri.begins_with("res://"):
			var ftext := FileAccess.get_file_as_string(target_uri)
			out.append({
				"path": target_uri,
				"offset": LineIndexScript.byte_to_char(ftext, int(rng.get("start", 0))),
			})
	return out

## Rename the EMBEDDED symbol at `offset` to `new_name`, scoped to spans that map back into THIS
## .guitkx buffer: { "ok": true, "edits": [{ "offset", "length", "new_text" }] } (descending
## offsets, ready to splice), or { "ok": false, "reason": String }. Cross-file edits are refused
## (a .guitkx-local symbol never legitimately renames a real .gd from here).
func rename(path: String, text: String, offset: int, new_name: String) -> Dictionary:
	var entry := _ensure_doc(path, text)
	var vbyte := _to_virtual_byte(entry, offset)
	if vbyte < 0:
		return { "ok": false, "reason": "not inside embedded GDScript" }
	var r: Variant = _az.rename(str(entry["uri"]), vbyte, new_name)
	if not (r is Dictionary):
		return { "ok": false, "reason": "analyzer returned no result" }
	var rd := r as Dictionary
	if rd.has("error"):
		return { "ok": false, "reason": JSON.stringify(rd["error"]) }
	var edits: Array = []
	for fe in (rd.get("ok", {}) as Dictionary).get("edits", []):
		var fed := fe as Dictionary
		var target_uri := str(fed.get("uri", ""))
		if target_uri != str(entry["uri"]):
			return { "ok": false, "reason": "rename would touch %s — out of buffer scope" % target_uri }
		for e in fed.get("edits", []):
			var edict := e as Dictionary
			var mapped := _range_to_guitkx(entry, edict.get("range", {}) as Dictionary)
			if mapped.is_empty():
				return { "ok": false, "reason": "rename touches virtual glue" }
			edits.append({
				"offset": int(mapped["offset"]), "length": int(mapped["length"]),
				"new_text": str(edict.get("new_text", edict.get("text", new_name))),
			})
	if edits.is_empty():
		return { "ok": false, "reason": "nothing to rename here" }
	edits.sort_custom(func(a, b): return int(a["offset"]) > int(b["offset"]))
	return { "ok": true, "edits": edits }

## Analyzer diagnostics for the buffer, remapped into .guitkx coords and shaped for the editor's
## renderer: { code, severity:int (RUIGuitkxDiag tiers), message, offset, length }. Entries whose
## range lands in virtual glue are dropped — scaffolding can never squiggle user code.
func diagnostics(path: String, text: String) -> Array:
	var entry := _ensure_doc(path, text)
	var out: Array = []
	for d in _az.diagnostics(str(entry["uri"])):
		var dd := d as Dictionary
		var mapped := _range_to_guitkx(entry, dd.get("range", {}) as Dictionary)
		if mapped.is_empty():
			continue
		out.append({
			"code": "GD:%s" % str(dd.get("code", "")),
			"severity": _severity_to_tier(str(dd.get("severity", "error"))),
			"message": str(dd.get("message", "")),
			"offset": int(mapped["offset"]),
			"length": maxi(1, int(mapped["length"])),
		})
	return out

static func _severity_to_tier(severity: String) -> int:
	match severity:
		"error":
			return RUIGuitkxDiag.ERROR
		"warning":
			return RUIGuitkxDiag.WARNING
		_:
			return RUIGuitkxDiag.HINT
