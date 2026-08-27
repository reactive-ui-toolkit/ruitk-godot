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

## An entry was chosen. `kind` is one of the ENTRY_* constants; `name` is the tag, hook or
## component name.
signal entry_activated(kind: String, name: String)

const ENTRY_ELEMENT := "element"
const ENTRY_HOOK := "hook"
const ENTRY_COMPONENT := "component"

## The elements that lead the list. Everything a UI actually starts with -- a box, a label, a
## button -- ahead of the hundred and thirty that follow.
const LEAD_ELEMENTS := [
	"VBoxContainer", "HBoxContainer", "Label", "Button", "PanelContainer",
	"LineEdit", "TextureRect", "ColorRect", "MarginContainer", "ScrollContainer",
]

## The hooks that lead the list, in the order a component usually needs them.
const LEAD_HOOKS := ["useState", "useEffect", "useRef", "useMemo", "useCallback", "useContext"]

## How many rows a section shows before the rest fold away.
const FOLD_AFTER := 10

var graph: Graph = null

var _sections := {}
## Which sections are open. A VIEW state -- it survives a rebuild, because a pane that re-folded
## itself every time the model changed would be unusable while anyone was working.
var _expanded := { ENTRY_ELEMENT: true, ENTRY_HOOK: true, ENTRY_COMPONENT: true }
var _search := ""
var _search_field: LineEdit = null
var _body: VBoxContainer = null


func _init() -> void:
	add_theme_constant_override("separation", 4)
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	_search_field = LineEdit.new()
	_search_field.placeholder_text = "Filter"
	_search_field.clear_button_enabled = true
	_search_field.text_changed.connect(func(text: String):
		_search = text.strip_edges().to_lower()
		rebuild())
	add_child(_search_field)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 2)
	scroll.add_child(_body)


func rebuild() -> void:
	for child in _body.get_children():
		child.queue_free()
		_body.remove_child(child)
	_sections.clear()

	_add_section(ENTRY_COMPONENT, "COMPONENTS", _component_entries())
	_add_section(ENTRY_ELEMENT, "ELEMENTS", _element_entries())
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
	row.flat = true
	row.alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.text = "    " + name
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
