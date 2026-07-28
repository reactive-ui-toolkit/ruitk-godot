class_name V
extends RefCounted
## Factory for building the virtual UI tree. Mirrors ReactiveUIToolKit's `V`.
##
## NOTE: GDScript reserves the lowercase keyword `func`, so the function-component
## factory is `V.fc(...)` ("function component"), not `V.func(...)`.
##
## Usage:
##   V.fc(MyComponent.render, { "title": "Hi" })                    # function component
##   V.Button({ "text": "OK", "onPressed": _on_ok })                # host element
##   V.VBoxContainer({ "style": { "separation": 8 } }, [ ...kids ]) # container + children
##
## NAMING (0.9.0, plans/NAMING_LOYALTY_PROPOSAL.md): element factories are named EXACTLY
## after the Godot class they instantiate (V.VBoxContainer, V.Button, V.RichTextLabel) —
## 1:1 loyal to the engine, matching the .guitkx tag vocabulary verbatim. Only structural,
## non-engine factories (fc/comp/memo/h/text/fragment/portal/suspense/error_boundary and
## the router set) stay lowercase.
##
## A render function has the signature:  func(props: Dictionary, children: Array) -> RUIVNode | Array

## Function component.
static func fc(render_fn: Callable, props := {}, children = null, key = null) -> RUIVNode:
	return RUIVNode.make_component(render_fn, props, _norm(children), _key(props, key))

## Lazy path-based component resolver. Generated code references sibling .guitkx components by
## FILE PATH (`V.fc(V.comp("res://ui/card.gd"), ...)`) instead of by global class_name, so the
## emitted script parses and runs with ZERO dependence on the global class registry — a class
## created seconds ago (mid-play-session), an editor cache that hasn't rescanned yet, a game
## launched before the class existed: all immune by construction (field captures 2026-07-04).
## The load is deferred to first render and cached; an in-place hot reload keeps the script
## resource's identity, so the cached Callable keeps dispatching the newest code and the
## reconciler's fiber matching is unaffected. Deferred loading also makes self-recursion and
## cross-file component cycles safe (nothing loads at parse time).
##
## `fn` (0.10.0 mixed-decl / imports leg) selects WHICH static func on the target script the
## Callable binds — `render` for a file's binding component (back-compat default: old generated
## code calls `V.comp("res://….gd")` with one arg), or a decl name for a non-binding exported
## component addressed cross-file (`V.comp("res://….gd", "LocalRow")`). The cache is keyed on
## `path::fn` so the two never collide.
static var _comp_cache := {}
static func comp(path: String, fn: String = "render") -> Callable:
	var k := path + "::" + fn
	var c = _comp_cache.get(k)
	if c == null:
		c = Callable(load(path), fn)
		_comp_cache[k] = c
	return c

## Merge an ordered list of prop dictionaries left-to-right (later keys win) into a NEW dict — the
## runtime backing `{...spread}` in guitkx markup (`<C {...base} x={1} />`). Non-dict segments are
## skipped defensively. Merges into a fresh dict (Godot 4.0+ Dictionary.merge), never mutating a source.
static func _spread_all(parts: Array) -> Dictionary:
	var out := {}
	for p in parts:
		if p is Dictionary:
			out.merge(p, true)
	return out

## Memoized function component (parity name for ReactiveUIToolKit's V.Memo). Functionally V.fc — every
## function component in this port already bails its re-render when props are unchanged. For a custom
## equality, pass `props.__memo_eq = func(old_props, new_props) -> bool` (consulted by the reconciler).
static func memo(render_fn: Callable, props := {}, children = null, key = null) -> RUIVNode:
	return fc(render_fn, props, children, key)

## Generic host element by Godot class name, e.g. V.h("ProgressBar", {...}).
## INLINED (no make_host/_key/_norm sub-calls, no throwaway `[]` for childless elements) —
## this is the hottest factory path; each GDScript call elided here is ~1 per element per
## frame, i.e. thousands/frame in a big list. [perf]
static func h(type: String, props := {}, children = null, key = null) -> RUIVNode:
	var n := RUIVNode.new()
	n.type = type
	n.props = props
	n.children = _EMPTY if children == null else _norm(children)
	if key != null:
		n.key = key
	elif props.has("key"):
		n.key = props["key"]
	return n

# --- host element factories (the generic `h()` reaches any other Godot Control) ---
# Each is named EXACTLY after the Godot class it instantiates (GDScript allows methods that
# share a native class's name — verified on 4.7; member access `V.Button` always resolves to
# the method, never the global class).

# Containers
static func Control(props := {}, children = null, key = null) -> RUIVNode: return h("Control", props, children, key)
static func VBoxContainer(props := {}, children = null, key = null) -> RUIVNode: return h("VBoxContainer", props, children, key)
static func HBoxContainer(props := {}, children = null, key = null) -> RUIVNode: return h("HBoxContainer", props, children, key)
static func BoxContainer(props := {}, children = null, key = null) -> RUIVNode: return h("BoxContainer", props, children, key)
static func GridContainer(props := {}, children = null, key = null) -> RUIVNode: return h("GridContainer", props, children, key)
static func MarginContainer(props := {}, children = null, key = null) -> RUIVNode: return h("MarginContainer", props, children, key)
static func PanelContainer(props := {}, children = null, key = null) -> RUIVNode: return h("PanelContainer", props, children, key)
static func CenterContainer(props := {}, children = null, key = null) -> RUIVNode: return h("CenterContainer", props, children, key)
static func ScrollContainer(props := {}, children = null, key = null) -> RUIVNode: return h("ScrollContainer", props, children, key)
static func FlowContainer(props := {}, children = null, key = null) -> RUIVNode: return h("FlowContainer", props, children, key)
static func HFlowContainer(props := {}, children = null, key = null) -> RUIVNode: return h("HFlowContainer", props, children, key)
static func VFlowContainer(props := {}, children = null, key = null) -> RUIVNode: return h("VFlowContainer", props, children, key)
static func TabContainer(props := {}, children = null, key = null) -> RUIVNode: return h("TabContainer", props, children, key)
static func SplitContainer(props := {}, children = null, key = null) -> RUIVNode: return h("SplitContainer", props, children, key)
static func HSplitContainer(props := {}, children = null, key = null) -> RUIVNode: return h("HSplitContainer", props, children, key)
static func VSplitContainer(props := {}, children = null, key = null) -> RUIVNode: return h("VSplitContainer", props, children, key)
static func AspectRatioContainer(props := {}, children = null, key = null) -> RUIVNode: return h("AspectRatioContainer", props, children, key)
static func FoldableContainer(props := {}, children = null, key = null) -> RUIVNode: return h("FoldableContainer", props, children, key)
static func SubViewportContainer(props := {}, children = null, key = null) -> RUIVNode: return h("SubViewportContainer", props, children, key)

# Text / display
static func Label(props := {}, children = null, key = null) -> RUIVNode: return h("Label", props, children, key)

## A text node: renders a string as a Label. Raw String children are AUTO-WRAPPED to this, so
## `V.VBoxContainer({}, ["Score: ", score_str])` and a component returning a bare String both work
## instead of the string being silently dropped. (Godot renders text via Label nodes — this is the
## text leaf; structural, so it keeps its lowercase non-class name.)
static func text(s, key = null) -> RUIVNode: return h("Label", { "text": str(s) }, null, key)
static func RichTextLabel(props := {}, children = null, key = null) -> RUIVNode: return h("RichTextLabel", props, children, key)
static func Panel(props := {}, children = null, key = null) -> RUIVNode: return h("Panel", props, children, key)
static func ColorRect(props := {}, children = null, key = null) -> RUIVNode: return h("ColorRect", props, children, key)
static func TextureRect(props := {}, children = null, key = null) -> RUIVNode: return h("TextureRect", props, children, key)
static func NinePatchRect(props := {}, children = null, key = null) -> RUIVNode: return h("NinePatchRect", props, children, key)
static func ReferenceRect(props := {}, children = null, key = null) -> RUIVNode: return h("ReferenceRect", props, children, key)
static func HSeparator(props := {}, children = null, key = null) -> RUIVNode: return h("HSeparator", props, children, key)
static func VSeparator(props := {}, children = null, key = null) -> RUIVNode: return h("VSeparator", props, children, key)

# Buttons
static func Button(props := {}, children = null, key = null) -> RUIVNode: return h("Button", props, children, key)
static func CheckBox(props := {}, children = null, key = null) -> RUIVNode: return h("CheckBox", props, children, key)
static func CheckButton(props := {}, children = null, key = null) -> RUIVNode: return h("CheckButton", props, children, key)
static func OptionButton(props := {}, children = null, key = null) -> RUIVNode: return h("OptionButton", props, children, key)
static func MenuButton(props := {}, children = null, key = null) -> RUIVNode: return h("MenuButton", props, children, key)
static func LinkButton(props := {}, children = null, key = null) -> RUIVNode: return h("LinkButton", props, children, key)
static func TextureButton(props := {}, children = null, key = null) -> RUIVNode: return h("TextureButton", props, children, key)

# Inputs
static func LineEdit(props := {}, children = null, key = null) -> RUIVNode: return h("LineEdit", props, children, key)
static func TextEdit(props := {}, children = null, key = null) -> RUIVNode: return h("TextEdit", props, children, key)
static func CodeEdit(props := {}, children = null, key = null) -> RUIVNode: return h("CodeEdit", props, children, key)
static func SpinBox(props := {}, children = null, key = null) -> RUIVNode: return h("SpinBox", props, children, key)
static func HSlider(props := {}, children = null, key = null) -> RUIVNode: return h("HSlider", props, children, key)
static func VSlider(props := {}, children = null, key = null) -> RUIVNode: return h("VSlider", props, children, key)
static func HScrollBar(props := {}, children = null, key = null) -> RUIVNode: return h("HScrollBar", props, children, key)
static func VScrollBar(props := {}, children = null, key = null) -> RUIVNode: return h("VScrollBar", props, children, key)
static func ProgressBar(props := {}, children = null, key = null) -> RUIVNode: return h("ProgressBar", props, children, key)
static func TextureProgressBar(props := {}, children = null, key = null) -> RUIVNode: return h("TextureProgressBar", props, children, key)
static func ColorPicker(props := {}, children = null, key = null) -> RUIVNode: return h("ColorPicker", props, children, key)
static func ColorPickerButton(props := {}, children = null, key = null) -> RUIVNode: return h("ColorPickerButton", props, children, key)
static func VirtualJoystick(props := {}, children = null, key = null) -> RUIVNode: return h("VirtualJoystick", props, children, key)

# Media (Godot's audio/video are scene nodes — thin host elements; see also useSfx for one-shots)
static func AudioStreamPlayer(props := {}, key = null) -> RUIVNode: return h("AudioStreamPlayer", props, null, key)
static func VideoStreamPlayer(props := {}, key = null) -> RUIVNode: return h("VideoStreamPlayer", props, null, key)

# Item-model controls (declarative props; see RUIHost adapters)
static func TabBar(props := {}, children = null, key = null) -> RUIVNode: return h("TabBar", props, children, key)
static func ItemList(props := {}, children = null, key = null) -> RUIVNode: return h("ItemList", props, children, key)
static func Tree(props := {}, children = null, key = null) -> RUIVNode: return h("Tree", props, children, key)
static func MenuBar(props := {}, children = null, key = null) -> RUIVNode: return h("MenuBar", props, children, key)

# --- structural vnodes ---

## A fragment groups children without introducing a host node.
static func fragment(children = null, key = null) -> RUIVNode:
	return RUIVNode.make_fragment(_norm(children), key)

## A portal renders its children under `target` instead of the normal parent node.
static func portal(target: Node, children = null, key = null) -> RUIVNode:
	return RUIVNode.make_portal(target, _norm(children), key)

## A Suspense boundary: shows props.fallback until ready (props.ready_signal fires or props.is_ready()
## becomes true), then renders `children`. GDScript can't throw-to-suspend, so readiness is signal/poll
## driven — see RUISuspense.
static func suspense(props := {}, children = null, key = null) -> RUIVNode:
	return fc(RUISuspense.suspense_fn, props, children, key)

## An error boundary. props: { "fallback": vnode, "on_error": Callable, "reset_key": any }.
## NOTE: GDScript can't catch render crashes; the boundary shows `fallback` when activated
## imperatively and resets when `reset_key` changes. See reconciler `_begin_error_boundary`.
static func error_boundary(props := {}, children = null, key = null) -> RUIVNode:
	return RUIVNode.make_error_boundary(props, _norm(children), key)

# --- router ---

## Provides router context to its subtree. props: { "history": RUIHistory, "initial": "/", "basename": "/" }.
static func router(props := {}, children = null, key = null) -> RUIVNode:
	return fc(RUIRouter.provider, props, children, key)

## Renders the best-matching route. Auto-detects the API:
##   • a Dictionary `routes` prop  -> legacy table: { "routes": [ { "path", "component" }, ... ] }
##   • <Route> children            -> ranked first-match switch: V.routes({}, [ V.route({...}), ... ])
static func routes(props := {}, children = null, key = null) -> RUIVNode:
	return fc(RUIRouter.routes, props, children, key)

## A single route. props: { "path": "/users/:id", "element": vnode | "render": func(match), "index": bool,
## "exact": bool, "case_sensitive": bool }. Children may be nested <Route>s rendered via <Outlet/>.
static func route(props := {}, children = null, key = null) -> RUIVNode:
	return fc(RUIRouter.route_fn, props, children, key)

## Renders the matched nested route (or `children` as a fallback). props: { "context": any }.
static func outlet(props := {}, children = null, key = null) -> RUIVNode:
	return fc(RUIRouter.outlet_fn, props, children, key)

## Declarative redirect (navigates from an effect after commit). props: { "to": "/x", "replace": true, "state": any }.
static func navigate(props := {}, key = null) -> RUIVNode:
	return fc(RUIRouter.navigate_fn, props, [], key)

## An active-aware navigation button. props: { "to", "label", "replace", "end", "case_sensitive",
## "style", "active_style", "state", "button_props" }.
static func nav_link(props := {}, children = null, key = null) -> RUIVNode:
	return fc(RUIRouter.nav_link_fn, props, children, key)

## A navigation button. props: { "to": "/path", "text": "...", "replace": bool, "button_props": {...} }.
static func link(props := {}, children = null, key = null) -> RUIVNode:
	return fc(RUIRouter.link, props, children, key)

static func _key(props, key):
	if key != null:
		return key
	if props is Dictionary and props.has("key"):
		return props["key"]
	return null

# A single shared, read-only empty array handed back for childless elements, so the
# ~N leaf vnodes built each frame don't each allocate a throwaway `[]`. The reconciler
# only ever READS children, never mutates them, so sharing one instance is safe. [perf P6]
const _EMPTY: Array = []

## Normalize children: accept a single vnode or an Array, DEEP-flatten nested arrays
## (so `[a, [b, [c, d]]]` from `.map().map()` / nested conditional output works), and drop nulls.
## Only raw Arrays are flattened — vnodes (with their own .children) are appended as-is.
static func _norm(children) -> Array:
	if children == null:
		return _EMPTY
	if children is String:
		return [text(children)]
	if not (children is Array):
		return [children]
	if children.is_empty():
		return _EMPTY
	var out: Array = []
	_flatten_into(children, out)
	return out

# Recursive deep-flatten helper: appends every non-null, non-Array element of `arr` (and of any
# nested Array, to any depth) into `out`. A vnode is never an Array, so subtrees are preserved.
static func _flatten_into(arr: Array, out: Array) -> void:
	for c in arr:
		if c == null:
			continue
		if c is Array:
			_flatten_into(c, out)
		elif c is String:
			out.append(text(c))   # auto-wrap a raw String child as a text Label
		else:
			out.append(c)
