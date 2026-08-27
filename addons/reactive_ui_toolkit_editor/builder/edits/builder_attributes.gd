@tool
class_name RuitkBuilderAttributes
extends RefCounted
## What attributes a row can be given, and what a fresh one should say.
##
## Ported from the Unity leg's `ShowAttributeMenu` / `PropsOf` / `DefaultValueFor`. Their menu is
## fed by a UI Toolkit schema; ours is fed by the SAME schema the `.guitkx` editor completes from,
## plus ClassDB, so the builder offers exactly what the language server would offer and what the
## engine will actually accept. A builder that guessed at property names would be a slower way of
## typing them wrong.
##
## Three sources, in the order the menu shows them:
##   * a COMPONENT tag -> the props it declares, parsed out of its own signature
##   * a HOST tag -> the Godot class's properties, and its signals as `on<Signal>` handlers
##   * anything at all -> the freeform row, because the language accepts more than any list knows

const Schema = preload("res://addons/reactive_ui_toolkit_editor/lsp/guitkx_schema.gd")
const Graph = preload("res://addons/reactive_ui_toolkit_editor/builder/canvas/builder_graph.gd")

## Structural attributes every element takes, whatever it is.
const STRUCTURAL := [
	{ "name": "key", "type": "String" },
	{ "name": "ref", "type": "Callable" },
	{ "name": "style", "type": "Dictionary" },
]


## The props a COMPONENT declares, parsed from the signature the card already carries.
##
## From the signature rather than from the file: the card is projected from the buffer, so the
## signature is current with what the user has typed, and a second parse of the same declaration
## is a second thing to keep in step.
static func props_of_component(card: Graph.Card) -> Array:
	var out: Array = []
	if card == null:
		return out
	var signature := card.signature
	var open := signature.find("(")
	var close := signature.rfind(")")
	if open < 0 or close <= open:
		return out
	for raw in signature.substr(open + 1, close - open - 1).split(","):
		var part := str(raw).strip_edges()
		if part.is_empty():
			continue
		# `name: Type = default` -> name, Type. The default is not offered: it is what the prop
		# already does when the attribute is absent.
		var equals := part.find("=")
		if equals >= 0:
			part = part.substr(0, equals).strip_edges()
		var colon := part.find(":")
		if colon < 0:
			out.append({ "name": part, "type": "Variant" })
			continue
		out.append({
			"name": part.substr(0, colon).strip_edges(),
			"type": part.substr(colon + 1).strip_edges(),
		})
	return out


## The attributes a HOST tag takes: the Godot class's own properties, then its signals as event
## handlers, spelled the way the compiler expects (`on` + PascalCase).
static func props_of_host(tag: String) -> Array:
	var out: Array = []
	var godot_class := Schema.godot_class_for(tag)
	if godot_class.is_empty():
		godot_class = tag
	for prop in Schema.godot_properties(godot_class):
		var name := str(prop)
		var info: Dictionary = Schema.property_info(godot_class, name)
		out.append({ "name": name, "type": str(info.get("type", "Variant")) })
	for event in Schema.events_for_class(godot_class):
		out.append({ "name": str(event), "type": "Callable" })
	return out


## What a newly-added attribute should say.
##
## SEEDED WITH SOMETHING THAT COMPILES, never a placeholder. An attribute added and left for a
## moment is an attribute the preview is compiling, and `text={value}` names an identifier that
## does not exist -- the user gets an error for an edit they have not finished making.
static func default_value(type: String) -> Dictionary:
	match type:
		"String", "StringName", "NodePath":
			return { "value": "text", "quoted": true }
		"bool":
			return { "value": "true", "quoted": false }
		"int":
			return { "value": "0", "quoted": false }
		"float":
			return { "value": "0.0", "quoted": false }
		"Vector2":
			return { "value": "Vector2.ZERO", "quoted": false }
		"Color":
			return { "value": "Color.WHITE", "quoted": false }
		"Dictionary":
			return { "value": "{}", "quoted": false }
		"Array":
			return { "value": "[]", "quoted": false }
		"Callable":
			return { "value": "func(): pass", "quoted": false }
	return { "value": "null", "quoted": false }


## The whole menu for one row, already filtered to what the row does not have.
##
## Returns `[{ label, payload:{ name, type }, detail }]` plus separators and headings, ready for
## `builder_search_menu.gd`.
static func menu_for(tag: String, row: Graph.Line, component: Graph.Card) -> Array:
	var present := {}
	for pair in row.attr_pairs:
		var text := str(pair)
		var equals := text.find("=")
		present[text.substr(0, equals) if equals >= 0 else text] = true

	var items: Array = []
	var declared := props_of_component(component) if component != null else []
	if not declared.is_empty():
		items.append({ "heading": "props of <%s>" % tag })
		_append(items, declared, present)
		# The line the Unity leg draws here, and it is worth drawing: anything below is NOT
		# declared on this component, so writing it needs a matching prop first.
		items.append({ "separator": true })
		items.append({ "heading": "not declared on %s — needs a matching prop" % tag })

	var host := props_of_host(tag)
	if not host.is_empty():
		_append(items, host, present)
	items.append({ "separator": true })
	items.append({ "heading": "structural" })
	_append(items, STRUCTURAL, present)
	return items


static func _append(items: Array, props: Array, present: Dictionary) -> void:
	for entry in props:
		var prop := entry as Dictionary
		var name := str(prop["name"])
		if present.has(name):
			continue
		items.append({
			"label": name,
			"detail": str(prop.get("type", "")),
			"payload": prop,
		})
