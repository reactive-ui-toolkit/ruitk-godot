extends SceneTree
## Dev/CI helper: (re)compile EVERY .guitkx under res://examples to its sibling .gd, reporting
## compiler diagnostics. Text-level errors (markup/structure) fail the run here; GDScript-level
## errors surface when the project is scanned (run demos_test.gd next for the real render check).
##   godot --headless --path <project> --script res://tests/guitkx_build.gd
const Codegen = preload("res://addons/reactive_ui_toolkit/guitkx/guitkx_codegen.gd")

func _initialize() -> void:
	var errors := 0
	var warnings := 0
	var paths: Array = Codegen.find_all("res://examples")
	paths.sort()
	# Resolve the component universe + binding paths ONCE, exactly like the editor plugin's
	# compile_all pass -- so this helper emits byte-identical output (V.comp paths included).
	var pb: Dictionary = Codegen.project_bindings(paths)
	var known: Array = pb["known"]
	var bindings: Dictionary = pb["bindings"]
	# M4 TWO-PASS: value imports lower to `const X = preload("res://…​.gd")`, so a file can only
	# parse-check once its dependency's .gd exists. PASS 1 compiles + writes every .gd with the
	# throwaway parse check DEFERRED; PASS 2 re-checks each output now that all preloads are on disk.
	var gd_paths: Array = []
	for p in paths:
		var r: Dictionary = Codegen.compile_file(p, known, bindings, false)   # parse_check deferred
		if not r["ok"]:
			errors += 1
			printerr("COMPILE FAIL  %s" % p)
			for d in r.get("diagnostics", [str(r.get("error", "?"))]):
				printerr("    %s" % str(d))
			continue
		var warns: Array = []
		for d in r["diagnostics"]:
			warns.append(str(d))
		warnings += warns.size()
		gd_paths.append(r["gd_path"])
		if warns.is_empty():
			print("OK    %s -> %s" % [p, r["gd_path"]])
		else:
			print("WARN  %s -> %s" % [p, r["gd_path"]])
			for w in warns:
				print("    %s" % w)
	# PASS 2 — COUNTED parse gate. A generated .gd that does not parse (unknown identifier, a
	# value-import preloading a target that STILL doesn't exist) is a hard error and exits 1; a file
	# whose only problem was a not-yet-written dep now heals because every .gd is on disk.
	for gd in gd_paths:
		if not Codegen.gd_path_parses(str(gd)):
			errors += 1
			printerr("GDSCRIPT PARSE FAIL  %s (the generated script does not parse -- see the parser messages above)" % gd)
	print("\n[guitkx_build] %d file(s), %d error(s), %d warning(s)" % [paths.size(), errors, warnings])
	quit(1 if errors > 0 else 0)
