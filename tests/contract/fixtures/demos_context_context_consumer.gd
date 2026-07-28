class_name DemoContextConsumer
extends RefCounted
## AUTO-GENERATED from demos_context_context_consumer.guitkx -- do not edit.

const __RUI_HOOK_SIG := "useContext"

const __RUI_KIND := "component"

static func render(props: Dictionary, children: Array) -> RuitkVNode:
	var accent = Hooks.useContext("accent")
	return V.PanelContainer({ "style": {"bg_color": accent, "corner_radius_all": 6, "content_margin_all": 12} }, [V.Label({ "text": "I'm tinted by context", "style": {"font_color": Color.WHITE} })])
