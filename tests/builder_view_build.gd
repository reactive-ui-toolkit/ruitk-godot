extends SceneTree
## Freshness tripwire for the `.guitkx` the ADDON itself ships. Run:
##   godot --headless --path <project> --script res://tests/builder_view_build.gd
##
## The builder's canvas is written in `.guitkx` and compiled to a sibling `.gd`, and unlike the
## examples' output that `.gd` is COMMITTED. It has to be: a user who installs the addon gets the
## folder as-is, and the plugin needs its own canvas before the compile-on-scan sweep has run --
## the plugin cannot compile the view it is about to load.
##
## Committed output goes stale. So this compiles every addon `.guitkx` in memory and compares it
## against what is on disk. On a mismatch it WRITES the fresh output and exits non-zero, exactly
## like the codemod tripwires: the fix is to commit what it rewrote.

const Codegen = preload("res://addons/reactive_ui_toolkit/guitkx/guitkx_codegen.gd")

const ADDON_ROOT := "res://addons"


func _initialize() -> void:
	var paths: Array = Codegen.find_all(ADDON_ROOT)
	if paths.is_empty():
		print("[builder_view_build] no .guitkx under %s -- nothing to check" % ADDON_ROOT)
		quit(0)
		return

	# The SWEEP's own inputs, resolved over the whole project: the component-class universe and the
	# class -> generated-.gd binding table. Compiled with empty ones instead, every guitkx-bound
	# tag lowers differently and the output never matches what the plugin writes -- so the
	# tripwire would report the same two files stale forever, rewriting them into a shape the
	# next sweep immediately undoes.
	var project_paths: Array = Codegen.find_all("res://")
	var pb: Dictionary = Codegen.project_bindings(project_paths)
	var known: Array = pb["known"]
	var bindings: Dictionary = pb["bindings"]

	var stale: Array = []
	var failed: Array = []
	for path in paths:
		# Compared BY BYTES, before and after. `compile_file` rewrites its output unconditionally
		# and reports nothing about whether the contents moved, so the only honest question is
		# what the file held a moment ago.
		var gd_path := str(path).get_basename() + ".gd"
		var before := FileAccess.get_file_as_string(gd_path) if FileAccess.file_exists(gd_path) else ""
		var result: Dictionary = Codegen.compile_file(str(path), known, bindings, false)
		if not bool(result.get("ok", false)):
			failed.append("%s: %s" % [path, str(result.get("error", "compile failed"))])
			continue
		if FileAccess.get_file_as_string(gd_path) != before:
			stale.append(gd_path)

	print("")
	if not failed.is_empty():
		for line in failed:
			printerr("[builder_view_build] %s" % line)
		printerr("[builder_view_build] %d addon .guitkx file(s) DO NOT COMPILE" % failed.size())
		quit(1)
		return
	if not stale.is_empty():
		for line in stale:
			printerr("[builder_view_build] regenerated %s" % line)
		printerr("[builder_view_build] %d committed output(s) were STALE -- commit what this rewrote"
			% stale.size())
		quit(1)
		return
	print("[builder_view_build] %d addon .guitkx file(s), every committed .gd is current" % paths.size())
	quit(0)
