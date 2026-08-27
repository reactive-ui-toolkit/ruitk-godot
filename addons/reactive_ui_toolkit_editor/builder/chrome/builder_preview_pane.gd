@tool
class_name RuitkBuilderPreviewPane
extends VBoxContainer
## LIVE PREVIEW — the focused component, actually rendered, actually running.
##
## The pipeline for this already existed and had nowhere to appear: `builder_preview.gd` compiles
## the mirrored tree and `mount()`s the focus through the real reconciler. Without a pane the
## builder showed a picture of a component's SOURCE beside a picture of its STRUCTURE and never
## the component, which is the one thing the person building it is trying to see.
##
## The mount is the real thing, not an approximation: same compiler, same reconciler, same host
## config as the game. What renders here is what renders there, or the preview is a liar.

const Parts = preload("res://addons/reactive_ui_toolkit_editor/builder/chrome/builder_chrome_parts.gd")
const Preview = preload("res://addons/reactive_ui_toolkit_editor/builder/preview/builder_preview.gd")
const Paths = preload("res://addons/reactive_ui_toolkit_editor/builder/document/builder_paths.gd")

const NOTE_FONT_SIZE := 10
const NOTE_COLOR := Color(0.478, 0.478, 0.545)

var preview: Preview = null

var _tag: Label = null
var _stage: PanelContainer = null
var _slot: MarginContainer = null
var _note: Label = null
var _origin: Label = null
var _path := ""


func _init() -> void:
	add_theme_constant_override("separation", 6)
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	_tag = Label.new()
	_tag.text = ""
	_tag.add_theme_font_size_override("font_size", Parts.TITLE_FONT_SIZE)
	_tag.add_theme_color_override("font_color", Parts.ACCENT_COLOR)
	add_child(Parts.pane_header("Live preview", _tag))

	# The component sits on a stage of its own rather than loose in the pane: a component with no
	# background of its own is invisible against the pane, and "my component renders nothing" and
	# "my component renders the same colour as the panel" look identical.
	_stage = PanelContainer.new()
	_stage.custom_minimum_size = Vector2(0, 120)
	_stage.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	# A BORDER, explicitly. Without one the rendered component is painted straight onto the pane
	# and there is nothing saying where the component ends and the builder's own chrome begins --
	# a preview whose bounds are invisible cannot answer "is my layout filling its parent".
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color(0.11, 0.11, 0.13)
	frame.border_color = Color(0.24, 0.24, 0.30)
	frame.set_border_width_all(1)
	frame.set_corner_radius_all(4)
	frame.set_content_margin_all(2)
	_stage.add_theme_stylebox_override("panel", frame)
	add_child(_stage)

	_slot = MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		_slot.add_theme_constant_override("margin_" + side, 10)
	_stage.add_child(_slot)

	_origin = Label.new()
	_origin.add_theme_font_size_override("font_size", NOTE_FONT_SIZE)
	_origin.add_theme_color_override("font_color", NOTE_COLOR)
	_origin.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_origin.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_origin)

	_note = Label.new()
	_note.add_theme_font_size_override("font_size", NOTE_FONT_SIZE)
	_note.add_theme_color_override("font_color", NOTE_COLOR)
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_note)

	# The captions describe the stage, so they sit under it and everything spare goes below them
	# rather than between.
	var tail := Control.new()
	tail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(tail)

	_show_idle()


## Renders `file_path`'s component onto the stage.
##
## A component that does not build LEAVES THE LAST GOOD RENDER standing and says so underneath —
## the same rule the rest of the preview pipeline follows. A pane that blanked on every broken
## keystroke would be blank for most of the time anyone is typing.
func show_module(file_path: String) -> void:
	if preview == null:
		return
	_path = Paths.canon(file_path)
	_tag.text = _tag_for(_path)
	if preview.mount(_slot, _path):
		_note.text = "rendered from the real component — every edit re-renders"
		_origin.text = "prop defaults taken from its usage in the tree"
		return

	# NOT BUILT YET is the common case, not an error: selecting a module the last round had no
	# reason to compile arrives here before its script exists. Ask for a round -- the window
	# re-shows this pane when one finishes, so the mount lands a beat later instead of never.
	preview.request_refresh()
	if _slot.get_child_count() > 0:
		_note.text = "last good render — the current edit does not build yet"
	else:
		_show_idle()


## Drops the mount. Called when the tree closes, so a preview never outlives the tree it came from.
func clear() -> void:
	if preview != null:
		preview.unmount()
	_path = ""
	_tag.text = ""
	_show_idle()


func path() -> String:
	return _path


func _show_idle() -> void:
	_note.text = "select a component to see it rendered"
	if _origin != null:
		_origin.text = ""


## `<RIGHTSIDE>` — the component named the way the markup that uses it names it, so the preview
## header and the tag in a parent's markup read as the same thing.
func _tag_for(file_path: String) -> String:
	if file_path.is_empty():
		return ""
	return "<%s>" % file_path.get_file().trim_suffix(Paths.SUFFIX_PLAIN).to_upper()
