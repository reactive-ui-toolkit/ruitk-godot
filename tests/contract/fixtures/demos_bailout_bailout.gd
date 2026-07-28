class_name DemoBailout
extends RefCounted
## AUTO-GENERATED from demos_bailout_bailout.guitkx -- do not edit.

const __RUI_HOOK_SIG := "useState"

const __RUI_KIND := "component"

static func render(props: Dictionary, children: Array) -> RuitkVNode:
	var n = Hooks.useState(0)
	return V.fc(DemoBox.render, { "title": "Bailout — unchanged children skip re-render" }, [V.Label({ "text": "Parent state: %d" % n[0] }), V.Button({ "text": "Re-render parent", "onPressed": func(): n[1].call(n[0] + 1) }), V.Label({ "text": "The child's props never change → its render count stays flat:", "style": {"font_color": Color(0.7, 0.7, 0.7)} }), V.fc(DemoBailoutChild.render, { "label": "static" })])
