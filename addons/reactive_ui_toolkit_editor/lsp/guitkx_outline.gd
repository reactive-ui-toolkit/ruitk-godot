@tool
class_name GuitkxOutline
extends RefCounted
## Document outline (parity plan G12): the file's declarations — components ◆, hooks ƒ, utils ƒ,
## values =, modules ▣ and their members — as [{name, kind, offset, export}], offset at the
## declaration NAME. ES-modules leg: declarations are SIGNATURE-classified (plain forms have no
## keyword), so the outline consumes the compiler's own scan (RUIGuitkx.analyzed_decls — the same
## single source of truth the workspace index and every identity table use), not a regex.

static func outline_of(text: String) -> Array:
	var out: Array = []
	var module_spans: Array = []   # [start] of wrapper-module bodies (member funcs belong to them)
	for dm in (RUIGuitkx.analyzed_decls(text, 0)["decls"] as Array):
		out.append({
			"name": str(dm["name"]), "kind": str(dm["kind"]), "offset": int(dm["name_at"]),
			"export": bool(dm["export"]),
		})
		if str(dm["kind"]) == "module":
			module_spans.append(int(dm["at"]))
	# Wrapper-module member functions (window syntax; a hoisted/plain file lists every decl at top
	# level already, so this only fires for not-yet-modernized files).
	if not module_spans.is_empty():
		var fn := RegEx.new()
		fn.compile("(?m)^[ \\t]+(?:export[ \\t]+)?(?:component|hook)[ \\t]+([A-Za-z_][A-Za-z0-9_]*)")
		for f in fn.search_all(text):
			if f.get_start(0) > int(module_spans[0]):
				out.append({ "name": f.get_string(1), "kind": "func", "offset": f.get_start(1), "export": false })
	out.sort_custom(func(a, b): return int(a["offset"]) < int(b["offset"]))
	return out
