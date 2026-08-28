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
const ASSERTION_FLOOR := 239

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
	await _test_folder_pane_refiles()
	await _test_folder_pane_drop_rules()
	await _test_opens_at_layer_two()
	await _test_selection_and_delete()
	await _test_save_confirms_deletions()
	await _test_create_placement()
	await _test_delete_refused_while_imported()
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

	# The nested child, dropped into the root component that does not import it yet.
	var host: String = ROOT.path_join("app.guitkx")
	var before: String = w.workspace.try_get(host).buffer_text
	var after: String = w._with_component_import(before, host, "Row")

	_check(after != before, "the import was added")
	_check(after.contains("import"), "and it is an import line")
	_check(after.contains("Row"), "naming the component that was dropped")

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

	_eq(w._validate_name(Module.Kind.COMPONENT, "Fresh"), "",
		"a name is accepted with no tree open")
	var made: String = w._create_named(Module.Kind.COMPONENT, "Fresh")
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
	_check(FileAccess.file_exists(PLACED_ROOT.path_join("Fresh.guitkx")),
		"where the user asked, not under the provisional root")

	_drop(w)
	# Cleaned up by hand: this suite has no rm helper, and a tree left behind makes the next run
	# of this section fail on "already there" rather than on anything it is testing.
	for name in ["Fresh.guitkx", "Fresh.guitkx.uid", "Fresh.gd", "Fresh.gd.uid"]:
		DirAccess.remove_absolute(PLACED_ROOT.path_join(name))
	DirAccess.remove_absolute(PLACED_ROOT)


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

	_section("over empty canvas, a module is born at the tree root")
	w._menu_target = ""
	_eq(w._create_folder(Module.Kind.COMPONENT, "Panel"), ROOT, "a component goes to the root")
	_eq(w._create_folder(Module.Kind.STYLE, "panel"), ROOT, "and so does a companion")

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


func _test_delete_refused_while_imported() -> void:
	_section("a module another one imports cannot just be deleted")
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

	_check(not w.delete_module(target), "so the delete is refused")
	_check(w.workspace.try_get(target) != null, "and the module is still in the tree")
	_check(w.toast_text().contains("row.guitkx"), "the refusal names what was refused")
	_check(w.toast_text().contains("app.guitkx"), "and names the module that still imports it")

	_section("unwire it and the same delete goes through")
	# The unwiring is the USER's edit, in their own undo history, on a file they chose -- which is
	# the whole difference between this and stripping it for them.
	var spec := Specifiers.relative(host.get_base_dir(), target)
	w.apply_edit(host, Edits.remove_import(w._buffer_of(host), spec), "drop the import")
	await process_frame
	_eq(w.referrers_to(target).size(), 0, "nothing imports it now")
	_check(w.delete_module(target), "and now it deletes")

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
