extends SceneTree
## 0.13.0 rebrand codemod (SHIPPED with the addon, like dev/migrate_0_11_0.gd): rewrite YOUR
## project for the "Reactive UI Toolkit" rename. Zero behavior changes -- names only:
##   (a) every renamed global class spelling, whole-word (RUIVNode -> RuitkVNode,
##       ReactiveRoot -> RuitkRoot, ReactiveRootNode -> RuitkRootNode, ... 36 pairs; `V` and
##       `Hooks` are unchanged) across `.guitkx` and hand-written `.gd`;
##   (b) every addon folder path (addons/reactive_ui -> addons/reactive_ui_toolkit,
##       addons/reactive_ui_editor -> addons/reactive_ui_toolkit_editor,
##       addons/reactive_ui_analyzer -> addons/reactive_ui_toolkit_analyzer) across `.gd`,
##       `.guitkx`, `.tscn`, `.tres`, and project.godot's enabled= plugin list.
## Idempotent + re-runnable (a second run reports 0). Run once after updating the addons:
##   godot --headless --path . --script res://addons/reactive_ui_toolkit/dev/migrate_0_13_0.gd
## The codemod never edits inside addons/ itself (update the addons from the store/release
## zips instead). Store updates never DELETE old folders: after migrating, delete the old
## addons/reactive_ui, addons/reactive_ui_editor, and addons/reactive_ui_analyzer folders by
## hand -- duplicate global class_name parse errors are the symptom of skipping that step.
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

## Folder renames -- _editor/_analyzer first; the \b guard keeps the bare form from ever
## matching inside an already-migrated `reactive_ui_toolkit*` path (idempotency).
const PATH_RENAMES: Array = [
	["addons/reactive_ui_editor", "addons/reactive_ui_toolkit_editor"],
	["addons/reactive_ui_analyzer", "addons/reactive_ui_toolkit_analyzer"],
	["addons/reactive_ui", "addons/reactive_ui_toolkit"],
]

## Extensions the codemod rewrites. Class renames apply to code files only; path renames
## apply to all of them (+ project.godot, handled separately in migrate_all).
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
	# project.godot: path renames only -- rewrites the enabled= plugin list (and any other
	# addon-path reference the project file carries).
	var pg := root.path_join("project.godot")
	if FileAccess.file_exists(pg):
		scanned += 1
		var row := _migrate_file(pg, rules, false)
		if int(row["count"]) > 0:
			changed.append(row)
	return {"scanned": scanned, "changed": changed}

static func _compile_rules() -> Dictionary:
	return {
		"classes": _compile_pairs(CLASS_RENAMES),
		"paths": _compile_pairs(PATH_RENAMES),
	}

static func _compile_pairs(pairs: Array) -> Array:
	var out: Array = []
	for pair in pairs:
		var re := RegEx.new()
		re.compile("\\b%s\\b" % pair[0])
		out.append([re, pair[1]])
	return out

static func _migrate_file(path: String, rules: Dictionary, with_classes: bool) -> Dictionary:
	var src := FileAccess.get_file_as_string(path)
	var text := src
	var count := 0
	if with_classes:
		var res_c := _apply(text, rules["classes"])
		text = res_c["text"]
		count += int(res_c["count"])
	var res_p := _apply(text, rules["paths"])
	text = res_p["text"]
	count += int(res_p["count"])
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
