class_name DemoReducer
extends RefCounted
## AUTO-GENERATED from demos_reducer_reducer.guitkx -- do not edit.

const __RUI_HOOK_SIG := "useReducer"

const __RUI_KIND := "component"

static func render(props: Dictionary, children: Array) -> RuitkVNode:
	var reducer = func(state, action):
		match action:
			"inc": return state + 1
			"dec": return state - 1
			"reset": return 0
		return state
	var r = Hooks.useReducer(reducer, 0)
	return V.fc(DemoBox.render, { "title": "useReducer — actions instead of raw setters" }, [V.Label({ "text": "State: %d" % r[0], "style": {"font_size": 28} }), V.HBoxContainer({ "style": {"separation": 8} }, [V.Button({ "text": "dec", "onPressed": func(): r[1].call("dec") }), V.Button({ "text": "inc", "onPressed": func(): r[1].call("inc") }), V.Button({ "text": "reset", "onPressed": func(): r[1].call("reset") })])])
