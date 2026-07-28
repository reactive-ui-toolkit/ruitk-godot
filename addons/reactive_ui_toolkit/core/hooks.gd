class_name Hooks
extends RefCounted
## React-style hooks over the fiber reconciler. State lives in the current fiber's
## RUIComponentState; a static pointer (`_cur`) is set around each component render by
## the reconciler via `_begin`/`_end`.
##
## RULES OF HOOKS: call hooks only at the top level of a render function — never in
## `if`/loops/nested lambdas. The positional-slot model relies on a stable call order.
##
## Ported from ReactiveUIToolKit's Hooks. Storage model: a positional array of slots
## plus separate cursors for state-hooks, passive effects, and layout effects; context
## reads are kept OUT of the slot array (so useContext can't perturb hook order).

static var _cur: RUIComponentState = null

# --------------------------------------------------------------------------
# Render-phase plumbing (called by the reconciler only)
# --------------------------------------------------------------------------

static func _begin(state: RUIComponentState) -> void:
	_cur = state
	state.hook_index = 0
	state.effect_index = 0
	state.layout_index = 0
	state.context_deps = []
	state.is_rendering = true
	if RUIConfig.enable_hook_validation:
		state.hook_log = []

static func _end() -> void:
	if _cur != null:
		_cur.is_rendering = false
		if RUIConfig.enable_hook_validation:
			if not _cur.hook_order_primed:
				_cur.hook_signatures = _cur.hook_log.duplicate()
				_cur.hook_order_primed = true
			else:
				_check_hook_order(_cur)
	_cur = null

# --------------------------------------------------------------------------
# Dev diagnostics (Phase 7.0) — hook-order validation + state-update-in-render guard.
# All gated behind RUIConfig flags (default debug-only); push_error/warning + degrade.
# --------------------------------------------------------------------------

## Record a hook call's kind in render order (no-op unless validation is on).
static func _record(state: RUIComponentState, kind: String) -> void:
	if RUIConfig.enable_hook_validation:
		state.hook_log.append(kind)

## Compare this render's hook order to the primed signature; push_error on first divergence.
static func _check_hook_order(state: RUIComponentState) -> void:
	var prev: Array = state.hook_signatures
	var now: Array = state.hook_log
	var n: int = min(prev.size(), now.size())
	for i in n:
		if prev[i] != now[i]:
			var m := "[Hooks][order] %s: hook #%d changed '%s' -> '%s' across renders — hooks must run in the same order every render (no hooks inside if/for/lambdas)." % [_comp_label(state), i, prev[i], now[i]]
			RUIDiagnostics.emit(m)
			push_error(m)
			return
	if prev.size() != now.size():
		var m2 := "[Hooks][order] %s: hook count changed %d -> %d across renders — a hook is being called conditionally." % [_comp_label(state), prev.size(), now.size()]
		RUIDiagnostics.emit(m2)
		push_error(m2)

## A readable component name for diagnostics (the render Callable's method, or <anonymous>).
static func _comp_label(state: RUIComponentState) -> String:
	if state != null and state.fiber != null and state.fiber.component is Callable:
		var m := (state.fiber.component as Callable).get_method()
		return m if m != "" else "<anonymous>"
	return "<component>"

## Push a strict warning once per (component, key).
static func _warn_once(state: RUIComponentState, key: String, msg: String) -> void:
	if state.diag_warned.has(key):
		return
	state.diag_warned[key] = true
	RUIDiagnostics.emit(msg)
	push_warning(msg)

# --------------------------------------------------------------------------
# State
# --------------------------------------------------------------------------

## useState(initial) -> [value, setter]. `setter` accepts a value OR an updater
## Callable `(old) -> new`. Setter identity is stable across renders; setting an equal
## value bails out (no re-render).
## @return-tuple(Variant, Callable)
static func useState(initial = null) -> Array:
	var s := _cur
	_record(s, "state")
	var i := s.hook_index
	s.hook_index += 1
	if i >= s.hooks.size():
		s.hooks.append({ "kind": "state", "value": initial, "setter": _make_setter(s, i) })
	var slot: Dictionary = s.hooks[i]
	return [slot["value"], slot["setter"]]

static func _make_setter(state: RUIComponentState, i: int) -> Callable:
	return func(update):
		if i >= state.hooks.size():   # state torn down (unmounted) — ignore late calls [audit C3]
			return
		if state.is_rendering and RUIConfig.enable_strict_diagnostics:
			_warn_once(state, "set_in_render", "[Hooks][Strict] state set during render of %s — move it to an effect or event handler (setting state in the render body loops)." % _comp_label(state))
		var slot: Dictionary = state.hooks[i]
		var prev = slot["value"]
		var next = update.call(prev) if (update is Callable) else update
		if _ref_equal(prev, next):   # Object.is semantics: a new equal collection still re-renders [audit]
			return
		slot["value"] = next
		if state.on_state_updated.is_valid():
			state.on_state_updated.call()

## useReducer(reducer, initial) -> [state, dispatch]. `reducer(state, action)->state`.
## `dispatch` identity is stable; the reducer closure is refreshed every render.
## @return-tuple(Variant, Callable)
static func useReducer(reducer: Callable, initial = null) -> Array:
	var s := _cur
	_record(s, "reducer")
	var i := s.hook_index
	s.hook_index += 1
	if i >= s.hooks.size():
		var slot := { "kind": "reducer", "value": initial, "reducer": reducer }
		slot["dispatch"] = _make_dispatch(s, i)
		s.hooks.append(slot)
	else:
		s.hooks[i]["reducer"] = reducer
	var slot2: Dictionary = s.hooks[i]
	return [slot2["value"], slot2["dispatch"]]

static func _make_dispatch(state: RUIComponentState, i: int) -> Callable:
	return func(action):
		if i >= state.hooks.size():
			return
		if state.is_rendering and RUIConfig.enable_strict_diagnostics:
			_warn_once(state, "set_in_render", "[Hooks][Strict] dispatch during render of %s — move it to an effect or event handler." % _comp_label(state))
		var slot: Dictionary = state.hooks[i]
		var prev = slot["value"]
		var next = slot["reducer"].call(prev, action)
		if _ref_equal(prev, next):   # Object.is semantics — match React/ReactiveUIToolKit [audit]
			return
		slot["value"] = next
		if state.on_state_updated.is_valid():
			state.on_state_updated.call()

# --------------------------------------------------------------------------
# Refs / memo / callbacks
# --------------------------------------------------------------------------

## useRef(initial) -> { "current": initial }  (stable box; never re-created; mutating
## `.current` does NOT trigger a re-render).
static func useRef(initial = null) -> Dictionary:
	var s := _cur
	_record(s, "ref")
	var i := s.hook_index
	s.hook_index += 1
	if i >= s.hooks.size():
		s.hooks.append({ "kind": "ref", "box": { "current": initial } })
	return s.hooks[i]["box"]

## useMemo(factory, deps) -> cached value, recomputed only when deps change (shallow).
static func useMemo(factory: Callable, deps: Array = []) -> Variant:
	var s := _cur
	_record(s, "memo")
	var i := s.hook_index
	s.hook_index += 1
	if i >= s.hooks.size():
		var v = factory.call()
		s.hooks.append({ "kind": "memo", "value": v, "deps": deps.duplicate() })
		return v
	var slot: Dictionary = s.hooks[i]
	if _deps_changed(slot["deps"], deps):
		slot["value"] = factory.call()
		slot["deps"] = deps.duplicate()
	return slot["value"]

## useCallback(cb, deps) -> a stable Callable while deps are unchanged.
static func useCallback(cb: Callable, deps: Array = []) -> Callable:
	return useMemo(func(): return cb, deps)

## useImperativeHandle(factory, deps) -> handle, recomputed only when deps change.
static func useImperativeHandle(factory: Callable, deps: Array = []) -> Variant:
	return useMemo(factory, deps)

# --------------------------------------------------------------------------
# Effects (recorded during render, run during commit)
# --------------------------------------------------------------------------

## useEffect(effect, deps): passive effect, runs AFTER commit (two-pass: all cleanups
## then all setups). `deps == null` => every commit; `[]` => once on mount; `[a,b]` =>
## when a dep changes. `effect()` may return a Callable cleanup.
static func useEffect(effect: Callable, deps = null) -> void:
	var s := _cur
	_record(s, "effect")
	var i := s.effect_index
	s.effect_index += 1
	if i >= s.effects.size():
		s.effects.append({ "factory": effect, "deps": deps, "last_deps": null, "cleanup": null })
	else:
		s.effects[i]["factory"] = effect
		s.effects[i]["deps"] = deps

## useLayoutEffect(effect, deps): runs SYNCHRONOUSLY during commit (pre-paint),
## cleanup-then-setup per fiber. Same dep semantics as useEffect.
static func useLayoutEffect(effect: Callable, deps = null) -> void:
	var s := _cur
	_record(s, "layout_effect")
	var i := s.layout_index
	s.layout_index += 1
	if i >= s.layout_effects.size():
		s.layout_effects.append({ "factory": effect, "deps": deps, "last_deps": null, "cleanup": null })
	else:
		s.layout_effects[i]["factory"] = effect
		s.layout_effects[i]["deps"] = deps

# --------------------------------------------------------------------------
# Context
# --------------------------------------------------------------------------

## Create a context handle — React parity for `createContext(default)`. Pass the handle to
## provideContext/useContext instead of a string key to avoid cross-feature key collisions and to
## get a default value when no provider exists. See [RUIContext].
static func createContext(default_value = null, ctx_name: String = "") -> RUIContext:
	return RUIContext.new(default_value, ctx_name)

## useContext(key) -> nearest provided value walking up the fiber tree. `key` is a [RUIContext]
## handle (recommended, collision-free) OR a String (back-compat). Returns the handle's `default`
## when no ancestor provides it (String keys return null). Does NOT consume a hook slot; records the
## read so context changes re-render.
static func useContext(key):
	var s := _cur
	var fiber: RUIFiber = s.fiber
	fiber.reads_context = true
	var val = _resolve_context(fiber, key)
	if val == null and key is RUIContext:
		val = key.default   # no provider up the tree -> the handle's default
	s.context_deps.append({ "key": key, "value": val })
	return val

static func _resolve_context(fiber: RUIFiber, key):  # key: RUIContext handle or String
	var f := fiber
	while f != null:
		if f.provided_context != null and f.provided_context.has(key):
			return f.provided_context[key]
		f = f.parent
	return null

## provideContext(key, value): expose `value` under `key` to this fiber's subtree. `key` is a
## [RUIContext] handle (recommended) or a String (back-compat); a handle's object identity keys the
## map so distinct contexts never collide. On change, marks consuming descendants dirty so they
## re-render even through bailouts.
static func provideContext(key, value) -> void:
	var fiber: RUIFiber = _cur.fiber
	if fiber.provided_context == null:
		fiber.provided_context = {}
	var changed := true
	var alt := fiber.alternate
	if alt != null and alt.provided_context != null and alt.provided_context.has(key):
		changed = not _equal(alt.provided_context[key], value)
	fiber.provided_context[key] = value
	if changed and alt != null and alt.child != null:
		_propagate_context_change(key, alt.child)

## DFS over the committed subtree marking consumers of `key` dirty. Returns whether
## anything was marked (so intermediate ancestors get subtree_has_updates). Stops at a
## nested provider that shadows the same key.
static func _propagate_context_change(key, first: RUIFiber) -> bool:  # key: RUIContext handle or String
	var any := false
	var f := first
	while f != null:
		if f.provided_context != null and f.provided_context.has(key):
			f = f.sibling
			continue
		var self_marked := false
		if f.reads_context and f.state != null:
			for dep in f.state.context_deps:
				if dep["key"] == key:
					f.has_pending_update = true
					self_marked = true
					any = true
					break
		if f.child != null:
			var children_marked := _propagate_context_change(key, f.child)
			if children_marked:
				any = true
				if not self_marked:
					f.subtree_has_updates = true
		f = f.sibling
	return any

# --------------------------------------------------------------------------
# Concurrency
# --------------------------------------------------------------------------

## useDeferredValue(value, deps?) -> a deferred copy of `value`. On the render where `value`
## changes it returns the PREVIOUS value, then commits the new value on a low-priority next-frame
## tick (re-rendering once) — so an urgent update paints first with the stale value and the
## expensive consumer catches up a frame later. Mirrors ReactiveUIToolKit's scheduler-backed
## UseDeferredValue (which defers via EnqueueBatchedEffect). Pass `deps` to gate on a key instead
## of the value itself. The deferral routes through the normal schedule (process_frame ->
## on_state_updated -> schedule_update_on_fiber), so it never re-enters the render's restart guard.
static func useDeferredValue(value, deps = null):
	var s := _cur
	_record(s, "deferred")
	var i := s.hook_index
	s.hook_index += 1
	if i >= s.hooks.size():
		s.hooks.append({ "kind": "deferred", "value": value, "target": value, "deps": deps, "pending": false })
		return value
	var slot: Dictionary = s.hooks[i]
	var changed: bool
	if deps != null:
		changed = _deps_changed(slot["deps"], deps)
		slot["deps"] = deps
	else:
		changed = not _equal(slot["value"], value)
	if changed and not _equal(slot["value"], value):
		slot["target"] = value
		if not slot["pending"]:
			slot["pending"] = true
			_schedule_deferred_commit(s, i)
	return slot["value"]

static func _schedule_deferred_commit(state: RUIComponentState, i: int) -> void:
	var loop := Engine.get_main_loop()
	if not (loop is SceneTree):
		# No frame loop (e.g. a pure unit context) — commit synchronously so the value isn't stuck.
		if i < state.hooks.size():
			state.hooks[i]["value"] = state.hooks[i]["target"]
			state.hooks[i]["pending"] = false
		return
	var cb := func():
		if i >= state.hooks.size():
			return
		var slot: Dictionary = state.hooks[i]
		slot["pending"] = false
		if not _equal(slot["value"], slot["target"]):
			slot["value"] = slot["target"]
			if state.on_state_updated.is_valid():
				state.on_state_updated.call()
	(loop as SceneTree).process_frame.connect(cb, CONNECT_ONE_SHOT)

## useTransition() -> [is_pending(false), start_transition]. Faithful to ReactiveUIToolKit's
## UseTransition, which is a no-op in the synchronous renderer: is_pending is always false and
## start_transition runs the action immediately.
## @return-tuple(bool, Callable)
static func useTransition() -> Array:
	var s := _cur
	_record(s, "transition")
	var i := s.hook_index
	s.hook_index += 1
	if i >= s.hooks.size():
		s.hooks.append({ "kind": "transition" })
	var start := func(action: Callable):
		if action.is_valid():
			action.call()
	return [false, start]

# --------------------------------------------------------------------------
# Stable callbacks (stable identity, always invoke the latest closure body)
# --------------------------------------------------------------------------

## useStableCallback(cb) / useStableFunc(cb): 0-arg, stable identity.
static func useStableCallback(cb: Callable) -> Callable:
	var s := _cur
	_record(s, "stable")
	var i := s.hook_index
	s.hook_index += 1
	if i >= s.hooks.size():
		var slot := { "kind": "stable", "cb": cb }
		slot["wrapper"] = func():
			var c: Callable = s.hooks[i]["cb"]
			return c.call() if c.is_valid() else null
		s.hooks.append(slot)
		return s.hooks[i]["wrapper"]
	s.hooks[i]["cb"] = cb
	return s.hooks[i]["wrapper"]

static func useStableFunc(cb: Callable) -> Callable:
	return useStableCallback(cb)

## useStableAction(cb): 1-arg, stable identity.
static func useStableAction(cb: Callable) -> Callable:
	var s := _cur
	_record(s, "stable")
	var i := s.hook_index
	s.hook_index += 1
	if i >= s.hooks.size():
		var slot := { "kind": "stable", "cb": cb }
		slot["wrapper"] = func(a):
			var c: Callable = s.hooks[i]["cb"]
			return c.call(a) if c.is_valid() else null
		s.hooks.append(slot)
		return s.hooks[i]["wrapper"]
	s.hooks[i]["cb"] = cb
	return s.hooks[i]["wrapper"]

# --------------------------------------------------------------------------
# Platform
# --------------------------------------------------------------------------

## useSafeArea() -> { left, top, right, bottom } device safe-area insets (pixels).
static func useSafeArea() -> Dictionary:
	var s := _cur
	_record(s, "safe_area")
	var i := s.hook_index
	s.hook_index += 1
	if i >= s.hooks.size():
		s.hooks.append({ "kind": "safe_area" })
	var rect := DisplayServer.get_display_safe_area()
	var screen := DisplayServer.screen_get_size()
	return {
		"left": rect.position.x,
		"top": rect.position.y,
		"right": maxi(0, screen.x - (rect.position.x + rect.size.x)),
		"bottom": maxi(0, screen.y - (rect.position.y + rect.size.y)),
	}

## useSignal(signal, selector?, comparer?) -> selected value. Subscribes to a RUISignal
## and re-renders when the (optionally selected) value changes. Unsubscribes on unmount.
static func useSignal(sig: RUISignal, selector = null, comparer = null):
	var s := _cur
	_record(s, "signal")
	var i := s.hook_index
	s.hook_index += 1
	if i >= s.hooks.size():
		var slot := { "kind": "signal", "sig": sig, "selector": selector, "comparer": comparer }
		slot["value"] = _select_signal(sig, selector)
		slot["unsub"] = sig.subscribe(_make_signal_sub(s, i)) if sig != null else Callable()
		s.hooks.append(slot)
		return slot["value"]
	# Re-bind every render (mirrors the C# Signal.Bind): refresh selector/comparer, resubscribe if the
	# signal instance changed, and recompute the selected value so a changed selector/sig is reflected. [audit]
	var slot2: Dictionary = s.hooks[i]
	slot2["selector"] = selector
	slot2["comparer"] = comparer
	if not is_same(slot2["sig"], sig):
		if slot2["unsub"] is Callable and slot2["unsub"].is_valid():
			slot2["unsub"].call()
		slot2["sig"] = sig
		slot2["unsub"] = sig.subscribe(_make_signal_sub(s, i)) if sig != null else Callable()
	slot2["value"] = _select_signal(sig, selector)
	return slot2["value"]

static func _select_signal(sig: RUISignal, selector):
	if sig == null:
		return null
	return selector.call(sig.get_value()) if (selector is Callable) else sig.get_value()

## useSignalKey(key, initial, selector?, comparer?) -> selected value of the PROCESS-WIDE signal
## registered under `key` (created lazily via RUISignals). Subscribes + re-renders like useSignal;
## the registry entry outlives the component, so any component reading the same key shares one store.
static func useSignalKey(key: String, initial = null, selector = null, comparer = null):
	return useSignal(RUISignals.get_or_create(key, initial), selector, comparer)

static func _make_signal_sub(state: RUIComponentState, i: int) -> Callable:
	# Reads sig/selector/comparer from the SLOT (not captured args) so the latest ones are used after
	# a re-bind. Default change-detection is reference-aware (a new equal collection counts as changed). [audit]
	return func(_v):
		if i >= state.hooks.size():   # unsubscribed/torn down between emit and dispatch [audit C3]
			return
		var slot: Dictionary = state.hooks[i]
		var nv = _select_signal(slot["sig"], slot["selector"])
		var comparer = slot["comparer"]
		var same: bool = comparer.call(slot["value"], nv) if (comparer is Callable) else _ref_equal(slot["value"], nv)
		if not same:
			slot["value"] = nv
			if state.on_state_updated.is_valid():
				state.on_state_updated.call()

## useTween(ref, property, to, duration, deps): smoothly tweens a mounted node's
## property via Godot's Tween when deps change. `ref` is a useRef box whose `current`
## is the target node (wire it with the "ref" prop). Kills the tween on change/unmount.
static func useTween(ref: Dictionary, property: String, to, duration: float, deps: Array = []) -> void:
	var eff := func():
		var node = ref.get("current")
		if node == null or not is_instance_valid(node) or not node.is_inside_tree():
			return func(): pass
		var tw: Tween = node.create_tween()
		tw.tween_property(node, property, to, duration)
		return func():
			if is_instance_valid(tw):
				tw.kill()
	useEffect(eff, deps)

## useTweenValue(from, to, duration, on_update, deps): drives on_update(value) each
## frame as a value interpolates (Tween.tween_method). Animate without re-rendering by
## setting a node property inside on_update.
static func useTweenValue(from, to, duration: float, on_update: Callable, deps: Array = []) -> void:
	var eff := func():
		var loop = Engine.get_main_loop()
		if not (loop is SceneTree):
			return func(): pass
		var tw: Tween = loop.create_tween()
		tw.tween_method(on_update, from, to, duration)
		return func():
			if is_instance_valid(tw):
				tw.kill()
	useEffect(eff, deps)

## useAnimate(ref, tracks, autoplay, deps): play a list of property tracks on a mounted node via a
## Godot Tween (the engine-native analog of ReactiveUIToolKit's UseAnimate). `ref` is a useRef box
## whose `.current` is the target node. Each track is a Dictionary:
##   { "property": "modulate:a", "to": <value>, "from"?: <value>, "duration"?: 0.3, "delay"?: 0.0,
##     "trans"?: Tween.TransitionType, "ease"?: Tween.EaseType, "parallel"?: false }
## A fresh tween is built on mount / when `deps` change; the previous one is killed (cleanup).
static func useAnimate(ref: Dictionary, tracks: Array, autoplay := true, deps: Array = []) -> void:
	var eff := func():
		var node = ref.get("current")
		if node == null or not is_instance_valid(node) or not node.is_inside_tree():
			return func(): pass
		if not autoplay or tracks == null or tracks.is_empty():
			return func(): pass
		var tw: Tween = node.create_tween()
		for track in tracks:
			if not (track is Dictionary):
				continue
			var prop := str(track.get("property", ""))
			if prop == "":
				continue
			if bool(track.get("parallel", false)):
				tw.parallel()
			var dur := float(track.get("duration", 0.3))
			var tweener := tw.tween_property(node, prop, track.get("to"), dur)
			if track.has("from"):
				tweener.from(track["from"])
			if track.has("delay"):
				tweener.set_delay(float(track["delay"]))
			if track.has("trans"):
				tweener.set_trans(int(track["trans"]))
			if track.has("ease"):
				tweener.set_ease(int(track["ease"]))
		return func():
			if is_instance_valid(tw):
				tw.kill()
	useEffect(eff, deps)

## useSfx(bus) -> a stable func(stream: AudioStream, volume_db := 0.0, pitch_scale := 1.0) that plays
## a one-shot sound on a transient, self-freeing AudioStreamPlayer (RUIMedia). Call it from event
## handlers; identity is stable across renders unless `bus` changes. Mirrors ReactiveUIToolKit's UseSfx.
static func useSfx(bus := "Master") -> Callable:
	var s := _cur
	_record(s, "sfx")
	var i := s.hook_index
	s.hook_index += 1
	if i >= s.hooks.size() or s.hooks[i].get("bus") != bus:
		var captured_bus := bus
		var action := func(stream: AudioStream, volume_db := 0.0, pitch_scale := 1.0):
			RUIMedia.play_one_shot(stream, captured_bus, volume_db, pitch_scale)
		var slot := { "kind": "sfx", "bus": bus, "action": action }
		if i >= s.hooks.size():
			s.hooks.append(slot)
		else:
			s.hooks[i] = slot
	return s.hooks[i]["action"]

# use_ui_document_root -> Godot has no UIDocument; resolve the mount viewport if needed.

# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------

## Shallow dependency comparison. null on either side => "changed" (always run).
## [G-09, design decision] `_equal` uses GDScript `==`, which DEEP-compares Array/Dictionary --
## unlike React's `Object.is`-per-dependency-item semantics (see `_ref_equal` below, used for
## state/signal change-detection instead). Concretely: `useEffect(fn, [some_array])` where a caller
## passes a FRESH-but-structurally-equal array every render will NOT re-run the effect here, where
## React (identity-based) WOULD. This is intentional -- see below -- but has a real perf cost: a
## large Array/Dictionary in a deps list is deep-compared on every render, not just pointer-checked.
## If that ever shows up in a profile, the fix is a `same_ref` opt-in (pass `_ref_equal` instead of
## `_equal` for a specific hook's deps check) -- not changing this default, since flipping it
## silently would make a currently-stable effect (relying on value-equality to SKIP redundant runs
## on equal-but-recreated deps) start re-running every render instead.
static func _deps_changed(prev, next) -> bool:
	if prev == null or next == null:
		return true
	if prev.size() != next.size():
		return true
	for i in prev.size():
		if not _equal(prev[i], next[i]):
			return true
	return false

static func _equal(a, b) -> bool:
	return a == b

## Object.is / EqualityComparer<T>.Default semantics: IDENTITY for reference types (Array /
## Dictionary / Object), VALUE equality for value types (int/float/String/Vector2/…). Used for
## state + signal change-detection so a freshly-built but structurally-equal collection still counts
## as changed (re-renders), matching React and ReactiveUIToolKit. (`_equal`/`_deps_changed` keep
## value-equality, which is the intended shallow-deps semantics.)
static func _ref_equal(a, b) -> bool:
	if a is Array or a is Dictionary or a is Object or b is Array or b is Dictionary or b is Object:
		return is_same(a, b)
	return a == b
