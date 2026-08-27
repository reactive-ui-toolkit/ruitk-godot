extends SceneTree
## VISUAL gate for the RUITK Builder's canvas: one reference screenshot per LOD band, captured
## from the real renderer and compared pixel for pixel.
##
## This one needs a WINDOW. Headless Godot has the whole node tree but no renderer, so the
## structural half of the canvas is covered by `builder_canvas_test.gd` in CI and the pixels are
## covered here, run by hand:
##
##   capture (writes the references):
##     godot --path <project> --script res://tests/builder_canvas_capture.gd -- --write
##   check (fails on drift):
##     godot --path <project> --script res://tests/builder_canvas_capture.gd -- --check
##
## The references are committed. A layout change, a style change or a metric change that alters
## what the canvas looks like will fail the check -- which is the point: a canvas is a thing you
## look at, and "it still renders" is not the same claim as "it still looks right". Re-run with
## `--write` and eyeball the diff before committing the new ones.
##
## TOLERANCE. Font rasterisation is not bit-identical across platforms or driver versions, so the
## comparison allows a small per-channel delta and a small fraction of pixels over it. A layout
## shift moves thousands of pixels by a lot; an antialiasing difference moves a few by a little.

const Workspace = preload("res://addons/reactive_ui_toolkit_editor/builder/document/builder_workspace.gd")
const Service = preload("res://addons/reactive_ui_toolkit_editor/builder/canvas/builder_graph_service.gd")
const Host = preload("res://addons/reactive_ui_toolkit_editor/builder/canvas/builder_canvas_host.gd")
const Metrics = preload("res://addons/reactive_ui_toolkit_editor/builder/canvas/builder_canvas_metrics.gd")
const Graph = preload("res://addons/reactive_ui_toolkit_editor/builder/canvas/builder_graph.gd")

const REFERENCE_DIR := "res://tests/canvas_reference"
const FIXTURE_ROOT := "res://tests/__builder_capture_tmp/app"

## What each shot is of. The three LOD bands, plus a selected card, because selection is a state
## with its own look and a state with no reference is a state nobody checks.
const SHOTS := [
	{ "name": "lod0_pill", "zoom": 0.30, "selected": -1 },
	{ "name": "lod1_sections", "zoom": 0.80, "selected": -1 },
	{ "name": "lod2_full", "zoom": 1.30, "selected": -1 },
	{ "name": "lod1_selected", "zoom": 0.80, "selected": 1 },
]

## Per-channel delta a pixel may differ by before it counts as changed, and the fraction of the
## image allowed to be over it.
const CHANNEL_TOLERANCE := 0.04
const PIXEL_FRACTION_TOLERANCE := 0.002

var _failures := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var write := "--write" in args
	if not write and not ("--check" in args):
		print("usage: --write to capture references, --check to compare against them")
		quit(2)
		return
	if DisplayServer.get_name() == "headless":
		print("canvas capture needs a window -- run without --headless")
		quit(2)
		return

	var graph: Graph = _build_graph()
	var host := Host.new()
	host.size = Vector2(root.size)
	root.add_child(host)
	host.show_graph(graph)

	DirAccess.make_dir_recursive_absolute(REFERENCE_DIR)
	for shot in SHOTS:
		var s := shot as Dictionary
		host.select_card(int(s["selected"]))
		host.set_camera(Vector2(60.0, 60.0), float(s["zoom"]))
		# Two frames: one for the reconciler to commit, one for the renderer to draw it.
		await process_frame
		await process_frame
		await process_frame
		var image := root.get_texture().get_image()
		var path := REFERENCE_DIR.path_join(str(s["name"]) + ".png")
		if write:
			image.save_png(path)
			print("  wrote  %s  (%dx%d)" % [path, image.get_width(), image.get_height()])
		else:
			_compare(image, path, str(s["name"]))

	host.unmount()
	_rm_rf(FIXTURE_ROOT.get_base_dir())

	print("")
	if write:
		print("canvas capture: %d reference(s) written -- LOOK AT THEM before committing" % SHOTS.size())
		quit(0)
	elif _failures == 0:
		print("canvas capture: ALL MATCH (%d shots)" % SHOTS.size())
		quit(0)
	else:
		print("canvas capture: %d SHOT(S) DRIFTED -- re-run with --write and inspect the diff" % _failures)
		quit(1)


func _compare(image: Image, reference_path: String, name: String) -> void:
	if not FileAccess.file_exists(reference_path):
		_failures += 1
		print("  MISSING  %s -- no reference; run with --write" % name)
		return
	var reference := Image.load_from_file(reference_path)
	if reference == null:
		_failures += 1
		print("  UNREADABLE  %s" % name)
		return
	if reference.get_width() != image.get_width() or reference.get_height() != image.get_height():
		_failures += 1
		print("  SIZE  %s: reference is %dx%d, capture is %dx%d"
			% [name, reference.get_width(), reference.get_height(),
				image.get_width(), image.get_height()])
		return

	var changed := 0
	var worst := 0.0
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var a := image.get_pixel(x, y)
			var b := reference.get_pixel(x, y)
			var delta: float = maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), absf(a.b - b.b))
			worst = maxf(worst, delta)
			if delta > CHANNEL_TOLERANCE:
				changed += 1
	var total := image.get_width() * image.get_height()
	var fraction := float(changed) / float(total)
	if fraction > PIXEL_FRACTION_TOLERANCE:
		_failures += 1
		print("  DRIFT  %s: %.3f%% of pixels changed (worst channel delta %.3f)"
			% [name, fraction * 100.0, worst])
	else:
		print("  match  %s (%.4f%% differing, worst %.3f)" % [name, fraction * 100.0, worst])


## A tree with something of every kind on it, so a shot shows every treatment the canvas has.
func _build_graph() -> Graph:
	var ws := Workspace.new()
	ws.create_new(FIXTURE_ROOT.path_join("app.guitkx"),
		"""import { Row } from "./components/row/row"
import { primary } from "./app.style"
import { use_count } from "./app.hooks"

export App(level: int = 1, title: String = "Canvas") -> RuitkVNode {
	var s = useState(0)
	var n = use_count(level)
	var label = title + str(n)
	return (
		<VBoxContainer style={ primary }>
			<Label text={ label } />
			@if (level > 1) {
				return (
					<Row text="deep" />
				)
			}
			@for (i in range(level)) {
				return (
					<Row key={ i } text={ str(i) } />
				)
			}
		</VBoxContainer>
	)
}
""")
	ws.create_new(FIXTURE_ROOT.path_join("app.style.guitkx"),
		"export primary := {\n\t\"separation\": 6,\n\t\"bg_color\": Color(0.2, 0.2, 0.3),\n}\n")
	ws.create_new(FIXTURE_ROOT.path_join("app.hooks.guitkx"),
		"export use_count(level: int) -> int {\n\treturn level * 2\n}\n")
	ws.create_new(FIXTURE_ROOT.path_join("components/row/row.guitkx"),
		"export Row(text: String = \"\") -> RuitkVNode {\n\treturn ( <Label text={ text } /> )\n}\n")
	ws.create_new(FIXTURE_ROOT.path_join("util.guitkx"),
		"export clamp01(v: float) -> float {\n\treturn maxf(0.0, minf(1.0, v))\n}\n")
	return Service.project(ws.modules(), FIXTURE_ROOT.path_join("app.guitkx"))


func _rm_rf(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var d := DirAccess.open(path)
	if d == null:
		return
	for file in d.get_files():
		DirAccess.remove_absolute(path.path_join(file))
	for sub in d.get_directories():
		_rm_rf(path.path_join(sub))
	DirAccess.remove_absolute(path)
