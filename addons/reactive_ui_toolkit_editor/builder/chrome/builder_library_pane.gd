@tool
class_name RuitkBuilderLibraryPane
extends VBoxContainer
## What can be dropped onto the canvas: host elements, hooks, and the open tree's own components.
##
## The vocabulary is the COMPILER's, not a list kept here. Host tags come from `vocabulary.json`
## (the same file the language server reads) and hooks from `RuitkGuitkx.hook_names()`, so an
## element the compiler accepts is an element the library offers, and neither can quietly grow a
## name the other has never heard of.
##
## A CURATED few lead each section and the rest fold away. The full host vocabulary is a hundred
## and forty Godot classes; a palette that shows all of them shows none of them.

const Compiler = preload("res://addons/reactive_ui_toolkit/guitkx/guitkx.gd")
const Graph = preload("res://addons/reactive_ui_toolkit_editor/builder/canvas/builder_graph.gd")
const Module = preload("res://addons/reactive_ui_toolkit_editor/builder/document/builder_module.gd")
const Parts = preload("res://addons/reactive_ui_toolkit_editor/builder/chrome/builder_chrome_parts.gd")

## An entry was chosen. `kind` is one of the ENTRY_* constants; `name` is the tag, hook or
## component name.
signal entry_activated(kind: String, name: String)

## A new module of `kind` was asked for from the pane's own `+ new` button. The library is where
## a user looks for "something to put in", and a module they have not written yet is exactly that
## -- so the create affordance belongs here rather than only behind a right-click on the canvas,
## which is a gesture you have to already know about.
signal create_requested(kind: int)

const ENTRY_ELEMENT := "element"
const ENTRY_HOOK := "hook"
const ENTRY_COMPONENT := "component"

## The elements that lead the list. Everything a UI actually starts with -- a box, a label, a
## button -- ahead of the hundred and thirty that follow.
## SHORT on purpose. The list used to lead with ten, and with 55 elements behind them the two
## sections below -- the tree's own components, and the hooks the hint bar tells you to drag --
## were pushed off the bottom of the pane where nobody could reach them. A palette that shows one
## section shows one section.
const LEAD_ELEMENTS := ["VBoxContainer", "HBoxContainer", "Label", "Button", "PanelContainer"]

## The hooks that lead the list, in the order a component usually needs them.
const LEAD_HOOKS := ["useState", "useEffect", "useRef", "useMemo", "useCallback", "useContext"]

## How many rows a section shows before the rest fold away.
const FOLD_AFTER := 5

var graph: Graph = null

var _sections := {}
## Which sections are open. A VIEW state -- it survives a rebuild, because a pane that re-folded
## itself every time the model changed would be unusable while anyone was working.
var _expanded := { ENTRY_ELEMENT: true, ENTRY_HOOK: true, ENTRY_COMPONENT: true }
var _search := ""
var _search_field: LineEdit = null
var _create_menu: PopupMenu = null
var _body: VBoxContainer = null


func _init() -> void:
	add_theme_constant_override("separation", 4)
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	var new_button := Button.new()
	new_button.text = "+ new"
	new_button.flat = true
	new_button.pressed.connect(_open_create_menu)
	add_child(Parts.pane_header("Library", new_button))

	_create_menu = PopupMenu.new()
	# A menu that names itself: this one is reached from a "+ new" button whose label is gone the
	# moment the popup covers it.
	_create_menu.add_separator("CREATE")
	_create_menu.add_item("New component (.guitkx)", Module.Kind.COMPONENT)
	_create_menu.add_item("New style module (.style.guitkx)", Module.Kind.STYLE)
	_create_menu.add_item("New hook module (.hooks.guitkx)", Module.Kind.HOOK)
	_create_menu.add_item("New util module (.guitkx)", Module.Kind.UTIL)
	_create_menu.id_pressed.connect(func(id: int): create_requested.emit(id))
	add_child(_create_menu)

	_search_field = LineEdit.new()
	_search_field.placeholder_text = "search library..."
	_search_field.clear_button_enabled = true
	_search_field.text_changed.connect(func(text: String):
		_search = text.strip_edges().to_lower()
		rebuild())
	add_child(_search_field)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	add_child(scroll)

	# The scroll wraps ALL THREE SECTIONS, and the body is told to fill it. Sized to its content
	# instead, the container measured only as far as the first section, so everything below the
	# native elements -- the tree's own components, and the hooks the hint bar tells you to drag
	# onto a body -- ran off the bottom of the pane with no way to scroll to them.
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 2)
	scroll.add_child(_body)


func rebuild() -> void:
	for child in _body.get_children():
		child.queue_free()
		_body.remove_child(child)
	_sections.clear()

	# Native first, then the tree's own, then hooks -- the order a component is usually assembled
	# in, and the order the Unity leg uses.
	_add_section(ENTRY_ELEMENT, "NATIVE ELEMENTS", _element_entries())
	_add_section(ENTRY_COMPONENT, "CUSTOM COMPONENTS", _component_entries())
	_add_section(ENTRY_HOOK, "HOOKS", _hook_entries())


## The open tree's own components -- what the user is building, offered alongside what the engine
## provides, because from the canvas's point of view they are the same kind of thing.
func _component_entries() -> PackedStringArray:
	var out := PackedStringArray()
	if graph == null:
		return out
	for card in graph.cards:
		if card.kind != Module.Kind.COMPONENT:
			continue
		for export_name in card.exports:
			out.append(export_name)
	# ALPHABETICAL. Projection order is graph order, which is the order the tree was walked in --
	# stable, but meaningless to someone scanning a list for a name.
	out.sort()
	return out


func _element_entries() -> PackedStringArray:
	var out := PackedStringArray()
	var seen := {}
	for tag in LEAD_ELEMENTS:
		out.append(tag)
		seen[tag] = true
	var rest := PackedStringArray()
	for tag in Compiler.host_tags().keys():
		if not seen.has(str(tag)):
			rest.append(str(tag))
	rest.sort()
	out.append_array(rest)
	return out


func _hook_entries() -> PackedStringArray:
	var out := PackedStringArray()
	var seen := {}
	for hook in LEAD_HOOKS:
		out.append(hook)
		seen[hook] = true
	var rest := PackedStringArray()
	for hook in Compiler.hook_names():
		if not seen.has(str(hook)):
			rest.append(str(hook))
	rest.sort()
	out.append_array(rest)
	return out


func _add_section(kind: String, heading: String, entries: PackedStringArray) -> void:
	var filtered := PackedStringArray()
	for entry in entries:
		if _search.is_empty() or str(entry).to_lower().contains(_search):
			filtered.append(entry)
	if filtered.is_empty():
		return

	var header := Button.new()
	header.flat = true
	header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.text = "%s  %s  (%d)" % ["v" if _expanded.get(kind, true) else ">", heading, filtered.size()]
	header.pressed.connect(func():
		_expanded[kind] = not bool(_expanded.get(kind, true))
		rebuild())
	_body.add_child(header)
	_sections[kind] = header
	if not bool(_expanded.get(kind, true)):
		return

	# A filter is the user asking to see everything that matches, so it overrides the fold: the
	# whole point of typing four characters is that the answer is short.
	var limit: int = filtered.size() if not _search.is_empty() else mini(filtered.size(), FOLD_AFTER)
	for i in range(limit):
		_body.add_child(_entry_row(kind, str(filtered[i])))
	if limit < filtered.size():
		var more := Button.new()
		more.flat = true
		more.alignment = HORIZONTAL_ALIGNMENT_LEFT
		more.text = "    + %d more" % (filtered.size() - limit)
		more.pressed.connect(func():
			_search_field.text = ""
			_search = ""
			_expanded[kind] = true
			_show_all(kind, filtered))
		_body.add_child(more)


func _show_all(kind: String, entries: PackedStringArray) -> void:
	# Expanding one section fully is a one-shot: the next rebuild folds it again, which is what
	# keeps the pane usable after the user has moved on to something else.
	rebuild()
	for i in range(FOLD_AFTER, entries.size()):
		_body.add_child(_entry_row(kind, str(entries[i])))


func _entry_row(kind: String, name: String) -> Button:
	var row := Button.new()
	# NOT flat. A palette entry is a drag handle and a click target, and flat text on a panel
	# background reads as a label -- the two things you are meant to drag looked exactly like the
	# heading above them.
	row.flat = false
	row.alignment = HORIZONTAL_ALIGNMENT_LEFT
	# Elements and components read as the TAG they insert; a hook reads as the call it is. The
	# library's job is to show what will land in the file, and `Label` and `<Label>` are not the
	# same thing to someone scanning markup.
	row.text = "    " + (name if kind == ENTRY_HOOK else "<%s>" % name)
	row.tooltip_text = "%s -- drag onto a card, or click to insert" % name
	row.set_meta("entry_kind", kind)
	row.set_meta("entry_name", name)
	row.pressed.connect(func(): entry_activated.emit(kind, name))
	return row


## Every entry currently on offer, as [{ kind, name }] -- what a test asserts against, and what a
## drag source enumerates.
func entries() -> Array:
	var out: Array = []
	for child in _body.get_children():
		if child.has_meta("entry_name"):
			out.append({ "kind": str(child.get_meta("entry_kind")), "name": str(child.get_meta("entry_name")) })
	return out


func set_filter(text: String) -> void:
	_search_field.text = text
	_search = text.strip_edges().to_lower()
	rebuild()


## Opens or closes a section. A VIEW state, so it survives a rebuild -- a pane that re-folded
## itself every time the model changed would be unusable while anyone was working.
func set_section_expanded(kind: String, open: bool) -> void:
	_expanded[kind] = open
	rebuild()


func is_section_expanded(kind: String) -> bool:
	return bool(_expanded.get(kind, true))


## Opens the create menu under the `+ new` button.
func _open_create_menu() -> void:
	_create_menu.position = Vector2i(get_screen_position() + Vector2(24, 28))
	_create_menu.popup()


## The create menu, for a harness or a caller that wants it opened without a click.
func open_create_menu() -> void:
	_open_create_menu()
