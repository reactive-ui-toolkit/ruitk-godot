extends SceneTree
## Throughput benchmark: N keyed ColorRects re-rendered every frame (only `position`
## changes) — the same shape as the stress test. Measures the LIBRARY cost (reconcile +
## commit) in isolation; headless has no GPU rendering, so this is pure framework CPU.
## Run: godot --headless --path <proj> --script res://tests/bench.gd

func _initialize() -> void:
	_run()

func _run() -> void:
	for n in [300, 750, 1500, 2000, 3000]:
		await _bench(n)
	quit()

func _make(n: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var arr: Array = []
	for i in n:
		arr.append({ "id": "b%d" % i, "x": rng.randf() * 790.0, "y": rng.randf() * 590.0,
			"vx": rng.randf() * 100.0 - 50.0, "vy": rng.randf() * 100.0 - 50.0,
			"color": Color.from_hsv(rng.randf(), 0.7, 0.9) })
	return arr

func _bench(n: int) -> void:
	var c := Control.new()
	c.size = Vector2(800, 600)
	root.add_child(c)
	var sim := { "boxes": _make(n) }
	var setb := { "fn": null }
	var sz := Vector2(8, 8)
	var comp := func(_p, _ch):
		var s = Hooks.useState(sim["boxes"])
		setb["fn"] = s[1]
		var nodes: Array = []
		for b in s[0]:
			nodes.append(V.ColorRect({ "key": b["id"], "position": Vector2(b["x"], b["y"]), "size": sz, "color": b["color"] }))
		return V.Control({}, nodes)
	var app := RuitkRoot.create(c, V.fc(comp))
	await process_frame
	await process_frame

	var warm := 15
	var measure := 100
	var t0 := 0
	for i in (warm + measure):
		var next: Array = []
		for b in sim["boxes"]:
			var nvx: float = b["vx"]
			var nvy: float = b["vy"]
			var nx: float = b["x"] + nvx * 0.016
			var ny: float = b["y"] + nvy * 0.016
			if nx < 0.0 or nx > 790.0: nvx = -nvx
			if ny < 0.0 or ny > 590.0: nvy = -nvy
			next.append({ "id": b["id"], "x": nx, "y": ny, "vx": nvx, "vy": nvy, "color": b["color"] })
		sim["boxes"] = next
		if i == warm:
			t0 = Time.get_ticks_usec()
		setb["fn"].call(next)
		await process_frame

	var elapsed: float = (Time.get_ticks_usec() - t0) / 1000000.0
	print("[bench] N=%4d : %7.1f fps   (%.3f ms/frame, reconcile+commit, headless/no-GPU)" % [n, measure / elapsed, elapsed / measure * 1000.0])
	app.unmount()
	c.queue_free()
	await process_frame
