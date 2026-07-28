extends SceneTree
## 0.9.0 naming-loyalty codemod (plans/NAMING_LOYALTY_PROPOSAL.md). Rewrites a project's
## `.guitkx` and hand-written `.gd` sources from the pre-0.9 vocabulary to the 1:1-loyal-to-Godot
## names: shorthand tags -> official class names, snake_case V.* factories -> verbatim class
## names, React event aliases -> on<Signal>, invented style keys -> exact Godot names.
##
## Run from the project root (see MIGRATION-0.9.md):
##   godot --headless --path . --script res://addons/reactive_ui_toolkit/dev/migrate_0_9_0.gd            # apply
##   godot --headless --path . --script res://addons/reactive_ui_toolkit/dev/migrate_0_9_0.gd -- --dry-run
##   godot --headless --path . --script res://addons/reactive_ui_toolkit/dev/migrate_0_9_0.gd -- res://ui res://scenes
##
## What it does NOT decide for you (flagged in the report instead of guessed):
##   • `onChange` whose element can't be inferred from the surrounding code
##   • non-literal values for expand_h/expand_v/grow_*/fill (needs a hand-picked size flag/preset)
##   • `"rotation":` outside a style context (props were always radians; only STYLE rotation was degrees)
## Generated `.gd` siblings of a `.guitkx` are SKIPPED (they regenerate on the next compile), as are
## addons/, .git/, .godot/.

# ---- rename tables ------------------------------------------------------------

const TAG_RENAMES := {
	"VBox": "VBoxContainer", "HBox": "HBoxContainer", "Grid": "GridContainer",
	"Margin": "MarginContainer", "Panel": "PanelContainer", "Center": "CenterContainer",
	"Scroll": "ScrollContainer", "Tabs": "TabContainer", "RichText": "RichTextLabel",
}

## Old snake_case factory -> 0.9.0 class-name factory. Also used for lowercase TAGS
## (`<vbox>` was `V.vbox` by definition) -> the official PascalCase tag.
const FACTORY_RENAMES := {
	"control": "Control", "vbox": "VBoxContainer", "hbox": "HBoxContainer", "grid": "GridContainer",
	"margin": "MarginContainer", "panel": "PanelContainer", "center": "CenterContainer",
	"scroll": "ScrollContainer", "flow_h": "HFlowContainer", "flow_v": "VFlowContainer",
	"tabs": "TabContainer", "split_h": "HSplitContainer", "split_v": "VSplitContainer",
	"aspect": "AspectRatioContainer", "foldable": "FoldableContainer",
	"label": "Label", "rich_text": "RichTextLabel", "color_rect": "ColorRect",
	"texture_rect": "TextureRect", "nine_patch": "NinePatchRect",
	"h_separator": "HSeparator", "v_separator": "VSeparator",
	"button": "Button", "check_box": "CheckBox", "check_button": "CheckButton",
	"option_button": "OptionButton", "menu_button": "MenuButton", "link_button": "LinkButton",
	"texture_button": "TextureButton",
	"line_edit": "LineEdit", "text_edit": "TextEdit", "code_edit": "CodeEdit",
	"spin_box": "SpinBox", "h_slider": "HSlider", "v_slider": "VSlider",
	"progress_bar": "ProgressBar", "texture_progress": "TextureProgressBar",
	"color_picker": "ColorPicker", "color_picker_button": "ColorPickerButton",
	"audio": "AudioStreamPlayer", "video": "VideoStreamPlayer",
	"tab_bar": "TabBar", "item_list": "ItemList", "tree": "Tree", "menu_bar": "MenuBar",
}

## Unambiguous event renames (same signal on every element).
const EVENT_RENAMES := {
	"onClick": "onPressed", "onInput": "onTextChanged", "onSubmit": "onTextSubmitted",
	"onFocus": "onFocusEntered", "onBlur": "onFocusExited",
	"onPointerDown": "onButtonDown", "onPointerUp": "onButtonUp",
	"onPointerEnter": "onMouseEntered", "onPointerLeave": "onMouseExited",
	"onResize": "onResized",
}

## `onChange` was polymorphic — the replacement depends on the element (0.9.0 class name).
const ONCHANGE_BY_CLASS := {
	"LineEdit": "onTextChanged", "TextEdit": "onTextChanged", "CodeEdit": "onTextChanged",
	"HSlider": "onValueChanged", "VSlider": "onValueChanged", "SpinBox": "onValueChanged",
	"HScrollBar": "onValueChanged", "VScrollBar": "onValueChanged", "ProgressBar": "onValueChanged",
	"TextureProgressBar": "onValueChanged",
	"OptionButton": "onItemSelected", "ItemList": "onItemSelected", "Tree": "onItemSelected",
	"TabBar": "onTabChanged", "TabContainer": "onTabChanged",
	"Button": "onToggled", "CheckBox": "onToggled", "CheckButton": "onToggled",
	"ColorPicker": "onColorChanged", "ColorPickerButton": "onColorChanged",
}

## Simple quoted style-key renames (safe anywhere: none of these are Godot property names).
const STYLE_KEY_RENAMES := {
	"min_size": "custom_minimum_size",
	"clip": "clip_contents", "tooltip": "tooltip_text", "pivot": "pivot_offset",
	"outline_color": "font_outline_color",
	"pad": "content_margin_all", "border_width": "border_width_all",
	"corner_radius": "corner_radius_all",
}

## Old size-flag value strings -> Godot constant expression.
const SIZE_FLAG_VALUES := {
	"fill": "Control.SIZE_FILL", "expand": "Control.SIZE_EXPAND",
	"expand_fill": "Control.SIZE_EXPAND_FILL", "grow": "Control.SIZE_EXPAND_FILL",
	"center": "Control.SIZE_SHRINK_CENTER", "shrink_center": "Control.SIZE_SHRINK_CENTER",
	"begin": "Control.SIZE_SHRINK_BEGIN", "shrink_begin": "Control.SIZE_SHRINK_BEGIN",
	"start": "Control.SIZE_SHRINK_BEGIN",
	"end": "Control.SIZE_SHRINK_END", "shrink_end": "Control.SIZE_SHRINK_END",
}

const SKIP_DIRS := ["addons", ".git", ".godot", "node_modules"]

var _dry := false
var _changed_files: Array = []
var _flags: Array = []   # { file, line, msg }
var _rx: Dictionary = {}

func _initialize() -> void:
	var roots: Array = []
	for a in OS.get_cmdline_user_args():
		if a == "--dry-run":
			_dry = true
		elif str(a).begins_with("res://"):
			roots.append(str(a))
	if roots.is_empty():
		roots = ["res://"]
	_compile_patterns()
	for r in roots:
		_walk(r)
	_report()
	quit(0)

func _compile_patterns() -> void:
	# Tag patterns demand a markup-shaped tail (whitespace, `>`, or `/`), so a comparison in
	# embedded GDScript (`i<tree.size()`, `a<label:`) can never be rewritten.
	_rx["tag"] = _mk("(</?)(%s)\\b(?=[\\s/>])" % "|".join(TAG_RENAMES.keys()))
	_rx["ltag"] = _mk("(</?)(%s)\\b(?=[\\s/>])" % "|".join(FACTORY_RENAMES.keys()))
	# \b alone misses `V.` preceded by a literal \t/\n ESCAPE inside a GDScript string (the 't'
	# is a word char) — sources that build component code as strings (HMR tests, generators) hit
	# this, so allow an escape-sequence lookbehind too.
	_rx["factory"] = _mk("(?:\\b|(?<=\\\\t)|(?<=\\\\n))V\\.(%s)\\(" % "|".join(FACTORY_RENAMES.keys()))
	_rx["event"] = _mk("\\b(%s)\\b" % "|".join(EVENT_RENAMES.keys()))
	_rx["onchange"] = _mk("\\bonChange\\b")
	_rx["stylekey"] = _mk("\"(%s)\"\\s*:" % "|".join(STYLE_KEY_RENAMES.keys()))
	_rx["margin"] = _mk("\"margin\"\\s*:\\s*([^,}\\n]+?)(\\s*[,}\\n])")
	_rx["expand"] = _mk("\"(expand_h|expand_v)\"\\s*:\\s*(true|false)")
	_rx["growalign"] = _mk("\"(grow_h|grow_v|h_align|v_align)\"\\s*:\\s*(\"[a-z_]+\"|\\d+)")
	_rx["fillkey"] = _mk("\"fill\"\\s*:\\s*(true|false)")
	_rx["rotation"] = _mk("\"rotation\"\\s*:\\s*([^,}\\n]+?)(\\s*[,}\\n])")
	_rx["colorkey"] = _mk("\"color\"\\s*:")
	# leftover old names that need a human (non-literal values, unresolvable onChange)
	_rx["flag_style"] = _mk("\"(expand_h|expand_v|grow_h|grow_v|h_align|v_align|fill|min_size|pad|border_width|corner_radius|margin|clip|tooltip|pivot|outline_color)\"\\s*:")

func _mk(pattern: String) -> RegEx:
	var r := RegEx.new()
	var err := r.compile(pattern)
	assert(err == OK)
	return r

func _walk(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		push_error("[migrate 0.9] cannot open %s" % path)
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		var p := path.path_join(name)
		if d.current_is_dir():
			if not name.begins_with(".") and not SKIP_DIRS.has(name):
				_walk(p)
		elif name.ends_with(".guitkx"):
			_migrate_file(p, true)
		elif name.ends_with(".gd") and not name.ends_with(".gen.gd"):
			# a generated sibling regenerates from its .guitkx on the next compile — skip it
			if not FileAccess.file_exists(p.substr(0, p.length() - 3) + ".guitkx"):
				_migrate_file(p, false)
		name = d.get_next()
	d.list_dir_end()

func _migrate_file(path: String, is_guitkx: bool) -> void:
	var src := FileAccess.get_file_as_string(path)
	if src.is_empty():
		return
	var out := src

	# 1. tags: PascalCase shorthands, then lowercase element tags. Applied to .gd too —
	# markup embedded in GDScript strings (tests, generators, compile() callers) is a real
	# pattern, and the `<`-anchored patterns can't collide with comparisons (`a < b` has a space).
	out = _sub2(_rx["tag"], out, func(m): return m.get_string(1) + TAG_RENAMES[m.get_string(2)])
	if is_guitkx or out.contains("<"):
		out = _sub2(_rx["ltag"], out, func(m): return m.get_string(1) + FACTORY_RENAMES[m.get_string(2)])

	# 2. factories (both file kinds — .guitkx embed GDScript).
	out = _sub2(_rx["factory"], out, func(m): return "V." + FACTORY_RENAMES[m.get_string(1)] + "(")

	# 3. events: unambiguous renames, then per-element onChange.
	out = _sub2(_rx["event"], out, func(m): return EVENT_RENAMES[m.get_string(1)])
	out = _resolve_onchange(path, out)

	# 4. style keys.
	out = _sub2(_rx["stylekey"], out, func(m): return "\"%s\":" % STYLE_KEY_RENAMES[m.get_string(1)])
	out = _sub2(_rx["margin"], out, func(m):
		var v: String = m.get_string(1)
		return "\"margin_left\": %s, \"margin_top\": %s, \"margin_right\": %s, \"margin_bottom\": %s%s" % [v, v, v, v, m.get_string(2)])
	out = _sub2(_rx["expand"], out, func(m):
		var key := "size_flags_horizontal" if m.get_string(1) == "expand_h" else "size_flags_vertical"
		var val := "Control.SIZE_EXPAND_FILL" if m.get_string(2) == "true" else "Control.SIZE_FILL"
		return "\"%s\": %s" % [key, val])
	out = _sub2(_rx["growalign"], out, func(m):
		var key := "size_flags_horizontal" if m.get_string(1) in ["grow_h", "h_align"] else "size_flags_vertical"
		var raw: String = m.get_string(2)
		if raw.begins_with("\""):
			var word := raw.substr(1, raw.length() - 2)
			if SIZE_FLAG_VALUES.has(word):
				return "\"%s\": %s" % [key, SIZE_FLAG_VALUES[word]]
			return m.get_string(0)   # unknown word — leave; flagged below
		return "\"%s\": %s" % [key, raw])
	out = _sub2(_rx["fillkey"], out, func(m):
		var preset := "Control.PRESET_FULL_RECT" if m.get_string(1) == "true" else "Control.PRESET_TOP_LEFT"
		return "\"anchors_preset\": %s" % preset)
	# rotation: STYLE rotation was degrees; 0.9.0 is radians (Godot's own semantics). Wrap the
	# old value in deg_to_rad(...) — behavior-preserving. Only in style-carrying lines.
	out = _rewrite_in_style_lines(out, _rx["rotation"], func(m):
		var v: String = m.get_string(1)
		if v.strip_edges().begins_with("deg_to_rad"):
			return m.get_string(0)
		return "\"rotation\": deg_to_rad(%s)%s" % [v, m.get_string(2)])
	# "color" is a real prop on ColorRect — rename to font_color ONLY on style-carrying lines.
	out = _rewrite_in_style_lines(out, _rx["colorkey"], func(_m): return "\"font_color\":")

	# 5. flag whatever survived (non-literal values, unresolved keys).
	_flag_leftovers(path, out)

	if out == src:
		return
	_changed_files.append(path)
	if not _dry:
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string(out)
		f.close()

## RegEx.sub with a callback (GDScript RegEx has no callback sub — do it manually, right to left).
func _sub2(rx: RegEx, text: String, cb: Callable) -> String:
	var matches := rx.search_all(text)
	for i in range(matches.size() - 1, -1, -1):
		var m: RegExMatch = matches[i]
		var rep: String = cb.call(m)
		text = text.substr(0, m.get_start()) + rep + text.substr(m.get_end())
	return text

## Apply a rewrite only inside lines that mention `style` (style={...}, "style":, active_style…).
func _rewrite_in_style_lines(text: String, rx: RegEx, cb: Callable) -> String:
	var lines := text.split("\n")
	for i in lines.size():
		if lines[i].contains("style"):
			lines[i] = _sub2(rx, lines[i], cb)
	return "\n".join(lines)

## onChange: resolve per element by scanning BACKWARD from the match for the nearest opening
## `<Tag` (markup) or `V.Factory(` (code) — whichever is closer. Unresolvable -> flag.
func _resolve_onchange(path: String, text: String) -> String:
	while true:
		var m := (_rx["onchange"] as RegEx).search(text)
		if m == null:
			break
		var before := text.substr(0, m.get_start())
		var cls := ""
		var tag_pos := -1
		var tag_rx := _mk("<([A-Z][A-Za-z0-9_]*)[^<>]*$")
		var tm := tag_rx.search(before)
		if tm != null:
			cls = tm.get_string(1)
			tag_pos = tm.get_start()
		var fac_rx := _mk("V\\.([A-Za-z_][A-Za-z0-9_]*)\\((?:[^()]|\\([^()]*\\))*$")
		var fm := fac_rx.search(before)
		if fm != null and fm.get_start() > tag_pos:
			cls = fm.get_string(1)
		if ONCHANGE_BY_CLASS.has(cls):
			text = before + ONCHANGE_BY_CLASS[cls] + text.substr(m.get_end())
		else:
			# leave it, but disarm the loop by flagging + renaming to a marker comment-safe token
			_flags.append({ "file": path, "line": _line_of(text, m.get_start()),
				"msg": "onChange could not be resolved (element '%s' unknown) -- replace with the control's real signal (onToggled/onItemSelected/onValueChanged/onTextChanged/onTabChanged)" % cls })
			text = before + "onChange_MIGRATE_ME" + text.substr(m.get_end())
	return text.replace("onChange_MIGRATE_ME", "onChange")

func _flag_leftovers(path: String, text: String) -> void:
	for m in (_rx["flag_style"] as RegEx).search_all(text):
		_flags.append({ "file": path, "line": _line_of(text, m.get_start()),
			"msg": "style key '%s' still present with a non-literal value -- rename by hand (see MIGRATION-0.9.md style table)" % m.get_string(1) })

func _line_of(text: String, pos: int) -> int:
	return text.count("\n", 0, pos) + 1 if pos > 0 else 1

func _report() -> void:
	var mode := "DRY RUN — no files written" if _dry else "APPLIED"
	print("\n[migrate 0.9] %s: %d file(s) rewritten" % [mode, _changed_files.size()])
	for f in _changed_files:
		print("  ~ %s" % f)
	if _flags.is_empty():
		print("[migrate 0.9] no manual-review sites — done. Recompile your .guitkx (open the project in the editor, or run tests/guitkx_build.gd headless).")
	else:
		print("[migrate 0.9] %d site(s) need a human:" % _flags.size())
		for fl in _flags:
			print("  ! %s:%d — %s" % [fl["file"], fl["line"], fl["msg"]])
	var rep := FileAccess.open("res://migrate_0_9_0_report.txt", FileAccess.WRITE)
	if rep != null:
		rep.store_string("migrate 0.9.0 — %s\nchanged (%d):\n%s\nflags (%d):\n%s\n" % [
			mode, _changed_files.size(), "\n".join(PackedStringArray(_changed_files)),
			_flags.size(),
			"\n".join(PackedStringArray(_flags.map(func(fl): return "%s:%d %s" % [fl["file"], fl["line"], fl["msg"]])))])
		rep.close()
		print("[migrate 0.9] report written to res://migrate_0_9_0_report.txt")
