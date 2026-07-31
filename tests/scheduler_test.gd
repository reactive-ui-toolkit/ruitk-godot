extends SceneTree
## Headless scheduler test suite. Run:
##   godot --headless --path <project> --script res://tests/scheduler_test.gd
## Exercises RuitkScheduler (the four-lane RenderScheduler port): lane priority order,
## High-starves-Normal escalation, Low-cancel-on-High, Idle gating + its budget/2 sub-budget,
## per-lane Callable dedup, batch begin/end deferral, the unbudgeted batched-effects flush,
## the cumulative per-frame budget, slice self-re-enqueue, pump_now, and metrics — plus the
## reconciler integration: a sliced render commits across scheduler pumps, mount is never
## sliced, and the sync path (time_slicing false) never touches the scheduler.
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

func _ok(cond: bool, msg: String) -> void:
	if cond:
		_passes += 1
	else:
		_fails += 1
		printerr("  FAIL: " + msg)
		push_error("FAIL: " + msg)
