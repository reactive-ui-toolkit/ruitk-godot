class_name RUIHmr
extends RefCounted
## Runtime Fast Refresh (Phase H): applies editor-pushed script reloads to the RUNNING game.
##
## The reactive_ui_toolkit EditorPlugin's watcher compiles `.guitkx` -> sibling `.gd` on save and pushes
## the changed paths into this game over the debugger channel (`rui_hmr:reload`, see
## editor/hmr_debugger.gd). We reload each script IN PLACE -- `source_code` + `reload(true)` on
## the SAME GDScript resource -- so method-reference Callables (`DemoBox.render`) keep their
## identity AND dispatch the new code (H0 spike + godot#85704). Fiber matching is Callable
## equality, so hook state survives for free; the only thing a reload cannot do by itself is
## defeat the reconciler's bailout cache -- RUIReconciler.hmr_refresh_all does that.
##
## Semantics (Unity RefreshRuntime parity):
##   - component script changed        -> targeted: only its fibers re-render (state preserved)
##   - hook/module script changed      -> global: every function fiber re-renders (any component
##                                        may call it -- Unity's TriggerGlobalReRender)
##   - hook SIGNATURE changed (__RUI_HOOK_SIG const, emitted by the compiler since 0.8.0)
##                                     -> that component's state is deliberately RESET
##   - reload failure / empty read     -> per-file isolation: keep old code, report, continue
##
## Inert outside editor runs: registration is gated on EngineDebugger.is_active(), and the
## editor only pushes when a debugger session is attached. Exported builds never see any of it.

static var _registered := false

## Called from RUIReconciler._init (the first mounted root arms HMR). Safe to call repeatedly.
static func ensure_registered() -> void:
	if _registered or not EngineDebugger.is_active():
		return
	_registered = true
	EngineDebugger.register_message_capture("rui_hmr", Callable(RUIHmr, "_on_message"))

## Debugger-channel entry. Messages arrive WITHOUT the "rui_hmr:" prefix. Returning true marks
## the message as handled. The whole reload+re-render pass runs synchronously INSIDE this
## callback: no frame boundary between the script swap and the commit, so live signal handlers
## minted by the old code can never fire in a half-swapped world.
static func _on_message(message: String, data: Array) -> bool:
	if message != "reload" and message != "rui_hmr:reload":   # engine versions differ on prefix stripping
		return false
	var t0 := Time.get_ticks_msec()
	var paths: Array = (data[0] as Array) if data.size() > 0 and data[0] is Array else []
	var bindings: Dictionary = (data[1] as Dictionary) if data.size() > 1 and data[1] is Dictionary else {}
	# M5: optional 3rd element = refresh_roots (component importers of changed hooks/modules). Older
	# editors send a 2-element message -> refresh_roots empty -> global-rerender fallback (wire-compat).
	var refresh_roots: Array = (data[2] as Array) if data.size() > 2 and data[2] is Array else []
	# Ack BEFORE doing anything: its presence in the editor Output proves delivery + capture,
	# so a crash inside apply() can never masquerade as "the message never arrived".
	EngineDebugger.send_message("rui_hmr:ack", [paths.size()])
	var res := apply(paths, bindings, refresh_roots)
	res["ms"] = Time.get_ticks_msec() - t0
	EngineDebugger.send_message("rui_hmr:status", [res])
	return true

## Reload the given generated .gd paths in place and refresh mounted trees. `bindings` is the
## project's class->generated-.gd map (from the sweep) used to hot-LINK brand-new components.
## Pure engine + reconciler work -- headless-testable without any debugger session.
## Returns { reloaded:int, reset:int, refreshed:int, linked:int, global:bool, errors:Array[String] }.
static func apply(paths: Array, bindings: Dictionary = {}, refresh_roots: Array = []) -> Dictionary:
	var changed: Array = []   # GDScript resources reloaded in place
	var resets: Array = []    # subset whose hook signature changed -> deliberate state reset
	var errors: Array = []
	var outcomes := {}        # path -> what happened (the editor prints this when nothing reloads)
	var linked := 0           # reloads that succeeded via new-component const injection
	var global_rerender := false
	# M5 / React Fast Refresh parity: when a changed hooks/module file has KNOWN component importers
	# (refresh_roots, computed by the editor over reverse import edges), re-render exactly those roots
	# instead of the whole world. An empty set (graph escaped, or a pre-import 2-element push) keeps
	# the global fallback -- today's behavior. Loaded lazily; only value-decl changes consult it.
	var targeted: Array = []
	for p in paths:
		var path := str(p)
		if not ResourceLoader.has_cached(path):
			outcomes[path] = "uncached"   # never loaded by this game -- next load() reads the new file
			continue
		var scr = load(path)
		if not (scr is GDScript):
			outcomes[path] = "not-a-script"
			continue
		var src := FileAccess.get_file_as_string(path)
		if src.is_empty():
			# The editor may still be mid-write; the next sweep pushes this path again.
			outcomes[path] = "empty-read"
			errors.append("%s: source read came back empty -- kept the old code" % path)
			continue
		if src == (scr as GDScript).source_code:
			outcomes[path] = "identical"   # e.g. a forced sweep re-wrote the same bytes
			continue
		var old_sig := _hook_sig(scr)
		# Inject BEFORE the first reload, never after a failure: we can already tell which
		# referenced classes this game cannot resolve (Godot registers global class_names at
		# LAUNCH, so a component created after F5 is unresolvable by name). A deliberately
		# failing first attempt would raise a script error that a debugger session BREAKS on,
		# freezing the whole HMR transaction mid-apply (field capture 2026-07-04). The injected
		# `const X = preload(path)` resolves exactly like the global would; the new component's
		# script loads fresh from disk; the session and its state survive.
		var patched := _inject_unregistered_bindings(src, bindings)
		(scr as GDScript).source_code = patched
		var err: int = (scr as GDScript).reload(true)
		if err != OK:
			(scr as GDScript).source_code = src   # leave the honest disk bytes in memory
			outcomes[path] = "failed err %d" % err
			errors.append("%s: in-place reload failed (err %d) -- fix the file and save again (or restart the run if it references classes from outside the guitkx pipeline)" % [path, err])
			continue
		if patched != src:
			linked += 1
			outcomes[path] = "linked"
		else:
			outcomes[path] = "reloaded"
		changed.append(scr)
		if _is_module(scr):
			# A value-decl (hooks/module) change: prefer targeting its component importers; fall back
			# to a global re-render only when none are known (graph escaped / pre-import push).
			if refresh_roots.is_empty():
				global_rerender = true
			else:
				for rr in refresh_roots:
					if ResourceLoader.has_cached(str(rr)):
						var rscr = load(str(rr))
						if rscr is GDScript and not targeted.has(rscr):
							targeted.append(rscr)
				if targeted.is_empty():
					global_rerender = true   # importers not loaded in this game -- safe fallback
		# A hook-SIGNATURE change resets the component's positional-hook state -- checked INDEPENDENTLY
		# of the module path, because a MIXED file is BOTH (its __RUI_HOOK_SIG is its render component's
		# fingerprint). Making these mutually exclusive skipped the reset for a mixed file whose
		# component shape changed, corrupting its state (BH-15). A pure module/hook file has an empty
		# __RUI_HOOK_SIG, so this never fires spuriously.
		if _hook_sig(scr) != old_sig:
			resets.append(scr)
	var refreshed := 0
	if not changed.is_empty():
		# `targeted` roots re-render alongside the directly-changed component scripts.
		refreshed = RUIReconciler.hmr_refresh_all(changed + targeted, resets, global_rerender)
	return {
		"reloaded": changed.size(), "reset": resets.size(), "refreshed": refreshed,
		"linked": linked, "global": global_rerender, "targeted": targeted.size(), "errors": errors, "outcomes": outcomes,
	}

## `const X = preload("<path>")` lines for every pushed binding that (a) this game does NOT
## know as a global class (launch-frozen map), (b) the source actually mentions, and (c) is not
## the file's OWN class (self-preload would cycle). Spliced right after the `extends` line.
## After the next restart the globals register and this returns the source untouched.
static func _inject_unregistered_bindings(src: String, bindings: Dictionary) -> String:
	if bindings.is_empty():
		return src
	var globals := {}
	for gc in ProjectSettings.get_global_class_list():
		globals[str(gc.get("class", ""))] = true
	var consts := ""
	for cls in bindings:
		var cname := str(cls)
		# Skip when: the game already knows the global class; the source never mentions it; it is the
		# file's OWN class (self-preload cycles); OR (M5/A6c) the source ALREADY const-declares it.
		# The last case is new in 0.10.0: mixed/import files emit their own `const Name = preload(...)`
		# for value imports, so injecting a second `const Name` = duplicate declaration = reload
		# ERR_PARSE_ERROR. `src.contains(cname)` above passes for that name, so a dedicated
		# line-anchored check is required (a bare `contains` would also match the usage site).
		if globals.has(cname) or not src.contains(cname) or src.contains("class_name " + cname) or _has_const_decl(src, cname):
			continue
		consts += "const %s = preload(\"%s\")\n" % [cname, str(bindings[cls])]
	if consts == "":
		return src
	# `const` must come AFTER the extends header (class_name/extends lead the file).
	var ext_at := -1
	if src.begins_with("extends "):
		ext_at = 0
	else:
		var nl := src.find("\nextends ")
		if nl != -1:
			ext_at = nl + 1
	if ext_at == -1:
		return consts + src   # headerless script -- consts may lead
	var line_end := src.find("\n", ext_at)
	if line_end == -1:
		return src
	return src.substr(0, line_end + 1) + consts + src.substr(line_end + 1)

## The compile-time hook-call fingerprint the guitkx compiler embeds (H4). Read as a script
## CONSTANT -- introspectable without instancing or static dispatch. Absent (hand-written
## component, pre-0.8 output) = "" on both sides of the compare -> never resets.
static func _hook_sig(scr: GDScript) -> String:
	return str(scr.get_script_constant_map().get("__RUI_HOOK_SIG", ""))

## [G-16 fix] A generated COMPONENT carries `const __RUI_KIND := "component"` (compiler since the
## G-16 fix) -- an unambiguous script-constant marker, read via get_script_constant_map() like
## __RUI_HOOK_SIG. Falls back to the OLD source-text heuristic (`contains("static func render(")`)
## only when the marker itself is absent (a hooks/module file, which doesn't emit it, or a
## component compiled before this fix) -- the fallback could misclassify a module whose OWN
## setup/comment text happens to contain that literal substring, but a freshly-compiled component
## can no longer be mistaken for a module (or vice versa) at all.
static func _is_module(scr: GDScript) -> bool:
	var kind := str((scr as GDScript).get_script_constant_map().get("__RUI_KIND", ""))
	if kind == "mixed":
		# 0.10.0 MIXED-DECL: a file holding several decls forces a global re-render only when it
		# declares a hook or module (an EAGER value that importers depend on); a component-only mixed
		# file re-renders through the normal component/hook-sig path (targeted, not global).
		return _has_value_decl(scr)
	if kind != "":
		return kind != "component"
	return not (scr as GDScript).source_code.contains("static func render(")

## True if a line-anchored `const <name>` OR `static var <name>` declaration exists in `src`
## (M5/A6c injector dedupe). The `static var` alternative is the ES-modules leg: generated files
## now hold `static var <name>` value declarations, and splicing a `const X` above a same-named
## `static var X` is a duplicate declaration = reload ERR_PARSE_ERROR (the A6c failure class).
static func _has_const_decl(src: String, name: String) -> bool:
	var re := RegEx.new()
	re.compile("(?m)^(const|static var)[ \\t]+" + name + "\\b")
	return re.search(src) != null

## True if this generated script's `__RUI_DECLS` table declares any EAGER decl -- hook, module,
## value, or util (M5 + ES-modules leg: values/utils are eagerly consumed by importers exactly
## like hooks/modules, so a change re-renders through the same refresh-root path). Absent table
## (single-decl component/hook/module file) -> false; those use the __RUI_KIND path above.
static func _has_value_decl(scr: GDScript) -> bool:
	var decls: Variant = (scr as GDScript).get_script_constant_map().get("__RUI_DECLS")
	if not (decls is Dictionary):
		return false
	for nm in (decls as Dictionary):
		var kind := str(((decls as Dictionary)[nm] as Dictionary).get("kind", ""))
		if kind == "hook" or kind == "module" or kind == "value" or kind == "util":
			return true
	return false
