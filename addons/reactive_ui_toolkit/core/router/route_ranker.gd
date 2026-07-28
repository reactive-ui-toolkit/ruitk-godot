class_name RUIRouteRanker
extends RefCounted
## Faithful port of the Unity reference RouteRanker.cs (Phase 7.5). Scoring (per resolved-path
## segment): static +10, :param +3, index-route +2, empty +1, splat -2; plus the index-route
## cost-cancellation (`if is_index: score -= segment_count`). pick() sorts by score DESC then
## declaration-index ASC and returns the first candidate whose pattern matches the location.

const STATIC_SEGMENT := 10
const DYNAMIC_SEGMENT := 3
const INDEX_ROUTE := 2
const EMPTY_SEGMENT := 1
const SPLAT_PENALTY := -2

static func compute_score(resolved_path: String, is_index: bool) -> int:
	var normalized := RUIRouterPath.normalize(resolved_path if resolved_path != null else "/")
	var segments: Array = [] if normalized == "/" else RUIRouterPath.split_segments(normalized)
	var score: int = segments.size()
	if is_index:
		score += INDEX_ROUTE
	for seg in segments:
		var s: String = seg
		if s == "*":
			score += SPLAT_PENALTY
		elif s.begins_with(":"):
			score += DYNAMIC_SEGMENT
		elif s.length() == 0:
			score += EMPTY_SEGMENT
		else:
			score += STATIC_SEGMENT
	if is_index and segments.size() > 0:
		score -= segments.size()
	return score

## candidates: Array of { declaration_index, resolved_path, is_index, exact, case_sensitive, node }.
## Returns { candidate, match } or null (no candidate matched).
static func pick(candidates: Array, current_location: String, parent_match: RUIRouteMatch):
	if candidates == null or candidates.is_empty():
		return null
	var scored: Array = []
	for c in candidates:
		scored.append({ "cand": c, "score": compute_score(c["resolved_path"], c["is_index"]) })
	scored.sort_custom(func(a, b):
		if a["score"] != b["score"]:
			return a["score"] > b["score"]
		return a["cand"]["declaration_index"] < b["cand"]["declaration_index"])
	for entry in scored:
		var c: Dictionary = entry["cand"]
		var exact: bool = c["is_index"] or c["exact"]
		var pat: String = ((parent_match.pattern if parent_match != null else "/") if c["is_index"] else c["resolved_path"])
		var m := RUIRouteMatcher.match(current_location, pat, exact, parent_match, c["case_sensitive"])
		if m != null:
			return { "candidate": c, "match": m }
	return null
