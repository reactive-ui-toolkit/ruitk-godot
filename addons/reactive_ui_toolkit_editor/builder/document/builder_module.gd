@tool
class_name RuitkBuilderModule
extends RefCounted
## One module in the builder's tree: its text, where it currently sits on disk, and nothing
## else. NOTHING here touches disk -- the whole tree is projected at Save.
##
## A module is REMOVED from the tree to delete it. There is deliberately no pending-delete
## flag: intent kept in a list beside the data is what the shape this replaces did, and
## every consumer then had to join the two. The Unity leg catalogues five defects in two
## days from consumers that forgot the join, or from routes that bypassed it.
##
## Text is LF-normalized internally (the `.guitkx` pipeline is line-oriented and the
## formatter emits LF); the file's original EOL flavor is recorded so Save can write bytes
## matching what the file used before.
##
## GODOT NOTE. There is no domain reload here, so a module is an ordinary RefCounted that
## simply stays alive for the plugin's lifetime -- none of the Unity leg's serialization
## shuttle applies. What DOES apply is crash recovery: `to_dict`/`from_dict` round-trip the
## module through the reload journal, and that trip has to preserve the two facts a naive
## round-trip loses -- the stable id, and "has never been written".
##
## Cross-file references inside the builder go through preload CONSTS, never the global
## `class_name`s these files also declare. A global name resolves through the editor
## class cache, and `ProjectSettings.save()` rewrites that cache from whatever the
## running process happens to have loaded -- so a headless run of one suite can
## truncate it and leave the whole document layer unable to load in the next. A
## preload is a compile-time edge that nothing can invalidate. The `class_name`s stay,
## for consumers and for typing.

## A script cannot name its own `class_name` without the class cache either, so it preloads
## ITSELF -- the same compile-time edge, pointed at this file.
const Self = preload("res://addons/reactive_ui_toolkit_editor/builder/document/builder_module.gd")
const Paths = preload("res://addons/reactive_ui_toolkit_editor/builder/document/builder_paths.gd")

## What a module IS. The first three are FILE-level kinds, decided by the suffix and used
## by the document layer; the rest are DECLARATION-level and decided by parsing, used by
## the graph layer for badges. Keeping them in one enum is deliberate: a card shows one
## kind, and a value that could mean two things at different layers is how a badge and a
## suffix come to disagree about the same file.
enum Kind {
	COMPONENT,   ## a plain `.guitkx` -- the default, and what a file-level split yields
	HOOK,        ## a `.hooks.guitkx` companion
	STYLE,       ## a `.style.guitkx` companion
	UTIL,        ## declaration-level: a plain callable, neither component nor hook
	VALUE,       ## declaration-level: `name := ...` data
	MODULE,      ## declaration-level: the deprecated `module` wrapper
	UNKNOWN,     ## nothing classifiable -- an empty or unparseable buffer
}

## Stable identity, opaque, generated once. A module keeps this across every rename and
## move, so anything that refers to a module -- a ledger entry, a card position, a
## selection -- survives its path changing. The path is DERIVED; this is not.
var id: String = ""

## Folder the module lives in, `res://`-canonical. Authoritative and mutable: stored rather
## than derived from a parent link, because deriving it would want to MOVE every existing
## tree that does not follow the `name/name.guitkx` convention. Change it through
## `RuitkBuilderTree.move_to`, which carries the subtree.
var folder: String = ""

## Module name without suffix -- "showcase_page".
var name: String = ""

var kind: Kind = Kind.COMPONENT

## The live buffer. The only mutable content a module has.
var buffer_text: String = ""

## The text this module was last PROJECTED from -- written to disk, or read from it at
## load. Dirtiness is the difference between this and `buffer_text`, so it needs no flag to
## maintain.
var projected_text: String = ""

## Read-only policy: a module in the project's package directory (`res://addons/`) or
## outside `res://` can be read but never written.
var read_only: bool = false

## The EOL flavor of the file this came from, so a Save writes bytes matching what was
## there before.
var used_crlf: bool = false

## Where this module sits on disk RIGHT NOW, or "" when it has never been written.
## Never compared directly -- use `is_on_disk()`.
var disk_path: String = ""


func is_on_disk() -> bool:
	return not disk_path.is_empty()


## Where this module BELONGS -- derived from the model, every time, never stored. Save
## compares it against `disk_path`: they disagree exactly when the module has moved.
func file_path() -> String:
	if folder.is_empty() or name.is_empty():
		return ""
	return Paths.canon(folder.path_join(name + suffix_for(kind)))


func is_dirty() -> bool:
	return buffer_text != projected_text


## Moved since it was last projected: it has a file, and that file is not where the model
## says the module belongs.
func has_moved() -> bool:
	return is_on_disk() and not Paths.same(disk_path, file_path())


## A component owns the folder it is named after, and takes the folder with it when
## renamed. A COMPANION never does -- a style module beside its component shares that
## folder without owning it, and both report the same name once the `.style`/`.hooks`
## infix is off, so name equality alone would hand ownership to whichever was asked first.
func owns_folder() -> bool:
	if kind == Kind.STYLE or kind == Kind.HOOK:
		return false
	if folder.is_empty() or name.is_empty():
		return false
	return Paths.canon(folder).get_file().to_lower() == name.to_lower()


static func suffix_for(k: Kind) -> String:
	match k:
		Kind.STYLE:
			return Paths.SUFFIX_STYLE
		Kind.HOOK:
			return Paths.SUFFIX_HOOKS
		_:
			return Paths.SUFFIX_PLAIN


## A fresh opaque id. Godot has no GUID type; a 128-bit value rendered as hex is the same
## thing, seeded from the crypto RNG so two modules created in the same frame cannot collide.
static func new_id() -> String:
	var bytes := Crypto.new().generate_random_bytes(16)
	var out := ""
	for b in bytes:
		out += "%02x" % b
	return out


static func normalize_lf(text: String) -> String:
	return text.replace("\r\n", "\n").replace("\r", "\n")


## Splits a `.guitkx` file name into the name the model holds and the kind its suffix
## declares. SUFFIX-FIRST, exactly as the builder classifies everywhere else: a
## `.style.guitkx` is a style module whatever its contents say.
##
## A name with no `.guitkx` suffix keeps its whole file name -- the caller is naming
## something that is not a module yet, and inventing a truncation would lose text.
static func split_file_name(file_name: String) -> Dictionary:
	var P := Paths
	if P.ends_with_ci(file_name, P.SUFFIX_STYLE):
		return {
			"name": file_name.substr(0, file_name.length() - P.SUFFIX_STYLE.length()),
			"kind": Kind.STYLE,
		}
	if P.ends_with_ci(file_name, P.SUFFIX_HOOKS):
		return {
			"name": file_name.substr(0, file_name.length() - P.SUFFIX_HOOKS.length()),
			"kind": Kind.HOOK,
		}
	if P.ends_with_ci(file_name, P.SUFFIX_PLAIN):
		return {
			"name": file_name.substr(0, file_name.length() - P.SUFFIX_PLAIN.length()),
			"kind": Kind.COMPONENT,
		}
	return { "name": file_name, "kind": Kind.COMPONENT }


static func name_of(full_path: String) -> String:
	return str(split_file_name(Paths.canon(full_path).get_file())["name"])


static func kind_of(full_path: String) -> Kind:
	return split_file_name(Paths.canon(full_path).get_file())["kind"] as Kind


## Builds a module for a file, splitting its name and kind and recording the EOL flavor of
## the bytes it came from.
static func from_file(full_path: String, raw_text: String, is_read_only: bool) -> Self:
	var full := Paths.canon(full_path)
	var split := split_file_name(full.get_file())
	var lf := normalize_lf(raw_text)
	var m := Self.new()
	m.id = new_id()
	m.folder = full.get_base_dir()
	m.name = str(split["name"])
	m.kind = split["kind"] as Kind
	m.buffer_text = lf
	m.projected_text = lf
	m.disk_path = full
	m.read_only = is_read_only
	m.used_crlf = raw_text.contains("\r\n")
	return m


## Builds a module that exists only in memory. It is dirty from the moment it is made, and
## the first Save writes it.
static func fresh(in_folder: String, module_name: String, k: Kind, initial_text: String) -> Self:
	var m := Self.new()
	m.id = new_id()
	m.folder = Paths.canon(in_folder)
	m.name = module_name
	m.kind = k
	m.buffer_text = normalize_lf(initial_text)
	m.projected_text = ""
	m.disk_path = ""
	m.read_only = false
	m.used_crlf = false
	return m


## Replaces the buffer. Refused on read-only modules -- callers gate the UI, this is the
## last line of defense -- and refused on text carrying CR, because every buffer in the
## builder is LF-normalized. Returns true when the edit was taken.
##
## GDScript cannot throw, so a refusal is a false return plus a pushed error: the caller
## that ignores it still leaves a trace, and the buffer is never quietly corrupted.
func apply_edit(new_text_lf: String) -> bool:
	if read_only:
		push_error("[builder] '%s' is read-only -- the builder must not edit it." % file_path())
		return false
	if new_text_lf.contains("\r"):
		push_error("[builder] buffers are LF-normalized; '%s' was handed CR." % file_path())
		return false
	buffer_text = new_text_lf
	return true


## Records that the module now matches what is on disk at `projected_path` -- the one place
## both halves of "clean" are set, so they cannot drift apart.
func mark_projected(projected_path: String) -> void:
	projected_text = buffer_text
	disk_path = Paths.canon(projected_path)


## External change under a CLEAN module: adopt the new disk text so open cards never keep
## serving a stale buffer. The caller enforces the dirty policy -- unsaved edits are never
## clobbered. Returns true when the text actually changed.
func adopt_disk_text(raw_text: String) -> bool:
	var lf := normalize_lf(raw_text)
	used_crlf = raw_text.contains("\r\n")
	if lf == buffer_text:
		return false
	buffer_text = lf
	projected_text = lf
	return true


## The bytes Save writes: the buffer, re-flavored to the EOL the file used before.
func to_disk_text() -> String:
	return buffer_text.replace("\n", "\r\n") if used_crlf else buffer_text


# ── Journal round trip ───────────────────────────────────────────────────────────────

func to_dict() -> Dictionary:
	return {
		"id": id,
		"folder": folder,
		"name": name,
		"kind": int(kind),
		"buffer": buffer_text,
		"projected": projected_text,
		"read_only": read_only,
		"used_crlf": used_crlf,
		"disk_path": disk_path,
	}


## Rebuilds a module from the journal. Every field is read with an explicit default of the
## right TYPE: JSON has no int/enum distinction and `null` for a missing key would poison
## the typed field it lands in.
##
static func from_dict(d: Dictionary) -> Self:
	var m := Self.new()
	m.id = str(d.get("id", ""))
	if m.id.is_empty():
		m.id = new_id()
	m.folder = Paths.canon(str(d.get("folder", "")))
	m.name = str(d.get("name", ""))
	m.kind = int(d.get("kind", int(Kind.COMPONENT))) as Kind
	m.buffer_text = normalize_lf(str(d.get("buffer", "")))
	m.projected_text = normalize_lf(str(d.get("projected", "")))
	m.read_only = bool(d.get("read_only", false))
	m.used_crlf = bool(d.get("used_crlf", false))
	m.disk_path = Paths.canon(str(d.get("disk_path", "")))
	return m
