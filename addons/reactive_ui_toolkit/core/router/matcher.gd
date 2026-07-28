class_name RUIRouteMatcher
extends RefCounted
## Path matching + ranking. Patterns support static segments ("/users"), params
## (":id"), and a trailing splat ("*"). Ports the engine-agnostic RouteMatcher/
## RouteRanker logic (more specific routes win, splat loses).

## Match `path` against `pattern`. Returns { "params": {...} } or null.
static func match_pattern(pattern: String, path: String):
	var pp := _segments(pattern)
	var ps := _segments(path)
	var params := {}
	var i := 0
	while i < pp.size():
		var seg: String = pp[i]
		if seg == "*":
			params["*"] = "/".join(ps.slice(i))
			return { "params": params }
		if i >= ps.size():
			return null
		if seg.begins_with(":"):
			params[seg.substr(1)] = ps[i]
		elif seg != ps[i]:
			return null
		i += 1
	if ps.size() != pp.size():
		return null
	return { "params": params }

## Higher = more specific. Static > param > splat; root ("/") beats splat.
static func rank(pattern: String) -> int:
	var score := 4
	for s in _segments(pattern):
		if s == "*": score -= 3
		elif s.begins_with(":"): score += 5
		else: score += 10
	return score

## Best match across a route table. Returns { "route": {...}, "params": {...} } or null.
static func match_routes(routes: Array, path: String):
	var best = null
	var best_rank := -2147483648
	for r in routes:
		var m = match_pattern(str(r.get("path", "")), path)
		if m != null:
			var rk := rank(str(r.get("path", "")))
			if rk > best_rank:
				best_rank = rk
				best = { "route": r, "params": m["params"] }
	return best

static func _segments(path: String) -> Array:
	return Array(path.strip_edges().split("/", false))

# --------------------------------------------------------------------------
# Component-tree matching (Phase 7.5) — faithful port of RouteMatcher.cs, used by V.route/<Routes>.
# Merges :param captures down the parent chain; trailing "*" is a wildcard prefix match.
# --------------------------------------------------------------------------

static func match(current_location: String, pattern: String, exact: bool, parent_match: RUIRouteMatch, case_sensitive := false) -> RUIRouteMatch:
	var normalized_location := RUIRouterPath.normalize(current_location)
	var parent_params: Dictionary = parent_match.params if parent_match != null else {}
	if pattern == null or pattern == "" or pattern == "*" or pattern == "/*":
		return RUIRouteMatch.new(normalized_location, normalized_location, _merge(parent_params, {}))
	var normalized_pattern := RUIRouterPath.normalize(pattern)
	var location_segments := RUIRouterPath.split_segments(normalized_location)
	var pattern_segments := RUIRouterPath.split_segments(normalized_pattern)
	var has_wildcard: bool = pattern_segments.size() > 0 and pattern_segments[-1] == "*"
	var match_segment_count: int = (pattern_segments.size() - 1) if has_wildcard else pattern_segments.size()
	var location_segment_count := location_segments.size()
	if match_segment_count > location_segment_count:
		return null
	var parameters := {}
	for i in match_segment_count:
		if i >= location_segment_count:
			return null
		var ps: String = pattern_segments[i]
		var ls: String = location_segments[i]
		if ps.begins_with(":"):
			var key := ps.substr(1)
			if key != "":
				parameters[key] = ls
			continue
		var same: bool = (ps == ls) if case_sensitive else (ps.nocasecmp_to(ls) == 0)
		if not same:
			return null
	if exact and not has_wildcard and location_segments.size() != match_segment_count:
		return null
	return RUIRouteMatch.new(normalized_location, normalized_pattern, _merge(parent_params, parameters))

static func _merge(parent: Dictionary, current: Dictionary) -> Dictionary:
	if (parent == null or parent.is_empty()) and (current == null or current.is_empty()):
		return {}
	var merged := {}
	if parent != null:
		for k in parent:
			merged[k] = parent[k]
	if current != null:
		for k in current:
			merged[k] = current[k]
	return merged
