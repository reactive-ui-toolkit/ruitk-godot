extends SceneTree
## Headless regression test for the update path. Run with:
##   godot --headless --path <project> --script res://tests/update_test.gd
##
## Verifies: initial render, that a setState triggers exactly one coalesced re-render,
## that the host node is REUSED (diff/patch, not recreate), and that the prop updated.

func _initialize() -> void:
	_run()

func _run() -> void:
	var container := Control.new()
	root.add_child(container)

	var renders := { "n": 0 }
	var out := {}

	var comp := func(props, _children):
		var s = Hooks.useState(0)
		renders["n"] += 1
		props["out"]["set"] = s[1]      # expose the setter to the test
		return V.Label({ "text": "v=%d" % int(s[0]) })

	var app := RuitkRoot.create(container, V.fc(comp, { "out": out }))

	# --- initial render ---
	var label1: Node = container.get_child(0)
	_check(renders["n"] == 1, "initial render count == 1 (got %d)" % renders["n"])
	_check(label1 is Label and label1.text == "v=0", "initial label text 'v=0' (got '%s')" % label1.text)
	print("[test] initial: text='%s' renders=%d" % [label1.text, renders["n"]])

	# --- trigger an update ---
	out["set"].call(5)
	await process_frame      # let the deferred flush run
	await process_frame

	var label2: Node = container.get_child(0)
	_check(renders["n"] == 2, "one coalesced re-render (got %d)" % renders["n"])
	_check(label2 == label1, "host node REUSED across update (diff, not recreate)")
	_check(label2.text == "v=5", "updated label text 'v=5' (got '%s')" % label2.text)
	print("[test] update:  text='%s' renders=%d same_node=%s" % [label2.text, renders["n"], str(label2 == label1)])

	# --- coalescing: two sets in one frame => one render ---
	out["set"].call(10)
	out["set"].call(11)
	await process_frame
	await process_frame
	_check(renders["n"] == 3, "two sets in a frame coalesce to one render (got %d)" % renders["n"])
	_check(label1.text == "v=11", "final text 'v=11' (got '%s')" % label1.text)
	print("[test] coalesce: text='%s' renders=%d" % [label1.text, renders["n"]])

	app.unmount()
	print("[test] ALL PASSED")
	quit()

func _check(ok: bool, msg: String) -> void:
	if not ok:
		push_error("[test] FAILED: " + msg)
		printerr("[test] FAILED: " + msg)
		quit(1)
