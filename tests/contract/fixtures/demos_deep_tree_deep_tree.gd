class_name DemoDeepTree
extends RefCounted
## AUTO-GENERATED from demos_deep_tree_deep_tree.guitkx -- do not edit.

const __RUI_HOOK_SIG := "useState"

const __RUI_KIND := "component"

static func render(props: Dictionary, children: Array) -> RuitkVNode:
	var depth = Hooks.useState(8)
	return V.fc(DemoBox.render, { "title": "Deep component tree" }, [V.HBoxContainer({ "style": {"separation": 8} }, [V.Button({ "text": "− depth", "onPressed": func(): depth[1].call(maxi(1, depth[0] - 1)) }), V.Label({ "text": "depth %d" % depth[0] }), V.Button({ "text": "+ depth", "onPressed": func(): depth[1].call(depth[0] + 1) })]), V.fc(DemoDeepTreeNode.render, { "level": depth[0] })])
