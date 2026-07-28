extends SceneTree
## One-shot Phase D migration: pre-0.7 directive bodies (bare markup children) become the
## `return ( <markup> )` form the 0.7 grammar requires. Per file it loops: find the FIRST
## directive body whose content is the legacy grammar (the compiler's own `_split_body`
## `legacy_at` detector -- the same check that emits GUITKX2103), wrap that body's content in
## `return ( ... )`, rescan -- until clean. Outer bodies wrap first; the nested directives that
## wrap exposes are caught on the next pass. `@match` outer bodies are arm containers and are
## never wrapped (their `@case`/`@default` bodies are). Cosmetic indentation is left to the
## formatter (run Format Document / the repo reformat afterwards).
##   godot --headless --path . --script res://addons/reactive_ui_toolkit/dev/migrate_directive_bodies.gd -- <dir-or-file> [...]

const L = preload("res://addons/reactive_ui_toolkit/guitkx/guitkx_lexer.gd")
const Compiler = preload("res://addons/reactive_ui_toolkit/guitkx/guitkx.gd")

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		args = ["res://examples"]
	var files: Array = []
	for a in args:
		_collect(str(a), files)
	var changed := 0
	for f in files:
		var src := FileAccess.get_file_as_string(f)
		if src.is_empty():
			continue
		var out := _migrate(src)
		if out != src:
			var w := FileAccess.open(f, FileAccess.WRITE)
			w.store_string(out)
			w.close()
			changed += 1
			print("migrated  ", f)
	print("[migrate_directive_bodies] %d file(s) changed of %d scanned" % [changed, files.size()])
	quit(0)

func _collect(path: String, out: Array, is_root: bool = true) -> void:
	if FileAccess.file_exists(path):
		if path.get_extension() == "guitkx":
			out.append(path)
		return
	var d := DirAccess.open(path)
	if d == null:
		return
	# An explicitly-passed root is migrated even when .gdignore'd (e.g. tests/contract/fixtures);
	# only dirs discovered by recursion honor the ignore.
	if not is_root and FileAccess.file_exists(path.path_join(".gdignore")):
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if name != "." and name != "..":
			var p := path.path_join(name)
			if d.current_is_dir():
				if not name.begins_with("."):
					_collect(p, out, false)
			elif name.get_extension() == "guitkx":
				out.append(p)
		name = d.get_next()
	d.list_dir_end()

func _migrate(src: String) -> String:
	var guard := 0
	while guard < 200:
		guard += 1
		var hit := _first_legacy_body(src)
		if hit.is_empty():
			return src
		var open: int = hit["open"]
		var close: int = hit["close"]
		var body := src.substr(open + 1, close - open - 1)
		src = src.substr(0, open) + "{ return (" + body + ") }" + src.substr(close + 1)
	push_error("migrate: did not converge (unbalanced source?)")
	return src

## The first directive body (document order) whose content is the pre-0.7 grammar.
func _first_legacy_body(src: String) -> Dictionary:
	var n := src.length()
	var i := 0
	while i < n:
		var k := L.skip_noncode(src, i)
		if k != i:
			i = k
			continue
		if src[i] != "@":
			i += 1
			continue
		var kw := ""
		for c in ["if", "elif", "for", "while", "case", "else", "default", "match"]:
			if L.keyword_at(src, i + 1, c):
				kw = c
				break
		if kw == "":
			i += 1
			continue
		var j := i + 1 + kw.length()
		if kw != "else" and kw != "default":
			# skip the (...) header
			j = _skip_ws(src, j, n)
			if j >= n or src[j] != "(":
				i += 1
				continue
			var pc := L.find_matching(src, j)
			if pc == -1:
				return {}
			j = pc + 1
		if kw == "match":
			i = j   # the match braces hold @case/@default arms, never a wrappable body
			continue
		j = _skip_ws(src, j, n)
		if j >= n or src[j] != "{":
			i += 1
			continue
		var bc := L.find_matching(src, j)
		if bc == -1:
			return {}
		var body := src.substr(j + 1, bc - j - 1)
		var sp: Dictionary = Compiler._split_body(body)
		if not sp.has("error") and int(sp["legacy_at"]) != -1:
			return { "open": j, "close": bc }
		i = j + 1   # scan inside for nested directives
	return {}

func _skip_ws(s: String, i: int, n: int) -> int:
	while i < n and (s[i] == " " or s[i] == "\t" or s[i] == "\n" or s[i] == "\r"):
		i += 1
	return i
