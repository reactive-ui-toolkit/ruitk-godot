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
const Diagnostics = preload("res://addons/reactive_ui_toolkit_editor/editor/guitkx_diagnostics_renderer.gd")
const Module = preload("res://addons/reactive_ui_toolkit_editor/builder/document/builder_module.gd")
const Paths = preload("res://addons/reactive_ui_toolkit_editor/builder/document/builder_paths.gd")
const GuitkxEditor = preload("res://addons/reactive_ui_toolkit_editor/editor/guitkx_code_edit.gd")
const Parts = preload("res://addons/reactive_ui_toolkit_editor/builder/chrome/builder_chrome_parts.gd")
const Compiler = preload("res://addons/reactive_ui_toolkit/guitkx/guitkx.gd")

## The buffer changed. `before`/`after` are the whole text either side, which is what the ledger
## records: a gesture is undone by putting the text back, not by replaying keystrokes.
signal buffer_edited(file_path: String, before: String, after: String)

## An edit was applied, or abandoned. The window re-projects on the first and restores on the
## second.
signal edit_applied(file_path: String, text: String)
signal edit_cancelled(file_path: String, restore: String)
## Something the user should be told, from a pane that has no toast of its own.
signal complained(message: String)

## Ctrl+click or F12 on a name the widget could resolve: a component tag, a hook, an identifier
## the analyzer knows. The widget does the whole resolution and emits it; nothing listened, so
## go-to-definition worked everywhere in this addon EXCEPT the pane the builder puts in front of
## the user.
signal definition_requested(file_path: String, offset: int)

## A click on the diagnostics gutter, carrying the record that drew the mark.
signal diagnostic_clicked(file_path: String, line: int, record: Variant)

var workspace: Workspace = null

var _title: Label = null
var _editor: GuitkxEditor = null
var _path := ""
var _edit_toggle: Button = null
var _apply: Button = null
var _revert: Button = null
## The buffer as it was when editing began, so `revert` has something to put back.
var _snapshot := ""
var _editing := false

## The line a card row pointed at, banded so it reads as a place rather than as a caret position.
var _selected_line := 0

## The names a hovered hook chip binds. Warmed here as well as on the card.
var _trace_names := PackedStringArray()


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
	_edit_toggle.button_pressed = false
	_edit_toggle.flat = true
	_edit_toggle.toggled.connect(_set_editing)
	trailing.add_child(_edit_toggle)

	_apply = Button.new()
	_apply.text = "apply  (Ctrl+Enter)"
	_apply.flat = true
	_apply.visible = false
	_apply.pressed.connect(apply_edit)
	trailing.add_child(_apply)

	_revert = Button.new()
	_revert.text = "cancel  (Esc)"
	_revert.flat = true
	_revert.visible = false
	_revert.pressed.connect(cancel_edit)
	trailing.add_child(_revert)
	trailing.add_child(_title)
	add_child(Parts.pane_header("Source — .guitkx", trailing))

	_editor = GuitkxEditor.new()
	_editor.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_editor.configure()
	# WRAP, and no minimap. The pane is a side column, not a main editor: at this width every
	# line of real markup ran off the right edge mid-token, so reading the file meant scrolling
	# it horizontally line by line, and the minimap spent a third of the remaining width drawing
	# a thumbnail of text too narrow to read in the first place.
	# NO WRAPPING. It was on to stop long lines running off a pane crowded with furniture; with
	# the gutter and the fold arrows gone there is room for the code, and a wrapped line makes the
	# displayed line count disagree with the source's -- which matters here, because clicking a
	# card row jumps this pane to a LINE NUMBER.
	_editor.wrap_mode = TextEdit.LINE_WRAPPING_NONE
	_editor.minimap_draw = false
	# NO GUTTER AND NO FOLD ARROWS. A side column has room for the code or for its furniture,
	# not both: between the line numbers, the fold chevrons and the indent markers a third of the
	# width went to things that are not the source, and every real line wrapped.
	_editor.gutters_draw_line_numbers = false
	_editor.gutters_draw_fold_gutter = false
	_editor.draw_tabs = false
	_editor.editable = false
	# SRC-13: READ MODE IS NOT A DISABLED STATE. Godot's TextEdit draws a non-editable buffer in
	# `font_readonly_color`, which in the editor theme is the code at roughly half opacity -- and
	# this pane is read-only almost all the time, so the builder's source view was permanently
	# dimmed and read as greyed-out furniture rather than as the file.
	_editor.add_theme_color_override("font_readonly_color",
		_editor.get_theme_color("font_color", "CodeEdit"))
	# SRC-09: DOUBLE-CLICK ENTERS EDIT MODE. The only way in was the toggle button, so the gesture
	# every other code surface uses did what a non-editable CodeEdit does -- select a word -- and
	# the pane stayed read-only with no hint that it could be anything else.
	_editor.gui_input.connect(_on_editor_gui_input)
	_editor.text_changed.connect(_on_text_changed)
	_editor.definition_requested.connect(func(target: String, offset: int):
		definition_requested.emit(target, offset))
	_editor.gutter_diagnostic_clicked.connect(func(line: int, record: Variant):
		diagnostic_clicked.emit(_path, line, record))
	add_child(_editor)


## Puts the caret on `line` (1-based) and scrolls it into view.
##
## What makes a card row and the source the SAME PLACE: clicking a row in the markup tree is the
## fastest way to find the line that produced it, and without this the two panes are two separate
## views of a file that never point at each other.
func goto_line(line: int) -> void:
	if _editor == null or line <= 0 or line > _editor.get_line_count():
		return
	_selected_line = line
	_repaint_line_bands()
	_editor.set_caret_line(line - 1)
	_editor.set_caret_column(0)
	# ADJUST, DO NOT CENTRE. `center_viewport_to_caret` scrolls the line to the middle whether or
	# not it was already visible, so clicking three adjacent rows on a card made the pane jump
	# three times for no reason. UB-86 in the Unity register, by name.
	_editor.adjust_viewport_to_caret()


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
	# Showing a module does not OPEN it. The edit toggle is what unlocks the buffer, and
	# switching files while an edit was open would otherwise carry the unlocked state onto a
	# file the user never asked to change.
	# ABANDONING AN EDIT PUTS THE BUFFER BACK. Switching module used to reset the flags and drop
	# the snapshot without restoring anything, so typed text stayed in the model with no ledger
	# entry and no way back -- and Save would have written it.
	_leave_edit()
	_editor.text = module.buffer_text


## Re-reads the buffer from the model, for a change that came from somewhere else -- an undo, a
## drag on the canvas, an import rewritten by a move. The caret is kept where it was, because
## losing it on every canvas gesture makes the two surfaces unusable together.
## Marks the field as holding text that would not parse, or clears the mark.
##
## A toast has faded by the time the reader looks back at the text, so a failed apply left no
## trace anywhere near the thing that failed -- and the pane went on looking exactly like a pane
## whose content is fine.
func set_error(on: bool) -> void:
	if _editor == null:
		return
	if not on:
		_editor.remove_theme_stylebox_override("normal")
		_editor.remove_theme_stylebox_override("focus")
		return
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.118, 0.106, 0.114)
	box.set_border_width_all(1)
	box.border_color = Color(0.94, 0.38, 0.38)
	box.set_content_margin_all(4)
	_editor.add_theme_stylebox_override("normal", box)
	_editor.add_theme_stylebox_override("focus", box)


## The names a hovered hook chip binds, so the pane can warm the same lines the canvas does.
##
## Half of the contract line was implemented: hovering a chip highlighted the matching MARKUP ROWS
## on the card and did nothing at all to the source, which is the surface showing the code those
## rows came from.
func set_trace_names(names: PackedStringArray) -> void:
	if _editor == null or names == _trace_names:
		return
	_trace_names = names
	_repaint_line_bands()


## Puts the caret on `line` (1-based) and BANDS it, so the row that was clicked is visible as a
## place rather than only as a caret position.
func _repaint_line_bands() -> void:
	if _editor == null:
		return
	for i in range(_editor.get_line_count()):
		_editor.set_line_background_color(i, Color(0, 0, 0, 0))
	if _selected_line > 0 and _selected_line <= _editor.get_line_count():
		# The clicked row's own band: the caret-line tint follows the caret wherever it goes next,
		# so it cannot say "this is the line you asked for".
		_editor.set_line_background_color(_selected_line - 1, Color(1.0, 0.835, 0.310, 0.14))
	if _trace_names.is_empty():
		return
	for i in range(_editor.get_line_count()):
		var text := _editor.get_line(i)
		for name in _trace_names:
			if _mentions_word(text, str(name)):
				_editor.set_line_background_color(i, Color(0.361, 0.588, 0.965, 0.12))
				break


## Word-boundary match, so `count` does not warm a line mentioning `counter`.
static func _mentions_word(haystack: String, needle: String) -> bool:
	if needle.is_empty():
		return false
	var at := haystack.find(needle)
	while at != -1:
		var before_ok := at == 0 or not _is_word_char(haystack[at - 1])
		var after := at + needle.length()
		var after_ok := after >= haystack.length() or not _is_word_char(haystack[after])
		if before_ok and after_ok:
			return true
		at = haystack.find(needle, at + 1)
	return false


static func _is_word_char(c: String) -> bool:
	return c == "_" or (c >= "0" and c <= "9") or (c >= "a" and c <= "z") or (c >= "A" and c <= "Z")


## Double-click on a read-only listing is the gesture that starts editing it.
func _on_editor_gui_input(event: InputEvent) -> void:
	if _editing or not (event is InputEventMouseButton):
		return
	var button := event as InputEventMouseButton
	if button.double_click and button.button_index == MOUSE_BUTTON_LEFT:
		_set_editing(true)
		if _edit_toggle != null:
			_edit_toggle.set_pressed_no_signal(true)


func refresh_from_model() -> void:
	if workspace == null or _path.is_empty():
		return
	var module := workspace.try_get(_path)
	if module == null:
		clear()
		return
	if module.buffer_text == _editor.text:
		return
	if _editing:
		# AN OPEN EDIT IS NOT OVERWRITTEN. This is called after every canvas gesture, and it
		# replaced the buffer under whatever the user was typing -- losing the text AND the
		# editor's undo history, since assigning `text` clears it. The edit wins; the change is
		# still in the model, and leaving edit mode adopts it.
		complained.emit("%s changed elsewhere — apply or revert to see it." % _path.get_file())
		return
	var line := _editor.get_caret_line()
	var column := _editor.get_caret_column()
	_editor.text = module.buffer_text
	_repaint_line_bands()
	_editor.set_caret_line(clampi(line, 0, maxi(0, _editor.get_line_count() - 1)))
	_editor.set_caret_column(clampi(column, 0,
		_editor.get_line(_editor.get_caret_line()).length()))


func clear() -> void:
	_leave_edit()
	_path = ""
	_title.text = "no module selected"
	_editor.text = ""


## Leaves edit mode, restoring the buffer the edit began from.
##
## THE ONE PLACE that resets the edit state. It was spelled out four times -- in `show_module`,
## `apply_edit`, `cancel_edit` and nowhere in `clear` -- and the exit that mattered most, leaving
## the pane by selecting something else, was the one that restored nothing.
func _leave_edit() -> void:
	var was_editing := _editing
	var restore := _snapshot
	var path := _path
	_editing = false
	_snapshot = ""
	_editor.editable = false
	_edit_toggle.button_pressed = false
	_apply.visible = false
	_revert.visible = false
	if not was_editing or path.is_empty() or workspace == null:
		return
	var module := workspace.try_get(path)
	if module == null or module.read_only or module.buffer_text == restore:
		return
	# The model can only differ here if something wrote it behind the pane's back; put it back the
	# way the edit began, and say so rather than discarding the difference silently.
	workspace.apply_edit(path, restore)
	complained.emit("Abandoned the edit in %s" % path.get_file())


## Writes a real edit back to the model.
##
## The guard is the COMPARISON, not a loading flag. Setting `TextEdit.text` from code does not
## emit `text_changed` at all, so a load cannot arrive here today -- and if that ever changed, a
## load is by definition text that already equals the model's, so it would still be rejected here.
## A flag would have to be right about the engine's behaviour; this does not.
## Ctrl+Enter applies, Escape cancels.
##
## The pane had NO keyboard at all: the only routes to apply or cancel were clicking the two
## buttons. The window's own key model deliberately stands down while a text surface holds focus,
## which is right -- but it left the editing surface with no chords of its own, so an edit could
## only be finished with the mouse.
##
## `_unhandled_key_input` rather than `_gui_input`, because the focus is on the CodeEdit inside
## this pane, not on the pane.
## Paints the compiler's diagnostics onto the editing surface.
##
## `GuitkxCodeEdit` OWNS a diagnostics gutter, a per-line store and a hover composer that
## prepends a line's diagnostics -- and the builder called none of it, so the gutter it embeds was
## permanently blank and an error in the file being edited was invisible on the surface it was
## being edited on. Everything here is the editor addon's own pipeline; what was missing was the
## call.
func show_diagnostics(diagnostics: Array) -> void:
	if _editor == null or _editor.diag_gutter < 0:
		return
	var err := _icon("StatusError")
	var warn := _icon("StatusWarning")
	Diagnostics.render(_editor, _editor.diag_gutter, diagnostics, err, warn)
	# And the same list per line, so the hover card carries the message rather than a bare icon.
	var by_line := {}
	for entry in diagnostics:
		if not (entry is Dictionary):
			continue
		var line := int((entry as Dictionary).get("line", -1))
		if line < 0:
			continue
		if not by_line.has(line):
			by_line[line] = []
		(by_line[line] as Array).append(entry)
	_editor.set_line_diagnostics(by_line)


## An editor theme icon, or null outside the editor -- the renderer handles a null icon.
func _icon(name: String) -> Texture2D:
	if not Engine.is_editor_hint():
		return null
	var theme := EditorInterface.get_editor_theme()
	if theme == null or not theme.has_icon(name, "EditorIcons"):
		return null
	return theme.get_icon(name, "EditorIcons")


func _unhandled_key_input(event: InputEvent) -> void:
	if not _editing or not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed:
		return
	if not _editor.has_focus() and not has_focus():
		return
	if key.keycode == KEY_ESCAPE:
		cancel_edit()
	elif (key.ctrl_pressed or key.meta_pressed) \
			and (key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER):
		apply_edit()
	else:
		return
	get_viewport().set_input_as_handled()


func _on_text_changed() -> void:
	if workspace == null or _path.is_empty():
		return
	var module := workspace.try_get(_path)
	if module == null or module.read_only:
		return
	# WHILE AN EDIT IS OPEN THE MODEL IS NOT TOUCHED. This wrote every keystroke straight into
	# the module, which is what made the whole source-edit path silently historyless: by the time
	# Apply ran, `before` already equalled `after`, so the window's funnel rejected it as a no-op
	# -- no ledger entry, no card re-projection, no preview round. The class comment below has
	# always said "the pane hands the buffer over ONCE, on apply"; now it does.
	#
	# Half-typed text also has no business in the model: it is what Save writes and what the crash
	# journal snapshots.
	if _editing:
		return
	var before := module.buffer_text
	var after := _editor.text
	if before == after:
		return
	if not workspace.apply_edit(_path, after):
		return
	buffer_edited.emit(_path, before, after)


## EDIT -> APPLY, the cycle the reference has and the hint bar already promised.
##
## Typing straight into the live buffer means every intermediate keystroke is a state the
## preview compiles and the canvas re-projects -- so half a tag name is an error report, and
## deleting a line to retype it blanks the card. The snapshot makes `revert` mean something,
## and applying PARSES FIRST: a buffer that does not parse is not a state to hand the rest of
## the builder.
func _set_editing(on: bool) -> void:
	if _editor == null:
		return
	if on:
		var module := workspace.try_get(_path) if workspace != null else null
		if module == null or module.read_only:
			_edit_toggle.button_pressed = false
			complained.emit("%s is read-only." % _path.get_file())
			return
		_snapshot = module.buffer_text
	_editing = on
	_editor.editable = on
	_apply.visible = on
	_revert.visible = on
	if on:
		_editor.grab_focus()


func is_editing() -> bool:
	return _editing


## Hands the edited text back, but only if it parses.
func apply_edit() -> void:
	if not _editing or _editor == null:
		return
	var text := _editor.text
	var parsed: Dictionary = Compiler.compile(text, _path.get_file().get_basename())
	if not bool(parsed.get("ok", false)):
		var first := ""
		for d in (parsed.get("diagnostics", []) as Array):
			if int((d as Dictionary).get("severity", 0)) == 0:
				first = str((d as Dictionary).get("message", ""))
				break
		complained.emit("Parse failed: %s" % first)
		return
	# The snapshot is dropped WITHOUT restoring: this text is the edit, and it goes out through
	# `edit_applied` to the window's one funnel, which records it and re-projects.
	_editing = false
	_snapshot = ""
	_editor.editable = false
	_edit_toggle.button_pressed = false
	_apply.visible = false
	_revert.visible = false
	edit_applied.emit(_path, text)


## Puts the buffer back the way it was when editing began.
func cancel_edit() -> void:
	if not _editing:
		return
	var restore := _snapshot
	_editing = false
	_snapshot = ""
	_editor.editable = false
	_edit_toggle.button_pressed = false
	_apply.visible = false
	_revert.visible = false
	_editor.text = restore
	edit_cancelled.emit(_path, restore)
