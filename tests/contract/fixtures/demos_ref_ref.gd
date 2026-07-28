class_name DemoRef
extends RefCounted
## AUTO-GENERATED from demos_ref_ref.guitkx -- do not edit.

const __RUI_HOOK_SIG := "useRef"

const __RUI_KIND := "component"

static func render(props: Dictionary, children: Array) -> RuitkVNode:
	var input_ref = Hooks.useRef(null)
	var focus = func():
		if input_ref["current"] != null:
			input_ref["current"].grab_focus()
	return V.fc(DemoBox.render, { "title": "useRef — imperative node access" }, [V.LineEdit({ "placeholder_text": "focus me with the button →", "ref": input_ref, "style": {"min_width": 280} }), V.Button({ "text": "Focus the field", "onPressed": focus })])
