@tool
class_name RuitkBuilderSourcePane
extends VBoxContainer
## The selected module's buffer, editable, in the same code editor the `.guitkx` view uses.
##
## REUSED, not rebuilt: `GuitkxCodeEdit` already carries the whole editing substrate -- markup
## completion, the diagnostics gutter, signature help, go-to-definition, comment toggling, the
## bookmark cycle. A second code editor in the same addon would be a second set of all of that,
## and the two would drift on the first change to either.
##
## The buffer is the WORKSPACE's. Typing here calls `apply_edit`, which is the same entry the
## canvas uses, so an edit made in the source pane and an edit made by a drag on the canvas are
## the same kind of event and land in the same ledger.

const Workspace = preload("res://addons/reactive_ui_toolkit_editor/builder/document/builder_workspace.gd")
const Module = preload("res://addons/reactive_ui_toolkit_editor/builder/document/builder_module.gd")
const Paths = preload("res://addons/reactive_ui_toolkit_editor/builder/document/builder_paths.gd")
const GuitkxEditor = preload("res://addons/reactive_ui_toolkit_editor/editor/guitkx_code_edit.gd")
const Parts = preload("res://addons/reactive_ui_toolkit_editor/builder/chrome/builder_chrome_parts.gd")

## The buffer changed. `before`/`after` are the whole text either side, which is what the ledger
## records: a gesture is undone by putting the text back, not by replaying keystrokes.
signal buffer_edited(file_path: String, before: String, after: String)

var workspace: Workspace = null

var _title: Label = null
var _editor: GuitkxEditor = null
var _path := ""
var _edit_toggle: Button = null


func _init() -> void:
	add_theme_constant_override("separation", 2)
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	_title = Label.new()
	_title.text = "no module selected"
	_title.add_theme_font_size_override("font_size", Parts.TITLE_FONT_SIZE)
	_title.add_theme_color_override("font_color", Parts.ACCENT_COLOR)
	# An explicit read/edit toggle. The buffer is live either way, but a side pane that silently
	# accepts keystrokes is a pane you can change a file in by clicking the wrong thing -- and the
	# target has the affordance, so a reader looking for it should find it.
	var trailing := HBoxContainer.new()
	trailing.add_theme_constant_override("separation", 6)
	_edit_toggle = Button.new()
	_edit_toggle.text = "edit"
	_edit_toggle.toggle_mode = true
	_edit_toggle.button_pressed = true
	_edit_toggle.flat = true
	_edit_toggle.toggled.connect(func(on: bool):
		if _editor != null:
			_editor.editable = on)
	trailing.add_child(_edit_toggle)
	trailing.add_child(_title)
	add_child(Parts.pane_header("Source — .guitkx", trailing))

	_editor = GuitkxEditor.new()
	_editor.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_editor.configure()
	# WRAP, and no minimap. The pane is a side column, not a main editor: at this width every
	# line of real markup ran off the right edge mid-token, so reading the file meant scrolling
	# it horizontally line by line, and the minimap spent a third of the remaining width drawing
	# a thumbnail of text too narrow to read in the first place.
	_editor.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_editor.minimap_draw = false
	_editor.text_changed.connect(_on_text_changed)
	add_child(_editor)


## Puts the caret on `line` (1-based) and scrolls it into view.
##
## What makes a card row and the source the SAME PLACE: clicking a row in the markup tree is the
## fastest way to find the line that produced it, and without this the two panes are two separate
## views of a file that never point at each other.
func goto_line(line: int) -> void:
	if _editor == null or line <= 0 or line > _editor.get_line_count():
		return
	_editor.set_caret_line(line - 1)
	_editor.set_caret_column(0)
	_editor.center_viewport_to_caret()


func editor() -> GuitkxEditor:
	return _editor


func path() -> String:
	return _path


## Shows a module. Re-showing the one already open is a no-op rather than a reload: reloading
## would drop the caret and the selection every time something else re-announced the same file.
func show_module(file_path: String) -> void:
	if workspace == null:
		return
	if Paths.key(file_path) == Paths.key(_path):
		return
	var module := workspace.try_get(file_path)
	if module == null:
		clear()
		return
	_path = module.file_path()
	_title.text = "%s%s" % [_path.get_file(), "  (read-only)" if module.read_only else ""]
	_editor.file_path = _path
	_editor.editable = not module.read_only
	_editor.text = module.buffer_text


## Re-reads the buffer from the model, for a change that came from somewhere else -- an undo, a
## drag on the canvas, an import rewritten by a move. The caret is kept where it was, because
## losing it on every canvas gesture makes the two surfaces unusable together.
func refresh_from_model() -> void:
	if workspace == null or _path.is_empty():
		return
	var module := workspace.try_get(_path)
	if module == null:
		clear()
		return
	if module.buffer_text == _editor.text:
		return
	var line := _editor.get_caret_line()
	var column := _editor.get_caret_column()
	_editor.text = module.buffer_text
	_editor.set_caret_line(clampi(line, 0, maxi(0, _editor.get_line_count() - 1)))
	_editor.set_caret_column(clampi(column, 0,
		_editor.get_line(_editor.get_caret_line()).length()))


func clear() -> void:
	_path = ""
	_title.text = "no module selected"
	_editor.text = ""


## Writes a real edit back to the model.
##
## The guard is the COMPARISON, not a loading flag. Setting `TextEdit.text` from code does not
## emit `text_changed` at all, so a load cannot arrive here today -- and if that ever changed, a
## load is by definition text that already equals the model's, so it would still be rejected here.
## A flag would have to be right about the engine's behaviour; this does not.
func _on_text_changed() -> void:
	if workspace == null or _path.is_empty():
		return
	var module := workspace.try_get(_path)
	if module == null or module.read_only:
		return
	var before := module.buffer_text
	var after := _editor.text
	if before == after:
		return
	if not workspace.apply_edit(_path, after):
		return
	buffer_edited.emit(_path, before, after)
