@tool
class_name RuitkSettings
extends RefCounted
## Project-Settings surface for the reactive_ui_toolkit runtime addon.
##
## Surfaces the existing runtime tunables (`RuitkConfig`, `RuitkDiagnostics`) as
## `reactive_ui_toolkit/*` Project Settings (shown as BASIC settings, so they appear without the
## "Advanced Settings" toggle), mirroring the sibling editor addon's RuitkEditorSettings pattern.
## The statics stay the live source of truth everywhere in the codebase — this class only seeds
## the editor UI (`register()`) and loads user-changed values onto the statics once at mount
## (`apply()`). Assigning the statics directly from code (`RuitkConfig.time_slicing = true`)
## keeps working exactly as documented in config.gd.

const GROUP := "reactive_ui_toolkit/"

const KEY_TIME_SLICING := GROUP + "runtime/time_slicing"
const KEY_TIME_SLICE_MS := GROUP + "runtime/time_slice_ms"
const KEY_FRAME_BUDGET_MS := GROUP + "runtime/frame_budget_ms"
const KEY_HOST_NODE_POOL := GROUP + "runtime/host_node_pool"
const KEY_HOOK_VALIDATION := GROUP + "runtime/hook_validation"
const KEY_STRICT_DIAGNOSTICS := GROUP + "runtime/strict_diagnostics"
const KEY_DIAG_ENABLED := GROUP + "diagnostics/enabled"
const KEY_DIAG_CAPTURE := GROUP + "diagnostics/capture"

## The tri-state hint for the two debug-gated validators. "auto" leaves the static at its current
## value (whose compiled default is `OS.is_debug_build()` — ON in debug, OFF in exported release);
## "enabled"/"disabled" force it on/off regardless of build type.
const TRI_STATE_HINT := "auto,enabled,disabled"

# key -> compiled default. These mirror the statics' own initializers (config.gd /
# diagnostics.gd); the two tri-states default to "auto" because their statics' compiled
# default is the non-constant `OS.is_debug_build()`.
const DEFAULTS := {
	KEY_TIME_SLICING: false,
	KEY_TIME_SLICE_MS: 2.0,
	KEY_FRAME_BUDGET_MS: 4.0,
	KEY_HOST_NODE_POOL: true,
	KEY_HOOK_VALIDATION: "auto",
	KEY_STRICT_DIAGNOSTICS: "auto",
	KEY_DIAG_ENABLED: false,
	KEY_DIAG_CAPTURE: false,
}

# One-shot guard for apply(): the mount path calls apply() on every RuitkRoot.create, and only
# the first call may do work.
static var _applied := false

## Register every reactive_ui_toolkit/* setting (idempotent — safe to call on every _enter_tree).
## Editor-only seeding: at runtime the settings are already baked into the project, so both
## plugins guard this call with `Engine.is_editor_hint()`.
static func register() -> void:
	var dirty := false
	for key in DEFAULTS:
		if not ProjectSettings.has_setting(key):
			ProjectSettings.set_setting(key, DEFAULTS[key])
			dirty = true
		# Always (re)assert the metadata so a hand-edited project.godot still gets a proper UI + revert.
		ProjectSettings.set_initial_value(key, DEFAULTS[key])
		ProjectSettings.add_property_info(_property_info(key))
		ProjectSettings.set_as_basic(key, true)
	if dirty:
		ProjectSettings.save()

## Load the reactive_ui_toolkit/* settings onto the RuitkConfig / RuitkDiagnostics statics.
## Called from the mount path (RuitkRoot.create) — one-shot, so it is zero-cost after the
## first call.
##
## A key is applied ONLY when `ProjectSettings.has_setting(key)` AND the stored value differs
## from the compiled default in DEFAULTS. Why both guards:
##   - Godot omits settings equal to their initial value from project.godot, so in exported
##     games and headless test runs only user-CHANGED keys exist at all.
##   - The differs-from-default guard means apply() never clobbers a value that user code or a
##     test assigned directly to the statics before mounting — the existing public API
##     (`RuitkConfig.time_slicing = true` in a _ready, per config.gd) must keep working.
## Tri-states: "auto" (the default) leaves the static at its current value; "enabled"/"disabled"
## force true/false.
static func apply() -> void:
	if _applied:
		return
	_applied = true
	_apply_now()

## Test hook: re-run the load regardless of the one-shot guard.
static func reapply() -> void:
	_applied = true
	_apply_now()

static func _apply_now() -> void:
	if _changed(KEY_TIME_SLICING):
		RuitkConfig.time_slicing = bool(ProjectSettings.get_setting(KEY_TIME_SLICING))
	if _changed(KEY_TIME_SLICE_MS):
		RuitkConfig.time_slice_ms = float(ProjectSettings.get_setting(KEY_TIME_SLICE_MS))
	if _changed(KEY_FRAME_BUDGET_MS):
		RuitkConfig.frame_budget_ms = float(ProjectSettings.get_setting(KEY_FRAME_BUDGET_MS))
	if _changed(KEY_HOST_NODE_POOL):
		RuitkConfig.host_node_pool = bool(ProjectSettings.get_setting(KEY_HOST_NODE_POOL))
	if _changed(KEY_HOOK_VALIDATION):
		match str(ProjectSettings.get_setting(KEY_HOOK_VALIDATION)):
			"enabled": RuitkConfig.enable_hook_validation = true
			"disabled": RuitkConfig.enable_hook_validation = false
			_: pass   # unrecognized value: treat as "auto", leave the static alone
	if _changed(KEY_STRICT_DIAGNOSTICS):
		match str(ProjectSettings.get_setting(KEY_STRICT_DIAGNOSTICS)):
			"enabled": RuitkConfig.enable_strict_diagnostics = true
			"disabled": RuitkConfig.enable_strict_diagnostics = false
			_: pass
	if _changed(KEY_DIAG_ENABLED):
		RuitkDiagnostics.enabled = bool(ProjectSettings.get_setting(KEY_DIAG_ENABLED))
	if _changed(KEY_DIAG_CAPTURE):
		RuitkDiagnostics.capture = bool(ProjectSettings.get_setting(KEY_DIAG_CAPTURE))

# True when `key` exists AND holds something other than its compiled default (see apply()).
static func _changed(key: String) -> bool:
	if not ProjectSettings.has_setting(key):
		return false
	return ProjectSettings.get_setting(key) != DEFAULTS[key]

# Editor metadata per key: the tri-states are String enums, everything else is typed off its default.
static func _property_info(key: String) -> Dictionary:
	var default_value = DEFAULTS[key]
	if default_value is String:
		return {
			"name": key,
			"type": TYPE_STRING,
			"hint": PROPERTY_HINT_ENUM,
			"hint_string": TRI_STATE_HINT,
		}
	return {
		"name": key,
		"type": typeof(default_value),
		"hint": PROPERTY_HINT_NONE,
		"hint_string": "",
	}
