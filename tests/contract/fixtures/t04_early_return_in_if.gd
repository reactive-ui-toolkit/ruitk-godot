class_name X
extends RefCounted
## AUTO-GENERATED from t04_early_return_in_if.guitkx -- do not edit.

const __RUI_HOOK_SIG := ""

const __RUI_KIND := "component"

static func render(props: Dictionary, children: Array) -> RuitkVNode:
	var ready = props.get("ready", false)
	if not ready:
		return V.Label({ "text": "early" })
	var y = 2
	return V.Button({ "text": "late" })
