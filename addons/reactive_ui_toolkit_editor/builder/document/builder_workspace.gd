@tool
class_name RuitkBuilderWorkspace
extends RefCounted
## The builder's document layer for one open tree: it owns the `RuitkBuilderTree`, loads it,
## and projects it back to disk at Save.
##
## Owns the save-only disk contract: during editing nothing here writes. Save walks the tree
## once and batches every write, then asks the editor to rescan for the batch.
##
## The shape this replaces kept a flat, path-keyed session store plus two side lists of
## INTENT -- pending deletes and pending folder moves -- and every consumer had to join the
## data against them. Delete now means the module is gone from the tree, and Save works out
## what that implies by diffing against the paths that were on disk last time.
##
## GODOT NOTE. There is no asset database here, so keeping a move coherent is this file's
## job: a `.guitkx` travels with its UID sidecar, its diagnostics sidecar, the generated
## `.gd` and that script's own UID sidecar (`RuitkBuilderPaths.companion_artifacts`).
## Everything below uses only `FileAccess`/`DirAccess`/`OS`, all of which work headlessly --
## the editor-only half (rescanning the filesystem dock) is an injected callable, so the
## whole save/abort matrix is testable without an editor.
##
## Cross-file references inside the builder go through preload CONSTS, never the global
## `class_name`s these files also declare. A global name resolves through the editor
## class cache, and `ProjectSettings.save()` rewrites that cache from whatever the
## running process happens to have loaded -- so a headless run of one suite can
## truncate it and leave the whole document layer unable to load in the next. A
## preload is a compile-time edge that nothing can invalidate. The `class_name`s stay,
## for consumers and for typing.

const Paths = preload("res://addons/reactive_ui_toolkit_editor/builder/document/builder_paths.gd")
const Module = preload("res://addons/reactive_ui_toolkit_editor/builder/document/builder_module.gd")
const BuilderTree = preload("res://addons/reactive_ui_toolkit_editor/builder/document/builder_tree.gd")
const Specifiers = preload("res://addons/reactive_ui_toolkit_editor/builder/document/builder_specifiers.gd")

signal changed

var _tree := BuilderTree.new()

## Asked to rescan after a batch of writes. The plugin wires this to the editor's
## filesystem; a headless run leaves it unset and nothing tries to reach an editor that
## is not there.
var rescan := Callable()

## How a retired file leaves the project, as `(path) -> bool`. Unset means the real thing:
## the platform trash, falling back to a plain remove where there is none. It is a seam
## because the save matrix has to be provable headlessly, and a suite that exercised the
## real trash would fill the machine's recycle bin with fixtures on every run.
var trash_file := Callable()


func tree() -> BuilderTree:
	return _tree


func modules() -> Array[Module]:
	return _tree.modules()


## Adopts a tree recovered from the reload journal. The only way in besides a load, and it
## exists because a tree that has never been written is otherwise gone the moment the
## process is.
func adopt_tree(t: BuilderTree) -> void:
	if t == null:
		return
	_tree = t
	changed.emit()


## Looks a module up by path. An empty or unknown path is NOT FOUND, never an error -- an
## empty tree has no focus, and asking about nothing should answer nothing.
func try_get(file_path: String) -> Module:
	return _tree.by_path(file_path)


func by_id(module_id: String) -> Module:
	return _tree.by_id(module_id)


func has_unsaved_changes() -> bool:
	return _tree.has_unsaved_work()


## Whether a module can live at this path. THE one rule, so the name prompt and the creation
## itself cannot disagree. Nothing needs an exception for "deleted but not saved yet": a
## deleted module is not in the tree, so its name is free the instant it goes.
func is_path_available(file_path: String) -> bool:
	var full := Paths.canon(file_path)
	if full.is_empty():
		return false
	return _tree.by_path(full) == null and not FileAccess.file_exists(full)


# ── Policy ───────────────────────────────────────────────────────────────────────────

## Whether a path is one the builder must never write.
##
## `res://addons/` is this project's package directory -- where installed content lands, and
## the Godot analogue of a non-embedded Unity package. Everything outside `res://` is off
## limits outright: the builder edits project sources, and a path elsewhere is either a
## mistake or something the project does not own.
static func is_read_only_location(file_path: String) -> bool:
	return not Paths.is_writable_location(file_path)


## The in-memory home of a tree started from the empty state. Nothing is ever written here:
## Save re-homes every module under it into the folder the user picks, and refuses to write
## one that is still here.
##
## Its name ends in `~`, which Godot's importer skips wholesale, so a module that somehow
## reached disk here is never imported and never compiled. It sits under `res://`
## deliberately -- `is_read_only_location` treats anything outside the project as immutable,
## so a provisional path in a temp directory would open the first card READ-ONLY and refuse
## every edit.
const UNSAVED_ROOT := "res://__ruitk_builder_unsaved__~"


## Whether a module is still at the provisional location.
##
## DERIVED from where the module sits, never a flag. As a flag, the caller that forgets is
## the create flow for the SECOND module in a new tree: with a focus file present it passes
## false, so a companion created beside its component never asks for a location, is never
## re-homed, and Save writes it under the provisional root -- which the importer ignores.
## The file exists, Godot never sees it, and the component's import resolves to nothing.
static func is_unlocated(file_path: String) -> bool:
	var full := Paths.canon(file_path)
	if full.is_empty():
		return false
	return Paths.is_under(full, UNSAVED_ROOT) \
		and Paths.key(full) != Paths.key(UNSAVED_ROOT)


## Every module still waiting to be told where it lives.
func unlocated_modules() -> Array[Module]:
	var pending: Array[Module] = []
	for module in _tree.modules():
		if is_unlocated(module.file_path()):
			pending.append(module)
	return pending


# ── Loading ──────────────────────────────────────────────────────────────────────────

## Reads the whole tree that `focus_path` belongs to, once. Everything after this reads from
## memory: what the canvas shows no longer depends on which files happen to be open, and no
## mount touches the filesystem again.
func load_tree(focus_path: String) -> void:
	var loaded: Array[Module] = []
	var projection := PackedStringArray()
	# Case-insensitive, because a specifier spells a path in whatever case the user typed
	# and the filesystem does not care -- ordinal keys would let one file in twice.
	var seen := {}

	var root := BuilderTree.resolve_root(focus_path)
	if not root.is_empty() and DirAccess.dir_exists_absolute(root):
		var files := _scan_guitkx(root)
		files.sort()
		for file in files:
			var full := Paths.canon(file)
			var k := full.to_lower()
			if seen.has(k):
				continue
			var raw := _read_text(full)
			if raw == null:
				continue
			seen[k] = true
			loaded.append(Module.from_file(full, str(raw), is_read_only_location(full)))
			projection.append(full)

	# Imports that leave the root pull their targets in, transitively. A tree is what the
	# focus can REACH; the folder scan is only its seed. A shared module one folder over is
	# outside the scan, so it would be missing from the model entirely and the import that
	# names it would resolve to nothing -- an anchor dot with no line, on a module that was
	# sitting on disk the whole time.
	var i := 0
	while i < loaded.size():
		for target in _import_targets_of(loaded[i]):
			var k2 := Paths.key(target)
			if seen.has(k2) or not FileAccess.file_exists(target):
				continue
			var raw2 := _read_text(target)
			if raw2 == null:
				continue
			seen[k2] = true
			loaded.append(Module.from_file(target, str(raw2), is_read_only_location(target)))
			projection.append(target)
		i += 1

	_tree.reset(loaded, projection)
	changed.emit()


## Brings a single file into the tree -- opening a module from outside the loaded tree, or
## one the loader could not see. A file that is already present is returned as-is, after
## re-checking disk: a clean module that never re-checks serves stale text forever.
func open(file_path: String) -> Module:
	var full := Paths.canon(file_path)
	var existing := _tree.by_path(full)
	if existing != null:
		if not existing.is_dirty() and FileAccess.file_exists(full):
			var raw := _read_text(full)
			if raw != null and existing.adopt_disk_text(str(raw)):
				changed.emit()
		return existing

	var module: Module = null
	if FileAccess.file_exists(full):
		var raw2 := _read_text(full)
		if raw2 == null:
			return null
		module = Module.from_file(full, str(raw2), is_read_only_location(full))
	else:
		module = Module.fresh(
			full.get_base_dir(), Module.name_of(full),
			Module.kind_of(full), "")
	_tree.add(module)
	changed.emit()
	return module


## External-change sweep: clean modules adopt the new disk text; dirty ones keep the user's
## unsaved buffer. Returns the paths whose text changed.
func reload_clean_from_disk(paths: PackedStringArray) -> PackedStringArray:
	var touched := PackedStringArray()
	for path in paths:
		var module := _tree.by_path(path)
		if module == null or module.is_dirty() or module.read_only:
			continue
		var full := Paths.canon(path)
		if not FileAccess.file_exists(full):
			continue
		var raw := _read_text(full)
		if raw != null and module.adopt_disk_text(str(raw)):
			touched.append(full)
	if not touched.is_empty():
		changed.emit()
	return touched


# ── Manipulation ─────────────────────────────────────────────────────────────────────

func create_new(file_path: String, initial_buffer: String) -> Module:
	var full := Paths.canon(file_path)
	if not is_path_available(full):
		return null
	var module := Module.fresh(
		full.get_base_dir(), Module.name_of(full),
		Module.kind_of(full), initial_buffer)
	_tree.add(module)
	changed.emit()
	return module


## Deletes a module: it leaves the tree. Save works out that its file is orphaned by diffing
## against the last projection, so there is no mark to set, nothing to filter, and the name
## is free at once.
func delete(file_path: String) -> bool:
	var module := _tree.by_path(file_path)
	if module == null or module.read_only:
		return false
	_tree.remove(module)
	changed.emit()
	return true


## Puts a removed module back, for undo. It keeps its identity and its disk path, so a
## module that had a file still owns that file.
func restore(module: Module) -> Module:
	if module == null or _tree.by_path(module.file_path()) != null:
		return null
	_tree.add(module)
	changed.emit()
	return module


func apply_edit(file_path: String, new_buffer_lf: String) -> bool:
	var module := _tree.by_path(file_path)
	if module == null:
		push_error("[builder] no module open for '%s' -- open it before editing." % file_path)
		return false
	if not module.apply_edit(new_buffer_lf):
		return false
	changed.emit()
	return true


func close(file_path: String) -> void:
	if _tree.remove_by_path(file_path):
		changed.emit()


## Gives a module its real home. A module carried along by a parent that owned its folder is
## already there, and moving it to where it already is changes nothing, so the walk is
## order-independent.
func place_at(module: Module, new_folder: String) -> Array:
	if module == null or _tree.by_path(module.file_path()) != module:
		return []
	return _move(module, new_folder, module.name)


## Moves a module, carrying its folder's contents when it owns the folder, and rewrites every
## specifier the move invalidated. Returns those rewrites -- EMPTY when the move was refused
## -- so the caller can put them in the ledger beside the move itself.
##
## Nothing happens on disk: Save sees the disk path disagree with the derived path and
## projects the move.
func move_to(file_path: String, new_folder: String, new_name: String) -> Array:
	var module := _tree.by_path(file_path)
	if module == null or module.read_only:
		return []
	return _move(module, new_folder, new_name)


## Moves a module to a target PATH, splitting the folder and name out of it. What the ledger
## replays: an entry records where a module went, and walking it back is the same operation
## the other way.
##
## The KIND is not re-read from the target name. A move that inferred it would let a rename
## into `x.style.guitkx` silently reclassify the module, and the suffix would then be applied
## twice on the next derivation.
func move_to_path(from_path: String, to_path: String) -> Array:
	var to := Paths.canon(to_path)
	if to.is_empty():
		return []
	return move_to(from_path, to.get_base_dir(), Module.name_of(to))


func _move(module: Module, new_folder: String, new_name: String) -> Array:
	var snapshot := capture_imports()
	_tree.move_to(module, new_folder, new_name)
	var rewrites := reconcile_imports(snapshot)
	changed.emit()
	return rewrites


# ── Import reconciliation ────────────────────────────────────────────────────────────

## What every import in the tree POINTED AT, taken before an operation that will move things.
##
## Keyed by (importer id, LINE, ordinal-on-that-line) rather than by the specifier text. A
## rename edits specifier text in place before the move happens, so a snapshot keyed on that
## text could no longer find its own entries afterwards -- which is how a specifier naming
## the moved FOLDER from outside it (`"../panel/panel"`) stays broken: the name rewrite has
## already made it unresolvable, so nothing downstream can tell what it had meant. A line
## survives an edit within it.
##
## The ORDINAL is what a line alone cannot carry. Nothing stops two imports sharing a line,
## and keyed by line alone the second would overwrite the first in the snapshot -- one
## import silently dropped from the reconcile, left pointing at a file that moved. Counting
## position within the line costs nothing and the case stops existing.
##
## Returns { "<importer id>#<line>#<ordinal>": "<target id>" }.
func capture_imports() -> Dictionary:
	var targets := {}
	for module in _tree.modules():
		if module.read_only:
			continue
		var ordinals := {}
		for imp in Specifiers.imports_of(module.buffer_text):
			var line := int(imp["line"])
			var ordinal := int(ordinals.get(line, 0))
			ordinals[line] = ordinal + 1
			var mapped := Specifiers.map(module.file_path(), str(imp["spec"]))
			if mapped.is_empty():
				continue
			var target := _tree.by_path(mapped)
			if target != null:
				targets["%s#%d#%d" % [module.id, line, ordinal]] = target.id
	return targets


## Re-spells every snapshotted import for where its two ends now sit, and returns the buffers
## it changed as [{ file_path, before, after }].
##
## Both ends matter: a module that MOVED changes how everyone reaches it, and an IMPORTER
## that moved changes how it reaches everyone else -- rewriting only the importers of the
## moved module would leave a relocated component pointing at everything it used to sit
## beside.
func reconcile_imports(snapshot: Dictionary) -> Array:
	var rewrites: Array = []
	if snapshot.is_empty():
		return rewrites

	var by_importer := {}
	for key in snapshot:
		var parts := str(key).rsplit("#", true, 2)
		if parts.size() != 3:
			continue
		var importer := _tree.by_id(str(parts[0]))
		var target := _tree.by_id(str(snapshot[key]))
		if importer == null or target == null or importer.read_only:
			continue
		var wanted := Specifiers.relative(importer.folder, target.file_path())
		if wanted.is_empty():
			continue
		if not by_importer.has(importer.id):
			by_importer[importer.id] = []
		(by_importer[importer.id] as Array).append({
			"line": int(str(parts[1])), "ordinal": int(str(parts[2])), "wanted": wanted,
		})

	for importer_id in by_importer:
		var importer := _tree.by_id(str(importer_id))
		var before := importer.buffer_text
		var after := _rewrite_specifiers(importer, by_importer[importer_id])
		if after.is_empty() or after == before:
			continue
		importer.apply_edit(after)
		rewrites.append({ "file_path": importer.file_path(), "before": before, "after": after })
	return rewrites


## Replaces the quoted specifier of each named import, using the PARSER's own span rather
## than searching the text: a specifier is an ordinary string and can appear anywhere else in
## the file. Edits are applied from the LAST offset backwards so the spans ahead of each one
## stay valid. "" when nothing needed changing.
func _rewrite_specifiers(importer: Module, wanted: Array) -> String:
	var source := importer.buffer_text
	var edits: Array = []
	var ordinals := {}
	for imp in Specifiers.imports_of(source):
		# The same per-line counter the snapshot used, recomputed from the CURRENT text so
		# the two agree even if the line's contents changed in between.
		var line := int(imp["line"])
		var ordinal := int(ordinals.get(line, 0))
		ordinals[line] = ordinal + 1
		for w in wanted:
			if line != int(w["line"]) or ordinal != int(w["ordinal"]) \
					or str(imp["spec"]) == str(w["wanted"]):
				continue
			# `spec_at` is the offset of the opening quote; the span covers both quotes.
			edits.append({
				"start": int(imp["spec_at"]),
				"length": str(imp["spec"]).length() + 2,
				"text": "\"%s\"" % str(w["wanted"]),
			})
			break
	if edits.is_empty():
		return ""
	edits.sort_custom(func(a, b): return int(a["start"]) > int(b["start"]))
	var out := source
	for e in edits:
		var start := int(e["start"])
		var length := int(e["length"])
		if start < 0 or start + length > out.length():
			continue
		out = out.substr(0, start) + str(e["text"]) + out.substr(start + length)
	return out


# ── Projection ───────────────────────────────────────────────────────────────────────

## Writes the tree to disk. A pure diff, so running it twice is a no-op: nothing is dirty, no
## disk path disagrees with its derived path, and nothing is orphaned. Returns how many files
## were written, removed or moved.
##
## Moves are renames of the whole artifact set -- the `.guitkx`, its UID and diagnostics
## sidecars, the generated `.gd` and that script's UID -- so a renamed module keeps the UID
## every `uid://` reference in the project resolves through. Deletions go to the trash rather
## than being erased, so even a confirmed, saved removal stays recoverable outside the builder.
func save_all() -> int:
	if not _tree.has_unsaved_work():
		return 0

	var written := 0
	var removed := 0
	# Counted separately, and INCLUDED in the total. A pure rename dirties no buffer and
	# orphans no path, so a count of writes plus removals reports zero for it -- and "saved
	# 0 files" after a rename that did move files reads as a save that did not happen.
	var moved := 0
	var vacated := {}
	var touched_disk := false

	# Orphans FIRST: a module that moved out of a folder and one that was deleted from it can
	# both be pending, and clearing the dead paths before writing keeps a stale file from
	# shadowing a new one at the same location.
	for orphan in _tree.orphaned_paths():
		if _retire(orphan):
			removed += 1
			touched_disk = true
			var dir := orphan.get_base_dir()
			if not dir.is_empty():
				vacated[dir] = true

	for module in _tree.modules():
		# The provisional root is checked HERE, at the write, so no route into Save can put a
		# module there: Godot's importer ignores that folder, so a file written to it exists
		# and is invisible, which is worse than not writing it at all.
		if module.read_only or is_unlocated(module.file_path()):
			continue
		var target := module.file_path()
		if target.is_empty():
			continue

		if module.has_moved():
			# Where it came FROM, so a folder the move empties can be taken out with it. A
			# move that leaves the old folder standing has not moved anything as far as the
			# filesystem dock is concerned.
			var from_dir := module.disk_path.get_base_dir()
			if not from_dir.is_empty():
				vacated[from_dir] = true
			_ensure_directory(target)
			if not _move_on_disk(module.disk_path, target):
				push_error("[builder] could not move %s to %s -- save stopped." % [module.disk_path, target])
				return written + removed + moved
			module.disk_path = target
			moved += 1
			touched_disk = true

		if not module.is_on_disk() or module.is_dirty():
			_ensure_directory(target)
			touched_disk = touched_disk or not module.is_on_disk()
			if not _write_text(target, module.to_disk_text()):
				push_error("[builder] could not write %s -- save stopped." % target)
				return written + removed + moved
			written += 1
		module.mark_projected(target)

	var projection := PackedStringArray()
	for module in _tree.modules():
		if module.is_on_disk():
			projection.append(module.disk_path)
	_tree.set_projection(projection)
	_prune_empty_folders(vacated.keys())

	if touched_disk and rescan.is_valid():
		rescan.call()
	changed.emit()
	return written + removed + moved


## Discards every pending change by re-reading the tree. Abort IS load re-run, which is why
## it needs no bookkeeping of its own. Returns how many pending changes were dropped.
func abort_all() -> int:
	if not _tree.has_unsaved_work():
		return 0
	var reverted := _tree.orphaned_paths().size()
	var anchor := ""
	for module in _tree.modules():
		if module.is_dirty() or not module.is_on_disk() or module.has_moved():
			reverted += 1
		if anchor.is_empty() and module.is_on_disk():
			anchor = module.disk_path

	if anchor.is_empty():
		# Nothing was ever written, so there is nothing to go back to.
		_tree.reset([], PackedStringArray())
		changed.emit()
	else:
		load_tree(anchor)
	return reverted


# ── Disk ─────────────────────────────────────────────────────────────────────────────

## The text of a file, or null when it cannot be read. Null rather than "" so a caller can
## tell an unreadable file from an empty one -- reading a locked file as empty is how a
## buffer gets silently blanked.
static func _read_text(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	# NOT `get_as_text(true)`: that skips CR, and the CR is the evidence -- a module records
	# the EOL flavor it came from so Save can write bytes matching what was there before.
	var text := f.get_as_text()
	f.close()
	return text


static func _write_text(path: String, text: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.close()
	return true


static func _ensure_directory(file_path: String) -> void:
	var dir := file_path.get_base_dir()
	if dir.is_empty() or DirAccess.dir_exists_absolute(dir):
		return
	DirAccess.make_dir_recursive_absolute(dir)


## Renames a `.guitkx` and every artifact that belongs to it. Godot keeps a file's UID in a
## sidecar, so moving the pair is what keeps the identity -- a `.guitkx` moved alone would
## leave the generated `.gd` behind, still carrying its `class_name` and still resolving from
## every `uid://` that named it.
##
## An artifact that is not there is not an error: the generated `.gd` may never have been
## produced, and the diagnostics sidecar only exists once the file has been compiled.
static func _move_on_disk(from: String, to: String) -> bool:
	if not FileAccess.file_exists(from):
		return true
	if DirAccess.rename_absolute(from, to) != OK:
		return false
	var from_companions := Paths.companion_artifacts(from)
	var to_companions := Paths.companion_artifacts(to)
	for i in range(from_companions.size()):
		if FileAccess.file_exists(from_companions[i]):
			DirAccess.rename_absolute(from_companions[i], to_companions[i])
	return true


## Takes one module out of the project, artifacts and all. Trash rather than erase, so even a
## confirmed, saved removal stays recoverable outside the builder.
func _retire(path: String) -> bool:
	if path.is_empty() or not FileAccess.file_exists(path):
		return false
	for companion in Paths.companion_artifacts(path):
		if FileAccess.file_exists(companion):
			_trash_one(companion)
	return _trash_one(path)


func _trash_one(path: String) -> bool:
	return bool(trash_file.call(path)) if trash_file.is_valid() else _trash(path)


static func _trash(path: String) -> bool:
	var global := ProjectSettings.globalize_path(path)
	if OS.move_to_trash(global) == OK:
		return true
	# No trash on this platform, or a path the shell refuses. Removing it is still the
	# outcome the user asked for; losing the undo is better than a save that silently
	# leaves the file behind.
	return DirAccess.remove_absolute(path) == OK


## Takes out folders a move emptied, and their parents, stopping at the first that still
## holds anything.
##
## COMPLETELY empty, deliberately: Godot has no `.meta` convention to discount, so anything
## left in the folder is content someone put there. Deleting a folder that still holds a
## stray sidecar would take a file the builder does not own.
static func _prune_empty_folders(folders: Array) -> void:
	for folder in folders:
		var walk := Paths.canon(str(folder))
		while not walk.is_empty() and walk != "res://" and _is_empty_folder(walk):
			var parent := walk.get_base_dir()
			if DirAccess.remove_absolute(walk) != OK:
				break
			if parent == walk:
				break
			walk = parent


static func _is_empty_folder(folder: String) -> bool:
	if not DirAccess.dir_exists_absolute(folder):
		return false
	var d := DirAccess.open(folder)
	if d == null:
		return false
	return d.get_files().is_empty() and d.get_directories().is_empty()


## Every `.guitkx` at or under `root`. Recursive by hand: `DirAccess` has no recursive list,
## and the walk has to skip Godot's own hidden folders anyway.
static func _scan_guitkx(root: String) -> PackedStringArray:
	var out := PackedStringArray()
	var pending: Array[String] = [Paths.canon(root)]
	while not pending.is_empty():
		var dir: String = pending.pop_back()
		var d := DirAccess.open(dir)
		if d == null:
			continue
		for file in d.get_files():
			if Paths.ends_with_ci(file, Paths.SUFFIX_PLAIN):
				out.append(Paths.canon(dir.path_join(file)))
		for sub in d.get_directories():
			# `.`-prefixed folders are Godot's own; a `~` suffix marks content the importer
			# skips, which is exactly what the provisional root uses to stay invisible.
			if sub.begins_with(".") or sub.ends_with("~"):
				continue
			pending.append(Paths.canon(dir.path_join(sub)))
	return out


## The absolute paths a module imports. Parsing is the only way to know: an import is text,
## and the module holding it may never have been written. A module that does not parse
## contributes nothing, which is the right answer for a file that is half-typed.
##
static func _import_targets_of(module: Module) -> PackedStringArray:
	var out := PackedStringArray()
	var from := module.file_path()
	if from.is_empty():
		return out
	for imp in Specifiers.imports_of(module.buffer_text):
		var mapped := Specifiers.map(from, str(imp["spec"]))
		if not mapped.is_empty():
			out.append(mapped)
	return out
