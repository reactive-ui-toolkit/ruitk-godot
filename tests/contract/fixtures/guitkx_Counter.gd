class_name GuitkxCounter
extends RefCounted
## AUTO-GENERATED from guitkx_Counter.guitkx -- do not edit.

const __RUI_HOOK_SIG := "useState"

const __RUI_KIND := "component"

static func render(props: Dictionary, children: Array) -> RuitkVNode:
	var start = props.get("start", 0)
	var s = Hooks.useState(start)
	var count = s[0]
	var set_count = s[1]
	var __cf0 = null
	if count > 5:
		for __cf0_once in 1:
			__cf0 = V.Label({ "text": "High five!" })
			continue
	return V.VBoxContainer({ "style": {"separation": 8} }, [V.Label({ "text": "Count: %d" % count }), V.Button({ "text": "+1", "onPressed": func(): set_count.call(count + 1) }), __cf0])
