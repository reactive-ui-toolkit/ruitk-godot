class_name DemoControls
extends RefCounted
## AUTO-GENERATED from demos_controls_controls.guitkx -- do not edit.

const __RUI_HOOK_SIG := "useState"

const __RUI_KIND := "component"

static func render(props: Dictionary, children: Array) -> RuitkVNode:
	var v = Hooks.useState(40.0)
	return V.fc(DemoBox.render, { "title": "Controls — a slice of the 60-control set" }, [V.CheckButton({ "text": "CheckButton" }), V.CheckBox({ "text": "CheckBox" }), V.HBoxContainer({ "style": {"separation": 8} }, [V.HSlider({ "min_value": 0, "max_value": 100, "value": v[0], "onValueChanged": func(x): v[1].call(x), "style": {"min_width": 220} }), V.Label({ "text": "%d" % int(v[0]) })]), V.ProgressBar({ "min_value": 0, "max_value": 100, "value": v[0], "style": {"min_width": 260} }), V.Label({ "text": "ItemList:" }), V.ItemList({ "items": ["Apple", "Banana", "Cherry", "Date"], "style": {"min_height": 90} }), V.Label({ "text": "Tree (declarative, expansion preserved):" }), V.Tree({ "hide_root": true, "items": [
				{ "id": "fruit", "text": "🍎 Fruit", "children": [{ "id": "apple", "text": "Apple" }, { "id": "pear", "text": "Pear" }] },
				{ "id": "veg", "text": "🥕 Veg", "children": [{ "id": "carrot", "text": "Carrot" }] },
			], "style": {"min_height": 150} })])
