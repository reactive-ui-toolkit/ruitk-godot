extends SceneTree
## Phase 7.6-7.9: the component-tree router spine — V.route/V.routes(children)/V.outlet/V.navigate/
## V.nav_link + the new hooks. Mounts REAL node trees at depth >=3, navigates, and asserts the
## rendered leaves, merged params, outlet resolution, declarative redirect, blockers, query, and
## basename. Run: godot --headless --path <project> --script res://tests/router_spine_test.gd

var _fails := 0
var _passes := 0

func _initialize() -> void:
	_run()

func _ok(cond: bool, msg: String) -> void:
	if cond:
		_passes += 1
	else:
		_fails += 1
		printerr("  FAIL: " + msg)
		push_error("FAIL: " + msg)

func _mount(render_fn: Callable, props := {}) -> Array:
	var c := Control.new()
	root.add_child(c)
	var app := RuitkRoot.create(c, V.fc(render_fn, props))
	return [c, app]

## Depth-first concatenation of every Label's text under `node` (space-joined).
func _texts(node: Node) -> String:
	var out: Array = []
	_collect_texts(node, out)
	return " ".join(out)

func _collect_texts(node: Node, out: Array) -> void:
	if node is Label:
		out.append(node.text)
	for ch in node.get_children():
		_collect_texts(ch, out)

func _run() -> void:
	await _test_children_switch_and_params()
	await _test_nested_outlet_depth3()
	await _test_index_route()
	await _test_declarative_redirect()
	await _test_blocker_vetoes()
	await _test_query_and_basename()
	await _test_outlet_fallback()
	await _test_can_go_reactive()
	await _test_direct_route_toggle()
	await _test_pure_helpers()
	print("\n[router_spine_test] %d passed, %d failed" % [_passes, _fails])

func _test_outlet_fallback() -> void:
	# [audit #4] When a layout keeps matching but its nested route STOPS matching, the outlet must
	# fall back to its own children (the stale OUTLET_ELEMENT must be cleared, not linger).
	var history := RuitkHistory.new("/u/edit")
	var layout := V.VBoxContainer({}, [
		V.Label({ "text": "LAYOUT" }),
		V.outlet({}, [V.Label({ "text": "FALLBACK" })]),
	])
	var app := func(_p, _c):
		return V.routes({}, [
			V.route({ "path": "/u", "element": layout }, [
				V.route({ "path": "edit", "element": V.Label({ "text": "EDIT" }) }),
			]),
		])
	var root_comp := func(_p, _c):
		return V.router({ "history": history }, [V.fc(app)])
	var m := _mount(root_comp)
	await process_frame
	await process_frame
	_ok(_texts(m[0]).contains("EDIT"), "nested route renders at /u/edit, got '%s'" % _texts(m[0]))
	history.push("/u")
	await process_frame
	await process_frame
	var t := _texts(m[0])
	_ok(t.contains("LAYOUT") and t.contains("FALLBACK") and not t.contains("EDIT"), "outlet falls back after nested unmatch, got '%s'" % t)
	m[1].unmount()
	m[0].queue_free()

func _test_can_go_reactive() -> void:
	# [audit #13] A useCanGo consumer must re-render when the history position changes.
	var history := RuitkHistory.new("/")
	var nav := { "go": null }
	var seen := { "back": null }
	var page := func(_p, _c):
		nav["go"] = RuitkRouter.useNavigate()
		seen["back"] = RuitkRouter.useCanGo(-1)
		return V.Label({ "text": "x" })
	var root_comp := func(_p, _c):
		return V.router({ "history": history }, [V.fc(page)])
	var m := _mount(root_comp)
	await process_frame
	_ok(seen["back"] == false, "can_go(-1) false at history root, got %s" % str(seen["back"]))
	nav["go"].call("/next")
	await process_frame
	await process_frame
	_ok(seen["back"] == true, "can_go(-1) becomes true after navigation (reactive), got %s" % str(seen["back"]))
	m[1].unmount()
	m[0].queue_free()

func _test_direct_route_toggle() -> void:
	# A bare V.route (NOT inside V.routes) renders in place and toggles match as the location changes.
	# All its hooks must run every render regardless of match (stable hook count) — no hook-order error.
	var history := RuitkHistory.new("/")
	var app := func(_p, _c):
		return V.VBoxContainer({}, [
			V.route({ "path": "/", "element": V.Label({ "text": "at-root" }) }),
			V.route({ "path": "/other", "element": V.Label({ "text": "at-other" }) }),
		])
	var root_comp := func(_p, _c):
		return V.router({ "history": history }, [V.fc(app)])
	var m := _mount(root_comp)
	await process_frame
	_ok(_texts(m[0]) == "at-root", "direct route matches at '/', got '%s'" % _texts(m[0]))
	history.push("/other")
	await process_frame
	await process_frame
	_ok(_texts(m[0]) == "at-other", "direct route toggled to '/other', got '%s'" % _texts(m[0]))
	history.push("/")
	await process_frame
	await process_frame
	_ok(_texts(m[0]) == "at-root", "direct route toggled back to '/', got '%s'" % _texts(m[0]))
	m[1].unmount()
	m[0].queue_free()
	quit(1 if _fails > 0 else 0)

# --------------------------------------------------------------------------

func _test_children_switch_and_params() -> void:
	var history := RuitkHistory.new("/")
	var seen := { "id": null }
	var user := func(m):
		seen["id"] = m.params.get("id")
		return V.Label({ "text": "user " + str(m.params.get("id")) })
	var app := func(_p, _c):
		return V.routes({}, [
			V.route({ "path": "/", "element": V.Label({ "text": "home" }) }),
			V.route({ "path": "/users/:id", "render": user }),
			V.route({ "path": "*", "element": V.Label({ "text": "notfound" }) }),
		])
	var root_comp := func(_p, _c):
		return V.router({ "history": history }, [V.fc(app)])

	var m := _mount(root_comp)
	_ok(_texts(m[0]).contains("home"), "ranked switch renders home at '/', got '%s'" % _texts(m[0]))

	history.push("/users/42")
	await process_frame
	await process_frame
	_ok(_texts(m[0]).contains("user 42"), "switch renders /users/:id, got '%s'" % _texts(m[0]))
	_ok(seen["id"] == "42", "render-func match param id==42, got %s" % str(seen["id"]))

	history.push("/whatever")
	await process_frame
	await process_frame
	_ok(_texts(m[0]).contains("notfound"), "splat '*' catches unmatched, got '%s'" % _texts(m[0]))
	m[1].unmount()
	m[0].queue_free()

func _test_nested_outlet_depth3() -> void:
	# Router -> layout <Route path="/users"> (renders an Outlet) -> nested index + :id routes.
	var history := RuitkHistory.new("/")
	var user := func(mm):
		return V.Label({ "text": "user " + str(mm.params.get("id")) })
	var layout := V.VBoxContainer({}, [
		V.Label({ "text": "users-layout" }),
		V.outlet(),
	])
	var app := func(_p, _c):
		return V.routes({}, [
			V.route({ "path": "/", "element": V.Label({ "text": "home" }) }),
			V.route({ "path": "/users", "element": layout }, [
				V.route({ "index": true, "element": V.Label({ "text": "users-index" }) }),
				V.route({ "path": ":id", "render": user }),
			]),
		])
	var root_comp := func(_p, _c):
		return V.router({ "history": history }, [V.fc(app)])

	var m := _mount(root_comp)
	history.push("/users")
	await process_frame
	await process_frame
	var t := _texts(m[0])
	_ok(t.contains("users-layout"), "layout route renders its element, got '%s'" % t)
	_ok(t.contains("users-index"), "outlet renders the index route at /users, got '%s'" % t)

	history.push("/users/7")
	await process_frame
	await process_frame
	t = _texts(m[0])
	_ok(t.contains("users-layout"), "layout persists on /users/7 (co-existence), got '%s'" % t)
	_ok(t.contains("user 7"), "outlet swaps to :id route with merged param, got '%s'" % t)
	_ok(not t.contains("users-index"), "index no longer shown on /users/7, got '%s'" % t)

	history.push("/")
	await process_frame
	await process_frame
	t = _texts(m[0])
	_ok(t.contains("home") and not t.contains("users-layout"), "layout torn down at '/', got '%s'" % t)
	m[1].unmount()
	m[0].queue_free()

func _test_index_route() -> void:
	var history := RuitkHistory.new("/dash")
	var app := func(_p, _c):
		return V.routes({}, [
			V.route({ "path": "/dash", "element": V.VBoxContainer({}, [V.Label({ "text": "dash" }), V.outlet()]) }, [
				V.route({ "index": true, "element": V.Label({ "text": "overview" }) }),
				V.route({ "path": "settings", "element": V.Label({ "text": "settings" }) }),
			]),
		])
	var root_comp := func(_p, _c):
		return V.router({ "history": history }, [V.fc(app)])
	var m := _mount(root_comp)
	await process_frame
	_ok(_texts(m[0]).contains("overview"), "index route renders for parent path, got '%s'" % _texts(m[0]))
	history.push("/dash/settings")
	await process_frame
	await process_frame
	_ok(_texts(m[0]).contains("settings") and not _texts(m[0]).contains("overview"), "child route replaces index, got '%s'" % _texts(m[0]))
	m[1].unmount()
	m[0].queue_free()

func _test_declarative_redirect() -> void:
	var history := RuitkHistory.new("/old")
	var app := func(_p, _c):
		return V.routes({}, [
			V.route({ "path": "/old", "element": V.navigate({ "to": "/new" }) }),
			V.route({ "path": "/new", "element": V.Label({ "text": "arrived" }) }),
		])
	var root_comp := func(_p, _c):
		return V.router({ "history": history }, [V.fc(app)])
	var m := _mount(root_comp)
	await process_frame
	await process_frame
	await process_frame
	_ok(history.location() == "/new", "V.navigate redirected /old -> /new, got '%s'" % history.location())
	_ok(_texts(m[0]).contains("arrived"), "redirect target rendered, got '%s'" % _texts(m[0]))
	m[1].unmount()
	m[0].queue_free()

func _test_blocker_vetoes() -> void:
	var history := RuitkHistory.new("/")
	var nav := { "go": null }
	var gate := { "block": true }
	var page := func(_p, _c):
		nav["go"] = RuitkRouter.useNavigate()
		RuitkRouter.useBlocker(func(_from, _to): return gate["block"], true)
		return V.Label({ "text": "loc " + RuitkRouter.useLocation() })
	var root_comp := func(_p, _c):
		return V.router({ "history": history }, [V.fc(page)])
	var m := _mount(root_comp)
	await process_frame   # effect registers the blocker
	nav["go"].call("/blocked")
	await process_frame
	await process_frame
	_ok(history.location() == "/", "blocker vetoed navigation (stayed at '/'), got '%s'" % history.location())
	gate["block"] = false
	nav["go"].call("/allowed")
	await process_frame
	await process_frame
	_ok(history.location() == "/allowed", "navigation allowed once blocker stands down, got '%s'" % history.location())
	m[1].unmount()
	m[0].queue_free()

func _test_query_and_basename() -> void:
	var history := RuitkHistory.new("/app")
	var seen := { "q": null, "loc": null }
	var nav := { "go": null }
	var page := func(_p, _c):
		nav["go"] = RuitkRouter.useNavigate()
		seen["q"] = RuitkRouter.useQuery()
		seen["loc"] = RuitkRouter.useLocation()
		return V.Label({ "text": "x" })
	var root_comp := func(_p, _c):
		return V.router({ "history": history, "basename": "/app" }, [V.fc(page)])
	var m := _mount(root_comp)
	await process_frame
	_ok(seen["loc"] == "/", "basename stripped: '/app' -> '/', got '%s'" % str(seen["loc"]))
	nav["go"].call("/search?term=godot&page=2")
	await process_frame
	await process_frame
	_ok(seen["loc"] == "/search", "basename-stripped location after nav, got '%s'" % str(seen["loc"]))
	_ok(history.location() == "/app/search", "basename re-attached in history, got '%s'" % history.location())
	_ok(seen["q"].get("term") == "godot" and seen["q"].get("page") == "2", "useQuery decodes, got %s" % str(seen["q"]))
	m[1].unmount()
	m[0].queue_free()

func _test_pure_helpers() -> void:
	# NavLink activation rules.
	_ok(RuitkRouter._nav_link_is_active("/", "/", false, false), "'/' active only on '/'")
	_ok(not RuitkRouter._nav_link_is_active("/users", "/", false, false), "'/' not active on /users")
	_ok(RuitkRouter._nav_link_is_active("/users/5", "/users", false, false), "prefix active on segment boundary")
	_ok(not RuitkRouter._nav_link_is_active("/usersxx", "/users", false, false), "prefix NOT active mid-segment")
	_ok(not RuitkRouter._nav_link_is_active("/users/5", "/users", true, false), "end=true requires exact")
	_ok(RuitkRouter._nav_link_is_active("/Users", "/users", false, false), "case-insensitive by default")
	_ok(not RuitkRouter._nav_link_is_active("/Users", "/users", false, true), "case-sensitive rejects /Users")
	# Target resolution against a navigation base.
	_ok(RuitkRouter._resolve_target("", "/users/:id") == "/users/:id", "empty 'to' -> base")
	_ok(RuitkRouter._resolve_target("/abs", "/users") == "/abs", "absolute 'to' normalized")
	_ok(RuitkRouter._resolve_target("edit", "/users/:id") == "/users/:id/edit", "relative 'to' combined onto base")
