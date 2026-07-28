class_name RUIHistory
extends RefCounted
## In-memory navigation history (the engine-agnostic core of the router). Holds a stack of
## RUIRouterLocation entries + an index, notifies listeners on change, and supports navigation
## blockers. Faithful port of ReactiveUIToolKit's MemoryHistory.
##
## Blocker convention (RR-correct, internally consistent): a blocker is
## `func(from: RUIRouterLocation, to: RUIRouterLocation) -> bool` that returns TRUE to BLOCK
## (veto) the transition and FALSE to allow it. (The Unity reference's AllowTransition/UsePrompt
## pair is self-inconsistent; we standardize on "true = block" to match react-router's useBlocker.)

var _entries: Array = []          # Array[RUIRouterLocation]
var _index := -1
var _listeners: Array = []        # Array[Callable(loc)]  — yields RUIRouterLocation
var _blockers: Array = []         # Array[Callable(from, to) -> bool]

func _init(initial := "/") -> void:
	_entries = []
	_index = -1
	push(initial)

# --- current location ---

func location_obj() -> RUIRouterLocation:
	if _index < 0 or _index >= _entries.size():
		return RUIRouterLocation.parse("/")
	return _entries[_index]

## Legacy/back-compat: the current location as a plain path String.
func location() -> String:
	return location_obj().path

func entry_count() -> int:
	return _entries.size()

func index() -> int:
	return _index

# --- relative navigation ---

func can_go(delta: int) -> bool:
	if delta == 0 or _entries.is_empty():
		return false
	var target := _index + delta
	return target >= 0 and target < _entries.size()

func can_go_back() -> bool:
	return can_go(-1)

func can_go_forward() -> bool:
	return can_go(1)

func go(delta: int) -> void:
	if not can_go(delta):
		return
	var target := _index + delta
	var next: RUIRouterLocation = _entries[target]
	var previous := location_obj()
	if not _allow_transition(previous, next):
		return
	_index = target
	_notify(location_obj())

func back() -> void:
	go(-1)

func forward() -> void:
	go(1)

# --- mutating navigation ---

func push(path: String, state = null) -> void:
	var loc := RUIRouterLocation.parse(path, state)
	var previous := location_obj() if _index >= 0 else null
	if previous != null and not _allow_transition(previous, loc):
		return
	if _index < _entries.size() - 1:
		_entries = _entries.slice(0, _index + 1)
	_entries.append(loc)
	_index = _entries.size() - 1
	_notify(loc)

func replace(path: String, state = null) -> void:
	var loc := RUIRouterLocation.parse(path, state)
	var previous := location_obj() if _index >= 0 else null
	if previous != null and not _allow_transition(previous, loc):
		return
	if _index < 0:
		_entries.append(loc)
		_index = 0
	else:
		_entries[_index] = loc
	_notify(loc)

# --- subscriptions ---

## Listen for location changes. The callback receives a RUIRouterLocation, and is invoked once
## IMMEDIATELY with the current location (port of MemoryHistory.Listen). The immediate replay
## resynchronizes a late subscriber — e.g. when a child's redirect effect runs before the
## provider's own subscribe effect, the provider still catches the already-applied location.
## Returns an unsubscribe Callable. (The provider seeds state from the same location object, so
## the replay is a no-op equality-bailout on a plain mount.)
func listen(cb: Callable) -> Callable:
	_listeners.append(cb)
	cb.call(location_obj())
	return func(): _listeners.erase(cb)

## Legacy: subscribe with a String-path callback (kept for back-compat with pre-7.8 callers).
func subscribe(cb: Callable) -> Callable:
	var wrapped := func(loc):
		cb.call(loc.path if loc is RUIRouterLocation else str(loc))
	_listeners.append(wrapped)
	return func(): _listeners.erase(wrapped)

## Register a navigation blocker. Returns an unsubscribe Callable.
func register_blocker(blocker: Callable) -> Callable:
	if not (blocker is Callable):
		return func(): pass
	_blockers.append(blocker)
	return func(): _blockers.erase(blocker)

# --- internals ---

func _allow_transition(from, to) -> bool:
	for b in _blockers.duplicate():
		if b is Callable and b.is_valid():
			if b.call(from, to) == true:   # true == veto the transition
				return false
	return true

func _notify(loc) -> void:
	for s in _listeners.duplicate():
		if s is Callable and s.is_valid():
			s.call(loc)
