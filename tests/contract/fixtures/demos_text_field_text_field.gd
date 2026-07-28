class_name DemoTextField
extends RefCounted
## AUTO-GENERATED from demos_text_field_text_field.guitkx -- do not edit.

const __RUI_HOOK_SIG := "useState"

const __RUI_KIND := "component"

static func render(props: Dictionary, children: Array) -> RuitkVNode:
	var s = Hooks.useState("")
	return V.fc(DemoBox.render, { "title": "Text Field — controlled input" }, [V.LineEdit({ "text": s[0], "placeholder_text": "Type something…", "onTextChanged": func(t): s[1].call(t), "style": {"min_width": 280} }), V.Label({ "text": "You typed: \"%s\"  (%d chars)" % [s[0], s[0].length()] })])
