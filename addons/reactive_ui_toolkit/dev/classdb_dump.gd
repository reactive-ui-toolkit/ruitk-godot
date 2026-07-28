extends SceneTree
## Generates the ClassDB property/signal dump the LSP uses for per-Control attribute completion
## (Phase 6c). The Node LSP has no in-process ClassDB, so a @tool/headless run walks Godot's ClassDB
## for Control + subclasses and writes own-only properties + signals (base-flattened in the LSP) to a
## JSON bundled with the extension. Regenerate per Godot minor:
##   godot --headless --path . --script res://addons/reactive_ui_toolkit/dev/classdb_dump.gd -- <output.json>

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var output: String = args[0] if not args.is_empty() else "res://ide-extensions/lsp-server/classdb/godot-control.json"
	var classes: Array = ["Control"]
	classes.append_array(ClassDB.get_inheriters_from_class("Control"))
	var out := {
		"godot": Engine.get_version_info()["string"],
		"classes": {},
	}
	for c in classes:
		if not ClassDB.class_exists(c):
			continue
		out["classes"][c] = {
			"base": ClassDB.get_parent_class(c),
			"properties": _props(c),
			"signals": _signals(c),
		}
	var f := FileAccess.open(output, FileAccess.WRITE)
	if f == null:
		push_error("classdb_dump: cannot write " + output)
		quit(1)
		return
	f.store_string(JSON.stringify(out, "  "))
	f.close()
	print("classdb_dump: wrote %d classes to %s" % [out["classes"].size(), output])
	quit(0)

func _props(c: String) -> Array:
	var result: Array = []
	for p in ClassDB.class_get_property_list(c, true):   # own-only
		var usage: int = p["usage"]
		if usage & PROPERTY_USAGE_GROUP or usage & PROPERTY_USAGE_SUBGROUP or usage & PROPERTY_USAGE_CATEGORY:
			continue
		if not (usage & PROPERTY_USAGE_EDITOR):
			continue
		var name: String = p["name"]
		if name.begins_with("_") or "/" in name:
			continue
		var entry := { "name": name, "type": type_string(p["type"]) }
		if p["hint"] == PROPERTY_HINT_ENUM and p["hint_string"] != "":
			entry["enum"] = p["hint_string"]   # "A,B,C" or "A:0,B:2,..."
		result.append(entry)
	return result

func _signals(c: String) -> Array:
	var result: Array = []
	for s in ClassDB.class_get_signal_list(c, true):   # own-only
		var sig_args: Array = []
		for a in s["args"]:
			sig_args.append({ "name": a["name"], "type": type_string(a["type"]) })
		result.append({ "name": s["name"], "args": sig_args })
	return result
