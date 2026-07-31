extends SceneTree
## Headless scheduler test suite. Run:
##   godot --headless --path <project> --script res://tests/scheduler_test.gd
## Exercises RuitkScheduler (the four-lane RenderScheduler port): lane priority order,
## High-starves-Normal escalation, Low-cancel-on-High, Idle gating + its budget/2 sub-budget,
## per-lane Callable dedup, batch begin/end deferral, the unbudgeted batched-effects flush,
## the cumulative per-frame budget, slice self-re-enqueue, pump_now, and metrics — plus the
## reconciler integration: a sliced render commits across scheduler pumps, mount is never
## sliced, and the sync path (time_slicing false) never touches the scheduler.
## Also the defer-don't-restart semantics (family parity P2): render-phase and commit-phase
## setStates defer + coalesce into ONE follow-up render, the render-depth-25 runaway guard,
## the sustained-updates starvation case, the superseded-tree redirect, and the
## detached-fiber bail.
##
## Determinism discipline (plan §9): every budget-sensitive unit test drives a FAKE clock
## through the scheduler's `time_source` seam — headless CI wall-clock timing is never
## asserted against. Integration tests use generous budgets + settle loops instead of tight
## real-time windows.

const SchedulerScript = preload("res://addons/reactive_ui_toolkit/core/scheduler.gd")
const P = SchedulerScript.Priority

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
	_test_lane_priority_order()
	_test_dedup_per_lane()
	_test_low_cancel_on_high()
	_test_high_starves_normal_escalation()
	_test_cumulative_budget_across_lanes()
	_test_idle_sub_budget()
	_test_batch_deferral()
	_test_batched_effects_flush_unbudgeted()
	_test_slice_self_reenqueue()
	_test_pump_now()
	await _test_sliced_render_commits()
	await _test_unmount_cancels_parked_slice()
	await _test_sync_path_untouched()
	await _test_defer_setstate_in_render_coalesces()
	await _test_defer_during_commit()
	await _test_render_depth_guard()
	await _test_sustained_updates_starvation()
	await _test_superseded_redirect()
	await _test_detached_fiber_bail()
	_restore_config()
	print("\n[scheduler_test] %d passed, %d failed" % [_passes, _fails])
	quit(1 if _fails > 0 else 0)

func _restore_config() -> void:
	RuitkConfig.time_slicing = _orig["time_slicing"]
	RuitkConfig.time_slice_ms = _orig["time_slice_ms"]
	RuitkConfig.frame_budget_ms = _orig["frame_budget_ms"]

## Fresh standalone scheduler + fake clock: [scheduler, clock]. Advance the clock from
## inside actions (`clock["t"] += ms`) to simulate slow work deterministically.
func _mk() -> Array:
	var sched = SchedulerScript.new()
	var clock := { "t": 0.0 }
	sched.time_source = func(): return clock["t"]
	return [sched, clock]

func _test_lane_priority_order() -> void:
	RuitkConfig.frame_budget_ms = 1000.0
	var pair := _mk()
	var s = pair[0]
	var order: Array = []
	s.enqueue(func(): order.append("i"), P.IDLE)
	s.enqueue(func(): order.append("l"), P.LOW)
	s.enqueue(func(): order.append("n"), P.NORMAL)
	s.pump()
	_ok(order == ["n", "l"], "normal runs before low; idle deferred while foreground ran (got %s)" % [order])
	s.pump()
	_ok(order == ["n", "l", "i"], "idle runs on the next quiet frame (got %s)" % [order])
	_ok(s.get_metrics()["idle_ran"] == 1, "idle execution counted")
	order.clear()
	s.enqueue(func(): order.append("n2"), P.NORMAL)
	s.enqueue(func(): order.append("h"), P.HIGH)
	s.pump()
	_ok(order == ["h", "n2"], "high lane drains before normal (got %s)" % [order])
	_restore_config()

func _test_dedup_per_lane() -> void:
	RuitkConfig.frame_budget_ms = 1000.0
	var pair := _mk()
	var s = pair[0]
	var count := { "n": 0 }
	var cb := func(): count["n"] += 1
	s.enqueue(cb, P.NORMAL)
	s.enqueue(cb, P.NORMAL)
	s.pump()
	_ok(count["n"] == 1, "same Callable enqueued twice in one lane runs once (got %d)" % count["n"])
	s.enqueue(cb, P.NORMAL)
	s.enqueue(cb, P.HIGH)
	s.pump()
	_ok(count["n"] == 3, "trackers are per lane: same Callable in two lanes runs in both (got %d)" % count["n"])
	_restore_config()

func _test_low_cancel_on_high() -> void:
	RuitkConfig.frame_budget_ms = 1000.0
	var pair := _mk()
	var s = pair[0]
	var ran := { "h": 0, "l": 0 }
	s.enqueue(func(): ran["l"] += 1, P.LOW)
	s.enqueue(func(): ran["l"] += 1, P.LOW)
	s.enqueue(func(): ran["h"] += 1, P.HIGH)
	s.pump()
	_ok(ran["h"] == 1 and ran["l"] == 0, "high+low non-empty at frame start -> ENTIRE low queue dropped")
	_ok(s.get_metrics()["low_cancelled"] == 2, "both cancelled low actions counted")
	s.pump()
	_ok(ran["l"] == 0, "cancelled low actions never run on a later frame (tracker cleared)")
	var lo := func(): ran["l"] += 1
	s.enqueue(lo, P.LOW)
	s.pump()
	_ok(ran["l"] == 1, "low runs normally once high is quiet (tracker re-accepts the Callable)")
	_restore_config()

func _test_high_starves_normal_escalation() -> void:
	RuitkConfig.frame_budget_ms = 4.0
	var pair := _mk()
	var s = pair[0]
	var clock = pair[1]
	var ran: Array = []
	var h1 := func():
		ran.append("h1")
		clock["t"] += 10.0
	var h2 := func():
		ran.append("h2")
		clock["t"] += 10.0
	s.enqueue(h1, P.HIGH)
	s.enqueue(h2, P.HIGH)
	s.enqueue(func(): ran.append("n"), P.NORMAL)
	s.pump()
	_ok(ran == ["h1"], "budget exhausted mid-high: h2 and normal held (got %s)" % [ran])
	_ok(s.get_metrics()["escalations"] == 1, "normal skipped behind a non-drained high queue = escalation")
	s.pump()
	_ok(ran == ["h1", "h2"], "next frame drains high; normal still over budget this frame (got %s)" % [ran])
	_ok(s.get_metrics()["escalations"] == 1, "high DID drain -> no second escalation")
	s.pump()
	_ok(ran == ["h1", "h2", "n"], "normal finally runs on a frame with budget (got %s)" % [ran])
	_restore_config()

func _test_cumulative_budget_across_lanes() -> void:
	RuitkConfig.frame_budget_ms = 4.0
	var pair := _mk()
	var s = pair[0]
	var clock = pair[1]
	var ran: Array = []
	var h := func():
		ran.append("h")
		clock["t"] += 3.0
	var n1 := func():
		ran.append("n1")
		clock["t"] += 2.0
	var n2 := func(): ran.append("n2")
	s.enqueue(h, P.HIGH)
	s.enqueue(n1, P.NORMAL)
	s.enqueue(n2, P.NORMAL)
	s.pump()
	# The budget is measured from the SHARED frame start: high spent 3 of the 4 ms, so the
	# normal lane gets only the remaining 1 ms — n1 starts inside it, n2 must wait.
	_ok(ran == ["h", "n1"], "normal lane inherits the elapsed high time (got %s)" % [ran])
	s.pump()
	_ok(ran == ["h", "n1", "n2"], "the held normal action runs next frame (got %s)" % [ran])
	_restore_config()

func _test_idle_sub_budget() -> void:
	RuitkConfig.frame_budget_ms = 4.0
	var pair := _mk()
	var s = pair[0]
	var clock = pair[1]
	var ran: Array = []
	var i1 := func():
		ran.append("i1")
		clock["t"] += 3.0   # > budget/2 (2.0) -> the idle sub-budget is spent
	var i2 := func(): ran.append("i2")
	s.enqueue(i1, P.IDLE)
	s.enqueue(i2, P.IDLE)
	s.pump()
	_ok(ran == ["i1"], "idle lane stops at the budget/2 sub-budget (got %s)" % [ran])
	_ok(s.get_metrics()["idle_ran"] == 1, "one idle action counted")
	s.pump()
	_ok(ran == ["i1", "i2"], "remaining idle work resumes on the next quiet frame (got %s)" % [ran])
	# idle never runs on a frame where foreground work ran
	ran.clear()
	s.enqueue(func(): ran.append("n"), P.NORMAL)
	s.enqueue(func(): ran.append("i3"), P.IDLE)
	s.pump()
	_ok(ran == ["n"], "foreground activity defers idle (got %s)" % [ran])
	s.pump()
	_ok(ran == ["n", "i3"], "idle drains once foreground is quiet (got %s)" % [ran])
	_restore_config()

func _test_batch_deferral() -> void:
	RuitkConfig.frame_budget_ms = 1000.0
	var pair := _mk()
	var s = pair[0]
	var ran: Array = []
	s.begin_batch()
	s.enqueue(func(): ran.append("n"), P.NORMAL)
	s.enqueue(func(): ran.append("h"), P.HIGH)
	s.pump()
	_ok(ran == ["h"], "during a batch: High passes through, non-High deferred (got %s)" % [ran])
	s.begin_batch()   # nested
	s.end_batch()
	s.pump()
	_ok(ran == ["h"], "inner end_batch does not flush (depth still > 0)")
	s.end_batch()     # outermost -> deferred enqueues flush into the queues
	s.pump()
	_ok(ran == ["h", "n"], "outermost end_batch releases the deferred enqueue (got %s)" % [ran])
	_restore_config()

func _test_batched_effects_flush_unbudgeted() -> void:
	RuitkConfig.frame_budget_ms = 4.0
	var pair := _mk()
	var s = pair[0]
	var clock = pair[1]
	var ran := { "effect": 0 }
	var slow := func(): clock["t"] += 50.0   # blow the whole frame budget
	s.enqueue(slow, P.NORMAL)
	s.enqueue_batched_effect(func(): ran["effect"] += 1)
	s.pump()
	_ok(ran["effect"] == 1, "batched effect flushed at frame end despite an exhausted budget")
	s.pump()
	_ok(ran["effect"] == 1, "flush clears the effect list (no re-run)")
	_restore_config()

func _test_slice_self_reenqueue() -> void:
	# The reference Slice pattern (FiberReconciler.cs:405-424): a 2 ms slice re-enqueues
	# itself while work remains, and the 4 ms cumulative budget lets several slices run in
	# ONE pump. With the fake clock at +2.0/slice and the strict `elapsed > budget` check,
	# a 5-slice job runs slices at elapsed 0/2/4 (three) on frame one and finishes on frame two.
	RuitkConfig.frame_budget_ms = 4.0
	var pair := _mk()
	var s = pair[0]
	var clock = pair[1]
	var state := { "remaining": 5, "fn": null }
	state["fn"] = func():
		state["remaining"] -= 1
		clock["t"] += 2.0
		if state["remaining"] > 0:
			s.enqueue(state["fn"], P.NORMAL)
	s.enqueue(state["fn"], P.NORMAL)
	s.pump()
	_ok(state["remaining"] == 2, "three 2 ms slices fit one 4 ms pump (got %d left)" % state["remaining"])
	s.pump()
	_ok(state["remaining"] == 0, "the re-enqueued remainder drains on the next pump")
	var m: Dictionary = s.get_metrics()
	_ok(m["actions"] == 5, "metrics: all five slice executions counted (got %d)" % m["actions"])
	_ok(m["frames"] == 2, "metrics: two pumps counted (got %d)" % m["frames"])
	_restore_config()

func _test_pump_now() -> void:
	RuitkConfig.frame_budget_ms = 1000.0
	var pair := _mk()
	var s = pair[0]
	var ran: Array = []
	s.enqueue(func(): ran.append("h"), P.HIGH)
	s.enqueue(func(): ran.append("n"), P.NORMAL)
	s.enqueue(func(): ran.append("l"), P.LOW)
	s.enqueue(func(): ran.append("i"), P.IDLE)
	s.enqueue_batched_effect(func(): ran.append("fx"))
	s.pump_now()
	_ok(ran == ["h", "n", "l", "i", "fx"], "pump_now drains all four lanes + flushes effects (got %s)" % [ran])
	_ok(s.get_metrics()["frames"] == 0, "pump_now is not a frame (renderedFrameCount untouched)")
	_restore_config()

## Integration: a sliced update (quantum 0 -> yield after EVERY unit, generous budget so CI
## speed can't flake it) commits correctly through the per-tree scheduler, and the mount
## itself is NEVER sliced (children exist before any frame elapses).
func _test_sliced_render_commits() -> void:
	RuitkConfig.time_slicing = true
	RuitkConfig.time_slice_ms = 0.0
	RuitkConfig.frame_budget_ms = 1000.0
	var c := Control.new()
	root.add_child(c)
	var ctrl := { "set": null }
	var comp := func(_p, _ch):
		var s = Hooks.useState(0)
		ctrl["set"] = s[1]
		var items: Array = []
		for i in 40:
			items.append(V.Label({ "text": "it %d-%d" % [i, s[0]], "key": str(i) }))
		return V.VBoxContainer({}, items)
	var app := RuitkRoot.create(c, V.fc(comp))
	var vbox: Node = c.get_child(0)
	_ok(vbox.get_child_count() == 40, "mount is never sliced: all 40 children exist synchronously")
	_ok(vbox.get_child(0).text == "it 0-0", "mount committed the initial text")
	ctrl["set"].call(1)
	var settled := false
	for i in 100:
		await process_frame
		if vbox.get_child_count() == 40 and vbox.get_child(39).text == "it 39-1":
			settled = true
			break
	_ok(settled, "sliced update committed via scheduler pumps")
	if settled:
		_ok(vbox.get_child(0).text == "it 0-1", "first item reached the new state")
	app.unmount()
	c.queue_free()
	_restore_config()
	await process_frame

## Integration: unmounting while a sliced render is parked leaves a stale slice entry in the
## scheduler queue — it must no-op (the _tick_pending cancellation guard), never resurrect
## work on the torn-down root.
func _test_unmount_cancels_parked_slice() -> void:
	RuitkConfig.time_slicing = true
	RuitkConfig.time_slice_ms = 0.0
	RuitkConfig.frame_budget_ms = 1000.0
	var c := Control.new()
	root.add_child(c)
	var ctrl := { "set": null }
	var comp := func(_p, _ch):
		var s = Hooks.useState(0)
		ctrl["set"] = s[1]
		return V.Label({ "text": "v%d" % s[0] })
	var app := RuitkRoot.create(c, V.fc(comp))
	_ok(c.get_child_count() == 1, "mounted synchronously")
	ctrl["set"].call(1)     # parks a slice on the scheduler
	app.unmount()           # cancels the pending tick before the pump ever runs it
	await process_frame     # the stale scheduler entry fires -> must no-op
	await process_frame
	_ok(c.get_child_count() == 0, "no zombie re-render after unmount (stale slice no-oped)")
	c.queue_free()
	_restore_config()
	await process_frame

## Integration: with time_slicing false nothing goes through the scheduler — the update
## commits on the very next frame via the call_deferred single-pass path (today's behavior).
func _test_sync_path_untouched() -> void:
	RuitkConfig.time_slicing = false
	var c := Control.new()
	root.add_child(c)
	var ctrl := { "set": null }
	var comp := func(_p, _ch):
		var s = Hooks.useState(0)
		ctrl["set"] = s[1]
		return V.Label({ "text": "v%d" % s[0] })
	var app := RuitkRoot.create(c, V.fc(comp))
	var label: Node = c.get_child(0)
	ctrl["set"].call(7)
	await process_frame
	_ok(label.text == "v7", "sync path commits within one frame (got '%s')" % label.text)
	app.unmount()
	c.queue_free()
	_restore_config()
	await process_frame

# --------------------------------------------------------------------------
# Defer-don't-restart (family parity P2) — FiberReconciler.cs:302-325, :884-909
# --------------------------------------------------------------------------

## setState DURING a render (reentrant, sync work loop) defers; N setStates in one pass
## coalesce into exactly ONE follow-up render, and every value lands.
func _test_defer_setstate_in_render_coalesces() -> void:
	RuitkConfig.time_slicing = false
	var c := Control.new()
	root.add_child(c)
	var probe := { "renders": 0, "fire": false, "set": null }
	var comp := func(_p, _ch):
		probe["renders"] += 1
		var s = Hooks.useState(0)
		var s2 = Hooks.useState(0)
		probe["set"] = s[1]
		if probe["fire"] and s[0] == 1:
			probe["fire"] = false
			s2[1].call(9)    # setState during render -> deferred, not restarted
			s2[1].call(10)   # a second one in the same pass -> coalesces into the SAME follow-up
		return V.Label({ "text": "a%d-b%d" % [s[0], s2[0]] })
	var app := RuitkRoot.create(c, V.fc(comp))
	var label: Node = c.get_child(0)
	_ok(probe["renders"] == 1, "mounted with one render")
	probe["fire"] = true
	probe["set"].call(1)
	await process_frame
	await process_frame
	_ok(label.text == "a1-b10", "both render-phase setStates landed (got '%s')" % label.text)
	_ok(probe["renders"] == 3, "exactly ONE coalesced follow-up render (mount + pass + follow-up = 3, got %d)" % probe["renders"])
	app.unmount()
	c.queue_free()
	_restore_config()
	await process_frame

## setState during the COMMIT phase (from a layout effect) takes the same deferred queue
## and coalesces into one follow-up render.
func _test_defer_during_commit() -> void:
	RuitkConfig.time_slicing = false
	var c := Control.new()
	root.add_child(c)
	var probe := { "renders": 0, "set": null }
	var comp := func(_p, _ch):
		probe["renders"] += 1
		var s = Hooks.useState(0)
		var s2 = Hooks.useState("x")
		probe["set"] = s[1]
		var fx := func():
			if s[0] == 1 and s2[0] == "x":
				s2[1].call("y")   # fires inside _commit_root (layout effects are commit-owned)
		Hooks.useLayoutEffect(fx, [s[0]])
		return V.Label({ "text": "%d-%s" % [s[0], s2[0]] })
	var app := RuitkRoot.create(c, V.fc(comp))
	var label: Node = c.get_child(0)
	probe["set"].call(1)
	await process_frame
	await process_frame
	_ok(label.text == "1-y", "commit-phase setState landed via the deferred queue (got '%s')" % label.text)
	_ok(probe["renders"] == 3, "one follow-up render for the commit-phase update (got %d)" % probe["renders"])
	app.unmount()
	c.queue_free()
	_restore_config()
	await process_frame

## An UNCONDITIONAL setState-in-render loop terminates via the render-depth-25 guard
## (FiberFunctionComponent.cs:16-18): the queued updates are dropped, the committed UI
## stays, and rendering stops.
func _test_render_depth_guard() -> void:
	RuitkConfig.time_slicing = false
	var c := Control.new()
	root.add_child(c)
	var probe := { "renders": 0 }
	var comp := func(_p, _ch):
		probe["renders"] += 1
		var s = Hooks.useState(0)
		s[1].call(s[0] + 1)   # unconditional setState during render — the classic runaway
		return V.Label({ "text": "n%d" % s[0] })
	print("  (depth-guard test: the following 'Too many re-renders' error is EXPECTED)")
	var app := RuitkRoot.create(c, V.fc(comp))
	await process_frame
	await process_frame
	var after: int = probe["renders"]
	_ok(after == 26, "depth guard stops the loop after mount + 25 follow-ups (got %d renders)" % after)
	await process_frame
	_ok(probe["renders"] == after, "loop stays terminated (no further renders)")
	_ok(c.get_child_count() == 1 and c.get_child(0) is Label, "committed UI intact after the abort")
	app.unmount()
	c.queue_free()
	_restore_config()
	await process_frame

## The starvation case the reference comment names (FiberReconciler.cs:311-320): sustained
## every-frame updates on a tree bigger than one slice must still COMMIT — the old
## restart-on-update model would begin the pass again every frame and never finish.
## Deterministic: the tree scheduler gets a fake clock, and a per-frame "jam" action blows
## the frame budget right after one slice ran, holding the pass to one unit per frame.
func _test_sustained_updates_starvation() -> void:
	RuitkConfig.time_slicing = true
	RuitkConfig.time_slice_ms = 0.0
	RuitkConfig.frame_budget_ms = 4.0
	var sched = SchedulerScript.for_tree(self)
	var clock := { "t": 0.0 }
	sched.time_source = func(): return clock["t"]
	var jam := func(): clock["t"] += 100.0
	var c := Control.new()
	root.add_child(c)
	var ctrl := { "set": null }
	var comp := func(_p, _ch):
		var s = Hooks.useState(0)
		ctrl["set"] = s[1]
		var items: Array = []
		for i in 12:
			items.append(V.Label({ "text": "s%d-%d" % [i, s[0]], "key": str(i) }))
		return V.VBoxContainer({}, items)
	var app := RuitkRoot.create(c, V.fc(comp))
	var vbox: Node = c.get_child(0)
	var committed_mid_storm := false
	var last := 0
	for i in range(1, 90):
		sched.enqueue(jam, SchedulerScript.Priority.NORMAL)
		ctrl["set"].call(i)
		last = i
		await process_frame
		if vbox.get_child(0).text != "s0-0":
			committed_mid_storm = true
	_ok(committed_mid_storm, "the pass commits under sustained per-frame updates (defer, not restart)")
	_ok(app._reconciler._render_depth == 0,
		"external sustained load never engages the render-depth guard (got depth %d)" % app._reconciler._render_depth)
	var settled := false
	for i in 100:
		await process_frame
		if vbox.get_child(0).text == "s0-%d" % last and vbox.get_child(11).text == "s11-%d" % last:
			settled = true
			break
	_ok(settled, "the coalesced final value lands once the storm stops (got '%s')" % vbox.get_child(0).text)
	app.unmount()
	c.queue_free()
	sched.time_source = Callable()
	_restore_config()
	await process_frame

## The P2.3 pin (plan §9 calls it mandatory): a deferred setState whose target fiber
## belongs to the SUPERSEDED generation still re-renders the right component. The window:
## the in-flight pass has already reconciled the component's position (carrying
## has_pending_update=false onto the WIP buddy) but not yet re-run its begin_function
## (which would re-bind state.fiber) — so the setter names the old-generation fiber, and
## without the replay redirect the flag would be clobbered by the next pass's carry and
## the component would bail out forever on its stale cached output.
func _test_superseded_redirect() -> void:
	RuitkConfig.time_slicing = true
	RuitkConfig.time_slice_ms = 0.0
	RuitkConfig.frame_budget_ms = 4.0
	var sched = SchedulerScript.for_tree(self)
	var clock := { "t": 0.0 }
	sched.time_source = func(): return clock["t"]
	var jam := func(): clock["t"] += 100.0
	var c := Control.new()
	root.add_child(c)
	var probe := { "parent_renders": 0, "set_parent": null, "set_b": null }
	var child_b := func(_p, _ch):
		var s = Hooks.useState("init")
		probe["set_b"] = s[1]
		return V.Label({ "text": s[0] })
	var child_a := func(_p, _ch):
		var items: Array = []
		for i in 14:
			items.append(V.Label({ "text": "f%d" % i, "key": str(i) }))
		return V.VBoxContainer({}, items)
	var parent := func(_p, _ch):
		probe["parent_renders"] += 1
		var s = Hooks.useState(0)
		probe["set_parent"] = s[1]
		return V.VBoxContainer({}, [V.fc(child_a), V.fc(child_b)])
	var app := RuitkRoot.create(c, V.fc(parent))
	var outer: Node = c.get_child(0)
	var b_label: Node = outer.get_child(1)
	_ok(b_label.text == "init", "mounted (child_b initial state)")
	probe["set_parent"].call(1)
	# March one unit per frame until the parent re-rendered (its children are reconciled —
	# the has_pending_update carry for child_b's position has already happened) ...
	var marched := false
	for i in 40:
		sched.enqueue(jam, SchedulerScript.Priority.NORMAL)
		await process_frame
		if probe["parent_renders"] >= 2:
			marched = true
			break
	_ok(marched, "sliced pass reached the parent render while parked")
	# ... then two more single-unit frames, placing the pass INSIDE child_a's subtree,
	# well before child_b's begin re-binds state.fiber ...
	sched.enqueue(jam, SchedulerScript.Priority.NORMAL)
	await process_frame
	sched.enqueue(jam, SchedulerScript.Priority.NORMAL)
	await process_frame
	# ... and set child_b's state: the setter targets the old-generation fiber.
	probe["set_b"].call("late")
	var settled := false
	for i in 100:
		await process_frame
		if b_label.text == "late":
			settled = true
			break
	_ok(settled, "deferred setState on an old-generation fiber re-renders the component (superseded-tree redirect), got '%s'" % b_label.text)
	app.unmount()
	c.queue_free()
	sched.time_source = Callable()
	_restore_config()
	await process_frame

## An update naming a fiber outside the live tree and its alternate (a deleted/detached
## subtree) is ignored with a warning — never scheduled (FiberReconciler.cs:282-289).
func _test_detached_fiber_bail() -> void:
	RuitkConfig.time_slicing = false
	var c := Control.new()
	root.add_child(c)
	var probe := { "renders": 0 }
	var comp := func(_p, _ch):
		probe["renders"] += 1
		return V.Label({ "text": "ok" })
	var app := RuitkRoot.create(c, V.fc(comp))
	var orphan := RuitkFiber.new()   # parentless — walks up to itself, matches no root
	print("  (detached-fiber test: the following 'detached fiber' warning is EXPECTED)")
	app._reconciler.schedule_update_on_fiber(orphan, null)
	await process_frame
	await process_frame
	_ok(probe["renders"] == 1, "update on a detached fiber is ignored (no re-render, got %d)" % probe["renders"])
	_ok(c.get_child(0).text == "ok", "live tree untouched")
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
