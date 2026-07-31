extends SceneTree
## Headless tests for the editor-layer pieces that don't need a live Godot editor: the
## GuitkxCodeEdit substrate configuration (parity plan §2B E-table) and, as later workstreams
## land, dirty-state logic, path retargeting, and diagnostics rendering records.
## Run: godot --headless --path . --script res://tests/guitkx_editor_test.gd

const CodeEditScript := preload("res://addons/reactive_ui_toolkit_editor/editor/guitkx_code_edit.gd")
const ViewScript := preload("res://addons/reactive_ui_toolkit_editor/editor/guitkx_editor_view.gd")
const TMP_PATH := "res://tests/__editor_test_tmp.guitkx"
const TMP_SRC := "component EditorTmp() {\n\treturn (\n\t\t<Label text=\"hi\" />\n\t)\n}\n"

var _failed := 0
var _passed := 0

func _initialize() -> void:
	# One marker line per section (flushed immediately): when a regression HANGS the suite, the
	# partial log names the culprit instead of leaving a blank file [field capture 2026-07-05].
	for t: Array in [
		["parses", _test_parses],
		["substrate", _test_substrate],
		["undoable", _test_undoable_set_text],
		["buffer_state", _test_buffer_state],
		["intelligence", _test_intelligence_wiring],
		["find_bar", _test_find_bar],
		["deps", _test_deps_handshake],
		["settings_dialog", _test_settings_dialog],
		["main_menu_helper", _test_main_menu_helper],
		["schema_sync", _test_schema_sync],
		["scan_diags", _test_scan_diags],
		["rich_hover", _test_rich_hover],
		["formatter_config", _test_formatter_config],
		["sidecar_overlay", _test_sidecar_overlay],
		["wave2_completion", _test_wave2_completion],
		["comment_toggle", _test_comment_toggle],
		["refs_and_rename", _test_refs_and_rename],
		["es_editor_intelligence", _test_es_editor_intelligence],
		["multifile", _test_multifile],
		["outline", _test_outline],
		["replace", _test_replace],
		["project_search", _test_project_search],
		["problems_project", _test_problems_project],
		["signature", _test_signature],
		["wave7_editing", _test_wave7_editing],
		["tokenizer_corpus", _test_tokenizer_corpus],
		["parity_pins", _test_parity_pins],
		["line_index", _test_line_index],
		["source_map", _test_source_map],
		["virtual_doc", _test_virtual_doc],
		["analyzer_bridge", _test_analyzer_bridge],
	]:
		print("[guitkx_editor_test] -- %s" % t[0])
		(t[1] as Callable).call()
	_cleanup_tmp()
	print("[guitkx_editor_test] %d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)

# Never leave a temp .guitkx behind: the reactive_ui_toolkit watcher in a live editor would sweep/compile it.
func _cleanup_tmp() -> void:
	if FileAccess.file_exists(TMP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_PATH))

# Editor-layer scripts only load inside a live editor; a parse error there would otherwise ship
# unseen. load() returns a script object even for a broken script, so gate on can_instantiate()
# (false when compilation failed), not on null.
func _test_parses() -> void:
	for p in [
		"res://addons/reactive_ui_toolkit_editor/plugin.gd",
		"res://addons/reactive_ui_toolkit_editor/ruitk_editor_deps.gd",
		"res://addons/reactive_ui_toolkit_editor/editor/guitkx_editor_view.gd",
		"res://addons/reactive_ui_toolkit_editor/editor/guitkx_code_edit.gd",
		"res://addons/reactive_ui_toolkit_editor/editor/guitkx_find_bar.gd",
		"res://addons/reactive_ui_toolkit_editor/editor/ruitk_settings_dialog.gd",
		"res://addons/reactive_ui_toolkit_editor/editor/guitkx_diagnostics_renderer.gd",
		"res://addons/reactive_ui_toolkit_editor/editor/guitkx_problems_panel.gd",
		"res://addons/reactive_ui_toolkit_editor/editor/guitkx_references_panel.gd",
		"res://addons/reactive_ui_toolkit_editor/editor/guitkx_search_panel.gd",
		"res://addons/reactive_ui_toolkit_editor/lsp/guitkx_outline.gd",
		"res://addons/reactive_ui_toolkit_editor/lsp/guitkx_signature.gd",
		"res://addons/reactive_ui_toolkit_editor/lsp/guitkx_source_map.gd",
		"res://addons/reactive_ui_toolkit_editor/lsp/guitkx_line_index.gd",
		"res://addons/reactive_ui_toolkit_editor/lsp/guitkx_virtual_doc.gd",
		"res://addons/reactive_ui_toolkit_editor/lsp/guitkx_analyzer_bridge.gd",
		"res://addons/reactive_ui_toolkit_editor/resources/guitkx_resource.gd",
		"res://addons/reactive_ui_toolkit_editor/resources/guitkx_resource_loader.gd",
	]:
		var s: GDScript = load(p)
		_ok(s != null and s.can_instantiate(), "%s compiles" % str(p).get_file())

func _ok(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		printerr("  FAIL: ", msg)

# W1 — every substrate property configure() promises (E1-E10, E16 subset). configure() is pure
# CodeEdit state, deliberately callable without the editor so this suite can pin it.
func _test_substrate() -> void:
	var ce: CodeEdit = CodeEditScript.new()
	ce.configure()

	# E3: indentation matches the formatter (spaces/2), not tabs/4 — the indent fight.
	_ok(ce.indent_use_spaces, "indent uses spaces (formatter parity)")
	_ok(ce.indent_size == 2, "indent size 2 (formatter parity)")
	_ok(ce.indent_automatic, "E5: automatic indent on Enter")
	_ok(ce.draw_tabs, "tab glyphs visible (mixed-indent visibility)")

	# Delimiters feed highlighting + folding.
	_ok(ce.has_comment_delimiter("#"), "# comment delimiter")
	_ok(ce.has_string_delimiter("\""), "double-quote string delimiter")
	_ok(ce.has_string_delimiter("'"), "single-quote string delimiter")

	# E4/E8: auto-close incl. markup's own pair, matching-brace highlight.
	_ok(ce.auto_brace_completion_enabled, "auto-brace completion enabled")
	_ok(ce.auto_brace_completion_pairs.has("<") and str(ce.auto_brace_completion_pairs["<"]) == ">",
		"E4: '<' auto-closes to '>'")
	_ok(ce.auto_brace_completion_highlight_matching, "E8: matching-brace highlight")

	# E1/E9: line numbers + folding gutters.
	_ok(ce.gutters_draw_line_numbers, "E1: line numbers gutter")
	_ok(ce.line_folding, "E9: line folding")
	_ok(ce.gutters_draw_fold_gutter, "E9: fold gutter")

	# E6/E7/E10/E16: view comforts.
	_ok(ce.highlight_current_line, "E6: current-line highlight")
	_ok(ce.highlight_all_occurrences, "E7: occurrence highlight")
	_ok(ce.minimap_draw, "E10: minimap")
	_ok(ce.caret_blink, "caret blinks")
	_ok(ce.scroll_smooth, "smooth scroll")
	_ok(ce.scroll_past_end_of_file, "scroll past end")
	var guides: Array = ce.line_length_guidelines
	_ok(guides.size() == 1 and int(guides[0]) == 100, "ruler at print width 100")

	# Diagnostics gutter: exists, icon-typed, clickable.
	_ok(ce.diag_gutter >= 0, "diagnostics gutter allocated")
	_ok(ce.get_gutter_type(ce.diag_gutter) == TextEdit.GUTTER_TYPE_ICON, "diagnostics gutter is icon type")
	_ok(ce.is_gutter_clickable(ce.diag_gutter), "diagnostics gutter clickable")

	# Completion triggers.
	_ok(ce.code_completion_enabled, "completion enabled")
	var prefixes := ce.code_completion_prefixes
	_ok("<" in prefixes and "@" in prefixes and " " in prefixes, "completion prefixes <, @, space")

	# E2: hover can actually fire — the property gates the symbol_hovered signal entirely.
	if "symbol_tooltip_on_hover" in ce:
		_ok(ce.symbol_tooltip_on_hover, "E2: symbol_tooltip_on_hover set (hover alive)")
		_ok(ce.is_connected("symbol_hovered", ce._on_symbol_hovered), "symbol_hovered connected")

	# configure() must be idempotent — plugin reload / re-open paths may call it again.
	var gutters_before := ce.get_gutter_count()
	ce.configure()
	_ok(ce.get_gutter_count() == gutters_before, "configure() idempotent (no duplicate gutters)")

	ce.free()

# W2/G33 — whole-buffer replacement must be ONE undoable edit; `.text =` wipes undo history.
func _test_undoable_set_text() -> void:
	var ce: CodeEdit = CodeEditScript.new()
	ce.text = "alpha\nbeta"
	ce.clear_undo_history()
	ce.set_caret_line(1)
	ce.set_caret_column(2)
	ce.set_text_undoable("gamma\ndelta\nepsilon")
	_ok(ce.text == "gamma\ndelta\nepsilon", "set_text_undoable replaces the buffer")
	_ok(ce.get_caret_line() == 1 and ce.get_caret_column() == 2, "caret preserved across replace")
	_ok(ce.has_undo(), "replacement is on the undo stack")
	ce.undo()
	_ok(ce.text == "alpha\nbeta", "one undo restores the pre-replace buffer")
	ce.set_text_undoable("x")
	_ok(ce.get_caret_line() == 0 and ce.get_caret_column() == 1, "caret clamped into shrunken buffer")
	ce.free()

# W2 — dirty tracking, retarget (L1), detach (L2), and save_silent's refusal paths (L4 flows).
func _test_buffer_state() -> void:
	var fa := FileAccess.open(TMP_PATH, FileAccess.WRITE)
	fa.store_string(TMP_SRC)
	fa.close()

	var v: Control = ViewScript.new()
	_ok(not v.is_dirty(), "fresh view is clean")
	_ok(v._file_label.text == "(scratch)", "fresh view starts on the scratch buffer")

	# An untouched scratch buffer must not be diagnosed (field capture: red X on an empty editor).
	v._refresh_diagnostics()
	_ok(v._code_edit.get_line_gutter_icon(0, v._code_edit.diag_gutter) == null,
		"empty pathless buffer carries no diagnostics")

	v.open_path(TMP_PATH)
	_ok(v.current_path() == TMP_PATH, "open_path sets current path")
	_ok(not v.is_dirty(), "freshly opened buffer is clean")
	_ok(v._loaded_mtime != 0, "load records the disk mtime")
	_ok(not v._code_edit.has_undo(), "load clears undo history")

	v._on_editor_text_changed(v._code_edit)
	_ok(v.is_dirty(), "user edit marks dirty")
	_ok(v._file_label.text.ends_with("*"), "dirty shown in the file label")

	# L1: rename-follow keeps buffer + dirty state, updates the path.
	v.retarget_path("res://tests/renamed_tmp.guitkx")
	_ok(v.current_path() == "res://tests/renamed_tmp.guitkx", "retarget updates path")
	_ok(v.is_dirty(), "retarget preserves dirty state")
	v.retarget_path(TMP_PATH)

	# G25 conflict: disk changed since load -> silent save must refuse, buffer stays dirty.
	v._loaded_mtime = 1
	_ok(not v.save_silent(), "save_silent refuses on disk conflict")
	_ok(v.is_dirty(), "conflict refusal keeps the buffer dirty")
	v._loaded_mtime = FileAccess.get_modified_time(TMP_PATH)

	# L2: deletion detach -> label + silent-save refusal (never resurrect during Save All).
	v.mark_detached()
	_ok(v._file_label.text.contains("(deleted on disk)"), "detached shown in the file label")
	_ok(not v.save_silent(), "save_silent refuses to recreate a deleted file")

	# Clean buffer: silent save is a no-op success.
	v._detached = false
	v._dirty = false
	_ok(v.save_silent(), "save_silent no-ops cleanly when nothing is dirty")

	# Detach does NOT imply dirty, and a clean detached buffer HEALS on focus once the file is
	# back on disk (the git-restore recovery; field capture: stuck "(deleted on disk) *").
	v.mark_detached()
	_ok(not v.is_dirty(), "detach alone does not dirty the buffer")
	v._notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	_ok(not v._detached, "focus-in heals a clean detached buffer when the file is back")
	_ok(not v._file_label.text.contains("deleted"), "healed label drops the deleted marker")

	# Same-file reopen with edits must NOT clobber the buffer (the double-click self-open trap).
	v._on_editor_text_changed(v._code_edit)
	var before: String = v._code_edit.text
	v._code_edit.text = before + "\n# local edit"
	v.open_path(TMP_PATH)
	_ok(v._code_edit.text.ends_with("# local edit"), "same-file reopen keeps dirty edits")

	v.free()

# W3 — goto-def resolution + navigation, cross-file bindings cache, pathless basename, adaptive gate.
func _test_intelligence_wiring() -> void:
	var fa := FileAccess.open(TMP_PATH, FileAccess.WRITE)
	fa.store_string(TMP_SRC)
	fa.close()
	GuitkxWorkspace.rescan()

	# Workspace exposes the full path list (feeds project_bindings).
	_ok(GuitkxWorkspace.all_paths().has(TMP_PATH), "all_paths includes the temp component")

	# G1: symbol lookup resolves a known component through the widget and emits the navigation
	# request; unknown symbols stay silent.
	var ce: CodeEdit = CodeEditScript.new()
	var got: Array = []
	ce.definition_requested.connect(func(p: String, o: int):
		got.append(p)
		got.append(o))
	ce._on_symbol_lookup("EditorTmp", 0, 0)
	_ok(got.size() == 2 and got[0] == TMP_PATH, "symbol lookup resolves the declaring file")
	_ok(got.size() == 2 and int(got[1]) == TMP_SRC.find("EditorTmp"), "symbol lookup carries the declaration offset")
	got.clear()
	ce._on_symbol_lookup("NoSuchComponentXyz", 0, 0)
	_ok(got.is_empty(), "unknown symbol emits nothing")
	_ok(ce.symbol_lookup_on_click, "ctrl+click lookup enabled")
	ce.free()

	# Same-file navigation places the caret at the declaration.
	var v: Control = ViewScript.new()
	v.open_path(TMP_PATH)
	v._on_definition_requested(TMP_PATH, TMP_SRC.find("EditorTmp"))
	_ok(v._code_edit.get_caret_line() == 0 and v._code_edit.get_caret_column() == TMP_SRC.find("EditorTmp"),
		"same-file goto-def lands on the declaration")

	# Cross-file navigation: pending offset survives the load.
	var second := "res://tests/__editor_test_tmp2.guitkx"
	var fb := FileAccess.open(second, FileAccess.WRITE)
	fb.store_string("component Other() {\n\treturn (\n\t\t<EditorTmp />\n\t)\n}\n")
	fb.close()
	v._on_definition_requested(second, 10)
	_ok(v.current_path() == second, "cross-file goto-def opens the target")
	_ok(v._code_edit.get_caret_line() == 0 and v._code_edit.get_caret_column() == 10,
		"pending jump applied after load")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(second))

	# G13/P2: bindings cache — computed once, invalidated by on_workspace_changed.
	var pb1: Dictionary = v._project_bindings()
	_ok((pb1.get("known", []) as Array).has("EditorTmp"), "project bindings know the temp component")
	_ok(v._bindings_valid, "bindings cached after compute")
	v.on_workspace_changed()
	_ok(v._bindings_valid, "on_workspace_changed recomputes (refresh re-fills the cache)")

	# D4: pathless buffers derive the compile identity from their own declaration.
	v._current_path = ""
	_ok(v._basename("component Foo() {\n}") == "Foo", "pathless basename from declaration")
	_ok(v._basename("# nothing declared") == "Component", "pathless fallback stays 'Component'")
	v._current_path = TMP_PATH
	_ok(v._basename() == "__editor_test_tmp", "pathed basename is the file stem")

	# P1: adaptive debounce math.
	_ok(absf(ViewScript._adaptive_wait(10.0) - 0.3) < 0.001, "fast compiles keep the 0.3s debounce")
	_ok(absf(ViewScript._adaptive_wait(200.0) - 0.8) < 0.001, "189ms-class compiles stretch to ~0.8s")
	_ok(absf(ViewScript._adaptive_wait(3000.0) - 2.0) < 0.001, "debounce capped at 2s")

	v.free()

# W4/G24 — find bar: open seeds from selection, counts, steps forward/back with wrap, case toggle.
func _test_find_bar() -> void:
	const FindBar := preload("res://addons/reactive_ui_toolkit_editor/editor/guitkx_find_bar.gd")
	var ce: CodeEdit = CodeEditScript.new()
	ce.text = "alpha beta\ngamma alpha\nALPHA end"
	var bar: HBoxContainer = FindBar.new()
	bar.attach(ce)

	_ok(not bar.visible, "find bar hidden by default")
	ce.select(0, 0, 0, 5)  # "alpha"
	bar.open_bar()
	_ok(bar.visible, "open shows the bar")
	_ok(bar.query_text() == "alpha", "open seeds the query from the selection")
	_ok(bar.armed_search() == "alpha", "all-match highlight armed")
	_ok(bar._count.text.begins_with("3 match"), "case-insensitive count includes ALPHA")

	# Live-jump landed on match 2 (after the caret); stepping selects match 3, then wraps to match 1.
	bar.find_step(true)
	_ok(ce.get_selected_text().to_lower() == "alpha", "next selects a match")
	_ok(ce.get_caret_line() == 2, "next advances to the last match")
	bar.find_step(true)
	_ok(ce.get_caret_line() == 0, "forward search wraps to the top")

	bar.find_step(false)
	_ok(ce.get_caret_line() == 2, "backward search wraps to the bottom")

	# Case-sensitive narrows to the two lowercase hits.
	bar._case.button_pressed = true
	bar._update_search()
	_ok(bar._count.text.begins_with("2 match"), "case-sensitive count excludes ALPHA")

	bar.close_bar()
	_ok(not bar.visible, "close hides the bar")
	_ok(bar.armed_search() == "", "close clears the match highlight")

	bar.free()
	ce.free()

# W5/F9 — dependency handshake facts + the numeric version comparator.
func _test_deps_handshake() -> void:
	const Deps := preload("res://addons/reactive_ui_toolkit_editor/ruitk_editor_deps.gd")
	var check: Dictionary = Deps.satisfied()
	_ok(bool(check.get("ok", false)), "handshake passes in this repo (reactive_ui_toolkit present)")
	var ver: String = Deps.installed_version()
	_ok(ver != "" and ver.split(".").size() == 3, "installed reactive_ui_toolkit version parses (got '%s')" % ver)
	_ok(not Deps._version_lt(ver, Deps.MIN_REACTIVE_UI), "installed version satisfies MIN_REACTIVE_UI")
	_ok(Deps._version_lt("0.8.1", "0.8.2"), "semver: 0.8.1 < 0.8.2")
	_ok(Deps._version_lt("0.9.9", "0.10.0"), "semver: numeric, not lexicographic")
	_ok(not Deps._version_lt("0.8.2", "0.8.2"), "semver: equal is not less")
	_ok(not Deps._version_lt("1.0.0", "0.9.9"), "semver: major dominates")
	# Godot-version gate (MIN_GODOT 4.4 -- the analyzer GDExtension's compatibility_minimum).
	_ok(Deps.godot_version_ok(), "gate: the RUNNING Godot satisfies MIN_GODOT (this suite runs on it)")
	_ok(not Deps.godot_version_ok("4.3.2"), "gate: 4.3.x is refused")
	_ok(Deps.godot_version_ok("4.4.0") and Deps.godot_version_ok("4.7.1") and Deps.godot_version_ok("5.0.0"), "gate: 4.4+/5.x pass")
	# The runtime addon's watcher gate agrees (same floor, its own testable static).
	const RtPlugin := preload("res://addons/reactive_ui_toolkit/plugin.gd")
	_ok(str(RtPlugin.MIN_GODOT) == str(Deps.MIN_GODOT), "gate: runtime and editor addons claim the SAME floor")
	_ok(RtPlugin.godot_supported() and not RtPlugin.godot_supported("4.3.2") and RtPlugin.godot_supported("4.4.0"), "gate: runtime godot_supported matches")

# The one-settings-screen dialog (family design): sections populate from ProjectSettings, a
# simulated control change writes through with register_all's only-save-when-dirty discipline,
# and the W5 arm (runtime addon absent) degrades to the Editor section alone. Every key this
# test touches is flipped back / cleared, and project.godot must end BYTE-IDENTICAL to how it
# started (the settings_test.gd no-residue promise).
func _test_settings_dialog() -> void:
	const DialogScript := preload("res://addons/reactive_ui_toolkit_editor/editor/ruitk_settings_dialog.gd")
	const EdSettings := preload("res://addons/reactive_ui_toolkit_editor/editor/ruitk_editor_settings.gd")
	var RtSettings: GDScript = load("res://addons/reactive_ui_toolkit/core/settings.gd")

	# Register both groups first (settings_test.gd's no-residue order): any first-registration
	# save happens while every key still equals its initial value, so nothing persists.
	EdSettings.register_all()
	RtSettings.register()
	var project_before := FileAccess.get_file_as_string("res://project.godot")

	var d: Window = DialogScript.new()
	_ok(Array(d._sections) == ["Runtime", "Editor"], "both sections built (runtime addon present)")
	_ok(d._controls.size() == RtSettings.DEFAULTS.size() + EdSettings.DEFAULTS.size(),
		"one control per settings key (got %d)" % d._controls.size())

	# Populate: bools -> CheckBox, the float -> SpinBox, tri-states -> OptionButton, all read
	# through ProjectSettings with the owning class's defaults as fallback.
	var cb: CheckBox = d._controls[EdSettings.KEY_FORMAT_ON_SAVE]
	_ok(cb.button_pressed == bool(ProjectSettings.get_setting(EdSettings.KEY_FORMAT_ON_SAVE, true)),
		"editor bool populates from the stored value")
	var sb: SpinBox = d._controls[RtSettings.KEY_FRAME_BUDGET_MS]
	_ok(sb.value == float(ProjectSettings.get_setting(RtSettings.KEY_FRAME_BUDGET_MS, 8.0)),
		"frame_budget_ms populates the SpinBox")
	var ob: OptionButton = d._controls[RtSettings.KEY_HOOK_VALIDATION]
	_ok(ob.item_count == 3, "tri-state offers auto/enabled/disabled")
	_ok(ob.get_item_text(ob.selected) == str(ProjectSettings.get_setting(RtSettings.KEY_HOOK_VALIDATION, "auto")),
		"tri-state populates the OptionButton")

	# A stored non-default value populates after rebuild (the about_to_popup refresh path).
	ProjectSettings.set_setting(RtSettings.KEY_FRAME_BUDGET_MS, 4.0)
	d.rebuild()
	_ok((d._controls[RtSettings.KEY_FRAME_BUDGET_MS] as SpinBox).value == 4.0,
		"rebuild re-reads a value changed in the native dialog")
	ProjectSettings.set_setting(RtSettings.KEY_FRAME_BUDGET_MS, RtSettings.DEFAULTS[RtSettings.KEY_FRAME_BUDGET_MS])
	d.rebuild()

	# Simulated toggle: flipping the CheckBox writes the key AND saves; flipping back restores
	# project.godot byte-identically (the value equals its initial value again -> omitted).
	cb = d._controls[EdSettings.KEY_FORMAT_ON_SAVE]
	var orig: bool = cb.button_pressed
	cb.button_pressed = not orig   # the setter emits toggled -> the dialog writes + saves
	_ok(bool(ProjectSettings.get_setting(EdSettings.KEY_FORMAT_ON_SAVE, true)) == (not orig),
		"toggle writes through to ProjectSettings")
	_ok(FileAccess.get_file_as_string("res://project.godot") != project_before,
		"changed value is persisted (save() ran)")
	cb.button_pressed = orig
	_ok(FileAccess.get_file_as_string("res://project.godot") == project_before,
		"flipping back restores project.godot byte-identically")

	# Save discipline: writing the unchanged value is a no-op (no set_setting, no save).
	d._write(EdSettings.KEY_FORMAT_ON_SAVE, orig, EdSettings.DEFAULTS[EdSettings.KEY_FORMAT_ON_SAVE])
	_ok(FileAccess.get_file_as_string("res://project.godot") == project_before,
		"unchanged value never dirties project.godot")

	# SpinBox write path. 4.7 Range gotcha (observed headless): value_changed only self-emits
	# while the control is INSIDE the tree — the popped-up dialog always is, but out-of-tree
	# test nodes must emit like the UI would (the OptionButton pattern below).
	sb = d._controls[RtSettings.KEY_FRAME_BUDGET_MS]
	sb.value = 4.0
	sb.value_changed.emit(sb.value)
	_ok(float(ProjectSettings.get_setting(RtSettings.KEY_FRAME_BUDGET_MS, 8.0)) == 4.0,
		"SpinBox change writes the float")
	sb.value = float(RtSettings.DEFAULTS[RtSettings.KEY_FRAME_BUDGET_MS])
	sb.value_changed.emit(sb.value)

	# Tri-state write path: select() alone never emits, so emit like the UI would.
	ob = d._controls[RtSettings.KEY_HOOK_VALIDATION]
	ob.select(1)
	ob.item_selected.emit(1)
	_ok(str(ProjectSettings.get_setting(RtSettings.KEY_HOOK_VALIDATION, "auto")) == "enabled",
		"tri-state selection writes the enum string")
	ob.select(0)
	ob.item_selected.emit(0)
	_ok(FileAccess.get_file_as_string("res://project.godot") == project_before,
		"all runtime keys restored -> project.godot byte-identical")
	d.free()

	# W5: runtime addon absent -> the Editor section alone (the dialog reaches RuitkSettings
	# only via load() behind a file_exists guard, so a missing path degrades, never errors).
	var d2: Window = DialogScript.new()
	d2.runtime_settings_path = "res://addons/__absent__/core/settings.gd"
	d2.rebuild()
	_ok(Array(d2._sections) == ["Editor"], "W5: missing runtime addon -> Editor section only")
	_ok(d2._controls.size() == EdSettings.DEFAULTS.size(), "W5: only the editor keys remain")
	_ok(not d2._controls.has(RtSettings.KEY_TIME_SLICING), "W5: no runtime controls built")
	d2.free()

	# Leave nothing behind (the settings_test.gd cleanup discipline: set_setting(null)).
	for key in RtSettings.DEFAULTS:
		ProjectSettings.set_setting(key, null)
	for key in EdSettings.DEFAULTS:
		ProjectSettings.set_setting(key, null)
	_ok(FileAccess.get_file_as_string("res://project.godot") == project_before,
		"suite leaves project.godot untouched")

# The top-level "Reactive UI Toolkit" menu injects a PopupMenu into the editor's MenuBar; the
# only editor-internals dependency is FINDING that bar, done by plugin.gd's static, depth-capped
# find_menu_bar — which is exactly what a synthetic tree can exercise headless. The fallback
# (Project > Tools via add_tool_menu_item) engages precisely when this helper returns null.
func _test_main_menu_helper() -> void:
	var PluginScript: GDScript = load("res://addons/reactive_ui_toolkit_editor/plugin.gd")
	_ok(PluginScript != null and PluginScript.can_instantiate(), "plugin.gd compiles")

	# Shallow synthetic editor shape: base -> title strip -> MenuBar. Found within budget.
	var base := Control.new()
	var strip := HBoxContainer.new()
	var bar := MenuBar.new()
	base.add_child(strip)
	strip.add_child(bar)
	_ok(PluginScript.find_menu_bar(base, 8) == bar, "MenuBar found through a shallow tree")
	_ok(PluginScript.find_menu_bar(bar, 8) == bar, "a MenuBar root returns itself")

	# Depth cap honored: a bar buried deeper than the budget is deliberately NOT found (the
	# fallback path is the tested, safe behavior on a restructured editor).
	var deep_root := Control.new()
	var cursor: Control = deep_root
	for _i in range(3):
		var next := Control.new()
		cursor.add_child(next)
		cursor = next
	var deep_bar := MenuBar.new()
	cursor.add_child(deep_bar)
	_ok(PluginScript.find_menu_bar(deep_root, 2) == null, "depth budget stops the search short")
	_ok(PluginScript.find_menu_bar(deep_root, 8) == deep_bar, "same tree resolves with real budget")

	# No MenuBar anywhere -> null, never an error.
	var empty := Control.new()
	empty.add_child(Control.new())
	_ok(PluginScript.find_menu_bar(empty, 8) == null, "menubar-less tree returns null")

	# MenuBar contract sanity (the official half of the technique): a child PopupMenu becomes a
	# titled top-level menu.
	var popup := PopupMenu.new()
	popup.name = "Reactive UI Toolkit"
	bar.add_child(popup)
	_ok(bar.get_menu_count() == 1 and bar.get_menu_title(0) == "Reactive UI Toolkit",
		"child PopupMenu surfaces as a titled top-level menu")

	base.free()
	deep_root.free()
	empty.free()

# W6/F8/F12 — the bundled schema is a hand-synced copy with no generator; these tripwires turn
# silent drift (between the two shipping editors, and against the compiler's tag universe) into
# CI failures.
func _test_schema_sync() -> void:
	var bundled := FileAccess.get_file_as_string("res://addons/reactive_ui_toolkit_editor/data/guitkx-schema.json")
	var grammar := FileAccess.get_file_as_string("res://ide-extensions/grammar/guitkx-schema.json")
	_ok(bundled != "", "bundled schema readable")
	if grammar != "":
		# Byte-identity with the source grammar (the copy the VS Code tooling ships from). The
		# grammar file is absent from store installs — this arm runs in the repo/CI only.
		_ok(bundled == grammar,
			"bundled schema == ide-extensions grammar (resync: copy grammar/guitkx-schema.json into addons/reactive_ui_toolkit_editor/data/)")
	# Store-packaging sync (field feedback on the AL listing): the addon folder carries its own
	# README/CHANGELOG/LICENSE so installs never touch the user's project root. The CHANGELOG is
	# a mirror of the root one — this tripwire keeps them byte-identical (resync: cp CHANGELOG.md
	# addons/reactive_ui_toolkit/CHANGELOG.md).
	_ok(FileAccess.get_file_as_string("res://addons/reactive_ui_toolkit/CHANGELOG.md")
		== FileAccess.get_file_as_string("res://CHANGELOG.md"),
		"addon CHANGELOG mirrors the root CHANGELOG")
	_ok(FileAccess.file_exists("res://addons/reactive_ui_toolkit/README.md"), "addon carries its own README")
	_ok(FileAccess.file_exists("res://addons/reactive_ui_toolkit/LICENSE"), "addon carries its own LICENSE")
	_ok(FileAccess.file_exists("res://addons/reactive_ui_toolkit_editor/README.md")
		and FileAccess.file_exists("res://addons/reactive_ui_toolkit_editor/LICENSE"),
		"editor addon carries its own README + LICENSE")

	var parsed: Variant = JSON.parse_string(bundled)
	_ok(parsed is Dictionary and (parsed as Dictionary).has("hostElements"), "bundled schema parses")
	# Every schema host element must exist in the compiler's vocabulary (the source of truth the
	# watcher compiles with) — a tag added there but not here silently vanishes from completion.
	var vocab_tags: Dictionary = RuitkGuitkx.vocab().get("host_tags", {})
	_ok(not vocab_tags.is_empty(), "compiler vocabulary host_tags readable")
	var missing: Array = []
	for el in (parsed as Dictionary).get("hostElements", []):
		var tag := str((el as Dictionary).get("tag", ""))
		if tag != "" and not vocab_tags.has(tag):
			missing.append(tag)
	_ok(missing.is_empty(), "schema hostElements ⊆ compiler vocabulary (unknown: %s)" % str(missing))

# Field captures from the M1 acceptance pass: fixture pollution + parse-masked 0105.
func _test_scan_diags() -> void:
	const Scan := preload("res://addons/reactive_ui_toolkit_editor/lsp/guitkx_scan_diags.gd")

	# .gdignore honored: the contract fixtures (duplicate/broken decls) never reach the index.
	GuitkxWorkspace.rescan()
	var polluted := false
	for p in GuitkxWorkspace.all_paths():
		if str(p).contains("/contract/fixtures/"):
			polluted = true
	_ok(not polluted, ".gdignore folders excluded from the workspace scan")
	var demo_box := GuitkxWorkspace.lookup("DemoBox")
	_ok(str(demo_box.get("path", "")).contains("examples/demos"),
		"DemoBox resolves to the real demo, not a fixture (got %s)" % str(demo_box.get("path", "")))

	# Severity constant stays pinned to the compiler's.
	_ok(Scan.SEVERITY_ERROR == RuitkGuitkxDiag.ERROR, "scan severity matches RuitkGuitkxDiag.ERROR")

	# The user's exact shape: typo'd open + original close -> parse error masks compiler 0105;
	# the scan still flags the typo with a did-you-mean.
	var src := "component T() {\n\treturn (\n\t\t<DemoaBox>\n\t\t\t<Label text=\"x\" />\n\t\t</DemoBox>\n\t)\n}\n"
	var recs: Array = Scan.unknown_tags(src, ["DemoBox"])
	_ok(recs.size() == 1, "scan flags exactly the typo'd tag (got %d)" % recs.size())
	if recs.size() == 1:
		var r: Dictionary = recs[0]
		_ok(str(r.get("code")) == "GUITKX0105", "scan record carries 0105")
		_ok(str(r.get("message")).contains("did you mean <DemoBox>"), "did-you-mean names the real component")
		_ok(int(r.get("offset")) == src.find("DemoaBox"), "scan anchors at the tag name")

	# No false positives: known tags, hosts, module-locals, comparisons, strings.
	_ok(Scan.unknown_tags("component T() {\n\treturn (\n\t\t<Label text=\"a\" />\n\t)\n}", []).is_empty(),
		"host tags pass")
	_ok(Scan.unknown_tags("component Card() {\n\treturn (\n\t\t<Card2 />\n\t)\n}\ncomponent Card2() {\n\treturn (\n\t\t<Label />\n\t)\n}", []).is_empty(),
		"module-local components pass without any known set")
	_ok(Scan.unknown_tags("component T() {\n\tvar x = a <level\n\treturn (\n\t\t<Label />\n\t)\n}", []).is_empty(),
		"comparisons are not tags")
	_ok(Scan.unknown_tags("component T() {\n\tvar s = \"<FakeTag>\"\n\treturn (\n\t\t<Label />\n\t)\n}", []).is_empty(),
		"tags inside strings are skipped")
	var low: Array = Scan.unknown_tags("component T() {\n\treturn (\n\t\t<vboxx />\n\t)\n}", [])
	_ok(low.size() == 1 and str((low[0] as Dictionary).get("message")).contains("vboxx"),
		"unknown lowercase factory flagged")

	# End-to-end: the view merges scan records into the gutter (parse error present).
	var fa := FileAccess.open(TMP_PATH, FileAccess.WRITE)
	fa.store_string(src)
	fa.close()
	var v: Control = ViewScript.new()
	v.open_path(TMP_PATH)
	var line := 2  # <DemoaBox> line
	var meta: Variant = v._code_edit.get_line_gutter_metadata(line, v._code_edit.diag_gutter)
	_ok(meta is Dictionary and str((meta as Dictionary).get("code", "")) == "GUITKX0105",
		"view surfaces the scan-tier 0105 in the gutter despite the parse error")

	# The diagnosed line's records reach the widget for hover composition (G10/G19).
	var hover_md: String = v._code_edit.compose_hover("", line)
	_ok(hover_md.contains("GUITKX0105") and hover_md.contains("did you mean"),
		"hover on the diagnosed line carries the code and the did-you-mean")
	v.free()

# M2 wave 1 — hook cards + markdown->bbcode rendering + diag/symbol hover composition.
func _test_rich_hover() -> void:
	# Hook cards answer in setup lines (the analyzer tier used to return nothing).
	var src := "component T() {\n\tvar s = useState(0)\n\treturn (\n\t\t<Label />\n\t)\n}"
	var md := GuitkxHover.for_caret(src, src.find("useState") + 2)
	_ok(md.contains("**useState**") and md.contains("Reactive state"), "useState hover card")
	_ok(GuitkxHover.HOOKS.size() == 23, "all 23 hook cards ported (got %d)" % GuitkxHover.HOOKS.size())

	# Markdown subset -> BBCode, with [ escaped so user text can't inject tags.
	_ok(GuitkxHover.md_to_bbcode("**b** and `c`") == "[b]b[/b] and [code]c[/code]", "bold+code convert")
	_ok(GuitkxHover.md_to_bbcode("a [tag] b") == "a [lb]tag] b", "literal [ escaped")

	# Symbol + line-diagnostic composition on the widget.
	var ce: CodeEdit = CodeEditScript.new()
	ce.set_line_diagnostics({ 3: [{ "severity": "error", "code": "GUITKX0105", "message": "unknown element <X>" }] })
	var composed: String = ce.compose_hover("**`<Label>`** — host element", 3)
	_ok(composed.contains("ERROR") and composed.contains("GUITKX0105") and composed.contains("host element"),
		"diagnostic prepends to the symbol card")
	_ok(ce.compose_hover("just symbol", 0) == "just symbol", "clean line passes the card through")
	ce.free()

	# The resource loader must NEVER return an error for an unreadable file — ResourceLoader
	# caches failures, permanently red-✕ing the file in the dock (field capture).
	const Loader := preload("res://addons/reactive_ui_toolkit_editor/resources/guitkx_resource_loader.gd")
	var ldr := Loader.new()
	var out: Variant = ldr._load("res://tests/__no_such_file_ever.guitkx", "", false, 0)
	_ok(out is Resource, "loader returns an (empty) resource for an unreadable path, never an error")

	# The loader MUST be a global class: the engine drops all custom format loaders on every
	# script-reload cycle and re-adds only class_name'd ones — the old manually-registered
	# instance silently died on the first reload after boot (red-✕/invisible-files field saga).
	var is_global := false
	for gc in ProjectSettings.get_global_class_list():
		if str(gc.get("class", "")) == "GuitkxResourceLoader":
			is_global = true
	_ok(is_global, "GuitkxResourceLoader is a global class (engine-owned, reload-surviving registration)")
	_ok(ResourceLoader.exists(TMP_PATH), "engine-registered loader serves ResourceLoader.exists for .guitkx")

	# Rapid-rename hygiene (field capture: "after 1-2 renames it breaks — the .gd stays behind"):
	# moving a .guitkx must synchronously remove the OLD name's generated outputs, or stacked
	# renames leave multiple .gd files declaring the same class_name.
	const PluginScript := preload("res://addons/reactive_ui_toolkit_editor/plugin.gd")
	var mv_src := "res://tests/__editor_test_move.guitkx"
	var fmv := FileAccess.open(mv_src, FileAccess.WRITE)
	fmv.store_string("component EditorTmpMove() {\n\treturn (\n\t\t<Label text=\"m\" />\n\t)\n}\n")
	fmv.close()
	RuitkGuitkxCodegen.compile_file(mv_src)
	var mv_gd: String = RuitkGuitkxCodegen.gd_path_for(mv_src)
	_ok(FileAccess.file_exists(mv_gd), "move fixture compiled its .gd")
	var mv_dst := "res://tests/__editor_test_moved.guitkx"
	DirAccess.rename_absolute(ProjectSettings.globalize_path(mv_src), ProjectSettings.globalize_path(mv_dst))
	PluginScript.cleanup_moved_guitkx(mv_src)
	_ok(not FileAccess.file_exists(mv_gd), "old-name .gd removed synchronously on move")
	_ok(not FileAccess.file_exists(mv_src + ".diags.json"), "old-name sidecar removed on move")
	# M4.3 (ES-modules, file=module): renames are MORE load-bearing with eager value exports --
	# a renamed VALUE file must drop its outputs the same way (no ghost class_name survives),
	# and an importer still holding the old specifier gets GUITKX2300 on its next compile.
	var val_src := "res://tests/__editor_test_val.guitkx"
	var fval := FileAccess.open(val_src, FileAccess.WRITE)
	fval.store_string("export tmp_val_w: int = 7
")
	fval.close()
	RuitkGuitkxCodegen.compile_file(val_src)
	var val_gd: String = RuitkGuitkxCodegen.gd_path_for(val_src)
	_ok(FileAccess.file_exists(val_gd), "value-export fixture compiled its .gd")
	var val_dst := "res://tests/__editor_test_val2.guitkx"
	DirAccess.rename_absolute(ProjectSettings.globalize_path(val_src), ProjectSettings.globalize_path(val_dst))
	PluginScript.cleanup_moved_guitkx(val_src)
	_ok(not FileAccess.file_exists(val_gd), "renamed value file drops its old .gd (no ghost class)")
	var val_imp := "res://tests/__editor_test_valimp.guitkx"
	var fvi := FileAccess.open(val_imp, FileAccess.WRITE)
	fvi.store_string("import { tmp_val_w } from \"./__editor_test_val\"
export ValImp() -> RuitkVNode {
	return ( <Label text={str(tmp_val_w)}/> )
}
")
	fvi.close()
	var vres: Dictionary = RuitkGuitkxCodegen.compile_file(val_imp)
	var v2300 := false
	for vd in (vres.get("diagnostics", []) as Array):
		if vd is Dictionary and str((vd as Dictionary).get("code", "")) == "GUITKX2300":
			v2300 = true
	_ok(v2300, "importer of the OLD specifier gets GUITKX2300, not a silent stale preload")
	for vjunk in [val_dst, val_dst + ".diags.json", RuitkGuitkxCodegen.gd_path_for(val_dst), val_imp, val_imp + ".diags.json", RuitkGuitkxCodegen.gd_path_for(val_imp), val_src + ".diags.json", val_gd + ".uid"]:
		if FileAccess.file_exists(str(vjunk)):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(str(vjunk)))

	# Hand-written .gd safety: a non-generated file under the old name must survive.
	var hw_src := "res://tests/__editor_test_hw.guitkx"
	var hw_gd := "res://tests/__editor_test_hw.gd"
	var fhw := FileAccess.open(hw_gd, FileAccess.WRITE)
	fhw.store_string("class_name EditorTmpHw\nextends RefCounted\n")
	fhw.close()
	PluginScript.cleanup_moved_guitkx(hw_src)
	_ok(FileAccess.file_exists(hw_gd), "hand-written .gd under the old name is untouchable")
	for junk in [mv_dst, mv_dst + ".diags.json", RuitkGuitkxCodegen.gd_path_for(mv_dst), hw_gd, mv_gd + ".uid", hw_gd + ".uid"]:
		if FileAccess.file_exists(junk):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(str(junk)))

# M2 wave 1b / G26 — guitkx.config.json discovery + end-to-end formatter plumbing.
func _test_formatter_config() -> void:
	const Config := preload("res://addons/reactive_ui_toolkit_editor/lsp/guitkx_config.gd")
	var dir := "res://tests/__cfg_tmp"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir + "/nested"))
	var w := func(p: String, s: String):
		var f := FileAccess.open(p, FileAccess.WRITE)
		f.store_string(s)
		f.close()
	w.call(dir + "/guitkx.config.json", '{"formatter": {"printWidth": 40, "insertSpaceBeforeSelfClose": false, "bogusKey": 1}}')

	var opts: Dictionary = Config.formatter_opts_for(dir + "/nested/x.guitkx")
	_ok(int(opts.get("printWidth", -1)) == 40, "nearest config found via parent walk")
	_ok(opts.get("insertSpaceBeforeSelfClose") == false, "bool option passes through")
	_ok(not opts.has("bogusKey"), "unknown keys filtered")
	_ok(Config.formatter_opts_for("res://tests/x.guitkx").is_empty(), "no config -> {} (formatter defaults)")

	# Malformed config: skipped without exploding.
	w.call(dir + "/nested/guitkx.config.json", "{not json")
	_ok(Config.formatter_opts_for(dir + "/nested/x.guitkx").is_empty(), "malformed nearest config -> {}")

	# End-to-end: the view formats with the discovered options (insertSpaceBeforeSelfClose=false).
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dir + "/nested/guitkx.config.json"))
	var v: Control = ViewScript.new()
	var src := "component CfgT() {\n  return (\n    <Label text=\"a\" />\n  )\n}\n"
	w.call(dir + "/cfg_t.guitkx", src)
	v.open_path(dir + "/cfg_t.guitkx")
	var out: String = v._formatted(src)
	_ok(out.contains("<Label text=\"a\"/>"), "view formatting honors insertSpaceBeforeSelfClose=false")
	v.free()

	for p in [dir + "/cfg_t.guitkx", dir + "/guitkx.config.json"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dir + "/nested"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dir))

# M2 wave 1b / D3+D5 — sidecar overlay (2106/2107 reach the editor) + hint rendering tier.
func _test_sidecar_overlay() -> void:
	# @class_name is kept here to pin the override grammar (GUITKX0103 is retired since 0.10.2,
	# so it's no longer needed to silence anything) — this test owns lines 0 and the tag line
	# exclusively.
	var src := "@class_name ScT\n\ncomponent ScT() {\n\treturn (\n\t\t<ScOther />\n\t)\n}\n"
	var fa := FileAccess.open(TMP_PATH, FileAccess.WRITE)
	fa.store_string(src)
	fa.close()
	# Plant a sweep-style sidecar with a 2107 anchored at the tag (only the sweep can produce it).
	var at := src.find("ScOther")
	RuitkGuitkxCodegen.write_diags_sidecar(TMP_PATH, src, [{
		"code": "GUITKX2107", "severity": RuitkGuitkxDiag.ERROR,
		"message": "component <ScOther> resolves to res://gone.gd, which no longer exists",
		"offset": at, "length": 7,
	}], { "ScOther": "res://gone.gd" })

	var v: Control = ViewScript.new()
	v.open_path(TMP_PATH)
	var line := int(RuitkGuitkxDiag.line_col(src, at).get("line", -1))
	var meta: Variant = v._code_edit.get_line_gutter_metadata(line, v._code_edit.diag_gutter)
	_ok(meta is Dictionary and str((meta as Dictionary).get("code", "")) == "GUITKX2107",
		"hash-matched sidecar 2107 anchors at the reference line")

	# Diverge the buffer: the anchored row must collapse into a line-0 hint naming the code.
	v._code_edit.text = src + "\n# edited"
	v._refresh_diagnostics()
	var l0: Variant = v._code_edit.get_line_gutter_metadata(0, v._code_edit.diag_gutter)
	_ok(l0 is Dictionary and str((l0 as Dictionary).get("code", "")).contains("GUITKX2107")
		and str((l0 as Dictionary).get("severity", "")) == "hint",
		"diverged buffer collapses sidecar-only codes into a line-0 hint")
	_ok(v._code_edit.get_line_gutter_icon(0, v._code_edit.diag_gutter) == null,
		"D5: hints carry no gutter icon")
	_ok(v._code_edit.get_line_background_color(0).a == 0.0, "D5: hints carry no line tint")
	v.free()

	DirAccess.remove_absolute(ProjectSettings.globalize_path(str(RuitkGuitkxCodegen.diags_path_for(TMP_PATH))))

# M2 wave 2 — completion contexts (G5/G6/G7/G8/G28) + the comment toggle (E12).
func _test_wave2_completion() -> void:
	var RET := "component X() {\n\treturn (\n\t\t"
	var END := "\n\t)\n}\n"

	# G5: bool property value -> true/false.
	var s1 := RET + "<Label visible=\"" + END
	var items: Array = GuitkxCompletion.for_caret(s1, (RET + "<Label visible=\"").length())
	var names := items.map(func(it): return str((it as Dictionary).get("insert", "")))
	_ok(names.has("true") and names.has("false"), "bool attr value offers true/false")

	# G5: enum property value -> hint names (Label.horizontal_alignment is an enum).
	var s2 := RET + "<Label horizontal_alignment=\"" + END
	items = GuitkxCompletion.for_caret(s2, (RET + "<Label horizontal_alignment=\"").length())
	_ok(items.size() >= 2, "enum attr value offers the hint names (got %d)" % items.size())

	# G6: style-dict keys inside style={ {"...
	var s3 := RET + "<Label style={ {\"" + END
	items = GuitkxCompletion.for_caret(s3, (RET + "<Label style={ {\"").length())
	names = items.map(func(it): return str((it as Dictionary).get("insert", "")))
	_ok(names.has("bg_color") and names.has("font_color") and names.has("separation"),
		"style dict offers the RuitkStyle keys")
	_ok(GuitkxSchema.style_keys().size() == 45, "schema carries all 45 style keys")

	# G7: builtin members after `Color.` in embedded code.
	var s4 := "component X() {\n\tvar c = Color." + "\n\treturn (\n\t\t<Label />" + END
	items = GuitkxCompletion.for_caret(s4, ("component X() {\n\tvar c = Color.").length())
	names = items.map(func(it): return str((it as Dictionary).get("insert", "")))
	_ok(names.has("WHITE") and names.has("CRIMSON"), "Color. offers builtin constants")

	# G8: hook names while typing `use` on a setup line.
	var s5 := "component X() {\n\tvar s = use" + "\n\treturn (\n\t\t<Label />" + END
	items = GuitkxCompletion.for_caret(s5, ("component X() {\n\tvar s = use").length())
	names = items.map(func(it): return str((it as Dictionary).get("insert", "")))
	_ok(names.has("useState") and names.has("useEffect"), "use… offers the hook names")

	# G28: the native on_<signal> spelling joins the React aliases (displays); G20: the inserts
	# carry `=` + an empty value pair the editor steps the caret into.
	var s6 := RET + "<Button " + END
	items = GuitkxCompletion.for_caret(s6, (RET + "<Button ").length())
	names = items.map(func(it): return str((it as Dictionary).get("display", "")))
	_ok(names.has("onPressed") and names.has("on_pressed"), "both event spellings offered")
	_ok(names.has("on_gui_input"), "verbatim escape hatch covers every signal")
	var inserts: Array = items.map(func(it): return str((it as Dictionary).get("insert", "")))
	_ok(inserts.has("onPressed={}") and inserts.has("text=\"\""), "attr inserts are snippet-shaped (G20)")

	# Context: the attr name resolves through braces (style value) and plain quotes.
	var c1 := GuitkxContext.classify(s3, (RET + "<Label style={ {\"").length())
	_ok(str(c1.get("attr", "")) == "style", "value context names its attribute through { {")
	var c2 := GuitkxContext.classify(s1, (RET + "<Label visible=\"").length())
	_ok(str(c2.get("attr", "")) == "visible", "value context names its attribute (quoted)")

# E12 — Ctrl+/ comment toggle: comment, uncomment, mixed selection, single undo step.
func _test_comment_toggle() -> void:
	var ce: CodeEdit = CodeEditScript.new()
	ce.text = "\tline_a\n\tline_b\n\n\tline_c"
	ce.clear_undo_history()
	ce.select(0, 0, 3, 7)
	ce.toggle_comment()
	_ok(ce.get_line(0) == "\t# line_a" and ce.get_line(1) == "\t# line_b" and ce.get_line(3) == "\t# line_c",
		"toggle comments every non-empty selected line at its indent")
	_ok(ce.get_line(2) == "", "blank lines untouched")
	ce.toggle_comment()
	_ok(ce.get_line(0) == "\tline_a" and ce.get_line(3) == "\tline_c", "second toggle uncomments")
	# Mixed state: one commented line -> everything COMMENTS (VS Code semantics).
	ce.set_line(0, "\t# line_a")
	ce.select(0, 0, 1, 7)
	ce.toggle_comment()
	_ok(ce.get_line(1) == "\t# line_b", "mixed selection comments the uncommented lines")
	# Undo granularity: one toggle = one undo.
	ce.text = "x"
	ce.clear_undo_history()
	ce.set_caret_line(0)
	ce.toggle_comment()
	_ok(ce.get_line(0) == "# x", "caret-line toggle without selection")
	ce.undo()
	_ok(ce.get_line(0) == "x", "toggle is a single undo step")
	ce.free()

# M2 wave 3 — references (G2), rename (G3), hook goto-def (G27).
func _test_refs_and_rename() -> void:
	const Refs := preload("res://addons/reactive_ui_toolkit_editor/lsp/guitkx_refs.gd")
	# Two fixture files: a component + a consumer referencing it twice (+ a comparison decoy).
	var a_path := "res://tests/__refs_a.guitkx"
	var b_path := "res://tests/__refs_b.guitkx"
	var a_src := "@class_name RefsWidget\n\ncomponent RefsWidget() {\n\treturn (\n\t\t<Label text=\"w\" />\n\t)\n}\n"
	var b_src := "component RefsHost() {\n\tvar x = 1\n\tvar y = x <RefsWidgetFake_not_a_tag\n\treturn (\n\t\t<VBoxContainer>\n\t\t\t<RefsWidget />\n\t\t\t<RefsWidget key=\"2\" />\n\t\t</VBoxContainer>\n\t)\n}\n"
	for pair in [[a_path, a_src], [b_path, b_src]]:
		var f := FileAccess.open(pair[0], FileAccess.WRITE)
		f.store_string(pair[1])
		f.close()
	GuitkxWorkspace.rescan()

	# In-file scan: decl + @class_name in A; two opens in B; the comparison is not a reference.
	var ra: Array = Refs.tag_refs_in(a_src, "RefsWidget")
	var kinds := ra.map(func(r): return str((r as Dictionary).get("kind", "")))
	_ok(kinds.has("decl") and kinds.has("class_name"), "declaration + @class_name tokens found")
	var rb: Array = Refs.tag_refs_in(b_src, "RefsWidget")
	_ok(rb.size() == 2, "two tag references in the consumer (comparison decoy skipped), got %d" % rb.size())

	# Project-wide, with previews.
	var proj: Array = Refs.project_refs("RefsWidget")
	_ok(proj.size() == 4, "project refs = decl + class_name + 2 usages (got %d)" % proj.size())
	_ok(str((proj[0] as Dictionary).get("preview", "")) != "", "reference rows carry a line preview")

	# Rename gates.
	_ok(not bool(Refs.rename_edits("RefsWidget", "Label").get("ok")), "host-tag collision refused")
	_ok(not bool(Refs.rename_edits("RefsWidget", "RefsHost").get("ok")), "existing-component collision refused")
	_ok(not bool(Refs.rename_edits("RefsWidget", "lower").get("ok")), "non-PascalCase refused")
	_ok(not bool(Refs.rename_edits("NoSuchThing", "Xyz").get("ok")), "unknown source refused")
	_ok(not bool(Refs.rename_edits("RefsWidget", "DemoBox").get("ok")), "global-class collision refused")

	# Apply: splice edits into both files (text-level check of the plan).
	var plan: Dictionary = Refs.rename_edits("RefsWidget", "RefsGadget")
	_ok(bool(plan.get("ok")), "valid rename plan accepted")
	var edits: Dictionary = plan.get("edits", {})
	var new_a: String = Refs.apply_edits_to_text(a_src, edits.get(a_path, []), "RefsGadget")
	var new_b: String = Refs.apply_edits_to_text(b_src, edits.get(b_path, []), "RefsGadget")
	_ok(new_a.contains("@class_name RefsGadget") and new_a.contains("component RefsGadget"),
		"declaration + override renamed")
	_ok(new_b.count("<RefsGadget") == 2 and not new_b.contains("<RefsWidget ")
		and not new_b.contains("<RefsWidget/"), "usages renamed (decoy substring excluded)")
	_ok(new_b.contains("RefsWidgetFake_not_a_tag"), "comparison decoy untouched")

	# ES-modules rename depth (E-07/E-08/E-09): import-clause REMOTE halves + export markers
	# rewrite in lockstep; a rename-import LOCAL alias and its uses stay untouched.
	var c_path := "res://tests/__refs_c.guitkx"
	var d_path := "res://tests/__refs_d.guitkx"
	var c_src := "export RefsChip() -> RuitkVNode {
	return ( <Label /> )
}
export { RefsChip }
export default RefsChip
"
	var d_src := "import { RefsChip as RBadge } from \"./__refs_c\"
export RefsUser() -> RuitkVNode {
	return ( <RBadge /> )
}
"
	for pair2 in [[c_path, c_src], [d_path, d_src]]:
		var f2 := FileAccess.open(pair2[0], FileAccess.WRITE)
		f2.store_string(pair2[1])
		f2.close()
	GuitkxWorkspace.rescan()
	var plan2: Dictionary = Refs.rename_edits("RefsChip", "RefsGem")
	_ok(bool(plan2.get("ok")), "rename plan through an as-import accepted")
	var edits2: Dictionary = plan2.get("edits", {})
	var new_c: String = Refs.apply_edits_to_text(c_src, edits2.get(c_path, []), "RefsGem")
	var new_d: String = Refs.apply_edits_to_text(d_src, edits2.get(d_path, []), "RefsGem")
	_ok(new_c.contains("export RefsGem() -> RuitkVNode") and new_c.contains("export { RefsGem }") and new_c.contains("export default RefsGem"), "decl + list marker + default marker renamed (got %s)" % new_c)
	_ok(new_d.contains("import { RefsGem as RBadge }"), "clause REMOTE half renamed (got %s)" % new_d)
	_ok(new_d.contains("<RBadge />"), "the local alias and its tag use stay untouched")
	for p2 in [c_path, d_path]:
		if FileAccess.file_exists(str(p2)):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(str(p2)))
	GuitkxWorkspace.rescan()

	# G27: hooks resolve to core/hooks.gd through the widget's lookup path.
	var ce: CodeEdit = CodeEditScript.new()
	var got: Array = []
	ce.definition_requested.connect(func(p: String, o: int):
		got.append(p)
		got.append(o))
	ce._on_symbol_lookup("useState", 0, 0)
	_ok(got.size() == 2 and str(got[0]).ends_with("core/hooks.gd") and int(got[1]) > 0,
		"useState jumps into core/hooks.gd")
	ce.free()

	for p in [a_path, b_path]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(str(p)))
	GuitkxWorkspace.rescan()

# M2 wave 4 — multi-file editors (G16), session state (G17), zoom (E11), wrap (E15).
func _test_multifile() -> void:
	var a := "res://tests/__mf_a.guitkx"
	var b := "res://tests/__mf_b.guitkx"
	for pair in [[a, "component MfA() {\n\treturn (\n\t\t<Label text=\"a\" />\n\t)\n}\n"],
			[b, "component MfB() {\n\treturn (\n\t\t<Label text=\"b\" />\n\t)\n}\n"]]:
		var f := FileAccess.open(pair[0], FileAccess.WRITE)
		f.store_string(pair[1])
		f.close()

	var v: Control = ViewScript.new()
	v.open_path(a)
	_ok(v.current_path() == a, "first file becomes current")
	_ok(not v._editors.has(""), "pristine scratch closes once a real file opens")

	# Edit A, then open B: switching preserves A's edits, dirty flag, and undo history.
	v._code_edit.insert_text_at_caret("# edit-a\n")
	v._on_editor_text_changed(v._code_edit)  # text_changed is deferred; no frames run headless
	_ok(v.is_dirty(), "A dirty after edit")
	v.open_path(b)
	_ok(v.current_path() == b, "switch to B")
	_ok(not v.is_dirty(), "B is clean (dirty state is per-file)")
	var ed_a: CodeEdit = v._editors[a]
	_ok(ed_a.dirty and ed_a.text.contains("# edit-a"), "A keeps its edits in the background")
	_ok(ed_a.has_undo(), "A keeps its undo history across the switch")

	_ok(v.open_paths().size() == 2, "open_paths lists both files")
	_ok(v.dirty_files() == [a], "dirty_files names exactly the edited file")

	# Background rename (L1 multi-file): retarget by OLD path, not just the current file.
	var a2 := "res://tests/__mf_a2.guitkx"
	v.retarget_path(a2, a)
	_ok(not v._editors.has(a) and v._editors.has(a2), "background retarget moves the editor key")
	_ok(v.current_path() == b, "current file untouched by background retarget")
	v.retarget_path(a, a2)

	# Switching back: same editor object, caret/undo intact; label follows.
	v.open_path(a)
	_ok(v._code_edit == ed_a, "switching back reuses the same editor instance")
	_ok(v._file_label.text.ends_with("*"), "label shows A's dirty state again")

	# Session state round-trip.
	var state: Dictionary = v.session_state()
	_ok((state.get("files", []) as Array).size() == 2 and str(state.get("current", "")) == a,
		"session snapshot carries files + current")

	# E15 wrap toggle applies to every editor.
	v._on_wrap_toggled(true)
	_ok(ed_a.wrap_mode == TextEdit.LINE_WRAPPING_BOUNDARY
		and (v._editors[b] as CodeEdit).wrap_mode == TextEdit.LINE_WRAPPING_BOUNDARY,
		"wrap toggle hits all editors")
	v._on_wrap_toggled(false)

	# E11 zoom: static-shared, applied per editor.
	(v._code_edit as CodeEdit).set_zoom(20)
	_ok(v._code_edit.get_theme_font_size("font_size") == 20, "zoom overrides the font size")
	(v._code_edit as CodeEdit).set_zoom(0)
	CodeEditScript.zoom_font_size = 0

	# close_file: clean B closes instantly; closing the last file leaves a scratch.
	v._code_edit.dirty = false
	ed_a.dirty = false
	v.close_file(b)
	_ok(not v._editors.has(b), "clean file closes")
	v.close_file(a)
	_ok(v._editors.has("") and v.current_path() == "", "last close falls back to a scratch buffer")

	v.free()
	for p in [a, b]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(str(p)))
	GuitkxWorkspace.rescan()

# W5/G12 — document outline: the compiler's declaration scan, offsets anchored at the NAME.
# ES-modules leg: the fixture uses REAL syntax (the outline consumes RuitkGuitkx.analyzed_decls,
# which parses actual declarations, not a keyword regex) and covers wrapper + plain forms.
func _test_outline() -> void:
	const Outline := preload("res://addons/reactive_ui_toolkit_editor/lsp/guitkx_outline.gd")
	var src := "hook useThing(x) {\n\treturn x\n}\nmodule Helpers {\n\thook one() {\n\t\treturn 1\n\t}\n\thook two() {\n\t\treturn 2\n\t}\n}\n"
	var entries: Array = Outline.outline_of(src)
	_ok(entries.size() == 4, "outline lists hook + module + 2 member funcs (got %d)" % entries.size())
	var names: Array = entries.map(func(e): return str((e as Dictionary).get("name", "")))
	_ok(names == ["useThing", "Helpers", "one", "two"], "outline sorted by offset (got %s)" % str(names))
	var kinds: Array = entries.map(func(e): return str((e as Dictionary).get("kind", "")))
	_ok(kinds == ["hook", "module", "func", "func"], "outline kinds classified (got %s)" % str(kinds))
	var anchored := true
	for e in entries:
		var ed := e as Dictionary
		if src.substr(int(ed["offset"]), str(ed["name"]).length()) != str(ed["name"]):
			anchored = false
	_ok(anchored, "every outline offset lands exactly on its name")

	# A single-component file keeps its internal funcs OFF the tree (no module — signal over noise).
	var comp := "component Foo() {\n\tfunc local():\n\t\tpass\n\treturn (\n\t\t<Label />\n\t)\n}\n"
	var centries: Array = Outline.outline_of(comp)
	_ok(centries.size() == 1, "component file outlines only the component")
	_ok(str((centries[0] as Dictionary).get("name", "")) == "Foo", "component name listed")
	_ok(Outline.outline_of("").is_empty(), "empty text -> empty outline")
	_ok(Outline.outline_of("# just a comment\n").is_empty(), "no declarations -> empty outline")
	# ES-modules: plain declarations outline with their signature-classified kinds + export flags.
	var plain := "export w := 1\nexport fmt(x: int) -> String {\n\treturn str(x)\n}\nuse_t() -> int {\n\treturn 1\n}\nexport Foo() -> RuitkVNode {\n\treturn (\n\t\t<Label />\n\t)\n}\n"
	var pentries: Array = Outline.outline_of(plain)
	var pkinds: Array = pentries.map(func(e): return str((e as Dictionary).get("kind", "")))
	_ok(pkinds == ["value", "util", "hook", "component"], "plain decls outline with E-01 kinds (got %s)" % str(pkinds))
	var pexports: Array = pentries.map(func(e): return bool((e as Dictionary).get("export", false)))
	_ok(pexports == [true, true, false, true], "outline carries export badges (got %s)" % str(pexports))

# W5/G24 — find-bar replace: step replaces the selected match, All is one undo step and
# terminates even when the replacement contains the query.
# ES-modules audit regressions: (a) a PLAIN-declared buffer-local sibling component is a legal
# tag in the live unknown-tag scan (the wrapper-only _local_decls regex false-flagged it);
# (b) namespace-member completion after `X.`; (c) kind-aware hover badges.
func _test_es_editor_intelligence() -> void:
	const ScanDiags := preload("res://addons/reactive_ui_toolkit_editor/lsp/guitkx_scan_diags.gd")
	const Completion := preload("res://addons/reactive_ui_toolkit_editor/lsp/guitkx_completion.gd")
	const Hover := preload("res://addons/reactive_ui_toolkit_editor/lsp/guitkx_hover.gd")
	# (a) plain sibling used as a tag in the SAME buffer -- no GUITKX0105.
	var buf := "Chip2() -> RuitkVNode {
	return ( <Label /> )
}
export Shell2() -> RuitkVNode {
	return ( <Chip2 /> )
}
"
	var diags: Array = ScanDiags.unknown_tags(buf, [])
	_ok(diags.is_empty(), "plain buffer-local sibling tag is known to the live scan (got %s)" % str(diags))
	# (b) `Hud.` completion offers the target file's exported decls, kind-tagged.
	var hud_p := "res://tests/__es_ed_hud.guitkx"
	var fh := FileAccess.open(hud_p, FileAccess.WRITE)
	fh.store_string("export panel_w: int = 320
export fmt(x: int) -> String {
	return str(x)
}
priv_v := 1
")
	fh.close()
	var app_p := "res://tests/__es_ed_app.guitkx"
	var app_src := "import * as Hud from \"./__es_ed_hud\"
export A2() -> RuitkVNode {
	return ( <Label text={str(Hud.)}/> )
}
"
	var caret := app_src.find("Hud.") + 4
	var items: Array = Completion.for_caret(app_src, caret, app_p)
	var names: Array = items.map(func(it): return str((it as Dictionary).get("insert", "")))
	_ok(names.has("panel_w") and names.has("fmt"), "ns-member completion offers exported decls (got %s)" % str(names))
	_ok(not names.has("priv_v"), "file-private decls are NOT offered")
	# (c) kind-aware hover badge for an indexed component incl. export/default.
	var chip_p := "res://tests/__es_ed_chip.guitkx"
	var fc2 := FileAccess.open(chip_p, FileAccess.WRITE)
	fc2.store_string("export EsChipX() -> RuitkVNode {
	return ( <Label /> )
}
export default EsChipX
")
	fc2.close()
	GuitkxWorkspace.rescan()
	var h := str(Hover._tag_hover("EsChipX"))
	_ok(h.contains("user component") and h.contains("exported") and h.contains("default export"), "hover carries kind + export + default badges (got %s)" % h)
	# (d) 0.11.1 field wave: Ctrl+Space inside import braces offers the target's exported names --
	# for the bare prefix AND the combined `import Def, { | }` prefix (which used to return
	# nothing: the context check required a bare `import` before the `{`).
	var fh2 := FileAccess.open(hud_p, FileAccess.WRITE)
	fh2.store_string("export panel_w: int = 320
export fmt(x: int) -> String {
	return str(x)
}
priv_v := 1
export default fmt
")
	fh2.close()
	var bare_src := "import {  } from \"./__es_ed_hud\"\n"
	var bare_items: Array = Completion.for_caret(bare_src, bare_src.find("{") + 1, app_p)
	var bare_names: Array = bare_items.map(func(it): return str((it as Dictionary).get("insert", "")))
	_ok(bare_names.has("panel_w") and bare_names.has("fmt"), "brace completion offers exported decls (got %s)" % str(bare_names))
	_ok(not bare_names.has("priv_v"), "brace completion never offers file-private decls")
	var comb_src := "import fetch_x, {  } from \"./__es_ed_hud\"\n"
	var comb_items: Array = Completion.for_caret(comb_src, comb_src.find("{") + 1, app_p)
	var comb_names: Array = comb_items.map(func(it): return str((it as Dictionary).get("insert", "")))
	_ok(comb_names.has("panel_w"), "combined-prefix brace completion still offers exports (got %s)" % str(comb_names))
	_ok(not comb_names.has("fmt"), "the default-bound export is excluded under a combined prefix")
	var listed_src := "import { panel_w,  } from \"./__es_ed_hud\"\n"
	var listed_items: Array = Completion.for_caret(listed_src, listed_src.find(",") + 2, app_p)
	var listed_names: Array = listed_items.map(func(it): return str((it as Dictionary).get("insert", "")))
	_ok(not listed_names.has("panel_w") and listed_names.has("fmt"), "already-listed names are excluded (got %s)" % str(listed_names))
	for pth in [hud_p, app_p, chip_p]:
		if FileAccess.file_exists(str(pth)):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(str(pth)))
	GuitkxWorkspace.rescan()

func _test_replace() -> void:
	const FindBar := preload("res://addons/reactive_ui_toolkit_editor/editor/guitkx_find_bar.gd")
	var ce: CodeEdit = CodeEditScript.new()
	ce.text = "alpha beta\ngamma alpha\nALPHA end"
	var bar: HBoxContainer = FindBar.new()
	bar.attach(ce)
	bar._query.text = "alpha"  # set_text emits no text_changed; drive the refresh directly
	bar._update_search()       # selects the first match at/after the caret: (0,0)-(0,5)
	bar._replace.text = "X"
	bar.replace_step()
	_ok(ce.get_line(0) == "X beta", "replace_step rewrites the selected match")
	_ok(ce.get_selected_text().to_lower() == "alpha", "replace_step advances to the next match")

	bar._replace.text = "Y"
	bar.replace_all()
	_ok(not ce.text.to_lower().contains("alpha"), "replace_all clears every remaining match")
	_ok(ce.get_line(1) == "gamma Y" and ce.get_line(2) == "Y end",
		"replace_all is case-insensitive by default")
	_ok(bar._count.text.begins_with("2 replaced"), "replace_all reports the count")
	ce.undo()
	_ok(ce.get_line(1) == "gamma alpha" and ce.get_line(2) == "ALPHA end",
		"replace_all undoes as ONE step")
	_ok(ce.get_line(0) == "X beta", "undo stops at the replace_all boundary")

	# Growth guard: replacing "a" with "aa" must terminate (search resumes AFTER the insertion).
	var ce2: CodeEdit = CodeEditScript.new()
	ce2.text = "b a b a"
	var bar2: HBoxContainer = FindBar.new()
	bar2.attach(ce2)
	bar2._query.text = "a"
	bar2._case.button_pressed = true
	bar2._replace.text = "aa"
	bar2.replace_all()
	_ok(ce2.text == "b aa b aa", "replacement containing the query terminates")
	bar2.free()
	ce2.free()
	bar.free()
	ce.free()

# W5/E18-replacement — project-wide .guitkx search over the workspace index.
func _test_project_search() -> void:
	const SearchPanel := preload("res://addons/reactive_ui_toolkit_editor/editor/guitkx_search_panel.gd")
	var a := "res://tests/__w5_a.guitkx"
	var b := "res://tests/__w5_b.guitkx"
	for pair in [[a, "component W5A() {\n\treturn (\n\t\t<Label text=\"needle needle\" />\n\t)\n}\n"],
			[b, "component W5B() {\n\treturn (\n\t\t<Label text=\"needle\" />\n\t)\n}\n"]]:
		var f := FileAccess.open(pair[0], FileAccess.WRITE)
		f.store_string(pair[1])
		f.close()
	GuitkxWorkspace.rescan()

	var mine := func(records: Array) -> Array:
		return records.filter(func(r): return str((r as Dictionary).get("path", "")) in [a, b])
	var hits: Array = mine.call(SearchPanel.search("needle", false))
	_ok(hits.size() == 2, "search finds one row per matching LINE (dupes on a line collapse)")
	var by_path := {}
	for h in hits:
		by_path[str((h as Dictionary).get("path", ""))] = h
	_ok(by_path.has(a) and by_path.has(b), "search covers every indexed file")
	_ok(int((by_path[a] as Dictionary).get("line", -1)) == 2, "search line is 0-based and correct")
	_ok(str((by_path[a] as Dictionary).get("preview", "")).contains("needle needle"),
		"search rows carry the line preview")
	_ok((mine.call(SearchPanel.search("NEEDLE", true)) as Array).is_empty(),
		"match-case excludes lowercase hits")
	_ok((mine.call(SearchPanel.search("NEEDLE", false)) as Array).size() == 2,
		"case-insensitive matches regardless")
	_ok(SearchPanel.search("   ", false).is_empty(), "blank query returns nothing")

	for p in [a, b]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(str(p)))
	GuitkxWorkspace.rescan()

# W5/G14+G34 — project-scope Problems: sidecar aggregation with resolved lines, codes in rows,
# and project-row activation emitting (path, line).
func _test_problems_project() -> void:
	const ProblemsPanel := preload("res://addons/reactive_ui_toolkit_editor/editor/guitkx_problems_panel.gd")
	var a := "res://tests/__w5_diag.guitkx"
	var src := "component W5Diag() {\n\treturn (\n\t\t<Label text=\"x\" />\n\t)\n}\n"
	var f := FileAccess.open(a, FileAccess.WRITE)
	f.store_string(src)
	f.close()
	RuitkGuitkxCodegen.write_diags_sidecar(a, src, [
		{ "code": "GUITKX9901", "severity": 0, "message": "boom", "offset": src.find("<Label"), "length": 6 },
	])
	GuitkxWorkspace.rescan()

	var recs: Array = ProblemsPanel.project_records().filter(
		func(r): return str((r as Dictionary).get("path", "")) == a)
	_ok(recs.size() == 1, "project_records aggregates the sidecar diagnostic")
	if recs.size() == 1:
		var rec := recs[0] as Dictionary
		_ok(str(rec.get("code", "")) == "GUITKX9901", "record carries the GUITKX code")
		_ok(str(rec.get("severity", "")) == "error", "sidecar int severity maps to a name")
		_ok(int(rec.get("line", -1)) == 2, "sidecar offset resolves to the line on disk")

	# Row rendering (G34) + project-row activation -> (path, line).
	var panel: Control = ProblemsPanel.new()
	var got: Array = []
	panel.location_activated.connect(func(p: String, l: int): got.append([p, l]))
	panel._scope.select(1)  # Project scope (id 1) — activation routes to location_activated
	panel._render_rows([{ "code": "GUITKX0105", "severity": "error", "message": "unknown tag",
		"line": 3, "path": "res://x.guitkx" }], true)
	_ok(panel._list.item_count == 1, "project scope renders sidecar rows")
	_ok(panel._list.get_item_text(0).contains("[GUITKX0105]"), "rows lead with the code (G34)")
	_ok(panel._list.get_item_text(0).contains("x.guitkx:4"), "project rows show path:line (1-based)")
	panel._on_item_activated(0)
	_ok(got == [["res://x.guitkx", 3]], "activating a project row emits location_activated")
	panel.free()

	for p in [a, RuitkGuitkxCodegen.diags_path_for(a)]:
		if FileAccess.file_exists(str(p)):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(str(p)))
	GuitkxWorkspace.rescan()

# W6/G4 — signature help: the back-scan arms only inside an event-handler lambda's parameter list
# on a HOST tag, resolves the bound signal via ClassDB, and tracks the active parameter.
func _test_signature() -> void:
	const Sig := preload("res://addons/reactive_ui_toolkit_editor/lsp/guitkx_signature.gd")
	var src := "component S() {\n\treturn (\n\t\t<CheckBox on_toggled={ func (t): pass } />\n\t)\n}\n"
	var off := src.find("func (") + "func (".length()
	var sig: Dictionary = Sig.signature_at(src, off)
	_ok(not sig.is_empty(), "arms inside an on_<signal> lambda param list")
	_ok(str(sig.get("signal", "")) == "toggled", "resolves the verbatim on_<signal> name")
	_ok(str(sig.get("label", "")) == "toggled(toggled_on: bool)", "label carries ClassDB param types")
	_ok(int(sig.get("active", -1)) == 0, "first param active at the open paren")

	# Active-parameter tracking across top-level commas (nested parens/strings don't count).
	var src2 := "component S() {\n\treturn (\n\t\t<ItemList on_item_clicked={ func (i, Vector2(0,0), b): pass } />\n\t)\n}\n"
	var after_second_comma := src2.find("), b") + ")".length() + ", ".length()
	var sig2: Dictionary = Sig.signature_at(src2, after_second_comma)
	_ok(int(sig2.get("active", -1)) == 2, "active param counts only top-level commas")
	_ok((sig2.get("params", []) as Array).size() == 3, "item_clicked exposes all three params")

	# React alias: onChange on OptionButton binds item_selected.
	var src3 := "component S() {\n\treturn (\n\t\t<OptionButton onItemSelected={ func (idx): pass } />\n\t)\n}\n"
	var sig3: Dictionary = Sig.signature_at(src3, src3.find("func (") + "func (".length())
	_ok(str(sig3.get("signal", "")) == "item_selected", "React alias resolves polymorphically")

	# Negatives: a method REFERENCE, a non-event attribute, a component tag, caret outside parens.
	var mref := "component S() {\n\treturn (\n\t\t<Button on_pressed={_on_click} />\n\t)\n}\n"
	_ok(Sig.signature_at(mref, mref.find("_on_click") + 4).is_empty(), "method reference offers no help")
	var nonev := "component S() {\n\treturn (\n\t\t<Label text={ func (x): pass } />\n\t)\n}\n"
	_ok(Sig.signature_at(nonev, nonev.find("func (") + "func (".length()).is_empty(),
		"non-event attribute offers no help")
	var comp := "component S() {\n\treturn (\n\t\t<MyThing on_toggled={ func (t): pass } />\n\t)\n}\n"
	_ok(Sig.signature_at(comp, comp.find("func (") + "func (".length()).is_empty(),
		"component tags (no ClassDB signals) offer no help")
	_ok(Sig.signature_at(src, src.find("<CheckBox") + 3).is_empty(), "caret outside a param list is silent")

	# Widget: the strip shows while the caret is in context and hides when it leaves (G4 UI).
	var ce: CodeEdit = CodeEditScript.new()
	ce.text = src
	var lc: Dictionary = RuitkGuitkxDiag.line_col(src, off)
	ce.set_caret_line(int(lc["line"]))
	ce.set_caret_column(int(lc["col"]))
	ce._signature_refresh()
	_ok(ce.signature_visible(), "strip appears with the caret in a param list")
	_ok(ce._sig_label.text.contains("toggled"), "strip renders the signal label")
	ce.set_caret_line(0)
	ce.set_caret_column(0)
	ce._signature_refresh()
	_ok(not ce.signature_visible(), "strip hides when the caret leaves the context")
	ce.free()

# W7 — G11 embedded sub-highlighting, G30 Enter-between-tags, G20 snippet confirm, E14 line
# verbs + bookmarks, D6 per-call compile refs.
func _test_wave7_editing() -> void:
	# G11: inside {expr}, GDScript classifies for real — keyword/number/string — braces are
	# symbols, and `<` is a comparison operator, never a tag. Outside, markup rules unchanged.
	var tok := GuitkxTokenizer.new()
	var line := "<Label text={ 1 if a < 2 else \"hi\" } />"
	var toks: Array = tok.tokenize_line(line)
	var kind_at := func(col: int) -> String:
		for t in toks:
			if int((t as Dictionary)["start"]) <= col and col < int((t as Dictionary)["end"]):
				return str((t as Dictionary)["kind"])
		return ""
	_ok(kind_at.call(1) == "tag", "host tag still classified")
	_ok(kind_at.call(line.find("text")) == "attr", "attr before ={ still classified")
	_ok(kind_at.call(line.find("{")) == "symbol", "expr open brace is a symbol")
	_ok(kind_at.call(line.find("1")) == "number", "number inside expr classified")
	_ok(kind_at.call(line.find("if")) == "keyword", "keyword inside expr classified")
	_ok(kind_at.call(line.find("\"hi\"") + 1) == "string", "string inside expr classified")
	_ok(kind_at.call(line.find("<", 5)) == "symbol", "`<` inside expr is an operator, not a tag")
	_ok(kind_at.call(line.find("}")) == "symbol", "expr close brace is a symbol")
	# gd_mode does NOT paint assignments as attributes.
	var gtoks: Array = tok.tokenize_line("x = \"s\"", true)
	var has_attr := false
	for t in gtoks:
		if str((t as Dictionary)["kind"]) == "attr":
			has_attr = true
	_ok(not has_attr, "gd_mode treats name= as assignment, not attribute")

	# G30: Enter with the caret between >|</ splits the pair around an indented middle line.
	var ce: CodeEdit = CodeEditScript.new()
	ce.text = "\t\t<VBoxContainer></VBoxContainer>"
	ce.set_caret_line(0)
	ce.set_caret_column("\t\t<VBoxContainer>".length())
	_ok(ce.handle_enter_between_tags(), "enter-between-tags arms on >|</")
	_ok(ce.get_line_count() == 3, "pair splits onto three lines")
	_ok(ce.get_line(1) == "\t\t  ", "middle line indents one level deeper")
	_ok(ce.get_line(2) == "\t\t</VBoxContainer>", "closing tag keeps the base indent")
	_ok(ce.get_caret_line() == 1 and ce.get_caret_column() == 4, "caret lands on the middle line")
	ce.undo()
	_ok(ce.get_line_count() == 1, "the split is one undo step")
	ce.set_caret_line(0)
	ce.set_caret_column(2)
	_ok(not ce.handle_enter_between_tags(), "elsewhere, Enter is left alone")
	ce.free()

	# G20: confirming a completion steps the caret back inside the trailing empty pair.
	var ce2: CodeEdit = CodeEditScript.new()
	ce2.text = "te"
	ce2.set_caret_line(0)
	ce2.set_caret_column(2)
	ce2.add_code_completion_option(CodeEdit.KIND_MEMBER, "text", "text=\"\"")
	ce2.update_code_completion_options(true)
	ce2.confirm_with_snippet_caret()
	_ok(ce2.get_line(0) == "text=\"\"", "confirm inserts the snippet body")
	_ok(ce2.get_caret_column() == 6, "caret steps back inside the quotes (G20)")
	ce2.free()

	# E14: line verbs ride the CodeEdit built-ins; bookmarks toggle and cycle.
	var ce3: CodeEdit = CodeEditScript.new()
	ce3.text = "aaa\nbbb\nccc"
	ce3.set_caret_line(2)
	ce3.set_caret_column(0)
	ce3.move_lines_up()
	_ok(ce3.get_line(1) == "ccc" and ce3.get_line(2) == "bbb", "move-line-up swaps with the neighbor")
	var before_dup := ce3.get_line_count()
	ce3.duplicate_lines()
	_ok(ce3.get_line_count() == before_dup + 1, "duplicate adds a copy")
	ce3.delete_lines()
	_ok(ce3.get_line_count() == before_dup, "delete removes the line")
	ce3.set_caret_line(0)
	ce3.toggle_bookmark()
	_ok(ce3.is_line_bookmarked(0), "Ctrl+B bookmarks the caret line")
	ce3.set_caret_line(2)
	ce3.goto_next_bookmark()
	_ok(ce3.get_caret_line() == 0, "bookmark cycle wraps to the first mark")
	ce3.toggle_bookmark()
	_ok(not ce3.is_line_bookmarked(0), "second toggle clears the bookmark")
	ce3.free()

	# D6: compile() returns PER-CALL refs — populated when a guitkx-bound component lowers, and
	# structurally empty on the next call (no static bleed between compiles).
	var src := "component RA() {\n\treturn (\n\t\t<Dep />\n\t)\n}\n"
	var r1: Dictionary = RuitkGuitkx.compile(src, "ra", ["Dep"], { "Dep": "res://x/dep.gd" })
	_ok(str((r1.get("refs", {}) as Dictionary).get("Dep", "")) == "res://x/dep.gd",
		"compile returns the per-call component refs")
	var r2: Dictionary = RuitkGuitkx.compile(
		"component RB() {\n\treturn (\n\t\t<Label />\n\t)\n}\n", "rb", [], {})
	_ok((r2.get("refs", {}) as Dictionary).is_empty(), "next compile starts with empty refs (D6)")

# F1 — tokenizer case table: the classification promises "headlessly unit-testable" finally pinned.
# Each case probes the KIND at specific columns (resilient to symbol-run splitting).
func _test_tokenizer_corpus() -> void:
	var tok := GuitkxTokenizer.new()
	# [line, {col: expected_kind}] — "" expects unclassified (default colour).
	var cases: Array = [
		["# a comment", { 0: "comment", 10: "comment" }],
		["\"text run\"", { 0: "string", 9: "string" }],
		["'sq'", { 0: "string" }],
		["<Label />", { 0: "symbol", 1: "tag", 5: "tag", 7: "symbol", 8: "symbol" }],
		["</VBoxContainer>", { 0: "symbol", 1: "symbol", 2: "tag", 15: "symbol" }],
		["< 5", { 0: "symbol", 2: "number" }],
		["@if cond", { 0: "directive", 2: "directive", 4: "" }],
		["@ x", { 0: "symbol" }],
		["123 0xFF 1.5", { 0: "number", 4: "number", 9: "number" }],
		["component Foo() {", { 0: "keyword", 10: "", 16: "symbol" }],
		["text=\"v\"", { 0: "attr", 4: "symbol", 5: "string" }],
		["x = 5", { 0: "", 2: "symbol", 4: "number" }],
		["on_pressed={ handler }", { 0: "attr", 11: "symbol", 13: "" }],
		["{ var s = \"x\" }", { 0: "symbol", 2: "keyword", 10: "string", 14: "symbol" }],
		["{ a < b }", { 4: "symbol" }],
		["style={ {\"bg_color\": 4} }", { 0: "attr", 8: "symbol", 9: "string", 21: "number" }],
		["{ unterminated", { 0: "symbol", 2: "" }],
	]
	for case in cases:
		var line := str(case[0])
		var toks: Array = tok.tokenize_line(line)
		for col in (case[1] as Dictionary):
			var want := str((case[1] as Dictionary)[col])
			var got := ""
			for t in toks:
				if int((t as Dictionary)["start"]) <= int(col) and int(col) < int((t as Dictionary)["end"]):
					got = str((t as Dictionary)["kind"])
					break
			_ok(got == want, "tokenize '%s' col %d -> '%s' (got '%s')" % [line, col, want, got])
	# Spans are ordered and non-overlapping — the highlighter's boundary-map precondition.
	var ordered := true
	for line_case in cases:
		var prev_end := -1
		for t in tok.tokenize_line(str(line_case[0])):
			if int((t as Dictionary)["start"]) < prev_end:
				ordered = false
			prev_end = int((t as Dictionary)["end"])
	_ok(ordered, "token spans stay ordered and non-overlapping across the corpus")

# F3 — TS-twin parity pins: behaviors the VS Code server pins that the addon inherited untested.
func _test_parity_pins() -> void:
	# 0.9.0 loyal events: on<Pascal> lowers generically to the snake_case signal — no alias table.
	_ok(GuitkxSchema.resolve_event_signal("onItemSelected", "OptionButton") == "item_selected",
		"onItemSelected on OptionButton -> item_selected")
	_ok(GuitkxSchema.resolve_event_signal("onValueChanged", "SpinBox") == "value_changed",
		"onValueChanged on SpinBox -> value_changed")
	_ok(GuitkxSchema.resolve_event_signal("onTextChanged", "LineEdit") == "text_changed",
		"onTextChanged on LineEdit -> text_changed")
	_ok(GuitkxSchema.resolve_event_signal("onToggled", "CheckBox") == "toggled",
		"onToggled on CheckBox -> toggled")
	# The removed React alias no longer resolves specially: onChange lowers to a literal `change`.
	_ok(GuitkxSchema.resolve_event_signal("onChange", "OptionButton") == "change",
		"removed alias onChange lowers generically (no polymorphic table)")
	var evs: Array = GuitkxSchema.events_for_class("OptionButton")
	var item_sel := ""
	var has_pressed := false
	for e in evs:
		if str((e as Dictionary).get("name", "")) == "onItemSelected":
			item_sel = str((e as Dictionary).get("signal", ""))
		if str((e as Dictionary).get("name", "")) == "onPressed":
			has_pressed = true
	_ok(item_sel == "item_selected", "events_for_class derives onItemSelected from ClassDB")
	_ok(has_pressed, "events_for_class includes INHERITED signals (onPressed from BaseButton)")

	# @class_name override binds the generated class (compile + codegen surface).
	var src := "@class_name Zed\ncomponent OvR() {\n\treturn (\n\t\t<Label />\n\t)\n}\n"
	var r: Dictionary = RuitkGuitkx.compile(src, "ovr")
	_ok(bool(r.get("ok", false)) and str(r.get("gd", "")).contains("class_name Zed"),
		"@class_name override names the generated class")

	# Index eviction: a deleted file's component leaves the workspace on rescan.
	var p := "res://tests/__evict_me.guitkx"
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string("component EvictMe() {\n\treturn (\n\t\t<Label />\n\t)\n}\n")
	f.close()
	GuitkxWorkspace.rescan()
	_ok(GuitkxWorkspace.component_tags().has("EvictMe"), "new component enters the index on rescan")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	GuitkxWorkspace.rescan()
	_ok(not GuitkxWorkspace.component_tags().has("EvictMe"), "deleted component is evicted on rescan")

	# Windows path canonicalization: every index/codegen surface speaks res:// forward slashes.
	var clean := true
	for wp in GuitkxWorkspace.all_paths():
		if not str(wp).begins_with("res://") or str(wp).contains("\\"):
			clean = false
	_ok(clean, "workspace paths are canonical res:// (no backslashes)")
	_ok(RuitkGuitkxCodegen.gd_path_for("res://a/b.guitkx") == "res://a/b.gd",
		"gd_path_for maps beside the source")
	_ok(RuitkGuitkxCodegen.diags_path_for("res://a/b.guitkx") == "res://a/b.guitkx.diags.json",
		"diags_path_for maps the sidecar name")

# M3 — the byte<->char boundary (GuitkxLineIndex): CodeEdit columns are CODE POINTS (probed:
# "aé😀b" -> length 4, caret col 4, 8 UTF-8 bytes); the analyzer speaks UTF-8 bytes.
func _test_line_index() -> void:
	const LI := preload("res://addons/reactive_ui_toolkit_editor/lsp/guitkx_line_index.gd")
	var s := "aé😀b"  # 1 + 2 + 4 + 1 UTF-8 bytes; 4 code points
	_ok(LI.char_to_byte(s, 0) == 0, "char 0 -> byte 0")
	_ok(LI.char_to_byte(s, 1) == 1, "ascii char -> 1 byte")
	_ok(LI.char_to_byte(s, 2) == 3, "2-byte char advances by 2")
	_ok(LI.char_to_byte(s, 3) == 7, "4-byte emoji advances by 4")
	_ok(LI.char_to_byte(s, 4) == 8, "end char -> total byte length")
	_ok(LI.byte_to_char(s, 8) == 4, "end byte -> char length")
	_ok(LI.byte_to_char(s, 7) == 3, "emoji start byte -> its char index")
	_ok(LI.byte_to_char(s, 5) == 2, "byte inside the emoji clamps to its char")
	_ok(LI.byte_to_char(s, 0) == 0 and LI.char_to_byte(s, 99) == 8 and LI.byte_to_char(s, 99) == 4,
		"out-of-range clamps at both ends")
	var ml := "ab\ncd😀\nef"
	var eoff := ml.find("f")
	_ok(LI.byte_to_char(ml, LI.char_to_byte(ml, eoff)) == eoff, "multiline round-trip is identity")

# M3 — GuitkxSourceMap: length-preserving spans translate by constant delta; outside -> -1.
func _test_source_map() -> void:
	const SM := preload("res://addons/reactive_ui_toolkit_editor/lsp/guitkx_source_map.gd")
	var m: RefCounted = SM.new()
	m.add_span(100, 10, 5)
	m.add_span(300, 40, 8)
	m.add_span(0, 0, 0)  # zero-length spans are dropped
	_ok(m.span_count() == 2, "zero-length spans are not recorded")
	_ok(m.to_generated(100) == 10 and m.to_generated(105) == 15, "source->gen translates by delta (inclusive ends)")
	_ok(m.to_source(44) == 304, "gen->source translates by delta")
	_ok(m.to_generated(99) == -1 and m.to_generated(200) == -1, "outside every span -> -1")
	_ok(m.to_source(9) == -1 and m.to_source(30) == -1, "gen glue -> -1")

# M3 — the virtual-document port (GuitkxVirtualDoc): scope-aware emission, verbatim mapping,
# hook stubs byte-identical to hooks.gd, misspelled-decl recovery, markup neutralization.
func _test_virtual_doc() -> void:
	const VD := preload("res://addons/reactive_ui_toolkit_editor/lsp/guitkx_virtual_doc.gd")
	var src := "component Probe(title) {\n\tvar b := Button.new()\n\treturn (\n\t\t<VBoxContainer>\n\t\t\t<Label text={ title } />\n\t\t\t@if (b.visible) {\n\t\t\t\t<Label text={ str(b.text) } />\n\t\t\t}\n\t\t</VBoxContainer>\n\t)\n}\n"
	var built: Dictionary = VD.build(src)
	var gen := str(built["text"])
	var map: RefCounted = built["map"]
	_ok(gen.begins_with("extends RefCounted\n"), "virtual doc extends RefCounted")
	_ok(gen.contains("static func useState(initial = null) -> Array: return Hooks.useState(initial)"),
		"hook stubs are class-level static wrappers")
	_ok(gen.contains("## @return-tuple(Variant, Callable)"), "tuple hooks carry the @return-tuple doc")
	_ok(gen.contains("static func render(props: Dictionary, children: Array) -> RuitkVNode:"),
		"top-level component emits render()")
	_ok(gen.contains("\tvar title = props.get(\"title\")"), "params destructure from props")
	_ok(gen.contains("\tvar b := Button.new()"), "setup splices verbatim")
	_ok(gen.contains("\tif b.visible:"), "@if lowers to a REAL if with the mapped condition")
	_ok(gen.contains("\t\tvar _e1 = (str(b.text) )"), "nested expr emits INSIDE the branch scope")
	# Round-trips: expr + setup + condition offsets map to the generated doc and back, identically.
	for probe: int in [src.find("{ title }") + 2, src.find("Button.new"), src.find("b.visible")]:
		var g: int = map.to_generated(probe)
		_ok(g >= 0 and map.to_source(g) == probe, "offset %d round-trips through the map" % probe)
	_ok(map.to_generated(src.find("<VBoxContainer>") + 1) == -1, "markup offsets stay unmapped (glue)")

	# Hook-stub parity: every stub's signature text must appear VERBATIM in hooks.gd (the same
	# discipline the TS twin asserts in core.test.ts — three implementations, one authority).
	var hooks_src := FileAccess.get_file_as_string("res://addons/reactive_ui_toolkit/core/hooks.gd")
	var stubs_ok := true
	for h in VD.HOOK_STUBS:
		var sig := "static func %s(%s)%s" % [str(h["name"]), str(h["params"]), str(h["ret"])]
		if not hooks_src.contains(sig):
			stubs_ok = false
			printerr("  stub drifted from hooks.gd: ", sig)
	_ok(stubs_ok, "every hook stub signature matches hooks.gd byte-for-byte")

	# Misspelled declaration recovery: embedded GDScript is still analyzed (never goes dark).
	var typo := "comssponent Foo() {\n\tvar x := 1\n\treturn (\n\t\t<Label />\n\t)\n}\n"
	var tgen := str((VD.build(typo) as Dictionary)["text"])
	_ok(tgen.contains("var x := 1"), "misspelled decl keyword still emits the body (recovery)")

	# Hook declarations keep their real name + mapped params; tuple return hints are dropped.
	var hsrc := "hook useThing(a: int, b := 2) -> (int, Callable) {\n\treturn [a, func(): pass]\n}\n"
	var hgen := str((VD.build(hsrc) as Dictionary)["text"])
	_ok(hgen.contains("static func useThing(a: int, b := 2):"), "hook keeps name+params; tuple hint dropped")

	# ES-modules (0.11.0): a plain multi-decl file emits EVERY top-level decl -- first component
	# as render, later ones under their names, hooks/utils real names, values as mapped static var.
	var multi := "export w := { \"a\": 1 }
export fmt(x: int) -> String {
	return str(x)
}
export use_t() -> int {
	return 1
}
export Foo() -> RuitkVNode {
	return (
		<Label />
	)
}
Bar() -> RuitkVNode {
	return (
		<Label />
	)
}
"
	var mgen := str((VD.build(multi) as Dictionary)["text"])
	_ok(mgen.contains("static var w := { \"a\": 1 }"), "value decl emits as mapped static var (got %s)" % mgen)
	_ok(mgen.contains("static func fmt(x: int)"), "util emits under its real name")
	_ok(mgen.contains("static func use_t("), "plain hook emits under its real name")
	_ok(mgen.contains("static func render(props: Dictionary, children: Array) -> RuitkVNode:"), "first plain component emits render")
	_ok(mgen.contains("static func Bar(props: Dictionary, children: Array) -> RuitkVNode:"), "second plain component emits under its decl name")

	# Markup nested inside an expression neutralizes to length-preserving null padding.
	var n := VD._neutralize_markup("open and <PanelContainer/> ")
	_ok(n.length() == "open and <PanelContainer/> ".length() and n.contains("null") and not n.contains("<Panel"),
		"nested markup neutralizes length-preserving")
	var blk := "return <s></a>\nvar ok := 1\n"
	var nb := VD._neutralize_setup_markup(blk)
	_ok(nb.length() == blk.length() and nb.count("\n") == blk.count("\n") and nb.contains("return null"),
		"setup markup neutralizes newline-preserving into `return null`")

	# 0.11.1 field wave: imported names are declared as permissive static-var stubs (the
	# virtualDoc.ts declareImportStubs port was missing here — imported names had no declaration
	# in the in-editor analysis). Every form contributes, incl. the parts of a COMBINED import.
	var isrc := "import { chip_w, fmt as fx } from \"./other\"\n" + \
		"import isEven, { get_something } from \"./more\"\n" + \
		"import D2, * as NS from \"./more\"\n" + \
		"import Solo from \"./third\"\n\n" + \
		"export ImpProbe() -> RuitkVNode {\n\tvar a = fx(chip_w)\n\treturn (\n\t\t<Label text={str(a)} />\n\t)\n}\n"
	var igen := str((VD.build(isrc) as Dictionary)["text"])
	for stub_name in ["chip_w", "fx", "isEven", "get_something", "D2", "NS", "Solo"]:
		_ok(igen.contains("static var %s\n" % stub_name), "import stub declared for `%s` (got %s)" % [stub_name, igen.substr(0, 400)])
	_ok(not igen.contains("static var fmt\n"), "a rename stubs the LOCAL alias, not the remote name")

# M3 — the analyzer bridge. DUAL-MODE by design: with the reactive_ui_toolkit_analyzer GDExtension
# installed (dev machines) the full e2e surface is asserted; without it (CI) the degrade path is
# asserted — instance() null, editor pipeline unaffected. Both paths stay covered somewhere.
func _test_analyzer_bridge() -> void:
	const Bridge := preload("res://addons/reactive_ui_toolkit_editor/lsp/guitkx_analyzer_bridge.gd")
	var src := "component Probe(title) {\n\tvar b := Button.new()\n\treturn (\n\t\t<VBoxContainer>\n\t\t\t<Label text={ title } />\n\t\t\t<Label text={ str(b.text) } />\n\t\t</VBoxContainer>\n\t)\n}\n"
	if not Bridge.available():
		print("[guitkx_editor_test]    (native analyzer ABSENT - asserting the degrade path)")
		_ok(Bridge.instance() == null, "absent extension -> instance() is null")
		var dv: Control = ViewScript.new()
		dv._code_edit.text = src
		dv._refresh_diagnostics()  # must not crash, and no GD: rows can exist
		var gd_rows := false
		for ln in dv._code_edit._line_diags:
			for rec in dv._code_edit._line_diags[ln]:
				if str((rec as Dictionary).get("code", "")).begins_with("GD:"):
					gd_rows = true
		_ok(not gd_rows, "absent extension -> no analyzer diagnostics, markup tier intact")
		dv.free()
		return

	print("[guitkx_editor_test]    (native analyzer %s - asserting the full e2e surface)" % Bridge.native_version())
	_ok(Bridge.native_version() != "", "native_version reports the library version")
	var bridge = Bridge.instance()
	_ok(bridge != null, "instance() constructs the singleton")
	var p := "res://tests/__m3_probe.guitkx"

	# Shim field-type parity: offsets arrive as Godot ints, codes/messages as Strings.
	var diags: Array = bridge.diagnostics(p, src)
	_ok(diags.is_empty(), "clean file -> zero analyzer diagnostics (glue never squiggles)")
	var bad := src.replace("str(b.text)", "b.text.no_such_member")
	var bdiags: Array = bridge.diagnostics(p, bad)
	_ok(not bdiags.is_empty(), "a type error inside {expr} produces an analyzer diagnostic")
	if not bdiags.is_empty():
		var d0 := bdiags[0] as Dictionary
		_ok(str(d0.get("code", "")).begins_with("GD:"), "analyzer codes carry the GD: prefix")
		_ok(typeof(d0.get("offset")) == TYPE_INT and typeof(d0.get("severity")) == TYPE_INT,
			"shim delivers integral offsets/severities as Godot ints")
		_ok(int(d0["offset"]) >= bad.find("b.text.no_such_member")
			and int(d0["offset"]) <= bad.find("no_such_member") + "no_such_member".length(),
			"diagnostic remaps onto the offending expression in .guitkx coords")

	# Hover: type-aware, guitkx-anchored.
	var hov: Dictionary = bridge.hover(p, src, src.find("b.text"))
	_ok(str(hov.get("ty_label", "")) == "Button", "hover inside {expr} infers the engine type")
	_ok(int(hov.get("offset", -1)) == src.find("b.text"), "hover range remaps to .guitkx coords")

	# Completions after `b.` inside the expr: engine members, raw analyzer items.
	var comps: Array = bridge.completions(p, src, src.find("b.text") + 2)
	_ok(comps.size() > 100, "member completion offers the engine surface (got %d)" % comps.size())
	var has_set_text := false
	for c in comps:
		if str((c as Dictionary).get("label", "")) == "set_text":
			has_set_text = true
			break
	_ok(has_set_text, "Button members include set_text")

	# Goto definition: usage inside {expr} -> the declaration in THIS .guitkx.
	var defs: Array = bridge.goto_definition(p, src, src.find("b.text"))
	_ok(defs.size() == 1 and str((defs[0] as Dictionary)["path"]) == p
		and int((defs[0] as Dictionary)["offset"]) == src.find("b :="),
		"goto-def lands on the setup declaration, remapped")

	# References: declaration + usage, both in-buffer.
	var refs: Array = bridge.find_references(p, src, src.find("b.text"))
	_ok(refs.size() >= 2, "find-references sees declaration + usage (got %d)" % refs.size())

	# Signature help inside a call, active parameter tracking.
	var csrc := src.replace("var b := Button.new()", "var b := Button.new()\n\tvar q = clampi(1, 2, 3)")
	var sig: Dictionary = bridge.signature_help(p, csrc, csrc.find("clampi(1, ") + "clampi(1, ".length())
	var sigs: Array = sig.get("signatures", [])
	_ok(not sigs.is_empty() and str((sigs[0] as Dictionary).get("label", "")).begins_with("clampi("),
		"signature help resolves the builtin call")
	_ok(int(sig.get("active_parameter", -1)) == 1, "active parameter tracks the comma")

	# Rename: buffer-scoped, both occurrences, descending offsets.
	var ren: Dictionary = bridge.rename(p, src, src.find("b :="), "btn")
	_ok(bool(ren.get("ok", false)) and (ren.get("edits", []) as Array).size() == 2,
		"rename resolves declaration + usage")
	if bool(ren.get("ok", false)):
		var edits: Array = ren["edits"]
		_ok(int((edits[0] as Dictionary)["offset"]) > int((edits[1] as Dictionary)["offset"]),
			"edits arrive descending (splice-safe)")

	# Markup offsets are not the analyzer's domain.
	_ok(not bridge.is_embedded_offset(p, src, src.find("<VBoxContainer>") + 1), "tag offsets stay unmapped")
	_ok(bridge.completions(p, src, src.find("<VBoxContainer>") + 1).is_empty(),
		"markup-caret queries return empty (markup tier owns them)")

	# View integration: an embedded type error flows into the diagnostics pipeline as a GD: row.
	var v: Control = ViewScript.new()
	v._code_edit.text = bad
	v._refresh_diagnostics()
	var found_gd := false
	for ln in v._code_edit._line_diags:
		for rec in v._code_edit._line_diags[ln]:
			if str((rec as Dictionary).get("code", "")).begins_with("GD:"):
				found_gd = true
	_ok(found_gd, "analyzer diagnostics merge into the editor pipeline (GD: rows)")
	v.free()
