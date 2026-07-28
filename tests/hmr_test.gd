extends SceneTree
## Headless tests for runtime Fast Refresh (Phase H, core/hmr.gd + the reconciler's
## hmr_refresh). No debugger session needed: RUIHmr_.apply is called directly — exactly what the
## debugger-channel callback does — against components loaded from scratch files, mounted with
## the real reconciler. Run: godot --headless --path . --script res://tests/hmr_test.gd

var _failed := 0
var _passed := 0

const DIR := "res://tests/__hmr_tmp"
## preload, not the global name: a freshly-added class_name only enters the global cache on the
## next editor scan, and this suite must run on a cold checkout (CI clones) regardless.
const RUIHmr_ = preload("res://addons/reactive_ui_toolkit/core/hmr.gd")

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	_test_fast_refresh_preserves_state()
	_test_signature_change_resets_state()
	_test_module_change_rerenders_globally()
	_test_value_change_rerenders_no_reset()
	_test_error_isolation_and_recovery()
	_test_empty_read_held()
	_test_uncached_path_skipped()
	_test_unmount_prunes_registry()
	_test_multi_root()
	_test_compiled_component_end_to_end()
	_test_mixed_batch_component_and_module()
	_test_rapid_resave_idempotent()
	_test_reload_with_pending_update()
	_test_new_component_hot_link()
	_test_injector_dedupe()
	_cleanup_dir()
	if _failed > 0:
		print("[hmr_test] FAILED (%d passed, %d failed)" % [_passed, _failed])
		quit(1)
	else:
		print("[hmr_test] ALL PASSED (%d checks)" % _passed)
		quit(0)

## M5 / A6c: the binding injector must SKIP a name the source already `const`-declares (mixed/import
## files emit their own `const Name = preload(...)` for value imports; a second one = reload crash).
func _test_injector_dedupe() -> void:
	var bindings := { "HudHooks": "res://x/hud_hooks.gd" }
	var with_const := "class_name Panel\nextends RefCounted\nconst HudHooks = preload(\"res://x/hud_hooks.gd\")\nstatic func render():\n\tHudHooks.use()\n"
	_check_true(RUIHmr_._inject_unregistered_bindings(with_const, bindings) == with_const, "injector: skips a name already const-declared (no duplicate const)")
	var bare := "class_name Panel\nextends RefCounted\nstatic func render():\n\tHudHooks.use()\n"
	_check_true(RUIHmr_._inject_unregistered_bindings(bare, bindings).contains("const HudHooks = preload("), "injector: still injects a used, non-global, non-const name")
	# _has_const_decl is line-anchored: a mid-line mention of the name is NOT a declaration.
	_check_true(RUIHmr_._has_const_decl("const Foo = 1\n", "Foo"), "injector: _has_const_decl matches a real const line")
	_check_true(not RUIHmr_._has_const_decl("var x = Foo\n", "Foo"), "injector: _has_const_decl ignores a usage site")
	# M5.2 (ES-modules leg): generated files now hold `static var <name>` VALUE declarations --
	# splicing a `const X` above a same-named `static var X` is a duplicate declaration =
	# reload ERR_PARSE_ERROR. The skip covers both spellings.
	_check_true(RUIHmr_._has_const_decl("static var Foo := 1\n", "Foo"), "injector: _has_const_decl matches a static var value decl")
	var with_static := "class_name Panel\nextends RefCounted\nstatic var HudHooks := 1\nstatic func render():\n\treturn HudHooks\n"
	_check_true(RUIHmr_._inject_unregistered_bindings(with_static, bindings) == with_static, "M5.2: injector skips a name already static-var-declared (no duplicate)")
	# ES-modules: a mixed file whose only eager decl is a VALUE (or util) classifies as
	# module-like for refresh purposes -- its importers consumed it eagerly.
	var val_mixed := GDScript.new()
	val_mixed.source_code = "extends RefCounted\nconst __RUI_DECLS := { \"C\": { \"kind\": \"component\", \"sig\": \"\", \"export\": true }, \"w\": { \"kind\": \"value\", \"export\": true } }\nconst __RUI_KIND := \"mixed\"\nconst __RUI_HOOK_SIG := \"\"\nstatic var w := 1\nstatic func render(_p, _c): return null\n"
	val_mixed.reload()
	_check_true(RUIHmr_._is_module(val_mixed), "M5.1: a mixed file with a VALUE decl drives importer refresh (kind value)")
	var util_mixed := GDScript.new()
	util_mixed.source_code = "extends RefCounted\nconst __RUI_DECLS := { \"fmt\": { \"kind\": \"util\", \"export\": true } }\nconst __RUI_KIND := \"mixed\"\nconst __RUI_HOOK_SIG := \"\"\nstatic func fmt(): return 1\n"
	util_mixed.reload()
	_check_true(RUIHmr_._is_module(util_mixed), "M5.1: a util-only mixed file drives importer refresh (kind util)")

	# BH-15: a MIXED file (component + a hook/module) is classified _is_module==true (its value decl
	# drives a global/targeted refresh) YET its render component's __RUI_HOOK_SIG must still be compared
	# so a shape change resets state. apply() now checks the hook-sig INDEPENDENTLY of _is_module.
	var mixed := GDScript.new()
	mixed.source_code = "extends RefCounted\nconst __RUI_DECLS := { \"C\": { \"kind\": \"component\", \"sig\": \"useState\", \"export\": true }, \"use_h\": { \"kind\": \"hook\", \"export\": true } }\nconst __RUI_KIND := \"mixed\"\nconst __RUI_HOOK_SIG := \"useState\"\nstatic func render(_p, _c): return null\nstatic func use_h(): return 1\n"
	mixed.reload()
	_check_true(RUIHmr_._is_module(mixed), "BH-15: a mixed file with a hook is classified as module (drives refresh)")
	_check_true(RUIHmr_._hook_sig(mixed) == "useState", "BH-15: yet its render component's hook-sig is still readable for the reset compare")

# --------------------------------------------------------------------------------- harness ---

func _check_true(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[hmr_test] FAIL: ", msg)

func _write(path: String, src: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(src)
	f.close()

func _find_first(n: Node, klass: String) -> Node:
	if n.get_class() == klass:
		return n
	for c in n.get_children():
		var r := _find_first(c, klass)
		if r != null:
			return r
	return null

func _labels_text(n: Node) -> Array:
	var out: Array = []
	if n is Label:
		out.append((n as Label).text)
	for c in n.get_children():
		out.append_array(_labels_text(c))
	return out

## A component in the exact shape the guitkx compiler emits (statics only + the H4 const).
## `prefix` shows in the label, `sig` is the hook fingerprint, `hooks` the number of useState
## calls (all but the first are padding to change the shape).
func _counter_src(prefix: String, sig: String, hooks: int = 1) -> String:
	var pad := ""
	for i in range(hooks - 1):
		pad += "\tvar _pad%d = Hooks.useState(0)\n" % i
	return "extends RefCounted\n" \
		+ "const __RUI_HOOK_SIG := \"" + sig + "\"\n" \
		+ "static func render(props: Dictionary, children: Array) -> RUIVNode:\n" \
		+ "\tvar n = Hooks.useState(0)\n" + pad \
		+ "\treturn V.VBoxContainer({}, [\n" \
		+ "\t\tV.Label({ \"text\": \"" + prefix + "-\" + str(n[0]) }),\n" \
		+ "\t\tV.Button({ \"text\": \"+\", \"onPressed\": func(): n[1].call(n[0] + 1) }),\n" \
		+ "\t])\n"

func _sibling_src(prefix: String) -> String:
	return "extends RefCounted\n" \
		+ "static var renders := 0\n" \
		+ "static func render(props: Dictionary, children: Array) -> RUIVNode:\n" \
		+ "\trenders += 1\n" \
		+ "\treturn V.Label({ \"text\": \"" + prefix + "\" })\n"

func _parent_src() -> String:
	return "extends RefCounted\n" \
		+ "static func render(props: Dictionary, children: Array) -> RUIVNode:\n" \
		+ "\treturn V.VBoxContainer({}, [V.fc(props[\"a\"], {}), V.fc(props[\"b\"], {})])\n"

## Mount parent(a, b) under a fresh Control; returns { app, root, rec }.
func _mount(a: GDScript, b: GDScript) -> Dictionary:
	var parent_path := DIR + "/parent.gd"
	if not FileAccess.file_exists(parent_path):
		_write(parent_path, _parent_src())
	var parent_scr: GDScript = load(parent_path)
	var root := Control.new()
	get_root().add_child(root)
	var app = ReactiveRoot.create(root, V.fc(Callable(parent_scr, "render"),
		{ "a": Callable(a, "render"), "b": Callable(b, "render") }))
	return { "app": app, "root": root, "rec": app._reconciler }

func _click_plus(root: Node, rec) -> void:
	var btn := _find_first(root, "Button") as Button
	btn.pressed.emit()
	rec._tick()   # the setter schedules a deferred tick; headless drives it directly

func _teardown(m: Dictionary) -> void:
	m["app"].unmount()
	(m["root"] as Node).free()

# ----------------------------------------------------------------------------------- tests ---

func _test_fast_refresh_preserves_state() -> void:
	# THE Fast Refresh acceptance, headless: new code runs, hook state survives, siblings bail.
	var ap := DIR + "/counter_a.gd"
	var bp := DIR + "/sib_b.gd"
	_write(ap, _counter_src("v1", "useState"))
	_write(bp, _sibling_src("sib"))
	var a: GDScript = load(ap)
	var b: GDScript = load(bp)
	var m := _mount(a, b)
	_click_plus(m["root"], m["rec"])
	_click_plus(m["root"], m["rec"])
	_check_true("v1-2" in _labels_text(m["root"]), "clicked twice -> v1-2 (got %s)" % str(_labels_text(m["root"])))
	var sib_renders_before: int = b.renders
	_write(ap, _counter_src("v2", "useState"))
	var res: Dictionary = RUIHmr_.apply([ap])
	_check_true(int(res["reloaded"]) == 1 and int(res["reset"]) == 0 and (res["errors"] as Array).is_empty(),
		"apply: 1 reloaded, 0 reset, no errors (got %s)" % str(res))
	_check_true(int(res["refreshed"]) == 1, "exactly ONE fiber refreshed (targeted), got %s" % str(res))
	_check_true("v2-2" in _labels_text(m["root"]),
		"NEW code + OLD state: v2-2 (got %s)" % str(_labels_text(m["root"])))
	_check_true(int(b.renders) == sib_renders_before,
		"untouched sibling did not re-render (bailout intact): %d == %d" % [int(b.renders), sib_renders_before])
	# state must keep working AFTER the swap: the new render's fresh onPressed increments from 2
	_click_plus(m["root"], m["rec"])
	_check_true("v2-3" in _labels_text(m["root"]), "post-swap click -> v2-3 (got %s)" % str(_labels_text(m["root"])))
	_teardown(m)

func _test_signature_change_resets_state() -> void:
	var ap := DIR + "/counter_sig.gd"
	var bp := DIR + "/sib_sig.gd"
	_write(ap, _counter_src("s1", "useState"))
	_write(bp, _sibling_src("sib"))
	var a: GDScript = load(ap)
	var b: GDScript = load(bp)
	var m := _mount(a, b)
	_click_plus(m["root"], m["rec"])
	_check_true("s1-1" in _labels_text(m["root"]), "state at 1 before the shape change")
	_write(ap, _counter_src("s2", "useState|useState", 2))   # hook SHAPE changed
	var res: Dictionary = RUIHmr_.apply([ap])
	_check_true(int(res["reset"]) == 1, "signature change counted as a reset (got %s)" % str(res))
	_check_true("s2-0" in _labels_text(m["root"]),
		"changed hook shape -> deliberate state RESET: s2-0 (got %s)" % str(_labels_text(m["root"])))
	# and the fresh state is live: click increments from 0
	_click_plus(m["root"], m["rec"])
	_check_true("s2-1" in _labels_text(m["root"]), "fresh state works after reset (s2-1)")
	_teardown(m)

func _test_module_change_rerenders_globally() -> void:
	var ap := DIR + "/counter_g.gd"
	var bp := DIR + "/sib_g.gd"
	var mp := DIR + "/hooks_mod.gd"
	_write(ap, _counter_src("g1", "useState"))
	_write(bp, _sibling_src("sib"))
	_write(mp, "extends RefCounted\nstatic func use_thing() -> int:\n\treturn 1\n")
	var a: GDScript = load(ap)
	var b: GDScript = load(bp)
	var mod: GDScript = load(mp)   # must be CACHED for apply to consider it
	assert(mod != null)
	var m := _mount(a, b)
	var sib_before: int = b.renders
	_write(mp, "extends RefCounted\nstatic func use_thing() -> int:\n\treturn 2\n")
	var res: Dictionary = RUIHmr_.apply([mp])
	_check_true(bool(res["global"]), "module (no render func) classified as global (got %s)" % str(res))
	_check_true(int(b.renders) == sib_before + 1,
		"global refresh re-ran the sibling too: %d == %d+1" % [int(b.renders), sib_before])
	_check_true(int(res["refreshed"]) >= 3, "all function fibers marked (parent+a+b), got %s" % str(res))
	_teardown(m)

## ES-modules M5.3: a VALUE-decl file edit re-renders consumers through the same eager-dep path
## as a module change, and resets NO hook state (the value file has no hook signature of its own;
## the consumer's __RUI_HOOK_SIG is untouched).
func _test_value_change_rerenders_no_reset() -> void:
	var ap := DIR + "/counter_v.gd"
	var bp := DIR + "/sib_v.gd"
	var vp := DIR + "/vals_v.gd"
	_write(ap, _counter_src("v1", "useState"))
	_write(bp, _sibling_src("sib-v"))
	# The ES-modules value-file shape: __RUI_DECLS with a value kind + a static var.
	_write(vp, "extends RefCounted
const __RUI_DECLS := { \"w\": { \"kind\": \"value\", \"export\": true } }
const __RUI_KIND := \"mixed\"
const __RUI_HOOK_SIG := \"\"
static var w := 1
")
	var a: GDScript = load(ap)
	var b: GDScript = load(bp)
	var vv: GDScript = load(vp)
	assert(vv != null)
	var m := _mount(a, b)
	_click_plus(m["root"], m["rec"])   # state: counter at 1
	var sib_before: int = b.renders
	_write(vp, "extends RefCounted
const __RUI_DECLS := { \"w\": { \"kind\": \"value\", \"export\": true } }
const __RUI_KIND := \"mixed\"
const __RUI_HOOK_SIG := \"\"
static var w := 2
")
	var res: Dictionary = RUIHmr_.apply([vp])
	_check_true(bool(res["global"]), "value file with no known importers falls back to global refresh (got %s)" % str(res))
	_check_true(int(res["reset"]) == 0, "a value edit resets NO hook state (got %s)" % str(res))
	_check_true(int(b.renders) == sib_before + 1, "consumers re-rendered (%d == %d+1)" % [int(b.renders), sib_before])
	_check_true("v1-1" in _labels_text(m["root"]), "counter STATE survived the value edit (got %s)" % str(_labels_text(m["root"])))
	_teardown(m)

func _test_error_isolation_and_recovery() -> void:
	var ap := DIR + "/counter_e.gd"
	var bp := DIR + "/sib_e.gd"
	_write(ap, _counter_src("e1", "useState"))
	_write(bp, _sibling_src("sib-e1"))
	var a: GDScript = load(ap)
	var b: GDScript = load(bp)
	var m := _mount(a, b)
	_click_plus(m["root"], m["rec"])
	# batch: A becomes UNPARSEABLE, B legitimately changes -- B must still swap, A reports
	_write(ap, "extends RefCounted\nstatic func render(:::broken:::\n")
	_write(bp, _sibling_src("sib-e2"))
	var res: Dictionary = RUIHmr_.apply([ap, bp])
	_check_true((res["errors"] as Array).size() == 1, "broken file reported (got %s)" % str(res["errors"]))
	_check_true(int(res["reloaded"]) == 1, "healthy file in the same batch still reloaded")
	_check_true("sib-e2" in _labels_text(m["root"]),
		"healthy sibling refreshed despite the broken batchmate (got %s)" % str(_labels_text(m["root"])))
	_check_true("e1-1" in _labels_text(m["root"]),
		"broken component keeps its last-good UI (got %s)" % str(_labels_text(m["root"])))
	# repair A -> next apply recovers it, state still intact
	_write(ap, _counter_src("e2", "useState"))
	var res2: Dictionary = RUIHmr_.apply([ap])
	_check_true((res2["errors"] as Array).is_empty() and int(res2["reloaded"]) == 1, "repaired file reloads clean")
	_check_true("e2-1" in _labels_text(m["root"]),
		"recovery: new code + state preserved across the broken interlude (got %s)" % str(_labels_text(m["root"])))
	_teardown(m)

func _test_empty_read_held() -> void:
	var ap := DIR + "/counter_h.gd"
	_write(ap, _counter_src("h1", "useState"))
	var a: GDScript = load(ap)
	var m := _mount(a, a)
	var f := FileAccess.open(ap, FileAccess.WRITE)   # truncate = the editor mid-write race
	f.close()
	var res: Dictionary = RUIHmr_.apply([ap])
	_check_true((res["errors"] as Array).size() == 1 and int(res["reloaded"]) == 0,
		"empty read held, old code kept (got %s)" % str(res))
	_check_true("h1-0" in _labels_text(m["root"]), "UI untouched on the empty read")
	_teardown(m)

func _test_uncached_path_skipped() -> void:
	var p := DIR + "/never_loaded.gd"
	_write(p, _sibling_src("x"))
	var res: Dictionary = RUIHmr_.apply([p])
	_check_true(int(res["reloaded"]) == 0 and (res["errors"] as Array).is_empty(),
		"a never-loaded script is skipped without error (got %s)" % str(res))

func _test_unmount_prunes_registry() -> void:
	var ap := DIR + "/counter_u.gd"
	_write(ap, _counter_src("u1", "useState"))
	var a: GDScript = load(ap)
	var m := _mount(a, a)
	_teardown(m)
	_write(ap, _counter_src("u2", "useState"))
	var res: Dictionary = RUIHmr_.apply([ap])
	_check_true(int(res["refreshed"]) == 0, "unmounted root is pruned: nothing refreshed (got %s)" % str(res))

func _test_multi_root() -> void:
	var ap := DIR + "/counter_m.gd"
	var bp := DIR + "/sib_m.gd"
	_write(ap, _counter_src("m1", "useState"))
	_write(bp, _sibling_src("sib"))
	var a: GDScript = load(ap)
	var b: GDScript = load(bp)
	var m1 := _mount(a, b)
	var m2 := _mount(a, b)
	_click_plus(m1["root"], m1["rec"])   # roots hold independent state: 1 vs 0
	_write(ap, _counter_src("m2", "useState"))
	var res: Dictionary = RUIHmr_.apply([ap])
	_check_true(int(res["refreshed"]) == 2, "both live roots refreshed (got %s)" % str(res))
	_check_true("m2-1" in _labels_text(m1["root"]), "root 1: new code, ITS state (m2-1)")
	_check_true("m2-0" in _labels_text(m2["root"]), "root 2: new code, ITS state (m2-0)")
	_teardown(m1)
	_teardown(m2)

## REAL compiler output end to end (ties H4 to H2/H3): compile a .guitkx, mount the generated
## script, bump state, recompile with the same hook shape (state preserved), then with an added
## hook (deliberate reset via the emitted __RUI_HOOK_SIG).
func _test_compiled_component_end_to_end() -> void:
	var Compiler = preload("res://addons/reactive_ui_toolkit/guitkx/guitkx.gd")
	var gp := DIR + "/e2e.gd"
	var r1: Dictionary = Compiler.compile(_e2e_guitkx("e1", false), "e2e")
	_check_true(bool(r1["ok"]), "e2e v1 compiles: " + str(r1.get("diagnostics")))
	_write(gp, _strip_class_name(str(r1["gd"])))
	var scr: GDScript = load(gp)
	var m := _mount(scr, scr)
	_click_plus(m["root"], m["rec"])
	_check_true("e1-1" in _labels_text(m["root"]), "compiled component mounted + clicked to e1-1 (got %s)" % str(_labels_text(m["root"])))
	# same hook shape, new text -> Fast Refresh preserves state
	var r2: Dictionary = Compiler.compile(_e2e_guitkx("e2", false), "e2e")
	_write(gp, _strip_class_name(str(r2["gd"])))
	var res2: Dictionary = RUIHmr_.apply([gp])
	_check_true(int(res2["reset"]) == 0 and "e2-1" in _labels_text(m["root"]),
		"recompiled (same shape): new code + preserved state e2-1 (got %s / %s)" % [str(res2), str(_labels_text(m["root"]))])
	# added hook -> changed __RUI_HOOK_SIG -> deliberate reset
	var r3: Dictionary = Compiler.compile(_e2e_guitkx("e3", true), "e2e")
	_write(gp, _strip_class_name(str(r3["gd"])))
	var res3: Dictionary = RUIHmr_.apply([gp])
	_check_true(int(res3["reset"]) == 1 and "e3-0" in _labels_text(m["root"]),
		"recompiled (added hook): deliberate state reset e3-0 (got %s / %s)" % [str(res3), str(_labels_text(m["root"]))])
	_teardown(m)

func _e2e_guitkx(prefix: String, extra_hook: bool) -> String:
	var pad := "\tvar extra = useState(9)\n" if extra_hook else ""
	return "component E2E() {\n" \
		+ "\tvar n = useState(0)\n" + pad \
		+ "\treturn (\n" \
		+ "\t\t<VBoxContainer>\n" \
		+ "\t\t\t<Label text={ \"" + prefix + "-\" + str(n[0]) } />\n" \
		+ "\t\t\t<Button text=\"+\" onPressed={ func(): n[1].call(n[0] + 1) } />\n" \
		+ "\t\t</VBoxContainer>\n" \
		+ "\t)\n}\n"

## Generated files start with `class_name E2E`; strip it so scratch scripts stay anonymous
## (no phantom global classes if an editor scan runs while the suite's tmp files exist).
func _strip_class_name(gd: String) -> String:
	if gd.begins_with("class_name "):
		return gd.substr(gd.find("\n") + 1)
	return gd

## One sweep can carry a component AND a module change (e.g. Foo.guitkx + Foo.hooks.guitkx
## saved together): global re-render fires, the component's new code shows, resets still apply.
func _test_mixed_batch_component_and_module() -> void:
	var ap := DIR + "/counter_x.gd"
	var bp := DIR + "/sib_x.gd"
	var mp := DIR + "/mod_x.gd"
	_write(ap, _counter_src("x1", "useState"))
	_write(bp, _sibling_src("sib"))
	_write(mp, "extends RefCounted\nstatic func use_x() -> int:\n\treturn 1\n")
	var a: GDScript = load(ap)
	var b: GDScript = load(bp)
	var mod: GDScript = load(mp)
	assert(mod != null)
	var m := _mount(a, b)
	_click_plus(m["root"], m["rec"])
	var sib_before: int = b.renders
	_write(ap, _counter_src("x2", "useState"))
	_write(mp, "extends RefCounted\nstatic func use_x() -> int:\n\treturn 2\n")
	var res: Dictionary = RUIHmr_.apply([ap, mp])
	_check_true(bool(res["global"]) and int(res["reloaded"]) == 2, "mixed batch: both reloaded, global set (got %s)" % str(res))
	_check_true("x2-1" in _labels_text(m["root"]), "component code swapped with state kept (x2-1)")
	_check_true(int(b.renders) == sib_before + 1, "module change re-ran the sibling in the same pass")
	_teardown(m)

## Rapid double-save of identical content: the second apply must skip (byte-identical) and
## touch nothing -- the editor's forced sweeps rewrite files without changing them.
func _test_rapid_resave_idempotent() -> void:
	var ap := DIR + "/counter_r.gd"
	_write(ap, _counter_src("r1", "useState"))
	var a: GDScript = load(ap)
	var m := _mount(a, a)
	_write(ap, _counter_src("r2", "useState"))
	var res1: Dictionary = RUIHmr_.apply([ap])
	var res2: Dictionary = RUIHmr_.apply([ap])   # same bytes again
	_check_true(int(res1["reloaded"]) == 1 and int(res2["reloaded"]) == 0,
		"identical re-apply skips (got %s then %s)" % [str(res1), str(res2)])
	_check_true("r2-0" in _labels_text(m["root"]), "UI stable across the idempotent re-apply")
	_teardown(m)

## A click can land right before the save: its deferred update is still pending when the
## reload arrives. The synchronous HMR flush must commit BOTH -- new code and the queued
## state change -- in one pass.
func _test_reload_with_pending_update() -> void:
	var ap := DIR + "/counter_p.gd"
	_write(ap, _counter_src("p1", "useState"))
	var a: GDScript = load(ap)
	var m := _mount(a, a)
	var btn := _find_first(m["root"], "Button") as Button
	btn.pressed.emit()   # deliberately NOT pumped -- the update is queued, not committed
	_write(ap, _counter_src("p2", "useState"))
	var res: Dictionary = RUIHmr_.apply([ap])
	_check_true(int(res["reloaded"]) == 1, "reload applied over a pending update")
	_check_true("p2-1" in _labels_text(m["root"]),
		"one atomic pass: new code AND the queued click both landed (got %s)" % str(_labels_text(m["root"])))
	_teardown(m)

## THE field case (2026-07-04): a BRAND-NEW component created while the game runs. Its global
## class_name is unregistered in this session -- Godot registers globals at LAUNCH, and a
## headless run never registers new ones at all, which simulates the frozen registry exactly --
## so the edited parent's reload fails by name and must be hot-LINKED via the injected preload
## const, with the session and its state intact.
func _test_new_component_hot_link() -> void:
	var ap := DIR + "/counter_n.gd"
	_write(ap, _counter_src("n1", "useState"))
	var a: GDScript = load(ap)
	var m := _mount(a, a)
	_click_plus(m["root"], m["rec"])
	var np := DIR + "/new_comp.gd"
	_write(np, "class_name HmrNewComp\nextends RefCounted\n## AUTO-GENERATED from new_comp.guitkx -- do not edit.\n\nstatic func render(props: Dictionary, children: Array) -> RUIVNode:\n\treturn V.Label({ \"text\": \"fresh!\" })\n")
	# the edited parent references the new component by GLOBAL NAME, exactly like generated code
	_write(ap, "extends RefCounted\nconst __RUI_HOOK_SIG := \"useState\"\nstatic func render(props: Dictionary, children: Array) -> RUIVNode:\n\tvar n = Hooks.useState(0)\n\treturn V.VBoxContainer({}, [\n\t\tV.Label({ \"text\": \"n2-\" + str(n[0]) }),\n\t\tV.Button({ \"text\": \"+\", \"onPressed\": func(): n[1].call(n[0] + 1) }),\n\t\tV.fc(HmrNewComp.render, {}),\n\t])\n")
	var res: Dictionary = RUIHmr_.apply([ap], { "HmrNewComp": np })
	_check_true(int(res.get("linked", 0)) == 1 and (res["errors"] as Array).is_empty(),
		"parent hot-LINKED the unregistered new component (got %s)" % str(res))
	var texts := _labels_text(m["root"])
	_check_true("n2-1" in texts, "parent swapped with state intact: n2-1 (got %s)" % str(texts))
	_check_true("fresh!" in texts, "the NEW component rendered live (got %s)" % str(texts))
	# and the linked parent keeps hot-reloading normally afterwards
	_write(ap, "extends RefCounted\nconst __RUI_HOOK_SIG := \"useState\"\nstatic func render(props: Dictionary, children: Array) -> RUIVNode:\n\tvar n = Hooks.useState(0)\n\treturn V.VBoxContainer({}, [\n\t\tV.Label({ \"text\": \"n3-\" + str(n[0]) }),\n\t\tV.Button({ \"text\": \"+\", \"onPressed\": func(): n[1].call(n[0] + 1) }),\n\t\tV.fc(HmrNewComp.render, {}),\n\t])\n")
	var res2: Dictionary = RUIHmr_.apply([ap], { "HmrNewComp": np })
	_check_true(int(res2.get("linked", 0)) == 1 and "n3-1" in _labels_text(m["root"]),
		"subsequent edits keep hot-linking (n3-1, got %s / %s)" % [str(res2), str(_labels_text(m["root"]))])
	_teardown(m)

func _cleanup_dir() -> void:
	var d := DirAccess.open(DIR)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if not d.current_is_dir():
			DirAccess.remove_absolute(DIR + "/" + name)
		name = d.get_next()
	d.list_dir_end()
	DirAccess.remove_absolute(DIR)
