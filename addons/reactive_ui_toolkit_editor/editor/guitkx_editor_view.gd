@tool
class_name GuitkxEditorView
extends Control
## The main-screen panel: a toolbar (Open / Save / Format + current-file label) over a GuitkxCodeEdit.
## Owns the edit -> debounced-compile -> diagnostics pipeline, the buffer's dirty/conflict state, and
## every guard that keeps the user's work safe (unsaved-switch confirms, external-change detection,
## deleted/renamed-source tracking). Depends on the reactive_ui_toolkit addon's global classes RuitkGuitkx
## (compiler) and RuitkGuitkxFormatter (formatter).
##
## Save writes ONLY the .guitkx text to disk; the reactive_ui_toolkit plugin's own filesystem watcher owns
## regenerating the sibling .gd, so the two never fight over the same file.

const MAX_LIVE_COMPILE := 150_000  # chars; above this, compile on Save only. Measured: ~2.1ms/KB on
                                   # the MAIN thread, so 150K ≈ 300ms worst-case stall per pause (P1).
                                   # [G-10 2026-07-10] the unicode_at scanner conversion cut whole-file
                                   # compile ~29% (71.96 -> 51.08ms on the 12.4KB doom component; see
                                   # tests/guitkx_bench.gd), so the worst-case stall shrinks accordingly.
const DEBOUNCE_SEC := 0.3

# Preload (not the global class name): a freshly-added class_name is absent from the global class
# cache on cold checkouts/headless runs, which would fail this whole script's parse.
const FindBarScript := preload("res://addons/reactive_ui_toolkit_editor/editor/guitkx_find_bar.gd")
const ScanDiags := preload("res://addons/reactive_ui_toolkit_editor/lsp/guitkx_scan_diags.gd")
const ConfigScript := preload("res://addons/reactive_ui_toolkit_editor/lsp/guitkx_config.gd")
const RefsScript := preload("res://addons/reactive_ui_toolkit_editor/lsp/guitkx_refs.gd")
const OutlineScript := preload("res://addons/reactive_ui_toolkit_editor/lsp/guitkx_outline.gd")
const BridgeScript := preload("res://addons/reactive_ui_toolkit_editor/lsp/guitkx_analyzer_bridge.gd")

# Multi-file model (M2/G16): ONE GuitkxCodeEdit per open file, stacked with only the current one
# visible — undo history, caret, scroll, decorations, and dirty/conflict state all survive file
# switches for free. `_current` is the active editor; the properties below delegate to it so the
# whole single-buffer pipeline (diagnostics, save, hover, dialogs) reads/writes per-file state
# without knowing about the stack.
var _current: GuitkxCodeEdit
var _editors: Dictionary = {}   # path ("" = the scratch buffer) -> GuitkxCodeEdit
var _editor_stack: Control
var _open_list: ItemList
var _outline: Tree
var _wrap_toggle: CheckBox

var _file_label: Label
var _find_bar: HBoxContainer  # GuitkxFindBar (typed loosely; see FindBarScript note)
var _debounce: Timer
var _problems: GuitkxProblemsPanel
var _err_icon: Texture2D
var _warn_icon: Texture2D

# _loading suppresses the text_changed handler while WE set a buffer (loads, format rewrites),
# so only user edits mark files dirty.
var _loading := false

var _code_edit: GuitkxCodeEdit:
	get:
		return _current
var _current_path: String:
	get:
		return _current.file_path if _current != null else ""
	set(v):
		if _current != null:
			_current.file_path = v
var _dirty: bool:
	get:
		return _current != null and _current.dirty
	set(v):
		if _current != null:
			_current.dirty = v
var _detached: bool:
	get:
		return _current != null and _current.detached
	set(v):
		if _current != null:
			_current.detached = v
var _loaded_mtime: int:
	get:
		return _current.loaded_mtime if _current != null else 0
	set(v):
		if _current != null:
			_current.loaded_mtime = v

# Cross-file compile context (W3, G13/P2): project_bindings() costs ~35ms over ~100 files, so it is
# cached and recomputed only when the filesystem shape changes — never per debounce tick.
var _bindings_cache: Dictionary = {}
var _bindings_valid := false

var _pending_jump_offset := -1  # goto-def target applied once the destination file finishes loading
var _last_compile_ms := 0.0     # drives the adaptive debounce (P1)

# G-06: paths already warned this session that format-on-save/Format fell back to verbatim (a
# syntax error) -- keyed so the modal alert fires once per file, not on every save of the same
# still-broken file.
var _format_fallback_warned: Dictionary = {}


## Toolbar Settings button -> the plugin pops the shared settings dialog (the same instance the
## Project > Tools menu item opens; the view never owns the dialog).
signal settings_requested

func _init() -> void:
	name = "ReactiveUITK"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	var split := HSplitContainer.new()
	split.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	split.split_offset = 180
	add_child(split)

	# Left: the open-files list (script-editor style; click switches, middle-click closes) over
	# the document outline (G12; activate to jump).
	var left := VSplitContainer.new()
	left.custom_minimum_size = Vector2(150, 0)
	left.split_offset = 220
	split.add_child(left)
	_open_list = ItemList.new()
	_open_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_open_list.item_selected.connect(_on_open_list_selected)
	_open_list.item_clicked.connect(_on_open_list_clicked)
	left.add_child(_open_list)
	_outline = Tree.new()
	_outline.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_outline.hide_root = true
	_outline.item_activated.connect(_on_outline_activated)
	left.add_child(_outline)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(vbox)

	var toolbar := HBoxContainer.new()
	vbox.add_child(toolbar)
	toolbar.add_child(_make_button("Open", _on_open_pressed))
	toolbar.add_child(_make_button("New", _on_new_pressed))
	toolbar.add_child(_make_button("Save", _on_save_pressed))
	toolbar.add_child(_make_button("Format", _on_format_pressed))
	_wrap_toggle = CheckBox.new()
	_wrap_toggle.text = "Wrap"
	_wrap_toggle.tooltip_text = "Soft-wrap long lines (E15)"
	_wrap_toggle.toggled.connect(_on_wrap_toggled)
	toolbar.add_child(_wrap_toggle)
	var settings_btn := _make_button("Settings", _on_settings_pressed)
	settings_btn.tooltip_text = "Reactive UI Toolkit settings (also: Project > Tools)"
	toolbar.add_child(settings_btn)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(spacer)
	_file_label = Label.new()
	_file_label.text = "(no file)"
	toolbar.add_child(_file_label)

	_find_bar = FindBarScript.new()
	vbox.add_child(_find_bar)

	_editor_stack = Control.new()
	_editor_stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_editor_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_editor_stack)

	_debounce = Timer.new()
	_debounce.one_shot = true
	_debounce.wait_time = DEBOUNCE_SEC
	_debounce.timeout.connect(_refresh_diagnostics)
	add_child(_debounce)

	# The scratch buffer: always exists so `_current` is never null.
	_switch_to(_ensure_editor(""))

## --- Multi-file plumbing (G16) ---

func _ensure_editor(path: String) -> GuitkxCodeEdit:
	if _editors.has(path):
		return _editors[path]
	var ed := GuitkxCodeEdit.new()
	ed.file_path = path
	ed.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ed.text_changed.connect(_on_editor_text_changed.bind(ed))
	ed.gutter_diagnostic_clicked.connect(_on_gutter_diagnostic_clicked)
	ed.definition_requested.connect(_on_definition_requested)
	ed.visible = false
	ed.apply_zoom()
	if _wrap_toggle != null and _wrap_toggle.button_pressed:
		ed.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_editor_stack.add_child(ed)
	_editors[path] = ed
	var idx := _open_list.add_item(_list_label(ed))
	_open_list.set_item_metadata(idx, path)
	_open_list.set_item_tooltip(idx, path if path != "" else "(scratch buffer)")
	return ed

func _switch_to(ed: GuitkxCodeEdit) -> void:
	if _current == ed:
		return
	if _current != null:
		_current.visible = false
	_current = ed
	ed.visible = true
	_find_bar.attach(ed)
	_update_file_label()
	for i in _open_list.item_count:
		if str(_open_list.get_item_metadata(i)) == ed.file_path:
			_open_list.select(i)
			break
	_refresh_diagnostics()
	if ed.is_inside_tree():
		ed.grab_focus()

func _list_label(ed: GuitkxCodeEdit) -> String:
	var label := ed.file_path.get_file() if ed.file_path != "" else "(scratch)"
	if ed.detached:
		label += " (deleted)"
	if ed.dirty:
		label += " *"
	return label

func _refresh_list_row(ed: GuitkxCodeEdit) -> void:
	for i in _open_list.item_count:
		if str(_open_list.get_item_metadata(i)) == ed.file_path:
			_open_list.set_item_text(i, _list_label(ed))
			return

func _on_open_list_selected(idx: int) -> void:
	var path := str(_open_list.get_item_metadata(idx))
	if _editors.has(path):
		_switch_to(_editors[path])

func _on_open_list_clicked(idx: int, _pos: Vector2, mouse_button: int) -> void:
	if mouse_button == MOUSE_BUTTON_MIDDLE:
		close_file(str(_open_list.get_item_metadata(idx)))

## Close a file (middle-click). Dirty buffers confirm; the last editor standing is the scratch.
func close_file(path: String) -> void:
	if not _editors.has(path):
		return
	var ed: GuitkxCodeEdit = _editors[path]
	if ed.dirty:
		var do_save := func():
			if _write_editor(ed):
				_close_editor(path)
		var do_discard := func():
			_close_editor(path)
		_confirm_two("Close %s?" % (path if path != "" else "the scratch buffer"),
			"Save & Close", do_save, "Discard & Close", do_discard)
		return
	_close_editor(path)

func _close_editor(path: String) -> void:
	var ed: GuitkxCodeEdit = _editors[path]
	_editors.erase(path)
	for i in _open_list.item_count:
		if str(_open_list.get_item_metadata(i)) == path:
			_open_list.remove_item(i)
			break
	var was_current := _current == ed
	ed.queue_free()
	if was_current:
		_current = null
		if _editors.is_empty():
			_switch_to(_ensure_editor(""))
		else:
			_switch_to(_editors[_editors.keys()[_editors.size() - 1]])

## Document outline (G12): declarations of the current buffer; activate to jump.
func _refresh_outline() -> void:
	if _outline == null or _current == null:
		return
	_outline.clear()
	var root := _outline.create_item()
	for entry in OutlineScript.outline_of(_current.text):
		var e := entry as Dictionary
		var item := _outline.create_item(root)
		var glyph := "◆"
		match str(e.get("kind", "")):
			"hook":
				glyph = "ƒ"
			"module":
				glyph = "▣"
			"func":
				glyph = "·"
			"value":
				glyph = "="
			"util":
				glyph = "ƒ"
		item.set_text(0, "%s %s" % [glyph, str(e.get("name", ""))])
		item.set_metadata(0, int(e.get("offset", 0)))

func _on_outline_activated() -> void:
	var item := _outline.get_selected()
	if item != null:
		_goto_offset(int(item.get_metadata(0)))

## All real (non-scratch) open file paths — the plugin's folder-lifecycle handlers iterate these.
func open_paths() -> Array:
	var out: Array = []
	for path in _editors:
		if str(path) != "":
			out.append(str(path))
	return out

## Every open file with unsaved changes (feeds the quit-confirmation via the plugin).
func dirty_files() -> Array:
	var out: Array = []
	for path in _editors:
		if (_editors[path] as GuitkxCodeEdit).dirty:
			out.append(path if path != "" else "(scratch)")
	return out

## Session snapshot (G17): open files, the current one, carets, zoom, wrap.
func session_state() -> Dictionary:
	var carets := {}
	for path in _editors:
		if path == "":
			continue
		var ed: GuitkxCodeEdit = _editors[path]
		carets[path] = [ed.get_caret_line(), ed.get_caret_column()]
	return {
		"files": carets.keys(), "current": _current_path, "carets": carets,
		"zoom": GuitkxCodeEdit.zoom_font_size,
		"wrap": _wrap_toggle != null and _wrap_toggle.button_pressed,
	}

func restore_session(state: Dictionary) -> void:
	GuitkxCodeEdit.zoom_font_size = int(state.get("zoom", 0))
	if _wrap_toggle != null:
		_wrap_toggle.button_pressed = bool(state.get("wrap", false))
	var carets: Dictionary = state.get("carets", {})
	for path in state.get("files", []):
		if FileAccess.file_exists(str(path)):
			_open_path_now(str(path))
			var c: Array = carets.get(path, [])
			if c.size() == 2 and _current != null:
				_current.set_caret_line(int(c[0]))
				_current.set_caret_column(int(c[1]))
	var cur := str(state.get("current", ""))
	if _editors.has(cur):
		_switch_to(_editors[cur])

func _on_wrap_toggled(on: bool) -> void:
	for path in _editors:
		(_editors[path] as GuitkxCodeEdit).wrap_mode = \
			TextEdit.LINE_WRAPPING_BOUNDARY if on else TextEdit.LINE_WRAPPING_NONE

func _ready() -> void:
	if not Engine.is_editor_hint():
		return
	var theme := EditorInterface.get_editor_theme()
	if theme != null:
		if theme.has_icon("StatusError", "EditorIcons"):
			_err_icon = theme.get_icon("StatusError", "EditorIcons")
		if theme.has_icon("StatusWarning", "EditorIcons"):
			_warn_icon = theme.get_icon("StatusWarning", "EditorIcons")

## Editor shortcuts while this screen is visible: Ctrl+S saves the .guitkx (without this, Godot's
## global Save Scene eats the keystroke and the buffer silently stays unsaved — G31), Ctrl+F opens
## the find bar, F3/Shift+F3 step matches, Esc closes the bar (G24). Godot's own save flows still
## reach us when the screen is NOT visible, via the plugin's _save_external_data.
func _shortcut_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	if k.is_command_or_control_pressed() and not k.shift_pressed and not k.alt_pressed:
		match k.keycode:
			KEY_S:
				_on_save_pressed()
				accept_event()
			KEY_F:
				_find_bar.open_bar()
				accept_event()
			KEY_G:
				_goto_line_dialog()
				accept_event()
		return
	match k.keycode:
		KEY_F3:
			if not _find_bar.query_text().is_empty():
				if not _find_bar.visible:
					_find_bar.visible = true
				_find_bar.find_step(not k.shift_pressed)
				accept_event()
		KEY_F2:
			_rename_dialog()
			accept_event()
		KEY_F12:
			if k.shift_pressed:
				_show_references()
				accept_event()
		KEY_ESCAPE:
			if _find_bar.visible:
				_find_bar.close_bar()
				accept_event()

## External-change watch (parity plan G25): when the editor window regains focus and the file changed
## on disk underneath a CLEAN buffer, reload silently (VS Code behavior). A DIRTY buffer is left
## alone — the conflict is resolved at Save time, where the user gets an explicit choice.
func _notification(what: int) -> void:
	if what != NOTIFICATION_APPLICATION_FOCUS_IN:
		return
	if _loading:
		return
	for path in _editors.keys():
		if str(path) == "":
			continue
		_check_editor_staleness(_editors[path])

## External-change watch for one buffer: missing file -> detached; returned file + clean buffer ->
## auto-reload (heals git restore); changed-on-disk + clean -> auto-reload; dirty conflicts resolve
## at Save time with an explicit choice.
func _check_editor_staleness(ed: GuitkxCodeEdit) -> void:
	if ed.file_path.is_empty():
		return
	if not FileAccess.file_exists(ed.file_path):
		if not ed.detached:
			ed.detached = true
			_refresh_list_row(ed)
			if ed == _current:
				_update_file_label()
		return
	if ed.detached or (ed.loaded_mtime != 0 and FileAccess.get_modified_time(ed.file_path) != ed.loaded_mtime):
		if not ed.dirty:
			_reload_editor(ed)

func _reload_editor(ed: GuitkxCodeEdit) -> void:
	var text := FileAccess.get_file_as_string(ed.file_path)
	_loading = true
	ed.text = text
	ed.clear_undo_history()
	_loading = false
	ed.dirty = false
	ed.detached = false
	ed.loaded_mtime = FileAccess.get_modified_time(ed.file_path)
	_refresh_list_row(ed)
	if ed == _current:
		_update_file_label()
		_refresh_diagnostics()

## Wire the shared bottom Problems panel (owned by the plugin).
func set_problems_panel(panel: GuitkxProblemsPanel) -> void:
	_problems = panel

## --- Buffer state (read by the plugin's _get_unsaved_status / lifecycle handlers) ---

func is_dirty() -> bool:
	return _dirty

func current_path() -> String:
	return _current_path

## A file was renamed/moved on disk (FileSystemDock signal via the plugin): whichever OPEN editor
## holds it follows, keeping buffer + dirty state — Save must never resurrect the OLD filename
## (parity plan L1). Works for any open file, not just the current one.
func retarget_path(new_path: String, old_path: String = "") -> void:
	var key := old_path if old_path != "" else _current_path
	if not _editors.has(key):
		return
	var ed: GuitkxCodeEdit = _editors[key]
	_editors.erase(key)
	_editors[new_path] = ed
	ed.file_path = new_path
	ed.detached = false
	ed.loaded_mtime = FileAccess.get_modified_time(new_path) if FileAccess.file_exists(new_path) else 0
	for i in _open_list.item_count:
		if str(_open_list.get_item_metadata(i)) == key:
			_open_list.set_item_metadata(i, new_path)
			_open_list.set_item_text(i, _list_label(ed))
			_open_list.set_item_tooltip(i, new_path)
			break
	if ed == _current:
		_update_file_label()

## A file was deleted on disk (parity plan L2): its buffer stays (it may be the only copy of the
## user's work) but is marked detached; Save asks before recreating. Detached does NOT imply
## dirty — that split is what lets a clean buffer HEAL automatically when the file comes back.
func mark_detached(path: String = "") -> void:
	var key := path if path != "" else _current_path
	if not _editors.has(key):
		return
	var ed: GuitkxCodeEdit = _editors[key]
	ed.detached = true
	_refresh_list_row(ed)
	if ed == _current:
		_update_file_label()

## --- Opening ---

## Open a .guitkx (Open button, Problems/References navigation, double-click route). With per-file
## editors, switching never loses anything: an already-open file just becomes current (its edits,
## caret, and undo history intact — after a staleness check); a new file gets its own editor.
func open_path(path: String) -> void:
	if _editors.has(path):
		var ed: GuitkxCodeEdit = _editors[path]
		_check_editor_staleness(ed)
		_switch_to(ed)
		if _pending_jump_offset >= 0:
			_goto_offset(_pending_jump_offset)
			_pending_jump_offset = -1
		return
	_open_path_now(path)

func _open_path_now(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		_alert("Cannot open %s (error %d)." % [path, FileAccess.get_open_error()])
		return
	var text := f.get_as_text()
	f.close()
	_load_text(path, text)
	# A pristine scratch buffer has served its purpose once a real file opens.
	if _editors.has("") and path != "":
		var scratch: GuitkxCodeEdit = _editors[""]
		if not scratch.dirty and scratch.text.strip_edges().is_empty():
			_close_editor("")

## Open from a double-clicked GuitkxResource (plugin _edit route).
func open_resource(res: GuitkxResource) -> void:
	if res == null:
		return
	# A double-clicked resource can be a CACHE_MODE_REUSE cache hit whose in-memory source predates an
	# external Save (we write .guitkx via FileAccess, never ResourceSaver). Re-read from disk when we
	# can, so a reopen always shows the current file; fall back to res.source only when pathless.
	if not res.resource_path.is_empty() and FileAccess.file_exists(res.resource_path):
		open_path(res.resource_path)
	else:
		_load_text(res.resource_path, res.source)

func goto_line(line: int) -> void:
	if _code_edit == null:
		return
	line = clampi(line, 0, maxi(0, _code_edit.get_line_count() - 1))
	_code_edit.set_caret_line(line)
	_code_edit.set_caret_column(0)
	_code_edit.center_viewport_to_caret()
	if _code_edit.is_inside_tree():
		_code_edit.grab_focus()

## Ctrl+click go-to-definition (G1): same-file jumps immediately; cross-file remembers the target
## offset and opens the file (through the dirty-buffer guard), applied when the load completes.
## M3: a res://*.gd target (an analyzer definition into real GDScript) routes to Godot's own
## script editor at the right line — .gd files are the Script editor's domain, not ours.
func _on_definition_requested(path: String, offset: int) -> void:
	if path.is_empty():
		return
	if path.get_extension() == "gd":
		if Engine.is_editor_hint():
			var script: Variant = load(path)
			if script is Script:
				var lc: Dictionary = RuitkGuitkxDiag.line_col(FileAccess.get_file_as_string(path), offset)
				EditorInterface.edit_script(script, int(lc.get("line", 0)) + 1, int(lc.get("col", 0)))
		return
	if path == _current_path:
		_goto_offset(offset)
		return
	_pending_jump_offset = offset
	open_path(path)

func _goto_offset(offset: int) -> void:
	var lc: Dictionary = RuitkGuitkxDiag.line_col(_code_edit.text, offset)
	goto_line(int(lc.get("line", 0)))
	_code_edit.set_caret_column(int(lc.get("col", 0)))

## The filesystem shape changed (files added/removed/renamed anywhere): recompute cross-file
## bindings on next compile and refresh so 0105/did-you-mean track reality (G13/G15).
## M3: re-feed the open files' generated siblings into the analyzer session — the watcher just
## recompiled them, and embedded expressions resolve user components through those .gd files.
func on_workspace_changed() -> void:
	_bindings_valid = false
	var bridge = BridgeScript.instance()
	if bridge != null:
		for p in open_paths():
			var gd_path: String = RuitkGuitkxCodegen.gd_path_for(str(p))
			if FileAccess.file_exists(gd_path):
				bridge.refresh_script(gd_path)
	_refresh_diagnostics()

func _load_text(path: String, text: String) -> void:
	var ed := _ensure_editor(path)
	_loading = true
	ed.text = text
	ed.clear_undo_history()
	_loading = false
	ed.dirty = false
	ed.detached = false
	ed.loaded_mtime = FileAccess.get_modified_time(path) if (not path.is_empty() and FileAccess.file_exists(path)) else 0
	_refresh_list_row(ed)
	_switch_to(ed)
	_update_file_label()
	_refresh_diagnostics()
	if _pending_jump_offset >= 0:
		_goto_offset(_pending_jump_offset)
		_pending_jump_offset = -1

func _on_editor_text_changed(ed: GuitkxCodeEdit) -> void:
	if _loading:
		return
	if not ed.dirty:
		ed.dirty = true
		_refresh_list_row(ed)
		if ed == _current:
			_update_file_label()
	if ed == _current and _debounce.is_inside_tree():
		_debounce.start()

func _update_file_label() -> void:
	if _current == null or _current_path.is_empty():
		_file_label.text = "(scratch)" if _current != null else "(no file)"
		return
	var label := _current_path
	if _detached:
		label += "  (deleted on disk)"
	if _dirty:
		label += "  *"
	_file_label.text = label
	_refresh_list_row(_current)

## --- Diagnostics pipeline ---

func _refresh_diagnostics() -> void:
	if _code_edit == null:
		return
	# The outline is pure text (no compile) — refresh it before any of the diagnostic gates below
	# can return, so it stays live with diagnostics disabled and on oversized files too.
	_refresh_outline()
	if not RuitkEditorSettings.is_enabled(RuitkEditorSettings.KEY_DIAGNOSTICS):
		GuitkxDiagnosticsRenderer.clear(_code_edit, _code_edit.diag_gutter)
		_code_edit.set_dim_lines({})
		if _problems != null:
			_problems.clear()
		return
	var text := _code_edit.text
	# A pathless, empty scratch buffer (fresh tab, nothing typed) is not a compile error — don't
	# greet the user with a red "missing declaration" icon on an untouched editor.
	if _current_path.is_empty() and text.strip_edges().is_empty():
		GuitkxDiagnosticsRenderer.clear(_code_edit, _code_edit.diag_gutter)
		_code_edit.set_dim_lines({})
		if _problems != null:
			_problems.clear()
		return
	if text.length() > MAX_LIVE_COMPILE:
		# Too large to compile on every keystroke — clear stale decorations so nothing mis-anchors as
		# the text shifts, and rely on the Save-time compile instead.
		GuitkxDiagnosticsRenderer.clear(_code_edit, _code_edit.diag_gutter)
		_code_edit.set_dim_lines({})
		if _problems != null:
			_problems.clear()
		return
	# Cross-file context (G13): known component classes + class->generated-.gd map, exactly what the
	# watcher's sweep passes — so unknown-component 0105 (with did-you-mean) arms in-editor too.
	var pb := _project_bindings()
	var t0 := Time.get_ticks_usec()
	var result: Dictionary = RuitkGuitkx.compile(
		text, _basename(text), pb.get("known", []), pb.get("bindings", {}))
	_last_compile_ms = float(Time.get_ticks_usec() - t0) / 1000.0
	# Adaptive gate (P1): compiles run on the main thread, so big files stretch the debounce
	# instead of freezing the editor on every typing pause (measured 189ms @ 90KB).
	_debounce.wait_time = _adaptive_wait(_last_compile_ms)
	var diags: Array = result.get("diagnostics", [])
	# Scan-tier unknown tags: the compiler's 0105 lives in its EMIT phase, so a parse error (the
	# classic: typo'd open tag -> mismatched close) masks the one report that explains the typo.
	# The parse-independent scan fills that hole; compiler-emitted diagnostics win on overlap.
	var seen := {}
	for d in diags:
		if d is Dictionary:
			seen["%s@%d" % [str(d.get("code", "")), int(d.get("offset", -1))]] = true
	for sd in ScanDiags.unknown_tags(text, pb.get("known", [])):
		if not seen.has("%s@%d" % [str(sd.get("code", "")), int(sd.get("offset", -1))]):
			diags.append(sd)
	# Sidecar overlay (M2/D3): the watcher's sweep computes two PROJECT-level codes the live
	# compile can never produce — GUITKX2106 (duplicate class binding) and GUITKX2107 (dangling
	# component reference) — and persists them in the file's .diags.json. Hash-gated exactly like
	# the VS Code server's merge: anchored entries appear only while the buffer matches the
	# compiled content; on divergence the sidecar-only codes collapse into one line-0 hint row
	# instead of mis-anchoring into shifted text.
	_merge_sidecar(text, diags)
	# M3: the native analyzer's embedded-GDScript tier — syntax + type diagnostics for {expr} and
	# setup code, computed on the virtual doc and remapped into .guitkx coords (glue-filtered, so
	# scaffolding can never squiggle user code). Codes carry a "GD:" prefix so they never collide
	# with GUITKX#### in dedup or docs. Absent extension -> instance() is null -> markup-only.
	var bridge = BridgeScript.instance()
	if bridge != null:
		diags.append_array(bridge.diagnostics(_current_path, text))
	var records := GuitkxDiagnosticsRenderer.render(
		_code_edit, _code_edit.diag_gutter, diags, _err_icon, _warn_icon)
	if _problems != null:
		_problems.set_records(records)
	# Hand the per-line records to the widget so hovering a diagnosed line shows the message
	# (with its did-you-mean) instead of requiring a gutter click.
	var by_line := {}
	for rec in records:
		var ln := int((rec as Dictionary).get("line", 0))
		if not by_line.has(ln):
			by_line[ln] = []
		(by_line[ln] as Array).append(rec)
	_code_edit.set_line_diagnostics(by_line)
	_apply_unreachable_dim(text)

func _project_bindings() -> Dictionary:
	if not _bindings_valid:
		_bindings_cache = RuitkGuitkxCodegen.project_bindings(GuitkxWorkspace.all_paths())
		_bindings_valid = true
	return _bindings_cache

## Debounce stretched proportionally to the last compile cost, floored at DEBOUNCE_SEC, capped at
## 2s — a 30ms file keeps the snappy 0.3s; a 200ms file waits ~0.8s between compiles.
static func _adaptive_wait(compile_ms: float) -> float:
	return clampf(compile_ms * 4.0 / 1000.0, DEBOUNCE_SEC, 2.0)

func _merge_sidecar(text: String, diags: Array) -> void:
	if _current_path.is_empty():
		return
	var sc_path: String = RuitkGuitkxCodegen.diags_path_for(_current_path)
	var raw := FileAccess.get_file_as_string(sc_path)
	if raw.is_empty():
		return
	var parsed: Variant = JSON.parse_string(raw)
	if not (parsed is Dictionary):
		return
	var sc := parsed as Dictionary
	var entries: Array = sc.get("diagnostics", [])
	if entries.is_empty():
		return
	var live_codes := {}
	var live_at := {}
	for d in diags:
		if d is Dictionary:
			live_codes[str((d as Dictionary).get("code", ""))] = true
			live_at["%s@%d" % [str((d as Dictionary).get("code", "")), int((d as Dictionary).get("offset", -1))]] = true
	if int(sc.get("src_hash", -1)) == RuitkGuitkxCodegen.src_hash(text):
		# Buffer == compiled content: merge precisely (sidecar keys are off/len; live uses
		# offset/length). Compile-time codes are already in the live set — only sweep-only
		# entries actually land.
		for e in entries:
			if not (e is Dictionary):
				continue
			var ed := e as Dictionary
			var key := "%s@%d" % [str(ed.get("code", "")), int(ed.get("off", -1))]
			if live_at.has(key):
				continue
			diags.append({
				"code": ed.get("code", ""), "severity": int(ed.get("severity", 0)),
				"message": str(ed.get("message", "")),
				"offset": int(ed.get("off", -1)), "length": int(ed.get("len", 0)),
			})
		return
	# Diverged buffer: never anchor stale offsets. Name the codes the last compile found that the
	# live tiers can't see, in one informational row.
	var hidden: Array = []
	for e in entries:
		if e is Dictionary and not live_codes.has(str((e as Dictionary).get("code", ""))):
			var c := str((e as Dictionary).get("code", ""))
			if not hidden.has(c):
				hidden.append(c)
	if not hidden.is_empty():
		diags.append({
			"code": ", ".join(hidden), "severity": 2,
			"message": "the last compile reported %s in this file — positions are hidden while the buffer has unsaved changes (save to re-anchor)" % ", ".join(hidden),
			"offset": -1, "length": 0,
		})

## Fade the lines after each component's markup return (unreachable code). [BUG-V6]
func _apply_unreachable_dim(text: String) -> void:
	var lines := {}
	for r in RuitkGuitkx.unreachable_line_ranges(text):
		for ln in range(int(r[0]), int(r[1]) + 1):
			lines[ln] = true
	_code_edit.set_dim_lines(lines)

## The identity the compiler checks the declared name against (GUITKX0103). A pathless scratch
## buffer derives it from its own first declaration — the literal "Component" fallback used to
## self-report a spurious name-mismatch on every unsaved buffer (parity plan D4).
## ES-modules leg: plain declarations have no keyword for a regex to anchor on, so the probe is
## the compiler's own scan (wrapper + plain forms alike).
func _basename(text: String = "") -> String:
	if not _current_path.is_empty():
		return _current_path.get_file().get_basename()
	var d: Dictionary = RuitkGuitkx._find_decl(text, 0)
	var nm := ""
	if str(d.get("kind", "")) != "":
		if bool(d.get("deprecated", false)):
			# wrapper row: `at` is the keyword -- the name follows it.
			var rows: Array = RuitkGuitkx._enumerate_decls(text, 0)
			if not rows.is_empty():
				nm = str((rows[0] as Dictionary).get("name", ""))
		else:
			nm = str(d.get("name", ""))
	return nm if nm != "" else "Component"

## --- Toolbar actions ---

func _on_open_pressed() -> void:
	var dlg := EditorFileDialog.new()
	dlg.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	dlg.access = EditorFileDialog.ACCESS_RESOURCES
	dlg.clear_filters()
	dlg.add_filter("*.guitkx", "GUITKX files")
	dlg.file_selected.connect(func(p: String):
		open_path(p)
		dlg.queue_free())
	dlg.canceled.connect(func(): dlg.queue_free())
	EditorInterface.get_base_control().add_child(dlg)
	dlg.popup_file_dialog()

func _on_save_pressed() -> void:
	if _current_path.is_empty():
		_alert("Open a .guitkx file before saving.")
		return
	# External-change conflict (G25): the file changed on disk since we loaded it. Explicit choice —
	# never silently overwrite someone else's newer content, never silently drop the user's edits.
	if not _detached and FileAccess.file_exists(_current_path):
		var disk := FileAccess.get_modified_time(_current_path)
		if _loaded_mtime != 0 and disk != _loaded_mtime:
			_confirm_two("The file changed on disk since it was loaded.\n%s" % _current_path,
				"Overwrite Disk", _write_buffer,
				"Reload From Disk (discard my edits)", func():
					_dirty = false
					_open_path_now(_current_path))
			return
	# Deleted-source guard (L2): Save would recreate a file the user deliberately deleted — ask.
	if _detached:
		_confirm_one("The source file was deleted (or moved) on disk.\nSave will recreate:\n%s" % _current_path,
			"Recreate File", _write_buffer)
		return
	_write_buffer()

func _write_buffer() -> void:
	_write_editor(_current)

## The unconditional write path for one editor (all guards passed). Formats when enabled, writes,
## and hands the change to the reactive_ui_toolkit watcher via a targeted update_file — the same cadence
## an external editor's save gets (a full scan() momentarily gated the watcher's triggers; L8).
func _write_editor(ed: GuitkxCodeEdit) -> bool:
	if ed == null or ed.file_path.is_empty():
		return false
	var text: String = ed.text
	if RuitkEditorSettings.is_enabled(RuitkEditorSettings.KEY_FORMAT_ON_SAVE):
		text = _format_text(text, ed.file_path)
	if text != ed.text:
		_loading = true
		ed.set_text_undoable(text)
		_loading = false
	var f := FileAccess.open(ed.file_path, FileAccess.WRITE)
	if f == null:
		# Visible failure (L3): push_error alone leaves the user believing the save happened.
		_alert("Could not write %s (error %d).\nThe buffer still holds your changes." % [
			ed.file_path, FileAccess.get_open_error()])
		push_error("[reactive_ui_toolkit_editor] cannot write %s (%d)" % [ed.file_path, FileAccess.get_open_error()])
		return false
	f.store_string(text)
	f.close()
	ed.dirty = false
	ed.detached = false
	ed.loaded_mtime = FileAccess.get_modified_time(ed.file_path)
	_bindings_valid = false  # our own save can change the project's class/binding shape
	_refresh_list_row(ed)
	if ed == _current:
		_update_file_label()
	EditorInterface.get_resource_filesystem().update_file(ed.file_path)
	# Keep the component index fresh so renamed/added components complete without a full rescan.
	GuitkxWorkspace.reindex(ed.file_path, ed.text)
	if ed == _current:
		_refresh_diagnostics()
	return true

## Dialog-free save of EVERY dirty buffer, for Godot's own flows (Save All / quit / Play via the
## plugin's _save_external_data / _apply_changes). Refuses conflicted/detached files rather than
## prompting mid-flow; those stay dirty and the user resolves them in the editor.
func save_silent() -> bool:
	var all_ok := true
	for path in _editors.keys():
		var ed: GuitkxCodeEdit = _editors[path]
		if str(path) == "" or not ed.dirty:
			continue
		if ed.detached:
			push_error("[reactive_ui_toolkit_editor] %s was deleted on disk — not recreating it during an editor save. Save it explicitly in the Reactive UI Toolkit editor." % ed.file_path)
			all_ok = false
			continue
		if FileAccess.file_exists(ed.file_path):
			var disk := FileAccess.get_modified_time(ed.file_path)
			if ed.loaded_mtime != 0 and disk != ed.loaded_mtime:
				push_error("[reactive_ui_toolkit_editor] %s changed on disk — not overwriting during an editor save. Resolve it in the Reactive UI Toolkit editor." % ed.file_path)
				all_ok = false
				continue
		if not _write_editor(ed):
			all_ok = false
	return all_ok

func _on_format_pressed() -> void:
	var text := _formatted(_code_edit.text)
	if text != _code_edit.text:
		_code_edit.set_text_undoable(text)
	_refresh_diagnostics()

## Gutter click -> a popup at the mouse with the full diagnostic (code + message), instead of a
## line lost in the Output panel (parity plan G19; field ask: the did-you-mean was invisible).
func _on_gutter_diagnostic_clicked(line: int, record: Variant) -> void:
	if not (record is Dictionary):
		return
	var md: String = _code_edit.compose_hover("", line)
	if md.is_empty():
		md = "**%s** `%s` — %s" % [
			str((record as Dictionary).get("severity", "error")).to_upper(),
			str((record as Dictionary).get("code", "")),
			str((record as Dictionary).get("message", ""))]
	var pop := PopupPanel.new()
	var rtl := RichTextLabel.new()
	rtl.bbcode_enabled = true
	rtl.fit_content = true
	rtl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rtl.custom_minimum_size = Vector2(480, 0)
	rtl.text = GuitkxHover.md_to_bbcode(md)
	pop.add_child(rtl)
	pop.popup_hide.connect(pop.queue_free)
	add_child(pop)
	pop.popup(Rect2i(DisplayServer.mouse_get_position(), Vector2i(500, 0)))

# RuitkGuitkxFormatter.format() returns the source verbatim on any parse error, so this never
# corrupts. Honors the nearest guitkx.config.json (G26) exactly like the VS Code extension, so
# one project formats identically in both editors.
func _formatted(text: String) -> String:
	return _format_text(text, _current_path)

## [G-06 fix] `fell_back` (r["fell_back"]) tells apart "already canonical" from "couldn't even try
## (syntax error)" -- both look identical from just `text == source`. Warns the user once per path
## per session instead of staying silent (format-on-save used to look like a no-op) or nagging on
## every save of the same still-broken file.
func _format_text(text: String, path: String) -> String:
	var r: Dictionary = RuitkGuitkxFormatter.format(text, ConfigScript.formatter_opts_for(path))
	if bool(r.get("fell_back", false)) and not _format_fallback_warned.has(path):
		_format_fallback_warned[path] = true
		_alert("%s has syntax errors -- format skipped." % path.get_file())
	if r.get("ok", false):
		return r.get("text", text)
	return text

## "New" (G18): pick a path, seed a minimal component skeleton named after the file, open it.
func _on_new_pressed() -> void:
	var dlg := EditorFileDialog.new()
	dlg.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	dlg.access = EditorFileDialog.ACCESS_RESOURCES
	dlg.clear_filters()
	dlg.add_filter("*.guitkx", "GUITKX files")
	dlg.file_selected.connect(func(p: String):
		if not p.ends_with(".guitkx"):
			p += ".guitkx"
		if not FileAccess.file_exists(p):
			var comp := p.get_file().get_basename().to_pascal_case()
			var f := FileAccess.open(p, FileAccess.WRITE)
			if f != null:
				f.store_string("component %s {\n  return (\n    <Label text=\"%s\" />\n  )\n}\n" % [comp, comp])
				f.close()
				EditorInterface.get_resource_filesystem().update_file(p)
				GuitkxWorkspace.reindex(p, FileAccess.get_file_as_string(p))
		open_path(p)
		dlg.queue_free())
	dlg.canceled.connect(dlg.queue_free)
	EditorInterface.get_base_control().add_child(dlg)
	dlg.popup_file_dialog()

## --- Dialog helpers (one-shot, self-freeing) ---

func _alert(text: String) -> void:
	var dlg := AcceptDialog.new()
	dlg.title = "Reactive UI Toolkit — Godot Editor"
	dlg.dialog_text = text
	dlg.confirmed.connect(dlg.queue_free)
	dlg.canceled.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered()

func _confirm_one(text: String, ok_label: String, on_ok: Callable) -> void:
	var dlg := ConfirmationDialog.new()
	dlg.title = "Reactive UI Toolkit — Godot Editor"
	dlg.dialog_text = text
	dlg.ok_button_text = ok_label
	dlg.confirmed.connect(func():
		on_ok.call()
		dlg.queue_free())
	dlg.canceled.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered()

func _confirm_two(text: String, ok_label: String, on_ok: Callable, alt_label: String, on_alt: Callable) -> void:
	var dlg := ConfirmationDialog.new()
	dlg.title = "Reactive UI Toolkit — Godot Editor"
	dlg.dialog_text = text
	dlg.ok_button_text = ok_label
	var alt := dlg.add_button(alt_label, true, "alt")
	alt.pressed.connect(func():
		dlg.hide()
		on_alt.call()
		dlg.queue_free())
	dlg.confirmed.connect(func():
		on_ok.call()
		dlg.queue_free())
	dlg.canceled.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered()

# (The W2 switch-away Save/Discard/Cancel prompt is gone by design: per-file editors mean
# switching never loses anything — dirty buffers simply persist in their own tab.)

## --- References + rename (G2/G3) ---

signal references_requested(tag: String, records: Array)

func _component_at_caret() -> String:
	var text := _code_edit.text
	var off := GuitkxContext.offset_of(text, _code_edit.get_caret_line(), _code_edit.get_caret_column())
	var word := GuitkxHover.word_at(text, off)
	return word if GuitkxWorkspace.is_component(word) else ""

## Shift+F12: project-wide references for the component under the caret, delivered to the
## References bottom panel via the plugin.
func _show_references() -> void:
	var tag := _component_at_caret()
	if tag.is_empty():
		# M3: references for the EMBEDDED symbol under the caret, through the analyzer (locals,
		# hook results, engine members used across this file's expressions).
		var bridge = BridgeScript.instance()
		if bridge != null:
			var text := _code_edit.text
			var off := GuitkxContext.offset_of(text, _code_edit.get_caret_line(), _code_edit.get_caret_column())
			var refs: Array = bridge.find_references(_current_path, text, off)
			if not refs.is_empty():
				references_requested.emit(_embedded_symbol_at_caret(), _embedded_ref_records(refs))
				return
		_alert("Place the caret on a component tag (or an embedded symbol) to find its references.")
		return
	references_requested.emit(tag, RefsScript.project_refs(tag))

# Shape analyzer reference hits like RefsScript.project_refs records (path/offset/length/kind/
# line/preview) so the References panel renders them identically.
func _embedded_ref_records(refs: Array) -> Array:
	var out: Array = []
	for r in refs:
		var rd := r as Dictionary
		var p := str(rd.get("path", ""))
		var off := int(rd.get("offset", 0))
		var text := _code_edit.text if p == _current_path else FileAccess.get_file_as_string(p)
		var lc: Dictionary = RuitkGuitkxDiag.line_col(text, off)
		var line := int(lc.get("line", 0))
		var ls := 0 if line == 0 else text.rfind("\n", maxi(0, off - 1)) + 1
		var le := text.find("\n", off)
		if le == -1:
			le = text.length()
		out.append({
			"path": p, "offset": off, "length": 0, "kind": "embedded", "line": line,
			"preview": text.substr(ls, le - ls).strip_edges(),
		})
	return out

# The identifier under the caret (for the References panel headline on embedded lookups).
func _embedded_symbol_at_caret() -> String:
	var line := _code_edit.get_line(_code_edit.get_caret_line())
	var col := _code_edit.get_caret_column()
	var s := col
	while s > 0 and _is_word_char(line[s - 1]):
		s -= 1
	var e := col
	while e < line.length() and _is_word_char(line[e]):
		e += 1
	return line.substr(s, e - s)

static func _is_word_char(c: String) -> bool:
	var u := c.unicode_at(0)
	return (u >= 65 and u <= 90) or (u >= 97 and u <= 122) or (u >= 48 and u <= 57) or u == 95

# M3: rename an embedded-GDScript symbol. Analyzer-gated (it refuses cross-file/glue-touching
# renames) and applied to the buffer as ONE undoable edit — never to disk, since an embedded
# local's scope IS this buffer.
func _embedded_rename_dialog(bridge) -> void:
	var symbol := _embedded_symbol_at_caret()
	var text := _code_edit.text
	var off := GuitkxContext.offset_of(text, _code_edit.get_caret_line(), _code_edit.get_caret_column())
	var dlg := ConfirmationDialog.new()
	dlg.title = "Rename Symbol (embedded GDScript)"
	var edit := LineEdit.new()
	edit.text = symbol
	edit.select_all()
	dlg.add_child(edit)
	dlg.register_text_enter(edit)
	dlg.ok_button_text = "Rename in Buffer"
	dlg.confirmed.connect(func():
		_apply_embedded_rename(bridge, off, edit.text.strip_edges())
		dlg.queue_free())
	dlg.canceled.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered()
	edit.grab_focus.call_deferred()

func _apply_embedded_rename(bridge, offset: int, new_name: String) -> void:
	if not new_name.is_valid_identifier():
		_alert("'%s' is not a valid identifier." % new_name)
		return
	var text := _code_edit.text
	var r: Dictionary = bridge.rename(_current_path, text, offset, new_name)
	if not bool(r.get("ok", false)):
		_alert("Rename refused: %s." % str(r.get("reason", "unknown")))
		return
	_code_edit.begin_complex_operation()
	for e in r.get("edits", []):  # descending offsets — later splices never shift earlier ones
		var ed := e as Dictionary
		var o := int(ed["offset"])
		var lc: Dictionary = RuitkGuitkxDiag.line_col(text, o)
		var lc_end: Dictionary = RuitkGuitkxDiag.line_col(text, o + int(ed["length"]))
		_code_edit.select(int(lc["line"]), int(lc["col"]), int(lc_end["line"]), int(lc_end["col"]))
		_code_edit.delete_selection()
		_code_edit.insert_text_at_caret(str(ed["new_text"]))
	_code_edit.end_complex_operation()
	_on_editor_text_changed(_code_edit)
	_refresh_diagnostics()

## F2: rename the component under the caret across the whole project — collision-refusing,
## applied to the open buffer as ONE undoable edit and to every other file on disk.
func _rename_dialog() -> void:
	var tag := _component_at_caret()
	if tag.is_empty():
		# M3: rename the EMBEDDED symbol under the caret (analyzer-resolved, buffer-scoped).
		var bridge = BridgeScript.instance()
		if bridge != null and _embedded_symbol_at_caret() != "":
			_embedded_rename_dialog(bridge)
			return
		_alert("Place the caret on a component tag to rename it.")
		return
	var dlg := ConfirmationDialog.new()
	dlg.title = "Rename Component"
	var edit := LineEdit.new()
	edit.text = tag
	edit.select_all()
	dlg.add_child(edit)
	dlg.register_text_enter(edit)
	dlg.ok_button_text = "Rename Everywhere"
	dlg.confirmed.connect(func():
		_apply_rename(tag, edit.text.strip_edges())
		dlg.queue_free())
	dlg.canceled.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered()
	edit.grab_focus.call_deferred()

func _apply_rename(old_tag: String, new_tag: String) -> void:
	if new_tag == old_tag or new_tag.is_empty():
		return
	var plan: Dictionary = RefsScript.rename_edits(old_tag, new_tag)
	if not bool(plan.get("ok", false)):
		_alert("Cannot rename: %s" % str(plan.get("reason", "")))
		return
	var edits: Dictionary = plan.get("edits", {})
	var touched := 0
	for path in edits:
		var file_edits: Array = edits[path]
		if _editors.has(str(path)):
			# ANY open buffer (current or background tab): apply through its editor as one
			# undoable operation and save via the normal flow — writing its disk file behind
			# the buffer would leave a stale tab that conflicts at its next save.
			var ed: GuitkxCodeEdit = _editors[str(path)]
			_loading = true
			ed.set_text_undoable(RefsScript.apply_edits_to_text(ed.text, file_edits, new_tag))
			_loading = false
			_write_editor(ed)
		else:
			var text := FileAccess.get_file_as_string(str(path))
			var f := FileAccess.open(str(path), FileAccess.WRITE)
			if f == null:
				_alert("Rename partially applied: cannot write %s." % str(path))
				continue
			f.store_string(RefsScript.apply_edits_to_text(text, file_edits, new_tag))
			f.close()
			EditorInterface.get_resource_filesystem().update_file(str(path))
		touched += 1
	GuitkxWorkspace.rescan()
	_bindings_valid = false
	_refresh_diagnostics()
	print("[reactive_ui_toolkit_editor] renamed <%s> -> <%s> across %d file(s)" % [old_tag, new_tag, touched])

## Ctrl+G (E13): jump to a 1-based line number.
func _goto_line_dialog() -> void:
	var dlg := AcceptDialog.new()
	dlg.title = "Go to Line"
	var edit := LineEdit.new()
	edit.placeholder_text = "Line number (1-%d)" % _code_edit.get_line_count()
	dlg.add_child(edit)
	dlg.register_text_enter(edit)
	dlg.confirmed.connect(func():
		if edit.text.is_valid_int():
			goto_line(int(edit.text) - 1)
		dlg.queue_free())
	dlg.canceled.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered()
	edit.grab_focus.call_deferred()

func _make_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	return b

func _on_settings_pressed() -> void:
	settings_requested.emit()
