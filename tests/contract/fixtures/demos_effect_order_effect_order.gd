class_name DemoEffectOrder
extends RefCounted
## AUTO-GENERATED from demos_effect_order_effect_order.guitkx -- do not edit.

const __RUI_HOOK_SIG := "useState|useState"

const __RUI_KIND := "component"

static func render(props: Dictionary, children: Array) -> RuitkVNode:
	var n = Hooks.useState(3)
	var log = Hooks.useState([])
	var append = func(msg): log[1].call(func(arr): return arr + [msg])
	var __cf0: Array = []
	for i in n[0]:
		__cf0.append(V.fc(DemoEffectOrderRow.render, { "idx": i, "append": append }, [], str(i)))
		continue
	return V.fc(DemoBox.render, { "title": "Effect cleanup order — mount / unmount" }, [V.HBoxContainer({ "style": {"separation": 8} }, [V.Button({ "text": "− row", "onPressed": func(): n[1].call(maxi(0, n[0] - 1)) }), V.Label({ "text": "%d rows" % n[0] }), V.Button({ "text": "+ row", "onPressed": func(): n[1].call(n[0] + 1) })]), V.VBoxContainer({ "style": {"separation": 2} }, [__cf0]), V.Label({ "text": "Effect log (add/remove rows — cleanup runs on unmount):", "style": {"font_color": Color(0.7, 0.7, 0.7)} }), V.Label({ "text": "\n".join(log[0]) })])
