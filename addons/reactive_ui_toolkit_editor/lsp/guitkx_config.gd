@tool
class_name GuitkxConfig
extends RefCounted
## `guitkx.config.json` discovery (parity plan G26): walk up from the file's folder to `res://`,
## nearest file wins — the same rule as the VS Code extension's loadFormatterConfig, so the same
## project formats identically in both editors. Only known formatter keys pass through; malformed
## or absent configs yield {} (the formatter's own defaults).

const FILE_NAME := "guitkx.config.json"
const FORMATTER_KEYS := [
	"printWidth", "indentStyle", "indentSize", "singleAttributePerLine", "insertSpaceBeforeSelfClose",
]

## Formatter options for the file at `path` (pass straight into RUIGuitkxFormatter.format).
static func formatter_opts_for(path: String) -> Dictionary:
	var dir := path.get_base_dir()
	if dir.is_empty() or not dir.begins_with("res://"):
		dir = "res://"
	while true:
		var candidate := dir.path_join(FILE_NAME)
		if FileAccess.file_exists(candidate):
			return _formatter_section(candidate)
		if dir == "res://":
			break
		var parent := dir.get_base_dir()
		if parent == dir:
			break
		dir = parent
	return {}

static func _formatter_section(config_path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(config_path))
	if not (parsed is Dictionary):
		return {}
	var fmt: Variant = (parsed as Dictionary).get("formatter")
	if not (fmt is Dictionary):
		return {}
	var out := {}
	for k in FORMATTER_KEYS:
		if (fmt as Dictionary).has(k):
			out[k] = (fmt as Dictionary)[k]
	return out
