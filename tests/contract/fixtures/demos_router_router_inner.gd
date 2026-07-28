class_name DemoRouterInner
extends RefCounted
## AUTO-GENERATED from demos_router_router_inner.guitkx -- do not edit.

const __RUI_HOOK_SIG := ""

const __RUI_KIND := "component"

static func render(props: Dictionary, children: Array) -> RuitkVNode:
	var loc = RuitkRouter.useLocation()
	var ACTIVE := { "font_color": Color(1.0, 0.85, 0.3) }
	var IDLE := { "font_color": Color(0.7, 0.7, 0.8) }
	var user = func(m): return V.Label({ "text": "👤  User #%s  (from the :id route param)" % str(m.params.get("id")) })
	var users_layout = func():
		return V.VBoxContainer({ "style": { "separation": 8 } }, [
			V.HBoxContainer({ "style": { "separation": 8 } }, [
				V.Label({ "text": "Users:", "style": { "font_color": Color(0.8, 0.8, 0.9) } }),
				V.nav_link({ "to": "/users/1", "label": "#1", "style": IDLE, "active_style": ACTIVE }),
				V.nav_link({ "to": "/users/2", "label": "#2", "style": IDLE, "active_style": ACTIVE }),
				V.nav_link({ "to": "/users/3", "label": "#3", "style": IDLE, "active_style": ACTIVE }),
			]),
			V.outlet(),
		])
	return V.fc(DemoBox.render, { "title": "Router — nested routes, outlet, active links" }, [V.HBoxContainer({ "style": {"separation": 12} }, [(V.nav_link({ "to": "/", "label": "Home", "end": true, "style": IDLE, "active_style": ACTIVE })), (V.nav_link({ "to": "/users", "label": "Users", "style": IDLE, "active_style": ACTIVE })), (V.nav_link({ "to": "/about", "label": "About", "style": IDLE, "active_style": ACTIVE })), (V.nav_link({ "to": "/nope", "label": "Broken", "style": IDLE, "active_style": ACTIVE }))]), V.Label({ "text": "location: %s" % loc, "style": {"font_color": Color(0.6, 0.8, 1.0)} }), V.PanelContainer({ "style": {"bg_color": Color(0.18, 0.18, 0.22), "corner_radius_all": 6, "content_margin_all": 14} }, [(V.routes({}, [
					V.route({ "path": "/", "element": V.Label({ "text": "🏠  Home page" }) }),
					V.route({ "path": "/users", "element": users_layout.call() }, [
						V.route({ "index": true, "element": V.Label({ "text": "← pick a user" }) }),
						V.route({ "path": ":id", "render": user }),
					]),
					V.route({ "path": "/about", "element": V.Label({ "text": "ℹ️  About this library" }) }),
					V.route({ "path": "*", "element": V.Label({ "text": "🚫  404 — no route matched" }) }),
				]))])])
