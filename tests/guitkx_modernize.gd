extends SceneTree
## 0.11.0 modernization tripwire (M8.6): run the ES-modules codemod over res://examples and FAIL
## (exit 1) if it changes anything -- the committed tree must already be plain-syntax. A non-zero
## count means someone committed wrapper keywords (`component`/`hook`/`module`); the runner just
## rewrote them locally -- commit the result. Idempotency itself is pinned by guitkx_test.gd; this
## is the CI gate that keeps the tree modernized.
##   godot --headless --path . --script res://tests/guitkx_modernize.gd
const Migrate = preload("res://addons/reactive_ui_toolkit/guitkx/guitkx_migrate.gd")

func _initialize() -> void:
	var res := Migrate.modernize_all("res://examples")
	var changed: Array = res["changed"]
	print("[guitkx_modernize] scanned %d file(s), modernized %d" % [int(res["scanned"]), changed.size()])
	for p in changed:
		print("    modernized  %s" % p)
	quit(1 if changed.size() > 0 else 0)
