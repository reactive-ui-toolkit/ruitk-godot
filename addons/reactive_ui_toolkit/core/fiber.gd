class_name RUIFiber
extends RefCounted
## A node in the persistent work tree. Current and work-in-progress fibers are paired
## via `alternate` (double buffering). Ports ReactiveUIToolKit's FiberNode.
##
## Effect flags (a bitmask in `effect_tag`) record what the commit phase must do.
## The fiber tree is NESTED (components/fragments own no host node); the real Godot
## node tree is the flattened projection of it.

enum Tag { FUNCTION, HOST, FRAGMENT, PORTAL, ERROR_BOUNDARY, ROOT }

const EFFECT_NONE := 0
const EFFECT_PLACEMENT := 1
const EFFECT_UPDATE := 2
const EFFECT_DELETION := 4
const EFFECT_LAYOUT := 8
const EFFECT_PASSIVE := 16
const EFFECT_PORTAL_RETARGET := 32

# --- tree ---
var parent: RUIFiber = null
var child: RUIFiber = null
var sibling: RUIFiber = null
var index: int = 0

# --- identity ---
var tag: int = Tag.HOST
var key = null
var type: String = ""             ## host class name
var component: Callable           ## function-component render fn

# --- props ---
var props = null                  ## committed props (Dictionary) or null = NEVER rendered
var pending_props: Dictionary = {}
var input_children: Array = []    ## child vnodes to reconcile

# --- cached apply plan (inline-cache for the commit/apply hot path) [perf] ---
# Classifying each prop (event / ref / style / item-model / plain) and checking unused features
# is recomputed-once and cached here, so a plain element's per-frame apply is just diff+write.
var apply_size: int = -1          ## props.size() the plan was built for; -1 = rebuild
var apply_special: bool = false   ## STICKY: ever had events/ref/style/item-model -> use generic apply
var apply_plain: Array = []       ## the plain (non-reserved, non-event) prop keys to diff+write

# --- host ---
var node: Node = null

# --- portal ---
var portal_target: Node = null

# --- error boundary ---
var eb_active := false
var eb_showing_fallback := false
var eb_last_error = null
var eb_reset_key = null
var eb_fallback = null            ## RUIVNode
var eb_handler: Callable
var eb_children: Array = []

# --- reconciliation / double buffer ---
var alternate: RUIFiber = null
var effect_tag: int = EFFECT_NONE
var next_effect: RUIFiber = null  ## singly-linked effect list (post-order)
var deletions: Array = []         ## Array[RUIFiber] removed this render
## Transient mark for the full-keyed reconcile mark-and-sweep (GO-08): set true when an
## old fiber is matched to a vnode this pass, so the trailing sweep deletes only unmatched
## fibers WITHOUT a per-frame `matched` Dictionary. Reset at the top of each full-keyed pass;
## per-fiber (not key-keyed) so duplicate user keys are handled exactly as before.
var matched_pass := false

# --- context ---
var provided_context = null       ## Dictionary or null
var reads_context := false

# --- bailout ---
var has_pending_update := false
var subtree_has_updates := false

# --- function-component state (RUIComponentState, SHARED across alternates) ---
var state = null

func is_function() -> bool: return tag == Tag.FUNCTION
func is_host() -> bool: return tag == Tag.HOST
func is_fragment() -> bool: return tag == Tag.FRAGMENT
func is_portal() -> bool: return tag == Tag.PORTAL
func is_error_boundary() -> bool: return tag == Tag.ERROR_BOUNDARY
func is_root() -> bool: return tag == Tag.ROOT

## True if this fiber can be reused for `vnode` (same kind + type/component).
func matches(vnode: RUIVNode) -> bool:
	match vnode.kind:
		RUIVNode.Kind.HOST:
			return tag == Tag.HOST and type == vnode.type
		RUIVNode.Kind.FUNCTION:
			return tag == Tag.FUNCTION and component == vnode.component
		RUIVNode.Kind.FRAGMENT:
			return tag == Tag.FRAGMENT
		RUIVNode.Kind.PORTAL:
			return tag == Tag.PORTAL
		RUIVNode.Kind.ERROR_BOUNDARY:
			return tag == Tag.ERROR_BOUNDARY
	return false

static func tag_for_vnode(vnode: RUIVNode) -> int:
	match vnode.kind:
		RUIVNode.Kind.HOST: return Tag.HOST
		RUIVNode.Kind.FUNCTION: return Tag.FUNCTION
		RUIVNode.Kind.FRAGMENT: return Tag.FRAGMENT
		RUIVNode.Kind.PORTAL: return Tag.PORTAL
		RUIVNode.Kind.ERROR_BOUNDARY: return Tag.ERROR_BOUNDARY
	return Tag.HOST
