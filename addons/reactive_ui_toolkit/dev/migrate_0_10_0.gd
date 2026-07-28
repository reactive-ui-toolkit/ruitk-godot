extends SceneTree
## 0.10.0 import-migration runner (SHIPPED with the addon, like dev/migrate_0_9_0.gd): rewrite every
## `.guitkx` in YOUR project to the explicit import model — `export ` on every top-level declaration
## plus one `import { … } from "…"` line per referenced file. Idempotent + re-runnable; hand-written
## `class_name` scripts are ambient and never touched. Run once after updating to 0.10.0:
##   godot --headless --path . --script res://addons/reactive_ui_toolkit/dev/migrate_0_10_0.gd
## Always migrates the WHOLE project: the import synthesizer needs every `.guitkx` declaration in
## its universe to resolve cross-directory references, so there is deliberately no subtree mode.
const Migrate = preload("res://addons/reactive_ui_toolkit/guitkx/guitkx_migrate.gd")

func _initialize() -> void:
	var res := Migrate.migrate_all("res://")
	var changed: Array = res["changed"]
	print("[migrate_0_10_0] scanned %d file(s), migrated %d" % [int(res["scanned"]), changed.size()])
	for p in changed:
		print("    migrated  %s" % p)
	quit(0)
