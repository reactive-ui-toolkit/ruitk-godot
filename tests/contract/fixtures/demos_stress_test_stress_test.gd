class_name DemoStress
extends RefCounted
## AUTO-GENERATED from demos_stress_test_stress_test.guitkx -- do not edit.

const __RUI_HOOK_SIG := "useState|useState|useState|useState|useState|useState|useRef"

const __RUI_KIND := "component"

static func render(props: Dictionary, children: Array) -> RuitkVNode:
	var box_count = Hooks.useState(300)
	var duration = Hooks.useState(10.0)
	var count_text = Hooks.useState("300")
	var dur_text = Hooks.useState("10")
	var running = Hooks.useState(false)
	var version = Hooks.useState(0)
	var area_ref = Hooks.useRef(null)

	var loop = DemoStressHooks.use_stress_loop(area_ref, box_count[0], duration[0], running[0], version[0], running[1])
	var boxes: Array = loop["boxes"]

	var status := "Stress test — Ready (press Start)"
	if loop["finished"]:
		status = "DONE — %d boxes | Avg FPS: %.1f | %.1fs | Frames: %d" % [boxes.size(), loop["fps"], loop["elapsed"], loop["frames"]]
	elif running[0]:
		status = "Running — %d boxes | FPS: %.1f | %.1f/%.0fs | Frames: %d" % [boxes.size(), loop["fps"], loop["elapsed"], duration[0], loop["frames"]]

	var start := func():
		if running[0]:
			return
		var n := int(count_text[0]) if count_text[0].is_valid_int() else 0
		var d := float(dur_text[0]) if dur_text[0].is_valid_float() else 0.0
		if n > 0 and n <= 10000 and d > 0:
			box_count[1].call(n)
			duration[1].call(d)
			version[1].call(version[0] + 1)
			running[1].call(true)
	var __cf0: Array = []
	for b in boxes:
		__cf0.append(V.ColorRect({ "position": Vector2(b["x"], b["y"]), "size": Vector2(b["size"], b["size"]), "color": b["color"] }, [], b["id"]))
		continue
	return V.fc(DemoBox.render, { "title": "Stress test — bouncing boxes (uitkx port)" }, [V.HBoxContainer({ "style": {"separation": 8} }, [V.Label({ "text": status, "style": {"size_flags_horizontal": Control.SIZE_EXPAND_FILL} }), V.Label({ "text": "Boxes:" }), V.LineEdit({ "text": count_text[0], "onTextChanged": func(t): count_text[1].call(t), "style": {"min_width": 70} }), V.Label({ "text": "Secs:" }), V.LineEdit({ "text": dur_text[0], "onTextChanged": func(t): dur_text[1].call(t), "style": {"min_width": 50} }), V.Button({ "text": "Running…" if running[0] else ("Restart" if loop["finished"] else "Start"), "onPressed": start })]), V.Control({ "ref": area_ref, "clip_contents": true, "style": {"size_flags_horizontal": Control.SIZE_EXPAND_FILL, "size_flags_vertical": Control.SIZE_EXPAND_FILL, "min_height": 320} }, [__cf0])])
