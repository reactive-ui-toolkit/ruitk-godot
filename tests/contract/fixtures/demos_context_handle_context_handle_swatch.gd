class_name DemoContextHandleSwatch
extends RefCounted
## AUTO-GENERATED from demos_context_handle_context_handle_swatch.guitkx -- do not edit.

const __RUI_HOOK_SIG := "useContext"

const __RUI_KIND := "component"

static func render(props: Dictionary, children: Array) -> RuitkVNode:
	const AccentContext = preload("res://examples/demos/context_handle/accent_context.gd")
	var c = Hooks.useContext(AccentContext.HANDLE)
	return V.Label({ "text": "   ● this label reads the accent straight from the context handle", "style": {"font_color": c} })
