@tool
class_name RUIEditorDeps
extends RefCounted
## Dependency handshake against the `reactive_ui_toolkit` runtime addon (parity plan S1/S2/F9).
##
## This editor addon REQUIRES reactive_ui_toolkit (compiler/formatter/lexer). Referencing its global
## classes from a script that loads while the dependency is absent is a hard, unfriendly compile
## failure — so plugin.gd checks HERE first and only then loads the editor scripts (which may use
## the RUIGuitkx* classes directly). This file itself must never name them.

## Oldest reactive_ui_toolkit this editor is tested against. 0.5.0 pairs with 0.8.4: the Problems panel's
## project scope and the sidecar overlay read the sweep's refs/2106/2107 verdicts, and mixed-version
## reports are not worth debugging — the two assets release together.
const MIN_REACTIVE_UI := "0.8.4"

## Oldest Godot this editor addon supports: the bundled native analyzer is a GDExtension with
## `compatibility_minimum = "4.4"` (it will not even load below), and the runtime sibling's
## compiler core needs 4.3+ APIs — so the pair claims 4.4. Verified on 4.7.
const MIN_GODOT := "4.4"

const _DEP_DIR := "res://addons/reactive_ui_toolkit"
const _DEP_CFG := _DEP_DIR + "/plugin.cfg"
const _COMPILER := _DEP_DIR + "/guitkx/guitkx.gd"
const _FORMATTER := _DEP_DIR + "/guitkx/guitkx_formatter.gd"

## { ok: bool, reason: String, version: String } — reason is user-facing when not ok.
static func satisfied() -> Dictionary:
	# Godot-version gate FIRST: below MIN_GODOT the bundled analyzer GDExtension cannot load and
	# the runtime sibling's compiler core is missing engine APIs -- fail with the reason, not a
	# cascade of script errors.
	if not godot_version_ok():
		return {
			"ok": false, "version": "",
			"reason": "Godot %s is not supported -- Reactive UI Toolkit — Godot Editor needs Godot %s or newer (verified on 4.7)." % [str(Engine.get_version_info()["string"]), MIN_GODOT],
		}
	if not FileAccess.file_exists(_DEP_CFG):
		return {
			"ok": false, "version": "",
			"reason": "The 'Reactive UI Toolkit — Godot' addon (addons/reactive_ui_toolkit) is not installed. " +
				"Install it from the Godot Asset Store, then re-enable this plugin.",
		}
	var ver := installed_version()
	if ver != "" and _version_lt(ver, MIN_REACTIVE_UI):
		return {
			"ok": false, "version": ver,
			"reason": "Reactive UI Toolkit — Godot %s is installed, but this editor needs %s or newer. Update the 'Reactive UI Toolkit — Godot' addon." % [ver, MIN_REACTIVE_UI],
		}
	for p in [_COMPILER, _FORMATTER]:
		if not FileAccess.file_exists(p):
			return {
				"ok": false, "version": ver,
				"reason": "The 'Reactive UI Toolkit — Godot' addon looks incomplete (missing %s). Reinstall it." % p,
			}
	return { "ok": true, "reason": "", "version": ver }

## True when the running (or given, for tests) Godot version satisfies MIN_GODOT.
static func godot_version_ok(version_string: String = "") -> bool:
	var v := version_string
	if v == "":
		var info := Engine.get_version_info()
		v = "%d.%d.%d" % [int(info["major"]), int(info["minor"]), int(info["patch"])]
	return not _version_lt(v, MIN_GODOT)

static func installed_version() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(_DEP_CFG) != OK:
		return ""
	return str(cfg.get_value("plugin", "version", ""))

## Numeric semver compare (lexicographic would say "0.10.0" < "0.8.0").
static func _version_lt(a: String, b: String) -> bool:
	var pa := a.split(".")
	var pb := b.split(".")
	for i in maxi(pa.size(), pb.size()):
		var na := int(pa[i]) if i < pa.size() else 0
		var nb := int(pb[i]) if i < pb.size() else 0
		if na != nb:
			return na < nb
	return false
