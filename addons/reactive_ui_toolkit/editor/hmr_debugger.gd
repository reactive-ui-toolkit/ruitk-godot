@tool
extends EditorDebuggerPlugin
## Editor side of runtime Fast Refresh (Phase H). plugin.gd registers one instance via
## add_debugger_plugin; after every sweep that compiled files it calls push_reload with the
## generated .gd paths, and we forward them to every RUNNING game session over the debugger
## protocol ("rui_hmr:reload"). The game side (core/hmr.gd) reloads the scripts in place,
## re-renders the affected components, and replies on "rui_hmr:status", which we print into
## the editor Output right next to the sweep lines -- the full save->screen loop is visible
## in one place.
##
## No session (nothing running, or run-without-debugger)? push_reload is a no-op. Godot's own
## "Synchronize Script Changes" can never do this job: it only fires for saves made in the
## built-in script editor, and every .gd in this pipeline is written by the compiler
## (godot#72825) -- hence this channel.

## Push freshly-compiled generated .gd paths into every live play session. `bindings` is the
## project's full class -> generated-.gd map: the game uses it to hot-LINK components whose
## global class_name was created after launch (unresolvable by name until the next run).
## `refresh_roots` (M5) = generated .gd paths of the COMPONENT importers of any changed hooks/module
## file this sweep -- the game re-renders exactly those instead of the whole world (React Fast Refresh
## parity). Sending a 3-element message stays wire-compatible: an older running game reads only the
## first two and takes the global-rerender fallback.
func push_reload(gd_paths: Array, bindings: Dictionary = {}, refresh_roots: Array = []) -> void:
	if gd_paths.is_empty():
		return
	var pushed := 0
	for s in get_sessions():
		var session := s as EditorDebuggerSession
		if session != null and session.is_active():
			session.send_message("rui_hmr:reload", [gd_paths, bindings, refresh_roots])
			pushed += 1
	# ALWAYS say what happened -- "-> 0 session(s)" means no debugger-attached game was running
	# (not launched via F5, or already closed), which is otherwise indistinguishable from a
	# push that vanished (field capture 2026-07-04: a silent log hid exactly this question).
	print("[guitkx] hmr push: %d script(s) -> %d session(s)" % [gd_paths.size(), pushed])

func _has_capture(capture: String) -> bool:
	return capture == "rui_hmr"

## The game's replies. Engine versions differ on whether the prefix is stripped for editor-side
## captures, so accept both spellings. The ACK fires before the game does any work (delivery
## proof); the STATUS always prints a verdict -- when nothing reloaded, the per-file outcomes
## say WHY (uncached / identical / failed), so game-side behavior can never be silent.
func _capture(message: String, data: Array, _session_id: int) -> bool:
	if message == "ack" or message == "rui_hmr:ack":
		print("[guitkx] hmr: game acknowledged %d script(s)" % (int(data[0]) if data.size() > 0 else -1))
		return true
	if message != "status" and message != "rui_hmr:status":
		return false
	var d: Dictionary = data[0] if (data.size() > 0 and data[0] is Dictionary) else {}
	var errs: Array = d.get("errors", [])
	if int(d.get("reloaded", 0)) > 0:
		var line := "[guitkx] hot-reloaded %d script(s) -> %d component(s) re-rendered in %d ms" % [
			int(d.get("reloaded", 0)), int(d.get("refreshed", 0)), int(d.get("ms", 0))]
		if int(d.get("reset", 0)) > 0:
			line += " (%d state reset: hook shape changed)" % int(d.get("reset", 0))
		if int(d.get("linked", 0)) > 0:
			line += " (%d new component(s) linked live)" % int(d.get("linked", 0))
		if bool(d.get("global", false)):
			line += " (global re-render: a hooks module changed)"
		print_rich("[color=cyan]%s[/color]" % line)
	else:
		var bits: Array = []
		var outs: Dictionary = d.get("outcomes", {})
		for path in outs:
			bits.append("%s: %s" % [str(path).get_file(), str(outs[path])])
		print("[guitkx] hmr: nothing reloaded (%s)" % ("; ".join(bits) if not bits.is_empty() else "no outcomes reported"))
	for e in errs:
		push_warning("[guitkx] hmr: %s" % str(e))
	return true
