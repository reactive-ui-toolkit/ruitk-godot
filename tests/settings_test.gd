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
		"time_slice_ms": RuitkConfig.time_slice_ms,
		"frame_budget_ms": RuitkConfig.frame_budget_ms,
		"host_node_pool": RuitkConfig.host_node_pool,
		"strict_mode": RuitkConfig.strict_mode,
		"enable_hook_validation": RuitkConfig.enable_hook_validation,
		"enable_strict_diagnostics": RuitkConfig.enable_strict_diagnostics,
		"environment": RuitkConfig.environment,
		"trace_level": RuitkDiagnostics.trace_level,
		"diff_tracing": RuitkDiagnostics.diff_tracing,
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
	_test_enum_knobs()
	_test_one_shot_guard()
	_cleanup_keys()
	print("\n[settings_test] %d passed, %d failed" % [_passes, _fails])
	quit(1 if _fails > 0 else 0)

func _restore_statics() -> void:
	RuitkConfig.time_slicing = _orig["time_slicing"]
	RuitkConfig.time_slice_ms = _orig["time_slice_ms"]
	RuitkConfig.frame_budget_ms = _orig["frame_budget_ms"]
	RuitkConfig.host_node_pool = _orig["host_node_pool"]
	RuitkConfig.strict_mode = _orig["strict_mode"]
	RuitkConfig.enable_hook_validation = _orig["enable_hook_validation"]
	RuitkConfig.enable_strict_diagnostics = _orig["enable_strict_diagnostics"]
	RuitkConfig.environment = _orig["environment"]
	RuitkDiagnostics.trace_level = _orig["trace_level"]
	RuitkDiagnostics.diff_tracing = _orig["diff_tracing"]
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
	_ok(RuitkConfig.time_slice_ms == _orig["time_slice_ms"], "no keys: time_slice_ms untouched")
	_ok(RuitkConfig.frame_budget_ms == _orig["frame_budget_ms"], "no keys: frame_budget_ms untouched")
	_ok(RuitkConfig.host_node_pool == _orig["host_node_pool"], "no keys: host_node_pool untouched")
	_ok(RuitkConfig.strict_mode == _orig["strict_mode"], "no keys: strict_mode untouched")
	_ok(RuitkConfig.enable_hook_validation == _orig["enable_hook_validation"], "no keys: enable_hook_validation untouched")
	_ok(RuitkConfig.enable_strict_diagnostics == _orig["enable_strict_diagnostics"], "no keys: enable_strict_diagnostics untouched")
	_ok(RuitkConfig.environment == _orig["environment"], "no keys: environment untouched")
	_ok(RuitkDiagnostics.trace_level == _orig["trace_level"], "no keys: trace_level untouched")
	_ok(RuitkDiagnostics.diff_tracing == _orig["diff_tracing"], "no keys: diff_tracing untouched")
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
	var tsm: Dictionary = infos.get(Settings.KEY_TIME_SLICE_MS, {})
	_ok(int(tsm.get("type", -1)) == TYPE_FLOAT, "time_slice_ms registered as a float")
	var sm: Dictionary = infos.get(Settings.KEY_STRICT_MODE, {})
	_ok(int(sm.get("type", -1)) == TYPE_BOOL, "strict_mode registered as a bool")
	# The two non-tri-state String enums carry their OWN vocabulary via HINTS (§4).
	var tl: Dictionary = infos.get(Settings.KEY_TRACE_LEVEL, {})
	_ok(int(tl.get("type", -1)) == TYPE_STRING and int(tl.get("hint", -1)) == PROPERTY_HINT_ENUM,
		"trace_level is a String enum setting")
	_ok(str(tl.get("hint_string", "")) == Settings.HINTS[Settings.KEY_TRACE_LEVEL]
		and str(tl.get("hint_string", "")) == "none,basic,verbose",
		"trace_level enum is exactly 'none,basic,verbose' (HINTS)")
	var env: Dictionary = infos.get(Settings.KEY_ENVIRONMENT, {})
	_ok(int(env.get("type", -1)) == TYPE_STRING and int(env.get("hint", -1)) == PROPERTY_HINT_ENUM,
		"environment is a String enum setting")
	_ok(str(env.get("hint_string", "")) == Settings.HINTS[Settings.KEY_ENVIRONMENT]
		and str(env.get("hint_string", "")) == "auto,development,production",
		"environment enum is exactly 'auto,development,production' (HINTS)")
	var dt: Dictionary = infos.get(Settings.KEY_DIFF_TRACING, {})
	_ok(int(dt.get("type", -1)) == TYPE_BOOL, "diff_tracing registered as a bool")
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
	ProjectSettings.set_setting(Settings.KEY_TIME_SLICE_MS, 1.0)
	ProjectSettings.set_setting(Settings.KEY_FRAME_BUDGET_MS, 6.0)   # ≠ the 4.0 default (L-02 re-scope)
	ProjectSettings.set_setting(Settings.KEY_HOST_NODE_POOL, false)
	ProjectSettings.set_setting(Settings.KEY_STRICT_MODE, true)
	ProjectSettings.set_setting(Settings.KEY_ENVIRONMENT, "production")
	ProjectSettings.set_setting(Settings.KEY_TRACE_LEVEL, "basic")
	ProjectSettings.set_setting(Settings.KEY_DIFF_TRACING, true)
	ProjectSettings.set_setting(Settings.KEY_DIAG_ENABLED, true)
	ProjectSettings.set_setting(Settings.KEY_DIAG_CAPTURE, true)
	Settings.reapply()
	_ok(RuitkConfig.time_slicing == true, "changed key applies: time_slicing -> true")
	_ok(RuitkConfig.time_slice_ms == 1.0, "changed key applies: time_slice_ms -> 1.0")
	_ok(RuitkConfig.frame_budget_ms == 6.0, "changed key applies: frame_budget_ms -> 6.0")
	_ok(RuitkConfig.host_node_pool == false, "changed key applies: host_node_pool -> false")
	_ok(RuitkConfig.strict_mode == true, "changed key applies: strict_mode -> true (the static round-trips; force-off lives at the READ site)")
	_ok(RuitkConfig.environment == "production", "changed key applies: environment -> 'production'")
	_ok(RuitkDiagnostics.trace_level == RuitkDiagnostics.TraceLevel.BASIC, "changed key applies: trace_level 'basic' -> TraceLevel.BASIC")
	_ok(RuitkDiagnostics.diff_tracing == true, "changed key applies: diff_tracing -> true")
	_ok(RuitkDiagnostics.enabled == true, "changed key applies: diagnostics/enabled -> true")
	_ok(RuitkDiagnostics.capture == true, "changed key applies: diagnostics/capture -> true")
	for key in [Settings.KEY_TIME_SLICING, Settings.KEY_TIME_SLICE_MS, Settings.KEY_FRAME_BUDGET_MS,
			Settings.KEY_HOST_NODE_POOL, Settings.KEY_STRICT_MODE, Settings.KEY_ENVIRONMENT,
			Settings.KEY_TRACE_LEVEL, Settings.KEY_DIFF_TRACING, Settings.KEY_DIAG_ENABLED, Settings.KEY_DIAG_CAPTURE]:
		ProjectSettings.set_setting(key, Settings.DEFAULTS[key])
	_restore_statics()

## A key present-but-equal-to-default must NOT clobber a static that user code assigned before
## mounting — `RuitkConfig.time_slicing = true` in a _ready (config.gd's documented API) must
## survive apply().
func _test_default_value_does_not_clobber() -> void:
	ProjectSettings.set_setting(Settings.KEY_TIME_SLICING, false)   # present AND equal to default
	ProjectSettings.set_setting(Settings.KEY_FRAME_BUDGET_MS, 4.0)
	ProjectSettings.set_setting(Settings.KEY_TIME_SLICE_MS, 2.0)
	RuitkConfig.time_slicing = true          # "user code" assigned directly, pre-mount
	RuitkConfig.frame_budget_ms = 12.0
	RuitkConfig.time_slice_ms = 5.0
	Settings.reapply()
	_ok(RuitkConfig.time_slicing == true, "default-valued key does not clobber a pre-assigned static (bool)")
	_ok(RuitkConfig.frame_budget_ms == 12.0, "default-valued key does not clobber a pre-assigned static (float)")
	_ok(RuitkConfig.time_slice_ms == 5.0, "default-valued key does not clobber a pre-assigned static (time_slice_ms)")
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

## The two non-tri-state String enums (P5): value -> static mapping, unknown-value
## degradation (a skewed dialog writing tri-state vocabulary must be harmless), and the
## environment read surface (RuitkConfig.environment_resolved()).
func _test_enum_knobs() -> void:
	# trace_level maps its strings onto the RuitkDiagnostics.TraceLevel ints.
	ProjectSettings.set_setting(Settings.KEY_TRACE_LEVEL, "verbose")
	Settings.reapply()
	_ok(RuitkDiagnostics.trace_level == RuitkDiagnostics.TraceLevel.VERBOSE, "trace_level 'verbose' -> TraceLevel.VERBOSE")
	ProjectSettings.set_setting(Settings.KEY_TRACE_LEVEL, "basic")
	Settings.reapply()
	_ok(RuitkDiagnostics.trace_level == RuitkDiagnostics.TraceLevel.BASIC, "trace_level 'basic' -> TraceLevel.BASIC")
	RuitkDiagnostics.trace_level = RuitkDiagnostics.TraceLevel.NONE
	ProjectSettings.set_setting(Settings.KEY_TRACE_LEVEL, "enabled")   # tri-state vocabulary = unknown here
	Settings.reapply()
	_ok(RuitkDiagnostics.trace_level == RuitkDiagnostics.TraceLevel.NONE, "unknown trace_level value leaves the static alone")
	# environment passes explicit labels through and ignores junk.
	ProjectSettings.set_setting(Settings.KEY_ENVIRONMENT, "development")
	Settings.reapply()
	_ok(RuitkConfig.environment == "development", "environment 'development' applies")
	_ok(RuitkConfig.environment_resolved() == "development", "resolved(): explicit 'development' passes through")
	RuitkConfig.environment = "auto"
	ProjectSettings.set_setting(Settings.KEY_ENVIRONMENT, "junk")
	Settings.reapply()
	_ok(RuitkConfig.environment == "auto", "unknown environment value leaves the static alone")
	# The read surface: "auto" (and any unrecognized static) resolves off the build type;
	# explicit labels win. Never hardcode the auto arm — it is OS.is_debug_build()-dependent.
	var auto_resolved := "development" if OS.is_debug_build() else "production"
	_ok(RuitkConfig.environment_resolved() == auto_resolved, "resolved(): 'auto' follows OS.is_debug_build()")
	RuitkConfig.environment = "production"
	_ok(RuitkConfig.environment_resolved() == "production", "resolved(): explicit 'production' passes through")
	RuitkConfig.environment = "weird"
	_ok(RuitkConfig.environment_resolved() == auto_resolved, "resolved(): unrecognized static resolves like 'auto'")
	ProjectSettings.set_setting(Settings.KEY_TRACE_LEVEL, Settings.DEFAULTS[Settings.KEY_TRACE_LEVEL])
	ProjectSettings.set_setting(Settings.KEY_ENVIRONMENT, Settings.DEFAULTS[Settings.KEY_ENVIRONMENT])
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

## Clear every key this suite created (register() seeded every DEFAULTS key) so the run leaves no residue.
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
