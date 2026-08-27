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

## The tree changed in a way the host should know about -- for the plugin's title, or a prompt on
## close.
signal dirty_changed(has_unsaved: bool)

## Menu ids. Named rather than positional, so inserting an item cannot silently re-point another.
enum MenuId { SAVE, ABORT, UNDO, REDO, FIT_VIEW, REVEAL }
enum CardMenuId { OPEN, RENAME, DELETE, REVEAL_CARD }

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
var _canvas_menu: PopupMenu = null

var _focus_path := ""
var _menu_target := ""
var _menu_world := Vector2.ZERO
var _was_dirty := false


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_wire()


func _exit_tree() -> void:
	preview.teardown()


# ── Assembly ─────────────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(column)

	_toolbar = HBoxContainer.new()
	column.add_child(_toolbar)
	_toolbar.add_child(_tool_button("Save", MenuId.SAVE))
	_toolbar.add_child(_tool_button("Abort", MenuId.ABORT))
	_toolbar.add_child(VSeparator.new())
	_toolbar.add_child(_tool_button("Undo", MenuId.UNDO))
	_toolbar.add_child(_tool_button("Redo", MenuId.REDO))
	_toolbar.add_child(VSeparator.new())
	_toolbar.add_child(_tool_button("Fit", MenuId.FIT_VIEW))
	_status = Label.new()
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_toolbar.add_child(_status)

	var body := HSplitContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)

	var left := VSplitContainer.new()
	left.custom_minimum_size = Vector2(240, 0)
	body.add_child(left)
	_folders = FolderPane.new()
	left.add_child(_folders)
	_library = LibraryPane.new()
	left.add_child(_library)

	var middle := VSplitContainer.new()
	middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(middle)

	# The canvas and the one floating inline editor share a layer, so the editor can sit over a
	# card without the canvas clipping it away.
	var canvas_layer := Control.new()
	canvas_layer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas_layer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	middle.add_child(canvas_layer)
	_canvas = CanvasHost.new()
	canvas_layer.add_child(_canvas)
	_inline = InlineEditor.new()
	canvas_layer.add_child(_inline)

	_console = Console.new()
	middle.add_child(_console)

	_source = SourcePane.new()
	_source.custom_minimum_size = Vector2(360, 0)
	body.add_child(_source)

	_card_menu = PopupMenu.new()
	_card_menu.add_item("Open", CardMenuId.OPEN)
	_card_menu.add_item("Rename...", CardMenuId.RENAME)
	_card_menu.add_separator()
	_card_menu.add_item("Delete", CardMenuId.DELETE)
	add_child(_card_menu)

	_canvas_menu = PopupMenu.new()
	_canvas_menu.add_item("Fit to view", MenuId.FIT_VIEW)
	add_child(_canvas_menu)


func _tool_button(label: String, id: int) -> Button:
	var button := Button.new()
	button.text = label
	button.pressed.connect(func(): run_command(id))
	button.set_meta("command", id)
	return button


func _wire() -> void:
	_folders.module_selected.connect(select_module)
	_folders.module_activated.connect(func(path: String):
		select_module(path)
		_canvas.select_card(graph.index_of(path) if graph != null else -1))
	_folders.module_context_requested.connect(func(path: String, _at: Vector2):
		_open_card_menu(path, get_global_mouse_position()))

	_canvas.card_selected.connect(_on_card_selected)
	_canvas.camera_changed.connect(_on_camera_changed)
	_canvas.card_context_requested.connect(func(index: int, world: Vector2):
		if graph == null or index < 0 or index >= graph.cards.size():
			return
		_menu_world = world
		_open_card_menu(graph.cards[index].file_path, get_global_mouse_position()))
	_canvas.canvas_context_requested.connect(func(world: Vector2):
		_menu_world = world
		_canvas_menu.position = Vector2i(get_global_mouse_position())
		_canvas_menu.popup())

	_source.buffer_edited.connect(_on_buffer_edited)
	_console.location_activated.connect(select_module)
	_card_menu.id_pressed.connect(_on_card_menu)
	_canvas_menu.id_pressed.connect(run_command)
	ledger.changed.connect(_refresh_status)
	preview.compile_finished.connect(func(_p: String, _ok: bool, _e: String): _refresh_status())


# ── Opening ──────────────────────────────────────────────────────────────────────────

## Opens the tree the given module belongs to.
func open_tree(focus_path: String) -> void:
	if workspace == null:
		workspace = Workspace.new()
	# On open, not only on teardown: a crashed editor leaves a mirror behind, and compiling
	# against a shadow tree is worse than compiling against nothing.
	Preview.clear_scratch()
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
func reproject() -> void:
	if workspace == null:
		return
	graph = Service.project(workspace.modules(), _focus_path)
	layout = CanvasLayout.for_graph(graph)
	layout.apply_to(graph)
	layout.adopt_unplaced(graph)
	if layout.zoom > 0.0:
		_canvas.camera = layout.camera
		_canvas.zoom = layout.zoom
	_canvas.show_graph(graph)
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


func _on_buffer_edited(file_path: String, before: String, after: String) -> void:
	# The source pane has already written the buffer, so the funnel records rather than re-applies.
	ledger.record_typing(file_path, before, after)
	_after_model_change(file_path)


# ── Preview ──────────────────────────────────────────────────────────────────────────

## Runs a preview round if the debounce has settled. Called from the host's idle tick.
func tick() -> void:
	if not preview.is_due():
		return
	var summary = preview.compile_dirty(_focus_path)
	if summary != null:
		_console.report(summary)
	_refresh_status()


# ── Commands ─────────────────────────────────────────────────────────────────────────

func run_command(id: int) -> void:
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


func save() -> int:
	if workspace == null:
		return 0
	var written := workspace.save_all()
	Journal.clear()
	_capture_layout()
	_folders.rebuild()
	_refresh_status()
	return written


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
	preview.request_refresh()
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
	_card_menu.position = Vector2i(at)
	_card_menu.popup()


func _on_card_menu(id: int) -> void:
	match id:
		CardMenuId.OPEN:
			select_module(_menu_target)
		CardMenuId.DELETE:
			delete_module(_menu_target)
		CardMenuId.RENAME:
			# The rename prompt itself is a chrome affordance; the model operation it drives is
			# `move_to_path`, which is what the ledger replays.
			select_module(_menu_target)


## Deletes a module: it leaves the tree, and the ledger holds the module itself so undo puts the
## SAME one back -- its identity, its buffer and its disk path.
func delete_module(file_path: String) -> bool:
	if workspace == null:
		return false
	var module := workspace.try_get(file_path)
	if module == null or module.read_only:
		return false
	if not workspace.delete(file_path):
		return false
	ledger.record_deletion(file_path, module)
	reproject()
	_source.refresh_from_model()
	preview.request_refresh()
	return true


func _refresh_status() -> void:
	var dirty := workspace != null and workspace.has_unsaved_changes()
	var parts := PackedStringArray()
	if workspace != null:
		parts.append("%d module(s)" % workspace.modules().size())
	parts.append("unsaved" if dirty else "saved")
	if ledger.can_undo():
		parts.append("undo: " + ledger.undo_label())
	_status.text = "   ".join(parts)
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
