class_name DemoSpread
extends RefCounted
## AUTO-GENERATED from demos_spread_spread.guitkx -- do not edit.

const __RUI_HOOK_SIG := "useState"

const __RUI_KIND := "component"

static func render(props: Dictionary, children: Array) -> RuitkVNode:
	var n = Hooks.useState(0)
	var shared = { "custom_minimum_size": Vector2(140, 0), "text": "shared" }
	return V.fc(DemoBox.render, { "title": "Prop spread — {...obj}" }, [V.Label({ "text": "A dict is spread into <Button>; props AFTER the spread override it:", "style": {"font_color": Color(0.7, 0.7, 0.7)} }), V.HBoxContainer({ "style": {"separation": 8} }, [V.Button(V._spread_all([(shared)])), V.Button(V._spread_all([(shared), { "text": "count %d" % n[0], "onPressed": func(): n[1].call(n[0] + 1) }]))])])
