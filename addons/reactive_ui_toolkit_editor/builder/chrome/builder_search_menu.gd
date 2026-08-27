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
var _freeform_label := ""
var _validate: Callable = Callable()
var _prompting := false


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
	_error.visible = false
	column.add_child(_error)

	var scroll := ScrollContainer.new()
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
## `freeform_label` is a format string taking the typed text (`"Add \"%s\""`); empty means the
## menu offers only what it was given.
func open_menu(title: String, items: Array, at: Vector2, freeform_label := "") -> void:
	_prompting = false
	_validate = Callable()
	_items = items
	_freeform_label = freeform_label
	_title.text = title
	_search.text = ""
	_search.placeholder_text = "filter..."
	_error.visible = false
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
	_freeform_label = ""
	_title.text = title
	_search.text = initial
	_search.placeholder_text = placeholder
	_error.visible = false
	_rebuild()
	popup(Rect2i(Vector2i(at), Vector2i(WIDTH, PROMPT_HEIGHT)))
	_search.grab_focus()
	_search.select_all()


func _rebuild() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()

	if _prompting:
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
	if not _freeform_label.is_empty() and not typed.is_empty():
		_list.add_child(_row(_freeform_label % typed, func(): _pick(typed), FREEFORM_COLOR))
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
				_error.visible = true
				return
		hide()
		submitted.emit(typed)
		return
	for child in _list.get_children():
		if child is Button:
			(child as Button).pressed.emit()
			return


func _input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if key.pressed and key.keycode == KEY_ESCAPE:
		hide()
		get_viewport().set_input_as_handled()
