class_name DemoHello
extends RefCounted
## AUTO-GENERATED from demos_hello_hello.guitkx -- do not edit.

const __RUI_HOOK_SIG := ""

const __RUI_KIND := "component"

static func render(props: Dictionary, children: Array) -> RuitkVNode:
	return V.fc(DemoBox.render, { "title": "Hello World" }, [V.Label({ "text": "Hello, reactive Godot! 👋", "style": {"font_size": 20} }), V.Label({ "text": "Every demo here is a .guitkx component — JSX-like markup compiled to a GDScript render fn.", "style": {"font_color": Color(0.7, 0.7, 0.7)} })])
