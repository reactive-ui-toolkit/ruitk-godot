class_name LambdaGuard
extends RefCounted
## AUTO-GENERATED from t15_lambda_paren_return.guitkx -- do not edit.

const __RUI_HOOK_SIG := ""

const __RUI_KIND := "component"

static func render(props: Dictionary, children: Array) -> RuitkVNode:
	var items = props.get("items", [])
	var pick = func(i):
		return (i * 2)
	var total = 0
	return V.VBoxContainer({}, [V.Label({ "text": str(pick.call(3)) })])
