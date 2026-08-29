extends SceneTree
## Headless test suite for the RUITK Builder's PREVIEW PIPELINE (checkpoint C2). Run:
##   godot --headless --path <project> --script res://tests/builder_preview_test.gd
##
## The pipeline turns unsaved buffers into a live component: mirror the tree to a scratch root
## that Godot ignores, compile there through the real compiler at real paths, materialise the
## generated scripts, and mount the focus through the real reconciler.
##
## Everything below runs headless. Godot has no renderer in this mode but it has the whole node
## tree, so a mount produces real `Control` nodes with real properties -- which is what the
## assertions read. The suite asserts a clean scratch root at the end: a mirror that survives is a
## shadow tree the next session would compile against.

const Workspace = preload("res://addons/reactive_ui_toolkit_editor/builder/document/builder_workspace.gd")
const Preview = preload("res://addons/reactive_ui_toolkit_editor/builder/preview/builder_preview.gd")
const Paths = preload("res://addons/reactive_ui_toolkit_editor/builder/document/builder_paths.gd")
const Codegen = preload("res://addons/reactive_ui_toolkit/guitkx/guitkx_codegen.gd")

const ROOT := "res://tests/__builder_preview_tmp/ui"

## The number of assertions a complete run makes. KEPT EXACT, and raised with the suite.
##
## Left slack, this guard does not work: a script error aborted one test mid-run and the suite
## still printed ALL PASS, because the count it reached was comfortably above a floor set several
## additions ago. The floor only catches a truncated run while it sits AT the real count.
const ASSERTION_FLOOR := 93

var _fails := 0
var _passes := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	Preview.clear_scratch()
	await _test_compile_and_mount()
	await _test_editing_a_child()
	await _test_editing_a_style()
	await _test_failure_isolation()
	await _test_keeps_the_last_good_render()
	await _test_dirty_is_since_last_build()
	await _test_focus_closure()
	await _test_ordering()
	await _test_debounce()
	await _test_budget()
	await _test_degenerate_input()
	await _test_scratch_hygiene()
	await _test_round_hands_off_once()
	await _test_last_error_is_askable()
	await _test_only_components_mount()
	await _test_teardown_leaves_nothing()

	print("")
	# A FLOOR ON THE COUNT. A suite that stops at a broken dependency prints ALL PASS on however
	# few assertions it reached before it stopped -- which is a green line for a run that never
	# arrived at its own subject, and it has now hidden three separate defects in this builder.
	# The number is the tell, so the number is checked.
	if _passes < ASSERTION_FLOOR:
		print("builder preview: only %d of at least %d assertions ran -- something stopped early"
			% [_passes, ASSERTION_FLOOR])
		quit(1)
	if _fails == 0:
		print("builder preview: ALL PASS (%d assertions)" % _passes)
		quit(0)
	else:
		print("builder preview: %d FAILURE(S) of %d assertions" % [_fails, _fails + _passes])
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

const CHILD := """export Child(n: int = 0) -> RuitkVNode {
	return ( <Label text={ "n=%d" % n } /> )
}
"""

const STYLE := """export primary := { "separation": 8 }
"""

const HOOKS := """export use_seed() -> int {
	return 7
}
"""

const PARENT := """import { Child } from "./child"
import { primary } from "./s.style"
import { use_seed } from "./h.hooks"

export Parent() -> RuitkVNode {
	var seed = use_seed()
	return (
		<VBoxContainer style={ primary }>
			<Child n={ seed } />
		</VBoxContainer>
	)
}
"""

## A component nothing in the focus tree imports -- it must never be built for this focus.
const ALOOF := """export Aloof() -> RuitkVNode {
	return ( <Button text="aloof" /> )
}
"""


func _fresh() -> Preview:
	var ws := Workspace.new()
	ws.create_new(ROOT.path_join("child.guitkx"), CHILD)
	ws.create_new(ROOT.path_join("s.style.guitkx"), STYLE)
	ws.create_new(ROOT.path_join("h.hooks.guitkx"), HOOKS)
	ws.create_new(ROOT.path_join("parent.guitkx"), PARENT)
	ws.create_new(ROOT.path_join("aloof.guitkx"), ALOOF)
	var preview := Preview.new()
	preview.workspace = ws
	return preview


func _focus() -> String:
	return ROOT.path_join("parent.guitkx")


func _mount(preview: Preview) -> Control:
	var container := Control.new()
	root.add_child(container)
	preview.mount(container, _focus())
	return container


func _drop(container: Control) -> void:
	if container != null:
		container.queue_free()


# ── The pipeline end to end ──────────────────────────────────────────────────────────

func _test_compile_and_mount() -> void:
	_section("a tree that has never been saved compiles and renders")
	var preview := _fresh()
	var summary := preview.compile_dirty(_focus())
	_check(summary != null, "a first round has work to do")
	_eq(summary.failures.size(), 0, "and nothing fails")
	_eq(summary.skipped.size(), 0, "so nothing is skipped either")
	_check(summary.focus_ok, "the focus built")
	_check(preview.built_script(_focus()) != null, "and has a script to mount")

	_check(not FileAccess.file_exists(ROOT.path_join("parent.guitkx")),
		"and NOTHING reached the real tree -- the save-only contract is intact")

	var container := _mount(preview)
	await process_frame
	_eq(container.get_child_count(), 1, "the focus mounted one root node")
	var box := container.get_child(0)
	_eq(box.get_class(), "VBoxContainer", "which is the component's own root element")
	_eq(box.get("theme_override_constants/separation"), 8,
		"styled from the value module it imports")
	_eq(box.get_child_count(), 1, "with the child component under it")
	_eq(box.get_child(0).text, "n=7",
		"rendered through the imported hook -- component, value and hook imports all resolved")

	preview.teardown()
	_drop(container)


func _test_editing_a_child() -> void:
	_section("editing a CHILD is visible through the parent")
	var preview := _fresh()
	preview.compile_dirty(_focus())
	var container := _mount(preview)
	await process_frame
	_eq(container.get_child(0).get_child(0).text, "n=7", "the first render")

	preview.workspace.apply_edit(ROOT.path_join("child.guitkx"),
		"export Child(n: int = 0) -> RuitkVNode {\n\treturn ( <Button text={ \"b=%d\" % n } /> )\n}\n")
	var summary := preview.compile_dirty(_focus())
	_check(summary != null, "the edit is a round's worth of work")
	_eq(summary.reasons.get(ROOT.path_join("child.guitkx"), ""), "text changed",
		"the child rebuilt because its text moved")
	_eq(summary.reasons.get(_focus(), ""), "dependency rebuilt",
		"and the parent rebuilt because the child did -- an importer whose own text has not moved is never a candidate on its own")

	_drop(container)
	container = _mount(preview)
	await process_frame
	var kid := container.get_child(0).get_child(0)
	_eq(kid.get_class(), "Button", "the second render is the NEW child")
	_eq(kid.text, "b=7", "with its new text")

	preview.teardown()
	_drop(container)


func _test_editing_a_style() -> void:
	_section("editing a VALUE module is visible in its importer")
	var preview := _fresh()
	preview.compile_dirty(_focus())
	preview.workspace.apply_edit(ROOT.path_join("s.style.guitkx"),
		"export primary := { \"separation\": 24 }\n")
	var summary := preview.compile_dirty(_focus())
	_check(summary.rebuilt.has(_focus()),
		"the component rebuilt, not just the style -- otherwise the preview keeps rendering against the old one")

	var container := _mount(preview)
	await process_frame
	_eq(container.get_child(0).get("theme_override_constants/separation"), 24,
		"and the new value is what renders")

	preview.teardown()
	_drop(container)


func _test_failure_isolation() -> void:
	_section("a failure skips only what depends on it")
	var preview := _fresh()
	preview.compile_dirty(_focus())
	preview.workspace.apply_edit(ROOT.path_join("child.guitkx"),
		"export Child(n: int = 0) -> RuitkVNode {\n\treturn ( <Label \n")
	# The aloof module is edited too, so the round has an independent sibling to prove survives.
	preview.workspace.apply_edit(ROOT.path_join("aloof.guitkx"),
		"export Aloof() -> RuitkVNode {\n\treturn ( <Button text=\"still here\" /> )\n}\n")

	var summary := preview.compile_dirty(_focus())
	_eq(summary.failures.size(), 1, "one module failed")
	_eq(str((summary.failures[0] as Dictionary)["path"]), ROOT.path_join("child.guitkx"),
		"and it is the one that was broken")
	_check(not str((summary.failures[0] as Dictionary)["error"]).is_empty(),
		"the failure carries a reason -- nothing about a round is silent")
	_eq(summary.skipped.size(), 1, "one module was skipped")
	_eq(str((summary.skipped[0] as Dictionary)["path"]), _focus(),
		"the parent, because building it would only cascade against a stale peer")
	_eq(str((summary.skipped[0] as Dictionary)["blocked_by"]), ROOT.path_join("child.guitkx"),
		"and it says what blocked it")
	_check(not summary.focus_ok, "so the focus did not build")

	_section("a repaired module clears the block")
	preview.workspace.apply_edit(ROOT.path_join("child.guitkx"), CHILD)
	var fixed := preview.compile_dirty(_focus())
	_check(fixed.is_clean(), "nothing fails and nothing is skipped")
	_check(fixed.focus_ok, "and the focus builds again")

	preview.teardown()


func _test_keeps_the_last_good_render() -> void:
	_section("a broken edit leaves the last good render standing")
	# Typing passes through broken states constantly. A preview that blanks on each one is a
	# preview nobody can work against.
	var preview := _fresh()
	preview.compile_dirty(_focus())
	var container := _mount(preview)
	await process_frame
	_eq(container.get_child(0).get_child(0).text, "n=7", "the good render is up")

	preview.workspace.apply_edit(_focus(), "export Parent() -> RuitkVNode {\n\treturn ( <VBox\n")
	var summary := preview.compile_dirty(_focus())
	_check(not summary.focus_ok, "the focus did not build")
	_check(preview.mount(container, _focus()) == false,
		"so a mount is refused rather than blanking the pane")
	_check(preview.is_mounted(), "and the previous render is still mounted")
	await process_frame
	_eq(container.get_child(0).get_child(0).text, "n=7", "showing what it showed before")

	preview.teardown()
	_check(not preview.is_mounted(), "teardown unmounts")
	_drop(container)


func _test_dirty_is_since_last_build() -> void:
	_section("dirty is measured against the last BUILD, not against disk")
	# Type a label, then type it back: the module is clean against disk again, but the preview
	# was built from the version in between.
	var preview := _fresh()
	preview.compile_dirty(_focus())
	_check(preview.compile_dirty(_focus()) == null, "a settled tree has no round to run")

	preview.workspace.apply_edit(ROOT.path_join("child.guitkx"),
		"export Child(n: int = 0) -> RuitkVNode {\n\treturn ( <Label text=\"typo\" /> )\n}\n")
	preview.compile_dirty(_focus())
	preview.workspace.apply_edit(ROOT.path_join("child.guitkx"), CHILD)
	var back := preview.compile_dirty(_focus())
	_check(back != null,
		"typing the edit BACK is still a round -- the build is one version behind, whatever disk says")
	_check(back.rebuilt.has(ROOT.path_join("child.guitkx")), "and the child is rebuilt")

	var container := _mount(preview)
	await process_frame
	_eq(container.get_child(0).get_child(0).text, "n=7", "so the render is the text that is there now")

	preview.teardown()
	_drop(container)


func _test_focus_closure() -> void:
	_section("only what the focus can reach is built")
	var preview := _fresh()
	var summary := preview.compile_dirty(_focus())
	_check(not summary.considered.has(ROOT.path_join("aloof.guitkx")),
		"a module the focus cannot reach is not a candidate -- building it is pure cost, paid on every settled keystroke")
	_eq(summary.considered.size(), 4, "the focus and the three modules it imports")

	_section("a NON-component focus pulls its importers in")
	# Clicking a style entry to edit it moves the focus onto that style. A forward-only walk
	# drops the component on screen, and it stops updating until the focus moves back.
	preview.workspace.apply_edit(ROOT.path_join("s.style.guitkx"),
		"export primary := { \"separation\": 12 }\n")
	var style_focus := preview.compile_dirty(ROOT.path_join("s.style.guitkx"))
	_check(style_focus.considered.has(_focus()),
		"the component that imports the style is considered, though the focus is the style")
	_check(style_focus.rebuilt.has(_focus()), "and rebuilt")

	preview.teardown()


func _test_ordering() -> void:
	_section("dependencies build before dependents")
	var preview := _fresh()
	var order := PackedStringArray()
	preview.compile_finished.connect(func(path: String, _ok: bool, _err: String):
		order.append(path.get_file()))
	preview.compile_dirty(_focus())
	var child_at := Array(order).find("child.guitkx")
	var style_at := Array(order).find("s.style.guitkx")
	var hooks_at := Array(order).find("h.hooks.guitkx")
	var parent_at := Array(order).find("parent.guitkx")
	_check(child_at >= 0 and style_at >= 0 and hooks_at >= 0 and parent_at >= 0,
		"every module reported (%s)" % ", ".join(order))
	_check(child_at < parent_at, "the child before its importer")
	_check(style_at < parent_at, "the value module before its importer")
	_check(hooks_at < parent_at, "the hook module before its importer")

	preview.teardown()


func _test_debounce() -> void:
	_section("a burst of typing settles into one round")
	var preview := _fresh()
	var clock := [1000]
	preview.now_msec = func() -> int: return clock[0]
	preview.debounce_msec = 300

	_check(not preview.is_due(), "nothing is due before anything is requested")
	preview.request_refresh()
	_check(preview.has_pending(), "a request is pending")
	clock[0] += 200
	_check(not preview.is_due(), "and not yet due")
	preview.request_refresh()
	clock[0] += 200
	_check(not preview.is_due(),
		"a second keystroke pushes the deadline out -- the burst has not settled")
	clock[0] += 150
	_check(preview.is_due(), "once it settles, it is due")
	_check(preview.is_due(), "and asking does not consume it")

	preview.compile_dirty(_focus())
	_check(not preview.has_pending(), "running the round consumes it")
	preview.teardown()


func _test_budget() -> void:
	_section("a round that runs out of budget defers rather than drops")
	var preview := _fresh()
	var clock := [0]
	preview.now_msec = func() -> int:
		clock[0] += 40
		return clock[0]
	preview.budget_msec = 1

	var first := preview.compile_dirty(_focus())
	_check(first.budget_exhausted, "the round stopped early")
	_check(first.rebuilt.size() >= 1, "after building at least one module")
	_check(first.rebuilt.size() < 4, "but not all of them (%d)" % first.rebuilt.size())

	preview.now_msec = Callable()
	preview.budget_msec = 5000
	var second := preview.compile_dirty(_focus())
	_check(second != null, "the rest is still dirty, so the next round picks it up")
	_check(second.focus_ok, "and the focus finishes building")
	_check(preview.compile_dirty(_focus()) == null, "after which there is nothing left to do")

	preview.teardown()


func _test_degenerate_input() -> void:
	_section("an empty buffer is a failure, not a crash")
	var preview := _fresh()
	preview.workspace.apply_edit(ROOT.path_join("child.guitkx"), "")
	var summary := preview.compile_dirty(_focus())
	_check(summary != null, "the round still runs")
	_check(not summary.focus_ok, "and the focus does not build against an empty peer")
	_check(summary.failures.size() + summary.skipped.size() >= 1,
		"with the outcome reported rather than swallowed")
	preview.teardown()

	_section("an import CYCLE completes rather than hanging")
	# The compiler diagnoses a value cycle itself; an ordering pass is not the place to refuse to
	# build, and it is certainly not the place to recurse forever.
	var cyclic := Workspace.new()
	cyclic.create_new(ROOT.path_join("a.guitkx"),
		"import { B } from \"./b\"\n\nexport A() -> RuitkVNode {\n\treturn ( <B /> )\n}\n")
	cyclic.create_new(ROOT.path_join("b.guitkx"),
		"import { A } from \"./a\"\n\nexport B() -> RuitkVNode {\n\treturn ( <A /> )\n}\n")
	var cycle_preview := Preview.new()
	cycle_preview.workspace = cyclic
	var cycle_summary := cycle_preview.compile_dirty(ROOT.path_join("a.guitkx"))
	_check(cycle_summary != null, "the round returns")
	_eq(cycle_summary.considered.size(), 2, "having considered both ends of the cycle")
	cycle_preview.teardown()

	_section("no workspace, no round")
	var bare := Preview.new()
	_check(bare.compile_dirty(_focus()) == null, "a preview with nothing to preview does nothing")
	_check(not bare.mount(null, _focus()), "and mounting into nothing is refused")
	bare.teardown()

	_section("a round says what it did")
	var traced := _fresh()
	var lines := PackedStringArray()
	traced.trace.connect(func(message: String): lines.append(message))
	traced.compile_dirty(_focus())
	_check(lines.size() == 1 and str(lines[0]).contains("built"),
		"one trace line per round (%s)" % ", ".join(lines))
	traced.teardown()


func _test_scratch_hygiene() -> void:
	_section("the mirror follows the tree")
	var preview := _fresh()
	preview.compile_dirty(_focus())
	var mirrored_child := Preview.scratch_path_of(ROOT.path_join("child.guitkx"))
	_check(FileAccess.file_exists(mirrored_child), "a module is mirrored")
	_check(FileAccess.file_exists(mirrored_child.get_basename() + ".gd"),
		"and its generated script is written beside it, so a value import's `preload` resolves")

	_section("a deleted module leaves the mirror")
	# A stale mirror is worse than none: a deleted module left behind keeps satisfying the import
	# that should have started failing.
	preview.workspace.delete(ROOT.path_join("aloof.guitkx"))
	preview.workspace.apply_edit(_focus(), PARENT + "\n")
	preview.compile_dirty(_focus())
	_check(not FileAccess.file_exists(Preview.scratch_path_of(ROOT.path_join("aloof.guitkx"))),
		"the deleted module's mirror is gone")
	_check(not FileAccess.file_exists(
			Preview.scratch_path_of(ROOT.path_join("aloof.guitkx")).get_basename() + ".gd"),
		"and so is its generated script")
	_check(FileAccess.file_exists(mirrored_child), "while the modules that remain are untouched")

	_section("the mirror is under a root nothing looks inside")
	_check(Preview.SCRATCH_ROOT.ends_with("~"),
		"so Godot's importer skips it -- nothing in it is imported or registered as a global class")
	# The `~` stops the IMPORTER, not the compiler: `find_all` walks with DirAccess and skips only
	# dot-directories and folders holding a `.gdignore`. Without the marker, the editor plugin's
	# sweep compiles the mirror, every component collides with the real one it copies (GUITKX2106),
	# and the remediation DELETES the real module's generated .gd. Observed, not hypothetical.
	_check(FileAccess.file_exists(Preview.SCRATCH_ROOT.path_join(".gdignore")),
		"and a .gdignore keeps the COMPILER sweep out of it too")
	var swept: Array = Codegen.find_all("res://")
	var leaked: Array = []
	for p in swept:
		if str(p).begins_with(Preview.SCRATCH_ROOT):
			leaked.append(p)
	_check(leaked.is_empty(),
		"so a project-wide sweep finds nothing in the mirror (found %s)" % str(leaked))
	_check(Preview.scratch_path_of(ROOT.path_join("child.guitkx"))
			.begins_with(Preview.SCRATCH_ROOT + "/"),
		"and every mirrored path is inside it")
	_check(Preview.scratch_path_of("res://a/b/c.guitkx") == Preview.SCRATCH_ROOT + "/a/b/c.guitkx",
		"with the tree's own shape preserved, so relative specifiers fold identically")

	preview.teardown()


## A STYLE MODULE IS NOT A COMPONENT, and the preview must not try to mount one.
##
## Selecting a style companion -- half of what a tree contains -- asked the reconciler to call a
## `render` that a module of plain statics does not have, so merely clicking one logged an engine
## error.
## A ROUND HANDS OFF ONCE, at its end.
##
## `compile_finished` fires INSIDE the build loop, once per module, and the window re-showed the
## preview pane on every one -- so a round rebuilding a style plus three components produced four
## full remounts in a single frame, each tearing down a fiber tree and building it again, three of
## them for a script the pane does not render.
func _test_round_hands_off_once() -> void:
	_section("one round, one hand-off")
	var preview := _fresh()
	var rounds: Array = []
	var per_module: Array = []
	preview.round_finished.connect(func(_s: Variant): rounds.append(1))
	preview.compile_finished.connect(func(_p: String, _ok: bool, _e: String): per_module.append(1))

	var summary = preview.compile_dirty(_focus())
	_check(summary != null, "the round did work")
	_eq(rounds.size(), 1, "and announced itself exactly once")
	_check(per_module.size() > 1,
		"while the per-module feed fired %d times -- which is why it is not the hand-off"
			% per_module.size())

	_section("a round that does nothing announces nothing")
	# The no-op early return must not emit, or the caller re-renders on every idle tick.
	var again = preview.compile_dirty(_focus())
	if again == null:
		_eq(rounds.size(), 1, "no second hand-off for a round with nothing to do")

	preview.teardown()


## THE PANE CAN ASK WHY A MODULE DID NOT BUILD.
##
## It used to infer a failure from an EMPTY STAGE, which is a different question -- and answers
## "yes" for a module nobody has compiled yet.
func _test_last_error_is_askable() -> void:
	_section("a clean module reports nothing")
	var preview := _fresh()
	preview.compile_dirty(_focus())
	_eq(preview.last_error_for(_focus()), "", "nothing wrong, nothing reported")

	_section("a broken one reports why, and recovers when fixed")
	var path := _focus()
	var good: String = preview.workspace.try_get(path).buffer_text
	preview.workspace.apply_edit(path, good + "
this is not guitkx <<<
")
	preview.compile_dirty(path)
	_check(not preview.last_error_for(path).is_empty(),
		"the failure is askable (%s)" % preview.last_error_for(path))

	preview.workspace.apply_edit(path, good)
	preview.compile_dirty(path)
	_eq(preview.last_error_for(path), "", "and clears when the module builds again")

	preview.teardown()


func _test_only_components_mount() -> void:
	_section("a component's script has a render; a style module's does not")
	var preview := _fresh()
	preview.compile_dirty(_focus())
	_check(Preview.has_render(preview.built_script(_focus())),
		"the focus component is mountable")

	var style_path := ROOT.path_join("s.style.guitkx")
	preview.compile_dirty(style_path)
	var style := preview.built_script(style_path)
	_check(style != null, "the style module builds")
	_check(not Preview.has_render(style), "and has no render to call")

	var stage := Control.new()
	root.add_child(stage)
	_check(not preview.mount(stage, style_path),
		"so mount reports false rather than asking for a function that is not there")
	stage.queue_free()
	preview.teardown()


func _test_teardown_leaves_nothing() -> void:
	_section("teardown leaves nothing")
	var preview := _fresh()
	preview.compile_dirty(_focus())
	var container := _mount(preview)
	await process_frame
	_check(DirAccess.dir_exists_absolute(Preview.SCRATCH_ROOT), "the mirror existed")

	preview.teardown()
	_check(not DirAccess.dir_exists_absolute(Preview.SCRATCH_ROOT),
		"and teardown removes it whole -- a mirror that survives is a shadow tree the next session compiles against")
	_check(preview.built_script(_focus()) == null, "every built script is dropped")

	var leaked := 0
	for key in (V._comp_cache as Dictionary).keys():
		if str(key).begins_with(Preview.SCRATCH_ROOT):
			leaked += 1
	_eq(leaked, 0, "and no component factory is left pointing into the mirror")

	_drop(container)
	_rm_rf(ROOT.get_base_dir())
	_check(not DirAccess.dir_exists_absolute(ROOT.get_base_dir()),
		"the fixture tree never touched disk, so there is nothing of it to clean up either")


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
