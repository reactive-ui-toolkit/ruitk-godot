class_name RuitkFail
extends RefCounted
## Cooperative render-error latch (family parity P3; ports the Unreal leg's D-10 design,
## RuitkCoreMisc.h/.cpp). GDScript has no exceptions, so there is no throw path: a failing
## render CALLS `RuitkFail.render(reason)` and returns whatever it can (null is fine); the
## reconciler checks the latch after each component render and unwinds the WIP subtree to
## the nearest error boundary (safe pre-commit — double buffering keeps the committed tree
## intact until the rebuilt pass commits the fallback). A real GDScript crash (bad index,
## call on null) still cannot be auto-caught — the latch is the cooperative substitute.

static var _reason = null   ## String, or null when no failure is latched

## Signal "this render failed". Call from inside a component's render fn and return early;
## the nearest enclosing `V.error_boundary` shows its `fallback` and receives `reason` via
## its `on_error` Callable. First failure wins — nested failures raised while the first one
## unwinds are fallout and keep the original reason.
static func render(reason: String) -> void:
	if _reason == null:   # first failure wins (nested failures are fallout)
		_reason = reason

## Reconciler-side: consume the latch — returns the reason String, or null when no failure
## is pending. Called after every component render (per-component, immediately).
static func _consume():
	var out = _reason
	_reason = null
	return out
