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
const Attributes = preload("res://addons/reactive_ui_toolkit_editor/builder/edits/builder_attributes.gd")

const NOTE_FONT_SIZE := 10
const NOTE_COLOR := Color(0.478, 0.478, 0.545)

## A component in the preview was clicked. The window selects the module that renders it.
signal component_picked(file_path: String)

var preview: Preview = null
## The projected graph, so the pane can find where this component is USED.
var graph = null

var _tag: Label = null
var _stage: PanelContainer = null
var _slot: MarginContainer = null
var _note: Label = null
var _origin: Label = null
var _path := ""
var _knobs: VBoxContainer = null
## What the knobs currently say. Passed to every mount.
var _props := {}
var _state_panel: VBoxContainer = null


func _init() -> void:
	add_theme_constant_override("separation", 6)
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	_tag = Label.new()
	_tag.text = ""
	_tag.add_theme_font_size_override("font_size", Parts.TITLE_FONT_SIZE)
	_tag.add_theme_color_override("font_color", Parts.ACCENT_COLOR)
	add_child(Parts.pane_header("Live preview", _tag))

	# KNOBS above the stage: one field per prop the component declares, so the preview can be
	# driven rather than only looked at.
	_knobs = VBoxContainer.new()
	_knobs.add_theme_constant_override("separation", 2)
	add_child(_knobs)

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
	_stage.gui_input.connect(_on_stage_input)
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

	# STATE, read off the running tree. What a component's hooks are HOLDING is only knowable
	# from the mount, and it is the thing a preview is most often opened to check -- "why is it
	# showing the empty branch" is a question about state, not about markup.
	_state_panel = VBoxContainer.new()
	_state_panel.add_theme_constant_override("separation", 2)
	add_child(_state_panel)

	# The captions describe the stage, so they sit under it and everything spare goes below them
	# rather than between.
	var tail := Control.new()
	tail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(tail)

	_show_idle()


## A click on the rendered component selects the module that renders it.
##
## Ported from the Unity leg's `OnPreviewComponentPicked`. Theirs maps the clicked ELEMENT back
## to the component that owns it; ours can only answer for the mounted one, because Godot's
## nodes carry no back-reference to the `.guitkx` row that made them. Selecting the mounted
## component is the useful half and is honest about being it.
func _on_stage_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var click := event as InputEventMouseButton
	if click.pressed and click.button_index == MOUSE_BUTTON_LEFT and not _path.is_empty():
		component_picked.emit(_path)


## What a module with nothing to render says about itself.
##
## Ported from the Unity leg's `ModuleInfoFor`. A hook or a util module has no component to put
## on the stage, and an empty box with "select a component" under it says the pane is broken
## rather than that this module is not a component. Its signature and the components that import
## it are both already on the graph, so the pane never has to fall back to generic phrasing.
func _module_note(file_path: String) -> String:
	if graph == null:
		return ""
	var index: int = graph.index_of(file_path)
	if index < 0:
		return ""
	var card = graph.cards[index]
	var consumers: PackedStringArray = PackedStringArray()
	for other in graph.cards:
		for row in other.imports:
			if str(row.text).contains(card.title):
				consumers.append(other.title)
				break
	var used := ("used by " + ", ".join(consumers)) if not consumers.is_empty() 		else "nothing imports it yet"
	return "%s — %s" % [card.signature if not card.signature.is_empty() else card.title, used]


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
	_build_knobs()
	if preview.mount(_slot, _path, _props):
		_note.text = "rendered from the real component — every edit re-renders"
		_origin.text = _usage_note(_path)
		_refresh_state()
		return

	# NOT BUILT YET is the common case, not an error: selecting a module the last round had no
	# reason to compile arrives here before its script exists. Ask for a round -- the window
	# re-shows this pane when one finishes, so the mount lands a beat later instead of never.
	preview.request_refresh()
	if _slot.get_child_count() > 0:
		_note.text = "last good render — the current edit does not build yet"
		return
	# NOT A COMPONENT is not a failure. A hook or a util module has nothing to put on a stage,
	# and saying "select a component" under an empty box reads as the pane being broken.
	var info := _module_note(_path)
	if not info.is_empty():
		_note.text = info
		_origin.text = "this module has no component to render"
		return
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


## Where this component is used, and with what.
##
## Ported from the Unity leg's `UsageFor`. A component is previewed with its DEFAULT props, and
## defaults are usually the least interesting values it ever takes -- a card with no title, a list
## with no items. Naming the component that uses it, and the attributes it passes, is the
## difference between "this renders" and "this is what it looks like where it actually appears".
func _usage_note(file_path: String) -> String:
	if graph == null:
		return "rendered with its own default props"
	var index: int = graph.index_of(file_path)
	if index < 0:
		return "rendered with its own default props"
	var title := str(graph.cards[index].title)
	for card in graph.cards:
		if card.file_path == file_path:
			continue
		for row in card.markup:
			if str(row.name) != title:
				continue
			var attrs := str(row.attrs_text).strip_edges()
			if attrs.is_empty():
				return "used by %s, which passes no props" % card.title
			return "prop defaults taken from its usage in %s: %s" % [card.title, attrs]
	return "nothing in this tree uses it yet — rendered with its own defaults"


## Builds one field per declared prop, seeded from where the component is USED.
##
## Ported from the Unity leg's `BuildKnobs` / `SeededLiteral`. A knob starts at the literal the
## real usage passes -- so previewing `Card` shows the title the app actually gives it, not an
## empty string -- and falls back to the prop's own default when the usage passes an expression
## rather than a literal, because `title={state[0]}` is not a value this pane can know.
func _build_knobs() -> void:
	for child in _knobs.get_children():
		_knobs.remove_child(child)
		child.queue_free()
	_props.clear()
	if graph == null:
		return
	var index: int = graph.index_of(_path)
	if index < 0:
		return
	var card = graph.cards[index]
	var props: Array = Attributes.props_of_component(card)
	if props.is_empty():
		return

	var usage := _usage_pairs(_path)
	for entry in props:
		var spec := entry as Dictionary
		var name := str(spec["name"])
		var seeded := _seeded_literal(usage, name)
		if seeded.is_empty():
			continue
		_props[name] = _typed(seeded, str(spec.get("type", "")))
		_knobs.add_child(_knob_row(name, seeded, str(spec.get("type", ""))))


## One knob: the prop's name, and a field that re-mounts the preview when it changes.
func _knob_row(name: String, value: String, type: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	var label := Label.new()
	label.text = name
	label.add_theme_font_size_override("font_size", NOTE_FONT_SIZE)
	label.add_theme_color_override("font_color", NOTE_COLOR)
	label.custom_minimum_size = Vector2(90, 0)
	row.add_child(label)

	var field := LineEdit.new()
	field.text = value
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.text_changed.connect(func(text: String):
		_props[name] = _typed(text, type)
		if preview != null:
			preview.mount(_slot, _path, _props))
	row.add_child(field)
	return row


## The literal a usage passes for `prop`, or "" when it passes something this pane cannot
## evaluate.
##
## Read off the usage row's OWN attribute pairs rather than by matching a pattern against the
## joined text: the pairs are already split exactly the way they were written, and a regex over
## the joined string has to re-derive a split the projection has already done correctly.
func _seeded_literal(pairs: PackedStringArray, prop: String) -> String:
	for pair in pairs:
		var text := str(pair)
		var equals := text.find("=")
		if equals < 0 or text.substr(0, equals) != prop:
			continue
		var raw := text.substr(equals + 1).strip_edges()
		if raw.begins_with("\""):
			return raw.trim_prefix("\"").trim_suffix("\"")
		var inner := raw.trim_prefix("{").trim_suffix("}").strip_edges()
		# An EXPRESSION is not a value. `title={state[0]}` names something only the running
		# component knows, and seeding a knob with the text of it shows code where a value goes.
		if inner.is_empty():
			return ""
		if inner.is_valid_float() or inner in ["true", "false"]:
			return inner
		return ""
	return ""

## The attribute pairs the first usage of this component passes.
func _usage_pairs(file_path: String) -> PackedStringArray:
	if graph == null:
		return PackedStringArray()
	var index: int = graph.index_of(file_path)
	if index < 0:
		return PackedStringArray()
	var title := str(graph.cards[index].title)
	for card in graph.cards:
		if card.file_path == file_path:
			continue
		for row in card.markup:
			if str(row.name) == title:
				return row.attr_pairs
	return PackedStringArray()


## A knob's text, as the type the prop declares.
func _typed(text: String, type: String) -> Variant:
	match type:
		"int":
			return int(text)
		"float":
			return float(text)
		"bool":
			return text.strip_edges().to_lower() == "true"
	return text


## Lists the hook slots the mounted component is holding.
##
## Ported in spirit from the Unity leg's state panel. Read-only here: their fields write back
## through reflection onto a C# object, and the equivalent -- calling a `useState` setter from
## outside a render -- would schedule a re-render of a preview the user is not interacting with,
## which is a different feature wearing the same label. Showing the values is the half that
## answers the question.
func _refresh_state() -> void:
	for child in _state_panel.get_children():
		_state_panel.remove_child(child)
		child.queue_free()
	if preview == null:
		return
	var fiber = preview.mounted_root_fiber()
	var slots := _collect_state(fiber, [])
	if slots.is_empty():
		return
	_state_panel.add_child(Parts.section_heading("state"))
	for entry in slots:
		var spec := entry as Dictionary
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var label := Label.new()
		label.text = str(spec["label"])
		label.add_theme_font_size_override("font_size", NOTE_FONT_SIZE)
		label.add_theme_color_override("font_color", NOTE_COLOR)
		label.custom_minimum_size = Vector2(90, 0)
		row.add_child(label)
		var value := Label.new()
		value.text = str(spec["value"])
		value.add_theme_font_size_override("font_size", NOTE_FONT_SIZE)
		value.clip_text = true
		row.add_child(value)
		_state_panel.add_child(row)


## Walks the committed tree and collects every state slot it finds, depth first.
func _collect_state(fiber, out: Array) -> Array:
	if fiber == null or out.size() >= STATE_LIMIT:
		return out
	var state = fiber.get("state")
	if state != null:
		var hooks = state.get("hooks")
		if hooks is Array:
			for i in range((hooks as Array).size()):
				var slot = (hooks as Array)[i]
				if not (slot is Dictionary) or str((slot as Dictionary).get("kind", "")) != "state":
					continue
				out.append({
					"label": "%s #%d" % [str(fiber.get("type")), i],
					"value": var_to_str((slot as Dictionary).get("value")),
				})
	_collect_state(fiber.get("child"), out)
	_collect_state(fiber.get("sibling"), out)
	return out


## How many slots the panel will list. A deep tree has hundreds and the pane is a side column.
const STATE_LIMIT := 12
