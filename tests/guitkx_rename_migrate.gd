extends SceneTree
## Codemod tripwire (0.13.0 rebrand): run the rename codemod over res://examples. The committed
## tree must already BE renamed -- a non-zero count means pre-0.13 spellings (the old class
## prefix or the old addon folder paths -- see MIGRATION-0.13.md's table) were committed; the
## runner just fixed them locally, so the fix is "commit what it rewrote". Idempotent +
## re-runnable. (The old spellings are deliberately not written out here -- the codemod itself
## would rewrite them.)
##   godot --headless --path . --script res://tests/guitkx_rename_migrate.gd
const Migrate = preload("res://addons/reactive_ui_toolkit/dev/migrate_0_13_0.gd")

func _initialize() -> void:
	var res := Migrate.migrate_all("res://examples")
	var changed: Array = res["changed"]
	print("[guitkx_rename_migrate] scanned %d file(s), migrated %d" % [int(res["scanned"]), changed.size()])
	for row in changed:
		print("    migrated  %s (%d change(s))" % [row["path"], int(row["count"])])
	quit(1 if changed.size() > 0 else 0)
