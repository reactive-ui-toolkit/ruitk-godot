@tool
class_name RuitkBuilderSpecifiers
extends RefCounted
## The two directions of an import specifier, kept together because they are only correct
## as a PAIR: whatever `relative` writes, `map` has to read back to the same file. A move
## re-spells every specifier it invalidated, so a disagreement between these two would not
## produce one bad import -- it would silently rewrite every import in the tree to something
## that no longer resolves.
##
## Both directions DELEGATE to the compiler's own canonical pair --
## `RuitkGuitkx.import_specifier` and `RuitkGuitkxResolve.resolve_specifier` -- rather than
## doing path arithmetic of their own. That is the whole point: the builder writes exactly
## the specifier the compiler would, including the `~/` root form, so a builder-authored
## import is indistinguishable from a hand-written one and cannot drift from the resolver
## as the language moves.
##
## Cross-file references inside the builder go through preload CONSTS, never the global
## `class_name`s these files also declare. A global name resolves through the editor
## class cache, and `ProjectSettings.save()` rewrites that cache from whatever the
## running process happens to have loaded -- so a headless run of one suite can
## truncate it and leave the whole document layer unable to load in the next. A
## preload is a compile-time edge that nothing can invalidate. The `class_name`s stay,
## for consumers and for typing.

const Paths = preload("res://addons/reactive_ui_toolkit_editor/builder/document/builder_paths.gd")

const Compiler = preload("res://addons/reactive_ui_toolkit/guitkx/guitkx.gd")
const Resolve = preload("res://addons/reactive_ui_toolkit/guitkx/guitkx_resolve.gd")
const Config = preload("res://addons/reactive_ui_toolkit/guitkx/guitkx_config.gd")


## The `~/` root a file's specifiers resolve against -- the nearest `guitkx.config.json`'s
## `"root"`, else `res://`. Asked of the FILE, never cached on the builder: two trees in one
## project can sit under different configs, and a root captured once would spell every
## specifier in the second of them against the first one's root.
static func root_for(from_file: String) -> String:
	return Config.root_for(Paths.canon(from_file))


## The absolute path a specifier names, with NO check that anything is there. The ONE place
## in the builder that turns an import into a path -- the preview compiler orders its
## compiles with the same answer the canvas draws its edges from.
##
## Existence is deliberately not asked: a module lives in memory until Save, so an import
## between two unsaved modules names a real target that no file backs yet, and refusing it
## would leave the canvas unable to draw the edge the user just made. "" only when the
## specifier is malformed or crosses the project boundary.
static func map(from_file: String, specifier: String) -> String:
	var from := Paths.canon(from_file)
	if from.is_empty() or specifier.is_empty():
		return ""
	var res := Resolve.resolve_specifier(specifier, from, root_for(from), false)
	if not bool(res.get("ok", false)):
		return ""
	return Paths.canon(str(res.get("guitkx", "")))


## The specifier an importer in `from_folder` has to write to reach `target_path`.
##
## The compiler's rule, verbatim: same directory spells `./name`, a target under the `~/`
## root spells `~/<root-relative>`, anything else spells a `../` relative path. "" when
## either end is missing.
static func relative(from_folder: String, target_path: String) -> String:
	var folder := Paths.canon(from_folder)
	var target := Paths.canon(target_path)
	if folder.is_empty() or target.is_empty():
		return ""
	# `import_specifier` reads only the importer's DIRECTORY, so the file name here is a
	# stand-in that never reaches the result -- but it has to be a `.guitkx` path for the
	# `~/` boundary test to fold the same way it will for the real importer.
	var from_file := folder.path_join("__importer__" + Paths.SUFFIX_PLAIN)
	return Compiler.import_specifier(from_file, target, root_for(from_file))


## Every import in `source`, as { spec, spec_at, line, at, end } with `line` 1-based.
##
## Keyed by LINE downstream rather than by the specifier text: a rename edits specifier text
## in place before the move happens, so a snapshot keyed on that text could no longer find
## its own entries afterwards. A line survives an edit within it.
static func imports_of(source: String) -> Array:
	var out: Array = []
	for imp in Compiler.scan_imports(source):
		var spec := str(imp.get("spec", ""))
		# `@`-prefixed specifiers name engine-side things, not files in the tree.
		if spec.is_empty() or spec.begins_with("@"):
			continue
		var spec_at := int(imp.get("spec_at", -1))
		if spec_at < 0:
			continue
		out.append({
			"spec": spec,
			"spec_at": spec_at,
			"line": line_of(source, spec_at),
			"at": int(imp.get("at", spec_at)),
			"end": int(imp.get("end", spec_at)),
		})
	return out


## The 1-based line an offset falls on.
##
static func line_of(source: String, offset: int) -> int:
	if offset <= 0:
		return 1
	return source.substr(0, mini(offset, source.length())).count("\n") + 1
