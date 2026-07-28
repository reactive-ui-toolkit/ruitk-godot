class_name DemoContextHandle
extends RefCounted
## AUTO-GENERATED from demos_context_handle_context_handle.guitkx -- do not edit.

const __RUI_HOOK_SIG := "useState|provideContext"

const __RUI_KIND := "component"

static func render(props: Dictionary, children: Array) -> RuitkVNode:
	const AccentContext = preload("res://examples/demos/context_handle/accent_context.gd")
	var accent = Hooks.useState(Color(0.4, 0.7, 1.0))
	Hooks.provideContext(AccentContext.HANDLE, accent[0])
	return V.fc(DemoBox.render, { "title": "Context handle — createContext / RuitkContext" }, [V.Label({ "text": "A createContext() handle (object identity, no string keys) provided to the subtree:", "style": {"font_color": Color(0.7, 0.7, 0.7)} }), V.HBoxContainer({ "style": {"separation": 8} }, [V.Button({ "text": "Blue", "onPressed": func(): accent[1].call(Color(0.4, 0.7, 1.0)) }), V.Button({ "text": "Green", "onPressed": func(): accent[1].call(Color(0.35, 0.85, 0.45)) }), V.Button({ "text": "Red", "onPressed": func(): accent[1].call(Color(0.9, 0.4, 0.35)) })]), V.fc(DemoContextHandleSwatch.render, {})])
