class_name RuitkConfig
extends RefCounted
## Global reactive-UI configuration.
##
## Time-slicing is OFF by default — synchronous renders are simplest and fast for normal
## UIs. Turn it on for very large trees that would otherwise stutter on a big update: the
## render phase is then chunked into quantum-sized slices driven by the four-lane
## RuitkScheduler (commit stays atomic). Two knobs, ported from the Unity leg
## (FiberReconciler.TimeSliceMs + RenderScheduler.frameBudgetMs):
##
##   time_slice_ms   — the render-phase QUANTUM: the work loop checks elapsed time AFTER
##                     each completed unit (one fiber) and yields past this; a long single
##                     unit overruns (cooperative — no preemption).
##   frame_budget_ms — the SCHEDULER's per-frame budget, cumulative across all lanes in
##                     one frame pump; a 2 ms slice can run twice inside a 4 ms budget.
##                     `false` time_slicing bypasses the scheduler entirely (synchronous
##                     single-pass render per update), so this is inert until slicing is on.
##
##   RuitkConfig.time_slicing = true

static var time_slicing := false
static var time_slice_ms := 2.0
static var frame_budget_ms := 4.0

## Host-node pool (GO-05): recycle childless leaf Controls across keyed-list churn instead of
## queue_free + ClassDB.instantiate. On by default — pure win for churn-heavy dynamic lists,
## and a no-op for static UIs (nothing churns). Exposed so it can be A/B-measured or disabled.
static var host_node_pool := true

## Strict mode (family knob; default OFF, explicit opt-in). When effective, every component
## render fn runs TWICE per pass with the FIRST result discarded — the React-StrictMode
## impure-render flusher (hidden state in a render body surfaces as a visible double
## effect). Effects are NOT double-invoked (the hook slots re-walk in place on the second
## invoke) and diagnostics count the render ONCE. Read via `strict_mode_effective()`.
static var strict_mode := false

## The read side of `strict_mode`: forced OFF in exported release builds regardless of the
## stored setting — the family contract's release force-off, the exact shape of the Unreal
## leg's IsStrictModeEnabled ("never in shipping, regardless of the CVar",
## RuitkCoreMisc.cpp). The stored setting/static round-trips untouched; only the read gates.
static func strict_mode_effective() -> bool:
	return strict_mode and OS.is_debug_build()

## Environment label (family knob 10; default "auto"). "auto" resolves to "development"
## in the editor and debug builds and "production" in exported release builds;
## "development"/"production" pass through explicitly. This is a READ-ONLY surface for
## USER components (`RuitkConfig.environment_resolved()` — e.g. gate a debug overlay);
## the library itself NEVER branches on it (§0 knob 10 — enforced by grep in review).
## The Unity analog surfaces the same label through the host context (RootRenderer's
## Environment["env"]).
static var environment := "auto"

## The resolved label: always "development" or "production". Unrecognized stored
## values resolve like "auto" (the settings bridge's unknown-value precedent).
static func environment_resolved() -> String:
	match environment:
		"development", "production":
			return environment
		_:
			return "development" if OS.is_debug_build() else "production"

## Dev diagnostics (Phase 7.0). Default ON in debug builds, OFF in exported games — they
## push_warning/push_error to surface misuse loudly while developing, and degrade silently
## in release (the port never throws catchable exceptions; GDScript can't).
##   enable_hook_validation     — hook-order mismatch detection (hooks in if/loops desync slots)
##   enable_strict_diagnostics  — state-update-during-render warning
static var enable_hook_validation := OS.is_debug_build()
static var enable_strict_diagnostics := OS.is_debug_build()
