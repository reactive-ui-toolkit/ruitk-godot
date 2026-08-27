@tool
class_name RuitkBuilderFolderPane
extends Tree
## The open tree, as a tree: every module grouped under the folder it lives in.
##
## This pane is the one place the builder shows the tree AS FILES, so it is also where the
## save-only contract is most visible -- a module that has never been written, one that has moved
## and one that is simply dirty all look different here, and all three are ordinary states that
## last until Save.
##
## Reads the MODEL, never the disk. The workspace is the inventory; the filesystem is a
## projection of it that is usually out of date on purpose.

const Module = preload("res://addons/reactive_ui_toolkit_editor/builder/document/builder_module.gd")
const Paths = preload("res://addons/reactive_ui_toolkit_editor/builder/document/builder_paths.gd")
const Workspace = preload("res://addons/reactive_ui_toolkit_editor/builder/document/builder_workspace.gd")

## A module row was chosen -- single click, so the canvas and the source pane follow the pane.
signal module_selected(file_path: String)
## A module row was double-clicked: focus its card on the canvas.
signal module_activated(file_path: String)
signal module_context_requested(file_path: String, at: Vector2)

const KIND_LABEL := {
	Module.Kind.COMPONENT: "component",
	Module.Kind.HOOK: "hook",
	Module.Kind.STYLE: "style",
	Module.Kind.UTIL: "util",
	Module.Kind.VALUE: "value",
	Module.Kind.MODULE: "module",
	Module.Kind.UNKNOWN: "",
}

var workspace: Workspace = null

## Path -> the row showing it, so a selection can be pushed in from elsewhere without a search.
var _rows := {}


func _init() -> void:
	columns = 2
	set_column_title(0, "Module")
	set_column_title(1, "State")
	set_column_expand(1, false)
	set_column_custom_minimum_width(1, 96)
	column_titles_visible = true
	hide_root = true
	allow_rmb_select = true
	select_mode = Tree.SELECT_ROW
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	item_selected.connect(_on_item_selected)
	item_activated.connect(_on_item_activated)
	item_mouse_selected.connect(_on_item_mouse_selected)


## Rebuilds from the workspace. Cheap enough to run on every model change: a tree of a few dozen
## modules is a few dozen rows, and a pane that only refreshes sometimes is a pane that is
## sometimes wrong.
func rebuild() -> void:
	var previously_selected := selected_path()
	clear()
	_rows.clear()
	if workspace == null:
		return

	var root_item := create_item()
	var folders := {}
	var ordered: Array[Module] = []
	for module in workspace.modules():
		ordered.append(module)
	ordered.sort_custom(func(a, b): return Paths.key(a.file_path()) < Paths.key(b.file_path()))

	for module in ordered:
		var folder := module.folder
		if not folders.has(folder):
			var group := create_item(root_item)
			group.set_text(0, _folder_label(folder))
			group.set_selectable(0, false)
			group.set_selectable(1, false)
			group.set_custom_color(0, Color(0.55, 0.58, 0.64))
			folders[folder] = group
		var row := create_item(folders[folder])
		row.set_text(0, module.file_path().get_file())
		row.set_text(1, _state_of(module))
		row.set_tooltip_text(0, "%s -- %s" % [module.file_path(), KIND_LABEL.get(module.kind, "")])
		row.set_metadata(0, module.file_path())
		if module.read_only:
			row.set_custom_color(0, Color(0.65, 0.65, 0.70))
		_rows[Paths.key(module.file_path())] = row

	if not previously_selected.is_empty():
		select_path(previously_selected)


## What is pending for a module, in the words the save prompt uses. Derived, every time -- the
## model has no flags to read and this pane must not invent any.
func _state_of(module: Module) -> String:
	if module.read_only:
		return "read-only"
	if not module.is_on_disk():
		return "new"
	if module.has_moved() and module.is_dirty():
		return "moved, edited"
	if module.has_moved():
		return "moved"
	if module.is_dirty():
		return "edited"
	return ""


func _folder_label(folder: String) -> String:
	if workspace == null:
		return folder
	return folder.trim_prefix("res://")


func selected_path() -> String:
	var item := get_selected()
	if item == null:
		return ""
	var meta: Variant = item.get_metadata(0)
	return str(meta) if meta != null else ""


## Moves the selection from outside -- the canvas selecting a card, say. Does not re-announce it:
## a pane that echoed every selection back would loop with whatever set it.
func select_path(file_path: String) -> void:
	var row: TreeItem = _rows.get(Paths.key(file_path))
	if row == null:
		deselect_all()
		return
	# Selecting the row that is ALREADY selected still emits `item_selected`, which the window
	# turns back into a request to select it -- and the two bounce forever. The guard belongs
	# here as well as in the window: this pane must be safe to point at whatever is already open.
	if row.is_selected(0):
		return
	row.select(0)
	scroll_to_item(row)


func _on_item_selected() -> void:
	var path := selected_path()
	if not path.is_empty():
		module_selected.emit(path)


func _on_item_activated() -> void:
	var path := selected_path()
	if not path.is_empty():
		module_activated.emit(path)


func _on_item_mouse_selected(at: Vector2, mouse_button_index: int) -> void:
	if mouse_button_index != MOUSE_BUTTON_RIGHT:
		return
	var path := selected_path()
	if not path.is_empty():
		module_context_requested.emit(path, at)
