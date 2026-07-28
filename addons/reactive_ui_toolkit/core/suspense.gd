class_name RUISuspense
extends RefCounted
## Declarative Suspense boundary (Phase 7.4). Shows `fallback` until a readiness condition is met,
## then renders `children`. GDScript has NO throw-to-suspend (React's mechanism), so this is a
## function component driven by either an awaited Godot Signal or a per-frame poll — not an exception.
##
## Usage (via V.suspense):
##   V.suspense({ "fallback": V.Label({"text":"Loading…"}), "ready_signal": res_loaded_signal },
##              [ <the real content> ])
##   V.suspense({ "fallback": …, "is_ready": func(): return ResourceLoader.has_cached(path) }, [ … ])
##
## props:
##   fallback     : RUIVNode shown while not ready (optional; renders nothing if omitted)
##   ready_signal : a Godot Signal — awaited once; readiness flips when it fires
##   is_ready     : Callable() -> bool — checked once immediately, then polled each frame if no signal

static func suspense_fn(props: Dictionary, children: Array):
	var ready_box: Array = Hooks.useState(false)
	var ready: bool = ready_box[0]
	var set_ready: Callable = ready_box[1]
	Hooks.useEffect(func():
		if ready:
			return func(): pass
		var is_ready_cb = props.get("is_ready")
		var ready_signal = props.get("ready_signal")
		# already satisfied? become ready synchronously.
		if is_ready_cb is Callable and is_ready_cb.call():
			set_ready.call(true)
			return func(): pass
		var token := { "cancelled": false }
		if ready_signal is Signal:
			_drive_signal(ready_signal, set_ready, token)
		elif is_ready_cb is Callable:
			_drive_poll(is_ready_cb, set_ready, token)
		return func(): token["cancelled"] = true   # stop the driver on unmount / dep change
	# Depend on the readiness source (and `ready`) so a parent that swaps ready_signal/is_ready tears
	# down the stale driver and re-subscribes to the new one. (Pass a STABLE is_ready, e.g. via
	# useCallback, to avoid re-subscribing every render.) [audit]
	, [props.get("ready_signal"), props.get("is_ready"), ready])
	if ready:
		return children
	var fb = props.get("fallback")
	return fb if fb != null else []

# Await the readiness signal once, then flip ready (unless the boundary was torn down meanwhile).
static func _drive_signal(sig: Signal, set_ready: Callable, token: Dictionary) -> void:
	await sig
	if not token["cancelled"]:
		set_ready.call(true)

# Poll the readiness Callable each frame until it returns true (or the boundary is torn down).
static func _drive_poll(is_ready: Callable, set_ready: Callable, token: Dictionary) -> void:
	var tree := Engine.get_main_loop()
	if not (tree is SceneTree):
		return
	while not token["cancelled"]:
		await (tree as SceneTree).process_frame
		if token["cancelled"]:
			return
		if is_ready.call():
			set_ready.call(true)
			return
