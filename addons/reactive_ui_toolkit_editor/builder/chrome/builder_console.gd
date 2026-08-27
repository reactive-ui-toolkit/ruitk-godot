@tool
class_name RuitkBuilderConsole
extends VBoxContainer
## What the last preview round did, and every diagnostic the open tree currently has.
##
## NOT `GuitkxProblemsPanel`, deliberately. That panel's project scope aggregates the compile
## SIDECARS on disk, and the builder's modules live in buffers that have not been written -- so
## pointed at a builder session it would report the state of the files as they were before the
## user started, confidently and wrongly. The row shape and the activation contract are the same,
## because those are good; the source of truth is the preview.
##
## NOTHING ABOUT A ROUND IS SILENT. A module that failed, one that was skipped because something
## it imports failed, and one that was never a candidate all look identical from outside -- so
## the first two say so here, by name, with the reason.

const Preview = preload("res://addons/reactive_ui_toolkit_editor/builder/preview/builder_preview.gd")
const Parts = preload("res://addons/reactive_ui_toolkit_editor/builder/chrome/builder_chrome_parts.gd")

## A row naming a module was activated: open it.
signal location_activated(file_path: String)

const SEVERITY_ERROR := 0
const SEVERITY_WARNING := 1

var _summary: Label = null
var _list: ItemList = null
var _rows: Array = []


func _init() -> void:
	name = "Console"
	add_theme_constant_override("separation", 2)
	# NO FLOOR AND NO STRETCH. The console is a strip that grows when it has something to say and
	# a single line when it does not: a fixed pane held a slab of empty black across the bottom of
	# the canvas in every state, including the one where nothing has compiled yet, and clipped the
	# lowest card in the tree to make room for it.
	size_flags_vertical = Control.SIZE_SHRINK_END

	_summary = Label.new()
	_summary.text = "nothing compiled yet"
	_summary.add_theme_font_size_override("font_size", Parts.TITLE_FONT_SIZE)
	add_child(Parts.pane_header("Console", _summary))

	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(0, 0)
	_list.auto_height = true
	_list.visible = false
	_list.item_activated.connect(_on_item_activated)
	add_child(_list)


## Reports one preview round. A null summary means the round decided there was nothing to do,
## which leaves the previous report standing -- clearing it would blank the console on every
## idle tick and hide the failure the user is in the middle of fixing.
func report(summary) -> void:
	if summary == null:
		return
	_rows.clear()
	_list.clear()
	_sync_visibility()

	for failure in summary.failures:
		var f := failure as Dictionary
		_add_row(SEVERITY_ERROR, str(f["path"]), str(f["error"]))
	for skipped in summary.skipped:
		var s := skipped as Dictionary
		_add_row(SEVERITY_WARNING, str(s["path"]),
			"skipped -- depends on %s, which failed" % str(s["blocked_by"]).get_file())

	if summary.budget_exhausted:
		_add_row(SEVERITY_WARNING, "",
			"the round ran out of its frame budget -- the rest is still queued")

	_summary.text = _summarize(summary)


func _summarize(summary) -> String:
	if not summary.failures.is_empty():
		return "%d failed, %d skipped, %d built" % [
			summary.failures.size(), summary.skipped.size(), summary.rebuilt.size()]
	if summary.rebuilt.is_empty():
		return "nothing to rebuild"
	return "%d module(s) rebuilt, no problems" % summary.rebuilt.size()


## Adds diagnostics that are not compile failures -- the warnings and hints a module carries even
## when it builds. Appended rather than replacing, because they are a different question from
## "did the round succeed" and the user needs both at once.
func add_diagnostics(file_path: String, diagnostics: Array) -> void:
	for d in diagnostics:
		var record := d as Dictionary
		var severity := int(record.get("severity", SEVERITY_ERROR))
		var line := int(record.get("line", -1))
		var where := file_path if line < 0 else "%s:%d" % [file_path, line + 1]
		_add_row(severity, where, "%s %s" % [str(record.get("code", "")), str(record.get("message", ""))])


func _add_row(severity: int, file_path: String, message: String) -> void:
	var mark := "ERROR" if severity == SEVERITY_ERROR else "warn "
	var where := "" if file_path.is_empty() else file_path.get_file() + ": "
	_list.add_item("%s  %s%s" % [mark, where, message])
	_sync_visibility()
	_list.set_item_tooltip(_list.item_count - 1, "%s\n%s" % [file_path, message])
	if severity == SEVERITY_ERROR:
		_list.set_item_custom_fg_color(_list.item_count - 1, Color(0.90, 0.45, 0.45))
	_rows.append({ "severity": severity, "path": file_path, "message": message })


func rows() -> Array:
	return _rows


func clear() -> void:
	_rows.clear()
	_list.clear()
	_sync_visibility()
	_summary.text = "nothing compiled yet"


func _on_item_activated(index: int) -> void:
	if index < 0 or index >= _rows.size():
		return
	var path := str((_rows[index] as Dictionary)["path"])
	if not path.is_empty():
		location_activated.emit(path)


## Dumps the session's own state into the console: what the tree holds, what is dirty, what the
## last round built, what the ledger remembers.
##
## The Unity leg calls this Trace and it earns its place on the toolbar: everything in a builder
## session is in memory until Save, so when something looks wrong there is otherwise NOTHING to
## inspect — no file to open, no log to read. This is the only window into the live state.
func trace(workspace, ledger, preview) -> void:
	_rows.clear()
	_list.clear()
	_sync_visibility()
	if workspace == null:
		_summary.text = "trace: no tree open"
		return
	var modules: Array = workspace.modules()
	var dirty := 0
	for module in modules:
		if module.is_dirty():
			dirty += 1
	_summary.text = "trace: %d module(s), %d dirty" % [modules.size(), dirty]
	for module in modules:
		var flags := PackedStringArray()
		if module.is_dirty():
			flags.append("dirty")
		if module.has_moved():
			flags.append("moved")
		if module.read_only:
			flags.append("read-only")
		var suffix := ("  [" + ", ".join(flags) + "]") if not flags.is_empty() else ""
		_add_line("%s%s" % [module.file_path(), suffix], module.file_path())
	if ledger != null:
		_add_line("history: %d entry(s)%s"
			% [ledger.entries.size(), ("  next undo: " + ledger.undo_label()) if ledger.can_undo() else ""], "")
	if preview != null:
		_add_line("preview: %s" % ("mounted " + preview.mounted_path() if preview.is_mounted() else "nothing mounted"), "")


## The interaction model, in the console, on request. The hint bar along the bottom carries the
## short form permanently; this is the long form for when the short one was not enough.
func show_help() -> void:
	_rows.clear()
	_list.clear()
	_sync_visibility()
	_summary.text = "how to drive it"
	for line in [
		"CANVAS — wheel zooms, drag pans, right-click for the canvas menu, Fit frames the tree.",
		"LAYERS — the toolbar dropdown picks the detail band; the canvas follows, and the zoom follows it back.",
		"LIBRARY — drag an element, hook or component onto a card. The band you drop on decides:",
		"          top third = before the row, middle = inside it, bottom third = after it.",
		"CARDS — drag a row to reorder it, drag a card onto another to move the module into its folder.",
		"        Right-click a card to open, rename or delete it.",
		"EDITING — click an attribute or a badge to edit it in place; the source pane edits the same buffer.",
		"SAVING — nothing reaches disk until Save. Abort throws the whole session away.",
		"          Unsaved work is journalled, so a crash offers the tree back.",
	]:
		_add_line(line, "")


## Adds one line to the list, remembering which module (if any) it points at so activating the row
## can open it.
func _add_line(text: String, file_path: String) -> void:
	_list.add_item(text)
	_rows.append({ "path": file_path })
	_sync_visibility()


## Shows the list only when it holds something, so an empty console is one line rather than a
## region. Called by everything that fills or clears it.
func _sync_visibility() -> void:
	_list.visible = _list.item_count > 0
