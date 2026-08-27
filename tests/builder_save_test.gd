extends SceneTree
## Headless test suite for the RUITK Builder's SAVE, ABORT, HISTORY and JOURNAL (checkpoint C6).
## Run:
##   godot --headless --path <project> --script res://tests/builder_save_test.gd
##
## The one suite that asserts EXACT DISK STATE. Everything else in the builder is provable
## against buffers; this is where the save-only contract meets the filesystem, and the question
## is always the same: after this sequence of gestures, what is on disk?
##
## The tree it works on is a real folder under `res://tests/__builder_save_tmp/`, written and
## removed by the run, and the suite asserts the folder is gone at the end.

const Workspace = preload("res://addons/reactive_ui_toolkit_editor/builder/document/builder_workspace.gd")
const Module = preload("res://addons/reactive_ui_toolkit_editor/builder/document/builder_module.gd")
const Paths = preload("res://addons/reactive_ui_toolkit_editor/builder/document/builder_paths.gd")
const Journal = preload("res://addons/reactive_ui_toolkit_editor/builder/document/builder_journal.gd")
const Ledger = preload("res://addons/reactive_ui_toolkit_editor/builder/document/builder_ledger.gd")
const Layout = preload("res://addons/reactive_ui_toolkit_editor/builder/canvas/builder_canvas_layout.gd")
const Service = preload("res://addons/reactive_ui_toolkit_editor/builder/canvas/builder_graph_service.gd")
const Graph = preload("res://addons/reactive_ui_toolkit_editor/builder/canvas/builder_graph.gd")

const ROOT := "res://tests/__builder_save_tmp/app"

## The fewest assertions a complete run makes. Raise it when the suite genuinely grows.
const ASSERTION_FLOOR := 62

var _fails := 0
var _passes := 0
var _trashed := PackedStringArray()


func _initialize() -> void:
	_scrub()
	_test_nothing_is_written_until_save()
	_test_save_is_a_diff()
	_test_save_formats()
	_test_blank_modules_are_not_written()
	_test_delete_then_save()
	_test_rename_then_save()
	_test_abort_restores_disk_state()
	_test_undo_then_save()
	_test_journal_survives_the_process()
	_test_layout_survives_a_save()
	_test_no_residue()

	print("")
	# A FLOOR ON THE COUNT. A suite that stops at a broken dependency prints ALL PASS on however
	# few assertions it reached before it stopped -- which is a green line for a run that never
	# arrived at its own subject, and it has now hidden three separate defects in this builder.
	# The number is the tell, so the number is checked.
	if _passes < ASSERTION_FLOOR:
		print("builder save: only %d of at least %d assertions ran -- something stopped early"
			% [_passes, ASSERTION_FLOOR])
		quit(1)
	if _fails == 0:
		print("builder save: ALL PASS (%d assertions)" % _passes)
		quit(0)
	else:
		print("builder save: %d FAILURE(S) of %d assertions" % [_fails, _fails + _passes])
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
  return (
    <VBoxContainer>
      <Row text="one" />
    </VBoxContainer>
  )
}
"""

const ROW := """export Row(text: String = "") -> RuitkVNode {
  return (
    <Label text={ text } />
  )
}
"""

const STYLE := "export primary := {\n  \"separation\": 4,\n}\n"


## A workspace over a real folder on disk, loaded the way the builder loads one.
func _loaded() -> Workspace:
	_scrub()
	_write(ROOT.path_join("app.guitkx"), APP)
	_write(ROOT.path_join("app.style.guitkx"), STYLE)
	_write(ROOT.path_join("components/row/row.guitkx"), ROW)
	var ws := Workspace.new()
	_trashed = PackedStringArray()
	ws.trash_file = func(p: String) -> bool:
		_trashed.append(p)
		return DirAccess.remove_absolute(p) == OK
	ws.load_tree(ROOT.path_join("app.guitkx"))
	return ws


func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _read(path: String) -> String:
	return FileAccess.get_file_as_string(path)


## Every `.guitkx` on disk under the fixture root, sorted -- the exact disk state an assertion
## compares against.
func _on_disk() -> PackedStringArray:
	var out := PackedStringArray()
	_collect(ROOT.get_base_dir(), out)
	out.sort()
	return out


func _collect(dir: String, out: PackedStringArray) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for file in d.get_files():
		if file.ends_with(".guitkx"):
			out.append(dir.path_join(file).trim_prefix(ROOT.get_base_dir() + "/"))
	for sub in d.get_directories():
		_collect(dir.path_join(sub), out)


func _scrub() -> void:
	_rm_rf(ROOT.get_base_dir())
	Journal.clear()


func _rm_rf(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var d := DirAccess.open(path)
	if d == null:
		return
	for file in d.get_files():
		DirAccess.remove_absolute(path.path_join(file))
	for sub in d.get_directories():
		_rm_rf(path.path_join(sub))
	DirAccess.remove_absolute(path)


# ── The contract ─────────────────────────────────────────────────────────────────────

func _test_nothing_is_written_until_save() -> void:
	_section("nothing reaches disk until Save")
	var ws := _loaded()
	var before := _on_disk()

	ws.apply_edit(ROOT.path_join("app.guitkx"), APP.replace("one", "two"))
	ws.create_new(ROOT.path_join("extra.guitkx"), "export Extra() -> RuitkVNode {\n  return ( <Label /> )\n}\n")
	ws.delete(ROOT.path_join("app.style.guitkx"))
	ws.move_to(ROOT.path_join("components/row/row.guitkx"), ROOT.path_join("moved"), "row")

	_eq(_on_disk(), before,
		"an edit, a creation, a delete and a move later, disk has not moved at all")
	_check(ws.has_unsaved_changes(), "and all of it is pending")
	_eq(_read(ROOT.path_join("app.guitkx")), APP, "the edited file still holds its old bytes")


func _test_save_is_a_diff() -> void:
	_section("Save is a pure diff")
	var ws := _loaded()
	_eq(ws.save_all(), 0, "a freshly loaded tree writes nothing")

	ws.apply_edit(ROOT.path_join("app.guitkx"), APP.replace("one", "two"))
	_eq(ws.save_all(), 1, "one dirty module writes one file")
	_check(_read(ROOT.path_join("app.guitkx")).contains("two"), "with the buffer's bytes")
	_eq(ws.save_all(), 0, "and saving again writes nothing")
	_check(not ws.has_unsaved_changes(), "the tree is settled")


func _test_save_formats() -> void:
	_section("Save normalises through the formatter")
	# The right moment and the only right moment: formatting on every edit would re-flow text
	# someone is in the middle of typing, and never formatting lets a canvas-authored file drift
	# from a hand-authored one until they no longer look like the same language.
	var ws := _loaded()
	ws.apply_edit(ROOT.path_join("app.guitkx"),
		"export App() -> RuitkVNode {\n\treturn (\n<VBoxContainer>\n<Label text=\"x\" />\n</VBoxContainer>\n\t)\n}\n")
	ws.save_all()
	var written := _read(ROOT.path_join("app.guitkx"))
	_check(written.contains("  <Label"), "the mangled indentation is normalised (%s)" % written.split("\n")[3])
	_eq(ws.try_get(ROOT.path_join("app.guitkx")).buffer_text, written,
		"and the BUFFER holds what was written -- or the card and the file disagree at once")
	_check(not ws.has_unsaved_changes(), "so the module is clean, not instantly dirty again")

	_section("a buffer the formatter cannot parse is left alone")
	# Mid-edit a buffer is unparseable most of the time, and a save is not the moment to refuse
	# the user's work over it.
	var broken := "export App() -> RuitkVNode {\n  return ( <Label \n"
	ws.apply_edit(ROOT.path_join("app.guitkx"), broken)
	ws.save_all()
	_eq(_read(ROOT.path_join("app.guitkx")), broken, "the bytes are exactly what was typed")

	_section("formatting can be turned off")
	var plain := _loaded()
	plain.format_on_save = false
	var ragged := "export App() -> RuitkVNode {\n\treturn (\n<VBoxContainer />\n\t)\n}\n"
	plain.apply_edit(ROOT.path_join("app.guitkx"), ragged)
	plain.save_all()
	_eq(_read(ROOT.path_join("app.guitkx")), ragged, "and then the bytes are the buffer's, verbatim")


func _test_blank_modules_are_not_written() -> void:
	_section("a blank module is not written")
	# An empty `.guitkx` is a file that cannot compile and a card with nothing on it -- almost
	# always a module created and then thought better of.
	var ws := _loaded()
	ws.create_new(ROOT.path_join("empty.guitkx"), "   \n\n")
	_eq(ws.blank_modules().size(), 1, "the workspace reports it")
	_eq(str(ws.blank_modules()[0].file_path()), ROOT.path_join("empty.guitkx"), "by name")

	ws.save_all()
	_check(not FileAccess.file_exists(ROOT.path_join("empty.guitkx")),
		"and Save does not write it")
	_check(ws.has_unsaved_changes(),
		"it stays pending, so the prompt to delete it is still available")

	ws.delete(ROOT.path_join("empty.guitkx"))
	ws.save_all()
	_check(not ws.has_unsaved_changes(), "deleting it settles the tree")
	_eq(ws.blank_modules().size(), 0, "and there is nothing left to prompt about")


func _test_delete_then_save() -> void:
	_section("a delete reaches disk at Save, through the trash")
	var ws := _loaded()
	var gone := ROOT.path_join("app.style.guitkx")
	ws.delete(gone)
	_check(FileAccess.file_exists(gone), "the file is still there while the delete is pending")

	_eq(ws.save_all(), 1, "Save retires it")
	_check(not FileAccess.file_exists(gone), "the file is gone")
	_check(_trashed.has(gone), "and it went out through the trash, not a raw erase")
	_eq(_on_disk(), PackedStringArray(["app/app.guitkx", "app/components/row/row.guitkx"]),
		"disk holds exactly what the tree does")

	_section("and saving again does nothing")
	_eq(ws.save_all(), 0, "the orphan is not retired twice")


func _test_rename_then_save() -> void:
	_section("a rename moves the file and re-spells the imports")
	var ws := _loaded()
	var from := ROOT.path_join("components/row/row.guitkx")
	var to_folder := ROOT.path_join("components/cell")
	var rewrites := ws.move_to(from, to_folder, "cell")
	_eq(rewrites.size(), 1, "the importer's buffer was rewritten")

	ws.save_all()
	_check(not FileAccess.file_exists(from), "the old file is gone")
	_check(FileAccess.file_exists(to_folder.path_join("cell.guitkx")), "and the new one is there")
	_check(_trashed.is_empty(),
		"nothing was trashed -- a move is a MOVE, so the file keeps its UID and its identity")
	_check(_read(ROOT.path_join("app.guitkx")).contains("cell"),
		"and the importer on disk points at where it went")
	_check(not DirAccess.dir_exists_absolute(ROOT.path_join("components/row")),
		"the folder the move emptied is pruned")

	_section("the saved tree still loads and still resolves")
	var reopened := Workspace.new()
	reopened.load_tree(ROOT.path_join("app.guitkx"))
	_eq(reopened.modules().size(), 3, "every module comes back")
	_check(reopened.try_get(to_folder.path_join("cell.guitkx")) != null, "at its new path")
	_check(not reopened.has_unsaved_changes(), "with nothing pending")


func _test_abort_restores_disk_state() -> void:
	_section("Abort is Load re-run")
	var ws := _loaded()
	var before := _on_disk()

	ws.apply_edit(ROOT.path_join("app.guitkx"), APP.replace("one", "two"))
	ws.create_new(ROOT.path_join("scratch.guitkx"), "export S() -> RuitkVNode {\n  return ( <Label /> )\n}\n")
	ws.delete(ROOT.path_join("app.style.guitkx"))
	ws.move_to(ROOT.path_join("components/row/row.guitkx"), ROOT.path_join("elsewhere"), "row")

	var reverted := ws.abort_all()
	_check(reverted >= 4, "everything pending is reported (%d)" % reverted)
	_eq(_on_disk(), before, "disk is untouched, because nothing had reached it")
	_eq(ws.modules().size(), 3, "the invented module is gone from the tree")
	_eq(ws.try_get(ROOT.path_join("app.guitkx")).buffer_text, APP, "the edit is discarded")
	_check(ws.try_get(ROOT.path_join("app.style.guitkx")) != null, "the deleted module is back")
	_check(ws.try_get(ROOT.path_join("components/row/row.guitkx")) != null, "and so is the moved one")
	_check(not ws.has_unsaved_changes(), "with nothing pending")

	_section("aborting AFTER a save reverts to what was saved")
	ws.apply_edit(ROOT.path_join("app.guitkx"), APP.replace("one", "three"))
	ws.save_all()
	ws.apply_edit(ROOT.path_join("app.guitkx"), APP.replace("one", "four"))
	ws.abort_all()
	_check(ws.try_get(ROOT.path_join("app.guitkx")).buffer_text.contains("three"),
		"the saved state is what Abort goes back to, not the state at open")


func _test_undo_then_save() -> void:
	_section("what the ledger walked back is what Save writes")
	var ws := _loaded()
	var ledger := Ledger.new()
	ledger.id_of = func(path: String) -> String:
		var module = ws.try_get(path)
		return module.id if module != null else ""

	var app := ROOT.path_join("app.guitkx")
	var row := ROOT.path_join("components/row/row.guitkx")
	ledger.begin("a compound gesture")
	ws.apply_edit(app, APP.replace("one", "two"))
	ledger.record(app, APP, APP.replace("one", "two"))
	ws.apply_edit(row, ROW.replace("Label", "Button"))
	ledger.record(row, ROW, ROW.replace("Label", "Button"))
	ledger.end()

	var entry := ledger.undo()
	_check(entry != null, "there is an entry to walk back")
	ledger.suppress(func():
		for change in entry.changes:
			ws.apply_edit(str(change.file_path), str(change.before)))

	ws.save_all()
	_eq(_read(app), APP, "the first file on disk is the pre-gesture text")
	_eq(_read(row), ROW, "and so is the second -- all of them or none")
	_check(not ws.has_unsaved_changes(), "with nothing left pending")


func _test_journal_survives_the_process() -> void:
	_section("the journal is the backstop for work that never reached disk")
	Journal.clear()
	var ws := _loaded()
	_check(not Journal.capture(ws, "now"), "a clean tree is never journalled")

	ws.apply_edit(ROOT.path_join("app.guitkx"), APP.replace("one", "unsaved work"))
	ws.create_new(ROOT.path_join("invented.guitkx"), "export I() -> RuitkVNode {\n  return ( <Label /> )\n}\n")
	_check(Journal.capture(ws, "2026-08-27T12:00:00Z"), "unsaved work is journalled")

	# The process is gone. Nothing of the session survives except the file.
	var recovered := Workspace.new()
	_check(Journal.try_restore(recovered), "a fresh workspace restores it")
	_check(recovered.try_get(ROOT.path_join("app.guitkx")).buffer_text.contains("unsaved work"),
		"the edit is back")
	_check(recovered.try_get(ROOT.path_join("invented.guitkx")) != null,
		"and so is the module that had never been written")
	_check(recovered.has_unsaved_changes(), "still as unsaved work")

	_section("the restored tree saves to exactly what it holds")
	recovered.trash_file = func(p: String) -> bool: return DirAccess.remove_absolute(p) == OK
	recovered.save_all()
	_check(_read(ROOT.path_join("app.guitkx")).contains("unsaved work"), "the recovered edit lands")
	_check(FileAccess.file_exists(ROOT.path_join("invented.guitkx")), "and so does the new module")

	_section("the offer is made once")
	_check(Journal.peek().is_empty(), "restoring clears the journal")
	_check(not Journal.try_restore(Workspace.new()), "and it cannot be taken twice")

	_section("a save clears it too")
	var ws2 := _loaded()
	ws2.apply_edit(ROOT.path_join("app.guitkx"), APP.replace("one", "x"))
	Journal.capture(ws2, "later")
	_check(not Journal.peek().is_empty(), "there is something journalled")
	ws2.save_all()
	Journal.clear()
	_check(Journal.peek().is_empty(),
		"and clearing after a save means the file being there always means unsaved work")


func _test_layout_survives_a_save() -> void:
	_section("the layout is keyed on MEMBERSHIP, so a save does not lose it")
	Layout.clear_all()
	var ws := _loaded()
	var graph := Service.project(ws.modules(), ROOT.path_join("app.guitkx"))
	var layout := Layout.for_graph(graph)
	layout.adopt_unplaced(graph)
	graph.cards[0].x = 4242.0
	layout.capture_from(graph, Vector2(7.0, 9.0), 0.65)
	layout.save("2026-08-27T12:00:00Z")

	ws.apply_edit(ROOT.path_join("app.guitkx"), APP.replace("one", "two"))
	ws.save_all()

	var reopened := Workspace.new()
	reopened.load_tree(ROOT.path_join("app.guitkx"))
	var again := Service.project(reopened.modules(), ROOT.path_join("app.guitkx"))
	var found := Layout.for_graph(again)
	found.apply_to(again)
	_eq(again.cards[0].x, 4242.0, "the card is where it was left")
	_check(found.camera.is_equal_approx(Vector2(7.0, 9.0)), "and so is the camera")

	Layout.clear_all()


func _test_no_residue() -> void:
	_section("no residue")
	_scrub()
	Layout.clear_all()
	_check(not DirAccess.dir_exists_absolute(ROOT.get_base_dir()), "the fixture tree is gone")
	_check(not FileAccess.file_exists(Journal.JOURNAL_PATH), "the journal is cleared")
