class_name RUIGuitkxMigrate
extends RefCounted
## The 0.10.0 import-migration CODEMOD (§M6). Rewrites every `.guitkx` in place so the tree satisfies
## strict cross-file resolution: (a) prefix `export ` onto EVERY top-level declaration (export-
## everything is the shipped default -- privacy is opt-in going forward), and (b) synthesize one
## `import { … } from "…"` line per OTHER file this one references. Idempotent + re-runnable, so an
## in-flight branch self-migrates on rebase. Pure/static + FileAccess-only (headless CI runner).
##
## Reference discovery is a FRESH source scan (never sidecar/edge-derived, which only record markup
## tags): every referenceable name = a top-level decl of ANOTHER `.guitkx` file; a name is imported
## when this file uses it as a markup tag (`<Name`) or a qualified reference (`Name.` / `Name(`).
## Hand-written `class_name` scripts (DoomTypes, …) and host/ClassDB elements are NOT `.guitkx` decls,
## so they are never in the referenceable set -- they stay ambient, import-free (rule 7).

const Compiler = preload("res://addons/reactive_ui_toolkit/guitkx/guitkx.gd")
const Config = preload("res://addons/reactive_ui_toolkit/guitkx/guitkx_config.gd")
const Resolve = preload("res://addons/reactive_ui_toolkit/guitkx/guitkx_resolve.gd")
const L = preload("res://addons/reactive_ui_toolkit/guitkx/guitkx_lexer.gd")

## Migrate every `.guitkx` under `root`. Returns { changed:[paths], scanned:int }.
static func migrate_all(root: String = "res://") -> Dictionary:
	var paths := _find_guitkx(root)
	var sources := {}
	var referenceable := {}   # decl name -> owning .guitkx path (the import universe)
	for p in paths:
		var src := FileAccess.get_file_as_string(p)
		sources[p] = src
		for dm in Compiler._enumerate_decls(src, 0):
			var nm := str(dm["name"])
			if nm != "" and not referenceable.has(nm):
				referenceable[nm] = p
	var changed: Array = []
	for p in paths:
		var res := migrate_source(p, str(sources[p]), referenceable)
		if res["changed"]:
			var f := FileAccess.open(p, FileAccess.WRITE)
			if f != null:
				f.store_string(str(res["source"]))
				f.close()
				changed.append(p)
	return { "changed": changed, "scanned": paths.size() }

## Compute the migrated source for one file (no write). `referenceable` = name -> owning path.
static func migrate_source(guitkx_path: String, src: String, referenceable: Dictionary) -> Dictionary:
	var decls := Compiler._enumerate_decls(src, 0)
	if decls.is_empty():
		return { "changed": false, "source": src }
	var own := {}
	for dm in decls:
		own[str(dm["name"])] = true
	# 1. Which OTHER files' names does this file reference?  target path -> sorted [names]
	# (the SAME canonical scan strict resolution uses, so the migrated tree is 2305-free by construction)
	var used := Resolve.referenced_names(src, referenceable, own)
	var already := {}
	for im in Compiler.scan_imports(src):
		for nm in (im["names"] as Array):
			already[str(nm["name"])] = true
		# `* as X` / default (and the combined forms') locals are bindings too -- without them a
		# default-imported component consumed as a tag would get a duplicate named import (2303).
		if str(im.get("ns", "")) != "":
			already[str(im["ns"])] = true
		if str(im.get("def", "")) != "":
			already[str(im["def"])] = true
	var by_file := {}
	for name in used:
		if already.has(name):
			continue   # idempotent: don't re-import an already-imported name
		var tp := str(referenceable[name])
		if not by_file.has(tp):
			by_file[tp] = []
		(by_file[tp] as Array).append(name)
	# 2. Build the new import lines (names sorted, targets sorted by specifier).
	var root := Config.root_for(guitkx_path)
	var import_lines: Array = []
	var specs := by_file.keys()
	specs.sort()
	for tp in specs:
		var names: Array = by_file[tp]
		names.sort()
		import_lines.append("import { %s } from \"%s\"" % [", ".join(names), _specifier(guitkx_path, str(tp), root)])
	import_lines.sort()
	# 3. Prefix `export ` on every not-yet-exported top-level decl (reverse order: offsets stay valid).
	var out := src
	for di in range(decls.size() - 1, -1, -1):
		var dm: Dictionary = decls[di]
		if not bool(dm["export"]):
			var at := int(dm["at"])   # the decl keyword (start == at when unexported)
			out = out.substr(0, at) + "export " + out.substr(at)
	# 4. Insert the import block at the first decl's start (after any @directives, before the decl).
	if not import_lines.is_empty():
		# Insert at the first decl's START (the `export` prefix when present, else the keyword), NOT its
		# keyword `at`. For an unexported decl start==at; for an ALREADY-exported first decl `at` points
		# PAST the existing `export `, so inserting there would split `export … component` into
		# `export import { … } … component` -- invalid + non-idempotent (BH-03). `start` is correct for
		# both, and step 3's reverse-order export insertions never move an earlier decl's start.
		var insert_at := int(decls[0]["start"])
		var block := "\n".join(import_lines) + "\n\n"
		out = out.substr(0, insert_at) + block + out.substr(insert_at)
	return { "changed": out != src, "source": out }

## Referenceable names actually USED in `src` (markup tag `<Name`, or qualified `Name.` / `Name(`),
## excluding this file's own decls. Lexer-aware: strings/comments are skipped.
static func _scan_references(src: String, referenceable: Dictionary, own: Dictionary) -> Dictionary:
	var out := {}
	var i := 0
	var n := src.length()
	while i < n:
		var k := L.skip_noncode(src, i)
		if k != i:
			i = k
			continue
		var c := src.unicode_at(i)
		if L._is_ident_code(c) and (c < 48 or c > 57) and (i == 0 or not L._is_ident_code(src.unicode_at(i - 1))):
			var s := i
			while i < n and L._is_ident_code(src.unicode_at(i)):
				i += 1
			var word := src.substr(s, i - s)
			if referenceable.has(word) and not own.has(word):
				var prev_lt := s > 0 and src[s - 1] == "<"
				var nxt := _next_nonspace(src, i)
				if prev_lt or nxt == "." or nxt == "(":
					out[word] = true
			continue
		i += 1
	return out

static func _next_nonspace(src: String, i: int) -> String:
	var n := src.length()
	while i < n and (src[i] == " " or src[i] == "\t"):
		i += 1
	return src[i] if i < n else ""

## The import specifier from `guitkx_path` to `target`: `./name` when siblings, else `~/`-rooted
## (root-relative, extensionless).
## Delegate to the compiler's CANONICAL specifier rule so the codemod can never write a specifier the
## resolver would resolve differently (or fail to resolve) -- the BH-13 path-boundary bug and the
## BH-14 out-of-root mis-rooting both lived in the old copy here.
static func _specifier(guitkx_path: String, target: String, root: String) -> String:
	return Compiler.import_specifier(guitkx_path, target, root)

static func _find_guitkx(root: String) -> Array:
	var out: Array = []
	_walk(root, out)
	out.sort()
	return out

static func _walk(dir: String, out: Array) -> void:
	if FileAccess.file_exists(dir.path_join(".gdignore")):
		return
	var d := DirAccess.open(dir)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if name != "." and name != "..":
			var p := dir.path_join(name)
			if d.current_is_dir():
				if not (name.begins_with(".") or name == "node_modules" or name.ends_with("~")):
					_walk(p, out)
			elif name.get_extension() == "guitkx":
				out.append(p)
		name = d.get_next()
	d.list_dir_end()


# ------------------------------------------------------------------------------------------------
# 0.11.0 ES-MODULES MODERNIZATION CODEMOD (plan M6). Pipeline per file: export-normalize + import
# insertion (the shipped 0.10.0 migrate_source, unchanged) -> hoist wrapper modules to top-level
# plain declarations (+ `@class_name M` so the binding/global identity survives -- the G-07 hatch
# doing exactly its job) -> rewrite the remaining `component`/`hook` wrapper keywords to plain
# E-01 declarations (components gain the `-> RUIVNode` annotation THAT IS the classification) ->
# flip importers of hoisted modules to `import * as M` when they consume M qualified (`M.x`).
# Idempotent + re-runnable: a plain-syntax tree reports 0 changed. Runner:
# dev/migrate_0_11_0.gd (always whole-project, like migrate_0_10_0.gd).
# ------------------------------------------------------------------------------------------------

## Modernize every `.guitkx` under `root`. Returns { changed:[paths], scanned:int }.
static func modernize_all(root: String = "res://") -> Dictionary:
	var paths := _find_guitkx(root)
	var sources := {}
	var referenceable := {}   # decl name -> owning path (the 0.10.0 import universe)
	var module_names := {}    # OLD wrapper-module name -> true (drives the importer flips)
	for p in paths:
		var src := FileAccess.get_file_as_string(p)
		sources[p] = src
		for dm in Compiler._enumerate_decls(src, 0):
			var nm := str(dm["name"])
			if nm != "" and not referenceable.has(nm):
				referenceable[nm] = p
			if str(dm["kind"]) == "module" and bool(dm.get("deprecated", false)):
				module_names[nm] = true
	var changed: Array = []
	for p in paths:
		var res := modernize_source(p, str(sources[p]), referenceable, module_names)
		if res["changed"]:
			var f := FileAccess.open(p, FileAccess.WRITE)
			if f != null:
				f.store_string(str(res["source"]))
				f.close()
				changed.append(p)
	return { "changed": changed, "scanned": paths.size() }

## Compute the modernized source for one file (no write). `module_names` = the OLD wrapper-module
## names across the whole tree (name -> true) -- imports of those flip to `* as` when consumed
## qualified. `referenceable` feeds the shipped 0.10.0 export/import pass.
static func modernize_source(guitkx_path: String, src: String, referenceable: Dictionary = {}, module_names: Dictionary = {}) -> Dictionary:
	# 1. export-normalize + import insertion: the SHIPPED 0.10.0 pass, unchanged (no-op on a
	# migrated tree).
	var out := src
	if not referenceable.is_empty():
		out = str(migrate_source(guitkx_path, out, referenceable)["source"])
	# 2. Hoist wrapper modules (reverse offset order; offsets stay valid).
	var rows := Compiler._enumerate_decls(out, 0)
	var hoisted_binding := ""   # first hoisted module's name -- the @class_name candidate
	for i in range(rows.size() - 1, -1, -1):
		var row: Dictionary = rows[i]
		if str(row["kind"]) != "module" or not bool(row.get("deprecated", false)):
			continue
		if hoisted_binding == "" or i == 0:
			hoisted_binding = str(row["name"])
		out = _hoist_module(out, row)
	# 2b. `@class_name M` so the file's binding/global identity stays the module's name (G-07),
	# inserted only when the file declares none.
	if hoisted_binding != "" and Resolve._class_name_override(out) == "":
		var first := Compiler._find_decl(out, 0)
		var ins := int(first.get("start", 0)) if str(first.get("kind", "")) != "" else 0
		out = out.substr(0, ins) + "@class_name %s\n\n" % hoisted_binding + out.substr(ins)
	# 3. Rewrite the remaining component/hook wrapper keywords (reverse order).
	rows = Compiler._enumerate_decls(out, 0)
	for i in range(rows.size() - 1, -1, -1):
		var row2: Dictionary = rows[i]
		if not bool(row2.get("deprecated", false)):
			continue
		if str(row2["kind"]) == "component":
			out = _rewrite_component_header(out, row2)
		elif str(row2["kind"]) == "hook":
			out = _rewrite_hook_header(out, row2)
	# 4. Flip imports of (other files') hoisted modules to `* as` when consumed qualified.
	for mn in module_names:
		out = _flip_module_import(out, str(mn))
	return { "changed": out != src, "source": out }

## Replace one wrapper `module M { members }` span with its members hoisted to top level:
## dedented ONE indent step, member order + interleaved `##` docs preserved, each member decl
## prefixed `export ` when the module itself was exported (member export = module export flag).
static func _hoist_module(src: String, row: Dictionary) -> String:
	var n := src.length()
	var at := int(row["at"])
	var j := at + 6
	j = Compiler._skip_ws_only(src, j)
	while j < n and L._is_ident_code(src.unicode_at(j)):
		j += 1
	j = Compiler._skip_ws_only(src, j)
	if j >= n or src[j] != "{":
		return src   # malformed -- leave for the compiler to diagnose
	var bclose := L.find_matching(src, j)
	if bclose == -1:
		return src
	var body := src.substr(j + 1, bclose - j - 1)
	var lines: Array = Array(body.split("\n"))
	while not lines.is_empty() and (lines[0] as String).strip_edges() == "":
		lines.pop_front()
	while not lines.is_empty() and (lines[-1] as String).strip_edges() == "":
		lines.pop_back()
	# One dedent step = the first non-blank line's leading whitespace (members sit exactly one
	# level in; interior lines carry it as a prefix).
	var ind := ""
	if not lines.is_empty():
		var l0 := lines[0] as String
		var k := 0
		while k < l0.length() and (l0[k] == " " or l0[k] == "\t"):
			k += 1
		ind = l0.substr(0, k)
	var out_lines: Array = []
	for l in lines:
		var s := l as String
		if ind != "" and s.begins_with(ind):
			s = s.substr(ind.length())
		out_lines.append(s)
	if bool(row.get("export", false)):
		for k2 in out_lines.size():
			var s2 := out_lines[k2] as String
			if s2.begins_with("component ") or s2.begins_with("hook "):
				out_lines[k2] = "export " + s2
	var replacement := "\n".join(out_lines)
	if not replacement.ends_with("\n"):
		replacement += "\n"
	return src.substr(0, int(row["start"])) + replacement + src.substr(int(row["next"]))

## `[export ]component X[(params)] {` -> `[export ]X(params) -> RUIVNode {` -- the annotation IS
## the E-01 classification; `()` is added when absent (formatter canon). Header whitespace
## normalizes; the body is untouched.
static func _rewrite_component_header(src: String, row: Dictionary) -> String:
	var n := src.length()
	var at := int(row["at"])
	var name := str(row["name"])
	var name_end := int(row["name_at"]) + name.length()
	var k := Compiler._skip_ws_only(src, name_end)
	var params_txt := "()"
	var after := name_end
	if k < n and src[k] == "(":
		var pc := L.find_matching(src, k)
		if pc == -1:
			return src
		params_txt = src.substr(k, pc - k + 1)
		after = pc + 1
	var j := Compiler._skip_ws_only(src, after)
	if j >= n or src[j] != "{":
		return src
	return src.substr(0, at) + "%s%s -> RUIVNode " % [name, params_txt] + src.substr(j)

## `[export ]hook use_x…` -> `[export ]use_x…` (keyword dropped; params/ret/body untouched).
static func _rewrite_hook_header(src: String, row: Dictionary) -> String:
	return src.substr(0, int(row["at"])) + src.substr(int(row["name_at"]))

## When this file imports `name` (an old wrapper module hoisted elsewhere) AND consumes it
## QUALIFIED (`name.member`), flip that clause to `import * as name from "spec"` -- the hoisted
## file's members are plain decls now, so the named form would 2302. Tag consumers keep the named
## form (the name then addresses a component decl directly). No-op when not imported/qualified.
static func _flip_module_import(src: String, name: String) -> String:
	if not _used_qualified(src, name):
		return src
	for im in Compiler.scan_imports(src):
		var names: Array = im.get("names", [])
		var hit := false
		var rest: Array = []
		for nm in names:
			if str((nm as Dictionary)["name"]) == name:
				hit = true
			else:
				var rn := str((nm as Dictionary).get("remote", (nm as Dictionary)["name"]))
				var ln := str((nm as Dictionary)["name"])
				rest.append(ln if rn == ln else "%s as %s" % [rn, ln])
		if not hit:
			continue
		var spec := str(im["spec"])
		var ns_line := "import * as %s from \"%s\"" % [name, spec]
		# A COMBINED clause (`import Def, { … } from`) must keep its default binding — rebuilding
		# only the named remnant would silently drop `Def` (the Unity formatter-drop lesson).
		var defn := str(im.get("def", ""))
		var def_prefix := "" if defn == "" else "%s, " % defn
		var repl := ns_line
		if not rest.is_empty():
			repl = "import %s{ %s } from \"%s\"\n%s" % [def_prefix, ", ".join(rest), spec, ns_line]
		elif defn != "":
			repl = "import %s from \"%s\"\n%s" % [defn, spec, ns_line]
		return src.substr(0, int(im["at"])) + repl + src.substr(int(im["end"]))
	return src

## True when `name` appears (outside imports/strings/comments) immediately followed by `.` --
## a qualified module-style consumer.
static func _used_qualified(src: String, name: String) -> bool:
	var i := 0
	var n := src.length()
	while i < n:
		var k := L.skip_noncode(src, i)
		if k != i:
			i = k
			continue
		if L.keyword_at(src, i, "import"):
			var le := src.find("\n", i)
			i = n if le == -1 else le
			continue
		if L.keyword_at(src, i, name):
			var j := i + name.length()
			while j < n and (src[j] == " " or src[j] == "\t"):
				j += 1
			if j < n and src[j] == ".":
				return true
			i = j
			continue
		i += 1
	return false
