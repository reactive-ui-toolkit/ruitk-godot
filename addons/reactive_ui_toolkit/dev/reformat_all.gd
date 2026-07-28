extends SceneTree
## Formats every .guitkx under the given roots with the formatter of record (canonical spaces-2
## since Phase D). Parse-error files come back verbatim (the formatter never corrupts), so the
## deliberately-broken contract fixtures are safe to sweep.
##   godot --headless --path . --script res://addons/reactive_ui_toolkit/dev/reformat_all.gd -- <dir-or-file> [...]

const Fmt = preload("res://addons/reactive_ui_toolkit/guitkx/guitkx_formatter.gd")

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		args = ["res://examples"]
	var files: Array = []
	for a in args:
		_collect(str(a), files, true)
	var changed := 0
	for f in files:
		var src := FileAccess.get_file_as_string(f)
		if src.is_empty():
			continue
		var r: Dictionary = Fmt.format(src)
		if bool(r["changed"]):
			var w := FileAccess.open(f, FileAccess.WRITE)
			w.store_string(str(r["text"]))
			w.close()
			changed += 1
			print("reformatted  ", f)
	print("[reformat_all] %d file(s) changed of %d scanned" % [changed, files.size()])
	quit(0)

func _collect(path: String, out: Array, is_root: bool) -> void:
	if FileAccess.file_exists(path):
		if path.get_extension() == "guitkx":
			out.append(path)
		return
	var d := DirAccess.open(path)
	if d == null:
		return
	if not is_root and FileAccess.file_exists(path.path_join(".gdignore")):
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if name != "." and name != "..":
			var p := path.path_join(name)
			if d.current_is_dir():
				if not name.begins_with("."):
					_collect(p, out, false)
			elif name.get_extension() == "guitkx":
				out.append(p)
		name = d.get_next()
	d.list_dir_end()
