extends SceneTree
## T0.1 contract harness — the GDScript half. For every fixture under tests/contract/fixtures/,
## runs the COMPILER-OF-RECORD pipeline (RuitkGuitkx) and dumps a canonical golden JSON:
##
##   { "ok", "diagnostics":[{code,severity,off,len}], "windows":[{start,end}],
##     "markup":[{ "error", "error_code", "error_at", "tree" }] }
##
## `windows` are the ABSOLUTE component markup windows found by the same walk the LSP's
## markupWindows() performs (components directly and inside modules; hooks skipped); `markup[i]`
## is guitkx_markup.gd's parse of windows[i] with node offsets ABSOLUTE in the fixture (the parse
## runs over the full source), serialized with sorted keys so the TS side can deep-compare.
##
## The TS half (src/test/contract.test.ts) asserts markupWindows() + parseMarkup() reproduce the
## goldens byte-for-byte — so guitkx.gd/guitkx_markup.gd and formatGuitkx.ts/markup.ts can never
## silently diverge on real files. Fixtures named *.pending.guitkx are KNOWN divergences: the TS
## test asserts they still diverge (when a fix lands, the test fails with "now agrees — promote").
##
##   regen:  godot --headless --path . --script res://tests/contract_dump.gd
##   check:  godot --headless --path . --script res://tests/contract_dump.gd -- --check   (CI)
##
## --check re-derives every golden in memory and fails (exit 1) on any drift — the GD-side half of
## the contract ("golden == current GD output"); the vitest half asserts "TS == golden".

const FIXTURES := "res://tests/contract/fixtures"
const GOLDEN := "res://tests/contract/golden"

const L = preload("res://addons/reactive_ui_toolkit/guitkx/guitkx_lexer.gd")
const Markup = preload("res://addons/reactive_ui_toolkit/guitkx/guitkx_markup.gd")
const Compiler = preload("res://addons/reactive_ui_toolkit/guitkx/guitkx.gd")

func _initialize() -> void:
	var check := "--check" in OS.get_cmdline_user_args()
	var names := _fixture_names()
	if names.is_empty():
		push_error("[contract] no fixtures found under %s" % FIXTURES)
		quit(1)
		return
	if not check:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(GOLDEN))
	var drift: Array = []
	for name in names:
		var src := FileAccess.get_file_as_string(FIXTURES + "/" + name).replace("\r", "")
		var golden := JSON.stringify(_derive(src, (name as String).get_basename().get_basename()), "\t", true) + "\n"
		var gpath := GOLDEN + "/" + (name as String).get_basename() + ".json"
		if check:
			var want := FileAccess.get_file_as_string(gpath).replace("\r", "")
			if want != golden.replace("\r", ""):
				drift.append(name)
		else:
			var f := FileAccess.open(gpath, FileAccess.WRITE)
			f.store_string(golden)
			f.close()
	if check:
		if drift.is_empty():
			print("[contract_dump] check OK: %d goldens match the compiler of record" % names.size())
			quit(0)
		else:
			push_error("[contract_dump] %d golden(s) STALE (regen: godot --headless --path . --script res://tests/contract_dump.gd): %s" % [drift.size(), ", ".join(drift)])
			quit(1)
	else:
		print("[contract_dump] wrote %d goldens to %s" % [names.size(), GOLDEN])
		quit(0)

func _fixture_names() -> Array:
	var out: Array = []
	var d := DirAccess.open(FIXTURES)
	if d == null:
		return out
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if not d.current_is_dir() and name.get_extension() == "guitkx":
			out.append(name)
		name = d.get_next()
	d.list_dir_end()
	out.sort()
	return out

## The full golden record for one fixture source.
func _derive(src: String, basename: String) -> Dictionary:
	var r: Dictionary = Compiler.compile(src, basename)
	var diags: Array = []
	for d in r["diagnostics"]:
		diags.append({ "code": d.get("code", ""), "severity": int(d.get("severity", 0)),
			"off": int(d.get("offset", -1)), "len": int(d.get("length", 0)) })
	diags.sort_custom(func(a, b): return a["off"] < b["off"] if a["off"] != b["off"] else a["code"] < b["code"])
	var windows: Array = []
	_collect_windows(src, 0, src.length(), windows)
	var markup: Array = []
	for w in windows:
		var p = Markup.new()
		var pr: Dictionary = p.parse(src, w["start"], w["end"])
		markup.append({ "error": pr["error"], "error_code": pr["error_code"], "error_at": int(pr["error_at"]),
			"tree": JSON.stringify(pr["nodes"], "", true) })
	return { "ok": bool(r["ok"]), "diagnostics": diags, "windows": windows, "markup": markup }

## The same decl walk as the LSP's markupWindows(): component windows directly and inside modules,
## hooks/utils/values/markers skipped. ES-modules leg: plain components (signature-classified, no
## keyword) carry their own `body_open`; wrapper components keep the keyword-anchored body walk.
## Deliberately NOT typo-recovering (the compiler's _find_decl is exact) — the declScan-recovery
## asymmetry is pinned by the *.pending.guitkx fixtures. MIRROR: workspaceIndex.ts markupWindows.
func _collect_windows(src: String, from: int, to: int, out: Array) -> void:
	var i := from
	while i < to:
		var d: Dictionary = Compiler._find_decl(src, i)
		if d["kind"] == "" or int(d["at"]) >= to:
			break
		var at := int(d["at"])
		var plain: bool = not bool(d.get("deprecated", true))
		if d["kind"] == "component":
			var b: Dictionary
			if plain:
				var close := L.find_matching_markup(src, int(d["body_open"]))
				b = {} if close == -1 else { "start": int(d["body_open"]) + 1, "close": close }
			else:
				b = _decl_body(src, at, true)
			if b.is_empty():
				i = at + 1
				continue
			var split: Dictionary = Compiler._split_return(src.substr(int(b["start"]), int(b["close"]) - int(b["start"])))
			if not split.has("error"):
				# Phase C mirror of markupWindows(): EARLY markup returns are windows too, in source
				# order before the final one.
				for part in split.get("parts", []):
					if str(part["t"]) == "ret" and int(part["m_end"]) > int(part["m_start"]):
						out.append({ "start": int(b["start"]) + int(part["m_start"]), "end": int(b["start"]) + int(part["m_end"]) })
				if int(split["m_end"]) > int(split["m_start"]):
					out.append({ "start": int(b["start"]) + int(split["m_start"]), "end": int(b["start"]) + int(split["m_end"]) })
			i = int(b["close"]) + 1
		elif d["kind"] == "hook" or d["kind"] == "util":
			if plain:
				var hc := L.find_matching(src, int(d["body_open"]))
				i = (hc + 1) if hc != -1 else at + 1
			else:
				var h: Dictionary = Compiler._parse_hook_at(src, at, [])
				i = int(h["next"]) if h["ok"] else at + 1
		elif d["kind"] == "value":
			var ve: int = Compiler._value_end(src, int(d["value_start"]))
			i = ve if ve != -1 else at + 1
		elif d["kind"] == "export_list" or d["kind"] == "export_default":
			i = int(d["list_end"])
		elif d["kind"] == "module":
			var mb := _decl_body(src, at)
			if mb.is_empty():
				i = at + 1
				continue
			_collect_windows(src, int(mb["start"]), int(mb["close"]), out)
			i = int(mb["close"]) + 1
		else:
			break

## The `{`…matching-`}` body span of a decl at `at` (keyword-token-agnostic, params-aware) —
## mirrors formatGuitkx.ts declBody so both walks locate the same body.
## `markup_body`: true for "component" (its body mixes GDScript setup with a markup return -- G-01,
## see guitkx_lexer.gd find_matching_markup). false for "module" (its top-level content is a MIX of
## hook -- GDScript -- and component -- markup -- declarations, so it stays GDScript-lexis, same as
## guitkx.gd _compile_module).
func _decl_body(src: String, at: int, markup_body: bool = false) -> Dictionary:
	var n := src.length()
	var i := at
	while i < n and L._is_ident(src[i]):
		i += 1
	i = _skip_ws(src, i)
	while i < n and L._is_ident(src[i]):
		i += 1
	i = _skip_ws(src, i)
	if i < n and src[i] == "(":
		var pc := L.find_matching(src, i)
		if pc == -1:
			return {}
		i = _skip_ws(src, pc + 1)
	if i >= n or src[i] != "{":
		return {}
	var close := L.find_matching_markup(src, i) if markup_body else L.find_matching(src, i)
	if close == -1:
		return {}
	return { "start": i + 1, "close": close }

func _skip_ws(s: String, i: int) -> int:
	var n := s.length()
	while i < n and (s[i] == " " or s[i] == "\t" or s[i] == "\n" or s[i] == "\r"):
		i += 1
	return i
