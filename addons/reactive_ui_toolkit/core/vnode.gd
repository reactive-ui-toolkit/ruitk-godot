class_name RUIVNode
extends RefCounted
## A virtual node — a lightweight, immutable *description* of a piece of UI, thrown
## away and rebuilt every render. The reconciler diffs vnodes against the persistent
## fiber tree. Mirrors ReactiveUIToolKit's VirtualNode and its five tags.

enum Kind { HOST, FUNCTION, FRAGMENT, PORTAL, ERROR_BOUNDARY }

var kind: int = Kind.HOST
var type: String = ""            ## Godot class name for HOST (e.g. "Button").
var component: Callable          ## (props, children) -> vnode|Array for FUNCTION.
var props: Dictionary = {}       ## host props, "style", "on_*" events, "ref", "key".
var children: Array = []         ## Array[RUIVNode].
var key = null                   ## stable identity for keyed reconciliation.
var portal_target: Node = null   ## mount target for PORTAL.

func is_component() -> bool: return kind == Kind.FUNCTION
func is_host() -> bool: return kind == Kind.HOST

static func make_host(p_type: String, p_props, p_children, p_key = null) -> RUIVNode:
	var n := RUIVNode.new()
	n.kind = Kind.HOST
	n.type = p_type
	n.props = p_props if p_props != null else {}
	n.children = p_children if p_children != null else []
	n.key = p_key
	return n

static func make_component(p_component: Callable, p_props, p_children, p_key = null) -> RUIVNode:
	var n := RUIVNode.new()
	n.kind = Kind.FUNCTION
	n.component = p_component
	n.props = p_props if p_props != null else {}
	n.children = p_children if p_children != null else []
	n.key = p_key
	return n

static func make_fragment(p_children, p_key = null) -> RUIVNode:
	var n := RUIVNode.new()
	n.kind = Kind.FRAGMENT
	n.children = p_children if p_children != null else []
	n.key = p_key
	return n

static func make_portal(p_target: Node, p_children, p_key = null) -> RUIVNode:
	var n := RUIVNode.new()
	n.kind = Kind.PORTAL
	n.portal_target = p_target
	n.children = p_children if p_children != null else []
	n.key = p_key
	return n

static func make_error_boundary(p_props, p_children, p_key = null) -> RUIVNode:
	var n := RUIVNode.new()
	n.kind = Kind.ERROR_BOUNDARY
	n.props = p_props if p_props != null else {}
	n.children = p_children if p_children != null else []
	n.key = p_key
	return n
