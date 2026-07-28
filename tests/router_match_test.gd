extends SceneTree
## Phase 7.5: pure router-foundation tests (RuitkRouterPath / RuitkRouteMatcher / RuitkRouteRanker).
## Value-asserts the score numbers + merge_params against the Unity reference, so the port is provably
## faithful. Run: godot --headless --path <project> --script res://tests/router_match_test.gd

var _fails := 0
var _passes := 0

func _initialize() -> void:
	_run()

func _ok(c: bool, m: String) -> void:
	if c:
		_passes += 1
	else:
		_fails += 1
		printerr("  FAIL: " + m)
		push_error("FAIL: " + m)

func _run() -> void:
	# RouterPath
	_ok(RuitkRouterPath.normalize("/users//5/") == "/users/5", "normalize collapses + trims")
	_ok(RuitkRouterPath.normalize("") == "/", "normalize empty -> /")
	_ok(RuitkRouterPath.combine("/users", ":id") == "/users/:id", "combine relative")
	_ok(RuitkRouterPath.combine("/users/*", "edit") == "/users/edit", "combine trims trailing wildcard")
	_ok(RuitkRouterPath.combine("/a", "/abs") == "/abs", "combine absolute replaces")
	var q := RuitkRouterPath.parse_query("a=1&b=hello%20world&c")
	_ok(q["a"] == "1" and q["b"] == "hello world" and q["c"] == "", "parse_query decodes")
	var parsed := RuitkRouterPath.parse("/users/5?tab=info")
	_ok(parsed["path"] == "/users/5" and parsed["query"]["tab"] == "info", "parse splits path + query")
	_ok(RuitkRouterPath.strip_basename("/app/users", "/app") == "/users", "strip_basename")
	_ok(RuitkRouterPath.with_basename("/users", "/app") == "/app/users", "with_basename")

	# RouteRanker scores (Unity numbers): seg-count start + static+10/:param+3/index+2/empty+1/splat-2
	_ok(RuitkRouteRanker.compute_score("/users", false) == 11, "static score 1+10=11, got %d" % RuitkRouteRanker.compute_score("/users", false))
	_ok(RuitkRouteRanker.compute_score("/users/:id", false) == 15, "param score 2+10+3=15, got %d" % RuitkRouteRanker.compute_score("/users/:id", false))
	_ok(RuitkRouteRanker.compute_score("/files/*", false) == 10, "splat score 2+10-2=10, got %d" % RuitkRouteRanker.compute_score("/files/*", false))
	_ok(RuitkRouteRanker.compute_score("/", true) == 2, "index-root score 0+2=2, got %d" % RuitkRouteRanker.compute_score("/", true))

	# RouteMatcher: param capture, exactness, wildcard, parent merge
	var m := RuitkRouteMatcher.match("/users/5", "/users/:id", true, null, false)
	_ok(m != null and m.params["id"] == "5", "matches + captures id=5")
	_ok(RuitkRouteMatcher.match("/users/5/edit", "/users/:id", true, null, false) == null, "exact non-wildcard rejects extra segments")
	_ok(RuitkRouteMatcher.match("/users/5/edit", "/users/:id/*", false, null, false) != null, "trailing wildcard accepts extra segments")
	var parent := RuitkRouteMatcher.match("/u/5/posts/9", "/u/:uid/*", false, null, false)
	var child := RuitkRouteMatcher.match("/u/5/posts/9", "/u/:uid/posts/:pid", true, parent, false)
	_ok(child != null and child.params["uid"] == "5" and child.params["pid"] == "9", "merge_params down the parent chain")

	# Pick: more specific wins, ties by declaration index
	var cands := [
		{ "declaration_index": 0, "resolved_path": "/users/*", "is_index": false, "exact": false, "case_sensitive": false, "node": null },
		{ "declaration_index": 1, "resolved_path": "/users/:id", "is_index": false, "exact": true, "case_sensitive": false, "node": null },
	]
	var picked = RuitkRouteRanker.pick(cands, "/users/5", null)
	_ok(picked != null and picked["candidate"]["declaration_index"] == 1, "pick chooses /users/:id over /users/* for /users/5")

	print("\n[router_match_test] %d passed, %d failed" % [_passes, _fails])
	quit(1 if _fails > 0 else 0)
