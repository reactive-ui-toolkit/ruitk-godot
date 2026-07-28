class_name RuitkStyle
extends RefCounted
## Declarative styling for Godot Controls. Godot has no USS/CSS: styling is Control
## properties + size flags (layout) and Theme overrides / StyleBox (paint). This layer
## maps a `style` Dictionary onto all of that, and is the ONLY place that knows Godot
## styling APIs.
##
## NAMING IS 1:1 LOYAL TO GODOT (0.9.0, plans/NAMING_LOYALTY_PROPOSAL.md): every style key is
## the exact Godot property / theme-item / StyleBoxFlat name. The pre-0.9 invented shorthands
## (expand_h, min_size, pad, tooltip, clip, pivot, fill, …) were REMOVED — _RENAMED_STYLE_090
## turns them into a precise "renamed" warning instead of a silent no-op.
##
## THREE LAYERS OF COVERAGE (least to most explicit):
##
## 1. Flat keys — exact Godot names (see `_apply_key` / `_reset`):
##    • Control/CanvasItem properties: custom_minimum_size, size_flags_horizontal,
##      size_flags_vertical, anchors_preset, modulate, self_modulate, rotation (radians —
##      Godot's own semantics), scale, pivot_offset, visible, clip_contents, mouse_filter,
##      tooltip_text, z_index, z_as_relative, material, texture_filter, texture_repeat.
##    • Theme items (exact names): font_color, font, font_size, font_outline_color,
##      outline_size, separation, h_separation, v_separation, margin_left/top/right/bottom.
##    • Documented framework extensions (Godot has no single-property equivalent):
##      min_width / min_height (the x/y of custom_minimum_size — a dict can't set `.x`).
##
## 2. StyleBox builder — ANY StyleBoxFlat/StyleBox property verbatim (bg_color, border_color,
##    border_width_left, corner_radius_top_left, content_margin_bottom, shadow_size, skew, …)
##    plus the `*_all` umbrellas named after Godot's own setters (set_border_width_all etc.):
##    border_width_all, corner_radius_all, content_margin_all, expand_margin_all. They combine
##    into ONE StyleBoxFlat applied to the control's primary stylebox slot.
##
## 3. Generic theme channels — reach ANY theme item of ANY control (100% coverage):
##      "colors": { name: Color }, "constants": { name: int }, "fonts": { name: Font },
##      "font_sizes": { name: int }, "icons": { name: Texture2D }, "styleboxes": { name: StyleBox }
##
## Enum-valued keys accept the raw int / Godot constant (canonical in code:
## Control.SIZE_EXPAND_FILL) or the exact Godot constant NAME as a case-insensitive string
## ("SIZE_EXPAND_FILL", "MOUSE_FILTER_IGNORE", "PRESET_FULL_RECT").
##
## Anything else (anchors, offsets, etc.) is a plain Control property and is set via the
## vnode's normal props, not `style`.

## The `*_all` umbrella keys — named after StyleBoxFlat's own set_*_all methods. Expanded
## FIRST when building, so explicit per-side keys in the same dict win.
const BOX_ALL_KEYS := {
	"border_width_all": "set_border_width_all",
	"corner_radius_all": "set_corner_radius_all",
	"content_margin_all": "set_content_margin_all",
	"expand_margin_all": "set_expand_margin_all",
}
const THEME_CHANNELS := {
	"colors": "color", "constants": "constant", "fonts": "font",
	"font_sizes": "font_size", "icons": "icon", "styleboxes": "stylebox",
}
## Per-state StyleBox slots (Phase 7.3) — these ARE the exact Godot theme stylebox item names.
## Godot retains them natively — no hover/press event wiring. A nested style dict
## `style={ hover: { bg_color: ... }, pressed: { ... } }` builds a StyleBoxFlat for the matching
## slot. Available slots vary by control (Button: hover/pressed/disabled/focus; LineEdit:
## focus/read_only) — requesting one a control lacks warns once.
const STATE_SLOTS := ["hover", "pressed", "focus", "disabled", "read_only"]

## Flat theme-item keys applied as add_theme_*_override with their EXACT Godot item name.
## (Everything else theme-side goes through the generic channels.)
const _THEME_COLOR_KEYS := { "font_color": true, "font_outline_color": true }
const _THEME_CONSTANT_KEYS := {
	"outline_size": true, "separation": true, "h_separation": true, "v_separation": true,
	"margin_left": true, "margin_top": true, "margin_right": true, "margin_bottom": true,
}

## Pre-0.9 shorthand -> what to write instead. NOT a compatibility shim (the old keys do NOT
## apply); consulted only by the unknown-key warning so a stale style gets the exact rename
## instead of a mystery. Remove after one release. [0.9.0 naming loyalty]
const _RENAMED_STYLE_090 := {
	"min_size": "custom_minimum_size",
	"expand_h": "size_flags_horizontal (Control.SIZE_EXPAND_FILL / SIZE_FILL)",
	"expand_v": "size_flags_vertical (Control.SIZE_EXPAND_FILL / SIZE_FILL)",
	"grow_h": "size_flags_horizontal", "grow_v": "size_flags_vertical",
	"h_align": "size_flags_horizontal", "v_align": "size_flags_vertical",
	"fill": "anchors_preset (Control.PRESET_FULL_RECT)",
	"clip": "clip_contents", "tooltip": "tooltip_text", "pivot": "pivot_offset",
	"color": "font_color", "outline_color": "font_outline_color",
	"pad": "content_margin_all", "border_width": "border_width_all",
	"corner_radius": "corner_radius_all",
	"margin": "margin_left/margin_top/margin_right/margin_bottom",
}

## Diff `old_style` against `new_style` and apply the delta to `node`.
static func apply(node: Node, old_style: Dictionary, new_style: Dictionary) -> void:
	if not (node is Control):
		return
	if old_style.is_empty() and new_style.is_empty():
		return

	# 1. Combined StyleBox (rebuild if any box key changed/added/removed).
	if _box_differs(old_style, new_style):
		_apply_box(node, new_style)

	# 1b. Per-state StyleBox slots (hover/pressed/focus/disabled/read_only).
	for st in STATE_SLOTS:
		if _changed(old_style.get(st), new_style.get(st)):
			_apply_state_box(node, st, new_style.get(st))

	# 2. Generic theme channels (inner-diffed per item name). Null-default get so a
	# style with none of these 6 channels (the overwhelmingly common case) allocates
	# ZERO throwaway empty dicts -- only the rare present-channel branch materializes
	# {} for _apply_theme_map. Was `.get(ch, {})` x 6 x (old+new) = 12 empty-dict
	# allocations per styled node per frame. [GO-06]
	for ch in THEME_CHANNELS:
		var oldm = old_style.get(ch)
		var newm = new_style.get(ch)
		if oldm == null and newm == null:
			continue
		var od: Dictionary = oldm if oldm is Dictionary else {}
		var nd: Dictionary = newm if newm is Dictionary else {}
		if od != nd:
			_apply_theme_map(node, THEME_CHANNELS[ch], od, nd)

	# 3. Flat keys: reset removed, apply changed. Iterate the dicts directly
	# instead of `.keys()` -- direct dict iteration yields keys with no Array
	# allocation (the same [perf] pattern host_config.gd uses). [GO-06]
	for k in old_style:
		if new_style.has(k) or _is_box_key(k) or k in STATE_SLOTS or THEME_CHANNELS.has(k):
			continue
		_reset(node, k)
	for k in new_style:
		if _is_box_key(k) or k in STATE_SLOTS or THEME_CHANNELS.has(k):
			continue
		if not old_style.has(k) or _changed(old_style[k], new_style[k]):
			_apply_key(node, k, new_style[k])

## Type-safe "value changed" — GDScript's `!=` RAISES on incompatible Variant operands
## (`3 != "SIZE_FILL"` is a runtime error), and a style value legitimately changes type
## across renders now that enum keys accept ints AND constant-name strings.
static func _changed(a, b) -> bool:
	if typeof(a) != typeof(b):
		return true
	return a != b

# --------------------------------------------------------------------------
# Generic theme channels
# --------------------------------------------------------------------------

static func _apply_theme_map(node: Control, kind: String, old_map: Dictionary, new_map: Dictionary) -> void:
	for name in old_map.keys():
		if not new_map.has(name):
			node.call("remove_theme_%s_override" % kind, name)
	for name in new_map.keys():
		if not old_map.has(name) or _changed(old_map[name], new_map[name]):
			node.call("add_theme_%s_override" % kind, name, new_map[name])

# --------------------------------------------------------------------------
# StyleBox builder — verbatim StyleBoxFlat properties + the *_all umbrellas
# --------------------------------------------------------------------------

## (class-cached) name -> true for every registered StyleBoxFlat property (includes the
## StyleBox base's content_margin_*). Built from ClassDB once, so the box vocabulary is the
## engine's own — zero maintained list, full coverage. [0.9.0 naming loyalty]
static var _sb_props: Dictionary = {}
static func _stylebox_props() -> Dictionary:
	if _sb_props.is_empty():
		for p in ClassDB.class_get_property_list("StyleBoxFlat"):
			var usage: int = p.get("usage", 0)
			if usage & (PROPERTY_USAGE_GROUP | PROPERTY_USAGE_SUBGROUP | PROPERTY_USAGE_CATEGORY):
				continue
			_sb_props[p["name"]] = true
	return _sb_props

static func _is_box_key(k) -> bool:
	return BOX_ALL_KEYS.has(k) or _stylebox_props().has(k)

static func _box_differs(old_style: Dictionary, new_style: Dictionary) -> bool:
	for k in old_style:
		if _is_box_key(k) and _changed(old_style[k], new_style.get(k)):
			return true
	for k in new_style:
		if _is_box_key(k) and not old_style.has(k):
			return true
	return false

static func _apply_box(node: Control, style: Dictionary) -> void:
	var slot := _primary_stylebox_name(node)
	if slot == "":
		# bg_color/border/etc. were requested on a control with no primary stylebox slot
		# (e.g. Label, a box container) — it would silently do nothing. Warn once. [audit M5]
		if not node.has_meta("__rui_boxw"):
			for k in style:
				if _is_box_key(k):
					push_warning("[reactive_ui_toolkit] StyleBox keys (bg_color/border_*/corner_radius_*/content_margin_*) need a Panel/Button/LineEdit-like control; %s has no primary stylebox. (warned once)" % node.get_class())
					node.set_meta("__rui_boxw", true)
					break
		return
	var has_box := false
	for k in style:
		if _is_box_key(k):
			has_box = true
			break
	if not has_box:
		node.remove_theme_stylebox_override(slot)
		return
	node.add_theme_stylebox_override(slot, _build_stylebox(style))

## Build a StyleBoxFlat from the box keys of a style dict: `*_all` umbrellas first (Godot's own
## set_*_all setters), then every verbatim StyleBoxFlat property (per-side keys therefore win
## over an umbrella in the same dict). bg_color defaults to transparent — a border-only or
## margin-only box must not paint a fill.
static func _build_stylebox(style: Dictionary) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	for k in style:
		if BOX_ALL_KEYS.has(k):
			sb.call(BOX_ALL_KEYS[k], style[k])
	for k in style:
		if _stylebox_props().has(k):
			sb.set(k, style[k])
	return sb

## Apply (or remove) the per-state StyleBox override for `slot` from a nested style dict.
static func _apply_state_box(node: Control, slot: String, dict) -> void:
	if dict == null:
		node.remove_theme_stylebox_override(slot)
		return
	if not (dict is Dictionary):
		return
	if not node.has_theme_stylebox(slot):
		var meta := "__rui_state_w_" + slot
		if not node.has_meta(meta):
			push_warning("[reactive_ui_toolkit] style state '%s' isn't available on %s (Button: hover/pressed/disabled/focus; LineEdit: focus/read_only). (warned once)" % [slot, node.get_class()])
			node.set_meta(meta, true)
		return
	node.add_theme_stylebox_override(slot, _build_stylebox(dict))

static func _primary_stylebox_name(node: Control) -> String:
	if node is Panel or node is PanelContainer:
		return "panel"
	if node is Button:  # Button + CheckBox/CheckButton/OptionButton/MenuButton/ColorPickerButton
		return "normal"
	if node is LineEdit or node is TextEdit:
		return "normal"
	if node is ProgressBar:
		return "background"
	return ""   # no meaningful primary stylebox slot — don't write into a phantom "panel" [audit M5]

# --------------------------------------------------------------------------
# Flat keys — exact Godot names
# --------------------------------------------------------------------------

static func _apply_key(node: Control, key: String, value) -> void:
	match key:
		"custom_minimum_size": node.custom_minimum_size = value
		"min_width": node.custom_minimum_size.x = value    # extension: the .x of custom_minimum_size
		"min_height": node.custom_minimum_size.y = value   # extension: the .y of custom_minimum_size
		"anchors_preset":
			# Godot's anchor preset (inspector "Anchors Preset" / set_anchors_preset). Applied
			# with offsets so the preset takes effect immediately, like the editor does.
			node.set_anchors_and_offsets_preset(_enum_val(value, "PRESET_", _ANCHOR_PRESETS, Control.PRESET_TOP_LEFT))
		"size_flags_horizontal": node.size_flags_horizontal = _enum_val(value, "SIZE_", _SIZE_FLAGS, Control.SIZE_FILL)
		"size_flags_vertical": node.size_flags_vertical = _enum_val(value, "SIZE_", _SIZE_FLAGS, Control.SIZE_FILL)
		"modulate": node.modulate = value
		"self_modulate": node.self_modulate = value
		"rotation": node.rotation = value   # radians — Godot's own Control.rotation semantics
		"scale": node.scale = value
		"pivot_offset": node.pivot_offset = value
		"visible": node.visible = value
		"clip_contents": node.clip_contents = value
		"mouse_filter": node.mouse_filter = _enum_val(value, "MOUSE_FILTER_", _MOUSE_FILTERS, Control.MOUSE_FILTER_STOP)
		"tooltip_text": node.tooltip_text = str(value)
		"z_index": node.z_index = value
		"z_as_relative": node.z_as_relative = value
		"material": node.material = value
		"texture_filter": node.texture_filter = value
		"texture_repeat": node.texture_repeat = value
		"font": node.add_theme_font_override("font", value)
		"font_size": node.add_theme_font_size_override("font_size", value)
		_:
			if _THEME_COLOR_KEYS.has(key):
				node.add_theme_color_override(key, value)
			elif _THEME_CONSTANT_KEYS.has(key):
				node.add_theme_constant_override(key, value)
			elif _RENAMED_STYLE_090.has(key):
				push_warning("[reactive_ui_toolkit] style key '%s' was renamed in 0.9.0 -- use %s (see MIGRATION-0.9.md)." % [key, _RENAMED_STYLE_090[key]])
			else:
				push_warning("[reactive_ui_toolkit] Unknown style key '%s' (use the colors/constants/… channels for arbitrary theme items)." % key)

static func _reset(node: Control, key: String) -> void:
	match key:
		"custom_minimum_size": node.custom_minimum_size = Vector2.ZERO
		"min_width": node.custom_minimum_size.x = 0
		"min_height": node.custom_minimum_size.y = 0
		"anchors_preset": node.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		"size_flags_horizontal": node.size_flags_horizontal = Control.SIZE_FILL
		"size_flags_vertical": node.size_flags_vertical = Control.SIZE_FILL
		"modulate": node.modulate = Color.WHITE
		"self_modulate": node.self_modulate = Color.WHITE
		"rotation": node.rotation = 0.0
		"scale": node.scale = Vector2.ONE
		"pivot_offset": node.pivot_offset = Vector2.ZERO
		"visible": node.visible = true
		"clip_contents": node.clip_contents = false
		"mouse_filter": node.mouse_filter = Control.MOUSE_FILTER_STOP
		"tooltip_text": node.tooltip_text = ""
		"z_index": node.z_index = 0
		"z_as_relative": node.z_as_relative = true
		"material": node.material = null
		"texture_filter": node.texture_filter = CanvasItem.TEXTURE_FILTER_PARENT_NODE
		"texture_repeat": node.texture_repeat = CanvasItem.TEXTURE_REPEAT_PARENT_NODE
		"font": node.remove_theme_font_override("font")
		"font_size": node.remove_theme_font_size_override("font_size")
		_:
			if _THEME_COLOR_KEYS.has(key):
				node.remove_theme_color_override(key)
			elif _THEME_CONSTANT_KEYS.has(key):
				node.remove_theme_constant_override(key)

# --------------------------------------------------------------------------
# Enum-name resolution — accept the raw int / Godot constant, or the exact
# Godot constant NAME as a case-insensitive string (with or without prefix).
# --------------------------------------------------------------------------

const _SIZE_FLAGS := {
	"SIZE_SHRINK_BEGIN": 0, "SIZE_FILL": 1, "SIZE_EXPAND": 2, "SIZE_EXPAND_FILL": 3,
	"SIZE_SHRINK_CENTER": 4, "SIZE_SHRINK_END": 8,
}
const _MOUSE_FILTERS := {
	"MOUSE_FILTER_STOP": 0, "MOUSE_FILTER_PASS": 1, "MOUSE_FILTER_IGNORE": 2,
}
const _ANCHOR_PRESETS := {
	"PRESET_TOP_LEFT": 0, "PRESET_TOP_RIGHT": 1, "PRESET_BOTTOM_LEFT": 2, "PRESET_BOTTOM_RIGHT": 3,
	"PRESET_CENTER_LEFT": 4, "PRESET_CENTER_TOP": 5, "PRESET_CENTER_RIGHT": 6, "PRESET_CENTER_BOTTOM": 7,
	"PRESET_CENTER": 8, "PRESET_LEFT_WIDE": 9, "PRESET_TOP_WIDE": 10, "PRESET_RIGHT_WIDE": 11,
	"PRESET_BOTTOM_WIDE": 12, "PRESET_VCENTER_WIDE": 13, "PRESET_HCENTER_WIDE": 14, "PRESET_FULL_RECT": 15,
}

## Resolve an enum-valued style value: ints (and Godot constants, which ARE ints) pass through;
## strings must be the exact Godot constant name, case-insensitive, prefix optional
## ("SIZE_EXPAND_FILL" == "expand_fill" is NOT accepted — the unprefixed form must still be the
## constant's own tail, e.g. "EXPAND_FILL"). Unknown names warn and fall back.
static func _enum_val(value, prefix: String, table: Dictionary, fallback: int) -> int:
	if value is int:
		return value
	if value is String:
		var name := (value as String).to_upper()
		if not name.begins_with(prefix):
			name = prefix + name
		if table.has(name):
			return table[name]
		push_warning("[reactive_ui_toolkit] '%s' is not a Godot %s* constant name." % [value, prefix])
	return fallback
