class_name RuitkGuitkxResolve
extends RefCounted
## Import RESOLUTION for the .guitkx compiler (0.10.0 imports leg, §M3). Turns a file's parsed
## preamble imports (from RuitkGuitkx._parse_import_at) into: (a) the lowering plan the emitter needs
## — component imports become `V.comp(path, func)` at their tag, value imports (hooks/modules) become
## `const Name = preload(path)[.Member]` header lines — and (b) the frozen family diagnostics
## GUITKX2300–2308 (§0.1). Pure/static + FileAccess-only, so it runs headlessly in the compiler and
## the build sweep. Specifiers are extensionless (`.guitkx` implied), relative (`./ ../`) or `~/`-
## rooted; engine-native `res:// uid://` are FORBIDDEN in import position (2300).
##
## The value-import graph (hook/module preload edges — NOT component edges, which stay lazy through
## V.comp) is where a load-order cycle can bite; value_cycle() finds one and prints the chain (2306).

const Compiler = preload("res://addons/reactive_ui_toolkit/guitkx/guitkx.gd")
const Config = preload("res://addons/reactive_ui_toolkit/guitkx/guitkx_config.gd")
const D = preload("res://addons/reactive_ui_toolkit/guitkx/guitkx_diag.gd")

## Resolve `spec` (an import specifier) relative to the importing `.guitkx` file `from_guitkx`, with
## `~/` bound to `root`. Returns { ok, guitkx: <res://…​.guitkx>, gd: <res://…​.gd>, error? }.
##
## `must_exist` false answers the PATH question alone -- the fold, the boundary check, the implied
## `.guitkx` extension -- without requiring a file to be there. Compilation always wants the default:
## an import naming nothing is GUITKX2300. The builder does not, because its modules live in memory
## until Save, and an import between two unsaved modules is perfectly well-formed. The alternative
## -- a second copy of the fold living in the builder -- is the drift this function exists to prevent.
static func resolve_specifier(spec: String, from_guitkx: String, root: String, must_exist: bool = true) -> Dictionary:
	if spec.begins_with("res://") or spec.begins_with("uid://"):
		return { "ok": false, "error": "engine-native path (use ./ ../ or ~/)" }
	var base := ""
	if spec.begins_with("~/"):
		base = root.path_join(spec.substr(2))
	elif spec.begins_with("./") or spec.begins_with("../"):
		base = from_guitkx.get_base_dir().path_join(spec)
	else:
		return { "ok": false, "error": "specifier must start with ./ ../ or ~/" }
	base = base.simplify_path()
	# A `../` chain (or a `~/` root) that climbs ABOVE res:// leaves a leading `res://../…` after
	# simplify_path -- the import crosses the project/module boundary (GUITKX2308). A legal path never
	# keeps a `..` segment. This is a distinct verdict from "no file" (2300): the target is out of
	# bounds regardless of whether a file happens to exist there.
	if base.begins_with("res://../") or base.begins_with("res://.."):
		return { "ok": false, "boundary": true, "guitkx": base, "error": "crosses the project boundary" }
	var guitkx_path := base if base.get_extension() == "guitkx" else base + ".guitkx"
	if must_exist and not FileAccess.file_exists(guitkx_path):
		return { "ok": false, "error": "no file at %s" % guitkx_path }
	return { "ok": true, "guitkx": guitkx_path, "gd": guitkx_path.get_basename() + ".gd" }

## The declaration table of a target `.guitkx`: { binding, default, decls: { name -> { kind,
## export, func } } }. `func` is the emitted static-func name a cross-file reference must call:
## `render` for the binding component, the decl name for any other component/hook/util (a value's
## `func` is its member name -- data, not callable), and the module name for a module (its
## preload member). `default` = the `export default` decl's name ("" when none -- E-07). Cached
## per source-hash so a sweep reads each target once.
static var _table_cache := {}
static func decl_table(guitkx_path: String) -> Dictionary:
	var src := FileAccess.get_file_as_string(guitkx_path)
	var key := guitkx_path + "#" + str(hash(src))
	if _table_cache.has(key):
		return _table_cache[key]
	var binding := binding_of(src)
	# analyzed_decls applies the E-07/E-09 export markers so list-exported / default-marked decls
	# read as exported here exactly as the emitter sees them (M1.3 single-source-of-truth).
	var analyzed := Compiler.analyzed_decls(src, 0)
	var decl_list: Array = analyzed["decls"]
	var render_comp := Compiler.render_component(decl_list, binding)   # the component that emits `render`
	var decls := {}
	for dm in decl_list:
		var nm := str(dm["name"])
		var kind := str(dm["kind"])
		var fn := "render" if (kind == "component" and nm == render_comp) else nm
		decls[nm] = { "kind": kind, "export": bool(dm["export"]), "func": fn }
	var out := { "binding": binding, "default": str(analyzed["default"]), "decls": decls }
	_table_cache[key] = out
	return out

## The binding name of a source (mirrors codegen._binding_name without the FileAccess round-trip):
## @class_name override, else first exported decl (marker-applied -- M1.3), else first decl, else "".
static func binding_of(src: String) -> String:
	var override := _class_name_override(src)
	if override != "":
		return override
	var decls: Array = Compiler.analyzed_decls(src, 0)["decls"]
	if decls.is_empty():
		return ""
	for dm in decls:
		if bool(dm["export"]):
			return str(dm["name"])
	return str(decls[0]["name"])

static func _class_name_override(src: String) -> String:
	var n := src.length()
	var i := 0
	# LAST `@class_name` wins, matching compile()'s preamble loop (which overwrites class_name_override
	# each time) and codegen._binding_name -- a scan that returned the FIRST would disagree with the
	# emitter on a (malformed) two-@class_name file (BH-17), mis-addressing every cross-file func.
	var override := ""
	while i < n:
		i = Compiler._skip_ws_and_comments(src, i)
		if i >= n:
			break
		if src.substr(i, 11) == "@class_name":
			var le := src.find("\n", i)
			if le == -1:
				le = n
			var raw := src.substr(i + 11, le - i - 11)
			var h := raw.find("#")
			if h != -1:
				raw = raw.substr(0, h)
			override = raw.strip_edges()
			i = le
			continue
		if Compiler.L.keyword_at(src, i, "import"):
			i = _skip_import(src, i)
			continue
		if src.substr(i, 4) == "@uss" or src.substr(i, 6) == "@theme":
			var le2 := src.find("\n", i)
			i = n if le2 == -1 else le2
			continue
		break
	return override

static func _skip_import(src: String, i: int) -> int:
	# Canonical full-form skip (named / `* as` / default / combined) — Compiler.import_end.
	return Compiler.import_end(src, i)

## Resolve every import of one file into the emitter's lowering plan + the frozen import diagnostics.
## `imports` = RuitkGuitkx.compile()'s parsed list; `used(name)->bool` reports whether a LOCAL name is
## referenced in the body (drives 2304 unused). Returns:
##   { comps: { local_name -> { gd, func } },     # component imports -> V.comp(gd, func)
##     values: [ { name, gd, member, kind } ],    # module + `* as` namespace -> const preloads
##     hooks:  [ { name, remote, gd } ],          # bare hooks -> aliased const + CALL rewrite (BH-06)
##     bares:  [ { name, remote, gd } ],          # named values/utils -> aliased const + FREE-REF rewrite
##     diags: [ … 2300-2304/2308/2326 … ] }
static func resolve_file_imports(imports: Array, from_guitkx: String, root: String, used: Callable = Callable()) -> Dictionary:
	var comps := {}
	var values: Array = []
	var hooks: Array = []
	var bares: Array = []
	var diags: Array = []
	var seen := {}   # LOCAL name -> spec (duplicate-import 2303, cross-line — the scan already caught same-line)
	for imp in imports:
		var spec := str(imp["spec"])
		var res := resolve_specifier(spec, from_guitkx, root)
		# 2308: a `~/` or `../` that climbs above res:// crosses the project/module boundary (checked
		# BEFORE the not-found 2300, since an out-of-bounds specifier is a boundary error regardless).
		if bool(res.get("boundary", false)):
			diags.append(D.make("GUITKX2308", D.ERROR, "import crosses a module/root boundary (%s -> %s) — imports are module-scoped in v1" % [from_guitkx, res["guitkx"]], int(imp["spec_at"]), spec.length() + 2))
			continue
		if not res["ok"]:
			diags.append(D.make("GUITKX2300", D.ERROR, "unknown import specifier `%s` — no file at %s" % [spec, spec], int(imp["spec_at"]), spec.length() + 2))
			continue
		var table := decl_table(str(res["guitkx"]))
		var decls: Dictionary = table["decls"]
		# NOTE: no exclusive branching below — a COMBINED import (`import Def, { a } from` /
		# `import Def, * as X from`) carries default + named/namespace parts in ONE declaration
		# and every part must yield its lowering (0.11.1 field wave; the LSP mirrors agree).
		# E-06 namespace form: ONE eager whole-script preload; members resolve as script statics at
		# runtime (`X.name`). A VALUE edge for 2306. No component tags via `X.` in v1.
		var nsn := str(imp.get("ns", ""))
		if nsn != "":
			var ns_at := int(imp.get("ns_at", int(imp["at"])))
			if seen.has(nsn):
				diags.append(D.make("GUITKX2303", D.ERROR, "duplicate import of `%s` (already imported from %s)" % [nsn, seen[nsn]], ns_at, nsn.length()))
			else:
				seen[nsn] = spec
				if used.is_valid() and not bool(used.call(nsn)):
					diags.append(D.make("GUITKX2304", D.ERROR, "unused import `%s`" % nsn, ns_at, nsn.length()))
				values.append({ "name": nsn, "gd": res["gd"], "member": "", "kind": "namespace" })
		# E-07 default form: binds the target's `export default` decl; lowers per that decl's KIND.
		var defn := str(imp.get("def", ""))
		if defn != "":
			var def_at := int(imp.get("def_at", int(imp["at"])))
			if seen.has(defn):
				diags.append(D.make("GUITKX2303", D.ERROR, "duplicate import of `%s` (already imported from %s)" % [defn, seen[defn]], def_at, defn.length()))
			else:
				seen[defn] = spec
				var tgt_default := str(table.get("default", ""))
				if tgt_default == "":
					diags.append(D.make("GUITKX2326", D.ERROR, "%s has no default export -- use a named import: import { %s } from \"%s\"" % [str(res["guitkx"]).get_file(), str(table["binding"]), spec], def_at, defn.length()))
				else:
					if used.is_valid() and not bool(used.call(defn)):
						diags.append(D.make("GUITKX2304", D.ERROR, "unused import `%s`" % defn, def_at, defn.length()))
					var dd: Dictionary = decls[tgt_default]
					match str(dd["kind"]):
						"component":
							comps[defn] = { "gd": res["gd"], "func": dd["func"] }
						"hook":
							hooks.append({ "name": defn, "remote": tgt_default, "gd": res["gd"], "at": def_at })
						"module":
							var dmember := "" if tgt_default == str(table["binding"]) else tgt_default
							values.append({ "name": defn, "gd": res["gd"], "member": dmember, "kind": "module" })
						_:
							bares.append({ "name": defn, "remote": tgt_default, "gd": res["gd"], "at": def_at })
		for nm_entry in (imp["names"] as Array):
			var nm := str(nm_entry["name"])                        # LOCAL binding name
			var remote := str(nm_entry.get("remote", nm))           # exported name it resolves against (E-08)
			var at := int(nm_entry["at"])
			var remote_at := int(nm_entry.get("remote_at", at))
			if seen.has(nm):
				diags.append(D.make("GUITKX2303", D.ERROR, "duplicate import of `%s` (already imported from %s)" % [nm, seen[nm]], at, nm.length()))
				continue
			seen[nm] = spec
			# 2301/2302 validate the REMOTE name (the one the target must declare/export), anchored
			# on its own offset -- for `a as b` the squiggle lands on `a` (E-08).
			if not decls.has(remote):
				diags.append(D.make("GUITKX2302", D.ERROR, "`%s` is not declared in %s" % [remote, res["guitkx"]], remote_at, remote.length()))
				continue
			var d: Dictionary = decls[remote]
			if not bool(d["export"]):
				diags.append(D.make("GUITKX2301", D.ERROR, "`%s` is not exported by %s — add `export` to its declaration" % [remote, res["guitkx"]], remote_at, remote.length()))
				continue
			# 2304: imported but never referenced in the body (by its LOCAL name).
			if used.is_valid() and not bool(used.call(nm)):
				diags.append(D.make("GUITKX2304", D.ERROR, "unused import `%s`" % nm, at, nm.length()))
			match str(d["kind"]):
				"component":
					comps[nm] = { "gd": res["gd"], "func": d["func"] }
				"hook":
					# a top-level hook is a static func, called bare -- aliased const + call rewrite.
					hooks.append({ "name": nm, "remote": remote, "gd": res["gd"], "at": at })
				"module":
					# module -> a value preload used as `Name.member(...)`. A binding member (the file's
					# own name) is the whole script; a non-binding module member is an inner class on it.
					var member := "" if remote == str(table["binding"]) else remote
					values.append({ "name": nm, "gd": res["gd"], "member": member, "kind": d["kind"] })
				_:
					# value/util (E-05): data / plain static func -- aliased const + free-ref rewrite
					# (a `const local = preload(gd).static_var` is NOT a constant expression).
					bares.append({ "name": nm, "remote": remote, "gd": res["gd"], "at": at })
	return { "comps": comps, "values": values, "hooks": hooks, "bares": bares, "diags": diags }

## Names from `referenceable` (name -> anything) actually USED in `src` as a markup tag (`<Name`) or
## a qualified reference (`Name.` / `Name(`), excluding this file's own decls, mapped to the offset of
## the FIRST such use. The CANONICAL cross-file reference scan -- shared by the codemod (which iterates
## the keys) and strict resolution (which uses the offset to anchor GUITKX2305 precisely, instead of a
## naive source.find that lands on a comment/substring -- BH-18) -- so the two can never disagree.
static func referenced_names(src: String, referenceable: Dictionary, own: Dictionary) -> Dictionary:
	var out := {}
	var i := 0
	var n := src.length()
	while i < n:
		var k := Compiler.L.skip_noncode(src, i)
		if k != i:
			i = k
			continue
		var c := src.unicode_at(i)
		if Compiler.L._is_ident_code(c) and (c < 48 or c > 57) and (i == 0 or not Compiler.L._is_ident_code(src.unicode_at(i - 1))):
			var s := i
			while i < n and Compiler.L._is_ident_code(src.unicode_at(i)):
				i += 1
			var word := src.substr(s, i - s)
			if referenceable.has(word) and not own.has(word):
				# A DOT-PRECEDED identifier is a member access (`X.entries(`): a use of the
				# QUALIFIER X, never a free reference to `entries` -- without this guard, hoisted
				# module members (top-level decls since 0.11.0) got spuriously self-imported by
				# the codemod on its second run (found by the modernize idempotency gate).
				var pb := s - 1
				while pb >= 0 and (src[pb] == " " or src[pb] == "\t"):
					pb -= 1
				var dotted := pb >= 0 and src[pb] == "."
				var prev_lt := s > 0 and src[s - 1] == "<"
				var j := i
				while j < n and (src[j] == " " or src[j] == "\t"):
					j += 1
				var nxt := src[j] if j < n else ""
				if not dotted and (prev_lt or nxt == "." or nxt == "("):
					if not out.has(word):
						out[word] = (s - 1) if prev_lt else s   # anchor a tag on `<`, a qualified ref on the name
			continue
		i += 1
	return out

## Detect a VALUE-import cycle (hook/module preload edges only; component edges are lazy V.comp and
## exempt). `edges(guitkx_path) -> Array[guitkx_path]` yields a file's value-import targets. Returns
## the cycle chain as `a.guitkx -> b.guitkx -> a.guitkx` (files basenames), or "" if acyclic.
static func value_cycle(start_guitkx: String, edges: Callable) -> String:
	var stack: Array = []
	var on_stack := {}
	var visited := {}
	var found := [""]
	_dfs_cycle(start_guitkx, edges, stack, on_stack, visited, found)
	return found[0]

static func _dfs_cycle(node: String, edges: Callable, stack: Array, on_stack: Dictionary, visited: Dictionary, found: Array) -> void:
	if found[0] != "":
		return
	stack.push_back(node)
	on_stack[node] = true
	for nxt in (edges.call(node) as Array):
		if found[0] != "":
			break
		if on_stack.has(nxt):
			var idx := stack.find(nxt)
			var chain: Array = []
			for k in range(idx, stack.size()):
				chain.append(str(stack[k]).get_file())
			chain.append(str(nxt).get_file())
			found[0] = " -> ".join(chain)
			break
		if not visited.has(nxt):
			_dfs_cycle(nxt, edges, stack, on_stack, visited, found)
	stack.pop_back()
	on_stack.erase(node)
	visited[node] = true
