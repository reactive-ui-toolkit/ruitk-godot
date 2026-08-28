@tool
class_name RuitkBuilderIslandEditor
extends TextEdit
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

## The edit was accepted. `token` is whatever the caller attached.
signal committed(token: Variant, text: String)

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


func commit() -> void:
	if not _open:
		return
	var value := text
	var for_token := _token
	# Captured BEFORE closing, because closing clears it -- compared afterwards, every commit
	# looks like a change from the empty string.
	var was := _initial
	_close()
	if value != was:
		committed.emit(for_token, value)


func cancel() -> void:
	if not _open:
		return
	var for_token := _token
	var undo_seeding := _seeded
	_close()
	cancelled.emit(for_token, undo_seeding)


func _close() -> void:
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
