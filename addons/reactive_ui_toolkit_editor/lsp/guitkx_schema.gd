@tool
class_name GuitkxSchema
extends RefCounted
## Markup vocabulary for `.guitkx` IDE intelligence. Loads the shared grammar schema
## (`guitkx-schema.json`) and resolves per-tag attributes / events / signals against the LIVE
## `ClassDB`. Because the native addon runs *inside* Godot, it queries `ClassDB` directly -- more
## accurate (matches the running engine version) than the headless TS LSP's bundled
## `godot-control.json` dump, and nothing to keep in sync. Single source of truth for markup
## completion + hover. [Phase 1 -- plans/GODOT_ANALYZER_INTEGRATION_PLAN.md §7]

# Bundled copy so the addon works installed standalone; dev fallback to the canonical grammar file.
const _BUNDLED_SCHEMA := "res://addons/reactive_ui_toolkit_editor/data/guitkx-schema.json"
const _DEV_SCHEMA := "res://ide-extensions/grammar/guitkx-schema.json"

# 0.9.0 naming loyalty: events are derived LIVE from ClassDB — `on` + PascalCase(signal) for
# every signal of the class (onPressed -> pressed). No alias table; mirrors host_config.gd's
# generic resolution and events.ts on the TS side [three-surface parity].

static var _schema: Dictionary = {}
static var _tags: Dictionary = {}   # tag name -> host element entry
static var _loaded := false

static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var raw := ""
	for p in [_BUNDLED_SCHEMA, _DEV_SCHEMA]:
		if FileAccess.file_exists(p):
			raw = FileAccess.get_file_as_string(p)
			if raw != "":
				break
	if raw == "":
		push_warning("GuitkxSchema: guitkx-schema.json not found (bundled or dev path).")
		return
	var parsed: Variant = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("GuitkxSchema: guitkx-schema.json did not parse to an object.")
		return
	_schema = parsed
	for e in _schema.get("hostElements", []):
		if e is Dictionary and e.has("tag"):
			_tags[e["tag"]] = e

# --- Static vocabulary -------------------------------------------------------------------------

static func host_tags() -> Array:
	_ensure_loaded()
	return _tags.keys()

## A tag is a host element if it's in the curated schema OR names any instantiable ClassDB Node
## class (0.9.0 open vocabulary — mirrors the compiler's tag resolution in guitkx.gd).
static func is_host_tag(tag: String) -> bool:
	_ensure_loaded()
	if _tags.has(tag):
		return true
	return ClassDB.class_exists(tag) and ClassDB.can_instantiate(tag) and ClassDB.is_parent_class(tag, "Node")

static func host_element(tag: String) -> Dictionary:
	_ensure_loaded()
	return _tags.get(tag, {})

static func godot_class_for(tag: String) -> String:
	var cls := str(host_element(tag).get("godotClass", ""))
	if cls == "" and ClassDB.class_exists(tag) and ClassDB.can_instantiate(tag) and ClassDB.is_parent_class(tag, "Node"):
		return tag   # open-vocabulary tag: the tag IS the class name
	return cls

static func control_flow() -> Array:
	_ensure_loaded()
	return _schema.get("controlFlow", [])

static func preamble_directives() -> Array:
	_ensure_loaded()
	return _schema.get("preambleDirectives", [])

static func declarations() -> Array:
	_ensure_loaded()
	return _schema.get("declarations", [])

static func structural_attributes() -> Array:
	_ensure_loaded()
	return _schema.get("structuralAttributes", [])

static func common_attributes() -> Array:
	_ensure_loaded()
	return _schema.get("commonAttributes", [])

# --- Live ClassDB resolution -------------------------------------------------------------------

## Settable, editor-facing properties of a host tag's Godot class (inherited included), as
## [{name, type}]. Skips category/group headers, internal (`_`) and subresource (`a/b`) names.
static func godot_properties(godot_class: String) -> Array:
	var out: Array = []
	if godot_class == "" or not ClassDB.class_exists(godot_class):
		return out
	for p in ClassDB.class_get_property_list(godot_class, false):
		var usage := int(p.get("usage", 0))
		if usage & (PROPERTY_USAGE_CATEGORY | PROPERTY_USAGE_GROUP | PROPERTY_USAGE_SUBGROUP):
			continue
		if (usage & PROPERTY_USAGE_EDITOR) == 0:
			continue
		var nm := str(p.get("name", ""))
		if nm == "" or nm.begins_with("_") or nm.contains("/"):
			continue
		out.append({ "name": nm, "type": type_string(int(p.get("type", TYPE_NIL))) })
	return out

## Property info for a single settable property on `godot_class`: { type:int (Variant.Type),
## hint:int, hint_string:String }, or {} when the class/property is unknown. Drives attribute
## VALUE completion (bool -> true/false, enum -> the hint names).
static func property_info(godot_class: String, prop: String) -> Dictionary:
	if godot_class == "" or prop == "" or not ClassDB.class_exists(godot_class):
		return {}
	for p in ClassDB.class_get_property_list(godot_class, false):
		if str(p.get("name", "")) == prop:
			return {
				"type": int(p.get("type", TYPE_NIL)),
				"hint": int(p.get("hint", PROPERTY_HINT_NONE)),
				"hint_string": str(p.get("hint_string", "")),
			}
	return {}

## The RuitkStyle vocabulary (the `style={ {...} }` dict keys), from the bundled schema:
## [{name, type, detail}]. Godot's own tooling has no vocabulary for these.
## The style vocabulary the runtime ACTUALLY accepts: the curated head from the schema, plus every
## `StyleBoxFlat` property, read live from ClassDB the same way `RuitkStyle` reads them.
##
## The schema's list is 45 hand-maintained entries against a surface of roughly 74, so the
## per-side and per-corner keys -- `border_width_left`, `corner_radius_top_right`,
## `content_margin_bottom` and the rest -- could not be reached from any menu, and the list could
## drift from the engine on any Godot release without anything noticing.
static func style_keys_live() -> Array:
	var out: Array = []
	var seen := {}
	for entry in style_keys():
		var spec := entry as Dictionary
		var name := str(spec.get("name", ""))
		if name.is_empty() or seen.has(name):
			continue
		seen[name] = true
		out.append(spec)
	for prop in ClassDB.class_get_property_list("StyleBoxFlat"):
		var info := prop as Dictionary
		var name := str(info.get("name", ""))
		# The same filter `RuitkStyle` applies: groups and category rows are not properties, and
		# the `resource_*` four belong to Resource rather than to the box.
		if name.is_empty() or seen.has(name) or name.begins_with("resource_"):
			continue
		var usage := int(info.get("usage", 0))
		if usage & PROPERTY_USAGE_GROUP or usage & PROPERTY_USAGE_SUBGROUP \
				or usage & PROPERTY_USAGE_CATEGORY:
			continue
		if not (usage & PROPERTY_USAGE_EDITOR):
			continue
		seen[name] = true
		out.append({
			"name": name,
			"type": type_string(int(info.get("type", TYPE_NIL))),
			"detail": "StyleBoxFlat.%s" % name,
		})
	return out


static func style_keys() -> Array:
	_ensure_loaded()
	return _schema.get("styleKeys", [])

## Loyal event names applicable to a host class + the Godot signal each binds to, as
## [{name, signal}] -- computed live from ClassDB: `on` + PascalCase(signal) for EVERY signal the
## class has (inherited included), so onPressed shows on buttons and onValueChanged on Ranges.
## Internal (`_`-prefixed) signals are skipped.
static func events_for_class(godot_class: String) -> Array:
	var out: Array = []
	if godot_class == "" or not ClassDB.class_exists(godot_class):
		return out
	for s in ClassDB.class_get_signal_list(godot_class, false):
		var sig := str(s.get("name", ""))
		if sig == "" or sig.begins_with("_"):
			continue
		out.append({ "name": "on" + sig.to_pascal_case(), "signal": sig })
	return out

## All signals of a class (the `on_<signal>` verbatim escape hatch), as [{name, args}].
static func godot_signals(godot_class: String) -> Array:
	var out: Array = []
	if godot_class == "" or not ClassDB.class_exists(godot_class):
		return out
	for s in ClassDB.class_get_signal_list(godot_class, false):
		out.append({ "name": str(s.get("name", "")), "args": s.get("args", []) })
	return out

## The Godot signal an event attribute binds to on `godot_class`, or "" if it is not an event.
## Mirrors host_config.gd (0.9.0): `on_<signal>` is verbatim; `on<Pascal>` lowers to snake_case.
static func resolve_event_signal(name: String, _godot_class: String) -> String:
	if name.begins_with("on_"):
		return name.substr(3)
	if name.length() > 2 and name.begins_with("on") and _is_upper(name.unicode_at(2)):
		return _camel_to_snake(name.substr(2))
	return ""

# --- Hover text (Markdown) ---------------------------------------------------------------------

static func hover_for_tag(tag: String) -> String:
	_ensure_loaded()
	if _tags.has(tag):
		var e: Dictionary = _tags[tag]
		return "**`<%s>`** — host element · Godot `%s` (factory `%s`)." % [tag, e.get("godotClass", ""), e.get("factory", "")]
	return ""

static func hover_for_directive(name: String) -> String:
	_ensure_loaded()
	for group in [control_flow(), preamble_directives(), declarations()]:
		for d in group:
			var key := str(d.get("directive", d.get("name", d.get("keyword", ""))))
			if key == name:
				var desc := str(d.get("description", ""))
				var form := str(d.get("form", ""))
				if form != "":
					return "**`%s`** — %s\n\n`%s`" % [name, desc, form]
				return "**`%s`** — %s" % [name, desc]
	return ""

static func hover_for_attribute(tag: String, attr: String) -> String:
	_ensure_loaded()
	for a in structural_attributes():
		if str(a.get("name", "")) == attr:
			return "**`%s`**: `%s` — %s" % [attr, a.get("type", ""), a.get("description", "")]
	var gclass := godot_class_for(tag)
	if attr.begins_with("on"):
		var sig := resolve_event_signal(attr, gclass)
		if sig != "":
			return "**`%s`** → Godot signal `%s`%s." % [attr, sig, (" on `%s`" % gclass) if gclass != "" else ""]
	for p in godot_properties(gclass):
		if str(p.get("name", "")) == attr:
			return "**`%s`**: `%s` — property on `%s`." % [attr, p.get("type", ""), gclass]
	for a in common_attributes():
		if str(a.get("name", "")) == attr:
			return "**`%s`**: `%s` — %s" % [attr, a.get("type", ""), a.get("description", "")]
	return ""

# --- Small helpers -----------------------------------------------------------------------------

static func _is_upper(c: int) -> bool:
	return c >= 65 and c <= 90

static func _camel_to_snake(s: String) -> String:
	var out := ""
	for i in s.length():
		var c := s.unicode_at(i)
		if _is_upper(c):
			if i > 0:
				out += "_"
			out += char(c + 32)
		else:
			out += char(c)
	return out
