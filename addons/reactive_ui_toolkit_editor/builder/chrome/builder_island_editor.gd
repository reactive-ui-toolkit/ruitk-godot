@tool
class_name RuitkBuilderIslandEditor
extends "res://addons/reactive_ui_toolkit_editor/editor/guitkx_code_edit.gd"
## The MULTILINE in-place editor: a card's setup island, edited where it sits.
##
## A sibling of `builder_inline_editor.gd` rather than a mode of it, because the two differ in the
## one place that matters -- what Enter means. A single-line editor commits on Enter; a code island
## is GDScript, where Enter is a new statement, so it commits on Ctrl+Enter and Enter is just a
## newline. Folding both into one control would have meant a flag deciding whether the primary key
## edits or finishes, which is the kind of switch nobody remembers is there.
##
## It exists because the island had NO editor at all. The canvas listed a card's setup lines, and
## the only way to change one was the source pane -- and when double-clicking a row was wired up,
## the island route reached the single-line editor, which would have flattened a multi-statement
## island into one line the moment it committed.
##
## The signal contract is deliberately identical to the inline editor's, so the window's one
## commit funnel serves both.
##
## IT IS THE `.guitkx` CODE EDITOR, not a bare TextEdit. A card's setup island is GDScript, and
## the addon already has a control that colours it, completes in it and carries a diagnostics
## gutter -- the same one the source pane uses. Editing code in a field with none of that is the
## defect SM-03 names, and the fix was to stop writing a second editor beside the one that exists.
##
## Extended by PATH rather than by `class_name`: everything under `builder/` reaches its
## dependencies through preloads, because `ProjectSettings.save()` truncates the editor class
## cache to what the running process loaded and a global name can vanish mid-session.

## The edit was accepted. `token` is whatever the caller attached.
## The edit was accepted. `applied` is true when the user ENDED it deliberately -- Enter here,
## Ctrl+Enter in the island editor -- and false when it ended because focus went elsewhere.
##
## The difference is "done, next" versus "done": an advance run continues on the first and stops
## on the second, and with one channel for both there was no way to tell them apart.
signal committed(token: Variant, text: String, applied: bool)

## The editor closed, by any route -- committed, cancelled, or replaced by the next edit. What a
## listener needs to put a buffer or a highlight back the way it found it.
signal closed(token: Variant)

## The edit was abandoned. `undo_seeding` is true when the builder itself wrote the text being
## edited as part of opening the editor, so cancelling should take that back too.
signal cancelled(token: Variant, undo_seeding: bool)

## The smallest box worth showing. An island editor sized to a one-line island is a field the user
## cannot see they may add lines to.
const MIN_SIZE := Vector2(320.0, 96.0)

var _token: Variant = null
var _initial := ""
var _open := false
var _seeded := false


func _init() -> void:
	visible = false
	# Above the canvas and its overlay, so a click lands here rather than starting a pan.
	mouse_filter = Control.MOUSE_FILTER_STOP
	wrap_mode = TextEdit.LINE_WRAPPING_NONE
	scroll_smooth = false
	focus_exited.connect(_on_focus_exited)


func _ready() -> void:
	# The colouring, the completion and the gutters come from the shared editor's own setup, so
	# the island reads exactly like the same code does in the source pane.
	configure()


func is_open() -> bool:
	return _open


func token() -> Variant:
	return _token


## Opens over a rectangle in the parent's coordinates, seeded with `initial`.
##
## Opening while already open COMMITS the previous edit, for the same reason the single-line
## editor does: a user moving straight from one thing to the next has not asked to throw the first
## one away.
func open_at(rect: Rect2, initial: String, for_token: Variant, seeded := false) -> void:
	if _open:
		commit()
	_seeded = seeded
	_token = for_token
	_initial = initial
	text = initial
	position = rect.position
	size = Vector2(maxf(rect.size.x, MIN_SIZE.x), maxf(rect.size.y, MIN_SIZE.y))
	visible = true
	_open = true
	grab_focus()
	# THE CARET GOES TO THE END and nothing is selected: an island edit starts from code the user
	# opened the editor to adjust, so a selection means the first keystroke wipes it.
	set_caret_line(get_line_count() - 1)
	set_caret_column(get_line(get_line_count() - 1).length())


func commit(applied := false) -> void:
	if not _open:
		return
	var value := text
	var for_token := _token
	# Captured BEFORE closing, because closing clears it -- compared afterwards, every commit
	# looks like a change from the empty string.
	var was := _initial
	_close()
	if value != was:
		committed.emit(for_token, value, applied)


func cancel() -> void:
	if not _open:
		return
	var for_token := _token
	var undo_seeding := _seeded
	_close()
	cancelled.emit(for_token, undo_seeding)


func _close() -> void:
	var was_token := _token
	closed.emit(was_token)
	_open = false
	_seeded = false
	visible = false
	_token = null
	_initial = ""
	text = ""


## Ctrl+Enter commits; Enter is a newline, because this is GDScript. Escape cancels.
func _gui_input(event: InputEvent) -> void:
	if not _open or not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed:
		return
	if key.keycode == KEY_ESCAPE:
		# A completion popup goes with the editor. Godot's CodeEdit does not report whether one is
		# open, so this closes both rather than guessing -- and Ctrl+Space is the only way to have
		# opened one, so the common Escape has nothing to cancel but the edit.
		cancel_code_completion()
		cancel()
		accept_event()
	elif (key.ctrl_pressed or key.meta_pressed) \
			and (key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER):
		commit()
		accept_event()


func _on_focus_exited() -> void:
	# Clicking elsewhere is how a person finishes typing -- the same rule the single-line editor
	# follows, and the one the capability reference states.
	if _open:
		commit()
