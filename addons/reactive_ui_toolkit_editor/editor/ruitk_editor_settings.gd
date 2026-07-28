@tool
class_name RuitkEditorSettings
extends RefCounted
## Project-Settings surface for the reactive_ui_toolkit_editor addon.
##
## Every feature is registered as a `reactive_ui_toolkit_editor/*` boolean that defaults to ON but can be
## flipped off in Project > Project Settings (shown as a BASIC setting, so it appears without the
## "Advanced Settings" toggle). `set_initial_value` makes each one's revert arrow reset to the
## default. Settings live in project.godot, so they travel with the project.

const GROUP := "reactive_ui_toolkit_editor/"

const KEY_HIGHLIGHTING := GROUP + "highlighting_enabled"
const KEY_DIAGNOSTICS := GROUP + "diagnostics_enabled"
const KEY_COMPLETION := GROUP + "completion_enabled"
const KEY_HOVER := GROUP + "hover_enabled"
const KEY_OPEN_IN_EDITOR := GROUP + "open_guitkx_in_editor"
const KEY_FORMAT_ON_SAVE := GROUP + "format_on_save"

# key -> default value. All default ON.
const DEFAULTS := {
	KEY_HIGHLIGHTING: true,
	KEY_DIAGNOSTICS: true,
	KEY_COMPLETION: true,
	KEY_HOVER: true,
	KEY_OPEN_IN_EDITOR: true,
	KEY_FORMAT_ON_SAVE: true,
}

## Register every reactive_ui_toolkit_editor/* setting (idempotent — safe to call on every _enter_tree).
static func register_all() -> void:
	var dirty := false
	for key in DEFAULTS:
		if not ProjectSettings.has_setting(key):
			ProjectSettings.set_setting(key, DEFAULTS[key])
			dirty = true
		# Always (re)assert the metadata so a hand-edited project.godot still gets a proper UI + revert.
		ProjectSettings.set_initial_value(key, DEFAULTS[key])
		ProjectSettings.add_property_info({
			"name": key,
			"type": TYPE_BOOL,
			"hint": PROPERTY_HINT_NONE,
			"hint_string": "",
		})
		ProjectSettings.set_as_basic(key, true)
	if dirty:
		ProjectSettings.save()

## Read a toggle, defaulting to ON when the setting is somehow absent.
static func is_enabled(key: String) -> bool:
	return bool(ProjectSettings.get_setting(key, true))
