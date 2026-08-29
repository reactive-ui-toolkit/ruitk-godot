extends SceneTree
## Headless tests for the Phase-1 markup-intelligence modules (GuitkxSchema / GuitkxContext /
## GuitkxWorkspace). Pure logic + live ClassDB + project scan; no editor UI.
## Run: godot --headless --path . --script res://tests/guitkx_lsp_test.gd

var _failed := 0
var _passed := 0

func _initialize() -> void:
	_test_context()
	_test_schema()
	_test_workspace()
	_test_completion()
	_test_hover()
	print("[guitkx_lsp_test] %d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)

func _ok(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		printerr("  FAIL: ", msg)

# Classify at the '|' caret marker in `s`.
func _ctx(s: String) -> Dictionary:
	var off := s.find("|")
	return GuitkxContext.classify(s.replace("|", ""), off)

func _test_context() -> void:
	var RET := "component X() {\n\treturn (\n\t\t"
	var END := "\n\t)\n}\n"
	# tag name after '<'
	_ok(_ctx(RET + "<|" + END)["kind"] == GuitkxContext.KIND_TAG, "'<' -> tagName")
	# tag name mid-word
	var t := _ctx(RET + "<Lab|" + END)
	_ok(t["kind"] == GuitkxContext.KIND_TAG and t["word"] == "Lab", "'<Lab' -> tagName word=Lab")
	# attribute name (space after tag)
	var a := _ctx(RET + "<Button |" + END)
	_ok(a["kind"] == GuitkxContext.KIND_ATTR and a["tag"] == "Button", "'<Button ' -> attrName tag=Button")
	var a2 := _ctx(RET + "<Button on|" + END)
	_ok(a2["kind"] == GuitkxContext.KIND_ATTR and a2["tag"] == "Button" and a2["word"] == "on", "'<Button on' -> attrName word=on")
	# attribute value (quoted)
	_ok(_ctx(RET + "<Button text=\"|\"" + END)["kind"] == GuitkxContext.KIND_ATTR_VALUE, "text=\"..\" -> attrValue")
	# embedded: {expr} attribute value
	_ok(_ctx(RET + "<Button text={ |" + END)["kind"] == GuitkxContext.KIND_EMBEDDED, "text={ .. } -> embedded")
	# directive
	var d := _ctx(RET + "@i|" + END)
	_ok(d["kind"] == GuitkxContext.KIND_DIRECTIVE and (d["word"] as String).begins_with("@"), "'@i' -> directive")
	# markup child slot (blank)
	_ok(_ctx(RET + "|" + END)["kind"] == GuitkxContext.KIND_MARKUP, "blank child -> markup")
	# embedded: setup line before return
	_ok(_ctx("component X() {\n\tvar n = use|\n\treturn ( <Label /> )\n}\n")["kind"] == GuitkxContext.KIND_EMBEDDED, "'var n = ' -> embedded")
	# '<' as a comparison inside an expr is NOT a tag
	_ok(_ctx(RET + "<Label text={ a < b|" + END)["kind"] == GuitkxContext.KIND_EMBEDDED, "'a < b' inside {} -> embedded (not tag)")

func _test_schema() -> void:
	# THE LOAD IS NOT LATCHED BY ONE FAILURE. `_loaded` was set BEFORE the read, so a schema file
	# not yet extracted from a freshly installed addon, or a transient read error, silently
	# disabled the markup vocabulary for the whole editor process -- and nothing anywhere could
	# ask whether it had loaded.
	_ok(GuitkxSchema.has_schema(), "the schema reports that it loaded")
	var tags := GuitkxSchema.host_tags()
	_ok(tags.size() >= 20, "host_tags loaded (%d)" % tags.size())
	_ok(tags.has("Button") and tags.has("VBoxContainer"), "host tags include Button + VBoxContainer")
	_ok(GuitkxSchema.godot_class_for("Button") == "Button", "Button -> Button")
	_ok(GuitkxSchema.godot_class_for("VBoxContainer") == "VBoxContainer", "VBoxContainer -> VBoxContainer")
	var props := GuitkxSchema.godot_properties("Button")
	_ok(_has_named(props, "text") and _has_named(props, "visible"), "Button properties include text + visible")
	var evs := GuitkxSchema.events_for_class("Button")
	_ok(_has_named(evs, "onPressed"), "Button events include onPressed")
	_ok(not _has_named(GuitkxSchema.events_for_class("Label"), "onPressed"), "Label has no onPressed (no `pressed`)")
	_ok(GuitkxSchema.resolve_event_signal("onPressed", "Button") == "pressed", "onPressed -> pressed")
	_ok(GuitkxSchema.resolve_event_signal("on_gui_input", "Button") == "gui_input", "on_gui_input -> gui_input")
	_ok(GuitkxSchema.hover_for_tag("Button").contains("Button"), "hover_for_tag(Button) mentions Button")
	_ok(GuitkxSchema.hover_for_directive("@for").contains("@for"), "hover_for_directive(@for)")
	_ok(GuitkxSchema.hover_for_attribute("Button", "onPressed").contains("pressed"), "hover onPressed -> pressed")
	_ok(GuitkxSchema.hover_for_attribute("Button", "text").contains("property"), "hover text -> property")

func _test_workspace() -> void:
	var tags := GuitkxWorkspace.component_tags()
	_ok(tags.size() > 0, "workspace indexed some components (%d)" % tags.size())
	_ok(GuitkxWorkspace.is_component("DemoBox"), "DemoBox is a known component")
	var loc := GuitkxWorkspace.lookup("DemoBox")
	_ok(loc.has("path") and (loc["path"] as String).ends_with("demo_box.guitkx"), "DemoBox -> demo_box.guitkx")
	_ok(not GuitkxWorkspace.is_component("Button"), "host tag Button is not a user component")

func _cmp(s: String) -> Array:
	return GuitkxCompletion.for_caret(s.replace("|", ""), s.find("|"))

func _test_completion() -> void:
	var RET := "component X() {\n\treturn (\n\t\t"
	var END := "\n\t)\n}\n"
	var tags := _cmp(RET + "<|" + END)
	_ok(_has_insert(tags, "Button") and _has_insert(tags, "DemoBox"), "tag completion offers Button + DemoBox")
	var mk := _cmp(RET + "|" + END)
	_ok(_has_insert(mk, "<Button") and _has_insert(mk, "@if ()"), "markup slot offers <Button + @if")
	var at := _cmp(RET + "<Button |" + END)
	# G20: attribute inserts are snippet-shaped — `=` plus an empty value pair the editor's
	# confirm steps the caret into (`=""` for String properties, `={}` for events/expressions).
	_ok(_has_insert(at, "onPressed={}") and _has_insert(at, "text=\"\"") and _has_insert(at, "style={}"),
		"Button attrs offer snippet-shaped onPressed + text + style")
	_ok(not _has_insert(_cmp(RET + "<Label |" + END), "onPressed={}"), "Label attrs exclude onPressed")
	var dr := _cmp(RET + "@|" + END)
	_ok(_has_insert(dr, "if ()") and _has_display(dr, "@if"), "directive '@' offers insert 'if ()' / display '@if'")
	_ok(_cmp(RET + "<Button text={ |" + END).is_empty(), "embedded {expr} offers nothing")

func _has_insert(items: Array, ins: String) -> bool:
	for it in items:
		if it is Dictionary and str(it.get("insert", "")) == ins:
			return true
	return false

func _has_display(items: Array, disp: String) -> bool:
	for it in items:
		if it is Dictionary and str(it.get("display", "")) == disp:
			return true
	return false

func _hov(s: String) -> String:
	return GuitkxHover.for_caret(s.replace("|", ""), s.find("|"))

func _test_hover() -> void:
	var RET := "component X() {\n\treturn (\n\t\t"
	var END := "\n\t)\n}\n"
	_ok(_hov(RET + "<Butt|on />" + END).contains("host element"), "hover host tag Button")
	_ok(_hov(RET + "<Demo|Box />" + END).contains("user component"), "hover user component DemoBox")
	_ok(_hov(RET + "<Button on|Pressed={ f } />" + END).contains("pressed"), "hover onPressed -> pressed")
	_ok(_hov(RET + "<Button te|xt=\"x\" />" + END).contains("property"), "hover text -> property")
	_ok(_hov(RET + "@fo|r (i in xs) { <Label /> }" + END).contains("@for"), "hover @for directive")
	_ok(_hov(RET + "<Button ke|y={ 1 } />" + END).contains("Reconciler"), "hover key -> structural")

func _has_named(arr: Array, name: String) -> bool:
	for e in arr:
		if e is Dictionary and str(e.get("name", "")) == name:
			return true
	return false
