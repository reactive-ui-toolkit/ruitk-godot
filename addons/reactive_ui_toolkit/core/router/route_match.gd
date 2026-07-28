class_name RUIRouteMatch
extends RefCounted
## A resolved route match (Phase 7.5) — port of the Unity reference RouteMatch.cs.
## `params` accumulates :param captures merged down the parent chain.

var location: String
var pattern: String
var params: Dictionary

func _init(loc: String, pat: String, prm: Dictionary) -> void:
	location = RUIRouterPath.normalize(loc)
	pattern = "/" if (pat == null or pat == "") else RUIRouterPath.normalize(pat)
	params = prm if prm != null else {}

static func create_root(loc: String) -> RUIRouteMatch:
	return RUIRouteMatch.new(loc, "/", {})
