extends SceneTree
## Milestone 2.1 compiler test: (1) compile-text checks on a hook-using component, and
## (2) an end-to-end runtime test — compile a hook-free component, write the generated .gd,
## load it, mount it through the reconciler, and verify the real Godot node tree.

const Codegen = preload("res://addons/reactive_ui_toolkit/guitkx/guitkx_codegen.gd")
const GDiag = preload("res://addons/reactive_ui_toolkit/guitkx/guitkx_diag.gd")

var _failed := false

func _initialize() -> void:
	_run()

func _run() -> void:
	_test_emit()
	_test_runtime()
	_test_control_flow()
	_test_match()
	_test_hook()
	_test_hook_alias()
	_test_hook_member_not_mangled()
	_test_null_only_component()
	_test_ctrl_flow_in_lambda()
	_test_module()
	_test_module_dup_across_kinds()
	_test_p1_error_gates()
	_test_t13_single_decl()
	_test_t14_last_return()
	_test_t15_unknown_tags()
	_test_t25_hook_contexts()
	_test_t26_naming()
	_test_t27_diag_ports()
	_test_t23_uss()
	_test_t35_parser_bugs()
	_test_severity_table()
	_test_p2_markup_features()
	_test_return_null_guard()
	_test_jsx_value()
	_test_diagnostics()
	_test_loop_single_root()
	_test_decl_validation()
	_test_codegen_staleness()
	_test_indent_robustness()
	_test_outlier_indent()
	_test_deep_flatten()
	_test_scanner_fixtures()
	_test_g23_prelude_comments()
	_test_markup_corpus()
	_test_vocabulary()
	_test_loyal_naming_090()
	_test_formatter()
	_test_formatter_corpus()
	_test_format_unsafe_str_attr()
	_test_format_fell_back()
	_test_formatter_options()
	_test_codegen()
	_test_cold_open_recovery()
	_test_phase_d_bodies()
	_test_spread()
	_test_imports_m1()
	_test_mixed_decl()
	_test_imports_m3()
	_test_m4()
	_test_codemod()
	_test_bughunt_fixes()
	_test_0103_retired()
	_test_2107_walk_order()
	_test_es_modules_declarations()
	_test_es_modules_imports()
	_test_es_combined_imports()
	_test_es_modules_m4_ordering()
	_test_es_formatter()
	if _failed:
		print("[guitkx_test] FAILED")
		quit(1)
	else:
		print("[guitkx_test] ALL PASSED")
		quit()

func _test_module() -> void:
	# module Name { ... } -> one class, named static funcs, intra-module <Card/> -> V.fc(Card, ...)
	var src := "module Widgets {\n" + \
		"\tcomponent Card(title: String = \"\") {\n" + \
		"\t\treturn ( <PanelContainer><Label text={ title } /></PanelContainer> )\n" + \
		"\t}\n" + \
		"\tcomponent Row() {\n" + \
		"\t\treturn ( <HBoxContainer><Card title=\"A\" /><Card title=\"B\" /></HBoxContainer> )\n" + \
		"\t}\n" + \
		"}\n"
	var r := RuitkGuitkx.compile(src, "Widgets")
	if not r["ok"]:
		_fail("module: compile failed: " + str(r["diagnostics"]))
	var gd: String = r["gd"]
	print("--- generated (Widgets module) ---\n" + gd + "----------------------------")
	_check(gd, "class_name Widgets", "module class name")
	_check(gd, "static func Card(", "Card static func")
	_check(gd, "static func Row(", "Row static func")
	_check(gd, "V.fc(Card,", "intra-module <Card/> -> bare sibling static func")
	_check_true(not ("Card.render" in gd), "module-local component does NOT use Foo.render")
	# runtime: Row renders 2 Cards -> 2 Labels
	var gd2 := gd.replace("class_name Widgets\n", "")
	var path := "user://__widgets.gd"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(gd2)
	f.close()
	var script = load(path)
	_check_true(script != null, "module .gd loads")
	var c := Control.new()
	root.add_child(c)
	var app := RuitkRoot.create(c, V.fc(Callable(script, "Row"), {}))
	_check_true(_count_class(c, "Label") == 2, "Row -> 2 Cards -> 2 Labels got %d" % _count_class(c, "Label"))
	app.unmount()
	c.free()

func _test_jsx_value() -> void:
	# markup nested inside expressions: ternary, short-circuit (and), and a .map() lambda return
	var src := "component JsxVal(items: Array = [\"a\", \"b\"], cond: bool = true) {\n" + \
		"\treturn (\n" + \
		"\t\t<VBoxContainer>\n" + \
		"\t\t\t{ <Label text=\"x\" /> if cond else <Label text=\"y\" /> }\n" + \
		"\t\t\t{ cond and <Button text=\"go\" /> }\n" + \
		"\t\t\t{ items.map(func(it): return <Label text={ it } />) }\n" + \
		"\t\t</VBoxContainer>\n" + \
		"\t)\n}\n"
	var r := RuitkGuitkx.compile(src, "JsxVal")
	if not r["ok"]:
		_fail("jsx_value: compile failed: " + str(r["diagnostics"]))
	var gd: String = r["gd"]
	print("--- generated (JsxVal) ---\n" + gd + "----------------------------")
	_check(gd, "if cond else", "ternary preserved")
	_check_true(not ("<Label" in gd), "no raw <Label markup left in expression")
	# 0.7.2 anchor regression (field capture 2026-07-04): diagnostics from setup-VALUE markup must
	# anchor in the ORIGINAL source. Aliasing used to run BEFORE the splice, so every inserted
	# `Hooks.` prefix (6 chars) shifted every later diagnostic onto the CLOSING tag (8:33 vs 8:21).
	# Splice first, alias second. (A no-suggestion PascalCase miss is GUITKX2307 since the imports leg.)
	var a_src := "component AnchorProbe() {\n" + \
		"\tvar n = useState(0)\n" + \
		"\tvar m = useState(1)\n" + \
		"\tvar c = (<Nope></Nope>)\n" + \
		"\treturn ( <VBoxContainer>{ c }<Label text={ str(n[0] + m[0]) } /></VBoxContainer> )\n}\n"
	var ra := RuitkGuitkx.compile(a_src, "AnchorProbe", ["DemoBox"])
	_check_true(not ra["ok"], "unknown component in a setup value fails the compile")
	var a_found := false
	for da in (ra["diagnostics"] as Array):
		if str((da as Dictionary).get("code", "")) == "GUITKX2307":
			a_found = true
			_check_true(int((da as Dictionary).get("offset", -1)) == a_src.find("<Nope>") + 1,
				"2307 anchors on the OPENING tag name in the original source (got %d, want %d)" % [int((da as Dictionary).get("offset", -1)), a_src.find("<Nope>") + 1])
	_check_true(a_found, "2307 reported for the unknown setup-value component (no file exports it)")
	_check(gd, "if (cond) else null", "short-circuit `and` desugared to ternary")
	_check(gd, "V.Label({ \"text\": it })", "map-lambda markup lowered")
	# runtime: cond=true -> Label x + (map a,b) = 3 Labels, + 1 Button (short-circuit)
	var gd2 := gd.replace("class_name JsxVal\n", "")
	var path := "user://__jsxval.gd"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(gd2)
	f.close()
	var script = load(path)
	_check_true(script != null, "JsxVal .gd loads")
	var c := Control.new()
	root.add_child(c)
	var app := RuitkRoot.create(c, V.fc(script.render, { "items": ["a", "b"], "cond": true }))
	_check_true(_count_class(c, "Label") == 3, "3 Labels (ternary x + map a,b) got %d" % _count_class(c, "Label"))
	_check_true(_count_class(c, "Button") == 1, "1 Button (short-circuit) got %d" % _count_class(c, "Button"))
	app.unmount()
	c.free()

func _test_hook_alias() -> void:
	# token-boundary hook aliasing: real calls prefixed; identifiers/strings/qualified left alone
	var src := "component HA() {\n" + \
		"\tvar s = useState(0)\n" + \
		"\tvar my_use_state_val = 1\n" + \
		"\tvar note = \"call useState() at the top\"\n" + \
		"\tvar r = Hooks.useRef(null)\n" + \
		"\treturn ( <Label text={ str(s[0]) + str(my_use_state_val) + str(r) } /> )\n}\n"
	var res := RuitkGuitkx.compile(src, "HA")
	if not res["ok"]:
		_fail("hook_alias: compile failed: " + str(res["diagnostics"]))
	var gd: String = res["gd"]
	_check(gd, "Hooks.useState(0)", "bare hook call prefixed")
	_check_true(not ("my_Hooks.useState" in gd), "identifier substring NOT corrupted")
	_check(gd, "\"call useState() at the top\"", "string literal NOT corrupted")
	_check_true(not ("Hooks.Hooks." in gd), "already-qualified not double-prefixed")
	_check(gd, "Hooks.useRef(null)", "already-qualified preserved")

func _test_hook_member_not_mangled() -> void:
	# [audit #6] A member call on a non-Hooks receiver named like a hook must NOT be auto-prefixed.
	var src := "component MM() {\n" + \
		"\tvar obj = make_thing()\n" + \
		"\tvar v = obj.useState(0)\n" + \
		"\treturn ( <Label text={ str(v) } /> )\n}\n"
	var res := RuitkGuitkx.compile(src, "MM")
	if not res["ok"]:
		_fail("hook_member: compile failed: " + str(res["diagnostics"]))
	var gd: String = res["gd"]
	_check(gd, "obj.useState(0)", "member .useState NOT prefixed")
	_check_true(not ("obj.Hooks." in gd), "no spurious Hooks. after member access")

func _test_null_only_component() -> void:
	# React semantics: a component whose body has a TOP-LEVEL `return null` and no markup return
	# is a legal "renders nothing" component -- 2101 no longer fires on it (all layers).
	var w := RuitkGuitkx.compile("component Gone() {\n\treturn null\n}\n", "Gone")
	_check_true(bool(w["ok"]), "null-only wrapper component compiles (got %s)" % str(w.get("diagnostics", [])))
	_check(str(w["gd"]), "return null", "emitted render carries the body's own return null")
	_check_true(not str(w["gd"]).contains("V."), "no markup lowering emitted for a null-only body")
	var p := RuitkGuitkx.compile("export Gone2(active: bool = false) -> RuitkVNode {\n\tif active:\n\t\treturn null\n\treturn null\n}\n", "Gone2")
	_check_true(bool(p["ok"]), "null-only PLAIN component (guard + final null) compiles (got %s)" % str(p.get("diagnostics", [])))
	_check(str(p["gd"]), "static func render(props: Dictionary, children: Array) -> RuitkVNode:", "plain null-only emits the render func")
	# hooks in a null-only body still alias (effect-only components are the use case)
	var h := RuitkGuitkx.compile("component Fx() {\n\tuseEffect(func():\n\t\tprint(\"x\")\n\t, [])\n\treturn null\n}\n", "Fx")
	_check_true(bool(h["ok"]), "effect-only null component compiles (got %s)" % str(h.get("diagnostics", [])))
	_check(str(h["gd"]), "Hooks.useEffect", "hook aliasing runs over the null-only body")
	# totality still enforced: a nested-only `return null` (fall-through body) stays GUITKX2101
	var bad := RuitkGuitkx.compile("component Bad(a: bool) {\n\tif a:\n\t\treturn null\n\tvar x = 1\n}\n", "Bad")
	_check_true(not bool(bad["ok"]) and _has_code(bad, "GUITKX2101"), "fall-through body still 2101 (got %s)" % str(bad.get("diagnostics", [])))
	# and a top-level non-markup value return stays GUITKX2102
	var v := RuitkGuitkx.compile("component Val() {\n\treturn 5\n}\n", "Val")
	_check_true(not bool(v["ok"]) and _has_code(v, "GUITKX2102"), "top-level value return stays 2102 (got %s)" % str(v.get("diagnostics", [])))
	# formatter: no invented markup window, idempotent (tabs are the repo default options)
	var fsrc := "export Gone3(active: bool = false) -> RuitkVNode {\n\tif active:\n\t\treturn null\n\treturn null\n}\n"
	var f1: Dictionary = RuitkGuitkxFormatter.format(fsrc, { "indentStyle": "tab" })
	_check_true(not str(f1.get("text", "")).contains("return (\n"), "formatter invents no empty markup window")
	var f2: Dictionary = RuitkGuitkxFormatter.format(str(f1.get("text", "")), { "indentStyle": "tab" })
	_check_true(str(f2.get("text", "")) == str(f1.get("text", "")), "null-only formatting is idempotent")

func _test_ctrl_flow_in_lambda() -> void:
	# [audit #17] control-flow inside a JSX-value lambda must lower INLINE (ternary / .map), not hoist
	# render-level `if/for` statements that can't see the lambda's locals (`it`).
	var src := "component CFL(items: Array = []) {\n" + \
		"\treturn (\n\t\t<VBoxContainer>\n" + \
		"\t\t\t{ items.map(func(it): return <>@if (it.ok) { return ( <Label text={ it.name } /> ) }</>) }\n" + \
		"\t\t</VBoxContainer>\n\t)\n}\n"
	var res := RuitkGuitkx.compile(src, "CFL")
	if not res["ok"]:
		_fail("ctrl_in_lambda: compile failed: " + str(res["diagnostics"]))
	var gd: String = res["gd"]
	_check_true("if (it.ok)" in gd, "@if lowered to an inline ternary (got: %s)" % gd)
	_check_true(not ("__cf" in gd), "no hoisted __cf statement (would be out of lambda scope)")
	# The generated .gd must be VALID GDScript — the bug produced an undeclared `it` at render scope.
	var script := GDScript.new()
	script.source_code = gd.replace("class_name CFL\n", "")
	_check_true(script.reload() == OK, "generated .gd with inline control-flow compiles cleanly")

	# @for inside a JSX-value lowers to .map (also lambda-safe).
	var src_for := "component CFF(items: Array = []) {\n" + \
		"\treturn ( <VBoxContainer>{ true and <>@for (x in items) { return ( <Label text={ x } /> ) }</> }</VBoxContainer> )\n}\n"
	var res_for := RuitkGuitkx.compile(src_for, "CFF")
	_check_true(res_for["ok"] and "items).map(func(x)" in str(res_for["gd"]), "@for in expression lowers to .map")

	# @match inside a JSX-value can't be an expression -> GUITKX0026, and since T1.1 an emit-time
	# error FAILS the compile (no diagnostic with error severity may coexist with ok:true).
	var src_m := "component CFM(x: int = 0) {\n" + \
		"\treturn ( <VBoxContainer>{ true and <>@match (x) { @case (0) { return ( <Label/> ) } }</> }</VBoxContainer> )\n}\n"
	var res_m := RuitkGuitkx.compile(src_m, "CFM")
	_check_true(_has_code(res_m, "GUITKX0026"), "@match in expression emits GUITKX0026")
	_check_true(not res_m["ok"], "T1.1: emit-time 0113 fails the compile")
	_check_true(res_m["gd"] == "", "T1.1: failed compile ships no generated code")

func _test_module_dup_across_kinds() -> void:
	# [audit #7] component + hook with the SAME name in a module must fail (would emit duplicate funcs).
	var src := "module M {\n" + \
		"component Foo() { return ( <Label/> ) }\n" + \
		"hook Foo() { return 1 }\n}\n"
	var res := RuitkGuitkx.compile(src, "M")
	_check_true(not res["ok"], "module component+hook same name rejected")
	_check_true(_has_code(res, "GUITKX2505"), "duplicate-decl diagnostic emitted")

func _test_p1_error_gates() -> void:
	# T1.2: malformed markup inside an @if body -> the INNER parser's error code, positioned exactly
	# on the broken tag, and (T1.1) ok:false. Previously: silent `null  # body parse error` emission.
	var src_if := "component B() {\n" + \
		"\treturn (\n\t\t<VBoxContainer>\n\t\t\t@if (true) { return ( <Broken> ) }\n\t\t</VBoxContainer>\n\t)\n}\n"
	var r := RuitkGuitkx.compile(src_if, "B")
	_check_true(not r["ok"], "T1.2: broken @if body fails the compile")
	_check_diag_at(r, "GUITKX0301", src_if, "<Broken>", "T1.2: 0301 lands on the unclosed tag in the @if body")

	# T1.2: broken markup in a @for body.
	var src_for := "component F(xs: Array = []) {\n" + \
		"\treturn ( <VBoxContainer>@for (x in xs) { return ( <Row };&& ) }</VBoxContainer> )\n}\n"
	var r2 := RuitkGuitkx.compile(src_for, "F")
	_check_true(not r2["ok"], "T1.2: broken @for body fails the compile")

	# T1.2: broken markup nested inside a JSX-value {expr} -- no validation pass ever reaches it,
	# so the emit-time parse is its only chance to be seen.
	var src_ex := "component C(open: bool = false) {\n" + \
		"\treturn ( <VBoxContainer>{ open and <Broken> }</VBoxContainer> )\n}\n"
	var r3 := RuitkGuitkx.compile(src_ex, "C")
	_check_true(not r3["ok"], "T1.2: broken nested-expr markup fails the compile")
	_check_diag_at(r3, "GUITKX0301", src_ex, "<Broken>", "T1.2: nested-expr 0301 lands on the broken tag")

	# T1.1: a module member whose loop body has 2 roots (validation ERROR 0108) fails the module --
	# previously _compile_module had no gate at all and shipped the broken class.
	var src_mod := "module M2 {\n" + \
		"\tcomponent A() {\n" + \
		"\t\treturn ( <VBoxContainer>@for (i in 3) { return ( <Label key={ str(i) } /> <Label key={ str(i) + \"b\" } /> ) }</VBoxContainer> )\n" + \
		"\t}\n}\n"
	var r4 := RuitkGuitkx.compile(src_mod, "M2")
	_check_true(not r4["ok"], "T1.1: module-member validation error fails the module compile")
	_check_true(_has_code(r4, "GUITKX0108"), "T1.1: the member's 0108 is the reported error")

func _test_t14_last_return() -> void:
	# T1.4 (Unity useLastReturn parity): the LAST top-level markup return is the component's window.
	# Phase C: an EARLIER top-level markup return is LEGAL -- lowered in place -- and everything
	# after it (including the final return) is dimmed unreachable, exactly like Unity's Site-B dim.
	var two_src := "component U2() {\n\treturn ( <Label /> )\n\tvar x = 5\n\treturn ( <Button /> )\n}\n"
	var two := RuitkGuitkx.compile(two_src, "U2")
	_check_true(bool(two["ok"]), "Phase C: an early top-level markup return compiles (got %s)" % str(two["diagnostics"]))
	_check_true(_has_code(two, "GUITKX0107"), "Phase C: code after the unconditional early return dims unreachable (got %s)" % str(two["diagnostics"]))
	_check_true("return V.Label" in str(two["gd"]), "Phase C: the early return's markup is lowered in place, got:\n%s" % str(two["gd"]))

	# Phase C: a markup return INSIDE an if: block is legal and lowered in place -- and its markup
	# is now REALLY parsed, so mismatched tags get the precise 0302 instead of a blanket 2102.
	var early_bad_src := "component S(weird: bool = false) {\n" + \
		"\tif weird:\n\t\treturn <s></a>\n" + \
		"\treturn (\n\t\t<VBoxContainer><Label text=\"ok\" /></VBoxContainer>\n\t)\n}\n"
	var early_bad := RuitkGuitkx.compile(early_bad_src, "S")
	_check_true(not early_bad["ok"], "Phase C: a BROKEN early markup return still fails the compile")
	_check_true(_has_code(early_bad, "GUITKX0302"), "Phase C: the early return's markup is parsed for real (0302 mismatched tag, got %s)" % str(early_bad["diagnostics"]))

	# Phase C, the t04 shape: a CONDITIONAL early markup return compiles to scope-correct GDScript
	# -- its lowered `return` sits INSIDE the `if weird:` block, at the block's indent.
	var early_src := "component S2(weird: bool = false) {\n" + \
		"\tif weird:\n\t\treturn ( <Label text=\"early\" /> )\n" + \
		"\treturn (\n\t\t<VBoxContainer><Label text=\"ok\" /></VBoxContainer>\n\t)\n}\n"
	var early := RuitkGuitkx.compile(early_src, "S2")
	_check_true(bool(early["ok"]), "Phase C: a conditional early markup return compiles (got %s)" % str(early["diagnostics"]))
	_check_true("\n\t\treturn V.Label" in str(early["gd"]), "Phase C: the early return is lowered at ITS OWN indent (inside the if block), got:\n%s" % str(early["gd"]))
	_check_true(not _has_code(early, "GUITKX0107"), "Phase C: a CONDITIONAL early return dims nothing (got %s)" % str(early["diagnostics"]))

	# Phase C runtime proof: both paths of the compiled guard actually render (the whole point).
	var sc := GDScript.new()
	sc.source_code = str(early["gd"]).replace("class_name S2\n", "")
	var lerr := sc.reload()
	_check_true(lerr == OK, "Phase C runtime: the lowered .gd parses+compiles (err %s):\n%s" % [str(lerr), str(early["gd"])])
	if lerr == OK:
		var inst = sc.new()
		var r_early = inst.render({ "weird": true }, [])
		var r_main = inst.render({ "weird": false }, [])
		_check_true(r_early is RuitkVNode and str((r_early as RuitkVNode).props.get("text", "")) == "early", "Phase C runtime: weird=true renders the early label (got %s)" % str(r_early))
		_check_true(r_main is RuitkVNode and (r_main as RuitkVNode).props.get("text", null) == null, "Phase C runtime: weird=false renders the main vbox root (got %s)" % str(r_main))

	# A PLAIN parenthesized return inside a setup lambda is legal GDScript -- never flagged.
	var lambda_src := "component L() {\n" + \
		"\tvar f = func():\n\t\treturn (1 + 2)\n" + \
		"\treturn ( <Label text={ str(f.call()) } /> )\n}\n"
	var lam := RuitkGuitkx.compile(lambda_src, "L")
	_check_true(bool(lam["ok"]), "T1.4: lambda `return (expr)` is not hijacked nor flagged (got %s)" % str(lam["diagnostics"]))
	_check_true("1 + 2" in str(lam["gd"]), "T1.4: lambda body stays in setup verbatim")

	# Unity 2102 fallback: a top-level return that is not `return (`/`return <`/`return null`.
	var malformed_src := "component M() {\n\treturn V.Label({})\n}\n"
	var mal := RuitkGuitkx.compile(malformed_src, "M")
	_check_true(not mal["ok"], "T1.4: malformed top-level return fails")
	_check_diag_at(mal, "GUITKX2102", malformed_src, "return V.Label({})", "T1.4: malformed-return 2102 position")

	# Unity LooksLikeMarkupRoot parity: `return ( plain_expr )` is 2102 -- the window must hold
	# an element, fragment, @directive, or {expr}.
	var plain_src := "component P() {\n\treturn ( 1 + 2 )\n}\n"
	var plain := RuitkGuitkx.compile(plain_src, "P")
	_check_true(not plain["ok"] and _has_code(plain, "GUITKX2102"), "T1.4: non-markup return window is 2102 (got %s)" % str(plain["diagnostics"]))

	# G9: a body that is ONLY an @for block (no return at all) must error missing-return.
	var g9_src := "component G9() {\n\t@for (i in 25) {\n\t\treturn ( <Label text={ str(i) } /> )\n\t}\n}\n"
	var g9 := RuitkGuitkx.compile(g9_src, "G9")
	_check_true(not g9["ok"] and _has_code(g9, "GUITKX2101"), "T1.4/G9: @for-only body errors missing-return (got %s)" % str(g9["diagnostics"]))

	# A `{expr}` root stays legal (LooksLikeMarkupRoot accepts `{`).
	var expr_src := "component E(items: Array = []) {\n\treturn ( { items.map(func(i): return <Label text={ str(i) } />) } )\n}\n"
	var expr := RuitkGuitkx.compile(expr_src, "E")
	_check_true(bool(expr["ok"]), "T1.4: {expr} root still compiles (got %s)" % str(expr["diagnostics"]))

func _test_t25_hook_contexts() -> void:
	# T2.5 (Unity 0013-0016): four contexts, each its own code, all ERRORS.
	var base := "component H(c: bool = true, xs: Array = []) {\n%s\treturn ( <Label text=\"x\" /> )\n}\n"
	var rl := RuitkGuitkx.compile(base % "\tfor x in xs:\n\t\tvar s = useState(0)\n", "H")
	_check_true(not rl["ok"] and _has_code(rl, "GUITKX0014"), "T2.5: hook in loop = 0014 (got %s)" % str(rl["diagnostics"]))
	var rm := RuitkGuitkx.compile(base % "\tmatch c:\n\t\ttrue:\n\t\t\tvar s = useState(0)\n", "H")
	_check_true(not rm["ok"] and _has_code(rm, "GUITKX0015"), "T2.5: hook in match = 0015 (got %s)" % str(rm["diagnostics"]))
	var rf := RuitkGuitkx.compile(base % "\tvar f = func():\n\t\tvar s = useState(0)\n", "H")
	_check_true(not rf["ok"] and _has_code(rf, "GUITKX0016"), "T2.5: hook in lambda = 0016 (got %s)" % str(rf["diagnostics"]))
	var ri := RuitkGuitkx.compile(base % "\tif c: var s = useState(0)\n", "H")
	_check_true(not ri["ok"] and _has_code(ri, "GUITKX0013"), "T2.5: single-line if hook = 0013 (got %s)" % str(ri["diagnostics"]))

	# (d) markup-expression context: attr expr + child expr.
	var ra := RuitkGuitkx.compile("component A() {\n\treturn ( <Label text={ str(useState(0)[0]) } /> )\n}\n", "A")
	_check_true(not ra["ok"] and _has_code(ra, "GUITKX0016"), "T2.5: hook call in attr expr = 0016 (got %s)" % str(ra["diagnostics"]))
	var rc := RuitkGuitkx.compile("component B() {\n\treturn ( <VBoxContainer>{ useState(0)[0] }</VBoxContainer> )\n}\n", "B")
	_check_true(not rc["ok"] and _has_code(rc, "GUITKX0016"), "T2.5: hook call in child expr = 0016 (got %s)" % str(rc["diagnostics"]))

	# NEGATIVES: top-level hook, hook RESULT in attr, look-alike identifier, member call.
	var ok_src := "component OK(c: bool = true) {\n" + \
		"\tvar s = useState(0)\n" + \
		"\tvar my_useState_thing = 1\n" + \
		"\tvar obj_call = s\n" + \
		"\treturn ( <Label text={ str(s[0]) } on_pressed={ s[1] } /> )\n}\n"
	var rok := RuitkGuitkx.compile(ok_src, "OK")
	_check_true(bool(rok["ok"]), "T2.5: top-level hook + result-in-attr stay clean (got %s)" % str(rok["diagnostics"]))

	# hook DECLARATION bodies are validated too (hooks compose hooks -- unconditionally).
	var rhb := RuitkGuitkx.compile("hook use_bad(c: bool = false) {\n\tif c:\n\t\tvar s = useState(0)\n\treturn 1\n}\n", "use_bad")
	_check_true(not rhb["ok"] and _has_code(rhb, "GUITKX0013"), "T2.5: hook body validated (got %s)" % str(rhb["diagnostics"]))

func _test_t27_diag_ports() -> void:
	# T2.7 / Unity 0018: an effect hook with only a callback runs every render -- warn.
	var src18 := "component E() {\n\tuseEffect(func(): print(\"hi\"))\n\treturn ( <Label text=\"x\" /> )\n}\n"
	var r18 := RuitkGuitkx.compile(src18, "E")
	_check_true(bool(r18["ok"]), "T2.7: missing-deps effect still compiles")
	_check_diag_at(r18, "GUITKX0018", src18, "useEffect", "T2.7: 0018 lands on the call")
	var ok18 := RuitkGuitkx.compile("component E2() {\n\tuseEffect(func(): print(\"hi\"), [])\n\treturn ( <Label text=\"x\" /> )\n}\n", "E2")
	_check_true(bool(ok18["ok"]) and not _has_code(ok18, "GUITKX0018"), "T2.7: deps array satisfies 0018 (got %s)" % str(ok18["diagnostics"]))

	# T2.7 / Unity 0019: the loop variable used DIRECTLY as the key.
	var src19 := "component K(xs: Array = []) {\n\treturn ( <VBoxContainer>@for (x in xs) { return ( <Label key={ x } text={ str(x) } /> ) }</VBoxContainer> )\n}\n"
	var r19 := RuitkGuitkx.compile(src19, "K")
	_check_true(bool(r19["ok"]) and _has_code(r19, "GUITKX0019"), "T2.7: direct binder key warns 0019 (got %s)" % str(r19["diagnostics"]))
	var ok19 := RuitkGuitkx.compile("component K2(xs: Array = []) {\n\treturn ( <VBoxContainer>@for (x in xs) { return ( <Label key={ str(x) } text={ str(x) } /> ) }</VBoxContainer> )\n}\n", "K2")
	_check_true(not _has_code(ok19, "GUITKX0019"), "T2.7: derived key stays clean")

	# T2.7 / Unity 0111: a component parameter never referenced anywhere in the body.
	var src111 := "component U(used: int = 1, dead: int = 2, _ignored: int = 3) {\n\treturn ( <Label text={ str(used) } /> )\n}\n"
	var r111 := RuitkGuitkx.compile(src111, "U")
	_check_true(bool(r111["ok"]), "T2.7: unused param still compiles")
	_check_diag_at(r111, "GUITKX0111", src111, "dead", "T2.7: 0111 lands on the unused param")
	_check_true(str(_diag(r111, "GUITKX0111").get("message", "")).contains("dead"), "T2.7: only `dead` flagged (underscore exempt)")

	# T2.7 / Unity 0120/0121: res:// string literals in asset attributes must exist / match type.
	var src120 := "component A() {\n\treturn ( <TextureRect texture=\"res://no/such/file.png\" /> )\n}\n"
	var r120 := RuitkGuitkx.compile(src120, "A")
	_check_true(not r120["ok"] and _has_code(r120, "GUITKX0120"), "T2.7: missing asset errors 0120 (got %s)" % str(r120["diagnostics"]))
	var src121 := "component B() {\n\treturn ( <TextureRect texture=\"res://project.godot\" /> )\n}\n"
	var r121 := RuitkGuitkx.compile(src121, "B")
	_check_true(not r121["ok"] and _has_code(r121, "GUITKX0121"), "T2.7: wrong-type asset errors 0121 (got %s)" % str(r121["diagnostics"]))

func _test_severity_table() -> void:
	# T3.2: one severity per code, everywhere -- vocabulary.json `severities` is the single source and
	# this tripwire pins every D.make() literal in the compiler to it.
	var vocab: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://addons/reactive_ui_toolkit/guitkx/vocabulary.json"))
	var sev_table: Dictionary = vocab.get("severities", {})
	_check_true(not sev_table.is_empty(), "T3.2: severities table present")
	var src := FileAccess.get_file_as_string("res://addons/reactive_ui_toolkit/guitkx/guitkx.gd")
	var re := RegEx.new()
	re.compile("D\\.make\\(\"(GUITKX\\d+)\", D\\.(ERROR|WARNING|HINT)")
	var names := { "ERROR": "error", "WARNING": "warning", "HINT": "hint" }
	var checked := 0
	for m in re.search_all(src):
		var code := m.get_string(1)
		var sev := str(names[m.get_string(2)])
		if not sev_table.has(code):
			_fail("T3.2: %s missing from the severity table" % code)
			continue
		_check_true(str(sev_table[code]) == sev, "T3.2: %s severity matches the table (site %s vs table %s)" % [code, sev, sev_table[code]])
		checked += 1
	_check_true(checked >= 25, "T3.2: table-driven check saw %d sites" % checked)
	for lc in vocab.get("live", []):
		_check_true(sev_table.has(lc), "T3.2: live code %s has a severity" % str(lc))

func _test_t35_parser_bugs() -> void:
	# T3.5: a commented `#elif` is NOT a ghost branch anymore -- it falls to literal text.
	var src06 := "component X(c: bool = true) {\n\treturn (\n\t\t<VBoxContainer>\n\t\t\t@if (c) { return ( <Label text=\"a\" /> ) }\n\t\t\t#elif (false) { <Label text=\"b\" /> }\n\t\t</VBoxContainer>\n\t)\n}\n"
	var r06 := RuitkGuitkx.compile(src06, "X")
	_check_true(bool(r06["ok"]) and not ("elif false" in str(r06["gd"])), "T3.5: #elif is not a ghost branch (got %s)" % str(r06["diagnostics"]))

	# digit / dotted tags are parse errors now (used to emit nonsense silently).
	_check_true(not RuitkGuitkx.compile("component X() {\n\treturn ( <9foo/> )\n}\n", "X")["ok"], "T3.5: digit tag errors")
	var rdot := RuitkGuitkx.compile("component X() {\n\treturn ( <Foo.Bar/> )\n}\n", "X")
	_check_true(not rdot["ok"] and _has_code(rdot, "GUITKX0300"), "T3.5: dotted tag errors (got %s)" % str(rdot["diagnostics"]))

	# unterminated attribute string errors at the quote (used to truncate silently).
	var r09 := RuitkGuitkx.compile("component X() {\n\treturn (\n\t\t<Label text=\"oops\n\t)\n}\n", "X")
	_check_true(not r09["ok"] and _has_code(r09, "GUITKX0300"), "T3.5: unterminated attr string errors (got %s)" % str(r09["diagnostics"]))

	# directive keywords need a token boundary.
	var rb := RuitkGuitkx.compile("@class_nameFoo\ncomponent A() {\n\treturn ( <Label text=\"x\" /> )\n}\n", "A")
	_check_true(not rb["ok"] and _has_code(rb, "GUITKX2105"), "T3.5: @class_nameFoo is junk, not a directive (got %s)" % str(rb["diagnostics"]))

	# jsx_scan: markup after `or` desugars (used to emit the raw markup as invalid GDScript).
	var ror := RuitkGuitkx.compile("component O(ready: bool = false) {\n\treturn ( <VBoxContainer>{ ready or <Label text=\"waiting\" /> }</VBoxContainer> )\n}\n", "O")
	_check_true(bool(ror["ok"]), "T3.5: `or <markup>` compiles (got %s)" % str(ror["diagnostics"]))
	_check_true("if not (ready) else null" in str(ror["gd"]), "T3.5: or-desugar emitted")

func _test_t23_uss() -> void:
	# T2.3 (Unity @uss): preloads a Theme and applies it to the root element's `theme` prop.
	var src := "@uss \"res://tests/assets/test_theme.tres\"\ncomponent T() {\n\treturn ( <VBoxContainer><Label text=\"x\" /></VBoxContainer> )\n}\n"
	var r := RuitkGuitkx.compile(src, "T")
	_check_true(bool(r["ok"]), "T2.3: @uss compiles (got %s)" % str(r["diagnostics"]))
	_check(str(r["gd"]), "const __THEME := preload(\"res://tests/assets/test_theme.tres\")", "T2.3: theme preload emitted")
	_check(str(r["gd"]), "\"theme\": __THEME", "T2.3: root element receives the theme prop")

	# @theme alias behaves identically.
	var ra := RuitkGuitkx.compile("@theme \"res://tests/assets/test_theme.tres\"\ncomponent T2() {\n\treturn ( <VBoxContainer><Label text=\"x\" /></VBoxContainer> )\n}\n", "T2")
	_check_true(bool(ra["ok"]) and "__THEME" in str(ra["gd"]), "T2.3: @theme alias works")

	# an explicit root theme wins -- no injection.
	var re3 := RuitkGuitkx.compile("@uss \"res://tests/assets/test_theme.tres\"\ncomponent T3(t: Theme = null) {\n\treturn ( <VBoxContainer theme={ t }><Label text=\"x\" /></VBoxContainer> )\n}\n", "T3")
	_check_true(bool(re3["ok"]) and not ("__THEME }" in str(re3["gd"])) and str(re3["gd"]).count("\"theme\"") == 1, "T2.3: explicit theme not overridden")

	# missing path -> 0120; wrong type -> 0121; hook file -> 2210; two directives -> 2210.
	var rm := RuitkGuitkx.compile("@uss \"res://no/such/theme.tres\"\ncomponent T4() {\n\treturn ( <Label text=\"x\" /> )\n}\n", "T4")
	_check_true(not rm["ok"] and _has_code(rm, "GUITKX0120"), "T2.3: missing theme errors 0120 (got %s)" % str(rm["diagnostics"]))
	var rt2 := RuitkGuitkx.compile("@uss \"res://project.godot\"\ncomponent T5() {\n\treturn ( <Label text=\"x\" /> )\n}\n", "T5")
	_check_true(not rt2["ok"] and _has_code(rt2, "GUITKX0121"), "T2.3: non-Theme errors 0121 (got %s)" % str(rt2["diagnostics"]))
	var rh2 := RuitkGuitkx.compile("@uss \"res://tests/assets/test_theme.tres\"\nhook use_x() {\n\treturn 1\n}\n", "use_x")
	_check_true(not rh2["ok"] and _has_code(rh2, "GUITKX2210"), "T2.3: @uss in a hook file errors 2210 (got %s)" % str(rh2["diagnostics"]))
	var rd := RuitkGuitkx.compile("@uss \"res://tests/assets/test_theme.tres\"\n@uss \"res://tests/assets/test_theme.tres\"\ncomponent T6() {\n\treturn ( <Label text=\"x\" /> )\n}\n", "T6")
	_check_true(not rd["ok"] and _has_code(rd, "GUITKX2210"), "T2.3: second @uss errors (got %s)" % str(rd["diagnostics"]))

	# G-07: FileAccess.file_exists doesn't understand `uid://` -- it must never produce the (wrong)
	# "asset not found" 0120 for one. A garbage/unregistered uid:// correctly falls through to
	# ResourceLoader.exists and reports 0121 instead (proving the uid:// path is no longer
	# short-circuited into the file_exists branch at all).
	var ru := RuitkGuitkx.compile("@uss \"uid://cnonexistentgarbage\"\ncomponent T7() {\n\treturn ( <Label text=\"x\" /> )\n}\n", "T7")
	_check_true(not _has_code(ru, "GUITKX0120"), "G-07: uid:// path must never report 0120 (got %s)" % str(ru["diagnostics"]))
	_check_true(not ru["ok"] and _has_code(ru, "GUITKX0121"), "G-07: garbage uid:// falls through to 0121 (got %s)" % str(ru["diagnostics"]))

func _test_t26_naming() -> void:
	# T2.6 (Unity 2100): component names are PascalCase -- they become the generated class_name.
	var src := "component my_widget() {\n\treturn ( <Label text=\"x\" /> )\n}\n"
	var r := RuitkGuitkx.compile(src, "my_widget")
	_check_true(not r["ok"], "T2.6: lowercase component name fails")
	_check_diag_at(r, "GUITKX2100", src, "my_widget", "T2.6: 2100 lands on the name")

	# T2.6 (Unity 2203): hooks should be use_-prefixed -- warning, still compiles.
	var src_h := "hook make_thing() {\n\treturn 1\n}\n"
	var rh := RuitkGuitkx.compile(src_h, "make_thing")
	_check_true(bool(rh["ok"]), "T2.6: non-use_ hook still compiles")
	_check_diag_at(rh, "GUITKX2203", src_h, "make_thing", "T2.6: 2203 lands on the hook name")

	# T2.6: real content BEFORE the first declaration errors instead of being silently skipped.
	var src_j := "var oops = 1\ncomponent A() {\n\treturn ( <Label text=\"x\" /> )\n}\n"
	var rj := RuitkGuitkx.compile(src_j, "A")
	_check_true(not rj["ok"], "T2.6: junk before the declaration fails")
	_check_diag_at(rj, "GUITKX2105", src_j, "var oops = 1", "T2.6: leading-junk 2105 position")
	_check_true(bool(RuitkGuitkx.compile("# header\ncomponent A() {\n\treturn ( <Label text=\"x\" /> )\n}\n", "A")["ok"]), "T2.6: leading comments stay legal")

func _test_p2_markup_features() -> void:
	# T2.1: all four comment forms parse, emit nothing, and don't count as roots/children.
	var src := "component C() {\n" + \
		"\treturn (\n" + \
		"\t\t// leading note\n" + \
		"\t\t<VBoxContainer>\n" + \
		"\t\t\t/* block\n\t\t\t   note */\n" + \
		"\t\t\t<Label {/* attr note */} text=\"a\" />\n" + \
		"\t\t\t<!-- html-style -->\n" + \
		"\t\t</VBoxContainer>\n" + \
		"\t)\n}\n"
	var r := RuitkGuitkx.compile(src, "C")
	_check_true(bool(r["ok"]), "T2.1: comments compile (got %s)" % str(r["diagnostics"]))
	var gd_out := str(r["gd"])
	_check_true(not ("note" in gd_out) and not ("<!--" in gd_out), "T2.1: comments emit nothing")

	# T2.2: <Fragment> is the named alias of <> (case-insensitive, Unity PropsResolver parity).
	var src_f := "component F() {\n" + \
		"\treturn (\n\t\t<Fragment>\n\t\t\t<Label text=\"a\" />\n\t\t\t<Label text=\"b\" />\n\t\t</Fragment>\n\t)\n}\n"
	var rf := RuitkGuitkx.compile(src_f, "F")
	_check_true(bool(rf["ok"]), "T2.2: <Fragment> compiles (got %s)" % str(rf["diagnostics"]))
	_check(str(rf["gd"]), "V.fragment([", "T2.2: named fragment emits V.fragment")
	var src_fk := "component FK() {\n\treturn ( <VBoxContainer>@for (i in 3) { return ( <Fragment key={ str(i) }><Label text={ str(i) } /></Fragment> ) }</VBoxContainer> )\n}\n"
	var rfk := RuitkGuitkx.compile(src_fk, "FK")
	_check_true(bool(rfk["ok"]), "T2.2: Fragment key compiles (got %s)" % str(rfk["diagnostics"]))
	_check_true(", str(i))" in str(rfk["gd"]), "T2.2: fragment key threads to V.fragment's 2nd arg")
	var rfb := RuitkGuitkx.compile("component FB() {\n\treturn ( <Fragment visible><Label text=\"x\" /></Fragment> )\n}\n", "FB")
	_check_true(not rfb["ok"] and _has_code(rfb, "GUITKX0109"), "T2.2: non-key Fragment attr errors (got %s)" % str(rfb["diagnostics"]))

	# T2.4: mid-text braces are LITERAL + 0150 migration warning; node-start {expr} still interpolates.
	var src_t := "component T(n: int = 3) {\n\treturn ( <Label>Count: {n} items</Label> )\n}\n"
	var rt := RuitkGuitkx.compile(src_t, "T")
	_check_true(bool(rt["ok"]), "T2.4: literal-brace text compiles (got %s)" % str(rt["diagnostics"]))
	_check_true(_has_code(rt, "GUITKX0150"), "T2.4: 0150 migration warning fires")
	_check_true("Count: {n} items" in str(rt["gd"]), "T2.4: braces stay literal in emission")
	var re2 := RuitkGuitkx.compile("component E(n: int = 3) {\n\treturn ( <Label>{ n } items</Label> )\n}\n", "E")
	_check_true(bool(re2["ok"]) and not _has_code(re2, "GUITKX0150"), "T2.4: node-start expr interpolates without warning (got %s)" % str(re2["diagnostics"]))
	_check_true("str(n)" in str(re2["gd"]), "T2.4: node-start expr emits interpolation")

	# T2.1+T2.4: formatter round-trips comments and literal-brace text (idempotent, no data loss).
	const Fmt2 = preload("res://addons/reactive_ui_toolkit/guitkx/guitkx_formatter.gd")
	var f1: Dictionary = Fmt2.format(src)
	_check(str(f1["text"]), "// leading note", "T2.1: formatter preserves the leading comment")
	_check(str(f1["text"]), "{/* attr note */}", "T2.1: formatter preserves the attr comment")
	_check(str(f1["text"]), "<!-- html-style -->", "T2.1: formatter preserves the html comment")
	_check_true(str(Fmt2.format(str(f1["text"]))["text"]) == str(f1["text"]), "T2.1: comment formatting is idempotent")
	var ff: Dictionary = Fmt2.format(src_f)
	_check(str(ff["text"]), "<Fragment>", "T2.2: formatter keeps the named Fragment spelling")

func _test_t15_unknown_tags() -> void:
	# T1.5 (G5): a lowercase tag must be a real V.* factory -- it compiles to a verbatim V.<tag>()
	# call, so an unknown one was a guaranteed nonexistent-method failure at runtime.
	var src := "component T() {\n\treturn ( <VBoxContainer><lable text=\"x\" /></VBoxContainer> )\n}\n"
	var r := RuitkGuitkx.compile(src, "T")
	_check_true(not r["ok"], "T1.5: unknown lowercase tag fails the compile")
	_check_diag_at(r, "GUITKX0105", src, "lable", "T1.5: 0105 lands on the tag name")
	_check_true("did you mean <Label>" in str(_diag(r, "GUITKX0105").get("message", "")), "T1.5: did-you-mean suggests label (got %s)" % str(_diag(r, "GUITKX0105")))

	# the user's G5 repro: `<s></a>` -- mismatched close, fails, both tags implicated by the parser.
	var g5 := "component S() {\n\treturn ( <s></a> )\n}\n"
	var rg5 := RuitkGuitkx.compile(g5, "S")
	_check_true(not rg5["ok"] and _has_code(rg5, "GUITKX0302"), "T1.5/G5: <s></a> mismatched close fails (got %s)" % str(rg5["diagnostics"]))

	# PascalCase components: checked only when the caller supplies known_components.
	var pc_src := "component P() {\n\treturn ( <VBoxContainer><Cardd /></VBoxContainer> )\n}\n"
	_check_true(bool(RuitkGuitkx.compile(pc_src, "P")["ok"]), "T1.5: PascalCase unchecked without a known set")
	var rp := RuitkGuitkx.compile(pc_src, "P", ["Card", "Row"])
	_check_true(not rp["ok"], "T1.5: unknown PascalCase fails with a known set")
	_check_diag_at(rp, "GUITKX0105", pc_src, "Cardd", "T1.5: PascalCase 0105 position")
	_check_true("did you mean <Card>" in str(_diag(rp, "GUITKX0105").get("message", "")), "T1.5: suggests Card")
	_check_true(bool(RuitkGuitkx.compile("component P2() {\n\treturn ( <VBoxContainer><Card /></VBoxContainer> )\n}\n", "P2", ["Card"])["ok"]), "T1.5: known PascalCase passes")

	# module-local members are always known, regardless of the external set.
	var mod_src := "module W {\n\tcomponent Card() { return ( <Label text=\"c\" /> ) }\n\tcomponent Row() { return ( <HBoxContainer><Card /></HBoxContainer> ) }\n}\n"
	_check_true(bool(RuitkGuitkx.compile(mod_src, "W", ["SomethingElse"])["ok"]), "T1.5: module-local <Card/> resolves")

	# unknown tag nested inside a JSX-value {expr} -- the emit-only path.
	var ex_src := "component E(open: bool = false) {\n\treturn ( <VBoxContainer>{ open and <lable text=\"x\" /> }</VBoxContainer> )\n}\n"
	var re := RuitkGuitkx.compile(ex_src, "E")
	_check_true(not re["ok"] and _has_code(re, "GUITKX0105"), "T1.5: unknown tag inside {expr} caught (got %s)" % str(re["diagnostics"]))

	# codegen integration: known_component_names resolves sibling bindings + @class_name overrides.
	var names: Array = Codegen.known_component_names([])
	_check_true(names is Array, "T1.5: known_component_names runs headless (global classes only)")

func _test_t13_single_decl() -> void:
	# 0.10.0 MIXED-DECL v1: several top-level declarations in one file are now LEGAL (they were a
	# GUITKX2105 error until this leg). The binding = first EXPORTED decl; it emits `render`, the rest
	# emit static funcs named after the decl. Content that is NOT a declaration still errors.
	var src := "export component A() {\n\treturn ( <Label /> )\n}\n\ncomponent B() {\n\treturn ( <Label /> )\n}\n"
	var r := RuitkGuitkx.compile(src, "A")
	_check_true(r["ok"], "mixed-decl: two top-level components compile (%s)" % str(r.get("diagnostics", [])))
	_check_true((r["gd"] as String).contains("class_name A"), "mixed-decl: binding = first exported decl")
	_check_true((r["gd"] as String).contains("static func render(") and (r["gd"] as String).contains("static func B("), "mixed-decl: binding -> render, non-binding -> its own name")

	# genuinely non-declaration content BETWEEN declarations still errors (GUITKX2105).
	var src_j := "component A() {\n\treturn ( <Label /> )\n}\nvar oops = 1\ncomponent B() { return ( <Label /> ) }\n"
	var r_j := RuitkGuitkx.compile(src_j, "A")
	_check_true(not r_j["ok"], "mixed-decl: non-declaration content between decls errors")
	_check_diag_at(r_j, "GUITKX2105", src_j, "var oops = 1", "mixed-decl: 2105 lands on the junk between decls")

	# trailing comments after the declaration stay legal.
	var src_c := "component A() {\n\treturn ( <Label /> )\n}\n# trailing note\n"
	_check_true(RuitkGuitkx.compile(src_c, "A")["ok"], "T1.3: trailing comments after the declaration are fine")

	# hook files too (the hook path now parses via _parse_hook_at and knows where it ends).
	var src_h := "hook use_x() {\n\treturn 1\n}\nstray text\n"
	var r_h := RuitkGuitkx.compile(src_h, "use_x")
	_check_true(not r_h["ok"], "T1.3: trailing junk after a hook fails the compile")
	_check_diag_at(r_h, "GUITKX2105", src_h, "stray text", "T1.3: hook trailing 2105 lands on the junk")

	# junk BETWEEN module members used to vanish silently (_find_decl skipped it).
	var src_m := "module M {\n\tcomponent A() { return ( <Label /> ) }\n\tvar oops = 1\n\thook use_y() { return 2 }\n}\n"
	var r_m := RuitkGuitkx.compile(src_m, "M")
	_check_true(not r_m["ok"], "T1.3: junk between module members fails the compile")
	_check_diag_at(r_m, "GUITKX2105", src_m, "var oops = 1", "T1.3: module junk 2105 lands on the junk")

func _test_return_null_guard() -> void:
	# [audit #19] `return null` as a conditional guard before the real markup return must compile.
	var src := "component G(show: bool = false) {\n" + \
		"\tif not show:\n\t\treturn null\n" + \
		"\treturn ( <Label text=\"ok\" /> )\n}\n"
	var res := RuitkGuitkx.compile(src, "G")
	if not res["ok"]:
		_fail("return_null_guard: compile failed: " + str(res["diagnostics"]))
	var gd: String = res["gd"]
	_check_true("return null" in gd, "guard `return null` preserved in setup")
	_check(gd, "V.Label(", "real markup return still emitted")

# Phase D acceptance: the Unity kitchen-sink nesting translated to guitkx -- 4 directive levels
# (@for -> markup -> @if/@else -> @for -> @if -> @for), prep vars at every level, a prep-markup
# variable consumed via {expr}, a `return null` skip-guard, and an @else arm -- compiled, parsed,
# MOUNTED, and the exact rendered Label count asserted (null-skip and branch choice are load-bearing).
func _test_phase_d_bodies() -> void:
	var src := """component Deep(cats: Array = ["A", "B"], n: int = 2, mode: String = "x") {
	var pills = ["x", "y", "z"]
	return (
		<VBoxContainer>
			@for (cat in cats) {
				var badge = (
					<HBoxContainer>
						<Label text={ cat } />
						@if (mode != "") {
							return ( <Label text={ "[" + mode + "]" } /> )
						}
					</HBoxContainer>
				)
				return (
					<VBoxContainer key={ cat }>
						{ badge }
						@for (d in n) {
							var frac := float(d) / maxi(1, n - 1)
							return (
								<VBoxContainer key={ cat + str(d) }>
									<Label text={ "depth %d %.1f" % [d, frac] } />
									@if (d % 2 == 0) {
										var slot = "even " + cat
										return (
											<HBoxContainer>
												<Label text={ slot } />
												@for (tag in pills) {
													if tag == "z" and d == 0:
														return null
													return ( <Label key={ tag } text={ tag } /> )
												}
											</HBoxContainer>
										)
									} @else {
										return ( <Label text="odd" /> )
									}
								</VBoxContainer>
							)
						}
					</VBoxContainer>
				)
			}
		</VBoxContainer>
	)
}"""
	var r := RuitkGuitkx.compile(src, "Deep")
	if not bool(r["ok"]):
		_fail("phase_d_bodies: compile failed: " + str(r["diagnostics"]))
		return
	var sc := GDScript.new()
	sc.source_code = str(r["gd"]).replace("class_name Deep\n", "")
	if sc.reload() != OK:
		_fail("phase_d_bodies: generated .gd does not parse:\n" + str(r["gd"]))
		return
	var c := Control.new()
	root.add_child(c)
	var inst = sc.new()
	var app := RuitkRoot.create(c, V.fc(inst.render, {}))
	var count := _count_labels(c)
	# per cat: badge (cat + [mode]) = 2; d=0 even: depth + slot + pills minus z = 4; d=1 odd: depth + odd = 2
	# -> 8 per cat x 2 cats = 16. The z-skip at d=0 and the @else arm are both load-bearing here.
	_check_true(count == 16, "phase D 4-deep render: 16 labels expected, got %d" % count)
	app.unmount()
	c.free()

func _count_labels(node: Node) -> int:
	var n := 1 if node is Label else 0
	for ch in node.get_children():
		n += _count_labels(ch)
	return n

func _test_formatter() -> void:
	const Fmt = preload("res://addons/reactive_ui_toolkit/guitkx/guitkx_formatter.gd")
	var src := "component  Foo( name: String = \"x\" )  {\n" + \
		"  var s = useState(0)\n" + \
		"  return (\n" + \
		"<VBoxContainer>\n" + \
		"<Label text={ name }/>\n" + \
		"@if (s[0] > 0) { return ( <Label text=\"big\" /> ) }\n" + \
		"</VBoxContainer>\n" + \
		"  )\n" + \
		"}\n"
	var r1 := Fmt.format(src)
	_check_true(r1["ok"], "formatter ok")
	var f1: String = r1["text"]
	print("--- formatted ---\n" + f1 + "---")
	_check(f1, "component Foo(name: String = \"x\") {", "header canonicalized")
	_check(f1, "    <VBoxContainer>", "markup indented (spaces-2 default, Phase D)")
	_check(f1, "<Label text={ name } />", "self-close spacing")
	_check(f1, "@if (s[0] > 0) {", "control flow formatted")
	# idempotency
	var f2: String = Fmt.format(f1)["text"]
	_check_true(f1 == f2, "idempotent: format(format(x)) == format(x)")
	# parse error -> verbatim (never corrupt)
	var bad := "component Broken( {\n\treturn ( <Label/> \n}\n"
	_check_true(Fmt.format(bad)["text"] == bad, "parse error -> source returned verbatim")

func _test_formatter_options() -> void:
	# [audit #16] insertSpaceBeforeSelfClose must be honored in the multi-attribute WRAP path, not
	# only the single-line path. With singleAttributePerLine the element wraps; the close must respect
	# the option.
	const Fmt = preload("res://addons/reactive_ui_toolkit/guitkx/guitkx_formatter.gd")
	var src := "component W() {\n\treturn ( <Label aaa=\"1\" bbb=\"2\" ccc=\"3\" /> )\n}\n"
	var no_space: String = Fmt.format(src, { "singleAttributePerLine": true, "insertSpaceBeforeSelfClose": false })["text"]
	_check_true(no_space.contains("/>") and not no_space.contains(" />"), "wrap path honors insertSpaceBeforeSelfClose=false")
	var with_space: String = Fmt.format(src, { "singleAttributePerLine": true })["text"]
	_check_true(with_space.contains(" />"), "wrap path default keeps the space before />")

## 0.9.0 naming loyalty (plans/NAMING_LOYALTY_PROPOSAL.md): open tag vocabulary, renamed-tag
## hints, and the engine-name-reserved warning.
func _test_loyal_naming_090() -> void:
	# Open vocabulary: a ClassDB Control with no curated factory compiles via the generic V.h.
	var open := RuitkGuitkx.compile("component O() {\n\treturn ( <GraphEdit /> )\n}\n", "O")
	_check_true(bool(open["ok"]), "open vocabulary: <GraphEdit> compiles (got %s)" % str(open["diagnostics"]))
	_check(str(open["gd"]), "V.h(\"GraphEdit\"", "open vocabulary emits V.h(\"GraphEdit\", ...)")
	# A curated tag still emits its named factory, not V.h.
	var cur := RuitkGuitkx.compile("component C() {\n\treturn ( <Panel /> )\n}\n", "C")
	_check(str(cur["gd"]), "V.Panel(", "<Panel> is Godot's Panel via the named factory")
	# A pre-0.9 shorthand gets the exact rename, not a generic did-you-mean. (The PascalCase
	# unknown-tag check arms only with a non-empty known-components set — plugin semantics.)
	var renamed := RuitkGuitkx.compile("component R() {\n\treturn ( <VBox /> )\n}\n", "R", ["SomeComp"])
	_check_true(not bool(renamed["ok"]), "removed shorthand <VBox> no longer compiles")
	var hit := false
	for d in renamed["diagnostics"]:
		if d["code"] == "GUITKX0105" and "renamed in 0.9.0" in str(d["message"]) and "VBoxContainer" in str(d["message"]):
			hit = true
	_check_true(hit, "<VBox> diagnostic carries the exact rename (got %s)" % str(renamed["diagnostics"]))
	# Engine names are reserved: a known component that shadows a Godot class warns (0151)
	# but the compile stays ok and the ENGINE element wins.
	var shadowed := RuitkGuitkx.compile("component S() {\n\treturn ( <Panel /> )\n}\n", "S", ["Panel", "SomeComp"])
	_check_true(bool(shadowed["ok"]), "shadowed engine tag still compiles")
	_check(str(shadowed["gd"]), "V.Panel(", "the engine element wins over the shadowing component")
	var warned := false
	for d in shadowed["diagnostics"]:
		if d["code"] == "GUITKX0151":
			warned = true
	_check_true(warned, "GUITKX0151 warns that the component is shadowed (got %s)" % str(shadowed["diagnostics"]))
	# The removed lowercase element tags error too (structural lowercase factories stay valid).
	var low := RuitkGuitkx.compile("component L() {\n\treturn ( <vbox /> )\n}\n", "L")
	_check_true(not bool(low["ok"]), "removed lowercase <vbox> no longer compiles")

func _test_vocabulary() -> void:
	# T0.3: vocabulary.json is the single source of truth. The compiler tables must come from it…
	_check_true(RuitkGuitkx.host_tags().get("VBoxContainer", "") == "VBoxContainer" and RuitkGuitkx.host_tags().size() >= 39,
		"host_tags() loaded from vocabulary.json (aliases included, got %d)" % RuitkGuitkx.host_tags().size())
	_check_true("useState" in RuitkGuitkx.hook_names() and RuitkGuitkx.hook_names().size() == 23,
		"hook_names() loaded from vocabulary.json (got %d)" % RuitkGuitkx.hook_names().size())
	# …and v_factories must mirror the REAL public V API (reflection tripwire: adding/removing a
	# static func on core/v.gd without updating vocabulary.json fails here with the exact diff).
	var v_script: Script = preload("res://addons/reactive_ui_toolkit/core/v.gd")
	var reflected: Array = []
	for m in v_script.get_script_method_list():
		var mname: String = m["name"]
		if not mname.begins_with("_") and not (mname in reflected):
			reflected.append(mname)
	reflected.sort()
	var vocab: Array = (RuitkGuitkx.v_factories() as Array).duplicate()
	vocab.sort()
	_check_true(str(reflected) == str(vocab),
		"vocabulary.v_factories mirrors core/v.gd public statics\n  reflected: %s\n  vocabulary: %s" % [str(reflected), str(vocab)])

func _test_markup_corpus() -> void:
	# the SHARED markup-AST corpus also asserted by the TS parseMarkup test — proves guitkx_markup.gd
	# and markup.ts parse identically (incl. `<`/`>` inside {expr}, the structural-fix bug class).
	const M = preload("res://addons/reactive_ui_toolkit/guitkx/guitkx_markup.gd")
	var raw := FileAccess.get_file_as_string("res://ide-extensions/lsp-server/test-fixtures/markup-cases.json")
	var corpus = JSON.parse_string(raw)
	_check_true(corpus != null and corpus.size() >= 13, "markup corpus loaded")
	for c in corpus:
		var p = M.new()
		var r: Dictionary = p.parse(c["input"], 0, (c["input"] as String).length())
		_check_true(r["error"] == c["error"], "markup corpus error '%s'" % c["name"])
		_check_true(JSON.stringify(r["nodes"]) == c["tree"], "markup corpus tree '%s'" % c["name"])

func _test_formatter_corpus() -> void:
	# the SHARED golden corpus also asserted by the TS formatGuitkx test — proves the two formatters
	# are byte-identical. Regression-guards the GDScript side against future drift.
	const Fmt = preload("res://addons/reactive_ui_toolkit/guitkx/guitkx_formatter.gd")
	var raw := FileAccess.get_file_as_string("res://ide-extensions/lsp-server/test-fixtures/formatter-cases.json")
	var corpus = JSON.parse_string(raw)
	_check_true(corpus != null and corpus.size() >= 9, "formatter corpus loaded")
	for c in corpus:
		var got: String = Fmt.format(c["input"])["text"]
		_check_true(got == c["expected"], "formatter corpus '%s'" % c["name"])
		_check_true(Fmt.format(got)["text"] == got, "formatter corpus idempotent '%s'" % c["name"])
	# Unity-style real-file idempotency: format(format(sample)) == format(sample) on every .guitkx.
	const Codegen = preload("res://addons/reactive_ui_toolkit/guitkx/guitkx_codegen.gd")
	for path in Codegen.find_all("res://examples"):
		var src := FileAccess.get_file_as_string(path)
		var f1: String = Fmt.format(src)["text"]
		_check_true(Fmt.format(f1)["text"] == f1, "sample format idempotent: %s" % path)

func _test_format_unsafe_str_attr() -> void:
	# G-05: the parser can't produce a `str` attr value with an embedded `"` today, so this
	# constructs the AST node directly to prove the safety net itself works if that ever changes.
	const Fmt = preload("res://addons/reactive_ui_toolkit/guitkx/guitkx_formatter.gd")
	var o := { "_unsafe_str_attr": false }
	Fmt._fmt_attr({ "kind": "str", "name": "text", "value": "safe" }, o)
	_check_true(bool(o["_unsafe_str_attr"]) == false, "a normal str attr must not flag unsafe")
	Fmt._fmt_attr({ "kind": "str", "name": "text", "value": "has \" inside" }, o)
	_check_true(bool(o["_unsafe_str_attr"]) == true, "an embedded quote must flag unsafe")

func _test_format_fell_back() -> void:
	# G-06: fell_back distinguishes a parse-error fallback from an already-canonical file.
	const Fmt = preload("res://addons/reactive_ui_toolkit/guitkx/guitkx_formatter.gd")
	var broken := "component Broken {\n  return (\n    <Label text=\"x\"\n  )\n}\n"   # unclosed tag
	var r1: Dictionary = Fmt.format(broken)
	_check_true(r1["text"] == broken, "verbatim on parse error")
	_check_true(bool(r1["fell_back"]) == true, "parse error must report fell_back")

	var r2: Dictionary = Fmt.format("")
	_check_true(bool(r2["fell_back"]) == false, "nothing-to-format is not a syntax-error fallback")

	var canonical := "component Ok {\n  return (\n    <Label text=\"x\" />\n  )\n}\n"
	var r3: Dictionary = Fmt.format(canonical)
	_check_true(bool(r3["changed"]) == false, "already canonical")
	_check_true(bool(r3["fell_back"]) == false, "an already-canonical file must not report fell_back")

func _test_scanner_fixtures() -> void:
	# byte-identity cross-test: the SAME corpus the TS scanner.ts asserts on (prevents lexer drift)
	const L = preload("res://addons/reactive_ui_toolkit/guitkx/guitkx_lexer.gd")
	var txt := FileAccess.get_file_as_string("res://ide-extensions/lsp-server/test-fixtures/scanner-cases.json")
	if txt == "":
		_fail("scanner fixtures not found / empty")
		return
	var fx = JSON.parse_string(txt)
	for c in fx["skipNoncode"]:
		var got: int = L.skip_noncode(c["input"], int(c["at"]))
		_check_true(got == int(c["expect"]), "skip_noncode(%s, %d) = %d expected %d" % [c["input"], int(c["at"]), got, int(c["expect"])])
	for c in fx["findMatching"]:
		var got2: int = L.find_matching(c["input"], int(c["at"]))
		_check_true(got2 == int(c["expect"]), "find_matching(%s, %d) = %d expected %d" % [c["input"], int(c["at"]), got2, int(c["expect"])])
	# G-01: the markup-lexis mode-aware counterparts (find_matching_markup skips `#` as literal and
	# `//`/`/* */`/`<!-- -->` as comments -- see guitkx_lexer.gd's docstring).
	for c in fx["skipNoncodeMarkup"]:
		var got3: int = L.skip_noncode_markup(c["input"], int(c["at"]))
		_check_true(got3 == int(c["expect"]), "skip_noncode_markup(%s, %d) = %d expected %d" % [c["input"], int(c["at"]), got3, int(c["expect"])])
	for c in fx["findMatchingMarkup"]:
		var got4: int = L.find_matching_markup(c["input"], int(c["at"]))
		_check_true(got4 == int(c["expect"]), "find_matching_markup(%s, %d) = %d expected %d" % [c["input"], int(c["at"]), got4, int(c["expect"])])

## G-23 regression (compile-level): a parenthetical comment split across two `#`/`##` lines in a
## component's setup prelude desynced find_matching_markup (the prelude was scanned as markup, so
## the comment's `(` opened a code island whose `)` on the next comment line was comment-skipped)
## -- surfacing as a bogus GUITKX0304 "unclosed component body". The exact shape that bit
## examples/demos/doom/doom_game_screen.guitkx.
func _test_g23_prelude_comments() -> void:
	var src := "component G23(title: String = \"\") {\n" + \
		"\t## Faithful port of the per-column texture windowing (BackgroundSize +\n" + \
		"\t## BackgroundPositionX/Y in the original): select the texel column.\n" + \
		"\t# note: early return (see docs\n" + \
		"\t# and { weird unbalanced\n" + \
		"\tvar msg := title\n" + \
		"\treturn (\n" + \
		"\t\t<PanelContainer>\n" + \
		"\t\t\t<Label text={ msg } />\n" + \
		"\t\t</PanelContainer>\n" + \
		"\t)\n" + \
		"}\n"
	var r := RuitkGuitkx.compile(src, "G23")
	_check_true(bool(r["ok"]), "G-23: split-paren prelude comments compile clean (got %s)" % str(r.get("diagnostics", [])))
	if r["ok"]:
		_check(r["gd"], "static func render", "G-23: render emitted")
	# Directive-body prelude: same comment shape inside an @for body.
	var src2 := "component G23b() {\n" + \
		"\tvar xs := [1, 2]\n" + \
		"\treturn (\n" + \
		"\t\t<VBoxContainer>\n" + \
		"\t\t\t@for (x in xs) {\n" + \
		"\t\t\t\t# per-item note (one\n" + \
		"\t\t\t\t# and two) done\n" + \
		"\t\t\t\treturn ( <Label text={ str(x) } /> )\n" + \
		"\t\t\t}\n" + \
		"\t\t</VBoxContainer>\n" + \
		"\t)\n" + \
		"}\n"
	var r2 := RuitkGuitkx.compile(src2, "G23b")
	_check_true(bool(r2["ok"]), "G-23: split-paren comment in a directive body compiles clean (got %s)" % str(r2.get("diagnostics", [])))

func _test_deep_flatten() -> void:
	# V._norm must deep-flatten nested arrays (Phase 4 §5: .map().map() children) + drop nulls at depth
	var a := V.Label({})
	var b := V.Button({})
	var d := V.Label({})
	var flat: Array = V._norm([a, [b, [d]]])
	_check_true(flat.size() == 3, "deep _norm flattens nested arrays (got %d)" % flat.size())
	_check_true(flat[0] == a and flat[1] == b and flat[2] == d, "deep _norm preserves order")
	var flat2: Array = V._norm([a, [null, [b, null]], null])
	_check_true(flat2.size() == 2, "deep _norm drops nested nulls (got %d)" % flat2.size())

# First diagnostic with `code` from a compile() result, or {} — T0.2 structured-diag test helper.
## M1 (0.10.0 imports leg): the import/export GRAMMAR + scan. Emission is unchanged this milestone
## (single binding decl); these cover preamble parsing, the `export` prefix, malformed-import errors,
## and the order-agnostic binding scan (`@class_name` after an import must still win).
func _test_imports_m1() -> void:
	# --- import parse forms accepted, stored on the result, and non-fatal to a normal compile ---
	var one := "import { StatusChip } from \"./status_chip\"\n\ncomponent A() {\n\treturn ( <Label /> )\n}\n"
	var r_one := RuitkGuitkx.compile(one, "A")
	_check_true(r_one["ok"], "M1: a single import line compiles (%s)" % str(r_one.get("diagnostics", [])))
	_check_true((r_one.get("imports", []) as Array).size() == 1, "M1: one import parsed and threaded onto the result")
	if (r_one.get("imports", []) as Array).size() == 1:
		var imp0: Dictionary = r_one["imports"][0]
		_check_true(str(imp0.get("spec", "")) == "./status_chip", "M1: import specifier captured verbatim")
		_check_true((imp0.get("names", []) as Array).size() == 1 and str(imp0["names"][0]["name"]) == "StatusChip", "M1: import name captured")

	# multi-name + `~/` root alias + `../` relative, in any preamble order relative to @class_name.
	var multi := "import { A, B } from \"~/demos/x\"\nimport { C } from \"../y\"\n@class_name Widget\n\ncomponent Thing() {\n\treturn ( <Label /> )\n}\n"
	var r_multi := RuitkGuitkx.compile(multi, "Thing")
	_check_true(r_multi["ok"], "M1: multi-name + ~/ + ../ imports before @class_name compile (%s)" % str(r_multi.get("diagnostics", [])))
	_check_true((r_multi.get("imports", []) as Array).size() == 2, "M1: two import lines parsed")
	_check_true((r_multi["imports"][0]["names"] as Array).size() == 2, "M1: `{ A, B }` yields two names")

	# @class_name AFTER an import must still bind the file (order-agnostic scan, §6.2 latent-bug fix).
	_check_true(Codegen._binding_name(multi) == "Widget", "M1: @class_name after imports wins the binding")
	# @uss before @class_name likewise (the other order case).
	var uss_first := "@uss \"res://theme.tres\"\n@class_name Themed\ncomponent T() { return ( <Label /> ) }\n"
	_check_true(Codegen._binding_name(uss_first) == "Themed", "M1: @class_name after @uss wins the binding")

	# --- the `export` prefix on each declaration kind is accepted; binding is unchanged ---
	var ec := "export component Exp() {\n\treturn ( <Label /> )\n}\n"
	var r_ec := RuitkGuitkx.compile(ec, "Exp")
	_check_true(r_ec["ok"], "M1: `export component` compiles (%s)" % str(r_ec.get("diagnostics", [])))
	_check_true(bool(r_ec.get("binding_export", false)), "M1: exported binding flagged on the result")
	_check_true(Codegen._binding_name(ec) == "Exp", "M1: `export component` binds to its name")
	var eh := "export hook use_thing() -> int {\n\treturn 1\n}\n"
	_check_true(RuitkGuitkx.compile(eh, "use_thing")["ok"], "M1: `export hook` compiles")
	var em := "export module Styles {\n\thook use_x() { return 1 }\n}\n"
	_check_true(RuitkGuitkx.compile(em, "Styles")["ok"], "M1: `export module` compiles")

	# a private (unexported) decl is still a legal file this milestone (privacy semantics land in M2).
	_check_true(RuitkGuitkx.compile("component Priv() { return ( <Label /> ) }\n", "Priv")["ok"], "M1: unexported decl still compiles")

	# --- malformed imports are GUITKX0300 errors and fail the compile ---
	var no_from := "import { A } \"./x\"\ncomponent C() { return ( <Label /> ) }\n"
	var r_nf := RuitkGuitkx.compile(no_from, "C")
	_check_true(not r_nf["ok"], "M1: import without `from` fails")
	_check_true(_has_code(r_nf, "GUITKX0300"), "M1: missing `from` -> GUITKX0300")

	# G-05 (ES-modules leg, supersedes the 0.10.0 named-only lock): `import A from "./x"` is now
	# the DEFAULT-import form and parses clean; a truly headless caller leaves it inert.
	var default_form := "import A from \"./x\"\ncomponent C() { return ( <Label /> ) }\n"
	var r_df := RuitkGuitkx.compile(default_form, "C")
	_check_true(not _has_code(r_df, "GUITKX0300"), "G-05: default-import form parses (got %s)" % str(r_df.get("diagnostics", [])))
	var no_clause := "import from \"./x\"\ncomponent C() { return ( <Label /> ) }\n"
	_check_true(_has_code(RuitkGuitkx.compile(no_clause, "C"), "GUITKX0300"), "M1: import with no clause -> GUITKX0300")

	var empty_braces := "import { } from \"./x\"\ncomponent C() { return ( <Label /> ) }\n"
	_check_true(_has_code(RuitkGuitkx.compile(empty_braces, "C"), "GUITKX0300"), "M1: empty `{ }` -> GUITKX0300")

	var unterminated := "import { A } from \"./x\ncomponent C() { return ( <Label /> ) }\n"
	_check_true(_has_code(RuitkGuitkx.compile(unterminated, "C"), "GUITKX0300"), "M1: unterminated specifier -> GUITKX0300")

	var bad_name := "import { 9bad } from \"./x\"\ncomponent C() { return ( <Label /> ) }\n"
	_check_true(_has_code(RuitkGuitkx.compile(bad_name, "C"), "GUITKX0300"), "M1: non-identifier import name -> GUITKX0300")

	# an import line must NOT be mistaken for stray content-before-decl (GUITKX2105).
	_check_true(not _has_code(r_one, "GUITKX2105"), "M1: a valid import never trips the 2105 junk check")

## Assert the emitted .gd actually PARSES as GDScript (the throwaway-reload check the codegen runs),
## with the `class_name` line stripped so it can't collide with the scanned global class.
func _gd_parses(gd: String) -> bool:
	var chk := GDScript.new()
	var src := gd
	if src.begins_with("class_name "):
		src = src.substr(src.find("\n") + 1)
	chk.source_code = src
	return chk.reload() == OK

## M2 (0.10.0): MIXED-DECL v1 emission (§6.3) — several declarations in one file, privacy, __RUI_DECLS.
func _test_mixed_decl() -> void:
	# --- exported binding + private component: binding -> render, private -> its name, class_name set ---
	var mc := "export component Hud() {\n\treturn ( <LocalRow /> )\n}\n\ncomponent LocalRow() {\n\treturn ( <Label text=\"r\" /> )\n}\n"
	var r := RuitkGuitkx.compile(mc, "hud")
	_check_true(r["ok"], "mixed: exported binding + private component compiles (%s)" % str(r.get("diagnostics", [])))
	var gd: String = r["gd"]
	_check_true(gd.contains("class_name Hud"), "mixed: class_name = binding (first exported)")
	_check_true(gd.contains("static func render(") and gd.contains("static func LocalRow("), "mixed: binding->render, private->name")
	_check_true(gd.contains("const __RUI_KIND := \"mixed\""), "mixed: __RUI_KIND is 'mixed'")
	_check_true(gd.contains("const __RUI_DECLS := {"), "mixed: __RUI_DECLS emitted")
	_check_true(gd.contains("\"Hud\": { \"kind\": \"component\"") and gd.contains("\"export\": true"), "mixed: __RUI_DECLS records binding export")
	_check_true(gd.contains("\"LocalRow\": { \"kind\": \"component\"") and gd.contains("\"export\": false"), "mixed: __RUI_DECLS records private decl")
	# the binding's markup references LocalRow -> a bare sibling static-func call, not V.comp.
	_check_true(gd.contains("V.fc(LocalRow"), "mixed: intra-file component ref lowers to the sibling static func")
	_check_true(_gd_parses(gd), "mixed: emitted mixed .gd parses as GDScript")

	# --- binding preference: the first EXPORTED decl wins over decl order (privacy: the non-exported
	# decl becomes a private static func, never the file's public `render`). A fully-unexported file
	# still binds to its first decl (back-compat until strict mode + the codemod land). ---
	var mixp := "component Helper() {\n\treturn ( <Label /> )\n}\n\nexport component Main() {\n\treturn ( <Label /> )\n}\n"
	var rmp := RuitkGuitkx.compile(mixp, "file")
	_check_true(rmp["ok"] and (rmp["gd"] as String).contains("class_name Main"), "mixed: first EXPORTED decl wins the binding over decl order")
	_check_true((rmp["gd"] as String).contains("static func render(") and (rmp["gd"] as String).contains("static func Helper("), "mixed: exported binding -> render; non-exported -> a private named func")
	_check_true(_gd_parses(rmp["gd"]), "mixed: emitted .gd parses")

	var noexp := "component A() {\n\treturn ( <Label /> )\n}\n\ncomponent B() {\n\treturn ( <Label /> )\n}\n"
	var rne := RuitkGuitkx.compile(noexp, "ab")
	_check_true(rne["ok"] and (rne["gd"] as String).contains("class_name A"), "mixed: a zero-export file binds to its first decl (back-compat)")
	_check_true(_gd_parses(rne["gd"]), "mixed: zero-export file parses")

	# --- component + top-level hook: hook emits a static func; a bare call to it stays un-prefixed ---
	var ch := "export component Panel() {\n\tvar d = use_blink(0.5)\n\treturn ( <Label text={d} /> )\n}\n\nexport hook use_blink(interval: float) -> float {\n\treturn interval\n}\n"
	var rc := RuitkGuitkx.compile(ch, "panel")
	_check_true(rc["ok"], "mixed-hook: component + top-level hook compiles (%s)" % str(rc.get("diagnostics", [])))
	_check_true((rc["gd"] as String).contains("static func use_blink("), "mixed-hook: top-level hook emits a static func")
	_check_true((rc["gd"] as String).contains("use_blink(0.5)") and not (rc["gd"] as String).contains("Hooks.use_blink("), "mixed-hook: sibling hook call stays un-prefixed (not Hooks.*)")
	_check_true((rc["gd"] as String).contains("\"use_blink\": { \"kind\": \"hook\""), "mixed-hook: __RUI_DECLS records the hook")
	_check_true(_gd_parses(rc["gd"]), "mixed-hook: emitted .gd parses")

	# --- component + module: module lowers to an inner `class Name:` block ---
	var cm := "export component Screen() {\n\treturn ( <Label /> )\n}\n\nexport module Styles {\n\thook use_tint() -> Color { return Color.RED }\n}\n"
	var rm := RuitkGuitkx.compile(cm, "screen")
	_check_true(rm["ok"], "mixed-module: component + module compiles (%s)" % str(rm.get("diagnostics", [])))
	_check_true((rm["gd"] as String).contains("class Styles:"), "mixed-module: non-binding module -> inner class")
	_check_true((rm["gd"] as String).contains("\n\tstatic func use_tint("), "mixed-module: module member indented one level inside the inner class")
	_check_true((rm["gd"] as String).contains("\"Styles\": { \"kind\": \"module\""), "mixed-module: __RUI_DECLS records the module")
	_check_true(_gd_parses(rm["gd"]), "mixed-module: emitted .gd parses")

	# --- @class_name override wins the binding over the first-exported rule ---
	# It names First (an unexported decl), so First becomes the binding component and emits render,
	# even though Second is the first EXPORTED decl.
	var ov := "@class_name First\ncomponent First() {\n\treturn ( <Label /> )\n}\nexport component Second() {\n\treturn ( <Label /> )\n}\n"
	var ro := RuitkGuitkx.compile(ov, "file")
	_check_true(ro["ok"] and (ro["gd"] as String).contains("class_name First"), "mixed: @class_name overrides the first-exported binding")
	_check_true((ro["gd"] as String).contains("static func render(") and (ro["gd"] as String).contains("static func Second("), "mixed: the @class_name'd component emits render, the other its name")

## M4 (0.10.0): the reverse-edge-staleness + two-pass PRIMITIVES (the integration is exercised by
## the green compile_all/guitkx_build two-pass; here we pin the building blocks).
func _test_m4() -> void:
	var eh1 := Codegen.export_hash(Codegen.exports_of("export component A() { return ( <Label /> ) }\n"))
	var eh2 := Codegen.export_hash(Codegen.exports_of("export component A() { return ( <Label /> ) }\n"))
	var eh3 := Codegen.export_hash(Codegen.exports_of("export component B() { return ( <Label /> ) }\n"))
	_check_true(eh1 == eh2, "M4: export_hash is stable for an identical export table")
	_check_true(eh1 != eh3, "M4: export_hash moves when the export table changes (drives reverse-edge staleness)")
	# exports_of = exported decls only; the binding component's cross-file func is `render`.
	var ex := Codegen.exports_of("export component Main() { return ( <Label /> ) }\ncomponent Priv() { return ( <Label /> ) }\n")
	_check_true(ex.size() == 1 and str(ex[0]["name"]) == "Main" and str(ex[0]["func"]) == "render", "M4: exports_of drops private decls; binding func = render")
	var ex2 := Codegen.exports_of("export hook use_x() -> int { return 1 }\n")
	_check_true(ex2.size() == 1 and str(ex2[0]["kind"]) == "hook" and str(ex2[0]["func"]) == "use_x", "M4: exported hook carries its own func name")
	# the counted-gate parse primitive.
	_check_true(Codegen.gd_source_parses("class_name X\nextends RefCounted\nstatic func f() -> int:\n\treturn 1\n"), "M4: gd_source_parses accepts a valid script")
	_check_true(not Codegen.gd_source_parses("class_name X\nextends RefCounted\nstatic func f( -> int:\n\treturn 1\n"), "M4: gd_source_parses rejects a broken script (counted-gate primitive)")

## M6 (0.10.0): the migration CODEMOD -- export-everything + synthesized imports, idempotent, ambient
## names left import-free. In-memory (no writes); the whole-tree run is a separate CI step.
func _test_codemod() -> void:
	const Migrate := preload("res://addons/reactive_ui_toolkit/guitkx/guitkx_migrate.gd")
	var ref := { "StatusChip": "res://ui/chip.guitkx", "HudHooks": "res://ui/hooks.guitkx", "Panel": "res://ui/panel.guitkx", "Far": "res://other/far.guitkx" }
	# Panel uses <StatusChip/> (markup tag) + HudHooks.use_x() (qualified) + DoomTypes.X (ambient hand class).
	var src := "component Panel() {\n\tvar d = HudHooks.use_x()\n\tvar t = DoomTypes.THING\n\treturn ( <StatusChip /> )\n}\n"
	var r := Migrate.migrate_source("res://ui/panel.guitkx", src, ref)
	_check_true(r["changed"], "codemod: file changed")
	var out: String = r["source"]
	_check_true(out.contains("export component Panel"), "codemod: export prefix added to the decl")
	_check_true(out.contains("import { StatusChip } from \"./chip\""), "codemod: markup-tag ref imported (%s)" % out)
	_check_true(out.contains("import { HudHooks } from \"./hooks\""), "codemod: qualified ref imported")
	_check_true(not out.contains("import { DoomTypes"), "codemod: ambient hand-class ref NOT imported")
	_check_true(out.contains("DoomTypes.THING"), "codemod: ambient ref left untouched in the body")
	_check_true(not out.contains("import { Panel"), "codemod: own decl not self-imported")
	# import block sits before the decl.
	_check_true(out.find("import {") < out.find("export component Panel"), "codemod: imports precede the first decl")

	# idempotent: a second run over the migrated output is a no-op.
	_check_true(not Migrate.migrate_source("res://ui/panel.guitkx", out, ref)["changed"], "codemod: idempotent (second run no-op)")

	# cross-directory references use a ~/-rooted specifier.
	var r2 := Migrate.migrate_source("res://ui/p.guitkx", "component P() { return ( <Far /> ) }\n", ref)
	_check_true((r2["source"] as String).contains("import { Far } from \"~/other/far\""), "codemod: cross-dir ref uses ~/ specifier (%s)" % r2["source"])

	# an already-migrated file (export + import present) is stable.
	var pre := "import { StatusChip } from \"./chip\"\n\nexport component Q() {\n\treturn ( <StatusChip /> )\n}\n"
	_check_true(not Migrate.migrate_source("res://ui/q.guitkx", pre, ref)["changed"], "codemod: already-migrated file untouched")

## Regression tests for the adversarial bug hunt (plans/IMPORTS_LEG_BUGHUNT.md). Each asserts the
## FIXED behavior on the exact repro that failed before.
func _test_bughunt_fixes() -> void:
	# BH-01: a component body's markup comment (`//`) with a brace must NOT desync decl enumeration.
	var bh01 := "component A() {\n\treturn (\n\t\t<Label /> // close } here\n\t)\n}\n\ncomponent B() {\n\treturn ( <Label /> )\n}\n"
	var r01 := RuitkGuitkx.compile(bh01, "file")
	_check_true(r01["ok"], "BH-01: mixed file with a markup comment containing `}` compiles (%s)" % str(r01.get("diagnostics", [])))
	_check_true((r01["gd"] as String).contains("static func render(") and (r01["gd"] as String).contains("static func B("), "BH-01: both components emitted")
	# `/* */` and `<!-- -->` markup comments too.
	var bh01b := "component A() {\n\treturn ( <Label /> /* brace } */ )\n}\ncomponent B() { return ( <Label /> ) }\n"
	_check_true(RuitkGuitkx.compile(bh01b, "file")["ok"], "BH-01: block markup comment `/* } */` doesn't desync")

	# BH-08: a multi-line import (names / `from` on later lines) is legal, no false GUITKX0300.
	var bh08 := "import {\n\tFoo,\n\tBar\n} from \"./x\"\n\ncomponent A() { return ( <Label /> ) }\n"
	var r08 := RuitkGuitkx.compile(bh08, "file")
	_check_true(r08["ok"], "BH-08: multi-line import compiles (%s)" % str(r08.get("diagnostics", [])))
	_check_true(not _has_code(r08, "GUITKX0300"), "BH-08: no false 0300 on a multi-line import")
	_check_true((r08.get("imports", []) as Array).size() == 1 and (r08["imports"][0]["names"] as Array).size() == 2, "BH-08: both names + specifier parsed across lines")
	# a specifier string that actually spans a newline is still unterminated -> 0300.
	_check_true(_has_code(RuitkGuitkx.compile("import { A } from \"./x\ncomponent B() { return ( <Label /> ) }\n", "b"), "GUITKX0300"), "BH-08: a newline inside the specifier string is still 0300")

	# BH-02: when @class_name != the decl name, the sole component still emits `render`, and the export
	# tables must ADDRESS it as `render` (not the decl name) -- else a cross-file import mis-targets it.
	const Resolve := preload("res://addons/reactive_ui_toolkit/guitkx/guitkx_resolve.gd")
	var bh02 := "@class_name Custom\nexport component Widget() {\n\treturn ( <Label /> )\n}\n"
	_check_true((RuitkGuitkx.compile(bh02, "file")["gd"] as String).contains("static func render("), "BH-02: sole component emits render under @class_name override")
	_check_true(str(Codegen.exports_of(bh02)[0]["func"]) == "render", "BH-02: exports_of addresses the sole component as render (%s)" % str(Codegen.exports_of(bh02)))
	_check_true(str(Resolve.decl_table(_bh_writefile("__bh02", bh02))["decls"]["Widget"]["func"]) == "render", "BH-02: decl_table addresses Widget as render")
	# mixed @class_name-mismatch: the first EXPORTED component becomes the render component.
	var bh02m := "@class_name Zzz\nexport component A() {\n\treturn ( <Label /> )\n}\nexport component B() {\n\treturn ( <Label /> )\n}\n"
	var r02m := RuitkGuitkx.compile(bh02m, "file")
	_check_true((r02m["gd"] as String).contains("static func render(") and (r02m["gd"] as String).contains("static func B("), "BH-02: mixed @class_name-mismatch -> first exported component renders")
	_check_true(str(Codegen.exports_of(bh02m)[0]["func"]) == "render", "BH-02: exports_of first-exported = render in mixed mismatch")

	# BH-17: resolver and codegen agree on the binding for a two-@class_name file (both take the LAST).
	var bh17 := "@class_name First\n@class_name Second\ncomponent A() { return ( <Label /> ) }\n"
	_check_true(Codegen._binding_name(bh17) == Resolve._binding_of(bh17), "BH-17: resolver/codegen agree on binding with two @class_name (%s vs %s)" % [Codegen._binding_name(bh17), Resolve._binding_of(bh17)])
	_check_true(Codegen._binding_name(bh17) == "Second", "BH-17: last @class_name wins (matches the emitter)")

	# BH-03: codemod inserts the import block at the decl START, not the keyword -- an already-exported
	# first decl must not become `export import { … } … component`; and it must stay idempotent.
	const Migrate := preload("res://addons/reactive_ui_toolkit/guitkx/guitkx_migrate.gd")
	var refc := { "Card": "res://x/card.guitkx" }
	var m1 := Migrate.migrate_source("res://x/widget.guitkx", "export component Widget() {\n\treturn ( <Card /> )\n}\n", refc)
	_check_true(not (m1["source"] as String).contains("export import"), "BH-03: no `export import` split (%s)" % (m1["source"] as String).substr(0, 40))
	_check_true((m1["source"] as String).find("import {") < (m1["source"] as String).find("export component"), "BH-03: import precedes the already-exported decl")
	_check_true(not Migrate.migrate_source("res://x/widget.guitkx", m1["source"], refc)["changed"], "BH-03: idempotent on an already-exported first decl")

	# BH-13: path-boundary. `<root>ui2/card` is NOT under root `<root>ui` -> must NOT be ~/2/card, and
	# whatever specifier is chosen must round-trip to the real file.
	var uiroot := "res://tests/__bh_tmp/ui"
	var s13 := RuitkGuitkx.import_specifier("res://tests/__bh_tmp/app/importer.guitkx", "res://tests/__bh_tmp/ui2/card.guitkx", uiroot)
	_check_true(not s13.begins_with("~/2"), "BH-13: prefix-sibling not mis-rooted (got %s)" % s13)
	var t13 := _bh_writefile_at("res://tests/__bh_tmp/ui2/card", "export component Card() { return ( <Label /> ) }\n")
	var from13 := "res://tests/__bh_tmp/app/importer.guitkx"
	var spec13 := RuitkGuitkx.import_specifier(from13, t13, uiroot)
	_check_true(str(Resolve.resolve_specifier(spec13, from13, uiroot).get("guitkx", "")) == t13, "BH-13: specifier round-trips to the right file (spec=%s)" % spec13)

	# BH-14: an under-root target still uses ~/ and round-trips.
	var t14 := _bh_writefile_at("res://tests/__bh_tmp/ui/sub/card", "export component Card() { return ( <Label /> ) }\n")
	var spec14 := RuitkGuitkx.import_specifier(from13, t14, uiroot)
	_check_true(spec14 == "~/sub/card", "BH-14: under-root target uses ~/root-relative (got %s)" % spec14)
	_check_true(str(Resolve.resolve_specifier(spec14, from13, uiroot).get("guitkx", "")) == t14, "BH-14: ~/ round-trips")

	# BH-06: a bare top-level hook import must lower to an aliased const + rewritten call -- the emitted
	# .gd must PARSE (a plain `const use_x = preload(...)` would call a resource).
	var hpath := _bh_writefile_at("res://tests/__bh_tmp/h", "export hook use_thing() -> int {\n\treturn 42\n}\n")
	Codegen.compile_file(hpath)   # produce h.gd so the preload target exists
	var bh06 := "import { use_thing } from \"./h\"\n\nexport component A() {\n\tvar v = use_thing()\n\treturn ( <Label text={str(v)} /> )\n}\n"
	var r06 := RuitkGuitkx.compile(bh06, "a", [], {}, "res://tests/__bh_tmp/a.guitkx", "res://")
	_check_true(r06["ok"], "BH-06: bare-hook importer compiles")
	_check_true((r06["gd"] as String).contains("__RUI_IMP_") and (r06["gd"] as String).contains(".use_thing("), "BH-06: bare call rewritten to <const>.use_thing(")
	_check_true(not (r06["gd"] as String).contains("const use_thing = preload"), "BH-06: no uncallable `const use_thing = preload`")
	_check_true(Codegen.gd_source_parses(r06["gd"]), "BH-06: emitted .gd PARSES")
	if FileAccess.file_exists("res://tests/__bh_tmp/h.gd"): DirAccess.remove_absolute("res://tests/__bh_tmp/h.gd")
	for ext in [".gd.uid", ".guitkx.diags.json", ".guitkx.uid"]:
		if FileAccess.file_exists("res://tests/__bh_tmp/h" + ext): DirAccess.remove_absolute("res://tests/__bh_tmp/h" + ext)

	# BH-09: mixed-decl @uss with a non-single-element render-component root emits GUITKX2210.
	var bh09 := "@uss \"res://theme.tres\"\nexport component A() {\n\treturn ( <><Label /><Label /></> )\n}\n\nexport component B() {\n\treturn ( <Label /> )\n}\n"
	_check_true(_has_code(RuitkGuitkx.compile(bh09, "file"), "GUITKX2210"), "BH-09: mixed @uss non-element root -> 2210 (not a silent drop)")

	# BH-11: a `../` (or ~/) specifier that climbs above res:// crosses the boundary -> GUITKX2308.
	var bh11 := RuitkGuitkx.compile("import { X } from \"../../../../outside\"\ncomponent A() { return ( <Label /> ) }\n", "a", [], {}, "res://tests/__bh_tmp/a.guitkx", "res://")
	_check_true(_has_code(bh11, "GUITKX2308"), "BH-11: root-escaping specifier -> 2308 (%s)" % str(bh11.get("diagnostics", [])))

	# BH-12: an import AFTER the first declaration -> GUITKX2309 (not a generic 2105).
	var bh12s := RuitkGuitkx.compile("component A() { return ( <Label /> ) }\nimport { X } from \"./x\"\n", "a")
	_check_true(_has_code(bh12s, "GUITKX2309") and not _has_code(bh12s, "GUITKX2105"), "BH-12: trailing import -> 2309 (single-decl)")
	var bh12m := RuitkGuitkx.compile("component A() { return ( <Label /> ) }\nimport { X } from \"./x\"\ncomponent B() { return ( <Label /> ) }\n", "a")
	_check_true(_has_code(bh12m, "GUITKX2309"), "BH-12: import between decls -> 2309 (mixed)")

	# BH-10: a value-import cycle (two modules importing each other) -> GUITKX2306 with the chain.
	var cdir := "res://tests/__bh_cyc"
	DirAccess.make_dir_recursive_absolute(cdir)
	_imp_write(cdir + "/va.guitkx", "import { VB } from \"./vb\"\n\nexport module VA {\n\thook use_a() -> int { return VB.use_b() }\n}\n")
	_imp_write(cdir + "/vb.guitkx", "import { VA } from \"./va\"\n\nexport module VB {\n\thook use_b() -> int { return VA.use_a() }\n}\n")
	var swept := Codegen.compile_all(cdir)
	var got2306 := false
	var chain2306 := ""
	for e in swept.get("errors", []):
		for d in e.get("diagnostics", []):
			if str(d.get("code", "")) == "GUITKX2306":
				got2306 = true
				chain2306 = str(d.get("message", ""))
	_check_true(got2306, "BH-10: value-import cycle emits 2306 (errors=%s)" % str(swept.get("errors", []).size()))
	_check_true(chain2306.contains("va.guitkx") and chain2306.contains("vb.guitkx"), "BH-10: 2306 prints the cycle chain (%s)" % chain2306)
	_bh_rm_tree(cdir)

	# BH-16: a PascalCase tag that no file exports (and has no near-miss) -> GUITKX2307; a lowercase
	# host-vocab miss or a near-miss typo stays GUITKX0105 (unchanged markup-vocab path).
	var bh16 := RuitkGuitkx.compile("component T() {\n\treturn ( <VBoxContainer><Zzyzx /></VBoxContainer> )\n}\n", "T", ["DemoBox"])
	_check_true(_has_code(bh16, "GUITKX2307") and not _has_code(bh16, "GUITKX0105"), "BH-16: unexported component-like tag -> 2307 (%s)" % str(bh16.get("diagnostics", [])))
	var bh16b := RuitkGuitkx.compile("component T() {\n\treturn ( <VBoxContainer><lable /></VBoxContainer> )\n}\n", "T", ["DemoBox"])
	_check_true(_has_code(bh16b, "GUITKX0105") and not _has_code(bh16b, "GUITKX2307"), "BH-16: lowercase host-vocab miss stays 0105")

	# BH-18: the strict-2305 squiggle anchors on the ACTUAL reference (a `<Tag`), not the first textual
	# occurrence (a comment). `Widget` appears first in a comment; 2305 must point at `<Widget`.
	var cp18 := { "Widget": "res://x/widget.gd" }
	var s18 := "# Widget is cool\ncomponent A() {\n\treturn ( <Widget /> )\n}\n"
	var d18 := _diag(RuitkGuitkx.compile(s18, "a", [], cp18, "res://x/a.guitkx", "res://"), "GUITKX2305")
	_check_true(int(d18.get("offset", -1)) == s18.find("<Widget"), "BH-18: 2305 anchors on `<Widget` not the comment (got %d, want %d)" % [int(d18.get("offset", -1)), s18.find("<Widget")])

	# BH-07: refresh roots include a TRANSITIVE component consumer (component -> module -> changed module).
	var rdir := "res://tests/__bh_rr"
	DirAccess.make_dir_recursive_absolute(rdir)
	_imp_write(rdir + "/m2.guitkx", "export module M2 {\n\thook use_x() -> int { return 1 }\n}\n")
	_imp_write(rdir + "/m1.guitkx", "import { M2 } from \"./m2\"\n\nexport module M1 {\n\thook use_y() -> int { return M2.use_x() }\n}\n")
	_imp_write(rdir + "/screen.guitkx", "import { M1 } from \"./m1\"\n\nexport component Screen() {\n\tvar v = M1.use_y()\n\treturn ( <Label text={str(v)} /> )\n}\n")
	var all := [rdir + "/m2.guitkx", rdir + "/m1.guitkx", rdir + "/screen.guitkx"]
	var srcs := {}
	for pth in all:
		srcs[pth] = FileAccess.get_file_as_string(pth)
	var roots := Codegen._compute_refresh_roots([{ "path": rdir + "/m2.guitkx" }], all, srcs)
	_check_true((roots as Array).has(rdir + "/screen.gd"), "BH-07: transitive component consumer is a refresh root (got %s)" % str(roots))
	_bh_rm_tree(rdir)

	# cleanup: remove the whole __bh_tmp tree (and the __bh02 file under __bh_tmp)
	_bh_rm_tree("res://tests/__bh_tmp")
	_bh_tmp_files.clear()

func _bh_writefile(name: String, content: String) -> String:
	return _bh_writefile_at("res://tests/__bh_tmp/" + name, content)

## Write `content` to `<path_no_ext>.guitkx` (creating parent dirs + a `.gdignore` at the __bh_tmp root
## so the build walker never sees these fixtures) and track it for cleanup. Returns the .guitkx path.
func _bh_writefile_at(path_no_ext: String, content: String) -> String:
	var p := path_no_ext + ".guitkx"
	DirAccess.make_dir_recursive_absolute(p.get_base_dir())
	if not FileAccess.file_exists("res://tests/__bh_tmp/.gdignore"):
		DirAccess.make_dir_recursive_absolute("res://tests/__bh_tmp")
		_imp_write("res://tests/__bh_tmp/.gdignore", "")
	_imp_write(p, content)
	_bh_tmp_files.append(p)
	return p

## Recursively delete a res:// directory tree (files + subdirs + the dir itself).
func _bh_rm_tree(dir: String) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if name != "." and name != "..":
			var p := dir.path_join(name)
			if d.current_is_dir():
				_bh_rm_tree(p)
			else:
				DirAccess.remove_absolute(p)
		name = d.get_next()
	d.list_dir_end()
	DirAccess.remove_absolute(dir)

var _bh_tmp_files: Array = []

func _imp_write(path: String, content: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(content)
		f.close()

## Retired 0.10.2 (plans/archive/CLASSNAME_CLEANUP_PLAN.md M1): a component whose name differs
## from the file's basename no longer warns -- imports made filename identity moot, since binding
## is inferred (override else first-exported-decl else first-decl), not required to match the file.
## The directive itself is kept as a grammar escape hatch: `@class_name` still overrides the binding.
func _test_0103_retired() -> void:
	var r := RuitkGuitkx.compile("component DemoThing() {\n\treturn ( <Label /> )\n}\n", "some_file")
	_check_true(bool(r["ok"]), "0103 retired: DemoThing in some_file.guitkx still compiles (%s)" % str(r.get("diagnostics", [])))
	_check_true(not _has_code(r, "GUITKX0103"), "0103 retired: no GUITKX0103 even though the name differs from the basename (got %s)" % str(r["diagnostics"]))
	# Grammar keep-alive: @class_name still overrides the binding.
	var ov := RuitkGuitkx.compile("@class_name Custom\n\ncomponent DemoThing() {\n\treturn ( <Label /> )\n}\n", "some_file")
	_check_true(bool(ov["ok"]), "0103 retired: @class_name override still compiles (%s)" % str(ov.get("diagnostics", [])))
	_check(str(ov["gd"]), "class_name Custom", "0103 retired: @class_name Custom still overrides the generated binding")

## Regression (CI 2026-07-16): the GUITKX2107 dangling verdict must not depend on DirAccess walk
## order. A ref whose .gd is missing but whose SOURCE .guitkx exists is pending regeneration, not
## dangling -- the CI runner's filesystem walked the dependent before the restored component, so
## the same-sweep heal never fired (NTFS walks alphabetically and always compiled the child first,
## which is why it never reproduced locally). Pinned deterministically by keeping the child OUTSIDE
## the swept dir: its .gd can never come back mid-sweep, so a disk-only predicate fails everywhere.
func _test_2107_walk_order() -> void:
	var a_dir := "res://tests/__2107_a_tmp"
	var b_dir := "res://tests/__2107_b_tmp"
	DirAccess.make_dir_recursive_absolute(a_dir)
	DirAccess.make_dir_recursive_absolute(b_dir)
	if Codegen.compiler_changed():
		Codegen.compile_all(a_dir)   # settle the fingerprint marker; every check below is non-force
	var w_child := b_dir + "/pend_child.guitkx"
	var w_parent := a_dir + "/pend_parent.guitkx"
	var w_child_src := "export component PendChild {\n\treturn ( <Label text=\"c\" /> )\n}\n"
	var wf1 := FileAccess.open(w_child, FileAccess.WRITE)
	wf1.store_string(w_child_src)
	wf1.close()
	var wf2 := FileAccess.open(w_parent, FileAccess.WRITE)
	wf2.store_string("import { PendChild } from \"../__2107_b_tmp/pend_child\"\n\nexport component PendParent {\n\treturn ( <VBoxContainer><PendChild /></VBoxContainer> )\n}\n")
	wf2.close()
	Codegen.compile_all(b_dir)
	var w1 := Codegen.compile_all(a_dir)
	_check_true((w1["errors"] as Array).is_empty(), "walk-order fixture compiles clean: " + str(w1["errors"]))
	# (a) missing .gd + PRESENT source = pending regeneration, not dangling: no flag, poll settled.
	DirAccess.remove_absolute(Codegen.gd_path_for(w_child))
	_check_true(not Codegen.has_stale(a_dir), "missing .gd with a present source is pending, not dangling (poll settled)")
	var w2 := Codegen.compile_all(a_dir)
	_check_true((w2["errors"] as Array).is_empty(), "missing .gd with a present source never flags 2107: " + str(w2["errors"]))
	# (b) source gone too -> NOW it dangles; restoring the SOURCE alone must trigger the heal,
	# even though the child's .gd stays absent for the whole sweep (b_dir is never swept again).
	DirAccess.remove_absolute(w_child)
	_check_true(Codegen.has_stale(a_dir), "output+source both gone -> dangling -> poll hot")
	var w3 := Codegen.compile_all(a_dir)
	var w3_hit := false
	for we in (w3["errors"] as Array):
		for wd in ((we as Dictionary).get("diagnostics", []) as Array):
			if str((wd as Dictionary).get("code", "")) == "GUITKX2107":
				w3_hit = true
	_check_true(w3_hit, "output+source both gone flags 2107: " + str(w3["errors"]))
	var wf3 := FileAccess.open(w_child, FileAccess.WRITE)
	wf3.store_string(w_child_src)
	wf3.close()
	_check_true(Codegen.has_stale(a_dir), "restored source mismatches the standing flag -> poll hot (heal work)")
	var w4 := Codegen.compile_all(a_dir)
	_check_true((w4["errors"] as Array).is_empty() and (w4["compiled"] as Array).size() == 1,
		"heal recompile fires with the child's .gd still absent (walk-order independent): " + str(w4["errors"]))
	_check_true(not Codegen.has_stale(a_dir), "poll settles after the heal")
	for wl in [w_child, Codegen.gd_path_for(w_child), w_child + ".diags.json", w_parent, Codegen.gd_path_for(w_parent), w_parent + ".diags.json"]:
		if FileAccess.file_exists(str(wl)):
			DirAccess.remove_absolute(str(wl))
	DirAccess.remove_absolute(a_dir)
	DirAccess.remove_absolute(b_dir)

## M3 (0.10.0): import RESOLUTION -- specifier->path, value/component lowering, frozen 2300-2308.
## Uses a `.gdignore`'d temp dir so the build walker never sees the fixtures; the resolver reaches
## them by direct FileAccess. Everything is cleaned up at the end.
func _test_imports_m3() -> void:
	const Resolve := preload("res://addons/reactive_ui_toolkit/guitkx/guitkx_resolve.gd")
	var dir := "res://tests/__imp_tmp"
	DirAccess.make_dir_recursive_absolute(dir)
	_imp_write(dir + "/.gdignore", "")
	_imp_write(dir + "/status_chip.guitkx", "export component StatusChip() {\n\treturn ( <Label /> )\n}\n")
	_imp_write(dir + "/hud_hooks.guitkx", "export module HudHooks {\n\thook use_blink() -> int { return 1 }\n}\n")
	_imp_write(dir + "/priv.guitkx", "component Secret() {\n\treturn ( <Label /> )\n}\n")
	# Compile the value-import target to .gd so the importer's `preload(...)` has a real target to
	# parse-check against (a missing preload = ERR_PARSE_ERROR -- the M4 two-pass ordering concern).
	Codegen.compile_file(dir + "/hud_hooks.guitkx")

	# component import -> V.comp(path); module import -> const preload; both usable in one file.
	var imp := "import { StatusChip } from \"./status_chip\"\nimport { HudHooks } from \"./hud_hooks\"\n\nexport component Panel() {\n\tvar b = HudHooks.use_blink()\n\treturn ( <StatusChip /> )\n}\n"
	var r := RuitkGuitkx.compile(imp, "panel", [], {}, dir + "/panel.guitkx", "res://")
	_check_true(r["ok"], "M3: importer compiles (%s)" % str(r.get("diagnostics", [])))
	_check_true((r["gd"] as String).contains("V.comp(\"res://tests/__imp_tmp/status_chip.gd\")"), "M3: component import lowers to V.comp(path)")
	_check_true((r["gd"] as String).contains("const HudHooks = preload(\"res://tests/__imp_tmp/hud_hooks.gd\")"), "M3: module import lowers to a const preload")
	_check_true(_gd_parses(r["gd"]), "M3: importer .gd parses")

	# 2302: name not declared in the target file.
	var r2 := RuitkGuitkx.compile("import { Nope } from \"./status_chip\"\ncomponent A() { return ( <Label /> ) }\n", "a", [], {}, dir + "/a.guitkx", "res://")
	_check_true(_has_code(r2, "GUITKX2302"), "M3: importing an undeclared name -> 2302")

	# 2301: name declared but not exported.
	var r3 := RuitkGuitkx.compile("import { Secret } from \"./priv\"\ncomponent A() { return ( <Secret /> ) }\n", "a", [], {}, dir + "/a.guitkx", "res://")
	_check_true(_has_code(r3, "GUITKX2301"), "M3: importing a non-exported decl -> 2301")

	# 2300: unresolvable specifier.
	var r4 := RuitkGuitkx.compile("import { X } from \"./nope\"\ncomponent A() { return ( <Label /> ) }\n", "a", [], {}, dir + "/a.guitkx", "res://")
	_check_true(_has_code(r4, "GUITKX2300"), "M3: unresolvable specifier -> 2300")

	# engine-native specifier is forbidden in import position -> 2300.
	var r4b := RuitkGuitkx.compile("import { X } from \"res://x\"\ncomponent A() { return ( <Label /> ) }\n", "a", [], {}, dir + "/a.guitkx", "res://")
	_check_true(_has_code(r4b, "GUITKX2300"), "M3: res:// specifier forbidden in import -> 2300")

	# 2303: duplicate import of the same name.
	var r5 := RuitkGuitkx.compile("import { StatusChip } from \"./status_chip\"\nimport { StatusChip } from \"./status_chip\"\ncomponent A() { return ( <StatusChip /> ) }\n", "a", [], {}, dir + "/a.guitkx", "res://")
	_check_true(_has_code(r5, "GUITKX2303"), "M3: duplicate import -> 2303")

	# 2304: imported but never referenced. ERROR tier since 0.11.1 (owner directive, family-wide):
	# consistent with the other import diagnostics, so an unused import fails the compile (T1.1).
	var r6 := RuitkGuitkx.compile("import { StatusChip } from \"./status_chip\"\ncomponent A() { return ( <Label /> ) }\n", "a", [], {}, dir + "/a.guitkx", "res://")
	_check_true(_has_code(r6, "GUITKX2304"), "M3: unused import -> 2304")
	_check_true(int(_diag(r6, "GUITKX2304").get("severity", -9)) == GDiag.ERROR, "M3: 2304 is error-tier (0.11.1 severity bump)")
	_check_true(not bool(r6["ok"]), "M3: an unused import fails the compile under the error tier")

	# resolve_specifier: ./ ../ ~/ forms + extensionless.
	var sc := Resolve.resolve_specifier("./status_chip", dir + "/panel.guitkx", "res://")
	_check_true(sc["ok"] and sc["gd"] == "res://tests/__imp_tmp/status_chip.gd", "M3: ./ resolves + .guitkx implied -> sibling .gd")
	var tilde := Resolve.resolve_specifier("~/tests/__imp_tmp/status_chip", dir + "/panel.guitkx", "res://")
	_check_true(tilde["ok"] and tilde["guitkx"] == "res://tests/__imp_tmp/status_chip.guitkx", "M3: ~/ resolves against the root")

	# 2306: value-import cycle (hook/module preload edges), chain printed. a -> b -> a.
	_imp_write(dir + "/cyc_a.guitkx", "export module CycA {\n\thook use_a() -> int { return 1 }\n}\n")
	_imp_write(dir + "/cyc_b.guitkx", "export module CycB {\n\thook use_b() -> int { return 1 }\n}\n")
	var edges := func(p: String) -> Array:
		if p.ends_with("cyc_a.guitkx"): return [dir + "/cyc_b.guitkx"]
		if p.ends_with("cyc_b.guitkx"): return [dir + "/cyc_a.guitkx"]
		return []
	var chain := Resolve.value_cycle(dir + "/cyc_a.guitkx", edges)
	_check_true(chain.contains("cyc_a.guitkx") and chain.contains("cyc_b.guitkx") and chain.contains(" -> "), "M3: value_cycle prints the chain (%s)" % chain)
	_check_true(Resolve.value_cycle(dir + "/status_chip.guitkx", func(_p): return []) == "", "M3: acyclic returns empty")

	# M6 STRICT: an un-imported cross-file reference to a guitkx binding (present in component_paths)
	# is GUITKX2305; importing it clears the error. This is the "implicit resolution is an error" gate.
	var cp := { "StatusChip": "res://tests/__imp_tmp/status_chip.gd" }
	var strict_bad := RuitkGuitkx.compile("component A() {\n\treturn ( <StatusChip /> )\n}\n", "a", [], cp, dir + "/a.guitkx", "res://")
	_check_true(_has_code(strict_bad, "GUITKX2305"), "M6 strict: un-imported cross-file ref -> 2305")
	var strict_ok := RuitkGuitkx.compile("import { StatusChip } from \"./status_chip\"\ncomponent A() {\n\treturn ( <StatusChip /> )\n}\n", "a", [], cp, dir + "/a.guitkx", "res://")
	_check_true(not _has_code(strict_ok, "GUITKX2305"), "M6 strict: importing the ref clears 2305")

	# M3.6: `~/`-rooted asset path rewrites to res:// before validation.
	var ua := RuitkGuitkx.compile("@uss \"~/tests/__imp_tmp/missing.tres\"\ncomponent A() { return ( <Label /> ) }\n", "a", [], {}, dir + "/a.guitkx", "res://")
	_check_true(_diag(ua, "GUITKX0120").get("message", "").contains("res://tests/__imp_tmp/missing.tres"), "M3.6: ~/ asset path rewritten to res:// (%s)" % str(ua.get("diagnostics", [])))

	# cleanup (sources + any generated .gd/.uid/sidecars from the compile_file call above)
	for f in ["status_chip", "hud_hooks", "priv", "cyc_a", "cyc_b"]:
		for ext in [".guitkx", ".gd", ".gd.uid", ".guitkx.uid", ".guitkx.diags.json"]:
			if FileAccess.file_exists(dir + "/" + f + ext):
				DirAccess.remove_absolute(dir + "/" + f + ext)
	DirAccess.remove_absolute(dir + "/.gdignore")
	DirAccess.remove_absolute(dir)

func _diag(r: Dictionary, code: String) -> Dictionary:
	for d in r.get("diagnostics", []):
		if d is Dictionary and (d as Dictionary).get("code", "") == code:
			return d
	return {}

func _has_code(r: Dictionary, code: String) -> bool:
	return not _diag(r, code).is_empty()

## Assert a diagnostic exists AND its offset points exactly at `needle` in `src` (T0.2 precision).
func _check_diag_at(r: Dictionary, code: String, src: String, needle: String, label: String) -> void:
	var d := _diag(r, code)
	_check_true(not d.is_empty(), "%s: %s present (got %s)" % [label, code, str(r.get("diagnostics", []))])
	if d.is_empty():
		return
	var off := int(d.get("offset", -1))
	_check_true(off >= 0 and src.substr(off, needle.length()) == needle,
		"%s: %s offset lands on '%s' (offset %d -> '%s')" % [label, code, needle, off, src.substr(maxi(0, off), needle.length())])

func _test_diagnostics() -> void:
	# rules of hooks: a hook called inside an if-block in setup — flagged AT the offending line
	var roh_src := "component Bad(c: bool = true) {\n\tvar a = useState(0)\n\tif c:\n\t\tvar b = useState(1)\n\treturn ( <Label /> )\n}\n"
	var roh := RuitkGuitkx.compile(roh_src, "Bad")
	_check_diag_at(roh, "GUITKX0013", roh_src, "var b = useState(1)", "rules-of-hooks")
	# T2.5 (Unity parity): rules-of-hooks violations are ERRORS and fail the compile.
	_check_true(int(_diag(roh, "GUITKX0013").get("severity", -9)) == GDiag.ERROR, "GUITKX0013 is an error")
	_check_true(not roh["ok"], "T2.5: conditional hook fails the compile")
	# duplicate literal keys among siblings — flagged at the SECOND key attribute
	var dk_src := "component Dup() {\n\treturn (\n\t\t<VBoxContainer>\n\t\t\t<Label key=\"x\" />\n\t\t\t<Label key=\"x\" />\n\t\t</VBoxContainer>\n\t)\n}\n"
	var dk := RuitkGuitkx.compile(dk_src, "Dup")
	_check_diag_at(dk, "GUITKX0104", dk_src, "key=\"x\"", "duplicate-key")
	_check_true(int(_diag(dk, "GUITKX0104").get("offset", -1)) > dk_src.find("key=\"x\""), "GUITKX0104 anchors to the SECOND duplicate, not the first")
	# loop child missing key — flagged at the element
	var lk_src := "component LK(items: Array = []) {\n\treturn (\n\t\t<VBoxContainer>\n\t\t\t@for (it in items) { return ( <Label text={ it } /> ) }\n\t\t</VBoxContainer>\n\t)\n}\n"
	var lk := RuitkGuitkx.compile(lk_src, "LK")
	_check_diag_at(lk, "GUITKX0106", lk_src, "<Label text={ it }", "keyless-loop-child")
	# a clean PLAIN component emits no warnings; the equivalent WRAPPER form gets exactly the G-10
	# deprecation warning (2320) and nothing else.
	var clean := RuitkGuitkx.compile("Clean() -> RuitkVNode {\n\tvar a = useState(0)\n\treturn ( <Label text={ str(a[0]) } /> )\n}\n", "Clean")
	_check_true(clean["ok"] and (clean["diagnostics"] as Array).is_empty(), "clean plain component has no diagnostics (got %s)" % str(clean["diagnostics"]))
	var clean_wrapper := RuitkGuitkx.compile("component Clean() {\n\tvar a = useState(0)\n\treturn ( <Label text={ str(a[0]) } /> )\n}\n", "Clean")
	_check_true(clean_wrapper["ok"] and (clean_wrapper["diagnostics"] as Array).size() == 1 and _has_code(clean_wrapper, "GUITKX2320"), "G-10: clean wrapper component gets exactly one 2320 deprecation warning (got %s)" % str(clean_wrapper["diagnostics"]))

func _test_loop_single_root() -> void:
	# BUG-V3: a @for/@while body with >1 sibling root is a hard error (single-root; parity Unity UITKX0108)
	var multi := RuitkGuitkx.compile("component M(n: int = 3) {\n" + \
		"\treturn (\n\t\t<VBoxContainer>\n" + \
		"\t\t\t@for (i in n) {\n\t\t\t\treturn (\n\t\t\t\t<Label key={ str(i) } />\n\t\t\t\t<Label key={ str(i) } />\n\t\t\t\t)\n\t\t\t}\n" + \
		"\t\t</VBoxContainer>\n\t)\n}\n", "M")
	_check_true(not multi["ok"] and _has_code(multi, "GUITKX0108"), "loop body with 2 roots fails with GUITKX0108 (got %s)" % str(multi["diagnostics"]))
	_check_true(int(_diag(multi, "GUITKX0108").get("offset", -1)) >= 0, "GUITKX0108 carries a position even through the nested loop-body re-parse")
	# BUG-V3: duplicate EXPRESSION keys among siblings are caught (not only literal key="..." keys)
	var dupe := RuitkGuitkx.compile("component D() {\n" + \
		"\treturn (\n\t\t<VBoxContainer>\n\t\t\t<Label key={ str(0) } />\n\t\t\t<Label key={ str(0) } />\n\t\t</VBoxContainer>\n\t)\n}\n", "D")
	_check_true(_has_code(dupe, "GUITKX0104"), "duplicate expr key caught with GUITKX0104 (got %s)" % str(dupe["diagnostics"]))
	# valid: a fragment root wrapping distinctly-keyed siblings inside the loop compiles cleanly
	var okc := RuitkGuitkx.compile("component OK(n: int = 3) {\n" + \
		"\treturn (\n\t\t<VBoxContainer>\n" + \
		"\t\t\t@for (i in n) {\n\t\t\t\treturn (\n\t\t\t\t<>\n\t\t\t\t\t<Label key={ \"a\" + str(i) } />\n\t\t\t\t\t<Label key={ \"b\" + str(i) } />\n\t\t\t\t</>\n\t\t\t\t)\n\t\t\t}\n" + \
		"\t\t</VBoxContainer>\n\t)\n}\n", "OK")
	_check_true(okc["ok"], "loop with fragment-wrapped distinct-key siblings compiles (got %s)" % str(okc["diagnostics"]))

func _test_decl_validation() -> void:
	# BUG-V2: an invalid @class_name value (multiple tokens) is rejected with GUITKX0300
	var badcn_src := "@class_name Foo Bar\ncomponent X() { return ( <Label /> ) }\n"
	var badcn := RuitkGuitkx.compile(badcn_src, "X")
	_check_true(not badcn["ok"], "invalid @class_name rejected (got %s)" % str(badcn["diagnostics"]))
	_check_diag_at(badcn, "GUITKX0300", badcn_src, "@class_name", "invalid @class_name")
	# a valid @class_name is accepted, and a trailing comment on the directive line is tolerated
	var okcn := RuitkGuitkx.compile("@class_name MyThing  # ok\ncomponent X() { return ( <Label /> ) }\n", "X")
	_check_true(okcn["ok"], "valid @class_name accepted (got %s)" % str(okcn["diagnostics"]))
	# BUG-V1: a misspelled declaration keyword yields a did-you-mean hint, anchored at the typo'd
	# word -- but only when NO valid declaration exists anywhere in the file. Under E-01's
	# signature-only classification a misspelled keyword followed by something that itself LOOKS
	# like a plain decl is no longer ambiguous: "componeent X() { ... }" now parses as invalid
	# content ("componeent") before a real plain util declaration ("X"), which is the more precise
	# diagnostic (there is no guarantee the author meant "component" specifically).
	var typo_src := "componeent Foo\n"
	var typo := RuitkGuitkx.compile(typo_src, "X")
	_check_true(not typo["ok"] and str(_diag(typo, "GUITKX2101").get("message", "")).contains("did you mean 'component'"), "misspelled keyword suggests component (got %s)" % str(typo["diagnostics"]))
	_check_diag_at(typo, "GUITKX2101", typo_src, "componeent", "misspelled keyword")
	# E-01: the same typo immediately followed by a callable shape is invalid CONTENT before a real
	# (plain util) declaration, not a did-you-mean -- "X" alone is legal new-style syntax.
	var typo_shadowed_src := "componeent X() { return ( <Label /> ) }\n"
	var typo_shadowed := RuitkGuitkx.compile(typo_shadowed_src, "X")
	_check_true(not typo_shadowed["ok"] and _has_code(typo_shadowed, "GUITKX2105") and not _has_code(typo_shadowed, "GUITKX2101"), "E-01: a typo shadowed by a real trailing decl is 2105, not 2101 (got %s)" % str(typo_shadowed["diagnostics"]))
	# BUG-V4: a space after `<` is an invalid tag name, not a silent fragment
	var badtag := RuitkGuitkx.compile("component B() {\n\treturn ( <  a> )\n}\n", "B")
	_check_true(not badtag["ok"] and _has_code(badtag, "GUITKX0300"), "invalid tag name rejected (got %s)" % str(badtag["diagnostics"]))
	# BUG-V5 (T1.4 semantics): code after the LAST top-level markup return is flagged unreachable
	# (GUITKX0107 warning) at the dead code; the compile still succeeds.
	var unreach_src := "component U() {\n\treturn ( <Label /> )\n\tvar x = 5\n}\n"
	var unreach := RuitkGuitkx.compile(unreach_src, "U")
	_check_true(bool(unreach["ok"]), "unreachable code is a warning, not an error (got %s)" % str(unreach["diagnostics"]))
	_check_diag_at(unreach, "GUITKX0107", unreach_src, "var x = 5", "unreachable-after-return")

# The stale-.gd disease: a sibling .gd that is NEWER than its source but was produced by an OLD
# compiler must still be regenerated. Guards guitkx_codegen's compiler-version staleness mechanism —
# the mtime-only guard silently skipped such files, so old-compiler output (e.g. an unprefixed
# useState) persisted after a pull while CI (which recompiles unconditionally) stayed green.
func _test_codegen_staleness() -> void:
	var CG := preload("res://addons/reactive_ui_toolkit/guitkx/guitkx_codegen.gd")
	var fp: String = CG.compiler_fingerprint()
	_check_true(fp.length() == 8 and fp != "00000000", "compiler fingerprint is a stable non-zero hash (got %s)" % fp)
	_check_true(fp == CG.compiler_fingerprint(), "compiler fingerprint is deterministic")
	if DirAccess.open("res://.godot") == null:
		return  # the marker lives in .godot (present after an editor import scan); skip the round-trip otherwise
	var mk := "res://.godot/rui_guitkx_compiler.fp"
	var had := FileAccess.file_exists(mk)
	var prev := FileAccess.get_file_as_string(mk) if had else ""
	_write_file(mk, "deadbeef")
	_check_true(CG.compiler_changed(), "a mismatched marker -> compiler_changed() true (forces full regen)")
	_write_file(mk, fp)
	_check_true(not CG.compiler_changed(), "a matching marker -> compiler_changed() false (mtime guard resumes)")
	if had:
		_write_file(mk, prev)
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(mk))

func _write_file(path: String, s: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(s)
		f.close()

# A tab + spaces renders identically to tabs in every editor (so the author can't see the difference)
# but differs byte-wise. The compiler must normalize such mixed indentation (depth-based reindent)
# into VALID GDScript instead of emitting a broken .gd ("unindent doesn't match") or a false
# GUITKX0013 -- while still catching a genuine hook-in-a-block.
func _test_indent_robustness() -> void:
	var mixed := "component X {\n\t\tvar a = useState(0)\n\t  var b = useState(0)\n\treturn ( <Label /> )\n}\n"
	var r := RuitkGuitkx.compile(mixed, "X")
	_check_true(r["ok"] and not _has_code(r, "GUITKX0013"), "mixed tab/space setup compiles, no false GUITKX0013 (got %s)" % str(r["diagnostics"]))
	var s := GDScript.new()
	s.source_code = (r["gd"] as String).replace("class_name X\n", "")
	_check_true(s.reload() == OK, "mixed tab/space setup generates VALID GDScript")
	var pure_space := RuitkGuitkx.compile("component X {\n    var a = useState(0)\n    return ( <Label /> )\n}\n", "X")
	var s2 := GDScript.new()
	s2.source_code = (pure_space["gd"] as String).replace("class_name X\n", "")
	_check_true(s2.reload() == OK, "pure-space setup also generates VALID GDScript")
	var bad := RuitkGuitkx.compile("component X {\n\tvar a = useState(0)\n\tif a[0]:\n\t\tvar b = useState(0)\n\treturn ( <Label /> )\n}\n", "X")
	_check_true(_has_code(bad, "GUITKX0013"), "a genuine hook-in-a-block still warns")

# One outlier-SHALLOW setup line must not shift the rest of the block: with a min-depth anchor,
# `var b` at column 0 made every OTHER line emit one level too deep (over-indented with no preceding
# `:` = "expected an expression" + the class-level diagnostic cascade). The reindent anchors to the
# FIRST non-blank line and clamps shallower lines up to body level. [BUG: G1]
func _test_outlier_indent() -> void:
	var src := "component X {\n\tvar a = useState(0)\nvar b = 1\n\tif a[0]:\n\t\tb += 1\n\treturn ( <Label /> )\n}\n"
	var r := RuitkGuitkx.compile(src, "X")
	_check_true(r["ok"], "outlier-shallow setup line still compiles (got %s)" % str(r["diagnostics"]))
	var gd: String = r["gd"]
	_check(gd, "\n\tvar a = Hooks.useState(0)", "normal setup lines stay at body level")
	_check(gd, "\n\tvar b = 1", "outlier line clamps up to body level")
	_check(gd, "\n\t\tb += 1", "nested depth is preserved")
	var s := GDScript.new()
	s.source_code = gd.replace("class_name X\n", "")
	_check_true(s.reload() == OK, "outlier-shallow setup generates VALID GDScript")
	# A leading over-indented comment must not become the anchor (comments are legal at any depth):
	# anchoring on it dedented the if-body out of its block -- invalid .gd + formatter corruption.
	var cmt := RuitkGuitkx.compile("component X {\n\t\t# note\n\tvar a = useState(0)\n\tif a[0]:\n\t\ta[1].call(1)\n\treturn ( <Label /> )\n}\n", "X")
	_check_true(cmt["ok"], "leading over-indented comment still compiles (got %s)" % str(cmt["diagnostics"]))
	var cgd: String = cmt["gd"]
	_check(cgd, "\n\tif a[0]:", "code anchors at body level, not at the comment")
	_check(cgd, "\n\t\ta[1].call(1)", "the if body stays nested under its if")
	var cs := GDScript.new()
	cs.source_code = cgd.replace("class_name X\n", "")
	_check_true(cs.reload() == OK, "comment-led setup generates VALID GDScript")
	# A comment-only hook body must still produce a valid func (comments are not statements).
	var ch := RuitkGuitkx.compile("hook use_todo() {\n\t# TODO: implement\n}\n", "UseTodo")
	_check_true(ch["ok"], "comment-only hook body compiles")
	var chs := GDScript.new()
	chs.source_code = (ch["gd"] as String).replace("class_name UseTodo\n", "")
	_check_true(chs.reload() == OK, "comment-only hook body generates VALID GDScript (trailing pass)")

func _test_hook() -> void:
	var src := "hook use_counter(start: int = 0) {\n" + \
		"\tvar s = useState(start)\n" + \
		"\treturn [s[0], func(): s[1].call(s[0] + 1)]\n" + \
		"}\n"
	var r := RuitkGuitkx.compile(src, "UseCounter")
	if not r["ok"]:
		_fail("hook: compile failed: " + str(r["diagnostics"]))
	var gd: String = r["gd"]
	print("--- generated (UseCounter) ---\n" + gd + "----------------------------")
	_check(gd, "class_name UseCounter", "hook class name from file")
	_check(gd, "static func use_counter(start: int = 0):", "hook function signature (params verbatim)")
	_check(gd, "Hooks.useState(start)", "hook body auto-prefixed")
	_check_true(not ("\t\tvar s " in gd), "hook body single-indented")
	var gd2 := gd.replace("class_name UseCounter\n", "")
	var path := "user://__guitkx_hook.gd"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(gd2)
	f.close()
	_check_true(load(path) != null, "hook .gd loads/parses")
	# module files are rejected (one declaration per file)
	var mr := RuitkGuitkx.compile("module Widgets {\n\tcomponent A() { return ( <Label /> ) }\n}\n", "Widgets")
	_check_true(mr["ok"], "module Name { ... } now compiles (got %s)" % str(mr["diagnostics"]))
	# empty / no declaration is rejected
	var er := RuitkGuitkx.compile("@class_name Foo\n# just a comment\n", "Foo")
	_check_true(not er["ok"] and _has_code(er, "GUITKX2101"), "no-declaration rejected with GUITKX2101")

func _test_match() -> void:
	var src := "component Status(state: String = \"idle\") {\n" + \
		"\treturn (\n" + \
		"\t\t<VBoxContainer>\n" + \
		"\t\t\t@match (state) {\n" + \
		"\t\t\t\t@case (\"loading\") { return ( <Label text=\"Loading...\" /> ) }\n" + \
		"\t\t\t\t@case (\"done\") { return ( <Label text=\"Done!\" /> ) }\n" + \
		"\t\t\t\t@default { return ( <Label text=\"Idle\" /> ) }\n" + \
		"\t\t\t}\n" + \
		"\t\t</VBoxContainer>\n" + \
		"\t)\n}\n"
	var r := RuitkGuitkx.compile(src, "Status")
	if not r["ok"]:
		_fail("match: compile failed: " + str(r["diagnostics"]))
	var gd: String = r["gd"]
	print("--- generated (Status) ---\n" + gd + "----------------------------")
	_check(gd, "match state:", "@match subject")
	_check(gd, "\"loading\":", "@case pattern")
	_check(gd, "_:", "@default arm")
	# runtime: "done" -> "Done!", unknown -> "Idle"
	var gd2 := gd.replace("class_name Status\n", "")
	var path := "user://__guitkx_status.gd"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(gd2)
	f.close()
	var script = load(path)
	_check_true(script != null, "Status .gd loads")
	var c := Control.new()
	root.add_child(c)
	var app := RuitkRoot.create(c, V.fc(script.render, { "state": "done" }))
	var lbl := _find_first(c, "Label")
	_check_true(lbl != null and lbl.text == "Done!", "@case done -> 'Done!' (got %s)" % (lbl.text if lbl else "<none>"))
	app.unmount()
	c.free()
	var c2 := Control.new()
	root.add_child(c2)
	var app2 := RuitkRoot.create(c2, V.fc(script.render, { "state": "wat" }))
	var lbl2 := _find_first(c2, "Label")
	_check_true(lbl2 != null and lbl2.text == "Idle", "@default -> 'Idle' (got %s)" % (lbl2.text if lbl2 else "<none>"))
	app2.unmount()
	c2.free()

func _test_codegen() -> void:
	# the sibling-.gd codegen mechanism (RuitkGuitkxCodegen), engine-free so it runs under --script
	var gx := "res://tests/__guitkx_fixture.guitkx"
	var src := "component Fixture(msg: String = \"hi\") {\n\treturn ( <Label text={ msg } /> )\n}\n"
	var f := FileAccess.open(gx, FileAccess.WRITE)
	_check_true(f != null, "can write fixture .guitkx under res://")
	f.store_string(src)
	f.close()
	_check_true(Codegen.find_all("res://tests").has(gx), "find_all locates the fixture")
	_check_true(Codegen.is_stale(gx), "fixture stale before compile (no sibling .gd)")
	var r := Codegen.compile_file(gx)
	_check_true(r["ok"], "compile_file ok: " + str(r))
	var gd := Codegen.gd_path_for(gx)
	_check_true(FileAccess.file_exists(gd), "sibling .gd written next to the .guitkx")
	var gd_src := FileAccess.get_file_as_string(gd)
	_check(gd_src, "class_name Fixture", "sibling .gd named from the file")
	_check(gd_src, "V.Label(", "sibling .gd compiled the markup")
	_check(gd_src, "const __RUI_HOOK_SIG := \"\"", "hookless component emits an empty Fast Refresh fingerprint")
	# Fast Refresh fingerprint (H4): ordered hook calls, builtin + Hooks.-qualified + user use_*
	var sig_r := RuitkGuitkx.compile("component SigProbe() {\n\tvar a = useState(0)\n\tvar b = use_custom_thing()\n\tHooks.useEffect(func(): pass, [])\n\treturn ( <Label text={ str(a[0]) } /> )\n}\n", "SigProbe")
	_check_true(bool(sig_r["ok"]), "sig probe compiles: " + str(sig_r["diagnostics"]))
	_check(str(sig_r["gd"]), "const __RUI_HOOK_SIG := \"useState|use_custom_thing|useEffect\"",
		"fingerprint lists the hooks in call order")
	_check_true(not Codegen.is_stale(gx), "not stale right after compile")
	# The env guard: an UNREADABLE VOCABULARY is a tooling state, not a source regression — the
	# compile must refuse (env_error + GUITKX2507) and compile_file must PRESERVE the sibling .gd
	# and the sidecar (during the editor's first filesystem scan this exact state once wiped every
	# generated demo .gd on a fresh CI clone). The lazy loader then self-heals on the next call.
	var sidecar_before := FileAccess.get_file_as_string(gx + ".diags.json")
	RuitkGuitkx._VOCAB = {}
	RuitkGuitkx._VOCAB_PATH = "res://addons/reactive_ui_toolkit/guitkx/__no_such_vocabulary__.json"
	var r_env := Codegen.compile_file(gx)
	_check_true(not r_env["ok"] and bool(r_env.get("env_error", false)), "unreadable vocabulary is an env_error: " + str(r_env))
	_check_true(str((r_env["diagnostics"] as Array)[0]["code"]) == "GUITKX2507", "env_error carries GUITKX2507")
	_check_true(FileAccess.file_exists(gd), "sibling .gd PRESERVED on env_error (never stale-deleted)")
	_check_true(FileAccess.get_file_as_string(gx + ".diags.json") == sidecar_before, "sidecar untouched on env_error")
	RuitkGuitkx._VOCAB_PATH = "res://addons/reactive_ui_toolkit/guitkx/vocabulary.json"
	_check_true(Codegen.compile_file(gx)["ok"], "vocabulary self-heals on the next compile (lazy retry)")
	# T1.1: a file that STOPS compiling must not leave its stale sibling .gd behind (the editor would
	# keep running code that no longer matches the source). compile_file deletes it.
	var f_bad := FileAccess.open(gx, FileAccess.WRITE)
	f_bad.store_string("component Fixture() {\n\treturn ( <Broken> )\n}\n")
	f_bad.close()
	var r_bad := Codegen.compile_file(gx)
	_check_true(not r_bad["ok"], "broken rewrite fails to compile")
	_check_true(not FileAccess.file_exists(gd), "stale sibling .gd deleted on failed compile")
	# 0.7.1: a KNOWN-BROKEN file (sidecar hash-matches the current content and carries an error
	# entry) is NOT stale -- the watch poll must not busy-recompile it every _POLL_SECS -- but its
	# persisted verdict stays visible through sidecar_error_diags (compile_all re-surfaces it on
	# every sweep; the dock dedup is what prevents spam, never silence).
	_check_true(not Codegen.is_stale(gx), "known-broken content is not stale (sidecar hash-match + error entry)")
	_check_true(Codegen.sidecar_error_diags(gx).size() > 0, "sidecar_error_diags surfaces the persisted verdict")
	# fix it again -> the .gd comes back
	var f_fix := FileAccess.open(gx, FileAccess.WRITE)
	f_fix.store_string(src)
	f_fix.close()
	_check_true(Codegen.compile_file(gx)["ok"], "fixed file compiles again")
	_check_true(FileAccess.file_exists(gd), "sibling .gd regenerated after the fix")
	# delete the .gd -> stale again (missing-file branch: the sidecar is CLEAN for this content, so
	# its absence of an error verdict must not mask a manually-removed output)
	DirAccess.remove_absolute(gd)
	_check_true(Codegen.is_stale(gx), "stale again after sibling .gd removed")
	DirAccess.remove_absolute(gx + ".diags.json")
	DirAccess.remove_absolute(gx)
	# has_stale: the watch-poll predicate (0.7.1) -- false while everything is fresh or known-broken,
	# true the moment content changes. Mtimes are whole seconds, so a save landing in the same second
	# as the last compile ties on mtime; the tie is broken by CONTENT (sidecar src_hash), which makes
	# this deterministic where bare `>` silently missed it ("saved it and Godot never recompiled").
	var hs_dir := "res://tests/__has_stale_tmp"
	DirAccess.make_dir_recursive_absolute(hs_dir)
	if Codegen.compiler_changed():
		Codegen.compile_all(hs_dir)   # settle the fingerprint marker so has_stale reflects FILE state
	var hgx := hs_dir + "/probe.guitkx"
	var hf := FileAccess.open(hgx, FileAccess.WRITE)
	hf.store_string("component Probe() {\n\treturn ( <Label text=\"a\" /> )\n}\n")
	hf.close()
	_check_true(Codegen.has_stale(hs_dir), "fresh .guitkx with no sibling .gd reads stale")
	_check_true(Codegen.compile_file(hgx)["ok"], "probe compiles")
	var hf2 := FileAccess.open(hgx, FileAccess.WRITE)   # rewrite lands in the SAME mtime second
	hf2.store_string("component Probe() {\n\treturn ( <Label text=\"b\" /> )\n}\n")
	hf2.close()
	_check_true(Codegen.is_stale(hgx), "a save in the same second as the last compile is stale (mtime tie, hash differs)")
	_check_true(Codegen.compile_file(hgx)["ok"], "probe recompiles")
	var hbad := FileAccess.open(hgx, FileAccess.WRITE)
	hbad.store_string("component Probe() {\n\treturn ( <Broken> )\n}\n")
	hbad.close()
	_check_true(not Codegen.compile_file(hgx)["ok"], "broken probe errors")
	_check_true(not Codegen.has_stale(hs_dir), "known-broken probe does not keep the watch poll hot")
	var hsweep := Codegen.compile_all(hs_dir)
	_check_true((hsweep["errors"] as Array).size() == 1 and (hsweep["compiled"] as Array).is_empty(),
		"sweep re-surfaces the persisted error without recompiling: " + str(hsweep))
	_check_true(int(hsweep.get("total", -1)) == 1, "sweep reports the tracked total")
	DirAccess.remove_absolute(hgx + ".diags.json")
	DirAccess.remove_absolute(hgx)   # (the probe .gd was already T1.1-deleted by the broken compile)
	# 0.8.1: renaming/deleting a .guitkx must not leak its generated outputs (field capture
	# 2026-07-04: renaming components/deep_tree.guitkx left an orphaned deep_tree.gd whose
	# class_name DUPLICATED the real demo's -- project-wide resolution chaos). The sweep removes
	# outputs whose AUTO-GENERATED source is gone; hand-written .gd files are never touched.
	var o_dir := "res://tests/__orphan_tmp"
	DirAccess.make_dir_recursive_absolute(o_dir)
	var ogx := o_dir + "/orig.guitkx"
	var of := FileAccess.open(ogx, FileAccess.WRITE)
	of.store_string("component Orig() {\n\treturn ( <Label text=\"o\" /> )\n}\n")
	of.close()
	_check_true(Codegen.compile_file(ogx)["ok"], "orphan fixture compiles")
	var ogd := Codegen.gd_path_for(ogx)
	var hand := o_dir + "/handwritten.gd"
	var hf3 := FileAccess.open(hand, FileAccess.WRITE)
	hf3.store_string("extends RefCounted\nfunc hi() -> int:\n\treturn 1\n")
	hf3.close()
	DirAccess.remove_absolute(ogx)   # the rename/delete: source gone, outputs remain
	_check_true(Codegen.has_stale(o_dir), "an orphaned output makes the poll predicate hot")
	var o_sweep := Codegen.compile_all(o_dir)
	_check_true((o_sweep.get("removed", []) as Array).has(ogd), "sweep reports the removed orphan: " + str(o_sweep))
	_check_true(not FileAccess.file_exists(ogd), "orphaned .gd deleted")
	_check_true(not FileAccess.file_exists(ogx + ".diags.json"), "orphaned sidecar deleted")
	_check_true(FileAccess.file_exists(hand), "hand-written .gd is never touched")
	_check_true(not Codegen.has_stale(o_dir), "poll predicate settles after the cleanup")
	DirAccess.remove_absolute(hand)
	# GUITKX2106: the copy-paste flow -- a SECOND source binding the same class errors with no
	# output written (the incumbent keeps compiling), so a duplicate class_name can never exist
	# on disk; the project converges the moment the copy is renamed, and the loser's orphaned
	# sidecar is swept with it.
	var dd := "res://tests/__dupe_tmp"
	DirAccess.make_dir_recursive_absolute(dd)
	var d_orig := dd + "/a_orig.guitkx"
	var d_copy := dd + "/z_copy.guitkx"
	var d_src := "@class_name DupeProbe\n\ncomponent DupeProbe {\n\treturn ( <Label text=\"1\" /> )\n}\n"
	var df1 := FileAccess.open(d_orig, FileAccess.WRITE)
	df1.store_string(d_src)
	df1.close()
	_check_true(Codegen.compile_file(d_orig)["ok"], "dupe incumbent compiles")
	var df2 := FileAccess.open(d_copy, FileAccess.WRITE)
	df2.store_string(d_src)
	df2.close()
	var d_sweep := Codegen.compile_all(dd)
	_check_true((d_sweep["errors"] as Array).size() == 1 and str(((d_sweep["errors"] as Array)[0] as Dictionary)["path"]) == d_copy,
		"the COPY errors, the incumbent does not: " + str(d_sweep["errors"]))
	var d_diag: Dictionary = (((d_sweep["errors"] as Array)[0] as Dictionary)["diagnostics"] as Array)[0]
	_check_true(str(d_diag["code"]) == "GUITKX2106", "the copy is flagged GUITKX2106 (got %s)" % str(d_diag))
	_check_true(not FileAccess.file_exists(Codegen.gd_path_for(d_copy)), "the copy never produces a .gd -- no duplicate class can exist")
	_check_true(FileAccess.file_exists(Codegen.gd_path_for(d_orig)), "the incumbent's .gd survives")
	DirAccess.remove_absolute(d_copy)   # the rename: copy becomes its own class
	var d_new := dd + "/renamed.guitkx"
	var df3 := FileAccess.open(d_new, FileAccess.WRITE)
	df3.store_string("@class_name RenamedProbe\n\ncomponent RenamedProbe {\n\treturn ( <Label text=\"2\" /> )\n}\n")
	df3.close()
	var d_sweep2 := Codegen.compile_all(dd)
	_check_true((d_sweep2["errors"] as Array).is_empty(), "post-rename sweep is clean: " + str(d_sweep2["errors"]))
	_check_true(FileAccess.file_exists(Codegen.gd_path_for(d_new)), "the renamed component compiles")
	_check_true(not FileAccess.file_exists(d_copy + ".diags.json"), "the dupe-loser's orphaned sidecar was swept")
	for lf in [d_orig, Codegen.gd_path_for(d_orig), d_orig + ".diags.json", d_new, Codegen.gd_path_for(d_new), d_new + ".diags.json"]:
		if FileAccess.file_exists(str(lf)):
			DirAccess.remove_absolute(str(lf))
	# BUG-ISO-1 (0.12.1): two files whose FIRST EXPORT is a same-named VALUE must NOT collide --
	# a value binding emits no `class_name` (the emitter's value/class rule), so there is nothing
	# to arbitrate: both compile, no GUITKX2106, and an importer preloads its target by path.
	var v_a := dd + "/a_vals.guitkx"
	var v_z := dd + "/z_vals.guitkx"
	var v_c := dd + "/c_imp.guitkx"
	var vf1 := FileAccess.open(v_a, FileAccess.WRITE)
	vf1.store_string("export speed := 10\n")
	vf1.close()
	var vf2 := FileAccess.open(v_z, FileAccess.WRITE)
	vf2.store_string("export speed := 99\n")
	vf2.close()
	var vf3 := FileAccess.open(v_c, FileAccess.WRITE)
	vf3.store_string("import { speed } from \"./z_vals\"\n\nexport CImp() -> RuitkVNode {\n\treturn ( <Label text={str(speed)} /> )\n}\n")
	vf3.close()
	var v_sweep := Codegen.compile_all(dd)
	_check_true((v_sweep["errors"] as Array).is_empty(), "value-binding twins: no 2106, sweep clean: " + str(v_sweep["errors"]))
	_check_true(FileAccess.file_exists(Codegen.gd_path_for(v_a)) and FileAccess.file_exists(Codegen.gd_path_for(v_z)),
		"value-binding twins: BOTH .gd written")
	_check_true(not FileAccess.get_file_as_string(Codegen.gd_path_for(v_a)).contains("class_name")
		and not FileAccess.get_file_as_string(Codegen.gd_path_for(v_z)).contains("class_name"),
		"value-binding twins: neither emits class_name (nothing to collide)")
	_check_true(FileAccess.get_file_as_string(Codegen.gd_path_for(v_c)).contains(Codegen.gd_path_for(v_z)),
		"value import preloads the RESOLVED PATH of its own target (z_vals), untouched by the twin")
	for vlf in [v_a, v_z, v_c]:
		for vp in [str(vlf), Codegen.gd_path_for(str(vlf)), str(vlf) + ".diags.json"]:
			if FileAccess.file_exists(vp):
				DirAccess.remove_absolute(vp)
	# GUITKX2107: deleting a referenced component flags the DEPENDENT -- which is not mtime-stale
	# -- at the dangling tag, in the SAME sweep that removes the orphan; restoring the component
	# heals the dependent on the next sweep (recompile clears the sidecar).
	var g_dir := "res://tests/__dangling_tmp"
	DirAccess.make_dir_recursive_absolute(g_dir)
	if Codegen.compiler_changed():
		Codegen.compile_all(g_dir)   # settle the fingerprint marker; the 2107 path is non-force
	var g_child := g_dir + "/child_probe.guitkx"
	var g_parent := g_dir + "/parent_probe.guitkx"
	# 0.10.0: strict cross-file resolution -- the parent IMPORTS the child (an implicit reference is a
	# GUITKX2305 error now). The import still lowers through V.comp, so the 2107 dangling-ref machinery
	# (which keys on the recorded V.comp path) works exactly as before when the child is deleted.
	var g_child_src := "@class_name ChildProbe\n\nexport component ChildProbe {\n\treturn ( <Label text=\"c\" /> )\n}\n"
	var gf1 := FileAccess.open(g_child, FileAccess.WRITE)
	gf1.store_string(g_child_src)
	gf1.close()
	var gf2 := FileAccess.open(g_parent, FileAccess.WRITE)
	gf2.store_string("@class_name ParentProbe\n\nimport { ChildProbe } from \"./child_probe\"\n\nexport component ParentProbe {\n\treturn ( <VBoxContainer><ChildProbe /></VBoxContainer> )\n}\n")
	gf2.close()
	var g_sweep1 := Codegen.compile_all(g_dir)
	_check_true((g_sweep1["errors"] as Array).is_empty() and (g_sweep1["compiled"] as Array).size() == 2,
		"dangling fixture compiles clean: " + str(g_sweep1["errors"]))
	_check(FileAccess.get_file_as_string(Codegen.gd_path_for(g_parent)), "V.comp(", "parent references child by path")
	DirAccess.remove_absolute(g_child)
	var g_sweep2 := Codegen.compile_all(g_dir)
	_check_true(not FileAccess.file_exists(Codegen.gd_path_for(g_child)), "child's orphaned .gd swept")
	var g_errs: Array = g_sweep2["errors"]
	var g_hit := false
	for ge in g_errs:
		if str((ge as Dictionary).get("path", "")) == g_parent:
			for gd2 in ((ge as Dictionary).get("diagnostics", []) as Array):
				if str((gd2 as Dictionary).get("code", "")) == "GUITKX2107":
					g_hit = true
	_check_true(g_hit, "dependent flagged GUITKX2107 in the SAME sweep as the deletion: " + str(g_errs))
	_check_true(FileAccess.file_exists(Codegen.gd_path_for(g_parent)), "dependent's .gd kept (last good code)")
	# a RE-SAVE of the flagged (unchanged) dependent bumps its mtime but must NOT wake the poll:
	# the 2107 branch re-surfaces without compiling, so an mtime-stale verdict here looped the
	# sweep every 2s forever (field capture 2026-07-04). Known-broken content is not stale.
	var g_same := FileAccess.get_file_as_string(g_parent)
	var gf_rs := FileAccess.open(g_parent, FileAccess.WRITE)
	gf_rs.store_string(g_same)
	gf_rs.close()
	_check_true(not Codegen.has_stale(g_dir), "re-saving the flagged dependent does not wake the poll (no sweep loop)")
	var g_sweep2b := Codegen.compile_all(g_dir)
	_check_true((g_sweep2b["compiled"] as Array).is_empty() and (g_sweep2b["errors"] as Array).size() == 1,
		"a sweep after the re-save only re-surfaces (no compile churn): " + str(g_sweep2b["errors"]))
	var gf3 := FileAccess.open(g_child, FileAccess.WRITE)   # restore -> heal
	gf3.store_string(g_child_src)
	gf3.close()
	var g_sweep3 := Codegen.compile_all(g_dir)
	_check_true((g_sweep3["errors"] as Array).is_empty(), "restore heals the dependent: " + str(g_sweep3["errors"]))
	_check_true((g_sweep3["compiled"] as Array).size() == 2, "child recompiled AND dependent healed (recompiled)")
	# FOLDER deletion: source AND outputs vanish together -- no orphan left for the poll to
	# notice, and the dependent isn't mtime-stale (field capture 2026-07-04: the 2107 only
	# landed when a save/focus happened to cause a sweep). The dangling-refs pass must make the
	# poll hot anyway, settle once flagged, go hot again on restore (heal work), then settle.
	for lf3 in [g_child, Codegen.gd_path_for(g_child), g_child + ".diags.json"]:
		if FileAccess.file_exists(str(lf3)):
			DirAccess.remove_absolute(str(lf3))
	_check_true(Codegen.has_stale(g_dir), "folder-style deletion (no orphans) still makes the poll hot")
	var g_sweep4 := Codegen.compile_all(g_dir)
	_check_true((g_sweep4["errors"] as Array).size() == 1, "folder-style deletion flags 2107: " + str(g_sweep4["errors"]))
	_check_true(not Codegen.has_stale(g_dir), "poll settles once the flag lands")
	var gf4 := FileAccess.open(g_child, FileAccess.WRITE)
	gf4.store_string(g_child_src)
	gf4.close()
	_check_true(Codegen.has_stale(g_dir), "restoring the component makes the poll hot again (heal work)")
	var g_sweep5 := Codegen.compile_all(g_dir)
	_check_true((g_sweep5["errors"] as Array).is_empty(), "the heal sweep clears everything: " + str(g_sweep5["errors"]))
	_check_true(not Codegen.has_stale(g_dir), "poll settles clean after the heal")
	for lf2 in [g_child, Codegen.gd_path_for(g_child), g_child + ".diags.json", g_parent, Codegen.gd_path_for(g_parent), g_parent + ".diags.json"]:
		if FileAccess.file_exists(str(lf2)):
			DirAccess.remove_absolute(str(lf2))

func _test_cold_open_recovery() -> void:
	# R0 (0.6.1): the vocabulary the compiler actually uses is the EMBEDDED const projection
	# (guitkx_vocabulary.gen.gd) -- it must never drift from vocabulary.json, the single source of
	# truth shared verbatim with the LSP. Regenerate with dev/gen_vocabulary.gd after any change.
	var gen = preload("res://addons/reactive_ui_toolkit/guitkx/guitkx_vocabulary.gen.gd")
	var json_text := FileAccess.get_file_as_string("res://addons/reactive_ui_toolkit/guitkx/vocabulary.json")
	var parsed = JSON.parse_string(json_text)
	_check_true(parsed is Dictionary, "vocabulary.json parses")
	_check_true(JSON.stringify(parsed) == JSON.stringify(gen.DATA),
		"guitkx_vocabulary.gen.gd in sync with vocabulary.json (regenerate: dev/gen_vocabulary.gd)")
	RuitkGuitkx._VOCAB = {}
	_check_true(not RuitkGuitkx.vocab().is_empty(), "vocab() serves the embedded const at the default path")
	# Editor static-init reality (2026-07-04, THE "Godot never recompiles" root cause): during the
	# editor's early script indexing `static var` INITIALIZERS may not have run, so _VOCAB_PATH
	# reads as "" (String type default) -- which used to fall into the test-seam file branch, read
	# a file at path "", and hold every compile of every editor session forever. Headless runs
	# initialize statics and were always healthy -- exactly why no suite ever caught it. An empty
	# path must therefore behave as DEFAULT (embedded const, no file read, no hold).
	RuitkGuitkx._VOCAB = {}
	RuitkGuitkx._VOCAB_PATH = ""
	_check_true(not RuitkGuitkx.vocab().is_empty(), "an uninitialized-static ('') vocab path serves the embedded const")
	RuitkGuitkx._VOCAB_PATH = RuitkGuitkx._VOCAB_PATH_DEFAULT
	RuitkGuitkx._VOCAB = {}
	# R2+R3 (0.6.1): a sweep hitting the unreadable-vocabulary environment reports those files as
	# HELD -- not errors (no per-file dock line; the loader's hold warning announced the episode) --
	# and must NOT consume the compiler-changed fingerprint marker: a held forced sweep compiled
	# nothing, so the force has to re-fire next sweep, or old-compiler outputs and sidecars survive
	# every later sweep (the 2026-07-03 zombie-sidecar field capture).
	var dir := "res://tests/__cold_open_tmp"
	DirAccess.make_dir_recursive_absolute(dir)
	var gx := dir + "/held_fixture.guitkx"
	var f := FileAccess.open(gx, FileAccess.WRITE)
	f.store_string("component HeldFixture(msg: String = \"hi\") {\n\treturn ( <Label text={ msg } /> )\n}\n")
	f.close()
	var marker := "res://.godot/rui_guitkx_compiler.fp"
	if FileAccess.file_exists(marker):
		DirAccess.remove_absolute(marker)   # -> compiler_changed() == true: the next sweep is FORCED
	RuitkGuitkx._VOCAB = {}
	RuitkGuitkx._VOCAB_PATH = "res://addons/reactive_ui_toolkit/guitkx/__no_such_vocabulary__.json"
	var held_sweep := Codegen.compile_all(dir)
	_check_true((held_sweep["compiled"] as Array).is_empty() and (held_sweep["errors"] as Array).is_empty(),
		"held sweep reports no compiles and NO errors: " + str(held_sweep))
	_check_true((held_sweep["held"] as Array) == [gx], "env-held file lands in held[]: " + str(held_sweep["held"]))
	_check_true(not FileAccess.file_exists(marker), "fingerprint marker NOT consumed by a held forced sweep")
	# Environment recovers (default path -> embedded const): the same sweep now compiles, holds
	# nothing, and the fingerprint marker finally lands.
	RuitkGuitkx._VOCAB_PATH = RuitkGuitkx._VOCAB_PATH_DEFAULT
	RuitkGuitkx._VOCAB = {}
	var ok_sweep := Codegen.compile_all(dir)
	_check_true((ok_sweep["held"] as Array).is_empty() and (ok_sweep["errors"] as Array).is_empty(),
		"recovered sweep holds nothing: " + str(ok_sweep))
	_check_true((ok_sweep["compiled"] as Array).size() == 1, "recovered sweep compiles the previously-held file")
	_check_true(bool(((ok_sweep["compiled"] as Array)[0] as Dictionary).get("gd_ok", false)),
		"sweep entries carry gd_ok (the HMR push filters on it)")
	_check_true(FileAccess.file_exists(marker), "fingerprint marker written once the forced sweep actually ran")
	# The persisted marker must be THIS process's healthily-computed fingerprint — never "" and
	# never a value hashed over scan-window empty reads (compiler_fingerprint returns "" then and
	# _write_fp_marker refuses to persist it).
	_check_true(Codegen.compiler_fingerprint() != "" and FileAccess.get_file_as_string(marker) == Codegen.compiler_fingerprint(),
		"marker holds the readable-sources fingerprint")
	DirAccess.remove_absolute(Codegen.gd_path_for(gx))
	DirAccess.remove_absolute(gx + ".diags.json")
	DirAccess.remove_absolute(gx)
	# 0.6.2: an empty SOURCE read of an existing file is the scan-window flake -- held (outputs
	# kept, env_error), never a compile failure (which would T1.1-delete the healthy sibling .gd).
	var gx2 := dir + "/empty_read.guitkx"
	var f2 := FileAccess.open(gx2, FileAccess.WRITE)
	f2.store_string("component EmptyRead() {\n\treturn ( <Label text=\"x\" /> )\n}\n")
	f2.close()
	var r_ok := Codegen.compile_file(gx2)
	_check_true(bool(r_ok["ok"]) and bool(r_ok.get("gd_parse_ok", false)), "healthy fixture compiles and its generated .gd parses: " + str(r_ok))
	var gd2 := Codegen.gd_path_for(gx2)
	var f3 := FileAccess.open(gx2, FileAccess.WRITE)   # truncate to empty = the flake, simulated
	f3.close()
	var r_empty := Codegen.compile_file(gx2)
	_check_true(not r_empty["ok"] and bool(r_empty.get("env_error", false)), "empty source read is HELD (env), not a compile failure: " + str(r_empty))
	_check_true(FileAccess.file_exists(gd2), "sibling .gd preserved on an empty source read")
	# 0.6.2: an unknown identifier is legal guitkx (a GDScript-level concern), but the generated
	# .gd is parse-checked immediately on a throwaway GDScript (Unity parity: errors surface at
	# compile time in the dock, not on first load at play time).
	var f4 := FileAccess.open(gx2, FileAccess.WRITE)
	f4.store_string("component EmptyRead() {\n\treturn ( <Label text={ str(slisced[0]) } /> )\n}\n")
	f4.close()
	var r_typo := Codegen.compile_file(gx2)
	_check_true(bool(r_typo["ok"]), "unknown identifier still compiles at the guitkx level: " + str(r_typo))
	_check_true(not bool(r_typo.get("gd_parse_ok", true)), "generated .gd parse-check FAILS on the unknown identifier")
	DirAccess.remove_absolute(gd2)
	DirAccess.remove_absolute(gx2 + ".diags.json")
	DirAccess.remove_absolute(gx2)
	DirAccess.remove_absolute(dir)

func _test_control_flow() -> void:
	var src := "component List2(items: Array = [], show_header: bool = true) {\n" + \
		"\treturn (\n" + \
		"\t\t<VBoxContainer>\n" + \
		"\t\t\t@if (show_header) { return ( <Label text=\"Header\" /> ) }\n" + \
		"\t\t\t@for (it in items) { return ( <Label text={ str(it) } /> ) }\n" + \
		"\t\t</VBoxContainer>\n" + \
		"\t)\n}\n"
	var r := RuitkGuitkx.compile(src, "List2")
	if not r["ok"]:
		_fail("control_flow: compile failed: " + str(r["diagnostics"]))
	var gd: String = r["gd"]
	print("--- generated (List2) ---\n" + gd + "----------------------------")
	_check(gd, "var __cf0 = null", "@if hoisted to pre-statement")
	_check(gd, "if show_header:", "@if condition")
	_check(gd, "var __cf1: Array = []", "@for accumulator")
	_check(gd, "for it in items:", "@for header")
	_check(gd, "__cf1.append(", "@for body append")
	_check(gd, "[__cf0, __cf1]", "control-flow locals referenced in children")
	# runtime: header shown + 2 items -> 3 Labels; header hidden -> 2 Labels
	var gd2 := gd.replace("class_name List2\n", "")
	var path := "user://__guitkx_list2.gd"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(gd2)
	f.close()
	var script = load(path)
	_check_true(script != null, "List2 .gd loads")
	# fresh container per case (headless --script has no frame loop, so queued frees don't flush)
	var c := Control.new()
	root.add_child(c)
	var app := RuitkRoot.create(c, V.fc(script.render, { "items": ["a", "b"], "show_header": true }))
	_check_true(_count_class(c, "Label") == 3, "header + 2 items = 3 Labels (got %d)" % _count_class(c, "Label"))
	app.unmount()
	c.free()
	var c2 := Control.new()
	root.add_child(c2)
	var app2 := RuitkRoot.create(c2, V.fc(script.render, { "items": ["a", "b"], "show_header": false }))
	_check_true(_count_class(c2, "Label") == 2, "no header -> 2 Labels (got %d)" % _count_class(c2, "Label"))
	app2.unmount()
	c2.free()

func _count_class(node: Node, cls: String) -> int:
	var total := 1 if node.get_class() == cls else 0
	for ch in node.get_children():
		total += _count_class(ch, cls)
	return total

func _test_spread() -> void:
	# `{...spread}` merges into props left-to-right (later wins), order-preserving, via V._spread_all.
	# Component tag:
	var c := RuitkGuitkx.compile("component C(base, t) {\n\treturn ( <Card {...base} title={ t } /> )\n}\n", "C")
	if not c["ok"]:
		_fail("spread: component compile failed: " + str(c["diagnostics"]))
	else:
		_check(c["gd"], "V.fc(Card.render, V._spread_all([(base), { \"title\": t }]))", "spread on a component")
	# Host tag with explicit props both BEFORE and AFTER a spread (order + last-wins preserved):
	var h := RuitkGuitkx.compile("component H(cfg) {\n\treturn ( <Button text=\"Hi\" {...cfg} onPressed={ f } /> )\n}\n", "H")
	if not h["ok"]:
		_fail("spread: host compile failed: " + str(h["diagnostics"]))
	else:
		_check(h["gd"], "V.Button(V._spread_all([{ \"text\": \"Hi\" }, (cfg), { \"onPressed\": f }]))", "spread on a host, order preserved")
	# Regression: a plain element (no spread) still emits a bare dict literal (unchanged hot path).
	var p := RuitkGuitkx.compile("component P() {\n\treturn ( <Button text=\"Hi\" /> )\n}\n", "P")
	if p["ok"]:
		_check(p["gd"], "V.Button({ \"text\": \"Hi\" })", "no-spread element keeps the plain dict literal")
		_check_true(not (p["gd"] as String).contains("_spread_all"), "no-spread element does NOT call _spread_all")

func _test_emit() -> void:
	var src := "@class_name Greeting\n\ncomponent Greeting(name: String = \"World\") {\n" + \
		"\tvar s = useState(0)\n" + \
		"\treturn (\n" + \
		"\t\t<VBoxContainer style={ {\"separation\": 8} }>\n" + \
		"\t\t\t<Label text={ \"Hello, %s (%d)\" % [name, s[0]] } />\n" + \
		"\t\t\t<Button text=\"+1\" onPressed={ inc } />\n" + \
		"\t\t</VBoxContainer>\n" + \
		"\t)\n}\n"
	var r := RuitkGuitkx.compile(src, "Greeting")
	if not r["ok"]:
		_fail("emit: compile failed: " + str(r["diagnostics"]))
	var gd: String = r["gd"]
	print("--- generated (Greeting) ---\n" + gd + "----------------------------")
	_check(gd, "class_name Greeting", "class_name")
	_check(gd, "props.get(\"name\", \"World\")", "param unpack")
	_check(gd, "Hooks.useState(0)", "hook auto-prefix")
	_check(gd, "V.VBoxContainer(", "VBox -> V.vbox")
	_check(gd, "V.Label(", "Label -> V.label")
	_check(gd, "V.Button(", "Button -> V.button")
	_check(gd, "\"onPressed\": inc", "event prop (React-canonical name flows through the compiler verbatim)")
	_check(gd, "\"style\":", "style prop")

func _test_runtime() -> void:
	# hook-free so render() can run outside a reconcile; multi-line setup exercises the dedent fix
	# (a double-indented second setup line would be a parse error on load)
	var src := "component Box2(label: String = \"hi\") {\n" + \
		"\tvar upper = label.to_upper()\n" + \
		"\tvar tag = \"[\" + upper + \"]\"\n" + \
		"\treturn (\n" + \
		"\t\t<VBoxContainer>\n" + \
		"\t\t\t<Label text={ tag } />\n" + \
		"\t\t\t<Button text=\"go\" />\n" + \
		"\t\t</VBoxContainer>\n" + \
		"\t)\n}\n"
	var r := RuitkGuitkx.compile(src, "Box2")
	if not r["ok"]:
		_fail("runtime: compile failed: " + str(r["diagnostics"]))
	var gd: String = r["gd"].replace("class_name Box2\n", "")   # avoid global-name registration on load
	_check(gd, "\tvar upper = label.to_upper()", "setup line 1 single-indented")
	_check(gd, "\tvar tag = ", "setup line 2 single-indented (dedent fix)")
	_check_true(not ("\t\tvar tag" in gd), "setup line 2 NOT double-indented")
	var path := "user://__guitkx_box2.gd"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(gd)
	f.close()
	var script = load(path)
	_check_true(script != null, "generated .gd loads as a script")
	var c := Control.new()
	root.add_child(c)
	var app := RuitkRoot.create(c, V.fc(script.render, { "label": "WORLD" }))
	# walk the produced node tree
	var vbox := _find_first(c, "VBoxContainer")
	_check_true(vbox != null, "rendered a VBoxContainer")
	var lbl := _find_first(c, "Label")
	_check_true(lbl != null and lbl.text == "[WORLD]", "Label text bound from setup-derived value")
	var btn := _find_first(c, "Button")
	_check_true(btn != null and btn.text == "go", "Button text literal")
	app.unmount()
	c.queue_free()

func _find_first(node: Node, cls: String) -> Node:
	if node.get_class() == cls:
		return node
	for ch in node.get_children():
		var r := _find_first(ch, cls)
		if r != null:
			return r
	return null

func _check(haystack: String, needle: String, msg: String) -> void:
	if not (needle in haystack):
		_fail("MISSING [%s]: expected to find `%s`" % [msg, needle])

func _check_true(cond: bool, msg: String) -> void:
	if not cond:
		_fail(msg)

func _fail(msg: String) -> void:
	print("[guitkx_test] FAIL: ", msg)
	_failed = true

## ES-modules Layer 2 (E-01..E-05, E-10 slice): plain, signature-classified declarations
## (component/hook/util/value) alongside the deprecated wrapper keywords. Import-surface
## extensions (E-06..E-09) are a separate, not-yet-landed chunk of this leg -- not covered here.
func _test_es_modules_declarations() -> void:
	# E-01: a plain component (`-> RuitkVNode` annotation, PascalCase) compiles clean, no 2320.
	var comp := RuitkGuitkx.compile("Foo() -> RuitkVNode {\n\treturn ( <Label /> )\n}\n", "Foo")
	_check_true(comp["ok"] and (comp["diagnostics"] as Array).is_empty(), "ES: plain component compiles with no diagnostics (got %s)" % str(comp.get("diagnostics", [])))
	_check_true((comp["gd"] as String).contains("static func render("), "ES: sole plain component emits render")

	# E-01/T2.6: a plain component still enforces PascalCase (the existing 2100, reused).
	var comp_lc := RuitkGuitkx.compile("foo() -> RuitkVNode {\n\treturn ( <Label /> )\n}\n", "foo")
	_check_true(not comp_lc["ok"] and _has_code(comp_lc, "GUITKX2100"), "ES: plain component name must be PascalCase (got %s)" % str(comp_lc["diagnostics"]))

	# E-02 cross-guard: `use_`-prefixed + `-> RuitkVNode` is 2321, not a silent component/2100 double-hit.
	var xguard := RuitkGuitkx.compile("use_foo() -> RuitkVNode {\n\treturn ( <Label /> )\n}\n", "use_foo")
	_check_true(not xguard["ok"] and _has_code(xguard, "GUITKX2321") and not _has_code(xguard, "GUITKX2100"), "E-02: use_-prefixed + RuitkVNode is 2321 only (got %s)" % str(xguard["diagnostics"]))

	# E-01 classifier guard (GUITKX2328): a decl that RETURNS MARKUP but is not a component. Left
	# unguarded, the body lowered VERBATIM and the generated .gd could not parse -- with `0 error(s)`
	# reported, because a raw GDScript parse error names no .guitkx source. The pre-0.13 spelling is
	# called out by name: it is what every 0.12->0.13 upgrader who skipped the codemod hits.
	# The pre-0.13 spelling is BUILT, never written as a literal: tests/guitkx_rename_migrate.gd
	# runs the rename codemod over res:// project-wide, and a literal here would be silently
	# rewritten to the new spelling -- turning this fixture into a valid component and quietly
	# gutting the test (it did exactly that once before this comment existed).
	var old_cls := "RUI" + "VNode"
	var old_ret := RuitkGuitkx.compile("HelloWorld() -> %s {\n\treturn ( <Label /> )\n}\n" % old_cls, "hello")
	_check_true(not old_ret["ok"] and _has_code(old_ret, "GUITKX2328"), "E-01: markup in a non-component is 2328 (got %s)" % str(old_ret["diagnostics"]))
	_check_true(str(_diag(old_ret, "GUITKX2328").get("message", "")).contains("migrate_0_13_0"), "E-01: 2328 names the codemod on the pre-0.13 spelling (got %s)" % str(_diag(old_ret, "GUITKX2328").get("message", "")))
	var no_ret := RuitkGuitkx.compile("HelloWorld() {\n\treturn ( <Label /> )\n}\n", "hello")
	_check_true(not no_ret["ok"] and _has_code(no_ret, "GUITKX2328"), "E-01: markup with NO return annotation is 2328 (got %s)" % str(no_ret["diagnostics"]))
	# ...and the guard must never fire on a parenthesized comparison, which merely LOOKS like markup.
	var cmp_ok := RuitkGuitkx.compile("lt(a: int, b: int) -> bool {\n\treturn (a < b)\n}\n", "lt")
	_check_true(cmp_ok["ok"] and not _has_code(cmp_ok, "GUITKX2328"), "E-01: `return (a < b)` is not markup (got %s)" % str(cmp_ok.get("diagnostics", [])))

	# E-01: a `use_`-prefixed callable with no `-> RuitkVNode` is a hook -- emits under its own name
	# (no `render` aliasing; that only applies to components).
	var hook := RuitkGuitkx.compile("use_count(start: int) -> int {\n\treturn start\n}\n", "use_count")
	_check_true(hook["ok"] and (hook["diagnostics"] as Array).is_empty(), "ES: plain hook compiles clean (got %s)" % str(hook.get("diagnostics", [])))
	_check_true((hook["gd"] as String).contains("static func use_count(") and not (hook["gd"] as String).contains("static func render("), "ES: lone plain hook emits under its own name, no render")

	# E-01: anything else (no use_ prefix, no RuitkVNode return) is a util.
	var util := RuitkGuitkx.compile("format_score(score: int) -> String {\n\treturn \"Score: %d\" % score\n}\n", "format_score")
	_check_true(util["ok"] and (util["diagnostics"] as Array).is_empty(), "ES: plain util compiles clean (got %s)" % str(util.get("diagnostics", [])))
	_check_true((util["gd"] as String).contains("static func format_score(") and (util["gd"] as String).contains("\"kind\": \"util\""), "ES: util emits under its own name with kind util in __RUI_DECLS")

	# E-04/E-05: the three value spellings all emit `static var`, never `const`.
	var vals := RuitkGuitkx.compile("export MAX_ITEMS: int = 5\nrow_style := { \"a\": 1 }\ntheme = { \"b\": 2 }\n", "vals")
	_check_true(vals["ok"] and (vals["diagnostics"] as Array).is_empty(), "ES: value decls compile clean (got %s)" % str(vals.get("diagnostics", [])))
	var vgd: String = vals["gd"]
	_check_true(vgd.contains("static var MAX_ITEMS: int = 5") and vgd.contains("static var row_style := { \"a\": 1 }") and vgd.contains("static var theme = { \"b\": 2 }"), "ES: value decls preserve their source spelling (=, :=, : Type =) (got %s)" % vgd)
	_check_true(not vgd.contains("const MAX_ITEMS") and not vgd.contains("const row_style") and not vgd.contains("const theme"), "E-05: value exports never emit `const` (got %s)" % vgd)
	_check_true(vgd.contains("\"kind\": \"value\""), "ES: __RUI_DECLS records the value kind")

	# G-10: a mixed file with ONE wrapper decl + ONE plain decl is legal; only the wrapper decl warns.
	var mix := RuitkGuitkx.compile("component A() {\n\treturn ( <Label /> )\n}\nB() -> RuitkVNode {\n\treturn ( <Label /> )\n}\n", "mix")
	_check_true(mix["ok"], "G-10: wrapper + plain mix in one file compiles (got %s)" % str(mix.get("diagnostics", [])))
	var warns2320 := (mix["diagnostics"] as Array).filter(func(d): return str(d.get("code", "")) == "GUITKX2320")
	_check_true(warns2320.size() == 1, "G-10: exactly one 2320 warning fires, for the wrapper decl only (got %s)" % str(mix["diagnostics"]))

	# A module's members stay WRAPPER-ONLY (E-01 has no plain `module` equivalent) -- a plain decl
	# inside a module body is invalid content (2105), not misread as a nested module (2504).
	var modplain := RuitkGuitkx.compile("module M {\n\tfoo() { }\n}\n", "modplain")
	_check_true(not modplain["ok"] and _has_code(modplain, "GUITKX2105") and not _has_code(modplain, "GUITKX2504"), "ES: a plain decl inside a module body is 2105, not a false nested-module 2504 (got %s)" % str(modplain["diagnostics"]))

	# Runtime: a plain component isn't just shape-plausible GDScript -- load it and mount it for
	# real (mirrors _test_runtime's wrapper-component pattern).
	var rsrc := "Box2Plain(label: String = \"hi\") -> RuitkVNode {\n" + \
		"\tvar upper = label.to_upper()\n" + \
		"\tvar tag = \"[\" + upper + \"]\"\n" + \
		"\treturn (\n" + \
		"\t\t<VBoxContainer>\n" + \
		"\t\t\t<Label text={ tag } />\n" + \
		"\t\t\t<Button text=\"go\" />\n" + \
		"\t\t</VBoxContainer>\n" + \
		"\t)\n}\n"
	var rr := RuitkGuitkx.compile(rsrc, "Box2Plain")
	_check_true(rr["ok"], "ES runtime: plain component compiles (got %s)" % str(rr.get("diagnostics", [])))
	if rr["ok"]:
		var rgd: String = (rr["gd"] as String).replace("class_name Box2Plain\n", "")
		var rpath := "user://__guitkx_box2plain.gd"
		var rf := FileAccess.open(rpath, FileAccess.WRITE)
		rf.store_string(rgd)
		rf.close()
		var rscript = load(rpath)
		_check_true(rscript != null, "ES runtime: generated .gd loads as a script")
		var rc := Control.new()
		root.add_child(rc)
		var rapp := RuitkRoot.create(rc, V.fc(rscript.render, { "label": "world" }))
		var rlbl := _find_first(rc, "Label")
		_check_true(rlbl != null and rlbl.text == "[WORLD]", "ES runtime: plain component renders and its setup-derived value binds (got %s)" % str(rlbl.text if rlbl != null else "<none>"))
		rapp.unmount()
		rc.queue_free()

## ES-modules Layer 2 import surface (G-05/E-06..E-09): rename, namespace, default imports,
## deferred export lists, the new diagnostics (2323-2327, 2325, 2326), the alias-rewrite value
## lowering (probe-forced: `const x = preload(gd).static_var` is not a constant expression), and
## __RUI_DEFAULT emission. Cross-file fixtures live under the .gdignore'd __bh_tmp root.
func _test_es_modules_imports() -> void:
	const Resolve := preload("res://addons/reactive_ui_toolkit/guitkx/guitkx_resolve.gd")
	# Target: a plain-syntax file with values, a util, a hook, components, a default.
	var hud := "export panel_w: int = 320\n" + \
		"export accent := { \"modulate\": Color(1, 0, 0) }\n" + \
		"export fmt(x: int) -> String {\n\treturn \"[%d]\" % x\n}\n" + \
		"export use_tick(start: int) -> int {\n\treturn start\n}\n" + \
		"export Chip(label: String) -> RuitkVNode {\n\treturn ( <Label text={label}/> )\n}\n" + \
		"Panel(title: String) -> RuitkVNode {\n\treturn ( <Label text={title}/> )\n}\n" + \
		"export default Panel\n"
	var hud_path := _bh_writefile_at("res://tests/__bh_tmp/es/hud", hud)
	Codegen.compile_file(hud_path)
	var hud_gd := FileAccess.get_file_as_string("res://tests/__bh_tmp/es/hud.gd")
	_check_true(hud_gd.contains("const __RUI_DEFAULT := \"Panel\""), "E-07: __RUI_DEFAULT emitted (got header %s)" % hud_gd.substr(0, 200))
	_check_true(hud_gd.contains("static var panel_w: int = 320"), "E-05: typed value emits static var")
	# The default mark counts as exported (M1.3): Panel joins the export table.
	var htbl := Resolve.decl_table(hud_path)
	_check_true(str(htbl["default"]) == "Panel", "E-07: decl_table carries the default")
	_check_true(bool((htbl["decls"]["Panel"] as Dictionary)["export"]), "E-07: default-marked decl reads as exported")
	# exports_of/default_of agree; export_hash moves when the default flips.
	_check_true(Codegen.default_of(hud) == "Panel", "E-07: default_of reads the marker")
	var eh_with := Codegen.export_hash(Codegen.exports_of(hud), Codegen.default_of(hud))
	var hud_nodef := hud.replace("export default Panel\n", "")
	var eh_without := Codegen.export_hash(Codegen.exports_of(hud_nodef), Codegen.default_of(hud_nodef))
	_check_true(eh_with != eh_without, "E-07: a default flip moves export_hash (reverse-edge staleness)")

	# Importer exercising EVERY form at once: named value, renamed util, bare hook, named component,
	# namespace, default component.
	var app := "import { panel_w, fmt as fmt_x, use_tick, Chip as Badge } from \"./hud\"\n" + \
		"import * as Hud from \"./hud\"\n" + \
		"import Root from \"./hud\"\n\n" + \
		"export App() -> RuitkVNode {\n" + \
		"\tvar t = use_tick(panel_w)\n" + \
		"\tvar s = fmt_x(t) + Hud.fmt(2)\n" + \
		"\treturn (\n\t\t<VBoxContainer>\n\t\t\t<Badge label={s}/>\n\t\t\t<Root title=\"hi\"/>\n\t\t</VBoxContainer>\n\t)\n}\n"
	var app_path := _bh_writefile_at("res://tests/__bh_tmp/es/app", app)
	var ar := Codegen.compile_file(app_path)
	_check_true(bool(ar["ok"]), "G-05: all-forms importer compiles (%s)" % str(ar.get("diagnostics", [])))
	var app_gd := FileAccess.get_file_as_string("res://tests/__bh_tmp/es/app.gd")
	_check_true(app_gd.contains("const Hud = preload"), "E-06: namespace lowers to ONE whole-script const")
	_check_true(app_gd.contains(".panel_w") and app_gd.contains("__RUI_IMP_"), "E-05: named value ref rewritten onto the alias const")
	_check_true(app_gd.contains(".fmt("), "E-08: renamed util call addresses the REMOTE name")
	_check_true(not app_gd.contains("fmt_x("), "E-08: the local alias never survives into the .gd")
	# Chip is hud's RENDER component (the binding decl is a value, so the first exported component
	# emits `render` -- E-10), so the renamed tag lowers to the func-less V.comp(gd) form; the
	# local alias `Badge` itself must never leak into the output.
	_check_true(not app_gd.contains("Badge"), "E-08: renamed component's local alias never survives into the .gd")
	_check_true(app_gd.contains("\"Panel\""), "E-07: default component resolves AT COMPILE TIME to its decl func")
	_check_true(not app_gd.contains("const Root = preload"), "E-07/G-08: default COMPONENT import stays lazy (no eager preload)")
	_check_true(Codegen.gd_source_parses(app_gd), "G-05: the all-forms importer's .gd PARSES")

	# 2326: default-importing a file with no default.
	var nodef_path := _bh_writefile_at("res://tests/__bh_tmp/es/nodef", "export Only() -> RuitkVNode {\n\treturn ( <Label /> )\n}\n")
	Codegen.compile_file(nodef_path)
	var r2326 := RuitkGuitkx.compile("import X from \"./nodef\"\nexport App2() -> RuitkVNode {\n\treturn ( <X /> )\n}\n", "app2", [], {}, "res://tests/__bh_tmp/es/app2.guitkx", "res://")
	_check_true(_has_code(r2326, "GUITKX2326"), "E-07: no default export -> 2326 (got %s)" % str(r2326.get("diagnostics", [])))
	_check_true(str(_diag(r2326, "GUITKX2326").get("message", "")).contains("import { Only }"), "2326 suggests the named-import fix using the target's binding")

	# 2301/2302 anchor on the REMOTE name of a rename clause.
	var r2302 := RuitkGuitkx.compile("import { nope as ok } from \"./hud\"\nexport App3() -> RuitkVNode {\n\treturn ( <Label text={str(ok)}/> )\n}\n", "app3", [], {}, "res://tests/__bh_tmp/es/app3.guitkx", "res://")
	_check_true(_has_code(r2302, "GUITKX2302"), "E-08: unknown REMOTE in a rename -> 2302 (got %s)" % str(r2302.get("diagnostics", [])))

	# 2323/2324/2327: export-marker validation.
	var r2323 := RuitkGuitkx.compile("export { ghost }\nexport A9() -> RuitkVNode {\n\treturn ( <Label /> )\n}\n", "m")
	_check_true(_has_code(r2323, "GUITKX2323"), "E-09: listing a non-decl -> 2323 (got %s)" % str(r2323.get("diagnostics", [])))
	var r2324 := RuitkGuitkx.compile("export a_val := 1\nexport { a_val }\nA8() -> RuitkVNode {\n\treturn ( <Label /> )\n}\n", "m")
	_check_true(_has_code(r2324, "GUITKX2324"), "E-09: double export -> 2324 (got %s)" % str(r2324.get("diagnostics", [])))
	var r2327 := RuitkGuitkx.compile("A7() -> RuitkVNode {\n\treturn ( <Label /> )\n}\nexport default A7\nexport default A7\n", "m")
	_check_true(_has_code(r2327, "GUITKX2327"), "E-07: duplicate default -> 2327 (got %s)" % str(r2327.get("diagnostics", [])))
	# export { } list marks a decl exported for the BINDING (first-exported rule).
	var listed := "val_x := 1\nexport { val_x }\nA6() -> RuitkVNode {\n\treturn ( <Label /> )\n}\n"
	_check_true(Codegen._binding_name(listed) == "val_x", "E-09: a list-exported decl wins the first-exported binding (got %s)" % Codegen._binding_name(listed))

	# 2325: alias collisions (vs decl, vs another import).
	var r2325a := RuitkGuitkx.compile("import { fmt as Clash } from \"./hud\"\nexport Clash() -> RuitkVNode {\n\treturn ( <Label /> )\n}\n", "c1", [], {}, "res://tests/__bh_tmp/es/c1.guitkx", "res://")
	_check_true(_has_code(r2325a, "GUITKX2325"), "E-08: alias vs in-file decl -> 2325 (got %s)" % str(r2325a.get("diagnostics", [])))
	var r2325b := RuitkGuitkx.compile("import { fmt as Two } from \"./hud\"\nimport * as Two from \"./hud\"\nexport C2() -> RuitkVNode {\n\treturn ( <Label text={Two.fmt(1)}/> )\n}\n", "c2", [], {}, "res://tests/__bh_tmp/es/c2.guitkx", "res://")
	_check_true(_has_code(r2325b, "GUITKX2325"), "E-08: alias vs another import -> 2325 (got %s)" % str(r2325b.get("diagnostics", [])))

	# 2306: a namespace import is a VALUE edge -- a ns-import cycle errors with the chain.
	var cyc_a := _bh_writefile_at("res://tests/__bh_tmp/es/cyc_a", "import * as B from \"./cyc_b\"\nexport a_v := 1\nexport CA() -> RuitkVNode {\n\treturn ( <Label text={str(B.b_v)}/> )\n}\n")
	var _cyc_b := _bh_writefile_at("res://tests/__bh_tmp/es/cyc_b", "import * as A from \"./cyc_a\"\nexport b_v := 2\nexport CB() -> RuitkVNode {\n\treturn ( <Label text={str(A.a_v)}/> )\n}\n")
	var chain := Resolve.value_cycle(cyc_a, func(p: String) -> Array: return Codegen._value_import_edges(p, {}))
	_check_true(chain.contains("cyc_a.guitkx") and chain.contains("cyc_b.guitkx"), "E-06: namespace imports join the 2306 DFS (chain: %s)" % chain)

	# 2322 NEVER fires on this leg (family divergence (a)): `:=` and plain `=` values are always legal.
	var r2322 := RuitkGuitkx.compile("export v9 := Time.get_ticks_msec()\nA5() -> RuitkVNode {\n\treturn ( <Label /> )\n}\n", "m")
	_check_true(not _has_code(r2322, "GUITKX2322"), "divergence (a): 2322 is never emitted by the Godot leg")

	# G-10 matrix: a WRAPPER decl + NEW import forms in one file -- imports are orthogonal to the
	# window; the file compiles with 2320 on the wrapper only.
	var wnew := "import * as Hud from \"./hud\"
component WOld {
	return ( <Label text={Hud.fmt(3)}/> )
}
"
	var rwn := RuitkGuitkx.compile(wnew, "wold", [], {}, "res://tests/__bh_tmp/es/wold.guitkx", "res://")
	_check_true(bool(rwn["ok"]), "G-10 matrix: wrapper decl + namespace import compiles (got %s)" % str(rwn.get("diagnostics", [])))
	_check_true(_has_code(rwn, "GUITKX2320") and (rwn["gd"] as String).contains("const Hud = preload"), "G-10 matrix: warns on the wrapper only; the ns import lowers normally")

	# Audit find: a LOCAL declaration shadowing an alias-lowered import is a loud 2325, never a
	# silent mis-lowering (the text rewrite cannot do scope analysis -- `var speed = 10` over an
	# imported `speed` would re-point in-scope refs at the import).
	var shadow := "import { panel_w } from \"./hud\"
export Sh() -> RuitkVNode {
	var panel_w = 10
	return ( <Label text={str(panel_w)}/> )
}
"
	var rsh := RuitkGuitkx.compile(shadow, "sh", [], {}, "res://tests/__bh_tmp/es/sh.guitkx", "res://")
	_check_true(not bool(rsh["ok"]) and _has_code(rsh, "GUITKX2325"), "a local var shadowing an imported value is 2325, not silent corruption (got %s)" % str(rsh.get("diagnostics", [])))
	# A component PARAM shadowing an imported value hits the same gate (params destructure to var).
	var pshadow := "import { panel_w } from \"./hud\"
export Sp(panel_w: int = 1) -> RuitkVNode {
	return ( <Label text={str(panel_w)}/> )
}
"
	var rps := RuitkGuitkx.compile(pshadow, "sp", [], {}, "res://tests/__bh_tmp/es/sp.guitkx", "res://")
	_check_true(not bool(rps["ok"]) and _has_code(rps, "GUITKX2325"), "a param shadowing an imported value is 2325 too (got %s)" % str(rps.get("diagnostics", [])))

	# Runtime proof: mount the all-forms importer and check the rendered values flow end to end.
	var app_script = load("res://tests/__bh_tmp/es/app.gd")
	_check_true(app_script != null, "G-05 runtime: importer .gd loads")
	if app_script != null:
		var rc2 := Control.new()
		root.add_child(rc2)
		var rapp2 := RuitkRoot.create(rc2, V.fc(app_script.render, {}))
		var lbl2 := _find_first(rc2, "Label")
		_check_true(lbl2 != null and lbl2.text == "[320][2]", "G-05 runtime: value+util+hook+ns imports all resolve (got %s)" % str(lbl2.text if lbl2 != null else "<none>"))
		rapp2.unmount()
		rc2.queue_free()

## 0.11.1 field wave: ES COMBINED import forms (`import Def, { a, b as c } from` /
## `import Def, * as X from` -- ONE declaration carrying the default binding plus the named/
## namespace surface) + the unused-import (2304) self-count fix that shipped with them.
func _test_es_combined_imports() -> void:
	const Resolve := preload("res://addons/reactive_ui_toolkit/guitkx/guitkx_resolve.gd")
	var utils := "export something := 42\n" + \
		"export get_something() -> int {\n\treturn something\n}\n" + \
		"export use_pulse(x: int) -> int {\n\treturn x\n}\n" + \
		"is_something_even() -> bool {\n\treturn something % 2 == 0\n}\n" + \
		"export default is_something_even\n"
	var utils_path := _bh_writefile_at("res://tests/__bh_tmp/esc/utils", utils)
	Codegen.compile_file(utils_path)

	# Parse shape: ONE declaration carrying every part.
	var rows := RuitkGuitkx.scan_imports("import isEven, { get_something as fetch } from \"./utils\"\nimport D2, * as U from \"./utils\"\n")
	_check_true(rows.size() == 2, "combined: scan parses both lines (got %d)" % rows.size())
	if rows.size() == 2:
		var r0: Dictionary = rows[0]
		_check_true(str(r0["def"]) == "isEven", "combined: default binding parsed (got %s)" % str(r0["def"]))
		_check_true((r0["names"] as Array).size() == 1 and str(((r0["names"] as Array)[0] as Dictionary)["name"]) == "fetch" \
			and str(((r0["names"] as Array)[0] as Dictionary)["remote"]) == "get_something", "combined: named part rides the SAME declaration")
		var r1: Dictionary = rows[1]
		_check_true(str(r1["def"]) == "D2" and str(r1["ns"]) == "U", "combined: default + `* as` in one declaration")

	# Lowering: every part yields -- default util bridged, renamed util rewritten to its REMOTE,
	# namespace preloaded -- in one importer.
	var app := "import isEven, { get_something as fetch } from \"./utils\"\n" + \
		"import D2, * as U from \"./utils\"\n\n" + \
		"export AppC() -> RuitkVNode {\n" + \
		"\tvar a = fetch() + U.get_something()\n" + \
		"\tvar b = isEven() or D2()\n" + \
		"\treturn (\n\t\t<Label text={str(a) + str(b)}/>\n\t)\n}\n"
	var app_path := _bh_writefile_at("res://tests/__bh_tmp/esc/app", app)
	var ar := Codegen.compile_file(app_path)
	_check_true(bool(ar["ok"]), "combined: importer compiles (%s)" % str(ar.get("diagnostics", [])))
	_check_true(bool(ar.get("gd_parse_ok", false)), "combined: importer .gd + its preloaded target compile")
	var app_gd := FileAccess.get_file_as_string("res://tests/__bh_tmp/esc/app.gd")
	_check_true(app_gd.contains("const U = preload"), "combined: `* as` part still lowers to the whole-script const")
	_check_true(app_gd.contains(".get_something(") and not app_gd.contains("fetch("), "combined: named part rewrites to the REMOTE name")
	_check_true(app_gd.contains(".is_something_even("), "combined: default part bridges to the default decl")
	_check_true(Codegen.gd_source_parses(app_gd), "combined: importer .gd parses")
	# Both parts contribute the value edge (2306 graph).
	var edges: Array = Codegen._value_import_edges(app_path, {})
	_check_true(edges.has(utils_path), "combined: value edge reaches the target (got %s)" % str(edges))

	# Duplicate binding across the parts of ONE declaration: `import a, { b as a }` errors.
	var rdup := RuitkGuitkx.compile("import a, { get_something as a } from \"./utils\"\nexport AD() -> RuitkVNode {\n\treturn ( <Label text={str(a)}/> )\n}\n", "ad", [], {}, "res://tests/__bh_tmp/esc/ad.guitkx", "res://")
	_check_true(_has_code(rdup, "GUITKX2325") or _has_code(rdup, "GUITKX2303"), "combined: duplicate binding across parts is reported (got %s)" % str(rdup.get("diagnostics", [])))

	# Malformed comma tail: `import Def, from` is a 0300, not a silent half-parse.
	var rmal := RuitkGuitkx.compile("import isEven, from \"./utils\"\nexport AM() -> RuitkVNode {\n\treturn ( <Label /> )\n}\n", "am", [], {}, "res://tests/__bh_tmp/esc/am.guitkx", "res://")
	_check_true(_has_code(rmal, "GUITKX0300"), "combined: dangling comma -> 0300 (got %s)" % str(rmal.get("diagnostics", [])))

	# 2304 self-count fix: an unused `* as` / default / combined binding used to self-count on its
	# own import line and was NEVER flagged (the old skip only understood the braced form).
	var run_ns := RuitkGuitkx.compile("import * as UnusedNs from \"./utils\"\nexport A1() -> RuitkVNode {\n\treturn ( <Label /> )\n}\n", "a1", [], {}, "res://tests/__bh_tmp/esc/a1.guitkx", "res://")
	_check_true(_has_code(run_ns, "GUITKX2304"), "2304: unused `* as` import is flagged (got %s)" % str(run_ns.get("diagnostics", [])))
	var run_def := RuitkGuitkx.compile("import UnusedDef from \"./utils\"\nexport A2() -> RuitkVNode {\n\treturn ( <Label /> )\n}\n", "a2", [], {}, "res://tests/__bh_tmp/esc/a2.guitkx", "res://")
	_check_true(_has_code(run_def, "GUITKX2304"), "2304: unused default import is flagged (got %s)" % str(run_def.get("diagnostics", [])))
	var run_comb := RuitkGuitkx.compile("import usedDef, { get_something } from \"./utils\"\nexport A3() -> RuitkVNode {\n\treturn ( <Label text={str(usedDef())}/> )\n}\n", "a3", [], {}, "res://tests/__bh_tmp/esc/a3.guitkx", "res://")
	_check_true(_has_code(run_comb, "GUITKX2304"), "2304: unused named part of a combined import is flagged (got %s)" % str(run_comb.get("diagnostics", [])))
	_check_true(str(_diag(run_comb, "GUITKX2304").get("message", "")).contains("get_something"), "2304 names the unused part, not the used default")
	# Pin (Unity field find B): a BARE value reference (`text={something}`) counts as a use --
	# every identifier is a reference for the warning-tier scan.
	var run_used := RuitkGuitkx.compile("import { something } from \"./utils\"\nexport A4() -> RuitkVNode {\n\treturn ( <Label text={something}/> )\n}\n", "a4", [], {}, "res://tests/__bh_tmp/esc/a4.guitkx", "res://")
	_check_true(not _has_code(run_used, "GUITKX2304"), "2304: a bare value reference marks the import USED (got %s)" % str(run_used.get("diagnostics", [])))

	# Formatter: combined import lines survive byte-for-byte (imports are verbatim preamble) and
	# the result is idempotent -- the named part must never be dropped on reprint.
	const Fmt := preload("res://addons/reactive_ui_toolkit/guitkx/guitkx_formatter.gd")
	var fsrc := "import isEven, { get_something } from \"./utils\"\nimport D3, * as U2 from \"./utils\"\n\nexport FC() -> RuitkVNode {\n\treturn (\n\t\t<Label />\n\t)\n}\n"
	var fr: Dictionary = Fmt.format(fsrc, { "indentStyle": "tab" })
	_check_true((fr["text"] as String).contains("import isEven, { get_something } from \"./utils\""), "fmt: combined named part preserved (got %s)" % str(fr["text"]))
	_check_true((fr["text"] as String).contains("import D3, * as U2 from \"./utils\""), "fmt: combined star part preserved")
	_check_true(str(Fmt.format(str(fr["text"]), { "indentStyle": "tab" })["text"]) == str(fr["text"]), "fmt: idempotent over combined imports")

	# ── F5 field battery round 2 (Unity ref 9451bc9b) ─────────────────────────────────────────

	# SAME-NAME DEFAULT (Unity CS0121 analog): the default alias KEEPS the default-exported
	# member's name while the named part brings the target's surface into scope too. This dialect
	# has no container-using/bridge duality -- every member import (named, renamed, default)
	# lowers through ONE deduped `const __RUI_IMP_<hash> = preload(target)` plus a per-LOCAL
	# rewrite -- so the same name must resolve through exactly one path. Pin that: one preload
	# const, the same-name default rewritten onto the shared const, qualified `U.member` access
	# untouched (dot-guard), and the emitted .gd compiles.
	var same := "import is_something_even, { get_something } from \"./utils\"\n" + \
		"import D4, * as U3 from \"./utils\"\n\n" + \
		"export SameName() -> RuitkVNode {\n" + \
		"\tvar a = get_something() + U3.get_something()\n" + \
		"\tvar b = is_something_even() or D4()\n" + \
		"\treturn (\n\t\t<Label text={str(a) + str(b)}/>\n\t)\n}\n"
	var same_path := _bh_writefile_at("res://tests/__bh_tmp/esc/same_name", same)
	var sr := Codegen.compile_file(same_path)
	_check_true(bool(sr["ok"]), "same-name default: importer compiles (%s)" % str(sr.get("diagnostics", [])))
	# gd_parse_ok is compile_file's own throwaway reload -- it compiles the DEPENDENCY chain
	# (utils.gd included), unlike a bare re-parse that can be satisfied by the script cache.
	_check_true(bool(sr.get("gd_parse_ok", false)), "same-name default: importer + its preloaded target BOTH compile -- one resolution path only")
	var same_gd := FileAccess.get_file_as_string("res://tests/__bh_tmp/esc/same_name.gd")
	_check_true(same_gd.count("const __RUI_IMP_") == 1, "same-name default: ONE deduped preload const, never a duplicate (got %d)" % same_gd.count("const __RUI_IMP_"))
	_check_true(same_gd.contains(".is_something_even("), "same-name default: rewritten onto the shared const like a named import")
	_check_true(same_gd.contains("U3.get_something()"), "same-name default: qualified `U3.member` stays dot-guarded, never double-rewritten")
	_check_true(not same_gd.contains("U3.__RUI_IMP"), "same-name default: the ns qualifier itself is never rewritten")
	# The VALUE-binding class_name fix this repro surfaced: utils' binding is the value
	# `something` (its first export); `class_name something` + `static var something` made every
	# bare self-reference resolve to the CLASS TYPE, so utils.gd failed to compile the moment an
	# importer preloaded it. A value binding now emits NO class_name.
	var utils_gd := FileAccess.get_file_as_string("res://tests/__bh_tmp/esc/utils.gd")
	_check_true(not utils_gd.begins_with("class_name "), "value-binding target emits no class_name (got head %s)" % utils_gd.substr(0, 40))
	_check_true(utils_gd.contains("static var something := 42"), "the value member itself still emits")
	# Same LOCAL bound twice across the parts stays the explicit error (never a silent double).
	var same_dup := RuitkGuitkx.compile("import get_something, { get_something } from \"./utils\"\nexport SD() -> RuitkVNode {\n\treturn ( <Label text={str(get_something())}/> )\n}\n", "sd", [], {}, "res://tests/__bh_tmp/esc/sd.guitkx", "res://")
	_check_true(_has_code(same_dup, "GUITKX2325") or _has_code(same_dup, "GUITKX2303"), "same LOCAL from default + named parts is a loud collision (got %s)" % str(same_dup.get("diagnostics", [])))

	# UNUSED STAR/DEFAULT parts of a COMBINED import (Unity round-2 pin): only the named part is
	# used -> 2304 fires and names the DEFAULT binding; the used named part stays clean. And the
	# mirror: only the default used -> 2304 names the star alias.
	var run_def_part := RuitkGuitkx.compile("import unusedDef, { get_something } from \"./utils\"\nexport A5() -> RuitkVNode {\n\treturn ( <Label text={str(get_something())}/> )\n}\n", "a5", [], {}, "res://tests/__bh_tmp/esc/a5.guitkx", "res://")
	_check_true(_has_code(run_def_part, "GUITKX2304"), "2304: unused DEFAULT part of a combined import is flagged (got %s)" % str(run_def_part.get("diagnostics", [])))
	_check_true(str(_diag(run_def_part, "GUITKX2304").get("message", "")).contains("unusedDef"), "2304 names the unused default binding")
	var run_star_part := RuitkGuitkx.compile("import usedD, * as UnusedU from \"./utils\"\nexport A6() -> RuitkVNode {\n\treturn ( <Label text={str(usedD())}/> )\n}\n", "a6", [], {}, "res://tests/__bh_tmp/esc/a6.guitkx", "res://")
	_check_true(_has_code(run_star_part, "GUITKX2304"), "2304: unused STAR part of a combined import is flagged (got %s)" % str(run_star_part.get("diagnostics", [])))
	_check_true(str(_diag(run_star_part, "GUITKX2304").get("message", "")).contains("UnusedU"), "2304 names the unused star alias, not the used default")

	# 2304 SPANS (F5 round 3): every finding squiggles the WHOLE binding token -- the parser
	# tracks ns_at/def_at, so star/default/combined parts anchor on the alias, alias-length long.
	var span_src := "import unusedDef, { get_something } from \"./utils\"\nexport A7s() -> RuitkVNode {\n\treturn ( <Label text={str(get_something())}/> )\n}\n"
	var r_span := RuitkGuitkx.compile(span_src, "a7s", [], {}, "res://tests/__bh_tmp/esc/a7s.guitkx", "res://")
	var d_span := _diag(r_span, "GUITKX2304")
	_check_true(int(d_span.get("offset", -1)) == span_src.find("unusedDef") and int(d_span.get("length", 0)) == "unusedDef".length(), "2304 spans the whole default token (got off %s len %s)" % [str(d_span.get("offset")), str(d_span.get("length"))])
	var span_src2 := "import * as UnusedNs2 from \"./utils\"\nexport A8s() -> RuitkVNode {\n\treturn ( <Label /> )\n}\n"
	var r_span2 := RuitkGuitkx.compile(span_src2, "a8s", [], {}, "res://tests/__bh_tmp/esc/a8s.guitkx", "res://")
	var d_span2 := _diag(r_span2, "GUITKX2304")
	_check_true(int(d_span2.get("offset", -1)) == span_src2.find("UnusedNs2") and int(d_span2.get("length", 0)) == "UnusedNs2".length(), "2304 spans the whole star-alias token (got off %s len %s)" % [str(d_span2.get("offset")), str(d_span2.get("length"))])

	# ERROR-TIER PRECONDITION (F5 round 3, the Unity interpolation-hole analog): the reference
	# scan used GDScript lexis over the WHOLE file, so markup TEXT could derail it -- an
	# apostrophe in markup text ("don't") opened a phantom string that swallowed a following
	# {expr} hole on the same line, and a binding used ONLY there false-flagged unused. Under the
	# error tier that is a build breaker; the scan now counts every identifier outside import
	# statements, string/comment mentions included (over-approximating "used" harder is the safe
	# direction for an error-tier check).
	var gap := "import { get_something } from \"./utils\"\nexport GapC() -> RuitkVNode {\n\treturn (\n\t\t<VBoxContainer>don't <Label text={str(get_something())}/></VBoxContainer>\n\t)\n}\n"
	var r_gap := RuitkGuitkx.compile(gap, "gapc", [], {}, "res://tests/__bh_tmp/esc/gapc.guitkx", "res://")
	_check_true(not _has_code(r_gap, "GUITKX2304"), "a reference after an apostrophe in markup text still counts as a use (got %s)" % str(r_gap.get("diagnostics", [])))
	var gap2 := "import { get_something } from \"./utils\"\nexport GapD() -> RuitkVNode {\n\treturn (\n\t\t<VBoxContainer>Score #1 <Label text={str(get_something())}/></VBoxContainer>\n\t)\n}\n"
	var r_gap2 := RuitkGuitkx.compile(gap2, "gapd", [], {}, "res://tests/__bh_tmp/esc/gapd.guitkx", "res://")
	_check_true(not _has_code(r_gap2, "GUITKX2304"), "a reference after a literal `#` in markup text still counts as a use (got %s)" % str(r_gap2.get("diagnostics", [])))

## M4 re-verification (ES-modules leg): the two-pass write-all-then-check-all must survive the
## NEW eager symbols. `a_imp` namespace-imports `z_vals` -- lexicographic pass-1 order compiles
## the importer FIRST (its preload target .gd doesn't exist yet); pass 2 must heal it. A
## deliberately-broken value initializer must still be caught by the counted parse gate (gd_ok
## false -> guitkx_build exits 1). Fixtures live OUTSIDE the .gdignore'd __bh_tmp root (compile_all
## honors .gdignore), in their own __es_m4_tmp dir, cleaned up at the end.
func _test_es_modules_m4_ordering() -> void:
	var dir := "res://tests/__es_m4_tmp"
	DirAccess.make_dir_recursive_absolute(dir)
	_imp_write(dir + "/a_imp.guitkx", "import * as Z from \"./z_vals\"\nexport AImp() -> RuitkVNode {\n\treturn ( <Label text={str(Z.zw)}/> )\n}\n")
	_imp_write(dir + "/z_vals.guitkx", "export zw: int = 9\n")
	var r := Codegen.compile_all(dir)
	var by_path := {}
	for c in (r["compiled"] as Array):
		by_path[str(c["path"])] = c
	_check_true(by_path.has(dir + "/a_imp.guitkx") and bool((by_path[dir + "/a_imp.guitkx"] as Dictionary)["gd_ok"]), "M4.1: importer compiled BEFORE its value target still passes pass-2 (two-pass heal)")
	_check_true(by_path.has(dir + "/z_vals.guitkx") and bool((by_path[dir + "/z_vals.guitkx"] as Dictionary)["gd_ok"]), "M4.1: the value target itself parses")
	# Break the value initializer -> the emitted static var references an unknown identifier ->
	# pass 2 must reject it (this is exactly what makes guitkx_build's counted gate exit 1).
	_imp_write(dir + "/z_vals.guitkx", "export zw: int = nonexistent_fn_xyz()\n")
	var r2 := Codegen.compile_all(dir)
	# The rejected entry STAYS in `compiled` with gd_ok=false -- callers must still be told the .gd
	# was written (plugin.gd _efs.update_file; a cold clone heals only because of that). gd_ok is
	# the verdict, and plugin.gd reports it separately from both compiled and errors.
	var broken_ok := true
	var present := false
	for c2 in (r2["compiled"] as Array):
		if str(c2["path"]) == dir + "/z_vals.guitkx":
			present = true
			broken_ok = bool(c2["gd_ok"])
	_check_true(present, "M4.1: a rejected output is still reported so its .gd reaches the filesystem")
	_check_true(not broken_ok, "M4.1: a broken value initializer FAILS the counted parse gate (gd_ok=false)")
	# M4.2: flipping a value's export status recompiles importers in the SAME sweep
	# (export_hash + _reverse_edge_stale). Restore, sweep to settle, then flip.
	_imp_write(dir + "/z_vals.guitkx", "export zw: int = 9\n")
	Codegen.compile_all(dir)
	_imp_write(dir + "/z_vals.guitkx", "zw: int = 9\nexport zw2: int = 10\n")
	var r3 := Codegen.compile_all(dir)
	var recompiled := {}
	for c3 in (r3["compiled"] as Array):
		recompiled[str(c3["path"])] = true
	_check_true(recompiled.has(dir + "/a_imp.guitkx"), "M4.2: an export-table change forces the importer stale in the SAME sweep")
	_bh_rm_tree(dir)

## ES-modules formatter coverage (M1.6): plain decls of all four kinds + markers format
## canonically and IDEMPOTENTLY; wrapper files keep their shipped formatting byte-stable.
func _test_es_formatter() -> void:
	const Fmt := preload("res://addons/reactive_ui_toolkit/guitkx/guitkx_formatter.gd")
	var o := { "indentStyle": "tab" }
	# Plain component: header keeps the -> RuitkVNode annotation (it IS the classification).
	var pc := "export   Foo( a: int )   -> RuitkVNode {\n\tvar b = a\n\treturn (\n\t\t<Label text={str(b)}/>\n\t)\n}\n"
	var r1: Dictionary = Fmt.format(pc, o)
	_check_true(bool(r1["ok"]) and (r1["text"] as String).contains("export Foo(a: int) -> RuitkVNode {"), "ES fmt: plain component header canonical (got %s)" % str(r1["text"]))
	var r1b: Dictionary = Fmt.format(str(r1["text"]), o)
	_check_true(str(r1b["text"]) == str(r1["text"]), "ES fmt: plain component idempotent")
	# Plain hook + util.
	var ph := "use_x( a:int )->int {\n\treturn a\n}\n"
	var r2: Dictionary = Fmt.format(ph, o)
	_check_true((r2["text"] as String).begins_with("use_x(a:int) -> int {"), "ES fmt: plain hook header canonical (got %s)" % str(r2["text"]))
	_check_true(str(Fmt.format(str(r2["text"]), o)["text"]) == str(r2["text"]), "ES fmt: plain hook idempotent")
	# Value decls: one line, spelling preserved.
	var pv := "export   w   :=   { \"a\": 1 }\n"
	var r3: Dictionary = Fmt.format(pv, o)
	_check_true((r3["text"] as String).begins_with("export w := { \"a\": 1 }"), "ES fmt: value := canonical one-liner (got %s)" % str(r3["text"]))
	_check_true(str(Fmt.format(str(r3["text"]), o)["text"]) == str(r3["text"]), "ES fmt: value idempotent")
	# Markers.
	var ml := "export {  a ,  b }\na := 1\nb := 2\n"
	var r4: Dictionary = Fmt.format(ml, o)
	_check_true((r4["text"] as String).begins_with("export { a, b }"), "ES fmt: export list canonical (got %s)" % str(r4["text"]))
	var md := "export default   Foo\nFoo() -> RuitkVNode {\n\treturn ( <Label /> )\n}\n"
	var r5: Dictionary = Fmt.format(md, o)
	_check_true((r5["text"] as String).begins_with("export default Foo"), "ES fmt: export default canonical (got %s)" % str(r5["text"]))
	# Wrapper file byte-stability: an already-canonical wrapper component round-trips unchanged.
	var wf := "component Keep {\n\treturn (\n\t\t<Label />\n\t)\n}\n"
	var r6: Dictionary = Fmt.format(wf, o)
	_check_true(str(r6["text"]) == wf, "ES fmt: canonical wrapper file stays byte-identical (window stability)")
