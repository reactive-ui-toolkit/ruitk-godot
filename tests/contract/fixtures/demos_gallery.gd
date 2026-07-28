class_name DemoGallery
extends RefCounted
## AUTO-GENERATED from demos_gallery.guitkx -- do not edit.

const __RUI_HOOK_SIG := "useState"

const __RUI_KIND := "component"

static func render(props: Dictionary, children: Array) -> RuitkVNode:
	var sel = Hooks.useState(0)
	var demos := DemoGalleryTable.entries()
	var buttons: Array = []
	for i in demos.size():
		var idx := i
		var is_sel: bool = sel[0] == i
		buttons.append(V.Button({
			"text": demos[i]["title"],
			"onPressed": func(): sel[1].call(idx),
			"style": {
				"size_flags_horizontal": Control.SIZE_EXPAND_FILL,
				"bg_color": Color(0.2, 0.4, 0.7) if is_sel else Color(0.18, 0.18, 0.22),
				"corner_radius_all": 4, "content_margin_all": 6,
			},
		}))
	return V.HBoxContainer({ "style": {"anchors_preset": Control.PRESET_FULL_RECT} }, [V.PanelContainer({ "style": {"bg_color": Color(0.1, 0.1, 0.12), "min_width": 210} }, [V.MarginContainer({ "style": {"margin_left": 8, "margin_top": 8, "margin_right": 8, "margin_bottom": 8} }, [V.VBoxContainer({ "style": {"separation": 4, "size_flags_vertical": Control.SIZE_EXPAND_FILL} }, [V.Label({ "text": "Reactive UI Toolkit — Godot", "style": {"font_size": 22, "font_color": Color(0.0, 0.9, 0.75)} }), V.Label({ "text": "Godot demo gallery", "style": {"font_color": Color(0.6, 0.6, 0.6)} }), V.HSeparator({}), V.ScrollContainer({ "horizontal_scroll_mode": ScrollContainer.SCROLL_MODE_DISABLED, "style": {"size_flags_vertical": Control.SIZE_EXPAND_FILL} }, [V.VBoxContainer({ "style": {"separation": 4} }, [(buttons)])])])])]), V.PanelContainer({ "style": {"bg_color": Color(0.13, 0.13, 0.16), "size_flags_horizontal": Control.SIZE_EXPAND_FILL, "size_flags_vertical": Control.SIZE_EXPAND_FILL} }, [(V.fc(demos[sel[0]]["fn"]))])])
