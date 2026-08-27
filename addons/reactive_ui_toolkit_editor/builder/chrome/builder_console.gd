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
	custom_minimum_size = Vector2(0, 140)
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	_summary = Label.new()
	_summary.text = "nothing compiled yet"
	add_child(_summary)

	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.auto_height = false
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
	_list.set_item_tooltip(_list.item_count - 1, "%s\n%s" % [file_path, message])
	if severity == SEVERITY_ERROR:
		_list.set_item_custom_fg_color(_list.item_count - 1, Color(0.90, 0.45, 0.45))
	_rows.append({ "severity": severity, "path": file_path, "message": message })


func rows() -> Array:
	return _rows


func clear() -> void:
	_rows.clear()
	_list.clear()
	_summary.text = "nothing compiled yet"


func _on_item_activated(index: int) -> void:
	if index < 0 or index >= _rows.size():
		return
	var path := str((_rows[index] as Dictionary)["path"])
	if not path.is_empty():
		location_activated.emit(path)
