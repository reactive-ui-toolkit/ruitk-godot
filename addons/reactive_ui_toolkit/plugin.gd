@tool
extends EditorPlugin
## The library is plain GDScript exposing global `class_name`s (V, Hooks, ReactiveRoot, ...), so
## it is usable as soon as the files exist -- enabling this plugin is optional for the RUNTIME.
## The plugin's job is the .guitkx toolchain: it watches the project filesystem and compiles each
## `Foo.guitkx` to a sibling `Foo.gd` (see RUIGuitkxCodegen). On compile it nudges the editor's
## EditorFileSystem so the generated script is picked up and hot-reloaded.
##
## RECOMPILE TRIGGERS (why more than filesystem_changed):
##   `.guitkx` is not a Godot-recognised resource type, so editing ONLY a `.guitkx` in an external
##   editor (VS Code) does not reliably flip EditorFileSystem's "changed" flag -> `filesystem_changed`
##   may not fire when you tab back, so the file never recompiled until a full editor restart. We ALSO
##   recompile on editor FOCUS-IN (NOTIFICATION_APPLICATION_FOCUS_IN): every time you return to Godot
##   from your editor, stale `.guitkx` are recompiled. is_stale() (mtime) keeps this cheap when nothing
##   changed. Diagnostics are DE-DUPLICATED (see _report): Godot's Errors dock is append-only (no engine
##   API clears it), so without dedup a persistently-broken file -- which stays stale and recompiles on
##   every focus-in -- would spam the dock with identical errors. We push each distinct error once and
##   print a green "resolved" line when a file starts compiling clean again.

const Codegen = preload("res://addons/reactive_ui_toolkit/guitkx/guitkx_codegen.gd")
const Diag = preload("res://addons/reactive_ui_toolkit/guitkx/guitkx_diag.gd")
const HmrDebugger = preload("res://addons/reactive_ui_toolkit/editor/hmr_debugger.gd")

## The oldest Godot this addon supports. Evidence-based floor (2026-07): the compiler/HMR core
## uses `ProjectSettings.get_global_class_list()` (added in 4.3), and the paired editor addon's
## bundled native analyzer is a GDExtension with `compatibility_minimum = "4.4"` — the two assets
## release together, so both claim 4.4. `FoldableContainer` (4.5) is is_class()/string-guarded and
## degrades gracefully below 4.5. Verified on 4.7.
const MIN_GODOT := "4.4"

## True when the running (or given, for tests) Godot version satisfies MIN_GODOT.
static func godot_supported(version_string: String = "") -> bool:
	var v := version_string
	if v == "":
		var info := Engine.get_version_info()
		v = "%d.%d.%d" % [int(info["major"]), int(info["minor"]), int(info["patch"])]
	var pa := v.split(".")
	var pb := MIN_GODOT.split(".")
	for i in maxi(pa.size(), pb.size()):
		var na := int(pa[i]) if i < pa.size() else 0
		var nb := int(pb[i]) if i < pb.size() else 0
		if na != nb:
			return na > nb
	return true

var _efs: EditorFileSystem
var _busy := false
var _busy_since := 0
# path -> the joined diagnostic string last reported for it, so we push_error/push_warning only when a
# file's diagnostics actually CHANGE (Godot's dock never clears; re-pushing on every focus-in = spam).
var _last_diags: Dictionary = {}
# Compiler-environment retry: when a sweep returns HELD files (vocabulary unreadable — the editor's
# first-scan window), "retrying on the next compile" must not wait for a user edit or focus change,
# or a cold open stays uncompiled until someone touches a file (field capture 2026-07-03: 3.5 hours).
# One pending timer at a time; retries are cheap (a held sweep attempts one read per file and stops),
# announced once per episode, and end the moment a sweep runs unheld.
const _ENV_RETRY_SECS := 2.0
var _env_retry_pending := false
var _env_retry_announced := false
# 0.7.1: the standing WATCH POLL. Focus-in and filesystem_changed both miss the common field case --
# save in VS Code while the Godot editor sits in the background (field capture 2026-07-04: a stale
# .guitkx survived 40 minutes and an editor restart unnoticed because no trigger ever fired while
# the file was saved). Poll the cheap read-only staleness predicate instead: an external save is
# picked up within ~_POLL_SECS with no focus dance and no restart. Known-broken files are
# hash-skipped in has_stale, so this never busy-recompiles a file that still errors.
const _POLL_SECS := 2.0
var _poll_timer: Timer
# Phase H: the Fast Refresh push channel into running play sessions (editor/hmr_debugger.gd).
var _hmr_dbg = null
# First sweep prints its summary even when nothing was stale -- cold-open proof of life. A silent
# Output after startup therefore means the PLUGIN IS NOT RUNNING, never "maybe nothing to do".
var _first_sweep_done := false
var _scan_waits := 0

func _enter_tree() -> void:
	# Godot-version gate: refuse politely instead of failing on a missing 4.3/4.4 API mid-sweep.
	# The runtime's global class_names still load (that needs no plugin); only the .guitkx
	# compile-on-save/HMR tooling is disabled on an unsupported engine.
	if not godot_supported():
		push_error("[reactive_ui_toolkit] Godot %s is not supported -- this addon needs Godot %s or newer (verified on 4.7). The .guitkx watcher stays disabled." % [Engine.get_version_info()["string"], MIN_GODOT])
		return
	_efs = EditorInterface.get_resource_filesystem()
	if _efs and not _efs.filesystem_changed.is_connected(_on_fs_changed):
		_efs.filesystem_changed.connect(_on_fs_changed)
	_poll_timer = Timer.new()
	_poll_timer.wait_time = _POLL_SECS
	_poll_timer.timeout.connect(_on_poll_timeout)
	add_child(_poll_timer)
	_poll_timer.start()
	_hmr_dbg = HmrDebugger.new()
	add_debugger_plugin(_hmr_dbg)
	_kick_initial_sweep()

# 0.6.2: the initial sweep must WAIT OUT the editor's first filesystem scan. Sweeping inside it
# is worthless-to-harmful: every FileAccess call flakes there -- mtimes read 0 (is_stale sees
# "fresh", the sweep silently finds nothing to do and nothing retries; field capture 2026-07-03:
# a stale demo survived a cold open uncompiled), source reads come back empty, and nothing is
# reliable until the scan settles. Headless/tests: is_scanning() is false -> immediate deferred
# sweep, the old behavior.
func _kick_initial_sweep() -> void:
	if _efs and _efs.is_scanning():
		print("[guitkx] editor is scanning -- initial .guitkx sweep runs when the scan completes")
		get_tree().create_timer(0.5).timeout.connect(_check_scan_done)
	else:
		call_deferred("_compile_all")

func _check_scan_done() -> void:
	if _efs == null:
		return
	if _efs.is_scanning():
		_scan_waits += 1
		if _scan_waits % 20 == 0:   # every ~10s: a scan that never settles must be VISIBLE, not silent
			print("[guitkx] still waiting for the editor's filesystem scan (%.0fs) -- the initial sweep runs after it" % (_scan_waits * 0.5))
		get_tree().create_timer(0.5).timeout.connect(_check_scan_done)
		return
	_compile_all()

func _on_poll_timeout() -> void:
	if _busy or _efs == null or _efs.is_scanning():
		return
	if Codegen.has_stale("res://"):
		_compile_all()

func _exit_tree() -> void:
	if _efs and _efs.filesystem_changed.is_connected(_on_fs_changed):
		_efs.filesystem_changed.disconnect(_on_fs_changed)
	_efs = null
	if _hmr_dbg != null:
		remove_debugger_plugin(_hmr_dbg)
		_hmr_dbg = null

func _notification(what: int) -> void:
	# Tab back into the Godot editor -> recompile any changed .guitkx. This is the reliable trigger:
	# it does not depend on Godot deciding a `.guitkx`-only edit counts as a filesystem change.
	if what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_compile_all()

func _on_fs_changed() -> void:
	# The mtime staleness guard makes this self-terminating: writing a .gd makes it newer than its
	# .guitkx, so the next filesystem_changed finds nothing stale and stops. _busy guards re-entry.
	# Mid-scan events are IGNORED (the 0.6.2 rule: FileAccess flakes inside the first scan, and
	# generated classes aren't registered yet so dependent parse-checks false-error): the initial
	# sweep runs when the scan settles, and the watch poll is is_scanning-gated the same way.
	if _efs and _efs.is_scanning():
		return
	_compile_all()

func _compile_all() -> void:
	if _efs == null:
		return
	if _busy:
		# A sweep that CRASHED mid-run (a script error anywhere below) never clears _busy, and
		# without a deadline that silences the plugin for the REST OF THE SESSION with zero
		# output -- indistinguishable from "nothing to do" (field capture 2026-07-04: repeated
		# saves, repeated restarts, never a compile). Treat a >30s busy as dead and sweep again:
		# a crash now costs one 30s outage, not the session -- and the resumed sweep re-hits
		# (and re-prints) the crash, so the cause stays visible in the Output.
		if Time.get_ticks_msec() - _busy_since < 30_000:
			return
		push_warning("[guitkx] the previous sweep never finished (crashed mid-run?) -- resuming sweeps")
	_busy = true
	_busy_since = Time.get_ticks_msec()
	var res: Dictionary = Codegen.compile_all("res://")
	# M4: hot-push only entries whose generated .gd PARSES (gd_ok). The old "push everything" rule
	# existed for a transient case -- a parent referencing a class the editor's registry hadn't caught
	# up to yet -- but post-M2 every guitkx-to-guitkx reference is PATH-based (V.comp / const preload),
	# not class-name-based, and the M4 two-pass makes gd_ok reliable (checked only after every .gd is
	# on disk). So a gd_ok=false entry genuinely doesn't parse and must NOT be hot-loaded; the in-game
	# injection retry (hmr.gd) still covers any pre-migration cached script that references bare names.
	if _hmr_dbg != null:
		var hot: Array = []
		for entry in res["compiled"]:
			if bool(entry.get("gd_ok", true)):
				hot.append(entry["gd_path"])
		_hmr_dbg.push_reload(hot, res.get("bindings", {}), res.get("refresh_roots", []))
	for orphan in res.get("removed", []):
		print("[guitkx] removed orphaned output %s (its .guitkx is gone -- renamed or deleted)" % orphan)
	# L9: forget the last-reported error body for sources that no longer exist. Without this, a
	# file deleted and later RECREATED with the same broken content matches its stale _last_diags
	# entry and its first error report is silently suppressed.
	for src_path in _last_diags.keys():
		if not FileAccess.file_exists(str(src_path)):
			_last_diags.erase(src_path)
	for entry in res["compiled"]:
		_efs.update_file(entry["gd_path"])
		# A file that previously errored now compiles clean -> announce it and forget its stale errors
		# (we can't wipe the dock, but a clear "resolved" line tells the user the fix landed).
		if _last_diags.has(entry["path"]):
			print_rich("[color=green][guitkx] %s: compile errors resolved.[/color]" % entry["path"])
			_last_diags.erase(entry["path"])
		print("[guitkx] compiled -> ", entry["gd_path"])
		_report_warnings(entry["path"], entry["warnings"])
	for e in res["errors"]:
		_report_error(e)
	# HELD files (compiler environment not ready) are NOT errors: no per-file dock line — the
	# loader's one-per-episode hold warning already announced it — just a scheduled retry so the
	# sweep re-runs by itself once the environment recovers.
	var held: Array = res.get("held", [])
	if held.is_empty():
		_env_retry_announced = false
	else:
		_schedule_env_retry(held.size())
	# Sweep summary: printed whenever the sweep DID anything, and unconditionally for the first
	# sweep of the session (cold-open proof of life -- see _first_sweep_done). Held-only sweeps
	# retry every couple of seconds while the environment recovers -- their one-per-episode line
	# already announced it, so they don't count as work here (a summary per retry floods Output).
	var attempted: int = (res["compiled"] as Array).size() + (res["errors"] as Array).size()
	if attempted > 0 or not _first_sweep_done:
		print("[guitkx] sweep: %d .guitkx tracked -- %d compiled, %d error(s), %d held" % [
			int(res.get("total", 0)), (res["compiled"] as Array).size(), (res["errors"] as Array).size(), held.size()])
	_first_sweep_done = true
	_busy = false

# One-shot deferred re-sweep while compiles are held. Bound method (not a lambda): if the plugin
# is freed before the timer fires, Godot drops the connection with the object.
func _schedule_env_retry(count: int) -> void:
	if _env_retry_pending:
		return
	_env_retry_pending = true
	if not _env_retry_announced:
		_env_retry_announced = true
		print("[guitkx] %d file(s) waiting for the compiler environment -- retrying every %.0fs until it recovers" % [count, _ENV_RETRY_SECS])
	get_tree().create_timer(_ENV_RETRY_SECS).timeout.connect(_on_env_retry_timeout)

func _on_env_retry_timeout() -> void:
	_env_retry_pending = false
	_compile_all()

# push_error only when THIS file's error set differs from what we last reported for it.
# One dock line PER diagnostic, "path:LINE:COL: CODE: message" (1-based, from the offsets the
# compiler threads through every diagnostic since T0.2) -- not a joined array string.
func _report_error(e: Dictionary) -> void:
	var path: String = e["path"]
	var lines := _diag_lines(path, e.get("diagnostics", []))
	if lines.is_empty():
		lines = ["%s: %s" % [path, str(e.get("error", "?"))]]
	var body := "\n".join(lines)
	if _last_diags.get(path, "") == "E:" + body:
		return
	_last_diags[path] = "E:" + body
	for ln in lines:
		push_error("[guitkx] " + ln)
	# Dock push_error entries navigate to THIS call site, not the .guitkx (parity plan L5), while
	# plain prints get their res:// paths linkified — so give errors the same clickable route the
	# "compiled ->" success lines already have. (The editor addon's Problems panel, Project scope,
	# mirrors these diagnostics with line-level navigation via the sidecar.)
	print_rich("[color=salmon][guitkx] errors in %s (details above)[/color]" % path)

func _report_warnings(path: String, warnings: Array) -> void:
	for ln in _diag_lines(path, warnings):
		push_warning("[guitkx] " + ln)

# Render structured diagnostics to per-line dock strings; line/col were derived at the codegen
# surface boundary (compile_file), so no source re-read is needed here.
func _diag_lines(path: String, diags: Array) -> Array:
	var out: Array = []
	for d in diags:
		if d is Dictionary and (d as Dictionary).has("code"):
			var dd := d as Dictionary
			var loc := ""
			if dd.has("line"):
				loc = "%d:%d: " % [int(dd["line"]) + 1, int(dd.get("col", 0)) + 1]
			var sev := int(dd.get("severity", Diag.ERROR))
			var sev_tag := "" if sev == Diag.ERROR else " (%s)" % Diag.severity_name(sev)
			out.append("%s:%s%s%s: %s" % [path, loc, dd.get("code", ""), sev_tag, dd.get("message", "")])
		else:
			out.append("%s: %s" % [path, str(d)])
	return out
