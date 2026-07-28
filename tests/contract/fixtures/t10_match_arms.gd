class_name X
extends RefCounted
## AUTO-GENERATED from t10_match_arms.guitkx -- do not edit.

const __RUI_HOOK_SIG := ""

const __RUI_KIND := "component"

static func render(props: Dictionary, children: Array) -> RuitkVNode:
	var v = props.get("v", 0)
	var __cf0 = null
	match v:
		0:
			for __cf0_once in 1:
				__cf0 = V.Label({ "text": "zero" })
				continue
		1:
			for __cf0_once in 1:
				__cf0 = V.Label({ "text": "one" })
				continue
		_:
			for __cf0_once in 1:
				__cf0 = V.Label({ "text": "many" })
				continue
	return V.VBoxContainer({}, [__cf0])
