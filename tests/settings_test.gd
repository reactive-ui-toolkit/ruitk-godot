extends SceneTree
## Headless settings test suite. Run:
##   godot --headless --path <project> --script res://tests/settings_test.gd
## Exercises the reactive_ui_toolkit/* Project Settings bridge (RuitkSettings): register()
## idempotency + editor metadata, apply()'s differs-from-default guard (never clobbers statics
## assigned directly by user code), the auto/enabled/disabled tri-states, and the one-shot guard.
## Every ProjectSettings key the suite sets is cleared (set to null) before quitting, and nothing
## here calls ProjectSettings.save() with a non-default value in place, so the run leaves no
## residue in project.godot.

const Settings = preload("res://addons/reactive_ui_toolkit/core/settings.gd")

var _fails := 0
var _passes := 0

# Compiled defaults of the statics, captured before any test runs and restored after each one —
# hook_validation/strict_diagnostics compile to OS.is_debug_build(), so never hardcode them.
var _orig := {}

func _initialize() -> void:
	_run()

func _run() -> void:
	_orig = {
		"time_slicing": RuitkConfig.time_slicing,
		"frame_budget_ms": RuitkConfig.frame_budget_ms,
		"host_node_pool": RuitkConfig.host_node_pool,
		"enable_hook_validation": RuitkConfig.enable_hook_validation,
		"enable_strict_diagnostics": RuitkConfig.enable_strict_diagnostics,
		"diag_enabled": RuitkDiagnostics.enabled,
		"diag_capture": RuitkDiagnostics.capture,
	}
	# ORDER MATTERS for the no-residue promise: register() runs its first-ever (dirty -> save)
	# pass while every key equals its initial value, so nothing persists to project.godot; every
	# later set_setting is in-memory only because no further save ever happens.
	_test_apply_no_keys_is_noop()
	_test_register_idempotent()
	_test_apply_changed_keys()
	_test_default_value_does_not_clobber()
	_test_tri_state_hook_validation()
	_test_one_shot_guard()
	_cleanup_keys()
	print("\n[settings_test] %d passed, %d failed" % [_passes, _fails])
	quit(1 if _fails > 0 else 0)

func _restore_statics() -> void:
	RuitkConfig.time_slicing = _orig["time_slicing"]
	RuitkConfig.frame_budget_ms = _orig["frame_budget_ms"]
	RuitkConfig.host_node_pool = _orig["host_node_pool"]
	RuitkConfig.enable_hook_validation = _orig["enable_hook_validation"]
	RuitkConfig.enable_strict_diagnostics = _orig["enable_strict_diagnostics"]
	RuitkDiagnostics.enabled = _orig["diag_enabled"]
	RuitkDiagnostics.capture = _orig["diag_capture"]

## In --script mode plugins never load, so no register() ran: the keys must be absent (exactly
## the exported-game shape — Godot omits settings equal to their initial value), and apply()
## must leave every static at its compiled default.
func _test_apply_no_keys_is_noop() -> void:
	for key in Settings.DEFAULTS:
		_ok(not ProjectSettings.has_setting(key), "precondition: %s absent in --script mode" % key)
	Settings.apply()   # the first-ever call — also arms the one-shot guard tested below
	_ok(RuitkConfig.time_slicing == _orig["time_slicing"], "no keys: time_slicing untouched")
	_ok(RuitkConfig.frame_budget_ms == _orig["frame_budget_ms"], "no keys: frame_budget_ms untouched")
	_ok(RuitkConfig.host_node_pool == _orig["host_node_pool"], "no keys: host_node_pool untouched")
	_ok(RuitkConfig.enable_hook_validation == _orig["enable_hook_validation"], "no keys: enable_hook_validation untouched")
	_ok(RuitkConfig.enable_strict_diagnostics == _orig["enable_strict_diagnostics"], "no keys: enable_strict_diagnostics untouched")
	_ok(RuitkDiagnostics.enabled == _orig["diag_enabled"], "no keys: RuitkDiagnostics.enabled untouched")
	_ok(RuitkDiagnostics.capture == _orig["diag_capture"], "no keys: RuitkDiagnostics.capture untouched")

func _test_register_idempotent() -> void:
	Settings.register()
	Settings.register()   # second call must be a clean no-op (no error, nothing re-dirtied)
	for key in Settings.DEFAULTS:
		_ok(ProjectSettings.has_setting(key), "register(): %s present" % key)
		_ok(ProjectSettings.get_setting(key) == Settings.DEFAULTS[key],
			"register(): %s seeded with its default" % key)
	# Editor metadata (add_property_info) is readable back through get_property_list().
	var infos := {}
	for p in ProjectSettings.get_property_list():
		infos[p["name"]] = p
	var hv: Dictionary = infos.get(Settings.KEY_HOOK_VALIDATION, {})
	_ok(not hv.is_empty(), "hook_validation appears in the settings property list")
	_ok(int(hv.get("type", -1)) == TYPE_STRING, "hook_validation is a String setting")
	_ok(int(hv.get("hint", -1)) == PROPERTY_HINT_ENUM, "hook_validation carries the enum hint")
	_ok(str(hv.get("hint_string", "")) == Settings.TRI_STATE_HINT,
		"hook_validation enum is exactly '%s'" % Settings.TRI_STATE_HINT)
	var ts: Dictionary = infos.get(Settings.KEY_TIME_SLICING, {})
	_ok(int(ts.get("type", -1)) == TYPE_BOOL, "time_slicing registered as a bool")
	var fb: Dictionary = infos.get(Settings.KEY_FRAME_BUDGET_MS, {})
	_ok(int(fb.get("type", -1)) == TYPE_FLOAT, "frame_budget_ms registered as a float")
	# register() must never overwrite a value the user already changed (keys all exist now, so
	# this cannot dirty -> save).
	ProjectSettings.set_setting(Settings.KEY_TIME_SLICING, true)
	Settings.register()
	_ok(ProjectSettings.get_setting(Settings.KEY_TIME_SLICING) == true,
		"register() preserves an already-changed value")
	ProjectSettings.set_setting(Settings.KEY_TIME_SLICING, Settings.DEFAULTS[Settings.KEY_TIME_SLICING])

## A key whose stored value differs from the compiled default is applied onto the static.
func _test_apply_changed_keys() -> void:
	ProjectSettings.set_setting(Settings.KEY_TIME_SLICING, true)
	ProjectSettings.set_setting(Settings.KEY_FRAME_BUDGET_MS, 4.0)
	ProjectSettings.set_setting(Settings.KEY_HOST_NODE_POOL, false)
	ProjectSettings.set_setting(Settings.KEY_DIAG_ENABLED, true)
	ProjectSettings.set_setting(Settings.KEY_DIAG_CAPTURE, true)
	Settings.reapply()
	_ok(RuitkConfig.time_slicing == true, "changed key applies: time_slicing -> true")
	_ok(RuitkConfig.frame_budget_ms == 4.0, "changed key applies: frame_budget_ms -> 4.0")
	_ok(RuitkConfig.host_node_pool == false, "changed key applies: host_node_pool -> false")
	_ok(RuitkDiagnostics.enabled == true, "changed key applies: diagnostics/enabled -> true")
	_ok(RuitkDiagnostics.capture == true, "changed key applies: diagnostics/capture -> true")
	for key in [Settings.KEY_TIME_SLICING, Settings.KEY_FRAME_BUDGET_MS, Settings.KEY_HOST_NODE_POOL,
			Settings.KEY_DIAG_ENABLED, Settings.KEY_DIAG_CAPTURE]:
		ProjectSettings.set_setting(key, Settings.DEFAULTS[key])
	_restore_statics()

## A key present-but-equal-to-default must NOT clobber a static that user code assigned before
## mounting — `RuitkConfig.time_slicing = true` in a _ready (config.gd's documented API) must
## survive apply().
func _test_default_value_does_not_clobber() -> void:
	ProjectSettings.set_setting(Settings.KEY_TIME_SLICING, false)   # present AND equal to default
	ProjectSettings.set_setting(Settings.KEY_FRAME_BUDGET_MS, 8.0)
	RuitkConfig.time_slicing = true          # "user code" assigned directly, pre-mount
	RuitkConfig.frame_budget_ms = 12.0
	Settings.reapply()
	_ok(RuitkConfig.time_slicing == true, "default-valued key does not clobber a pre-assigned static (bool)")
	_ok(RuitkConfig.frame_budget_ms == 12.0, "default-valued key does not clobber a pre-assigned static (float)")
	_restore_statics()

func _test_tri_state_hook_validation() -> void:
	# "enabled" forces true regardless of build type.
	RuitkConfig.enable_hook_validation = false
	ProjectSettings.set_setting(Settings.KEY_HOOK_VALIDATION, "enabled")
	Settings.reapply()
	_ok(RuitkConfig.enable_hook_validation == true, "tri-state 'enabled' forces hook_validation ON")
	# "disabled" forces false regardless of build type.
	ProjectSettings.set_setting(Settings.KEY_HOOK_VALIDATION, "disabled")
	Settings.reapply()
	_ok(RuitkConfig.enable_hook_validation == false, "tri-state 'disabled' forces hook_validation OFF")
	# "auto" (the default) leaves the static wherever it is — both ways.
	ProjectSettings.set_setting(Settings.KEY_HOOK_VALIDATION, "auto")
	RuitkConfig.enable_hook_validation = true
	Settings.reapply()
	_ok(RuitkConfig.enable_hook_validation == true, "tri-state 'auto' leaves a true static alone")
	RuitkConfig.enable_hook_validation = false
	Settings.reapply()
	_ok(RuitkConfig.enable_hook_validation == false, "tri-state 'auto' leaves a false static alone")
	# strict_diagnostics shares the exact same code path; pin one direction as a tripwire.
	RuitkConfig.enable_strict_diagnostics = true
	ProjectSettings.set_setting(Settings.KEY_STRICT_DIAGNOSTICS, "disabled")
	Settings.reapply()
	_ok(RuitkConfig.enable_strict_diagnostics == false, "tri-state 'disabled' forces strict_diagnostics OFF")
	ProjectSettings.set_setting(Settings.KEY_HOOK_VALIDATION, Settings.DEFAULTS[Settings.KEY_HOOK_VALIDATION])
	ProjectSettings.set_setting(Settings.KEY_STRICT_DIAGNOSTICS, Settings.DEFAULTS[Settings.KEY_STRICT_DIAGNOSTICS])
	_restore_statics()

## apply() is one-shot (RuitkRoot.create calls it on every mount): after the first call it must
## be a free no-op; reapply() is the explicit test/dev override.
func _test_one_shot_guard() -> void:
	ProjectSettings.set_setting(Settings.KEY_TIME_SLICING, true)
	RuitkConfig.time_slicing = false
	Settings.apply()   # already armed by the first apply() in _test_apply_no_keys_is_noop
	_ok(RuitkConfig.time_slicing == false, "second apply() is a no-op (one-shot guard)")
	Settings.reapply()
	_ok(RuitkConfig.time_slicing == true, "reapply() bypasses the guard and applies")
	ProjectSettings.set_setting(Settings.KEY_TIME_SLICING, Settings.DEFAULTS[Settings.KEY_TIME_SLICING])
	_restore_statics()

## Clear every key this suite created (register() seeded all seven) so the run leaves no residue.
func _cleanup_keys() -> void:
	for key in Settings.DEFAULTS:
		ProjectSettings.set_setting(key, null)
		_ok(not ProjectSettings.has_setting(key), "cleanup: %s cleared" % key)

func _ok(cond: bool, msg: String) -> void:
	if cond:
		_passes += 1
	else:
		_fails += 1
		printerr("  FAIL: " + msg)
		push_error("FAIL: " + msg)
