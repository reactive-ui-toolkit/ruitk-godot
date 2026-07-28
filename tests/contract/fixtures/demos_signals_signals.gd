class_name DemoSignals
extends RefCounted
## AUTO-GENERATED from demos_signals_signals.guitkx -- do not edit.

const __RUI_HOOK_SIG := ""

const __RUI_KIND := "component"

static func render(props: Dictionary, children: Array) -> RuitkVNode:
	return V.fc(DemoBox.render, { "title": "Signals — shared state, no prop drilling" }, [V.Label({ "text": "Two independent components read the SAME RuitkSignal:", "style": {"font_color": Color(0.7, 0.7, 0.7)} }), V.fc(DemoSignalsDisplay.render, {}), V.fc(DemoSignalsDisplay.render, {}), V.Button({ "text": "Increment shared signal", "onPressed": func(): DemoSignalsStore.shared.update(func(v): return v + 1) })])
