class_name DemoKeyed
extends RefCounted
## AUTO-GENERATED from demos_keyed_keyed.guitkx -- do not edit.

const __RUI_HOOK_SIG := "useState"

const __RUI_KIND := "component"

static func render(props: Dictionary, children: Array) -> RuitkVNode:
	var items = Hooks.useState(["A", "B", "C", "D", "E"])
	var shuffle = func():
		var arr: Array = items[0].duplicate()
		arr.shuffle()
		items[1].call(arr)
	var __cf0: Array = []
	for id in items[0]:
		__cf0.append(V.fc(DemoKeyedTile.render, { "id": id }, [], str(id)))
		continue
	return V.fc(DemoBox.render, { "title": "Keyed diff — identity survives reordering" }, [V.Button({ "text": "Shuffle", "onPressed": shuffle }), V.Label({ "text": "Each tile keeps its node (and its random color) across shuffles — that's keys at work.", "style": {"font_color": Color(0.7, 0.7, 0.7)} }), V.HBoxContainer({ "style": {"separation": 6} }, [__cf0])])
