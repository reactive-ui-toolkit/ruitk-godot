class_name DemoKeyedTile
extends RefCounted
## AUTO-GENERATED from demos_keyed_keyed_tile.guitkx -- do not edit.

const __RUI_HOOK_SIG := "useRef"

const __RUI_KIND := "component"

static func render(props: Dictionary, children: Array) -> RuitkVNode:
	var id = props.get("id")
	var col = Hooks.useRef(null)
	if col["current"] == null:
		col["current"] = Color(randf() * 0.5 + 0.3, randf() * 0.5 + 0.3, randf() * 0.5 + 0.3)
	return V.PanelContainer({ "style": {"bg_color": col["current"], "corner_radius_all": 6, "custom_minimum_size": Vector2(54, 54)} }, [V.CenterContainer({}, [V.Label({ "text": str(id), "style": {"font_size": 22, "font_color": Color.WHITE} })])])
