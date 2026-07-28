@tool
class_name GuitkxSearchPanel
extends VBoxContainer
## Project-wide `.guitkx` search (the addon-native replacement for the retired Godot
## Search-in-Files registration — that route let the built-in Script editor adopt our files).
## Plain-text substring search over every indexed .guitkx; rows are path:line + the line text;
## activating a row asks the plugin to open + jump.

signal location_activated(path: String, line: int)

var _query: LineEdit
var _case: CheckBox
var _summary: Label
var _list: ItemList

func _init() -> void:
	name = "Search .guitkx"
	custom_minimum_size = Vector2(0, 140)
	var top := HBoxContainer.new()
	add_child(top)
	_query = LineEdit.new()
	_query.placeholder_text = "Search every .guitkx in the project…"
	_query.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_query.text_submitted.connect(func(_t: String): run_search())
	top.add_child(_query)
	_case = CheckBox.new()
	_case.text = "Aa"
	_case.tooltip_text = "Match case"
	top.add_child(_case)
	var go := Button.new()
	go.text = "Search"
	go.pressed.connect(run_search)
	top.add_child(go)
	_summary = Label.new()
	_summary.text = ""
	add_child(_summary)
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_activated.connect(_on_activated)
	add_child(_list)

func run_search() -> void:
	show_results(search(_query.text, _case.button_pressed))

## Pure search core (headless-testable): [{path, line (0-based), preview}].
static func search(query: String, match_case: bool) -> Array:
	var out: Array = []
	if query.strip_edges().is_empty():
		return out
	var needle := query if match_case else query.to_lower()
	for p in GuitkxWorkspace.all_paths():
		var text := FileAccess.get_file_as_string(str(p))
		if text.is_empty():
			continue
		var hay := text if match_case else text.to_lower()
		var from := 0
		while true:
			var i := hay.find(needle, from)
			if i < 0:
				break
			var line := text.count("\n", 0, i) if i > 0 else 0
			var ls := 0 if line == 0 else text.rfind("\n", i - 1) + 1
			var le := text.find("\n", i)
			if le == -1:
				le = text.length()
			out.append({ "path": str(p), "line": line, "preview": text.substr(ls, le - ls).strip_edges() })
			from = le if le > i else i + 1  # one hit per line is plenty
	return out

func show_results(records: Array) -> void:
	_list.clear()
	for r in records:
		var rd := r as Dictionary
		var idx := _list.add_item("%s:%d    %s" % [
			str(rd.get("path", "")).trim_prefix("res://"), int(rd.get("line", 0)) + 1,
			str(rd.get("preview", ""))])
		_list.set_item_metadata(idx, { "path": rd.get("path", ""), "line": rd.get("line", 0) })
	_summary.text = "%d hit%s" % [records.size(), "" if records.size() == 1 else "s"]

func _on_activated(idx: int) -> void:
	var meta: Variant = _list.get_item_metadata(idx)
	if meta is Dictionary:
		location_activated.emit(str((meta as Dictionary).get("path", "")), int((meta as Dictionary).get("line", 0)))
