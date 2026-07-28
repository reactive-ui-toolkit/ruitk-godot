class_name DemoSlicing
extends RefCounted
## AUTO-GENERATED from demos_slicing_slicing.guitkx -- do not edit.

const __RUI_HOOK_SIG := "useState|useState"

const __RUI_KIND := "component"

static func render(props: Dictionary, children: Array) -> RuitkVNode:
	var sliced = Hooks.useState(RuitkConfig.time_slicing)
	var rev = Hooks.useState(0)
	var toggle = func():
		RuitkConfig.time_slicing = not sliced[0]
		sliced[1].call(not sliced[0])
	var __cf0: Array = []
	for i in 25:
		__cf0.append(V.Label({ "text": "row %d  (rev %d)" % [i, rev[0]] }, [], str(i)))
		continue
	return V.fc(DemoBox.render, { "title": "Time-slicing — chunk big renders across frames" }, [V.HBoxContainer({ "style": {"separation": 8} }, [V.Button({ "text": "Time-slicing: %s" % ("ON" if sliced[0] else "OFF"), "onPressed": toggle }), V.Button({ "text": "Re-render 25 rows", "onPressed": func(): rev[1].call(rev[0] + 1) })]), V.Label({ "text": "With slicing ON, big updates spread over frames (commit stays atomic).", "style": {"font_color": Color(0.7, 0.7, 0.7)} }), V.ScrollContainer({ "style": {"min_height": 200} }, [V.VBoxContainer({ "style": {"separation": 2} }, [__cf0])])])
