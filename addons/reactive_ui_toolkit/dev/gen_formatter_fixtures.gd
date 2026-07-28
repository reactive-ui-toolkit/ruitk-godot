extends SceneTree
## Generates the SHARED formatter golden-fixture corpus. Runs the GDScript formatter (the authority)
## on each messy input, checks idempotency, and writes {name, input, expected} to
## test-fixtures/formatter-cases.json. Both the GDScript test (tests/guitkx_test.gd) and the TS unit
## test (formatGuitkx) assert format(input)==expected, proving the two formatters are byte-identical.
##   godot --headless --path . --script res://addons/reactive_ui_toolkit/dev/gen_formatter_fixtures.gd

const Fmt = preload("res://addons/reactive_ui_toolkit/guitkx/guitkx_formatter.gd")

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var output: String = args[0] if not args.is_empty() else "res://ide-extensions/lsp-server/test-fixtures/formatter-cases.json"
	var cases := [
		{ "name": "counter", "input": "component  Counter( start: int = 0 ){\n\tvar s = useState(start)\n\treturn (\n<VBox>\n<Label text={s[0]}/>\n<Button text=\"+1\" on_pressed={inc}/>\n</VBox>\n)\n}\n" },
		{ "name": "attrs", "input": "component Btn(){\nreturn (\n<Button text=\"Click\" disabled flat={true} on_pressed={go}/>\n)\n}\n" },
		{ "name": "if_elif_else", "input": "component Status(state:int){\nreturn (\n<VBox>\n@if (state == 0) { return (<Label text=\"idle\"/>) } @elif (state == 1) { return (<Label text=\"run\"/>) } @else { return (<Label text=\"done\"/>) }\n</VBox>\n)\n}\n" },
		{ "name": "for_loop", "input": "component L(items:Array){\nreturn (\n<VBox>\n@for (it in items) { return (<Label text={str(it)} key={it}/>) }\n</VBox>\n)\n}\n" },
		{ "name": "match", "input": "component M(x:int){\nreturn (\n<VBox>\n@match (x) { @case (0) { return (<Label text=\"zero\"/>) } @default { return (<Label text=\"other\"/>) } }\n</VBox>\n)\n}\n" },
		# Phase D: a directive body with prep code + null-skip -- the code-block grammar formats too.
		{ "name": "body_prep_code", "input": "component P(items:Array){\nreturn (\n<VBox>\n@for (it in items) {\nvar label := \"row %s\" % it\nif it == null:\nreturn null\nreturn (<Label key={str(it)} text={label}/>)\n}\n</VBox>\n)\n}\n" },
		{ "name": "fragment", "input": "component F(){\nreturn (\n<>\n<Label text=\"a\"/>\n<Label text=\"b\"/>\n</>\n)\n}\n" },
		{ "name": "hook", "input": "hook use_counter( start:int ){\n\tvar s = useState(start)\n\treturn s\n}\n" },
		{ "name": "module", "input": "module Widgets {\ncomponent A(){ return (<Label text=\"a\"/>) }\ncomponent B(){ return (<A/>) }\n}\n" },
		# Phase D reformat finds: module-member `##` docs and `-> Type` hints must survive the re-emit
		# (both were silently dropped -- the hint loss cascaded := inference errors through callers).
		{ "name": "module_docs_and_hint", "input": "module Docs {\n## builds the thing.\n## second line.\nhook use_built( n: int ) -> Dictionary {\n\tvar s = useState(n)\n\treturn { \"v\": s }\n}\n\n## renders it.\ncomponent Shown(){ return (<Label text=\"x\"/>) }\n}\n" },
		{ "name": "classname", "input": "@class_name Fancy\ncomponent Card(title:String){\nreturn (\n<Panel>\n<Label text={title}/>\n</Panel>\n)\n}\n" },
		{ "name": "hook_return_hint", "input": "hook use_thing( n: int ) -> Array {\n\tvar s = useState(n)\n\treturn s\n}\n" },
		{ "name": "guard_return_null", "input": "component G(show: bool) {\n\tif not show:\n\t\treturn null\n\treturn (<Label text=\"x\" />)\n}\n" },
		# Mixed tab/space setup: the lambda body is `\t    ` (tab + 4 spaces). Depth-based reanchor must
		# normalize it to real tabs (`\t\t`), NOT emit it verbatim as tab+spaces. [BUG: mixed-indent]
		{ "name": "setup_mixed_indent", "input": "component Mix() {\n\tvar a = useState(0)\n\tvar toggle = func():\n\t    a[1].call(1)\n\treturn (<Label text=\"x\" />)\n}\n" },
		# One outlier-SHALLOW setup line (`var b` at column 0). A min-depth anchor pushed every OTHER
		# line one level deeper (over-indented with no preceding `:` = invalid generated .gd); the
		# first-line anchor keeps normal lines at body level and clamps the outlier up to it. [BUG: G1/G4]
		{ "name": "setup_outlier_indent", "input": "component Out() {\n\tvar a = useState(0)\nvar b = 1\n\tif a[0]:\n\t\tb += 1\n\treturn (<Label text=\"x\" />)\n}\n" },
		# A leading OVER-INDENTED comment (legal at any indentation in GDScript). Anchoring on it
		# dragged real code off its base: the if-body got dedented out of its block. The anchor must
		# come from the first non-comment line. [BUG: comment-anchor]
		{ "name": "setup_comment_anchor", "input": "component Cmt() {\n\t\t# over-indented note\n\tvar a = useState(0)\n\tif a[0]:\n\t\ta[1].call(1)\n\treturn (<Label text=\"x\" />)\n}\n" },
	]
	var out: Array = []
	for c in cases:
		var r: Dictionary = Fmt.format(c["input"])
		var r2: Dictionary = Fmt.format(r["text"])
		if r2["text"] != r["text"]:
			push_error("NON-IDEMPOTENT fixture '%s'" % c["name"])
			quit(1)
			return
		out.append({ "name": c["name"], "input": c["input"], "expected": r["text"] })
	var f := FileAccess.open(output, FileAccess.WRITE)
	if f == null:
		push_error("cannot write " + output)
		quit(1)
		return
	f.store_string(JSON.stringify(out, "  "))
	f.close()
	print("gen_formatter_fixtures: wrote %d cases to %s" % [out.size(), output])
	quit(0)
