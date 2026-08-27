@tool
class_name RuitkBuilderPaths
extends RefCounted
## Path arithmetic for the builder's document layer, in ONE place.
##
## Every path the builder holds is a `res://` path in canonical form: forward slashes, no
## `.`/`..` segments, no trailing slash. `canon` is the only way in, so no call site can
## invent a second spelling of the same file -- which is what a path-keyed index cannot
## survive (two spellings of one file are two modules, and the second silently shadows the
## first in the index while both claim the same bytes on disk).
##
## Godot's own path helpers are the primitives (`simplify_path`, `path_join`, `get_base_dir`,
## `get_file`); this file adds only the folding rules the model needs and the comparison
## discipline. Comparisons are CASE-INSENSITIVE because the filesystems this ships on
## (NTFS, APFS by default) are: `res://UI/Panel.guitkx` and `res://ui/panel.guitkx` are one
## file, and treating them as two produces exactly the duplicate-module hazard above.

## `.guitkx` companion suffixes, longest first -- the order `split_file_name` must test in.
const SUFFIX_STYLE := ".style.guitkx"
const SUFFIX_HOOKS := ".hooks.guitkx"
const SUFFIX_PLAIN := ".guitkx"

## The folder name that nests child components inside a component that owns its folder.
## A level of the house layout, not a rule the compiler knows -- see `RuitkBuilderTree`.
const COMPONENTS_FOLDER := "components"


## The canonical spelling of `path`. "" for anything unusable, so callers test length
## rather than null.
##
## A path outside `res://` is folded back in when it names something inside the project
## (an absolute OS path handed over by a file dialog); one that genuinely lies outside is
## returned simplified but otherwise untouched, so the read-only policy can still see it
## for what it is.
static func canon(path: String) -> String:
	if path.is_empty():
		return ""
	var p := path.replace("\\", "/")
	if not p.begins_with("res://") and not p.begins_with("user://"):
		var localized := ProjectSettings.localize_path(p)
		if localized.begins_with("res://"):
			p = localized
	p = p.simplify_path()
	# A trailing slash is noise on a folder, but it is STRUCTURE on a scheme root: trimming
	# `user://` leaves `user:/`, which names nothing and compares equal to nothing.
	if p.ends_with("/") and not p.ends_with("://"):
		p = p.trim_suffix("/")
	return p


## Whether two paths name the same file. The ONE comparison -- never `==` on raw strings.
static func same(a: String, b: String) -> bool:
	return canon(a).to_lower() == canon(b).to_lower()


## The dictionary key for a path: canonical and case-folded, so an index cannot hold two
## entries for one file.
static func key(path: String) -> String:
	return canon(path).to_lower()


## Whether `path` is at, or under, `folder`. PATH-BOUNDARY matched: `res://ui2/x` is not
## under `res://ui`, which a plain `begins_with` would say it was.
static func is_under(path: String, folder: String) -> bool:
	var p := key(path)
	var f := key(folder)
	if f.is_empty() or p.is_empty():
		return false
	if p == f:
		return true
	var prefix := f if f.ends_with("/") else f + "/"
	return p.begins_with(prefix)


## Whether `folder` is a `res://` location the builder may write to. Everything outside the
## project is off limits; `res://addons/` is the project's package directory -- installed
## content, the Godot analogue of Unity's non-embedded packages -- and is read-only.
static func is_writable_location(path: String) -> bool:
	var p := key(path)
	if not p.begins_with("res://"):
		return false
	return not p.begins_with("res://addons/")


## Case-insensitive suffix test, for the same reason `same` folds case: the filesystems
## this ships on do not distinguish `.Style.guitkx` from `.style.guitkx`.
static func ends_with_ci(text: String, suffix: String) -> bool:
	return text.length() >= suffix.length() and text.to_lower().ends_with(suffix)


## The sibling files a `.guitkx` owns, and that therefore have to travel with it: the UID
## sidecar the editor writes for the imported resource, the compiler's diagnostics sidecar,
## the generated GDScript, and that script's own UID sidecar.
##
## Godot has no asset database to keep a move coherent, so the builder keeps it: a rename
## that moved only the `.guitkx` would leave the generated `.gd` at the old path, still
## carrying its `class_name` and still resolving from every `uid://` in every scene that
## referenced it -- a working reference to a script the source no longer produces.
static func companion_artifacts(guitkx_path: String) -> PackedStringArray:
	var p := canon(guitkx_path)
	if p.is_empty():
		return PackedStringArray()
	var base := p.get_basename()
	return PackedStringArray([
		p + ".uid",
		p + ".diags.json",
		base + ".gd",
		base + ".gd.uid",
	])
