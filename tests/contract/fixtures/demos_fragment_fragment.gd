class_name DemoFragment
extends RefCounted
## AUTO-GENERATED from demos_fragment_fragment.guitkx -- do not edit.

const __RUI_HOOK_SIG := ""

const __RUI_KIND := "component"

static func render(props: Dictionary, children: Array) -> RuitkVNode:
	return V.fc(DemoBox.render, { "title": "Fragment — group nodes without a wrapper" }, [V.Label({ "text": "A fragment inserts its children flat — no extra container node:" }), V.PanelContainer({ "style": {"bg_color": Color(0.18, 0.18, 0.22), "content_margin_all": 10} }, [V.VBoxContainer({ "style": {"separation": 4} }, [V.Label({ "text": "• before fragment" }), V.fragment([V.Label({ "text": "• — fragment child A —", "style": {"font_color": Color(0.6, 0.85, 1.0)} }), V.Label({ "text": "• — fragment child B —", "style": {"font_color": Color(0.6, 0.85, 1.0)} })]), V.Label({ "text": "• after fragment" })])])])
