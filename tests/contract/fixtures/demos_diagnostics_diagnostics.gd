class_name DemoDiagnostics
extends RefCounted
## AUTO-GENERATED from demos_diagnostics_diagnostics.guitkx -- do not edit.

const __RUI_HOOK_SIG := "useState|useState|useEffect"

const __RUI_KIND := "component"

static func render(props: Dictionary, children: Array) -> RuitkVNode:
	RuitkDiagnostics.enabled = true
	var tick = Hooks.useState(0)
	var shown = Hooks.useState(RuitkDiagnostics.report())
	var capture = func():
		shown[1].call(RuitkDiagnostics.report())
		return Callable()
	Hooks.useEffect(capture, [tick[0]])
	var do_reset = func():
		RuitkDiagnostics.reset()
		shown[1].call(RuitkDiagnostics.report())
	var rep: Dictionary = shown[0]
	return V.fc(DemoBox.render, { "title": "Diagnostics — render/commit metrics" }, [V.Label({ "text": "renders: %d    commits: %d" % [rep["renders"], rep["commits"]] }), V.Label({ "text": "placements: %d    updates: %d    deletions: %d" % [rep["placements"], rep["updates"], rep["deletions"]] }), V.Label({ "text": "captured after the last click's commit (displaying is itself a render)", "style": {"font_color": Color(0.55, 0.55, 0.55)} }), V.HBoxContainer({ "style": {"separation": 8} }, [V.Button({ "text": "Trigger a render", "onPressed": func(): tick[1].call(tick[0] + 1) }), V.Button({ "text": "Reset counters", "onPressed": do_reset })])])
