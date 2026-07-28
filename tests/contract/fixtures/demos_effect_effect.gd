class_name DemoEffect
extends RefCounted
## AUTO-GENERATED from demos_effect_effect.guitkx -- do not edit.

const __RUI_HOOK_SIG := "useState|useRef|useEffect"

const __RUI_KIND := "component"

static func render(props: Dictionary, children: Array) -> RuitkVNode:
	var on = Hooks.useState(true)
	var log = Hooks.useRef([])
	var eff = func():
		var was: bool = on[0]
		log["current"].append("▶ setup (dep=%s)" % was)
		return func(): log["current"].append("■ cleanup (dep=%s)" % was)
	Hooks.useEffect(eff, [on[0]])
	return V.fc(DemoBox.render, { "title": "useEffect — lifecycle + cleanup" }, [V.Button({ "text": "Toggle dependency (now %s)" % on[0], "onPressed": func(): on[1].call(not on[0]) }), V.Label({ "text": "Effect log (cleanup runs before the next setup):", "style": {"font_color": Color(0.7, 0.7, 0.7)} }), V.Label({ "text": "\n".join(log["current"]) })])
