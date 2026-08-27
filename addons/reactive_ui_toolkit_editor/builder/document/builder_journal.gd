@tool
class_name RuitkBuilderJournal
extends RefCounted
## The backstop for unsaved work: the tree, dumped to JSON outside the project, so it
## survives what nothing else can.
##
## The builder's save-only contract means a session can hold a great deal of work that has
## never reached disk. Everything else lowers the CHANCE of losing it; none of it recovers
## the work once the process is gone -- and an editor does go, to a crash or a kill.
##
## The journal exists ONLY while there is unsaved work: nothing writes it for a clean tree,
## and it is cleared when the work is saved, aborted, restored or explicitly discarded. So
## the file being there means exactly one thing -- work existed that never reached disk --
## and the restore offer needs no other evidence to be sure it is not noise.
##
## It lives under `user://`, which is outside the project: Godot's importer never sees it, so
## no import, no UID sidecar, and nothing for the compiler sweep to pick up.
##
## Cross-file references inside the builder go through preload CONSTS, never the global
## `class_name`s these files also declare. A global name resolves through the editor
## class cache, and `ProjectSettings.save()` rewrites that cache from whatever the
## running process happens to have loaded -- so a headless run of one suite can
## truncate it and leave the whole document layer unable to load in the next. A
## preload is a compile-time edge that nothing can invalidate. The `class_name`s stay,
## for consumers and for typing.

const BuilderTree = preload("res://addons/reactive_ui_toolkit_editor/builder/document/builder_tree.gd")
const BuilderWorkspace = preload("res://addons/reactive_ui_toolkit_editor/builder/document/builder_workspace.gd")

const JOURNAL_PATH := "user://ruitk_builder_tree.json"


## Writes the tree when it holds unsaved work.
##
## A clean tree is NOT evidence that an older journal has been dealt with -- it is usually a
## different tree, freshly loaded -- so this never clears. Clearing is a decision: the work
## was saved, aborted, restored, or explicitly discarded. Deleting here instead would destroy
## a crashed session's only copy the moment the user opened the builder on some other file,
## before anyone was ever asked about it.
static func capture(workspace: BuilderWorkspace, saved_at: String) -> bool:
	if workspace == null or not workspace.has_unsaved_changes():
		return false
	var payload := {
		"saved_at": saved_at,
		"modules": workspace.modules().size(),
		"tree": workspace.tree().to_dict(),
	}
	var f := FileAccess.open(JOURNAL_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("[builder] could not write the reload journal: %s" % error_string(FileAccess.get_open_error()))
		return false
	f.store_string(JSON.stringify(payload, "\t"))
	f.close()
	return true


## What the journal holds, without restoring it -- enough to ask the user whether they want
## it back. { modules, saved_at } when there is something, {} when there is not.
##
static func peek() -> Dictionary:
	var payload := _read()
	if payload.is_empty():
		return {}
	var tree := payload.get("tree", {}) as Dictionary
	if (tree.get("modules", []) as Array).is_empty():
		return {}
	return { "modules": int(payload.get("modules", 0)), "saved_at": str(payload.get("saved_at", "")) }


static func try_restore(workspace: BuilderWorkspace) -> bool:
	var payload := _read()
	if workspace == null or payload.is_empty():
		return false
	var tree := payload.get("tree", {}) as Dictionary
	if (tree.get("modules", []) as Array).is_empty():
		return false
	workspace.adopt_tree(BuilderTree.from_dict(tree))
	clear()
	return true


static func clear() -> void:
	if FileAccess.file_exists(JOURNAL_PATH):
		# A journal that cannot be removed is offered once more and declined once more;
		# losing the file is not worth an error the user can do nothing about.
		DirAccess.remove_absolute(JOURNAL_PATH)


static func _read() -> Dictionary:
	if not FileAccess.file_exists(JOURNAL_PATH):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(JOURNAL_PATH))
	return parsed if parsed is Dictionary else {}
