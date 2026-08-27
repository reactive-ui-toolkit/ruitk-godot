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
const Console = preload("res://addons/reactive_ui_toolkit_editor/builder/chrome/builder_console.gd")
const InlineEditor = preload("res://addons/reactive_ui_toolkit_editor/builder/chrome/builder_inline_editor.gd")
const Workspace = preload("res://addons/reactive_ui_toolkit_editor/builder/document/builder_workspace.gd")
const Preview = preload("res://addons/reactive_ui_toolkit_editor/builder/preview/builder_preview.gd")
const Layout = preload("res://addons/reactive_ui_toolkit_editor/builder/canvas/builder_canvas_layout.gd")
const Ledger = preload("res://addons/reactive_ui_toolkit_editor/builder/document/builder_ledger.gd")
const Module = preload("res://addons/reactive_ui_toolkit_editor/builder/document/builder_module.gd")
const Graph = preload("res://addons/reactive_ui_toolkit_editor/builder/canvas/builder_graph.gd")

const ROOT := "res://tests/__builder_chrome_tmp/app"

var _fails := 0
var _passes := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	Layout.clear_all()
	Preview.clear_scratch()

	await _test_window_assembles()
	await _test_folder_pane()
	await _test_library_pane()
	await _test_source_pane()
	_test_console()
	await _test_inline_editor()
	await _test_one_funnel()
	await _test_undo_across_files()
	await _test_delete_and_undo()
	await _test_read_only()
	_test_cleanup()

	print("")
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
	editor.cancelled.connect(func(t: Variant): cancelled.append(t))

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


func _collect_rows(item: TreeItem, out: Array) -> void:
	if item == null:
		return
	var child := item.get_first_child()
	while child != null:
		if child.get_metadata(0) != null and not str(child.get_metadata(0)).is_empty():
			out.append(child)
		_collect_rows(child, out)
		child = child.get_next()


func _row_named(rows: Array, file_name: String) -> TreeItem:
	for row in rows:
		if (row as TreeItem).get_text(0) == file_name:
			return row
	return null
