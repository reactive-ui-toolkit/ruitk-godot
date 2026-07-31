class_name RuitkDiagnostics
extends RefCounted
## Opt-in render/commit metrics. Toggle `RuitkDiagnostics.enabled = true`, then read the
## counters or `report()`. The reconciler feeds these. Analogue of ReactiveUIToolKit's
## diagnostics / WhyDidYouRender (lightweight counter form).

static var enabled := false

## Diagnostic message capture (Phase 7.0). When `capture` is on, the hook validators record their
## messages here (in addition to push_error/push_warning) so headless tests can assert them.
static var capture := false
static var messages: Array[String] = []

static func emit(msg: String) -> void:
	if capture:
		messages.append(msg)

static func clear_messages() -> void:
	messages.clear()

## Trace ladder (family knob 8; mirrors the Unity leg's DiagnosticsConfig.TraceLevel).
## NONE emits nothing; BASIC = STRUCTURAL events only (placements, deletions, node
## replacements, commit summaries); VERBOSE = Basic + per-element/per-hook detail
## (updates, portal retargets, component render entries, hook slots).
enum TraceLevel { NONE, BASIC, VERBOSE }
static var trace_level := TraceLevel.NONE

## Independent diff-tracing switch (family knob 9): reconciler diff-DECISION logs
## (bailout taken/skipped, reuse-vs-replace, keyed-list match decisions). OR
## semantics — the legacy-Unity contract: a diff site fires when
## `diff_tracing or trace_level == TraceLevel.VERBOSE` (Verbose alone lights it;
## diff_tracing alone lights it with the structural channel dark).
##
## Gates, spelled inline at every emitting site (hot-path discipline — the cheap
## enum/bool compare comes FIRST, message formatting only after):
##   structural = trace_level != TraceLevel.NONE
##   detail     = trace_level == TraceLevel.VERBOSE
##   diff       = diff_tracing or trace_level == TraceLevel.VERBOSE
static var diff_tracing := false

## Trace-channel emission: prints (the Debug.Log analog) and mirrors into `messages`
## when `capture` is on so headless tests can assert trace output. Callers gate BEFORE
## formatting the message — this helper never checks the level itself.
static func trace(msg: String) -> void:
	print(msg)
	if capture:
		messages.append(msg)

static var renders := 0       ## component render-fn invocations (excludes bailouts)
static var commits := 0       ## commit passes
static var placements := 0    ## host nodes inserted
static var updates := 0       ## host nodes prop-diffed
static var deletions := 0     ## subtrees removed

static func reset() -> void:
	renders = 0
	commits = 0
	placements = 0
	updates = 0
	deletions = 0

static func on_render() -> void: if enabled: renders += 1
static func on_commit() -> void: if enabled: commits += 1
static func on_placement() -> void: if enabled: placements += 1
static func on_update() -> void: if enabled: updates += 1
static func on_deletion() -> void: if enabled: deletions += 1

static func report() -> Dictionary:
	return {
		"renders": renders, "commits": commits, "placements": placements,
		"updates": updates, "deletions": deletions,
	}
