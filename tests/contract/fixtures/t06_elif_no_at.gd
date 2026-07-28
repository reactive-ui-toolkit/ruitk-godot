class_name X
extends RefCounted
## AUTO-GENERATED from t06_elif_no_at.guitkx -- do not edit.

const __RUI_HOOK_SIG := ""

const __RUI_KIND := "component"

static func render(props: Dictionary, children: Array) -> RuitkVNode:
	var c = props.get("c", true)
	var __cf0 = null
	if c:
		for __cf0_once in 1:
			__cf0 = V.Label({ "text": "a" })
			continue
	return V.VBoxContainer({}, [__cf0, V.Label({ "text": "#elif (false) {" }), V.Label({ "text": "b" }), V.Label({ "text": "}" })])
