class_name RUIRouterPath
extends RefCounted
## Pure path algebra for the router (Phase 7.5) — faithful port of the Unity reference RouterPath.cs.
## No engine dependencies; the most testable router piece. `parse` returns a plain Dictionary
## { path, query, state } (the RUIRouterLocation shape used from 7.8 on).

static func combine(base_path: String, relative_path: String) -> String:
	var normalized_base := normalize(base_path)
	normalized_base = _trim_trailing_wildcard(normalized_base)
	if relative_path == null or relative_path.strip_edges() == "":
		return normalized_base
	if relative_path == "*" or relative_path == "/*":
		if normalized_base == "/":
			return "/*"
		return normalize(_trim_trailing_slashes(normalized_base) + "/*")
	if relative_path.begins_with("/"):
		return normalize(relative_path)
	var combined := ("/" + relative_path) if normalized_base == "/" else (_trim_trailing_slashes(normalized_base) + "/" + relative_path)
	return normalize(combined)

static func parse(raw: String, state = null) -> Dictionary:
	var working := raw if raw != null else "/"
	var qi := working.find("?")
	var path_part := working.substr(0, qi) if qi >= 0 else working
	var query_part := working.substr(qi + 1) if (qi >= 0 and qi + 1 < working.length()) else ""
	return { "path": normalize(path_part), "query": parse_query(query_part), "state": state }

static func normalize(path: String) -> String:
	if path == null or path.strip_edges() == "":
		return "/"
	var sanitized := path.replace("\\", "/").strip_edges()
	if sanitized == "/":
		return "/"
	var segments := _split_segments_internal(sanitized)
	if segments.is_empty():
		return "/"
	return "/" + "/".join(segments)

static func split_segments(path: String) -> Array:
	return _split_segments_internal(path)

static func parse_query(query: String) -> Dictionary:
	var dict := {}
	if query == null or query.strip_edges() == "":
		return dict
	for part in query.split("&"):
		if part == "":
			continue
		var eq: int = part.find("=")
		var key := (part.substr(0, eq) if eq >= 0 else part).uri_decode()
		var value := (part.substr(eq + 1) if eq >= 0 else "").uri_decode()
		if key == "":
			continue
		dict[key] = value
	return dict

static func build_query(query: Dictionary) -> String:
	if query == null or query.is_empty():
		return ""
	var parts: Array = []
	for k in query:
		if str(k) == "":
			continue
		var s := str(k).uri_encode()
		if query[k] != null:
			s += "=" + str(query[k]).uri_encode()
		parts.append(s)
	return "&".join(parts)

static func strip_basename(path: String, basename: String) -> String:
	if basename == null or basename == "" or basename == "/":
		return normalize(path)
	var nb := normalize(basename)
	var np := normalize(path)
	if np.to_lower().begins_with(nb.to_lower()):
		if np.length() == nb.length():
			return "/"
		if np[nb.length()] == "/":
			return normalize(np.substr(nb.length()))
	return np

static func with_basename(path: String, basename: String) -> String:
	if basename == null or basename == "" or basename == "/":
		return normalize(path)
	var nb := normalize(basename)
	var np := normalize(path)
	if np.to_lower().begins_with(nb.to_lower()):
		return np
	if np == "/":
		return nb
	return normalize(_trim_trailing_slashes(nb) + np)

static func _split_segments_internal(path: String) -> Array:
	var buffer: Array = []
	if path == null or path == "":
		return buffer
	for segment in path.replace("\\", "/").split("/", false):
		var trimmed := segment.strip_edges()
		if trimmed.length() == 0:
			continue
		buffer.append(trimmed)
	return buffer

static func _trim_trailing_wildcard(path: String) -> String:
	if path == null or path == "":
		return "/"
	if path.ends_with("/*"):
		return "/" if path.length() <= 2 else path.substr(0, path.length() - 2)
	return path

static func _trim_trailing_slashes(s: String) -> String:
	var i := s.length()
	while i > 0 and s[i - 1] == "/":
		i -= 1
	return s.substr(0, i)
