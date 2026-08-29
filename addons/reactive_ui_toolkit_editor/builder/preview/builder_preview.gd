@tool
class_name RuitkBuilderPreview
extends RefCounted
## Turns the builder's unsaved buffers into a live, rendered component.
##
## THE WHOLE TREE IS MIRRORED to a scratch root and compiled there, through the real compiler,
## at real paths. That is the design decision the rest of this file follows from.
##
## The alternative -- compiling buffers in memory and faking every import -- means a second
## implementation of import resolution, and a preview that compiles differently from the build.
## A preview that compiles differently from the build is the one thing a preview must not do.
## Mirroring costs a few kilobytes of writes per edit and buys exact fidelity: the same
## `resolve_specifier`, the same `preload` lowering, the same `V.comp` lazy binding.
##
## The scratch root is doubly hidden: its name ends in `~`, which Godot's importer skips wholesale,
## and it holds a `.gdignore`, which keeps the COMPILER's own sweep out (the `~` does not -- see
## `_ensure_scratch_root`). It is cleared on teardown AND on open, so a crashed session cannot
## leave a shadow tree behind.
##
## WHAT IS DIRTY is what has changed since it was last BUILT -- not what is unsaved. Those differ
## in a case that bites immediately: type a label, then type it back, and the module is clean
## again. Keyed on dirtiness it leaves the batch, nothing recompiles, and the preview goes on
## showing the edit that was taken back.
##
## Cross-file references go through preload CONSTS, never global `class_name`s -- see
## `builder_module.gd` for why.

const Module = preload("res://addons/reactive_ui_toolkit_editor/builder/document/builder_module.gd")
const Paths = preload("res://addons/reactive_ui_toolkit_editor/builder/document/builder_paths.gd")
const Specifiers = preload("res://addons/reactive_ui_toolkit_editor/builder/document/builder_specifiers.gd")
const Compiler = preload("res://addons/reactive_ui_toolkit/guitkx/guitkx.gd")
# The preview writes SHADOWS of real modules, so it strips their `class_name` the same way the
# compiler's own parse gate does -- one definition of what that means, in the compiler.
const Codegen = preload("res://addons/reactive_ui_toolkit/guitkx/guitkx_codegen.gd")
const Config = preload("res://addons/reactive_ui_toolkit/guitkx/guitkx_config.gd")
const BuilderWorkspace = preload("res://addons/reactive_ui_toolkit_editor/builder/document/builder_workspace.gd")
# The runtime half, preloaded for the same reason as everything else here: a global `class_name`
# resolves through a cache another process can truncate.
const V = preload("res://addons/reactive_ui_toolkit/core/v.gd")
const RuitkRoot = preload("res://addons/reactive_ui_toolkit/core/reactive_root.gd")

## Where the mirrored tree lives. Under `res://` so relative and `~/` specifiers fold exactly as
## they do in the real tree; suffixed `~` so Godot never looks inside.
const SCRATCH_ROOT := "res://__ruitk_builder_preview__~"

## Emitted per module the round decided about: (path, ok, error).
signal compile_finished(path: String, ok: bool, error: String)

## THE ROUND IS OVER. Emitted once, after every module it decided.
##
## `compile_finished` fires INSIDE the build loop, once per module, and the window re-showed the
## preview pane on every one of them -- so a round that rebuilt a style plus three components
## produced four full remounts in a single frame, each tearing down a fiber tree and building it
## again, three of them for a script the pane does not render. It is a per-module DIAGNOSTIC feed;
## it was never an end-of-round hand-off, and using it as one meant the pane re-mounted for files
## it has nothing to do with.
signal round_finished(summary: Variant)

## What the pipeline did, for the diagnostics console. Nothing about a round is silent.
signal trace(message: String)


## Per-run outcome. Everything the round decided about, and why -- a module missing from a batch
## looks exactly like one that compiled and changed nothing, which is a difference no one can see
## from the outside.
class Summary extends RefCounted:
	## Every module the round considered, after the focus closure trimmed the batch.
	var considered := PackedStringArray()
	## Set when the COMPILER ITSELF could not run this round -- a tool state, not a source fault.
	## Reported once for the round rather than once per module, because it is one condition.
	var env_error := ""

	## Why each rebuilt module was rebuilt: "text changed" or "dependency rebuilt".
	var reasons := {}
	var rebuilt := PackedStringArray()
	## [{ path, error }] -- a module whose own compile failed.
	var failures: Array = []
	## [{ path, blocked_by }] -- a module skipped because something it imports failed. Building it
	## would only cascade the same error against a stale peer.
	var skipped: Array = []
	var focus_ok := false
	var focus_error := ""
	## The round ran out of its frame budget and stopped early. What it did not reach is still
	## dirty, so the next round picks it up -- the work is deferred, never dropped.
	var budget_exhausted := false

	func is_clean() -> bool:
		return failures.is_empty() and skipped.is_empty()


## The tree being previewed. Set once; the preview reads its buffers and never its files.
var workspace: BuilderWorkspace = null

## How long a burst of typing settles before a compile round runs.
var debounce_msec := 300

## How long one round may spend compiling. A round that runs out stops cleanly and leaves the
## rest dirty; it does not half-build a module or drop one.
var budget_msec := 50

## Injectable clock, in milliseconds -- the debounce and the budget are the only things that read
## it, and a test that cannot control it can only assert timing by sleeping.
var now_msec := Callable()

# The buffer each module was last COMPILED from. Absent means "never built".
var _compiled_from := {}

## The last error reported per module, by path key.
var _last_error := {}
# The buffer each module was last MIRRORED from, so an unchanged module is not rewritten.
var _mirrored := {}
# The generated script each module was last successfully built into.
var _built := {}

var _pending := false
var _pending_since := 0

var _root: RuitkRoot = null

## The reason the mounted component's render failed, or "".
var _mount_error := ""
var _mounted_path := ""


func _now() -> int:
	return int(now_msec.call()) if now_msec.is_valid() else Time.get_ticks_msec()


# ── Debounce ─────────────────────────────────────────────────────────────────────────

## Notes that something changed. Repeated calls push the deadline out, so a burst of typing
## settles into one round instead of one round per keystroke.
func request_refresh() -> void:
	_pending = true
	_pending_since = _now()


## Whether the pending request has settled. Reading this does not consume it -- `compile_dirty`
## does, so a caller that checks and then decides not to run has not lost the request.
func is_due() -> bool:
	return _pending and (_now() - _pending_since) >= debounce_msec


func has_pending() -> bool:
	return _pending


# ── Paths ────────────────────────────────────────────────────────────────────────────

## Where a module is mirrored. The path under `res://` is preserved verbatim, so `./x` and `../x`
## resolve between mirrored modules exactly as they do between the real ones.
static func scratch_path_of(module_path: String) -> String:
	var rel := Paths.canon(module_path).trim_prefix("res://")
	return SCRATCH_ROOT if rel.is_empty() else SCRATCH_ROOT.path_join(rel)


## The `~/` root a mirrored module resolves against: the real root, mirrored. Passed to the
## compiler explicitly rather than discovered, because discovering it would find the config file
## of whatever real tree the scratch copy happens to sit under -- which is none of them.
static func scratch_root_for(module_path: String) -> String:
	return scratch_path_of(Config.root_for(Paths.canon(module_path)))


# ── The round ────────────────────────────────────────────────────────────────────────

## Compiles everything the focus needs, dependencies before dependents, and returns what it did.
## null when there was nothing to do.
func compile_dirty(focus_path: String) -> Summary:
	if workspace == null:
		return null
	_pending = false
	var focus := Paths.canon(focus_path)

	var by_path := {}
	for module in workspace.modules():
		var p := module.file_path()
		if not p.is_empty():
			by_path[Paths.key(p)] = module

	var dirty := {}
	for key in by_path:
		var module: Module = by_path[key]
		if not _compiled_from.has(key) or str(_compiled_from[key]) != module.buffer_text:
			dirty[key] = module
	if dirty.is_empty():
		return null

	# Before a single file is mirrored: the root has to be invisible to the compiler sweep from
	# the moment it holds anything at all.
	_ensure_scratch_root()

	# A module whose DEPENDENCY changed has to be rebuilt too, and its own text has not moved, so
	# it is never a candidate on its own. Editing a style otherwise rebuilds the style and nothing
	# that uses it, and the preview goes on rendering the component against the old one.
	_add_importers_of(dirty, by_path)
	_restrict_to_focus_closure(dirty, by_path, focus)

	var summary := Summary.new()
	for key in dirty:
		summary.considered.append((dirty[key] as Module).file_path())

	_sync_scratch(by_path)

	var deps := {}
	var order := _order_by_imports(dirty, deps)
	var failed_roots := {}
	var rebuilt := {}
	var started := _now()

	for key in order:
		if _now() - started > budget_msec and not rebuilt.is_empty():
			# Out of budget. What was not reached stays dirty, because `_compiled_from` was never
			# updated for it -- so the next round starts exactly where this one stopped.
			summary.budget_exhausted = true
			trace.emit("preview: budget exhausted after %d module(s)" % rebuilt.size())
			break
		var module: Module = dirty[key]
		var path := module.file_path()

		var blocked_by := ""
		for dep in (deps.get(key, []) as Array):
			if failed_roots.has(dep):
				blocked_by = str(failed_roots[dep])
				break
		if not blocked_by.is_empty():
			failed_roots[key] = blocked_by
			summary.skipped.append({ "path": path, "blocked_by": blocked_by })
			compile_finished.emit(path, false, "skipped -- depends on failed %s" % blocked_by.get_file())
			continue

		# Nothing to do for a module whose own text has not moved and none of whose imports were
		# rebuilt this round. Walking in import order is what makes the second half of that test
		# valid: every dependency has been decided before its dependents are.
		var text_moved := not _compiled_from.has(key) or str(_compiled_from[key]) != module.buffer_text
		var dependency_rebuilt := false
		if not text_moved:
			for dep in (deps.get(key, []) as Array):
				if rebuilt.has(dep):
					dependency_rebuilt = true
					break
		if not text_moved and not dependency_rebuilt:
			continue

		summary.reasons[path] = "text changed" if text_moved else "dependency rebuilt"
		var result := _build(module)
		rebuilt[key] = true
		summary.rebuilt.append(path)
		if bool(result["ok"]):
			_compiled_from[key] = module.buffer_text
			_last_error.erase(key)
		elif bool(result.get("env_error", false)):
			# THE LAST GOOD BUILD KEEPS SERVING. `_compiled_from` is left alone so the next round
			# tries this module again, `_built` is left alone so the mount still has a script, and
			# the module is NOT a failed root -- nothing downstream of it is skipped for a
			# condition that has nothing to do with any of them.
			summary.env_error = str(result["error"])
		else:
			_compiled_from.erase(key)
			_built.erase(key)
			failed_roots[key] = path
			_last_error[key] = str(result["error"])
			summary.failures.append({ "path": path, "error": str(result["error"]) })
		compile_finished.emit(path, bool(result["ok"]), str(result.get("error", "")))
		if Paths.key(path) == Paths.key(focus):
			summary.focus_ok = bool(result["ok"])
			summary.focus_error = str(result.get("error", ""))

	if summary.rebuilt.is_empty() and summary.is_clean():
		# Nothing the focus can reach has moved. A module outside the closure may well still be
		# unbuilt -- it never needed building -- so the candidate set is not empty, but a round
		# that did nothing has to SAY it did nothing, or the caller re-renders on every tick.
		return null
	trace.emit("preview: %d built, %d failed, %d skipped, of %d considered"
		% [summary.rebuilt.size(), summary.failures.size(), summary.skipped.size(),
			summary.considered.size()])
	round_finished.emit(summary)
	return summary


## Compiles one module's buffer and materialises the generated script.
##
## The generated `.gd` is written to the mirror AND the cached script resource is re-parsed from
## it. Writing alone is not enough: `load` answers from the resource cache, so a second round
## hands back the FIRST round's script and the preview goes on rendering an edit ago -- and it
## sticks, because nothing later comes along to correct it.
## The error the last round reported for a module, or "".
##
## Kept because the pane had no way to ask: it inferred a failure from an empty stage, which is a
## different question and answers "yes" for a module nobody has compiled yet.
func last_error_for(path: String) -> String:
	var key := Paths.key(path)
	return str(_last_error[key]) if _last_error.has(key) else ""


func _build(module: Module) -> Dictionary:
	var path := module.file_path()
	var mirrored := scratch_path_of(path)
	var result := Compiler.compile(
		module.buffer_text, mirrored.get_file().get_basename(), [], {},
		mirrored, scratch_root_for(path))
	# A TRANSIENT ENVIRONMENT FAILURE IS NOT A SOURCE FAILURE. The compiler reports `env_error`
	# when it cannot read the vocabulary -- a fact about the TOOL, not about this file -- and its
	# own comment states the caller contract: keep the existing sibling .gd and the previous
	# sidecar. Treated as an ordinary failure it blamed every module in the tree for a condition
	# none of them caused, and discarded the last good build for all of them.
	if bool(result.get("env_error", false)):
		return { "ok": false, "env_error": true,
			"error": "the .guitkx compiler is not ready — the last good render is still showing" }
	if not bool(result.get("ok", false)):
		return { "ok": false, "error": _first_error(result) }

	var gd_path := mirrored.get_basename() + ".gd"
	var generated := Codegen.strip_class_name(str(result.get("gd", "")))
	if not _write(gd_path, generated):
		return { "ok": false, "error": "could not write the preview script for %s" % path.get_file() }

	var script: GDScript = load(gd_path)
	if script == null:
		return { "ok": false, "error": "could not load the preview script for %s" % path.get_file() }
	script.source_code = generated
	# `reload(false)`, NOT keep_state. Keeping state preserves the script's STATIC VARS -- which
	# is exactly where a value module's exported data lives, so an edited style would re-parse
	# and then hand back its previous contents. Nothing is mounted against these scripts at this
	# point; the mount happens after the round.
	var err := script.reload(false)
	if err != OK:
		return { "ok": false, "error": "the generated script for %s did not parse (%s)"
			% [path.get_file(), error_string(err)] }
	_built[Paths.key(path)] = script
	return { "ok": true, "error": "" }


static func _first_error(result: Dictionary) -> String:
	for d in (result.get("diagnostics", []) as Array):
		if int((d as Dictionary).get("severity", 0)) == 0:
			return "%s: %s" % [str(d.get("code", "")), str(d.get("message", ""))]
	return "compile failed"


## The script a module was last successfully built into, or null.
func built_script(path: String) -> GDScript:
	return _built.get(Paths.key(path), null)


# ── Batch shaping ────────────────────────────────────────────────────────────────────

## Pulls in every module that reaches something already in the batch. Searched over the WHOLE
## tree, not the batch: the modules being added are by definition the ones that did NOT change,
## so they are not in it yet.
func _add_importers_of(candidates: Dictionary, by_path: Dictionary) -> void:
	var grew := true
	while grew:
		grew = false
		for key in by_path:
			if candidates.has(key):
				continue
			for dep in _imports_of(by_path[key]):
				if candidates.has(dep):
					candidates[key] = by_path[key]
					grew = true
					break


## Drops every candidate the focus cannot reach. A module nobody in the preview refers to cannot
## change what the preview shows, and building it is pure cost -- paid on every settled keystroke.
func _restrict_to_focus_closure(candidates: Dictionary, by_path: Dictionary, focus: String) -> void:
	var focus_key := Paths.key(focus)
	if not by_path.has(focus_key):
		# No focus to reason from -- build whatever changed rather than nothing.
		return

	# Walked over the WHOLE TREE, not over the candidate set. What the focus can reach is a
	# property of the tree; walking the candidates instead drops a changed module whose only
	# path from the focus runs through a module that happens to be clean.
	var keep := { focus_key: true }
	var queue: Array[String] = [focus_key]

	# A module with no visual of its own is never what the preview is SHOWING -- a component that
	# imports it is. Clicking a style entry to edit it moves the focus onto that style, so a
	# forward-only walk drops the very component on screen and it stops updating.
	var focus_module: Module = by_path[focus_key]
	if focus_module.kind != Module.Kind.COMPONENT:
		for importer in _importers_of(focus_key, by_path):
			if not keep.has(importer):
				keep[importer] = true
				queue.append(importer)

	while not queue.is_empty():
		var key: String = queue.pop_front()
		if not by_path.has(key):
			continue
		for dep in _imports_of(by_path[key]):
			if by_path.has(dep) and not keep.has(dep):
				keep[dep] = true
				queue.append(dep)

	for key in candidates.keys():
		if not keep.has(key):
			candidates.erase(key)


## Every candidate that reaches `target` through its imports, directly or not.
func _importers_of(target: String, candidates: Dictionary) -> PackedStringArray:
	var found := PackedStringArray()
	var seen := { target: true }
	var grew := true
	while grew:
		grew = false
		for key in candidates:
			if seen.has(key):
				continue
			for dep in _imports_of(candidates[key]):
				if seen.has(dep):
					seen[key] = true
					found.append(key)
					grew = true
					break
	return found


## Topological order over the batch, imported peers first. `deps_out` keeps the in-batch
## dependency edges for the caller's skip-downstream-of-failure pass. A cycle falls back to
## insertion order -- the compiler diagnoses value cycles itself, and an ordering pass is not the
## place to refuse to build.
func _order_by_imports(batch: Dictionary, deps_out: Dictionary) -> PackedStringArray:
	var order := PackedStringArray()
	var state := {}
	for key in batch:
		_visit(key, batch, deps_out, state, order)
	return order


func _visit(key: String, batch: Dictionary, deps_out: Dictionary,
		state: Dictionary, order: PackedStringArray) -> void:
	if int(state.get(key, 0)) != 0:
		return
	state[key] = 1
	var mine: Array = []
	for dep in _imports_of(batch[key]):
		if not batch.has(dep):
			continue
		mine.append(dep)
		if int(state.get(dep, 0)) == 0:
			_visit(dep, batch, deps_out, state, order)
	deps_out[key] = mine
	state[key] = 2
	order.append(key)


## The in-tree modules a module imports, as index keys. ONE resolver for the whole builder: the
## compile order and the edges the canvas draws have to agree about what an import points at, or
## a module compiles before the thing it depends on.
func _imports_of(module: Module) -> PackedStringArray:
	var out := PackedStringArray()
	var from := module.file_path()
	if from.is_empty():
		return out
	for imp in Specifiers.imports_of(module.buffer_text):
		var mapped := Specifiers.map(from, str(imp["spec"]))
		if not mapped.is_empty():
			out.append(Paths.key(mapped))
	return out


# ── The mirror ───────────────────────────────────────────────────────────────────────

## Brings the scratch tree in line with the workspace: writes what changed, and removes what no
## module claims any more. A stale mirror is worse than none -- a deleted module left behind
## keeps satisfying the import that should have started failing.
func _sync_scratch(by_path: Dictionary) -> void:
	var wanted := {}
	for key in by_path:
		var module: Module = by_path[key]
		var mirrored := scratch_path_of(module.file_path())
		wanted[Paths.key(mirrored)] = true
		var known := _mirrored.get(key, {}) as Dictionary
		if str(known.get("text", "\uFFFF")) == module.buffer_text and FileAccess.file_exists(mirrored):
			continue
		if _write(mirrored, module.buffer_text):
			# The mirrored PATH is remembered, not rebuilt from the index key: the key is
			# case-folded, and a path rebuilt from it would miss the file it was meant to remove
			# on any filesystem that tells `Panel.guitkx` from `panel.guitkx`.
			_mirrored[key] = { "text": module.buffer_text, "path": mirrored }

	for key in _mirrored.keys():
		if by_path.has(key):
			continue
		var stale := str((_mirrored[key] as Dictionary).get("path", ""))
		_mirrored.erase(key)
		_compiled_from.erase(key)
		_built.erase(key)
		_remove_module_files(stale)

	# Anything under the scratch root the workspace does not claim: the remains of an earlier
	# session, or of a module renamed while this one was open.
	_prune_unclaimed(SCRATCH_ROOT, wanted)




static func _remove_module_files(mirrored: String) -> void:
	if mirrored.is_empty():
		return
	for path in [mirrored, mirrored.get_basename() + ".gd"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


static func _prune_unclaimed(dir: String, wanted: Dictionary) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for file in d.get_files():
		if file == ".gdignore":
			continue   # the marker that keeps the sweep out; see _ensure_scratch_root
		var path := dir.path_join(file)
		if not Paths.ends_with_ci(file, Paths.SUFFIX_PLAIN):
			# A generated `.gd` is claimed by its own source; anything else under the scratch
			# root was never ours to keep.
			if file.ends_with(".gd") and wanted.has(Paths.key(path.get_basename() + Paths.SUFFIX_PLAIN)):
				continue
			DirAccess.remove_absolute(path)
			continue
		if not wanted.has(Paths.key(path)):
			_remove_module_files(path)
	for sub in d.get_directories():
		_prune_unclaimed(dir.path_join(sub), wanted)
		# An empty mirror folder is a folder the tree no longer has.
		var child := DirAccess.open(dir.path_join(sub))
		if child != null and child.get_files().is_empty() and child.get_directories().is_empty():
			DirAccess.remove_absolute(dir.path_join(sub))


## The mirror must be INVISIBLE to the compiler sweep, and the trailing `~` is not enough.
##
## Godot skips a `~`-suffixed folder in the IMPORTER, so nothing under the mirror is imported or
## registered as a global class -- but `RuitkGuitkxCodegen.find_all` walks with DirAccess and
## skips only dot-directories and folders holding a `.gdignore`. Without the marker, the editor
## plugin's compile-on-scan sweep finds the mirror's `.guitkx`, compiles it, and every component
## in it collides with the real one it is a copy of (GUITKX2106) -- whose generated `.gd` the
## duplicate-binding remediation then DELETES. A preview is not allowed to touch the project.
static func _ensure_scratch_root() -> void:
	DirAccess.make_dir_recursive_absolute(SCRATCH_ROOT)
	var marker := SCRATCH_ROOT.path_join(".gdignore")
	if FileAccess.file_exists(marker):
		return
	var f := FileAccess.open(marker, FileAccess.WRITE)
	if f != null:
		f.close()


static func _write(path: String, text: String) -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.close()
	return true


## Whether a built script is a COMPONENT -- something with a `render` the reconciler can call.
##
## Asked of the script's own method list rather than `has_method`, which does not report a
## GDScript's statics on the script object itself.
static func has_render(script: GDScript) -> bool:
	if script == null:
		return false
	for method in script.get_script_method_list():
		if str((method as Dictionary).get("name", "")) == "render":
			return true
	return false


# ── Rendering ────────────────────────────────────────────────────────────────────────

## Mounts the focus component into `container`, replacing whatever was there.
##
## KEEPS THE LAST GOOD RENDER. A focus that did not build leaves the previous mount standing and
## reports false: a preview that blanks on every transient syntax error is a preview nobody can
## work against, because typing passes through broken states constantly.
func mount(container: Node, focus_path: String, props := {}) -> bool:
	if container == null:
		return false
	var script := built_script(focus_path)
	if script == null:
		return false
	# ONLY A COMPONENT HAS A `render`. A style, util or hook module compiles to a script of plain
	# statics, and mounting one asked the reconciler to call a function that is not there -- so
	# merely SELECTING a style companion, which is half of what a tree contains, logged an engine
	# error and left the stage on the last component. The pane shows the module's own note instead.
	if not has_render(script):
		return false
	unmount()
	# `V.comp` caches by path, so a Callable bound to the PREVIOUS build of a child survives a
	# rebuild that reloaded the script under it. Clearing before a mount costs one `load` per
	# child and removes a whole class of "the edit is not showing".
	_clear_scratch_comp_cache()
	# PROPS, not an empty dictionary. A component previewed with its declared defaults is
	# previewed with the least interesting values it ever takes -- an empty label, a list with no
	# items -- and the knobs above the stage exist precisely to change them.
	# ISOLATED: its own scheduler, its own frame budget. The stage renders USER CODE -- a component
	# mid-edit, whose effects the builder neither wrote nor can vet -- into the EDITOR's SceneTree,
	# the one that also pumps the canvas. On the shared lane a preview that will not settle spends
	# the budget the tool it lives in needs to stay usable, and the symptom is the whole editor
	# stuttering rather than one panel misbehaving.
	# BEHIND AN ERROR BOUNDARY. The stage renders USER CODE mid-edit -- a component whose render
	# may call `RuitkFail.render` through any of the runtime's own guards -- straight into the
	# editor's tree. Without a boundary the failure unwound to the ROOT, which for this mount means
	# the stage goes blank and the reason is nowhere: the runtime's documented substitute for
	# try/catch existed and this, of all mounts, was not using it.
	_mount_error = ""
	_root = RuitkRoot.create_isolated(container, V.error_boundary({
		"fallback": V.Label({ "text": "this component's render failed — see the console" }),
		"on_error": func(reason): _on_mount_failed(str(reason)),
	}, [V.fc(Callable(script, "render"), props)]))
	_mounted_path = Paths.canon(focus_path)
	return _root != null


## A render failure inside the mounted component, or "".
##
## Reported rather than swallowed: the boundary keeps the stage alive, and the pane needs the
## reason to say why what is on it is a fallback rather than the component.
func mount_error() -> String:
	return _mount_error


func _on_mount_failed(reason: String) -> void:
	_mount_error = reason
	compile_finished.emit(_mounted_path, false, reason)
	trace.emit("preview: the mounted component's render failed -- %s" % reason)


## The reconciler's committed fiber tree for the current mount, or null.
##
## For the state panel: the values a component's hooks are HOLDING are only knowable from the
## running tree, and they are the thing a preview is most often opened to check.
func mounted_root_fiber():
	if _root == null:
		return null
	var reconciler = _root.get("_reconciler")
	return reconciler.get("_root_current") if reconciler != null else null


func mounted_path() -> String:
	return _mounted_path


func is_mounted() -> bool:
	return _root != null


func unmount() -> void:
	_mount_error = ""
	if _root != null:
		_root.unmount()
		_root = null
	_mounted_path = ""


## Ends the session: unmounts, clears the mirror, and drops every cache entry that pointed into
## it. The gate asserts zero residue, because a scratch root that survives is a shadow tree the
## next session would compile against.
func teardown() -> void:
	unmount()
	_clear_scratch_comp_cache()
	_compiled_from.clear()
	_mirrored.clear()
	_built.clear()
	_pending = false
	clear_scratch()


## Removes the whole mirror. Called on teardown AND before the first round of a session, so a
## crashed editor cannot leave one behind for the next.
static func clear_scratch() -> void:
	_rm_rf(SCRATCH_ROOT)


static func _rm_rf(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var d := DirAccess.open(path)
	if d == null:
		return
	# HIDDEN FILES INCLUDED, or the root survives its own teardown. `.gdignore` is a dot-file, and
	# on Linux DirAccess omits those by default while Windows lists them -- so a mirror that tore
	# down cleanly on one platform left a non-empty, undeletable directory on the other.
	d.include_hidden = true
	for file in d.get_files():
		DirAccess.remove_absolute(path.path_join(file))
	for sub in d.get_directories():
		_rm_rf(path.path_join(sub))
	DirAccess.remove_absolute(path)


## Drops the component-factory cache entries that point into the mirror. Namespaced by the
## scratch root, so a real component's cached factory is never disturbed.
static func _clear_scratch_comp_cache() -> void:
	for key in (V._comp_cache as Dictionary).keys():
		if str(key).begins_with(SCRATCH_ROOT):
			(V._comp_cache as Dictionary).erase(key)


