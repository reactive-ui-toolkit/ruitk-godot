class_name RUISignals
extends RefCounted
## Process-wide string-keyed shared signal registry (Phase 7.1). Mirrors ReactiveUIToolKit's signal
## factory: `get_or_create(key, initial)` lazily creates ONE shared RUISignal per key, so any
## component anywhere in the tree (or across scenes) that reads the same key sees the same store.
## Subscribe with `Hooks.useSignalKey(key, initial)`.
##
## LIFETIME: the registry is a static (process-global) Dictionary; keyed signals OUTLIVE the
## components that read them — that is the point (shared app state). Call `clear()` on a full
## game/session reset (e.g. returning to the main menu) to drop keyed state; otherwise it persists
## for the process lifetime, matching the Unity reference's lazy-init registry.
##
## EQUALITY: RUISignal change-detection is reference-aware (Object.is): value types by value,
## reference types (Array/Dictionary/Object) by IDENTITY — so set a freshly-built collection to
## notify. In-place mutation of the same reference will NOT notify; pass a per-subscriber `comparer`
## to useSignalKey if you must detect in-place mutation.

static var _signals: Dictionary = {}   ## key:String -> RUISignal

## The shared signal for `key`, created with `initial` on first access (initial ignored thereafter).
static func get_or_create(key: String, initial = null) -> RUISignal:
	var sig: RUISignal = _signals.get(key)
	if sig == null:
		sig = RUISignal.new(initial)
		_signals[key] = sig
	return sig

static func try_get(key: String) -> RUISignal:
	return _signals.get(key)

static func has(key: String) -> bool:
	return _signals.has(key)

## Drop all keyed signals (subscribers are NOT notified). Call on a full session reset.
static func clear() -> void:
	_signals.clear()
