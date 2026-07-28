class_name DemoBailoutChild
extends RefCounted
## AUTO-GENERATED from demos_bailout_bailout_child.guitkx -- do not edit.

const __RUI_HOOK_SIG := "useRef"

const __RUI_KIND := "component"

static func render(props: Dictionary, children: Array) -> RuitkVNode:
	var renders = Hooks.useRef(0)
	renders["current"] += 1
	return V.PanelContainer({ "style": {"bg_color": Color(0.2, 0.2, 0.26), "corner_radius_all": 6, "content_margin_all": 10} }, [V.Label({ "text": "child render count: %d  (bailed out)" % renders["current"] })])
