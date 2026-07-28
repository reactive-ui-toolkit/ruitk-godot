extends SceneTree
## Smoke test: mounts EVERY gallery demo (and the gallery shell) and asserts each one
## actually renders nodes without error. Catches a broken demo before it ships. Run:
##   godot --headless --path <project> --script res://tests/demos_test.gd

var _fails := 0
var _passes := 0

func _initialize() -> void:
	_run()

func _run() -> void:
	for entry in DemoGalleryTable.entries():
		await _smoke(entry["title"], entry["fn"])
	await _smoke("Gallery shell", DemoGallery.render)
	# Doom (plans/DOOM_GAME_GUITKX_PORT_PLAN.md) is a standalone scene, not routed
	# through the gallery (§1.8) -- smoke it directly so it's still covered by
	# this "every demo renders without error" sweep.
	await _smoke("Doom (Phase 1 static frame)", DoomGameScreen.render)
	await _test_root_fills()
	await _test_diagnostics_buttons()
	RuitkDiagnostics.enabled = false   # demos may have toggled these
	RuitkConfig.time_slicing = false
	print("\n[demos_test] %d passed, %d failed" % [_passes, _fails])
	quit(1 if _fails > 0 else 0)

func _smoke(title: String, fn: Callable) -> void:
	var c := Control.new()
	root.add_child(c)
	var app := RuitkRoot.create(c, V.fc(fn))
	await process_frame
	await process_frame   # let mount-effects (e.g. portal) settle
	if c.get_child_count() > 0:
		_passes += 1
	else:
		_fails += 1
		printerr("  FAIL: demo '%s' rendered no nodes" % title)
	app.unmount()
	c.queue_free()

## The gallery root uses style:{fill:true} -> it should fill the mount container.
func _test_root_fills() -> void:
	var c := Control.new()
	c.size = Vector2(900, 640)
	root.add_child(c)
	var app := RuitkRoot.create(c, V.fc(DemoGallery.render))
	await process_frame
	var hbox: Control = c.get_child(0)
	var fills: bool = hbox.size.x >= 880 and hbox.size.y >= 620
	if fills:
		_passes += 1
	else:
		_fails += 1
		printerr("  FAIL: root did not fill container, hbox size = %s" % str(hbox.size))
	app.unmount()
	c.queue_free()

## The Diagnostics demo's buttons must actually move the displayed numbers.
func _test_diagnostics_buttons() -> void:
	RuitkDiagnostics.reset()
	var c := Control.new()
	root.add_child(c)
	var app := RuitkRoot.create(c, V.fc(DemoDiagnostics.render))
	await process_frame
	await process_frame
	var labels: Array = []
	var buttons: Array = []
	_collect(c, "Label", labels)
	_collect(c, "Button", buttons)
	var rl: Node = null
	var trigger: Node = null
	var reset: Node = null
	for l in labels:
		if l.text.begins_with("renders:"):
			rl = l
	for b in buttons:
		if b.text.begins_with("Trigger"): trigger = b
		if b.text.begins_with("Reset"): reset = b
	if rl == null or trigger == null or reset == null:
		_fails += 1
		printerr("  FAIL: diagnostics controls not found")
		app.unmount(); c.queue_free(); return

	reset.emit_signal("pressed")
	await process_frame
	await process_frame
	if rl.text.begins_with("renders: 0 "):
		_passes += 1
	else:
		_fails += 1
		printerr("  FAIL: Reset did not zero the display: '%s'" % rl.text)

	trigger.emit_signal("pressed")
	await process_frame
	await process_frame
	if not rl.text.begins_with("renders: 0 "):
		_passes += 1
	else:
		_fails += 1
		printerr("  FAIL: Trigger did not update the display: '%s'" % rl.text)
	app.unmount()
	c.queue_free()

func _collect(node: Node, cls: String, out: Array) -> void:
	for ch in node.get_children():
		if ch.get_class() == cls:
			out.append(ch)
		_collect(ch, cls, out)
