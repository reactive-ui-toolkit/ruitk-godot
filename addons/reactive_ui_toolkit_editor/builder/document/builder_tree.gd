@tool
class_name RuitkBuilderTree
extends RefCounted
## The builder's data structure: every module of one tree, held in memory, with disk as a
## projection computed at Save.
##
## Load reads the tree once. Every manipulation -- create, delete, rename, move, edit --
## happens here. Rendering reads from here. Save walks it and writes. Nothing else consults
## the filesystem while editing, so what the canvas shows no longer depends on which files
## happen to be open.
##
## DELETION IS ABSENCE. A module is removed from `modules` and that is the whole of it.
## `last_projection` remembers what was on disk, so Save can tell that a file is now
## orphaned and trash it. The shape this replaces kept intent in lists BESIDE the data --
## pending deletes, pending folder moves -- and every consumer had to join the two.
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
const Self = preload("res://addons/reactive_ui_toolkit_editor/builder/document/builder_tree.gd")
const Paths = preload("res://addons/reactive_ui_toolkit_editor/builder/document/builder_paths.gd")
const Module = preload("res://addons/reactive_ui_toolkit_editor/builder/document/builder_module.gd")

var _modules: Array[Module] = []

## The paths that were on disk as of the last load or save. The one piece of state that
## makes Save a diff rather than a set of remembered intents: anything in here that no
## module claims any more has been deleted, whatever route it left the tree by.
var _last_projection: PackedStringArray = PackedStringArray()

var _by_id := {}
var _by_path := {}
var _indexed := false


func modules() -> Array[Module]:
	return _modules


func last_projection() -> PackedStringArray:
	return _last_projection


# ── Lookup ───────────────────────────────────────────────────────────────────────────

func by_id(module_id: String) -> Module:
	if module_id.is_empty():
		return null
	_ensure_indexes()
	return _by_id.get(module_id, null)


## Lookup by path. An empty or unknown path is NOT FOUND, never an error: an empty tree has
## no focus, and asking about nothing should answer nothing.
func by_path(path: String) -> Module:
	var k := Paths.key(path)
	if k.is_empty():
		return null
	_ensure_indexes()
	return _by_path.get(k, null)


func contains(path: String) -> bool:
	return by_path(path) != null


# ── Mutation ─────────────────────────────────────────────────────────────────────────

func add(module: Module) -> Module:
	if module == null:
		return null
	if module.id.is_empty():
		module.id = Module.new_id()
	_modules.append(module)
	_reindex()
	return module


## Removes a module. THIS is what deleting means -- there is no mark, so nothing downstream
## has to filter and nothing can disagree about whether the module is present. Save notices
## the orphaned file through `last_projection`.
func remove(module: Module) -> bool:
	if module == null:
		return false
	var at := _modules.find(module)
	if at == -1:
		return false
	_modules.remove_at(at)
	_reindex()
	return true


func remove_by_path(path: String) -> bool:
	return remove(by_path(path))


## Re-files a module and, when it owns its folder, everything inside that folder with it.
## The subtree moves because the FOLDER moves: every module keeps its position relative to
## the folder, so every relative import inside it stays correct without being touched.
##
## "Inside" means IN the folder as well as under it. Carrying only the nested case leaves a
## component's own companions -- the style and hook modules beside it, which are the whole
## reason the folder exists -- at a path their folder has vacated.
## Returns false when the move was REFUSED, which happens when another module already derives the
## destination path.
##
## The guard lives HERE rather than in each caller, because two modules claiming one path is a
## state the model must not be able to enter: `_reindex` keys `_by_path` by derived path, so the
## second arrival silently displaces the first in the index while both stay in `_modules` -- and
## Save then writes one over the other. The canvas drop, the folder-pane drop, the card menu and
## every future caller get the refusal for free.
func move_to(module: Module, new_folder: String, new_name: String) -> bool:
	if module == null:
		return false
	var destination := Paths.canon(new_folder).path_join(
		new_name + Module.suffix_for(module.kind))
	var resident := by_path(destination)
	if resident != null and resident != module:
		return false
	var old_folder := module.folder
	var owns := module.owns_folder()
	var target := Paths.canon(new_folder)

	module.folder = target
	module.name = new_name

	if owns and not old_folder.is_empty():
		var old_canon := Paths.canon(old_folder)
		var from := old_canon.to_lower()
		var prefix := from + "/"
		for other in _modules:
			if other == module or other.folder.is_empty():
				continue
			var f := Paths.key(other.folder)
			if f == from:
				other.folder = target
				continue
			if not f.begins_with(prefix):
				continue
			# Re-root on the ORIGINAL spelling, not the case-folded key: the tail carries
			# the child's own folder names, and lower-casing them would rename every
			# nested folder on a case-sensitive filesystem.
			var tail := Paths.canon(other.folder).substr(old_canon.length() + 1)
			other.folder = Paths.canon(target.path_join(tail))
	_reindex()
	return true


## Replaces the whole contents -- used by load, and by abort, which is load re-run.
## `projection` is what was on disk at that moment.
func reset(new_modules: Array, projection: PackedStringArray) -> void:
	_modules.clear()
	for module in new_modules:
		# `is`, not `as`: casting a non-Object with `as` is a runtime error rather than a
		# null, so the type test has to come first. The list is untyped because it arrives
		# from the loader and from the journal, and the journal's contents are a file.
		if not (module is Module):
			continue
		var m: Module = module
		if m.id.is_empty():
			m.id = Module.new_id()
		_modules.append(m)
	set_projection(projection)
	_reindex()


## Records the projection Save just performed: every path a module now occupies. What it no
## longer contains is what Save deleted.
func set_projection(paths: PackedStringArray) -> void:
	_last_projection = PackedStringArray()
	var seen := {}
	for path in paths:
		var c := Paths.canon(path)
		if c.is_empty():
			continue
		var k := c.to_lower()
		if seen.has(k):
			continue
		seen[k] = true
		_last_projection.append(c)


## Paths that WERE on disk and no longer belong to any module -- the files Save has to
## remove. Computed, never accumulated, so it cannot drift from the tree.
func orphaned_paths() -> PackedStringArray:
	var claimed := {}
	for module in _modules:
		if module.is_on_disk():
			claimed[Paths.key(module.disk_path)] = true
	var orphans := PackedStringArray()
	for path in _last_projection:
		if not claimed.has(Paths.key(path)):
			orphans.append(path)
	return orphans


func has_unsaved_work() -> bool:
	if not orphaned_paths().is_empty():
		return true
	for module in _modules:
		if module.read_only:
			continue
		if module.is_dirty() or not module.is_on_disk() or module.has_moved():
			return true
	return false


# ── Indexes ──────────────────────────────────────────────────────────────────────────

func _ensure_indexes() -> void:
	if _indexed:
		return
	_reindex()


func _reindex() -> void:
	_by_id = {}
	_by_path = {}
	for module in _modules:
		if module == null:
			continue
		if module.id.is_empty():
			module.id = Module.new_id()
		_by_id[module.id] = module
		var k := Paths.key(module.file_path())
		if not k.is_empty():
			_by_path[k] = module
	_indexed = true


# ── Self-check ───────────────────────────────────────────────────────────────────────

## Asserts the invariants a bad round trip could break, and says so loudly when one has.
## The point is not the check: it is that a broken tree announces itself WHERE IT HAPPENS,
## instead of surfacing later as an inexplicable bug in something that trusted it. Returns
## the problems found; empty means healthy.
func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	_ensure_indexes()

	var seen_ids := {}
	var seen_paths := {}
	for module in _modules:
		if module == null:
			problems.append("a null module survived the round trip")
			continue
		if module.id.is_empty():
			problems.append("module at %s lost its id" % module.file_path())
		elif seen_ids.has(module.id):
			problems.append("duplicate module id %s" % module.id)
		else:
			seen_ids[module.id] = true

		var k := Paths.key(module.file_path())
		if k.is_empty():
			problems.append("module %s has no derivable path" % module.id)
		elif seen_paths.has(k):
			problems.append("two modules claim %s" % module.file_path())
		else:
			seen_paths[k] = true

	if _by_id.size() != seen_ids.size() or _by_path.size() != seen_paths.size():
		problems.append("the indexes disagree with the module list")
	return problems


# ── Journal round trip ───────────────────────────────────────────────────────────────

## The tree as plain data, for the crash-recovery journal.
##
## The projection travels WITH the modules. Without it a restored tree has forgotten what
## was on disk, so every file the crashed session had deleted comes back un-orphaned and the
## next Save leaves them all in place -- a delete silently undone by a crash.
func to_dict() -> Dictionary:
	var out: Array = []
	for module in _modules:
		out.append(module.to_dict())
	return { "modules": out, "projection": Array(_last_projection) }


static func from_dict(d: Dictionary) -> Self:
	var t := Self.new()
	var restored: Array[Module] = []
	for raw in (d.get("modules", []) as Array):
		if raw is Dictionary:
			restored.append(Module.from_dict(raw))
	var projection := PackedStringArray()
	for path in (d.get("projection", []) as Array):
		projection.append(str(path))
	t.reset(restored, projection)
	return t


# ── Where a tree starts ──────────────────────────────────────────────────────────────

## The tree root decided from the MODULES rather than from disk.
##
## The filesystem answer is wrong for a tree that has never been saved: nothing exists yet,
## so the walk stops at the first folder and the root is wherever the FOCUS happens to be.
## Creating a nested component then moves the focus deeper, moves the root with it, and
## re-keys the whole saved layout -- which is the canvas rearranging itself for no reason
## the user could see.
static func resolve_root_from(module_list: Array, focus_path: String) -> String:
	return _resolve_root_core(focus_path, func(folder: String) -> bool:
		var wanted := Paths.key(folder)
		for module in module_list:
			var m := module as Module
			if m != null and m.owns_folder() and Paths.key(m.folder) == wanted:
				return true
		return false)


## The same walk, answered from DISK. Used by the loader, which runs before there is a tree
## to ask.
static func resolve_root(focus_path: String) -> String:
	return _resolve_root_core(focus_path, func(folder: String) -> bool:
		var f := Paths.canon(folder)
		return FileAccess.file_exists(f.path_join(f.get_file() + Paths.SUFFIX_PLAIN)))


## Climbs to the outermost folder of the tree the focus belongs to. `owns_a_module` answers
## "is there a component named after this folder" -- the one question the walk asks, and
## the only thing that differs between asking the tree and asking the disk.
##
static func _resolve_root_core(focus_path: String, owns_a_module: Callable) -> String:
	var focus := Paths.canon(focus_path)
	if focus.is_empty():
		return ""
	var dir := focus.get_base_dir()
	if dir.is_empty() or dir == "res://" or not dir.begins_with("res://"):
		return dir

	while true:
		var parent := dir.get_base_dir()
		if parent.is_empty() or parent == dir:
			break
		# `components` is a nesting level ONLY where it is the house layout -- a folder
		# named `components` INSIDE a component that owns it. The name alone is not
		# enough: a project may well keep unrelated trees under a shared `components/`,
		# and matching on the name climbs straight past the real root and loads all of
		# them into one canvas.
		if parent.get_file().to_lower() == Paths.COMPONENTS_FOLDER:
			var grand := parent.get_base_dir()
			if not grand.is_empty() and grand != parent and owns_a_module.call(grand):
				dir = grand
				continue
		# A folder that owns a module named after itself is still inside the tree, so
		# keep climbing.
		if parent != "res://" and owns_a_module.call(parent):
			dir = parent
			continue
		break
	return dir
