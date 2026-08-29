@tool
class_name RuitkBuilderChromeParts
extends RefCounted
## The small shared pieces every pane in the builder is built out of: a pane header, a section
## heading, a legend swatch, a hint strip.
##
## HERE RATHER THAN IN EACH PANE because a pane header that is built three times is a pane header
## that looks three ways. The Unity leg's chrome reads as one surface precisely because its panes
## do not each invent their own title bar, and the moment ours did, the folder pane had no title
## at all while the library had a different one.
##
## Hand-written `@tool` GDScript, like `canvas_palette.gd` and for the same reason: the chrome is
## editor code, and a generated `.gd` is not a `@tool` script, so a `.style.guitkx` module read
## from here comes back with every key missing.

const TITLE_FONT_SIZE := 11
const SECTION_FONT_SIZE := 10
const HINT_FONT_SIZE := 10

const TITLE_COLOR := Color(0.541, 0.573, 0.612)
const SECTION_COLOR := Color(0.478, 0.478, 0.545)
const HINT_COLOR := Color(0.478, 0.478, 0.522)
const ACCENT_COLOR := Color(0.361, 0.588, 0.965)


## A pane's title bar: a small upper-case name on the left, and whatever the pane wants on the
## right (a `+ new` button, the open file, an `edit` toggle).
##
## Every pane gets one. A pane with no title is a region a reader has to identify by its contents,
## which is exactly the reading the builder should be saving them.
static func pane_header(title: String, trailing: Control = null) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	var label := Label.new()
	label.text = title.to_upper()
	label.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	label.add_theme_color_override("font_color", TITLE_COLOR)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)

	if trailing != null:
		row.add_child(trailing)
	return row


## A pane header that FOLDS its pane. The caret is part of the title, so the whole header is the
## target rather than a chevron the size of a full stop.
##
## `on_toggle` is called with no argument; the CALLER owns the folded state and calls
## `set_folded` back. A widget that remembered would be a second answer to the same question.
static func folding_pane_header(title: String, on_toggle: Callable) -> Button:
	var header := Button.new()
	header.flat = true
	header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.text = "v  " + title.to_upper()
	header.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	header.add_theme_color_override("font_color", TITLE_COLOR)
	header.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	header.tooltip_text = "Show or hide this pane"
	header.set_meta("pane_title", title.to_upper())
	header.pressed.connect(on_toggle)
	return header


## Redraws a folding header's caret. Separate from the constructor because the state lives with
## the caller and this is called every time it changes.
static func set_folded(header: Button, folded: bool) -> void:
	if header == null:
		return
	header.text = "%s  %s" % [">" if folded else "v", str(header.get_meta("pane_title", ""))]


## A heading INSIDE a pane — "NATIVE ELEMENTS", "HOOKS", "IMPORTS". Smaller and dimmer than a pane
## title, because it divides a pane rather than naming one.
static func section_heading(text: String) -> Label:
	var label := Label.new()
	label.text = text.to_upper()
	label.add_theme_font_size_override("font_size", SECTION_FONT_SIZE)
	label.add_theme_color_override("font_color", SECTION_COLOR)
	return label


## One legend entry: a colour dot and what it means.
static func legend_entry(text: String, tint: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)

	var dot := ColorRect.new()
	dot.color = tint
	dot.custom_minimum_size = Vector2(8, 8)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(dot)

	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	label.add_theme_color_override("font_color", TITLE_COLOR)
	row.add_child(label)
	return row


## The strip along the bottom of the window that says how the thing is driven.
##
## A builder is a direct-manipulation surface, and every gesture it accepts is invisible until
## someone tries it. The Unity leg keeps the whole interaction model on screen permanently rather
## than in documentation nobody opens while dragging.
static func hint_bar(hints: PackedStringArray) -> Label:
	var label := Label.new()
	label.text = "  •  ".join(hints)
	label.add_theme_font_size_override("font_size", HINT_FONT_SIZE)
	label.add_theme_color_override("font_color", HINT_COLOR)
	label.clip_text = true
	return label


## A placeholder line for a pane with nothing in it yet.
static func placeholder(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	label.add_theme_color_override("font_color", TITLE_COLOR)
	return label
