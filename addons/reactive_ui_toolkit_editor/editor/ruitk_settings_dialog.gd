@tool
extends AcceptDialog
## "Reactive UI Toolkit Settings" — the ONE settings screen for the family's Godot leg (family
## design decision: one settings dialog per leg, opened from the plugin's own menu surface).
## Two labeled sections over simple Controls:
##   Runtime — the reactive_ui_toolkit/* keys (RuitkSettings, the runtime addon)
##   Editor  — the reactive_ui_toolkit_editor/* booleans (RuitkEditorSettings, this addon)
## Storage is UNTOUCHED: every control reads and writes the same native ProjectSettings keys,
## so Project > Project Settings keeps working as this dialog's mirror.
##
## NO class_name, deliberately: the dialog is load()-ed by path (plugin.gd's Project > Tools
## item and the main-screen toolbar's Settings button share one instance via the plugin), so
## adding or updating this file never requires a class-cache rescan.
##
## W5: the editor addon must stay loadable with the runtime addon absent — the runtime's
## RuitkSettings is reached ONLY through load() behind a FileAccess.file_exists guard (the
## plugin.gd pattern); when it is missing, only the Editor section is built.

# Preload (own addon, dependency-free): fresh class_names are absent from cold class caches.
const EditorSettingsScript := preload("res://addons/reactive_ui_toolkit_editor/editor/ruitk_editor_settings.gd")

## The runtime addon's settings bridge. A variable (not a const) so the headless suite can point
## it at a nonexistent path and pin the W5 degradation without uninstalling the addon.
var runtime_settings_path := "res://addons/reactive_ui_toolkit/core/settings.gd"

# key -> its editing Control (CheckBox / SpinBox / OptionButton); rebuilt by rebuild().
var _controls: Dictionary = {}
# Section headers actually built, in order ("Runtime", "Editor") — the W5 test pins this.
var _sections: PackedStringArray = PackedStringArray()

var _vbox: VBoxContainer

func _init() -> void:
	title = "Reactive UI Toolkit Settings"
	min_size = Vector2i(460, 0)
	_vbox = VBoxContainer.new()
	_vbox.add_theme_constant_override("separation", 8)
	add_child(_vbox)
	# Values may have changed in the native Project Settings dialog since the last open — the
	# mirror goes both ways, so every popup re-reads the stored state.
	about_to_popup.connect(rebuild)
	rebuild()

## (Re)build both sections from the CURRENT ProjectSettings values.
func rebuild() -> void:
	for c in _vbox.get_children():
		_vbox.remove_child(c)
		c.free()
	_controls.clear()
	_sections = PackedStringArray()

	var runtime: GDScript = _runtime_settings()
	if runtime != null:
		var grid := _add_section("Runtime")
		for key in runtime.DEFAULTS:
			_add_row(grid, key, runtime.DEFAULTS[key], str(runtime.GROUP), str(runtime.TRI_STATE_HINT))
	else:
		var missing := Label.new()
		missing.text = "Runtime settings appear here when the Reactive UI Toolkit runtime addon (addons/reactive_ui_toolkit) is installed."
		missing.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		missing.custom_minimum_size = Vector2(420, 0)
		missing.modulate = Color(1, 1, 1, 0.65)
		_vbox.add_child(missing)

	var grid_ed := _add_section("Editor")
	for key in EditorSettingsScript.DEFAULTS:
		_add_row(grid_ed, key, EditorSettingsScript.DEFAULTS[key], EditorSettingsScript.GROUP, "")
	# Mirror the README's caveat: the loader-reroute toggle is structural, not live.
	var open_ctl: Control = _controls.get(EditorSettingsScript.KEY_OPEN_IN_EDITOR)
	if open_ctl != null:
		open_ctl.tooltip_text += "\nStructural: applies after the addon is re-enabled."
	var note := Label.new()
	note.text = "Note: open_guitkx_in_editor is structural — it applies after the addon is disabled and re-enabled."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(420, 0)
	note.modulate = Color(1, 1, 1, 0.65)
	_vbox.add_child(note)

# W5: load()-only + existence guard (same as plugin.gd) — never name RuitkSettings here.
func _runtime_settings() -> GDScript:
	if not FileAccess.file_exists(runtime_settings_path):
		return null
	return load(runtime_settings_path) as GDScript

func _add_section(header: String) -> GridContainer:
	if not _sections.is_empty():
		_vbox.add_child(HSeparator.new())
	_sections.append(header)
	var label := Label.new()
	label.text = header
	label.theme_type_variation = &"HeaderSmall"
	_vbox.add_child(label)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	_vbox.add_child(grid)
	return grid

## One row: name label + the Control matching the key's type (bool -> CheckBox, float ->
## SpinBox, tri-state String -> OptionButton). Values read through ProjectSettings with the
## owning class's default as fallback; populate uses the no-signal setters, and _write's
## unchanged-guard makes any populate-time signal echo harmless either way.
func _add_row(grid: GridContainer, key: String, default_value: Variant, group: String, tri_hint: String) -> void:
	var label := Label.new()
	label.text = _pretty_name(key, group)
	label.tooltip_text = key
	label.mouse_filter = Control.MOUSE_FILTER_STOP  # labels swallow tooltips otherwise
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(label)

	var stored: Variant = ProjectSettings.get_setting(key, default_value)
	var control: Control
	if default_value is bool:
		var cb := CheckBox.new()
		cb.text = "On"
		cb.set_pressed_no_signal(bool(stored))
		cb.toggled.connect(_on_bool_changed.bind(key, default_value))
		control = cb
	elif default_value is float:
		var sb := SpinBox.new()
		sb.min_value = 0.1
		sb.max_value = 100.0
		sb.allow_greater = true
		sb.step = 0.1
		if key.ends_with("_ms"):
			sb.suffix = "ms"
		sb.custom_minimum_size = Vector2(100, 0)
		sb.set_value_no_signal(float(stored))
		sb.value_changed.connect(_on_float_changed.bind(key, default_value))
		control = sb
	else:  # tri-state String enum (auto/enabled/disabled)
		var ob := OptionButton.new()
		var options := tri_hint.split(",")
		for opt in options:
			ob.add_item(opt)
		var idx := Array(options).find(str(stored))
		ob.select(maxi(idx, 0))
		ob.item_selected.connect(_on_tri_selected.bind(ob, key, default_value))
		control = ob
	control.tooltip_text = key
	control.size_flags_horizontal = Control.SIZE_SHRINK_END
	grid.add_child(control)
	_controls[key] = control

func _on_bool_changed(pressed: bool, key: String, default_value: Variant) -> void:
	_write(key, pressed, default_value)

func _on_float_changed(value: float, key: String, default_value: Variant) -> void:
	_write(key, value, default_value)

func _on_tri_selected(index: int, ob: OptionButton, key: String, default_value: Variant) -> void:
	_write(key, ob.get_item_text(index), default_value)

## Save discipline (matches RuitkEditorSettings.register_all): set_setting + save() ONLY when
## the value actually changed — populate-time signal echoes and re-picking the current value
## never touch project.godot.
func _write(key: String, value: Variant, default_value: Variant) -> void:
	if ProjectSettings.get_setting(key, default_value) == value:
		return
	ProjectSettings.set_setting(key, value)
	ProjectSettings.save()

# "reactive_ui_toolkit/runtime/time_slicing" -> "Time Slicing" (the runtime subgroup is implied
# by the section header); "reactive_ui_toolkit/diagnostics/enabled" -> "Diagnostics Enabled";
# "reactive_ui_toolkit_editor/format_on_save" -> "Format On Save".
static func _pretty_name(key: String, group: String) -> String:
	var sub := key.trim_prefix(group).trim_prefix("runtime/")
	return sub.replace("/", "_").capitalize()
