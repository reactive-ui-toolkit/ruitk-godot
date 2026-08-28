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
		# `name: Type = default` -> name, Type, default.
		#
		# The default used to be thrown away here with a comment saying it is what the prop does
		# when the attribute is absent -- true for the ATTRIBUTE menu, and exactly wrong for the
		# preview, which needs a value to render with when nothing in the tree uses the component
		# yet.
		var declared := ""
		var equals := part.find("=")
		if equals >= 0:
			declared = part.substr(equals + 1).strip_edges()
			part = part.substr(0, equals).strip_edges()
		var colon := part.find(":")
		if colon < 0:
			out.append({ "name": part, "type": "Variant", "default": declared })
			continue
		out.append({
			"name": part.substr(0, colon).strip_edges(),
			"type": part.substr(colon + 1).strip_edges(),
			"default": declared,
		})
	return out


## The attributes a HOST tag takes: the Godot class's own properties, then its signals as event
## handlers, spelled the way the compiler expects (`on` + PascalCase).
static func props_of_host(tag: String) -> Array:
	var out: Array = []
	var godot_class := Schema.godot_class_for(tag)
	if godot_class.is_empty():
		godot_class = tag
	# READ THE RECORD, do not stringify it. `godot_properties` hands back `[{ name, type }, ...]`,
	# and `str(prop)` on that yields the literal text `{ "name": "text", "type": "String" }` --
	# which became the menu label, then the attribute name, then the text written into the tag.
	# Every one of a Button's 139 properties was offered under that name, and `property_info`
	# looking the garbage up returned {} so every type collapsed to "Variant" and every seeded
	# value to `null`.
	#
	# The round-trip through `property_info` goes with it: `godot_properties` already reports
	# `type` as a `type_string()` -- "String", "bool", "int", "float", "Vector2", "Color" -- which
	# is exactly the vocabulary `default_value` below matches on.
	for prop in Schema.godot_properties(godot_class):
		var info := prop as Dictionary
		out.append({ "name": str(info.get("name", "")), "type": str(info.get("type", "Variant")) })
	for event in Schema.events_for_class(godot_class):
		var spec: Variant = event
		var event_name := str((spec as Dictionary).get("name", "")) if spec is Dictionary else str(spec)
		out.append({ "name": event_name, "type": "Callable" })
	return out


## The setup line a hook insertion writes.
##
## `var _ = useState()` was written for every one of the 23 hooks, and it is wrong twice over.
## `var _` is not legal GDScript -- the parser rejects it with "Expected variable name after
## \"var\"" -- so the generated .gd failed at load. And roughly ten of the hooks take
## required arguments, so the call was wrong even where the binding was not.
##
## Hooks that return nothing are written as bare calls; the rest bind a name derived from the
## hook, so the line reads like code someone would have typed.
const HOOK_STUBS := {
	"useState": "var state = useState(null)",
	"useReducer": "var store = useReducer(func(s, action): return s, null)",
	"useRef": "var ref = useRef(null)",
	"useMemo": "var memo = useMemo(func(): return null, [])",
	"useCallback": "var callback = useCallback(func(): pass, [])",
	"useEffect": "useEffect(func(): pass, [])",
	"useLayoutEffect": "useLayoutEffect(func(): pass, [])",
	"useImperativeHandle": "useImperativeHandle(null, func(): return null, [])",
	"createContext": "var context = createContext(null)",
	"useContext": "var value = useContext(null)",
	"provideContext": "provideContext(null, null)",
	"useDeferredValue": "var deferred = useDeferredValue(null)",
	"useTransition": "var transition = useTransition()",
	"useStableCallback": "var stable = useStableCallback(func(): pass)",
	"useStableFunc": "var stable = useStableFunc(func(): pass)",
	"useStableAction": "var action = useStableAction(func(): pass)",
	"useSafeArea": "var safe_area = useSafeArea()",
	"useSignal": "var signal_value = useSignal(null)",
	"useSignalKey": "var signal_key = useSignalKey(null)",
	"useTween": "var tween = useTween()",
	"useTweenValue": "var tween_value = useTweenValue(0.0, 1.0, 0.3)",
	"useAnimate": "var animate = useAnimate()",
	"useSfx": "var sfx = useSfx()",
}


## The line to insert for `hook_name`, always legal GDScript.
##
## A hook this table does not know still gets a binding rather than `var _`: an unknown hook is a
## user hook from a `.hooks.guitkx` module, and binding its result is the common case.
static func hook_stub(hook_name: String) -> String:
	if HOOK_STUBS.has(hook_name):
		return str(HOOK_STUBS[hook_name])
	return "var %s = %s()" % [_binding_for(hook_name), hook_name]


## A snake_case binding derived from a hook's name: `useCartTotal` -> `cart_total`.
static func _binding_for(hook_name: String) -> String:
	var stem := hook_name
	if stem.begins_with("use_"):
		stem = stem.substr(4)
	elif stem.begins_with("use") and stem.length() > 3:
		stem = stem.substr(3)
	var out := ""
	for i in stem.length():
		var ch := stem[i]
		if ch >= "A" and ch <= "Z":
			if not out.is_empty():
				out += "_"
			out += ch.to_lower()
		else:
			out += ch
	return out if not out.is_empty() else "value"


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
