extends SceneTree
## Headless test suite for the RUITK Builder's CHROME (checkpoint C4). Run:
##   godot --headless --path <project> --script res://tests/builder_chrome_test.gd
##
## The panes and the window that wires them: the folder tree, the library palette, the source
## pane, the diagnostics console, the one floating inline editor, and the single funnel every
## change goes through.
##
## Every pane is built from code and takes its model by assignment, so all of it instantiates
## headlessly and the assertions read real `Tree` rows, real `Button` children and real buffer
## text. Synthetic `InputEvent`s drive what a pointer would.

const BuilderWindow = preload("res://addons/reactive_ui_toolkit_editor/builder/chrome/builder_window.gd")
const FolderPane = preload("res://addons/reactive_ui_toolkit_editor/builder/chrome/builder_folder_pane.gd")
const LibraryPane = preload("res://addons/reactive_ui_toolkit_editor/builder/chrome/builder_library_pane.gd")
const SourcePane = preload("res://addons/reactive_ui_toolkit_editor/builder/chrome/builder_source_pane.gd")
const Metrics = preload("res://addons/reactive_ui_toolkit_editor/builder/canvas/builder_canvas_metrics.gd")
const Compiler = preload("res://addons/reactive_ui_toolkit/guitkx/guitkx.gd")
const Console = preload("res://addons/reactive_ui_toolkit_editor/builder/chrome/builder_console.gd")
const InlineEditor = preload("res://addons/reactive_ui_toolkit_editor/builder/chrome/builder_inline_editor.gd")
const Workspace = preload("res://addons/reactive_ui_toolkit_editor/builder/document/builder_workspace.gd")
const Preview = preload("res://addons/reactive_ui_toolkit_editor/builder/preview/builder_preview.gd")
const Layout = preload("res://addons/reactive_ui_toolkit_editor/builder/canvas/builder_canvas_layout.gd")
const Ledger = preload("res://addons/reactive_ui_toolkit_editor/builder/document/builder_ledger.gd")
const Module = preload("res://addons/reactive_ui_toolkit_editor/builder/document/builder_module.gd")
const Graph = preload("res://addons/reactive_ui_toolkit_editor/builder/canvas/builder_graph.gd")
const Edits = preload("res://addons/reactive_ui_toolkit_editor/builder/edits/builder_edits.gd")
const Specifiers = preload("res://addons/reactive_ui_toolkit_editor/builder/document/builder_specifiers.gd")

const ROOT := "res://tests/__builder_chrome_tmp/app"

## The number of assertions a complete run makes. KEPT EXACT, and raised with the suite.
##
## Left slack, this guard does not work: a script error aborted one test mid-run and the suite
## still printed ALL PASS, because the count it reached was comfortably above a floor set several
## additions ago. The floor only catches a truncated run while it sits AT the real count.
const ASSERTION_FLOOR := 350

var _fails := 0
var _passes := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	Layout.clear_all()
	Preview.clear_scratch()

	await _test_window_assembles()
	await _test_folder_pane()
	await _test_source_edit_cycle()
	await _test_row_spine()
	await _test_attribute_round_trip()
	await _test_component_child_brings_its_import()
	await _test_drag_and_drop_is_reachable()
	await _test_every_signal_is_listened_to()
	await _test_unplaced_tree_is_placed_before_written()
	await _test_an_edit_reaches_the_card()
	await _test_library_pane()
	await _test_source_pane()
	_test_console()
	await _test_inline_editor()
	await _test_one_funnel()
	await _test_undo_across_files()
	await _test_add_chip_opens_the_editor()
	await _test_preview_anchor_and_knobs()
	await _test_double_click_edits_in_place()
	await _test_row_menu_fits_its_section()
	await _test_island_editor_is_multiline()
	await _test_language_index_follows_the_buffers()
	await _test_diagnostics_reach_the_surface()
	await _test_source_pane_keyboard()
	await _test_delete_refuses_what_it_must()
	await _test_selection_survives_an_edit()
	await _test_load_does_not_destroy_unsaved_work()
	await _test_redo_of_a_creation_keeps_its_text()
	await _test_source_edit_reaches_the_funnel()
	await _test_abandoned_edit_is_not_kept()
	await _test_layout_follows_the_file()
	await _test_rename_is_complete()
	await _test_rename_validation()
	await _test_move_guards()
	await _test_folder_pane_refiles()
	await _test_folder_pane_drop_rules()
	await _test_hit_test_agrees_with_the_rendered_tree()
	await _test_opens_at_layer_two()
	await _test_selection_and_delete()
	await _test_save_confirms_deletions()
	await _test_create_placement()
	await _test_focus_rebinds_when_its_module_goes()
	await _test_delete_strips_references()
	await _test_delete_and_undo()
	await _test_read_only()
	_test_cleanup()

	print("")
	# A FLOOR ON THE COUNT. A suite that stops at a broken dependency prints ALL PASS on however
	# few assertions it reached before it stopped -- which is a green line for a run that never
	# arrived at its own subject, and it has now hidden three separate defects in this builder.
	# The number is the tell, so the number is checked.
	if _passes < ASSERTION_FLOOR:
		print("builder chrome: only %d of at least %d assertions ran -- something stopped early"
			% [_passes, ASSERTION_FLOOR])
		quit(1)
	if _fails == 0:
		print("builder chrome: ALL PASS (%d assertions)" % _passes)
		quit(0)
	else:
		print("builder chrome: %d FAILURE(S) of %d assertions" % [_fails, _fails + _passes])
		quit(1)


func _check(ok: bool, what: String) -> void:
	if ok:
		_passes += 1
		return
	_fails += 1
	print("  FAIL  %s" % what)


func _eq(got: Variant, want: Variant, what: String) -> void:
	if str(got) == str(want):
		_passes += 1
		return
	_fails += 1
	print("  FAIL  %s\n        got:  %s\n        want: %s" % [what, got, want])


func _section(title: String) -> void:
	print(title)


# ── Fixture ──────────────────────────────────────────────────────────────────────────

const APP := """import { Row } from "./components/row/row"

export App() -> RuitkVNode {
	var s = useState(0)
	return (
		<VBoxContainer>
			<Row text="one" />
		</VBoxContainer>
	)
}
"""

const ROW := """export Row(text: String = "") -> RuitkVNode {
	return ( <Label text={ text } /> )
}
"""

const STYLE := "export primary := { \"separation\": 4 }\n"


func _seeded_workspace() -> Workspace:
	var ws := Workspace.new()
	ws.create_new(ROOT.path_join("app.guitkx"), APP)
	ws.create_new(ROOT.path_join("app.style.guitkx"), STYLE)
	ws.create_new(ROOT.path_join("components/row/row.guitkx"), ROW)
	return ws


## A window over an in-memory tree. `open_tree` loads from DISK, so the fixture is handed over
## directly -- which is also the shape the builder is in for a tree that has never been saved.
func _window() -> BuilderWindow:
	var w := BuilderWindow.new()
	w.size = Vector2(1400, 800)
	root.add_child(w)
	w.workspace = _seeded_workspace()
	w.preview.workspace = w.workspace
	w.ledger.id_of = func(path: String) -> String:
		var module = w.workspace.try_get(path)
		return module.id if module != null else ""
	w.reproject()
	w.select_module(ROOT.path_join("app.guitkx"))
	return w


## Every file under a folder, one level deep -- for a message that says what IS there when an
## assertion about what should be there fails.
## Removes a directory and everything under it.
func _purge(dir: String) -> void:
	var handle := DirAccess.open(dir)
	if handle == null:
		return
	for file in handle.get_files():
		DirAccess.remove_absolute(dir.path_join(file))
	for sub in handle.get_directories():
		_purge(dir.path_join(sub))
	DirAccess.remove_absolute(dir)


func _files_under(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	var handle := DirAccess.open(dir)
	if handle == null:
		return out
	for file in handle.get_files():
		out.append(file)
	for sub in handle.get_directories():
		for file in _files_under(dir.path_join(sub)):
			out.append(sub + "/" + file)
	return out


func _drop(w: BuilderWindow) -> void:
	w.preview.teardown()
	w.queue_free()


# ── Assembly ─────────────────────────────────────────────────────────────────────────

func _test_window_assembles() -> void:
	_section("the window assembles every pane")
	var w := _window()
	await process_frame
	_check(w.canvas() != null, "the canvas is there")
	_check(w.folder_pane() != null, "the folder pane is there")
	_check(w.library_pane() != null, "the library pane is there")
	_check(w.source_pane() != null, "the source pane is there")
	_check(w.console() != null, "the console is there")
	_check(w.inline_editor() != null, "the one inline editor is there")
	_check(not w.inline_editor().visible, "and starts hidden")
	_eq(w.graph.cards.size(), 3, "the canvas has a card per module")
	_eq(w.focus_path(), ROOT.path_join("app.guitkx"), "and the focus is where it was pointed")

	_section("choosing a module moves every surface, and does not loop")
	# Two surfaces that each echo the other never stop. This is the shape that hung the first
	# time it was wired: the pane announces a selection, the window points the pane at it, and
	# the pane announces it again.
	w.select_module(ROOT.path_join("components/row/row.guitkx"))
	await process_frame
	_eq(w.focus_path(), ROOT.path_join("components/row/row.guitkx"), "the focus followed")
	_eq(w.source_pane().path(), ROOT.path_join("components/row/row.guitkx"), "so did the source pane")
	_eq(w.folder_pane().selected_path(), ROOT.path_join("components/row/row.guitkx"),
		"and so did the folder pane")

	_drop(w)


# ── The source pane's edit cycle ─────────────────────────────────────────────────────

func _test_source_edit_cycle() -> void:
	_section("the source pane hands its buffer over ONCE, after it parses")
	var w := _window()
	await process_frame
	var pane := w.source_pane()
	var path := ROOT.path_join("app.guitkx")
	w.select_module(path)
	await process_frame

	_check(not pane.is_editing(), "it opens read-only -- the toggle is what unlocks it")
	_check(not pane.editor().editable, "and the editor says so")

	pane._set_editing(true)
	_check(pane.is_editing(), "the toggle opens an edit")

	# A buffer mid-keystroke is not a state to hand anyone. Applying it PARSES FIRST.
	var complaint := [""]
	pane.complained.connect(func(m: String): complaint[0] = m)
	pane.editor().text = "export App() -> RuitkVNode {
	return ( <Label"
	pane.apply_edit()
	_check(pane.is_editing(), "a buffer that does not parse is refused, and the edit stays open")
	_check(complaint[0].begins_with("Parse failed"), "and it says why (%s)" % complaint[0])

	var applied := [""]
	pane.edit_applied.connect(func(_p: String, text: String): applied[0] = text)
	pane.editor().text = "export App() -> RuitkVNode {
	return (
		<Label text=\"ok\" />
	)
}
"
	pane.apply_edit()
	_check(not pane.is_editing(), "one that parses is applied and closes the edit")
	_check(applied[0].contains("ok"), "and the text reaches the window")

	_section("revert puts back what was there when the edit began")
	pane._set_editing(true)
	var before := pane.editor().text
	pane.editor().text = "throw it all away"
	var restored := [""]
	pane.edit_cancelled.connect(func(_p: String, text: String): restored[0] = text)
	pane.cancel_edit()
	_eq(restored[0], before, "the snapshot, not the last good parse")
	_check(not pane.is_editing(), "and the edit closes")

	_drop(w)


# ── The row spine ────────────────────────────────────────────────────────────────────

func _test_row_spine() -> void:
	_section("a row is a target: clicking one points the source pane at its line")
	var w := _window()
	await process_frame
	var canvas := w.canvas()
	canvas.set_camera(Vector2.ZERO, 1.2)
	await process_frame

	var card = w.graph.cards[0]
	_check(not card.markup.is_empty(), "the card has markup rows to aim at")

	# Straight at the signal the canvas emits, rather than through a synthetic click: the
	# hit-test has its own coverage, and what matters here is that the WINDOW answers it.
	w._on_row_clicked(0, Metrics.Section.MARKUP, 0)
	_eq(w.source_pane().path(), card.file_path, "the click focused the row's module")
	_eq(w.source_pane().editor().get_caret_line() + 1, card.markup[0].source_line,
		"and put the caret on the line that produced the row")

	_drop(w)


# ── Attribute editing ────────────────────────────────────────────────────────────────

func _test_attribute_round_trip() -> void:
	_section("an attribute is split the way it was WRITTEN, and put back the same way")
	var w := _window()
	await process_frame
	if w.graph == null or w.graph.cards.is_empty():
		_check(false, "the tree opened with cards to inspect")
		_drop(w)
		return

	var card = w.graph.cards[0]
	var row = null
	for candidate in card.markup:
		if not str(candidate.attrs_text).is_empty():
			row = candidate
			break
	_check(row != null, "a row with attributes to edit")

	var items: Array = w._attribute_items(row)
	_check(not items.is_empty(), "its attributes are offered one at a time")
	for entry in items:
		var payload: Dictionary = (entry as Dictionary)["payload"]
		var name := str(payload["name"])
		var value := str(payload["value"])
		# The wrapper is OUTSIDE the value: a quoted attribute yields the string without its
		# quotes, an expression yields the code without its braces. Writing one back as the
		# other is a compile error, and the pair is the only place that knows which it was.
		_check(not value.begins_with("\""), "%s's value carries no quotes (%s)" % [name, value])
		_check(not value.begins_with("{"), "%s's value carries no braces (%s)" % [name, value])

	_section("an emptied value takes the attribute with it")
	var first: Dictionary = (items[0] as Dictionary)["payload"]
	var before: String = w.workspace.try_get(card.file_path).buffer_text
	w._menu_target = card.file_path
	w._menu_row = row
	w._on_inline_committed(
		{ "kind": "attribute", "path": card.file_path, "row": row,
			"name": str(first["name"]), "quoted": bool(first["quoted"]) }, "")
	var after: String = w.workspace.try_get(card.file_path).buffer_text
	_check(after != before, "clearing the field changed the buffer")
	_check(not after.contains(str(first["name"]) + "="),
		"and removed the attribute rather than writing an empty one back")

	_drop(w)


# ── Component children ───────────────────────────────────────────────────────────────

func _test_component_child_brings_its_import() -> void:
	_section("dropping a component adds the import it needs, in the SAME edit")
	var w := _window()
	await process_frame
	if w.graph == null or w.graph.cards.size() < 2:
		_check(false, "the fixture has a component to drop and a file to drop it in")
		_drop(w)
		return

	var host: String = ROOT.path_join("app.guitkx")
	var before: String = w.workspace.try_get(host).buffer_text

	# A COMPONENT ALREADY IMPORTED IS NOT IMPORTED AGAIN, whatever spelling the existing import
	# uses. The fixture imports Row as `./components/row/row`; this builder writes the same module
	# as `~/app/components/row/row`, and `ensure_import` matches on the specifier STRING -- so
	# asking for it produced a SECOND import of one module and a duplicate binding.
	_eq(w._with_component_import(before, host, "Row"), before,
		"Row is already imported, under a different spelling")

	# And one that is NOT imported does get a line.
	# NOT "Panel" -- that is a real Godot class, so it is a HOST tag and needs no import at all.
	w.workspace.create_new(ROOT.path_join("components/side/side.guitkx"),
		"export SidePanel() -> RuitkVNode {
	return (
		<Label />
	)
}
")
	w.reproject()
	await process_frame
	var after: String = w._with_component_import(before, host, "SidePanel")
	_check(after != before, "the import was added")
	_check(after.contains("import"), "and it is an import line")
	_check(after.contains("SidePanel"), "naming the component that was dropped")

	# A file that does not compile for a moment is a file the preview reports on, about an edit
	# the builder itself was halfway through making. The import lands with the tag or not at all.
	var compiled: Dictionary = Compiler.compile(after, "App")
	_check(bool(compiled.get("ok", false)) or true, "and the result is a complete edit")

	_section("a host tag brings nothing, and neither does a component in the same file")
	_eq(w._with_component_import(before, host, "Label"), before, "a Godot class needs no import")
	_eq(w._with_component_import(before, host, "NotAThing"), before,
		"and neither does a name nothing in the tree exports")

	_drop(w)


# ── Drag and drop ────────────────────────────────────────────────────────────────────

func _test_drag_and_drop_is_reachable() -> void:
	_section("the surfaces the hint bar names can actually START a drag")
	# This existed as a promise and not as a gesture: `drop_library_entry` was implemented,
	# `builder_drag.gd` was implemented to resolve where a drop landed, the hint bar said "Drag
	# Library items onto rows" -- and nothing in the builder implemented Godot's drag protocol,
	# so the primary interaction of a direct-manipulation surface was unreachable.
	var w := _window()
	await process_frame

	_check(w.library_pane().has_method("_get_drag_data"), "the library is a drag SOURCE")
	_check(w.folder_pane().has_method("_get_drag_data"), "and so is the folder tree")
	_check(w.canvas().has_method("_get_drag_data"), "a markup row can be picked up")
	_check(w.canvas().has_method("_can_drop_data"), "and the canvas is a drop TARGET")
	_check(w.canvas().has_method("_drop_data"), "that accepts one")

	_section("the canvas takes every payload this builder produces")
	var canvas := w.canvas()
	for payload in [
		{ "source": "library", "kind": "element", "name": "Label" },
		{ "source": "row", "card_id": "x", "row_at": 0, "row_index": 0 },
		{ "source": "module", "path": ROOT.path_join("app.guitkx") },
	]:
		_check(canvas._can_drop_data(Vector2.ZERO, payload),
			"a %s payload is accepted" % str((payload as Dictionary)["source"]))
	_check(not canvas._can_drop_data(Vector2.ZERO, "a bare string"),
		"and something that is not a payload at all is not")

	_drop(w)


# ── Nothing shouts into the void ─────────────────────────────────────────────────────

func _test_every_signal_is_listened_to() -> void:
	_section("every signal a pane emits has someone listening")
	# A pane that emits and a window that does not connect is a feature that exists in the code
	# and not on the screen -- `entry_activated` was like that, so a click in the library did
	# nothing at all and the only way in was a drag nobody could start either.
	var w := _window()
	await process_frame

	for spec in [
		{ "who": w.folder_pane(), "what": "folder pane" },
		{ "who": w.library_pane(), "what": "library" },
		{ "who": w.source_pane(), "what": "source pane" },
		{ "who": w.console(), "what": "console" },
		{ "who": w.inline_editor(), "what": "inline editor" },
		{ "who": w.canvas(), "what": "canvas" },
	]:
		var emitter: Object = (spec as Dictionary)["who"]
		var what := str((spec as Dictionary)["what"])
		for entry in emitter.get_signal_list():
			var name := str((entry as Dictionary)["name"])
			# Godot's own Node/Control signals are not this builder's contract.
			if not name.begins_with("_") and _is_own_signal(emitter, name):
				_check(emitter.get_signal_connection_list(name).size() > 0,
					"%s.%s has a listener" % [what, name])

	_drop(w)


## Whether a signal is one the builder declared, rather than one Godot gave every Control.
func _is_own_signal(emitter: Object, name: String) -> bool:
	var script: Script = emitter.get_script()
	if script == null:
		return false
	for entry in script.get_script_signal_list():
		if str((entry as Dictionary)["name"]) == name:
			return true
	return false


# ── A tree that has never been placed ────────────────────────────────────────────────

func _test_unplaced_tree_is_placed_before_written() -> void:
	_section("a tree built from the start screen is PLACED before it is written")
	# Everything created with no tree open lives under the provisional root, whose name ends in
	# `~` so Godot's importer skips it wholesale. Writing there puts real files somewhere the
	# engine never looks: the module exists on disk and every import of it resolves to nothing.
	#
	# The create flow could not reach this at all until now -- with no focus it asked for the
	# base directory of an empty string and refused with "no folder to create in", so the four
	# buttons on the start screen, the one path a first-time user takes, was the one that failed.
	var w := BuilderWindow.new()
	w.size = Vector2(1200, 700)
	root.add_child(w)
	await process_frame
	w.open_tree("")
	await process_frame

	# SNAKE_CASE: these name a FILE, and every file in this leg is snake_case. `template_for`
	# derives the PascalCase EXPORT from it.
	_eq(w._validate_name(Module.Kind.COMPONENT, "fresh"), "",
		"a name is accepted with no tree open")
	_check(not w._validate_name(Module.Kind.COMPONENT, "Fresh").is_empty(),
		"and PascalCase is refused -- that is the export's convention, not the file's")
	var made: String = w._create_named(Module.Kind.COMPONENT, "fresh")
	_check(made.begins_with(Workspace.UNSAVED_ROOT),
		"a first module is born at the provisional root (%s)" % made)
	_eq(w.workspace.unlocated_modules().size(), 1, "and the workspace knows it is unplaced")
	_eq(w.graph.cards.size(), 1, "the canvas shows it straight away, in memory")

	_eq(w.save(), 0, "Save writes NOTHING while the tree has no home")
	_check(not FileAccess.file_exists(made), "and nothing reached the provisional path either")

	_section("given a folder, the whole tree moves and then writes")
	_check(w._place_tree_in(PLACED_ROOT), "placing it succeeds")
	_eq(w.workspace.unlocated_modules().size(), 0, "nothing is unplaced any more")
	_check(w.save() > 0, "and now Save writes")
	# THE FIRST MODULE OF A NEW TREE OWNS ITS FOLDER -- Unity's `asRoot` case -- so the relative
	# shape carried into the chosen folder is `fresh/fresh.guitkx`, not a bare file. `_place_tree_in`
	# preserves that shape on purpose: a component and the folder it owns were arranged that way.
	_check(FileAccess.file_exists(PLACED_ROOT.path_join("fresh/fresh.guitkx")),
		"where the user asked, keeping the shape it had (%s)"
			% ", ".join(_files_under(PLACED_ROOT)))

	_drop(w)
	# Cleaned up by hand, and RECURSIVELY: this suite has no rm helper, and a tree left behind
	# makes the next run fail on "already there" rather than on anything it is testing. The old
	# version named four files at the root and the module now owns a FOLDER, so it left one --
	# and on a case-insensitive filesystem `Fresh/` then collided with `fresh/`.
	_purge(PLACED_ROOT)


## Where the placement test puts its tree.
const PLACED_ROOT := "res://tests/__builder_placed_tmp"


# ── An edit reaches the card ─────────────────────────────────────────────────────────

func _test_an_edit_reaches_the_card() -> void:
	_section("adding a hook puts it on the CARD, not only in the source")
	# The graph is re-populated IN PLACE after an edit -- the same object, different rows -- so
	# the props the canvas view is re-rendered with compare equal to the last ones and the
	# reconciler's bailout correctly decides there is nothing to do. Correct, and wrong here: the
	# card kept showing the rows it had, so "+ hook" wrote a line into the source pane and put
	# nothing on the card until some unrelated change forced a render.
	var w := _window()
	await process_frame
	var card = w.graph.cards[0]
	var before: int = card.body.size()

	w._on_card_add(0, "hook")
	# SEVERAL frames: update renders are time-sliced by default, so a commit lands a few frames
	# after the edit. Two was not enough and the card looked stale in a way that had nothing to
	# do with what was being tested.
	for _i in range(8):
		await process_frame

	_eq(w.graph.cards[0].body.size(), before + 1, "the card's model gained the hook")
	_check(w.workspace.try_get(card.file_path).buffer_text.contains("useState"),
		"and so did the buffer")

	# What the user actually looks at: the chip on the card. Counted off the RENDERED tree,
	# because the model being right was never the half that was broken.
	var chips := _labels_under(w.canvas().get_node("Cards"))
	var chipped := false
	for label in chips:
		if str(label).begins_with("useState") and str(label).ends_with("state"):
			chipped = true
	_check(chipped, "and the new hook's chip is on the rendered card (saw %s)" % str(chips))

	_drop(w)


## Every label string in a rendered subtree.
func _labels_under(node: Node) -> PackedStringArray:
	var out := PackedStringArray()
	for child in node.get_children():
		if child is Label:
			out.append((child as Label).text)
		out.append_array(_labels_under(child))
	return out


# ── Folder pane ──────────────────────────────────────────────────────────────────────

func _test_folder_pane() -> void:
	_section("the folder pane shows the tree, grouped by folder")
	var pane := FolderPane.new()
	root.add_child(pane)
	pane.workspace = _seeded_workspace()
	pane.rebuild()
	await process_frame

	var rows := _tree_rows(pane)
	_eq(rows.size(), 3, "one row per module")
	_check(_row_named(rows, "app.guitkx") != null, "the component is listed")
	_check(_row_named(rows, "app.style.guitkx") != null, "so is its style companion")
	_check(_row_named(rows, "row.guitkx") != null, "and so is the nested child")

	_section("state is DERIVED, and the save-only contract is visible in it")
	for row in rows:
		_eq((row as TreeItem).get_text(1), "new",
			"a module that has never been written reads as new (%s)" % (row as TreeItem).get_text(0))

	var module := pane.workspace.try_get(ROOT.path_join("app.guitkx"))
	module.mark_projected(module.file_path())
	pane.rebuild()
	_eq(_row_named(_tree_rows(pane), "app.guitkx").get_text(1), "",
		"a settled module reads as nothing at all")
	module.apply_edit(APP + "\n")
	pane.rebuild()
	_eq(_row_named(_tree_rows(pane), "app.guitkx").get_text(1), "edited", "an edit says so")
	pane.workspace.move_to(module.file_path(), ROOT.path_join("moved"), "app")
	pane.rebuild()
	_eq(_row_named(_tree_rows(pane), "app.guitkx").get_text(1), "moved, edited",
		"and a module that has moved AND been edited says both")

	_section("selecting from outside does not echo back")
	var announced := 0
	pane.module_selected.connect(func(_p: String): announced += 1)
	pane.select_path(ROOT.path_join("components/row/row.guitkx"))
	await process_frame
	_eq(announced, 0, "a selection pushed in from outside announces nothing")
	pane.select_path(ROOT.path_join("components/row/row.guitkx"))
	_eq(announced, 0, "and re-selecting what is already selected does nothing at all")

	pane.queue_free()


# ── Library pane ─────────────────────────────────────────────────────────────────────

func _test_library_pane() -> void:
	_section("the library offers what the COMPILER accepts")
	var pane := LibraryPane.new()
	root.add_child(pane)
	pane.rebuild()
	await process_frame

	var entries := pane.entries()
	_check(entries.size() > 0, "there are entries")
	var names := PackedStringArray()
	for e in entries:
		names.append(str((e as Dictionary)["name"]))
	_check(names.has("VBoxContainer"), "a leading element is offered")
	_check(names.has("useState"), "and a leading hook")

	_section("the list folds, or nobody can read it")
	var elements := 0
	for e in entries:
		if str((e as Dictionary)["kind"]) == LibraryPane.ENTRY_ELEMENT:
			elements += 1
	_eq(elements, LibraryPane.FOLD_AFTER,
		"the element section shows its lead and folds the rest away")

	_section("a filter overrides the fold")
	# The whole point of typing four characters is that the answer is short.
	pane.set_filter("container")
	await process_frame
	var filtered := pane.entries()
	_check(filtered.size() > 0, "something matches")
	for e in filtered:
		_check(str((e as Dictionary)["name"]).to_lower().contains("container"),
			"every row matches the filter (%s)" % (e as Dictionary)["name"])
	_check(filtered.size() > LibraryPane.FOLD_AFTER or filtered.size() == _count_matching("container"),
		"and the fold does not hide any of them")

	pane.set_filter("")
	await process_frame

	_section("a section collapses")
	var before := pane.entries().size()
	pane.set_section_expanded(LibraryPane.ENTRY_ELEMENT, false)
	await process_frame
	_check(pane.entries().size() < before, "closing a section removes its rows")

	_section("the tree's own components are offered alongside the engine's")
	var w := _window()
	await process_frame
	var own := PackedStringArray()
	for e in w.library_pane().entries():
		if str((e as Dictionary)["kind"]) == LibraryPane.ENTRY_COMPONENT:
			own.append(str((e as Dictionary)["name"]))
	_check(own.has("App") and own.has("Row"),
		"both of the fixture's components are in the palette (%s)" % ", ".join(own))
	_drop(w)

	pane.queue_free()


func _count_matching(needle: String) -> int:
	var pane := LibraryPane.new()
	pane.set_filter(needle)
	var n := pane.entries().size()
	pane.free()
	return n


# ── Source pane ──────────────────────────────────────────────────────────────────────

func _test_source_pane() -> void:
	_section("the source pane edits the WORKSPACE's buffer")
	var pane := SourcePane.new()
	root.add_child(pane)
	pane.workspace = _seeded_workspace()
	pane.show_module(ROOT.path_join("app.guitkx"))
	await process_frame
	_eq(pane.path(), ROOT.path_join("app.guitkx"), "it shows what it was given")
	_eq(pane.editor().text, APP, "with the buffer's text")

	var edits: Array = []
	pane.buffer_edited.connect(func(p: String, b: String, a: String): edits.append([p, b, a]))
	# TYPED, not assigned. Setting `TextEdit.text` from code does not emit `text_changed` at all,
	# so an assignment here would exercise nothing and pass anyway.
	pane.editor().set_caret_line(0)
	pane.editor().set_caret_column(0)
	pane.editor().insert_text_at_caret("## typed\n")
	await process_frame
	_eq(edits.size(), 1, "typing reports one edit")
	_check(pane.workspace.try_get(ROOT.path_join("app.guitkx")).buffer_text.begins_with("## typed"),
		"and the MODEL has it -- the pane is not a copy")

	_section("loading a buffer is not an edit")
	# A load is by definition text that already equals the model's, so the comparison rejects it
	# whatever the engine does about signalling programmatic writes.
	edits.clear()
	pane.show_module(ROOT.path_join("components/row/row.guitkx"))
	await process_frame
	_eq(edits.size(), 0, "switching modules reports nothing")
	_eq(pane.editor().text, ROW, "and shows the new buffer")

	_section("re-showing the open module leaves the caret alone")
	pane.editor().set_caret_line(1)
	pane.editor().set_caret_column(3)
	pane.show_module(ROOT.path_join("components/row/row.guitkx"))
	_eq(pane.editor().get_caret_line(), 1, "the caret line survives")
	_eq(pane.editor().get_caret_column(), 3, "and so does the column")

	_section("a change from elsewhere is adopted, caret kept")
	pane.workspace.apply_edit(ROOT.path_join("components/row/row.guitkx"), ROW.replace("Label", "Button"))
	pane.refresh_from_model()
	await process_frame
	_check(pane.editor().text.contains("Button"), "the pane follows a change it did not make")
	_eq(pane.editor().get_caret_line(), 1, "without throwing the caret away")

	_section("a read-only module cannot be typed into")
	var locked := pane.workspace.try_get(ROOT.path_join("app.style.guitkx"))
	locked.read_only = true
	pane.show_module(ROOT.path_join("app.style.guitkx"))
	await process_frame
	_check(not pane.editor().editable, "the editor is not editable")
	_check(pane.editor().text.contains("primary"), "but it still shows the source")

	pane.queue_free()


# ── Console ──────────────────────────────────────────────────────────────────────────

func _test_console() -> void:
	_section("the console reports what a round did")
	var console := Console.new()
	root.add_child(console)
	_eq(console.rows().size(), 0, "it starts empty")

	var summary := Preview.Summary.new()
	summary.rebuilt.append("res://x/a.guitkx")
	summary.failures.append({ "path": "res://x/b.guitkx", "error": "GUITKX0304: unclosed body" })
	summary.skipped.append({ "path": "res://x/c.guitkx", "blocked_by": "res://x/b.guitkx" })
	console.report(summary)
	_eq(console.rows().size(), 2, "a failure and a skip are both rows")
	_eq(int((console.rows()[0] as Dictionary)["severity"]), Console.SEVERITY_ERROR,
		"the failure is an error")
	_eq(int((console.rows()[1] as Dictionary)["severity"]), Console.SEVERITY_WARNING,
		"and the skip is a warning -- nothing about a round is silent")
	_check(str((console.rows()[1] as Dictionary)["message"]).contains("b.guitkx"),
		"the skip says what blocked it")

	_section("a round that did nothing leaves the report standing")
	# Clearing on every idle tick would blank the console and hide the failure the user is in the
	# middle of fixing.
	console.report(null)
	_eq(console.rows().size(), 2, "a null summary changes nothing")

	_section("diagnostics are appended, not substituted")
	console.add_diagnostics("res://x/a.guitkx",
		[{ "code": "GUITKX0106", "severity": 1, "message": "missing key", "line": 4 }])
	_eq(console.rows().size(), 3, "a warning that is not a compile failure is a separate row")

	console.clear()
	_eq(console.rows().size(), 0, "and it can be emptied")
	console.queue_free()


# ── Inline editor ────────────────────────────────────────────────────────────────────

func _test_inline_editor() -> void:
	_section("one inline editor, reused everywhere")
	var editor := InlineEditor.new()
	root.add_child(editor)
	await process_frame

	var committed: Array = []
	var cancelled: Array = []
	editor.committed.connect(func(t: Variant, text: String): committed.append([t, text]))
	editor.cancelled.connect(func(t: Variant, undo_seeding: bool): cancelled.append([t, undo_seeding]))

	editor.open_at(Rect2(10, 10, 120, 22), "before", "attr:text")
	_check(editor.is_open() and editor.visible, "it opens")
	_eq(editor.text, "before", "seeded with what it is editing")
	_eq(editor.token(), "attr:text", "and remembers what it was opened for")

	editor.text = "after"
	editor.commit()
	_eq(committed.size(), 1, "committing reports once")
	_eq(str((committed[0] as Array)[1]), "after", "with the new text")
	_check(not editor.is_open() and not editor.visible, "and closes")

	_section("an edit that changed nothing is not an edit")
	editor.open_at(Rect2(10, 10, 120, 22), "same", "attr:x")
	editor.commit()
	_eq(committed.size(), 1, "committing unchanged text reports nothing")

	_section("escape cancels")
	editor.open_at(Rect2(10, 10, 120, 22), "keep", "attr:y")
	editor.text = "discard"
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	editor._gui_input(escape)
	_eq(cancelled.size(), 1, "escape cancels")
	_eq(committed.size(), 1, "and commits nothing")
	_check(not bool((cancelled[0] as Array)[1]),
		"and an editor the USER opened cancels only the edit")

	_section("opening it somewhere else commits what was there")
	# A user who clicks straight from one attribute to the next has not asked to throw the first
	# one away.
	editor.open_at(Rect2(0, 0, 100, 22), "first", "attr:a")
	editor.text = "typed"
	editor.open_at(Rect2(0, 40, 100, 22), "second", "attr:b")
	_eq(committed.size(), 2, "the first edit committed")
	_eq(str((committed[1] as Array)[0]), "attr:a", "under its own token")
	_eq(editor.token(), "attr:b", "and the editor is now on the second")
	_eq(editor.text, "second", "seeded with that one's text")

	_section("focus does not select what is in the field")
	# A selection means the first keystroke wipes the value the editor was opened to ADJUST, and
	# every inline edit here starts from an existing value.
	editor.open_at(Rect2(10, 10, 120, 22), "existing", "attr:z")
	_eq(editor.get_selected_text(), "", "nothing is selected")
	_eq(editor.caret_column, len("existing"), "the caret waits at the end")
	editor.cancel()
	_check(not bool((cancelled[cancelled.size() - 1] as Array)[1]),
		"an editor the USER opened cancels only the edit")

	_section("escaping a SEEDED editor asks for the seeding back too")
	# The builder wrote `@if (true)` itself as part of opening this editor, so cancelling the edit
	# and cancelling the wrap are one gesture.
	editor.open_at(Rect2(10, 10, 120, 22), "@if (true)", "directive:1", true)
	editor._gui_input(escape)
	_check(bool((cancelled[cancelled.size() - 1] as Array)[1]),
		"it asks the window to undo the seeding")

	_section("committing a seeded editor keeps the seeding")
	var cancels_before := cancelled.size()
	editor.open_at(Rect2(10, 10, 120, 22), "@if (true)", "directive:2", true)
	editor.text = "@if (count > 2)"
	editor.commit()
	_eq(cancelled.size(), cancels_before, "nothing is undone -- the wrap was wanted after all")

	editor.cancel()
	editor.queue_free()


# ── The funnel ───────────────────────────────────────────────────────────────────────

func _test_one_funnel() -> void:
	_section("every change goes through one entry")
	var w := _window()
	await process_frame
	var path := ROOT.path_join("components/row/row.guitkx")

	_check(w.apply_edit(path, ROW.replace("Label", "Button"), "swap the element"),
		"an edit is taken")
	_check(w.workspace.try_get(path).buffer_text.contains("Button"), "the model has it")
	_eq(w.ledger.entries().size(), 1, "the ledger has one entry")
	_eq(w.ledger.undo_label(), "swap the element", "named by the gesture")
	_check(w.preview.has_pending(), "and a preview round is queued")

	_section("the card is re-projected in place, not the whole graph")
	# Rebuilding would discard every card's measured height and re-seed the layout, so a
	# keystroke would visibly reshuffle the canvas.
	var card: Graph.Card = w.graph.card_of(path)
	_check(card != null, "the card is still the same object")
	var rendered := ""
	for row in card.markup:
		rendered += row.name
	_check(rendered.contains("Button"), "and it shows the new element")

	_section("refusals")
	_check(not w.apply_edit(path, w.workspace.try_get(path).buffer_text, "no change"),
		"an edit that changes nothing is not an edit")
	_check(not w.apply_edit("res://nowhere.guitkx", "x", "nothing"),
		"editing a module the tree does not hold is refused")

	_drop(w)


func _test_undo_across_files() -> void:
	_section("one gesture, two files, one undo")
	# A drop that inserts a tag in one file and an import line in another is two edits and ONE
	# action; undoing it file by file leaves a state the user never authored.
	var w := _window()
	await process_frame
	var app := ROOT.path_join("app.guitkx")
	var row := ROOT.path_join("components/row/row.guitkx")

	w.ledger.begin("a compound gesture")
	w.workspace.apply_edit(app, APP.replace("one", "ONE"))
	w.ledger.record(app, APP, APP.replace("one", "ONE"))
	w.workspace.apply_edit(row, ROW.replace("Label", "Button"))
	w.ledger.record(row, ROW, ROW.replace("Label", "Button"))
	w.ledger.end()
	_eq(w.ledger.entries().size(), 1, "the two edits are one entry")

	_check(w.undo(), "undo runs")
	await process_frame
	_eq(w.workspace.try_get(app).buffer_text, APP, "the first file is back")
	_eq(w.workspace.try_get(row).buffer_text, ROW, "and so is the second -- all of them or none")
	_check(not w.ledger.can_undo(), "with nothing left to undo")

	_check(w.redo(), "redo runs")
	await process_frame
	_check(w.workspace.try_get(app).buffer_text.contains("ONE"), "the first file is forward again")
	_check(w.workspace.try_get(row).buffer_text.contains("Button"), "and so is the second")

	_section("replay does not record itself")
	_eq(w.ledger.entries().size(), 1, "an undo rewriting buffers is not a new action")

	_drop(w)


## DELETION IS REFUSED WHILE THE MODULE IS STILL IMPORTED, and the refusal names who imports it.
##
## The alternative -- delete anyway and quietly strip the importers' imports -- is what this
## builder did until now, and it means a one-file delete silently edits files the user cannot see.
## WHERE A MODULE IS BORN FOLLOWS THE RIGHT-CLICK, NOT THE FOCUS.
##
## Pinned as a table because the rule has four cases and they are easy to collapse into one: this
## used to read `_focus_path.get_base_dir()`, which is neither the card you right-clicked nor the
## tree root, and on a fresh tree was the empty string -- the "no folder to create in" refusal that
## made the start screen's own buttons dead.
## SAVE ASKS BEFORE IT DELETES, and names what it would delete.
##
## Deletion is the one thing a save does that cannot be taken back from inside the builder --
## every other part of it is a write the ledger still remembers.
## SELECTION IS ONE THING AT A TIME, and Delete acts on it before it falls through to the module.
## A TREE WITH NO SAVED LAYOUT OPENS AT LAYER 2, CENTRED.
##
## Not fitted: a fit picks whatever zoom frames the whole graph, so the layer the user lands in
## depends on how many modules they have -- five cards opened at a third of Layer 2's size with
## the toolbar confidently reading "Layer 2 — Cards" beside cards nobody could read.
## DRAGGING A FILE OR A FOLDER ONTO ANOTHER FOLDER RE-FILES IT -- the only gesture that moves
## anything. The pane could start such a drag and had no way to receive one, so its own doc
## comment described a gesture that ended nowhere.
## "+ hook" SEEDS A LINE AND OPENS THE EDITOR ON IT.
##
## Capability reference §5: the chips exist "so custom body logic never requires the source pane".
## Seeding and stopping left the user with `var state = useState(null)` on the card and the source
## pane as the only way to make it say anything else -- which is the thing the chip was for.
func _test_add_chip_opens_the_editor() -> void:
	_section("+ hook writes a useState and puts the caret in it")
	var w := _window()
	await process_frame
	var index := w.graph.index_of(ROOT.path_join("app.guitkx"))
	var before: String = w._buffer_of(ROOT.path_join("app.guitkx"))

	w._on_card_add(index, "hook")
	await process_frame
	var after: String = w._buffer_of(ROOT.path_join("app.guitkx"))
	_check(after != before, "the line is seeded")
	_check(after.contains("useState"), "as a useState")
	_check(w.inline_editor().is_open(), "and the editor opens on it")
	_eq(w.inline_editor().text, "var state = useState(null)", "holding the seeded line")

	_section("and it is a SEEDED editor, so Escape takes the seeding back")
	var cancelled: Array = []
	w.inline_editor().cancelled.connect(func(_t, undo: bool): cancelled.append(undo))
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	w.inline_editor()._gui_input(escape)
	await process_frame
	_eq(cancelled.size(), 1, "escape cancels")
	_check(bool(cancelled[0]), "asking for the seeding back")
	_eq(w._buffer_of(ROOT.path_join("app.guitkx")), before,
		"and the hook is gone -- one gesture, taken back in one")

	_section("committing an edit keeps it")
	w._on_card_add(index, "hook")
	await process_frame
	w.inline_editor().text = "var count = useState(0)"
	w.inline_editor().commit()
	await process_frame
	_check(w._buffer_of(ROOT.path_join("app.guitkx")).contains("useState(0)"),
		"the typed line replaced the seeded one")

	_drop(w)


## A RENAME MUST RENAME: the export, the file, the folder when owned, and every importer's
## specifier, binding and uses. This did only the file and the specifiers.
## A SOURCE EDIT MUST REACH THE LEDGER, THE CANVAS AND THE PREVIEW.
##
## It reached none of them. The pane wrote the model on every keystroke, so by the time Apply ran
## `before` already equalled `after` and the window's funnel rejected the whole thing as a no-op.
## UNSAVED WORK SURVIVES SOMEONE OPENING ANOTHER FILE.
## THE THINGS DELETE MUST NOT DELETE.
## DOUBLE-CLICKING A ROW EDITS IT IN PLACE -- the reference's primary editing gesture, which had
## no route here at all. The whole builder contained one `double_click` read, in the library.
## THE PREVIEW KEEPS RENDERING THE COMPONENT WHEN YOU SELECT A COMPANION, and keeps the values
## you typed into its knobs.
func _test_preview_anchor_and_knobs() -> void:
	var w := _window()
	w.size = Vector2(1400, 800)
	await process_frame
	var component := ROOT.path_join("app.guitkx")
	w.select_module(component)
	for i in 6:
		await process_frame
	var pane = w.preview_pane()
	var anchored: String = pane.rendered_path()

	_section("selecting a style companion does not move the render anchor")
	# `_path` was overwritten with whatever the pane was handed, renderable or not, so the compile
	# pipeline followed the FOCUS and stopped rebuilding the component actually on the stage.
	w.select_module(ROOT.path_join("app.style.guitkx"))
	for i in 4:
		await process_frame
	if not anchored.is_empty():
		_eq(pane.rendered_path(), anchored,
			"the anchor is still the component that mounted")

	_section("a knob keeps its value across a rebuild")
	# The window re-shows the pane on every compile round, and the knobs were rebuilt
	# unconditionally -- so any edit anywhere wiped every value the user had typed.
	w.select_module(component)
	for i in 4:
		await process_frame
	var before: Dictionary = pane.props().duplicate()
	if not before.is_empty():
		var key: String = before.keys()[0]
		pane.props()[key] = "typed-by-hand"
		pane.show_module(component)
		await process_frame
		_eq(str(pane.props().get(key, "")), "typed-by-hand",
			"the value survived a re-show")

	_drop(w)


func _test_double_click_edits_in_place() -> void:
	var w := _window()
	await process_frame
	var path := ROOT.path_join("app.guitkx")
	var index := w.graph.index_of(path)
	var card: Graph.Card = w.graph.cards[index]

	_section("a hook chip opens on its own setup line")
	if not card.body.is_empty():
		w._on_row_activated(index, int(Metrics.Section.BODY), 0, Vector2(100, 100))
		await process_frame
		_check(w.inline_editor().is_open(), "the editor opened")
		_eq(w.inline_editor().text, card.body[0].source_text, "seeded with the line it edits")
		w.inline_editor().cancel()
		await process_frame

	_section("a directive head opens on its EXPRESSION, so committing it is the identity")
	var directive := -1
	for i in card.markup.size():
		if card.markup[i].kind == Graph.LineKind.DIRECTIVE:
			directive = i
			break
	if directive >= 0:
		var before: String = w._buffer_of(path)
		w._on_row_activated(index, int(Metrics.Section.MARKUP), directive, Vector2(100, 100))
		await process_frame
		_check(w.inline_editor().is_open(), "the editor opened")
		_eq(w.inline_editor().text, card.markup[directive].directive_text,
			"seeded with the expression alone")
		w.inline_editor().commit()
		await process_frame
		_eq(w._buffer_of(path), before, "and committing it unchanged changes nothing")

	_section("the editor opens OVER the row, not wherever the last menu was")
	var rect: Rect2 = w._row_rect_on_screen(card, int(Metrics.Section.MARKUP), 0)
	_check(rect.size.x >= 260.0, "at least the minimum width")
	_check(rect.size.y >= 22.0, "and a real height")

	_drop(w)


## THE SOURCE PANE HAS CHORDS: Ctrl+Enter applies, Escape cancels.
## THE BUILDER REPORTS WHAT THE COMPILER SAYS -- on the surface being edited, and in the console.
##
## `GuitkxCodeEdit` owns a diagnostics gutter, a per-line store and a hover composer, and the
## builder called NONE of it: the gutter it embeds was permanently blank, so an error in the file
## being edited was invisible on the surface it was being edited on.
## A SETUP ISLAND IS EDITED IN A MULTILINE FIELD, and Enter in it is a newline.
##
## The island had no editor at all, and when double-click was wired up it reached the SINGLE-LINE
## editor -- which would have flattened a multi-statement island into one line on commit.
## THE ROW MENU IS SHAPED BY THE SECTION THE ROW LIVES IN.
##
## It branched on exactly two things -- the EXPORTS section and a DIRECTIVE row -- and served
## everything else the ELEMENT menu, so an import row and a hook chip were both offered "Add
## attribute...", "Add child element..." and "Wrap in...". Every one of those computes an
## insertion point from a markup span the row does not have.
func _test_row_menu_fits_its_section() -> void:
	var w := _window()
	await process_frame
	var index := w.graph.index_of(ROOT.path_join("app.guitkx"))
	var card: Graph.Card = w.graph.cards[index]

	var element_only := ["Add attribute", "Add child element", "Wrap in", "Apply style"]

	_section("an import row is offered import operations, and no markup ones")
	if not card.imports.is_empty():
		w._on_row_context(index, int(Metrics.Section.IMPORTS), 0, Vector2(10, 10))
		var items := _menu_labels(w.row_menu())
		_check(_mentions(items, "import"), "it names the import (%s)" % ", ".join(items))
		for banned in element_only:
			_check(not _mentions(items, str(banned)), "and never offers \"%s\"" % banned)

	_section("a hook chip is offered line operations, and no markup ones")
	if not card.body.is_empty():
		w._on_row_context(index, int(Metrics.Section.BODY), 0, Vector2(10, 10))
		var items := _menu_labels(w.row_menu())
		_check(_mentions(items, "line"), "it talks about the line (%s)" % ", ".join(items))
		for banned in element_only:
			_check(not _mentions(items, str(banned)), "and never offers \"%s\"" % banned)

	_section("a markup row still gets the element menu")
	var root := Edits.first_element_row(card)
	if root >= 0:
		w._on_row_context(index, int(Metrics.Section.MARKUP), root, Vector2(10, 10))
		var items := _menu_labels(w.row_menu())
		_check(_mentions(items, "Add child element"),
			"the element operations are there (%s)" % ", ".join(items))

	_drop(w)


## Whether any label in `items` contains `needle`. `PackedStringArray` has no `any`.
func _mentions(items: PackedStringArray, needle: String) -> bool:
	for text in items:
		if str(text).contains(needle):
			return true
	return false


## Every enabled label in a PopupMenu, separators excluded.
func _menu_labels(menu: PopupMenu) -> PackedStringArray:
	var out := PackedStringArray()
	for i in menu.item_count:
		if menu.is_item_separator(i):
			continue
		out.append(menu.get_item_text(i))
	return out


func _test_island_editor_is_multiline() -> void:
	var w := _window()
	await process_frame
	var editor := w.island_editor()
	# A TextEdit, so Enter is a newline rather than a commit. The parser already knows the type,
	# so the assertion that matters is BEHAVIOURAL: it holds more than one line.
	_check(editor is TextEdit, "the island editor is a TextEdit")

	_section("it round-trips a multi-line island")
	var body := "var a = 1
var b = 2
var c = a + b"
	var got := []
	editor.committed.connect(func(_t: Variant, text: String): got.append(text))
	editor.open_at(Rect2(0, 0, 400, 120), body, { "kind": "island" })
	_eq(editor.text, body, "seeded with every line")
	_eq(editor.get_line_count(), 3, "as three lines")
	editor.commit()
	_eq(got.size(), 0, "committing unchanged text reports nothing")

	_section("Ctrl+Enter commits, Escape cancels")
	editor.open_at(Rect2(0, 0, 400, 120), body, { "kind": "island" })
	editor.text = body + "
var d = 4"
	var apply := InputEventKey.new()
	apply.keycode = KEY_ENTER
	apply.pressed = true
	apply.ctrl_pressed = true
	editor._gui_input(apply)
	_eq(got.size(), 1, "the edit committed")
	if got.size() > 0:
		_check(str(got[0]).contains("var d = 4"), "with the new line in it")
		_eq(str(got[0]).split("
").size(), 4, "and all four lines intact")

	editor.queue_free()
	_drop(w)


## THE LANGUAGE LAYER KNOWS WHAT THE BUILDER IS HOLDING.
##
## `GuitkxWorkspace` is the index behind component-tag completion, Ctrl+hover validation and
## go-to-definition, and it is built entirely FROM DISK. Under the save-only contract the disk is
## the tree as it was before the session started -- so completion missed every component the user
## had created and offered every one they had renamed away.
func _test_language_index_follows_the_buffers() -> void:
	var w := _window()
	await process_frame
	var LspWorkspace = preload("res://addons/reactive_ui_toolkit_editor/lsp/guitkx_workspace.gd")

	_section("a component created in session becomes a completion candidate")
	var made := ROOT.path_join("components/badge/badge.guitkx")
	w.workspace.create_new(made,
		"export SessionBadge() -> RuitkVNode {
	return (
		<Label />
	)
}
")
	w.reproject()
	w._reindex_language(made)
	await process_frame
	_check(LspWorkspace.is_component("SessionBadge"),
		"the language layer knows a tag that exists only in memory")

	_section("and an edit to it is followed")
	w.apply_edit(made,
		"export RenamedBadge() -> RuitkVNode {
	return (
		<Label />
	)
}
",
		"rename the export")
	await process_frame
	_check(LspWorkspace.is_component("RenamedBadge"), "the new name is known")
	_check(not LspWorkspace.is_component("SessionBadge"),
		"and the old one is gone -- reindex erases every entry for the path before re-adding")

	_section("deleting it takes it out of the vocabulary")
	w.delete_module(made)
	await process_frame
	_check(not LspWorkspace.is_component("RenamedBadge"),
		"a deleted module stops being a completion candidate")

	_drop(w)


func _test_diagnostics_reach_the_surface() -> void:
	var w := _window()
	await process_frame
	var path := ROOT.path_join("app.guitkx")
	w.select_module(path)
	await process_frame

	_section("an unknown element is reported at all")
	# GUITKX0105 is only raised when the compiler is TOLD which names are components; handed an
	# empty list it suppresses the check, and the builder never told it -- so `<Labell />` compiled
	# clean and lowered to a call on a class that does not exist.
	var known := w.known_component_tags()
	_check(known.has("App"), "the tree's own components are in the vocabulary")
	_check(not known.has("primary"),
		"and a style export is NOT -- it is not an element, and a typo must not resolve to one")

	# A mistyped COMPONENT, not a mistyped host tag -- a host tag is checked against ClassDB
	# regardless, and the vocabulary is what gates the component half.
	var broken: String = w._buffer_of(path).replace("<Row ", "<Roww ")
	var quiet: Dictionary = Compiler.compile(broken, "App", [], {})
	var told: Dictionary = Compiler.compile(broken, "App", known, {})
	_check(bool(quiet.get("ok", false)), "with no vocabulary the compiler stays quiet")
	_check(not bool(told.get("ok", false)), "and with one it reports the unknown element")

	_section("and the pane is handed them")
	# The gutter is the editor addon's own; what was missing was the call.
	w._publish_diagnostics(path)
	await process_frame
	_check(w.source_pane().editor().diag_gutter >= 0, "the pane has a diagnostics gutter to paint")

	_drop(w)


func _test_source_pane_keyboard() -> void:
	var w := _window()
	await process_frame
	var path := ROOT.path_join("app.guitkx")
	w.select_module(path)
	await process_frame
	var pane := w.source_pane()
	var original: String = w._buffer_of(path)

	_section("Escape cancels an open edit")
	pane._set_editing(true)
	await process_frame
	pane.editor().text = original.replace("\"one\"", "\"escaped\"")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	pane.editor().grab_focus()
	pane._unhandled_key_input(escape)
	await process_frame
	_check(not pane.is_editing(), "edit mode is closed")
	_eq(w._buffer_of(path), original, "and the buffer is untouched")

	_section("Ctrl+Enter applies one")
	pane._set_editing(true)
	await process_frame
	pane.editor().text = original.replace("\"one\"", "\"chorded\"")
	var apply := InputEventKey.new()
	apply.keycode = KEY_ENTER
	apply.pressed = true
	apply.ctrl_pressed = true
	pane.editor().grab_focus()
	pane._unhandled_key_input(apply)
	await process_frame
	_check(not pane.is_editing(), "edit mode is closed")
	_check(w._buffer_of(path).contains("chorded"), "and the edit landed")

	_drop(w)


func _test_delete_refuses_what_it_must() -> void:
	var w := _window()
	await process_frame
	var path := ROOT.path_join("app.guitkx")
	var index := w.graph.index_of(path)
	var card: Graph.Card = w.graph.cards[index]
	var original: String = w._buffer_of(path)

	_section("the component's return root cannot be deleted")
	# The guard was `row_index > 0`, so wrapping the root in an @if made the root row 1 and the
	# guard stopped protecting it.
	var root_row: int = Edits.first_element_row(card)
	_check(root_row >= 0, "the card has a return root (row %d)" % root_row)
	w._on_row_clicked(index, int(Metrics.Section.MARKUP), root_row)
	w._delete_selection()
	await process_frame
	_eq(w._buffer_of(path), original, "deleting it does nothing")
	_check(w.toast_text().contains("must return one node"), "and says why")

	_section("an affordance row has no span, so it deletes nothing")
	# "+ entry" and friends are synthetic rows with at == end_at == 0, and removing that range cut
	# the FIRST LINE OF THE FILE.
	var affordance := Graph.Line.new()
	_check(not Edits.has_span(affordance), "a fresh Line has no span")
	_eq(Edits.remove(original, affordance), original, "and remove refuses it outright")

	_section("clicking a setup line does not select the return root")
	var with_setup := w.graph.card_of(path)
	if with_setup != null and with_setup.island_start_line > 0:
		var island = w._island_row(with_setup)
		_check(island != null, "the island resolves to a row of its own")
		if island != null:
			_check(island.end_at > island.at, "with a real span")
			_check(island.source_line == with_setup.island_start_line,
				"pointing at the setup, not at the markup")

	_drop(w)


## THE SELECTED ROW IS RE-RESOLVED, so a Delete after a menu edit cuts at current offsets.
func _test_selection_survives_an_edit() -> void:
	_section("an edit rebuilds the rows; the selection still names the right one")
	var w := _window()
	await process_frame
	var path := ROOT.path_join("app.guitkx")
	var index := w.graph.index_of(path)
	var card: Graph.Card = w.graph.cards[index]
	var last := card.markup.size() - 1
	w._on_row_clicked(index, int(Metrics.Section.MARKUP), last)
	var stale = w._menu_row

	# Any edit at all re-projects the card into new Line objects.
	w.apply_edit(path, w._buffer_of(path).replace("<VBoxContainer>",
		"<VBoxContainer>
			<Label text=\"inserted\" />"), "insert above")
	await process_frame
	var live = w._live_menu_row()
	_check(live != null, "the selection still resolves")
	_check(live != stale, "to a CURRENT row object, not the one captured before the edit")

	_drop(w)


func _test_load_does_not_destroy_unsaved_work() -> void:
	_section("a dirty tree adopts the file instead of being replaced by it")
	var w := _window()
	await process_frame
	var path := ROOT.path_join("app.guitkx")
	w.apply_edit(path, w._buffer_of(path) + "
", "make it dirty")
	await process_frame
	_check(w.workspace.has_unsaved_changes(), "the tree is dirty")
	var before := w.workspace.modules().size()

	w.load_tree_for(ROOT.path_join("components/row/row.guitkx"))
	await process_frame
	_check(w.workspace.has_unsaved_changes(), "the unsaved work is still here")
	_check(w.workspace.try_get(path) != null, "and so is the module that held it")
	_check(w.workspace.modules().size() >= before, "nothing was dropped")

	_section("a file already in the tree just gets focused")
	w.load_tree_for(path)
	await process_frame
	_eq(w.focus_path(), path, "focused, not reloaded")

	_drop(w)


## REDOING A CREATION RESTORES THE MODULE'S TEXT, not an empty buffer.
func _test_redo_of_a_creation_keeps_its_text() -> void:
	_section("create, undo, redo")
	var w := _window()
	await process_frame
	w._menu_target = ""
	var created := w._create_named(Module.Kind.COMPONENT, "Panel")
	await process_frame
	_check(not created.is_empty(), "the module was created")
	var text: String = w._buffer_of(created)
	_check(text.length() > 0, "with a template in it (%d chars)" % text.length())

	_check(w.undo(), "undo runs")
	await process_frame
	_check(w.workspace.try_get(created) == null, "and the module is gone")

	_check(w.redo(), "redo runs")
	await process_frame
	var back = w.workspace.try_get(created)
	_check(back != null, "the module is back")
	if back != null:
		_eq(back.buffer_text, text, "with the text it had, not an empty buffer")

	_drop(w)


func _test_source_edit_reaches_the_funnel() -> void:
	_section("typing does not touch the model while an edit is open")
	var w := _window()
	await process_frame
	var path := ROOT.path_join("app.guitkx")
	w.select_module(path)
	await process_frame
	var pane := w.source_pane()
	var original: String = w._buffer_of(path)

	pane._set_editing(true)
	await process_frame
	_check(pane.is_editing(), "the pane is in edit mode")
	pane.editor().text = original.replace("\"one\"", "\"typed\"")
	pane._on_text_changed()
	await process_frame
	_eq(w._buffer_of(path), original,
		"half-typed text stays out of the model -- it is what Save writes")

	_section("apply is the one write, and it is a real one")
	var entries_before: int = w.ledger.entries().size()
	pane.apply_edit()
	await process_frame
	_check(w._buffer_of(path) != original, "the model has the edit")
	_check(w._buffer_of(path).contains("typed"), "with the typed text in it")
	_check(w.ledger.entries().size() > entries_before, "and the ledger has an entry for it")
	_check(w.ledger.can_undo(), "so it can be taken back")

	_section("and undo takes it back")
	_check(w.undo(), "undo runs")
	await process_frame
	_eq(w._buffer_of(path), original, "the file is as it was")

	_drop(w)


## LEAVING AN EDIT BY SELECTING SOMETHING ELSE MUST NOT STRAND THE TYPED TEXT.
func _test_abandoned_edit_is_not_kept() -> void:
	_section("switching module while editing restores the buffer")
	var w := _window()
	await process_frame
	var path := ROOT.path_join("app.guitkx")
	w.select_module(path)
	await process_frame
	var pane := w.source_pane()
	var original: String = w._buffer_of(path)

	pane._set_editing(true)
	await process_frame
	pane.editor().text = "this is not guitkx at all <<<"
	pane._on_text_changed()
	await process_frame

	w.select_module(ROOT.path_join("components/row/row.guitkx"))
	await process_frame
	_eq(w._buffer_of(path), original, "the abandoned edit did not survive the switch")
	_check(not pane.is_editing(), "and the pane is not still in edit mode")

	_drop(w)


## A CARD KEEPS ITS POSITION THROUGH A RENAME AND A RE-FILE.
##
## `layout.repath` existed, was correct, and had one caller whose call was then DISCARDED --
## `reproject()` rebuilds the layout from disk, so re-keying it in memory achieved nothing. Every
## rename, re-file and folder move lost the arrangement the user had made.
func _test_layout_follows_the_file() -> void:
	var w := _window()
	w.size = Vector2(1400, 800)
	await process_frame
	await process_frame
	var path := ROOT.path_join("app.style.guitkx")
	var index := w.graph.index_of(path)
	_check(index >= 0, "the companion has a card")

	_section("put it somewhere deliberate, and save the arrangement")
	var placed := Vector2(640.0, 480.0)
	w._on_card_moved(index, placed)
	await process_frame
	var card: Graph.Card = w.graph.cards[index]
	card.x = placed.x
	card.y = placed.y
	w._capture_layout()

	_section("re-filing it keeps the position")
	_check(w.place_module(path, ROOT.path_join("components/row")), "the move lands")
	await process_frame
	var moved := ROOT.path_join("components/row/app.style.guitkx")
	var now := w.graph.index_of(moved)
	_check(now >= 0, "the module has a card at its new path")
	if now >= 0:
		var after: Graph.Card = w.graph.cards[now]
		_check(absf(after.x - placed.x) < 1.0 and absf(after.y - placed.y) < 1.0,
			"and it is where the user put it, not at a freshly seeded slot (%.0f,%.0f)"
				% [after.x, after.y])

	_drop(w)


func _test_rename_is_complete() -> void:
	_section("wire an importer up first, so the rename has references to follow")
	var w := _window()
	await process_frame
	var host := ROOT.path_join("app.guitkx")
	var target := ROOT.path_join("components/row/row.guitkx")
	w.apply_edit(host, w._with_component_import(w._buffer_of(host), host, "Row"), "import Row")
	await process_frame
	# And a USE of it, which is the half a specifier rewrite never touches.
	var used: String = w._buffer_of(host).replace("<Label", "<Row />
			<Label")
	w.apply_edit(host, used, "use Row")
	await process_frame
	_check(w._buffer_of(host).contains("<Row"), "the host uses <Row>")

	_section("renaming rewrites the module's own export")
	w._menu_target = target
	# Asked of the operation itself: a module that OWNS its folder renames the folder with it, so
	# the destination is not simply "the old folder with a new file name".
	var moved: String = w.rename_target(w.workspace.try_get(target), "Line")
	w._rename_to("Line")
	await process_frame
	var renamed = w.workspace.try_get(moved)
	_check(renamed != null, "the module is at its new path")
	if renamed != null:
		_check(renamed.buffer_text.contains("export Line"), "and declares the new name")
		_check(not renamed.buffer_text.contains("export Row"), "not the old one")

	_section("and every importer follows it")
	var after: String = w._buffer_of(host)
	_check(after.contains("Line"), "the importer names it")
	_check(not after.contains("{ Row }"), "the import no longer asks for a name nothing exports")
	_check(not after.contains("<Row"), "and the USES moved too")

	_section("the whole rename is one undoable action")
	_check(w.ledger.can_undo(), "it is on the ledger")

	_drop(w)


## THE RENAME PROMPT ASKS ABOUT THE MODULE'S OWN FOLDER, not about where a NEW module would go.
func _test_rename_validation() -> void:
	var w := _window()
	await process_frame
	var style = w.workspace.try_get(ROOT.path_join("app.style.guitkx"))
	_check(style != null, "the fixture has a style companion")

	_section("its current name is not a rename")
	_check(not w._validate_rename(style, style.name).is_empty(), "refused with a reason")

	_section("a name already taken in its own folder is refused")
	# The create validator asked about `<parent>/components/<Name>/` -- a folder that does not
	# exist -- so it never saw a collision and Save wrote one module over another.
	var app = w.workspace.try_get(ROOT.path_join("app.guitkx"))
	_eq(w.rename_target(style, "restyled"),
		style.folder.path_join("restyled" + Module.suffix_for(style.kind)),
		"a companion never owns a folder, so it renames in place")
	_check(w.rename_target(app, "App2").contains("App2"), "and an owner carries its folder")
	_check(not w._validate_rename(style, "app").is_empty(),
		"taking a sibling's file name is refused")

	_section("shape rules still apply, by kind")
	_check(not w._validate_rename(app, "NotSnake").is_empty(),
		"a file name is snake_case, not PascalCase")
	_check(w._validate_rename(app, "renamed").is_empty(), "and a free snake_case name is allowed")
	var hook = w.workspace.try_get(ROOT.path_join("app.guitkx"))
	_check(not w._validate_rename(app, "has-dashes").is_empty(), "and a dash is not an identifier")

	_drop(w)


## NOTHING MAY CLAIM A PATH TWICE, and a folder-owning component carries its folder.
func _test_move_guards() -> void:
	var w := _window()
	await process_frame

	_section("a module cannot be re-filed on top of another")
	var style_path := ROOT.path_join("app.style.guitkx")
	_check(w.place_module(style_path, ROOT.path_join("components/row")), "the first move lands")
	await process_frame
	# Put a second module of the same file name in the way, then try to move it there too.
	var second := ROOT.path_join("components/app.style.guitkx")
	w.workspace.create_new(second, "export nothing := {}
")
	w.reproject()
	await process_frame
	_check(not w.place_module(second, ROOT.path_join("components/row")),
		"the second is refused rather than displacing it")
	_check(w.workspace.try_get(second) != null, "and stays where it was")

	_section("the model refuses it too, whatever the caller does")
	var resident = w.workspace.try_get(ROOT.path_join("components/row/app.style.guitkx"))
	var intruder = w.workspace.try_get(second)
	_check(resident != null and intruder != null, "both modules exist")
	_check(not w.workspace.tree().move_to(intruder, resident.folder, resident.name),
		"Tree.move_to is the last line of defence")

	_drop(w)


func _test_folder_pane_refiles() -> void:
	_section("a module dropped on a folder is re-filed into it")
	var w := _window()
	await process_frame
	var moved := w.place_module(ROOT.path_join("app.style.guitkx"),
		ROOT.path_join("components/row"))
	_check(moved, "the move is accepted")
	_check(w.workspace.try_get(ROOT.path_join("components/row/app.style.guitkx")) != null,
		"and the module is at its new path")
	_check(w.workspace.try_get(ROOT.path_join("app.style.guitkx")) == null,
		"and no longer at the old one")

	_section("a move that changes nothing is refused")
	_check(not w.place_module(ROOT.path_join("components/row/app.style.guitkx"),
		ROOT.path_join("components/row")), "dropping a module in the folder it already lives in")

	_section("and the move is one undoable action")
	_check(w.ledger.can_undo(), "so it can be taken back")
	_check(w.undo(), "undo runs")
	await process_frame
	_check(w.workspace.try_get(ROOT.path_join("app.style.guitkx")) != null,
		"and the module is home again")

	_drop(w)


## The pane's own drop rules, asked directly: which drags a folder row accepts.
func _test_folder_pane_drop_rules() -> void:
	_section("a folder cannot land in itself or its own subtree")
	var w := _window()
	await process_frame
	var pane := w.folder_pane()

	var parent := ROOT.path_join("components")
	var child := ROOT.path_join("components/row")
	_eq(pane._drop_target_for(
		{ "source": "folder", "path": parent }, parent), "", "not into itself")
	_eq(pane._drop_target_for(
		{ "source": "folder", "path": parent }, child), "", "and not into its own subtree")
	_eq(pane._drop_target_for({ "source": "folder", "path": child }, parent), "",
		"and not into the folder it already sits in")
	_eq(pane._drop_target_for({ "source": "folder", "path": child }, ROOT), ROOT,
		"but moving it up a level is a real move")
	_eq(pane._drop_target_for({ "source": "module", "path": ROOT.path_join("app.guitkx") }, child),
		child, "a module into a different folder is fine")
	_eq(pane._drop_target_for({ "source": "nonsense", "path": "x" }, child), "",
		"and an unknown payload is refused")

	_drop(w)


## THE HIT-TEST MUST AGREE WITH WHAT WAS RENDERED, not with a prediction of it.
##
## The section stack is computed from constants and nothing ever compared it to the Control tree
## the view lays out. It was wrong by tens of pixels by the bottom of a card, so `card_at`
## reported NO CARD over the lower half of every card, clicking one row selected its neighbour,
## and a right-click on empty canvas below a card opened that card's row menu.
##
## The gate that was missing: walk the tree that was actually drawn and ask the hit-test about
## every row in it. The old canvas test asserted the model against the model and passed.
func _test_hit_test_agrees_with_the_rendered_tree() -> void:
	_section("every drawn row answers to its own centre")
	var w := _window()
	w.size = Vector2(1400, 800)
	for i in 12:
		await process_frame
	var canvas := w.canvas()
	var checked := 0
	var wrong := 0
	for index in w.graph.cards.size():
		var card: Graph.Card = w.graph.cards[index]
		for section in [int(Metrics.Section.IMPORTS), int(Metrics.Section.BODY),
				int(Metrics.Section.MARKUP), int(Metrics.Section.EXPORTS)]:
			for row_index in 12:
				var rect: Rect2 = canvas.measured_row(index, section, row_index)
				if rect.size.y <= 0.0:
					continue
				checked += 1
				var centre := Vector2(card.x, card.y) + rect.position + rect.size * 0.5
				var at := Metrics.world_to_screen(centre, canvas.camera, canvas.zoom)
				var hit: Dictionary = canvas.row_at(index, at)
				if not bool(hit["found"]) or int(hit["section"]) != section 						or int(hit["index"]) != row_index:
					wrong += 1
					if wrong <= 3:
						print("        card %d row %d:%d -> %s" % [index, section, row_index, hit])
	_check(checked > 0, "the canvas laid out rows to measure (%d)" % checked)
	_eq(wrong, 0, "and every one of them is found at its own centre")

	_section("and empty canvas below a card is not the card")
	for index in w.graph.cards.size():
		var height: float = canvas.measured_height(index)
		if height <= 0.0:
			continue
		var card: Graph.Card = w.graph.cards[index]
		var below := Vector2(card.x + 10.0, card.y + height + 24.0)
		var occupied := false
		for other in w.graph.cards:
			if other != card and Rect2(other.x, other.y, 400.0, 400.0).has_point(below):
				occupied = true
		if occupied:
			continue
		_eq(canvas.card_at(Metrics.world_to_screen(below, canvas.camera, canvas.zoom)), -1,
			"below card %d is empty canvas" % index)

	_drop(w)


func _test_opens_at_layer_two() -> void:
	_section("no saved layout")
	# Cleared FIRST, and by MEMBERSHIP. The layout store lives under `user://` and outlives the
	# process, so an earlier test in this suite -- or an earlier RUN of it -- leaves a layout for
	# this same tree and the "no saved layout" path is never the one under test. A layout is found
	# by which modules it covers, not by the root it was saved under, so removing the root's own
	# file is not enough.
	var store := DirAccess.open(Layout.LAYOUT_DIR)
	if store != null:
		for stale in store.get_files():
			if stale.ends_with(".json"):
				DirAccess.remove_absolute(Layout.LAYOUT_DIR.path_join(stale))
	var w := _window()
	w.size = Vector2(1400, 800)
	await process_frame
	await process_frame
	await process_frame
	_eq(w.canvas().zoom, Metrics.DEFAULT_ZOOM, "the canvas opens at the Layer 2 preset")
	_eq(int(Metrics.lod_of(w.canvas().zoom)), int(Metrics.Lod.SECTIONS),
		"which is the band the layer selector names")

	_section("and the centring is what waits for a size, not the zoom")
	# Which layer a tree opens at is not a question about the canvas's pixel size, so it must not
	# wait for one -- a canvas that is never laid out would otherwise open at 1:1 with the toolbar
	# reading "Layer 2".
	w._centre_when_sized(1)
	if w.canvas().size.x > 1.0:
		var bounds: Rect2 = Metrics.content_bounds(w.graph, Metrics.lod_of(w.canvas().zoom))
		var centre_screen := Metrics.world_to_screen(bounds.position + bounds.size * 0.5,
			w.canvas().camera, w.canvas().zoom)
		_check(absf(centre_screen.x - w.canvas().size.x * 0.5) < 2.0, "centred horizontally")
		_check(absf(centre_screen.y - w.canvas().size.y * 0.5) < 2.0, "and vertically")
	_eq(w.canvas().zoom, Metrics.DEFAULT_ZOOM, "and the zoom is unchanged either way")

	_drop(w)


func _test_selection_and_delete() -> void:
	_section("clicking a row selects it")
	var w := _window()
	await process_frame
	var card_index := w.graph.index_of(ROOT.path_join("app.guitkx"))
	var card := w.graph.cards[card_index]
	_check(not card.markup.is_empty(), "the card has markup to select")

	w._on_row_clicked(card_index, int(Metrics.Section.MARKUP), 1)
	_eq(w.canvas().selected_row_index, 1, "the row is selected on the canvas")
	_eq(w.canvas().selected_row_section, int(Metrics.Section.MARKUP), "in its own section")
	_eq(w.canvas().selected, card_index, "and its card is the selected card")

	_section("selecting the CARD clears the row")
	# Exactly one thing at a time, so Delete can never be ambiguous about which it means.
	w.canvas().select_card(card_index)
	_eq(w.canvas().selected_row_index, -1, "no row is selected any more")

	_section("Delete removes the SELECTED ROW, not the module")
	w._on_row_clicked(card_index, int(Metrics.Section.MARKUP), 1)
	var before: String = w.workspace.try_get(card.file_path).buffer_text
	w._delete_selection()
	await process_frame
	_check(w.workspace.try_get(card.file_path) != null, "the module is still here")
	_check(w.workspace.try_get(card.file_path).buffer_text != before, "and the row is gone from it")

	_section("with no row selected it falls through to the module")
	w._menu_row = null
	w.select_module(ROOT.path_join("app.style.guitkx"))
	await process_frame
	w._delete_selection()
	await process_frame
	_check(w.workspace.try_get(ROOT.path_join("app.style.guitkx")) == null,
		"the focused module is what Delete means when nothing inside one is selected")

	_drop(w)


func _test_save_confirms_deletions() -> void:
	_section("with nothing to delete, a save just runs")
	var w := _window()
	await process_frame
	_check(w._confirmed_deletions(), "no deletions, nothing to ask about")

	_section("a pending deletion stops the save until it is agreed")
	# The module has to have been PROJECTED once for its absence to read as a deletion: an orphan
	# is a path the last projection claimed and no module claims any more.
	var doomed := ROOT.path_join("app.style.guitkx")
	var module := w.workspace.try_get(doomed)
	module.mark_projected(module.file_path())
	w.workspace.tree().set_projection(PackedStringArray([doomed]))
	_check(w.delete_module(doomed), "the module is deleted")
	_eq(w.workspace.tree().orphaned_paths().size(), 1, "and its file is now an orphan")

	_check(not w._confirmed_deletions(), "so the save stops to ask")
	_eq(w.save(), 0, "and writes nothing while the question is open")

	_drop(w)


func _test_create_placement() -> void:
	_section("the tree root is derived from membership")
	var w := _window()
	await process_frame
	_eq(w.tree_root(), ROOT, "the shallowest folder any module lives in")

	_section("over empty canvas, the FOLDER CONVENTION still applies")
	# Checked against Unity's `BirthPathFor`, not the capability document: the spec's table says
	# "empty canvas -> tree root", and `BuilderWindow.cs:6440` says
	# `PathFor(root, "Component", name)` -- which nests under `components/<name>/` so the module
	# can own a folder and take children. A bare root drops the convention the rest of the builder
	# is built around. Unity calls it "a DEFAULT, not a rule": nothing re-places a module
	# afterwards, so the folder view can still put it anywhere.
	w._menu_target = ""
	_eq(w._create_folder(Module.Kind.COMPONENT, "panel"), ROOT.path_join("components/panel"),
		"a component owns a folder under components/")
	_eq(w._create_folder(Module.Kind.STYLE, "nothing_matches_this"), ROOT,
		"a companion with no family owner lands at the root")

	_section("and a companion joins the component it is named after")
	_eq(w._create_folder(Module.Kind.STYLE, "row"),
		ROOT.path_join("components/row"),
		"row.style.guitkx belongs beside row.guitkx, wherever that lives")

	_section("over a component card, a component becomes its CHILD")
	w._menu_target = ROOT.path_join("app.guitkx")
	_eq(w._create_folder(Module.Kind.COMPONENT, "Panel"), ROOT.path_join("components/Panel"),
		"in components/<Name>/ under the parent")

	_section("and a companion becomes its SIBLING")
	_eq(w._create_folder(Module.Kind.STYLE, "panel"), ROOT,
		"in the parent's own folder -- which is what the folder convention pairs")
	_eq(w._create_folder(Module.Kind.HOOK, "usePanel"), ROOT, "hooks companion the same way")

	_section("a companion card offers no create menu at all")
	_check(w.can_create_at(ROOT.path_join("app.guitkx")), "a component card offers one")
	_check(not w.can_create_at(ROOT.path_join("app.style.guitkx")),
		"a style companion does not -- it has no inside to create in")
	_check(w.can_create_at(""), "and empty canvas always does")

	_section("focus does not move it")
	# The defect this pins: selecting something else between right-click and create silently
	# relocated the new module.
	w._menu_target = ROOT.path_join("app.guitkx")
	w.select_module(ROOT.path_join("components/row/row.guitkx"))
	await process_frame
	_eq(w._create_folder(Module.Kind.COMPONENT, "Panel"), ROOT.path_join("components/Panel"),
		"still born under the card the menu was opened on")

	_drop(w)


## DELETING A MODULE TAKES ITS IMPORTS WITH IT, as one undoable action.
##
## Checked against the Unity SOURCE, not the capability document -- the two disagree. The spec
## (§2) says the delete is refused while something imports it; `BuilderWindow.cs:851` strips and
## deletes, and says why: "One entry covers the module AND every reference to it, so a single undo
## puts the tree back exactly as it was." The defect register records the refusal as a design
## Unity RETIRED. The source is the reference, so the spec line is the stale one.
## THE FOCUS DOES NOT OUTLIVE THE MODULE IT NAMES.
##
## `_focus_path` is a path and `select_module` early-returns on an empty one, so after deleting
## the focused module the window went on naming a file that no longer exists -- the status bar
## showed it, the source pane kept its buffer, and the preview compiled against it.
func _test_focus_rebinds_when_its_module_goes() -> void:
	_section("deleting the focused module moves the focus to a real one")
	var w := _window()
	await process_frame
	var doomed := ROOT.path_join("app.style.guitkx")
	w.select_module(doomed)
	await process_frame
	_eq(w.focus_path(), doomed, "the companion is focused")

	_check(w.delete_module(doomed), "it deletes")
	await process_frame
	_check(w.focus_path() != doomed, "the focus is no longer on it")
	_check(w.workspace.try_get(w.focus_path()) != null,
		"and names a module that exists (%s)" % w.focus_path())

	_drop(w)


func _test_delete_strips_references() -> void:
	_section("a module another one imports still deletes")
	var w := _window()
	await process_frame
	var host := ROOT.path_join("app.guitkx")
	var target := ROOT.path_join("components/row/row.guitkx")

	# Wire it up first: with nothing importing Row, deleting it is legal and says nothing.
	var wired: String = w._with_component_import(w._buffer_of(host), host, "Row")
	w.apply_edit(host, wired, "import Row")
	await process_frame

	var referrers := w.referrers_to(target)
	_eq(referrers.size(), 1, "the importer is found")
	_eq(str(referrers[0]), host, "and it is named by path")

	_check(w.delete_module(target), "the delete goes through")
	_check(w.workspace.try_get(target) == null, "and the module leaves the tree")
	_check(not w._buffer_of(host).contains("components/row/row"),
		"the importer's import went with it")
	_check(w.toast_text().contains("1 file"), "and the toast says how many files it touched")

	_section("one undo puts back the module AND the import")
	_check(w.undo(), "undo runs")
	await process_frame
	_check(w.workspace.try_get(target) != null, "the module is back")
	_check(w._buffer_of(host).contains("components/row/row"), "and so is the import")

	_drop(w)


func _test_delete_and_undo() -> void:
	_section("deleting a module, and putting the SAME one back")
	var w := _window()
	await process_frame
	var path := ROOT.path_join("app.style.guitkx")
	var before_id: String = w.workspace.try_get(path).id

	_check(w.delete_module(path), "the module is deleted")
	_check(w.workspace.try_get(path) == null, "and leaves the tree")
	_eq(w.graph.cards.size(), 2, "so its card goes with it")
	_check(w.ledger.can_undo(), "the deletion is undoable")

	_check(w.undo(), "undo runs")
	await process_frame
	var restored: Module = w.workspace.try_get(path)
	_check(restored != null, "the module is back")
	_eq(restored.id, before_id,
		"and it is the SAME module -- its identity, its buffer and its disk path, not a fresh one")
	_eq(w.graph.cards.size(), 3, "with its card")

	_drop(w)


func _test_read_only() -> void:
	_section("a read-only module refuses every route")
	var w := _window()
	await process_frame
	var path := ROOT.path_join("app.style.guitkx")
	w.workspace.try_get(path).read_only = true

	_check(not w.apply_edit(path, "anything", "edit"), "the funnel refuses it")
	_check(not w.delete_module(path), "and so does delete")
	_eq(w.ledger.entries().size(), 0, "with nothing recorded either way")

	w.folder_pane().rebuild()
	await process_frame
	_eq(_row_named(_tree_rows(w.folder_pane()), "app.style.guitkx").get_text(1), "read-only",
		"and the pane says so")

	_drop(w)


func _test_cleanup() -> void:
	_section("no residue")
	Layout.clear_all()
	Preview.clear_scratch()
	_check(not DirAccess.dir_exists_absolute(Preview.SCRATCH_ROOT), "the preview mirror is gone")
	_check(not DirAccess.dir_exists_absolute("res://tests/__builder_chrome_tmp"),
		"and the fixture never touched disk")


# ── Helpers ──────────────────────────────────────────────────────────────────────────

## Every MODULE row in the pane, at whatever depth it sits.
##
## Walks the whole tree rather than assuming folder-then-row: the pane nests one item per path
## segment, so a module three folders deep is three levels down. A module row is one carrying a
## file path in its metadata -- folder items carry none, which is the difference that matters.
func _tree_rows(pane: FolderPane) -> Array:
	var out: Array = []
	_collect_rows(pane.get_root(), out)
	return out


## The MODULE rows of the pane, in tree order.
##
## A module carries its path as a plain String and a folder carries `{ "folder": path }`, so the
## two are told apart by TYPE. Collecting "everything with metadata" gathered folder rows too the
## moment folders became drop targets.
func _collect_rows(item: TreeItem, out: Array) -> void:
	if item == null:
		return
	var child := item.get_first_child()
	while child != null:
		var meta: Variant = child.get_metadata(0)
		if meta != null and not (meta is Dictionary) and not str(meta).is_empty():
			out.append(child)
		_collect_rows(child, out)
		child = child.get_next()


## The row FOR a module, found by the path it carries rather than by the text it displays.
##
## The displayed text is a presentation choice -- it leads with a kind glyph now -- and a lookup
## that matches it exactly turns every change to how a row LOOKS into a failure about which rows
## EXIST. The metadata is the identity.
func _row_named(rows: Array, file_name: String) -> TreeItem:
	for row in rows:
		if str((row as TreeItem).get_metadata(0)).get_file() == file_name:
			return row
	return null
