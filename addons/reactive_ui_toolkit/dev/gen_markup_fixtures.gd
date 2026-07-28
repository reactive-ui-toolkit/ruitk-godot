extends SceneTree
## Generates the SHARED markup-AST golden corpus (the parser parity enforcer — analogous to
## scanner-cases.json for the lexer and formatter-cases.json for the formatter). Runs the GDScript
## parser of record (RUIGuitkxMarkup.parse) on each input and records the JSON-serialized node tree +
## error code. BOTH tests/guitkx_test.gd and the TS core.test.ts assert parse(input) reproduces it, so
## guitkx_markup.gd and markup.ts can never silently diverge. Many cases deliberately embed `<`/`>`
## comparisons inside {expr}/attrs — the exact bug class the structural fix kills.
##   godot --headless --path . --script res://addons/reactive_ui_toolkit/dev/gen_markup_fixtures.gd

const M = preload("res://addons/reactive_ui_toolkit/guitkx/guitkx_markup.gd")

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var output: String = args[0] if not args.is_empty() else "res://ide-extensions/lsp-server/test-fixtures/markup-cases.json"
	var cases := [
		{ "name": "simple_el", "input": "<Label text=\"hi\" />" },
		{ "name": "text_child", "input": "<Label>hello</Label>" },
		{ "name": "bool_and_expr_attrs", "input": "<Button text=\"x\" on_pressed={go} disabled />" },
		{ "name": "expr_child_lt_compare", "input": "<Label>{ a < b }</Label>" },
		{ "name": "attr_expr_gt_compare", "input": "<Label v={a > b}/>" },
		{ "name": "adjacent_compare_exprs", "input": "<VBox>{ a < b }{ c < d }</VBox>" },
		{ "name": "nested_with_compare", "input": "<VBox><HBox><Label>{ x < y }</Label></HBox></VBox>" },
		{ "name": "fragment_with_compare", "input": "<>{ a < b }</>" },
		{ "name": "for_body_with_compare", "input": "<VBox>@for (i in xs) { <Label>{ i < 3 }</Label> }</VBox>" },
		{ "name": "if_else_markup", "input": "<VBox>@if (ok) { <Label text=\"y\" /> } @else { <Label text=\"n\" /> }</VBox>" },
		{ "name": "jsx_as_value_attr", "input": "<Box child={ cond if c else <Inner a={p > q}/> } />" },
		{ "name": "mismatched_tag_error", "input": "<VBox><HBox></VBox>" },
		{ "name": "unclosed_expr_error", "input": "<Label>{ a < b </Label>" },
	]
	var out: Array = []
	for c in cases:
		var p = M.new()
		var r: Dictionary = p.parse(c["input"], 0, (c["input"] as String).length())
		out.append({ "name": c["name"], "input": c["input"], "error": r["error"], "tree": JSON.stringify(r["nodes"]) })
	var f := FileAccess.open(output, FileAccess.WRITE)
	if f == null:
		push_error("cannot write " + output)
		quit(1)
		return
	f.store_string(JSON.stringify(out, "  "))
	f.close()
	print("gen_markup_fixtures: wrote %d cases to %s" % [out.size(), output])
	quit(0)
