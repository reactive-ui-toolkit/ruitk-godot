@tool
class_name GuitkxProblemsPanel
extends Control
## The bottom-panel "Problems" list: the CURRENT buffer's diagnostics, or — via the scope switch —
## the whole PROJECT's, aggregated from every compile sidecar (parity plan G14; the sweep-produced
## verdicts the watcher persists per file). Rows carry the GUITKX code (G34) and the full message
## as tooltip; activation emits `diagnostic_activated(line)` for current-file rows and
## `location_activated(path, line)` for project rows. Code-built UI (no .tscn).

signal diagnostic_activated(line: int)
signal location_activated(path: String, line: int)

var _list: ItemList
var _summary: Label
var _scope: OptionButton
var _current_records: Array = []

func _init() -> void:
	name = "Problems"
	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(vbox)

	var top := HBoxContainer.new()
	vbox.add_child(top)
	_scope = OptionButton.new()
	_scope.add_item("Current File", 0)
	_scope.add_item("Project", 1)
	_scope.item_selected.connect(func(_i: int): _render())
	top.add_child(_scope)
	_summary = Label.new()
	_summary.text = "No problems."
	top.add_child(_summary)

	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.auto_height = false
	_list.item_activated.connect(_on_item_activated)
	vbox.add_child(_list)

	custom_minimum_size = Vector2(0, 140)

## records: Array of { code, severity, message, line } from GuitkxDiagnosticsRenderer.
func set_records(records: Array) -> void:
	_current_records = records
	if _scope == null or _scope.get_selected_id() == 0:
		_render()

func _render() -> void:
	if _list == null:
		return
	if _scope.get_selected_id() == 1:
		_render_rows(project_records(), true)
	else:
		_render_rows(_current_records, false)

func _render_rows(records: Array, project_scope: bool) -> void:
	_list.clear()
	var errors := 0
	var warnings := 0
	for rec in records:
		var sev := str(rec.get("severity", "error"))
		if sev == "error":
			errors += 1
		elif sev == "warning":
			warnings += 1
		var mark := "●" if sev == "error" else ("▲" if sev == "warning" else "·")
		var code := str(rec.get("code", ""))
		var where := "line %d" % (int(rec.get("line", 0)) + 1)
		if project_scope:
			where = "%s:%d" % [str(rec.get("path", "")).trim_prefix("res://"), int(rec.get("line", 0)) + 1]
		var idx := _list.add_item("%s %s  %s   (%s)" % [
			mark, ("[%s]" % code) if code != "" else "", rec.get("message", ""), where])
		_list.set_item_tooltip(idx, "%s\n%s" % [code, str(rec.get("message", ""))])
		_list.set_item_custom_fg_color(idx,
			Color(0.95, 0.45, 0.45) if sev == "error" else
			(Color(0.95, 0.8, 0.35) if sev == "warning" else Color(0.7, 0.7, 0.7)))
		_list.set_item_metadata(idx, { "line": int(rec.get("line", 0)), "path": str(rec.get("path", "")) })
	if records.is_empty():
		_summary.text = "  No problems."
	else:
		_summary.text = "  %d error(s), %d warning(s)" % [errors, warnings]

## Aggregate every sidecar in the project (headless-testable): rows shaped like current-file
## records plus "path". Lines are resolved against the CURRENT file content on disk.
static func project_records() -> Array:
	var out: Array = []
	for p in GuitkxWorkspace.all_paths():
		var sc_path: String = RUIGuitkxCodegen.diags_path_for(str(p))
		var raw := FileAccess.get_file_as_string(sc_path)
		if raw.is_empty():
			continue
		var parsed: Variant = JSON.parse_string(raw)
		if not (parsed is Dictionary):
			continue
		var text := FileAccess.get_file_as_string(str(p))
		for e in (parsed as Dictionary).get("diagnostics", []):
			if not (e is Dictionary):
				continue
			var ed := e as Dictionary
			var off := int(ed.get("off", -1))
			var lc: Dictionary = RUIGuitkxDiag.line_col(text, off) if off >= 0 else { "line": 0 }
			out.append({
				"path": str(p), "code": str(ed.get("code", "")),
				"severity": RUIGuitkxDiag.severity_name(int(ed.get("severity", 0))),
				"message": str(ed.get("message", "")), "line": int(lc.get("line", 0)),
			})
	return out

func clear() -> void:
	set_records([])

func _on_item_activated(index: int) -> void:
	var meta: Variant = _list.get_item_metadata(index)
	if not (meta is Dictionary):
		return
	var md := meta as Dictionary
	if _scope.get_selected_id() == 1 and str(md.get("path", "")) != "":
		location_activated.emit(str(md.get("path", "")), int(md.get("line", 0)))
	else:
		diagnostic_activated.emit(int(md.get("line", 0)))
