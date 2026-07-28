extends SceneTree
## 0.11.0 ES-modules modernization runner (SHIPPED with the addon, like dev/migrate_0_10_0.gd):
## rewrite every `.guitkx` in YOUR project to plain, signature-classified declarations —
## `component X {}` becomes `X() -> RUIVNode {}`, `hook use_x {}` becomes `use_x {}`,
## `module M { … }` hoists its members to top level (+ `@class_name M` so the binding stays M),
## and imports of hoisted modules flip to `import * as M`. Idempotent + re-runnable; run once
## after updating to 0.11.0:
##   godot --headless --path . --script res://addons/reactive_ui_toolkit/dev/migrate_0_11_0.gd
## Always migrates the WHOLE project: reference resolution needs every declaration in its
## universe, so there is deliberately no subtree mode.
const Migrate = preload("res://addons/reactive_ui_toolkit/guitkx/guitkx_migrate.gd")

func _initialize() -> void:
	var res := Migrate.modernize_all("res://")
	var changed: Array = res["changed"]
	print("[migrate_0_11_0] scanned %d file(s), modernized %d" % [int(res["scanned"]), changed.size()])
	for p in changed:
		print("    modernized  %s" % p)
	quit(0)
