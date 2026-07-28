class_name DemoBox
extends RefCounted
## AUTO-GENERATED from demos_demo_box.guitkx -- do not edit.

const __RUI_HOOK_SIG := ""

const __RUI_KIND := "component"

static func render(props: Dictionary, children: Array) -> RuitkVNode:
	var title = props.get("title", "")
	return V.MarginContainer({ "style": {"margin_left": 20, "margin_top": 20, "margin_right": 20, "margin_bottom": 20} }, [V.VBoxContainer({ "style": {"separation": 12} }, [V.Label({ "text": title, "style": {"font_size": 24, "font_color": Color(0.55, 0.8, 1.0)} }), V.HSeparator({}), (children)])])
