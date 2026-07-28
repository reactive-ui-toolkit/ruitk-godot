class_name DemoStyling
extends RefCounted
## AUTO-GENERATED from demos_styling_styling.guitkx -- do not edit.

const __RUI_HOOK_SIG := ""

const __RUI_KIND := "component"

static func render(props: Dictionary, children: Array) -> RuitkVNode:
	return V.fc(DemoBox.render, { "title": "Styling — StyleBoxFlat + theme channels" }, [V.PanelContainer({ "style": DemoStylingStyle.PANEL }, [V.VBoxContainer({ "style": {"separation": 4} }, [V.Label({ "text": "Styled panel", "style": {"font_size": 22, "font_color": Color(0.6, 0.8, 1.0)} }), V.Label({ "text": "bg + corner radius + border, all from one StyleBoxFlat (styles live in styling.style.gd)", "style": {"font_color": Color(0.7, 0.7, 0.7)} })])]), V.HBoxContainer({ "style": {"separation": 10} }, [V.PanelContainer({ "style": DemoStylingStyle.SQUARE_RED }), V.PanelContainer({ "style": DemoStylingStyle.SQUARE_GREEN }), V.PanelContainer({ "style": DemoStylingStyle.SQUARE_BLUE })]), V.Label({ "text": "Theme channels reach any item:", "style": {"font_color": Color(0.7, 0.7, 0.7)} }), V.Label({ "text": "outlined text", "style": DemoStylingStyle.OUTLINED })])
