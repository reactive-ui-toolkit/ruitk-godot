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
signal cancelled(token: Variant)

var _token: Variant = null
var _initial := ""
var _open := false


func _init() -> void:
	visible = false
	select_all_on_focus = true
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
func open_at(rect: Rect2, initial: String, for_token: Variant) -> void:
	if _open:
		commit()
	_token = for_token
	_initial = initial
	text = initial
	position = rect.position
	size = Vector2(maxf(rect.size.x, 60.0), maxf(rect.size.y, 22.0))
	visible = true
	_open = true
	grab_focus()
	select_all()


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
	_close()
	cancelled.emit(for_token)


func _close() -> void:
	_open = false
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
