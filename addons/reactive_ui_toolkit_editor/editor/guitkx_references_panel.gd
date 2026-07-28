@tool
class_name GuitkxReferencesPanel
extends VBoxContainer
## Bottom-panel list for find-references results (parity plan G2): one row per reference with
## file, line, and the line's text; activating a row asks the plugin to open the file and jump.
## Separate from the Problems panel so the diagnostics refresh never clobbers a results list.

signal location_activated(path: String, line: int)

var _summary: Label
var _list: ItemList

func _init() -> void:
	name = "References"
	custom_minimum_size = Vector2(0, 120)
	_summary = Label.new()
	_summary.text = "No search yet."
	add_child(_summary)
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_activated.connect(_on_activated)
	add_child(_list)

## records: [{path, line (0-based), preview, kind}]
func show_references(tag: String, records: Array) -> void:
	_list.clear()
	for r in records:
		var rd := r as Dictionary
		var marker := "●"
		match str(rd.get("kind", "")):
			"decl":
				marker = "◆"
			"class_name":
				marker = "◇"
			"close":
				marker = "○"
		var idx := _list.add_item("%s  %s:%d    %s" % [
			marker, str(rd.get("path", "")).trim_prefix("res://"),
			int(rd.get("line", 0)) + 1, str(rd.get("preview", ""))])
		_list.set_item_metadata(idx, { "path": rd.get("path", ""), "line": rd.get("line", 0) })
	_summary.text = "%d reference%s to <%s>   (◆ declaration · ◇ @class_name · ○ closing tag)" % [
		records.size(), "" if records.size() == 1 else "s", tag]

func _on_activated(idx: int) -> void:
	var meta: Variant = _list.get_item_metadata(idx)
	if meta is Dictionary:
		location_activated.emit(str((meta as Dictionary).get("path", "")), int((meta as Dictionary).get("line", 0)))
