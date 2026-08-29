@tool
class_name RuitkBuilderSearchMenu
extends PopupPanel
## A SEARCHABLE menu, and the name prompt that shares its chrome.
##
## Ported from the Unity leg's `BuilderSearchMenu`. Every menu in that builder that offers more
## than a handful of choices is this one: the attribute list for a tag, the tags you can add as a
## child, the directives you can wrap a row in, the modules a usage can import from. A plain
## `PopupMenu` cannot do the job -- a Control has a hundred and forty properties and fifty-five
## tags exist, and a list you can only scroll is a list you read rather than one you use.
##
## THE FREEFORM ROW is what makes it a menu and not a picker: whatever you typed is offered as
## itself, in warning-orange, when nothing matches. The schema knows a lot of attribute names and
## the language accepts more than the schema knows, so a menu that could only offer what it had
## heard of would be a menu that forbids valid code.
##
## Enter takes the first match. Escape closes. Filtering hides separators and section headings,
## because a heading with nothing under it is a heading that lies about what is there.

## A choice was made. `payload` is whatever the caller attached to the item.
signal picked(payload: Variant)
## A name prompt was submitted with a name its validator accepted.
signal submitted(text: String)

const Parts = preload("res://addons/reactive_ui_toolkit_editor/builder/chrome/builder_chrome_parts.gd")

const WIDTH := 300
const HEIGHT := 340
const PROMPT_HEIGHT := 130
const FREEFORM_COLOR := Color(1.0, 0.72, 0.30)

var _title: Label = null
var _search: LineEdit = null
var _list: VBoxContainer = null
var _error: Label = null
var _items: Array = []
var _freeform := Callable()
var _validate: Callable = Callable()
var _prompting := false

## Which pickable row the keyboard is on, or -1. The menu that offers 140 attributes and 55 tags
## had no keyboard at all: Enter always fired the FIRST match, and nothing could reach the second.
var _highlight := -1


func _init() -> void:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	add_child(column)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", Parts.TITLE_FONT_SIZE)
	_title.add_theme_color_override("font_color", Parts.TITLE_COLOR)
	column.add_child(_title)

	_search = LineEdit.new()
	_search.text_changed.connect(func(_t: String): _rebuild())
	_search.text_submitted.connect(func(_t: String): _submit())
	column.add_child(_search)

	_error = Label.new()
	_error.add_theme_font_size_override("font_size", Parts.HINT_FONT_SIZE)
	_error.add_theme_color_override("font_color", Color(0.90, 0.45, 0.45))
	# ALWAYS PRESENT, never toggled. Showing and hiding it moved the Create row up and down under
	# the pointer, so a second click after a rejected name landed on whatever had slid into place.
	_error.visible = true
	_error.text = ""
	_error.custom_minimum_size = Vector2(0, Parts.HINT_FONT_SIZE + 4)
	column.add_child(_error)

	var scroll := ScrollContainer.new()
	# THE LIST FOLLOWS THE KEYBOARD. Walking down past the fold moved the highlight to a row
	# that was not on screen, so the menu answered a keypress by showing nothing new.
	scroll.follow_focus = true
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)

	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 1)
	scroll.add_child(_list)


## One pickable row. `payload` comes back on `picked`.
static func item(label: String, payload: Variant, detail := "") -> Dictionary:
	return { "label": label, "payload": payload, "detail": detail }


static func separator() -> Dictionary:
	return { "separator": true }


static func heading(text: String) -> Dictionary:
	return { "heading": text }


## Opens the menu at a SCREEN point.
##
## `freeform` is a FACTORY, not a format string: it takes the trimmed text and returns either
## `{ label, payload }` or `{}` to decline. It has to be, because the payload SHAPE differs per
## menu -- a style-entry pick is a `{export, key, value}` dictionary while an attribute pick is a
## bare name -- and a format string could only ever produce the string. The style-entry menu was
## the one that broke: its freeform row emitted the typed text, the handler read `payload as
## Dictionary`, and typing a key the schema does not list did nothing at all.
##
## An empty Callable means the menu offers only what it was given.
func open_menu(title: String, items: Array, at: Vector2, freeform := Callable()) -> void:
	_prompting = false
	_validate = Callable()
	_items = items
	_freeform = freeform
	_title.text = title
	_search.text = ""
	_search.placeholder_text = "filter..."
	_error.text = ""
	_rebuild()
	popup(Rect2i(Vector2i(at), Vector2i(WIDTH, HEIGHT)))
	_search.grab_focus()


## Opens the name prompt: one field, an inline error, and a Create row.
##
## A failed validation writes the reason and KEEPS THE MENU OPEN, because the alternative is to
## close on a rejected name and make the user reopen the menu to try a second one.
func open_name_prompt(title: String, placeholder: String, validate: Callable, at: Vector2,
		initial := "") -> void:
	_prompting = true
	_validate = validate
	_items = []
	_freeform = Callable()
	_title.text = title
	_search.text = initial
	_search.placeholder_text = placeholder
	_error.text = ""
	_rebuild()
	popup(Rect2i(Vector2i(at), Vector2i(WIDTH, PROMPT_HEIGHT)))
	_search.grab_focus()
	_search.select_all()


func _rebuild() -> void:
	# The rows this indexed are about to be freed.
	_highlight = -1
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()

	if _prompting:
		# THE ERROR CLEARS WHILE YOU TYPE. It was written on a rejected name and then left there,
		# so the reason the LAST attempt failed sat under the field contradicting the one being
		# typed -- and the user had to read it to find out it was stale.
		_error.text = ""
		_list.add_child(_row("Create", func(): _submit(), Parts.TITLE_COLOR))
		return

	var filter := _search.text.strip_edges().to_lower()
	var shown := 0
	for entry in _items:
		var spec := entry as Dictionary
		if bool(spec.get("separator", false)):
			# Hidden while filtering: a divider between two groups that are no longer both on
			# screen is a line separating nothing from nothing.
			if filter.is_empty():
				var rule := ColorRect.new()
				rule.color = Color(0.24, 0.24, 0.29)
				rule.custom_minimum_size = Vector2(0, 1)
				_list.add_child(rule)
			continue
		if spec.has("heading"):
			if filter.is_empty():
				_list.add_child(Parts.section_heading(str(spec["heading"])))
			continue
		var label := str(spec.get("label", ""))
		if not filter.is_empty() and not label.to_lower().contains(filter):
			continue
		var payload: Variant = spec.get("payload")
		_list.add_child(_row(_labelled(spec), func(): _pick(payload), Parts.TITLE_COLOR))
		shown += 1

	var typed := _search.text.strip_edges()
	if _freeform.is_valid() and not typed.is_empty():
		var made: Variant = _freeform.call(typed)
		if made is Dictionary and not (made as Dictionary).is_empty():
			var spec2 := made as Dictionary
			var payload2: Variant = spec2.get("payload")
			_list.add_child(_row(str(spec2.get("label", typed)),
				func(): _pick(payload2), FREEFORM_COLOR))
			return
	if shown == 0:
		var none := Label.new()
		none.text = "(no matches)"
		none.add_theme_font_size_override("font_size", Parts.HINT_FONT_SIZE)
		none.add_theme_color_override("font_color", Parts.HINT_COLOR)
		_list.add_child(none)


## `label` plus its detail, right-aligned in the same row -- what carries "child" / "beside" on a
## create menu and the property type on an attribute menu.
func _labelled(spec: Dictionary) -> String:
	var detail := str(spec.get("detail", ""))
	if detail.is_empty():
		return str(spec.get("label", ""))
	return "%s    %s" % [str(spec.get("label", "")), detail]


func _row(text: String, on_press: Callable, tint: Color) -> Button:
	var row := Button.new()
	row.text = text
	row.flat = true
	# A row you can click looks like one.
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	row.alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.add_theme_color_override("font_color", tint)
	row.pressed.connect(on_press)
	return row


func _pick(payload: Variant) -> void:
	hide()
	picked.emit(payload)


## Enter: submit the name, or take the FIRST MATCH -- the row the list is already showing at the
## top, so typing three letters and pressing return is the whole interaction.
func _submit() -> void:
	if _prompting:
		var typed := _search.text.strip_edges()
		if _validate.is_valid():
			var reason := str(_validate.call(typed))
			if not reason.is_empty():
				_error.text = reason
				return
		hide()
		submitted.emit(typed)
		return
	# THE HIGHLIGHTED ROW, falling back to the first match when the keyboard has not been used --
	# which keeps "type three letters and press return" working exactly as before.
	var rows := _rows()
	if rows.is_empty():
		return
	var index: int = _highlight if _highlight >= 0 and _highlight < rows.size() else 0
	(rows[index] as Button).pressed.emit()


func _input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed:
		return
	match key.keycode:
		KEY_ESCAPE:
			hide()
		KEY_DOWN:
			_move_highlight(1)
		KEY_UP:
			_move_highlight(-1)
		KEY_HOME:
			_set_highlight(0)
		KEY_END:
			_set_highlight(_rows().size() - 1)
		_:
			return
	get_viewport().set_input_as_handled()


## The pickable rows, in the order they are shown. Headings and separators are not among them --
## a keyboard that can land on a heading is a keyboard that appears to be stuck.
func _rows() -> Array:
	var out: Array = []
	for child in _list.get_children():
		if child is Button:
			out.append(child)
	return out


func _move_highlight(delta: int) -> void:
	var rows := _rows()
	if rows.is_empty():
		return
	# WRAPS, because a list you can walk off the end of makes the user look for the end.
	var next := _highlight + delta
	if next < 0:
		next = rows.size() - 1
	elif next >= rows.size():
		next = 0
	_set_highlight(next)


func _set_highlight(index: int) -> void:
	var rows := _rows()
	_highlight = clampi(index, -1, rows.size() - 1)
	for i in rows.size():
		var row: Button = rows[i]
		if i == _highlight:
			var box := StyleBoxFlat.new()
			box.bg_color = Color(Parts.ACCENT_COLOR, 0.16)
			box.corner_radius_top_left = 4
			box.corner_radius_top_right = 4
			box.corner_radius_bottom_left = 4
			box.corner_radius_bottom_right = 4
			row.add_theme_stylebox_override("normal", box)
			_scroll_to(row)
		else:
			row.remove_theme_stylebox_override("normal")


## Keeps the highlighted row on screen. A highlight that scrolls off is a selection the user
## cannot see, which is the same defect as no highlight at all.
func _scroll_to(row: Control) -> void:
	var scroll := _list.get_parent() as ScrollContainer
	if scroll == null:
		return
	var top := row.position.y
	var bottom := top + row.size.y
	if top < scroll.scroll_vertical:
		scroll.scroll_vertical = int(top)
	elif bottom > scroll.scroll_vertical + scroll.size.y:
		scroll.scroll_vertical = int(bottom - scroll.size.y)
