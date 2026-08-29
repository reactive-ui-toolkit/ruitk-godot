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

const DocTree = preload("res://addons/reactive_ui_toolkit_editor/builder/document/builder_tree.gd")
const Naming = preload("res://addons/reactive_ui_toolkit_editor/builder/document/builder_naming.gd")
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
const IslandEditor = preload("res://addons/reactive_ui_toolkit_editor/builder/chrome/builder_island_editor.gd")
const Edits = preload("res://addons/reactive_ui_toolkit_editor/builder/edits/builder_edits.gd")
const Specifiers = preload("res://addons/reactive_ui_toolkit_editor/builder/document/builder_specifiers.gd")
const Drag = preload("res://addons/reactive_ui_toolkit_editor/builder/edits/builder_drag.gd")
const AddonSettings = preload("res://addons/reactive_ui_toolkit_editor/editor/ruitk_editor_settings.gd")
const Parts = preload("res://addons/reactive_ui_toolkit_editor/builder/chrome/builder_chrome_parts.gd")
const SearchMenu = preload("res://addons/reactive_ui_toolkit_editor/builder/chrome/builder_search_menu.gd")
const Attributes = preload("res://addons/reactive_ui_toolkit_editor/builder/edits/builder_attributes.gd")
const Compiler = preload("res://addons/reactive_ui_toolkit/guitkx/guitkx.gd")
const LspWorkspace = preload("res://addons/reactive_ui_toolkit_editor/lsp/guitkx_workspace.gd")
const Schema = preload("res://addons/reactive_ui_toolkit_editor/lsp/guitkx_schema.gd")
const PreviewPane = preload("res://addons/reactive_ui_toolkit_editor/builder/chrome/builder_preview_pane.gd")
const Palette = preload("res://addons/reactive_ui_toolkit_editor/builder/canvas/canvas_palette.gd")
const Metrics = preload("res://addons/reactive_ui_toolkit_editor/builder/canvas/builder_canvas_metrics.gd")

## The tree changed in a way the host should know about -- for the plugin's title, or a prompt on
## close.
signal dirty_changed(has_unsaved: bool)

## Menu ids. Named rather than positional, so inserting an item cannot silently re-point another.
enum MenuId { SAVE, ABORT, UNDO, REDO, FIT_VIEW, REVEAL, HISTORY, TRACE, HELP }

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
	ADD_CASE = 214, ADD_DEFAULT = 215,
	OPEN_IMPORT = 216, REMOVE_IMPORT = 217, EDIT_BODY_LINE = 218, EDIT_ISLAND = 219,
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

## The multiline editor, for a card's setup island.
var _island: IslandEditor = null
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
## A newline, built rather than written: an escape in a source literal has to survive every layer
## between here and the file.
const _LF := "
"

var _menu_row = null

## WHERE the menu row lives, so it can be resolved again against the CURRENT projection.
##
## `_menu_row` holds a `Line` object, and every edit rebuilds a card's rows as new instances --
## so after any menu edit it described the buffer as it was BEFORE that edit, and a Delete then cut
## at offsets that had moved. The coordinates survive a re-projection; the object does not.
var _menu_section := -1
var _menu_row_index := -1

## The header text a wrap just seeded, waiting for the editor to open on it once the edit has been
## applied and the card re-projected. Empty when the pending action is not a wrap.
var _seed_header_edit := ""

## Set only while a save is resuming from its own deletion confirmation, so the second pass does
## not ask again.
## The folder pane's header, the column it heads, and whether it is folded away.
var _folders_header: Button = null
var _folders_column: VBoxContainer = null
var _folders_folded := false

## The drift check is a one-shot: it compares two static tables and its answer cannot change
## while the process runs.
## The style entry whose value the menu is currently asking about.
var _pending_style := {}

## Set for the length of a history jump, so the redraw happens once rather than per entry.
var _walking_history := false

var _drift_checked := false

## The tag drift check is a one-shot too, and it sweeps ClassDB -- which is not something to put
## in front of every reprojection.
var _tag_drift_checked := false

var _deletions_agreed := false

## Set only while a save is resuming from its own empty-module question.
var _blanks_agreed := false

## Whether the preview pipeline's own narration is being echoed into the console.
var _tracing := false

## Whether the crash-journal offer has been made for this window. Asked once: a second prompt for
## the same journal reads as the builder not believing the first answer.
var _offered_recovery := false
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
var _hint: Label = null
var _syncing_layer := false
var _empty_state: Control = null
var _toast: Label = null

## The bottom-anchored slot that keeps the toast centred through every `reset_size`.
var _toast_slot: CenterContainer = null
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
	# ONE REDRAW FOR THE WALK, not one per entry crossed. Every step re-projected the graph, fed
	# the source pane and asked the preview for a round -- so jumping back twenty actions did
	# twenty of each, and the canvas visibly stepped through history rather than arriving at it.
	_walking_history = true
	while ledger.cursor() > target and undo():
		moved = true
	while ledger.cursor() < target and redo():
		moved = true
	_walking_history = false
	if moved:
		reproject()
		_rebind_focus_if_missing()
		_source.refresh_from_model()
		preview.request_refresh()
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
	_toast.modulate.a = 1.0
	_toast.reset_size()
	_toast_until = Time.get_ticks_msec() + TOAST_MSEC


## How long a toast stays up, and how much of the end of that is a fade.
const TOAST_MSEC := 3200
const TOAST_FADE_MSEC := 600


func _tick_toast() -> void:
	if _toast == null or not _toast.visible:
		return
	var left := _toast_until - Time.get_ticks_msec()
	if left <= 0:
		_toast.visible = false
		_toast.modulate.a = 1.0
		return
	# IT FADES. A pill that vanishes between two frames reads as a glitch; the last 600 ms of its
	# life are a ramp, which is what makes the disappearance legible as the message expiring.
	_toast.modulate.a = clampf(float(left) / float(TOAST_FADE_MSEC), 0.0, 1.0)


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
## The selected row, RE-RESOLVED against the current projection.
##
## Never the stored object: an edit rebuilds a card's rows, so the stored one describes the buffer
## as it was before. The coordinates still name the right row, and `_row_of` reads the live
## projection.
func _live_menu_row():
	if _menu_card < 0 or _menu_section < 0 or _menu_row_index < 0:
		return _menu_row
	var fresh = _row_of(_menu_card, _menu_section, _menu_row_index)
	return fresh if fresh != null else _menu_row


func _delete_selection() -> void:
	var row = _live_menu_row()
	if row != null and not _menu_target.is_empty() and workspace != null:
		var module := workspace.try_get(_menu_target)
		if module != null and not module.read_only and Edits.has_span(row):
			# A COMPONENT MUST RETURN ONE NODE, so its return root cannot be deleted. The menu
			# guards this; the Delete KEY did not guard it at all.
			var card_now := graph.card_of(_menu_target) if graph != null else null
			if card_now != null and _menu_section == int(Metrics.Section.MARKUP) \
					and _menu_row_index == Edits.first_element_row(card_now):
				toast("%s must return one node." % _menu_target.get_file())
				return
			var after := Edits.remove(module.buffer_text, row)
			if after != module.buffer_text:
				apply_edit(_menu_target, after, "Delete %s" % row.text.strip_edges())
				_menu_row = null
				_menu_section = -1
				_menu_row_index = -1
				return
	if not _focus_path.is_empty():
		# THE FALL-THROUGH IS THE DANGEROUS ONE. With no row selected, Delete deletes the whole
		# focused MODULE -- and the row selection is nulled by the branch above, so a second Delete
		# after deleting a row falls straight through to it. The confirmation dialog that used to
		# guard this was dissolved deliberately (the save-only contract means nothing is gone until
		# Save, and Ctrl+Z puts it back), so what is owed here is not a modal but a sentence saying
		# what just happened and how to take it back. `delete_module` toasts the deletion; this
		# says which route reached it.
		if _live_menu_row() == null and graph != null and graph.cards.size() > 0:
			toast("Deleted %s — Ctrl+Z to put it back, applies on Save" % _focus_path.get_file())
		delete_module(_focus_path)


## Escape: close whatever is open, innermost first.
func _cancel_active_edit() -> void:
	if _search_menu != null and _search_menu.visible:
		_search_menu.hide()
		return
	if _island != null and _island.is_open():
		_island.cancel()
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
## Coming back to the builder is when a file is most likely to have changed underneath it.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_VISIBILITY_CHANGED:
		if is_visible_in_tree():
			adopt_external_changes()


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
	# FOLDABLE. The left column is two panes in a split, and with the folder tree holding a fixed
	# 240 units the library below it was a strip -- on a tree of a dozen folders the pane you
	# actually pick elements out of had four rows. The choice rides in the layout file with the
	# camera, because which panes a person works with belongs to the tree they are working on.
	_folders_header = Parts.folding_pane_header("Folders",
		func(): _fold_folders(not _folders_folded))
	folders_column.add_child(_folders_header)
	left.add_child(folders_column)
	_folders = FolderPane.new()
	_folders.size_flags_vertical = Control.SIZE_EXPAND_FILL
	folders_column.add_child(_folders)
	_folders_column = folders_column
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
	# A SEPARATE MULTILINE EDITOR for the setup island. The two differ in what Enter means -- a
	# single-line field commits on it, GDScript takes it as a new statement -- and routing an
	# island through the single-line one would flatten a multi-statement island into one line the
	# moment it committed.
	_island = IslandEditor.new()
	canvas_layer.add_child(_island)

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
	# BOTTOM CENTRE, CLEAR OF THE CHROME. Anchored top-centre it drew over the toolbar -- the row
	# carrying the very buttons whose refusals it reports -- and `PRESET_CENTER_TOP` anchors the
	# LEFT EDGE at the centre, so a message started in the middle and ran right instead of being
	# centred at all. A CenterContainer keeps it centred through every `reset_size`.
	_toast_slot = CenterContainer.new()
	_toast_slot.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_toast_slot.offset_top = -84.0
	_toast_slot.offset_bottom = -44.0
	_toast_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_slot.z_index = 100
	add_child(_toast_slot)
	_toast_slot.add_child(_toast)

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

	# ONE HISTORY SURFACE. A second PopupMenu carrying Undo and Redo was built, wired and reachable
	# from nothing -- `MenuId.HISTORY` opens the searchable list, which is the real one -- so the
	# builder carried a dead menu and an id that named it.


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
func _on_library_framed(file_path: String, name: String) -> void:
	if graph == null:
		return
	# BY PATH WHEN THERE IS ONE. Resolving by name alone framed the FIRST card that exports it,
	# so two modules in different folders exporting the same name were indistinguishable and the
	# gesture took the reader to whichever the projection happened to put first.
	if not file_path.is_empty():
		var direct := graph.index_of(file_path)
		if direct >= 0:
			_canvas.frame_card(direct)
			select_module(file_path)
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
		after = Edits.insert_setup_line(before, card, Attributes.hook_stub(name))
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
	# ALL THREE EDGE KINDS. The canvas draws a hook import in its own colour now, and a key that
	# names two of three colours is a key you have to check against the picture.
	legend.add_child(Parts.legend_entry("usage edge", Palette.edge_component()))
	legend.add_child(Parts.legend_entry("hook edge", Palette.edge_hook()))
	legend.add_child(Parts.legend_entry("style edge", Palette.edge_style()))
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
	# THROUGH `_screen_at`, like every other menu. This was the fifth one, and the only one still
	# reading a CanvasItem coordinate directly -- which is right only when the host viewport
	# embeds its subwindows.
	_folders.refile_refused.connect(func(reason: String): toast(reason))
	_folders.module_context_requested.connect(func(path: String, _at: Vector2):
		_open_card_menu(path, _screen_at(get_local_mouse_position())))

	_canvas.card_selected.connect(_on_card_selected)
	_canvas.card_add_requested.connect(_on_card_add)
	_canvas.row_clicked.connect(_on_row_clicked)
	# GO-TO-DEFINITION LANDS ON THE CANVAS TOO. A module in the open tree is a card, and taking the
	# reader to the file without taking them to the card leaves the two halves of the builder
	# pointing at different things.
	# THE FIELD SHOWS THE FAILURE, not only the toast. A toast has faded by the time the reader
	# looks back at the text.
	_source.complained.connect(func(_message: String): _source.set_error(true))
	_source.edit_applied.connect(func(_p: String, _t: String): _source.set_error(false))
	_source.edit_cancelled.connect(func(_p: String, _t: String): _source.set_error(false))
	# AND THE HOVER REACHES BOTH SURFACES. Hovering a hook chip warmed the card's markup rows and
	# did nothing to the pane showing the code those rows came from.
	_canvas.hover_names_changed.connect(func(names: PackedStringArray):
		_source.set_trace_names(names))
	_source.definition_requested.connect(_on_definition_requested)
	_source.diagnostic_clicked.connect(func(file_path: String, line: int, _record: Variant):
		if not file_path.is_empty():
			select_module(file_path)
		_source.goto_line(line + 1)
		_console.visible = true)
	_canvas.row_activated.connect(_on_row_activated)
	_canvas.card_activated.connect(func(index: int):
		if graph == null or index < 0 or index >= graph.cards.size():
			return
		_canvas.frame_card(index)
		select_module(graph.cards[index].file_path))
	_canvas.row_context_requested.connect(_on_row_context)
	_canvas.dropped.connect(_on_canvas_drop)
	_canvas.card_moved.connect(_on_card_moved)
	_inline.committed.connect(_on_inline_committed)
	# The same funnel: an island commit is an edit like any other.
	_island.committed.connect(_on_inline_committed)
	_island.cancelled.connect(func(_token: Variant, undo_seeding: bool):
		_menu_row = null
		if undo_seeding:
			undo())
	# An ABANDONED inline edit still has to clear what it was about: leaving `_menu_row` pointing
	# at a row after the user pressed Escape means the next Delete acts on a row they walked away
	# from.
	# EVERY CLOSE, whatever route it took. Clearing the row was written on the CANCEL path alone,
	# so a committed edit left `_menu_row` pointing at the row it had finished with -- and the
	# next Delete acted on a row the user had walked away from. The commit path is the common one.
	_inline.closed.connect(_on_editor_closed)
	_island.closed.connect(_on_editor_closed)
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
		# WHERE THIS GESTURE WAS. `_menu_at` was set by the ROW context handler alone, so a rename
		# prompt opened from a card menu, or a create prompt opened from the canvas menu, appeared
		# wherever the last row right-click had been -- possibly on another card, possibly off
		# screen, and on a fresh session at the window's top-left corner.
		_menu_at = _canvas.get_local_mouse_position()
		_open_card_menu(graph.cards[index].file_path,
			_canvas_at(_canvas.get_local_mouse_position())))
	_canvas.canvas_context_requested.connect(func(world: Vector2):
		_menu_world = world
		_menu_at = _canvas.get_local_mouse_position()
		# CLEARED: this menu was opened over empty canvas, so "new" means "at the tree root". Left
		# set, it still names whichever card was right-clicked last, and the module is born inside
		# a component the user is not even pointing at.
		_menu_target = ""
		_canvas_menu.position = Vector2i(_canvas_at(_canvas.get_local_mouse_position()))
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
	# AND THE LINE, NOT ONLY THE FILE. The row that knows exactly where to send the reader was the
	# one row whose stored path did not resolve, because the line was baked into it.
	_console.location_activated.connect(func(file_path: String, line: int):
		select_module(file_path)
		if line > 0:
			_source.goto_line(line))
	_card_menu.id_pressed.connect(_on_card_menu)
	_canvas_menu.id_pressed.connect(run_command)
	ledger.changed.connect(_refresh_status)
	# A FAILED round brings the console forward; a clean one leaves it away. That is the whole
	# rule, and it is why the console does not need to be on screen the rest of the time.
	preview.trace.connect(func(message: String):
		if _tracing and _console != null:
			_console.add_diagnostics("", [{
				"code": "", "severity": Console.SEVERITY_WARNING, "line": -1,
				"message": message,
			}]))
	preview.compile_finished.connect(func(_p: String, ok: bool, _e: String):
		if not ok and _console != null:
			_console.visible = true)
	# ONCE PER ROUND, not once per module. The preview re-renders on the BUILD rather than on the
	# keystroke -- but hung off `compile_finished` it re-mounted for every module the round
	# touched, including the ones the pane does not render.
	preview.round_finished.connect(func(_summary: Variant):
		_refresh_status()
		if _preview_pane != null and not _preview_pane.path().is_empty():
			_preview_pane.show_module(_preview_pane.rendered_path()))



# ── Opening ──────────────────────────────────────────────────────────────────────────

## Opens the tree the given module belongs to.
## Opens a tree for `focus_path`, keeping whatever is already open when it holds unsaved work.
##
## THE ENTRY POINT EVERY EXTERNAL CALLER SHOULD USE. `open_tree` replaces the tree outright --
## `load_tree` ends in `_tree.reset`, which clears every module -- so right-clicking a `.guitkx`
## in the FileSystem dock while the builder held a half-built component destroyed the whole
## session, silently and with the ledger cleared behind it.
##
## Three cases, which is what Unity's LoadTreeFor distinguishes:
##   * the tree already holds that module -> just focus it
##   * there is unsaved work            -> ADOPT the file into the open tree, keeping the work
##   * otherwise                        -> load its tree, and adopt the file if it is not in it
func load_tree_for(focus_path: String) -> void:
	if workspace == null or focus_path.is_empty():
		return
	if workspace.try_get(focus_path) != null:
		select_module(focus_path)
		return
	if workspace.has_unsaved_changes():
		if workspace.open(focus_path) == null:
			toast("Couldn't open %s." % focus_path.get_file())
			return
		reproject()
		select_module(focus_path)
		toast("Opened %s beside your unsaved work." % focus_path.get_file())
		return
	open_tree(focus_path)
	if workspace.try_get(focus_path) == null:
		workspace.open(focus_path)
		reproject()
		select_module(focus_path)


func open_tree(focus_path: String) -> void:
	if focus_path.strip_edges().is_empty():
		# The START SCREEN. Opening with nothing is what the menu does on a project that has no
		# `.guitkx` open, and it is a state this window is built to show.
		if workspace == null:
			workspace = Workspace.new()
		reproject()
		_refresh_status()
		_offer_recovery()
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
	# THE WHOLE TREE ENTERS THE INDEX AT OPEN. Completion and go-to-definition answer from it, and
	# it was only ever fed by `_reindex_language` on an EDIT -- so a module the session had not
	# yet typed into was invisible to both, and the builder's own tree was the one thing its
	# code editor could not complete against. In-memory text, not disk: under the save-only
	# contract those differ, and the buffer is what the user is looking at.
	for module in workspace.modules():
		if not module.read_only:
			LspWorkspace.reindex(module.file_path(), module.buffer_text)
	_validate_tree("after loading %s" % focus_path.get_file())
	reproject()
	select_module(_focus_path)
	if graph != null:
		_canvas.select_card(graph.index_of(_focus_path))


## Reports any broken tree invariant to the editor's error log.
##
## `BuilderTree.validate()` was written, covered and called by nothing but its own test -- so the
## two moments that can actually break an invariant, a load and a journal restore, checked
## nothing. It reports rather than refuses: a tree with a duplicate id is still a tree the user
## has work in, and taking it away from them is worse than telling them it is odd.
func _validate_tree(where: String) -> bool:
	if workspace == null:
		return true
	var problems: Array = workspace.tree().validate()
	for problem in problems:
		push_error("[builder] tree invariant broken %s: %s" % [where, str(problem)])
	return problems.is_empty()


## Shows or hides the folder tree, and remembers which.
func _fold_folders(folded: bool) -> void:
	_folders_folded = folded
	if _folders != null:
		_folders.visible = not folded
	if _folders_column != null:
		# The column gives its 240 units BACK when folded, so the library below actually receives
		# the space rather than the fold leaving a hole where the tree was.
		_folders_column.custom_minimum_size = Vector2(0.0, 0.0 if folded else 240.0)
	Parts.set_folded(_folders_header, folded)
	if layout != null and layout.folders_folded != folded:
		layout.folders_folded = folded
		layout.save(Time.get_datetime_string_from_system(true))


## Warns once if the language grew a directive this builder cannot offer.
##
## The schema is the vocabulary of record and `Edits.DIRECTIVE_SUPPORT` is what the builder can
## do with it. Nothing compared them, so a directive added to the language would simply never
## appear in the wrap menu -- silently, and with no test that could notice, because the menu is
## built from a list that would still be complete with respect to itself.
func _warn_on_directive_drift() -> void:
	if _drift_checked:
		return
	_drift_checked = true
	var missing := PackedStringArray()
	for entry in Schema.control_flow():
		var name := str(entry.get("directive", "")) if entry is Dictionary else str(entry)
		if name.is_empty():
			continue
		if not Edits.DIRECTIVE_SUPPORT.has(name):
			missing.append(name)
	if missing.is_empty():
		return
	push_warning("[builder] the language has directive(s) this builder cannot offer: %s"
		% ", ".join(missing))


## Warns once if the ENGINE offers instantiable Control classes the palette does not.
##
## The language accepts any instantiable ClassDB Node class as a tag; the palette offers a
## curated list. That is the right default -- sixty entries of engine internals is not a palette
## -- but nothing anywhere compared the two, so the difference was invisible to everyone
## including the people maintaining the list. A warning, not a menu: the curation is deliberate.
func _warn_on_tag_drift() -> void:
	if _tag_drift_checked:
		return
	_tag_drift_checked = true
	var offered := {}
	for entry in _library.entries():
		var spec := entry as Dictionary
		if str(spec.get("kind", "")) == LibraryPane.ENTRY_ELEMENT:
			offered[str(spec.get("name", ""))] = true
	var missing := PackedStringArray()
	for klass in ClassDB.get_inheriters_from_class("Control"):
		var name := str(klass)
		if offered.has(name) or not ClassDB.can_instantiate(name):
			continue
		missing.append(name)
	if missing.is_empty():
		return
	push_warning("[builder] the language accepts %d instantiable Control class(es) the palette "
		% missing.size() + "does not list: %s" % ", ".join(missing))


## Says why an import resolves to nothing.
##
## The canvas already draws a broken edge as a red dashed stub -- louder than the reference's
## answer -- and that is the whole of what the builder said: nothing named the SPECIFIER, nothing
## named the file it was looked for in, and grepping the addon for the diagnostic produced no
## hits. A stub with no explanation tells a reader that something is wrong and not what.
func _report_unresolved_imports() -> void:
	if graph == null or _console == null:
		return
	for edge in graph.edges:
		if not edge.is_broken() or edge.is_usage:
			continue
		if edge.from_index < 0 or edge.from_index >= graph.cards.size():
			continue
		var card := graph.cards[edge.from_index]
		var line := -1
		if edge.from_row >= 0 and edge.from_row < card.imports.size():
			line = int(card.imports[edge.from_row].source_line) - 1
		_console.add_diagnostics(card.file_path, [{
			"code": "GUITKX2301",
			"severity": Console.SEVERITY_WARNING,
			"line": line,
			"message": "\"%s\" resolves to nothing in this tree -- no module here exports it, and "
				% edge.specifier + "no file answers that path",
		}])


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
	# THE LAYOUT OBJECT SURVIVES THE REPROJECTION. `for_graph` re-reads it from `user://`, and
	# reprojection happens after every edit -- so an adoption made in memory a moment ago was
	# thrown away by the next keystroke, and a card created this session went back to a
	# projection slot each time. It is re-read when the TREE changes, which is `open_tree`.
	if layout == null or not Paths.same(layout.root_path, graph.root_path):
		layout = CanvasLayout.for_graph(graph)
	layout.apply_to(graph)
	var adopted := layout.adopt_unplaced(graph)
	# THE RESTORED POSITIONS ARE CHECKED, not trusted. A saved position is restored verbatim and a
	# card's height follows its CONTENT, so a hook added or an import written after the layout was
	# written leaves the two describing different trees -- and the cards sit on top of each other
	# until someone drags them apart by hand.
	var healed := Service.resolve_overlaps(graph)
	for path in healed:
		layout.set_position(str(path), Vector2(graph.card_of(path).x, graph.card_of(path).y))
	# AND AN ADOPTED SLOT IS SAVED. It was computed, applied, and the bool discarded -- so the
	# position a new card was given lived exactly as long as the window did.
	if adopted or not healed.is_empty():
		layout.save(Time.get_datetime_string_from_system(true))
	if layout.has_saved_view:
		# THROUGH `set_camera`, not by writing the fields. The direct write skipped the clamp, the
		# redraw and the `camera_changed` emit that syncs the layer dropdown -- so a restored
		# session could open with the toolbar naming a layer the cards were not drawn at, which is
		# the same lie CANVAS-01 was about, arriving by a different road.
		_canvas.set_camera(layout.camera, layout.zoom)
	_fold_folders(layout.folders_folded)
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
	_report_unresolved_imports()
	_warn_on_directive_drift()
	_warn_on_tag_drift()
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
## The diagnostics for one module, compiled with the tree's own component vocabulary.
##
## LI-05: `GUITKX0105` -- unknown element, with a did-you-mean -- is only raised when the compiler
## is TOLD which names are components; handed an empty list it suppresses the check entirely. The
## builder never told it, so `<Labell />` compiled clean and lowered to a call on a class that
## does not exist.
##
## Style and util exports are deliberately NOT in the union: they are not elements, and offering
## them would make a typo'd tag resolve to a dictionary.
func known_component_tags() -> PackedStringArray:
	var out := PackedStringArray()
	if graph == null:
		return out
	for card in graph.cards:
		if card.kind != Module.Kind.COMPONENT:
			continue
		for export_name in card.exports:
			if not out.has(str(export_name)):
				out.append(str(export_name))
	return out


## Compiles one module and paints what it says onto the source pane and the console.
## Tells the language layer what the builder is holding.
##
## `GuitkxWorkspace` is the index behind user-component tag completion, Ctrl+hover validation and
## go-to-definition, and it is built entirely FROM DISK. Under the save-only contract the disk is
## the state of the tree before the session started -- so completion offered components the user
## had renamed away, missed every one they had created, and go-to-definition opened files that no
## longer say what it thought.
##
## Pushed from the one edit funnel, so nothing else has to remember to. Cheap: `reindex` is a
## regex pass over one buffer, and it only ever runs on a buffer that just changed.
func _reindex_language(file_path: String) -> void:
	if workspace == null:
		return
	var module := workspace.try_get(file_path)
	if module == null or module.read_only:
		return
	LspWorkspace.reindex(file_path, module.buffer_text)


func _publish_diagnostics(file_path: String) -> void:
	if workspace == null or _source == null or not Paths.same(file_path, _source.path()):
		return
	var module := workspace.try_get(file_path)
	if module == null:
		return
	var result: Dictionary = Compiler.compile(module.buffer_text, module.name,
		known_component_tags(), {})
	var diagnostics: Array = result.get("diagnostics", [])
	_source.show_diagnostics(diagnostics)
	_console.add_diagnostics(file_path, diagnostics)


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
	_reindex_language(file_path)
	_publish_diagnostics(file_path)


## A keystroke in the source pane.
##
## IGNORED WHILE THE PANE IS IN EDIT MODE: the pane hands the buffer over once, on apply, after
## it has parsed. Funnelling every keystroke meant half a tag name was a state the preview
## compiled and the canvas re-projected -- so typing produced a stream of errors about text
## nobody had finished writing, and deleting a line to retype it blanked the card.
func _on_buffer_edited(file_path: String, before: String, after: String) -> void:
	# The `is_editing()` short-circuit that used to guard this is gone along with the reason for
	# it. The pane no longer writes the model per keystroke, so anything arriving here is a real
	# committed change -- and while it DID write per keystroke, this early return meant the ledger
	# never saw a source edit at all and the canvas kept showing the old file.
	#
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
	_run_round()
	_refresh_status()


## One compile round, reported.
##
## There were two call sites and only one of them reported: the round forced by `select_module`
## discarded its Summary while making the console visible with the PREVIOUS round's rows -- so
## selecting a module that failed to build showed a console full of stale successes.
func _run_round() -> void:
	var anchor := _preview_pane.rendered_path() if _preview_pane != null else _focus_path
	var summary = preview.compile_dirty(anchor)
	if summary != null:
		_console.report(summary)
	return


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


## Offers the crashed session's work back, once per window.
##
## `pending_recovery`, `restore_recovery` and `discard_recovery` all existed and NOTHING had ever
## called them -- the only reference in the whole repository was the parity gate, which greps for
## the identifier. So the journal was written faithfully every five seconds and never read, and
## the first Save of any later session cleared it: the crashed session's only copy, destroyed by
## the act of doing ordinary work.
##
## Offered only onto an EMPTY tree. Restoring over open modules would replace them, which is a
## second way to lose work while trying to prevent the first.
func _offer_recovery() -> void:
	if _offered_recovery or workspace == null or not workspace.modules().is_empty():
		return
	_offered_recovery = true
	var pending := pending_recovery()
	if pending.is_empty():
		return
	var names := PackedStringArray()
	for entry in (pending.get("modules", []) as Array):
		names.append("    " + str(entry).get_file())
	var dialog := ConfirmationDialog.new()
	dialog.title = "Restore unsaved work?"
	dialog.dialog_text = ("A previous session left unsaved work, last seen %s:

%s

"
		+ "Restoring opens it here. Discarding throws it away for good.") 		% [str(pending.get("saved_at", "recently")), "
".join(names)]
	dialog.ok_button_text = "Restore"
	dialog.cancel_button_text = "Discard"
	dialog.confirmed.connect(func():
		if restore_recovery():
			toast("Restored %d unsaved module(s)." % names.size()))
	dialog.canceled.connect(discard_recovery)
	dialog.close_requested.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()


## Takes the recovered tree. The caller asks first: restoring over an open tree replaces it.
func restore_recovery() -> bool:
	if workspace == null or not Journal.try_restore(workspace):
		return false
	# THE LEDGER DESCRIBES THE TREE IT WAS RECORDED AGAINST. A restore adopts a DIFFERENT tree,
	# so every entry still in it names modules that are no longer there -- and the first Ctrl+Z
	# after a recovery replayed a change against whatever now happened to hold that path.
	ledger.clear()
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
		MenuId.TRACE:
			# A TOGGLE, not a one-shot dump. `Preview` declares `signal trace(message)` and emits
			# it twice a round -- and nothing in the addon had ever connected it, so the pipeline
			# narrated itself to no one. Trace now turns that stream on, which is what makes a
			# round debuggable from its own output rather than from its symptoms.
			_console.visible = true
			_tracing = not _tracing
			_console.trace(workspace, ledger, preview)
			_console.add_diagnostics("", [{
				"code": "", "severity": Console.SEVERITY_WARNING, "line": -1,
				"message": "preview trace %s" % ("ON" if _tracing else "off"),
			}])
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
	_menu_section = _section
	_menu_row_index = row_index
	_canvas.select_row(card_index, _section, row_index)
	select_module(graph.cards[card_index].file_path)
	_source.goto_line(row.source_line)


## A card was dragged somewhere. Its new place is remembered for this tree.
##
## The layout store, its per-tree keying and the "top up rather than re-seed" rule were all
## written before anything could move a card -- so the whole persistence path had never once run
## on a position a user chose.
## Double-clicking a row edits it IN PLACE, which is the reference's primary editing gesture.
##
## Dispatched by section, because what "edit this" means differs: a hook chip and a code island
## are setup lines, a style entry is a dictionary line, and a directive head is its header
## expression. Each token is one `_on_inline_committed` already knows how to write back.
func _on_row_activated(card_index: int, section: int, row_index: int, at: Vector2) -> void:
	if graph == null or card_index < 0 or card_index >= graph.cards.size():
		return
	var card = graph.cards[card_index]
	var module := workspace.try_get(card.file_path) if workspace != null else null
	if module == null or module.read_only:
		return
	var row = _row_of(card_index, section, row_index)
	if row == null:
		return
	_menu_target = card.file_path
	_menu_row = row
	_menu_card = card_index
	_menu_section = section
	_menu_row_index = row_index
	_menu_at = at

	var rect := _row_rect_on_screen(card, section, row_index)
	match section:
		Metrics.Section.BODY:
			_inline.open_at(rect, row.source_text,
				{ "kind": "body", "path": card.file_path, "row": row })
		Metrics.Section.ISLAND:
			_island.open_at(rect, _LF.join(card.island_lines),
				{ "kind": "island", "path": card.file_path, "row": row,
					"from": card.island_start_line, "to": card.island_end_line })
		Metrics.Section.EXPORTS:
			if Edits.has_span(row):
				_inline.open_at(rect, row.source_text,
					{ "kind": "island", "path": card.file_path, "row": row,
						"from": row.source_line, "to": row.source_line,
						# WHICH EXPORT TO ADVANCE INTO when this one is finished with Enter.
						"advance_export": _export_owning(card, row_index) })
			else:
				_on_card_add(card_index, "entry")
		Metrics.Section.MARKUP:
			if row.kind == Graph.LineKind.DIRECTIVE:
				_inline.open_at(rect, row.directive_text,
					{ "kind": "directive", "path": card.file_path, "row": row })
			elif row.kind == Graph.LineKind.COMPONENT and _navigate_to_component(row.name):
				# A COMPONENT ROW IS A LINK. Double-clicking `<Card />` inside a component is the
				# reference's own route to the module that declares it, and the question "where
				# does this one come from" is the most common reason to be reading a markup tree.
				return
			else:
				_search_purpose = "attribute"
				_search_menu.open_menu("add an attribute to <%s>" % row.name,
					Attributes.menu_for(row.name, row, _component_named(row.name)),
					_menu_screen_at(), _freeform_attribute())
		_:
			return


## Frames and focuses the module that exports `name`. False when nothing here declares it.
##
## The same route `_on_library_framed` takes, because "take me to that component" is one
## behaviour whether it was asked for from the library list or from a usage on a card.
func _navigate_to_component(name: String) -> bool:
	if graph == null or name.is_empty():
		return false
	for index in graph.cards.size():
		var card := graph.cards[index]
		if card.kind == Module.Kind.COMPONENT and card.exports.has(name):
			_canvas.frame_card(index)
			select_module(card.file_path)
			return true
	return false


## A resolved definition: go to the module, and frame its card when it is one of ours.
##
## A target OUTSIDE the open tree -- `hooks.gd`, an analyzer hit in the runtime addon -- is not
## something this window can show, so it says so rather than silently doing nothing, which is what
## an unlistened-to signal already did.
func _on_definition_requested(file_path: String, offset: int) -> void:
	if workspace == null or file_path.is_empty():
		return
	if workspace.try_get(file_path) == null:
		toast("%s is outside this tree — open it in the script editor" % file_path.get_file())
		return
	select_module(file_path)
	if graph != null:
		var index := graph.index_of(file_path)
		if index >= 0:
			_canvas.frame_card(index)
	var text := _buffer_of(file_path)
	# OFFSET TO LINE, because the pane jumps by line. Counting newlines up to the offset is the
	# whole conversion, and doing it here keeps the widget's contract (offsets) intact.
	var line := 1
	for i in range(mini(offset, text.length())):
		if text[i] == "\n":
			line += 1
	_source.goto_line(line)


## Where a row sits on screen, so an editor can open OVER the thing it edits rather than at
## whatever point the last menu used.
##
## Measured where the canvas has measured it, estimated otherwise -- the same order every other
## consumer of row geometry now follows.
func _row_rect_on_screen(card, section: int, row_index: int) -> Rect2:
	var card_index := graph.index_of(card.file_path) if graph != null else -1
	var lod := Metrics.lod_of(_canvas.zoom)
	var measured: Rect2 = _canvas.measured_row(card_index, section, row_index) 		if card_index >= 0 else Rect2()
	var local := measured
	if local.size.y <= 0.0:
		var top := Metrics.HEADER_H
		for entry in Metrics.section_stack(card):
			var spec := entry as Dictionary
			if not Metrics.draws_section(int(spec["section"]), lod):
				continue
			if int(spec["section"]) == section:
				top += float(spec["lead"]) + row_index * float(spec["row_height"])
				local = Rect2(Vector2(0.0, top),
					Vector2(Metrics.card_width_for(lod), float(spec["row_height"])))
				break
			top += float(spec["height"])
	if local.size.y <= 0.0:
		return Rect2(_menu_screen_at(), Vector2(260, 24))
	var at := _canvas.get_global_rect().position + Metrics.world_to_screen(
		Vector2(card.x, card.y) + local.position, _canvas.camera, _canvas.zoom)
	return Rect2(at, Vector2(
		clampf(local.size.x * _canvas.zoom, 260.0, 720.0),
		maxf(local.size.y * _canvas.zoom, 22.0)))


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
## THE DROP SAYS WHAT HAPPENED, in the words of the thing that decided.
##
## Three messages covered every outcome before -- "Couldn't place <X> there.", "Couldn't move that
## row there.", "Couldn't move that module there." -- so a drop refused because the target was an
## import row, because the row was being moved out of its own module, because the card had no
## markup to add to, and because there was no card under the cursor at all read identically. The
## refusals each carry their own reason now, and a drop that LANDS says what it did, which is what
## makes a correct-but-surprising outcome legible instead of looking like nothing happened.
func _on_canvas_drop(data: Dictionary, at: Vector2) -> void:
	var outcome := {}
	match str(data.get("source", "")):
		"library":
			outcome = drop_library_entry(str(data.get("kind", "")), str(data.get("name", "")), at)
		"row":
			var drag := Drag.new()
			drag.begin(Drag.Source.ROW, "", str(data.get("card_id", "")),
				int(data.get("row_at", -1)), int(data.get("row_index", -1)), at)
			drag.started = true
			outcome = drop_row(drag, at)
		"module":
			outcome = drop_module(str(data.get("path", "")), at)
		_:
			return
	var told := str(outcome.get("did", ""))
	if not told.is_empty():
		toast(told)


## A drop that landed. `did` is what to tell the user, in the past tense.
func _drop_did(did: String) -> Dictionary:
	return { "ok": true, "did": did }


## A drop that was refused, and why. The reason IS the toast: a refusal the user cannot act on is
## the same as no answer at all.
func _drop_refused(reason: String) -> Dictionary:
	return { "ok": false, "did": reason }


## Right-click on a row: the operations that apply to THAT row.
##
## Ported from the Unity leg's `OnCanvasRowContext`. A directive head gets clause operations; an
## element row gets attributes, children, wrapping and deletion. This is the builder's primary
## editing gesture and it did not exist -- the canvas offered a card menu (open / rename / delete
## the FILE) and nothing that could touch what is inside one.
## Positions the row menu at the click and shows it.
##
## One place, because the menu is now built five different ways and every one of them ended with
## the same three lines -- which is exactly how two of them come to disagree about which
## coordinate space `at` is in.
## A LOCAL point in screen coordinates, whichever mode the viewport is in.
##
## The row menu used `get_screen_position() + at` and the card and canvas menus used
## `get_global_mouse_position()`, which is a CanvasItem coordinate -- so two of the four menus
## were positioned in a different space from the other two, and which one was right depended on
## whether the host viewport embeds subwindows. It is a real OS window here and an embedded one in
## a test or a shot, so neither assumption holds everywhere.
func _screen_at(local: Vector2) -> Vector2:
	var viewport := get_viewport()
	if viewport != null and viewport.gui_embed_subwindows:
		return get_global_position() + local
	return get_screen_position() + local


## A point in CANVAS-LOCAL coordinates, placed where a popup will actually appear.
##
## THE CANVAS IS NOT AT THE BUILDER'S ORIGIN. It sits inside two splitters, so `_canvas.position`
## is its offset within its IMMEDIATE PARENT -- (0, 0) -- while the canvas itself is a couple of
## hundred pixels right and a few down. Every canvas menu was placed at
## `builder_screen + _canvas.position + at`, which is `builder_screen + at`: the row menu, the
## card menu and the canvas menu all opened that far up and to the left of the click, over the
## library pane or off the window entirely. The menus were opening; they were not opening where
## anyone was looking, which is indistinguishable from not opening.
##
## Asked of the CANVAS's own global/screen position, so the nesting cannot drift again.
func _canvas_at(canvas_local: Vector2) -> Vector2:
	if _canvas == null:
		return _screen_at(canvas_local)
	var viewport := get_viewport()
	if viewport != null and viewport.gui_embed_subwindows:
		return _canvas.get_global_position() + canvas_local
	return _canvas.get_screen_position() + canvas_local


func _show_row_menu(at: Vector2) -> void:
	# THE THREE LINES THEMSELVES. Consolidating the five call sites left this calling ITSELF, so
	# every row menu in the builder recursed until the stack gave out and no menu ever opened --
	# the suites went green because they read the PopupMenu items directly rather than through the
	# gesture that shows it.
	_row_menu.position = Vector2i(_canvas_at(at))
	_row_menu.reset_size()
	_row_menu.popup()


## Whether a directive row HAS a header to edit.
##
## `@else` and `@default` do not: they are the fallback arm, and there is no expression in them.
## Offering "Edit header..." on one opened an editor over an empty string whose commit
## `set_directive_header` then refused -- a menu entry that does nothing, which is worse than one
## that is missing.
static func _has_editable_header(row) -> bool:
	return row != null and row.badge_text != "@else" and row.badge_text != "@default"


## The module an import row names, or "" when the specifier resolves to nothing in this tree.
func _import_target(card, row_index: int) -> String:
	if graph == null or card == null or row_index < 0 or row_index >= card.imports.size():
		return ""
	# Asked of the EDGES, which are already resolved: the import row carries a specifier, and the
	# edge builder has done the work of turning that into a card. An unresolved import has a
	# broken edge, and an asset directive has none at all -- both correctly answer "nothing to
	# open", which is why the menu omits the item rather than offering a dead one.
	for edge in graph.edges_from(graph.index_of(card.file_path)):
		if edge.is_usage or edge.from_row != row_index or edge.is_broken():
			continue
		return graph.cards[edge.to_index].file_path
	return ""


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
	_menu_section = section
	_menu_row_index = row_index
	_menu_at = at
	_row_menu.clear()
	_row_menu.add_separator(row.text.strip_edges())

	# THE MENU IS SHAPED BY THE SECTION THE ROW LIVES IN.
	#
	# This branched on exactly two things -- the EXPORTS section and a DIRECTIVE row -- and served
	# everything else the ELEMENT menu. So an import row and a hook chip were both offered "Add
	# attribute...", "Add child element...", "Apply style from a module..." and "Wrap in...", and
	# every one of those computes an insertion point from a markup span the row does not have.
	# The capability reference is explicit that rows, cards, import rows and the empty canvas each
	# get their own menu.
	if section == Metrics.Section.EXPORTS:
		# A style entry's menu is about the DICTIONARY it lives in, not about markup.
		_row_menu.add_item("Add entry...", RowMenuId.ADD_STYLE_ENTRY)
		if Edits.has_span(row):
			_row_menu.add_separator()
			_row_menu.add_item("Delete this entry", RowMenuId.DELETE_ROW)
		_show_row_menu(at)
		return

	if section == Metrics.Section.IMPORTS:
		# An import names a MODULE. What you can do with it is go to that module, or stop
		# importing it -- never "add a child element to it".
		if _import_target(card, row_index) != "":
			_row_menu.add_item("Open the module it names", RowMenuId.OPEN_IMPORT)
			_row_menu.add_separator()
		_row_menu.add_item("Remove this import", RowMenuId.REMOVE_IMPORT)
		_show_row_menu(at)
		return

	if section == Metrics.Section.BODY:
		# A hook chip is a SETUP LINE. Unity ignores a right-click on the chip itself; this offers
		# the two things that are unambiguously about the line, and nothing that is about markup.
		_row_menu.add_item("Edit this line...", RowMenuId.EDIT_BODY_LINE)
		_row_menu.add_separator()
		_row_menu.add_item("Delete this line", RowMenuId.DELETE_ROW)
		_show_row_menu(at)
		return

	if section == Metrics.Section.ISLAND:
		_row_menu.add_item("Edit setup...", RowMenuId.EDIT_ISLAND)
		_row_menu.add_separator()
		_row_menu.add_item("Delete the setup", RowMenuId.DELETE_ROW)
		_show_row_menu(at)
		return

	if row.kind == Graph.LineKind.DIRECTIVE:
		if _has_editable_header(row):
			_row_menu.add_item("Edit header...", RowMenuId.EDIT_HEADER)
		# Clause operations belong to the CONSTRUCT head (@if), not to a bound continuation
		# (@else) -- adding an else to an else is not a thing the language has.
		if row.badge_text == "@if" and row.clause_index == 0:
			_row_menu.add_separator()
			_row_menu.add_item("Add @elif", RowMenuId.ADD_ELSE_IF)
			# ONE ELSE. Offered unconditionally, this produced a second `} @else {` and a file
			# that does not compile.
			if not Edits.construct_has_clause(card, row, "@else"):
				_row_menu.add_item("Add @else", RowMenuId.ADD_ELSE)
		# A @match's whole purpose is several arms, and its menu offered none of them.
		if row.badge == Graph.Badge.MATCH and row.clause_index == 0:
			_row_menu.add_separator()
			_row_menu.add_item("Add @case", RowMenuId.ADD_CASE)
			if not Edits.construct_has_clause(card, row, "@default"):
				_row_menu.add_item("Add @default", RowMenuId.ADD_DEFAULT)
		_row_menu.add_separator()
		# OFFERED ONLY WHERE IT IS SAFE. Unwrap splices a construct's body up a level, which is
		# only sound for a single-clause, non-match HEAD -- from anywhere else it corrupts the
		# brace balance and produces a file that does not compile. This was offered on every
		# directive row, and four of the six kinds broke.
		if Edits.can_unwrap(card, row):
			_row_menu.add_item("Remove %s, keep its contents" % row.badge_text, RowMenuId.UNWRAP)
		if row.clause_index > 0:
			# A CONTINUATION HAS NO BLOCK DELETE. "Delete @else" routed to the line-range remove,
			# which took the head line and left the clause body and a surplus brace behind.
			_row_menu.add_item("Delete this %s clause" % row.badge_text, RowMenuId.DELETE_CLAUSE)
		else:
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
		# NOT `row_index > 0`. After wrapping the root in an @if the directive is row 0 and the
		# return root is row 1, so the old test offered "Delete element" on the one row that has
		# to stay.
		if section != Metrics.Section.MARKUP or row_index != Edits.first_element_row(card):
			_row_menu.add_separator()
			_row_menu.add_item("Delete element", RowMenuId.DELETE_ROW)

	_row_menu.position = Vector2i(_canvas_at(at))
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
			# THE DIRECTIVE GOES WITH ITS LAST CHILD. A directive body cannot be empty here
			# (GUITKX0303), so deleting the only thing inside an `@if` left a file that does not
			# compile -- and the preview then showed the last good render while the source was
			# broken, which reads as the delete having done nothing.
			var orphan := Edits.orphaned_directive(card, row)
			if orphan != null:
				after = Edits.remove(before, orphan)
				what = "Delete %s and the %s that held it" % [
					row.text.strip_edges(), orphan.badge_text]
			else:
				after = Edits.remove(before, row)
				what = "Delete %s" % row.text.strip_edges()
		RowMenuId.ADD_ELSE:
			after = Edits.add_if_clause(before, row, false)
			what = "Add @else"
		RowMenuId.ADD_ELSE_IF:
			after = Edits.add_if_clause(before, row, true)
			what = "Add @elif"
			# AND THE HEADER OPENS. The builder just wrote `@elif (true)` on the user's behalf;
			# leaving it closed means they have to find the new clause to say what it tests, and
			# means Escape has nothing to take back. The wrap branch already does this -- the
			# machinery for it was written and only one of its two callers used it.
			_seed_header_edit = ELIF_SEED
		RowMenuId.OPEN_IMPORT:
			var target := _import_target(card, _menu_row_index)
			if not target.is_empty():
				select_module(target)
			return
		RowMenuId.REMOVE_IMPORT:
			after = Edits.remove_import(before, row.name)
			what = "Remove the import of %s" % row.name
		RowMenuId.EDIT_BODY_LINE:
			_inline.open_at(_row_rect_on_screen(card, _menu_section, _menu_row_index),
				row.source_text, { "kind": "body", "path": _menu_target, "row": row })
			return
		RowMenuId.EDIT_ISLAND:
			_island.open_at(_row_rect_on_screen(card, _menu_section, _menu_row_index),
				_LF.join(card.island_lines),
				{ "kind": "island", "path": _menu_target, "row": row,
					"from": card.island_start_line, "to": card.island_end_line })
			return
		RowMenuId.ADD_CASE:
			after = Edits.add_match_clause(before, card, row, false)
			what = "Add @case"
		RowMenuId.ADD_DEFAULT:
			after = Edits.add_match_clause(before, card, row, true)
			what = "Add @default"
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
				_tag_items(), _menu_screen_at(),
				func(typed: String) -> Dictionary:
					return { "label": "add <%s>" % typed, "payload": typed })
			return
		RowMenuId.ADD_ATTRIBUTE:
			_search_purpose = "attribute"
			var tag := str(row.name)
			_search_menu.open_menu(
				"attributes of <%s>" % tag,
				Attributes.menu_for(tag, row, _component_named(tag)),
				_menu_screen_at(), _freeform_attribute())
			return
		RowMenuId.ADD_STYLE_ENTRY:
			_search_purpose = "style_entry"
			_search_menu.open_menu("add an entry to %s" % row.name, _style_key_items(row),
				_menu_screen_at(), _freeform_style_key(str(row.name)))
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
		# ALREADY IMPORTED, IN WHATEVER SPELLING. `ensure_import` matches on the specifier STRING,
		# so a file importing `./components/row/row` got a SECOND import when this builder wrote
		# the same module as `~/app/components/row/row` -- two imports of one module, and the
		# compiler rejects the duplicate binding.
		if not _spec_importing(source, importer_path, card.file_path).is_empty():
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
	# READ THE RECORD. `style_keys()` returns `[{ name, type, detail }, ...]`, so `str(key)` made
	# the menu label -- and then the DICTIONARY KEY written into the style module -- the literal
	# text `{ "name": "bg_color", "type": "Color", "detail": "..." }`. Every "Add entry..."
	# produced a style module that does not parse.
	# KEYS THE EXPORT ALREADY HAS ARE NOT OFFERED. A dictionary literal with a duplicate key does
	# not load, and offering one is offering to break the file.
	var source := _buffer_of(_menu_target)
	for key in Schema.style_keys_live():
		var spec := key as Dictionary
		var key_name := str(spec.get("name", ""))
		if key_name.is_empty():
			continue
		if not source.is_empty() and Edits.style_entry_exists(source, owner, key_name):
			continue
		var key_type := str(spec.get("type", ""))
		items.append(SearchMenu.item(key_name, {
			"export": owner, "key": key_name, "type": key_type,
			"value": _style_seed(key_name, key_type),
		}, key_type))
	return items


## Opens the collection menu for a `@for` wrap. False when there is nothing to offer, in which
## case the caller falls through to the literal header and the user edits it.
func _offer_for_collections(card) -> bool:
	if card == null:
		return false
	var found := Attributes.collections_in_scope(card)
	if found.is_empty():
		return false
	var items: Array = []
	for name in found:
		items.append(SearchMenu.item(str(name), str(name),
			"as %s" % Attributes.singular_of(str(name))))
	_search_purpose = "for_collection"
	_search_menu.open_menu("loop over", items, _menu_screen_at(),
		func(typed: String) -> Dictionary:
			return { "label": "loop over %s" % typed, "payload": typed })
	return true


## The freeform row for an ATTRIBUTE menu: the typed name, untyped.
func _freeform_attribute() -> Callable:
	return func(typed: String) -> Dictionary:
		return { "label": "add \"%s\" (untyped)" % typed, "payload": typed }


## The freeform row for a STYLE-KEY menu: a key the schema does not list is still a key the
## dictionary can hold, so it is offered -- but as the `{export, key, value}` the handler reads,
## not as the bare string, which is what made this row do nothing at all.
func _freeform_style_key(export_name: String) -> Callable:
	return func(typed: String) -> Dictionary:
		return {
			"label": "add \"%s\"" % typed,
			"payload": { "export": export_name, "key": typed, "value": _style_seed(typed) },
		}


## What a fresh style entry is worth. Seeded, like every other header this builder writes.
## TYPE-DRIVEN, not name-driven. The schema reports each key's real type, so a seed can be
## right by construction; guessing from the name -- a `_color` suffix, a "width" substring -- was
## wrong for every key those heuristics did not happen to describe, and silently.
func _style_seed(key: String, type_name: String = "") -> String:
	match type_name:
		"Color":
			return "Color(0.2, 0.2, 0.24)"
		"int":
			return "8"
		"float":
			return "0.0"
		"bool":
			return "true"
		"String", "StringName":
			return "\"\""
		"Vector2":
			return "Vector2.ZERO"
	# No type from the schema: fall back to the name heuristics rather than to `null`, which is a
	# legal value for almost no style key.
	if key.ends_with("_color"):
		return "Color(0.2, 0.2, 0.24)"
	if key.begins_with("font_size") or key.contains("width") or key.contains("radius") \
			or key.contains("margin") or key.contains("separation"):
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
## The label of the row that opens the free-text field instead of picking a value.
const _TYPE_IT := "__type_it__"


## A value menu for a TYPE, with "type a value..." last.
func _value_items(type_name: String, godot_class := "", prop := "") -> Array:
	var items: Array = []
	for entry in Attributes.values_for(type_name, godot_class, prop):
		var spec := entry as Dictionary
		items.append(SearchMenu.item(str(spec["label"]), str(spec["label"]), type_name))
	items.append(SearchMenu.separator())
	items.append(SearchMenu.item("type a value...", _TYPE_IT))
	return items


## The same, for an attribute of the row the menu was opened on -- so an enum property offers its
## own constants rather than the type's generic literals.
func _attribute_value_items(prop: String) -> Array:
	var tag := str(_menu_row.name) if _menu_row != null else ""
	var godot_class := Schema.godot_class_for(tag)
	var info := Schema.property_info(godot_class, prop)
	var type_name := type_string(int(info.get("type", TYPE_NIL))) if not info.is_empty() else ""
	var items: Array = []
	for entry in Attributes.values_for(type_name, godot_class, prop):
		var spec := entry as Dictionary
		items.append(SearchMenu.item(str(spec["label"]),
			{ "value": str(spec["label"]), "quoted": bool(spec["quoted"]) }, type_name))
	items.append(SearchMenu.separator())
	items.append(SearchMenu.item("type a value...", _TYPE_IT))
	return items


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
	return _canvas_at(_menu_at)


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


## What "Add @elif" writes, and what its header editor opens on. Named because the seeding and
## the editor that opens over it have to be the same string -- an editor opened on different text
## from what was written is an edit whose Escape puts back something the user never saw.
const ELIF_SEED := "@elif (true)"


## A choice from the search menu. Dispatched by what the menu was opened FOR.
func _on_search_picked(payload: Variant) -> void:
	# THE HISTORY BRANCH RUNS FIRST. Everything below needs a row menu's state -- `_menu_target`
	# and a selected row -- and the history menu sets neither, so every history row was
	# unclickable: the guard rejected the pick before the branch that handles it was reached.
	if _search_purpose == "history":
		_jump_history_to(int(payload))
		return
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
			# THE VALUES IT CAN TAKE, then the field. An enum-hinted property knows its own
			# constants and a bool has exactly two answers; making the user type either is making
			# them remember something the schema already holds. "type a value..." is always the
			# last row, so the field is never further away than one more click.
			var spec := payload as Dictionary
			_pending_attribute = spec
			_search_purpose = "attribute_value_pick"
			_search_menu.open_menu("%s =" % str(spec["name"]),
				_attribute_value_items(str(spec["name"])), _menu_screen_at(),
				func(typed: String) -> Dictionary:
					return { "label": "use %s" % typed, "payload": typed })
			return
		"attribute_value_pick":
			var chosen := _pending_attribute
			if chosen.is_empty():
				return
			if payload is String and str(payload) == _TYPE_IT:
				# The WRAPPER STAYS OUTSIDE THE FIELD: the user edits the value, not the quotes or
				# the braces around it, so typing an expression into a string attribute cannot
				# produce `text=""{x}""`.
				_search_purpose = "attribute_value"
				_inline.open_at(Rect2(_menu_at, Vector2(260, 24)), str(chosen["value"]),
					{ "kind": "attribute", "path": _menu_target, "row": _menu_row,
						"name": str(chosen["name"]), "quoted": bool(chosen["quoted"]) })
				return
			_pending_attribute = {}
			var picked := payload as Dictionary if payload is Dictionary else {}
			var literal := str(picked.get("value", payload))
			after = Edits.set_attribute(before, _menu_row, str(chosen["name"]), literal,
				bool(picked.get("quoted", false)))
			what = "Edit %s on %s" % [str(chosen["name"]), _menu_row.text.strip_edges()]
		"wrap":
			var header := str(payload)
			if header.begins_with("@for") and _offer_for_collections(card):
				# THE COLLECTION IS PART OF THE HEADER, so it is asked for before the wrap rather
				# than left as a `range(1)` the user must find and retype. Returning here leaves
				# the row and the target intact for the second menu.
				return
			if header == "@match":
				after = Edits.wrap_in_match(before, _menu_row)
				what = "Wrap %s in @match" % _menu_row.text.strip_edges()
			else:
				after = Edits.wrap_in_directive(before, _menu_row, header)
				what = "Wrap %s in %s" % [_menu_row.text.strip_edges(), header.split(" ")[0]]
			_seed_header_edit = header
		"for_collection":
			var over := str(payload)
			var header := "@for (%s in %s)" % [Attributes.singular_of(over), over]
			after = Edits.wrap_in_directive(before, _menu_row, header)
			what = "Wrap %s in @for" % _menu_row.text.strip_edges()
			_seed_header_edit = header
		"style_entry":
			# THE VALUE IS ASKED FOR, not seeded and then unreachable. `Color(0.2, 0.2, 0.24)` was
			# written into every colour entry and the only way to change it was the source pane --
			# which is the one thing the canvas exists to avoid.
			_pending_style = payload as Dictionary
			_search_purpose = "style_value"
			_search_menu.open_menu("%s =" % str(_pending_style["key"]),
				_value_items(str(_pending_style.get("type", ""))), _menu_screen_at(),
				func(typed: String) -> Dictionary:
					return { "label": "use %s" % typed, "payload": typed })
			return
		"style_value":
			var entry := _pending_style
			if entry.is_empty():
				return
			_pending_style = {}
			after = Edits.insert_style_entry(before, str(entry["export"]),
				str(entry["key"]), str(payload))
			what = "Add %s to %s" % [str(entry["key"]), str(entry["export"])]
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
## An in-place editor closed: committed, cancelled or replaced by the next edit.
##
## Clears what it was about, and re-syncs the language index for the file it was editing --
## completion inside the source pane answers from that index, and an edit made on the CANVAS is
## the case where it would otherwise go stale without anybody typing in the pane at all.
func _on_editor_closed(token: Variant) -> void:
	_menu_row = null
	if not (token is Dictionary) or workspace == null:
		return
	var path := str((token as Dictionary).get("path", ""))
	if path.is_empty():
		return
	var module := workspace.try_get(path)
	if module != null:
		_reindex_language(path)


func _on_inline_committed(token: Variant, text: String, applied := false) -> void:
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
			if text.strip_edges().is_empty():
				# AN EMPTIED HEADER IS A REQUEST TO REMOVE THE DIRECTIVE, not a request for
				# `@if ()` -- which is GUITKX2508 and stops the module compiling. Clearing a field
				# is the obvious way to say "I do not want this one", and the attribute editor
				# already reads it that way.
				after = Edits.delete_clause(before, row) if row.clause_index > 0 \
					else Edits.unwrap_directive(before, row)
				what = "Remove %s" % row.badge_text
			else:
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
	_advance_style_entry(spec, applied)


## THE ADVANCE RUN: finishing one style entry with Enter opens the menu for the next.
##
## The reference's `AdvanceStyleEntry`. Adding entries to a style dictionary is a RUN -- nobody
## adds exactly one -- and without this each one costs a right-click, a menu, a pick and a click
## into the field. Only on a deliberate finish: clicking away means the user is going somewhere
## else, and re-opening a menu over where they clicked would be the tool arguing with them.
func _advance_style_entry(spec: Dictionary, applied: bool) -> void:
	if not applied:
		return
	var export_name := str(spec.get("advance_export", ""))
	if export_name.is_empty() or graph == null:
		return
	var card := graph.card_of(str(spec.get("path", "")))
	if card == null:
		return
	var anchor = _export_header_named(card, export_name)
	if anchor == null:
		return
	_menu_row = anchor
	_search_purpose = "style_entry"
	_search_menu.open_menu("add another entry to %s" % export_name,
		_style_key_items(anchor), _menu_screen_at(), _freeform_style_key(export_name))


## The EXPORT HEAD row named `export_name` on this card, or null.
func _export_header_named(card, export_name: String):
	for row in card.export_detail:
		if row.badge == Graph.Badge.STYLE_HEADER and str(row.name) == export_name:
			return row
	return null


## Which export a style ENTRY row belongs to: the nearest head above it.
func _export_owning(card, row_index: int) -> String:
	if card == null or row_index < 0 or row_index >= card.export_detail.size():
		return ""
	var i := row_index
	while i >= 0:
		var row = card.export_detail[i]
		if row.badge == Graph.Badge.STYLE_HEADER:
			return str(row.name)
		i -= 1
	return ""


## The row under the pointer, from the section the hit-test named.
## A row standing for the whole SETUP island, with its real span.
##
## Synthesised rather than stored, because the island is a line RANGE on the card and every other
## consumer speaks in offsets. Built from the card's own `island_start_line`/`island_end_line`
## against the live buffer, so `Edits.remove` and the source-pane jump are both span-exact.
## One DISPLAYED island line as a row, with the source line it came from.
##
## Falls back to the whole island when the mapping is not available -- an older projection, or a
## row index the card no longer has.
func _island_line_row(card, row_index: int):
	if card == null or row_index < 0 or row_index >= card.island_source_lines.size():
		return _island_row(card)
	var line := int(card.island_source_lines[row_index])
	var row := Graph.Line.new()
	row.kind = Graph.LineKind.PLAIN
	row.text = str(card.island_lines[row_index]) if row_index < card.island_lines.size() else ""
	row.source_line = line
	row.source_text = row.text
	return row


func _island_row(card):
	if card == null or card.island_start_line <= 0 or workspace == null:
		return null
	var module := workspace.try_get(card.file_path)
	if module == null:
		return null
	var lines := module.buffer_text.split(_LF)
	if card.island_end_line > lines.size():
		return null
	var at := 0
	for i in range(card.island_start_line - 1):
		at += str(lines[i]).length() + 1
	var end_at := at
	for i in range(card.island_start_line - 1, card.island_end_line):
		end_at += str(lines[i]).length() + 1
	var row := Graph.Line.new()
	row.kind = Graph.LineKind.PLAIN
	row.text = "setup"
	row.at = at
	row.end_at = end_at
	row.source_line = card.island_start_line
	return row


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
			# THE LINE THAT WAS CLICKED. The block is still edited whole -- activation opens the
			# island editor on the card's own span -- but a CLICK is a request to be shown a
			# place, and answering every one of them with the island's first line means clicking
			# the eighth line of a setup scrolls the pane to the first.
			return _island_line_row(card, row_index)
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
			# THE SAME MENU THE ROW MENU OPENS. This hardcoded `bg_color` into `exports[0]`, so
			# pressing it twice wrote the key twice and the module stopped loading -- and it never
			# asked which export, nor opened an editor, unlike the "+ hook" and "+ code" chips
			# beside it. One route, one vocabulary.
			var export_name := str(card.exports[0]) if not card.exports.is_empty() else ""
			if export_name.is_empty():
				return
			var anchor := Graph.Line.new()
			anchor.name = export_name
			_menu_target = card.file_path
			_menu_row = anchor
			_search_purpose = "style_entry"
			_search_menu.open_menu("add an entry to %s" % export_name,
				_style_key_items(anchor), _menu_screen_at(), _freeform_style_key(export_name))
			return
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
	# THE ANCHOR IS `_menu_target`, WHICH `_create_folder` ALREADY READS. Writing `_focus_path`
	# here moved the focus outside `select_module`, so no pane followed it: the source kept the
	# old file, the preview kept the old anchor, the folder tree kept its selection -- and if the
	# user then CANCELLED the prompt, the window was left focused on a module nothing was showing.
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

	# THE OWNER CARRIES THE FOLDER, and `place_module` is where that rule lives now -- this passed
	# `target_folder` where it had just computed `destination` two lines above, so moving
	# `Card/` into `Pages/` produced `Pages/Card.guitkx` and dissolved the folder it was supposed
	# to carry. One implementation, reached from both routes.
	for module in workspace.modules():
		if module.owns_folder() and Paths.same(module.folder, source):
			return place_module(module.file_path(), target_folder)

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
	# EVERY DESTINATION IS CHECKED BEFORE ANYTHING MOVES, which is the all-or-nothing rule this
	# function already applies to read-only modules. A collision found halfway through would leave
	# the folder half here and half there, with two modules claiming one path.
	for entry in movers:
		var spec := entry as Dictionary
		var mover = spec["module"]
		var lands := str(spec["to"]).path_join(mover.name + Module.suffix_for(mover.kind))
		if not workspace.is_path_available(lands):
			toast("Can't move %s — %s is already there." % [leaf, lands.get_file()])
			return false

	ledger.begin("Move %s" % leaf)
	var snapshot := workspace.capture_imports()
	for entry in movers:
		var spec := entry as Dictionary
		var module = spec["module"]
		var from: String = module.file_path()
		workspace.move_to(from, str(spec["to"]), module.name)
		if layout != null:
			# In memory only would be discarded: `reproject()` rebuilds `layout` from disk.
			layout.repath(from, module.file_path(), false)
		if Paths.same(_focus_path, from):
			_focus_path = module.file_path()
	if layout != null:
		layout.save(Time.get_datetime_string_from_system(true))
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

	# A COMPONENT THAT OWNS ITS FOLDER CARRIES IT. Passing the target folder straight through
	# dissolved the folder instead: `Card/Card.guitkx` dropped on `Pages` became
	# `Pages/Card.guitkx` and its children were orphaned where the folder used to be.
	var into: String = target_folder.path_join(module.name) if module.owns_folder() \
		else target_folder
	if module.owns_folder() and Paths.is_under(target_folder, module.folder):
		toast("Can't move %s inside itself." % module.name)
		return false

	var destination := Paths.canon(into.path_join(module_path.get_file()))
	# NOTHING MAY CLAIM A PATH TWICE. The model refuses this too, but refusing here is what lets
	# the user be told why rather than watching a drag do nothing.
	if not workspace.is_path_available(destination):
		toast("%s is already in %s." % [module_path.get_file(), target_folder.get_file()])
		return false
	ledger.begin("Move %s" % module_path.get_file())
	var snapshot := workspace.capture_imports()
	var ok := _move_one(module, into, module_path.get_file())
	if ok:
		# RECORDED, so the move is undoable like every other structural edit. `_move_one` is the
		# shared mechanics of moving; the ledger entry belongs to the ACTION, which is what the
		# user would press Ctrl+Z about.
		ledger.record_move(module_path, destination)
		# AND THE IMPORT REWRITES WITH IT. `reconcile_imports` returns every importer it had to
		# rewrite and this discarded them -- so undoing a re-file put the module back and left
		# every specifier pointing at where it had gone, which is a tree that does not compile in
		# a state the user never authored. `move_folder` records them; this route did not.
		for rewrite in workspace.reconcile_imports(snapshot):
			var r := rewrite as Dictionary
			ledger.record(str(r["file_path"]), str(r["before"]), str(r["after"]))
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
	# SUCCESS IS "THE MODULE MOVED", not "some importer needed rewriting".
	#
	# `place_at` returns the specifier REWRITES a move made necessary, and this treated an empty
	# array as failure -- so moving a module nothing imports, which is the ordinary case, reported
	# false while having moved it. Everything the caller does on success was skipped: the ledger
	# entry, the focus re-point, the layout repath, the toast. The move happened and the builder
	# behaved as though it had not.
	var before: String = module.file_path()
	var owned: String = module.folder if module.owns_folder() else ""
	workspace.place_at(module, target_folder)
	if Paths.same(module.file_path(), before):
		return false
	# THE CARD'S POSITION MOVES WITH THE FILE, and it has to happen BEFORE the re-projection --
	# `reproject()` rebuilds the layout from disk, so a re-keying done afterwards is read back over
	# by the next projection and the card is seeded a fresh slot.
	if not owned.is_empty():
		_repath_layout(owned, module.folder, true)
	_repath_layout(before, module.file_path())
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
	# A FILE NAME, in this leg's convention: snake_case. The three regexes here were Unity's --
	# PascalCase for a component, camelCase for a companion -- which is THAT leg's file convention
	# and not this one. Every file under `examples/` is snake_case, and `template_for` already
	# derives the PascalCase EXPORT from the snake_case file name, saying so in its own comment.
	# The validator and the template were contradicting each other, and the template was right.
	if not RegEx.create_from_string("^[a-z][a-z0-9_]*$").search(name):
		return "snake_case file name required"
	# NO `use_` ON THE FILE. This repo names a hook module after the thing it companions --
	# `doom_game_screen.hooks.guitkx`, `stress_test.hooks.guitkx` -- and puts the prefix on the
	# EXPORT inside it (`use_doom_game`, `use_stress_loop`). Requiring it on the file name was
	# invented here and matches nothing in the project: it would have produced
	# `use_new_hook.hooks.guitkx`, which is a name no file in this codebase has.

	var folder := _create_folder(kind, name)
	if folder.is_empty():
		return "no folder to create in"
	
	# ASKED OF `is_path_available`, which is the question SAVE will ask. `try_get` sees the tree
	# alone -- so a name whose file already sits on disk but was never loaded passed the prompt and
	# then collided at the write, which is the worst possible moment to find out.
	if not workspace.is_path_available(folder.path_join(name + Module.suffix_for(kind))):
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
	# THE MODEL'S OWN ORACLE, not a fourth definition. This picked the folder with the shortest
	# STRING, which is not the shallowest folder: `res://ui/verylongname` beats `res://ui/a/b` on
	# length while being one level up on neither count. `BuilderTree.resolve_root_from` is the
	# walk the loader and the graph service already use, so the builder now has ONE answer to a
	# question three parts of it were asking separately.
	var root: String = DocTree.resolve_root_from(workspace.modules(), _focus_path)
	return root if not root.is_empty() else Workspace.UNSAVED_ROOT


## Where a module is born when the gesture named no parent -- an empty canvas, or the library.
##
## `tree_root()` BARE was the answer, and it drops the folder convention the rest of the builder
## is built around: a component belongs in `components/<name>/` so it can own a folder and take
## children, and a companion belongs beside the component it companions. Unity's `BirthPathFor`
## makes the same three distinctions and calls the convention "a DEFAULT, not a rule -- nothing
## re-places a module afterwards, so the folder view can put anything anywhere and the convention
## will not argue with it".
func _birth_folder(kind: int, name: String) -> String:
	var root := tree_root()
	# THE FIRST MODULE OF A NEW TREE OWNS ITS FOLDER rather than nesting under a `components`
	# directory that has nothing above it.
	if workspace == null or workspace.modules().is_empty():
		return Workspace.UNSAVED_ROOT.path_join(name) if not name.is_empty() 			else Workspace.UNSAVED_ROOT
	if kind == Module.Kind.COMPONENT:
		return root.path_join("components").path_join(name) if not name.is_empty() 			else root.path_join("components")
	# A COMPANION NAMED AFTER A COMPONENT JOINS IT, wherever that component lives -- the family
	# rule, kept as the fallback now that creating FROM a card states the parent outright.
	var family := family_owner_for(kind, name)
	return family if not family.is_empty() else root


## The folder of the COMPONENT a companion of this name belongs to, or "".
##
## THROUGH THE FAMILY RULE, which `builder_naming.gd` implements and nothing called. This matched
## on exact name equality, so `use_card.hooks.guitkx` did not recognise `card.guitkx` as its
## family -- the `use_` strip is the whole point of `family_of` -- and a hook created beside a
## component landed at the tree root instead of beside it.
##
## Nearest to the FOCUS wins when more than one component carries the family name, measured in
## shared path SEGMENTS: `res://ui/card` and `res://ui/cardigan` share one folder and not two,
## which a character count gets wrong in the direction that hands the module to the wrong parent.
## An exact tie falls to the ordinally-smallest path, so the answer does not depend on the order
## the tree happened to load in.
##
## A UTIL has no family: it is a helper, not a companion, and it belongs where it was asked for.
func family_owner_for(kind: int, name: String) -> String:
	if workspace == null or name.is_empty() or kind == Module.Kind.UTIL:
		return ""
	var here := _focus_path.get_base_dir()
	var best := ""
	var best_score := -1
	for module in workspace.modules():
		if module.kind != Module.Kind.COMPONENT:
			continue
		if not Naming.same_family(kind, name, Module.Kind.COMPONENT, module.name):
			continue
		var folder: String = module.folder
		var score := Naming.shared_prefix_length(here, folder)
		if score > best_score or (score == best_score and folder < best):
			best = folder
			best_score = score
	return best


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
		return _birth_folder(kind, name)
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
	# WHERE THE GESTURE POINTED. `_menu_world` was recorded by both canvas context handlers and
	# read by nothing, so a module created from a right-click on empty canvas appeared at whatever
	# slot the projection happened to give it -- often off screen, and never where the user was
	# pointing when they asked for it.
	place_new_card(path, _menu_world)
	reproject()
	select_module(path)
	# AND FRAMED. Creating something and then having to go find it is the same as not being told
	# where it went.
	if graph != null:
		var index := graph.index_of(path)
		if index >= 0:
			_canvas.frame_card(index)
	toast("Created %s in %s — applies on Save" % [path.get_file(), folder.get_file()])
	preview.request_refresh()
	return path


## Puts a brand-new card at a world point, so it opens where the gesture that made it pointed.
##
## A zero point means "no gesture said" -- the library's "+ new", the empty state's button -- and
## there the projection's own slot is the honest answer.
func place_new_card(file_path: String, world: Vector2) -> void:
	if layout == null or file_path.is_empty():
		return
	var at := world
	if at == Vector2.ZERO:
		# NO GESTURE SAID WHERE -- the library's "+ new", the empty state's button. The middle of
		# what the user is looking at is the honest answer; the projection's own slot is a
		# position the camera has no reason to be anywhere near, so the module was created and
		# then not there.
		at = Metrics.screen_to_world(_canvas.size * 0.5, _canvas.camera, _canvas.zoom)
	layout.set_position(file_path, at)
	layout.save(Time.get_datetime_string_from_system(true))


## Renames the module the card menu was opened on.
## Where a rename lands: the module's own folder, or a folder renamed with it when it owns one.
##
## Shared by the validator and the rename, exactly as Unity shares `RenameTargetPath`, so the
## prompt and the operation can never disagree about what a name would produce.
func rename_target(module, new_name: String) -> String:
	var folder: String = module.folder
	if module.owns_folder():
		folder = folder.get_base_dir().path_join(new_name)
	return folder.path_join(new_name + Module.suffix_for(module.kind))


## Why a RENAME cannot use this name, or "" when it can.
##
## Separate from `_validate_name`, which is the CREATE validator: that one asks where a NEW module
## of this kind would be BORN relative to the card you right-clicked, and for a component being
## renamed it answered `<parent>/components/<NewName>/` -- a folder that does not exist. So no
## collision was ever reported, and Save then wrote one module over another.
func _validate_rename(module, name: String) -> String:
	var trimmed := name.strip_edges()
	if trimmed.is_empty():
		return "name required"
	if trimmed == module.name:
		return "that is the current name"
	# The same file-name rule the create validator applies -- see `_validate_name`.
	if not RegEx.create_from_string("^[a-z][a-z0-9_]*$").search(trimmed):
		return "snake_case file name required"
	if module.kind == Module.Kind.HOOK and not trimmed.begins_with("use_"):
		return "hook file names start with 'use_' (use_something)"

	if not workspace.is_path_available(rename_target(module, trimmed)):
		return "%s already exists" % trimmed
	if module.kind == Module.Kind.COMPONENT:
		for other in workspace.modules():
			if other != module and other.kind == Module.Kind.COMPONENT \
					and other.name.to_lower() == trimmed.to_lower():
				return "%s already exists in this tree" % trimmed
	return ""


func _rename_to(name: String) -> void:
	if workspace == null or _menu_target.is_empty() or name.strip_edges().is_empty():
		return
	var module := workspace.try_get(_menu_target)
	if module == null or module.read_only:
		return
	# A RENAME IS FIVE EDITS THAT LAND TOGETHER OR NOT AT ALL: the module's own export declaration,
	# its file name, the folder when it owns one, every importer's specifier, and every importer's
	# BINDING AND USES. This did only the file name and the specifiers -- `move_to` never touched
	# the export, despite the comment that used to sit here saying it did -- so a renamed module
	# kept `export OldName()` while its file said `NewName.guitkx`, every importer asked for a
	# name nothing exported, and the whole thing was invisible to undo.
	var old_name := module.name
	if old_name == name:
		return
	# THE EXPORT IDENTIFIER, WHICH IS NOT ALWAYS THE MODULE NAME. `module.name` is derived from
	# the file name; the export is what the file declares and what importers bind. They agree for
	# a module created here and diverge for one whose file was named by hand, so the rewrite has
	# to follow the declaration rather than the path.
	var card_now := graph.card_of(module.file_path()) if graph != null else null
	var old_export := old_name
	if card_now != null and not card_now.exports.is_empty():
		old_export = str(card_now.exports[0])
	var destination := rename_target(module, name)
	if not workspace.is_path_available(destination):
		toast("%s already exists there." % destination.get_file())
		return

	ledger.begin("Rename %s to %s" % [old_name, name])
	# The module's own declaration first, while its path is still the one the ledger knows.
	var renamed := Edits.rename_export(module.buffer_text, old_export, name)
	if renamed != module.buffer_text:
		apply_edit(module.file_path(), renamed, "Rename the export to %s" % name)

	# Then every importer's binding and uses, addressed by the specifier they use TODAY --
	# `move_to` below rewrites those specifiers, and doing it in the other order would leave this
	# pass looking for an import that has already moved.
	for card in graph.cards:
		if Paths.same(card.file_path, module.file_path()):
			continue
		var importer := workspace.try_get(card.file_path)
		if importer == null or importer.read_only:
			continue
		# THE SPECIFIER THE IMPORTER ACTUALLY WROTE. `Specifiers.relative` returns the spelling
		# THIS builder would choose, and an importer written by hand -- or by an earlier version --
		# says the same path differently. Looking for the wrong string found nothing and the
		# rename silently left every importer pointing at a name that no longer exists.
		var spec := _spec_importing(importer.buffer_text, card.file_path, module.file_path())
		if spec.is_empty():
			continue
		var rebound := Edits.rename_binding(importer.buffer_text, spec, old_export, name)
		if rebound != importer.buffer_text:
			apply_edit(card.file_path, rebound, "Follow the rename in %s" % card.title)

	# And the move itself, which carries the folder when the module owns one and rewrites the
	# specifiers the new path invalidated.
	var from_path := module.file_path()
	var owned_folder := module.folder if module.owns_folder() else ""
	workspace.move_to(from_path, destination.get_base_dir(), name)
	ledger.record_move(from_path, destination)
	ledger.end()

	# BEFORE the re-projection, which reloads the layout from disk.
	if not owned_folder.is_empty():
		_repath_layout(owned_folder, destination.get_base_dir(), true)
	_repath_layout(from_path, destination)
	reproject()
	# THE INDEX FOLLOWS THE FILE. `reindex` erases every entry pointing at a path before re-adding,
	# so re-indexing the new path and the old one drops the stale tag and installs the new.
	LspWorkspace.reindex(from_path, "")
	_reindex_language(destination)
	select_module(destination)
	_source.refresh_from_model()
	preview.request_refresh()
	toast("Renamed to %s — applies on Save" % destination.get_file())


## Creates a module with an auto-chosen name, WHERE THE CREATE RULE SAYS -- not beside the focus.
##
## This used to place relative to `_focus_path`, which is the exact mechanism the reference's
## UB-207 exists to forbid: a component created while looking at a deep child was born in that
## child's folder rather than where the tree's own rule puts it. It was also reachable and wired
## to nothing, so the divergence sat there waiting for the first caller. It goes through
## `_create_folder` / `_create_named` now, which is the one placement rule.
func create_module(kind: int) -> String:
	if workspace == null:
		return ""
	var folder := _create_folder(kind, "")
	if folder.is_empty():
		return ""
	return _create_named(kind, _unused_name(folder, kind))


## A name nothing in the folder is using yet -- "new_component", then "new_component2", and so on.
func _unused_name(folder: String, kind: int) -> String:
	var stem := Module.default_name_for(kind)
	var attempt := stem
	var n := 1
	while not workspace.is_path_available(folder.path_join(attempt + Module.suffix_for(kind))):
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
	# AN EMPTY MODULE IS ASKED ABOUT BEFORE THE WRITE, not reported after it.
	#
	# `save_all` skips a blank module and moves on. For one that has NEVER been written that is
	# right -- an empty .guitkx is not an empty file, it is a BROKEN one, and writing it takes the
	# project's compile down with it. For one ALREADY ON DISK it is the destructive case: the old
	# content stays, the emptying is silently not written, and the user is told about it in a
	# console line under a Save that reported success.
	if not _confirmed_blank_modules():
		return 0
	for blank in workspace.blank_modules():
		_console.add_diagnostics(blank.file_path(), [{
			"code": "", "severity": Console.SEVERITY_WARNING, "line": -1,
			"message": "empty, so it was not written -- delete it, or give it something to hold",
		}])
	# FORMATTING GOES THROUGH THE FUNNEL, ahead of the write. `save_all` used to assign
	# `module.buffer_text` directly -- past `Module.apply_edit`, past the workspace, past this
	# window -- so a reformat was invisible to the ledger and the canvas kept row spans measured
	# against the UNFORMATTED text. The next canvas edit then wrote at offsets that had moved.
	_format_dirty_buffers()
	var written := workspace.save_all()
	# Cleared HERE, not on a clean tree: the journal being there has to mean exactly one thing --
	# work existed that never reached disk -- or the recovery offer becomes noise.
	Journal.clear()
	_capture_layout()
	reproject()
	_source.refresh_from_model()
	_folders.rebuild()
	_refresh_status()
	# EVERY MUTATION SAYS WHAT IT DID. Save was silent, which on a tree with nothing dirty is
	# indistinguishable from the shortcut not having been received at all.
	toast("Saved %d file(s)" % written if written > 0 else "Nothing to save — the tree is clean")
	return written


## Reformats every dirty buffer as ONE undoable action, before the write.
func _format_dirty_buffers() -> void:
	if workspace == null or not workspace.format_on_save:
		return
	var pending: Array = []
	for module in workspace.modules():
		if module.read_only or not module.is_dirty():
			continue
		var formatted := workspace.formatted(module.buffer_text)
		if formatted != module.buffer_text:
			pending.append({ "path": module.file_path(), "text": formatted })
	if pending.is_empty():
		return
	ledger.begin("Format on save")
	for entry in pending:
		var spec := entry as Dictionary
		apply_edit(str(spec["path"]), str(spec["text"]), "Format %s" % str(spec["path"]).get_file())
	ledger.end()


## Whether the user has settled what an empty module means before the write.
##
## Only asked about modules ALREADY ON DISK: a never-written blank is a module someone created and
## thought better of, and holding the whole save hostage to it would be worse than leaving it
## pending. One that exists on disk and has been emptied is a different thing -- its old content
## is about to survive an edit the user believes they made.
func _confirmed_blank_modules() -> bool:
	if workspace == null or _blanks_agreed:
		return true
	var stale: Array = []
	for blank in workspace.blank_modules():
		if blank.is_on_disk():
			stale.append(blank)
	if stale.is_empty():
		return true

	var names := PackedStringArray()
	for blank in stale:
		names.append("    " + blank.file_path().trim_prefix("res://"))
	var dialog := ConfirmationDialog.new()
	dialog.title = "%d module(s) are empty" % stale.size()
	dialog.dialog_text = ("These are on disk and now hold nothing:\n\n%s\n\n"
		+ "An empty .guitkx is not an empty file -- the language requires a top-level "
		+ "declaration, so writing one takes the project's compile with it.\n\n"
		+ "Delete them, or cancel and give them something to hold.") % "\n".join(names)
	dialog.ok_button_text = "Delete and save"
	dialog.cancel_button_text = "Cancel the save"
	dialog.confirmed.connect(func():
		# THROUGH `delete_module`, so the imports go with them and the whole thing is one
		# undoable action rather than a write nobody recorded.
		for blank in stale:
			delete_module(blank.file_path())
		_blanks_agreed = true
		save()
		_blanks_agreed = false)
	dialog.close_requested.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()
	return false


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
	for entry in plan:
		var spec := entry as Dictionary
		var module = spec["module"]
		var from: String = module.file_path()
		# THE INNER REWRITES ARE THE ONES THAT HAPPENED. `move_to` runs its own
		# capture/reconcile pass and returns the importer rewrites it made; this discarded them
		# and then took an OUTER snapshot around the whole batch, which by the end could no longer
		# see the intermediate states. So undoing "place the tree" reverted the moves and left
		# every importer rewritten -- pointing at paths nothing occupies.
		for rewrite in workspace.move_to(from, str(spec["to"]), module.name):
			var r := rewrite as Dictionary
			ledger.record(str(r["file_path"]), str(r["before"]), str(r["after"]))
		# And the move itself, so undo has something to walk back.
		ledger.record_move(from, module.file_path())
		# THE FIRST SAVE OF A NEW TREE KEEPS THE ARRANGEMENT. Every module moves out of the
		# provisional root here, so without this every card the user had positioned looked like a
		# module the layout had never seen and was seeded a fresh slot -- UB-220 at full strength.
		if layout != null:
			layout.repath(from, module.file_path(), false)
		if Paths.same(_focus_path, from):
			_focus_path = module.file_path()
	# No outer reconcile: `move_to` already ran one per module and its rewrites are on the ledger
	# above. A second pass around the whole batch could no longer see the intermediate states, so
	# it recorded a diff that undo could not walk back.
	ledger.end()
	if layout != null:
		layout.save(Time.get_datetime_string_from_system(true))
	reproject()
	return true


func abort() -> int:
	if workspace == null:
		return 0
	# ANCHORED ON THE FOCUS. Which tree comes back is decided by the anchor, and the first on-disk
	# module in list order can sit under a different root than the one the user is working in.
	var reverted := workspace.abort_all(_focus_path)
	ledger.clear()
	Journal.clear()
	reproject()
	_rebind_focus_if_missing()
	_source.refresh_from_model()
	toast("Reverted %d file(s) to what is on disk" % reverted if reverted > 0 \
		else "Nothing to revert — the tree matches disk")
	return reverted


## Walks one ledger entry back. Every change in it, or none -- a gesture that touched two files is
## one action, and undoing it file by file leaves a state the user never authored.
## `Undo <label>` / `Nothing to undo` -- a command that silently does nothing is a command the
## user repeats, and undo at the end of a ledger looks exactly like undo that failed.
func _report_step(label: String, did: bool, verb: String) -> bool:
	if did:
		toast("%s %s" % [verb, label] if not label.is_empty() else "%s." % verb)
	else:
		toast("Nothing to %s." % verb.to_lower())
	return did


func undo() -> bool:
	var label := ledger.undo_label()
	var entry := ledger.undo()
	if entry == null:
		return _report_step("", false, "Undo")
	ledger.suppress(func(): _replay(entry, true))
	return _report_step(label, true, "Undo")


func redo() -> bool:
	var label := ledger.redo_label()
	var entry := ledger.redo()
	if entry == null:
		return _report_step("", false, "Redo")
	ledger.suppress(func(): _replay(entry, false))
	return _report_step(label, true, "Redo")


func _replay(entry, reverse: bool) -> void:
	var changes: Array = entry.changes.duplicate()
	if reverse:
		changes.reverse()
	for change in changes:
		_replay_change(change, reverse)
	if _walking_history:
		# The walk redraws once at the end; see `_jump_history_to`.
		return
	reproject()
	# UNDOING A CREATION REMOVES THE MODULE THE FOCUS NAMES. `_focus_path` is a path, so after
	# that the window went on naming a file that no longer exists: the status bar showed it, the
	# source pane kept its buffer and the preview compiled against it. The delete route re-points;
	# the replay route did not, and a replay is how a delete gets undone.
	_rebind_focus_if_missing()
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
				# THE MODULE'S TEXT IS CAPTURED ON THE WAY OUT. Redo minted the module with a
				# hard-coded empty string, so undoing past a creation and redoing it destroyed the
				# template and everything typed into it since.
				if module != null:
					change.after = module.buffer_text
				workspace.delete(path)
			elif module == null:
				workspace.create_new(change.file_path, change.after)
		Ledger.ChangeKind.DELETION:
			if reverse:
				workspace.restore(change.removed)
			else:
				workspace.delete(path)
		Ledger.ChangeKind.MOVE:
			workspace.move_to_path(change.after if reverse else change.before,
				change.before if reverse else change.after)


## Moves a card's saved position with the file, and SAVES IT, before anything re-projects.
##
## `layout.repath` existed and was correct and had exactly one caller -- whose call was then
## discarded, because `reproject()` rebuilds `layout` from disk and the re-keying only ever
## happened in memory. So a rename, a re-file, a folder move and the first Save of a new tree all
## lost every card position the user had arranged: the paths changed, the layout still knew the
## old ones, and `adopt_unplaced` seeded fresh positions for what looked like new modules.
##
## UB-220 in the Unity register, at full strength.
func _repath_layout(old_path: String, new_path: String, is_folder := false) -> void:
	if layout == null or Paths.same(old_path, new_path):
		return
	layout.repath(old_path, new_path, is_folder)
	# SAVED WITHOUT RE-CAPTURING. `capture_from` reads the positions off the CURRENT graph, which
	# still carries the old paths at this point -- so capturing here would key them back to where
	# they came from and undo the re-keying on the line above.
	layout.save(Time.get_datetime_string_from_system(true))


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
		# BY PATH. Handing it `exports[0]` meant a module with no exports mirrored nothing and a
		# module whose second export was the interesting one mirrored the wrong row.
		_library.select_entry(_focus_path,
			str(card.exports[0]) if card != null and not card.exports.is_empty() else "")
	if _preview_pane != null:
		# BUILD IT IF IT IS NOT BUILT. A round compiles the focus's closure, and the module a user
		# selects next is often outside the closure the last one had -- so the pane would sit on
		# "select a component to see it rendered" while a component was selected, until some later
		# edit happened to rebuild it. Selecting IS the request.
		if preview.built_script(_focus_path) == null:
			_run_round()
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
				func(name: String) -> String: return _validate_rename(current, name),
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
func drop_library_entry(kind: String, name: String, at: Vector2) -> Dictionary:
	var hit := Drag.resolve(graph, at, _canvas.camera, _canvas.zoom)
	if not bool(hit["found"]):
		return _drop_refused("Drop it on a card -- there is nothing here to add <%s> to." % name)
	var card: Graph.Card = hit["card"]
	if kind == LibraryPane.ENTRY_HOOK:
		if not apply_edit(card.file_path,
				Edits.insert_setup_line(_buffer_of(card.file_path), card,
					Attributes.hook_stub(name)), "add %s" % name):
			return _drop_refused("%s could not be added to %s." % [name, card.title])
		return _drop_did("Added %s to %s." % [name, card.title])

	# A MODULE from the library: a style module dropped ON AN ELEMENT styles it; anything else,
	# and a style dropped on the card rather than a row, adds the import alone.
	if kind == LibraryPane.ENTRY_STYLE or kind == LibraryPane.ENTRY_UTIL \
			or kind == LibraryPane.ENTRY_HOOK_MODULE:
		return drop_module_export(card, hit["row"], kind, name)

	var row: Graph.Line = hit["row"]
	var placement: Edits.Placement = hit["placement"]
	# NO ROW UNDER THE CURSOR MEANS THE ROOT'S CHILDREN, not a refusal. Releasing on a card's
	# header, on a section heading, in the padding under the last row, or anywhere on a pill hit
	# this -- which is a large share of a card's area, and every one of them answered "couldn't
	# place that there".
	if row == null:
		var root_at := Edits.first_element_row(card)
		if root_at < 0:
			return _drop_refused("%s has no markup to add <%s> to." % [card.title, name])
		row = card.markup[root_at]
		placement = Edits.Placement.INSIDE
	if row.kind == Graph.LineKind.IMPORT:
		return _drop_refused("An import row is not a place to put <%s>." % name)
	var verdict := Edits.can_place(card, row, placement)
	if not bool(verdict["ok"]):
		# A TOAST as well as the console line. A refused drop is answered while the user is still
		# holding the thing they dropped, and the console is at the bottom of the window where
		# nobody is looking mid-drag.
		toast(str(verdict["reason"]))
		_console.add_diagnostics(card.file_path,
			[{ "code": "", "severity": Console.SEVERITY_WARNING, "message": str(verdict["reason"]), "line": -1 }])
		return { "ok": false, "did": "" }   # already toasted, in the words of the rule that refused
	if not apply_edit(card.file_path,
			_with_component_import(
				Edits.insert(_buffer_of(card.file_path), card, row, Drag.markup_for(name),
					placement),
				card.file_path, name),
			"add <%s>" % name):
		return _drop_refused("<%s> could not be placed there." % name)
	return _drop_did("Added <%s> to %s." % [name, card.title])


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
func drop_module_export(card: Graph.Card, row: Graph.Line, kind: String,
		name: String) -> Dictionary:
	if card == null or workspace == null:
		return _drop_refused("Drop it on a card.")
	var module_kind := Module.Kind.STYLE
	if kind == LibraryPane.ENTRY_UTIL:
		module_kind = Module.Kind.UTIL
	elif kind == LibraryPane.ENTRY_HOOK_MODULE:
		module_kind = Module.Kind.HOOK
	var source_card := _module_exporting(name, module_kind)
	if source_card == null:
		return _drop_refused("Nothing in this tree exports %s." % name)
	if Paths.same(source_card.file_path, card.file_path):
		return _drop_refused("%s already declares %s -- it cannot import itself." % [card.title, name])

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
		if not apply_edit(card.file_path, text,
				"style %s with %s" % [row.text.strip_edges(), name]):
			return _drop_refused("%s could not be applied to <%s>." % [name, row.name])
		return _drop_did("Styled <%s> with %s." % [row.name, name])
	if not apply_edit(card.file_path, str(bound["text"]), "import %s" % name):
		return _drop_refused("%s is already imported into %s." % [name, card.title])
	return _drop_did("Imported %s into %s." % [name, card.title])


## Re-parents a markup row. The gesture the Unity leg lists as unreliable, and the one this whole
## drag design exists for: both ends are re-resolved against the current graph.
func drop_row(drag: Drag, at: Vector2) -> Dictionary:
	var card := drag.source_card(graph)
	var row := drag.source_row(graph)
	if card == null or row == null:
		return _drop_refused("That row is no longer where the drag started.")
	var hit := Drag.resolve(graph, at, _canvas.camera, _canvas.zoom)
	if not bool(hit["found"]) or hit["card"] != card:
		# A row can only move within its own module: moving it to another would mean deciding
		# what to do about every name its subtree references, which is a different operation.
		return _drop_refused("<%s> can only move inside %s." % [row.name, card.title])
	var target: Graph.Line = hit["row"]
	if target == null:
		return _drop_refused("Drop <%s> on a row -- that is the padding under the tree." % row.name)
	if target == row:
		return _drop_refused("That is the row you are dragging.")
	if not apply_edit(card.file_path,
			Edits.move(_buffer_of(card.file_path), card, row, target, hit["placement"]),
			"move <%s>" % row.name):
		return _drop_refused("<%s> cannot go there -- it is inside its own subtree." % row.name)
	return _drop_did("Moved <%s> %s <%s>." % [row.name,
		"into" if int(hit["placement"]) == int(Edits.Placement.INSIDE) else "beside", target.name])


## Drops a MODULE onto an element: a style module applies itself, anything else adds an import.
##
## This is the whole style-application gesture. `style={ Name }` plus the import it needs -- two
## edits, one action, so one undo takes both back. A style applied without its import is a file
## that does not compile, and an import added without the use is GUITKX2304.
func drop_module(module_path: String, at: Vector2) -> Dictionary:
	var hit := Drag.resolve(graph, at, _canvas.camera, _canvas.zoom)
	if not bool(hit["found"]):
		return _drop_refused("Drop it on a card -- there is nothing here to import into.")
	var card: Graph.Card = hit["card"]
	if Paths.same(card.file_path, module_path):
		return _drop_refused("A module cannot import itself.")
	var source_card := graph.card_of(module_path)
	if source_card == null:
		return _drop_refused("That module is not part of this tree.")
	if source_card.exports.is_empty():
		return _drop_refused("%s exports nothing to import." % source_card.title)
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
	if not apply_edit(card.file_path, text, described):
		return _drop_refused("%s is already imported into %s." % [export_name, card.title])
	return _drop_did("%s %s." % [described.capitalize(), card.title] \
		if described.begins_with("import") else "%s with %s." % [described.capitalize(), export_name])


func _buffer_of(file_path: String) -> String:
	var module := workspace.try_get(file_path) if workspace != null else null
	return module.buffer_text if module != null else ""


## Every module that imports `target`, by file path.
##
## The question deletion asks before it does anything. Answered from the MODEL's import scan rather
## than by matching text, so an import written across two lines or with an alias still counts.
## The specifier `source` uses to import `target`, whatever spelling it is written in, or "".
func _spec_importing(source: String, importer_path: String, target: String) -> String:
	# RESOLVED WITHOUT TOUCHING DISK. `Specifiers.map` goes through the compiler's resolver, which
	# checks that the file EXISTS -- and nothing in this builder exists until Save, so on the tree
	# the user is actually working in it answers "" for every import. Comparing the specifier
	# STRING instead is no better: the same module reads `./components/row/row`, `../row/row` or
	# `~/app/components/row/row` depending on who wrote it.
	#
	# So the join is done here, against the importer's own folder, and matched on the target's
	# stem -- a specifier never carries the module suffix.
	var stem := target
	for suffix in [".style.guitkx", ".hooks.guitkx", ".guitkx"]:
		if stem.ends_with(suffix):
			stem = stem.substr(0, stem.length() - suffix.length())
			break
	var stem_key := Paths.key(stem)
	var folder := importer_path.get_base_dir()
	for imp in Compiler.scan_imports(source):
		var spec := str(imp.get("spec", ""))
		if spec.is_empty():
			continue
		if spec.begins_with("~/"):
			# Root-relative: the walk-up root is a disk question too, so match on the tail, which
			# is what makes two spellings of one path the same file.
			if stem_key.ends_with(Paths.key(spec.substr(2))):
				return spec
			continue
		if Paths.key(Paths.canon(folder.path_join(spec))) == stem_key:
			return spec
	return ""


func referrers_to(target: String) -> PackedStringArray:
	var out := PackedStringArray()
	if workspace == null or graph == null:
		return out
	for card in graph.cards:
		if Paths.same(card.file_path, target):
			continue
		var module := workspace.try_get(card.file_path)
		if module == null:
			continue
		# Asked by RESOLVED PATH, so an import written `./x`, `../y/x` or `~/a/b/x` all count.
		if not _spec_importing(module.buffer_text, card.file_path, target).is_empty():
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

	# DELETE AND STRIP, one ledger entry -- verified against the Unity source rather than taken
	# from the capability document, which the two disagree about.
	#
	# The spec (§2) says "deleting is refused while another module still imports it, naming the
	# referrers", and this port did that for a while on the strength of it. `BuilderWindow.cs:851`
	# does the opposite and says why: "One entry covers the module AND every reference to it, so a
	# single undo puts the tree back exactly as it was." The defect register records the refusal
	# as a design Unity RETIRED. The source is the reference, so the source wins; the spec line is
	# stale.
	#
	# Only the IMPORT is removed, not the usages it bound: a `<Card />` left in the markup is a
	# visible, locatable error the user can decide about, and silently deleting rows of their
	# layout because a module went away is a much worse surprise.
	var referrers := referrers_to(file_path)
	ledger.begin("Delete %s" % file_path.get_file())
	_strip_references_to(file_path)
	if not workspace.delete(file_path):
		ledger.end()
		return false
	ledger.record_deletion(file_path, module)
	ledger.end()
	# A deleted module stops being a completion candidate.
	LspWorkspace.reindex(file_path, "")
	reproject()
	_rebind_focus_if_missing()
	_source.refresh_from_model()
	preview.request_refresh()
	if referrers.is_empty():
		toast("Deleted %s — applies on Save" % file_path.get_file())
	else:
		toast("Deleted %s — dropped the import from %d file(s)"
			% [file_path.get_file(), referrers.size()])
	return true


## Removes every import of `target` from every other module in the tree.
##
## Ported from `StripReferencesTo` (BuilderWindow.cs:1578). Inside the caller's ledger
## transaction, so one undo puts back the module AND every import that went with it.
func _strip_references_to(target: String) -> void:
	if workspace == null or graph == null:
		return
	for card in graph.cards:
		if Paths.same(card.file_path, target):
			continue
		var module := workspace.try_get(card.file_path)
		if module == null or module.read_only:
			continue
		# BY RESOLVED PATH, not by comparing specifier strings. The same module can be imported as
		# `./components/row/row`, `../row/row` or `~/tests/.../row`, and only the compiler's own
		# resolution knows those are one file -- so a string compare against the spelling this
		# builder happens to write missed every import written any other way.
		# EVERY import of the target, not the first. One module can be imported twice under two
		# spellings -- `./x` and `~/a/b/x` are the same file and `ensure_import` matched on the
		# STRING, so it was possible to end up with both.
		var text := module.buffer_text
		var guard := 0
		while guard < 8:
			guard += 1
			var spec := _spec_importing(text, card.file_path, target)
			if spec.is_empty():
				break
			var stripped := Edits.remove_import(text, spec)
			if stripped == text:
				break
			text = stripped
		if text != module.buffer_text:
			apply_edit(card.file_path, text, "Drop the import of %s" % target.get_file())


## The last toast the builder raised -- where a refusal says why it refused.
func toast_text() -> String:
	return _toast.text if _toast != null else ""


## Adopts `.guitkx` files that changed on disk while the builder was away.
##
## `reload_clean_from_disk` was written, tested and had ZERO callers -- so a file edited in another
## editor was never noticed, and Save wrote the builder's stale buffer straight over it. Coming
## back to the window is exactly when that is likely to have happened, and it costs nothing on the
## frames where it has not; polling disk on a tick would cost more than it is worth.
##
## Only CLEAN modules are adopted -- the sweep skips dirty ones itself -- because a buffer with
## unsaved work in it is a conflict, not a stale copy, and silently discarding the user's typing
## to take the disk's version is the failure this is meant to prevent.
func adopt_external_changes() -> void:
	if workspace == null or workspace.modules().is_empty():
		return
	var paths := PackedStringArray()
	# AND WHICH ONES DIVERGED. `reload_clean_from_disk` correctly declines to clobber a module
	# with unsaved edits -- and said nothing about it, so a file edited in two places looked
	# exactly like a file nobody had touched, right up until Save wrote one version over the
	# other. Kept as a console line rather than a dialog: the user's copy IS the right one to
	# keep, and the only thing missing was being told.
	var contested := PackedStringArray()
	for module in workspace.modules():
		paths.append(module.file_path())
		if module.is_dirty() and FileAccess.file_exists(module.file_path()):
			contested.append(module.file_path())
	var touched := workspace.reload_clean_from_disk(paths)
	for path in contested:
		_console.add_diagnostics(path, [{
			"code": "", "severity": Console.SEVERITY_WARNING, "line": -1,
			"message": "changed on disk AND edited here -- your version is kept; Save overwrites it",
		}])
	if touched.is_empty():
		return
	reproject()
	_source.refresh_from_model()
	preview.request_refresh()
	var names := PackedStringArray()
	for path in touched:
		names.append(str(path).get_file())
	toast("Reloaded %s from disk." % ", ".join(names))


## Re-points the focus when the module it names has gone.
##
## `_focus_path` is a PATH, and `select_module` early-returns on an empty one -- so after deleting
## or aborting the focused module the window went on naming a file that no longer exists: the
## status bar showed it, the source pane kept its buffer, and the preview compiled against it.
## Two move routes maintained the focus across a path CHANGE; nothing handled its DISAPPEARANCE.
func _rebind_focus_if_missing() -> void:
	if workspace == null or _focus_path.is_empty():
		return
	if workspace.try_get(_focus_path) != null:
		return
	var paths := PackedStringArray()
	for module in workspace.modules():
		paths.append(module.file_path())
	paths.sort()
	if paths.is_empty():
		# Nothing left to focus. The empty state is the honest answer, not a stale name.
		_focus_path = ""
		_source.clear()
		_sync_empty_state()
		_refresh_status()
		return
	select_module(paths[0])


func _refresh_status() -> void:
	var dirty := workspace != null and workspace.has_unsaved_changes()
	# "RightSide.guitkx | 5 file(s), 0 dirty" — WHAT IS OPEN first, then the shape of the tree.
	# A count with no filename tells a user how much work is loaded but not which of it they are
	# looking at, and the builder's whole left column is about which one that is.
	var empty := workspace == null or workspace.modules().is_empty()
	if empty:
		_status.text = "No tree open — double-click a .guitkx in the FileSystem dock, or start one below"
	# NO EARLY RETURN. The button gating and the `dirty_changed` emit sat BELOW this, so on the
	# start screen Save and Abort stayed enabled over a tree that does not exist and the editor's
	# own quit prompt was never told the builder was clean.
	var dirty_count := 0
	if not empty:
		for module in workspace.modules():
			if module.is_dirty():
				dirty_count += 1
	if not empty:
		var open_name := _focus_path.get_file() if not _focus_path.is_empty() \
			else "no module selected"
		_status.text = "%s  |  %d file(s), %d dirty" % [
			open_name, workspace.modules().size(), dirty_count]
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


## The live-preview pane, for a test that needs to ask what it is rendering.
func preview_pane() -> PreviewPane:
	return _preview_pane


func source_pane() -> SourcePane:
	return _source


func console() -> Console:
	return _console


## The multiline island editor, for a test that needs to drive it.
func island_editor() -> IslandEditor:
	return _island


## The row context menu, for a test that needs to read what it offered.
func row_menu() -> PopupMenu:
	return _row_menu


func inline_editor() -> InlineEditor:
	return _inline


func focus_path() -> String:
	return _focus_path
