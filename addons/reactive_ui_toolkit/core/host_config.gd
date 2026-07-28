class_name RUIHost
extends RefCounted
## The Godot "host config" — the ONLY layer that knows about concrete Godot node
## APIs. The reconciler talks to nodes exclusively through here, mirroring how
## ReactiveUIToolKit isolates `PropsApplier` / element adapters from the reconciler.
## Swapping this file (plus `RUIStyle`) is what would, in principle, retarget the
## same reconciler at a different host.
##
## Prop conventions on a host vnode's props Dictionary:
##   "style"        -> handed to RUIStyle
##   "ref"          -> a Callable(node) or a { "current": ... } box, receives the node
##   event handlers -> a Callable connected to a Godot signal on the node. NAMING IS 1:1 LOYAL TO
##                     GODOT (0.9.0, plans/NAMING_LOYALTY_PROPOSAL.md): the event prop is the exact
##                     signal name with an `on` marker. Two spellings, both valid:
##                     • onPascalCase (canonical): on + PascalCase(signal) -> the snake_case signal.
##                       onPressed -> pressed, onValueChanged -> value_changed, onTextSubmitted ->
##                       text_submitted, onGuiInput -> gui_input. Reaches ANY signal of ANY node.
##                     • on_<signal> (verbatim escape): binds literally to "<signal>" (e.g.
##                       on_gui_input, on_id_pressed) — the most literal spelling, same coverage.
##                     The pre-0.9 React aliases (onClick, polymorphic onChange, onInput, onSubmit,
##                     onFocus/onBlur, onPointer*, onResize) were REMOVED — _RENAMED_EVENTS_090
##                     turns them into a precise "renamed" warning instead of a silent no-op.
##   "draw_fn"      -> a Callable(canvas_item) for custom drawing (invoked via the node's `draw` signal)
##   "redraw_key"   -> bump to repaint `draw_fn` without changing the callback (pair with useStableCallback)
##   "key"          -> reconciliation key (consumed by V; never applied)
##   anything else  -> set directly as a node property (text, editable, disabled, ...)

const RESERVED := { "key": true, "ref": true, "style": true, "classes": true, "children": true, "items": true, "draw_fn": true, "redraw_key": true, "reuse_by_slot": true }  # O(1) lookup [perf #4]

static func create_node(type: String) -> Node:
	if not ClassDB.class_exists(type):
		push_error("[reactive_ui_toolkit] Unknown host element type: '%s'. Falling back to Control." % type)
		return Control.new()
	return ClassDB.instantiate(type)

## GO-05 host-node pool support. Prepare a childless leaf Control for reuse instead of
## queue_free + a later native ClassDB.instantiate. Returns false if the node must NOT be
## pooled (caller queue_free's it) — currently only item-model controls, whose non-node item
## state we don't generically clear.
##
## Design (measured): the *cheap* path. Rather than eagerly resetting the node to class defaults
## (which cost about as much as the instantiate it avoids), we only DETACH it and stash its
## last-applied props under `__rui_pool_old`. When the reconciler reuses it, it calls
## `apply_props(node, __rui_pool_old, new_props)` — a DIFF that (a) transitions events, (b) diffs
## style, (c) sets only CHANGED plain props (cheaper than the fresh path's full set), and calls
## `reset_removed_plain` for the audit-#23 gap (plain keys present last life but absent now). For
## the homogeneous-shape churn this pool targets (list rows, Doom bands), the diff is minimal and
## the removed-plain set is empty, so reuse is far cheaper than instantiate + full apply. A pooled
## node is orphaned (out of the tree), so its retained signal connections cannot fire.
static func reset_for_pool(node: Node, props) -> bool:
	if props is Dictionary and props.has("items"):
		return false  # item-model control (OptionButton/ItemList/…) — don't pool; caller frees.
	var parent := node.get_parent()
	if parent != null:
		parent.remove_child(node)
	node.set_meta("__rui_pool_old", props if props is Dictionary else {})
	return true

## GO-05: when reusing a pooled node for a DIFFERENT element, reset any plain prop it carried last
## life that the new props don't set, back to the class default — so a recycled node never leaks a
## stale plain value (events/style are handled by the apply_props diff; this closes the audit-#23
## "removed plain prop not reset" gap for cross-element reuse). Empty loop when shapes match.
static func reset_removed_plain(node: Node, old_props: Dictionary, new_props: Dictionary) -> void:
	var cls := node.get_class()
	for k in old_props:
		if RESERVED.has(k) or _is_event(k) or new_props.has(k):
			continue
		node.set(k, _class_default(cls, k))

## Cached (class, property) -> engine default value, so recycling isn't a per-node ClassDB probe.
static var _default_cache: Dictionary = {}
static func _class_default(cls: String, prop: String):
	var ck := cls + ":" + prop
	if _default_cache.has(ck):
		return _default_cache[ck]
	var d = ClassDB.class_get_property_default_value(cls, prop)
	_default_cache[ck] = d
	return d

## Where children of `node` should be parented. Unlike Unity's VisualElement (which
## auto-redirects Add() into contentContainer), Godot has no such indirection, so the
## reconciler calls this on every append/insert/reorder. Default: the node itself.
## Phase 1.3 overrides this per-element (e.g. ScrollContainer / TabContainer sinks).
static func resolve_child_host(node: Node) -> Node:
	# Most Godot controls take direct children (no Unity-style contentContainer indirection). A custom
	# scene can expose an inner content node via `node.set_meta("rui_content", <inner>)`; children then
	# parent there instead. Default: the node itself.
	if node.has_meta("rui_content"):
		var content = node.get_meta("rui_content")
		if content is Node and is_instance_valid(content):
			return content
	return node

## Apply the prop delta (`old_props` -> `new_props`) onto an existing/new node.
## NOTE: a *removed* plain prop (present last render, absent this render) is NOT reset to its default
## — Godot has no generic per-prop default to restore to without surprises. Treat props React-style:
## pass every prop you want set on every render; conditionally-applied props should toggle to an
## explicit value rather than being omitted. Events/refs/styles ARE cleaned up on removal. [audit #23]
static func apply_props(node: Node, old_props: Dictionary, new_props: Dictionary) -> void:
	# 1. Disconnect events that disappeared (skip entirely if the node has no events). [perf #4]
	if node.has_meta("__rui_events"):
		for k in old_props:   # iterate keys directly — no .keys() array allocation [perf]
			if _is_event(k) and not new_props.has(k):
				_disconnect_event(node, k)

	# 2. Apply new / changed props.
	for k in new_props:   # iterate keys directly — no .keys() array allocation [perf]
		if RESERVED.has(k):
			continue
		if _is_event(k):
			var old_cb = old_props.get(k)
			var new_cb = new_props[k]
			if old_cb != new_cb:
				_disconnect_event(node, k)
				_connect_event(node, k, new_cb)
			continue
		var val = new_props[k]
		# typeof guard: GDScript's `!=` RAISES on incompatible Variant operands (int vs String),
		# and a prop can legitimately change type across renders (e.g. enum int -> name string).
		if not old_props.has(k) or typeof(old_props[k]) != typeof(val) or old_props[k] != val:
			_set_prop(node, k, val)

	# 3. ref (called every commit so the latest node is exposed).
	if new_props.has("ref"):
		var r = new_props["ref"]
		if r is Callable and r.is_valid():
			r.call(node)
		elif r is Dictionary and r.has("current"):
			r["current"] = node

	# 4. style + USS-style `classes` — skip the whole machinery when neither side has either. [perf #4]
	var os = old_props.get("style")
	var ns = new_props.get("style")
	var oc = old_props.get("classes")
	var nc = new_props.get("classes")
	if os != null or ns != null or oc != null or nc != null:
		RUIStyle.apply(node, _effective_style(old_props), _effective_style(new_props))

	# 5. declarative item-model controls (stateful adapters) — dispatched through an extensible
	#    registry so userland can register adapters for custom controls (see register_item_adapter).
	_apply_item_model(node, old_props, new_props)

	# 6. custom drawing (draw_fn / redraw_key) — skip the machinery when neither side declares it. [perf]
	if new_props.has("draw_fn") or old_props.has("draw_fn"):
		_apply_custom_draw(node, old_props, new_props)

## Resolve a host element's effective style: merge the styles of its `classes` (left-to-right via
## RUIStyleSheet) then overlay its inline `style` (which wins). A plain dictionary merge — no CSS
## cascade/specificity (decision #3). Returns {} when there's nothing to apply.
static func _effective_style(props: Dictionary) -> Dictionary:
	var classes = props.get("classes")
	var inline = props.get("style")
	if classes == null and inline == null:
		return {}
	if classes == null:
		return inline if inline is Dictionary else {}
	var merged := {}
	if classes is Array:
		for c in classes:
			var cs = RUIStyleSheet.resolve(str(c))
			if cs is Dictionary:
				for k in cs:
					merged[k] = cs[k]
	if inline is Dictionary:
		for k in inline:
			merged[k] = inline[k]
	return merged

## Set a node property. Controlled text inputs are special-cased: setting `text` every
## render (from state) would reset the caret to 0 mid-typing, so we skip when the node's
## value already matches (the common controlled-input case) and otherwise preserve the
## caret. This is a general UX fix for any LineEdit/TextEdit driven by state.
static func _set_prop(node: Node, key: String, val) -> void:
	if key == "text" and node is LineEdit:
		var le := node as LineEdit
		if le.text == val:
			return
		var c := le.caret_column
		le.text = str(val)
		le.caret_column = mini(c, le.text.length())
		return
	if key == "text" and node is TextEdit:
		var te := node as TextEdit
		if te.text == val:
			return
		var ln := te.get_caret_line()
		var col := te.get_caret_column()
		te.text = str(val)
		te.set_caret_line(mini(ln, maxi(0, te.get_line_count() - 1)))
		te.set_caret_column(col)
		return
	node.set(key, val)

# Pre-0.9 React aliases -> what to write instead. NOT a compatibility shim (the aliases do NOT
# bind); consulted only by the unknown-signal warning so a stale callsite gets the exact rename
# instead of a mystery. Remove after one release. [0.9.0 naming loyalty]
const _RENAMED_EVENTS_090 := {
	"onClick": "onPressed",
	"onChange": "the control's real signal: onToggled / onItemSelected / onValueChanged / onTextChanged / onTabChanged",
	"onInput": "onTextChanged",
	"onSubmit": "onTextSubmitted",
	"onFocus": "onFocusEntered",
	"onBlur": "onFocusExited",
	"onPointerDown": "onButtonDown",
	"onPointerUp": "onButtonUp",
	"onPointerEnter": "onMouseEntered",
	"onPointerLeave": "onMouseExited",
	"onResize": "onResized",
}

## An attribute is an event handler if it uses the native on_<signal> convention OR the React
## camelCase convention (on + UpperCase…, e.g. onPressed/onValueChanged). Purely syntactic (no node needed)
## so the reconciler can classify props cheaply; signal resolution happens later in _resolve_signal.
static func _is_event(key: String) -> bool:
	if key.begins_with("on_"):
		return true
	return key.length() > 2 and key.begins_with("on") and _is_ascii_upper(key.unicode_at(2))

static func _is_ascii_upper(c: int) -> bool:
	return c >= 65 and c <= 90  # 'A'..'Z'

## Resolve an event prop key to the Godot signal name to connect on `node`:
##   • on_<signal>  -> "<signal>" verbatim (escape hatch to any signal)
##   • on<Pascal>   -> PascalCase->snake_case (onPressed -> pressed, onValueChanged -> value_changed)
static func _resolve_signal(node: Object, key: String) -> String:
	if key.begins_with("on_"):
		return key.substr(3)
	return _camel_to_snake(key.substr(2))  # strip "on"

static func _camel_to_snake(s: String) -> String:
	var out := ""
	for i in s.length():
		var c := s.unicode_at(i)
		if c >= 65 and c <= 90:  # 'A'..'Z'
			if i > 0:
				out += "_"
			out += char(c + 32)
		else:
			out += char(c)
	return out

static func _connect_event(node: Node, key: String, cb) -> void:
	if not (cb is Callable) or not cb.is_valid():
		return
	var sig := _resolve_signal(node, key)
	if sig == "" or not node.has_signal(sig):
		if _RENAMED_EVENTS_090.has(key):
			push_warning("[reactive_ui_toolkit] event prop '%s' was renamed in 0.9.0 -- use %s (see MIGRATION-0.9.md)." % [key, _RENAMED_EVENTS_090[key]])
		else:
			push_warning("[reactive_ui_toolkit] %s has no signal for event prop '%s' (resolved '%s')." % [node.get_class(), key, sig])
		return
	if not node.is_connected(sig, cb):   # guard against a stale meta/connection divergence [audit C1]
		node.connect(sig, cb)
	var m: Dictionary = node.get_meta("__rui_events", {})
	m[key] = { "cb": cb, "sig": sig }   # store the RESOLVED signal so disconnect is node-independent
	node.set_meta("__rui_events", m)

static func _disconnect_event(node: Node, key: String) -> void:
	var m: Dictionary = node.get_meta("__rui_events", {})
	if not m.has(key):
		return
	var rec: Dictionary = m[key]
	var cb = rec.get("cb")
	var sig: String = rec.get("sig", "")
	if cb is Callable and sig != "" and node.is_connected(sig, cb):
		node.disconnect(sig, cb)
	m.erase(key)
	node.set_meta("__rui_events", m)

## Custom drawing. `draw_fn` is a Callable(canvas_item) that issues the node's `draw_*` calls; it runs
## during the node's `draw` signal. A register-once trampoline reads the LATEST `draw_fn` from meta, so
## a fresh closure each render never re-subscribes — it repaints (`queue_redraw`) only when the callback
## identity OR `redraw_key` changes (the Godot analogue of Unity's OnGenerateVisualContent + RedrawKey).
static func _apply_custom_draw(node: Node, old_props: Dictionary, new_props: Dictionary) -> void:
	var new_fn = new_props.get("draw_fn")
	if new_fn is Callable and new_fn.is_valid():
		if not (node is CanvasItem):
			push_warning("[reactive_ui_toolkit] 'draw_fn' ignored: %s is not a CanvasItem." % node.get_class())
			return
		node.set_meta("__rui_draw", new_fn)
		if not node.has_meta("__rui_draw_tramp"):
			# Register the trampoline exactly once; it always reads the current draw_fn from meta.
			var tramp := func() -> void:
				var d = node.get_meta("__rui_draw", null)
				if d is Callable and d.is_valid():
					d.call(node)
			node.connect("draw", tramp)
			node.set_meta("__rui_draw_tramp", tramp)
		# Repaint when the callback identity changed OR redraw_key changed.
		if new_fn != old_props.get("draw_fn") or new_props.get("redraw_key") != old_props.get("redraw_key"):
			(node as CanvasItem).queue_redraw()
	elif old_props.has("draw_fn"):
		_remove_custom_draw(node)

## Drop a node's custom drawing: disconnect the trampoline, clear the meta, and repaint to erase it.
static func _remove_custom_draw(node: Node) -> void:
	if node.has_meta("__rui_draw_tramp"):
		var tramp = node.get_meta("__rui_draw_tramp")
		if tramp is Callable and node.is_connected("draw", tramp):
			node.disconnect("draw", tramp)
		node.remove_meta("__rui_draw_tramp")
	if node.has_meta("__rui_draw"):
		node.remove_meta("__rui_draw")
	if node is CanvasItem:
		(node as CanvasItem).queue_redraw()

# --------------------------------------------------------------------------
# Declarative item-model adapters (stateful controls) + extensible registry
# --------------------------------------------------------------------------
# Each adapter rebuilds a control's items when the `items` prop changes while preserving runtime
# state (selection / current tab / expansion) by item IDENTITY — the "tracker" pattern. The
# registry lets userland plug adapters for custom controls without touching this file.

static var _item_adapters: Array = []   # [ { "match": Callable(node)->bool, "apply": Callable(node, old, new) } ]

## Register a custom item-model adapter. `match_fn(node)->bool` selects nodes; `apply_fn(node,
## old_props, new_props)` mutates them. User adapters take precedence over the built-ins.
static func register_item_adapter(match_fn: Callable, apply_fn: Callable) -> void:
	_item_adapters.append({ "match": match_fn, "apply": apply_fn })

static func _ensure_builtin_adapters() -> void:
	if not _item_adapters.is_empty():
		return
	# Order: most-specific first. OptionButton/MenuButton are Buttons; TabBar/ItemList/Tree are Controls.
	_item_adapters.append({ "match": func(n): return n is ItemList, "apply": _apply_item_list })
	_item_adapters.append({ "match": func(n): return n is Tree, "apply": _apply_tree })
	_item_adapters.append({ "match": func(n): return n is TabBar, "apply": _apply_tab_bar })
	_item_adapters.append({ "match": func(n): return n is OptionButton, "apply": _apply_option_button })
	_item_adapters.append({ "match": func(n): return n is PopupMenu, "apply": _apply_popup_menu })

static func _apply_item_model(node: Node, old_props: Dictionary, new_props: Dictionary) -> void:
	_ensure_builtin_adapters()
	for a in _item_adapters:
		if a["match"].call(node):
			a["apply"].call(node, old_props, new_props)
			return

## ItemList: declarative `items` prop (Array of String or { text, icon, disabled }).
## Rebuilds only when the items array changes, preserving the user's selection by index
## (the "tracker" pattern — runtime state survives a re-render). Wire selection changes
## with `onItemSelected` / `onItemActivated`.
static func _apply_item_list(node: ItemList, old_props: Dictionary, new_props: Dictionary) -> void:
	if not new_props.has("items"):
		return
	var items: Array = new_props["items"]
	var old_items: Array = old_props.get("items", [])
	if items == old_items:
		return
	# Preserve selection by item IDENTITY (id, else text/value) — not raw index — so it survives
	# reordering/insertion, and honor single vs multi select_mode. Count per id (a MULTISET) so when
	# several items share an id/text we re-select AT MOST the original number, not every duplicate. [audit M2]
	var selected_ids := {}
	for s in node.get_selected_items():
		if s < old_items.size():
			var iid = _item_id(old_items[s])
			selected_ids[iid] = selected_ids.get(iid, 0) + 1
	var single := node.select_mode == ItemList.SELECT_SINGLE
	node.clear()
	for it in items:
		var idx: int
		if it is Dictionary:
			idx = node.add_item(str(it.get("text", "")), it.get("icon"), it.get("selectable", true))
			if it.get("disabled", false):
				node.set_item_disabled(idx, true)
		else:
			idx = node.add_item(str(it))
		var iid2 = _item_id(it)
		if selected_ids.get(iid2, 0) > 0:
			node.select(idx, single)
			selected_ids[iid2] -= 1

static func _item_id(it):
	if it is Dictionary:
		return it.get("id", str(it.get("text", "")))
	return str(it)

## TabBar: declarative `items` (Array of String or { text, icon, disabled }). Rebuilds on change,
## preserving the current tab by item IDENTITY. Wire tab changes with `onTabChanged` /
## `onTabSelected`.
static func _apply_tab_bar(node: TabBar, old_props: Dictionary, new_props: Dictionary) -> void:
	if not new_props.has("items"):
		return
	var items: Array = new_props["items"]
	var old_items: Array = old_props.get("items", [])
	if items == old_items:
		return
	var cur_id = null
	if node.current_tab >= 0 and node.current_tab < old_items.size():
		cur_id = _item_id(old_items[node.current_tab])
	node.clear_tabs()
	var restore := -1
	for it in items:
		node.add_tab(str(it.get("text", "")) if it is Dictionary else str(it))
		var idx := node.tab_count - 1
		if it is Dictionary:
			if it.get("icon") != null:
				node.set_tab_icon(idx, it.get("icon"))
			if it.get("disabled", false):
				node.set_tab_disabled(idx, true)
		if restore == -1 and cur_id != null and _item_id(it) == cur_id:
			restore = idx   # first match — deterministic when several tabs share text/id [audit]
	if restore >= 0:
		node.current_tab = restore

## OptionButton: declarative `items` (Array of String or { text, icon, disabled, id }). Rebuilds on
## change, preserving the selection by item IDENTITY. Wire changes with `onItemSelected`.
static func _apply_option_button(node: OptionButton, old_props: Dictionary, new_props: Dictionary) -> void:
	if not new_props.has("items"):
		return
	var items: Array = new_props["items"]
	var old_items: Array = old_props.get("items", [])
	if items == old_items:
		return
	var sel_id = null
	if node.selected >= 0 and node.selected < old_items.size():
		sel_id = _item_id(old_items[node.selected])
	node.clear()
	var restore := -1
	for it in items:
		if it is Dictionary:
			node.add_item(str(it.get("text", "")), int(it.get("id", -1)) if it.has("id") else -1)
		else:
			node.add_item(str(it))
		var idx := node.item_count - 1
		if it is Dictionary:
			if it.get("icon") != null:
				node.set_item_icon(idx, it.get("icon"))
			if it.get("disabled", false):
				node.set_item_disabled(idx, true)
		if restore == -1 and sel_id != null and _item_id(it) == sel_id:
			restore = idx   # first match — deterministic when several items share text/id [audit]
	if restore >= 0:
		node.select(restore)

## PopupMenu: declarative `items` (Array of String or { text, id, disabled, checkable, checked,
## separator }). Stateless rebuild (menus carry no persistent selection). Wire with `onIdPressed` (native: `on_id_pressed`).
static func _apply_popup_menu(node: PopupMenu, old_props: Dictionary, new_props: Dictionary) -> void:
	if not new_props.has("items"):
		return
	var items: Array = new_props["items"]
	var old_items: Array = old_props.get("items", [])
	if items == old_items:
		return
	node.clear()
	for it in items:
		if it is Dictionary:
			if it.get("separator", false):
				node.add_separator(str(it.get("text", "")))
				continue
			if it.get("checkable", false):
				node.add_check_item(str(it.get("text", "")), int(it.get("id", -1)) if it.has("id") else -1)
			else:
				node.add_item(str(it.get("text", "")), int(it.get("id", -1)) if it.has("id") else -1)
			var idx := node.item_count - 1
			if it.get("disabled", false):
				node.set_item_disabled(idx, true)
			if it.has("checked"):
				node.set_item_checked(idx, bool(it["checked"]))
		else:
			node.add_item(str(it))

## Warn (once per node) when a single/limited-child container is given too many children —
## Godot lays out only the first (or first two), so excess children silently break. [audit M1]
static func warn_capacity(node: Node, count: int) -> void:
	if count <= 1 or node.has_meta("__rui_capw"):
		return
	var limit := -1
	if node is SplitContainer:
		limit = 2
	elif node is ScrollContainer or node is AspectRatioContainer or node is CenterContainer \
			or node is PanelContainer or node is MarginContainer or node.is_class("FoldableContainer"):
		limit = 1
	if limit > 0 and count > limit:
		push_warning("[reactive_ui_toolkit] %s lays out at most %d child(ren) but got %d — wrap them in a VBox/HBox/Grid. (warned once)" % [node.get_class(), limit, count])
		node.set_meta("__rui_capw", true)

## Tree: declarative hierarchical `items` (Array of { id, text, children:[...], collapsed? }).
## Rebuilds on change but PRESERVES the user's expand/collapse state and selection by `id`
## (the tracker pattern) — so re-rendering a tree doesn't reset what the user expanded.
## Wire selection/activation with `onItemSelected` / `onItemActivated`.
static func _apply_tree(node: Tree, old_props: Dictionary, new_props: Dictionary) -> void:
	if not new_props.has("items"):
		return
	var items: Array = new_props["items"]
	var cols: int = int(new_props.get("columns", 1))
	if node.columns != cols:
		node.columns = cols
	if new_props.has("hide_root"):
		node.hide_root = new_props["hide_root"]
	if items == old_props.get("items") and cols == int(old_props.get("columns", 1)):
		return

	# Capture runtime state (expansion + selection) keyed by id before rebuilding.
	var expanded := {}
	var existing_root := node.get_root()
	if existing_root != null:
		_tree_capture(existing_root, expanded)
	var selected_id = null
	var sel := node.get_selected()
	if sel != null:
		selected_id = sel.get_metadata(0)

	node.clear()
	var groot := node.create_item()
	for it in items:
		_tree_build(node, groot, it, expanded)

	if selected_id != null:
		var found = _tree_find_by_id(node.get_root(), selected_id)
		if found != null:
			found.select(0)

static func _tree_capture(item: TreeItem, out: Dictionary) -> void:
	var id = item.get_metadata(0)
	if id != null:
		out[id] = not item.collapsed
	for child in item.get_children():
		_tree_capture(child, out)

static func _tree_build(tree: Tree, parent: TreeItem, data, expanded: Dictionary) -> void:
	var ti := tree.create_item(parent)
	var id = data.get("id") if data is Dictionary else null
	ti.set_text(0, str(data.get("text", "")) if data is Dictionary else str(data))
	if id != null:
		ti.set_metadata(0, id)
	var collapsed := bool(data.get("collapsed", false)) if data is Dictionary else false
	if id != null and expanded.has(id):
		collapsed = not expanded[id]   # restore captured expansion
	ti.collapsed = collapsed
	if data is Dictionary and data.has("children"):
		for child in data["children"]:
			_tree_build(tree, ti, child, expanded)

static func _tree_find_by_id(item: TreeItem, id):
	if item == null:
		return null
	if item.get_metadata(0) == id:
		return item
	for child in item.get_children():
		var f = _tree_find_by_id(child, id)
		if f != null:
			return f
	return null
