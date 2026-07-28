@tool
class_name GuitkxFindBar
extends HBoxContainer
## In-editor find + replace bar (parity plan G24). Drives TextEdit's built-in search painting
## (set_search_text highlights every match) plus explicit next/prev navigation over
## TextEdit.search(), which returns Vector2i(column, line) and does not wrap — wrapping is handled
## here. Replace steps through matches; Replace All is one undoable complex operation.
## Ctrl+F/F3/Shift+F3/Esc are wired by the owning view.

var _target: CodeEdit
var _query: LineEdit
var _replace: LineEdit
var _count: Label
var _case: CheckBox
var _armed := ""  # mirrors set_search_text (TextEdit has no getter) — for state checks + tests

func _init() -> void:
	visible = false

	var lbl := Label.new()
	lbl.text = " Find: "
	add_child(lbl)

	_query = LineEdit.new()
	_query.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_query.placeholder_text = "Search…"
	_query.text_changed.connect(func(_t: String): _update_search())
	_query.gui_input.connect(_on_query_input)
	add_child(_query)

	_count = Label.new()
	_count.text = ""
	add_child(_count)

	_case = CheckBox.new()
	_case.text = "Aa"
	_case.tooltip_text = "Match case"
	_case.toggled.connect(func(_on: bool): _update_search())
	add_child(_case)

	var prev := Button.new()
	prev.text = "↑"
	prev.tooltip_text = "Previous match (Shift+F3)"
	prev.pressed.connect(func(): find_step(false))
	add_child(prev)

	var next := Button.new()
	next.text = "↓"
	next.tooltip_text = "Next match (F3)"
	next.pressed.connect(func(): find_step(true))
	add_child(next)

	_replace = LineEdit.new()
	_replace.custom_minimum_size = Vector2(140, 0)
	_replace.placeholder_text = "Replace…"
	add_child(_replace)

	var rep := Button.new()
	rep.text = "Replace"
	rep.tooltip_text = "Replace the selected match, then find the next"
	rep.pressed.connect(replace_step)
	add_child(rep)

	var rep_all := Button.new()
	rep_all.text = "All"
	rep_all.tooltip_text = "Replace every match (single undo step)"
	rep_all.pressed.connect(replace_all)
	add_child(rep_all)

	var close := Button.new()
	close.text = "✕"
	close.tooltip_text = "Close (Esc)"
	close.pressed.connect(close_bar)
	add_child(close)

func attach(target: CodeEdit) -> void:
	_target = target

## Open (Ctrl+F): seed from the current selection, focus the query, highlight matches. Focus is
## DEFERRED: grabbing it in the same frame the bar becomes visible races visibility propagation,
## and when it loses, every keystroke lands in the code editor instead of the query field.
## [field capture: "type and nothing happens" on first open]
func open_bar() -> void:
	if _target == null:
		return
	visible = true
	var sel := _target.get_selected_text()
	if sel != "" and not sel.contains("\n"):
		_query.text = sel
	_query.select_all()
	(func():
		if _query.is_inside_tree():
			_query.grab_focus()).call_deferred()
	_update_search()

func close_bar() -> void:
	visible = false
	if _target != null:
		_armed = ""
		_target.set_search_text("")
		_target.queue_redraw()
		if _target.is_inside_tree():
			_target.grab_focus()

func query_text() -> String:
	return _query.text

func armed_search() -> String:
	return _armed

## Jump to the next/previous match from the caret, selecting it. Wraps around the buffer.
func find_step(forward: bool) -> void:
	if _target == null or _query.text.is_empty():
		return
	var q := _query.text
	var flags := _flags() | (0 if forward else TextEdit.SEARCH_BACKWARDS)
	var line := _target.get_caret_line()
	var col := _target.get_caret_column()
	if forward and _target.has_selection():
		# Step past the current match, or a repeated Next would stand still.
		line = _target.get_selection_to_line()
		col = _target.get_selection_to_column()
	elif not forward and _target.has_selection():
		# Step BEFORE the current match. A match starting at column 0 must hop to the previous
		# line's end (clamping to column 0 would re-find the same match and stand still).
		line = _target.get_selection_from_line()
		col = _target.get_selection_from_column() - 1
		if col < 0:
			line -= 1
			if line < 0:
				line = _target.get_line_count() - 1
			col = _target.get_line(line).length()
	var hit := _target.search(q, flags, line, col)
	if hit.x < 0:
		# Wrap: restart from the top (forward) or from the very end (backward).
		if forward:
			hit = _target.search(q, flags, 0, 0)
		else:
			var last := _target.get_line_count() - 1
			hit = _target.search(q, flags, last, _target.get_line(last).length())
	if hit.x < 0:
		return
	var match_line := hit.y
	var match_col := hit.x
	_target.select(match_line, match_col, match_line, match_col + q.length())
	_target.set_caret_line(match_line)
	_target.set_caret_column(match_col + q.length())
	_target.center_viewport_to_caret()

## Replace the selection when it IS the current match, then step to the next occurrence. When
## nothing is selected yet this just finds the first match (VS Code's Replace-button behavior).
func replace_step() -> void:
	if _target == null or _query.text.is_empty():
		return
	var q := _query.text
	var sel := _target.get_selected_text()
	var selected_is_match := sel == q if _case.button_pressed else sel.to_lower() == q.to_lower()
	if _target.has_selection() and selected_is_match:
		_target.begin_complex_operation()
		_target.delete_selection()
		_target.insert_text_at_caret(_replace.text)
		_target.end_complex_operation()
	find_step(true)

## Replace every match, front to back, as ONE undoable operation. String-level, NOT a
## TextEdit.search loop: search() clamps an at-line-end from_column back INTO the line, so a
## replacement containing the query ("a" -> "aa") re-matches its own output and grows the buffer
## forever [field capture 2026-07-05: hung the headless suite]. Building the result in a plain
## String makes termination structural — the scan cursor only moves forward past each match, and
## replacements are never rescanned.
func replace_all() -> void:
	if _target == null or _query.text.is_empty():
		return
	var src := _target.text
	var hay := src if _case.button_pressed else src.to_lower()
	var needle := _query.text if _case.button_pressed else _query.text.to_lower()
	var out := ""
	var from := 0
	var replaced := 0
	while true:
		var i := hay.find(needle, from)
		if i < 0:
			break
		out += src.substr(from, i - from) + _replace.text
		from = i + needle.length()
		replaced += 1
	if replaced == 0:
		_count.text = "0 replaced "
		return
	out += src.substr(from)
	_target.begin_complex_operation()
	_target.select_all()
	_target.delete_selection()
	_target.insert_text_at_caret(out)
	_target.end_complex_operation()
	_update_search()
	_count.text = "%d replaced " % replaced

func replace_text() -> String:
	return _replace.text

func set_replace_text(t: String) -> void:
	_replace.text = t

func _flags() -> int:
	return TextEdit.SEARCH_MATCH_CASE if _case.button_pressed else 0

## Refresh the built-in all-matches highlight + the match counter, and land on the first match at
## or after the caret (live-jump while typing the query).
func _update_search() -> void:
	if _target == null:
		return
	var q := _query.text
	_armed = q
	_target.set_search_text(q)
	_target.set_search_flags(_flags())
	_target.queue_redraw()
	var n := _count_matches(q)
	_count.text = "" if q.is_empty() else ("%d match%s " % [n, "" if n == 1 else "es"])
	if n > 0:
		# Land on the match at/after the caret without advancing past a current selection.
		var hit := _target.search(q, _flags(), _target.get_caret_line(), _target.get_caret_column())
		if hit.x < 0:
			hit = _target.search(q, _flags(), 0, 0)
		if hit.x >= 0:
			_target.select(hit.y, hit.x, hit.y, hit.x + q.length())
			_target.set_caret_line(hit.y)
			_target.set_caret_column(hit.x + q.length())
			_target.center_viewport_to_caret()

func _count_matches(q: String) -> int:
	if q.is_empty():
		return 0
	var hay := _target.text
	if not _case.button_pressed:
		hay = hay.to_lower()
		q = q.to_lower()
	var n := 0
	var from := 0
	while true:
		var i := hay.find(q, from)
		if i < 0:
			break
		n += 1
		from = i + q.length()
	return n

func _on_query_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed:
		return
	match k.keycode:
		KEY_ENTER, KEY_KP_ENTER:
			find_step(not k.shift_pressed)
			accept_event()
		KEY_ESCAPE:
			close_bar()
			accept_event()
