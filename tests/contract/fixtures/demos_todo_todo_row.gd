class_name DemoTodoRow
extends RefCounted
## AUTO-GENERATED from demos_todo_todo_row.guitkx -- do not edit.

const __RUI_HOOK_SIG := ""

const __RUI_KIND := "component"

static func render(props: Dictionary, children: Array) -> RuitkVNode:
	var item = props.get("item")
	var onRemove = props.get("onRemove")
	return V.HBoxContainer({ "style": {"separation": 8} }, [V.Label({ "text": "•  " + str(item["text"]), "style": {"size_flags_horizontal": Control.SIZE_EXPAND_FILL} }), V.Button({ "text": " ✕ ", "onPressed": func(): onRemove.call(item["id"]) })])
