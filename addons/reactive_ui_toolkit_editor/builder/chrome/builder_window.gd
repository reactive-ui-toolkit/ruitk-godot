@tool
class_name RuitkBuilderWindow
extends Control
## The builder, assembled: the folder and library panes on the left, the canvas in the middle,
## the source pane on the right, the console along the bottom, and a toolbar over all of it.
##
## THE WINDOW IS THE ONLY THING THAT KNOWS ABOUT ALL THE PARTS. Every pane below it takes a model
## and emits what happened; none of them reaches for another. That is what keeps them testable on
## their own, and it is why the wiring lives in one readable block instead of being spread across
## six files that each know a little about the others.
##
## ONE FUNNEL FOR EVERY CHANGE. A buffer edit from the source pane, a drop on the canvas and a
## replayed undo all go through `apply_edit`, so they produce the same ledger entry, the same
## preview round and the same re-projection. A second path into the model is how two surfaces
## come to disagree about what the file says.
##
## Godot's `PopupMenu` is a real popup with real submenus and correct focus, so the context menus
## here are ordinary menus. The Unity leg builds its own out of a panel layer because a custom
## EditorWindow cannot own a submenu without the child killing its parent -- none of which
## applies here, and inventing a menu system to match would be a cost with no return.

const Workspace = preload("res://addons/reactive_ui_toolkit_editor/builder/document/builder_workspace.gd")
const Module = preload("res://addons/reactive_ui_toolkit_editor/builder/document/builder_module.gd")
const Paths = preload("res://addons/reactive_ui_toolkit_editor/builder/document/builder_paths.gd")
const Ledger = preload("res://addons/reactive_ui_toolkit_editor/builder/document/builder_ledger.gd")
const Journal = preload("res://addons/reactive_ui_toolkit_editor/builder/document/builder_journal.gd")
const Service = preload("res://addons/reactive_ui_toolkit_editor/builder/canvas/builder_graph_service.gd")
const Graph = preload("res://addons/reactive_ui_toolkit_editor/builder/canvas/builder_graph.gd")
const CanvasHost = preload("res://addons/reactive_ui_toolkit_editor/builder/canvas/builder_canvas_host.gd")
const CanvasLayout = preload("res://addons/reactive_ui_toolkit_editor/builder/canvas/builder_canvas_layout.gd")
const Preview = preload("res://addons/reactive_ui_toolkit_editor/builder/preview/builder_preview.gd")
const FolderPane = preload("res://addons/reactive_ui_toolkit_editor/builder/chrome/builder_folder_pane.gd")
const LibraryPane = preload("res://addons/reactive_ui_toolkit_editor/builder/chrome/builder_library_pane.gd")
const SourcePane = preload("res://addons/reactive_ui_toolkit_editor/builder/chrome/builder_source_pane.gd")
const Console = preload("res://addons/reactive_ui_toolkit_editor/builder/chrome/builder_console.gd")
const InlineEditor = preload("res://addons/reactive_ui_toolkit_editor/builder/chrome/builder_inline_editor.gd")
const Edits = preload("res://addons/reactive_ui_toolkit_editor/builder/edits/builder_edits.gd")
const Drag = preload("res://addons/reactive_ui_toolkit_editor/builder/edits/builder_drag.gd")
const AddonSettings = preload("res://addons/reactive_ui_toolkit_editor/editor/ruitk_editor_settings.gd")
const Parts = preload("res://addons/reactive_ui_toolkit_editor/builder/chrome/builder_chrome_parts.gd")
const PreviewPane = preload("res://addons/reactive_ui_toolkit_editor/builder/chrome/builder_preview_pane.gd")
const Palette = preload("res://addons/reactive_ui_toolkit_editor/builder/canvas/canvas_palette.gd")
const Metrics = preload("res://addons/reactive_ui_toolkit_editor/builder/canvas/builder_canvas_metrics.gd")

## The tree changed in a way the host should know about -- for the plugin's title, or a prompt on
## close.
signal dirty_changed(has_unsaved: bool)

## Menu ids. Named rather than positional, so inserting an item cannot silently re-point another.
enum MenuId { SAVE, ABORT, UNDO, REDO, FIT_VIEW, REVEAL, HISTORY, TRACE, HELP }

## The three detail bands, NAMED. The canvas already had them — as a zoom threshold nobody could
## see, so a user could not tell which band they were in or ask for one. The Unity leg puts them
## on a dropdown, and a named layer is the difference between a level of detail and an accident
## of how far you happened to scroll.
const LAYERS := [
	{ "title": "Layer 1 — Pills", "zoom": 0.34 },
	{ "title": "Layer 2 — Cards", "zoom": 0.80 },
	{ "title": "Layer 3 — Edit", "zoom": 1.20 },
]
enum CardMenuId { OPEN, RENAME, DELETE, REVEAL_CARD }

var workspace: Workspace = null
var ledger := Ledger.new()
var preview := Preview.new()

var graph: Graph = null
var layout: CanvasLayout = null

var _canvas: CanvasHost = null
var _folders: FolderPane = null
var _library: LibraryPane = null
var _source: SourcePane = null
var _console: Console = null
var _inline: InlineEditor = null
var _toolbar: HBoxContainer = null
var _status: Label = null
var _card_menu: PopupMenu = null
var _new_menu: PopupMenu = null
var _canvas_menu: PopupMenu = null
var _preview_pane: PreviewPane = null
var _layers: OptionButton = null
var _history_menu: PopupMenu = null
var _hint: Label = null
var _syncing_layer := false
var _empty_state: Control = null

var _focus_path := ""
var _menu_target := ""
var _menu_world := Vector2.ZERO
var _was_dirty := false


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_wire()


func _exit_tree() -> void:
	preview.teardown()


## The builder drives its own idle work: the debounced preview round and the crash journal.
##
## Here rather than in the host that opened it, because the cadence is the builder's own business
## and a host that forgot to pump it would leave the preview permanently one edit behind -- with
## nothing to show for it, since a missed tick looks exactly like an edit that changed nothing.
func _process(_delta: float) -> void:
	tick()


# ── Assembly ─────────────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(column)

	column.add_child(_build_toolbar())

	var body := HSplitContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)

	var left := VSplitContainer.new()
	left.custom_minimum_size = Vector2(240, 0)
	body.add_child(left)
	_folders = FolderPane.new()
	left.add_child(_folders)
	_library = LibraryPane.new()
	left.add_child(_library)

	var middle := VSplitContainer.new()
	middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(middle)

	# The canvas and the one floating inline editor share a layer, so the editor can sit over a
	# card without the canvas clipping it away.
	var canvas_layer := Control.new()
	canvas_layer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas_layer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas_layer.custom_minimum_size = Vector2(0, 420)
	middle.add_child(canvas_layer)
	_canvas = CanvasHost.new()
	canvas_layer.add_child(_canvas)
	_inline = InlineEditor.new()
	canvas_layer.add_child(_inline)

	# The onboarding panel sits on the canvas layer and hides itself the moment a tree opens.
	# A builder whose empty state is an empty grey rectangle has told a first-time user nothing:
	# not what it is, not that nothing is written until Save, and not that the four things they
	# might want to make are one click away.
	_empty_state = _build_empty_state()
	canvas_layer.add_child(_empty_state)

	# The console gets a FLOOR, not half the column. It carries diagnostics, which are usually one
	# line and occasionally many, and a split that opens at the middle gave a one-line console the
	# same room as the canvas — the surface the whole window exists to show.
	_console = Console.new()
	_console.custom_minimum_size = Vector2(0, 96)
	middle.add_child(_console)
	middle.split_offset = 10000   # clamped to the canvas's floor: console at its minimum

	# The right column is TWO panes, the way the Unity leg has it: what the component looks like
	# above what it says. Source alone answers "what did I write"; only the preview answers "what
	# did I build", and that is the question a visual builder is for.
	var right := VSplitContainer.new()
	right.custom_minimum_size = Vector2(380, 0)
	body.add_child(right)
	_preview_pane = PreviewPane.new()
	_preview_pane.preview = preview
	right.add_child(_preview_pane)
	_source = SourcePane.new()
	right.add_child(_source)

	_hint = Parts.hint_bar(PackedStringArray([
		"Wheel: zoom",
		"Drag Library items onto rows (top=before, bottom=after, middle=inside)",
		"Drag rows to reorder",
		"Right-click rows / cards / canvas to edit, delete, create",
		"Click attributes and badges to edit in place",
		"Source pane: edits apply as you type",
		"Drag splitters to resize",
	]))
	column.add_child(_hint)

	# A card's menu leads with CREATE, because the commonest thing to want next to a component is
	# another module related to it -- and a create action reached from the card carries where it
	# goes with it: a component becomes a CHILD of the one clicked, the companions land BESIDE it.
	_new_menu = PopupMenu.new()
	_new_menu.name = "New"
	_new_menu.add_item("New component            child", Module.Kind.COMPONENT)
	_new_menu.add_item("New style module        beside", Module.Kind.STYLE)
	_new_menu.add_item("New hook module      beside", Module.Kind.HOOK)
	_new_menu.add_item("New util module         beside", Module.Kind.UTIL)
	_new_menu.id_pressed.connect(_on_card_new)

	_card_menu = PopupMenu.new()
	_card_menu.add_child(_new_menu)
	_card_menu.add_submenu_item("New", "New")
	_card_menu.add_separator()
	_card_menu.add_item("Open", CardMenuId.OPEN)
	_card_menu.add_item("Rename...", CardMenuId.RENAME)
	_card_menu.add_separator()
	_card_menu.add_item("Delete", CardMenuId.DELETE)
	add_child(_card_menu)

	_canvas_menu = PopupMenu.new()
	_canvas_menu.add_item("Fit to view", MenuId.FIT_VIEW)
	add_child(_canvas_menu)

	_history_menu = PopupMenu.new()
	_history_menu.add_item("Undo", MenuId.UNDO)
	_history_menu.add_item("Redo", MenuId.REDO)
	add_child(_history_menu)


## The "nothing open yet" panel: what this is, what it will not do behind your back, and the four
## things you can start.
func _build_empty_state() -> Control:
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_PASS

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	centre.add_child(column)

	var heading := Label.new()
	heading.text = "Start a UI"
	heading.add_theme_font_size_override("font_size", 26)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(heading)

	var subtitle := Label.new()
	subtitle.text = "Nothing is written to disk until you press Save."
	subtitle.add_theme_color_override("font_color", Parts.TITLE_COLOR)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(subtitle)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	for entry in [
		{ "label": "New component", "kind": Module.Kind.COMPONENT },
		{ "label": "New style module", "kind": Module.Kind.STYLE },
		{ "label": "New hook module", "kind": Module.Kind.HOOK },
		{ "label": "New util module", "kind": Module.Kind.UTIL },
	]:
		var spec := entry as Dictionary
		var button := Button.new()
		button.text = str(spec["label"])
		var kind := int(spec["kind"])
		button.pressed.connect(func(): create_module(kind))
		buttons.add_child(button)
	column.add_child(buttons)

	var hint := Label.new()
	hint.text = "...or double-click a .guitkx file in the FileSystem dock to edit an existing tree."
	hint.add_theme_font_size_override("font_size", Parts.HINT_FONT_SIZE)
	hint.add_theme_color_override("font_color", Parts.HINT_COLOR)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(hint)
	return centre


## The header: what tree is open, which layer it is drawn at, the commands, and the legend that
## makes the canvas's colours mean something.
func _build_toolbar() -> HBoxContainer:
	_toolbar = HBoxContainer.new()
	_toolbar.add_theme_constant_override("separation", 6)

	var title := Label.new()
	title.text = "RUITK Visual Editor"
	title.add_theme_color_override("font_color", Palette.kind_tint(0))
	_toolbar.add_child(title)

	_status = Label.new()
	_status.add_theme_font_size_override("font_size", Parts.TITLE_FONT_SIZE)
	_status.add_theme_color_override("font_color", Parts.TITLE_COLOR)
	_toolbar.add_child(_status)

	_layers = OptionButton.new()
	for layer in LAYERS:
		_layers.add_item(str((layer as Dictionary)["title"]))
	_layers.selected = 2
	_layers.item_selected.connect(_on_layer_chosen)
	_toolbar.add_child(_layers)

	_toolbar.add_child(VSeparator.new())
	_toolbar.add_child(_tool_button("History", MenuId.HISTORY))
	_toolbar.add_child(_tool_button("Trace", MenuId.TRACE))
	_toolbar.add_child(_tool_button("? How to drive it", MenuId.HELP))
	_toolbar.add_child(VSeparator.new())
	_toolbar.add_child(_tool_button("Save", MenuId.SAVE))
	_toolbar.add_child(_tool_button("Abort", MenuId.ABORT))

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_toolbar.add_child(spacer)

	# The legend, and it is not decoration: the canvas says what a module IS with a colour, and a
	# colour with no key is a colour the reader has to reverse-engineer from the filenames.
	var legend := HBoxContainer.new()
	legend.add_theme_constant_override("separation", 12)
	legend.add_child(Parts.legend_entry("component", Palette.kind_tint(Module.Kind.COMPONENT)))
	legend.add_child(Parts.legend_entry("hook module", Palette.kind_tint(Module.Kind.HOOK)))
	legend.add_child(Parts.legend_entry("style module", Palette.kind_tint(Module.Kind.STYLE)))
	legend.add_child(Parts.legend_entry("usage edge", Palette.edge_component()))
	_toolbar.add_child(legend)
	return _toolbar


## Layer chosen from the dropdown: the canvas moves to that band's zoom, about its own centre.
func _on_layer_chosen(index: int) -> void:
	if _syncing_layer or _canvas == null or index < 0 or index >= LAYERS.size():
		return
	var want := float((LAYERS[index] as Dictionary)["zoom"])
	var centre: Vector2 = _canvas.size * 0.5
	_canvas.set_camera(Metrics.zoom_about(_canvas.camera, _canvas.zoom, want, centre), want)


## Dropdown follows the zoom, because the zoom can change without it — a wheel, a fit, a restored
## layout. A selector that only ever leads and never follows starts lying on the first scroll.
func _sync_layer_selector() -> void:
	if _layers == null or _canvas == null:
		return
	var band := int(Metrics.lod_of(_canvas.zoom))
	if _layers.selected == band:
		return
	_syncing_layer = true
	_layers.selected = band
	_syncing_layer = false


func _tool_button(label: String, id: int) -> Button:
	var button := Button.new()
	button.text = label
	button.pressed.connect(func(): run_command(id))
	button.set_meta("command", id)
	return button


func _wire() -> void:
	_folders.module_selected.connect(select_module)
	_folders.module_activated.connect(func(path: String):
		select_module(path)
		_canvas.select_card(graph.index_of(path) if graph != null else -1))
	_folders.module_context_requested.connect(func(path: String, _at: Vector2):
		_open_card_menu(path, get_global_mouse_position()))

	_canvas.card_selected.connect(_on_card_selected)
	_canvas.card_add_requested.connect(_on_card_add)
	_canvas.camera_changed.connect(_on_camera_changed)
	_canvas.camera_changed.connect(func(_c: Vector2, _z: float): _sync_layer_selector())
	_canvas.card_context_requested.connect(func(index: int, world: Vector2):
		if graph == null or index < 0 or index >= graph.cards.size():
			return
		_menu_world = world
		_open_card_menu(graph.cards[index].file_path, get_global_mouse_position()))
	_canvas.canvas_context_requested.connect(func(world: Vector2):
		_menu_world = world
		_canvas_menu.position = Vector2i(get_global_mouse_position())
		_canvas_menu.popup())

	_library.create_requested.connect(create_module)
	_source.buffer_edited.connect(_on_buffer_edited)
	_console.location_activated.connect(select_module)
	_card_menu.id_pressed.connect(_on_card_menu)
	_canvas_menu.id_pressed.connect(run_command)
	ledger.changed.connect(_refresh_status)
	preview.compile_finished.connect(func(_p: String, _ok: bool, _e: String):
		_refresh_status()
		# The preview re-renders on the BUILD, not on the keystroke: mounting a script that has not
		# recompiled yet just re-mounts the one already showing.
		if _preview_pane != null and not _preview_pane.path().is_empty():
			_preview_pane.show_module(_preview_pane.path()))
	_history_menu.id_pressed.connect(run_command)


# ── Opening ──────────────────────────────────────────────────────────────────────────

## Opens the tree the given module belongs to.
func open_tree(focus_path: String) -> void:
	if workspace == null:
		workspace = Workspace.new()
	# On open, not only on teardown: a crashed editor leaves a mirror behind, and compiling
	# against a shadow tree is worse than compiling against nothing.
	Preview.clear_scratch()
	workspace.format_on_save = AddonSettings.is_enabled(AddonSettings.KEY_FORMAT_ON_SAVE)
	workspace.load_tree(focus_path)
	preview.workspace = workspace
	ledger.clear()
	ledger.id_of = func(path: String) -> String:
		var module := workspace.try_get(path)
		return module.id if module != null else ""
	_focus_path = Paths.canon(focus_path)
	reproject()
	select_module(_focus_path)
	if graph != null:
		_canvas.select_card(graph.index_of(_focus_path))


## Rebuilds the canvas model from the workspace and re-applies the saved layout.
##
## The layout is applied and then TOPPED UP: what it already knows keeps its slot, and only a
## module it has never seen takes a seeded one. Re-seeding everything would move every card the
## user has ever dragged the moment one module is added.
## Whether the onboarding panel should be on screen: only when there is genuinely nothing open.
func _sync_empty_state() -> void:
	if _empty_state == null:
		return
	_empty_state.visible = workspace == null or workspace.modules().is_empty()


func reproject() -> void:
	if workspace == null:
		return
	graph = Service.project(workspace.modules(), _focus_path)
	layout = CanvasLayout.for_graph(graph)
	layout.apply_to(graph)
	layout.adopt_unplaced(graph)
	if layout.zoom > 0.0:
		_canvas.camera = layout.camera
		_canvas.zoom = layout.zoom
	_canvas.show_graph(graph)
	_sync_empty_state()
	_folders.workspace = workspace
	_folders.rebuild()
	_library.graph = graph
	_library.rebuild()
	_refresh_status()


# ── The one funnel ───────────────────────────────────────────────────────────────────

## EVERY change to a buffer goes through here: the source pane, a canvas gesture, a replayed
## undo. One entry means one ledger record, one preview round and one re-projection per change,
## whatever produced it.
func apply_edit(file_path: String, after: String, description: String) -> bool:
	if workspace == null:
		return false
	var module := workspace.try_get(file_path)
	if module == null or module.read_only:
		return false
	var before := module.buffer_text
	if before == after:
		return false
	if not workspace.apply_edit(file_path, after):
		return false
	ledger.begin(description)
	ledger.record(file_path, before, after)
	ledger.end()
	_after_model_change(file_path)
	return true


## Re-projects the one card that changed, refreshes the panes, and asks for a preview round.
##
## The card is re-populated in place rather than the whole graph being rebuilt: rebuilding would
## discard every card's measured height and re-seed the layout, so a keystroke would visibly
## reshuffle the canvas.
func _after_model_change(file_path: String) -> void:
	if graph != null:
		var index := graph.index_of(file_path)
		if index >= 0:
			var module := workspace.try_get(file_path)
			if module != null:
				Service.populate_card(graph.cards[index], module.buffer_text)
				Service.refresh_edges_for(graph, index)
		_canvas.show_graph(graph)
	_folders.rebuild()
	_source.refresh_from_model()
	preview.request_refresh()
	_refresh_status()


func _on_buffer_edited(file_path: String, before: String, after: String) -> void:
	# The source pane has already written the buffer, so the funnel records rather than re-applies.
	ledger.record_typing(file_path, before, after)
	_after_model_change(file_path)


# ── Preview ──────────────────────────────────────────────────────────────────────────

## Runs a preview round if the debounce has settled, and journals unsaved work on its own
## cadence. Called from the host's idle tick.
func tick() -> void:
	_journal_tick()
	if not preview.is_due():
		return
	var summary = preview.compile_dirty(_focus_path)
	if summary != null:
		_console.report(summary)
	_refresh_status()


## How often unsaved work is written to the crash journal, in milliseconds.
##
## On a TIMER, not on every change: the journal is the whole tree serialised, and writing it per
## keystroke would put a file write in the typing path. Five seconds is the most work a crash can
## cost, which against losing a whole session is the trade worth making.
const JOURNAL_INTERVAL_MSEC := 5000

var _journalled_at := 0


func _journal_tick() -> void:
	if workspace == null or not workspace.has_unsaved_changes():
		return
	var now := Time.get_ticks_msec()
	if now - _journalled_at < JOURNAL_INTERVAL_MSEC:
		return
	_journalled_at = now
	Journal.capture(workspace, Time.get_datetime_string_from_system(true))


## What a crashed session left behind, or {} -- { modules, saved_at }.
##
## The journal exists ONLY while there is unsaved work, so the file being there means exactly one
## thing and the offer needs no other evidence to be sure it is not noise.
func pending_recovery() -> Dictionary:
	return Journal.peek()


## Takes the recovered tree. The caller asks first: restoring over an open tree replaces it.
func restore_recovery() -> bool:
	if workspace == null or not Journal.try_restore(workspace):
		return false
	reproject()
	_source.refresh_from_model()
	preview.request_refresh()
	return true


func discard_recovery() -> void:
	Journal.clear()


# ── Commands ─────────────────────────────────────────────────────────────────────────

func run_command(id: int) -> void:
	match id:
		MenuId.HISTORY:
			# The ledger, as a menu. Undo and Redo are the whole of it today; the entries they
			# would walk are already named in `ledger.entries`, which is what a fuller list draws from.
			_history_menu.position = Vector2i(get_screen_position() + Vector2(0, 32))
			_history_menu.popup()
			return
		MenuId.TRACE:
			_console.trace(workspace, ledger, preview)
			return
		MenuId.HELP:
			_console.show_help()
			return
	match id:
		MenuId.SAVE:
			save()
		MenuId.ABORT:
			abort()
		MenuId.UNDO:
			undo()
		MenuId.REDO:
			redo()
		MenuId.FIT_VIEW:
			_canvas.fit_to_view()


## A card's "+" was used. Turns it into ONE edit through the funnel, like every other gesture.
##
## The inserted text is a STARTING POINT, not a prompt: a hook chip that opened a dialog asking
## which hook, with what arguments, before it would put anything in the file is slower than
## typing the line. It lands as `useState(null)` and the user edits it where it now is.
func _on_card_add(index: int, what: String) -> void:
	if graph == null or workspace == null or index < 0 or index >= graph.cards.size():
		return
	var card = graph.cards[index]
	var module := workspace.try_get(card.file_path)
	if module == null or module.read_only:
		return
	var before := module.buffer_text
	var after := before
	var description := ""
	match what:
		"hook":
			after = Edits.insert_setup_line(before, card, "var state = useState(null)")
			description = "Add a hook to %s" % card.title
		"code":
			after = Edits.insert_setup_line(before, card, "# ...")
			description = "Add a setup line to %s" % card.title
		"style", "entry":
			var export_name := str(card.exports[0]) if not card.exports.is_empty() else ""
			if export_name.is_empty():
				return
			after = Edits.insert_style_entry(before, export_name, "bg_color", "Color(0.2, 0.2, 0.24)")
			description = "Add a style entry to %s" % card.title
		_:
			return
	if after != before:
		apply_edit(card.file_path, after, description)


## Create, from a card's own menu: the clicked module is the anchor, so the new one lands in its
## folder and -- for a component -- is imported by it, which is what "child" means here.
func _on_card_new(kind: int) -> void:
	if _menu_target.is_empty():
		return
	var previous := _focus_path
	_focus_path = _menu_target
	var created := create_module(kind)
	if created.is_empty():
		_focus_path = previous


## Creates a module of `kind` beside the focus, opens it, and points every surface at it.
##
## THROUGH THE WORKSPACE, like everything else: the module lands in the tree in memory with a
## template buffer and nothing is written until Save, so creating one and thinking better of it
## costs a Ctrl+Z rather than a file on disk to go and delete.
func create_module(kind: int) -> String:
	if workspace == null:
		return ""
	var folder := _focus_path.get_base_dir()
	if folder.is_empty():
		return ""
	var base := _unused_name(folder, kind)
	var path := folder.path_join(base + Module.suffix_for(kind))
	var module := workspace.create_new(path, Edits.template_for(kind, base))
	if module == null:
		return ""
	ledger.record_creation(path)
	reproject()
	select_module(path)
	preview.request_refresh()
	return path


## A name nothing in the folder is using yet -- "NewComponent", then "NewComponent2", and so on.
func _unused_name(folder: String, kind: int) -> String:
	var stem := Module.default_name_for(kind)
	var attempt := stem
	var n := 1
	while workspace.try_get(folder.path_join(attempt + Module.suffix_for(kind))) != null:
		n += 1
		attempt = "%s%d" % [stem, n]
	return attempt


## Writes the tree.
##
## A BLANK module is not written and does not block the save: it stays pending, and the console
## says so, because it is almost always a module someone created and then thought better of.
## Deleting it is the user's call, and refusing the whole save over it would hold every other
## change hostage to a decision about one empty file.
func save() -> int:
	if workspace == null:
		return 0
	for blank in workspace.blank_modules():
		_console.add_diagnostics(blank.file_path(), [{
			"code": "", "severity": Console.SEVERITY_WARNING, "line": -1,
			"message": "empty, so it was not written -- delete it, or give it something to hold",
		}])
	var written := workspace.save_all()
	# Cleared HERE, not on a clean tree: the journal being there has to mean exactly one thing --
	# work existed that never reached disk -- or the recovery offer becomes noise.
	Journal.clear()
	_capture_layout()
	_folders.rebuild()
	_refresh_status()
	return written


func abort() -> int:
	if workspace == null:
		return 0
	var reverted := workspace.abort_all()
	ledger.clear()
	Journal.clear()
	reproject()
	_source.refresh_from_model()
	return reverted


## Walks one ledger entry back. Every change in it, or none -- a gesture that touched two files is
## one action, and undoing it file by file leaves a state the user never authored.
func undo() -> bool:
	var entry := ledger.undo()
	if entry == null:
		return false
	ledger.suppress(func(): _replay(entry, true))
	return true


func redo() -> bool:
	var entry := ledger.redo()
	if entry == null:
		return false
	ledger.suppress(func(): _replay(entry, false))
	return true


func _replay(entry, reverse: bool) -> void:
	var changes: Array = entry.changes.duplicate()
	if reverse:
		changes.reverse()
	for change in changes:
		_replay_change(change, reverse)
	reproject()
	_source.refresh_from_model()
	preview.request_refresh()


func _replay_change(change, reverse: bool) -> void:
	# Resolved by IDENTITY first: an entry outlives the path it was recorded against, and a
	# replay that looked the module up by path would write to a name nothing answers to.
	var module := workspace.by_id(change.module_id)
	var path: String = module.file_path() if module != null else change.file_path
	match change.kind:
		Ledger.ChangeKind.EDIT:
			workspace.apply_edit(path, change.before if reverse else change.after)
		Ledger.ChangeKind.CREATION:
			if reverse:
				workspace.delete(path)
			elif module == null:
				workspace.create_new(change.file_path, "")
		Ledger.ChangeKind.DELETION:
			if reverse:
				workspace.restore(change.removed)
			else:
				workspace.delete(path)
		Ledger.ChangeKind.MOVE:
			workspace.move_to_path(change.after if reverse else change.before,
				change.before if reverse else change.after)


func _capture_layout() -> void:
	if layout == null or graph == null:
		return
	layout.capture_from(graph, _canvas.camera, _canvas.zoom)
	layout.save(Time.get_datetime_string_from_system(true))


# ── Reactions ────────────────────────────────────────────────────────────────────────

## The focus moved. Every surface follows it, INCLUDING the one that asked -- which is why this
## is re-entrancy guarded: the folder pane announces a selection, this points the folder pane at
## it, and the pane announces it again. Two surfaces that each echo the other never stop.
func select_module(file_path: String) -> void:
	var wanted := Paths.canon(file_path)
	if _choosing or wanted.is_empty():
		return
	_choosing = true
	_focus_path = wanted
	_source.workspace = workspace
	_source.show_module(_focus_path)
	_folders.select_path(_focus_path)
	if _preview_pane != null:
		# BUILD IT IF IT IS NOT BUILT. A round compiles the focus's closure, and the module a user
		# selects next is often outside the closure the last one had -- so the pane would sit on
		# "select a component to see it rendered" while a component was selected, until some later
		# edit happened to rebuild it. Selecting IS the request.
		if preview.built_script(_focus_path) == null:
			preview.compile_dirty(_focus_path)
		_preview_pane.show_module(_focus_path)
	preview.request_refresh()
	_refresh_status()
	_choosing = false


var _choosing := false


func _on_card_selected(index: int) -> void:
	if graph == null or index < 0 or index >= graph.cards.size():
		return
	select_module(graph.cards[index].file_path)


func _on_camera_changed(camera: Vector2, zoom: float) -> void:
	if layout == null:
		return
	layout.camera = camera
	layout.zoom = zoom


func _open_card_menu(file_path: String, at: Vector2) -> void:
	_menu_target = file_path
	var module := workspace.try_get(file_path) if workspace != null else null
	_card_menu.set_item_disabled(_card_menu.get_item_index(CardMenuId.DELETE),
		module == null or module.read_only)
	_card_menu.set_item_disabled(_card_menu.get_item_index(CardMenuId.RENAME),
		module == null or module.read_only)
	# The menu says WHICH module it is about. "Delete" over a canvas of five cards is a question
	# the user has to answer from memory of where they right-clicked.
	var shown := file_path.get_file()
	_card_menu.set_item_text(_card_menu.get_item_index(CardMenuId.RENAME), "Rename %s..." % shown)
	_card_menu.set_item_text(_card_menu.get_item_index(CardMenuId.DELETE), "Delete %s" % shown)
	_card_menu.position = Vector2i(at)
	_card_menu.popup()


func _on_card_menu(id: int) -> void:
	match id:
		CardMenuId.OPEN:
			select_module(_menu_target)
		CardMenuId.DELETE:
			delete_module(_menu_target)
		CardMenuId.RENAME:
			# The rename prompt itself is a chrome affordance; the model operation it drives is
			# `move_to_path`, which is what the ledger replays.
			select_module(_menu_target)


# ── Gestures ─────────────────────────────────────────────────────────────────────────

## Drops a library entry onto the canvas at a screen point.
##
## The target is resolved from the POINTER at the moment of the drop, against the graph as it is
## then -- never from rows captured when the drag began. The canvas re-renders while a drag is in
## flight, because the preview recompiles as the user works.
func drop_library_entry(kind: String, name: String, at: Vector2) -> bool:
	var hit := Drag.resolve(graph, at, _canvas.camera, _canvas.zoom)
	if not bool(hit["found"]):
		return false
	var card: Graph.Card = hit["card"]
	if kind == LibraryPane.ENTRY_HOOK:
		return apply_edit(card.file_path,
			Edits.insert_setup_line(_buffer_of(card.file_path), card, "var _ = %s()" % name),
			"add %s" % name)

	var row: Graph.Line = hit["row"]
	if row == null or row.kind == Graph.LineKind.IMPORT:
		return false
	var placement: Edits.Placement = hit["placement"]
	var verdict := Edits.can_place(card, row, placement)
	if not bool(verdict["ok"]):
		_console.add_diagnostics(card.file_path,
			[{ "code": "", "severity": Console.SEVERITY_WARNING, "message": str(verdict["reason"]), "line": -1 }])
		return false
	return apply_edit(card.file_path,
		Edits.insert(_buffer_of(card.file_path), card, row, Drag.markup_for(name), placement),
		"add <%s>" % name)


## Re-parents a markup row. The gesture the Unity leg lists as unreliable, and the one this whole
## drag design exists for: both ends are re-resolved against the current graph.
func drop_row(drag: Drag, at: Vector2) -> bool:
	var card := drag.source_card(graph)
	var row := drag.source_row(graph)
	if card == null or row == null:
		return false
	var hit := Drag.resolve(graph, at, _canvas.camera, _canvas.zoom)
	if not bool(hit["found"]) or hit["card"] != card:
		# A row can only move within its own module: moving it to another would mean deciding
		# what to do about every name its subtree references, which is a different operation.
		return false
	var target: Graph.Line = hit["row"]
	if target == null or target == row:
		return false
	return apply_edit(card.file_path,
		Edits.move(_buffer_of(card.file_path), card, row, target, hit["placement"]),
		"move <%s>" % row.name)


## Drops a MODULE onto an element: a style module applies itself, anything else adds an import.
##
## This is the whole style-application gesture. `style={ Name }` plus the import it needs -- two
## edits, one action, so one undo takes both back. A style applied without its import is a file
## that does not compile, and an import added without the use is GUITKX2304.
func drop_module(module_path: String, at: Vector2) -> bool:
	var hit := Drag.resolve(graph, at, _canvas.camera, _canvas.zoom)
	if not bool(hit["found"]):
		return false
	var card: Graph.Card = hit["card"]
	if Paths.same(card.file_path, module_path):
		return false
	var source_card := graph.card_of(module_path)
	if source_card == null or source_card.exports.is_empty():
		return false
	var export_name := str(source_card.exports[0])

	var row: Graph.Line = hit["row"]
	var text := _buffer_of(card.file_path)
	var described := ""
	if source_card.kind == Module.Kind.STYLE and row != null \
			and (row.kind == Graph.LineKind.ELEMENT or row.kind == Graph.LineKind.COMPONENT):
		text = Edits.set_attribute(text, row, "style", export_name, false)
		described = "style <%s>" % row.name
	else:
		described = "import %s" % export_name
	text = Edits.ensure_import(text, card.file_path, module_path, PackedStringArray([export_name]))
	return apply_edit(card.file_path, text, described)


func _buffer_of(file_path: String) -> String:
	var module := workspace.try_get(file_path) if workspace != null else null
	return module.buffer_text if module != null else ""


## Deletes a module: it leaves the tree, and the ledger holds the module itself so undo puts the
## SAME one back -- its identity, its buffer and its disk path.
func delete_module(file_path: String) -> bool:
	if workspace == null:
		return false
	var module := workspace.try_get(file_path)
	if module == null or module.read_only:
		return false
	if not workspace.delete(file_path):
		return false
	ledger.record_deletion(file_path, module)
	reproject()
	_source.refresh_from_model()
	preview.request_refresh()
	return true


func _refresh_status() -> void:
	var dirty := workspace != null and workspace.has_unsaved_changes()
	# "RightSide.guitkx | 5 file(s), 0 dirty" — WHAT IS OPEN first, then the shape of the tree.
	# A count with no filename tells a user how much work is loaded but not which of it they are
	# looking at, and the builder's whole left column is about which one that is.
	if workspace == null:
		_status.text = "no tree open — open a .guitkx to start"
		return
	var dirty_count := 0
	for module in workspace.modules():
		if module.is_dirty():
			dirty_count += 1
	var open_name := _focus_path.get_file() if not _focus_path.is_empty() else "no module selected"
	_status.text = "%s  |  %d file(s), %d dirty" % [open_name, workspace.modules().size(), dirty_count]
	for button in _toolbar.get_children():
		if not button.has_meta("command"):
			continue
		match int(button.get_meta("command")):
			MenuId.UNDO:
				(button as Button).disabled = not ledger.can_undo()
			MenuId.REDO:
				(button as Button).disabled = not ledger.can_redo()
			MenuId.SAVE, MenuId.ABORT:
				(button as Button).disabled = not dirty
	if dirty != _was_dirty:
		_was_dirty = dirty
		dirty_changed.emit(dirty)


# ── Accessors, for the plugin and the tests ──────────────────────────────────────────

func canvas() -> CanvasHost:
	return _canvas


func folder_pane() -> FolderPane:
	return _folders


func library_pane() -> LibraryPane:
	return _library


func source_pane() -> SourcePane:
	return _source


func console() -> Console:
	return _console


func inline_editor() -> InlineEditor:
	return _inline


func focus_path() -> String:
	return _focus_path
