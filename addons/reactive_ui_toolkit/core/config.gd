class_name RUIConfig
extends RefCounted
## Global reactive-UI configuration.
##
## Time-slicing is OFF by default — synchronous renders are simplest and fast for normal
## UIs. Turn it on for very large trees that would otherwise stutter on a big update: the
## render phase is then chunked across frames (commit stays atomic). Ports the frame-budget
## idea from ReactiveUIToolKit's RenderScheduler.
##
##   RUIConfig.time_slicing = true
##   RUIConfig.frame_budget_ms = 8.0   # work per frame before parking until the next one

static var time_slicing := false
static var frame_budget_ms := 8.0

## Host-node pool (GO-05): recycle childless leaf Controls across keyed-list churn instead of
## queue_free + ClassDB.instantiate. On by default — pure win for churn-heavy dynamic lists,
## and a no-op for static UIs (nothing churns). Exposed so it can be A/B-measured or disabled.
static var host_node_pool := true

## Dev diagnostics (Phase 7.0). Default ON in debug builds, OFF in exported games — they
## push_warning/push_error to surface misuse loudly while developing, and degrade silently
## in release (the port never throws catchable exceptions; GDScript can't).
##   enable_hook_validation     — hook-order mismatch detection (hooks in if/loops desync slots)
##   enable_strict_diagnostics  — state-update-during-render warning
static var enable_hook_validation := OS.is_debug_build()
static var enable_strict_diagnostics := OS.is_debug_build()
