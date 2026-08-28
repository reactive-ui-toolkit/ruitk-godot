@tool
class_name RuitkBuilderInlineEditor
extends LineEdit
## ONE floating editor, reused for every in-place edit on the canvas: an attribute value, a
## directive header, a hook chip, a style entry, a card title.
##
## One, not one per row. The Unity leg's inline-editor defect cluster is almost entirely about
## two of them being open at once, or one being open over a row that has since been re-rendered
## away -- and every fix there is another rule about which of them wins. A single editor cannot
## have that problem: opening it anywhere closes it everywhere else, because there is nowhere
## else.
##
## IT COMMITS ON THE WAY OUT. Enter commits, Escape cancels, and losing focus commits -- because
## clicking on something else is how a person finishes typing, and an editor that threw the edit
## away on focus loss would lose work every time the user reached for the thing they were about
## to do next.

## The edit was accepted. `token` is whatever the opener passed in, so the caller can tell which
## row it opened this for without keeping the state itself.
signal committed(token: Variant, text: String)
## `undo_seeding` is true when the builder had written the text being edited as part of opening
## the editor, so cancelling should take that back as well.
signal cancelled(token: Variant, undo_seeding: bool)

var _token: Variant = null
var _initial := ""
var _open := false

## Whether the text in the editor was written by the BUILDER when it opened.
var _seeded := false


func _init() -> void:
	visible = false
	# FOCUS NEVER SELECTS THE WHOLE TEXT (capability reference §5). Selecting it means the first
	# keystroke wipes the value the user opened the editor to ADJUST -- and every inline edit here
	# starts from an existing value, because that is what "edit in place" means.
	select_all_on_focus = false
	# Above the canvas and its overlay, so a click lands here rather than starting a pan.
	mouse_filter = Control.MOUSE_FILTER_STOP
	text_submitted.connect(func(_t: String): commit())
	focus_exited.connect(_on_focus_exited)


func is_open() -> bool:
	return _open


func token() -> Variant:
	return _token


## Opens over a rectangle in the parent's coordinates, seeded with `initial`.
##
## Opening while already open COMMITS the previous edit first. The alternative is to discard it,
## and a user who clicks straight from one attribute to the next has not asked to throw the first
## one away.
## `seeded` marks an editor the BUILDER opened on text it had just written itself -- a fresh wrap
## header, a new clause. Escaping one of those undoes the seeding too (capability reference §5):
## the user asked to wrap a row and then changed their mind, and leaving `@if (true)` behind makes
## cancelling the edit and cancelling the action two separate steps.
func open_at(rect: Rect2, initial: String, for_token: Variant, seeded := false) -> void:
	if _open:
		commit()
	_seeded = seeded
	_token = for_token
	_initial = initial
	text = initial
	position = rect.position
	size = Vector2(maxf(rect.size.x, 60.0), maxf(rect.size.y, 22.0))
	visible = true
	_open = true
	grab_focus()
	# THE CARET GOES TO THE END, and nothing is selected: every inline edit here starts from a
	# value the user opened the editor to adjust, so a selection means the first keystroke wipes it.
	caret_column = text.length()


func commit() -> void:
	if not _open:
		return
	var value := text
	var for_token := _token
	# Captured BEFORE closing, because closing clears it -- compared afterwards, every commit
	# looks like a change from the empty string and an untouched value reports an edit.
	var was := _initial
	_close()
	# Emitted AFTER closing, so a handler that opens the editor again -- moving to the next
	# attribute, say -- is not immediately closed by the tail of this call.
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


func _gui_input(event: InputEvent) -> void:
	if not _open or not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if key.pressed and key.keycode == KEY_ESCAPE:
		cancel()
		accept_event()


func _on_focus_exited() -> void:
	# Clicking elsewhere is how a person finishes typing.
	if _open:
		commit()
