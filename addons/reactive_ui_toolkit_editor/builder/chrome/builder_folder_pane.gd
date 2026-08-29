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
const Palette = preload("res://addons/reactive_ui_toolkit_editor/builder/canvas/canvas_palette.gd")

## A module row was chosen -- single click, so the canvas and the source pane follow the pane.
signal module_selected(file_path: String)
## A module row was double-clicked: focus its card on the canvas.
signal module_activated(file_path: String)
signal module_context_requested(file_path: String, at: Vector2)

## Something was dropped onto a FOLDER row. `what` is "module" or "folder" and `path` is what was
## dragged; `into` is the folder it landed on.
##
## DRAGGING A FILE OR A FOLDER ONTO ANOTHER FOLDER RE-FILES IT, and the capability reference calls
## this "the only gesture that moves anything". The pane could START such a drag -- its own doc
## comment said "onto another folder row to move it" -- and had no way to RECEIVE one, so the
## sentence described a gesture that ended nowhere.
signal refile_requested(what: String, path: String, into: String)

## What each kind's row is marked with. Text, not editor icons: the pane is built headlessly in
## the suites, where `EditorInterface` has no theme to ask.
const KIND_GLYPH := {
	Module.Kind.COMPONENT: "◆",
	Module.Kind.HOOK: "⬡",
	Module.Kind.STYLE: "◐",
	Module.Kind.UTIL: "▪",
	Module.Kind.VALUE: "▫",
	Module.Kind.MODULE: "▪",
	Module.Kind.UNKNOWN: "•",
}

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
	set_column_title(0, "")
	set_column_title(1, "")
	# The NAME column takes what it needs and the state column takes what is left. Both columns
	# expanding split the pane in half, so every file name ellipsised at ten characters -- with a
	# third of the pane sitting empty beside it, and the two modules that differ only by their
	# companion suffix rendering identically.
	set_column_expand(0, true)
	set_column_clip_content(0, false)
	set_column_expand(1, false)
	set_column_custom_minimum_width(1, 72)
	# NO COLUMN TITLES. Rendered as two buttons over the tree they read as a TAB BAR -- "Folders"
	# and "State" looked like two views to switch between rather than one tree with a status
	# column, and the pane's real name is on the header above it.
	column_titles_visible = false
	hide_root = true
	allow_rmb_select = true
	select_mode = Tree.SELECT_ROW
	# THE POINTER SAYS THE ROWS ARE ACTIONABLE. A Tree draws the OS arrow, so this pane -- where
	# every row can be clicked, dragged and dropped on -- read exactly like a static listing.
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	# FP-07: THE ROW UNDER THE CURSOR LIGHTS UP. Godot's Tree paints its own drop highlight when a
	# drop mode is set and `_can_drop_data` says yes -- so a drag across this pane showed nothing
	# at all until the mouse came up, and the only way to learn where a file would land was to
	# drop it and read the toast.
	drop_mode_flags = Tree.DROP_MODE_ON_ITEM
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	item_collapsed.connect(_on_item_collapsed)
	item_selected.connect(_on_item_selected)
	item_activated.connect(_on_item_activated)
	item_mouse_selected.connect(_on_item_mouse_selected)


## A drop this pane will not take, and the reason -- which the forbidden cursor cannot carry.
signal refile_refused(reason: String)


## A module row is draggable: onto the canvas to place it, onto another folder row to move it.
func _get_drag_data(at_position: Vector2) -> Variant:
	var item := get_item_at_position(at_position)
	if item == null:
		return null
	var meta: Variant = item.get_metadata(0)
	var payload := {}
	var label := ""
	if meta is Dictionary and (meta as Dictionary).has("folder"):
		var folder := str((meta as Dictionary)["folder"])
		payload = { "source": "folder", "path": folder }
		label = folder.get_file()
	else:
		var path := str(meta)
		if path.is_empty():
			return null
		payload = { "source": "module", "path": path }
		label = path.get_file()
	var ghost := Label.new()
	ghost.text = label
	set_drag_preview(ghost)
	return payload


## Only a FOLDER row takes a drop, and never one onto itself or into its own subtree.
func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	var target := _drop_target(at_position, data)
	if not target.is_empty():
		_refused_over = null
		return true
	# WHY NOT, ONCE. Godot never calls `_drop_data` for a refused drop, so the specific message --
	# "a folder cannot go inside itself", "it is already there" -- had no route to the user at all:
	# the forbidden cursor said no and nothing said why. Emitted on the row TRANSITION rather than
	# on every motion event, because `_can_drop_data` runs per frame while the mouse is still.
	var item := get_item_at_position(at_position)
	if item != null and item != _refused_over:
		_refused_over = item
		var reason := _refusal_for(data, item)
		if not reason.is_empty():
			refile_refused.emit(reason)
	return false


## The row a refusal has already been reported for, so it is reported once and not per frame.
var _refused_over: TreeItem = null


## Why `data` cannot land on `item`, or "" when there is nothing worth saying.
func _refusal_for(data: Variant, item: TreeItem) -> String:
	if item == null:
		return ""
	var meta: Variant = item.get_metadata(0)
	var into := str((meta as Dictionary)["folder"]) if meta is Dictionary \
		and (meta as Dictionary).has("folder") else str(meta).get_base_dir()
	return _refusal_into(data, into)


## THE RULE ALONE, with the row lookup taken out of it -- the same split `_drop_target_for` makes,
## and for the same reason: the message a refusal carries can then be asked for without a
## laid-out Tree to hit-test against.
func _refusal_into(data: Variant, into: String) -> String:
	if not (data is Dictionary):
		return ""
	var spec := data as Dictionary
	var source := str(spec.get("source", ""))
	var dragged := str(spec.get("path", ""))
	if dragged.is_empty() or into.is_empty():
		return ""
	if source == "folder":
		if Paths.same(dragged, into) or Paths.is_under(into, dragged):
			return "Can't move %s inside itself." % dragged.get_file()
		if Paths.same(into, dragged.get_base_dir()):
			return "%s is already in %s." % [dragged.get_file(), into.get_file()]
		return ""
	if source == "module" and Paths.same(dragged.get_base_dir(), into):
		return "%s is already in %s." % [dragged.get_file(), into.get_file()]
	return ""


func _drop_data(at_position: Vector2, data: Variant) -> void:
	_refused_over = null
	var into := _drop_target(at_position, data)
	if into.is_empty():
		return
	var spec := data as Dictionary
	refile_requested.emit(str(spec["source"]), str(spec["path"]), into)


## The folder `data` would land in, or "" when this is not a legal drop.
func _drop_target(at_position: Vector2, data: Variant) -> String:
	var item := get_item_at_position(at_position)
	if item == null:
		return ""
	var meta: Variant = item.get_metadata(0)
	if meta is Dictionary and (meta as Dictionary).has("folder"):
		return _drop_target_for(data, str((meta as Dictionary)["folder"]))
	# A FILE ROW STANDS FOR ITS OWN FOLDER. Refusing it meant dropping a module "beside its
	# neighbours" -- which is how anyone reading a file list thinks about where a file goes --
	# was refused, and the user had to find the folder ROW, which in a deep tree can be scrolled
	# off the top. The already-there guard inside `_drop_target_for` still declines a no-op.
	var path := str(meta)
	return "" if path.is_empty() else _drop_target_for(data, path.get_base_dir())


## THE RULE ALONE, with the row lookup taken out of it: whether `data` may land in `into`.
##
## Separated so the rule can be asked a question without a laid-out Tree to hit-test against --
## these are the cases that produce a move with no destination, and they are worth pinning
## somewhere cheaper than a mouse position.
func _drop_target_for(data: Variant, into: String) -> String:
	if not (data is Dictionary) or into.is_empty():
		return ""
	var spec := data as Dictionary
	var source := str(spec.get("source", ""))
	var dragged := str(spec.get("path", ""))
	if dragged.is_empty() or (source != "module" and source != "folder"):
		return ""
	if source == "module":
		# Already there is not a move.
		return "" if Paths.same(dragged.get_base_dir(), into) else into
	# A FOLDER CANNOT LAND IN ITSELF OR IN ITS OWN SUBTREE -- that is a move with no destination,
	# and the projection it produces has no root.
	if Paths.same(dragged, into) or Paths.is_under(into, dragged):
		return ""
	return "" if Paths.same(into, dragged.get_base_dir()) else into


## Rebuilds from the workspace. Cheap enough to run on every model change: a tree of a few dozen
## modules is a few dozen rows, and a pane that only refreshes sometimes is a pane that is
## sometimes wrong.
func rebuild() -> void:
	var previously_selected := selected_path()
	clear()
	_rows.clear()
	# "No tree open." rather than a blank pane: an empty region says nothing about whether it is
	# empty because there is nothing, or empty because something failed.
	if workspace == null or workspace.modules().is_empty():
		var empty := create_item(create_item())
		empty.set_text(0, "No tree open.")
		empty.set_selectable(0, false)
		empty.set_custom_color(0, Color(0.55, 0.58, 0.64))
		return

	var root_item := create_item()
	var folders := {}
	var ordered: Array[Module] = []
	for module in workspace.modules():
		ordered.append(module)
	ordered.sort_custom(func(a, b): return Paths.key(a.file_path()) < Paths.key(b.file_path()))

	# NESTED, one item per path SEGMENT, under the tree's own root.
	#
	# One flat group per distinct folder, labelled with the whole path, was four rows all reading
	# "tests/__builder…" in a 240px pane -- the same truncated prefix repeated, with the part that
	# differs cut off. A folder tree that cannot show which folder is which is not showing a tree.
	var base := _common_root(ordered)

	for module in ordered:
		var parent := _folder_item(root_item, folders, base, module.folder)
		var row := create_item(parent)
		# A GLYPH PER KIND, ahead of the name. Colour alone carries the kind only for a reader who
		# has the legend in view and is not colour-blind; a shape carries it for everyone.
		row.set_text(0, "%s  %s" % [KIND_GLYPH.get(module.kind, "•"), module.file_path().get_file()])
		row.set_text(1, _state_of(module))
		row.set_tooltip_text(0, "%s -- %s" % [module.file_path(), KIND_LABEL.get(module.kind, "")])
		row.set_metadata(0, module.file_path())
		# TINTED BY KIND, from the same palette the card badges and the toolbar legend use. The
		# tree was the one surface where a component and its style companion were the same colour,
		# so the kind a card states outright had to be inferred here from the file name -- which
		# is exactly the two names that differ only by a companion suffix.
		row.set_custom_color(0, Palette.kind_tint(int(module.kind)))
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


## The item for `folder`, creating every level between it and `base` that does not exist yet.
func _folder_item(root_item: TreeItem, folders: Dictionary, base: String, folder: String) -> TreeItem:
	var relative := folder.trim_prefix(base).trim_prefix("/")
	if relative.is_empty():
		return _ensure_folder(root_item, folders, base, base.get_file())
	var parent := _ensure_folder(root_item, folders, base, base.get_file())
	var walk := base
	for segment in relative.split("/", false):
		walk = walk.path_join(segment)
		parent = _ensure_folder(parent, folders, walk, segment)
	return parent


## Which folders the user has folded, by path key. Kept on the pane rather than on the items,
## because the items do not survive a rebuild.
var _collapsed := {}


func _on_item_collapsed(item: TreeItem) -> void:
	if item == null:
		return
	var meta: Variant = item.get_metadata(0)
	if not (meta is Dictionary) or not (meta as Dictionary).has("folder"):
		return
	var key := Paths.key(str((meta as Dictionary)["folder"]))
	if item.collapsed:
		_collapsed[key] = true
	else:
		_collapsed.erase(key)


func _ensure_folder(parent: TreeItem, folders: Dictionary, path: String, label: String) -> TreeItem:
	if folders.has(path):
		return folders[path]
	var item := create_item(parent)
	item.set_text(0, "▸ " + label)
	item.set_selectable(0, false)
	item.set_selectable(1, false)
	item.set_custom_color(0, Color(0.55, 0.58, 0.64))
	# A FOLDER carries its path as a Dictionary, a module as a plain String. The two are told
	# apart by TYPE rather than by a second lookup, so no caller can read one as the other.
	item.set_metadata(0, { "folder": path })
	# THE FULL PATH, which the label cannot carry: a nested pane shows leaves, and two folders
	# called `components` under different parents are indistinguishable by their text alone.
	item.set_tooltip_text(0, "%s\n\nDrag a module here to move it. Drag this folder onto another"
		% path + " to move the whole folder.")
	# FOLDING SURVIVES THE REBUILD. `rebuild()` runs on every model change -- every keystroke that
	# reaches the funnel -- and `Tree.clear()` frees every item, so a folded folder sprang open on
	# the next character typed.
	item.collapsed = _collapsed.has(Paths.key(path))
	folders[path] = item
	return item


## The deepest folder every module in the tree lives under -- the tree's own root, so the pane
## shows the shape INSIDE it rather than the path to it.
func _common_root(modules: Array) -> String:
	var common := PackedStringArray()
	var first := true
	for module in modules:
		var parts := str(module.folder).trim_prefix("res://").split("/", false)
		if first:
			common = parts
			first = false
			continue
		var shared := PackedStringArray()
		for i in range(mini(common.size(), parts.size())):
			if common[i] != parts[i]:
				break
			shared.append(common[i])
		common = shared
	return "res://" + "/".join(common)


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
