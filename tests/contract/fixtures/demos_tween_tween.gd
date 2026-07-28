class_name DemoTween
extends RefCounted
## AUTO-GENERATED from demos_tween_tween.guitkx -- do not edit.

const __RUI_HOOK_SIG := "useRef|useState|useTween"

const __RUI_KIND := "component"

static func render(props: Dictionary, children: Array) -> RuitkVNode:
	var box_ref = Hooks.useRef(null)
	var n = Hooks.useState(0)
	Hooks.useTween(box_ref, "modulate", Color(1, 1, 1, 1), 0.5, [n[0]])
	var pulse = func():
		if box_ref["current"] != null:
			box_ref["current"].modulate = Color(1, 1, 1, 0.0)
		n[1].call(n[0] + 1)
	return V.fc(DemoBox.render, { "title": "useTween — animate a node via Godot's Tween" }, [V.Button({ "text": "Pulse (fade in)", "onPressed": pulse }), V.PanelContainer({ "ref": box_ref, "style": {"bg_color": Color(0.3, 0.6, 0.9), "corner_radius_all": 8, "custom_minimum_size": Vector2(220, 90), "content_margin_all": 12} }, [V.Label({ "text": "I fade in on every pulse", "style": {"font_color": Color.WHITE} })])])
