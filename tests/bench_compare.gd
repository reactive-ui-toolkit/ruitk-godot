extends SceneTree
## Fair A/B: for each N, run NATIVE (pure Godot, direct node writes) then LIBRARY (our
## reconciler) back-to-back in one process, so each pair is at the same thermal state.
## The gap = ReactiveUI's reconcile/diff/commit overhead. Headless = CPU only (no GPU).
## Run: godot --headless --path <proj> --script res://tests/bench_compare.gd

func _initialize() -> void:
	_run()

func _run() -> void:
	for n in [300, 750, 1500, 2000]:
		var nat := await _native(n)
		var lib := await _lib(n)
		print("[cmp] N=%4d : native %.2f ms | library %.2f ms | overhead %.2f ms (%.1fx)" % [n, nat, lib, lib - nat, lib / nat])
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

func _step(boxes: Array) -> Array:
	var next: Array = []
	for b in boxes:
		var nvx: float = b["vx"]
		var nvy: float = b["vy"]
		var nx: float = b["x"] + nvx * 0.016
		var ny: float = b["y"] + nvy * 0.016
		if nx < 0.0 or nx > 790.0: nvx = -nvx
		if ny < 0.0 or ny > 590.0: nvy = -nvy
		next.append({ "id": b["id"], "x": nx, "y": ny, "vx": nvx, "vy": nvy, "color": b["color"] })
	return next

func _native(n: int) -> float:
	var c := Control.new(); c.size = Vector2(800, 600); root.add_child(c)
	var boxes := _make(n)
	var sz := Vector2(8, 8)
	var rects: Array = []
	for b in boxes:
		var r := ColorRect.new(); r.position = Vector2(b["x"], b["y"]); r.size = sz; r.color = b["color"]
		c.add_child(r); rects.append(r)
	await process_frame; await process_frame
	var t0 := 0
	for i in 115:
		boxes = _step(boxes)
		if i == 15: t0 = Time.get_ticks_usec()
		for j in n:
			rects[j].position = Vector2(boxes[j]["x"], boxes[j]["y"])
		await process_frame
	var ms := (Time.get_ticks_usec() - t0) / 1000.0 / 100.0
	c.queue_free(); await process_frame
	return ms

func _lib(n: int) -> float:
	var c := Control.new(); c.size = Vector2(800, 600); root.add_child(c)
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
	await process_frame; await process_frame
	var t0 := 0
	for i in 115:
		sim["boxes"] = _step(sim["boxes"])
		if i == 15: t0 = Time.get_ticks_usec()
		setb["fn"].call(sim["boxes"])
		await process_frame
	var ms := (Time.get_ticks_usec() - t0) / 1000.0 / 100.0
	app.unmount(); c.queue_free(); await process_frame
	return ms
