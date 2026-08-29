extends SceneTree
## PARITY SWEEP: every feature the Unity leg's builder has, and where this one answers it. Run:
##   godot --headless --path <project> --script res://tests/builder_parity.gd
##
## The reference is `../ruitk-unity/Builder/Editor/` — 20k lines, and the thing this builder is a
## port OF. It is NOT in this repository, so this gate cannot read it; what it can do is hold the
## checklist derived from it and fail when an entry stops being answered.
##
## WHY THIS EXISTS. This builder was written from a plan document while the source sat unread in
## a sibling checkout, and the result was a subsystem full of behaviour I invented and then
## justified in comments. Everything below was found afterwards, one user report at a time, and
## most of it was a mechanism that already existed with nothing wired to it: a drop handler with
## no drag, a layout store with no way to move a card, an `entry_activated` nobody listened to,
## a provisional root the create flow never used. A list is the only thing that catches that
## class of gap, because each one individually looks like a feature nobody has asked for yet.
##
## An entry is a Unity method name and a token that must appear somewhere under `builder/` or in
## the editor plugin. The token is deliberately a distinctive IDENTIFIER, not prose: prose gets
## reworded and the gate rots into a test of its own comments.
##
## WHAT THIS GATE CANNOT DO, said plainly because it was believed to do it. A token that exists is
## not a feature that works: this sweep is green over any identifier, however inert. Three ways it
## was found lying, all fixed here, all worth knowing about when adding an entry:
##
##   * MIS-MAPPED -- `MoveModuleToFolder` pointed at `drop_module`, which is the style-application
##     gesture and has nothing to do with re-filing. The token existed, so the gate was green.
##   * AMBIGUOUS -- `func apply_edit` is defined in FOUR files with four different jobs, so the
##     entry stayed green with the one it named deleted. Prefer a token that exists once.
##   * INERT -- an entry can name a function that is correct and unreachable. `undo` was green
##     while no key or button could trigger it, and `trace` while nothing listened to the signal.
##
## So this is a CHECKLIST OF COVERAGE, not a test of behaviour. The behaviour lives in the seven
## builder suites and in `scripts/builder-shots.mjs`, which drives real input at a real editor
## window. Adding an entry here is not adding a test.

const ROOTS := [
	"res://addons/reactive_ui_toolkit_editor/builder",
	"res://addons/reactive_ui_toolkit_editor/plugin.gd",
]

## Unity method -> the identifier that answers it here.
const PARITY := [
	# Entry points
	["OpenEmpty", "func open_tree"],
	["OpenFor", "func open_builder_on"],
	["Assets/Open in RUITK UI Builder", "CONTEXT_SLOT_FILESYSTEM"],
	# Folders and modules
	["MoveModuleToFolder", "func place_module"],
	["MoveFolderToFolder", "func move_folder"],
	["the layout follows the file", "func _repath_layout"],
	["re-file by dragging onto a folder row", "signal refile_requested"],

	["ShowEmptyState", "func _build_empty_state"],
	["NewFile / ShowCreatePrompt", "func prompt_create"],
	["ValidateNewName", "func _validate_name"],
	["CreateModule", "func _create_named"],
	["BirthPathFor (the folder convention)", "func _birth_folder"],
	["ShowRenamePrompt", "func _rename_to"],
	["RenameTargetPath (shared by prompt and rename)", "func rename_target"],
	["RenameModule (export + bindings + uses)", "func rename_export"],
	["ValidateRenameName", "func _validate_rename"],
	["StripReferencesTo (delete takes its imports with it)", "func _strip_references_to"],
	["an import matched by RESOLVED PATH, not by spelling", "func _spec_importing"],
	# The source pane
	["BeginSourceEdit", "func _set_editing"],
	["ApplySourceEdit", "edit_applied.emit"],
	["CancelSourceEdit", "func cancel_edit"],
	# History
	["UndoAction / RedoAction", "func undo"],
	["JumpHistoryTo", "func _jump_history_to"],
	["ToggleHistory", "func _show_history"],
	# The row spine
	["OnCanvasRowClicked", "func _on_row_clicked"],
	["OnCanvasRowContext", "func _on_row_context"],
	["SyncLibrarySelection", "func select_entry"],
	["double-click a workspace entry to FRAME its card", "signal entry_framed"],
	["style / util / hook MODULE sections", "const ENTRY_HOOK_MODULE"],
	["ShowAttributeMenu", "func menu_for"],
	["the language index follows the buffers", "func _reindex_language"],
	["ShowRemoveAttributeMenu", "RowMenuId.REMOVE_ATTRIBUTE"],
	["an IMPORT row has its own menu", "RowMenuId.REMOVE_IMPORT"],
	["a BODY chip has its own menu", "RowMenuId.EDIT_BODY_LINE"],
	["ExtractIslandLines for hooks and utils", "func _plain_body_structure"],
	["OnAttrValueEdited", "func _attribute_items"],
	["ShowAddChildMenu", "func _tag_items"],
	["AddUsageImport", "func _with_component_import"],
	["ApplyStyleModuleToRow", "RowMenuId.APPLY_STYLE"],
	["style module applied by DROPPING it on an element", "func drop_module_export"],
	["ImportAliasFor (a binding that cannot collide)", "func bind_export"],
	["DeleteElementRow", "RowMenuId.DELETE_ROW"],
	# Directives
	["AddWrapItems", "const WRAPS"],
	["WrapRowInDirective", "func wrap_in_directive"],
	["WrapRowInSwitch", "func wrap_in_match"],
	["RemoveDirectiveBlock", "func unwrap_directive"],
	["AddIfClause", "func add_if_clause"],
	["AddSwitchClause + next case label", "func add_match_clause"],
	["ConstructClause walk", "func clauses_of"],
	["ExternalChangeSweep", "func adopt_external_changes"],
	["menu keyboard navigation", "func _move_highlight"],
	["DeleteClause", "func delete_clause"],
	["OnDirectiveEdited", "RowMenuId.EDIT_HEADER"],
	# Islands and style entries
	["OnIslandEdited", "func set_island"],
	["a MULTILINE island editor, syntax-coloured", "guitkx_code_edit.gd\""],
	["double-click to edit a row in place", "signal row_activated"],
	["the editor takes the size of what it edits", "func _row_rect_on_screen"],
	["drop hint (band + caret)", "func _draw_drop_hint"],
	["source pane chords (Ctrl+Enter / Esc)", "func _unhandled_key_input"],
	# Drag and drop
	["OnCanvasRowDrop", "func _on_canvas_drop"],
	["drag sources", "func _get_drag_data"],
	["drop target", "func _can_drop_data"],
	["card dragging, by the TITLE BAR", "func on_title_bar"],
	["one definition of what a layer draws", "func draws_section"],
	["one definition of which sections a card HAS", "func has_body_section"],
	["RebindFocusIfMissing", "func _rebind_focus_if_missing"],
	["one coordinate space for every menu", "func _screen_at"],
	["AnchorOf/CardRect (measure the drawn card)", "func measured_row"],
	["IsSingleClauseConstruct (unwrap guard)", "func can_unwrap"],
	["hook stubs that are legal GDScript", "func hook_stub"],
	["card dragging", "signal card_moved"],
	["the bottom band's first-child rule", "Placement.FIRST_CHILD"],
	["DrawCardShadow", "shadow_size"],
	["directive badges on the row (BadgeColor/BadgeBg)", "func directive_badge"],
	["detailVisible: export heads at Layer 2, entries at Layer 3", "func draws_export_row"],
	["DotColor(kind) -- an anchor dot is its import's kind", "func edge_tint"],
	["the lattice coarsens instead of vanishing", "doublings"],
	["UB-23: every card section is capped and scrolls", "func section_cap"],
	["the kind chip is a drag handle for the MODULE", "func on_kind_badge"],
	["double-click a component row to go to its module", "func _navigate_to_component"],
	["double-click a card to frame it", "signal card_activated"],
	["a drop reports its own outcome", "func _drop_refused"],
	["a restored zoom is clamped on the way in", "stored.zoom = Metrics.DEFAULT_ZOOM"],
	["an adopted slot is written down", "var adopted := layout.adopt_unplaced(graph)"],
	["restored positions are checked, not trusted", "func resolve_overlaps"],
	["the zoom is in the layout, not on the node", "func scaled"],
	["the card move and Godot's DnD do not both claim the left drag", "if _moving >= 0:"],
	["FamilyOwnerFor", "func family_owner_for"],
	["one oracle for the tree root", "DocTree.resolve_root_from"],
	["BuilderTree.validate is actually called", "func _validate_tree"],
	["a new card lands where the gesture pointed", "func place_new_card"],
	["RememberMenuPointer", "_menu_at = _canvas.get_local_mouse_position()"],
	["adding a clause opens its header", "ELIF_SEED"],
	["UB-112: a template invents no content", "export %s := {"],
	["the delete rule takes an emptied directive with it", "func orphaned_directive"],
	["every mutation reports itself", "Renamed to %s"],
	["AdvanceStyleEntry", "func _advance_style_entry"],
	["the freeform row builds its own payload", "func _freeform_style_key"],
	["BuilderCursor", "func _get_cursor_shape"],
	["the inline editor says HOW an edit ended", "signal closed(token: Variant)"],
	["go-to-definition from the source pane", "func _on_definition_requested"],
	["a gutter click goes to its diagnostic", "signal diagnostic_clicked"],
	["+N more expands INSIDE its section", "_expanded_fully"],
	["a file row is a drop target for its own folder", "_drop_target_for(data, path.get_base_dir())"],
	["the drop target row is highlighted", "drop_mode_flags = Tree.DROP_MODE_ON_ITEM"],
	["a refused drop says which refusal", "func _refusal_into"],
	["folder rows carry their full path", "item.set_tooltip_text"],
	["the FOLDERS pane folds, and it is remembered", "func _fold_folders"],
	["RevealSelected", "func _reveal_selected"],
	["framing resolves by FILE, not by name alone", "signal entry_framed(file_path: String"],
	["a re-file records the import rewrites it made", "for rewrite in workspace.reconcile_imports(snapshot):"],
	["SetError on the source field", "func set_error"],
	["double-click the listing to edit it", "func _on_editor_gui_input"],
	["an open edit is not overwritten from elsewhere", "changed elsewhere"],
	["read mode is not a disabled state", "font_readonly_color"],
	["the clicked row gets a band in the source", "func _repaint_line_bands"],
	["a hovered chip warms the source too", "func set_trace_names"],
	["an island row jumps to ITS line", "func _island_line_row"],
	["the inline editor scales with the row", "int(rect.size.y * 0.55)"],
	["one reported round, whoever asked for it", "func _run_round"],
	["Summary.reasons reaches the console", "func _why"],
	["the mount runs behind an error boundary", "func mount_error"],
	["a module changed on BOTH sides is reported", "changed on disk AND edited here"],
	["undo and redo report what they walked", "func _report_step"],
	["the hint bar wraps rather than clipping", "AUTOWRAP_WORD_SMART"],
	["the toast is bottom-centred and fades", "TOAST_FADE_MSEC"],
	["an unresolved import is explained", "func _report_unresolved_imports"],
	["the delete fall-through says what it deleted", "Ctrl+Z to put it back"],
	["a replay re-points a focus it removed", "_rebind_focus_if_missing()"],
	["every diagnostic reaches the console, warnings included", "for d in listed:"],
	["an emptied directive header removes the directive", "func delete_clause"],
	["the formatter reads the options for the FILE", "func _options_for"],
	["a schema-drift warning", "func _warn_on_directive_drift"],
	["the directive capability table", "DIRECTIVE_SUPPORT"],
	["@for loops over something in scope", "func collections_in_scope"],
	["and singularises its loop variable", "func singular_of"],
	["a style entry value is chosen, not seeded", "func _value_items"],
	["an attribute offers the values it can take", "func _attribute_value_items"],
	["an enum offers its own constants", "func values_for"],
	["an import of a real file outside the tree is pulled in", "func _pull_in_reachable_files"],
	["a host-tag drift warning", "func _warn_on_tag_drift"],
	["CollectStateNames", "func _state_names"],
	["the camera lives on the container, not in every card", "func _apply_camera"],
	["a pan only rebuilds when the cull set changes", "func _near_signature"],
	["the open tree enters the completion index", "LspWorkspace.reindex(module.file_path()"],
	["the drop bands are 0.3 / 0.7", "const BAND_EDGE := 0.3"],
	["Edit header is not offered where it does nothing", "func _has_editable_header"],
	["a diagnostic row carries its line separately", "signal location_activated(file_path: String, line: int)"],
	["a clean round takes back the space it took", "FILLED_BY_ROUND"],
	["create_module goes through the one placement rule", "return _create_named(kind, _unused_name"],
	["a placeholder is the height of the card it stands for", "M.drawn_height(card, lod)"],
	["a module with no exports is still in the palette", "if not out.has(card.title):"],
	["the search matches what the row SHOWS", "lstrip"],
	["+ new opens under the chip that opened it", "_new_button.get_screen_position()"],
	["a recovery starts with a ledger that describes THAT tree", "func restore_recovery"],
	["a history walk redraws once", "_walking_history"],
	["the file suffix decides for style and hook", "if by_name == Module.Kind.STYLE"],
	["the consumer list is resolved, not substring-matched", "for edge in graph.edges_to(index):"],
	["the inline editor stays inside the window", "get_parent_area_size()"],
	["abort goes back to the tree you were in", "func abort_all(prefer"],
	["a scrollable section eats the plain wheel; Ctrl+wheel is still the zoom", "func _input"],
	["UB-78: the signature is two runs, cut at the paren", "func signature_head"],
	# The preview
	["UsageFor", "func _usage_note"],
	["ModuleInfoFor", "func _module_note"],
	["BuildKnobs", "func _build_knobs"],
	["knob values carry across a rebuild", "func _knob_signature"],
	["the render anchor is not the focus", "func rendered_path"],
	["OnPreviewComponentPicked", "signal component_picked"],
	["state panel", "func _refresh_state"],
	["OnRecompiled (one hand-off per round)", "signal round_finished"],
	["the pane can ask why a module failed", "func last_error_for"],
	["BuilderRenderScheduler (a frame budget of its own)", "RuitkRoot.create_isolated"],
	# Chrome
	["Toast", "func toast"],
	["ToggleHelp", "func show_help"],
	["TogglePreviewTrace", "preview.trace.connect"],
	["diagnostics on the editing surface", "func show_diagnostics"],
	["GUITKX0105 vocabulary (unknown element)", "func known_component_tags"],
	["a tool failure is not a source failure", "env_error"],
	["SetActiveMode", "func _on_layer_chosen"],
	["BuildLegend", "func legend_entry"],
	["OnKeyDown (tree-wide chords)", "func _shortcut_input"],
	["the typing guard, which stands them down", "func _typing_focused"],
	["DeleteSelection", "func _delete_selection"],
	["row selection, one thing at a time", "func select_row"],
	["hovering a hook chip highlights its usages", "func row_mentions"],
	["a copyable diagnostics console", "func copy_text"],
	["CancelActiveEdit", "func _cancel_active_edit"],
	# Save
	["ResolveUnsavedLocation", "func _ask_where_the_tree_lives"],
	["style vocabulary read from the engine", "Schema.style_keys_live()"],
	["ResolveEmptyModules", "func _confirmed_blank_modules"],
	["a tree with no saved layout opens at Layer 2", "func _centre_when_sized"],
	["FormatDirtyBuffers", "format_on_save"],
	["SaveAll", "func save_all"],
	["Save names every file it would delete", "func _confirmed_deletions"],
	["AbortAll", "func abort_all"],
	["OfferJournalRestore", "func _offer_recovery"],
	["the editor's quit door knows the builder is dirty", "dirty_changed.connect"],
	["LoadTreeFor (keeps unsaved work)", "func load_tree_for"],
	["FormatDirtyBuffers through the funnel", "func _format_dirty_buffers"],
]

## Features the Unity leg has that this one deliberately does not, and why. Listed so the sweep
## reads as a complete account rather than as a list that quietly stops where I stopped.
const DELIBERATE := [
	["ImportUxml", "no Godot analogue -- a .tscn importer is a separate project with its own design"],
	["CodeField", "the source pane reuses guitkx_code_edit.gd, which is the .guitkx editor's own"],
	["BuilderLspClient (the TRANSPORT only)",
		"the editor addon's LSP layer owns the process and the protocol. What the Unity client "
		+ "CARRIED is listed above as its own entries -- diagnostics on the surface, the "
		+ "GUITKX0105 vocabulary, the live index -- because skipping the transport used to absorb "
		+ "them and leave the area with no coverage at all"],
]


func _initialize() -> void:
	var sources := _all_sources()
	var missing: Array = []
	for entry in PARITY:
		var pair := entry as Array
		if not _found(sources, str(pair[1])):
			missing.append("%s  (no `%s`)" % [str(pair[0]), str(pair[1])])

	print("")
	for entry in DELIBERATE:
		print("  skipped  %-24s %s" % [str((entry as Array)[0]), str((entry as Array)[1])])
	# AMBIGUOUS ENTRIES ARE REPORTED, not silently tolerated. Not a failure: a few tokens
	# legitimately appear in more than one file (a signal and its connection, a const and its use).
	# Naming them keeps the next person from adding a fifth `func apply_edit`.
	var ambiguous: Array = []
	for entry in PARITY:
		var pair := entry as Array
		var hits := _files_matching(sources, str(pair[1]))
		if hits > 1:
			ambiguous.append("%s  (`%s` matches %d files)" % [str(pair[0]), str(pair[1]), hits])
	if not ambiguous.is_empty():
		print("  %d entr(ies) match more than one file -- prefer a token that exists once:"
			% ambiguous.size())
		for line in ambiguous:
			print("    %s" % line)
		print("")

	print("")
	if not missing.is_empty():
		for line in missing:
			printerr("  MISSING  %s" % line)
		printerr("[builder_parity] %d of %d features have no answer here"
			% [missing.size(), PARITY.size()])
		quit(1)
		return
	print("[builder_parity] all %d features answered, %d deliberately skipped"
		% [PARITY.size(), DELIBERATE.size()])
	quit(0)


func _found(sources: PackedStringArray, token: String) -> bool:
	return _files_matching(sources, token) > 0


## How many FILES carry this token.
##
## More than one means the entry is ambiguous: `func apply_edit` is defined in four files with
## four different jobs, so the entry stayed green with the one it named deleted. An ambiguous
## token is a gate that cannot fail for the reason it exists.
func _files_matching(sources: PackedStringArray, token: String) -> int:
	var n := 0
	for text in sources:
		if text.contains(token):
			n += 1
	return n


## Every `.gd` and `.guitkx` under the builder, read once.
func _all_sources() -> PackedStringArray:
	var out := PackedStringArray()
	for root in ROOTS:
		if FileAccess.file_exists(root):
			out.append(FileAccess.get_file_as_string(root))
			continue
		_walk(root, out)
	return out


func _walk(dir: String, out: PackedStringArray) -> void:
	var handle := DirAccess.open(dir)
	if handle == null:
		return
	for file in handle.get_files():
		if file.ends_with(".gd") or file.ends_with(".guitkx"):
			out.append(FileAccess.get_file_as_string(dir.path_join(file)))
	for sub in handle.get_directories():
		_walk(dir.path_join(sub), out)
