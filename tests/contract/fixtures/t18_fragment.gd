class_name NamedFragment
extends RefCounted
## AUTO-GENERATED from t18_fragment.guitkx -- do not edit.

const __RUI_HOOK_SIG := ""

const __RUI_KIND := "component"

static func render(props: Dictionary, children: Array) -> RuitkVNode:
	var xs = props.get("xs", [])
	var __cf0: Array = []
	for i in 3:
		__cf0.append(V.fragment([V.Label({ "text": str(i) })], str(i)))
		continue
	return V.VBoxContainer({}, [V.fragment([V.Label({ "text": "a" }), V.Label({ "text": "b" })]), __cf0])
