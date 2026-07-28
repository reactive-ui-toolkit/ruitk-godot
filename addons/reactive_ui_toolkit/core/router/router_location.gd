class_name RUIRouterLocation
extends RefCounted
## A full router location (Phase 7.8) — port of the Unity reference RouterLocation.cs.
## `path` is the normalized pathname, `query` the decoded query dictionary, `state` the
## opaque navigation state. Distinct objects (RefCounted) so the reconciler's identity-based
## context change-detection fires on every navigation, even to the same path.

var path: String
var query: Dictionary
var state

func _init(p: String, q: Dictionary = {}, s = null) -> void:
	path = p if (p != null and p != "") else "/"
	query = q if q != null else {}
	state = s

func _to_string() -> String:
	return path

## Parse a raw "/path?a=1&b=2" string (+ optional opaque state) into a location.
static func parse(raw: String, state_obj = null) -> RUIRouterLocation:
	var d := RUIRouterPath.parse(raw, state_obj)
	return RUIRouterLocation.new(d["path"], d["query"], d["state"])
