class_name RUIRouter
extends RefCounted
## React-Router-style routing built on the reactive core (context + hooks). All pieces are static
## render functions used via the V.router/route/routes/outlet/navigate/nav_link/link helpers. This
## is a faithful port of ReactiveUIToolKit's RouterComponents.cs + RouterHooks.cs, adapted to
## GDScript and to this port's two-context split (M4): a STABLE nav context that survives
## navigations and a VOLATILE location context — so navigate-only widgets don't re-render when the
## location changes.
##
## Component-tree routing:
##   V.router({ "history": h, "basename": "/app" }, [ app ])      # provides router context
##   V.routes({}, [                                               # ranked first-match switch
##       V.route({ "path": "/",          "element": home }),
##       V.route({ "path": "/users/:id", "element": user }),
##       V.route({ "path": "*",          "element": not_found }),
##   ])
##   V.outlet()                                                   # renders the matched nested route
##   V.navigate({ "to": "/login" })                              # declarative redirect (effect)
##   V.nav_link({ "to": "/users", "label": "Users", "active_style": {...} })
##
## Legacy table routing (kept working): V.routes({ "routes": [ { "path", "component" }, ... ] }).
##
## Hooks (call from any descendant component):
##   RUIRouter.useNavigate(replace := false) -> func(path, state := null) -> bool
##   RUIRouter.useLocation()    -> current path String
##   RUIRouter.useQuery()       -> { ... } decoded query
##   RUIRouter.useParams()      -> { "id": "1", ... } for the matched route
##   RUIRouter.useMatches()     -> [RUIRouteMatch ...] root -> current
##   RUIRouter.useGo() / useCanGo(delta) / useResolvedPath(to) / useSearchParams()
##   RUIRouter.useBlocker(blocker, enabled) / usePrompt(when, message)

# --- context keys ------------------------------------------------------------
# Split nav/loc (M4): NAV_CTX is memoized (stable identity) so navigate-only consumers don't
# re-render on navigation; LOC_CTX churns. NAV_BASE_CTX is a stable *string* base for relative
# navigation (value-equal across navigations, so leaf navigators stay stable too).
const NAV_CTX := "__rui_router_nav"
const LOC_CTX := "__rui_router_loc"
const NAV_BASE_CTX := "__rui_router_nav_base"
const ROUTER_OWNER := "__rui_router_owner"
const ROUTE_MATCH := "__rui_route_match"
const ROUTE_PATTERN := "__rui_route_pattern"
const ROUTE_ENTRY := "__rui_route_context_entry"
const MATCH_CHAIN := "__rui_router_match_chain"
const OUTLET_ELEMENT := "__rui_router_outlet_element"
const OUTLET_CONTEXT := "__rui_router_outlet_context"

# --- per-route context entry (owner-stamped; used for nav-base + parent-chain resolution) ----
class RouteContextEntry:
	extends RefCounted
	var route_match: RUIRouteMatch
	var navigation_base: String
	var parent: RouteContextEntry
	var owner   # the RUIComponentState that published this entry (identity stamp)
	func _init(m: RUIRouteMatch, nb: String, p: RouteContextEntry, o) -> void:
		route_match = m
		navigation_base = "/" if (nb == null or nb == "") else nb
		parent = p
		owner = o

static var _root_entry_cache: RouteContextEntry = null

static func _root_entry() -> RouteContextEntry:
	if _root_entry_cache == null:
		_root_entry_cache = RouteContextEntry.new(RUIRouteMatch.create_root("/"), "/", null, null)
	return _root_entry_cache

# =============================================================================
# Provider — V.router
# =============================================================================
static func provider(props: Dictionary, children: Array):
	# Nested-Router guard (decision #2: push_error + degrade, don't hard-crash). A re-render of
	# the SAME router is legal because the owner stamp == our own component state.
	var nest_warned: Dictionary = Hooks.useRef(false)
	var existing_owner = Hooks.useContext(ROUTER_OWNER)
	if existing_owner != null and existing_owner != Hooks._cur and not nest_warned["current"]:
		nest_warned["current"] = true
		var nmsg := "[Router] <Router> cannot be nested inside another <Router>. Use a single root <Router> and compose <Route>s underneath it; for a sub-section use <Routes>. (Degrading: the inner router will shadow the outer for its subtree.)"
		RUIDiagnostics.emit(nmsg)
		push_error(nmsg)

	var provided_history = props.get("history", null)
	var initial_path := str(props.get("initial", "/"))
	var basename_in = props.get("basename", "/")
	var basename := "/" if (basename_in == null or str(basename_in) == "") else str(basename_in)

	var resolved_history = Hooks.useMemo(func():
		return provided_history if provided_history != null else RUIHistory.new(initial_path)
	, [provided_history, initial_path])

	var loc_state := Hooks.useState(resolved_history.location_obj() if resolved_history != null else RUIRouterLocation.parse("/"))
	var location = loc_state[0]
	var set_location: Callable = loc_state[1]

	Hooks.useEffect(func():
		if resolved_history == null:
			return null
		var unsub = resolved_history.listen(func(loc): set_location.call(loc))
		return func():
			if unsub is Callable:
				unsub.call()
	, [resolved_history])

	# STABLE nav context — memoized on [history, basename] so its identity survives navigations.
	var nav_ctx := Hooks.useMemo(func(): return _build_nav_ctx(resolved_history, basename), [resolved_history, basename])

	Hooks.provideContext(NAV_CTX, nav_ctx)
	Hooks.provideContext(ROUTER_OWNER, Hooks._cur)

	# Consumers see the location with the basename stripped (RR semantics: useLocation() is
	# app-relative); navigation re-attaches it. Memoized so LOC_CTX identity is stable between navs.
	var visible_location = Hooks.useMemo(func():
		if location == null:
			return RUIRouterLocation.parse("/")
		return RUIRouterLocation.new(RUIRouterPath.strip_basename(location.path, basename), location.query, location.state)
	, [location, basename])
	Hooks.provideContext(LOC_CTX, visible_location)

	var root_match := RUIRouteMatch.create_root(visible_location.path)
	Hooks.provideContext(ROUTE_MATCH, root_match)
	Hooks.provideContext(ROUTE_PATTERN, "/")
	Hooks.provideContext(NAV_BASE_CTX, "/")
	Hooks.provideContext(ROUTE_ENTRY, RouteContextEntry.new(root_match, "/", null, Hooks._cur))
	Hooks.provideContext(MATCH_CHAIN, [root_match])

	return _fragment(children)

static func _build_nav_ctx(history, basename: String) -> Dictionary:
	if history == null:
		return {
			"navigate": func(_p, _s = null): return false,
			"replace": func(_p, _s = null): return false,
			"go": func(_d): return false,
			"can_go": func(_d): return false,
			"register_blocker": func(_b): return func(): pass,
			"basename": basename,
			"history": null,
		}
	var do_navigate := func(path, state = null):
		history.push(RUIRouterPath.with_basename(str(path), basename), state)
		return true
	var do_replace := func(path, state = null):
		history.replace(RUIRouterPath.with_basename(str(path), basename), state)
		return true
	var do_go := func(delta):
		if not history.can_go(delta):
			return false
		history.go(delta)
		return true
	var do_can_go := func(delta):
		return history.can_go(delta)
	var do_register := func(blocker):
		return history.register_blocker(blocker)
	return {
		"navigate": do_navigate,
		"replace": do_replace,
		"go": do_go,
		"can_go": do_can_go,
		"register_blocker": do_register,
		"basename": basename,
		"history": history,
	}

# =============================================================================
# Route — V.route
# =============================================================================
static func route_fn(props: Dictionary, children: Array):
	var router = useRouter()
	if router == null:
		return null

	var path = props.get("path", null)
	var exact: bool = bool(props.get("exact", false))
	var is_index: bool = bool(props.get("index", false))
	var case_sensitive: bool = bool(props.get("case_sensitive", false))
	var element = props.get("element", null)
	var render_func = props.get("render", null)   # func(match: RUIRouteMatch) -> vnode

	# Index routes are pinned to the parent pattern; a path is meaningless (decision #2: warn + drop).
	if is_index and path != null and str(path) != "":
		var imsg := "[Router] <Route index> cannot also declare a 'path'. Index routes always match the parent route's pattern exactly. Dropping the path."
		RUIDiagnostics.emit(imsg)
		push_error(imsg)
		path = null

	var parent_entry = _resolve_current_entry()
	var parent_navigation_base: String = parent_entry.navigation_base if parent_entry != null else "/"
	var parent_match: RUIRouteMatch = parent_entry.route_match if (parent_entry != null and parent_entry.route_match != null) else RUIRouteMatch.create_root(router["location"].path)
	var parent_pattern: String = parent_match.pattern if parent_match != null else "/"

	var resolved_path: String
	if is_index:
		resolved_path = parent_pattern
	elif path == null or str(path) == "":
		resolved_path = parent_pattern
	else:
		resolved_path = RUIRouterPath.combine(parent_pattern, str(path))

	# RR v6 leaf semantics: a route consumes the FULL path (exact) unless it is a layout (has
	# nested <Route> children rendered via <Outlet/>) or carries a trailing splat in its pattern.
	var effective_exact: bool = exact or is_index or not _has_route_children(children)
	var loc_path: String = router["location"].path
	var m = Hooks.useMemo(func():
		return RUIRouteMatcher.match(loc_path, resolved_path, effective_exact, parent_match, case_sensitive)
	, [loc_path, resolved_path, effective_exact, parent_match, case_sensitive])

	# All hooks run UNCONDITIONALLY (before the no-match early return) so the hook count is stable
	# whether or not the route matches — required by the positional hook model + the 7.0 hook-order
	# validator. (Routes inside <Routes> only render when picked, but a bare V.route can render and
	# not match in place; computing these with a null `m` is harmless — they just aren't provided.)
	var provided_pattern: String = resolved_path if (resolved_path != null and resolved_path != "") else (m.pattern if m != null else parent_pattern)
	var base_seed: String = resolved_path if (resolved_path != null and resolved_path != "") else parent_navigation_base
	var navigation_base := RUIRouterPath.combine(base_seed if base_seed != null else "/", "")
	var route_entry = Hooks.useMemo(func():
		return RouteContextEntry.new(m, navigation_base, parent_entry, Hooks._cur)
	, [m, navigation_base, parent_entry, Hooks._cur])
	var parent_chain = Hooks.useContext(MATCH_CHAIN)
	var our_chain = Hooks.useMemo(func(): return _append_chain(parent_chain, m), [parent_chain, m])

	if m == null:
		return null

	Hooks.provideContext(ROUTE_MATCH, m)
	Hooks.provideContext(ROUTE_PATTERN, provided_pattern)
	Hooks.provideContext(NAV_BASE_CTX, navigation_base)
	Hooks.provideContext(ROUTE_ENTRY, route_entry)
	Hooks.provideContext(MATCH_CHAIN, our_chain)

	# Layout-route co-existence: publish the best nested <Route> for a descendant <Outlet/> to
	# render. ALWAYS publish (even null) — provided_context persists across renders (the reused
	# fiber duplicates it), so a stale match from a previous navigation would otherwise linger and
	# suppress the outlet's fallback when the nested route stops matching. [audit]
	var nested = _select_nested_route_for_outlet(children, loc_path, m, resolved_path)
	Hooks.provideContext(OUTLET_ELEMENT, nested)

	if render_func is Callable:
		return render_func.call(m)
	if element is RUIVNode:
		return element
	return _fragment(children)

# =============================================================================
# Outlet — V.outlet
# =============================================================================
static func outlet_fn(props: Dictionary, children: Array):
	if useRouter() == null:
		if RUIConfig.enable_strict_diagnostics:
			push_warning("[Router] <Outlet/> rendered outside any <Router>. The outlet will render nothing.")
		return null
	var ctx = props.get("context", null)
	if ctx != null:
		Hooks.provideContext(OUTLET_CONTEXT, ctx)
	var slot = Hooks.useContext(OUTLET_ELEMENT)
	if slot != null:
		return slot
	return _fragment(children)

# =============================================================================
# Routes — V.routes (auto-detects: Dictionary `routes` table vs JSX-style children switch)
# =============================================================================
static func routes(props: Dictionary, children: Array):
	if props.has("routes") and props["routes"] is Array:
		return _routes_table(props, children)
	return _routes_switch(props, children)

# Legacy table API (kept working for examples/demos/router + core_test).
static func _routes_table(props: Dictionary, _children: Array):
	var route_list: Array = props.get("routes", [])
	var location := useLocation()
	var matched = RUIRouteMatcher.match_routes(route_list, location)
	if matched == null:
		return []
	var route = matched["route"]
	var params: Dictionary = matched["params"]
	var pattern := str(route.get("path", "/"))
	# Publish a RouteMatch so useParams() works uniformly (legacy + spine).
	Hooks.provideContext(ROUTE_MATCH, RUIRouteMatch.new(location, pattern, params))
	var comp = route.get("component")
	if comp is Callable:
		return V.fc(comp, { "params": params })
	if comp is RUIVNode:
		return comp
	return []

# New ranked switch over <Route> children (first/most-specific match wins).
static func _routes_switch(_props: Dictionary, children: Array):
	var router = useRouter()
	if router == null:
		return null
	var parent_entry = _resolve_current_entry()
	var parent_match: RUIRouteMatch = parent_entry.route_match if (parent_entry != null and parent_entry.route_match != null) else RUIRouteMatch.create_root(router["location"].path)
	var parent_pattern: String = parent_match.pattern if parent_match != null else "/"

	var candidates: Array = []
	var counter: Array = [0]
	_collect_route_candidates(children, parent_pattern, candidates, counter)
	if candidates.is_empty():
		return null
	var loc_path: String = router["location"].path
	var picked = Hooks.useMemo(func():
		return RUIRouteRanker.pick(candidates, loc_path, parent_match)
	, [loc_path, parent_match, candidates.size()])
	if picked == null:
		return null
	return picked["candidate"]["node"]

# =============================================================================
# Navigate — V.navigate (declarative redirect)
# =============================================================================
static func navigate_fn(props: Dictionary, _children: Array):
	var to := str(props.get("to", "/"))
	var replace: bool = bool(props.get("replace", true))   # <Navigate> defaults to replace
	var state = props.get("state", null)
	var navigate := useNavigate(replace)
	# Effect runs after commit so we never navigate from inside render.
	Hooks.useEffect(func():
		navigate.call(to, state)
		return null
	, [to, replace, state])
	return null

# =============================================================================
# NavLink — V.nav_link (active-aware navigation button)
# =============================================================================
static func nav_link_fn(props: Dictionary, _children: Array):
	var router = useRouter()
	if router == null:
		return null
	var route_match = Hooks.useContext(ROUTE_MATCH)
	if route_match == null:
		route_match = RUIRouteMatch.create_root(router["location"].path)
	var base = Hooks.useContext(NAV_BASE_CTX)
	var navigation_base: String = base if base != null else (route_match.pattern if route_match != null else "/")

	var to := str(props.get("to", "/"))
	var label := str(props.get("label", to))
	var replace: bool = bool(props.get("replace", false))
	var end: bool = bool(props.get("end", false))
	var case_sensitive: bool = bool(props.get("case_sensitive", false))
	var style = props.get("style", null)
	var active_style = props.get("active_style", null)
	var state = props.get("state", null)

	var resolved_target := _resolve_target(to, navigation_base)
	var is_active := _nav_link_is_active(router["location"].path, resolved_target, end, case_sensitive)
	var navigate: Callable = router["replace"] if replace else router["navigate"]

	var btn := { "text": label, "on_pressed": func(): navigate.call(resolved_target, state) }
	var final_style = active_style if (is_active and active_style != null) else style
	if final_style != null:
		btn["style"] = final_style
	var extra: Dictionary = props.get("button_props", {})
	for k in extra:
		btn[k] = extra[k]
	return V.Button(btn)

# =============================================================================
# Link — V.link (plain navigation button; base-relative `to`)
# =============================================================================
static func link(props: Dictionary, _children: Array):
	var router = useRouter()
	var base = Hooks.useContext(NAV_BASE_CTX)
	var navigation_base: String = base if base != null else "/"
	var to := str(props.get("to", "/"))
	var replace: bool = bool(props.get("replace", false))
	var state = props.get("state", null)
	var resolved_target := _resolve_target(to, navigation_base)
	var nav_fn: Callable
	if router == null:
		nav_fn = func(): pass
	elif replace:
		nav_fn = func(): router["replace"].call(resolved_target, state)
	else:
		nav_fn = func(): router["navigate"].call(resolved_target, state)
	var btn := { "text": str(props.get("text", to)), "on_pressed": nav_fn }
	var extra: Dictionary = props.get("button_props", {})
	for k in extra:
		btn[k] = extra[k]
	return V.Button(btn)

# =============================================================================
# Hooks
# =============================================================================

## Combined RouterState (location + handlers). Reads NAV + LOC, so consumers re-render on
## navigation. Returns null when not inside a <Router>.
static func useRouter():
	var nav = Hooks.useContext(NAV_CTX)
	if nav == null:
		return null
	var loc = Hooks.useContext(LOC_CTX)
	return {
		"location": loc if loc is RUIRouterLocation else RUIRouterLocation.parse("/"),
		"navigate": nav["navigate"],
		"replace": nav["replace"],
		"go": nav["go"],
		"can_go": nav["can_go"],
		"register_blocker": nav["register_blocker"],
		"basename": nav["basename"],
	}

## The current location object (or null outside a Router).
static func useLocationInfo():
	var loc = Hooks.useContext(LOC_CTX)
	return loc if loc is RUIRouterLocation else null

## The current location path String. Reads only LOC_CTX (re-renders on navigation).
static func useLocation() -> String:
	var loc = Hooks.useContext(LOC_CTX)
	if loc is RUIRouterLocation:
		return loc.path
	return str(loc) if loc != null else "/"

## The decoded query dictionary of the current location. Returns a defensive copy — the location's
## own dict is part of an immutable-identity object used for context change-detection. [audit]
static func useQuery() -> Dictionary:
	var loc = Hooks.useContext(LOC_CTX)
	return loc.query.duplicate() if loc is RUIRouterLocation else {}

## The opaque navigation state of the current location.
static func useNavigationState():
	var loc = Hooks.useContext(LOC_CTX)
	return loc.state if loc is RUIRouterLocation else null

## Captured :params of the matched route (merged down the parent chain). Returns a defensive copy
## (the RouteMatch is an immutable-identity object used for context change-detection). [audit]
static func useParams() -> Dictionary:
	var m = Hooks.useContext(ROUTE_MATCH)
	return m.params.duplicate() if m is RUIRouteMatch else {}

## The matched RUIRouteMatch for the nearest route (or null).
static func useRouteMatch():
	var m = Hooks.useContext(ROUTE_MATCH)
	return m if m is RUIRouteMatch else null

## A navigator: func(path, state := null) -> bool. Resolves relative paths against the current
## route's navigation base. Reads only the STABLE nav contexts, so navigate-only widgets do NOT
## re-render on navigation.
static func useNavigate(replace := false) -> Callable:
	var nav = Hooks.useContext(NAV_CTX)
	var base = Hooks.useContext(NAV_BASE_CTX)
	if nav == null:
		return func(_p, _s = null): return false
	var navigation_base: String = base if base != null else "/"
	var handler: Callable = nav["replace"] if replace else nav["navigate"]
	return func(path, state = null):
		return handler.call(_resolve_target(str(path) if path != null else "", navigation_base), state)

## The navigation base (resolved pattern) of the current route.
static func useNavigationBase() -> String:
	var base = Hooks.useContext(NAV_BASE_CTX)
	return base if base != null else "/"

## A relative-history navigator: func(delta) -> bool.
static func useGo() -> Callable:
	var nav = Hooks.useContext(NAV_CTX)
	if nav == null:
		return func(_d): return false
	return nav["go"]

## Whether history can move `delta` entries from the current position. Subscribes to LOC_CTX so the
## consumer re-renders on navigation (the history index moved) — NAV_CTX alone is stable. [audit]
static func useCanGo(delta: int) -> bool:
	var nav = Hooks.useContext(NAV_CTX)
	Hooks.useContext(LOC_CTX)   # subscribe to location changes so can-go state stays fresh
	if nav == null:
		return false
	return nav["can_go"].call(delta)

## The ordered chain of RouteMatch entries root -> current (for breadcrumbs / analytics).
static func useMatches() -> Array:
	var chain = Hooks.useContext(MATCH_CHAIN)
	return chain if chain is Array else []

## The value handed down by the closest enclosing <Outlet context=...>.
static func useOutletContext():
	return Hooks.useContext(OUTLET_CONTEXT)

## Resolve `to` against the current navigation base — the absolute path useNavigate would dispatch.
static func useResolvedPath(to: String) -> String:
	var base = Hooks.useContext(NAV_BASE_CTX)
	return _resolve_target(to, base if base != null else "/")

## [query, setter]. setter(next_query: Dictionary, replace := false) replaces only the query string.
static func useSearchParams() -> Array:
	var router = useRouter()
	var current: Dictionary = router["location"].query if router != null else {}
	var current_path: String = router["location"].path if router != null else "/"
	var current_state = router["location"].state if router != null else null
	var setter := func(next: Dictionary, replace := false):
		if router == null:
			return
		var qs := RUIRouterPath.build_query(next)
		var target := current_path if qs == "" else current_path + "?" + qs
		if replace:
			router["replace"].call(target, current_state)
		else:
			router["navigate"].call(target, current_state)
	return [current, setter]

## Register a navigation blocker for the lifetime of this component (while `enabled`).
## blocker: func(from: RUIRouterLocation, to: RUIRouterLocation) -> bool, returns TRUE to block.
static func useBlocker(blocker: Callable, enabled := true) -> void:
	var nav = Hooks.useContext(NAV_CTX)   # stable — register once, not every render
	Hooks.useEffect(func():
		if not enabled or nav == null or not (blocker is Callable):
			return null
		var unsub = nav["register_blocker"].call(blocker)
		return func():
			if unsub is Callable:
				unsub.call()
	, [nav, enabled])

## Convenience: block navigation whenever `when` is true (e.g. an unsaved-changes prompt). The
## message is logged in strict-diagnostics mode (the host has no dialog surface).
static func usePrompt(when: bool, message := "") -> void:
	useBlocker(func(_from, _to):
		if when and message != "" and RUIConfig.enable_strict_diagnostics:
			push_warning("[Router prompt] " + message)
		return when   # true == block
	, when)

# =============================================================================
# Internals — candidate collection, ranking glue, path resolution, fragment
# =============================================================================

static func _is_route(child) -> bool:
	return child is RUIVNode and child.kind == RUIVNode.Kind.FUNCTION and child.component.is_valid() and child.component.get_method() == "route_fn"

# Walks `nodes` for <Route> vnodes (descending transparently through fragments), building ranked
# candidates against `parent_resolved_path`. `counter` is a single-element Array used as an int
# out-param (GDScript ints are value types).
static func _collect_route_candidates(nodes: Array, parent_resolved_path: String, candidates: Array, counter: Array) -> void:
	if nodes == null:
		return
	for child in nodes:
		if child == null:
			continue
		if child is RUIVNode and child.kind == RUIVNode.Kind.FRAGMENT and not child.children.is_empty():
			_collect_route_candidates(child.children, parent_resolved_path, candidates, counter)
			continue
		if not _is_route(child):
			continue
		var cp: Dictionary = child.props
		var child_path = cp.get("path", null)
		var is_index: bool = bool(cp.get("index", false))
		var resolved: String
		if is_index or child_path == null or str(child_path) == "":
			resolved = parent_resolved_path if parent_resolved_path != null else "/"
		else:
			resolved = RUIRouterPath.combine(parent_resolved_path if parent_resolved_path != null else "/", str(child_path))
		# Leaf routes (no nested <Route> children) match exactly; layouts match as a prefix.
		var is_leaf := not _has_route_children(child.children)
		candidates.append({
			"declaration_index": counter[0],
			"resolved_path": resolved,
			"is_index": is_index,
			"exact": bool(cp.get("exact", false)) or is_leaf,
			"case_sensitive": bool(cp.get("case_sensitive", false)),
			"node": child,
		})
		counter[0] += 1

# True if `nodes` contains any <Route> (descending transparently through fragments).
static func _has_route_children(nodes) -> bool:
	if not (nodes is Array):
		return false
	for child in nodes:
		if child == null:
			continue
		if child is RUIVNode and child.kind == RUIVNode.Kind.FRAGMENT and not child.children.is_empty():
			if _has_route_children(child.children):
				return true
			continue
		if _is_route(child):
			return true
	return false

static func _select_nested_route_for_outlet(children: Array, current_location: String, parent_match: RUIRouteMatch, parent_resolved_path: String):
	if children == null or children.is_empty():
		return null
	var candidates: Array = []
	var counter: Array = [0]
	_collect_route_candidates(children, parent_resolved_path, candidates, counter)
	if candidates.is_empty():
		return null
	var picked = RUIRouteRanker.pick(candidates, current_location, parent_match)
	if picked == null:
		return null
	return picked["candidate"]["node"]

# Resolve the entry of the PARENT route (owner-unwraps our own previously-published entry, which
# context reads see because provided_context persists on the fiber across renders).
static func _resolve_current_entry() -> RouteContextEntry:
	var entry = Hooks.useContext(ROUTE_ENTRY)
	if entry == null:
		return _root_entry()
	if entry.owner == Hooks._cur:
		return entry.parent if entry.parent != null else _root_entry()
	return entry

static func _append_chain(parent, m: RUIRouteMatch) -> Array:
	if m == null:
		return parent if parent is Array else []
	if not (parent is Array) or parent.is_empty():
		return [m]
	var arr: Array = parent.duplicate()
	arr.append(m)
	return arr

# Resolve a `to` against a navigation base: "" -> base; "/abs" -> normalized; else base-relative.
static func _resolve_target(to: String, navigation_base: String) -> String:
	if to == null or to == "":
		return navigation_base if navigation_base != null else "/"
	if to.begins_with("/"):
		return RUIRouterPath.normalize(to)
	return RUIRouterPath.combine(navigation_base if navigation_base != null else "/", to)

# Mirrors RR's NavLink activation: end => exact; "/" only on "/"; else prefix-on-segment-boundary.
static func _nav_link_is_active(current_location: String, resolved_target: String, end: bool, case_sensitive: bool) -> bool:
	var norm_loc := RUIRouterPath.normalize(current_location)
	var norm_target := RUIRouterPath.normalize(resolved_target)
	var cl := norm_loc if case_sensitive else norm_loc.to_lower()
	var ct := norm_target if case_sensitive else norm_target.to_lower()
	if ct == "/":
		return cl == "/"
	if cl == ct:
		return true
	if end:
		return false
	return cl.length() > ct.length() and cl.begins_with(ct) and cl[ct.length()] == "/"

static func _fragment(children):
	if children == null or (children is Array and children.is_empty()):
		return V.fragment()
	if children is Array and children.size() == 1:
		return children[0]
	return V.fragment(children)
