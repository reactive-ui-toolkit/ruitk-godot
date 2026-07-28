class_name DemoDeepTreeNode
extends RefCounted
## AUTO-GENERATED from demos_deep_tree_deep_tree_node.guitkx -- do not edit.

const __RUI_HOOK_SIG := ""

const __RUI_KIND := "component"

static func render(props: Dictionary, children: Array) -> RuitkVNode:
	var level = props.get("level", 0)
	var __cf0 = null
	if level <= 0:
		for __cf0_once in 1:
			__cf0 = V.Label({ "text": "🌳 leaf", "style": {"font_color": Color(0.5, 0.9, 0.5)} })
			continue
	else:
		for __cf0_once in 1:
			__cf0 = V.MarginContainer({ "style": {"margin_left": 5, "margin_top": 5, "margin_right": 5, "margin_bottom": 5} }, [V.PanelContainer({ "style": {"bg_color": Color(0.15, 0.15, 0.18), "content_margin_all": 4} }, [V.VBoxContainer({ "style": {"separation": 2} }, [V.Label({ "text": "level %d" % level, "style": {"font_color": Color(0.6, 0.7, 0.9)} }), V.fc(DemoDeepTreeNode.render, { "level": level - 1 })])])])
			continue
	return V.fragment([__cf0])
