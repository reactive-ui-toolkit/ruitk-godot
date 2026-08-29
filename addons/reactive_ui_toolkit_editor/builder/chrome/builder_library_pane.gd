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

## A WORKSPACE entry was double-clicked: bring its card up on the canvas (capability reference
## §10). Only the tree's own modules answer this -- a native element and a built-in hook have no
## card to go to.
## The user asked to be taken to an entry. Carries the FILE as well as the name: two modules in
## different folders can export the same name, and a listener resolving by name alone frames
## whichever one the projection happened to put first.
signal entry_framed(file_path: String, name: String)


## A new module of `kind` was asked for from the pane's own `+ new` button. The library is where
## a user looks for "something to put in", and a module they have not written yet is exactly that
## -- so the create affordance belongs here rather than only behind a right-click on the canvas,
## which is a gesture you have to already know about.
signal create_requested(kind: int)

const ENTRY_ELEMENT := "element"
const ENTRY_HOOK := "hook"
const ENTRY_COMPONENT := "component"
## The tree's own COMPANION modules, listed by kind (capability reference §10). A style module and
## a util module are things you reach for while building, exactly as a component is -- and until
## they were listed the library could show you a tree's components while silently omitting half
## of what that tree contained.
const ENTRY_STYLE := "style"
const ENTRY_UTIL := "util"
const ENTRY_HOOK_MODULE := "hook_module"

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
var _expanded := {
	ENTRY_ELEMENT: true, ENTRY_HOOK: true, ENTRY_COMPONENT: true,
	ENTRY_STYLE: true, ENTRY_UTIL: true, ENTRY_HOOK_MODULE: true,
}
var _search := ""

## The component whose card is selected on the canvas, so the palette row for it can say so.
## Without it the library is the one region that never reflects the selection every other region
## is showing.
var _selected_component := ""

## The file the selection belongs to, when it has one. A name alone cannot tell two modules apart.
var _selected_path := ""

## Sections the user asked to see in full, by kind. Read by the rebuild, so the extra rows land
## INSIDE their own section rather than after everything else.
var _expanded_fully := {}
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

	for section in _sections_model():
		_add_section(str(section["kind"]), str(section["heading"]), section["entries"])


## The sections in order, as [{ kind, heading, entries }].
##
## Native first, then the tree's own, then hooks -- the order a component is usually assembled in,
## and the order the reference uses. The tree's OWN companion modules get a section per kind
## rather than one merged "modules" list, because what you DO with an entry depends on its kind:
## a style module is dragged onto a row, a util is imported and called.
##
## ONE description, read by the rebuild and by reveal-selected. Written twice they would disagree
## about which section an entry is in, and the fold would open the wrong one.
func _sections_model() -> Array:
	return [
		{ "kind": ENTRY_ELEMENT, "heading": "NATIVE ELEMENTS", "entries": _element_entries() },
		{ "kind": ENTRY_COMPONENT, "heading": "CUSTOM COMPONENTS", "entries": _component_entries() },
		{ "kind": ENTRY_HOOK, "heading": "HOOKS", "entries": _hook_entries() },
		{ "kind": ENTRY_STYLE, "heading": "STYLE MODULES",
			"entries": _module_entries(Module.Kind.STYLE) },
		{ "kind": ENTRY_UTIL, "heading": "UTIL MODULES",
			"entries": _module_entries(Module.Kind.UTIL) },
		{ "kind": ENTRY_HOOK_MODULE, "heading": "HOOK MODULES",
			"entries": _module_entries(Module.Kind.HOOK) },
	]


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


## The open tree's modules of one companion KIND, by exported name.
func _module_entries(kind: int) -> PackedStringArray:
	var out := PackedStringArray()
	if graph == null:
		return out
	for card in graph.cards:
		if card.kind != kind:
			continue
		for export_name in card.exports:
			out.append(export_name)
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
	# AN EMPTY SECTION STILL HAS ITS HEADING. Returning early meant a tree with no style modules
	# showed no STYLE MODULES header at all -- so the pane's answer to "can I make one of these"
	# was indistinguishable from "this builder has no such thing". While FILTERING it is the
	# opposite: a heading with nothing under it is noise on every keystroke.
	if filtered.is_empty() and not _search.is_empty():
		return

	var header := Button.new()
	row_cursor(header)
	header.flat = true
	header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.text = "%s  %s  (%d)" % ["v" if _expanded.get(kind, true) else ">", heading, filtered.size()]
	header.pressed.connect(func():
		_expanded[kind] = not bool(_expanded.get(kind, true))
		rebuild())
	_body.add_child(header)
	_sections[kind] = header
	if not bool(_expanded.get(kind, true)) or filtered.is_empty():
		return

	# A filter is the user asking to see everything that matches, so it overrides the fold: the
	# whole point of typing four characters is that the answer is short.
	# FULL EXPANSION IS PART OF THE MODEL the rebuild reads, not a second pass after it. It used
	# to call `rebuild()` and then `add_child` the remaining entries -- and `add_child` APPENDS,
	# so rows 6..N of the components section landed at the very bottom of the pane, under every
	# other section, outside the heading that counts them. It also cleared the search box to get
	# there, throwing away what the user had typed.
	var full := bool(_expanded_fully.get(kind, false))
	var limit: int = filtered.size() if not _search.is_empty() or full \
		else mini(filtered.size(), FOLD_AFTER)
	for i in range(limit):
		_body.add_child(_entry_row(kind, str(filtered[i])))
	if limit < filtered.size():
		var more := Button.new()
		row_cursor(more)
		more.flat = true
		more.alignment = HORIZONTAL_ALIGNMENT_LEFT
		more.text = "    + %d more" % (filtered.size() - limit)
		more.pressed.connect(func():
			_expanded_fully[kind] = true
			rebuild())
		_body.add_child(more)
	elif full and filtered.size() > FOLD_AFTER:
		# AND IT FOLDS BACK. A one-way expansion leaves a pane that only ever gets longer.
		var less := Button.new()
		row_cursor(less)
		less.flat = true
		less.alignment = HORIZONTAL_ALIGNMENT_LEFT
		less.text = "    - show less"
		less.pressed.connect(func():
			_expanded_fully[kind] = false
			rebuild())
		_body.add_child(less)


## Godot's drag protocol, on the pane rather than on each row: the pane knows which row the
## pointer is over, and one implementation beats one per button.
##
## THE HINT BAR HAS ADVERTISED THIS SINCE THE FIRST CHROME COMMIT and nothing implemented it.
## `drop_library_entry` existed, `builder_drag.gd` existed to resolve where a drop landed, and no
## gesture in the builder could start a drag -- so the primary interaction of a
## direct-manipulation surface was a function nobody could reach.
## Whether entries of this kind name a module IN THE OPEN TREE, rather than something the engine
## or the runtime provides.
static func _is_workspace_kind(kind: String) -> bool:
	return kind == ENTRY_COMPONENT or kind == ENTRY_STYLE 		or kind == ENTRY_UTIL or kind == ENTRY_HOOK_MODULE


func _get_drag_data(at_position: Vector2) -> Variant:
	var row: Control = _row_under(at_position)
	if row == null:
		return null
	var kind := str(row.get_meta("entry_kind", ""))
	var name := str(row.get_meta("entry_name", ""))
	if name.is_empty():
		return null

	var ghost := Label.new()
	ghost.text = row.text.strip_edges()
	ghost.add_theme_color_override("font_color", Parts.ACCENT_COLOR)
	set_drag_preview(ghost)
	return { "source": "library", "kind": kind, "name": name }


## The entry row under a point in this pane's coordinates.
func _row_under(at_position: Vector2):
	for child in _body.get_children():
		if not (child is Button) or not child.has_meta("entry_name"):
			continue
		var control := child as Control
		if Rect2(control.get_global_rect().position - get_global_rect().position,
				control.size).has_point(at_position):
			return control
	return null


## The module a workspace entry comes from, or "" for a native element or a built-in hook.
func _path_exporting(kind: String, name: String) -> String:
	if graph == null or not _is_workspace_kind(kind):
		return ""
	for card in graph.cards:
		if card.exports.has(name):
			return card.file_path
	return ""


## Whether this entry is the one the workspace has selected.
##
## BY PATH when both sides have one, which is what makes two modules exporting the same name
## distinguishable; by name otherwise, which is the only identity a native element has.
func _is_selected(kind: String, name: String) -> bool:
	if not _selected_path.is_empty():
		return _path_exporting(kind, name) == _selected_path
	return kind == ENTRY_COMPONENT and name == _selected_component


func _entry_row(kind: String, name: String) -> Button:
	var row := Button.new()
	row_cursor(row)
	# NOT flat. A palette entry is a drag handle and a click target, and flat text on a panel
	# background reads as a label -- the two things you are meant to drag looked exactly like the
	# heading above them.
	row.flat = false
	row.alignment = HORIZONTAL_ALIGNMENT_LEFT
	# PASS, NOT THE BUTTON DEFAULT. Godot's `Viewport::_gui_get_drag_data` walks UP from the
	# control the press landed on and stops at the first `MOUSE_FILTER_STOP` -- which is a
	# Button's default -- so the pane's `_get_drag_data` was never reached and the library could
	# not be dragged at all. PASS keeps the Button's own press and hover behaviour, so
	# click-to-insert and the double-click framing still work, while letting the press continue
	# up to the pane that knows how to package it.
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	# Elements and components read as the TAG they insert; a hook reads as the call it is. The
	# library's job is to show what will land in the file, and `Label` and `<Label>` are not the
	# same thing to someone scanning markup.
	# Only ELEMENTS and COMPONENTS read as tags: those are the two you write in angle brackets.
	# A hook, a style export and a util are identifiers you call or reference.
	var tagged := kind == ENTRY_ELEMENT or kind == ENTRY_COMPONENT
	row.text = "    " + ("<%s>" % name if tagged else name)
	# THE PATH, when the entry HAS one. Every row carried the same sentence -- its own text plus a
	# gesture the hint bar already states -- so the one thing a tooltip could usefully add, WHICH
	# FILE this name comes from, was the one thing it did not say.
	var from := _path_exporting(kind, name)
	row.tooltip_text = from if not from.is_empty() \
		else "%s -- drag onto a card, or click to insert" % name
	row.set_meta("entry_kind", kind)
	row.set_meta("entry_name", name)
	row.set_meta("entry_path", _path_exporting(kind, name))
	if _is_selected(kind, name):
		# TOGGLE MODE FIRST. Godot's `BaseButton::set_pressed` early-returns while `toggle_mode`
		# is false, so setting them the other way round was a no-op and the selection mirror never
		# painted at all.
		row.toggle_mode = true
		row.button_pressed = true
	row.set_meta("entry_name", name)
	row.pressed.connect(func(): entry_activated.emit(kind, name))
	if _is_workspace_kind(kind):
		row.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton 					and (event as InputEventMouseButton).double_click 					and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
				entry_framed.emit(_path_exporting(kind, name), name))
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


## Points the palette at the component the canvas has selected.
func select_component(name: String) -> void:
	select_entry("", name)


## Mirrors the workspace selection, identified by FILE PATH.
##
## A bare name cannot identify a module. `select_component` was fed `card.exports[0]` of the
## focused module, so a module with NO exports mirrored nothing, a module whose second export was
## the interesting one mirrored the wrong row, and two modules exporting the same name in
## different folders were indistinguishable. The path is what the workspace rows are keyed on.
##
## The name is kept as the fallback, because a native element and a built-in hook have no file --
## for those, the name IS the identity.
func select_entry(file_path: String, name: String) -> void:
	if _selected_path == file_path and _selected_component == name:
		return
	_selected_path = file_path
	_selected_component = name
	_reveal_selected()
	rebuild()


## Opens the fold of whichever section holds the selection.
##
## With FOLD_AFTER at five, selecting the sixth component alphabetically highlighted a row that
## is not on screen -- so the pane's answer to "which one am I looking at" was a blank.
func _reveal_selected() -> void:
	if _selected_path.is_empty() and _selected_component.is_empty():
		return
	for section in _sections_model():
		var kind := str(section["kind"])
		var entries: PackedStringArray = section["entries"]
		for i in range(entries.size()):
			if i < FOLD_AFTER:
				continue
			if _is_selected(kind, str(entries[i])):
				_expanded[kind] = true
				_expanded_fully[kind] = true
				return


## A row the pointer can act on looks like one. Every pane here builds bare `Button`s, which draw
## the OS arrow -- so a list you can click read exactly like a list you cannot.
static func row_cursor(button: Button) -> void:
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
