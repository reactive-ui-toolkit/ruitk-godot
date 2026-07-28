class_name DemoPortal
extends RefCounted
## AUTO-GENERATED from demos_portal_portal.guitkx -- do not edit.

const __RUI_HOOK_SIG := "useState|useState|useRef|useEffect"

const __RUI_KIND := "component"

static func render(props: Dictionary, children: Array) -> RuitkVNode:
	var show = Hooks.useState(true)
	var mounted = Hooks.useState(false)
	var target = Hooks.useRef(null)
	var mount_eff = func():
		mounted[1].call(true)
		return Callable()
	Hooks.useEffect(mount_eff, [])
	var content = null
	if show[0] and mounted[0] and target["current"] != null:
		content = V.portal(target["current"], [
			V.VBoxContainer({ "style": { "separation": 4 } }, [
				V.Label({ "text": "🎯 Portaled content" }),
				V.Label({ "text": "declared on the left, mounted on the right", "style": { "font_color": Color(0.7, 0.7, 0.7) } }),
			]),
		])
	return V.fc(DemoBox.render, { "title": "Portal — render into a different subtree" }, [V.Button({ "text": "Toggle portal (%s)" % show[0], "onPressed": func(): show[1].call(not show[0]) }), V.HBoxContainer({ "style": {"separation": 16} }, [V.VBoxContainer({ "style": {"size_flags_horizontal": Control.SIZE_EXPAND_FILL} }, [V.Label({ "text": "Logical parent (left column):" }), (content if content != null else V.Label({ "text": "(portal hidden)" }))]), V.PanelContainer({ "ref": target, "style": {"bg_color": Color(0.13, 0.22, 0.13), "content_margin_all": 8, "custom_minimum_size": Vector2(280, 110)} })])])
