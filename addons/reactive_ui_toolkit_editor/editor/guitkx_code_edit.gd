@tool
class_name GuitkxCodeEdit
extends CodeEdit
## The editing surface for a .guitkx buffer. Self-configures editing UX, assigns the .guitkx
## SyntaxHighlighter, owns a dedicated diagnostics gutter, and offers minimal tag completion. All of
## it reads the reactive_ui_toolkit_editor/* Project Settings so each feature honours its toggle.

## Emitted when the user clicks the diagnostics gutter icon on a diagnosed line.
signal gutter_diagnostic_clicked(line: int, record: Variant)

## Emitted when Ctrl+click resolves a component tag to its declaration (parity plan G1). The view
## owns navigation (open the file, place the caret); the widget only resolves.
signal definition_requested(path: String, offset: int)

var diag_gutter: int = -1

## Per-file buffer state (M2/G16 — one GuitkxCodeEdit per open file, so undo history, caret,
## scroll, and dirty/conflict state all survive file switches; the view reads/writes these).
var file_path: String = ""
var dirty := false
var detached := false           # the source file was deleted/moved away on disk
var loaded_mtime := 0           # disk mtime the buffer was loaded from / last saved to

## Editor font zoom (E11), shared across all open editors and the session.
static var zoom_font_size := 0  # 0 = theme default

var _highlighter
var _theme_source: Control
var _line_diags: Dictionary = {}  # line (int) -> Array of diagnostic records (from the view)

# Signature help (G4): a hand-drawn strip above the caret while it sits inside an event-handler
# lambda's parameter list. Preload (not the global class name): cold class caches.
const SignatureScript := preload("res://addons/reactive_ui_toolkit_editor/lsp/guitkx_signature.gd")
# BY PATH, NOT BY GLOBAL NAME. This widget is reused by the BUILDER's source pane and its island
# editor, and everything under `builder/` reaches its dependencies through preloads for a stated
# reason: `ProjectSettings.save()` truncates the editor class cache to what the running process
# loaded, so a global name can stop resolving mid-session. Naming five of them here put the
# builder's own availability back inside the hazard it was written to avoid.
const CompletionScript := preload("res://addons/reactive_ui_toolkit_editor/lsp/guitkx_completion.gd")
const ContextScript := preload("res://addons/reactive_ui_toolkit_editor/lsp/guitkx_context.gd")
const HoverScript := preload("res://addons/reactive_ui_toolkit_editor/lsp/guitkx_hover.gd")
const WorkspaceScript := preload("res://addons/reactive_ui_toolkit_editor/lsp/guitkx_workspace.gd")
const HighlighterScript := preload("res://addons/reactive_ui_toolkit_editor/editor/guitkx_code_highlighter.gd")
# M3: the native embedded-GDScript tier. The bridge feature-detects the reactive_ui_toolkit_analyzer
# GDExtension; instance() is null when it is absent and every call site degrades to markup-only.
const BridgeScript := preload("res://addons/reactive_ui_toolkit_editor/lsp/guitkx_analyzer_bridge.gd")
var _sig_panel: PanelContainer
var _sig_label: RichTextLabel

func _init() -> void:
	# Pure CodeEdit state — safe in every context (editor, headless tests), so the widget is never
	# half-configured (a -1 diag_gutter would make the diagnostics renderer index out of bounds).
	configure()

func _ready() -> void:
	if not Engine.is_editor_hint():
		return

	# Syntax highlighting (own SyntaxHighlighter route). Always assigned; the highlighter honours
	# KEY_HIGHLIGHTING per line, so the toggle applies live without a plugin reload. Editor-only:
	# the highlighter reads EditorSettings theme colours.
	_highlighter = HighlighterScript.new()
	syntax_highlighter = _highlighter

	# Refresh highlight colours when the editor theme changes.
	_theme_source = EditorInterface.get_base_control()
	if _theme_source != null and not _theme_source.theme_changed.is_connected(_on_theme_changed):
		_theme_source.theme_changed.connect(_on_theme_changed)

## Applies the whole editing substrate: indentation, delimiters, brace pairs, gutters, view
## comforts, completion triggers, and hover. Pure CodeEdit state with no editor-singleton
## dependency, so the headless suite instantiates a GuitkxCodeEdit and asserts this directly
## (tests/guitkx_editor_test.gd).
func configure() -> void:
	# Indentation — MUST match the formatter's output (guitkx_formatter.gd defaults: spaces, 2),
	# or live typing and format-on-save fight each other and every save produces mixed indent.
	indent_use_spaces = true
	indent_size = 2
	indent_automatic = true
	draw_tabs = true

	if not has_comment_delimiter("#"):
		add_comment_delimiter("#", "", true)
	if not has_string_delimiter("\""):
		add_string_delimiter("\"", "\"")
	if not has_string_delimiter("'"):
		add_string_delimiter("'", "'")

	# CodeEdit already ships the default { } ( ) [ ] " " ' ' auto-close pairs; re-adding them throws
	# "auto brace completion open key '...' already exists". `<` -> `>` is ours to add for markup.
	auto_brace_completion_enabled = true
	auto_brace_completion_highlight_matching = true
	if not auto_brace_completion_pairs.has("<"):
		add_auto_brace_completion_pair("<", ">")

	# Gutters + view comforts, mirroring the built-in script editor's defaults.
	gutters_draw_line_numbers = true
	gutters_draw_bookmarks = true   # E14: Ctrl+B toggles, Ctrl+Shift+B cycles
	line_folding = true
	gutters_draw_fold_gutter = true
	highlight_current_line = true
	highlight_all_occurrences = true
	minimap_draw = true
	caret_blink = true
	scroll_smooth = true
	scroll_past_end_of_file = true
	# One ruler at the formatter's print width.
	line_length_guidelines = [100]

	# Diagnostics gutter (icon type), to the right of the built-in gutters. Guarded so a repeat
	# configure() (plugin reload, re-open) never allocates a duplicate gutter.
	if diag_gutter == -1:
		diag_gutter = get_gutter_count()
		add_gutter(diag_gutter)
		set_gutter_type(diag_gutter, TextEdit.GUTTER_TYPE_ICON)
		set_gutter_width(diag_gutter, 24)
		set_gutter_clickable(diag_gutter, true)
	if not gutter_clicked.is_connected(_on_gutter_clicked):
		gutter_clicked.connect(_on_gutter_clicked)

	# Markup completion. Triggers: `<` (tags), `@` (directives), space (attributes), `.` (builtin
	# members like Color./Vector2.), `"` (attribute values + style-dict keys); the context
	# classifier decides what to offer per caret position. KEY_COMPLETION is honoured live.
	code_completion_enabled = true
	code_completion_prefixes = PackedStringArray(["<", "@", " ", ".", "\""])

	# Markup hover: Godot 4.4+ CodeEdit emits `symbol_hovered` while the mouse rests on a symbol —
	# but ONLY when `symbol_tooltip_on_hover` is set; without it the signal never fires and hover is
	# dead. Both are 4.4+, guarded so older builds no-op.
	if "symbol_tooltip_on_hover" in self:
		symbol_tooltip_on_hover = true
	if has_signal("symbol_hovered") and not is_connected("symbol_hovered", _on_symbol_hovered):
		connect("symbol_hovered", _on_symbol_hovered)

	# Go-to-definition (G1): Ctrl+hover validates component tags as lookup words (underline +
	# pointer), Ctrl+click resolves through the workspace index and asks the view to navigate.
	symbol_lookup_on_click = true
	if not symbol_validate.is_connected(_on_symbol_validate):
		symbol_validate.connect(_on_symbol_validate)
	if not symbol_lookup.is_connected(_on_symbol_lookup):
		symbol_lookup.connect(_on_symbol_lookup)

	# Signature help (G4): recompute on every edit AND caret move — entering the param list shows
	# it, leaving it (or Esc) hides it, so no separate dismissal bookkeeping can go stale.
	if not text_changed.is_connected(_signature_refresh):
		text_changed.connect(_signature_refresh)
	if not caret_changed.is_connected(_signature_refresh):
		caret_changed.connect(_signature_refresh)
	if not focus_exited.is_connected(_signature_hide):
		focus_exited.connect(_signature_hide)

func _exit_tree() -> void:
	if _theme_source != null and _theme_source.theme_changed.is_connected(_on_theme_changed):
		_theme_source.theme_changed.disconnect(_on_theme_changed)

func _on_theme_changed() -> void:
	if _highlighter != null:
		_highlighter.update_colors()
		queue_redraw()

## Signature help (G4): pure logic in GuitkxSignature; this is only the strip. Placed ABOVE the
## caret line so it never covers what the user is typing, and never focusable — keystrokes stay
## in the editor. Honors the completion toggle (parameter hints are typing intelligence).
func _signature_refresh() -> void:
	if not RuitkEditorSettings.is_enabled(RuitkEditorSettings.KEY_COMPLETION):
		_signature_hide()
		return
	var t := get_text()
	var off := ContextScript.offset_of(t, get_caret_line(), get_caret_column())
	var sig: Dictionary = SignatureScript.signature_at(t, off)
	if sig.is_empty():
		# M3: signature help inside embedded GDScript calls, through the analyzer. Adapted to the
		# same {signal, params, active} shape the markup tier feeds the strip.
		var bridge = BridgeScript.instance()
		if bridge != null:
			var ah: Dictionary = bridge.signature_help(file_path, t, off)
			var sigs: Array = ah.get("signatures", [])
			if not sigs.is_empty():
				var active_sig := clampi(int(ah.get("active_signature", 0)), 0, sigs.size() - 1)
				var info := sigs[active_sig] as Dictionary
				var label := str(info.get("label", ""))
				var params: Array = []
				for p in info.get("params", []):
					params.append(str((p as Dictionary).get("label", "")))
				sig = {
					"signal": label.get_slice("(", 0),
					"params": params,
					"active": int(ah.get("active_parameter", 0)),
				}
	if sig.is_empty():
		_signature_hide()
		return
	if _sig_panel == null:
		_sig_panel = PanelContainer.new()
		_sig_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_sig_panel.focus_mode = Control.FOCUS_NONE
		_sig_label = RichTextLabel.new()
		_sig_label.bbcode_enabled = true
		_sig_label.fit_content = true
		_sig_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		_sig_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_sig_label.focus_mode = Control.FOCUS_NONE
		_sig_panel.add_child(_sig_label)
		add_child(_sig_panel)
	var parts: Array = []
	var params: Array = sig.get("params", [])
	for pi in params.size():
		var p := str(params[pi])
		parts.append(("[b]%s[/b]" % p) if pi == int(sig.get("active", 0)) else p)
	_sig_label.text = "[code]%s(%s)[/code]" % [str(sig.get("signal", "")), ", ".join(PackedStringArray(parts))]
	_sig_panel.visible = true
	_sig_panel.reset_size()
	var pos := get_caret_draw_pos()
	_sig_panel.position = Vector2(
		clampf(pos.x, 0.0, maxf(0.0, size.x - _sig_panel.size.x)),
		maxf(0.0, pos.y - get_line_height() - _sig_panel.size.y - 2.0))

func _signature_hide() -> void:
	if _sig_panel != null:
		_sig_panel.visible = false

func signature_visible() -> bool:
	return _sig_panel != null and _sig_panel.visible

## Keyboard verbs: Ctrl+/ comment toggle (E12), Ctrl+wheel / Ctrl+=/-/0 zoom (E11), Alt+Up/Down
## move lines + Ctrl+Shift+D/K duplicate/delete + Ctrl(+Shift)+B bookmarks (E14), Enter splitting
## a `>|</` tag pair with an indented middle line (G30), and Enter/Tab confirming a completion
## with snippet-aware caret placement (G20).
func _gui_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k != null and k.pressed and not k.echo and k.keycode == KEY_ESCAPE and signature_visible():
		_signature_hide()
		accept_event()
		return
	if k != null and k.pressed and not k.echo and k.alt_pressed and not k.is_command_or_control_pressed():
		match k.keycode:
			KEY_UP:
				move_lines_up()
				accept_event()
			KEY_DOWN:
				move_lines_down()
				accept_event()
		return
	if k != null and k.pressed and not k.echo and k.is_command_or_control_pressed():
		match k.keycode:
			KEY_SLASH, KEY_KP_DIVIDE:
				toggle_comment()
				accept_event()
			KEY_EQUAL, KEY_KP_ADD:
				zoom_step(1)
				accept_event()
			KEY_MINUS, KEY_KP_SUBTRACT:
				zoom_step(-1)
				accept_event()
			KEY_0, KEY_KP_0:
				set_zoom(0)
				accept_event()
			KEY_D:
				if k.shift_pressed:
					duplicate_lines()
					accept_event()
			KEY_K:
				if k.shift_pressed:
					delete_lines()
					accept_event()
			KEY_B:
				if k.shift_pressed:
					goto_next_bookmark()
				else:
					toggle_bookmark()
				accept_event()
		return
	if k != null and k.pressed and not k.echo \
			and (k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER or k.keycode == KEY_TAB) \
			and get_code_completion_selected_index() >= 0:
		confirm_with_snippet_caret()
		accept_event()
		return
	if k != null and k.pressed and not k.echo and not k.shift_pressed \
			and (k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER):
		if handle_enter_between_tags():
			accept_event()
			return
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.ctrl_pressed:
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_step(1)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_step(-1)
			accept_event()

## G20: confirm the selected completion, then step the caret back inside a trailing empty pair —
## `text=""` and `on_pressed={}` land ready to type the value, `@if ()` ready for the condition.
func confirm_with_snippet_caret() -> void:
	var idx := get_code_completion_selected_index()
	if idx < 0:
		return
	var opt: Dictionary = get_code_completion_option(idx)
	confirm_code_completion()
	var ins := str(opt.get("insert_text", ""))
	if ins.ends_with("\"\"") or ins.ends_with("{}") or ins.ends_with("()"):
		set_caret_column(maxi(0, get_caret_column() - 1))

## G30: Enter with the caret exactly between `>` and `</` splits the pair onto three lines with an
## indented middle, VS Code style. Returns false (let Enter behave normally) anywhere else.
func handle_enter_between_tags() -> bool:
	if has_selection() or get_caret_count() > 1:
		return false
	var line := get_caret_line()
	var col := get_caret_column()
	var lt := get_line(line)
	if col == 0 or col > lt.length():
		return false
	if lt[col - 1] != ">" or not lt.substr(col).begins_with("</"):
		return false
	var base := lt.substr(0, lt.length() - lt.strip_edges(true, false).length())
	var ind := " ".repeat(indent_size) if indent_use_spaces else "\t"
	begin_complex_operation()
	insert_text_at_caret("\n" + base + ind + "\n" + base)
	end_complex_operation()
	set_caret_line(line + 1)
	set_caret_column((base + ind).length())
	return true

## E14 bookmarks, over CodeEdit's built-in bookmark gutter.
func toggle_bookmark() -> void:
	var l := get_caret_line()
	set_line_as_bookmarked(l, not is_line_bookmarked(l))

func goto_next_bookmark() -> void:
	var marks: PackedInt32Array = get_bookmarked_lines()
	if marks.is_empty():
		return
	var cur := get_caret_line()
	for m in marks:
		if int(m) > cur:
			set_caret_line(int(m))
			return
	set_caret_line(int(marks[0]))  # wrap to the first bookmark

func zoom_step(dir: int) -> void:
	var base := get_theme_font_size("font_size")
	var cur := zoom_font_size if zoom_font_size > 0 else base
	set_zoom(clampi(cur + dir, 8, 48))

## `size` 0 resets to the theme default. Static-shared: every open editor follows.
func set_zoom(size: int) -> void:
	zoom_font_size = size
	apply_zoom()

func apply_zoom() -> void:
	if zoom_font_size > 0:
		add_theme_font_size_override("font_size", zoom_font_size)
	else:
		remove_theme_font_size_override("font_size")

func toggle_comment() -> void:
	var from_line := get_caret_line()
	var to_line := from_line
	if has_selection():
		from_line = get_selection_from_line()
		to_line = get_selection_to_line()
		# A selection ending at column 0 shouldn't drag the next line into the toggle.
		if to_line > from_line and get_selection_to_column() == 0:
			to_line -= 1
	var all_commented := true
	for ln in range(from_line, to_line + 1):
		var t := get_line(ln).strip_edges()
		if t != "" and not t.begins_with("#"):
			all_commented = false
			break
	begin_complex_operation()
	for ln in range(from_line, to_line + 1):
		var line := get_line(ln)
		if line.strip_edges() == "":
			continue
		if all_commented:
			var idx := line.find("#")
			var rest := line.substr(idx + 1)
			if rest.begins_with(" "):
				rest = rest.substr(1)
			set_line(ln, line.substr(0, idx) + rest)
		else:
			var ws := line.length() - line.strip_edges(true, false).length()
			set_line(ln, line.substr(0, ws) + "# " + line.substr(ws))
	end_complex_operation()

## Replaces the whole buffer as ONE undoable edit. Assigning `.text` clears the undo history —
## with format-on-save enabled that meant every Save destroyed Ctrl+Z (parity plan G33). The
## caret is preserved (clamped to the new bounds).
func set_text_undoable(new_text: String) -> void:
	var l := get_caret_line()
	var c := get_caret_column()
	begin_complex_operation()
	select_all()
	delete_selection()
	insert_text_at_caret(new_text)
	end_complex_operation()
	set_caret_line(mini(l, maxi(0, get_line_count() - 1)))
	set_caret_column(mini(c, get_line(get_caret_line()).length()))

## Fade the given lines (a set: line -> true) as unreachable code. [BUG-V6]
func set_dim_lines(lines: Dictionary) -> void:
	if _highlighter != null:
		_highlighter.set_dim_lines(lines)
		queue_redraw()

func _on_gutter_clicked(line: int, gutter: int) -> void:
	if gutter == diag_gutter:
		gutter_diagnostic_clicked.emit(line, get_line_gutter_metadata(line, diag_gutter))

# Context-aware markup completion: tag names (host + user components), per-tag attributes / events,
# and directives. The logic lives in the UI-free GuitkxCompletion provider (unit-tested headlessly);
# this override just maps its items onto CodeEdit options. Attribute-value / embedded contexts yield
# nothing in Phase 1 (the analyzer layer owns those). [plans/GODOT_ANALYZER_INTEGRATION_PLAN.md §7]
func _request_code_completion(_force: bool) -> void:
	if not RuitkEditorSettings.is_enabled(RuitkEditorSettings.KEY_COMPLETION):
		return
	var text := get_text()
	var off := ContextScript.offset_of(text, get_caret_line(), get_caret_column())
	var items := CompletionScript.for_caret(text, off, file_path)
	var seen := {}
	for it in items:
		seen[str(it["display"])] = true
		add_code_completion_option(_kind_of(str(it["kind"])), str(it["display"]), str(it["insert"]))
	# M3: type-aware items from the native analyzer for embedded GDScript ({expr}/setup). The
	# bridge returns [] when the caret is in markup or the extension is absent, so this merge is
	# structurally a no-op outside its domain. Analyzer items dedupe against the static tier by
	# display (the hook stubs exist in both).
	var bridge = BridgeScript.instance()
	if bridge != null:
		for ai in bridge.completions(file_path, text, off):
			var ad := ai as Dictionary
			var label := str(ad.get("label", ""))
			var detail := str(ad.get("detail", ""))
			var display := label if detail == "" else "%s  %s" % [label, detail]
			if label == "" or seen.has(label) or seen.has(display):
				continue
			seen[label] = true
			var insert := str(ad.get("insert_text", "")) if str(ad.get("insert_text", "")) != "" else label
			add_code_completion_option(_analyzer_kind_of(str(ad.get("kind", ""))), display, insert)
	if seen.is_empty():
		return
	update_code_completion_options(true)

# Analyzer CompletionKind (snake_case) -> CodeEdit option kind.
func _analyzer_kind_of(kind: String) -> int:
	match kind:
		"function":
			return CodeEdit.KIND_FUNCTION
		"variable":
			return CodeEdit.KIND_VARIABLE
		"constant":
			return CodeEdit.KIND_CONSTANT
		"class":
			return CodeEdit.KIND_CLASS
		"signal":
			return CodeEdit.KIND_SIGNAL
		"member", "property":
			return CodeEdit.KIND_MEMBER
		"enum":
			return CodeEdit.KIND_ENUM
		_:
			return CodeEdit.KIND_PLAIN_TEXT

func _kind_of(kind: String) -> int:
	match kind:
		CompletionScript.CLASS:
			return CodeEdit.KIND_CLASS
		CompletionScript.SIGNAL:
			return CodeEdit.KIND_SIGNAL
		CompletionScript.MEMBER:
			return CodeEdit.KIND_MEMBER
		_:
			return CodeEdit.KIND_PLAIN_TEXT

const HOOKS_GD := "res://addons/reactive_ui_toolkit/core/hooks.gd"

func _on_symbol_validate(symbol: String) -> void:
	if WorkspaceScript.is_component(symbol) or HoverScript.HOOKS.has(symbol):
		set_symbol_lookup_word_as_valid(true)
		return
	# M3: an identifier inside a mapped embedded span is navigable through the analyzer. The check
	# is map-only (hash-cached virtual doc, no analyzer query) so ctrl+hover stays cheap.
	var bridge = BridgeScript.instance()
	if bridge != null:
		var text := get_text()
		var pos := get_line_column_at_pos(get_local_mouse_pos())
		var off := ContextScript.offset_of(text, pos.y, pos.x)
		set_symbol_lookup_word_as_valid(bridge.is_embedded_offset(file_path, text, off))
		return
	set_symbol_lookup_word_as_valid(false)

func _on_symbol_lookup(symbol: String, line: int, column: int) -> void:
	var hit := WorkspaceScript.lookup(symbol)
	if not hit.is_empty():
		definition_requested.emit(str(hit.get("path", "")), int(hit.get("offset", 0)))
		return
	# Hooks jump to their implementation in core/hooks.gd (G27 — the VS Code server chains
	# through virtual-doc stubs; natively a name scan suffices, hooks.gd functions are camelCase).
	if HoverScript.HOOKS.has(symbol) and FileAccess.file_exists(HOOKS_GD):
		var src := FileAccess.get_file_as_string(HOOKS_GD)
		var at := src.find("func %s(" % symbol)
		if at >= 0:
			definition_requested.emit(HOOKS_GD, at + 5)
			return
	# M3: embedded-GDScript definitions through the analyzer — same-file hits land back in this
	# buffer (remapped); cross-file hits carry a real res://*.gd path the view routes to Godot's
	# script editor.
	var bridge = BridgeScript.instance()
	if bridge != null:
		var text := get_text()
		var hits: Array = bridge.goto_definition(file_path, text, ContextScript.offset_of(text, line, column))
		if not hits.is_empty():
			var first := hits[0] as Dictionary
			definition_requested.emit(str(first.get("path", "")), int(first.get("offset", 0)))

## Diagnostics for the current buffer, keyed by line — folded into the hover card so the message
## (and its did-you-mean) is readable without clicking the gutter. [field ask]
func set_line_diagnostics(by_line: Dictionary) -> void:
	_line_diags = by_line

# Markup hover: GuitkxHover owns the (tested) logic; the text stored in tooltip_text is raw
# Markdown, rendered rich by _make_custom_tooltip at show time (no stale-tooltip double delay —
# the previous native-tooltip path often needed a second hover pass to display anything).
func _on_symbol_hovered(_symbol: String, line: int, column: int) -> void:
	if not RuitkEditorSettings.is_enabled(RuitkEditorSettings.KEY_HOVER):
		tooltip_text = ""
		return
	var text := get_text()
	var off := ContextScript.offset_of(text, line, column)
	var md := HoverScript.for_caret(text, off)
	# M3: type-aware hover for embedded GDScript — the inferred type/signature line leads, engine
	# docs follow. Markup hover keeps priority (a tag is a tag); the analyzer only fills the gap.
	if md == "":
		var bridge = BridgeScript.instance()
		if bridge != null:
			var h: Dictionary = bridge.hover(file_path, text, off)
			var ty := str(h.get("ty_label", ""))
			if ty != "":
				md = "**`%s`**" % ty
				var doc := str(h.get("doc", ""))
				if doc != "":
					md += "\n\n" + doc
	tooltip_text = compose_hover(md, line)

## Prepend the hovered line's diagnostics (message includes any did-you-mean) to the symbol card.
func compose_hover(symbol_md: String, line: int) -> String:
	var parts: Array = []
	for rec in _line_diags.get(line, []):
		if rec is Dictionary:
			parts.append("**%s** `%s` — %s" % [
				str(rec.get("severity", "error")).to_upper(), str(rec.get("code", "")),
				str(rec.get("message", ""))])
	if symbol_md != "":
		parts.append(symbol_md)
	return "\n\n".join(parts)

## Rich tooltip: `for_text` is the raw Markdown from _on_symbol_hovered.
func _make_custom_tooltip(for_text: String) -> Object:
	if for_text.strip_edges().is_empty():
		return null
	var rtl := RichTextLabel.new()
	rtl.bbcode_enabled = true
	rtl.fit_content = true
	rtl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rtl.custom_minimum_size = Vector2(480, 0)
	rtl.text = HoverScript.md_to_bbcode(for_text)
	return rtl
