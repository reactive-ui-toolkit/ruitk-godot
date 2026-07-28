class_name DemoSignalsDisplay
extends RefCounted
## AUTO-GENERATED from demos_signals_signals_display.guitkx -- do not edit.

const __RUI_HOOK_SIG := "useSignal"

const __RUI_KIND := "component"

static func render(props: Dictionary, children: Array) -> RuitkVNode:
	var v = Hooks.useSignal(DemoSignalsStore.shared)
	return V.PanelContainer({ "style": {"bg_color": Color(0.18, 0.18, 0.22), "corner_radius_all": 6, "content_margin_all": 10} }, [V.Label({ "text": "consumer sees: %d" % v })])
