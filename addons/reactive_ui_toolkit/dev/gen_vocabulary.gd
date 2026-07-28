extends SceneTree
## Projects vocabulary.json into guitkx_vocabulary.gen.gd as a `const DATA` Dictionary, so the
## compiler never depends on a runtime FileAccess read: during the editor's FIRST filesystem scan,
## `res://` (and even absolute-path) reads return EMPTY for the whole window — the GUITKX2507
## cold-open wall (field capture 2026-07-03) — while script loading itself is reliable. If
## guitkx.gd runs at all, its preloaded const sibling exists too.
##
## vocabulary.json stays the SINGLE SOURCE OF TRUTH (the LSP ships the byte-identical copy); this
## .gen.gd is the committed GDScript projection — the same pattern as Unity compiling the
## vocabulary into the generator DLL. tests/guitkx_test.gd fails if the two drift; regenerate
## after ANY vocabulary.json change:
##   godot --headless --path . --script res://addons/reactive_ui_toolkit/dev/gen_vocabulary.gd

const _SRC := "res://addons/reactive_ui_toolkit/guitkx/vocabulary.json"
const _DST := "res://addons/reactive_ui_toolkit/guitkx/guitkx_vocabulary.gen.gd"

func _initialize() -> void:
	var text := FileAccess.get_file_as_string(_SRC)
	var parsed = JSON.parse_string(text)
	if not (parsed is Dictionary and (parsed as Dictionary).has("host_tags") and (parsed as Dictionary).has("hooks")):
		push_error("gen_vocabulary: %s is missing or not the expected shape -- nothing written" % _SRC)
		quit(1)
		return
	# JSON.stringify output is also a valid GDScript Dictionary literal (string keys, true/false/
	# null, arrays, numbers), so the projection is just the parsed-and-reserialized source:
	# shape-validated, key order preserved, byte-stable for the drift test on both ends.
	var body := JSON.stringify(parsed, "\t")
	var f := FileAccess.open(_DST, FileAccess.WRITE)
	if f == null:
		push_error("gen_vocabulary: cannot write " + _DST)
		quit(1)
		return
	f.store_string(
		"## GENERATED from vocabulary.json by dev/gen_vocabulary.gd -- DO NOT EDIT.\n"
		+ "## Regenerate after any vocabulary.json change:\n"
		+ "##   godot --headless --path . --script res://addons/reactive_ui_toolkit/dev/gen_vocabulary.gd\n"
		+ "##\n"
		+ "## Embedded as a script const so the compiler needs NO runtime file read: during the\n"
		+ "## editor's first filesystem scan, FileAccess reads return empty (the GUITKX2507 cold-open\n"
		+ "## wall) while script loading is reliable -- if guitkx.gd loads, this Dictionary exists.\n"
		+ "## tests/guitkx_test.gd fails when this file drifts from vocabulary.json.\n"
		+ "const DATA: Dictionary = " + body + "\n"
	)
	f.close()
	print("gen_vocabulary: wrote %s (%d chars)" % [_DST, body.length()])
	quit(0)
