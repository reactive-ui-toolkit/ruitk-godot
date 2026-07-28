@tool
class_name GuitkxCodeHighlighter
extends SyntaxHighlighter
## SyntaxHighlighter for a .guitkx CodeEdit. Overrides _get_line_syntax_highlighting(line) to paint
## the line from GuitkxTokenizer spans, sourcing colours from the user's editor theme so it always
## matches the GDScript editor. Colours are refreshed by the owning CodeEdit on `theme_changed`
## (see guitkx_code_edit.gd) — this class holds no signal connections of its own, keeping its
## lifetime trivial.
##
## Embedded `{expr}` regions sub-highlight (G11): the tokenizer recurses inside braces in gd_mode,
## so GDScript keywords/strings/numbers colour correctly while `<` stays an operator there.
## Tag colours split host vs component (G29): host elements take the engine-class colour
## (base_type_color), PascalCase components the user-class colour (user_type_color) — the same
## distinction Godot's own script editor draws between engine and user types.

var _tok := GuitkxTokenizer.new()

# kind (String) -> Color. Seeded with dark-theme fallbacks; update_colors() overrides from the editor.
var _palette := {
	"comment": Color("707070"),
	"string": Color("ffd166"),
	"tag": Color("5cc6d0"),
	"tag_component": Color("4ec9b0"),
	"attr": Color("9cdcfe"),
	"expr": Color("d4d4d4"),
	"directive": Color("c586c0"),
	"keyword": Color("ff7085"),
	"number": Color("a3e635"),
	"symbol": Color("abb2bf"),
}
var _c_default := Color("d4d4d4")
var _c_dim := Color("707070")   # muted colour for unreachable code (BUG-V6); recomputed in update_colors
var _dim_lines: Dictionary = {}   # line -> true for unreachable lines to fade

func _init() -> void:
	update_colors()

## Re-read colours from the editor theme (EditorSettings text-editor highlighting palette).
func update_colors() -> void:
	var es := EditorInterface.get_editor_settings()
	if es == null:
		return
	_c_default = _es_color(es, "text_color", _c_default)
	_palette["comment"] = _es_color(es, "comment_color", _palette["comment"])
	_palette["string"] = _es_color(es, "string_color", _palette["string"])
	_palette["tag"] = _es_color(es, "base_type_color", _palette["tag"])
	_palette["tag_component"] = _es_color(es, "user_type_color", _palette["tag_component"])
	_palette["attr"] = _es_color(es, "member_variable_color", _palette["attr"])
	_palette["expr"] = _c_default
	_palette["directive"] = _es_color(es, "control_flow_keyword_color", _palette["directive"])
	_palette["keyword"] = _es_color(es, "keyword_color", _palette["keyword"])
	_palette["number"] = _es_color(es, "number_color", _palette["number"])
	_palette["symbol"] = _es_color(es, "symbol_color", _palette["symbol"])
	# Dim = the text colour lerped toward the editor background, for faded unreachable code.
	_c_dim = _c_default.lerp(_es_color(es, "background_color", Color("181c26")), 0.55)

## Lines (a set: line -> true) to render dimmed as unreachable code. [BUG-V6]
func set_dim_lines(lines: Dictionary) -> void:
	_dim_lines = lines

func _es_color(es: EditorSettings, name: String, fallback: Color) -> Color:
	var key := "text_editor/theme/highlighting/" + name
	if es.has_setting(key):
		return es.get_setting(key)
	return fallback

func _get_line_syntax_highlighting(line: int) -> Dictionary:
	# Honoured live (cheap ProjectSettings lookup) so toggling KEY_HIGHLIGHTING needs no plugin reload.
	if not RUIEditorSettings.is_enabled(RUIEditorSettings.KEY_HIGHLIGHTING):
		return {}
	if _dim_lines.has(line):
		return { 0: { "color": _c_dim } }
	var te := get_text_edit()
	if te == null:
		return {}
	var text := te.get_line(line)
	var n := text.length()
	if n == 0:
		return {}
	var toks := _tok.tokenize_line(text)
	if toks.is_empty():
		return {}
	# Fill a per-column colour array (default first, then each span overwrites its range), then collapse
	# to the { column: { "color": Color } } boundary map Godot expects (keys strictly ascending).
	var carr: Array = []
	carr.resize(n)
	carr.fill(_c_default)
	for t in toks:
		var kind: String = t["kind"]
		var s: int = t["start"]
		var e: int = mini(int(t["end"]), n)
		# G29: a tag that is not in the host vocabulary is a component — paint it as a user class.
		if kind == "tag" and not GuitkxSchema.is_host_tag(text.substr(s, e - s)):
			kind = "tag_component"
		var col: Color = _palette.get(kind, _c_default)
		for x in range(s, e):
			carr[x] = col
	var out := {}
	for x in n:
		if x == 0 or carr[x] != carr[x - 1]:
			out[x] = {"color": carr[x]}
	return out
