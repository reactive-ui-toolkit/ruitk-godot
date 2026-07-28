class_name LiteralBraces
extends RefCounted
## AUTO-GENERATED from t19_text_literal_braces.guitkx -- do not edit.

const __RUI_HOOK_SIG := ""

const __RUI_KIND := "component"

static func render(props: Dictionary, children: Array) -> RuitkVNode:
	var n = props.get("n", 3)
	return V.VBoxContainer({}, [V.Label({ "text": "Count: {n} items" }), V.Label({ "text": str(n) + "at node start" })])
