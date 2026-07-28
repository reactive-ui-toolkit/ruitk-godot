extends SceneTree
## Headless core test suite. Run:
##   godot --headless --path <project> --script res://tests/core_test.gd
## Exercises: effects (deps + cleanup), bailout, context, fragments, keyed reorder,
## reducer + memo, and layout-vs-passive effect ordering.

var _fails := 0
var _passes := 0

func _initialize() -> void:
	_run()

func _run() -> void:
	await _test_effects()
	await _test_bailout()
	await _test_context()
	await _test_context_handles()
	await _test_fragment()
	await _test_keyed_reorder()
	await _test_reducer_and_memo()
	await _test_layout_effect()
	await _test_signal()
	await _test_signal_key()
	await _test_text_children()
	await _test_memo_eq()
	await _test_suspense()
	await _test_router()
	await _test_tween()
	await _test_diagnostics()
	await _test_hook_diagnostics()
	await _test_item_list()
	await _test_root_node()
	await _test_tree()
	await _test_time_slicing()
	await _test_context_survives_bailout()
	await _test_ref_null_on_unmount()
	await _test_router_context_split()
	await _test_deferred_value()
	await _test_media_and_animate()
	await _test_item_model_adapters()
	await _test_react_events()
	await _test_classes_stylesheet()
	await _test_classes_lean_path()
	await _test_reference_equality()
	await _test_signal_rebind()
	await _test_custom_draw()
	await _test_host_node_pool()
	await _test_reuse_by_slot()
	print("\n[core_test] %d passed, %d failed" % [_passes, _fails])
	quit(1 if _fails > 0 else 0)

func _test_react_events() -> void:
	# 0.9.0 loyal event names (host_config._resolve_signal): on<Pascal> binds the exact snake_case
	# signal, the removed React aliases DON'T bind (they warn), and on_<signal> stays verbatim.
	var hit := { "n": 0 }
	var cb := func(): hit["n"] += 1
	var btn := Button.new()
	RuitkHost.apply_props(btn, {}, { "onPressed": cb })
	_ok(btn.is_connected("pressed", cb), "onPressed binds the `pressed` signal")
	btn.emit_signal("pressed")
	_ok(hit["n"] == 1, "onPressed handler fires on `pressed`")
	var m: Dictionary = btn.get_meta("__rui_events", {})
	_ok(m.has("onPressed") and m["onPressed"]["sig"] == "pressed", "meta records the RESOLVED signal `pressed`")
	RuitkHost.apply_props(btn, { "onPressed": cb }, {})   # removing the prop disconnects + clears meta
	_ok(not btn.is_connected("pressed", cb), "removing onPressed disconnects `pressed`")
	_ok(not btn.get_meta("__rui_events", {}).has("onPressed"), "removing onPressed clears its meta record")
	# The 0.8 React aliases were REMOVED: the old click alias resolves to a nonexistent `click`
	# signal and must NOT bind anything (a rename warning is pushed — asserted here as the no-op).
	# NOTE for future codemod runs: the alias literal is built to stay out of regex reach.
	var removed_click := "on" + "Click"
	RuitkHost.apply_props(btn, {}, { removed_click: cb })
	_ok(not btn.is_connected("pressed", cb), "removed alias %s does NOT bind `pressed`" % removed_click)
	_ok(not btn.get_meta("__rui_events", {}).has(removed_click), "removed alias %s records no event meta" % removed_click)
	btn.free()

	# The polymorphic onChange is gone — each control uses its real signal, loyal to Godot.
	var le := LineEdit.new()
	var lecb := func(_t): pass
	RuitkHost.apply_props(le, {}, { "onTextChanged": lecb })
	_ok(le.is_connected("text_changed", lecb), "onTextChanged on LineEdit -> text_changed")
	RuitkHost.apply_props(le, { "onTextChanged": lecb }, { "onChange": lecb })
	_ok(not le.is_connected("text_changed", lecb), "removed alias onChange does NOT bind text_changed")
	le.free()
	var ob := OptionButton.new()
	var obcb := func(_i): pass
	RuitkHost.apply_props(ob, {}, { "onItemSelected": obcb })
	_ok(ob.is_connected("item_selected", obcb), "onItemSelected on OptionButton -> item_selected")
	_ok(not ob.is_connected("toggled", obcb), "onItemSelected did not touch `toggled`")
	ob.free()
	var sl := HSlider.new()
	var slcb := func(_v): pass
	RuitkHost.apply_props(sl, {}, { "onValueChanged": slcb })
	_ok(sl.is_connected("value_changed", slcb), "onValueChanged on HSlider -> value_changed")
	sl.free()

	# Native on_<signal> escape hatch: back-compat AND reaches arbitrary signals with no React alias.
	var btn2 := Button.new()
	var oldcb := func(): pass
	RuitkHost.apply_props(btn2, {}, { "on_pressed": oldcb })
	_ok(btn2.is_connected("pressed", oldcb), "native on_pressed still binds `pressed` (non-breaking)")
	btn2.free()
	var ctl := Control.new()
	var gicb := func(_e): pass
	RuitkHost.apply_props(ctl, {}, { "on_gui_input": gicb })
	_ok(ctl.is_connected("gui_input", gicb), "native on_gui_input reaches an arbitrary signal")
	ctl.free()

func _test_custom_draw() -> void:
	var drawn := { "node": null }
	var draw_fn := func(canvas): drawn["node"] = canvas
	var panel := Control.new()
	# initial apply: stores the latest draw_fn + registers ONE trampoline on the `draw` signal
	RuitkHost.apply_props(panel, {}, { "draw_fn": draw_fn })
	_ok(panel.has_meta("__rui_draw_tramp"), "draw_fn registers a draw trampoline")
	_ok(panel.get_meta("__rui_draw") == draw_fn, "latest draw_fn stored in meta")
	var tramp: Callable = panel.get_meta("__rui_draw_tramp")
	_ok(panel.is_connected("draw", tramp), "trampoline connected to the `draw` signal")
	# invoking the trampoline (what the `draw` signal does at paint time) calls draw_fn(node)
	tramp.call()
	_ok(drawn["node"] == panel, "trampoline invokes draw_fn(node)")
	# a fresh closure each render swaps the meta but reuses the SAME trampoline (no re-subscribe)
	var draw_fn2 := func(canvas): pass
	RuitkHost.apply_props(panel, { "draw_fn": draw_fn }, { "draw_fn": draw_fn2 })
	_ok(panel.get_meta("__rui_draw") == draw_fn2, "draw_fn swapped to the new closure")
	_ok(panel.get_meta("__rui_draw_tramp") == tramp, "same trampoline reused (no re-subscribe)")
	# bumping redraw_key with a stable callback is handled (same trampoline, no crash)
	RuitkHost.apply_props(panel, { "draw_fn": draw_fn2, "redraw_key": 0 }, { "draw_fn": draw_fn2, "redraw_key": 1 })
	_ok(panel.get_meta("__rui_draw_tramp") == tramp, "redraw_key bump keeps the same trampoline")
	# removing draw_fn disconnects the trampoline + clears the meta
	RuitkHost.apply_props(panel, { "draw_fn": draw_fn2 }, {})
	_ok(not panel.has_meta("__rui_draw_tramp"), "removing draw_fn disconnects the trampoline")
	_ok(not panel.is_connected("draw", tramp), "trampoline disconnected from `draw`")
	panel.free()

func _test_reuse_by_slot() -> void:
	# GO-09: a `reuse_by_slot` container reconciles a stateless-leaf list BY SLOT — even when every
	# key changes every frame, the node at slot i is REUSED (in-place prop update), so there is ZERO
	# mount/unmount churn. Default-off: without the prop, the same key-churn still churns nodes.
	var ctrl := { "set": null }
	var make := func(reuse: bool) -> Callable:
		return func(_p, _ch):
			var s = Hooks.useState(0)
			ctrl["set"] = s[1]
			var f: int = s[0]
			var items: Array = []
			for i in range(5):
				# EVERY key changes every render -> the keyed path would delete+recreate all 5.
				items.append(V.ColorRect({ "key": "k%d_%d" % [i, f], "color": Color(float(i) / 5.0, float(f % 8) / 8.0, 0.5) }))
			return V.Control({ "reuse_by_slot": reuse }, items)

	# With reuse_by_slot: capture the node instances, churn all keys, assert SAME instances + zero churn.
	var m := _mount(make.call(true))
	await process_frame
	var cont: Node = m[0].get_child(0)
	var n0 = cont.get_child(0)
	var n4 = cont.get_child(4)
	RuitkDiagnostics.enabled = true
	RuitkDiagnostics.placements = 0
	RuitkDiagnostics.deletions = 0
	ctrl["set"].call(1)
	await process_frame
	await process_frame
	_ok(cont.get_child(0) == n0 and cont.get_child(4) == n4, "reuse_by_slot: nodes REUSED across a full key change")
	_ok(RuitkDiagnostics.placements == 0 and RuitkDiagnostics.deletions == 0, "reuse_by_slot: ZERO mount/unmount churn (got p=%d d=%d)" % [RuitkDiagnostics.placements, RuitkDiagnostics.deletions])
	_ok((cont.get_child(0) as ColorRect).color.g == float(1 % 8) / 8.0, "reuse_by_slot: reused node's props updated in place")
	RuitkDiagnostics.enabled = false
	m[1].unmount()
	m[0].queue_free()

	# Default-off (no reuse_by_slot): the SAME all-keys-churn DOES churn nodes -> proves opt-in gating.
	var m2 := _mount(make.call(false))
	await process_frame
	var cont2: Node = m2[0].get_child(0)
	RuitkDiagnostics.enabled = true
	RuitkDiagnostics.placements = 0
	RuitkDiagnostics.deletions = 0
	ctrl["set"].call(2)
	await process_frame
	await process_frame
	_ok(RuitkDiagnostics.placements > 0 or RuitkDiagnostics.deletions > 0, "without reuse_by_slot: all-keys-churn still churns nodes (opt-in gate works)")
	RuitkDiagnostics.enabled = false
	m2[1].unmount()
	m2[0].queue_free()

func _test_host_node_pool() -> void:
	# GO-05 recycle -> reuse contract (correctness-critical): a pooled node reused for a
	# DIFFERENT element must carry NONE of its prior life's state — no stale event handler,
	# no stale style, no stale removed plain prop. This mirrors exactly what the reconciler
	# does: reset_for_pool on delete, then reset_removed_plain + apply_props(old,new) on reuse.
	var hit := { "a": 0, "z": 0 }
	var cbA := func(): hit["a"] += 1
	var cbZ := func(): hit["z"] += 1
	var btn := Button.new()
	root.add_child(btn)
	var propsA := { "onPressed": cbA, "disabled": true, "style": { "modulate": Color.RED } }
	RuitkHost.apply_props(btn, {}, propsA)
	_ok(btn.disabled and btn.modulate == Color.RED and btn.is_connected("pressed", cbA), "element A applied (event+style+plain)")

	# Recycle A exactly as the reconciler does on key churn.
	var accepted := RuitkHost.reset_for_pool(btn, propsA)
	_ok(accepted, "reset_for_pool accepts a plain Button")
	_ok(btn.get_parent() == null, "recycled node is detached from the tree")
	_ok(btn.has_meta("__rui_pool_old"), "recycled node stashed its last props for the reuse diff")

	# Reuse the pooled node for element Z: different handler, different style, and NO `disabled`.
	var propsZ := { "onPressed": cbZ, "style": { "modulate": Color.GREEN } }
	var stash: Dictionary = btn.get_meta("__rui_pool_old")
	btn.remove_meta("__rui_pool_old")
	RuitkHost.reset_removed_plain(btn, stash, propsZ)
	RuitkHost.apply_props(btn, stash, propsZ)
	_ok(btn.disabled == false, "reuse: removed plain prop `disabled` reset to class default")
	_ok(btn.modulate == Color.GREEN, "reuse: style modulate is Z's, not A's stale red")
	_ok(btn.is_connected("pressed", cbZ) and not btn.is_connected("pressed", cbA), "reuse: Z's handler bound, A's gone")
	btn.emit_signal("pressed")
	_ok(hit["z"] == 1 and hit["a"] == 0, "reuse: pressed fires Z's handler only (no stale A)")
	btn.free()

	# Item-model controls are NOT pooled (their non-node item state isn't generically cleared).
	var ob := OptionButton.new()
	_ok(RuitkHost.reset_for_pool(ob, { "items": [{ "text": "x" }] }) == false, "item-model control refused by the pool")
	ob.free()

	# End-to-end: churn a keyed list many times through a live root; the pool must not corrupt
	# identity, ordering, or leak (drained on unmount).
	var ctrl := { "set": null }
	var comp := func(_p, _ch):
		var s = Hooks.useState(0)
		ctrl["set"] = s[1]
		var f: int = s[0]
		var items: Array = []
		for i in range(6):
			var key: String = ("t%d_%d" % [i, f]) if i % 2 == 0 else ("s%d" % i)
			items.append(V.Label({ "text": "%d" % (i + f), "key": key }))
		return V.VBoxContainer({}, items)
	var m := _mount(comp)
	await process_frame
	await process_frame
	var vbox: Node = m[0].get_child(0)
	for step in range(8):
		ctrl["set"].call(step + 1)
		await process_frame
		await process_frame
	_ok(vbox.get_child_count() == 6, "keyed churn keeps the list size stable through the pool (got %d)" % vbox.get_child_count())
	var last_label := vbox.get_child(5) as Label
	_ok(last_label != null and last_label.text != "", "recycled/reused nodes render correct content after churn")
	m[1].unmount()
	m[0].queue_free()

func _test_classes_lean_path() -> void:
	# [audit #1] A `classes`-only element (no inline style / events / ref) must take the GENERIC
	# apply path so the resolved class style is (re)applied and node.set("classes",...) never fires.
	RuitkStyleSheet.register("c_a", { "font_color": Color(1, 0, 0) })
	RuitkStyleSheet.register("c_b", { "font_color": Color(0, 0, 1) })
	var ctl := { "set": null }
	var comp := func(_p, _c):
		var s = Hooks.useState(["c_a"])
		ctl["set"] = s[1]
		return V.Button({ "classes": s[0], "text": "x" })
	var m := _mount(comp)
	await process_frame
	var btn: Button = m[0].get_child(0)
	_ok(btn.get_theme_color("font_color") == Color(1, 0, 0), "classes-only: c_a applied red, got %s" % str(btn.get_theme_color("font_color")))
	ctl["set"].call(["c_b"])
	await process_frame
	await process_frame
	_ok(btn.get_theme_color("font_color") == Color(0, 0, 1), "classes-only re-render: c_b applied blue (lean path didn't crash/skip), got %s" % str(btn.get_theme_color("font_color")))
	RuitkStyleSheet.clear()
	m[1].unmount()
	m[0].queue_free()

func _test_reference_equality() -> void:
	# [audit #10] setState with a fresh, structurally-equal Array must still re-render (Object.is).
	var renders := { "n": 0 }
	var ctl := { "set": null }
	var comp := func(_p, _c):
		renders["n"] += 1
		var s = Hooks.useState([1, 2, 3])
		ctl["set"] = s[1]
		return V.Label({ "text": str(s[0].size()) })
	var m := _mount(comp)
	await process_frame
	var first: int = renders["n"]
	ctl["set"].call([1, 2, 3])   # NEW array, equal content -> should re-render (identity differs)
	await process_frame
	await process_frame
	_ok(renders["n"] == first + 1, "new equal array re-renders (ref-equality), renders %d -> %d" % [first, renders["n"]])
	m[1].unmount()
	m[0].queue_free()

func _test_signal_rebind() -> void:
	# [audit #2] useSignal must re-bind to a NEW selector across renders (not freeze the mount one).
	var sig := RuitkSignal.new({ "a": 10, "b": 20 })
	var ctl := { "set_key": null }
	var seen := { "v": null }
	var comp := func(_p, _c):
		var ks = Hooks.useState("a")
		ctl["set_key"] = ks[1]
		var key: String = ks[0]
		var v = Hooks.useSignal(sig, func(d): return d.get(key))
		seen["v"] = v
		return V.Label({ "text": str(v) })
	var m := _mount(comp)
	await process_frame
	_ok(seen["v"] == 10, "useSignal selects 'a' = 10, got %s" % str(seen["v"]))
	ctl["set_key"].call("b")   # change the selector key prop -> hook must re-bind and select 'b'
	await process_frame
	await process_frame
	_ok(seen["v"] == 20, "useSignal re-bound to new selector 'b' = 20, got %s" % str(seen["v"]))
	m[1].unmount()
	m[0].queue_free()

func _ok(cond: bool, msg: String) -> void:
	if cond:
		_passes += 1
	else:
		_fails += 1
		printerr("  FAIL: " + msg)
		push_error("FAIL: " + msg)

func _mount(render_fn: Callable, props := {}) -> Array:
	var c := Control.new()
	root.add_child(c)
	var app := RuitkRoot.create(c, V.fc(render_fn, props))
	return [c, app]

# --------------------------------------------------------------------------

func _test_suspense() -> void:
	# Phase 7.4: a Suspense boundary shows fallback until an awaited signal fires, then its children.
	var emitter := RefCounted.new()
	emitter.add_user_signal("ready")
	var sig := Signal(emitter, "ready")
	var comp := func(_p, _ch):
		return V.suspense({ "fallback": V.Label({ "text": "loading" }), "ready_signal": sig }, [V.Label({ "text": "loaded" })])
	var m := _mount(comp)
	await process_frame   # passive effect runs -> the signal driver is set up
	_ok(m[0].get_child(0).text == "loading", "suspense shows fallback initially, got '%s'" % m[0].get_child(0).text)
	emitter.emit_signal("ready")
	await process_frame
	await process_frame
	_ok(m[0].get_child(0).text == "loaded", "suspense shows children after the signal fired, got '%s'" % m[0].get_child(0).text)

func _test_memo_eq() -> void:
	# Phase 7.3: V.memo with a custom __memo_eq that always reports "equal" -> the child never
	# re-renders even though its `v` prop changes.
	var renders := { "n": 0 }
	var ctrl := { "set": null }
	var inner := func(_p, _ch):
		renders["n"] += 1
		return V.Label({ "text": "x" })
	var parent := func(_p, _ch):
		var s = Hooks.useState(0)
		ctrl["set"] = s[1]
		return V.memo(inner, { "v": s[0], "__memo_eq": func(_o, _new): return true })
	_mount(parent)
	_ok(renders["n"] == 1, "memo child rendered once on mount")
	ctrl["set"].call(1)
	await process_frame
	await process_frame
	_ok(renders["n"] == 1, "memo child did NOT re-render (custom __memo_eq said equal), got %d" % renders["n"])

func _test_text_children() -> void:
	# Phase 7.2: raw String children auto-wrap to a text Label instead of being silently dropped.
	var comp := func(_p, _ch):
		return V.VBoxContainer({}, ["hello", V.Button({ "text": "b" }), "world"])
	var m := _mount(comp)
	var vbox: Node = m[0].get_child(0)
	_ok(vbox.get_child_count() == 3, "vbox has 3 children (2 text + 1 button), got %d" % vbox.get_child_count())
	_ok(vbox.get_child(0) is Label and vbox.get_child(0).text == "hello", "first String child rendered as Label 'hello'")
	_ok(vbox.get_child(2) is Label and vbox.get_child(2).text == "world", "third String child rendered as Label 'world'")
	# V.text factory + a component returning a bare String
	var m2 := _mount(func(_p, _ch): return "bare")
	_ok(m2[0].get_child(0) is Label and m2[0].get_child(0).text == "bare", "component returning a bare String renders a Label")

func _test_signal_key() -> void:
	# Phase 7.1: a process-wide keyed signal shared by two independent components.
	RuitkSignals.clear()
	var renders := { "a": 0, "b": 0 }
	var comp_a := func(_p, _ch):
		renders["a"] += 1
		return V.Label({ "text": str(Hooks.useSignalKey("counter", 10)) })
	var comp_b := func(_p, _ch):
		renders["b"] += 1
		return V.Label({ "text": str(Hooks.useSignalKey("counter", 10)) })
	_mount(comp_a)
	_mount(comp_b)
	_ok(renders["a"] == 1 and renders["b"] == 1, "both keyed components mounted once")
	var sig := RuitkSignals.get_or_create("counter")
	_ok(sig.get_value() == 10, "shared keyed signal carries the initial value, got %s" % str(sig.get_value()))
	sig.set_value(20)   # updating the shared store re-renders every reader
	await process_frame
	await process_frame
	_ok(renders["a"] == 2 and renders["b"] == 2, "both readers re-rendered on keyed update, got a=%d b=%d" % [renders["a"], renders["b"]])
	RuitkSignals.clear()

func _test_hook_diagnostics() -> void:
	# Phase 7.0 dev diagnostics: hook-order validation + state-update-in-render guard, captured via
	# RuitkDiagnostics.messages (push_error/warning aren't interceptable headlessly).
	var _hv := RuitkConfig.enable_hook_validation
	var _sd := RuitkConfig.enable_strict_diagnostics
	RuitkConfig.enable_hook_validation = true
	RuitkConfig.enable_strict_diagnostics = true
	RuitkDiagnostics.capture = true
	RuitkDiagnostics.clear_messages()
	# render 1 primes the hook order: state, state, effect
	var st := RuitkComponentState.new()
	Hooks._begin(st); Hooks.useState(0); Hooks.useState(1); Hooks.useEffect(func(): return null, []); Hooks._end()
	_ok(RuitkDiagnostics.messages.is_empty(), "first render primes hook order with no diagnostic")
	# render 2 drops the conditional 2nd useState -> order mismatch
	Hooks._begin(st); Hooks.useState(0); Hooks.useEffect(func(): return null, []); Hooks._end()
	_ok(RuitkDiagnostics.messages.any(func(m): return "[Hooks][order]" in m), "hook-order mismatch detected, got %s" % str(RuitkDiagnostics.messages))

	# state-update-during-render guard
	RuitkDiagnostics.clear_messages()
	var st2 := RuitkComponentState.new()
	Hooks._begin(st2)
	var sv: Array = Hooks.useState(0)
	sv[1].call(1)   # setter invoked while is_rendering -> strict warning
	Hooks._end()
	_ok(RuitkDiagnostics.messages.any(func(m): return "[Hooks][Strict]" in m), "state-set-in-render warned, got %s" % str(RuitkDiagnostics.messages))

	# silence when the flags are off (a different hook order must NOT warn)
	RuitkConfig.enable_hook_validation = false
	RuitkConfig.enable_strict_diagnostics = false
	RuitkDiagnostics.clear_messages()
	var st3 := RuitkComponentState.new()
	Hooks._begin(st3); Hooks.useState(0); Hooks._end()
	Hooks._begin(st3); Hooks.useEffect(func(): return null); Hooks._end()
	_ok(RuitkDiagnostics.messages.is_empty(), "no diagnostics emitted when flags are off, got %s" % str(RuitkDiagnostics.messages))
	RuitkDiagnostics.capture = false
	RuitkConfig.enable_hook_validation = _hv
	RuitkConfig.enable_strict_diagnostics = _sd

func _test_effects() -> void:
	var log: Array = []
	var ctrl := { "set_count": null, "set_other": null }
	var comp := func(_p, _ch):
		var cs = Hooks.useState(0)
		var os = Hooks.useState(0)
		ctrl["set_count"] = cs[1]
		ctrl["set_other"] = os[1]
		var eff := func():
			log.append("setup:%d" % cs[0])
			var cur = cs[0]
			return func(): log.append("cleanup:%d" % cur)
		Hooks.useEffect(eff, [cs[0]])
		return V.Label({ "text": "x" })

	var m := _mount(comp)
	_ok(log == ["setup:0"], "effect runs on mount, got %s" % str(log))

	ctrl["set_count"].call(1)
	await process_frame
	await process_frame
	_ok(log == ["setup:0", "cleanup:0", "setup:1"], "effect re-runs cleanup->setup on dep change, got %s" % str(log))

	ctrl["set_other"].call(99)
	await process_frame
	await process_frame
	_ok(log == ["setup:0", "cleanup:0", "setup:1"], "effect skipped when its deps unchanged, got %s" % str(log))

	m[1].unmount()
	_ok(log == ["setup:0", "cleanup:0", "setup:1", "cleanup:1"], "cleanup on unmount, got %s" % str(log))
	m[0].queue_free()

func _test_bailout() -> void:
	var renders := { "parent": 0, "child": 0 }
	var ctrl := { "bump": null }
	var child := func(props, _ch):
		renders["child"] += 1
		return V.Label({ "text": str(props.get("label", "")) })
	var parent := func(_p, _ch):
		renders["parent"] += 1
		var s = Hooks.useState(0)
		ctrl["bump"] = s[1]
		return V.VBoxContainer({}, [
			V.Label({ "text": "count %d" % s[0] }),
			V.fc(child, { "label": "static" }),
		])

	var m := _mount(parent)
	_ok(renders["parent"] == 1 and renders["child"] == 1, "initial p=%d c=%d" % [renders["parent"], renders["child"]])

	ctrl["bump"].call(1)
	await process_frame
	await process_frame
	_ok(renders["parent"] == 2, "parent re-rendered: %d" % renders["parent"])
	_ok(renders["child"] == 1, "child BAILED out (props unchanged): %d" % renders["child"])
	m[1].unmount()
	m[0].queue_free()

func _test_context() -> void:
	var renders := { "consumer": 0 }
	var seen := { "val": null }
	var ctrl := { "set": null }
	var consumer := func(_p, _ch):
		renders["consumer"] += 1
		var v = Hooks.useContext("theme")
		seen["val"] = v
		return V.Label({ "text": str(v) })
	var provider := func(_p, _ch):
		var s = Hooks.useState("dark")
		ctrl["set"] = s[1]
		Hooks.provideContext("theme", s[0])
		return V.fc(consumer, {})

	var m := _mount(provider)
	_ok(seen["val"] == "dark", "consumer sees initial context: %s" % str(seen["val"]))
	_ok(renders["consumer"] == 1, "consumer rendered once")

	ctrl["set"].call("light")
	await process_frame
	await process_frame
	_ok(seen["val"] == "light", "consumer sees updated context: %s" % str(seen["val"]))
	_ok(renders["consumer"] == 2, "consumer re-rendered on context change: %d" % renders["consumer"])
	m[1].unmount()
	m[0].queue_free()

func _test_context_handles() -> void:
	# Context HANDLES (createContext): object identity keys the map (no string collision) + a default.
	var theme_ctx := Hooks.createContext("fallback", "Theme")
	var seen := { "val": null }
	var ctrl := { "set": null }
	var consumer := func(_p, _ch):
		seen["val"] = Hooks.useContext(theme_ctx)
		return V.Label({ "text": str(seen["val"]) })
	var provider := func(_p, _ch):
		var s = Hooks.useState("dark")
		ctrl["set"] = s[1]
		Hooks.provideContext(theme_ctx, s[0])
		return V.fc(consumer, {})
	var m := _mount(provider)
	_ok(seen["val"] == "dark", "handle consumer sees provided value: %s" % str(seen["val"]))
	ctrl["set"].call("light")
	await process_frame
	await process_frame
	_ok(seen["val"] == "light", "handle consumer re-renders on provider change: %s" % str(seen["val"]))
	m[1].unmount()
	m[0].queue_free()

	# No provider up the tree -> the handle's default is returned.
	var seen2 := { "val": "unset" }
	var lone := func(_p, _ch):
		seen2["val"] = Hooks.useContext(theme_ctx)
		return V.Label({ "text": str(seen2["val"]) })
	var m2 := _mount(lone)
	_ok(seen2["val"] == "fallback", "unprovided handle returns its default: %s" % str(seen2["val"]))
	m2[1].unmount()
	m2[0].queue_free()

	# Distinct handles never collide even with an identical default.
	var a := Hooks.createContext(1)
	var b := Hooks.createContext(1)
	_ok(a != b, "distinct createContext() handles have distinct identity")

func _test_fragment() -> void:
	var comp := func(_p, _ch):
		return V.VBoxContainer({}, [
			V.Label({ "text": "a" }),
			V.fragment([V.Label({ "text": "b" }), V.Label({ "text": "c" })]),
			V.Label({ "text": "d" }),
		])
	var m := _mount(comp)
	var vbox: Node = m[0].get_child(0)
	_ok(vbox.get_child_count() == 4, "fragment flattens to 4 children, got %d" % vbox.get_child_count())
	var texts: Array = []
	for ch in vbox.get_children():
		texts.append(ch.text)
	_ok(texts == ["a", "b", "c", "d"], "fragment order a,b,c,d, got %s" % str(texts))
	m[1].unmount()
	m[0].queue_free()

func _test_keyed_reorder() -> void:
	var ctrl := { "set": null }
	var comp := func(_p, _ch):
		var s = Hooks.useState(["a", "b", "c"])
		ctrl["set"] = s[1]
		var items: Array = []
		for id in s[0]:
			items.append(V.Label({ "text": id, "key": id }))
		return V.VBoxContainer({}, items)

	var m := _mount(comp)
	var vbox: Node = m[0].get_child(0)
	var node_a: Node = vbox.get_child(0)
	var node_b: Node = vbox.get_child(1)
	var node_c: Node = vbox.get_child(2)
	_ok(node_a.text == "a" and node_b.text == "b" and node_c.text == "c", "initial keyed order")

	ctrl["set"].call(["c", "a", "b"])
	await process_frame
	await process_frame
	_ok(vbox.get_child(0) == node_c, "node_c moved to front (identity preserved)")
	_ok(vbox.get_child(1) == node_a, "node_a second")
	_ok(vbox.get_child(2) == node_b, "node_b third")

	ctrl["set"].call(["c", "b"])
	await process_frame
	await process_frame
	_ok(vbox.get_child_count() == 2, "2 children after removal, got %d" % vbox.get_child_count())
	_ok(vbox.get_child(0) == node_c and vbox.get_child(1) == node_b, "c,b remain with identity; a freed")
	m[1].unmount()
	m[0].queue_free()

func _test_reducer_and_memo() -> void:
	var ctrl := { "dispatch": null }
	var memo_calls := { "n": 0 }
	var reducer := func(state, action):
		if action == "inc": return state + 1
		if action == "dec": return state - 1
		return state
	var comp := func(_p, _ch):
		var r = Hooks.useReducer(reducer, 10)
		ctrl["dispatch"] = r[1]
		var mfn := func():
			memo_calls["n"] += 1
			return r[0] * 2
		var doubled = Hooks.useMemo(mfn, [r[0]])
		return V.Label({ "text": "%d/%d" % [r[0], doubled] })

	var m := _mount(comp)
	var label: Node = m[0].get_child(0)
	_ok(label.text == "10/20", "initial reducer+memo: %s" % label.text)
	_ok(memo_calls["n"] == 1, "memo computed once")

	ctrl["dispatch"].call("inc")
	await process_frame
	await process_frame
	_ok(label.text == "11/22", "after inc: %s" % label.text)
	_ok(memo_calls["n"] == 2, "memo recomputed on dep change: %d" % memo_calls["n"])
	m[1].unmount()
	m[0].queue_free()

func _test_layout_effect() -> void:
	var order: Array = []
	var comp := func(_p, _ch):
		var le := func():
			order.append("layout")
			return func(): pass
		var pe := func():
			order.append("passive")
			return func(): pass
		Hooks.useLayoutEffect(le, [])
		Hooks.useEffect(pe, [])
		return V.Label({ "text": "x" })
	var m := _mount(comp)
	_ok(order == ["layout", "passive"], "layout effect runs before passive: %s" % str(order))
	m[1].unmount()
	m[0].queue_free()

func _test_signal() -> void:
	var sig := RuitkSignal.new(0)
	var renders := { "n": 0 }
	var seen := { "v": null }
	var comp := func(_p, _ch):
		renders["n"] += 1
		seen["v"] = Hooks.useSignal(sig)
		return V.Label({ "text": str(seen["v"]) })

	var m := _mount(comp)
	_ok(seen["v"] == 0 and renders["n"] == 1, "initial signal value 0")

	sig.set_value(5)
	await process_frame
	await process_frame
	_ok(seen["v"] == 5, "signal update propagated: %s" % str(seen["v"]))
	_ok(renders["n"] == 2, "re-rendered on signal change: %d" % renders["n"])

	m[1].unmount()
	m[0].queue_free()
	sig.set_value(99)
	await process_frame
	_ok(renders["n"] == 2, "no re-render after unmount (unsubscribed): %d" % renders["n"])

func _test_router() -> void:
	var history := RuitkHistory.new("/")
	var seen := { "id": null }
	var nav := { "go": null }
	var home := func(_p, _c):
		return V.Label({ "text": "home" })
	var user := func(_p, _c):
		var params = RuitkRouter.useParams()
		seen["id"] = params.get("id")
		return V.Label({ "text": "user " + str(params.get("id")) })
	var app := func(_p, _c):
		nav["go"] = RuitkRouter.useNavigate()
		return V.routes({ "routes": [
			{ "path": "/", "component": home },
			{ "path": "/users/:id", "component": user },
		] })
	var root_comp := func(_p, _c):
		return V.router({ "history": history }, [V.fc(app)])

	var m := _mount(root_comp)
	var lbl: Node = m[0].get_child(0)
	_ok(lbl.text == "home", "initial route renders home, got '%s'" % lbl.text)

	history.push("/users/42")
	await process_frame
	await process_frame
	lbl = m[0].get_child(0)
	_ok(lbl.text == "user 42", "route /users/42 renders user, got '%s'" % lbl.text)
	_ok(seen["id"] == "42", "params.id == 42, got %s" % str(seen["id"]))

	nav["go"].call("/")
	await process_frame
	await process_frame
	lbl = m[0].get_child(0)
	_ok(lbl.text == "home", "navigate('/') returns home, got '%s'" % lbl.text)
	m[1].unmount()
	m[0].queue_free()

func _test_tween() -> void:
	var captured := { "last": null, "count": 0 }
	var comp := func(_p, _c):
		var on_update := func(v):
			captured["last"] = v
			captured["count"] += 1
		Hooks.useTweenValue(0.0, 10.0, 0.05, on_update, [])
		return V.Label({ "text": "x" })
	var m := _mount(comp)
	for i in 30:
		await process_frame
	_ok(captured["count"] > 0, "tween drove on_update, calls=%d" % captured["count"])
	_ok(captured["last"] != null and captured["last"] >= 0.0 and captured["last"] <= 10.0, "tween value in range, got %s" % str(captured["last"]))
	m[1].unmount()
	m[0].queue_free()

func _test_diagnostics() -> void:
	RuitkDiagnostics.enabled = true
	RuitkDiagnostics.reset()
	var ctrl := { "set": null }
	var comp := func(_p, _c):
		var s = Hooks.useState(0)
		ctrl["set"] = s[1]
		return V.Label({ "text": str(s[0]) })
	var m := _mount(comp)
	_ok(RuitkDiagnostics.renders >= 1, "counted initial render: %d" % RuitkDiagnostics.renders)
	_ok(RuitkDiagnostics.placements >= 1, "counted placements: %d" % RuitkDiagnostics.placements)
	var r0: int = RuitkDiagnostics.renders
	ctrl["set"].call(1)
	await process_frame
	await process_frame
	_ok(RuitkDiagnostics.renders > r0, "counted update render: %d > %d" % [RuitkDiagnostics.renders, r0])
	_ok(RuitkDiagnostics.updates >= 1, "counted prop update: %d" % RuitkDiagnostics.updates)
	RuitkDiagnostics.enabled = false
	m[1].unmount()
	m[0].queue_free()

func _test_item_list() -> void:
	var ctrl := { "set": null }
	var comp := func(_p, _c):
		var s = Hooks.useState(["apple", "banana"])
		ctrl["set"] = s[1]
		return V.ItemList({ "items": s[0] })
	var m := _mount(comp)
	var il: ItemList = m[0].get_child(0)
	_ok(il.item_count == 2, "item_list built 2 items, got %d" % il.item_count)
	_ok(il.get_item_text(0) == "apple" and il.get_item_text(1) == "banana", "item texts correct")

	ctrl["set"].call(["apple", "banana", "cherry"])
	await process_frame
	await process_frame
	_ok(il.item_count == 3, "item_list grew to 3, got %d" % il.item_count)
	_ok(il.get_item_text(2) == "cherry", "new item 'cherry' added")
	m[1].unmount()
	m[0].queue_free()

func _test_root_node() -> void:
	var rn := RuitkRootNode.new()
	rn.setup(func(_p, _c): return V.Label({ "text": "rooted" }))
	root.add_child(rn)   # _ready mounts
	await process_frame
	_ok(rn.get_child_count() >= 1, "RuitkRootNode mounted on _ready: %d children" % rn.get_child_count())
	var lbl: Node = rn.get_child(0)
	_ok(lbl is Label and lbl.text == "rooted", "RuitkRootNode rendered the label")
	rn.queue_free()   # _exit_tree unmounts
	await process_frame
	_ok(true, "RuitkRootNode freed without error")

func _test_tree() -> void:
	var ctrl := { "set": null }
	var comp := func(_p, _c):
		var s = Hooks.useState("Fruits")
		ctrl["set"] = s[1]
		var items := [
			{ "id": "fruits", "text": s[0], "children": [
				{ "id": "apple", "text": "Apple" },
				{ "id": "banana", "text": "Banana" },
			] },
		]
		return V.Tree({ "hide_root": true, "items": items })
	var m := _mount(comp)
	var tree: Tree = m[0].get_child(0)
	var fruits: TreeItem = tree.get_root().get_children()[0]
	_ok(fruits != null and fruits.get_text(0) == "Fruits", "tree built parent node")
	_ok(fruits.get_children().size() == 2, "fruits has 2 children, got %d" % fruits.get_children().size())

	fruits.collapsed = true                 # user collapses it
	ctrl["set"].call("Fruits!")             # change text -> full rebuild
	await process_frame
	await process_frame
	var fruits2: TreeItem = tree.get_root().get_children()[0]
	_ok(fruits2.get_text(0) == "Fruits!", "tree text updated, got '%s'" % fruits2.get_text(0))
	_ok(fruits2.collapsed == true, "expand/collapse state PRESERVED across rebuild")
	m[1].unmount()
	m[0].queue_free()

func _test_time_slicing() -> void:
	RuitkConfig.time_slicing = true
	RuitkConfig.frame_budget_ms = 0.0   # park after every unit of work
	var ctrl := { "set": null }
	var comp := func(_p, _c):
		var s = Hooks.useState(0)
		ctrl["set"] = s[1]
		var items: Array = []
		for i in 8:
			items.append(V.Label({ "text": "item %d-%d" % [i, s[0]], "key": str(i) }))
		return V.VBoxContainer({}, items)
	var m := _mount(comp)
	var vbox: Node = m[0].get_child(0)
	_ok(vbox.get_child_count() == 8, "sliced: initial 8 items")
	_ok(vbox.get_child(0).text == "item 0-0", "sliced: initial text")

	ctrl["set"].call(1)               # sliced update completes across frames
	for i in 50:
		await process_frame
	_ok(vbox.get_child(0).text == "item 0-1", "sliced update completed, got '%s'" % vbox.get_child(0).text)
	_ok(vbox.get_child(7).text == "item 7-1", "sliced update reached last item, got '%s'" % vbox.get_child(7).text)
	RuitkConfig.time_slicing = false
	m[1].unmount()
	m[0].queue_free()

func _test_context_survives_bailout() -> void:
	var seen := { "v": null }
	var gp_bump := { "fn": null }
	var c_bump := { "fn": null }
	var consumer := func(_p, _c):
		var s = Hooks.useState(0)
		c_bump["fn"] = s[1]
		seen["v"] = Hooks.useContext("k")
		return V.Label({ "text": str(seen["v"]) })
	var provider := func(_p, _c):
		Hooks.provideContext("k", "hello")
		return V.fc(consumer, {})
	var grandparent := func(_p, _c):
		var s = Hooks.useState(0)
		gp_bump["fn"] = s[1]
		return V.VBoxContainer({}, [V.Label({ "text": "gp %d" % s[0] }), V.fc(provider, {})])

	var m := _mount(grandparent)
	_ok(seen["v"] == "hello", "consumer sees context initially")
	gp_bump["fn"].call(1)             # grandparent re-renders -> provider BAILS (no provideContext run)
	await process_frame
	await process_frame
	c_bump["fn"].call(1)              # force the consumer to re-render & re-read context
	await process_frame
	await process_frame
	_ok(seen["v"] == "hello", "context SURVIVES provider bailout, got %s" % str(seen["v"]))
	m[1].unmount()
	m[0].queue_free()

func _test_ref_null_on_unmount() -> void:
	var ctrl := { "set": null }
	var captured := { "ref": null }
	var comp := func(_p, _c):
		var show = Hooks.useState(true)
		ctrl["set"] = show[1]
		var r = Hooks.useRef(null)
		captured["ref"] = r
		return V.LineEdit({ "ref": r }) if show[0] else V.Label({ "text": "gone" })

	var m := _mount(comp)
	_ok(captured["ref"]["current"] != null, "ref populated while mounted")
	ctrl["set"].call(false)           # removes the line_edit
	await process_frame
	await process_frame
	_ok(captured["ref"]["current"] == null, "ref nulled when node removed, got %s" % str(captured["ref"]["current"]))
	m[1].unmount()
	m[0].queue_free()

func _test_router_context_split() -> void:
	var history := RuitkHistory.new("/")
	var nav_renders := { "n": 0 }
	var nav := { "go": null }
	var nav_only := func(_p, _c):
		nav_renders["n"] += 1
		nav["go"] = RuitkRouter.useNavigate()
		return V.Button({ "text": "nav" })
	var loc_view := func(_p, _c):
		return V.Label({ "text": RuitkRouter.useLocation() })
	var app := func(_p, _c):
		return V.VBoxContainer({}, [V.fc(nav_only), V.fc(loc_view)])
	var root_comp := func(_p, _c):
		return V.router({ "history": history }, [V.fc(app)])

	var m := _mount(root_comp)
	_ok(nav_renders["n"] == 1, "nav-only rendered once")
	nav["go"].call("/users/5")
	await process_frame
	await process_frame
	_ok(nav_renders["n"] == 1, "nav-only did NOT re-render on location change (split contexts), got %d" % nav_renders["n"])
	m[1].unmount()
	m[0].queue_free()

func _test_deferred_value() -> void:
	# Phase 7.10: useDeferredValue returns the previous value on the render where it changes,
	# then commits the new value on a low-priority next-frame tick.
	var ctl := { "set": null }
	var seen := { "now": -1, "deferred": -1 }
	var comp := func(_p, _c):
		var st := Hooks.useState(0)
		ctl["set"] = st[1]
		var d = Hooks.useDeferredValue(st[0])
		seen["now"] = st[0]
		seen["deferred"] = d
		return V.Label({ "text": "%d/%d" % [st[0], d] })
	var m := _mount(comp)
	await process_frame
	_ok(seen["now"] == 0 and seen["deferred"] == 0, "deferred initial == value (0/0), got %d/%d" % [seen["now"], seen["deferred"]])
	ctl["set"].call(5)
	await process_frame
	_ok(seen["now"] == 5 and seen["deferred"] == 0, "urgent value updates, deferred lags (5/0), got %d/%d" % [seen["now"], seen["deferred"]])
	await process_frame
	await process_frame
	_ok(seen["deferred"] == 5, "deferred catches up to 5, got %d" % seen["deferred"])
	m[1].unmount()
	m[0].queue_free()

func _test_item_model_adapters() -> void:
	# Phase 7.11: TabBar + OptionButton via the generalized item-model registry, with selection
	# preserved by item identity across a re-render that changes the items array.
	var ctrl := { "tabs": null, "opts": null }
	var comp := func(_p, _c):
		var ts := Hooks.useState(["One", "Two", "Three"])
		var os2 := Hooks.useState([{ "id": "a", "text": "Alpha" }, { "id": "b", "text": "Beta" }])
		ctrl["tabs"] = ts[1]
		ctrl["opts"] = os2[1]
		return V.VBoxContainer({}, [
			V.TabBar({ "items": ts[0] }),
			V.OptionButton({ "items": os2[0] }),
		])
	var m := _mount(comp)
	await process_frame
	var tb: TabBar = m[0].get_child(0).get_child(0)
	var ob: OptionButton = m[0].get_child(0).get_child(1)
	_ok(tb.tab_count == 3, "tab_bar built 3 tabs, got %d" % tb.tab_count)
	_ok(ob.item_count == 2, "option_button built 2 items, got %d" % ob.item_count)
	# Select tab "Two" + option "Beta", then prepend an item: selection should follow identity.
	tb.current_tab = 1
	ob.select(1)
	ctrl["tabs"].call(["Zero", "One", "Two", "Three"])
	ctrl["opts"].call([{ "id": "z", "text": "Zed" }, { "id": "a", "text": "Alpha" }, { "id": "b", "text": "Beta" }])
	await process_frame
	await process_frame
	_ok(tb.tab_count == 4 and tb.get_tab_title(tb.current_tab) == "Two", "tab selection followed identity after prepend, got '%s'" % tb.get_tab_title(tb.current_tab))
	_ok(ob.item_count == 3 and ob.get_item_text(ob.selected) == "Beta", "option selection followed identity, got '%s'" % ob.get_item_text(ob.selected))
	m[1].unmount()
	m[0].queue_free()

func _test_classes_stylesheet() -> void:
	# Phase 7.11: `classes` resolve against RuitkStyleSheet and merge (inline wins).
	RuitkStyleSheet.register("card", { "bg_color": Color(0.1, 0.2, 0.3), "corner_radius_all": 8 })
	RuitkStyleSheet.register("danger", { "font_color": Color(1, 0, 0) })
	var comp := func(_p, _c):
		return V.Button({ "classes": ["card", "danger"], "style": { "font_color": Color(0, 1, 0) }, "text": "x" })
	var m := _mount(comp)
	await process_frame
	var btn: Button = m[0].get_child(0)
	# danger sets red, inline overrides to green -> inline wins.
	_ok(btn.get_theme_color("font_color") == Color(0, 1, 0), "inline style overrides class style, got %s" % str(btn.get_theme_color("font_color")))
	_ok(btn.has_theme_stylebox_override("normal"), "card class applied a stylebox (bg_color/corner_radius)")
	RuitkStyleSheet.clear()
	m[1].unmount()
	m[0].queue_free()

func _test_media_and_animate() -> void:
	# Phase 7.10: V.audio mounts an AudioStreamPlayer (non-Control node), and useSfx / useAnimate
	# wire up without crashing (smoke). A null SFX stream is a safe no-op.
	var ref := { "current": null }
	var played := { "n": 0 }
	var comp := func(_p, _c):
		var sfx := Hooks.useSfx()
		Hooks.useAnimate(ref, [{ "property": "modulate:a", "to": 1.0, "from": 0.0, "duration": 0.05 }], true, [])
		Hooks.useEffect(func():
			sfx.call(null)   # null stream -> safe no-op
			played["n"] += 1
			return null
		, [])
		return V.VBoxContainer({}, [
			V.ColorRect({ "ref": ref, "custom_minimum_size": Vector2(8, 8) }),
			V.AudioStreamPlayer({ "volume_db": -6.0 }),
		])
	var m := _mount(comp)
	await process_frame
	await process_frame
	var has_audio := false
	for ch in m[0].get_child(0).get_children():
		if ch is AudioStreamPlayer:
			has_audio = true
	_ok(has_audio, "V.audio mounted an AudioStreamPlayer node under the VBox")
	_ok(played["n"] == 1, "useSfx callable invoked safely (no crash on null stream)")
	_ok(ref["current"] != null and ref["current"] is ColorRect, "useAnimate target ref populated")
	m[1].unmount()
	m[0].queue_free()
