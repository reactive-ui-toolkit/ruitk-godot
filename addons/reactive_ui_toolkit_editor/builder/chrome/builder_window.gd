@tool
class_name RuitkBuilderWindow
extends Control
## The builder, assembled: the folder and library panes on the left, the canvas in the middle,
## the source pane on the right, the console along the bottom, and a toolbar over all of it.
##
## THE WINDOW IS THE ONLY THING THAT KNOWS ABOUT ALL THE PARTS. Every pane below it takes a model
## and emits what happened; none of them reaches for another. That is what keeps them testable on
## their own, and it is why the wiring lives in one readable block instead of being spread across
## six files that each know a little about the others.
##
## ONE FUNNEL FOR EVERY CHANGE. A buffer edit from the source pane, a drop on the canvas and a
## replayed undo all go through `apply_edit`, so they produce the same ledger entry, the same
## preview round and the same re-projection. A second path into the model is how two surfaces
## come to disagree about what the file says.
##
## Godot's `PopupMenu` is a real popup with real submenus and correct focus, so the context menus
## here are ordinary menus. The Unity leg builds its own out of a panel layer because a custom
## EditorWindow cannot own a submenu without the child killing its parent -- none of which
## applies here, and inventing a menu system to match would be a cost with no return.

const Workspace = preload("res://addons/reactive_ui_toolkit_editor/builder/document/builder_workspace.gd")
const Module = preload("res://addons/reactive_ui_toolkit_editor/builder/document/builder_module.gd")
const Paths = preload("res://addons/reactive_ui_toolkit_editor/builder/document/builder_paths.gd")
const Ledger = preload("res://addons/reactive_ui_toolkit_editor/builder/document/builder_ledger.gd")
const Journal = preload("res://addons/reactive_ui_toolkit_editor/builder/document/builder_journal.gd")
const Service = preload("res://addons/reactive_ui_toolkit_editor/builder/canvas/builder_graph_service.gd")
const Graph = preload("res://addons/reactive_ui_toolkit_editor/builder/canvas/builder_graph.gd")
const CanvasHost = preload("res://addons/reactive_ui_toolkit_editor/builder/canvas/builder_canvas_host.gd")
const CanvasLayout = preload("res://addons/reactive_ui_toolkit_editor/builder/canvas/builder_canvas_layout.gd")
const Preview = preload("res://addons/reactive_ui_toolkit_editor/builder/preview/builder_preview.gd")
const FolderPane = preload("res://addons/reactive_ui_toolkit_editor/builder/chrome/builder_folder_pane.gd")
const LibraryPane = preload("res://addons/reactive_ui_toolkit_editor/builder/chrome/builder_library_pane.gd")
const SourcePane = preload("res://addons/reactive_ui_toolkit_editor/builder/chrome/builder_source_pane.gd")
const Console = preload("res://addons/reactive_ui_toolkit_editor/builder/chrome/builder_console.gd")
const InlineEditor = preload("res://addons/reactive_ui_toolkit_editor/builder/chrome/builder_inline_editor.gd")
const Edits = preload("res://addons/reactive_ui_toolkit_editor/builder/edits/builder_edits.gd")
const Specifiers = preload("res://addons/reactive_ui_toolkit_editor/builder/document/builder_specifiers.gd")
const Drag = preload("res://addons/reactive_ui_toolkit_editor/builder/edits/builder_drag.gd")
const AddonSettings = preload("res://addons/reactive_ui_toolkit_editor/editor/ruitk_editor_settings.gd")
const Parts = preload("res://addons/reactive_ui_toolkit_editor/builder/chrome/builder_chrome_parts.gd")
const SearchMenu = preload("res://addons/reactive_ui_toolkit_editor/builder/chrome/builder_search_menu.gd")
const Attributes = preload("res://addons/reactive_ui_toolkit_editor/builder/edits/builder_attributes.gd")
const Compiler = preload("res://addons/reactive_ui_toolkit/guitkx/guitkx.gd")
const Schema = preload("res://addons/reactive_ui_toolkit_editor/lsp/guitkx_schema.gd")
const PreviewPane = preload("res://addons/reactive_ui_toolkit_editor/builder/chrome/builder_preview_pane.gd")
const Palette = preload("res://addons/reactive_ui_toolkit_editor/builder/canvas/canvas_palette.gd")
const Metrics = preload("res://addons/reactive_ui_toolkit_editor/builder/canvas/builder_canvas_metrics.gd")

## The tree changed in a way the host should know about -- for the plugin's title, or a prompt on
## close.
signal dirty_changed(has_unsaved: bool)

## Menu ids. Named rather than positional, so inserting an item cannot silently re-point another.
enum MenuId { SAVE, ABORT, UNDO, REDO, FIT_VIEW, REVEAL, HISTORY, TRACE, HELP, _HISTORY_OLD }

## The three detail bands, NAMED. The canvas already had them — as a zoom threshold nobody could
## see, so a user could not tell which band they were in or ask for one. The Unity leg puts them
## on a dropdown, and a named layer is the difference between a level of detail and an accident
## of how far you happened to scroll.
const LAYERS := [
	{ "title": "Layer 1 — Architecture", "zoom": Metrics.LAYER_PRESETS[0] },
	{ "title": "Layer 2 — Cards", "zoom": Metrics.LAYER_PRESETS[1] },
	{ "title": "Layer 3 — Edit", "zoom": Metrics.LAYER_PRESETS[2] },
]
## Card-menu ids, started past zero. `add_submenu_item` takes no id and Godot assigns it one from
## the low end, so ids counted from 0 collided with it -- `get_item_index(RENAME)` answered with the
## submenu row, and setting its text put "Rename ..." on the item that opens New.
enum CardMenuId { OPEN = 100, RENAME = 101, DELETE = 102, REVEAL_CARD = 103 }

## Row-menu ids, in their own range for the same reason the card menu's are.
enum RowMenuId {
	ADD_ATTRIBUTE = 200, ADD_CHILD = 201, REMOVE_ATTRIBUTE = 202,
	WRAP_IF = 203, WRAP_FOR = 204, DELETE_ROW = 205, EDIT_HEADER = 206,
	ADD_ELSE = 207, ADD_ELSE_IF = 208, DELETE_CLAUSE = 209, EDIT_ATTRIBUTE = 210,
	APPLY_STYLE = 211, UNWRAP = 212, ADD_STYLE_ENTRY = 213,
}

var workspace: Workspace = null
var ledger := Ledger.new()
var preview := Preview.new()

var graph: Graph = null
var layout: CanvasLayout = null

var _canvas: CanvasHost = null
var _folders: FolderPane = null
var _library: LibraryPane = null
var _source: SourcePane = null
var _console: Console = null
var _inline: InlineEditor = null
var _toolbar: HBoxContainer = null
var _status: Label = null
var _card_menu: PopupMenu = null
var _new_menu: PopupMenu = null
var _row_menu: PopupMenu = null
var _search_menu: SearchMenu = null
## What the open search menu is choosing. One field, because only one menu is open at a time.
var _search_purpose := ""
## The module kind a create prompt is naming.
var _pending_kind := -1
var _menu_row = null

## The header text a wrap just seeded, waiting for the editor to open on it once the edit has been
## applied and the card re-projected. Empty when the pending action is not a wrap.
var _seed_header_edit := ""

## Set only while a save is resuming from its own deletion confirmation, so the second pass does
## not ask again.
var _deletions_agreed := false
var _menu_card := -1
var _menu_at := Vector2.ZERO
var _pending_attribute := {}

## The card menu's header row: the only item addressed positionally.
const _HEADER_ITEM := 0
## The "New" submenu row, immediately under the header. Like the header it is addressed by INDEX,
## because `add_submenu_item` takes no id.
const _NEW_SUBMENU_ITEM := 1
var _canvas_menu: PopupMenu = null
var _preview_pane: PreviewPane = null
var _layers: OptionButton = null
var _history_menu: PopupMenu = null
var _hint: Label = null
var _syncing_layer := false
var _empty_state: Control = null
var _toast: Label = null
## When the toast should go, in milliseconds since start. 0 = nothing showing.
var _toast_until := 0

var _focus_path := ""
var _menu_target := ""
var _menu_world := Vector2.ZERO
var _was_dirty := false


func _init() -> void:
	# Focusable, or the window never sees a key at all.
	focus_mode = Control.FOCUS_ALL
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_wire()


func _exit_tree() -> void:
	preview.teardown()


## The history, as a list you can jump into.
##
## Ported from the Unity leg's `ToggleHistory` / `JumpHistoryTo`. Undo and Redo alone make the
## ledger a stack you can only step through one entry at a time and cannot see -- so "put it back
## the way it was five edits ago" means pressing Ctrl+Z five times and hoping, with no way to know
## where you are until you look at the file.
func _show_history() -> void:
	var rows: Array = []
	var entries := ledger.entries()
	if entries.is_empty():
		rows.append(SearchMenu.item("no actions yet", -1))
	else:
		var at := ledger.cursor()
		for i in range(entries.size()):
			# Entries BELOW the cursor are applied. The one AT the cursor is what redo would do
			# next, so the marker sits on the last applied row.
			var marker := "•  " if i == at - 1 else "    "
			rows.append(SearchMenu.item(
				"%s%s" % [marker, entries[i].description], i + 1,
				"applied" if i < at else "undone"))
		rows.append(SearchMenu.separator())
		rows.append(SearchMenu.item("    (before everything)", 0, "undone"))
	_search_purpose = "history"
	_search_menu.open_menu("history — click a row to jump there", rows, _toolbar_screen_at())


## Walks the ledger to `target` applied entries, in whichever direction gets there.
func _jump_history_to(target: int) -> void:
	var moved := false
	while ledger.cursor() > target and undo():
		moved = true
	while ledger.cursor() < target and redo():
		moved = true
	if moved:
		toast("History — %d action(s) applied" % ledger.cursor())


## Under the toolbar, where the command that opened the menu lives.
func _toolbar_screen_at() -> Vector2:
	return _toolbar.get_screen_position() + Vector2(0, _toolbar.size.y)


## Says something, briefly, over the canvas.
##
## Ported from the Unity leg's `Toast`. Every refusal in this builder used to be silent: a drop
## that could not be placed, an edit on a read-only module, a rename that collided. Silence reads
## as a bug in the tool rather than an answer from it.
func toast(message: String) -> void:
	if _toast == null or message.strip_edges().is_empty():
		return
	_toast.text = message
	_toast.visible = true
	_toast.reset_size()
	_toast_until = Time.get_ticks_msec() + TOAST_MSEC


## How long a toast stays up.
const TOAST_MSEC := 3200


func _tick_toast() -> void:
	if _toast == null or not _toast.visible:
		return
	if Time.get_ticks_msec() >= _toast_until:
		_toast.visible = false


## The keyboard model, ported from the Unity leg's `OnKeyDown`.
##
## Ctrl+S saves, Ctrl+Z / Ctrl+Shift+Z / Ctrl+Y walk the ACTION LEDGER -- not the focused file's
## own undo stack, so a gesture that touched two files reverts as one step and from whichever
## file happens to be in focus. Unmodified Delete deletes the selection and Escape cancels the
## edit in progress.
##
## ALL OF IT IS OFF WHILE A TEXT SURFACE HAS FOCUS. Delete inside the source pane means "delete a
## character" and Escape there is the field's own cancel; a canvas keyboard model that fired
## under one would eat both.
## THE CHORDS ARE DELIVERED TREE-WIDE, not to whoever holds focus.
##
## This was `_gui_input`, which Godot delivers only to `gui.key_focus` -- and nothing in the
## builder ever focused the window except one of the three entry routes, so the entire keyboard
## model was unreachable from the menu item and stopped working the moment a click landed on the
## folder tree, the library, the source pane or the layer selector. `_shortcut_input` runs for the
## whole viewport after the focused Control has declined the event, which is the Godot shape of
## what Unity gets from TrickleDown-plus-consume.
func _shortcut_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not (event as InputEventKey).pressed:
		return
	var key := event as InputEventKey

	# THE CTRL BRANCH RUNS FIRST, before the typing guard, which is the order Unity uses. The
	# guard exists so bare Delete and Escape belong to whatever field is being typed in; it must
	# not also hand Ctrl+Z to that field, because once a source-pane edit is a ledger entry the
	# ledger is where undo has to happen.
	if key.ctrl_pressed or key.meta_pressed:
		match key.keycode:
			KEY_S:
				save()
			KEY_Z:
				redo() if key.shift_pressed else undo()
			KEY_Y:
				redo()
			_:
				return
		get_viewport().set_input_as_handled()
		return

	if _typing_focused():
		return
	match key.keycode:
		KEY_DELETE:
			_delete_selection()
		KEY_ESCAPE:
			_cancel_active_edit()
		_:
			return
	get_viewport().set_input_as_handled()


## True while something that takes typing owns the keyboard.
func _typing_focused() -> bool:
	var focused := get_viewport().gui_get_focus_owner() if get_viewport() != null else null
	if focused == null:
		return false
	return focused is TextEdit or focused is LineEdit or focused is CodeEdit


## Delete: the selected ROW when one is selected, else the selected MODULE.
##
## The row first, because it is the more specific selection and the one the user most recently
## made. Deleting a whole module on a keypress meant for one element is not a mistake a builder
## should let happen quietly.
func _delete_selection() -> void:
	if _menu_row != null and not _menu_target.is_empty() and workspace != null:
		var module := workspace.try_get(_menu_target)
		if module != null and not module.read_only:
			var after := Edits.remove(module.buffer_text, _menu_row)
			if after != module.buffer_text:
				apply_edit(_menu_target, after, "Delete %s" % _menu_row.text.strip_edges())
				_menu_row = null
				return
	if not _focus_path.is_empty():
		delete_module(_focus_path)


## Escape: close whatever is open, innermost first.
func _cancel_active_edit() -> void:
	if _search_menu != null and _search_menu.visible:
		_search_menu.hide()
		return
	if _inline != null and _inline.is_open():
		_inline.cancel()
		return
	if _canvas != null:
		_canvas.select_card(-1)
	_menu_row = null


## The builder drives its own idle work: the debounced preview round and the crash journal.
##
## Here rather than in the host that opened it, because the cadence is the builder's own business
## and a host that forgot to pump it would leave the preview permanently one edit behind -- with
## nothing to show for it, since a missed tick looks exactly like an edit that changed nothing.
func _process(_delta: float) -> void:
	tick()


# ── Assembly ─────────────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(column)

	column.add_child(_build_toolbar())

	var body := HSplitContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)

	# The folder tree is a handful of short rows; the library is three sections of many. Split at
	# the middle, the tree sat mostly empty over a library that could not show its second section.
	var left := VSplitContainer.new()
	left.custom_minimum_size = Vector2(260, 0)
	body.add_child(left)
	# The tree, under a header of its own, so the left column reads as two named sections the way
	# the reference's does.
	var folders_column := VBoxContainer.new()
	folders_column.add_theme_constant_override("separation", 4)
	folders_column.custom_minimum_size = Vector2(0, 240)
	folders_column.add_child(Parts.pane_header("Folders"))
	left.add_child(folders_column)
	_folders = FolderPane.new()
	_folders.size_flags_vertical = Control.SIZE_EXPAND_FILL
	folders_column.add_child(_folders)
	_library = LibraryPane.new()
	left.add_child(_library)
	# NEGATIVE: a VSplitContainer's offset is measured from the centre, so a positive one hands
	# the top child MORE than half -- which put the library in a strip at the bottom, the exact
	# problem the split was being set to fix.
	left.split_offset = -210

	var middle := VSplitContainer.new()
	middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(middle)

	# The canvas and the one floating inline editor share a layer, so the editor can sit over a
	# card without the canvas clipping it away.
	var canvas_layer := Control.new()
	canvas_layer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas_layer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas_layer.custom_minimum_size = Vector2(0, 420)
	middle.add_child(canvas_layer)
	_canvas = CanvasHost.new()
	canvas_layer.add_child(_canvas)
	_inline = InlineEditor.new()
	canvas_layer.add_child(_inline)

	# The onboarding panel sits on the canvas layer and hides itself the moment a tree opens.
	# A builder whose empty state is an empty grey rectangle has told a first-time user nothing:
	# not what it is, not that nothing is written until Save, and not that the four things they
	# might want to make are one click away.
	_empty_state = _build_empty_state()
	canvas_layer.add_child(_empty_state)

	# THE CONSOLE IS NOT A REGION OF THE WINDOW. It was mine, not the reference's, and it spent
	# its life as a strip along the bottom of the canvas saying "no problems" -- a permanent
	# fixture reporting the absence of news, in the space the canvas wanted. It lives behind
	# Trace now, alongside the help, and comes forward on its own when a round actually fails.
	_console = Console.new()
	_console.visible = false
	middle.add_child(_console)

	# The right column is TWO panes, the way the Unity leg has it: what the component looks like
	# above what it says. Source alone answers "what did I write"; only the preview answers "what
	# did I build", and that is the question a visual builder is for.
	var right := VSplitContainer.new()
	right.custom_minimum_size = Vector2(380, 0)
	body.add_child(right)
	_preview_pane = PreviewPane.new()
	_preview_pane.preview = preview
	right.add_child(_preview_pane)
	_source = SourcePane.new()
	right.add_child(_source)

	# A window that has never opened a tree has also never refreshed: nothing had called
	# `_refresh_status` or rebuilt the folder pane, so the two places that are supposed to say
	# "no tree open" said nothing at all -- which is how the empty state came to be the one state
	# with no words in it.
	_folders.rebuild()
	_refresh_status()

	# A toast layer over everything, for the things that are neither a diagnostic nor a dialog:
	# an operation that declined, a save that wrote nothing, a placement that could not be made.
	# Without one those either go to the console, where nobody is looking during a drag, or
	# nowhere at all -- which is how a refused gesture becomes "the builder ignored me".
	_toast = Label.new()
	_toast.visible = false
	_toast.z_index = 100
	_toast.add_theme_color_override("font_color", Color(0.95, 0.95, 0.98))
	var toast_box := StyleBoxFlat.new()
	toast_box.bg_color = Color(0.16, 0.16, 0.20, 0.96)
	toast_box.border_color = Color(0.36, 0.59, 0.96)
	toast_box.set_border_width_all(1)
	toast_box.set_corner_radius_all(6)
	toast_box.set_content_margin_all(10)
	_toast.add_theme_stylebox_override("normal", toast_box)
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	add_child(_toast)

	_hint = Parts.hint_bar(PackedStringArray([
		"Wheel: zoom (Ctrl+wheel over a scrolling section)",
		"Drag Library items onto rows (top=before, bottom=after, middle=inside) or BODY (hooks)",
		"Drag rows to reorder",
		"Right-click rows / cards / canvas for typed attributes, directives, delete, create",
		"L3: click attrs / badges / style entries to edit",
		"Source pane: edit → apply re-parses",
		"Drag splitters to resize",
	]))
	column.add_child(_hint)

	# A card's menu leads with CREATE, because the commonest thing to want next to a component is
	# another module related to it -- and a create action reached from the card carries where it
	# goes with it: a component becomes a CHILD of the one clicked, the companions land BESIDE it.
	_new_menu = PopupMenu.new()
	_new_menu.name = "New"
	_new_menu.add_item("New component            child", Module.Kind.COMPONENT)
	_new_menu.add_item("New style module        beside", Module.Kind.STYLE)
	_new_menu.add_item("New hook module      beside", Module.Kind.HOOK)
	_new_menu.add_item("New util module         beside", Module.Kind.UTIL)
	_new_menu.id_pressed.connect(_on_card_new)

	_card_menu = PopupMenu.new()
	# A header naming the module the menu is about. "Delete" over a canvas of five cards is a
	# question the user answers from memory of where they right-clicked.
	# Index 0, and nothing else is ever addressed by index.
	_card_menu.add_separator("")
	_card_menu.add_child(_new_menu)
	_card_menu.add_submenu_item("New", "New")
	_card_menu.add_separator()
	_card_menu.add_item("Open", CardMenuId.OPEN)
	_card_menu.add_item("Rename...", CardMenuId.RENAME)
	_card_menu.add_separator()
	_card_menu.add_item("Delete", CardMenuId.DELETE)
	add_child(_card_menu)

	# The canvas's own menu: what you can do with the SURFACE, plus the create actions, because
	# right-clicking empty canvas is where someone reaches for "put something here".
	_canvas_menu = PopupMenu.new()
	_canvas_menu.add_separator("CANVAS")
	_canvas_menu.add_item("Fit to view", MenuId.FIT_VIEW)
	_canvas_menu.add_separator()
	_canvas_menu.add_child(_canvas_new_menu())
	_canvas_menu.add_submenu_item("New", "CanvasNew")
	add_child(_canvas_menu)

	_search_menu = SearchMenu.new()
	_search_menu.picked.connect(_on_search_picked)
	_search_menu.submitted.connect(_on_search_submitted)
	add_child(_search_menu)

	_row_menu = PopupMenu.new()
	_row_menu.id_pressed.connect(_on_row_menu)
	add_child(_row_menu)

	_history_menu = PopupMenu.new()
	_history_menu.add_item("Undo", MenuId.UNDO)
	_history_menu.add_item("Redo", MenuId.REDO)
	add_child(_history_menu)


## The "nothing open yet" panel: what this is, what it will not do behind your back, and the four
## things you can start.
func _build_empty_state() -> Control:
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_PASS

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	centre.add_child(column)

	var heading := Label.new()
	heading.text = "Start a UI"
	heading.add_theme_font_size_override("font_size", 26)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(heading)

	var subtitle := Label.new()
	subtitle.text = "Nothing is written to disk until you press Save."
	subtitle.add_theme_color_override("font_color", Parts.TITLE_COLOR)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(subtitle)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	for entry in [
		{ "label": "New component", "kind": Module.Kind.COMPONENT },
		{ "label": "New style module", "kind": Module.Kind.STYLE },
		{ "label": "New hook module", "kind": Module.Kind.HOOK },
		{ "label": "New util module", "kind": Module.Kind.UTIL },
	]:
		var spec := entry as Dictionary
		var button := Button.new()
		button.text = str(spec["label"])
		var kind := int(spec["kind"])
		button.pressed.connect(func(): prompt_create(kind))
		buttons.add_child(button)
	column.add_child(buttons)

	var hint := Label.new()
	hint.text = "...or double-click a .guitkx file in the FileSystem dock to edit an existing tree."
	hint.add_theme_font_size_override("font_size", Parts.HINT_FONT_SIZE)
	hint.add_theme_color_override("font_color", Parts.HINT_COLOR)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(hint)
	return centre


## The create submenu the canvas menu carries.
func _canvas_new_menu() -> PopupMenu:
	var menu := PopupMenu.new()
	menu.name = "CanvasNew"
	menu.add_item("New component", Module.Kind.COMPONENT)
	menu.add_item("New style module", Module.Kind.STYLE)
	menu.add_item("New hook module", Module.Kind.HOOK)
	menu.add_item("New util module", Module.Kind.UTIL)
	menu.id_pressed.connect(prompt_create)
	return menu


## A library entry was clicked. Inserts it where the selection is.
## Double-clicking a workspace entry BRINGS ITS CARD UP: the canvas zooms so the card fills the
## surface and centres on it.
##
## The library is how you find a module by name on a tree too big to scan visually, so the entry
## has to be able to take you to it -- otherwise finding it in the list and then finding it on the
## canvas are two separate searches.
func _on_library_framed(name: String) -> void:
	if graph == null:
		return
	for index in graph.cards.size():
		if graph.cards[index].exports.has(name):
			_canvas.frame_card(index)
			select_module(graph.cards[index].file_path)
			return


## "+ new" in the library creates AT THE TREE ROOT (capability reference §10).
##
## The library is not pointing at anywhere in particular -- it is a list of everything -- so there
## is no right-click target to inherit a location from, and the root is the one answer that does
## not depend on what happens to be selected.
func _on_library_create(kind: int) -> void:
	_menu_target = ""
	prompt_create(kind)


func _on_library_activated(kind: String, name: String) -> void:
	if graph == null or _focus_path.is_empty():
		toast("Select a card first — a click in the library inserts into the selected module.")
		return
	var index := graph.index_of(_focus_path)
	if index < 0:
		return
	var card = graph.cards[index]
	var module := workspace.try_get(card.file_path)
	if module == null or module.read_only:
		toast("%s is read-only." % card.title)
		return

	var before := module.buffer_text
	var after := before
	if kind == LibraryPane.ENTRY_HOOK:
		after = Edits.insert_setup_line(before, card, "var _ = %s()" % name)
	else:
		# Into the LAST markup row, which is where "add one more" means on a card you are
		# looking at. A drag says where precisely; a click says "somewhere sensible".
		if card.markup.is_empty():
			toast("%s has no markup to add to yet." % card.title)
			return
		var row = card.markup[card.markup.size() - 1]
		after = _with_component_import(
			Edits.insert(before, card, row, Drag.markup_for(name), Edits.Placement.AFTER),
			card.file_path, name)
	if after == before:
		toast("Couldn't insert <%s> there." % name)
		return
	apply_edit(card.file_path, after, "Add %s to %s" % [name, card.title])


## The header: what tree is open, which layer it is drawn at, the commands, and the legend that
## makes the canvas's colours mean something.
func _build_toolbar() -> HBoxContainer:
	_toolbar = HBoxContainer.new()
	_toolbar.add_theme_constant_override("separation", 6)

	var title := Label.new()
	title.text = "RUITK Visual Editor"
	title.add_theme_color_override("font_color", Palette.kind_tint(0))
	_toolbar.add_child(title)

	_status = Label.new()
	_status.add_theme_font_size_override("font_size", Parts.TITLE_FONT_SIZE)
	_status.add_theme_color_override("font_color", Parts.TITLE_COLOR)
	_toolbar.add_child(_status)

	_layers = OptionButton.new()
	for layer in LAYERS:
		_layers.add_item(str((layer as Dictionary)["title"]))
	_layers.selected = 1
	_layers.item_selected.connect(_on_layer_chosen)
	_toolbar.add_child(_layers)

	_toolbar.add_child(VSeparator.new())
	# UNDO AND REDO HAVE A VISIBLE DOOR. The chords are the fast path, but they were the ONLY
	# path -- and the enable/disable sweep that greys commands by `can_undo`/`can_redo` had no
	# button to act on, so it swept nothing. A destructive canvas is one where the way back is
	# discoverable.
	_toolbar.add_child(_tool_button("Undo", MenuId.UNDO))
	_toolbar.add_child(_tool_button("Redo", MenuId.REDO))
	_toolbar.add_child(VSeparator.new())
	_toolbar.add_child(_tool_button("History", MenuId.HISTORY))
	_toolbar.add_child(_tool_button("Trace", MenuId.TRACE))
	_toolbar.add_child(_tool_button("? How to drive it", MenuId.HELP))
	_toolbar.add_child(VSeparator.new())
	_toolbar.add_child(_tool_button("Save", MenuId.SAVE))
	_toolbar.add_child(_tool_button("Abort", MenuId.ABORT))

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_toolbar.add_child(spacer)

	# The legend, and it is not decoration: the canvas says what a module IS with a colour, and a
	# colour with no key is a colour the reader has to reverse-engineer from the filenames.
	var legend := HBoxContainer.new()
	legend.add_theme_constant_override("separation", 12)
	legend.add_child(Parts.legend_entry("component", Palette.kind_tint(Module.Kind.COMPONENT)))
	legend.add_child(Parts.legend_entry("hook module", Palette.kind_tint(Module.Kind.HOOK)))
	legend.add_child(Parts.legend_entry("style module", Palette.kind_tint(Module.Kind.STYLE)))
	legend.add_child(Parts.legend_entry("usage edge", Palette.edge_component()))
	_toolbar.add_child(legend)
	return _toolbar


## Layer chosen from the dropdown: the canvas moves to that band's zoom, about its own centre.
func _on_layer_chosen(index: int) -> void:
	if _syncing_layer or _canvas == null or index < 0 or index >= LAYERS.size():
		return
	var want := float((LAYERS[index] as Dictionary)["zoom"])
	var centre: Vector2 = _canvas.size * 0.5
	_canvas.set_camera(Metrics.zoom_about(_canvas.camera, _canvas.zoom, want, centre), want)


## Dropdown follows the zoom, because the zoom can change without it — a wheel, a fit, a restored
## layout. A selector that only ever leads and never follows starts lying on the first scroll.
func _sync_layer_selector() -> void:
	if _layers == null or _canvas == null:
		return
	var band := int(Metrics.lod_of(_canvas.zoom))
	if _layers.selected == band:
		return
	_syncing_layer = true
	_layers.selected = band
	_syncing_layer = false


func _tool_button(label: String, id: int) -> Button:
	var button := Button.new()
	button.text = label
	button.pressed.connect(func(): run_command(id))
	button.set_meta("command", id)
	return button


func _wire() -> void:
	_folders.module_selected.connect(select_module)
	# Re-filing from the pane goes through the SAME two operations the canvas and the card menu
	# use, so a move made by dragging in the tree and one made any other way produce the same
	# ledger entry and the same importer rewrites.
	_folders.refile_requested.connect(func(what: String, path: String, into: String):
		var moved := move_folder(path, into) if what == "folder" else place_module(path, into)
		if not moved:
			toast("Couldn't move %s into %s." % [path.get_file(), into.get_file()]))
	_folders.module_activated.connect(func(path: String):
		select_module(path)
		_canvas.select_card(graph.index_of(path) if graph != null else -1))
	_folders.module_context_requested.connect(func(path: String, _at: Vector2):
		_open_card_menu(path, get_global_mouse_position()))

	_canvas.card_selected.connect(_on_card_selected)
	_canvas.card_add_requested.connect(_on_card_add)
	_canvas.row_clicked.connect(_on_row_clicked)
	_canvas.row_context_requested.connect(_on_row_context)
	_canvas.dropped.connect(_on_canvas_drop)
	_canvas.card_moved.connect(_on_card_moved)
	_inline.committed.connect(_on_inline_committed)
	# An ABANDONED inline edit still has to clear what it was about: leaving `_menu_row` pointing
	# at a row after the user pressed Escape means the next Delete acts on a row they walked away
	# from.
	_inline.cancelled.connect(func(_token: Variant, undo_seeding: bool):
		_menu_row = null
		# ESCAPE ON A SEEDED EDITOR TAKES THE SEEDING BACK. The builder wrote that `@if (true)`
		# itself, a moment ago, as one ledger entry -- so undoing it is the same undo the user
		# would reach for, and doing it here means "cancel" means the same thing whether they
		# changed their mind during the edit or after it.
		if undo_seeding:
			undo())
	_canvas.camera_changed.connect(_on_camera_changed)
	_canvas.camera_changed.connect(func(_c: Vector2, _z: float): _sync_layer_selector())
	_canvas.card_context_requested.connect(func(index: int, world: Vector2):
		if graph == null or index < 0 or index >= graph.cards.size():
			return
		_menu_world = world
		_open_card_menu(graph.cards[index].file_path, get_global_mouse_position()))
	_canvas.canvas_context_requested.connect(func(world: Vector2):
		_menu_world = world
		# CLEARED: this menu was opened over empty canvas, so "new" means "at the tree root". Left
		# set, it still names whichever card was right-clicked last, and the module is born inside
		# a component the user is not even pointing at.
		_menu_target = ""
		_canvas_menu.position = Vector2i(get_global_mouse_position())
		_canvas_menu.popup())

	# CLICKING an entry inserts it into the selected card, which is the keyboard-and-trackpad
	# route to the same place the drag goes. The signal existed and nothing listened, so a click
	# in the library did nothing at all and the only way in was a drag.
	_library.entry_activated.connect(_on_library_activated)
	_library.entry_framed.connect(_on_library_framed)
	_library.create_requested.connect(_on_library_create)
	_source.buffer_edited.connect(_on_buffer_edited)
	_source.edit_applied.connect(func(path: String, text: String):
		apply_edit(path, text, "Edit %s" % path.get_file()))
	_source.edit_cancelled.connect(func(path: String, restore: String):
		apply_edit(path, restore, "Revert %s" % path.get_file()))
	_source.complained.connect(toast)
	_preview_pane.component_picked.connect(select_module)
	_console.location_activated.connect(select_module)
	_card_menu.id_pressed.connect(_on_card_menu)
	_canvas_menu.id_pressed.connect(run_command)
	ledger.changed.connect(_refresh_status)
	# A FAILED round brings the console forward; a clean one leaves it away. That is the whole
	# rule, and it is why the console does not need to be on screen the rest of the time.
	preview.compile_finished.connect(func(_p: String, ok: bool, _e: String):
		if not ok and _console != null:
			_console.visible = true)
	preview.compile_finished.connect(func(_p: String, _ok: bool, _e: String):
		_refresh_status()
		# The preview re-renders on the BUILD, not on the keystroke: mounting a script that has not
		# recompiled yet just re-mounts the one already showing.
		if _preview_pane != null and not _preview_pane.path().is_empty():
			_preview_pane.show_module(_preview_pane.path()))
	_history_menu.id_pressed.connect(run_command)


# ── Opening ──────────────────────────────────────────────────────────────────────────

## Opens the tree the given module belongs to.
func open_tree(focus_path: String) -> void:
	if focus_path.strip_edges().is_empty():
		# The START SCREEN. Opening with nothing is what the menu does on a project that has no
		# `.guitkx` open, and it is a state this window is built to show.
		if workspace == null:
			workspace = Workspace.new()
		reproject()
		_refresh_status()
		return
	if workspace == null:
		workspace = Workspace.new()
	# On open, not only on teardown: a crashed editor leaves a mirror behind, and compiling
	# against a shadow tree is worse than compiling against nothing.
	Preview.clear_scratch()
	workspace.format_on_save = AddonSettings.is_enabled(AddonSettings.KEY_FORMAT_ON_SAVE)
	workspace.load_tree(focus_path)
	preview.workspace = workspace
	ledger.clear()
	ledger.id_of = func(path: String) -> String:
		var module := workspace.try_get(path)
		return module.id if module != null else ""
	_focus_path = Paths.canon(focus_path)
	reproject()
	select_module(_focus_path)
	if graph != null:
		_canvas.select_card(graph.index_of(_focus_path))


## Rebuilds the canvas model from the workspace and re-applies the saved layout.
##
## The layout is applied and then TOPPED UP: what it already knows keeps its slot, and only a
## module it has never seen takes a seeded one. Re-seeding everything would move every card the
## user has ever dragged the moment one module is added.
## Puts the tree at Layer 2, centred on its content, once the canvas actually has a size.
##
## Deferred for the same reason `_fit_when_sized` is: `reproject` runs before the containers have
## laid out, and centring against a zero-sized canvas centres on nothing.
func _centre_when_sized(attempts := 8) -> void:
	if _canvas == null or attempts <= 0:
		return
	if _canvas.size.x > 1.0 and _canvas.size.y > 1.0:
		var zoom: float = _canvas.zoom
		var bounds := Metrics.content_bounds(graph, Metrics.lod_of(zoom))
		var centre := bounds.position + bounds.size * 0.5
		_canvas.set_camera(_canvas.size * 0.5 - centre * zoom, zoom)
		return
	await get_tree().process_frame
	_centre_when_sized(attempts - 1)


## Frames the tree once the canvas actually has a size.
##
## Deferred, because `reproject` runs before the containers have laid out and a fit against a
## zero-sized canvas frames nothing. The retry is bounded: a canvas that never gets a size is a
## window that was never shown.
func _fit_when_sized(attempts := 8) -> void:
	if _canvas == null or attempts <= 0:
		return
	if _canvas.size.x > 1.0 and _canvas.size.y > 1.0:
		_canvas.fit_to_view()
		return
	await get_tree().process_frame
	_fit_when_sized(attempts - 1)


## Whether the onboarding panel should be on screen: only when there is genuinely nothing open.
func _sync_empty_state() -> void:
	if _empty_state == null:
		return
	_empty_state.visible = workspace == null or workspace.modules().is_empty()


func reproject() -> void:
	if workspace == null:
		return
	graph = Service.project(workspace.modules(), _focus_path)
	layout = CanvasLayout.for_graph(graph)
	layout.apply_to(graph)
	layout.adopt_unplaced(graph)
	if layout.has_saved_view:
		_canvas.camera = layout.camera
		_canvas.zoom = layout.zoom
	_canvas.show_graph(graph)
	# A TREE WITH NO SAVED LAYOUT OPENS AT LAYER 2 (capability reference §2), CENTRED -- not
	# fitted. A fit picks whatever zoom frames the whole graph, so the layer the user lands in
	# depends on how many modules they have: five cards opened at a third of Layer 2's size, with
	# the toolbar confidently reading "Layer 2 — Cards" beside cards nobody could read. Setting the
	# zoom and then fitting, which is what this did, is just the fit.
	if not layout.has_saved_view and not graph.cards.is_empty():
		# THE ZOOM IS SET NOW, the centring deferred. Which layer a tree opens at is not a
		# question about the canvas's pixel size, so it must not wait for one: deferred with the
		# centring, a canvas that is never laid out -- headless, or a window opened and measured
		# in the same frame -- opens at 1:1 with the toolbar reading "Layer 2".
		_canvas.zoom = Metrics.DEFAULT_ZOOM
		_centre_when_sized()
	if _preview_pane != null:
		_preview_pane.graph = graph
	_sync_empty_state()
	_folders.workspace = workspace
	_folders.rebuild()
	_library.graph = graph
	_library.rebuild()
	_refresh_status()


# ── The one funnel ───────────────────────────────────────────────────────────────────

## EVERY change to a buffer goes through here: the source pane, a canvas gesture, a replayed
## undo. One entry means one ledger record, one preview round and one re-projection per change,
## whatever produced it.
func apply_edit(file_path: String, after: String, description: String) -> bool:
	if workspace == null:
		return false
	var module := workspace.try_get(file_path)
	if module == null or module.read_only:
		return false
	var before := module.buffer_text
	if before == after:
		return false
	if not workspace.apply_edit(file_path, after):
		return false
	ledger.begin(description)
	ledger.record(file_path, before, after)
	ledger.end()
	_after_model_change(file_path)
	return true


## Re-projects the one card that changed, refreshes the panes, and asks for a preview round.
##
## The card is re-populated in place rather than the whole graph being rebuilt: rebuilding would
## discard every card's measured height and re-seed the layout, so a keystroke would visibly
## reshuffle the canvas.
func _after_model_change(file_path: String) -> void:
	if graph != null:
		var index := graph.index_of(file_path)
		if index >= 0:
			var module := workspace.try_get(file_path)
			if module != null:
				Service.populate_card(graph.cards[index], module.buffer_text)
				Service.refresh_edges_for(graph, index)
		_canvas.show_graph(graph)
	_folders.rebuild()
	_source.refresh_from_model()
	preview.request_refresh()
	_refresh_status()


## A keystroke in the source pane.
##
## IGNORED WHILE THE PANE IS IN EDIT MODE: the pane hands the buffer over once, on apply, after
## it has parsed. Funnelling every keystroke meant half a tag name was a state the preview
## compiled and the canvas re-projected -- so typing produced a stream of errors about text
## nobody had finished writing, and deleting a line to retype it blanked the card.
func _on_buffer_edited(file_path: String, before: String, after: String) -> void:
	if _source != null and _source.is_editing():
		return
	# The source pane has already written the buffer, so the funnel records rather than re-applies.
	ledger.record_typing(file_path, before, after)
	_after_model_change(file_path)


# ── Preview ──────────────────────────────────────────────────────────────────────────

## Runs a preview round if the debounce has settled, and journals unsaved work on its own
## cadence. Called from the host's idle tick.
func tick() -> void:
	_tick_toast()
	_journal_tick()
	if not preview.is_due():
		return
	var summary = preview.compile_dirty(_focus_path)
	if summary != null:
		_console.report(summary)
	_refresh_status()


## How often unsaved work is written to the crash journal, in milliseconds.
##
## On a TIMER, not on every change: the journal is the whole tree serialised, and writing it per
## keystroke would put a file write in the typing path. Five seconds is the most work a crash can
## cost, which against losing a whole session is the trade worth making.
const JOURNAL_INTERVAL_MSEC := 5000

var _journalled_at := 0


func _journal_tick() -> void:
	if workspace == null or not workspace.has_unsaved_changes():
		return
	var now := Time.get_ticks_msec()
	if now - _journalled_at < JOURNAL_INTERVAL_MSEC:
		return
	_journalled_at = now
	Journal.capture(workspace, Time.get_datetime_string_from_system(true))


## What a crashed session left behind, or {} -- { modules, saved_at }.
##
## The journal exists ONLY while there is unsaved work, so the file being there means exactly one
## thing and the offer needs no other evidence to be sure it is not noise.
func pending_recovery() -> Dictionary:
	return Journal.peek()


## Takes the recovered tree. The caller asks first: restoring over an open tree replaces it.
func restore_recovery() -> bool:
	if workspace == null or not Journal.try_restore(workspace):
		return false
	reproject()
	_source.refresh_from_model()
	preview.request_refresh()
	return true


func discard_recovery() -> void:
	Journal.clear()


# ── Commands ─────────────────────────────────────────────────────────────────────────

func run_command(id: int) -> void:
	match id:
		MenuId.HISTORY:
			_show_history()
			return
		MenuId._HISTORY_OLD:
			# The ledger, as a menu. Undo and Redo are the whole of it today; the entries they
			# would walk are already named in `ledger.entries`, which is what a fuller list draws from.
			_history_menu.position = Vector2i(get_screen_position() + Vector2(0, 32))
			_history_menu.popup()
			return
		MenuId.TRACE:
			_console.visible = true
			_console.trace(workspace, ledger, preview)
			return
		MenuId.HELP:
			_console.visible = true
			_console.show_help()
			return
	match id:
		MenuId.SAVE:
			save()
		MenuId.ABORT:
			abort()
		MenuId.UNDO:
			undo()
		MenuId.REDO:
			redo()
		MenuId.FIT_VIEW:
			_canvas.fit_to_view()


## A row was clicked: focus its module and put the source pane's caret on the line that made it.
##
## The two panes were two views of the same file that never pointed at each other. A markup tree
## whose rows carry exact source spans and does nothing with them on a click is showing structure
## it refuses to navigate.
func _on_row_clicked(card_index: int, _section: int, row_index: int) -> void:
	var row = _row_of(card_index, _section, row_index)
	if row == null:
		return
	# CLICKING A ROW SELECTS IT. Selection was only ever set by the row MENU, so a row could be
	# clicked -- moving the source pane, highlighting on the card -- and still not be what Delete
	# acted on: the key fell through to the module instead, deleting the whole file. Any row the
	# canvas lists is selectable, not only markup: a hook chip, an import row, a code island and a
	# style entry are each backed by a line range and each know how to remove themselves.
	_menu_target = graph.cards[card_index].file_path
	_menu_row = row
	_menu_card = card_index
	_canvas.select_row(card_index, _section, row_index)
	select_module(graph.cards[card_index].file_path)
	_source.goto_line(row.source_line)


## A card was dragged somewhere. Its new place is remembered for this tree.
##
## The layout store, its per-tree keying and the "top up rather than re-seed" rule were all
## written before anything could move a card -- so the whole persistence path had never once run
## on a position a user chose.
func _on_card_moved(index: int, to: Vector2) -> void:
	if graph == null or layout == null or index < 0 or index >= graph.cards.size():
		return
	layout.set_position(graph.cards[index].file_path, to)
	_capture_layout()


## Something was dropped on the canvas. Routes it to the operation that already existed for it.
##
## The three payloads are the three the reference has: a LIBRARY entry becomes an element or a
## hook, a ROW is re-parented, and a MODULE card moves into a folder. Each was implemented and
## unreachable, because nothing could start a drag.
func _on_canvas_drop(data: Dictionary, at: Vector2) -> void:
	match str(data.get("source", "")):
		"library":
			if not drop_library_entry(str(data.get("kind", "")), str(data.get("name", "")), at):
				toast("Couldn't place <%s> there." % str(data.get("name", "")))
		"row":
			var drag := Drag.new()
			drag.begin(Drag.Source.ROW, "", str(data.get("card_id", "")),
				int(data.get("row_at", -1)), int(data.get("row_index", -1)), at)
			drag.started = true
			if not drop_row(drag, at):
				toast("Couldn't move that row there.")
		"module":
			if not drop_module(str(data.get("path", "")), at):
				toast("Couldn't move that module there.")


## Right-click on a row: the operations that apply to THAT row.
##
## Ported from the Unity leg's `OnCanvasRowContext`. A directive head gets clause operations; an
## element row gets attributes, children, wrapping and deletion. This is the builder's primary
## editing gesture and it did not exist -- the canvas offered a card menu (open / rename / delete
## the FILE) and nothing that could touch what is inside one.
func _on_row_context(card_index: int, section: int, row_index: int, at: Vector2) -> void:
	var row = _row_of(card_index, section, row_index)
	if row == null or graph == null:
		return
	var card = graph.cards[card_index]
	var module := workspace.try_get(card.file_path) if workspace != null else null
	if module == null:
		return
	if module.read_only:
		toast("%s is read-only — it lives under addons/." % card.title)
		return

	_menu_target = card.file_path
	_menu_row = row
	_menu_card = card_index
	_menu_at = at
	_row_menu.clear()
	_row_menu.add_separator(row.text.strip_edges())

	if section == Metrics.Section.EXPORTS:
		# A style entry's menu is about the DICTIONARY it lives in, not about markup.
		_row_menu.add_item("Add entry...", RowMenuId.ADD_STYLE_ENTRY)
		_row_menu.add_separator()
		_row_menu.add_item("Delete this entry", RowMenuId.DELETE_ROW)
		_row_menu.position = Vector2i(_canvas.get_screen_position() + at)
		_row_menu.reset_size()
		_row_menu.popup()
		return

	if row.kind == Graph.LineKind.DIRECTIVE:
		_row_menu.add_item("Edit header...", RowMenuId.EDIT_HEADER)
		# Clause operations belong to the CONSTRUCT head (@if), not to a bound continuation
		# (@else) -- adding an else to an else is not a thing the language has.
		if row.badge_text == "@if" and row.clause_index == 0:
			_row_menu.add_separator()
			_row_menu.add_item("Add @elif", RowMenuId.ADD_ELSE_IF)
			_row_menu.add_item("Add @else", RowMenuId.ADD_ELSE)
		_row_menu.add_separator()
		_row_menu.add_item("Remove %s, keep its contents" % row.badge_text, RowMenuId.UNWRAP)
		if row.clause_index > 0:
			_row_menu.add_item("Delete this %s clause" % row.badge_text, RowMenuId.DELETE_CLAUSE)
		_row_menu.add_item("Delete " + row.badge_text, RowMenuId.DELETE_ROW)
	else:
		_row_menu.add_item("Add attribute...", RowMenuId.ADD_ATTRIBUTE)
		_row_menu.add_item("Add child element...", RowMenuId.ADD_CHILD)
		if _has_style_modules():
			_row_menu.add_item("Apply style from a module...", RowMenuId.APPLY_STYLE)
		if not str(row.attrs_text).is_empty():
			_row_menu.add_item("Edit attribute...", RowMenuId.EDIT_ATTRIBUTE)
			_row_menu.add_item("Remove attribute...", RowMenuId.REMOVE_ATTRIBUTE)
		_row_menu.add_separator()
		_row_menu.add_item("Wrap in...", RowMenuId.WRAP_IF)
		# The FIRST element row is the component's return root: deleting it leaves a component
		# with nothing to return, which is a compile error rather than an edit.
		if row_index > 0 or section != Metrics.Section.MARKUP:
			_row_menu.add_separator()
			_row_menu.add_item("Delete element", RowMenuId.DELETE_ROW)

	_row_menu.position = Vector2i(_canvas.get_screen_position() + at)
	_row_menu.reset_size()
	_row_menu.popup()


## Carries out a row-menu choice. Every branch ends in one `apply_edit`, like every other gesture.
func _on_row_menu(id: int) -> void:
	var row = _menu_row
	if row == null or workspace == null or _menu_target.is_empty():
		return
	var module := workspace.try_get(_menu_target)
	if module == null or module.read_only:
		return
	var card = graph.cards[_menu_card] if graph != null and _menu_card >= 0 		and _menu_card < graph.cards.size() else null
	var before := module.buffer_text
	var after := before
	var what := ""

	match id:
		RowMenuId.DELETE_ROW:
			after = Edits.remove(before, row)
			what = "Delete %s" % row.text.strip_edges()
		RowMenuId.ADD_ELSE:
			after = Edits.add_if_clause(before, row, false)
			what = "Add @else"
		RowMenuId.ADD_ELSE_IF:
			after = Edits.add_if_clause(before, row, true)
			what = "Add @elif"
		RowMenuId.UNWRAP:
			after = Edits.unwrap_directive(before, row)
			what = "Remove %s, keeping its contents" % row.badge_text
		RowMenuId.DELETE_CLAUSE:
			after = Edits.delete_clause(before, row)
			what = "Delete the %s clause" % row.badge_text
		RowMenuId.WRAP_IF:
			_search_purpose = "wrap"
			var wraps: Array = []
			for entry in Edits.WRAPS:
				var spec := entry as Dictionary
				wraps.append(SearchMenu.item(str(spec["label"]), str(spec["header"]),
					str(spec["header"])))
			wraps.append(SearchMenu.item("@match", "@match", "with one @case"))
			_search_menu.open_menu("wrap %s in" % row.text.strip_edges(), wraps,
				_menu_screen_at())
			return
		RowMenuId.ADD_CHILD:
			_search_purpose = "child"
			_search_menu.open_menu("add a child to %s" % row.text.strip_edges(),
				_tag_items(), _menu_screen_at(), "add <%s>")
			return
		RowMenuId.ADD_ATTRIBUTE:
			_search_purpose = "attribute"
			var tag := str(row.name)
			_search_menu.open_menu(
				"attributes of <%s>" % tag,
				Attributes.menu_for(tag, row, _component_named(tag)),
				_menu_screen_at(), "add \"%s\" (untyped)")
			return
		RowMenuId.ADD_STYLE_ENTRY:
			_search_purpose = "style_entry"
			_search_menu.open_menu("add an entry to %s" % row.name, _style_key_items(row),
				_menu_screen_at(), "add \"%s\"")
			return
		RowMenuId.APPLY_STYLE:
			_search_purpose = "style"
			_search_menu.open_menu("apply a style to %s" % row.text.strip_edges(),
				_style_items(), _menu_screen_at())
			return
		RowMenuId.EDIT_ATTRIBUTE:
			_search_purpose = "edit_attribute"
			_search_menu.open_menu("edit an attribute", _attribute_items(row), _menu_screen_at())
			return
		RowMenuId.REMOVE_ATTRIBUTE:
			_search_purpose = "remove_attribute"
			var present: Array = []
			for pair in row.attr_pairs:
				var text := str(pair)
				var equals := text.find("=")
				present.append(SearchMenu.item(
					text.substr(0, equals) if equals >= 0 else text, text.substr(0, equals)))
			_search_menu.open_menu("remove an attribute", present, _menu_screen_at())
			return
		RowMenuId.EDIT_HEADER:
			# Edited in place over the row, not behind a dialog: the header is one line of the
			# user's own code and they are already looking at it.
			_inline.open_at(Rect2(_menu_at, Vector2(260, 24)), row.directive_text,
				{ "kind": "directive", "path": _menu_target, "row": row })
			return
		_:
			return

	if after != before:
		apply_edit(_menu_target, after, what)


## Adds the import a COMPONENT tag needs, if the tag names one and the file has not got it.
##
## In the SAME commit as the insertion, which is the reference's rule and the only one that
## works: a `<Card />` with no `import { Card }` is a file that does not compile, so putting the
## tag in first and the import in second means every drop of a component spends a moment in an
## error state -- reported by the preview, in the console, about an edit the builder itself was
## halfway through making.
##
## A HOST tag needs nothing, and a component that lives in the same file needs nothing either.
func _with_component_import(source: String, importer_path: String, tag: String) -> String:
	if graph == null or Compiler.host_tags().has(tag):
		return source
	for card in graph.cards:
		if card.kind != Module.Kind.COMPONENT or not (tag in card.exports):
			continue
		if Paths.same(card.file_path, importer_path):
			return source
		return Edits.ensure_import(source, importer_path, card.file_path,
			PackedStringArray([tag]))
	return source


## The style keys a new entry can take, from the same catalogue the `.guitkx` editor completes
## style dictionaries with -- so the builder offers what the style system actually understands
## rather than a list kept beside it.
func _style_key_items(row) -> Array:
	var items: Array = []
	var owner := str(row.name)
	for key in Schema.style_keys():
		items.append(SearchMenu.item(str(key), {
			"export": owner, "key": str(key), "value": _style_seed(str(key)),
		}))
	return items


## What a fresh style entry is worth. Seeded, like every other header this builder writes.
func _style_seed(key: String) -> String:
	if key.ends_with("_color"):
		return "Color(0.2, 0.2, 0.24)"
	if key.begins_with("font_size") or key.contains("width") or key.contains("radius") 			or key.contains("margin") or key.contains("separation"):
		return "8"
	return "null"


## Whether the open tree has a style module to offer at all.
func _has_style_modules() -> bool:
	if graph == null:
		return false
	for card in graph.cards:
		if card.kind == Module.Kind.STYLE and not card.exports.is_empty():
			return true
	return false


## Every style a module in this tree exports, as menu items.
##
## One entry per EXPORT, not per module: a style module holds several looks and "apply a style"
## means one of them, so a menu that stopped at the module would need a second menu behind it.
func _style_items() -> Array:
	var items: Array = []
	if graph == null:
		return items
	for card in graph.cards:
		if card.kind != Module.Kind.STYLE or card.exports.is_empty():
			continue
		items.append({ "heading": card.title })
		for export_name in card.exports:
			items.append(SearchMenu.item(str(export_name), {
				"export": str(export_name),
				"path": card.file_path,
				"alias": str(export_name),
			}, card.title))
	return items


## A row's attributes, split into name / value / how the value was written.
##
## The SPELLING matters: `text="hi"` is a quoted string and `style={s}` is an expression, and
## writing one back as the other is a compile error. The pair already carries which it was.
func _attribute_items(row) -> Array:
	var items: Array = []
	for pair in row.attr_pairs:
		var text := str(pair)
		var equals := text.find("=")
		if equals < 0:
			items.append(SearchMenu.item(text, { "name": text, "value": "", "quoted": false }))
			continue
		var name := text.substr(0, equals)
		var raw := text.substr(equals + 1).strip_edges()
		var quoted := raw.begins_with("\"")
		var value := raw
		if quoted:
			value = raw.trim_prefix("\"").trim_suffix("\"")
		elif raw.begins_with("{"):
			value = raw.trim_prefix("{").trim_suffix("}").strip_edges()
		items.append(SearchMenu.item(name, { "name": name, "value": value, "quoted": quoted },
			raw))
	return items


## Where a menu opened from the last row gesture belongs, in screen coordinates.
func _menu_screen_at() -> Vector2:
	return _canvas.get_screen_position() + _menu_at


## Every tag the library offers, as menu items -- the same vocabulary, because two lists of legal
## tags is one list that is wrong.
func _tag_items() -> Array:
	var items: Array = []
	items.append({ "heading": "elements" })
	for tag in Compiler.host_tags().keys():
		items.append(SearchMenu.item("<%s>" % str(tag), str(tag)))
	if graph != null:
		var components: Array = []
		for card in graph.cards:
			if card.kind != Module.Kind.COMPONENT:
				continue
			for export_name in card.exports:
				components.append(str(export_name))
		if not components.is_empty():
			components.sort()
			items.append({ "separator": true })
			items.append({ "heading": "components in this tree" })
			for name in components:
				items.append(SearchMenu.item("<%s>" % name, name))
	return items


## The card whose component is named `tag`, or null when the tag is a host element.
func _component_named(tag: String):
	if graph == null:
		return null
	for card in graph.cards:
		if card.kind == Module.Kind.COMPONENT and tag in card.exports:
			return card
	return null


## A choice from the search menu. Dispatched by what the menu was opened FOR.
func _on_search_picked(payload: Variant) -> void:
	if workspace == null or _menu_target.is_empty() or _menu_row == null:
		return
	var module := workspace.try_get(_menu_target)
	if module == null or module.read_only:
		return
	var card = graph.cards[_menu_card] if graph != null and _menu_card >= 0 		and _menu_card < graph.cards.size() else null
	var before := module.buffer_text
	var after := before
	var what := ""

	match _search_purpose:
		"history":
			if payload is int and int(payload) >= 0:
				_jump_history_to(int(payload))
			return
		"child":
			var tag := str(payload)
			after = _with_component_import(
				Edits.insert(before, card, _menu_row, Drag.markup_for(tag), Edits.Placement.INSIDE),
				_menu_target, tag)
			what = "Add <%s> to %s" % [tag, _menu_row.text.strip_edges()]
		"attribute":
			var name := ""
			var seed := { "value": "", "quoted": true }
			if payload is Dictionary:
				name = str((payload as Dictionary)["name"])
				seed = Attributes.default_value(str((payload as Dictionary).get("type", "")))
			else:
				name = str(payload)
				seed = Attributes.default_value("")
			after = Edits.set_attribute(before, _menu_row, name,
				str(seed["value"]), bool(seed["quoted"]))
			what = "Add %s to %s" % [name, _menu_row.text.strip_edges()]
		"edit_attribute":
			# The WRAPPER STAYS OUTSIDE THE FIELD: the user edits the value, not the quotes or
			# the braces around it, so typing an expression into a string attribute cannot
			# produce `text=""{x}""`.
			var spec := payload as Dictionary
			_pending_attribute = spec
			_search_purpose = "attribute_value"
			_inline.open_at(Rect2(_menu_at, Vector2(260, 24)), str(spec["value"]),
				{ "kind": "attribute", "path": _menu_target, "row": _menu_row,
					"name": str(spec["name"]), "quoted": bool(spec["quoted"]) })
			return
		"wrap":
			var header := str(payload)
			if header == "@match":
				after = Edits.wrap_in_match(before, _menu_row)
				what = "Wrap %s in @match" % _menu_row.text.strip_edges()
			else:
				after = Edits.wrap_in_directive(before, _menu_row, header)
				what = "Wrap %s in %s" % [_menu_row.text.strip_edges(), header.split(" ")[0]]
			_seed_header_edit = header
		"style_entry":
			var pick := payload as Dictionary
			after = Edits.insert_style_entry(before, str(pick["export"]),
				str(pick["key"]), str(pick["value"]))
			what = "Add %s to %s" % [str(pick["key"]), str(pick["export"])]
		"style":
			# THE IMPORT LANDS WITH THE ATTRIBUTE. `style={Palette.CARD}` with nothing importing
			# `Palette` is a file that does not compile, and a style applied in two commits is a
			# style that is briefly an error.
			var pick := payload as Dictionary
			var export_name := str(pick["export"])
			# THE BINDING the file will actually have, decided before either edit, so the
			# attribute and the import cannot disagree about what the style is called here.
			var bind := Edits.bind_export(before, _menu_target, str(pick["path"]), export_name)
			after = Edits.set_attribute(before, _menu_row, "style", str(bind["binding"]), false)
			after = str(Edits.bind_export(after, _menu_target, str(pick["path"]), export_name)["text"])
			what = "Style %s with %s" % [_menu_row.text.strip_edges(), export_name]
		"remove_attribute":
			after = Edits.remove_attribute(before, _menu_row, str(payload))
			what = "Remove %s from %s" % [str(payload), _menu_row.text.strip_edges()]
		_:
			return

	if after == before:
		toast("Nothing changed — %s could not be applied here." % what.to_lower())
		return
	var target := _menu_target
	var seeded_row: Graph.Line = _menu_row
	apply_edit(target, after, what)

	# A SEEDED WRAP OPENS FOR EDITING IMMEDIATELY. `@if (true)` is a placeholder, not an answer:
	# the point of wrapping a row is the condition, so the builder writes a header that compiles
	# and then puts the caret in it. Escape here undoes the wrap as well as the edit, which is
	# what `seeded` on the editor is for.
	if not _seed_header_edit.is_empty() and seeded_row != null:
		var header := _seed_header_edit
		_seed_header_edit = ""
		var fresh := _row_after_reproject(target, seeded_row)
		if fresh != null:
			_inline.open_at(Rect2(_menu_at, Vector2(260, 24)), header,
				{ "kind": "directive", "path": target, "row": fresh }, true)
	_seed_header_edit = ""


## A name prompt was submitted.
## The DIRECTIVE row that now wraps `original`, found again after the re-projection an edit
## triggers. The `Line` the menu was opened on belongs to the old projection and is stale the
## moment the buffer changes -- editing through it writes at the offsets the row used to have.
func _row_after_reproject(path: String, original: Graph.Line) -> Graph.Line:
	if graph == null or original == null:
		return null
	var card := graph.card_of(path)
	if card == null:
		return null
	for row in card.markup:
		if row.kind == Graph.LineKind.DIRECTIVE and row.source_line <= original.source_line:
			# The nearest directive at or above where the wrapped row was: wrapping puts the
			# header immediately before the row it wrapped.
			var candidate := row
			for later in card.markup:
				if later.kind == Graph.LineKind.DIRECTIVE 						and later.source_line > candidate.source_line 						and later.source_line <= original.source_line:
					candidate = later
			return candidate
	return null


func _on_search_submitted(text: String) -> void:
	match _search_purpose:
		"create":
			_create_named(_pending_kind, text)
		"rename":
			_rename_to(text)


## An inline edit was committed. Dispatched by the token the editor was opened with, so one
## floating field serves every in-place edit the canvas offers.
func _on_inline_committed(token: Variant, text: String) -> void:
	if not (token is Dictionary) or workspace == null:
		return
	var spec := token as Dictionary
	var path := str(spec.get("path", ""))
	var module := workspace.try_get(path)
	if module == null or module.read_only:
		return
	var row = spec.get("row")
	var before := module.buffer_text
	var after := before
	var what := ""
	match str(spec.get("kind", "")):
		"directive":
			after = Edits.set_directive_header(before, row, text)
			what = "Edit %s" % row.badge_text
		"island":
			after = Edits.set_island(before, int(spec.get("from", 0)), int(spec.get("to", 0)), text)
			what = "Edit the setup of %s" % path.get_file()
		"body":
			# ONE setup line, edited in place. `set_island` already replaces an inclusive line
			# range, and a hook chip or a code line is a range of exactly one -- so this is the
			# same edit, not a second implementation of it.
			after = Edits.set_island(before, row.source_line, row.source_line, text)
			what = "Edit %s" % row.text.strip_edges()
		"attribute":
			var attr_name := str(spec.get("name", ""))
			# AN EMPTIED VALUE TAKES THE ATTRIBUTE WITH IT. Writing `text=""` back would leave a
			# dead attribute nobody asked for, and clearing a field is the obvious way to say
			# "I do not want this one".
			if text.strip_edges().is_empty():
				after = Edits.remove_attribute(before, row, attr_name)
				what = "Remove %s from %s" % [attr_name, row.text.strip_edges()]
			else:
				after = Edits.set_attribute(before, row, attr_name, text,
					bool(spec.get("quoted", true)))
				what = "Edit %s on %s" % [attr_name, row.text.strip_edges()]
		_:
			return
	if after != before:
		apply_edit(path, after, what)


## The row under the pointer, from the section the hit-test named.
func _row_of(card_index: int, section: int, row_index: int):
	if graph == null or card_index < 0 or card_index >= graph.cards.size():
		return null
	var card = graph.cards[card_index]
	var rows: Array = []
	match section:
		Metrics.Section.IMPORTS:
			rows = card.imports
		Metrics.Section.BODY:
			rows = card.body
		Metrics.Section.MARKUP:
			rows = card.markup
		Metrics.Section.EXPORTS:
			rows = card.export_detail
		Metrics.Section.ISLAND:
			# The SETUP block is edited whole, not row by row: it is GDScript, and half a
			# statement is not a thing to write back.
			return card.markup[0] if not card.markup.is_empty() else null
		_:
			return null
	return rows[row_index] if row_index >= 0 and row_index < rows.size() else null


## A card's "+" was used. Turns it into ONE edit through the funnel, like every other gesture.
##
## The inserted text is a STARTING POINT, not a prompt: a hook chip that opened a dialog asking
## which hook, with what arguments, before it would put anything in the file is slower than
## typing the line. It lands as `useState(null)` and the user edits it where it now is.
func _on_card_add(index: int, what: String) -> void:
	if graph == null or workspace == null or index < 0 or index >= graph.cards.size():
		return
	var card = graph.cards[index]
	var module := workspace.try_get(card.file_path)
	if module == null or module.read_only:
		return
	var before := module.buffer_text
	var after := before
	var description := ""
	# `+ hook` seeds a useState and `+ code` a plain statement, and BOTH THEN OPEN THE INLINE
	# EDITOR ON THE NEW LINE (capability reference §5) -- that is the whole point of the chips:
	# "custom body logic never requires the source pane". Seeding and stopping left the user with
	# `var state = useState(null)` on the card and the source pane as the only way to make it say
	# anything else.
	var seeded_body := ""
	match what:
		"hook":
			seeded_body = "var state = useState(null)"
			after = Edits.insert_setup_line(before, card, seeded_body)
			description = "Add a hook to %s" % card.title
		"code":
			seeded_body = "# ..."
			after = Edits.insert_setup_line(before, card, seeded_body)
			description = "Add a setup line to %s" % card.title
		"style", "entry":
			var export_name := str(card.exports[0]) if not card.exports.is_empty() else ""
			if export_name.is_empty():
				return
			after = Edits.insert_style_entry(before, export_name, "bg_color", "Color(0.2, 0.2, 0.24)")
			description = "Add a style entry to %s" % card.title
		_:
			return
	if after == before:
		return
	var path: String = card.file_path
	apply_edit(path, after, description)
	if seeded_body.is_empty():
		return

	# On the line the seed just produced, found again AFTER the re-projection: the `Line` objects
	# this function started with belong to the old projection and carry offsets the buffer no
	# longer has.
	#
	# A HOOK CALL AND A PLAIN STATEMENT LAND IN DIFFERENT SECTIONS. A hook becomes a chip in BODY;
	# anything else is setup code and joins the card's ISLAND. Editing them is the same gesture to
	# the user and two different line ranges underneath.
	_menu_target = path
	var fresh := graph.card_of(path) if graph != null else null
	if fresh == null:
		return
	if what == "hook":
		for row_index in fresh.body.size():
			var row: Graph.Line = fresh.body[row_index]
			if row.source_text != seeded_body:
				continue
			_menu_row = row
			_inline.open_at(_body_row_rect(fresh, row_index), seeded_body,
				{ "kind": "body", "path": path, "row": row }, true)
			return
		return
	for i in fresh.island_lines.size():
		if str(fresh.island_lines[i]).strip_edges() != seeded_body:
			continue
		var line := fresh.island_start_line + i
		_inline.open_at(_body_row_rect(fresh, 0), seeded_body,
			{ "kind": "island", "path": path, "row": null, "from": line, "to": line }, true)
		return


## Where a BODY row sits on screen, so the editor can open over the line it edits rather than
## wherever the last menu was.
func _body_row_rect(card: Graph.Card, row_index: int) -> Rect2:
	var lod := Metrics.lod_of(_canvas.zoom)
	var top := Metrics.HEADER_H
	for entry in Metrics.section_stack(card):
		var section := entry as Dictionary
		if not Metrics.draws_section(int(section["section"]), lod):
			continue
		if int(section["section"]) == int(Metrics.Section.BODY):
			top += float(section["lead"]) + row_index * float(section["row_height"])
			var at := _canvas.get_global_rect().position + Metrics.world_to_screen(
				Vector2(card.x, card.y) + Vector2(8.0, top), _canvas.camera, _canvas.zoom)
			return Rect2(at, Vector2(Metrics.card_width_for(lod) * _canvas.zoom - 16.0,
				float(section["row_height"]) * _canvas.zoom))
		top += float(section["height"])
	return Rect2(_menu_screen_at(), Vector2(260, 24))


## Create, from a card's own menu: the clicked module is the anchor, so the new one lands in its
## folder and -- for a component -- is imported by it, which is what "child" means here.
func _on_card_new(kind: int) -> void:
	if _menu_target.is_empty():
		return
	# The clicked card is the anchor, so the new module is born in ITS folder.
	_focus_path = _menu_target
	prompt_create(kind)


## Moves a whole folder under another, and returns whether it went.
##
## Ported from the Unity leg's `MoveFolderToFolder`. Two things in it are worth keeping:
##
## The component that OWNS the folder carries it, so when one exists the move is delegated to
## moving that module -- the same move by a shorter route, and the one that keeps the house
## layout intact instead of scattering a family across two parents.
##
## A read-only module anywhere inside REFUSES THE WHOLE MOVE, before anything has moved. Moving
## what can move and stopping at the first package file would leave a folder half here and half
## there, which is worse than not starting.
func move_folder(source_folder: String, target_folder: String) -> bool:
	if workspace == null:
		return false
	var source := Paths.canon(source_folder)
	var leaf := source.get_file()
	if leaf.is_empty():
		return false
	var destination := Paths.canon(target_folder.path_join(leaf))
	if Paths.same(destination, source):
		return false
	if Paths.is_under(destination, source):
		toast("Can't move %s into itself." % leaf)
		return false

	for module in workspace.modules():
		if module.owns_folder() and Paths.same(module.folder, source):
			return _move_one(module, target_folder, leaf)

	var movers: Array = []
	for module in workspace.modules():
		var folder := Paths.canon(module.folder)
		if not Paths.same(folder, source) and not Paths.is_under(folder, source):
			continue
		if module.read_only:
			toast("Can't move %s — it holds a read-only module." % leaf)
			return false
		var relative := folder.trim_prefix(source).trim_prefix("/")
		movers.append({ "module": module, "to": destination.path_join(relative) })
	if movers.is_empty():
		return false

	ledger.begin("Move %s" % leaf)
	var snapshot := workspace.capture_imports()
	for entry in movers:
		var spec := entry as Dictionary
		var module = spec["module"]
		var from: String = module.file_path()
		workspace.move_to(from, str(spec["to"]), module.name)
		if layout != null:
			layout.repath(from, module.file_path(), false)
		if Paths.same(_focus_path, from):
			_focus_path = module.file_path()
	for rewrite in workspace.reconcile_imports(snapshot):
		var r := rewrite as Dictionary
		ledger.record(str(r["file_path"]), str(r["before"]), str(r["after"]))
	ledger.end()
	reproject()
	preview.request_refresh()
	toast("Moved %s — applies on Save" % leaf)
	return true


## One module carrying its own folder.
## Re-files ONE module into `target_folder`, as one ledger entry.
##
## The folder pane's drop lands here; the card menu's move and the canvas drop land in the same
## place by other routes. A module that owns its folder carries it, which `place_at` handles.
func place_module(module_path: String, target_folder: String) -> bool:
	if workspace == null:
		return false
	var module := workspace.try_get(module_path)
	if module == null or module.read_only:
		return false
	if Paths.same(module.folder, target_folder):
		return false
	var destination := Paths.canon(target_folder.path_join(module_path.get_file()))
	ledger.begin("Move %s" % module_path.get_file())
	var snapshot := workspace.capture_imports()
	var ok := _move_one(module, target_folder, module_path.get_file())
	if ok:
		# RECORDED, so the move is undoable like every other structural edit. `_move_one` is the
		# shared mechanics of moving; the ledger entry belongs to the ACTION, which is what the
		# user would press Ctrl+Z about.
		ledger.record_move(module_path, destination)
		workspace.reconcile_imports(snapshot)
	ledger.end()
	if ok:
		reproject()
		# THE FOCUS FOLLOWS THE MODULE IT IS ON. `_focus_path` is a PATH, and a re-file changes it
		# -- so re-filing the module you are looking at left the focus naming a file that no longer
		# exists: the source pane blanked, the folder pane deselected, and `Service.project`
		# re-rooted the graph off a dead focus. `move_folder` already re-points; this route did not.
		if Paths.same(module_path, _focus_path):
			select_module(destination)
		_source.refresh_from_model()
		preview.request_refresh()
	return ok


func _move_one(module, target_folder: String, leaf: String) -> bool:
	var moved := workspace.place_at(module, target_folder)
	if moved.is_empty():
		return false
	reproject()
	toast("Moved %s — applies on Save" % leaf)
	return true


## Creates a module of `kind` beside the focus, opens it, and points every surface at it.
##
## THROUGH THE WORKSPACE, like everything else: the module lands in the tree in memory with a
## template buffer and nothing is written until Save, so creating one and thinking better of it
## costs a Ctrl+Z rather than a file on disk to go and delete.
## Asks for a name, then creates. A module's name is its export, its file, often its folder and
## every importer's specifier -- auto-naming it "NewComponent2" and making the user rename it is
## four edits to undo one decision they were never offered.
func prompt_create(kind: int) -> void:
	if workspace == null:
		return
	_pending_kind = kind
	_search_purpose = "create"
	_search_menu.open_name_prompt(
		"new %s" % Module.kind_label(kind), "name...",
		func(name: String) -> String: return _validate_name(kind, name),
		_menu_screen_at() if _menu_at != Vector2.ZERO else get_screen_position() + size * 0.3,
		Module.default_name_for(kind))


## Why a name cannot be used, or "" when it can.
##
## Ported from the Unity leg's `ValidateNewName`, including its two rules that are easy to miss:
## a name is taken only when the FILE it would produce is taken (a style module `card` and a
## component `Card` are the pairing the folder convention is built around, not a collision), and
## a COMPONENT name is a name in the WHOLE TREE -- two components exporting `Card` in different
## folders make every import of it ambiguous, and the path was free so nothing refused it.
func _validate_name(kind: int, name: String) -> String:
	if name.strip_edges().is_empty():
		return "name required"
	if kind == Module.Kind.HOOK:
		if not RegEx.create_from_string("^use[A-Z][A-Za-z0-9]*$").search(name):
			return "hook names start with 'use' (useSomething)"
	elif kind == Module.Kind.COMPONENT:
		if not RegEx.create_from_string("^[A-Z][A-Za-z0-9]*$").search(name):
			return "PascalCase identifier required"
	elif not RegEx.create_from_string("^[a-z][A-Za-z0-9]*$").search(name):
		return "camelCase identifier required"

	var folder := _create_folder(kind, name)
	if folder.is_empty():
		return "no folder to create in"
	
	if workspace.try_get(folder.path_join(name + Module.suffix_for(kind))) != null:
		return "%s already exists" % name
	if kind == Module.Kind.COMPONENT:
		for module in workspace.modules():
			if module.kind == Module.Kind.COMPONENT and module.name.to_lower() == name.to_lower():
				return "%s already exists in this tree" % name
	return ""


## THE ROOT OF THE OPEN TREE: the shallowest folder any module in it lives in.
##
## Derived rather than stored. A tree is recognised by MEMBERSHIP -- which modules are in it -- so
## it has no recorded root to go stale when the shallowest module is moved or deleted.
func tree_root() -> String:
	if workspace == null:
		return Workspace.UNSAVED_ROOT
	var best := ""
	for module in workspace.modules():
		var folder: String = module.folder
		if folder.is_empty():
			continue
		if best.is_empty() or folder.length() < best.length():
			best = folder
	return best if not best.is_empty() else Workspace.UNSAVED_ROOT


## Whether a create menu may be offered over `card_path` at all.
##
## A COMPANION card offers none (capability reference §5). A style or util module has no children:
## it is a leaf that belongs to the component beside it, and "create inside this" has no meaning
## there -- so the menu is absent rather than present and quietly creating somewhere else.
func can_create_at(card_path: String) -> bool:
	if workspace == null:
		return false
	if card_path.is_empty():
		return true
	var module := workspace.try_get(card_path)
	if module == null:
		return true
	return module.kind == Module.Kind.COMPONENT


## Where a new module of `kind` is born, given the card the menu was opened over.
##
## BIRTH LOCATION FOLLOWS WHERE YOU RIGHT-CLICKED, NEVER WHAT IS FOCUSED (capability reference §5).
## Those are different things constantly: the focus follows selection, and selection follows the
## last thing you clicked anywhere -- a library entry, a source pane, a preview element. Creating
## from a card's own menu and having the module appear beside some other card, because that other
## card happened to be selected, is the version this had before, and it is unexplainable from the
## screen.
##
##   empty canvas   -> the tree root
##   component card -> a COMPONENT becomes its child, in `<parent>/components/<Name>/`
##                     a COMPANION becomes its sibling, in `<parent>` itself
##
## "Create states placement; wiring states usage" -- so none of this adds an import. Where a module
## LIVES and whether anything USES it are separate decisions, and conflating them is how you get a
## tree of files that import each other because of where they were born.
func _create_folder(kind: int = Module.Kind.COMPONENT, name := "") -> String:
	var over := _menu_target
	if over.is_empty() or workspace == null:
		return tree_root()
	var parent := workspace.try_get(over)
	if parent == null or parent.kind != Module.Kind.COMPONENT:
		return tree_root()
	if kind != Module.Kind.COMPONENT:
		# A companion belongs BESIDE the component it companions -- that is the whole folder
		# convention: `Card.guitkx` and `card.style.guitkx` in one folder.
		return parent.folder
	var child := name.strip_edges()
	if child.is_empty():
		return parent.folder.path_join("components")
	return parent.folder.path_join("components").path_join(child)


## Creates `name` once the prompt accepted it.
func _create_named(kind: int, name: String) -> String:
	if workspace == null or name.strip_edges().is_empty():
		return ""
	var folder := _create_folder(kind, name)
	if folder.is_empty():
		return ""
	var path := folder.path_join(name + Module.suffix_for(kind))
	var module := workspace.create_new(path, Edits.template_for(kind, name))
	if module == null:
		return ""
	ledger.record_creation(path)
	reproject()
	select_module(path)
	preview.request_refresh()
	return path


## Renames the module the card menu was opened on.
func _rename_to(name: String) -> void:
	if workspace == null or _menu_target.is_empty() or name.strip_edges().is_empty():
		return
	var module := workspace.try_get(_menu_target)
	if module == null or module.read_only:
		return
	# THROUGH `move_to`, which is the one operation that knows a rename is four edits that land
	# together or not at all: the export, the file, the folder when the module owns one, and every
	# importer's specifier. Renaming the module object alone would leave the tree importing a name
	# nothing exports any more.
	var folder := module.folder
	var rewrites := workspace.move_to(module.file_path(), folder, name)
	if rewrites.is_empty() and module.name != name:
		return
	reproject()
	select_module(folder.path_join(name + Module.suffix_for(module.kind)))
	preview.request_refresh()


func create_module(kind: int) -> String:
	if workspace == null:
		return ""
	var folder := _focus_path.get_base_dir()
	if folder.is_empty():
		return ""
	var base := _unused_name(folder, kind)
	var path := folder.path_join(base + Module.suffix_for(kind))
	var module := workspace.create_new(path, Edits.template_for(kind, base))
	if module == null:
		return ""
	ledger.record_creation(path)
	reproject()
	select_module(path)
	preview.request_refresh()
	return path


## A name nothing in the folder is using yet -- "NewComponent", then "NewComponent2", and so on.
func _unused_name(folder: String, kind: int) -> String:
	var stem := Module.default_name_for(kind)
	var attempt := stem
	var n := 1
	while workspace.try_get(folder.path_join(attempt + Module.suffix_for(kind))) != null:
		n += 1
		attempt = "%s%d" % [stem, n]
	return attempt


## Writes the tree.
##
## A BLANK module is not written and does not block the save: it stays pending, and the console
## says so, because it is almost always a module someone created and then thought better of.
## Deleting it is the user's call, and refusing the whole save over it would hold every other
## change hostage to a decision about one empty file.
func save() -> int:
	if workspace == null:
		return 0
	# A TREE THAT HAS NEVER BEEN PLACED IS PLACED FIRST. Everything a user builds from the start
	# screen lives under the provisional root, whose name ends in `~` so Godot's importer skips
	# it -- writing there would put real files somewhere the engine never looks, and the module
	# would exist on disk while every import of it resolved to nothing.
	if not workspace.unlocated_modules().is_empty():
		_ask_where_the_tree_lives()
		return 0
	# SAVE NAMES EVERY FILE IT WOULD DELETE, and asks first. Deletion is the one thing a save does
	# that cannot be taken back from inside the builder -- everything else is a write the ledger
	# still remembers. A module leaves the tree the moment it is deleted, so by the time Save runs
	# the only trace of it is a path in the last projection that no module claims any more; a
	# confirmation that just said "3 files will be removed" would be naming nothing the user could
	# check.
	if not _confirmed_deletions():
		return 0
	for blank in workspace.blank_modules():
		_console.add_diagnostics(blank.file_path(), [{
			"code": "", "severity": Console.SEVERITY_WARNING, "line": -1,
			"message": "empty, so it was not written -- delete it, or give it something to hold",
		}])
	var written := workspace.save_all()
	# Cleared HERE, not on a clean tree: the journal being there has to mean exactly one thing --
	# work existed that never reached disk -- or the recovery offer becomes noise.
	Journal.clear()
	_capture_layout()
	_folders.rebuild()
	_refresh_status()
	return written


## Whether the user has agreed to the deletions this save would perform.
##
## Returns true when there are none, which is the ordinary case. The dialog is raised once and the
## save resumes through `save()` when it is accepted, so the answer is not remembered between
## saves -- a later save deleting a different file has to ask about that one.
func _confirmed_deletions() -> bool:
	if workspace == null:
		return true
	var doomed := workspace.tree().orphaned_paths()
	if doomed.is_empty() or _deletions_agreed:
		return true

	var names := PackedStringArray()
	for path in doomed:
		names.append("    " + str(path).trim_prefix("res://"))
	var dialog := ConfirmationDialog.new()
	dialog.title = "Save will delete %d file(s)" % doomed.size()
	dialog.dialog_text = "These files leave the project:

%s

They go to the system trash." 		% "
".join(names)
	dialog.ok_button_text = "Delete and save"
	dialog.confirmed.connect(func():
		_deletions_agreed = true
		save()
		_deletions_agreed = false)
	dialog.close_requested.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()
	return false


## Asks for a folder, then moves every unplaced module into it.
##
## Ported from the Unity leg's `ResolveUnsavedLocation`. The whole relocation is PLANNED BEFORE
## ANYTHING MOVES, so a collision cancels all of it rather than leaving half the tree in the new
## folder and half at the provisional path -- and the relative shape under the provisional root
## is preserved, because a component and the folder it owns were arranged that way on purpose.
func _ask_where_the_tree_lives() -> void:
	var dialog := EditorFileDialog.new()
	dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_DIR
	dialog.access = EditorFileDialog.ACCESS_RESOURCES
	dialog.title = "Where should this UI live?"
	dialog.dir_selected.connect(func(folder: String):
		dialog.queue_free()
		if _place_tree_in(folder):
			save())
	dialog.canceled.connect(func():
		dialog.queue_free()
		toast("Save cancelled — a new tree needs a folder before it can be written."))
	add_child(dialog)
	dialog.popup_centered_ratio(0.6)


## Moves every unplaced module under `folder`, keeping the shape they had. False when nothing
## moved, so the caller does not go on to save a tree that is still unplaced.
func _place_tree_in(folder: String) -> bool:
	var pending := workspace.unlocated_modules()
	if pending.is_empty():
		return true
	var root := Workspace.UNSAVED_ROOT

	# Planned first, in full.
	var plan: Array = []
	for module in pending:
		var relative := Paths.canon(module.folder).trim_prefix(root).trim_prefix("/")
		var target := folder.path_join(relative) if not relative.is_empty() else folder
		var destination := target.path_join(module.file_path().get_file())
		if workspace.try_get(destination) != null or FileAccess.file_exists(destination):
			toast("%s is already there — nothing was moved." % destination.get_file())
			return false
		plan.append({ "module": module, "to": target })

	ledger.begin("Place the tree")
	var snapshot := workspace.capture_imports()
	for entry in plan:
		var spec := entry as Dictionary
		var module = spec["module"]
		var from: String = module.file_path()
		workspace.move_to(from, str(spec["to"]), module.name)
		if Paths.same(_focus_path, from):
			_focus_path = module.file_path()
	for rewrite in workspace.reconcile_imports(snapshot):
		var r := rewrite as Dictionary
		ledger.record(str(r["file_path"]), str(r["before"]), str(r["after"]))
	ledger.end()
	reproject()
	return true


func abort() -> int:
	if workspace == null:
		return 0
	var reverted := workspace.abort_all()
	ledger.clear()
	Journal.clear()
	reproject()
	_source.refresh_from_model()
	return reverted


## Walks one ledger entry back. Every change in it, or none -- a gesture that touched two files is
## one action, and undoing it file by file leaves a state the user never authored.
func undo() -> bool:
	var entry := ledger.undo()
	if entry == null:
		return false
	ledger.suppress(func(): _replay(entry, true))
	return true


func redo() -> bool:
	var entry := ledger.redo()
	if entry == null:
		return false
	ledger.suppress(func(): _replay(entry, false))
	return true


func _replay(entry, reverse: bool) -> void:
	var changes: Array = entry.changes.duplicate()
	if reverse:
		changes.reverse()
	for change in changes:
		_replay_change(change, reverse)
	reproject()
	_source.refresh_from_model()
	preview.request_refresh()


func _replay_change(change, reverse: bool) -> void:
	# Resolved by IDENTITY first: an entry outlives the path it was recorded against, and a
	# replay that looked the module up by path would write to a name nothing answers to.
	var module := workspace.by_id(change.module_id)
	var path: String = module.file_path() if module != null else change.file_path
	match change.kind:
		Ledger.ChangeKind.EDIT:
			workspace.apply_edit(path, change.before if reverse else change.after)
		Ledger.ChangeKind.CREATION:
			if reverse:
				workspace.delete(path)
			elif module == null:
				workspace.create_new(change.file_path, "")
		Ledger.ChangeKind.DELETION:
			if reverse:
				workspace.restore(change.removed)
			else:
				workspace.delete(path)
		Ledger.ChangeKind.MOVE:
			workspace.move_to_path(change.after if reverse else change.before,
				change.before if reverse else change.after)


func _capture_layout() -> void:
	if layout == null or graph == null:
		return
	layout.capture_from(graph, _canvas.camera, _canvas.zoom)
	layout.save(Time.get_datetime_string_from_system(true))


# ── Reactions ────────────────────────────────────────────────────────────────────────

## The focus moved. Every surface follows it, INCLUDING the one that asked -- which is why this
## is re-entrancy guarded: the folder pane announces a selection, this points the folder pane at
## it, and the pane announces it again. Two surfaces that each echo the other never stop.
func select_module(file_path: String) -> void:
	var wanted := Paths.canon(file_path)
	if _choosing or wanted.is_empty():
		return
	_choosing = true
	_focus_path = wanted
	_source.workspace = workspace
	_source.show_module(_focus_path)
	_folders.select_path(_focus_path)
	if _library != null and graph != null:
		var at := graph.index_of(_focus_path)
		var card = graph.cards[at] if at >= 0 else null
		_library.select_component(
			str(card.exports[0]) if card != null and not card.exports.is_empty() else "")
	if _preview_pane != null:
		# BUILD IT IF IT IS NOT BUILT. A round compiles the focus's closure, and the module a user
		# selects next is often outside the closure the last one had -- so the pane would sit on
		# "select a component to see it rendered" while a component was selected, until some later
		# edit happened to rebuild it. Selecting IS the request.
		if preview.built_script(_focus_path) == null:
			preview.compile_dirty(_focus_path)
		_preview_pane.show_module(_focus_path)
	preview.request_refresh()
	_refresh_status()
	_choosing = false


var _choosing := false


func _on_card_selected(index: int) -> void:
	if graph == null or index < 0 or index >= graph.cards.size():
		return
	select_module(graph.cards[index].file_path)


func _on_camera_changed(camera: Vector2, zoom: float) -> void:
	if layout == null:
		return
	layout.camera = camera
	layout.zoom = zoom


func _open_card_menu(file_path: String, at: Vector2) -> void:
	_menu_target = file_path
	var module := workspace.try_get(file_path) if workspace != null else null
	_card_menu.set_item_disabled(_card_menu.get_item_index(CardMenuId.DELETE),
		module == null or module.read_only)
	_card_menu.set_item_disabled(_card_menu.get_item_index(CardMenuId.RENAME),
		module == null or module.read_only)
	# The menu says WHICH module it is about. "Delete" over a canvas of five cards is a question
	# the user has to answer from memory of where they right-clicked.
	var shown := file_path.get_file()
	_card_menu.set_item_text(_HEADER_ITEM, shown.to_upper())
	_card_menu.set_item_text(_card_menu.get_item_index(CardMenuId.RENAME), "Rename %s..." % shown)
	_card_menu.set_item_text(_card_menu.get_item_index(CardMenuId.DELETE), "Delete %s" % shown)
	# A COMPANION CARD OFFERS NO CREATE MENU (capability reference §5): a style or util module has
	# no inside to create in, so the submenu would only ever mean "somewhere else".
	_card_menu.set_item_disabled(_NEW_SUBMENU_ITEM, not can_create_at(file_path))
	_card_menu.position = Vector2i(at)
	_card_menu.popup()


func _on_card_menu(id: int) -> void:
	match id:
		CardMenuId.OPEN:
			select_module(_menu_target)
		CardMenuId.DELETE:
			delete_module(_menu_target)
		CardMenuId.RENAME:
			_search_purpose = "rename"
			var current := workspace.try_get(_menu_target) if workspace != null else null
			if current == null:
				return
			_search_menu.open_name_prompt("rename %s" % current.name, "name...",
				func(name: String) -> String: return _validate_name(current.kind, name),
				_menu_screen_at(), current.name)
			return
		CardMenuId.REVEAL_CARD:
			# The rename prompt itself is a chrome affordance; the model operation it drives is
			# `move_to_path`, which is what the ledger replays.
			select_module(_menu_target)


# ── Gestures ─────────────────────────────────────────────────────────────────────────

## Drops a library entry onto the canvas at a screen point.
##
## The target is resolved from the POINTER at the moment of the drop, against the graph as it is
## then -- never from rows captured when the drag began. The canvas re-renders while a drag is in
## flight, because the preview recompiles as the user works.
func drop_library_entry(kind: String, name: String, at: Vector2) -> bool:
	var hit := Drag.resolve(graph, at, _canvas.camera, _canvas.zoom)
	if not bool(hit["found"]):
		return false
	var card: Graph.Card = hit["card"]
	if kind == LibraryPane.ENTRY_HOOK:
		return apply_edit(card.file_path,
			Edits.insert_setup_line(_buffer_of(card.file_path), card, "var _ = %s()" % name),
			"add %s" % name)

	# A MODULE from the library: a style module dropped ON AN ELEMENT styles it; anything else,
	# and a style dropped on the card rather than a row, adds the import alone.
	if kind == LibraryPane.ENTRY_STYLE or kind == LibraryPane.ENTRY_UTIL 			or kind == LibraryPane.ENTRY_HOOK_MODULE:
		return drop_module_export(card, hit["row"], kind, name)

	var row: Graph.Line = hit["row"]
	if row == null or row.kind == Graph.LineKind.IMPORT:
		return false
	var placement: Edits.Placement = hit["placement"]
	var verdict := Edits.can_place(card, row, placement)
	if not bool(verdict["ok"]):
		# A TOAST as well as the console line. A refused drop is answered while the user is still
		# holding the thing they dropped, and the console is at the bottom of the window where
		# nobody is looking mid-drag.
		toast(str(verdict["reason"]))
		_console.add_diagnostics(card.file_path,
			[{ "code": "", "severity": Console.SEVERITY_WARNING, "message": str(verdict["reason"]), "line": -1 }])
		return false
	return apply_edit(card.file_path,
		_with_component_import(
			Edits.insert(_buffer_of(card.file_path), card, row, Drag.markup_for(name), placement),
			card.file_path, name),
		"add <%s>" % name)


## The card that exports `name` and is of `kind`, or null.
func _module_exporting(name: String, kind: int) -> Graph.Card:
	if graph == null:
		return null
	for card in graph.cards:
		if card.kind == kind and card.exports.has(name):
			return card
	return null


## A MODULE EXPORT dropped on the canvas.
##
## A STYLE DROPPED ON AN ELEMENT IS APPLIED TO IT -- the style attribute is set and the import
## added, as ONE undoable action. Adding only the import was the version this had: the card gained
## a line, the preview looked identical, and the styling still had to be typed by hand.
##
## THE WRITE ORDER IS LOAD-BEARING. The attribute goes in FIRST, against the row's current source
## line, because inserting an import at the top of the file shifts every line below it down by one
## and the row's recorded position would then be off by exactly that.
##
## Dropped on the CARD rather than a row it adds the import alone, which is the right answer
## there -- and the only answer for a util or hook module, which style nothing.
func drop_module_export(card: Graph.Card, row: Graph.Line, kind: String, name: String) -> bool:
	if card == null or workspace == null:
		return false
	var module_kind := Module.Kind.STYLE
	if kind == LibraryPane.ENTRY_UTIL:
		module_kind = Module.Kind.UTIL
	elif kind == LibraryPane.ENTRY_HOOK_MODULE:
		module_kind = Module.Kind.HOOK
	var source_card := _module_exporting(name, module_kind)
	if source_card == null or Paths.same(source_card.file_path, card.file_path):
		return false

	var text := _buffer_of(card.file_path)
	var styleable := kind == LibraryPane.ENTRY_STYLE and row != null 		and (row.kind == Graph.LineKind.ELEMENT or row.kind == Graph.LineKind.COMPONENT)

	# The BINDING, not the export name: a style module and the component it belongs to are named
	# by two conventions that collapse onto one identifier, so importing `Card` into `Card`
	# redeclares the file's own name.
	var bound := Edits.bind_export(text, card.file_path, source_card.file_path, name)
	var binding := str(bound["binding"])

	if styleable:
		text = Edits.set_attribute(text, row, "style", binding, false)
		text = str(Edits.bind_export(text, card.file_path, source_card.file_path, name)["text"])
		return apply_edit(card.file_path, text,
			"style %s with %s" % [row.text.strip_edges(), name])
	return apply_edit(card.file_path, str(bound["text"]), "import %s" % name)


## Re-parents a markup row. The gesture the Unity leg lists as unreliable, and the one this whole
## drag design exists for: both ends are re-resolved against the current graph.
func drop_row(drag: Drag, at: Vector2) -> bool:
	var card := drag.source_card(graph)
	var row := drag.source_row(graph)
	if card == null or row == null:
		return false
	var hit := Drag.resolve(graph, at, _canvas.camera, _canvas.zoom)
	if not bool(hit["found"]) or hit["card"] != card:
		# A row can only move within its own module: moving it to another would mean deciding
		# what to do about every name its subtree references, which is a different operation.
		return false
	var target: Graph.Line = hit["row"]
	if target == null or target == row:
		return false
	return apply_edit(card.file_path,
		Edits.move(_buffer_of(card.file_path), card, row, target, hit["placement"]),
		"move <%s>" % row.name)


## Drops a MODULE onto an element: a style module applies itself, anything else adds an import.
##
## This is the whole style-application gesture. `style={ Name }` plus the import it needs -- two
## edits, one action, so one undo takes both back. A style applied without its import is a file
## that does not compile, and an import added without the use is GUITKX2304.
func drop_module(module_path: String, at: Vector2) -> bool:
	var hit := Drag.resolve(graph, at, _canvas.camera, _canvas.zoom)
	if not bool(hit["found"]):
		return false
	var card: Graph.Card = hit["card"]
	if Paths.same(card.file_path, module_path):
		return false
	var source_card := graph.card_of(module_path)
	if source_card == null or source_card.exports.is_empty():
		return false
	var export_name := str(source_card.exports[0])

	var row: Graph.Line = hit["row"]
	var text := _buffer_of(card.file_path)
	var described := ""
	if source_card.kind == Module.Kind.STYLE and row != null \
			and (row.kind == Graph.LineKind.ELEMENT or row.kind == Graph.LineKind.COMPONENT):
		text = Edits.set_attribute(text, row, "style", export_name, false)
		described = "style <%s>" % row.name
	else:
		described = "import %s" % export_name
	text = Edits.ensure_import(text, card.file_path, module_path, PackedStringArray([export_name]))
	return apply_edit(card.file_path, text, described)


func _buffer_of(file_path: String) -> String:
	var module := workspace.try_get(file_path) if workspace != null else null
	return module.buffer_text if module != null else ""


## Every module that imports `target`, by file path.
##
## The question deletion asks before it does anything. Answered from the MODEL's import scan rather
## than by matching text, so an import written across two lines or with an alias still counts.
func referrers_to(target: String) -> PackedStringArray:
	var out := PackedStringArray()
	if workspace == null or graph == null:
		return out
	for card in graph.cards:
		if Paths.same(card.file_path, target):
			continue
		var spec := Specifiers.relative(card.file_path.get_base_dir(), target)
		if spec.is_empty():
			continue
		var module := workspace.try_get(card.file_path)
		if module == null:
			continue
		if Edits.imports_specifier(module.buffer_text, spec):
			out.append(card.file_path)
	return out


## Deletes a module: it leaves the tree, and the ledger holds the module itself so undo puts the
## SAME one back -- its identity, its buffer and its disk path.
##
## REFUSED WHILE ANOTHER MODULE IMPORTS IT, and the refusal NAMES THE REFERRERS (capability
## reference §2). This used to strip the importers' imports instead and delete anyway, which is a
## worse answer than it looks: the user asked to delete ONE file and silently got an edit to
## several others, none of them on screen, none of them the thing they were looking at. Unwiring is
## a decision about those files, so it belongs to whoever owns them -- and the refusal tells them
## exactly which ones to go and look at.
func delete_module(file_path: String) -> bool:
	if workspace == null:
		return false
	var module := workspace.try_get(file_path)
	if module == null or module.read_only:
		return false

	var referrers := referrers_to(file_path)
	if not referrers.is_empty():
		var names := PackedStringArray()
		for path in referrers:
			names.append(str(path).get_file())
		toast("Can't delete %s — still imported by %s" % [file_path.get_file(), ", ".join(names)])
		return false

	ledger.begin("Delete %s" % file_path.get_file())
	if not workspace.delete(file_path):
		ledger.end()
		return false
	ledger.record_deletion(file_path, module)
	ledger.end()
	reproject()
	_source.refresh_from_model()
	preview.request_refresh()
	return true


## The last toast the builder raised -- where a refusal says why it refused.
func toast_text() -> String:
	return _toast.text if _toast != null else ""


func _refresh_status() -> void:
	var dirty := workspace != null and workspace.has_unsaved_changes()
	# "RightSide.guitkx | 5 file(s), 0 dirty" — WHAT IS OPEN first, then the shape of the tree.
	# A count with no filename tells a user how much work is loaded but not which of it they are
	# looking at, and the builder's whole left column is about which one that is.
	if workspace == null or workspace.modules().is_empty():
		_status.text = "No tree open — double-click a .guitkx in the FileSystem dock, or start one below"
		return
	var dirty_count := 0
	for module in workspace.modules():
		if module.is_dirty():
			dirty_count += 1
	var open_name := _focus_path.get_file() if not _focus_path.is_empty() else "no module selected"
	_status.text = "%s  |  %d file(s), %d dirty" % [open_name, workspace.modules().size(), dirty_count]
	for button in _toolbar.get_children():
		if not button.has_meta("command"):
			continue
		match int(button.get_meta("command")):
			MenuId.UNDO:
				(button as Button).disabled = not ledger.can_undo()
			MenuId.REDO:
				(button as Button).disabled = not ledger.can_redo()
			MenuId.SAVE, MenuId.ABORT:
				(button as Button).disabled = not dirty
	if dirty != _was_dirty:
		_was_dirty = dirty
		dirty_changed.emit(dirty)


# ── Accessors, for the plugin and the tests ──────────────────────────────────────────

func canvas() -> CanvasHost:
	return _canvas


func folder_pane() -> FolderPane:
	return _folders


func library_pane() -> LibraryPane:
	return _library


func source_pane() -> SourcePane:
	return _source


func console() -> Console:
	return _console


func inline_editor() -> InlineEditor:
	return _inline


func focus_path() -> String:
	return _focus_path
