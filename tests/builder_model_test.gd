extends SceneTree
## Headless test suite for the RUITK Builder's DOCUMENT MODEL (checkpoint C0). Run:
##   godot --headless --path <project> --script res://tests/builder_model_test.gd
##
## The model is where the builder's correctness lives: path arithmetic, tree operations,
## orphans, the naming convention, specifier round trips, save/abort projection and the
## cross-file ledger. All of it is pure or FileAccess-only, so all of it is provable without
## an editor -- which is the point. The Unity leg's equivalent suite is what caught its whole
## save-contract defect class before any of it reached a user.
##
## Everything that touches disk does so under `res://tests/__builder_tmp/`, which is created
## and removed by the run; a clean tree is asserted at the end, so a suite that leaves
## residue fails rather than quietly polluting the project.

const Paths = preload("res://addons/reactive_ui_toolkit_editor/builder/document/builder_paths.gd")
const Module = preload("res://addons/reactive_ui_toolkit_editor/builder/document/builder_module.gd")
const BTree = preload("res://addons/reactive_ui_toolkit_editor/builder/document/builder_tree.gd")
const Naming = preload("res://addons/reactive_ui_toolkit_editor/builder/document/builder_naming.gd")
const Specifiers = preload("res://addons/reactive_ui_toolkit_editor/builder/document/builder_specifiers.gd")
const Workspace = preload("res://addons/reactive_ui_toolkit_editor/builder/document/builder_workspace.gd")
const Ledger = preload("res://addons/reactive_ui_toolkit_editor/builder/document/builder_ledger.gd")
const Journal = preload("res://addons/reactive_ui_toolkit_editor/builder/document/builder_journal.gd")

const SANDBOX := "res://tests/__builder_tmp"

## The number of assertions a complete run makes. KEPT EXACT, and raised with the suite.
##
## Left slack, this guard does not work: a script error aborted one test mid-run and the suite
## still printed ALL PASS, because the count it reached was comfortably above a floor set several
## additions ago. The floor only catches a truncated run while it sits AT the real count.
const ASSERTION_FLOOR := 347

var _fails := 0
var _passes := 0


func _initialize() -> void:
	_scrub_sandbox()
	_test_paths()
	_test_module_derivation()
	_test_module_edits()
	_test_module_round_trip()
	_test_tree_indexing()
	_test_delete_is_absence()
	_test_move_carries_the_folder()
	_test_move_is_not_a_delete()
	_test_unsaved_work()
	_test_abort_is_load_rerun()
	_test_validation()
	_test_tree_round_trip()
	_test_naming()
	_test_specifiers()
	_test_root_resolution()
	_test_workspace_load()
	_test_workspace_create_and_delete()
	_test_workspace_move_reconciles_imports()
	_test_workspace_save()
	_test_workspace_save_moves_artifacts()
	_test_workspace_abort()
	_test_workspace_read_only()
	_test_workspace_unlocated()
	_test_journal()
	_test_ledger()
	_test_no_residue()

	print("")
	# A FLOOR ON THE COUNT. A suite that stops at a broken dependency prints ALL PASS on however
	# few assertions it reached before it stopped -- which is a green line for a run that never
	# arrived at its own subject, and it has now hidden three separate defects in this builder.
	# The number is the tell, so the number is checked.
	if _passes < ASSERTION_FLOOR:
		print("builder model: only %d of at least %d assertions ran -- something stopped early"
			% [_passes, ASSERTION_FLOOR])
		quit(1)
	if _fails == 0:
		print("builder model: ALL PASS (%d assertions)" % _passes)
		quit(0)
	else:
		print("builder model: %d FAILURE(S) of %d assertions" % [_fails, _fails + _passes])
		quit(1)


func _check(ok: bool, what: String) -> void:
	if ok:
		_passes += 1
		return
	_fails += 1
	print("  FAIL  %s" % what)


func _section(title: String) -> void:
	print(title)


# ── Fixtures ─────────────────────────────────────────────────────────────────────────

func _make(folder: String, name: String, kind: Module.Kind, text: String, on_disk: bool) -> Module:
	var m := Module.new()
	m.id = Module.new_id()
	m.folder = Paths.canon(folder)
	m.name = name
	m.kind = kind
	m.buffer_text = text
	m.projected_text = text if on_disk else ""
	m.disk_path = m.file_path() if on_disk else ""
	return m


func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _read(path: String) -> String:
	return FileAccess.get_file_as_string(path)


func _scrub_sandbox() -> void:
	_rm_rf(SANDBOX)
	_rm_rf(Workspace.UNSAVED_ROOT)
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


# ── Paths ────────────────────────────────────────────────────────────────────────────

func _test_paths() -> void:
	_section("paths")
	_check(Paths.canon("") == "", "an empty path canonicalizes to empty")
	_check(Paths.canon("res://a/b/../c.guitkx") == "res://a/c.guitkx", "`..` is folded out")
	_check(Paths.canon("res://a\\b.guitkx") == "res://a/b.guitkx", "backslashes become forward slashes")
	_check(Paths.canon("res://a/") == "res://a", "a trailing slash is dropped")
	_check(Paths.canon("res://") == "res://", "the project root keeps its slashes")
	_check(Paths.canon("user://") == "user://",
		"and so does any scheme root -- trimming it would leave `user:/`, which names nothing")
	_check(Paths.canon("res://a/b/") == "res://a/b", "a folder's trailing slash is still dropped")
	_check(Paths.same("res://A/B.guitkx", "res://a/b.guitkx"), "comparison folds case")
	_check(Paths.key("res://A/B.guitkx") == "res://a/b.guitkx", "the index key folds case")

	_check(Paths.is_under("res://ui/panel.guitkx", "res://ui"), "a file under a folder is under it")
	_check(Paths.is_under("res://ui", "res://ui"), "a folder is under itself")
	_check(not Paths.is_under("res://ui2/panel.guitkx", "res://ui"),
		"`ui2` is NOT under `ui` -- the boundary is a path segment, not a string prefix")
	_check(not Paths.is_under("res://ui/panel.guitkx", ""), "nothing is under an empty folder")

	_check(Paths.is_writable_location("res://ui/panel.guitkx"), "project sources are writable")
	_check(not Paths.is_writable_location("res://addons/x/panel.guitkx"),
		"`res://addons/` is the package directory and is not writable")
	_check(not Paths.is_writable_location("user://panel.guitkx"), "outside res:// is not writable")
	_check(not Paths.is_writable_location("/tmp/panel.guitkx"), "an OS path is not writable")

	var art := Paths.companion_artifacts("res://ui/panel/panel.guitkx")
	_check(art.size() == 4, "a module owns four companion artifacts")
	_check(art.has("res://ui/panel/panel.guitkx.uid"), "the guitkx UID sidecar is one of them")
	_check(art.has("res://ui/panel/panel.guitkx.diags.json"), "the diagnostics sidecar is one of them")
	_check(art.has("res://ui/panel/panel.gd"), "the generated script is one of them")
	_check(art.has("res://ui/panel/panel.gd.uid"), "the generated script's UID sidecar is one of them")
	_check(Paths.companion_artifacts("").is_empty(), "no path owns no artifacts")


# ── Module ───────────────────────────────────────────────────────────────────────────

func _test_module_derivation() -> void:
	_section("derived path and kind suffixes")
	var comp := SANDBOX.path_join("showcase")
	var c := _make(comp, "showcase", Module.Kind.COMPONENT, "x", true)
	var s := _make(comp, "showcase", Module.Kind.STYLE, "", true)
	var h := _make(comp, "use_thing", Module.Kind.HOOK, "", false)
	_check(c.file_path().ends_with("showcase.guitkx"), "a component takes the plain suffix")
	_check(s.file_path().ends_with("showcase.style.guitkx"), "a style takes the `.style` infix")
	_check(h.file_path().ends_with("use_thing.hooks.guitkx"), "a hook takes the `.hooks` infix")
	_check(_make("", "x", Module.Kind.COMPONENT, "", false).file_path() == "",
		"a module with no folder has no derivable path")
	_check(_make(comp, "", Module.Kind.COMPONENT, "", false).file_path() == "",
		"a module with no name has no derivable path")

	_section("never-written stays never-written")
	_check(not h.is_on_disk(), "a fresh module is not on disk")
	h.disk_path = ""
	_check(not h.is_on_disk(), "an empty disk path is still not on disk")
	_check(c.is_on_disk(), "a written module is on disk")

	_section("folder ownership")
	_check(c.owns_folder(), "a component named after its folder owns it")
	_check(not s.owns_folder(), "a style companion does not own the folder")
	_check(not _make(comp, "showcase", Module.Kind.HOOK, "", false).owns_folder(),
		"a hook sharing the component name still does not own it")
	_check(not _make(comp, "other", Module.Kind.COMPONENT, "", false).owns_folder(),
		"a component NOT named after its folder does not own it")
	_check(_make(SANDBOX.path_join("Showcase"), "showcase", Module.Kind.COMPONENT, "", false).owns_folder(),
		"ownership folds case, like the filesystem does")

	_section("file-name splitting")
	var sp := Module.split_file_name("panel.style.guitkx")
	_check(str(sp["name"]) == "panel" and sp["kind"] == Module.Kind.STYLE, "`.style.guitkx` splits to a style")
	sp = Module.split_file_name("panel.hooks.guitkx")
	_check(str(sp["name"]) == "panel" and sp["kind"] == Module.Kind.HOOK, "`.hooks.guitkx` splits to a hook")
	sp = Module.split_file_name("panel.guitkx")
	_check(str(sp["name"]) == "panel" and sp["kind"] == Module.Kind.COMPONENT, "a plain `.guitkx` splits to a component")
	sp = Module.split_file_name("panel.STYLE.GuiTkx")
	_check(sp["kind"] == Module.Kind.STYLE, "the suffix test folds case")
	sp = Module.split_file_name("notes.txt")
	_check(str(sp["name"]) == "notes.txt", "a name with no module suffix keeps every character")
	_check(Module.name_of("res://ui/panel.style.guitkx") == "panel", "name_of strips the whole suffix")
	_check(Module.kind_of("res://ui/panel.hooks.guitkx") == Module.Kind.HOOK, "kind_of reads the suffix")

	_section("identity")
	var ids := {}
	for _i in range(64):
		ids[Module.new_id()] = true
	_check(ids.size() == 64, "ids generated back to back do not collide")


func _test_module_edits() -> void:
	_section("dirtiness is derived, not maintained")
	var clean := _make(SANDBOX, "clean", Module.Kind.COMPONENT, "same", true)
	_check(not clean.is_dirty(), "text equal to the projected text is clean")
	_check(clean.apply_edit("different"), "an edit is taken")
	_check(clean.is_dirty(), "and makes the module dirty")
	clean.mark_projected(clean.file_path())
	_check(not clean.is_dirty(), "projecting makes it clean again")

	_section("read-only is the last line of defence")
	var ro := _make(SANDBOX, "package", Module.Kind.COMPONENT, "x", true)
	ro.read_only = true
	_check(not ro.apply_edit("y"), "a read-only module refuses an edit")
	_check(ro.buffer_text == "x", "and its buffer is untouched")

	_section("line endings")
	var crlf := Module.from_file(SANDBOX.path_join("crlf.guitkx"), "a\r\nb\r\n", false)
	_check(crlf.buffer_text == "a\nb\n", "a CRLF file is LF-normalized in memory")
	_check(crlf.used_crlf, "and remembers the flavor it came from")
	_check(crlf.to_disk_text() == "a\r\nb\r\n", "so Save writes the bytes the file used before")
	var lf := Module.from_file(SANDBOX.path_join("lf.guitkx"), "a\nb\n", false)
	_check(not lf.used_crlf and lf.to_disk_text() == "a\nb\n", "an LF file stays LF")
	_check(not crlf.apply_edit("a\r\nb"), "a buffer carrying CR is refused")
	_check(Module.normalize_lf("a\rb\r\nc") == "a\nb\nc", "a lone CR normalizes too")

	_section("adopting external change")
	var ad := Module.from_file(SANDBOX.path_join("ad.guitkx"), "one\n", false)
	_check(not ad.adopt_disk_text("one\n"), "adopting identical text reports no change")
	_check(ad.adopt_disk_text("two\n"), "adopting different text reports a change")
	_check(ad.buffer_text == "two\n" and not ad.is_dirty(), "and leaves the module clean at the new text")

	_section("moved is derived from where it belongs")
	var mv := _make(SANDBOX, "mv", Module.Kind.COMPONENT, "x", true)
	_check(not mv.has_moved(), "a module at its own path has not moved")
	mv.folder = SANDBOX.path_join("elsewhere")
	_check(mv.has_moved(), "changing the folder makes it moved")
	var never := _make(SANDBOX, "never", Module.Kind.COMPONENT, "x", false)
	never.folder = SANDBOX.path_join("elsewhere")
	_check(not never.has_moved(), "a module with no file cannot have moved")


func _test_module_round_trip() -> void:
	_section("module journal round trip")
	var m := _make(SANDBOX, "round", Module.Kind.STYLE, "text", true)
	m.used_crlf = true
	var back := Module.from_dict(m.to_dict())
	_check(back.id == m.id, "the stable id survives the trip")
	_check(back.kind == Module.Kind.STYLE, "so does the kind")
	_check(back.file_path() == m.file_path(), "so does the derived path")
	_check(back.used_crlf, "so does the EOL flavor")
	_check(not back.is_dirty(), "a clean module comes back clean")

	var fresh := Module.fresh(SANDBOX, "fresh", Module.Kind.COMPONENT, "z")
	var fresh_back := Module.from_dict(fresh.to_dict())
	_check(not fresh_back.is_on_disk(),
		"a never-written module stays never-written -- the fact the trip must not lose")
	_check(fresh_back.is_dirty(), "and is still unsaved work")

	var id_less := Module.from_dict({ "folder": SANDBOX, "name": "x" })
	_check(not id_less.id.is_empty(), "a payload with no id is given one rather than left broken")
	_check(id_less.kind == Module.Kind.COMPONENT, "and defaults to a component")


# ── Tree ─────────────────────────────────────────────────────────────────────────────

func _test_tree_indexing() -> void:
	_section("tree indexing")
	var comp := SANDBOX.path_join("showcase")
	var t := BTree.new()
	var c := _make(comp, "showcase", Module.Kind.COMPONENT, "x", true)
	var s := _make(comp, "showcase", Module.Kind.STYLE, "y", true)
	var sub := _make(comp.path_join("components/sub"), "sub", Module.Kind.COMPONENT, "z", true)
	t.add(c); t.add(s); t.add(sub)
	_check(t.by_path(c.file_path()) == c, "by_path finds a module")
	_check(t.by_id(c.id) == c, "by_id finds a module")
	_check(t.by_path(c.file_path().to_upper()) == c, "by_path folds case")
	_check(t.by_path("") == null, "an empty path is not-found, not an error")
	_check(t.by_id("") == null, "an empty id is not-found, not an error")
	_check(t.by_path(SANDBOX.path_join("nope.guitkx")) == null, "an unknown path is not-found")
	_check(t.contains(s.file_path()), "contains agrees with by_path")
	_check(t.modules().size() == 3, "the tree holds what was added")
	_check(t.add(null) == null, "adding nothing adds nothing")
	_check(not t.remove(null), "removing nothing removes nothing")
	var stranger := _make(SANDBOX, "stranger", Module.Kind.COMPONENT, "", false)
	_check(not t.remove(stranger), "removing a module the tree never held reports false")
	_check(t.modules().size() == 3, "and leaves the tree alone")

	var no_id := _make(comp, "noid", Module.Kind.COMPONENT, "", false)
	no_id.id = ""
	t.add(no_id)
	_check(not no_id.id.is_empty(), "a module added without an id is given one")


func _test_delete_is_absence() -> void:
	_section("delete is absence")
	var comp := SANDBOX.path_join("showcase")
	var t := BTree.new()
	var c := _make(comp, "showcase", Module.Kind.COMPONENT, "x", true)
	var s := _make(comp, "showcase", Module.Kind.STYLE, "y", true)
	t.add(c); t.add(s)
	t.set_projection(PackedStringArray([c.file_path(), s.file_path()]))
	_check(t.orphaned_paths().is_empty(), "nothing is orphaned while every module is present")

	var gone := s.file_path()
	_check(t.remove(s), "removing reports success")
	_check(t.by_path(gone) == null, "the removed module is gone from the index")
	var orphans := t.orphaned_paths()
	_check(orphans.size() == 1 and str(orphans[0]).ends_with("showcase.style.guitkx"),
		"its file is reported orphaned, with no pending list anywhere")
	_check(t.by_path(gone) == null, "the deleted name is immediately reusable")

	t.add(s)
	_check(t.orphaned_paths().is_empty(),
		"putting the module back un-orphans its file, identity and all")
	_check(t.by_path(gone) == s, "and the index followed it")

	_section("projection de-duplicates")
	t.set_projection(PackedStringArray([c.file_path(), c.file_path().to_upper()]))
	_check(t.last_projection().size() == 1, "two spellings of one path are one projection entry")


func _test_move_carries_the_folder() -> void:
	_section("a folder that moves takes what is IN it")
	var t := BTree.new()
	var home := SANDBOX.path_join("panel")
	var owner := _make(home, "panel", Module.Kind.COMPONENT, "x", true)
	var style_beside := _make(home, "panel", Module.Kind.STYLE, "y", true)
	var hook_beside := _make(home, "panel", Module.Kind.HOOK, "z", true)
	var nested := _make(home.path_join("components/leaf"), "leaf", Module.Kind.COMPONENT, "w", true)
	var stranger := _make(SANDBOX.path_join("other"), "other", Module.Kind.COMPONENT, "v", true)
	t.add(owner); t.add(style_beside); t.add(hook_beside); t.add(nested); t.add(stranger)

	var moved := SANDBOX.path_join("renamed")
	t.move_to(owner, moved, "renamed")
	_check(owner.file_path() == moved.path_join("renamed.guitkx"), "the module moved")
	_check(Paths.same(style_beside.folder, moved), "the style companion beside it moved with the folder")
	_check(Paths.same(hook_beside.folder, moved), "the hook companion beside it moved with the folder")
	_check(nested.folder.ends_with("renamed/components/leaf"),
		"the nested child kept its position under the folder")
	_check(Paths.same(stranger.folder, SANDBOX.path_join("other")),
		"a module in a DIFFERENT folder is not dragged along")
	_check(t.by_path(moved.path_join("panel.style.guitkx")) == style_beside,
		"and the index followed it -- a companion keeps its OWN name, it is only re-filed")
	_check(owner.has_moved() and nested.has_moved(),
		"both report a pending move against their disk path")

	_section("a companion renaming must not take the folder with it")
	t.move_to(style_beside, moved, "other_style")
	_check(Paths.same(owner.folder, moved) and Paths.same(hook_beside.folder, moved),
		"renaming a companion moves only itself")

	_section("idempotence")
	var before := "%s|%s" % [owner.file_path(), nested.file_path()]
	t.move_to(owner, moved, "renamed")
	_check("%s|%s" % [owner.file_path(), nested.file_path()] == before,
		"repeating a move changes nothing, subtree included")
	t.move_to(null, moved, "x")
	_check("%s|%s" % [owner.file_path(), nested.file_path()] == before, "moving nothing is a no-op")

	_section("case in the moved subtree is preserved")
	var mixed := BTree.new()
	var mowner := _make(SANDBOX.path_join("panel"), "panel", Module.Kind.COMPONENT, "x", true)
	var mchild := _make(SANDBOX.path_join("panel/Components/Leaf"), "leaf", Module.Kind.COMPONENT, "y", true)
	mixed.add(mowner); mixed.add(mchild)
	mixed.move_to(mowner, SANDBOX.path_join("moved"), "moved")
	_check(mchild.folder.ends_with("moved/Components/Leaf"),
		"the child's own folder names keep their spelling across the re-root")


func _test_move_is_not_a_delete() -> void:
	_section("moving does not orphan")
	var t := BTree.new()
	var m := _make(SANDBOX, "moved", Module.Kind.COMPONENT, "x", true)
	var was_at := m.disk_path
	t.add(m)
	t.set_projection(PackedStringArray([m.file_path()]))
	t.move_to(m, SANDBOX.path_join("elsewhere"), "moved")
	_check(m.has_moved(), "the module knows it has moved")
	_check(t.orphaned_paths().is_empty(),
		"its old file is NOT orphaned -- Save renames the file, keeping its UID")
	m.mark_projected(m.file_path())
	t.set_projection(PackedStringArray([m.file_path()]))
	_check(not m.has_moved() and t.orphaned_paths().is_empty() and not t.has_unsaved_work(),
		"after the projection there is nothing left to do")
	_check(was_at != m.disk_path, "and the disk path followed the module")


func _test_unsaved_work() -> void:
	_section("unsaved work is derived from the tree, never accumulated")
	var t := BTree.new()
	var w := _make(SANDBOX, "work", Module.Kind.COMPONENT, "x", true)
	t.add(w)
	t.set_projection(PackedStringArray([w.file_path()]))
	_check(not t.has_unsaved_work(), "a freshly loaded tree has nothing to save")
	w.apply_edit("y")
	_check(t.has_unsaved_work(), "an edit is unsaved work")
	w.mark_projected(w.file_path())
	_check(not t.has_unsaved_work(), "projecting the edit settles it")

	var fresh := _make(SANDBOX, "fresh", Module.Kind.COMPONENT, "z", false)
	t.add(fresh)
	_check(t.has_unsaved_work(), "a module that has never been written is unsaved work")
	t.remove(fresh)
	_check(not t.has_unsaved_work(), "and removing it settles the tree again")

	var ro := _make(SANDBOX, "locked", Module.Kind.COMPONENT, "p", true)
	ro.read_only = true
	ro.apply_edit("q")
	t.add(ro)
	_check(not t.has_unsaved_work(),
		"a read-only module is never unsaved work -- the builder cannot write it")

	var moved := _make(SANDBOX, "shift", Module.Kind.COMPONENT, "s", true)
	t.add(moved)
	t.set_projection(PackedStringArray([w.file_path(), moved.file_path()]))
	_check(not t.has_unsaved_work(), "settled again")
	t.move_to(moved, SANDBOX.path_join("far"), "shift")
	_check(t.has_unsaved_work(), "a pending move is unsaved work")


func _test_abort_is_load_rerun() -> void:
	_section("abort")
	var t := BTree.new()
	var m := _make(SANDBOX, "abort", Module.Kind.COMPONENT, "x", true)
	t.add(m)
	t.set_projection(PackedStringArray([m.file_path()]))
	t.move_to(m, SANDBOX.path_join("gone"), "abort")
	t.remove(m)
	_check(t.orphaned_paths().size() == 1 and t.has_unsaved_work(), "the tree has pending work")
	var reloaded := _make(SANDBOX, "abort", Module.Kind.COMPONENT, "x", true)
	t.reset([reloaded], PackedStringArray([reloaded.file_path()]))
	_check(not t.has_unsaved_work() and t.orphaned_paths().is_empty(),
		"resetting from disk leaves nothing pending, whatever happened before")
	_check(t.modules().size() == 1, "and the tree holds only what was reloaded")
	t.reset([null, reloaded], PackedStringArray())
	_check(t.modules().size() == 1, "a null in the reset list is dropped, not stored")
	t.reset(["not a module", 42, reloaded], PackedStringArray())
	_check(t.modules().size() == 1,
		"and so is anything that is not a module -- the guard tests the CAST, not the raw value")


func _test_validation() -> void:
	_section("validation")
	var healthy := BTree.new()
	healthy.add(_make(SANDBOX, "a", Module.Kind.COMPONENT, "1", true))
	healthy.add(_make(SANDBOX, "b", Module.Kind.STYLE, "2", false))
	_check(healthy.validate().is_empty(), "a healthy tree validates clean")

	var dup_path := BTree.new()
	dup_path.add(_make(SANDBOX, "dup", Module.Kind.COMPONENT, "1", true))
	dup_path.add(_make(SANDBOX, "dup", Module.Kind.COMPONENT, "2", true))
	_check(not dup_path.validate().is_empty(), "two modules claiming one path is reported")

	var dup_id := BTree.new()
	var x := _make(SANDBOX, "x", Module.Kind.COMPONENT, "1", true)
	var y := _make(SANDBOX, "y", Module.Kind.COMPONENT, "2", true)
	dup_id.add(x); dup_id.add(y)
	y.id = x.id
	_check(not dup_id.validate().is_empty(), "a duplicate id is reported")

	var no_path := BTree.new()
	var z := _make(SANDBOX, "z", Module.Kind.COMPONENT, "1", true)
	no_path.add(z)
	z.name = ""
	_check(not no_path.validate().is_empty(), "a module with no derivable path is reported")


func _test_tree_round_trip() -> void:
	_section("tree journal round trip")
	var t := BTree.new()
	var on_disk := _make(SANDBOX, "kept", Module.Kind.COMPONENT, "a", true)
	var never := _make(SANDBOX, "new", Module.Kind.COMPONENT, "b", false)
	t.add(on_disk); t.add(never)
	t.set_projection(PackedStringArray([on_disk.file_path(), SANDBOX.path_join("deleted.guitkx")]))

	var json := JSON.stringify(t.to_dict())
	var back := BTree.from_dict(JSON.parse_string(json))
	_check(back.modules().size() == 2, "every module comes back")
	_check(back.by_id(on_disk.id) != null, "the id index rebuilds after the trip")
	_check(back.by_path(never.file_path()) != null, "the path index rebuilds after the trip")
	_check(not back.by_id(never.id).is_on_disk(), "a never-written module stays never-written")
	_check(back.orphaned_paths().size() == 1,
		"the projection travels with the tree, so a crashed session's DELETE is not undone")
	_check(back.validate().is_empty(), "and the restored tree is healthy")


# ── Naming ───────────────────────────────────────────────────────────────────────────

func _test_naming() -> void:
	_section("family names")
	var K := Module.Kind
	_check(Naming.family_of(K.COMPONENT, "showcase_page") == "showcase_page",
		"a component's family is its own name")
	_check(Naming.family_of(K.STYLE, "showcase_page") == "showcase_page",
		"a style already carries the family name")
	_check(Naming.family_of(K.HOOK, "showcase_page") == "showcase_page",
		"so does a hook named for the component, which is this leg's convention")
	_check(Naming.family_of(K.HOOK, "use_showcase_page") == "showcase_page",
		"a hook that spells the `use_` prefix drops it")
	_check(Naming.family_of(K.COMPONENT, "ShowcasePage") == "showcasepage",
		"the family folds case")
	_check(Naming.family_of(K.COMPONENT, "use_thing") == "use_thing",
		"`use_` is only stripped from a HOOK -- a component keeps its whole name")
	_check(Naming.family_of(K.HOOK, "use_") == "use_",
		"a bare `use_` keeps its name -- there is nothing behind it to be the family")
	_check(Naming.family_of(K.HOOK, "useful") == "useful",
		"`use` without the separator is not a prefix")
	_check(Naming.family_of(K.STYLE, "") == "", "an empty name has no family")

	_check(Naming.same_family(K.STYLE, "showcase_page", K.COMPONENT, "showcase_page"),
		"style and component are one family")
	_check(Naming.same_family(K.HOOK, "use_showcase_page", K.COMPONENT, "showcase_page"),
		"hook and component are one family")
	_check(not Naming.same_family(K.STYLE, "button_style", K.COMPONENT, "showcase_page"),
		"an unrelated name is not family")
	_check(not Naming.same_family(K.STYLE, "", K.COMPONENT, ""),
		"two empty names are not a family match")

	_section("nearest wins")
	var near := SANDBOX.path_join("page/components/card")
	var far := SANDBOX.path_join("page")
	var focus := SANDBOX.path_join("page/components/card/components/row")
	_check(Naming.shared_prefix_length(focus, near) > Naming.shared_prefix_length(focus, far),
		"the nearer component shares more of the path")
	_check(Naming.shared_prefix_length("res://ui/card", "res://ui/cardigan")
		== Naming.shared_prefix_length("res://ui/card", "res://ui/other"),
		"a longer NAME is not a closer folder -- segments are compared, not characters")
	_check(Naming.shared_prefix_length("", "res://ui") == 0, "nothing shares a prefix with nothing")


# ── Specifiers ───────────────────────────────────────────────────────────────────────

func _test_specifiers() -> void:
	_section("specifier round trip")
	# The pair has to agree exactly: whatever `relative` writes, `map` must read back to the
	# same file. A disagreement would not produce one bad import -- a move re-spells every
	# specifier it invalidated, so it would rewrite the whole tree to something unresolvable.
	var root := SANDBOX.path_join("panel")
	var owner := root.path_join("panel.guitkx")
	var beside := root.path_join("panel.style.guitkx")
	var leaf := root.path_join("components/leaf/leaf.guitkx")
	var other := root.path_join("components/twig/twig.guitkx")

	_round_trip(owner, beside, "a companion beside its component")
	_round_trip(owner, leaf, "a child under components/")
	_round_trip(leaf, owner, "the parent, from a child")
	_round_trip(leaf, beside, "a shared style, from a child")
	_round_trip(leaf, other, "a sibling child")
	_round_trip(owner, SANDBOX.path_join("shared/util.guitkx"), "a module outside the tree")

	_check(Specifiers.relative(owner.get_base_dir(), beside) == "./panel.style",
		"a sibling spells as `./name` (got %s)" % Specifiers.relative(owner.get_base_dir(), beside))

	_section("the canonical rule: `./` for a sibling, `~/` for anything else under the root")
	# This is where the Godot leg genuinely differs from Unity, and it is the COMPILER's rule,
	# not a builder invention -- `RuitkGuitkx.import_specifier` is the single source of truth
	# the codemod and the strict-import hint already use, so a builder-written specifier is
	# indistinguishable from a hand-written one.
	var moved := SANDBOX.path_join("elsewhere/leaf.guitkx")
	var was := Specifiers.relative(leaf.get_base_dir(), beside)
	var now := Specifiers.relative(moved.get_base_dir(), beside)
	_check(was.begins_with("~/") and now.begins_with("~/"),
		"a target under the `~/` root spells the same from anywhere (was=%s now=%s)" % [was, now])
	_check(was == now, "so moving the IMPORTER alone does not invalidate it")
	_check(Paths.same(Specifiers.map(moved, now), beside),
		"and it still resolves from the new home")
	_check(Specifiers.relative(leaf.get_base_dir(), leaf.get_base_dir().path_join("twig.guitkx"))
			== "./twig",
		"a sibling still spells `./name`, which IS home-dependent")

	_section("specifiers resolve for modules that are not on disk")
	_check(not FileAccess.file_exists(beside), "the fixture really is unsaved -- nothing on disk")
	_check(Paths.same(Specifiers.map(owner, "./panel.style"), beside),
		"an import between two UNSAVED modules still names its target")

	_section("degenerate input")
	_check(Specifiers.relative("", beside) == "", "no folder spells nothing")
	_check(Specifiers.relative(root, "") == "", "no target spells nothing")
	_check(Specifiers.map(owner, "") == "", "no specifier maps to nothing")
	_check(Specifiers.map("", "./x") == "", "no importer maps to nothing")
	_check(Specifiers.map(owner, "res://ui/x") == "",
		"an engine-native path is not a legal specifier and maps to nothing")
	_check(Specifiers.map(owner, "bare") == "", "a bare specifier maps to nothing")

	_section("import scanning")
	var src := "import { A } from \"./a\"\nimport { B } from \"../b\"\n\nFoo() -> RuitkVNode {\n\treturn ( <Label /> )\n}\n"
	var imports := Specifiers.imports_of(src)
	_check(imports.size() == 2, "both imports are seen")
	_check(str(imports[0]["spec"]) == "./a" and int(imports[0]["line"]) == 1, "the first is on line 1")
	_check(str(imports[1]["spec"]) == "../b" and int(imports[1]["line"]) == 2, "the second is on line 2")
	_check(src.substr(int(imports[0]["spec_at"]), 1) == "\"",
		"the specifier offset points at the opening quote, which is what a rewrite spans")
	_check(Specifiers.imports_of("Foo() -> RuitkVNode {\n\treturn ( <Label /> )\n}\n").is_empty(),
		"a file with no preamble has no imports")
	_check(Specifiers.line_of("a\nb\nc", 0) == 1, "offset 0 is line 1")
	_check(Specifiers.line_of("a\nb\nc", 4) == 3, "an offset past two newlines is line 3")


func _round_trip(from_file: String, target: String, what: String) -> void:
	var spec := Specifiers.relative(from_file.get_base_dir(), target)
	_check(not spec.is_empty(), "%s spells as something" % what)
	_check(Paths.same(Specifiers.map(from_file, spec), target),
		"%s maps back to the same file (spec=%s)" % [what, spec])


# ── Root resolution ──────────────────────────────────────────────────────────────────

func _test_root_resolution() -> void:
	_section("tree root, from disk")
	# `resolve_root` reads the FILESYSTEM, so these build the real folder shapes rather than
	# asserting against a string.
	var page := SANDBOX.path_join("samples/components/showcase_page")
	_write(page.path_join("showcase_page.guitkx"), "export X() -> RuitkVNode {\n\treturn ( <Label /> )\n}\n")
	_write(page.path_join("components/fields/fields.guitkx"), "export F() -> RuitkVNode {\n\treturn ( <Label /> )\n}\n")
	_write(page.path_join("components/top_bar/top_bar.guitkx"), "export T() -> RuitkVNode {\n\treturn ( <Label /> )\n}\n")
	_write(SANDBOX.path_join("samples/components/doom/doom.guitkx"), "export D() -> RuitkVNode {\n\treturn ( <Label /> )\n}\n")

	var child := page.path_join("components/fields/fields.guitkx")
	_check(Paths.same(BTree.resolve_root(child), page),
		"a child under components/ resolves to the component that owns it")
	_check(Paths.same(BTree.resolve_root(page.path_join("showcase_page.guitkx")), page),
		"the root module resolves to its own folder")
	_check(not BTree.resolve_root(child).ends_with("samples"),
		"a folder merely NAMED components is not the house nesting level")

	_write(SANDBOX.path_join("flat/loose.guitkx"), "export L() -> RuitkVNode {\n\treturn ( <Label /> )\n}\n")
	_check(Paths.same(BTree.resolve_root(SANDBOX.path_join("flat/loose.guitkx")), SANDBOX.path_join("flat")),
		"a module in a plain folder roots at that folder")

	_write(SANDBOX.path_join("orphan/components/thing/thing.guitkx"), "export T() -> RuitkVNode {\n\treturn ( <Label /> )\n}\n")
	_check(Paths.same(
			BTree.resolve_root(SANDBOX.path_join("orphan/components/thing/thing.guitkx")),
			SANDBOX.path_join("orphan/components/thing")),
		"components/ with no owning component above it is just a folder -- the guard cuts both ways")

	_check(BTree.resolve_root("") == "", "no focus resolves to no root")

	_section("the root is the same answer from every module in the tree")
	# The root is what the saved layout is KEYED on, so it has to be the same answer from
	# every module -- including one nothing imports yet, which is every module the moment it
	# is created.
	_write(page.path_join("loose.style.guitkx"), "export primary := { \"a\": 1 }\n")
	_write(page.path_join("components/top_bar/top_bar.style.guitkx"), "export bar := { \"a\": 1 }\n")
	var every := [
		page.path_join("showcase_page.guitkx"),
		page.path_join("loose.style.guitkx"),
		child,
		page.path_join("components/top_bar/top_bar.guitkx"),
		page.path_join("components/top_bar/top_bar.style.guitkx"),
	]
	var same_everywhere := true
	for module in every:
		if not Paths.same(BTree.resolve_root(str(module)), page):
			same_everywhere = false
	_check(same_everywhere, "every module in the tree resolves to the SAME root, imported or not")

	_section("tree root, from the MODULES")
	# A tree that has never been saved has NO files, so the disk answer is "wherever the
	# focus is" -- and creating a nested component moves the focus deeper, which moves the
	# root with it and re-keys the whole saved layout. Asked of the modules, the answer holds.
	var mem := SANDBOX.path_join("unsaved/root")
	var unsaved := [
		_make(mem, "root", Module.Kind.COMPONENT, "x", false),
		_make(mem, "root", Module.Kind.STYLE, "x", false),
		_make(mem.path_join("components/mid"), "mid", Module.Kind.COMPONENT, "x", false),
		_make(mem.path_join("components/mid/components/leaf"), "leaf", Module.Kind.COMPONENT, "x", false),
	]
	_check(not DirAccess.dir_exists_absolute(mem), "the fixture really is unsaved -- nothing on disk")
	var stable := true
	for module in unsaved:
		if not Paths.same(BTree.resolve_root_from(unsaved, (module as Module).file_path()), mem):
			stable = false
	_check(stable, "an UNSAVED tree resolves to one root from every module in it")
	_check(not Paths.same(BTree.resolve_root((unsaved[3] as Module).file_path()), mem),
		"and the disk answer would have been wrong, which is the whole reason for the pair")


# ── Workspace ────────────────────────────────────────────────────────────────────────

func _test_workspace_load() -> void:
	_section("load reads the whole tree once")
	var root := SANDBOX.path_join("load/app")
	_write(root.path_join("app.guitkx"),
		"import { Row } from \"./components/row/row\"\nimport { helper } from \"~/tests/__builder_tmp/load/shared/helper\"\n\nexport App() -> RuitkVNode {\n\treturn ( <Row v={helper()} /> )\n}\n")
	_write(root.path_join("components/row/row.guitkx"),
		"export Row(v) -> RuitkVNode {\n\treturn ( <Label text={str(v)} /> )\n}\n")
	_write(root.path_join("app.style.guitkx"), "export primary := { \"a\": 1 }\n")
	# Deliberately OUTSIDE the folder scan: only an import reaches it.
	_write(SANDBOX.path_join("load/shared/helper.guitkx"), "export helper() -> int {\n\treturn 1\n}\n")

	var ws := Workspace.new()
	ws.load_tree(root.path_join("app.guitkx"))
	_check(ws.modules().size() == 4, "the folder scan and the import walk together find four modules (got %d)" % ws.modules().size())
	_check(ws.try_get(root.path_join("app.guitkx")) != null, "the focus module is loaded")
	_check(ws.try_get(root.path_join("components/row/row.guitkx")) != null, "the nested child is loaded")
	_check(ws.try_get(root.path_join("app.style.guitkx")) != null, "the style companion is loaded")
	_check(ws.try_get(SANDBOX.path_join("load/shared/helper.guitkx")) != null,
		"a module OUTSIDE the scan is pulled in by the import that names it")
	_check(not ws.has_unsaved_changes(), "a freshly loaded tree has nothing to save")
	_check(ws.tree().validate().is_empty(), "and it is healthy")
	_check(ws.tree().last_projection().size() == 4, "every loaded file is in the projection")

	_section("open brings in one file")
	_write(SANDBOX.path_join("load/outside.guitkx"), "export O() -> RuitkVNode {\n\treturn ( <Label /> )\n}\n")
	var opened := ws.open(SANDBOX.path_join("load/outside.guitkx"))
	_check(opened != null and ws.modules().size() == 5, "open adds a module the loader did not see")
	_check(ws.open(SANDBOX.path_join("load/outside.guitkx")) == opened,
		"opening the same file again returns the same module")

	_section("a clean module re-checks disk; a dirty one does not")
	_write(SANDBOX.path_join("load/outside.guitkx"), "export O() -> RuitkVNode {\n\treturn ( <Button /> )\n}\n")
	ws.open(SANDBOX.path_join("load/outside.guitkx"))
	_check(opened.buffer_text.contains("Button"), "a clean module adopts the new disk text")
	opened.apply_edit("export O() -> RuitkVNode {\n\treturn ( <Panel /> )\n}\n")
	_write(SANDBOX.path_join("load/outside.guitkx"), "export O() -> RuitkVNode {\n\treturn ( <Label /> )\n}\n")
	ws.open(SANDBOX.path_join("load/outside.guitkx"))
	_check(opened.buffer_text.contains("Panel"), "a DIRTY module keeps the user's unsaved buffer")

	_section("the external-change sweep follows the same rule")
	var swept := ws.reload_clean_from_disk(PackedStringArray([SANDBOX.path_join("load/outside.guitkx")]))
	_check(swept.is_empty(), "the sweep leaves a dirty module alone")
	opened.mark_projected(opened.file_path())
	_write(SANDBOX.path_join("load/outside.guitkx"), "export O() -> RuitkVNode {\n\treturn ( <Tree /> )\n}\n")
	swept = ws.reload_clean_from_disk(PackedStringArray([SANDBOX.path_join("load/outside.guitkx")]))
	_check(swept.size() == 1 and opened.buffer_text.contains("Tree"), "and updates a clean one")
	_check(ws.reload_clean_from_disk(PackedStringArray([SANDBOX.path_join("load/nothing.guitkx")])).is_empty(),
		"a path the tree does not hold is skipped")

	_section("close removes without orphaning intent")
	ws.close(SANDBOX.path_join("load/outside.guitkx"))
	_check(ws.try_get(SANDBOX.path_join("load/outside.guitkx")) == null, "close takes the module out")


func _test_workspace_create_and_delete() -> void:
	_section("create and delete")
	var ws := Workspace.new()
	var root := SANDBOX.path_join("crud")
	var made := ws.create_new(root.path_join("thing.guitkx"), "export T() -> RuitkVNode {\n\treturn ( <Label /> )\n}\n")
	_check(made != null, "a module is created in memory")
	_check(not made.is_on_disk(), "and nothing is written")
	_check(ws.has_unsaved_changes(), "so it counts as unsaved work")
	_check(ws.create_new(root.path_join("thing.guitkx"), "") == null,
		"the same path cannot be claimed twice")
	_check(not ws.is_path_available(root.path_join("thing.guitkx")),
		"and is_path_available agrees -- one rule, so the prompt and the creation cannot disagree")

	_check(ws.delete(root.path_join("thing.guitkx")), "deleting reports success")
	_check(ws.is_path_available(root.path_join("thing.guitkx")),
		"the name is free the instant the module goes")
	_check(not ws.delete(root.path_join("thing.guitkx")), "deleting it twice reports false")
	_check(ws.restore(made) == made, "restore puts the SAME module back")
	_check(ws.restore(made) == null, "restoring it twice is refused -- the path is taken")

	_check(not ws.is_path_available(""), "an empty path is never available")
	_check(ws.apply_edit(root.path_join("nothing.guitkx"), "x") == false,
		"editing a module that is not open is refused")


func _test_workspace_move_reconciles_imports() -> void:
	_section("a move re-spells every specifier it invalidated")
	var root := SANDBOX.path_join("recon/panel")
	_write(root.path_join("panel.guitkx"),
		"import { Leaf } from \"./components/leaf/leaf\"\n\nexport Panel() -> RuitkVNode {\n\treturn ( <Leaf /> )\n}\n")
	_write(root.path_join("components/leaf/leaf.guitkx"),
		"export Leaf() -> RuitkVNode {\n\treturn ( <Label /> )\n}\n")
	var ws := Workspace.new()
	ws.load_tree(root.path_join("panel.guitkx"))
	_check(ws.modules().size() == 2, "both modules loaded")

	var rewrites := ws.move_to(
		root.path_join("components/leaf/leaf.guitkx"), SANDBOX.path_join("recon/moved"), "leaf")
	_check(rewrites.size() == 1, "the importer's buffer was rewritten (got %d)" % rewrites.size())
	var importer := ws.try_get(root.path_join("panel.guitkx"))
	_check(not importer.buffer_text.contains("./components/leaf/leaf"),
		"the stale specifier is gone")
	var spec := str(Specifiers.imports_of(importer.buffer_text)[0]["spec"])
	_check(Paths.same(Specifiers.map(importer.file_path(), str(spec)), SANDBOX.path_join("recon/moved/leaf.guitkx")),
		"and the new one resolves to where the module went (spec=%s)" % spec)
	_check(importer.is_dirty(), "the importer is unsaved work now, which is what Save has to see")

	_section("moving the IMPORTER keeps its own imports true")
	ws.move_to(root.path_join("panel.guitkx"), SANDBOX.path_join("recon/faraway"), "panel")
	var moved_importer := ws.try_get(SANDBOX.path_join("recon/faraway/panel.guitkx"))
	var spec2 := str(Specifiers.imports_of(moved_importer.buffer_text)[0]["spec"])
	_check(Paths.same(Specifiers.map(moved_importer.file_path(), spec2), SANDBOX.path_join("recon/moved/leaf.guitkx")),
		"a relocated component still points at what it imported (spec=%s)" % spec2)

	_section("a `./` sibling import IS invalidated by the importer moving")
	# The one shape that is home-dependent, so this is where reconciling the IMPORTER's own
	# end earns its keep -- rewriting only the importers OF a moved module would leave this
	# one pointing at a file it no longer sits beside.
	# The importer deliberately does NOT own its folder: a folder-owning component takes the
	# whole folder with it, siblings included, and its `./` imports stay true for free.
	var root3 := SANDBOX.path_join("recon3/pair")
	_write(root3.path_join("alpha.guitkx"),
		"import { Mate } from \"./mate\"\n\nexport Alpha() -> RuitkVNode {\n\treturn ( <Mate /> )\n}\n")
	_write(root3.path_join("mate.guitkx"), "export Mate() -> RuitkVNode {\n\treturn ( <Label /> )\n}\n")
	var ws4 := Workspace.new()
	ws4.load_tree(root3.path_join("alpha.guitkx"))
	_check(not ws4.try_get(root3.path_join("alpha.guitkx")).owns_folder(),
		"the fixture importer really does not own its folder")
	var rewrites3 := ws4.move_to(root3.path_join("alpha.guitkx"), SANDBOX.path_join("recon3/away"), "alpha")
	_check(rewrites3.size() == 1, "the moved importer rewrote itself (got %d)" % rewrites3.size())
	var away := ws4.try_get(SANDBOX.path_join("recon3/away/alpha.guitkx"))
	var spec3 := str(Specifiers.imports_of(away.buffer_text)[0]["spec"])
	_check(spec3 != "./mate", "the sibling spelling is gone (got %s)" % spec3)
	_check(Paths.same(Specifiers.map(away.file_path(), spec3), root3.path_join("mate.guitkx")),
		"and the new one still names the module it left behind")
	_check(ws4.try_get(root3.path_join("mate.guitkx")) != null,
		"and the sibling itself stayed put -- only a folder OWNER carries the folder")

	_section("only the import specifier is touched")
	var root2 := SANDBOX.path_join("recon2/host")
	_write(root2.path_join("host.guitkx"),
		"import { Leaf } from \"./components/leaf/leaf\"\n\nexport Host() -> RuitkVNode {\n\tvar decoy := \"./components/leaf/leaf\"\n\treturn ( <Leaf text={decoy} /> )\n}\n")
	_write(root2.path_join("components/leaf/leaf.guitkx"),
		"export Leaf(text) -> RuitkVNode {\n\treturn ( <Label text={text} /> )\n}\n")
	var ws2 := Workspace.new()
	ws2.load_tree(root2.path_join("host.guitkx"))
	ws2.move_to(root2.path_join("components/leaf/leaf.guitkx"), SANDBOX.path_join("recon2/away"), "leaf")
	var host := ws2.try_get(root2.path_join("host.guitkx"))
	_check(host.buffer_text.contains("var decoy := \"./components/leaf/leaf\""),
		"an ordinary string that happens to read like a specifier is left alone")

	_section("two imports on ONE line are two entries, not one")
	# Keyed by line alone, the second would overwrite the first in the snapshot and quietly
	# drop out of the reconcile -- an import left pointing at a file that moved.
	var root4 := SANDBOX.path_join("recon4/hub")
	_write(root4.path_join("hub.guitkx"),
		"import { A } from \"./components/a/a\"  import { B } from \"./components/b/b\"\n\nexport Hub() -> RuitkVNode {\n\treturn ( <A><B /></A> )\n}\n")
	_write(root4.path_join("components/a/a.guitkx"),
		"export A(children = null) -> RuitkVNode {\n\treturn ( <VBoxContainer>{children}</VBoxContainer> )\n}\n")
	_write(root4.path_join("components/b/b.guitkx"), "export B() -> RuitkVNode {\n\treturn ( <Label /> )\n}\n")
	var ws5 := Workspace.new()
	ws5.load_tree(root4.path_join("hub.guitkx"))
	_check(ws5.modules().size() == 3, "all three modules loaded")
	var hub := ws5.try_get(root4.path_join("hub.guitkx"))
	_check(Specifiers.imports_of(hub.buffer_text).size() == 2, "both imports are on one line")
	_check(ws5.capture_imports().size() == 2,
		"and the snapshot holds BOTH -- the per-line ordinal is what keeps them apart")

	ws5.move_to(root4.path_join("components/a/a.guitkx"), SANDBOX.path_join("recon4/moved_a"), "a")
	ws5.move_to(root4.path_join("components/b/b.guitkx"), SANDBOX.path_join("recon4/moved_b"), "b")
	var hub_imports := Specifiers.imports_of(hub.buffer_text)
	_check(hub_imports.size() == 2, "still two imports after both moves")
	_check(Paths.same(Specifiers.map(hub.file_path(), str(hub_imports[0]["spec"])),
			SANDBOX.path_join("recon4/moved_a/a.guitkx")),
		"the first still names its target (spec=%s)" % hub_imports[0]["spec"])
	_check(Paths.same(Specifiers.map(hub.file_path(), str(hub_imports[1]["spec"])),
			SANDBOX.path_join("recon4/moved_b/b.guitkx")),
		"and so does the second (spec=%s)" % hub_imports[1]["spec"])

	_section("refusals")
	_check(ws2.move_to(SANDBOX.path_join("recon2/nothing.guitkx"), SANDBOX, "x").is_empty(),
		"moving a module the tree does not hold is refused")
	_check(ws2.move_to_path(root2.path_join("host.guitkx"), "").is_empty(),
		"moving to nowhere is refused")

	_section("move_to_path does not reclassify")
	var ws3 := Workspace.new()
	var comp := ws3.create_new(SANDBOX.path_join("kind/thing.guitkx"), "x")
	ws3.move_to_path(comp.file_path(), SANDBOX.path_join("kind/other.style.guitkx"))
	_check(comp.kind == Module.Kind.COMPONENT,
		"a rename does not silently reclassify the module by its new suffix")
	_check(comp.name == "other",
		"the target's suffix is split off, never carried into the name -- otherwise the module's own suffix would be applied on top of it")
	_check(comp.file_path().ends_with("other.guitkx"),
		"so the derived path keeps the kind the module actually has")


func _test_workspace_save() -> void:
	_section("save is a diff")
	var root := SANDBOX.path_join("save/app")
	var ws := Workspace.new()
	var trashed := PackedStringArray()
	ws.trash_file = func(p: String) -> bool:
		trashed.append(p)
		return DirAccess.remove_absolute(p) == OK

	var app := ws.create_new(root.path_join("app.guitkx"), "export App() -> RuitkVNode {\n\treturn ( <Label /> )\n}\n")
	var style := ws.create_new(root.path_join("app.style.guitkx"), "export primary := { \"a\": 1 }\n")
	_check(ws.save_all() == 2, "two new modules write two files")
	_check(FileAccess.file_exists(app.file_path()), "the component reached disk")
	_check(FileAccess.file_exists(style.file_path()), "so did the style companion")
	_check(not ws.has_unsaved_changes(), "and the tree is settled")
	_check(ws.save_all() == 0, "saving again writes nothing -- Save is a pure diff")

	_section("an edit writes only what changed")
	app.apply_edit("export App() -> RuitkVNode {\n\treturn ( <Button /> )\n}\n")
	_check(ws.save_all() == 1, "one dirty module writes one file")
	_check(_read(app.file_path()).contains("Button"), "and the bytes are the buffer's")

	_section("a delete trashes the file")
	ws.delete(style.file_path())
	var was := style.file_path()
	_check(ws.save_all() == 1, "the orphan is retired")
	_check(not FileAccess.file_exists(was), "the file is gone")
	_check(trashed.has(was), "and it went out through the trash, not a raw erase")
	_check(not ws.has_unsaved_changes(), "the tree is settled again")

	_section("CRLF survives the round trip")
	var crlf_path := root.path_join("crlf.guitkx")
	_write(crlf_path, "export C() -> RuitkVNode {\r\n\treturn ( <Label /> )\r\n}\r\n")
	var crlf := ws.open(crlf_path)
	_check(crlf.used_crlf, "the module recorded the flavor")
	crlf.apply_edit(crlf.buffer_text.replace("Label", "Button"))
	ws.save_all()
	_check(_read(crlf_path).contains("\r\n"), "and Save wrote the bytes the file used before")


func _test_workspace_save_moves_artifacts() -> void:
	_section("a move carries every artifact the module owns")
	var root := SANDBOX.path_join("artifacts/panel")
	var ws := Workspace.new()
	ws.trash_file = func(p: String) -> bool: return DirAccess.remove_absolute(p) == OK
	var src := root.path_join("panel.guitkx")
	_write(src, "export Panel() -> RuitkVNode {\n\treturn ( <Label /> )\n}\n")
	_write(src + ".uid", "uid://fake000000001")
	_write(src + ".diags.json", "{\"v\":4}")
	_write(root.path_join("panel.gd"), "## generated\n")
	_write(root.path_join("panel.gd.uid"), "uid://fake000000002")

	ws.load_tree(src)
	var target_folder := SANDBOX.path_join("artifacts/renamed")
	ws.move_to(src, target_folder, "renamed")
	_check(ws.save_all() > 0, "the move is projected")

	_check(FileAccess.file_exists(target_folder.path_join("renamed.guitkx")), "the source moved")
	_check(FileAccess.file_exists(target_folder.path_join("renamed.guitkx.uid")),
		"its UID sidecar moved -- which is what keeps every `uid://` reference resolving")
	_check(FileAccess.file_exists(target_folder.path_join("renamed.guitkx.diags.json")),
		"the diagnostics sidecar moved")
	_check(FileAccess.file_exists(target_folder.path_join("renamed.gd")),
		"the GENERATED script moved -- left behind, it would keep serving its class_name from a source that no longer produces it")
	_check(FileAccess.file_exists(target_folder.path_join("renamed.gd.uid")),
		"and the generated script's own UID sidecar moved")
	_check(not FileAccess.file_exists(src), "nothing is left at the old path")
	_check(not DirAccess.dir_exists_absolute(root),
		"the emptied folder is pruned -- a move that leaves it standing has not moved anything")
	_check(not ws.has_unsaved_changes(), "and the tree is settled")

	_section("a missing artifact is not an error")
	var lone := SANDBOX.path_join("artifacts/lone/lone.guitkx")
	_write(lone, "export L() -> RuitkVNode {\n\treturn ( <Label /> )\n}\n")
	var ws2 := Workspace.new()
	ws2.load_tree(lone)
	ws2.move_to(lone, SANDBOX.path_join("artifacts/lone2"), "lone")
	_check(ws2.save_all() > 0, "a module with no companions still moves")
	_check(FileAccess.file_exists(SANDBOX.path_join("artifacts/lone2/lone.guitkx")), "and lands intact")

	_section("a folder that still holds something is not pruned")
	var keep := SANDBOX.path_join("artifacts/keep")
	_write(keep.path_join("keep.guitkx"), "export K() -> RuitkVNode {\n\treturn ( <Label /> )\n}\n")
	_write(keep.path_join("notes.txt"), "mine")
	var ws3 := Workspace.new()
	ws3.load_tree(keep.path_join("keep.guitkx"))
	ws3.move_to(keep.path_join("keep.guitkx"), SANDBOX.path_join("artifacts/keep2"), "keep")
	ws3.save_all()
	_check(DirAccess.dir_exists_absolute(keep) and FileAccess.file_exists(keep.path_join("notes.txt")),
		"a file the builder does not own keeps its folder alive")


func _test_workspace_abort() -> void:
	_section("abort is load re-run")
	var root := SANDBOX.path_join("abort/app")
	_write(root.path_join("app.guitkx"), "export App() -> RuitkVNode {\n\treturn ( <Label /> )\n}\n")
	var ws := Workspace.new()
	ws.load_tree(root.path_join("app.guitkx"))
	var app := ws.try_get(root.path_join("app.guitkx"))
	app.apply_edit("export App() -> RuitkVNode {\n\treturn ( <Button /> )\n}\n")
	ws.create_new(root.path_join("extra.guitkx"), "export E() -> RuitkVNode {\n\treturn ( <Label /> )\n}\n")
	_check(ws.abort_all() == 2, "two pending changes are reported")
	_check(ws.modules().size() == 1, "the invented module is gone")
	_check(ws.try_get(root.path_join("app.guitkx")).buffer_text.contains("Label"),
		"and the edit is discarded")
	_check(not ws.has_unsaved_changes(), "nothing is pending afterwards")
	_check(ws.abort_all() == 0, "aborting a settled tree does nothing")

	_section("aborting a tree that was never written empties it")
	var ws2 := Workspace.new()
	ws2.create_new(SANDBOX.path_join("abort/never/x.guitkx"), "x")
	_check(ws2.abort_all() == 1, "the pending creation is reported")
	_check(ws2.modules().is_empty(), "and there is nothing to go back to, so the tree empties")


func _test_workspace_read_only() -> void:
	_section("read-only locations")
	_check(Workspace.is_read_only_location("res://addons/reactive_ui_toolkit_editor/x.guitkx"),
		"the package directory is read-only")
	_check(not Workspace.is_read_only_location("res://ui/x.guitkx"), "project sources are not")
	_check(Workspace.is_read_only_location("user://x.guitkx"), "outside the project is read-only")

	var ws := Workspace.new()
	var ro := _make(SANDBOX, "locked", Module.Kind.COMPONENT, "x", true)
	ro.read_only = true
	ws.tree().add(ro)
	ws.tree().set_projection(PackedStringArray([ro.file_path()]))
	_check(not ws.delete(ro.file_path()), "a read-only module cannot be deleted")
	_check(ws.move_to(ro.file_path(), SANDBOX, "other").is_empty(), "nor moved")
	_check(not ws.apply_edit(ro.file_path(), "y"), "nor edited")
	_check(not ws.has_unsaved_changes(), "and it never counts as unsaved work")


func _test_workspace_unlocated() -> void:
	_section("the provisional root")
	_check(Workspace.is_unlocated(Workspace.UNSAVED_ROOT.path_join("x.guitkx")),
		"a module under the provisional root is unlocated")
	_check(not Workspace.is_unlocated(Workspace.UNSAVED_ROOT),
		"the root itself is not a module")
	_check(not Workspace.is_unlocated("res://ui/x.guitkx"), "a placed module is not unlocated")
	_check(not Workspace.is_unlocated(""), "nothing is not unlocated")
	_check(Workspace.UNSAVED_ROOT.ends_with("~"),
		"the provisional root ends in `~`, which Godot's importer skips wholesale")

	var ws := Workspace.new()
	var a := ws.create_new(Workspace.UNSAVED_ROOT.path_join("root/root.guitkx"),
		"export R() -> RuitkVNode {\n\treturn ( <Label /> )\n}\n")
	var b := ws.create_new(Workspace.UNSAVED_ROOT.path_join("root/root.style.guitkx"),
		"export primary := { \"a\": 1 }\n")
	_check(ws.unlocated_modules().size() == 2,
		"both modules of a brand-new tree are waiting for a location -- including the COMPANION, which a caller-set flag is what forgets")
	_check(ws.save_all() == 0, "Save refuses to write anything still at the provisional root")
	_check(not FileAccess.file_exists(a.file_path()) and not FileAccess.file_exists(b.file_path()),
		"and nothing reached disk, invisible or otherwise")

	ws.place_at(a, SANDBOX.path_join("placed/root"))
	ws.place_at(b, SANDBOX.path_join("placed/root"))
	_check(ws.unlocated_modules().is_empty(), "placing them clears the queue")
	_check(ws.save_all() == 2, "and now Save writes them")
	_check(FileAccess.file_exists(SANDBOX.path_join("placed/root/root.guitkx")), "the component landed")
	_check(FileAccess.file_exists(SANDBOX.path_join("placed/root/root.style.guitkx")), "so did the companion")
	_check(ws.place_at(null, SANDBOX).is_empty(), "placing nothing is a no-op")


func _test_journal() -> void:
	_section("the reload journal")
	Journal.clear()
	_check(Journal.peek().is_empty(), "a cleared journal holds nothing")

	var ws := Workspace.new()
	ws.load_tree(SANDBOX.path_join("placed/root/root.guitkx"))
	_check(not Journal.capture(ws, "now"), "a CLEAN tree is never journalled")
	_check(Journal.peek().is_empty(), "so there is still nothing to offer")

	var made := ws.create_new(SANDBOX.path_join("placed/root/pending.guitkx"),
		"export P() -> RuitkVNode {\n\treturn ( <Label /> )\n}\n")
	_check(Journal.capture(ws, "2026-08-27 10:00:00"), "unsaved work is journalled")
	var peeked := Journal.peek()
	_check(int(peeked.get("modules", 0)) == ws.modules().size(), "the peek reports how much is at stake")
	_check(str(peeked.get("saved_at", "")) == "2026-08-27 10:00:00", "and when it was captured")

	var restored := Workspace.new()
	_check(Journal.try_restore(restored), "the journal restores into a fresh workspace")
	_check(restored.try_get(made.file_path()) != null, "the unsaved module came back")
	_check(restored.try_get(made.file_path()).id == made.id, "with its identity intact")
	_check(restored.has_unsaved_changes(), "and it is still unsaved work")
	_check(Journal.peek().is_empty(), "restoring clears the journal -- the offer is made once")
	_check(not Journal.try_restore(Workspace.new()), "and cannot be taken twice")
	_check(not Journal.try_restore(null), "restoring into nothing is refused")


func _test_ledger() -> void:
	_section("the ledger groups a gesture into one entry")
	var led := Ledger.new()
	var clock := [1000]
	led.now_msec = func() -> int: return clock[0]
	led.id_of = func(p: String) -> String: return "id:" + p

	led.begin("drop a Button")
	led.record("res://a.guitkx", "before-a", "after-a")
	led.record("res://b.guitkx", "before-b", "after-b")
	led.end()
	_check(led.entries().size() == 1, "two files, one gesture, one entry")
	_check(led.entries()[0].changes.size() == 2, "carrying both changes")
	_check(led.entries()[0].description == "drop a Button", "under the gesture's own name")
	_check(led.entries()[0].file_summary() == "a.guitkx +1", "and a summary that names the count")
	_check(led.entries()[0].changes[0].module_id == "id:res://a.guitkx",
		"identity is captured at record time, so a later rename cannot strand the entry")

	_section("nested scopes collapse into the outermost")
	led.begin("compound")
	led.begin("inner")
	led.record("res://c.guitkx", "1", "2")
	led.end()
	led.end()
	_check(led.entries().size() == 2, "one entry, not two")
	_check(led.entries()[1].description == "compound", "named by the outermost scope")

	_section("a cancelled gesture leaves no history")
	led.begin("nothing happened")
	led.end()
	_check(led.entries().size() == 2, "an empty scope is dropped")

	_section("a gesture that writes one file twice keeps one change")
	led.begin("twice")
	led.record("res://d.guitkx", "0", "1")
	led.record("res://d.guitkx", "1", "2")
	led.end()
	var twice := led.entries()[2]
	_check(twice.changes.size() == 1, "one change")
	_check(twice.changes[0].before == "0" and twice.changes[0].after == "2",
		"spanning the whole gesture -- before is where the gesture started")

	_section("undo and redo walk the cursor")
	_check(led.can_undo() and not led.can_redo(), "the cursor sits at the tip")
	_check(led.undo_label() == "twice", "the undo label names what is about to be reverted")
	var undone := led.undo()
	_check(undone != null and undone.description == "twice", "undo hands back the entry to replay")
	_check(led.can_redo() and led.redo_label() == "twice", "and it becomes the redo tail")
	_check(led.redo().description == "twice", "redo hands the same entry back")
	_check(not led.can_redo(), "and the tail is consumed")

	_section("recording truncates the redo tail")
	led.undo()
	led.undo()
	_check(led.cursor() == 1, "two undos step the cursor back twice")
	led.record("res://e.guitkx", "x", "y")
	_check(led.entries().size() == 2, "a new action drops the branch the user walked away from")
	_check(not led.can_redo(), "and there is nothing to redo")

	_section("typing merges inside its window")
	var typing := Ledger.new()
	var t := [5000]
	typing.now_msec = func() -> int: return t[0]
	typing.record_typing("res://f.guitkx", "", "a")
	t[0] += 200
	typing.record_typing("res://f.guitkx", "a", "ab")
	t[0] += 200
	typing.record_typing("res://f.guitkx", "ab", "abc")
	_check(typing.entries().size() == 1, "a burst of keystrokes is ONE entry, not one per character")
	_check(typing.entries()[0].changes[0].after == "abc", "carrying the latest text")
	_check(typing.entries()[0].changes[0].before == "", "and the text the burst started from")

	t[0] += Ledger.TYPING_WINDOW_MSEC + 1
	typing.record_typing("res://f.guitkx", "abc", "abcd")
	_check(typing.entries().size() == 2, "a pause past the window starts a new entry")

	typing.record_typing("res://g.guitkx", "", "z")
	_check(typing.entries().size() == 3, "typing in a DIFFERENT file never merges")

	typing.undo()
	typing.record_typing("res://g.guitkx", "z", "zz")
	_check(typing.entries().size() == 3,
		"typing after an undo does not silently extend the entry the cursor left behind")

	typing.begin("gesture")
	typing.record_typing("res://h.guitkx", "", "q")
	typing.end()
	_check(typing.entries()[typing.entries().size() - 1].changes.size() == 1,
		"typing inside a gesture scope joins the gesture instead of merging")

	_section("structural records")
	var st := Ledger.new()
	st.id_of = func(p: String) -> String: return "id:" + p
	st.record_creation("res://new.guitkx")
	_check(st.entries()[0].changes[0].kind == Ledger.ChangeKind.CREATION, "a creation is recorded as one")
	var removed := _make(SANDBOX, "gone", Module.Kind.COMPONENT, "x", true)
	st.record_deletion("res://gone.guitkx", removed)
	var del := st.entries()[1].changes[0]
	_check(del.kind == Ledger.ChangeKind.DELETION, "a deletion is recorded as one")
	_check(del.removed == removed, "holding the module itself, so undo puts the SAME one back")
	st.record_move("res://from.guitkx", "res://to.guitkx")
	var mv := st.entries()[2].changes[0]
	_check(mv.kind == Ledger.ChangeKind.MOVE, "a move is ONE change, not a creation plus a deletion")
	_check(mv.before == "res://from.guitkx" and mv.after == "res://to.guitkx", "carrying both ends")
	_check(mv.module_id == "id:res://from.guitkx",
		"and identity resolved from where the module came from, which is the path the caller knows")

	_section("a deletion takes identity from the module in hand")
	var st2 := Ledger.new()
	st2.id_of = func(_p: String) -> String: return ""
	st2.record_deletion("res://gone2.guitkx", removed)
	_check(st2.entries()[0].changes[0].module_id == removed.id,
		"the module is already out of the tree, so the path lookup finds nothing")

	_section("replay does not log itself")
	var rp := Ledger.new()
	rp.record("res://x.guitkx", "1", "2")
	rp.suppress(func() -> void:
		rp.record("res://x.guitkx", "2", "1")
		rp.record_creation("res://y.guitkx"))
	_check(rp.entries().size() == 1, "an undo rewriting buffers is not a new action")
	_check(not rp.replaying, "and the flag is restored when the scope ends")

	_section("nothing is recorded for nothing")
	var nul := Ledger.new()
	nul.record("res://x.guitkx", "same", "same")
	nul.record("", "a", "b")
	nul.record_typing("res://x.guitkx", "same", "same")
	nul.record_move("", "res://y.guitkx")
	nul.record_creation("")
	nul.record_deletion("")
	_check(nul.entries().is_empty(), "a change that changes nothing leaves no history")
	_check(nul.undo() == null and nul.redo() == null, "and there is nothing to walk")

	_section("the history has a ceiling")
	var cap := Ledger.new()
	for i in range(Ledger.MAX_ENTRIES + 25):
		cap.record("res://cap.guitkx", str(i), str(i + 1))
	_check(cap.entries().size() == Ledger.MAX_ENTRIES, "old entries fall off the front")
	_check(cap.cursor() == Ledger.MAX_ENTRIES, "and the cursor moves with them, so the tip is still the tip")

	cap.clear()
	_check(cap.entries().is_empty() and cap.cursor() == 0 and not cap.can_undo(),
		"clearing empties the whole history")


func _test_no_residue() -> void:
	_section("no residue")
	_rm_rf(SANDBOX)
	_rm_rf(Workspace.UNSAVED_ROOT)
	Journal.clear()
	_check(not DirAccess.dir_exists_absolute(SANDBOX), "the sandbox is gone")
	_check(not DirAccess.dir_exists_absolute(Workspace.UNSAVED_ROOT),
		"and so is the provisional root, if anything ever reached it")
	_check(not FileAccess.file_exists(Journal.JOURNAL_PATH), "and the journal is cleared")
