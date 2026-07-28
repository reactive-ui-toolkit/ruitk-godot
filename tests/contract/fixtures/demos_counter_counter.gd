class_name DemoCounter
extends RefCounted
## AUTO-GENERATED from demos_counter_counter.guitkx -- do not edit.

const __RUI_HOOK_SIG := "useState"

const __RUI_KIND := "component"

static func render(props: Dictionary, children: Array) -> RuitkVNode:
	var s = Hooks.useState(0)
	return V.fc(DemoBox.render, { "title": "Counter — useState" }, [V.Label({ "text": "Count: %d" % s[0], "style": {"font_size": 28} }), V.HBoxContainer({ "style": {"separation": 8} }, [V.Button({ "text": "  −1  ", "onPressed": func(): s[1].call(s[0] - 1) }), V.Button({ "text": "  +1  ", "onPressed": func(): s[1].call(func(c): return c + 1) }), V.Button({ "text": " Reset ", "onPressed": func(): s[1].call(0) })])])
