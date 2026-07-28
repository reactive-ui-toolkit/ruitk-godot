extends SceneTree
## 0.13.0 rebrand codemod (SHIPPED with the addon, like dev/migrate_0_11_0.gd): rewrite YOUR
## project for the "Reactive UI Toolkit" rename. Zero behavior changes -- names only:
##   (a) every renamed global class spelling, whole-word (RUIVNode -> RuitkVNode,
##       ReactiveRoot -> RuitkRoot, ReactiveRootNode -> RuitkRootNode, ... 36 pairs; `V` and
##       `Hooks` are unchanged) across `.guitkx` and hand-written `.gd`;
##   (b) every addon folder path (addons/reactive_ui -> addons/reactive_ui_toolkit,
##       addons/reactive_ui_editor -> addons/reactive_ui_toolkit_editor,
##       addons/reactive_ui_analyzer -> addons/reactive_ui_toolkit_analyzer) across `.gd`,
##       `.guitkx`, `.tscn`, `.tres`, and project.godot's enabled= plugin list;
##   (c) the editor addon's ProjectSettings section in project.godot ([reactive_ui_editor] ->
##       [reactive_ui_toolkit_editor]), so the toggles you turned OFF stay off after upgrading.
## Idempotent + re-runnable (a second run reports 0). Run once after updating the addons:
##   godot --headless --path . --script res://addons/reactive_ui_toolkit/dev/migrate_0_13_0.gd
## The codemod never edits inside addons/ itself (update the addons from the store/release
## zips instead). Store updates never DELETE old folders: after migrating, delete the old
## addons/reactive_ui, addons/reactive_ui_editor, and addons/reactive_ui_analyzer folders by
## hand -- the symptom of skipping that step is a scan full of "UID duplicate detected between
## res://addons/reactive_ui_toolkit/core/<f>.gd and res://addons/reactive_ui/core/<f>.gd"
## warnings (the new addon silently wins the global class names; the stale copy just lingers).
## See MIGRATION-0.13.md for the full guide.

## The 36 whole-word class renames of the 0.13.0 wave (34 RUI* classes + the two mount
## surfaces). Longest-first within each family so prefixes can never shadow.
const CLASS_RENAMES: Array = [
	["RUIGuitkxCodegen", "RuitkGuitkxCodegen"],
	["RUIGuitkxFormatter", "RuitkGuitkxFormatter"],
	["RUIGuitkxResolve", "RuitkGuitkxResolve"],
	["RUIGuitkxMigrate", "RuitkGuitkxMigrate"],
	["RUIGuitkxMarkup", "RuitkGuitkxMarkup"],
	["RUIGuitkxJsxScan", "RuitkGuitkxJsxScan"],
	["RUIGuitkxLexer", "RuitkGuitkxLexer"],
	["RUIGuitkxConfig", "RuitkGuitkxConfig"],
	["RUIGuitkxDiag", "RuitkGuitkxDiag"],
	["RUIGuitkx", "RuitkGuitkx"],
	["RUIRouterLocation", "RuitkRouterLocation"],
	["RUIRouterPath", "RuitkRouterPath"],
	["RUIRouteMatcher", "RuitkRouteMatcher"],
	["RUIRouteRanker", "RuitkRouteRanker"],
	["RUIRouteMatch", "RuitkRouteMatch"],
	["RUIRouter", "RuitkRouter"],
	["RUIStyleSheet", "RuitkStyleSheet"],
	["RUIStyle", "RuitkStyle"],
	["RUISignals", "RuitkSignals"],
	["RUISignal", "RuitkSignal"],
	["RUIComponentState", "RuitkComponentState"],
	["RUIEditorSettings", "RuitkEditorSettings"],
	["RUIEditorDeps", "RuitkEditorDeps"],
	["RUIConfig", "RuitkConfig"],
	["RUIContext", "RuitkContext"],
	["RUIDiagnostics", "RuitkDiagnostics"],
	["RUIFiber", "RuitkFiber"],
	["RUIHistory", "RuitkHistory"],
	["RUIHmr", "RuitkHmr"],
	["RUIHost", "RuitkHost"],
	["RUIMedia", "RuitkMedia"],
	["RUIReconciler", "RuitkReconciler"],
	["RUISuspense", "RuitkSuspense"],
	["RUIVNode", "RuitkVNode"],
	["ReactiveRootNode", "RuitkRootNode"],
	["ReactiveRoot", "RuitkRoot"],
]

## Folder renames -- _editor/_analyzer first; the trailing \b guard keeps the bare form from
## ever matching inside an already-migrated `reactive_ui_toolkit*` path (idempotency), and the
## leading anchor (see _compile_paths) keeps it out of `user://` / URL contexts.
const PATH_RENAMES: Array = [
	["addons/reactive_ui_editor", "addons/reactive_ui_toolkit_editor"],
	["addons/reactive_ui_analyzer", "addons/reactive_ui_toolkit_analyzer"],
	["addons/reactive_ui", "addons/reactive_ui_toolkit"],
]

## project.godot ProjectSettings section renames. The editor addon's settings group moved with
## the folder (`reactive_ui_editor/*` -> `reactive_ui_toolkit_editor/*`), and these keys are
## PERSISTED in the user's project.godot ("settings live in project.godot, so they travel with
## the project"). Without this rule every feature the user switched OFF -- format_on_save,
## diagnostics_enabled, ... -- silently comes back ON after upgrading, and the dead section
## lingers in the project file forever.
const SECTION_RENAMES: Array = [
	["reactive_ui_editor", "reactive_ui_toolkit_editor"],
]

## Extensions the codemod rewrites. Class renames apply to code files only (plus `script_class=`
## inside scene/resource files); path renames apply to all of them (+ project.godot, which also
## gets the section renames -- handled separately in migrate_all).
const CODE_EXTS: Array = ["gd", "guitkx"]
const SCENE_EXTS: Array = ["tscn", "tres"]

func _initialize() -> void:
	var res := migrate_all("res://")
	var changed: Array = res["changed"]
	print("[migrate_0_13_0] scanned %d file(s), migrated %d" % [int(res["scanned"]), changed.size()])
	for row in changed:
		print("    migrated  %s (%d change(s))" % [row["path"], int(row["count"])])
	quit(0)

## Rewrite every eligible file under `root` (+ root's project.godot, if present).
## Returns {"scanned": int, "changed": [{"path": String, "count": int}, ...]}.
static func migrate_all(root: String = "res://") -> Dictionary:
	var rules := _compile_rules()
	var files: Array = []
	_walk(root, files)
	var scanned := 0
	var changed: Array = []
	for path in files:
		scanned += 1
		var ext: String = path.get_extension().to_lower()
		var with_classes: bool = ext in CODE_EXTS
		var row := _migrate_file(path, rules, with_classes)
		if int(row["count"]) > 0:
			changed.append(row)
	# project.godot: path renames (the enabled= plugin list and any other addon-path reference
	# the project file carries) + the ProjectSettings section renames. No class renames.
	var pg := root.path_join("project.godot")
	if FileAccess.file_exists(pg):
		scanned += 1
		var row := _migrate_file(pg, rules, false, true)
		if int(row["count"]) > 0:
			changed.append(row)
	return {"scanned": scanned, "changed": changed}

static func _compile_rules() -> Dictionary:
	return {
		"classes": _compile_words(CLASS_RENAMES),
		"paths": _compile_paths(PATH_RENAMES),
		"script_class": _compile_script_class(CLASS_RENAMES),
	}

## Whole-word identifier rules (class renames): `\bName\b`.
static func _compile_words(pairs: Array) -> Array:
	var out: Array = []
	for pair in pairs:
		var re := RegEx.new()
		re.compile("\\b%s\\b" % pair[0])
		out.append([re, pair[1]])
	return out

## Folder-path rules. The literal alone is too loose -- `addons/reactive_ui` also occurs inside
## `user://` data paths and in URLs, and the codemod writes files in place. So the match must sit
## at a path root we recognise: straight after `res://`, straight after a `./` or `../` segment,
## or at a boundary that is not part of a longer path/scheme at all (start of line, after a quote,
## `=`, `(`, whitespace, ...). `user://addons/reactive_ui`, `https://host/x/addons/reactive_ui`
## and `myaddons/reactive_ui` therefore no longer match. Zero-width lookbehinds, so the
## replacement stays a plain literal.
static func _compile_paths(pairs: Array) -> Array:
	var out: Array = []
	for pair in pairs:
		var re := RegEx.new()
		re.compile("(?:(?<=res://)|(?<=\\./)|(?<![A-Za-z0-9_:/.]))%s\\b" % pair[0])
		out.append([re, pair[1]])
	return out

## Scene/resource files carry a global class NAME in exactly one place: the `script_class="..."`
## attribute Godot writes for a script-backed Resource (packed scenes reference node scripts by
## path only). Rewriting just that attribute closes the gap without touching arbitrary string
## content inside a scene. Latent today -- all 36 renamed classes are RefCounted, so none can be
## saved as a .tres -- but it stops silently under-migrating the moment one becomes a Resource.
static func _compile_script_class(pairs: Array) -> Array:
	var out: Array = []
	for pair in pairs:
		var re := RegEx.new()
		re.compile("script_class=\"%s\"" % pair[0])
		out.append([re, "script_class=\"%s\"" % pair[1]])
	return out

static func _migrate_file(path: String, rules: Dictionary, with_classes: bool, with_sections: bool = false) -> Dictionary:
	var src := FileAccess.get_file_as_string(path)
	var text := src
	var count := 0
	if with_classes:
		var res_c := _apply(text, rules["classes"])
		text = res_c["text"]
		count += int(res_c["count"])
	else:
		var res_sc := _apply(text, rules["script_class"])
		text = res_sc["text"]
		count += int(res_sc["count"])
	var res_p := _apply(text, rules["paths"])
	text = res_p["text"]
	count += int(res_p["count"])
	if with_sections:
		var res_s := _migrate_sections(text)
		text = res_s["text"]
		count += int(res_s["count"])
	if count > 0 and text != src:
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string(text)
		f.close()
	return {"path": path, "count": count}

static func _apply(text: String, compiled: Array) -> Dictionary:
	var count := 0
	for rule in compiled:
		var re: RegEx = rule[0]
		var hits := re.search_all(text)
		if hits.size() > 0:
			count += hits.size()
			text = re.sub(text, rule[1], true)
	return {"text": text, "count": count}

## Rename project.godot's persisted ProjectSettings sections (SECTION_RENAMES). Not a plain
## text substitution, because the destination section may ALREADY exist: if the user re-enabled
## the 0.11.0 editor plugin before running the codemod, register_all() will have written a fresh
## `[reactive_ui_toolkit_editor]` block full of defaults. So: lift the old block out, and on a
## collision keep the OLD values (they are the user's actual pre-upgrade choices) while carrying
## over any key only the new block has. Idempotent -- with no old section present, count is 0.
static func _migrate_sections(text: String) -> Dictionary:
	var count := 0
	for pair in SECTION_RENAMES:
		var old_cut := _cut_section(text, pair[0])
		if not bool(old_cut["found"]):
			continue
		count += 1
		text = old_cut["text"]
		var body: String = old_cut["body"]
		var new_cut := _cut_section(text, pair[1])
		if bool(new_cut["found"]):
			body = _merge_ini_bodies(body, new_cut["body"])
			text = new_cut["text"]
		text = text.rstrip("\n") + "\n\n[%s]\n%s\n" % [pair[1], body.strip_edges()]
	return {"text": text, "count": count}

## Lift `[name]` (header + body, up to the next section header or EOF) out of an ini-style text.
## Returns {"found": bool, "body": String, "text": String} -- `text` is the input minus the section.
static func _cut_section(text: String, name: String) -> Dictionary:
	var head := RegEx.new()
	head.compile("(?m)^\\[%s\\][ \\t]*\\r?\\n" % name)
	var m := head.search(text)
	if m == null:
		return {"found": false, "body": "", "text": text}
	var body_start := m.get_end()
	var next_head := RegEx.new()
	next_head.compile("(?m)^\\[")
	var nm := next_head.search(text, body_start)
	var body_end: int = nm.get_start() if nm != null else text.length()
	return {
		"found": true,
		"body": text.substr(body_start, body_end - body_start),
		"text": text.substr(0, m.get_start()) + text.substr(body_end),
	}

## Union of two ini section bodies; `primary`'s value wins for any key both declare.
static func _merge_ini_bodies(primary: String, secondary: String) -> String:
	var keys := {}
	for line in primary.split("\n"):
		var k := _ini_key(line)
		if k != "":
			keys[k] = true
	var extra := PackedStringArray()
	for line in secondary.split("\n"):
		var k := _ini_key(line)
		if k != "" and not keys.has(k):
			keys[k] = true
			extra.append(line.strip_edges())
	if extra.is_empty():
		return primary
	return primary.rstrip("\n") + "\n" + "\n".join(extra)

## The `key` of an ini `key=value` line ("" for blanks, comments, and continuation lines).
static func _ini_key(line: String) -> String:
	var t := line.strip_edges()
	if t == "" or t.begins_with(";") or t.begins_with("#") or t.begins_with("["):
		return ""
	var eq := t.find("=")
	return "" if eq <= 0 else t.substr(0, eq).strip_edges()

## Collect every .gd/.guitkx/.tscn/.tres under `dir`, skipping hidden folders (.git/.godot),
## node_modules, and -- deliberately -- any `addons` folder: the codemod migrates YOUR code,
## never the addons themselves (those are replaced by the store/release update).
static func _walk(dir: String, out: Array) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if name.begins_with("."):
			name = d.get_next()
			continue
		var path := dir.path_join(name)
		if d.current_is_dir():
			if name != "addons" and name != "node_modules":
				_walk(path, out)
		else:
			var ext := name.get_extension().to_lower()
			if ext in CODE_EXTS or ext in SCENE_EXTS:
				out.append(path)
		name = d.get_next()
	d.list_dir_end()
