class_name X
extends RefCounted
## AUTO-GENERATED from t03_return_null_guard.guitkx -- do not edit.

const __RUI_HOOK_SIG := ""

const __RUI_KIND := "component"

static func render(props: Dictionary, children: Array) -> RuitkVNode:
	var ready = props.get("ready", false)
	if not ready:
		return null
	return V.Label({ "text": "on" })
