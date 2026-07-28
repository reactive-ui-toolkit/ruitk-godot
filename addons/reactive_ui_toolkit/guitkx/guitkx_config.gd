class_name RUIGuitkxConfig
extends RefCounted
## `guitkx.config.json` discovery for the COMPILER (0.10.0 imports leg, §M3). Walk up from a file's
## folder to `res://`; the NEAREST config wins with NO merge — a formatter-only config in a subdir
## shadows an ancestor that set `root` (documented family behavior, A5g). This lives in the runtime
## addon (not the editor addon) because the compiler must resolve `~/` import/asset specifiers
## headlessly, with zero dependence on the editor plugin; the editor's GuitkxConfig + the TS loader
## delegate to the same rule so a project resolves identically everywhere.
##
## The new top-level key is `"root"` — the UI source root that `~/` specifiers resolve against
## (Godot default: `res://`). A value beginning with `res://` is used verbatim; any other value is
## taken relative to the config file's own directory.

const FILE_NAME := "guitkx.config.json"
const DEFAULT_ROOT := "res://"

## The `~/` root for the file at `path`: the nearest `guitkx.config.json`'s `"root"` (normalized to a
## `res://` directory, no trailing slash except the bare `res://`), else `res://`.
static func root_for(path: String) -> String:
	var found := _find_config(path)
	if found == "":
		return DEFAULT_ROOT
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(found))
	if not (parsed is Dictionary):
		return DEFAULT_ROOT
	var raw: Variant = (parsed as Dictionary).get("root", "")
	if not (raw is String) or (raw as String).is_empty():
		return DEFAULT_ROOT
	return _normalize_root(str(raw), found.get_base_dir())

## Absolute path of the nearest `guitkx.config.json` at/above `path`'s directory, or "" if none.
static func _find_config(path: String) -> String:
	var dir := path.get_base_dir()
	if dir.is_empty() or not dir.begins_with("res://"):
		dir = "res://"
	while true:
		var candidate := dir.path_join(FILE_NAME)
		if FileAccess.file_exists(candidate):
			return candidate
		if dir == "res://":
			break
		var parent := dir.get_base_dir()
		if parent == dir:
			break
		dir = parent
	return ""

## Fold a `"root"` value to a canonical `res://` directory with no trailing slash (bare `res://` kept).
static func _normalize_root(raw: String, config_dir: String) -> String:
	var r := raw
	if not r.begins_with("res://"):
		r = config_dir.path_join(r)
	r = r.simplify_path()
	if r != "res://" and r.ends_with("/"):
		r = r.trim_suffix("/")
	return r
