@tool
class_name RuitkBuilderLedger
extends RefCounted
## One ordered log of every builder action, with undo/redo that walks it atomically ACROSS
## files.
##
## A per-file history cannot express a user gesture: a drop that inserts a tag in one file
## and an import line in another is two edits and one ACTION, and undoing it file-by-file
## leaves the tree in a state the user never authored. An entry here owns the whole set of
## (file, before, after) triples a single gesture produced, so one undo reverts all of them
## or none.
##
## Redo is the tail past the cursor. Recording a new action truncates it, which is the
## standard linear-history rule -- a branch the user walked away from is not reachable again.
##
## The ledger is NOT persisted. Godot has no domain reload to survive, so the history simply
## lives as long as the builder is open; closing it is the one thing that ends the history,
## and that is the same boundary the user already understands.
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

## The kinds of change one entry can hold. `EDIT` carries text; the other three carry
## intent, because nothing on disk moves for any of them -- the file is only written at Save.
enum ChangeKind {
	EDIT,       ## a buffer rewritten: `before`/`after` are its text
	CREATION,   ## a NEW module. Undo removes it from the tree, redo puts it back
	DELETION,   ## a module LEAVING the tree. Undo puts it back, redo removes it again
	MOVE,       ## `before` is the path it came from, `after` where it went
}


class Change extends RefCounted:
	var file_path: String = ""
	var before: String = ""
	var after: String = ""
	var kind: ChangeKind = ChangeKind.EDIT

	## The module a deletion removed, held so undo can put the SAME module back -- its
	## identity, its buffer and its disk path. A deletion is not a mark that undo clears:
	## the module genuinely leaves the tree, so undo needs the thing itself.
	var removed: Module = null

	## The module's stable identity at record time. A ledger entry outlives the PATH it was
	## recorded against -- a rename moves the module, and a replay that looked it up by
	## path would write to a name nothing answers to. Replay resolves identity first.
	var module_id: String = ""


class Entry extends RefCounted:
	var description: String = ""
	var at_msec: int = 0

	## Free typing, as opposed to a discrete gesture. Consecutive keystrokes in the same
	## file merge into one of these.
	var is_typing: bool = false
	var changes: Array[Change] = []

	func file_summary() -> String:
		if changes.is_empty():
			return ""
		var first := changes[0].file_path.get_file()
		return first if changes.size() == 1 else "%s +%d" % [first, changes.size() - 1]


signal changed

## How long a typing burst stays open for merging, in milliseconds. Affects UNDO
## GRANULARITY only -- nothing downstream is timed off it.
const TYPING_WINDOW_MSEC := 1500

## The history ceiling. Old entries fall off the front; the cursor moves with them so the
## redo tail stays where the user left it.
const MAX_ENTRIES := 400

var _entries: Array[Entry] = []

## Entries BELOW the cursor are applied; entries at or above it have been undone and form
## the redo tail.
var _cursor := 0
var _open: Entry = null
var _depth := 0

## Suppresses recording while the ledger itself is rewriting buffers -- an undo must not be
## logged as a new action.
var replaying := false

## Resolves a path to the owning module's stable identity, set by the window. Capturing it
## at record time is what makes replay immune to the paths moving underneath it.
var id_of := Callable()

## Injectable clock, in milliseconds. The typing-merge window is the only thing that reads
## it, and a test that cannot control it can only assert the merge by sleeping.
var now_msec := Callable()


func entries() -> Array[Entry]:
	return _entries


func cursor() -> int:
	return _cursor


func can_undo() -> bool:
	return _cursor > 0


func can_redo() -> bool:
	return _cursor < _entries.size()


func undo_label() -> String:
	return _entries[_cursor - 1].description if can_undo() else ""


func redo_label() -> String:
	return _entries[_cursor].description if can_redo() else ""


func _now() -> int:
	return int(now_msec.call()) if now_msec.is_valid() else Time.get_ticks_msec()


func _id_for(path: String) -> String:
	return str(id_of.call(path)) if id_of.is_valid() else ""


## Opens a grouping scope. Nested begin/end pairs collapse into the OUTERMOST one, so a
## compound gesture that internally reuses a single-file primitive still lands as one entry.
func begin(description: String) -> void:
	if replaying:
		return
	_depth += 1
	if _open == null:
		_open = Entry.new()
		_open.description = description if not description.is_empty() else "edit"
		_open.at_msec = _now()
	elif not description.is_empty() and _depth == 1:
		_open.description = description


## Closes the outermost scope and pushes it. An empty scope is dropped -- a gesture the user
## cancelled leaves no history.
func end() -> void:
	if replaying:
		return
	if _depth > 0:
		_depth -= 1
	if _depth > 0:
		return
	_commit()


## Records free typing. Consecutive keystrokes in the same file merge into ONE entry instead
## of one per character, which is what an un-merged source pane produces: a hundred history
## rows for typing a name, and an undo that walks back one letter at a time.
##
## Merging only happens at the tip of the history and outside any gesture scope: an undo
## moves the cursor, and a compound action owns its own entry, so neither can be silently
## extended by the next keystroke.
func record_typing(file_path: String, before: String, after: String) -> void:
	if replaying or file_path.is_empty() or before == after:
		return
	if _open != null:
		record(file_path, before, after)
		return

	var last: Entry = null
	if _cursor > 0 and _cursor == _entries.size():
		last = _entries[_cursor - 1]
	var now := _now()
	if last != null and last.is_typing and last.changes.size() == 1 \
			and Paths.same(last.changes[0].file_path, file_path) \
			and now - last.at_msec < TYPING_WINDOW_MSEC:
		last.changes[0].after = after
		last.at_msec = now
		changed.emit()
		return

	_open = Entry.new()
	_open.description = "type in " + file_path.get_file()
	_open.at_msec = now
	_open.is_typing = true
	_open.changes.append(_change(file_path, ChangeKind.EDIT, before, after))
	_commit()


func record(file_path: String, before: String, after: String) -> void:
	if replaying or file_path.is_empty() or before == after:
		return
	var standalone := _open == null
	if standalone:
		_open_default("edit")
	# A gesture that writes the same file twice keeps ONE change whose `before` is the state
	# the gesture started from.
	for existing in _open.changes:
		if existing.kind == ChangeKind.EDIT and Paths.same(existing.file_path, file_path):
			existing.after = after
			if standalone:
				_commit()
			return
	_open.changes.append(_change(file_path, ChangeKind.EDIT, before, after))
	if standalone:
		_commit()


## Records a module changing PATH as ONE change, rather than an unrelated creation and
## deletion. The pair was never two events: it is one module in two places, and describing
## it as two is what lets undo put the module back without its history.
func record_move(from_path: String, to_path: String) -> void:
	if replaying or from_path.is_empty() or to_path.is_empty():
		return
	var standalone := _open == null
	if standalone:
		_open_default("rename")
	var c := _change(to_path, ChangeKind.MOVE, from_path, to_path)
	# THE ORIGIN LOOKUP ONLY WINS WHEN IT ANSWERS. By the time this is called the module already
	# sits at the destination, so `_id_for(from_path)` finds nothing -- and assigning it
	# unconditionally overwrote the id `_change` had just resolved correctly from `to_path` with
	# an empty string, which is the one thing a replay resolves identity by.
	var from_id := _id_for(from_path)
	if not from_id.is_empty():
		c.module_id = from_id
	_open.changes.append(c)
	if standalone:
		_commit()


## Records that a module left the tree. Carries no text because none is needed: the file is
## still on disk until Save, and the module itself rides along for undo.
func record_deletion(file_path: String, removed: Module = null) -> void:
	if replaying or file_path.is_empty():
		return
	var standalone := _open == null
	if standalone:
		_open_default("delete")
	var c := _change(file_path, ChangeKind.DELETION, "", "")
	c.removed = removed
	if c.module_id.is_empty() and removed != null:
		# The module is already out of the tree by the time this is called, so the path
		# lookup finds nothing -- take the identity from the module in hand.
		c.module_id = removed.id
	_open.changes.append(c)
	if standalone:
		_commit()


## Records a new module.
func record_creation(file_path: String) -> void:
	if replaying or file_path.is_empty():
		return
	var standalone := _open == null
	if standalone:
		_open_default("create")
	_open.changes.append(_change(file_path, ChangeKind.CREATION, "", ""))
	if standalone:
		_commit()


## Steps the cursor back one entry and returns it, for the caller to replay in reverse.
## null when there is nothing to undo.
func undo() -> Entry:
	if not can_undo():
		return null
	_cursor -= 1
	changed.emit()
	return _entries[_cursor]


func redo() -> Entry:
	if not can_redo():
		return null
	var entry := _entries[_cursor]
	_cursor += 1
	changed.emit()
	return entry


## Runs `body` with recording suppressed. GDScript has no `IDisposable`, so the scope is the
## callable itself -- which is stronger: the flag cannot be left set by an early return.
##
func suppress(body: Callable) -> void:
	var was := replaying
	replaying = true
	body.call()
	replaying = was


func clear() -> void:
	_entries.clear()
	_cursor = 0
	_open = null
	_depth = 0
	changed.emit()


func _open_default(description: String) -> void:
	_open = Entry.new()
	_open.description = description
	_open.at_msec = _now()


func _change(file_path: String, kind: ChangeKind, before: String, after: String) -> Change:
	var c := Change.new()
	c.file_path = Paths.canon(file_path)
	c.kind = kind
	c.before = before
	c.after = after
	c.module_id = _id_for(file_path)
	return c


func _commit() -> void:
	var entry := _open
	_open = null
	_depth = 0
	if entry == null or entry.changes.is_empty():
		return
	if _cursor < _entries.size():
		# The redo tail the user walked away from is not reachable again.
		_entries.resize(_cursor)
	_entries.append(entry)
	_cursor = _entries.size()
	if _entries.size() > MAX_ENTRIES:
		var drop := _entries.size() - MAX_ENTRIES
		_entries = _entries.slice(drop)
		_cursor -= drop
	changed.emit()
