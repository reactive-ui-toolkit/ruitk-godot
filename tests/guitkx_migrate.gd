extends SceneTree
## Codemod runner (§M6): migrate every `.guitkx` under res://examples to the 0.10.0 import model
## (export-everything + explicit `import` lines). Idempotent + re-runnable -- a second run reports 0
## changed. Run BEFORE guitkx_build (Gate 2): the sweep must then produce a ZERO-23xx tree.
##   godot --headless --path . --script res://tests/guitkx_migrate.gd
const Migrate = preload("res://addons/reactive_ui_toolkit/guitkx/guitkx_migrate.gd")

func _initialize() -> void:
	var res := Migrate.migrate_all("res://examples")
	var changed: Array = res["changed"]
	print("[guitkx_migrate] scanned %d file(s), migrated %d" % [int(res["scanned"]), changed.size()])
	for p in changed:
		print("    migrated  %s" % p)
	# CI tripwire: the committed tree must already BE migrated -- a non-zero count means someone
	# committed pre-0.10 syntax (the runner just fixed it locally; commit the result).
	quit(1 if changed.size() > 0 else 0)
