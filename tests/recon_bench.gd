extends SceneTree
## Reconciler hot-path benchmark (permanent) — the before/after harness for the §0
## CRITICAL reconciler fixes in plans/FINAL_AUDIT_GODOT_OPTIMIZATIONS.md (GO-05..GO-08).
## Isolates reconcile+commit cost for N nodes under the workloads that matter, with NO
## raycast/textures/game-code, so a number here is PURE reconciler. This is a benchmark,
## not a pass/fail test (like bench.gd) — run it before and after each fix.
##   godot --headless --path <proj> --script res://tests/recon_bench.gd

const N := 2384

func _initialize() -> void:
	await _run()
	quit(0)

func _run() -> void:
	print("=== recon_bench: reconcile+commit, %d nodes, headless (no raycast/textures) ===" % N)
	await _bench("A  stable keys, position only            ", 0)
	await _bench("B  stable keys, pos+size+color (plain)   ", 1)
	await _bench("C  stable keys, pos + style={{modulate}} ", 2)
	await _bench("D  churning keys ~14%/frame + rich props ", 3)

func _bench(label: String, mode: int) -> void:
	var c := Control.new()
	c.size = Vector2(800, 600)
	root.add_child(c)
	var frame := { "n": 0 }
	var setter := { "fn": null }
	var precol: Array = []
	for i in range(100):
		precol.append(Color.from_hsv(i / 100.0, 0.7, 0.9))
	var comp := func(_p, _ch):
		var s = Hooks.useState(0)
		setter["fn"] = s[1]
		var f: int = frame["n"]
		var nodes: Array = []
		for i in range(N):
			var key: String
			if mode == 3 and (i + f) % 7 == 0:
				key = "c%d_%d" % [i, f]   # unique per frame -> this slot churns (unmount+mount)
			else:
				key = "e%d" % i
			var x := float((i * 7 + f * 3) % 800)
			var y := float((i * 13 + f * 5) % 600)
			var col: Color = precol[(i + f) % 100]
			var sz := 6.0 + float((i + f) % 10)
			var props := { "key": key, "position": Vector2(x, y) }
			if mode == 1 or mode == 3:
				props["size"] = Vector2(sz, sz)
				props["color"] = col
			if mode == 2 or mode == 3:
				props["style"] = { "modulate": col }
			nodes.append(V.ColorRect(props))
		return V.Control({}, nodes)
	var app := RuitkRoot.create(c, V.fc(comp))
	await process_frame
	await process_frame
	var warm := 10
	var measure := 60
	var t0 := 0
	for i in range(warm + measure):
		frame["n"] = i
		if i == warm:
			t0 = Time.get_ticks_usec()
		setter["fn"].call(i)
		await process_frame
	var ms := (Time.get_ticks_usec() - t0) / 1000.0 / measure
	print("  %s : %6.2f ms/frame  (%.0f fps)" % [label, ms, 1000.0 / ms])
	app.unmount()
	c.queue_free()
	await process_frame
