@tool
extends EditorPlugin
## reactive_ui_toolkit_editor — a main-screen Godot editor for .guitkx files with syntax highlighting and live
## compiler diagnostics. Sibling to the reactive_ui_toolkit runtime addon, which it depends on for the .guitkx
## compiler/formatter (global classes RuitkGuitkx / RuitkGuitkxFormatter).
##
## Lifecycle: registers the reactive_ui_toolkit_editor/* Project Settings and mounts the editor into the
## main screen plus a "Problems" list into the bottom panel. Double-click routing rides the
## GuitkxResourceLoader global class (engine-registered — see the NOTE in _enter_tree) through
## _handles/_edit; the open_guitkx_in_editor toggle is enforced in _handles. Everything mounted
## here is torn down in _exit_tree so a disable/re-enable cycle leaves no orphans.

const PLUGIN_NAME := "ReactiveUITK"
# The Project > Tools item that opens the settings dialog (family design: ONE settings screen
# per leg, opened from the plugin's own menu surface). Same string for add/remove.
const SETTINGS_MENU := "Reactive UI Toolkit Settings..."
const MAIN_MENU_TITLE := "Reactive UI Toolkit"
# The editor's main menu is a MenuBar close under the base control; the cap keeps the search from
# ever crawling the whole editor tree if the layout changes (in which case we fall back anyway).
const _MENU_BAR_SEARCH_DEPTH := 8
# Preload (own addon, dependency-free): fresh class_names are absent from cold class caches.
const Deps := preload("res://addons/reactive_ui_toolkit_editor/ruitk_editor_deps.gd")

# Deliberately untyped (Control/Node): naming GuitkxEditorView here would chain-compile the whole
# editor layer — and its RuitkGuitkx* references — at plugin load, turning a missing reactive_ui_toolkit
# into a raw script error instead of the friendly dependency message below (S1/S2/F9).
var _view: Control
var _problems: Control
var _problems_button: Button
var _references: Control
var _search: Control
var _fs_debounce: Timer
var _settings_dialog: AcceptDialog  # lazy; shared by the menu entries and the toolbar button
var _main_menu: PopupMenu = null  # top-level "Reactive UI Toolkit" menu; null when on the fallback
var _tools_fallback := false  # true when the Project > Tools item was registered instead
var _deps_ok := false

func _enter_tree() -> void:
	# Dependency handshake FIRST — nothing that references reactive_ui_toolkit classes loads before this.
	var check: Dictionary = Deps.satisfied()
	_deps_ok = bool(check.get("ok", false))
	if not _deps_ok:
		push_error("[reactive_ui_toolkit_editor] disabled: " + str(check.get("reason", "")))
		var dlg := AcceptDialog.new()
		dlg.title = "Reactive UI Toolkit — Godot Editor"
		dlg.dialog_text = str(check.get("reason", ""))
		dlg.confirmed.connect(dlg.queue_free)
		dlg.canceled.connect(dlg.queue_free)
		EditorInterface.get_base_control().add_child(dlg)
		dlg.popup_centered()
		return

	RuitkEditorSettings.register_all()
	# Also seed the RUNTIME addon's reactive_ui_toolkit/* settings — many users enable only this
	# editor plugin; registration is idempotent so double-registration with the runtime plugin is
	# harmless. load()-indirected (never naming RuitkSettings here): plugin.gd must stay compilable
	# with the reactive_ui_toolkit addon absent so the W5 dependency dialog can show, and an older
	# runtime without core/settings.gd is tolerated via the file_exists guard.
	if Engine.is_editor_hint() and FileAccess.file_exists("res://addons/reactive_ui_toolkit/core/settings.gd"):
		var runtime_settings: GDScript = load("res://addons/reactive_ui_toolkit/core/settings.gd")
		if runtime_settings != null:
			runtime_settings.register()
	_register_searchable_extension()

	# ONE settings screen per leg (family design), reachable from a top-level "Reactive UI
	# Toolkit" menu in the editor's main menu bar — the same surface the Unity and Unreal legs
	# use. Godot has no official API for a top-level menu, so this injects a PopupMenu into the
	# editor's MenuBar (a documented MenuBar behavior; only FINDING the bar relies on editor
	# internals). If the bar isn't found the entry degrades to Project > Tools — the worst case
	# on any future Godot is "the menu moved", never "the menu is gone". The main-screen
	# toolbar's Settings button (connected below) opens the SAME dialog instance either way.
	# The dialog itself is sectioned per addon: Runtime (from the reactive_ui_toolkit addon,
	# when installed) and Editor (this addon), so settings come from both without requiring both.
	_register_settings_menu()

	# M3: announce the native analyzer once per session — embedded-GDScript intelligence
	# (type-aware completion/hover/diagnostics inside {expr} and setup code) turns on when the
	# reactive_ui_toolkit_analyzer GDExtension is loaded. Since 0.6.1 the editor download BUNDLES it, so
	# absence is unusual (folder removed, or no prebuilt binary for this platform) — note it
	# softly: markup-only stays a fully-supported baseline, not an error state.
	var bridge_script: GDScript = load("res://addons/reactive_ui_toolkit_editor/lsp/guitkx_analyzer_bridge.gd")
	if bridge_script != null and bool(bridge_script.available()):
		print_rich("[color=green][reactive_ui_toolkit_editor] native analyzer %s detected — embedded GDScript intelligence ON.[/color]" % str(bridge_script.native_version()))
	else:
		print_rich("[color=yellow][reactive_ui_toolkit_editor] native analyzer not loaded — embedded-GDScript intelligence off; markup features are unaffected. The editor download bundles it at addons/reactive_ui_toolkit_analyzer; if that folder exists, your platform may lack a prebuilt binary (see its README).[/color]")

	_view = load("res://addons/reactive_ui_toolkit_editor/editor/guitkx_editor_view.gd").new()
	_view.settings_requested.connect(_open_settings_dialog)
	EditorInterface.get_editor_main_screen().add_child(_view)
	_make_visible(false)

	_problems = load("res://addons/reactive_ui_toolkit_editor/editor/guitkx_problems_panel.gd").new()
	_view.set_problems_panel(_problems)
	_problems.diagnostic_activated.connect(_on_problem_activated)
	_problems.location_activated.connect(_on_reference_activated)
	_problems_button = add_control_to_bottom_panel(_problems, "Problems")

	# References results (Shift+F12) get their own bottom panel so the diagnostics refresh can
	# never clobber a result list mid-read (G2).
	_references = load("res://addons/reactive_ui_toolkit_editor/editor/guitkx_references_panel.gd").new()
	_references.location_activated.connect(_on_reference_activated)
	add_control_to_bottom_panel(_references, "References")
	_view.references_requested.connect(_on_references_requested)

	# Project-wide .guitkx search (the addon-native replacement promised when E18 stripped our
	# extension from Godot's Search in Files — see _register_searchable_extension).
	_search = load("res://addons/reactive_ui_toolkit_editor/editor/guitkx_search_panel.gd").new()
	_search.location_activated.connect(_on_reference_activated)
	add_control_to_bottom_panel(_search, "Search .guitkx")

	# Follow the open file through dock renames/moves/deletes (parity plan L1/L2) — otherwise the
	# view's path goes stale and Save resurrects the old filename with the user's edits in it.
	var dock := EditorInterface.get_file_system_dock()
	dock.files_moved.connect(_on_file_moved)
	dock.folder_moved.connect(_on_folder_moved)
	dock.file_removed.connect(_on_file_removed)
	dock.folder_removed.connect(_on_folder_removed)

	# Keep the component index + cross-file bindings fresh when the filesystem shape changes
	# (external creates/renames/deletes — G15/P2). Debounced: filesystem_changed fires in bursts.
	_fs_debounce = Timer.new()
	_fs_debounce.one_shot = true
	_fs_debounce.wait_time = 0.5
	_fs_debounce.timeout.connect(_on_fs_settled)
	add_child(_fs_debounce)
	EditorInterface.get_resource_filesystem().filesystem_changed.connect(_on_fs_changed)

	# NOTE: the GuitkxResourceLoader is NOT registered here. It carries a class_name, so the
	# ENGINE registers it — and, critically, re-adds it after every script-reload cycle (the
	# engine drops all custom loaders on reload and re-adds only global-class ones; a manually
	# added instance silently dies on the first reload after boot). The open_guitkx_in_editor
	# toggle is enforced in _handles() below instead.

func _exit_tree() -> void:
	if not _deps_ok:
		return
	if _tools_fallback:
		remove_tool_menu_item(SETTINGS_MENU)
		_tools_fallback = false
	if _main_menu != null:
		_main_menu.queue_free()  # detaches from the MenuBar; disabling the plugin removes the menu
		_main_menu = null
	if _settings_dialog != null:
		_settings_dialog.queue_free()
		_settings_dialog = null
	var efs := EditorInterface.get_resource_filesystem()
	if efs.filesystem_changed.is_connected(_on_fs_changed):
		efs.filesystem_changed.disconnect(_on_fs_changed)
	var dock := EditorInterface.get_file_system_dock()
	if dock.files_moved.is_connected(_on_file_moved):
		dock.files_moved.disconnect(_on_file_moved)
	if dock.folder_moved.is_connected(_on_folder_moved):
		dock.folder_moved.disconnect(_on_folder_moved)
	if dock.file_removed.is_connected(_on_file_removed):
		dock.file_removed.disconnect(_on_file_removed)
	if dock.folder_removed.is_connected(_on_folder_removed):
		dock.folder_removed.disconnect(_on_folder_removed)
	if _problems != null:
		remove_control_from_bottom_panel(_problems)
		_problems.queue_free()
		_problems = null
	if _references != null:
		remove_control_from_bottom_panel(_references)
		_references.queue_free()
		_references = null
	if _search != null:
		remove_control_from_bottom_panel(_search)
		_search.queue_free()
		_search = null
	_problems_button = null
	if _view != null:
		_view.queue_free()
		_view = null

## Lazy singleton behind both entry points (the Tools menu item and the toolbar's Settings
## button). load()-by-path — the dialog carries no class_name, so the file needs no class-cache
## rescan; the dialog itself rebuilds from ProjectSettings on every about_to_popup.
func _open_settings_dialog() -> void:
	if _settings_dialog == null:
		_settings_dialog = load("res://addons/reactive_ui_toolkit_editor/editor/ruitk_settings_dialog.gd").new()
		EditorInterface.get_base_control().add_child(_settings_dialog)
	_settings_dialog.popup_centered()

## Top-level "Reactive UI Toolkit" menu, with the Project > Tools item as the automatic fallback
## (see the _enter_tree comment for the design + risk rationale).
func _register_settings_menu() -> void:
	var bar := find_menu_bar(EditorInterface.get_base_control(), _MENU_BAR_SEARCH_DEPTH)
	if bar == null:
		add_tool_menu_item(SETTINGS_MENU, _open_settings_dialog)
		_tools_fallback = true
		print_rich("[color=yellow][reactive_ui_toolkit_editor] main menu bar not found — Settings lives under Project > Tools on this Godot build.[/color]")
		return
	_main_menu = PopupMenu.new()
	# MenuBar renders each child PopupMenu as a top-level menu titled by its node name.
	_main_menu.name = MAIN_MENU_TITLE
	_main_menu.add_item("Settings...", 0)
	_main_menu.id_pressed.connect(_on_main_menu_pressed)
	bar.add_child(_main_menu)

func _on_main_menu_pressed(id: int) -> void:
	if id == 0:
		_open_settings_dialog()

## Breadth-limited search for the editor's main MenuBar. Static and depth-capped on purpose:
## testable headless with a synthetic tree, and it can never crawl the whole editor UI — if the
## bar is not shallow where we expect it, we WANT the null so the Tools fallback engages.
static func find_menu_bar(node: Node, depth_budget: int) -> MenuBar:
	if node is MenuBar:
		return node
	if depth_budget <= 0:
		return null
	for child in node.get_children():
		var found := find_menu_bar(child, depth_budget - 1)
		if found != null:
			return found
	return null

## Godot asks every plugin for unsaved state before quitting: a non-empty string joins the editor's
## own quit-confirmation dialog (parity plan L4 — without this, quit silently drops buffers).
func _get_unsaved_status(for_scene: String) -> String:
	if for_scene.is_empty() and _view != null:
		var dirty: Array = _view.dirty_files()
		if not dirty.is_empty():
			return "Reactive UI Toolkit — Godot Editor: unsaved changes in %s." % ", ".join(dirty)
	return ""

## Session persistence across editor restarts (G17): open files, current tab, carets, zoom, wrap
## ride Godot's own editor-layout store.
func _get_window_layout(configuration: ConfigFile) -> void:
	if _view != null:
		configuration.set_value(PLUGIN_NAME, "session", _view.session_state())

func _set_window_layout(configuration: ConfigFile) -> void:
	if _view != null and configuration.has_section_key(PLUGIN_NAME, "session"):
		_view.restore_session(configuration.get_value(PLUGIN_NAME, "session"))

## Godot's own save flows (Save All, save-on-quit confirm) flush our buffer as "external data".
func _save_external_data() -> void:
	if _view != null:
		_view.save_silent()

## Called when the user hits Play: flush the buffer first so the game runs what's on screen (the
## watcher then recompiles the sibling .gd before launch).
func _apply_changes() -> void:
	if _view != null:
		_view.save_silent()

func _on_file_moved(old_file: String, new_file: String) -> void:
	cleanup_moved_guitkx(old_file, new_file)
	if _view != null:
		_view.retarget_path(new_file, old_file)

## A dock rename/move of a .guitkx leaves its generated outputs (.gd/.uid/sidecar) under the OLD
## name until the watcher's next sweep (~2s) — long enough for rapid renames to stack multiple
## generated files declaring the SAME class_name, which wounds Godot's global class registry
## [field capture: "after 1-2 renames it breaks — the .gd files stay behind"]. Clean the old
## name's outputs synchronously in the rename event and nudge the new name toward compilation.
##
## Static + load()-indirected (never naming RuitkGuitkx* here): plugin.gd must stay compilable
## with the reactive_ui_toolkit addon absent so the W5 dependency dialog can show.
static func cleanup_moved_guitkx(old_source: String, new_source: String = "") -> void:
	if old_source.get_extension().to_lower() != "guitkx":
		return
	if not FileAccess.file_exists("res://addons/reactive_ui_toolkit/guitkx/guitkx_codegen.gd"):
		return
	var codegen: GDScript = load("res://addons/reactive_ui_toolkit/guitkx/guitkx_codegen.gd")
	var old_gd: String = codegen.gd_path_for(old_source)
	# Reuse the sweep's own orphan test (AUTO-GENERATED header + source gone) so hand-written
	# .gd files stay untouchable here exactly as they are in the watcher.
	if FileAccess.file_exists(old_gd) and codegen._is_orphaned_output(old_gd, {}):
		codegen._remove_orphaned_output(old_gd)
	else:
		# Never compiled (or already swept): still drop a stale sidecar left under the old name.
		var sidecar := old_source + ".diags.json"
		if FileAccess.file_exists(sidecar):
			DirAccess.remove_absolute(sidecar)
	if new_source != "" and Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().update_file(new_source)

func _on_folder_moved(old_folder: String, new_folder: String) -> void:
	if _view == null:
		return
	var prefix := old_folder if old_folder.ends_with("/") else old_folder + "/"
	var dst := new_folder if new_folder.ends_with("/") else new_folder + "/"
	for p in _view.open_paths():
		if str(p).begins_with(prefix):
			_view.retarget_path(dst + str(p).substr(prefix.length()), str(p))

func _on_file_removed(file: String) -> void:
	if _view != null:
		_view.mark_detached(file)

func _on_folder_removed(folder: String) -> void:
	if _view == null:
		return
	var prefix := folder if folder.ends_with("/") else folder + "/"
	for p in _view.open_paths():
		if str(p).begins_with(prefix):
			_view.mark_detached(str(p))

func _on_fs_changed() -> void:
	if _fs_debounce != null and _fs_debounce.is_inside_tree():
		_fs_debounce.start()

func _on_fs_settled() -> void:
	GuitkxWorkspace.rescan()
	if _view != null:
		_view.on_workspace_changed()

func _has_main_screen() -> bool:
	return true

func _get_plugin_name() -> String:
	return PLUGIN_NAME

func _get_plugin_icon() -> Texture2D:
	var t := EditorInterface.get_editor_theme()
	if t != null and t.has_icon("Script", "EditorIcons"):
		return t.get_icon("Script", "EditorIcons")
	return null

func _make_visible(visible: bool) -> void:
	if _view != null:
		_view.visible = visible

func _handles(object: Object) -> bool:
	# The toggle lives HERE (the loader itself is engine-owned and always registered): with
	# open_guitkx_in_editor off, we decline and the double-click lands in the Inspector.
	return object is GuitkxResource and RuitkEditorSettings.is_enabled(RuitkEditorSettings.KEY_OPEN_IN_EDITOR)

func _edit(object: Object) -> void:
	if object == null:
		return
	if object is GuitkxResource:
		EditorInterface.set_main_screen_editor(PLUGIN_NAME)
		_make_visible(true)
		if _view != null:
			_view.open_resource(object)

## REVERSAL of the earlier E18 registration, and it must stay a reversal: listing "guitkx" in
## docks/filesystem/textfile_extensions let Godot's built-in Script editor adopt .guitkx files
## whenever our routing was momentarily down — and the Script editor persists its adoptees in
## THREE places (script_editor_cache.cfg, editor_layout.cfg open_scripts, project_metadata.cfg
## history), each replaying as a boot error ('Parameter "seb" is null': it restores the entry,
## then can't build a text editor for what is now a GuitkxResource). Actively STRIP the
## extension so the Script editor is structurally unable to touch .guitkx. Trade-off: Godot's
## Search in Files no longer sees .guitkx — replaced by the addon's own project search (M2).
func _register_searchable_extension() -> void:
	var es := EditorInterface.get_editor_settings()
	if es == null:
		return
	var key := "docks/filesystem/textfile_extensions"
	var cur: String = str(es.get_setting(key))
	var parts: Array = Array(cur.split(",", false))
	if parts.has("guitkx"):
		parts.erase("guitkx")
		es.set_setting(key, ",".join(PackedStringArray(parts)))

func _on_references_requested(tag: String, records: Array) -> void:
	if _references == null:
		return
	_references.show_references(tag, records)
	make_bottom_panel_item_visible(_references)

func _on_reference_activated(path: String, line: int) -> void:
	EditorInterface.set_main_screen_editor(PLUGIN_NAME)
	_make_visible(true)
	if _view != null:
		_view.open_path(path)
		_view.goto_line(line)

func _on_problem_activated(line: int) -> void:
	EditorInterface.set_main_screen_editor(PLUGIN_NAME)
	_make_visible(true)
	if _view != null:
		_view.goto_line(line)
