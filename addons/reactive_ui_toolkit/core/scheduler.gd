class_name RuitkScheduler
extends RefCounted
## Four-lane cooperative render scheduler — a faithful port of the Unity leg's
## RenderScheduler (ruitk-unity/Runtime/Core/RenderScheduler.cs), engine-idiomatic per the
## family parity plan (L-09): pumped from `SceneTree.process_frame` (Godot's LateUpdate
## analog) via a lazily-created per-SceneTree instance — no autoload, no plugin-enable —
## and fully headless-testable by constructing one directly and calling `pump()` manually.
##
## Lane algorithm (byte-loyal to RenderScheduler.cs `LateUpdate`, :116-164):
##   1. If High AND Low are both non-empty at frame start, the ENTIRE Low queue is
##      cancelled (dropped and counted) — stale low-priority work must not run after
##      urgent work supersedes it.
##   2. High runs first. Normal runs only if High drained (otherwise the skip is counted
##      as an escalation). Low runs after both.
##   3. Idle runs only when NOTHING ran, all foreground queues are empty, AND elapsed time
##      is still under budget/2 — and it gets a budget/2 sub-budget of its own.
##   4. The batched-effects flush runs UNBUDGETED at frame end, every frame.
##
## The per-frame budget (`budget_ms()` -- this instance's `frame_budget_ms` when it has one,
## `RuitkConfig.frame_budget_ms` read live otherwise) is CUMULATIVE across all
## lanes: every `_execute_queue` call in one pump measures from the same frame-start
## timestamp (:166-204). Budget checks happen BETWEEN actions — a long action overruns
## (cooperative, no preemption). A render pass participates as a self-re-enqueueing slice
## action (see reconciler.gd `_scheduled_slice`), so a 2 ms slice can run twice inside a
## 4 ms budget in one frame.
##
## Enqueue dedup is per lane via Callable identity (the HashSet-tracker pattern, :62-84):
## the same Callable enqueued twice in one lane runs once. `begin_batch`/`end_batch` defer
## non-High enqueues until the outermost batch ends (:54-57, :88-114).
##
## GDScript divergence: no try/catch, so there is no per-action exception guard — a failing
## render goes through the cooperative RuitkFail latch instead (family parity P3). An
## invalidated Callable (freed target object) is skipped but still counted, the closest
## analog of the reference's caught-and-logged action exception (:192-199).

enum Priority { HIGH, NORMAL, LOW, IDLE }

## Test seam: when valid, called instead of the real clock and must return milliseconds as
## a float. Lets the suite drive budget exhaustion deterministically (headless CI wall-clock
## timing is too flaky to assert against).
var time_source: Callable = Callable()

## THIS INSTANCE'S per-frame budget in ms, or -1 to read `RuitkConfig.frame_budget_ms`.
##
## The reference gives every editor pane a scheduler of its own with its own `TickBudgetMs`
## (BuilderRenderScheduler; VISUAL_EDITOR_PLAN VE-10), and the reason it states is structural
## rather than cosmetic: queues that are process-global with a process-global budget let ONE
## surface's runaway render starve every other surface sharing the pump. Here the sharing is
## per-SceneTree rather than per-process, which in a game is the same tree the UI belongs to --
## but in the EDITOR it is the tree that also runs the builder's canvas, the preview stage and
## anything else an addon mounted. A root created through `RuitkRoot.create_isolated` owns an
## instance of this class with its own budget, so a preview that will not settle costs the
## preview its frames and nobody else theirs.
var frame_budget_ms := -1.0

## The tree pumping this instance, when it is an OWNED one. The per-SceneTree instances
## `for_tree` hands out leave this null: they live as long as their tree and are never detached.
var _pumped_tree: SceneTree = null

# One FIFO Array[Callable] + one dedup tracker Dictionary (Callable -> true) per lane,
# indexed by Priority (RenderScheduler.cs:10-17).
var _queues: Array = [[], [], [], []]
var _trackers: Array = [{}, {}, {}, {}]

var _batched_effects: Array = []
var _deferred_batch_enqueues: Array = []   # [Callable, Priority] pairs (:22, :54-57)
var _batch_depth := 0

# Metrics (RenderScheduler.cs:24-29).
var _rendered_frame_count := 0
var _executed_action_count := 0
var _escalation_count := 0
var _low_cancelled_count := 0
var _idle_executed_count := 0
var _last_frame_start_ms := 0.0

## Lazily-created per-SceneTree instances, keyed by the tree's instance id. The pump
## connection holds the scheduler alive for the tree's lifetime; entries whose tree died
## are pruned on the next lookup.
static var _by_tree: Dictionary = {}

## An INDEPENDENT scheduler, outside the per-SceneTree table, with a budget of its own.
##
## Owned by whoever asks for it: attach it to a tree to have it pumped, and `detach()` it when
## the surface it serves goes away. `RuitkRoot.create_isolated` does both.
static func owned(budget_ms := -1.0) -> RuitkScheduler:
	var sched := RuitkScheduler.new()
	sched.frame_budget_ms = budget_ms
	return sched

## Pumps this scheduler from `tree`'s frames. Idempotent, and cheap enough to call on every
## enqueue -- which is what the reconciler does, because a container is not always inside a tree
## at the moment its root is created.
func attach(tree: SceneTree) -> void:
	if tree == null or _pumped_tree == tree:
		return
	detach()
	_pumped_tree = tree
	tree.process_frame.connect(pump)

## Stops the pump and drops the connection. A no-op on a `for_tree` instance, which never set
## `_pumped_tree`; those are pruned by tree identity instead.
func detach() -> void:
	if _pumped_tree != null and is_instance_valid(_pumped_tree) \
			and _pumped_tree.process_frame.is_connected(pump):
		_pumped_tree.process_frame.disconnect(pump)
	_pumped_tree = null

## The budget in force: this instance's, or the project-wide default when it has none.
func budget_ms() -> float:
	return frame_budget_ms if frame_budget_ms >= 0.0 else RuitkConfig.frame_budget_ms

static func for_tree(tree: SceneTree) -> RuitkScheduler:
	var tid := tree.get_instance_id()
	var existing = _by_tree.get(tid)
	if existing != null:
		return existing
	for k in _by_tree.keys():
		if instance_from_id(k) == null:
			_by_tree.erase(k)
	var sched := RuitkScheduler.new()
	_by_tree[tid] = sched
	tree.process_frame.connect(sched.pump)
	return sched

## Enqueue `action` on a lane, deduped per lane by Callable identity. During a batch,
## non-High enqueues are deferred until the outermost `end_batch` (:45-86).
func enqueue(action: Callable, priority: Priority = Priority.NORMAL) -> void:
	if action.is_null():
		return
	if _batch_depth > 0 and priority != Priority.HIGH:
		_deferred_batch_enqueues.append([action, priority])
		return
	var tracker: Dictionary = _trackers[priority]
	if not tracker.has(action):
		tracker[action] = true
		_queues[priority].append(action)

func begin_batch() -> void:
	_batch_depth += 1

func end_batch() -> void:
	if _batch_depth == 0:
		return
	_batch_depth -= 1
	if _batch_depth > 0:
		return
	if _deferred_batch_enqueues.is_empty():
		return
	var snapshot := _deferred_batch_enqueues
	_deferred_batch_enqueues = []
	for entry in snapshot:
		enqueue(entry[0], entry[1])

## The per-frame pump (RenderScheduler.cs `LateUpdate`, :116-164). Connected to
## `SceneTree.process_frame` by `for_tree`; tests call it directly.
func pump() -> void:
	var frame_start := _now_ms()
	_last_frame_start_ms = frame_start
	if not _queues[Priority.HIGH].is_empty() and not _queues[Priority.LOW].is_empty():
		var low: Array = _queues[Priority.LOW]
		var low_tracker: Dictionary = _trackers[Priority.LOW]
		_low_cancelled_count += low.size()
		while not low.is_empty():
			var removed: Callable = low.pop_front()
			low_tracker.erase(removed)
	var high_ran := _execute_queue(Priority.HIGH, frame_start)
	var normal_ran := 0
	if _queues[Priority.HIGH].is_empty():
		normal_ran = _execute_queue(Priority.NORMAL, frame_start)
	else:
		_escalation_count += 1
	var low_ran := _execute_queue(Priority.LOW, frame_start)
	var ran_foreground := high_ran > 0 or normal_ran > 0 or low_ran > 0
	var queues_empty: bool = _queues[Priority.HIGH].is_empty() \
			and _queues[Priority.NORMAL].is_empty() \
			and _queues[Priority.LOW].is_empty()
	if not ran_foreground and queues_empty \
			and _now_ms() - frame_start < budget_ms() * 0.5:
		_idle_executed_count += _execute_queue(Priority.IDLE, frame_start, false)
	_flush_batched_effects()
	_rendered_frame_count += 1

## Drain one lane until empty or over budget. The budget is measured from the SHARED
## frame-start timestamp — cumulative across every lane executed this frame (:166-204).
## A budget of 0 disables the check (reference `budgetLimit > 0f` guard). Idle's
## `allow_over_budget = false` halves the limit (:177).
func _execute_queue(priority: Priority, frame_start_ms: float, allow_over_budget := true) -> int:
	var queue: Array = _queues[priority]
	if queue.is_empty():
		return 0
	var budget: float = budget_ms()
	var budget_limit: float = budget if allow_over_budget else budget * 0.5
	if budget_limit < 0.0:
		budget_limit = 0.0
	var tracker: Dictionary = _trackers[priority]
	var executed := 0
	while not queue.is_empty():
		if budget_limit > 0.0 and _now_ms() - frame_start_ms > budget_limit:
			break
		var action: Callable = queue.pop_front()
		tracker.erase(action)
		if action.is_valid():
			action.call()
		_executed_action_count += 1
		executed += 1
	return executed

## Queue an effect for the unbudgeted frame-end flush (:206-212).
func enqueue_batched_effect(effect: Callable) -> void:
	if not effect.is_null():
		_batched_effects.append(effect)

## Drain high/normal/low/idle immediately, without the per-frame gating (no low-cancel,
## no normal-gate, no idle-gate) — then flush batched effects (:214-223). The cumulative
## budget still applies within each queue, exactly as the reference code does.
## Currently exercised by tests only — no production caller in this leg (the Unreal leg's
## FlushSync analog serves surfaces this leg doesn't have). API kept for family parity.
func pump_now() -> void:
	var frame_start := _now_ms()
	_execute_queue(Priority.HIGH, frame_start)
	_execute_queue(Priority.NORMAL, frame_start)
	_execute_queue(Priority.LOW, frame_start)
	_execute_queue(Priority.IDLE, frame_start)
	_flush_batched_effects()

## Frame-end effect flush — runs every queued effect regardless of budget (:225-243).
## Snapshot-swapped so an effect that enqueues another batched effect lands in the next
## flush (the reference's live-list foreach makes that case a hard error; snapshotting is
## the defined-behavior equivalent).
func _flush_batched_effects() -> void:
	if _batched_effects.is_empty():
		return
	var effects := _batched_effects
	_batched_effects = []
	for effect in effects:
		if effect.is_valid():
			effect.call()

## Counters mirroring RenderScheduler.cs `GetMetrics` (:245-258).
func get_metrics() -> Dictionary:
	return {
		"frames": _rendered_frame_count,
		"actions": _executed_action_count,
		"escalations": _escalation_count,
		"low_cancelled": _low_cancelled_count,
		"idle_ran": _idle_executed_count,
	}

func _now_ms() -> float:
	if time_source.is_valid():
		return float(time_source.call())
	return float(Time.get_ticks_usec()) / 1000.0
