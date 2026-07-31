extends SceneTree
## Headless error-boundary latch + strict-mode test suite. Run:
##   godot --headless --path <project> --script res://tests/strict_boundary_test.gd
## Exercises the cooperative render-error latch (family parity P3 — RuitkFail + the
## reconciler's _handle_render_failure/_begin_error_boundary, ported from the Unreal leg's
## D-10 design): nearest-boundary capture, first-failure-wins, the captured-boundary rule
## (an active boundary's failing fallback escalates upward), mount-pass pending activation
## by key-path, reset_key recovery, the no-boundary error path, the error-restart cap, and
## the latch under time_slicing both off and on.
##
## NOTE: every latch test intentionally triggers push_error output ("render failed ...") —
## suites fail via quit code, not error output; the EXPECTED markers below flag the noise.

var _fails := 0
var _passes := 0
var _orig := {}

func _initialize() -> void:
	_run()

func _run() -> void:
	_orig = {
		"time_slicing": RuitkConfig.time_slicing,
		"time_slice_ms": RuitkConfig.time_slice_ms,
		"frame_budget_ms": RuitkConfig.frame_budget_ms,
	}
	print("  (latch suite: 'render failed' errors below are EXPECTED — they are the feature)")
	_test_latch_first_wins_api()
	_test_mount_pass_pending_activation()
	await _test_update_latch_nearest_boundary()
	_test_first_failure_wins_two_children()
	await _test_active_boundary_escalates()
	await _test_reset_key_recovers()
	await _test_no_boundary_push_error()
	_test_error_restart_cap()
	await _test_latch_under_slicing()
	await _test_fast_list_survives_poisoned_pass()
	_restore_config()
	print("\n[strict_boundary_test] %d passed, %d failed" % [_passes, _fails])
	quit(1 if _fails > 0 else 0)

func _restore_config() -> void:
	RuitkConfig.time_slicing = _orig["time_slicing"]
	RuitkConfig.time_slice_ms = _orig["time_slice_ms"]
	RuitkConfig.frame_budget_ms = _orig["frame_budget_ms"]

## Collect error-boundary fibers in DFS order (white-box: eb_active/eb_last_error pins).
func _find_ebs(fiber, out: Array) -> void:
	if fiber == null:
		return
	if fiber.tag == RuitkFiber.Tag.ERROR_BOUNDARY:
		out.append(fiber)
	var c = fiber.child
	while c != null:
		_find_ebs(c, out)
		c = c.sibling

# --------------------------------------------------------------------------
# The latch API itself
# --------------------------------------------------------------------------

func _test_latch_first_wins_api() -> void:
	RuitkFail.render("first")
	RuitkFail.render("second")   # nested failure is fallout — must not overwrite
	_ok(RuitkFail._consume() == "first", "first failure wins on the latch")
	_ok(RuitkFail._consume() == null, "consume clears the latch (second read is null)")

# --------------------------------------------------------------------------
# Mount-pass failure: pending activation recorded by key-path, adopted by the rebuild
# --------------------------------------------------------------------------

func _test_mount_pass_pending_activation() -> void:
	RuitkConfig.time_slicing = false
	var c := Control.new()
	root.add_child(c)
	var err: Array = []
	var failing := func(_p, _ch):
		RuitkFail.render("mount-boom")
		return null
	var app := RuitkRoot.create(c, V.error_boundary({
		"fallback": V.Label({ "text": "fb" }),
		"on_error": func(r): err.append(r),
	}, [V.fc(failing)]))
	# Mount is synchronous and so is the error rebuild: the fallback must land in THIS commit.
	_ok(c.get_child_count() == 1 and c.get_child(0) is Label and c.get_child(0).text == "fb",
		"mount-pass failure shows the fallback synchronously (pending activation adopted)")
	_ok(err == ["mount-boom"], "on_error invoked once with the reason (got %s)" % [err])
	var ebs: Array = []
	_find_ebs(app._reconciler._root_current, ebs)
	_ok(ebs.size() == 1 and ebs[0].eb_active and ebs[0].eb_last_error == "mount-boom",
		"committed boundary fiber carries eb_active + eb_last_error")
	app.unmount()
	c.queue_free()
	_restore_config()

# --------------------------------------------------------------------------
# Update-pass failure: nearest boundary captures; siblings + outer boundary unaffected
# --------------------------------------------------------------------------

func _test_update_latch_nearest_boundary() -> void:
	RuitkConfig.time_slicing = false
	var c := Control.new()
	root.add_child(c)
	var probe := { "fail": false, "set": null, "err": [] }
	var child := func(_p, _ch):
		if probe["fail"]:
			RuitkFail.render("boom-inner")
			return null
		return V.Label({ "text": "child-ok" })
	var app_c := func(_p, _ch):
		var s = Hooks.useState(0)
		probe["set"] = s[1]
		return V.error_boundary({ "fallback": V.Label({ "text": "outer-fb" }) }, [
			V.VBoxContainer({}, [
				V.Label({ "text": "sib" }),
				V.error_boundary({
					"fallback": V.Label({ "text": "inner-fb" }),
					"on_error": func(r): probe["err"].append(r),
				}, [V.fc(child, { "n": s[0] })]),
			]),
		])
	var app := RuitkRoot.create(c, V.fc(app_c))
	var vbox: Node = c.get_child(0)
	_ok(vbox.get_child(1).text == "child-ok", "mounted benign")
	probe["fail"] = true
	probe["set"].call(1)
	await process_frame
	await process_frame   # deletions (the replaced child label) fully settle
	_ok(vbox.get_child(1).text == "inner-fb", "NEAREST boundary shows its fallback (got '%s')" % vbox.get_child(1).text)
	_ok(vbox.get_child(0).text == "sib", "sibling outside the boundary unaffected")
	_ok(c.get_child(0) == vbox, "outer boundary did not activate (children intact)")
	_ok(probe["err"] == ["boom-inner"], "on_error got the reason exactly once (got %s)" % [probe["err"]])
	var ebs: Array = []
	_find_ebs(app._reconciler._root_current, ebs)
	_ok(ebs.size() == 2 and not ebs[0].eb_active, "outer boundary fiber stays inactive")
	_ok(ebs[1].eb_active and ebs[1].eb_last_error == "boom-inner", "inner boundary fiber latched with the reason")
	app.unmount()
	c.queue_free()
	_restore_config()
	await process_frame

# --------------------------------------------------------------------------
# First failure wins at the pass level: the second failing child never renders
# --------------------------------------------------------------------------

func _test_first_failure_wins_two_children() -> void:
	RuitkConfig.time_slicing = false
	var c := Control.new()
	root.add_child(c)
	var err: Array = []
	var fail_a := func(_p, _ch):
		RuitkFail.render("boom-a")
		return null
	var fail_b := func(_p, _ch):
		RuitkFail.render("boom-b")
		return null
	var app := RuitkRoot.create(c, V.error_boundary({
		"fallback": V.Label({ "text": "fb" }),
		"on_error": func(r): err.append(r),
	}, [V.fc(fail_a), V.fc(fail_b)]))
	_ok(c.get_child_count() == 1 and c.get_child(0).text == "fb", "fallback shown")
	_ok(err == ["boom-a"], "first failure wins — the pass unwinds before the second child renders (got %s)" % [err])
	app.unmount()
	c.queue_free()
	_restore_config()

# --------------------------------------------------------------------------
# Captured-boundary rule: an ACTIVE boundary's failing fallback escalates upward
# --------------------------------------------------------------------------

func _test_active_boundary_escalates() -> void:
	RuitkConfig.time_slicing = false
	var c := Control.new()
	root.add_child(c)
	var probe := { "fail": false, "set": null, "err_in": [], "err_out": [] }
	var bad_fb := func(_p, _ch):
		RuitkFail.render("boom-fb")
		return null
	var child := func(_p, _ch):
		if probe["fail"]:
			RuitkFail.render("boom-child")
			return null
		return V.Label({ "text": "child-ok" })
	var app_c := func(_p, _ch):
		var s = Hooks.useState(0)
		probe["set"] = s[1]
		return V.error_boundary({
			"fallback": V.Label({ "text": "outer-fb" }),
			"on_error": func(r): probe["err_out"].append(r),
		}, [
			V.error_boundary({
				"fallback": V.fc(bad_fb),
				"on_error": func(r): probe["err_in"].append(r),
			}, [V.fc(child, { "n": s[0] })]),
		])
	var app := RuitkRoot.create(c, V.fc(app_c))
	_ok(c.get_child(0).text == "child-ok", "mounted benign")
	probe["fail"] = true
	probe["set"].call(1)
	await process_frame
	await process_frame
	# Rebuild #1 renders the inner fallback, which itself fails; the inner boundary is now
	# ACTIVE and must be skipped (its fallback is what just failed) — the OUTER one captures.
	_ok(c.get_child(0).text == "outer-fb",
		"active boundary skipped; failure escalated to the next boundary up (got '%s')" % c.get_child(0).text)
	_ok(probe["err_in"] == ["boom-child"], "inner on_error saw the child failure (got %s)" % [probe["err_in"]])
	_ok(probe["err_out"] == ["boom-fb"], "outer on_error saw the fallback failure (got %s)" % [probe["err_out"]])
	app.unmount()
	c.queue_free()
	_restore_config()
	await process_frame

# --------------------------------------------------------------------------
# reset_key recovery
# --------------------------------------------------------------------------

func _test_reset_key_recovers() -> void:
	RuitkConfig.time_slicing = false
	var c := Control.new()
	root.add_child(c)
	var probe := { "fail": false, "set": null, "set_reset": null, "err": [] }
	var child := func(_p, _ch):
		if probe["fail"]:
			RuitkFail.render("boom")
			return null
		return V.Label({ "text": "child-ok" })
	var app_c := func(_p, _ch):
		var s = Hooks.useState(0)
		var rk = Hooks.useState(0)
		probe["set"] = s[1]
		probe["set_reset"] = rk[1]
		return V.error_boundary({
			"fallback": V.Label({ "text": "fb" }),
			"on_error": func(r): probe["err"].append(r),
			"reset_key": rk[0],
		}, [V.fc(child, { "n": s[0] })])
	var app := RuitkRoot.create(c, V.fc(app_c))
	probe["fail"] = true
	probe["set"].call(1)
	await process_frame
	await process_frame
	_ok(c.get_child(0).text == "fb", "boundary tripped")
	probe["fail"] = false            # the underlying problem is fixed ...
	probe["set_reset"].call(1)       # ... and a reset_key change clears the boundary
	await process_frame
	await process_frame
	_ok(c.get_child(0).text == "child-ok", "reset_key change clears the boundary and re-renders children (got '%s')" % c.get_child(0).text)
	var ebs: Array = []
	_find_ebs(app._reconciler._root_current, ebs)
	_ok(ebs.size() == 1 and not ebs[0].eb_active and ebs[0].eb_last_error == null,
		"reset cleared eb_active + eb_last_error")
	_ok(probe["err"] == ["boom"], "on_error fired only for the original failure")
	app.unmount()
	c.queue_free()
	_restore_config()
	await process_frame

# --------------------------------------------------------------------------
# No boundary above: error logged, output discarded, the rest of the tree stays
# --------------------------------------------------------------------------

func _test_no_boundary_push_error() -> void:
	RuitkConfig.time_slicing = false
	var c := Control.new()
	root.add_child(c)
	var probe := { "fail": false, "set": null }
	var child := func(_p, _ch):
		if probe["fail"]:
			RuitkFail.render("boom-nb")
			return null
		return V.Label({ "text": "ok" })
	var app_c := func(_p, _ch):
		var s = Hooks.useState(0)
		probe["set"] = s[1]
		return V.VBoxContainer({}, [
			V.Label({ "text": "sib" }),
			V.fc(child, { "n": s[0] }),
		])
	var app := RuitkRoot.create(c, V.fc(app_c))
	var vbox: Node = c.get_child(0)
	_ok(vbox.get_child_count() == 2, "mounted benign")
	print("  (no-boundary test: the following 'no error boundary above' error is EXPECTED)")
	probe["fail"] = true
	probe["set"].call(1)
	await process_frame
	await process_frame
	_ok(vbox.get_child_count() == 1 and vbox.get_child(0).text == "sib",
		"no restart without a boundary: the failed component renders empty, siblings stay")
	probe["fail"] = false
	probe["set"].call(2)
	await process_frame
	await process_frame
	_ok(vbox.get_child_count() == 2 and vbox.get_child(1).text == "ok",
		"rendering keeps working after a no-boundary failure (component recovered)")
	app.unmount()
	c.queue_free()
	_restore_config()
	await process_frame

# --------------------------------------------------------------------------
# The error-restart cap: a mount-path adopt-miss loop is bounded at 25 rebuilds
# --------------------------------------------------------------------------

func _test_error_restart_cap() -> void:
	RuitkConfig.time_slicing = false
	var c := Control.new()
	root.add_child(c)
	var probe := { "renders": 0, "err": 0 }
	var always_fail := func(_p, _ch):
		RuitkFail.render("cap-boom")
		return null
	# The boundary's KEY changes every render, so the recorded key-path NEVER matches on the
	# rebuild (the pending adoption misses), the child fails again, and the loop must be cut
	# by the cap instead of hanging the mount forever.
	var cap_app := func(_p, _ch):
		probe["renders"] += 1
		return V.error_boundary({
			"fallback": V.Label({ "text": "fb" }),
			"on_error": func(_r): probe["err"] += 1,
		}, [V.fc(always_fail)], "k%d" % probe["renders"])
	print("  (cap test: 26 'render failed' errors + one 'Too many error-boundary rebuilds' error are EXPECTED)")
	var app := RuitkRoot.create(c, V.fc(cap_app))
	_ok(probe["renders"] == 26, "initial pass + 25 rebuilds, then the cap (got %d renders)" % probe["renders"])
	_ok(probe["err"] == 26, "each pass captured once before its adopt-miss (got %d)" % probe["err"])
	_ok(c.get_child_count() == 0, "the pass was abandoned — nothing committed")
	_ok(app._reconciler._work_active == false and app._reconciler._restart == false,
		"reconciler is quiescent after the abandon")
	_ok(app._reconciler._pending_eb_activations.size() == 26,
		"every adopt-miss left its stale pending activation (got %d)" % app._reconciler._pending_eb_activations.size())
	app.unmount()   # must survive the abandoned pass (reclaimed WIP, stale pendings) without crashing
	c.queue_free()
	_restore_config()

# --------------------------------------------------------------------------
# The latch under time_slicing: the failure rebuild works inside a sliced pass
# --------------------------------------------------------------------------

func _test_latch_under_slicing() -> void:
	RuitkConfig.time_slicing = true
	RuitkConfig.time_slice_ms = 0.0     # yield after every unit — maximally sliced
	RuitkConfig.frame_budget_ms = 1000.0
	var c := Control.new()
	root.add_child(c)
	var probe := { "fail": false, "set": null, "err": [] }
	var child := func(_p, _ch):
		if probe["fail"]:
			RuitkFail.render("boom-sliced")
			return null
		return V.Label({ "text": "child-ok" })
	var app_c := func(_p, _ch):
		var s = Hooks.useState(0)
		probe["set"] = s[1]
		var items: Array = []
		for i in 10:
			items.append(V.Label({ "text": "row%d-%d" % [i, s[0]], "key": str(i) }))
		items.append(V.error_boundary({
			"fallback": V.Label({ "text": "fb" }),
			"on_error": func(r): probe["err"].append(r),
		}, [V.fc(child, { "n": s[0] })], "eb"))
		return V.VBoxContainer({}, items)
	var app := RuitkRoot.create(c, V.fc(app_c))
	var vbox: Node = c.get_child(0)
	_ok(vbox.get_child(10).text == "child-ok", "mounted benign (sliced mode, sync mount)")
	probe["fail"] = true
	probe["set"].call(1)
	var settled := false
	for i in 100:
		await process_frame
		if vbox.get_child_count() == 11 and vbox.get_child(10).text == "fb":
			settled = true
			break
	_ok(settled, "sliced pass rebuilt on failure and committed the fallback")
	if settled:
		_ok(vbox.get_child(0).text == "row0-1", "the sliced pass's other updates still landed")
	_ok(probe["err"] == ["boom-sliced"], "on_error fired exactly once under slicing (got %s)" % [probe["err"]])
	app.unmount()
	c.queue_free()
	_restore_config()
	await process_frame

# --------------------------------------------------------------------------
# Bughunt P3-1 pin: the fast-leaf-list path reuses LIVE fibers in place (alternate == null,
# committed nodes) directly inside the WIP chain — the abandoned-WIP reclaim of a poisoned
# pass must NOT sever them. Without the guard, the live sibling chain breaks and the next
# pass duplicates the whole row list on screen.
# --------------------------------------------------------------------------

func _test_fast_list_survives_poisoned_pass() -> void:
	RuitkConfig.time_slicing = false
	var c := Control.new()
	root.add_child(c)
	var probe := { "fail": false, "set": null }
	var child := func(_p, _ch):
		if probe["fail"]:
			RuitkFail.render("boom-fl")
			return null
		return V.Label({ "text": "child-ok" })
	var app_c := func(_p, _ch):
		var s = Hooks.useState(0)
		probe["set"] = s[1]
		var rows: Array = []
		for i in 10:
			rows.append(V.Label({ "text": "r%d-%d" % [i, s[0]], "key": str(i) }))
		return V.VBoxContainer({}, [
			V.VBoxContainer({ "name": "rows" }, rows),   # a stable keyed leaf list -> fast-list path
			V.error_boundary({ "fallback": V.Label({ "text": "fb" }) }, [V.fc(child, { "n": s[0] })]),
		])
	var app := RuitkRoot.create(c, V.fc(app_c))
	var outer: Node = c.get_child(0)
	var rows_box: Node = outer.get_child(0)
	_ok(rows_box.get_child_count() == 10 and outer.get_child(1).text == "child-ok", "mounted benign")
	var row0: Node = rows_box.get_child(0)
	var row9: Node = rows_box.get_child(9)
	# Update s=1: rows go through the update pass BEFORE the boundary child fails and
	# poisons it — the abandoned WIP holds the live fast-listed rows when reclaim runs.
	probe["fail"] = true
	probe["set"].call(1)
	await process_frame
	await process_frame
	_ok(outer.get_child(1).text == "fb", "boundary tripped in the same pass")
	_ok(rows_box.get_child_count() == 10, "fast-listed live rows intact after the poisoned pass (got %d)" % rows_box.get_child_count())
	# Identity, not just count: in-place reuse means the SAME node instances survive — a
	# severed chain reconstructed via pool recycling would swap instances and pass a
	# count-only assert.
	_ok(rows_box.get_child(0) == row0 and rows_box.get_child(9) == row9,
		"rows were reused IN PLACE (same node instances) across the poisoned pass")
	_ok(rows_box.get_child(0).text == "r0-1" and rows_box.get_child(9).text == "r9-1",
		"the rebuilt pass still committed the row updates")
	# A further update proves the live sibling chain survived (severed links would
	# duplicate or drop rows here).
	probe["set"].call(2)
	await process_frame
	await process_frame
	_ok(rows_box.get_child_count() == 10, "row list stable across the next pass (got %d)" % rows_box.get_child_count())
	_ok(rows_box.get_child(0).text == "r0-2" and rows_box.get_child(9).text == "r9-2", "rows keep updating in place")
	app.unmount()
	c.queue_free()
	_restore_config()
	await process_frame

func _ok(cond: bool, msg: String) -> void:
	if cond:
		_passes += 1
	else:
		_fails += 1
		printerr("  FAIL: " + msg)
		push_error("FAIL: " + msg)
