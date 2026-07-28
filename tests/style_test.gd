extends SceneTree
## Headless tests for the style layer (apply/diff/reset across all channels) and the
## expanded element factories. Run:
##   godot --headless --path <project> --script res://tests/style_test.gd

var _fails := 0
var _passes := 0

func _initialize() -> void:
	_run()

func _run() -> void:
	await _test_style_apply_and_reset()
	await _test_theme_channels()
	await _test_stylebox_builder()
	await _test_state_styles()
	await _test_elements_instantiate()
	await _test_loyal_keys_090()
	print("\n[style_test] %d passed, %d failed" % [_passes, _fails])
	quit(1 if _fails > 0 else 0)

func _ok(cond: bool, msg: String) -> void:
	if cond: _passes += 1
	else:
		_fails += 1
		printerr("  FAIL: " + msg)
		push_error("FAIL: " + msg)

func _mount(fn: Callable, props := {}) -> Array:
	var c := Control.new()
	root.add_child(c)
	return [c, RuitkRoot.create(c, V.fc(fn, props))]

## 0.9.0 naming loyalty: exact Godot names, Godot enum-name strings, anchors_preset,
## verbatim StyleBoxFlat properties + *_all umbrellas, radians rotation, removed-key no-op.
func _test_loyal_keys_090() -> void:
	var n := Control.new()
	# size flags: raw constant, exact name string, case-insensitive tail
	RuitkStyle.apply(n, {}, { "size_flags_horizontal": Control.SIZE_EXPAND_FILL })
	_ok(n.size_flags_horizontal == Control.SIZE_EXPAND_FILL, "size_flags_horizontal takes the Godot constant")
	RuitkStyle.apply(n, { "size_flags_horizontal": Control.SIZE_EXPAND_FILL }, { "size_flags_horizontal": "SIZE_SHRINK_CENTER" })
	_ok(n.size_flags_horizontal == Control.SIZE_SHRINK_CENTER, "exact constant-name string accepted")
	RuitkStyle.apply(n, { "size_flags_horizontal": "SIZE_SHRINK_CENTER" }, { "size_flags_vertical": "expand_fill" })
	_ok(n.size_flags_horizontal == Control.SIZE_FILL, "removed size_flags_horizontal resets to SIZE_FILL")
	_ok(n.size_flags_vertical == Control.SIZE_EXPAND_FILL, "unprefixed constant tail accepted (case-insensitive)")
	# anchors_preset (replaces the pre-0.9 `fill` extension)
	RuitkStyle.apply(n, {}, { "anchors_preset": Control.PRESET_FULL_RECT })
	_ok(n.anchor_right == 1.0 and n.anchor_bottom == 1.0, "anchors_preset PRESET_FULL_RECT anchors the control")
	RuitkStyle.apply(n, { "anchors_preset": Control.PRESET_FULL_RECT }, { "anchors_preset": "PRESET_TOP_LEFT" })
	_ok(n.anchor_right == 0.0, "anchors_preset accepts the constant-name string")
	# custom_minimum_size exact name + the kept min_width/min_height extensions
	RuitkStyle.apply(n, {}, { "custom_minimum_size": Vector2(30, 40) })
	_ok(n.custom_minimum_size == Vector2(30, 40), "custom_minimum_size applies verbatim")
	RuitkStyle.apply(n, { "custom_minimum_size": Vector2(30, 40) }, { "min_width": 55 })
	_ok(n.custom_minimum_size == Vector2(55, 0), "min_width extension sets .x (removed custom_minimum_size resets first)")
	# rotation is radians now (Godot's own semantics)
	RuitkStyle.apply(n, {}, { "rotation": PI })
	_ok(absf(n.rotation - PI) < 0.0001, "style rotation is radians, applied verbatim")
	# exact property/theme names that replaced shorthands
	RuitkStyle.apply(n, {}, { "tooltip_text": "tip", "clip_contents": true, "pivot_offset": Vector2(3, 4), "font_outline_color": Color.RED })
	_ok(n.tooltip_text == "tip" and n.clip_contents and n.pivot_offset == Vector2(3, 4), "tooltip_text/clip_contents/pivot_offset apply")
	_ok(n.get_theme_color("font_outline_color") == Color.RED, "font_outline_color theme override applies")
	n.free()
	# StyleBox builder: *_all umbrellas + ANY StyleBoxFlat property verbatim; per-side wins over umbrella
	var p := PanelContainer.new()
	RuitkStyle.apply(p, {}, { "bg_color": Color.BLUE, "corner_radius_all": 6, "border_width_all": 2, "border_width_left": 5, "shadow_size": 3 })
	var sb := p.get_theme_stylebox("panel") as StyleBoxFlat
	_ok(sb != null and sb.bg_color == Color.BLUE, "bg_color (exact StyleBoxFlat name) applies")
	_ok(sb.corner_radius_top_left == 6 and sb.corner_radius_bottom_right == 6, "corner_radius_all umbrella (Godot's set_corner_radius_all)")
	_ok(sb.border_width_top == 2 and sb.border_width_left == 5, "per-side border_width_left wins over the umbrella")
	_ok(sb.shadow_size == 3, "ANY StyleBoxFlat property applies verbatim (shadow_size)")
	p.free()
	# margin_* exact theme constants (replaced the `margin` umbrella)
	var m := MarginContainer.new()
	RuitkStyle.apply(m, {}, { "margin_left": 7, "margin_top": 8 })
	_ok(m.get_theme_constant("margin_left") == 7 and m.get_theme_constant("margin_top") == 8, "margin_* exact theme constants apply")
	m.free()
	# a removed pre-0.9 key is a warning + no-op, never a silent misapply
	var q := Control.new()
	var before := q.custom_minimum_size
	RuitkStyle.apply(q, {}, { "min_size": Vector2(9, 9) })
	_ok(q.custom_minimum_size == before, "removed key 'min_size' does not apply (warns with the rename)")
	q.free()

func _test_state_styles() -> void:
	# Phase 7.3: per-state StyleBox slots (Godot retains hover/pressed/etc. natively).
	var btn := Button.new()
	RuitkStyle.apply(btn, {}, { "hover": { "bg_color": Color.RED }, "pressed": { "bg_color": Color.BLUE } })
	_ok(btn.has_theme_stylebox_override("hover"), "hover state stylebox applied to Button")
	_ok(btn.has_theme_stylebox_override("pressed"), "pressed state stylebox applied to Button")
	RuitkStyle.apply(btn, { "hover": { "bg_color": Color.RED }, "pressed": { "bg_color": Color.BLUE } }, { "pressed": { "bg_color": Color.BLUE } })
	_ok(not btn.has_theme_stylebox_override("hover"), "removed hover state stylebox")
	_ok(btn.has_theme_stylebox_override("pressed"), "kept unchanged pressed state stylebox")
	# a Label has no hover slot -> warn-once + no override (never crashes)
	var lbl := Label.new()
	RuitkStyle.apply(lbl, {}, { "hover": { "bg_color": Color.RED } })
	_ok(not lbl.has_theme_stylebox_override("hover"), "Label has no hover slot -> no override")
	btn.free()
	lbl.free()

func _test_style_apply_and_reset() -> void:
	var ctrl := { "set": null }
	var comp := func(_p, _ch):
		var s = Hooks.useState(true)
		ctrl["set"] = s[1]
		var style := { "min_width": 120, "modulate": Color(1, 0, 0) }
		if s[0]:
			style["font_size"] = 22
		return V.Label({ "text": "hi", "style": style })

	var m := _mount(comp)
	var lbl: Control = m[0].get_child(0)
	_ok(lbl.custom_minimum_size.x == 120, "min_width applied: %s" % str(lbl.custom_minimum_size.x))
	_ok(lbl.modulate == Color(1, 0, 0), "modulate applied")
	_ok(lbl.has_theme_font_size_override("font_size"), "font_size override applied")

	ctrl["set"].call(false)
	await process_frame
	await process_frame
	_ok(not lbl.has_theme_font_size_override("font_size"), "font_size override REMOVED on style-key removal")
	_ok(lbl.custom_minimum_size.x == 120, "min_width still applied after partial style change")
	m[1].unmount()
	m[0].queue_free()

func _test_theme_channels() -> void:
	var ctrl := { "set": null }
	var comp := func(_p, _ch):
		var s = Hooks.useState(true)
		ctrl["set"] = s[1]
		var colors := { "font_color": Color(0, 1, 0) }
		if s[0]:
			colors["font_outline_color"] = Color(0, 0, 1)
		return V.Label({ "text": "x", "style": { "colors": colors, "constants": { "outline_size": 3 } } })

	var m := _mount(comp)
	var lbl: Control = m[0].get_child(0)
	_ok(lbl.get_theme_color("font_color") == Color(0, 1, 0), "generic color channel applied")
	_ok(lbl.has_theme_color_override("font_outline_color"), "second color override applied")
	_ok(lbl.get_theme_constant("outline_size") == 3, "generic constant channel applied")

	ctrl["set"].call(false)
	await process_frame
	await process_frame
	_ok(not lbl.has_theme_color_override("font_outline_color"), "removed color override pruned (inner diff)")
	_ok(lbl.has_theme_color_override("font_color"), "kept color override retained")
	m[1].unmount()
	m[0].queue_free()

func _test_stylebox_builder() -> void:
	var comp := func(_p, _ch):
		return V.PanelContainer({ "style": { "bg_color": Color(0.2, 0.2, 0.2), "corner_radius_all": 8, "border_width_all": 2, "border_color": Color(1, 1, 1) } })
	var m := _mount(comp)
	var panel: Control = m[0].get_child(0)
	var sb := panel.get_theme_stylebox("panel")
	_ok(sb is StyleBoxFlat, "StyleBoxFlat built for panel")
	_ok(sb.bg_color == Color(0.2, 0.2, 0.2), "bg_color set")
	_ok(sb.corner_radius_top_left == 8, "corner_radius set")
	_ok(sb.border_width_left == 2, "border_width set")
	m[1].unmount()
	m[0].queue_free()

func _test_elements_instantiate() -> void:
	var comp := func(_p, _ch):
		return V.VBoxContainer({}, [
			V.Button({ "text": "B" }),
			V.CheckButton({ "text": "C" }),
			V.OptionButton({}),
			V.HSlider({}),
			V.ProgressBar({ "value": 50 }),
			V.RichTextLabel({ "text": "rt" }),
			V.TabContainer({}),
			V.Tree({}),
			V.ItemList({}),
		])
	var m := _mount(comp)
	var vbox: Node = m[0].get_child(0)
	_ok(vbox.get_child_count() == 9, "9 varied controls instantiated, got %d" % vbox.get_child_count())
	_ok(vbox.get_child(0) is Button, "button")
	_ok(vbox.get_child(4) is ProgressBar and vbox.get_child(4).value == 50.0, "progress_bar value prop")
	_ok(vbox.get_child(6) is TabContainer, "tabs")
	_ok(vbox.get_child(7) is Tree, "tree instantiated")
	_ok(vbox.get_child(8) is ItemList, "item_list instantiated")
	m[1].unmount()
	m[0].queue_free()
