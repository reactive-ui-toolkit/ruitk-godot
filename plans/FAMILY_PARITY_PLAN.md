# Family parity — scheduler + defer, strict mode, boundary latch, trace ladder — Godot leg — EXECUTION PLAN

> **Status:** authored 2026-07-31; every `file:line` anchor below verified BY READING against the
> live working tree the same day (runtime addon `plugin.cfg` 0.13.0, editor addon 0.11.0), which
> includes the **uncommitted unified-settings campaign** (`core/settings.gd`,
> `tests/settings_test.gd`, dialog, README/docs/changelog edits — all present but not yet
> committed). **This plan builds ON that state.** If `addons/reactive_ui_toolkit/core/settings.gd`
> is missing when you start, the settings campaign was reverted — STOP AND ASK. If the tree moved,
> re-verify anchors before editing; line numbers drift, the surrounding shapes quoted here don't.
> **Reference implementation: the Unity leg**, read from the sibling checkout as
> `ruitk-unity/<path>:<line>`; the Unreal leg (`ruitk-unreal/<path>:<line>`) is the reference for
> the two features it invented (strict mode, cooperative boundary latch). **Executors READ the
> reference before porting each semantic — never improvise a behavior this plan or the reference
> pins.** §3 is the mandatory reading list.
> **Branch:** one feature branch off `origin/dev` (owner flow: feature → PR into dev → owner
> merges → master fast-forward). Never push master/dev; do NOT commit or push without an explicit
> owner ask; no Co-Authored-By trailers (check `git log` style first).
> **House rules:** research → develop → test → bughunt → fix per phase; production-grade only;
> never weaken a gate; the full verify list (§7) must be green at the END OF EVERY PHASE.
> **Machine-local paths:** never write a drive-absolute path into any tracked file; the Godot
> binary resolves per CLAUDE.md "Machine-local paths" (`.ruitk-local.json`, gitignored);
> `node scripts/check-machine-paths.mjs` is part of every phase's gate.

---

## 0. Family parity contract (normative)

*The Unity and Unreal campaign plans carry this same contract; substance is identical across the
three plans. Rulings by the owner (2026-07-31) — executors do NOT relitigate them.*

Reference implementation: **ruitk-unity**.

- **All library settings ship into builds**; defaults are off/production so an untouched build
  behaves exactly as today.
- **One-go campaign:** the scheduler + defer semantics port AND the default flip happen in the
  same campaign (internally phased: semantics green under unchanged defaults first, then the
  flip + coupling fixes).
- **strict_mode:** all legs, default OFF, explicit opt-in, force-off in release/shipping builds.
- **No UI Toolkit pooling in Unity** (a GlobalVisualElementPool existed 2025-11-17 for <16h and
  was deliberately removed — generic VisualElement reset causes state bleed; the safe
  adapter-gated pattern is the only sanctioned pooling).
- **exceptionControlFlow stays removed** (its consumer was a legacy-reconciler strategy selector;
  the surviving feature is unconditional and better; the knob is impossible in GDScript/C++ legs).
- **Basic trace level is RESTORED family-wide** (it meant "structural events" in the legacy Unity
  reconciler and was lost in the fiber rewrite, not by design).
- **Pool caps stay per-leg constants** (engine-tuned), NOT settings.

**Canonical knobs** (identical names/semantics/defaults family-wide; per-engine key spellings
follow engine convention):

1. **time_slicing** — bool, default **TRUE (post-campaign)**. `false` = bypass the scheduler
   entirely: synchronous single-pass render per update (today's sibling behavior).
2. **time_slice_ms** — float, default **2.0**. Render-phase quantum: the work loop checks elapsed
   AFTER each completed unit (one fiber) and yields; a long single unit overruns (no preemption).
   Reference: `ruitk-unity/Shared/Core/Fiber/FiberReconciler.cs:31` (const 2.0f), `:429-472`
   (check-after-unit loop).
3. **frame_budget_ms** — float, default **4.0**. Scheduler per-frame budget, CUMULATIVE across
   all lanes in one frame callback. Reference: `ruitk-unity/Runtime/Core/RenderScheduler.cs:19-20`
   (default), `:116-164` (frame flow), `:166-204` (shared frame-start timestamp = cumulative).
4. **host_node_pool** — bool, default **true** (adapter-gated safe pooling only).
5. **hook_validation** — tri-state auto/enabled/disabled, default **auto** (dev/debug ON, release
   OFF). Rules-of-hooks record+compare+report, warning/error logs only.
6. **strict_diagnostics** — tri-state, default **auto**. Misuse warnings ONLY: (a) state update
   during render, (b) missing dependency array. Deduped once per component per key.
7. **strict_mode** — bool default **false**, opt-in, force-off in release. Render functions
   double-invoked, first result discarded; effects are NOT double-invoked; diagnostics count the
   render ONCE. Reference semantics:
   `ruitk-unreal/Plugins/ReactiveUIToolkit/Source/RuitkCore/Private/RuitkReconciler.cpp:565-570`
   (Unreal invented it; the family adopts it).
8. **trace_level** — None/Basic/Verbose, default **None**. Basic = structural events only
   (placements, deletions, node replacements, commits). Verbose = Basic + per-element/per-hook
   detail.
9. **diff_tracing** — bool default **false**, INDEPENDENT switch (OR with trace_level — the
   legacy-Unity semantic): enables reconciler diff-decision logs.
10. **environment** — auto/development/production, default **auto** (editor or debug build →
    development, else production). Surfaced read-only to user components; the library itself
    never branches on it.

Leg-specific extras are allowed on the settings surface only if clearly marked "(<engine>-only)"
in UI and docs — Godot's `diagnostics/enabled` + `diagnostics/capture` keys are such extras.

**Scheduler semantics to port faithfully** (reference
`ruitk-unity/Runtime/Core/RenderScheduler.cs`): four lanes High/Normal/Low/Idle (`:10-17`);
per-frame flow = if High AND Low are both non-empty at frame start, the ENTIRE Low queue is
cancelled (dropped, counted — `:120-128`); Normal runs only if High drained (`:131-142`,
escalation counted); Idle runs only if nothing ran, all foreground queues are empty, AND elapsed
< budget/2 (`:149-161`), with a budget/2 sub-budget of its own (`:159` + `:177`); enqueue dedup
per lane via delegate identity (`:62-84`); the batched-effects flush runs UNBUDGETED at frame end
(`:162`, `:225-243`); render passes enqueue a `Slice` action that re-enqueues itself at the same
priority while work remains (`ruitk-unity/Shared/Core/Fiber/FiberReconciler.cs:405-424`), so a
2ms slice can run twice inside the 4ms budget in one frame. **Mount is ALWAYS synchronous (never
sliced)** — React 18 createRoot parity, already true in all legs.

**Defer-don't-restart semantics to port** (reference
`ruitk-unity/Shared/Core/Fiber/FiberReconciler.cs:304-325`, `:884-909`): an update arriving while
a pass is in flight or parked is DEFERRED (queued), never restarts the pass; deferred updates are
replayed after commit, coalesced into ONE follow-up render (`:884-909` — replay with
`scheduleWork:false`, then schedule ONCE); updates during commit take the same queue (`:302-309`);
guard flags `_isCommitting`/`_isReplayingDeferred` (`:22-23`); superseded-tree redirect
(`:254-281`) and detached-fiber bail (`:282-289`) per reference. The restart-from-root machinery
+ its cap is REPLACED by this; the equivalent runaway guard is **render-depth-25** on
setState-during-render loops (`ruitk-unity/Shared/Core/Fiber/FiberFunctionComponent.cs:16-18`,
`:140-155`).

---

## 1. Decision log — owner rulings + Godot-local decisions

Owner rulings (2026-07-31, final — the §0 contract): one-go campaign; ship-into-builds with
off/production defaults; strict_mode off + release-force-off; no Unity UITK pooling; no
exceptionControlFlow analog anywhere; Basic trace restored; pool caps stay constants.

Godot-local decisions (do not re-litigate mid-execution; conflict with §0 = §0 wins):

- **L-01 — Key spellings.** Canonical knobs keep the existing group discipline:
  `reactive_ui_toolkit/runtime/*` for `RuitkConfig`-backed knobs, `reactive_ui_toolkit/diagnostics/*`
  for `RuitkDiagnostics`-backed ones. Final surface in §4.
- **L-02 — frame_budget_ms is a SPLIT, not a rename.** The existing key
  `runtime/frame_budget_ms` (today: the single per-render park budget, default 8.0 —
  `core/config.gd:14`, read at `core/reconciler.gd:154`) KEEPS ITS NAME and becomes the canonical
  scheduler per-frame budget (default 4.0); the NEW key `runtime/time_slice_ms` (2.0) is the
  render quantum. Migration: Godot omits settings equal to their initial value from
  `project.godot` (`core/settings.gd:66-72`), so the only persisted values are user-tuned ≠8.0
  ones — those carry forward under the new (cumulative) meaning via the unchanged
  differs-from-default apply rule; `register()`'s `set_initial_value` re-assert
  (`core/settings.gd:56`) updates the stored initial to 4.0. The changelog documents the
  re-scoping loudly (§5 P7). No key is written, moved, or deleted by code.
- **L-03 — trace_level/diff_tracing live on `RuitkDiagnostics`** (mirroring Unity's
  `DiagnosticsConfig`, `ruitk-unity/Shared/Core/Diagnostics/DiagnosticsConfig.cs:11-26`);
  strict_mode/environment/time_slice_ms live on `RuitkConfig`. Keys follow L-01.
- **L-04 — strict_mode release force-off at the READ site**, not the store: a
  `RuitkConfig.strict_mode_effective()` getter returns `strict_mode and OS.is_debug_build()` —
  the exact shape of `ruitk-unreal/.../RuitkCore/Private/RuitkCoreMisc.cpp:70-77` (shipping
  returns false regardless of the CVar). The stored setting round-trips untouched.
- **L-05 — The failure-restart stays; the update-restart goes.** Defer-don't-restart removes
  restart-on-update; the error-boundary latch still restarts the pass on a render FAILURE
  (Unreal keeps `bRestart` for exactly this — `RuitkReconciler.cpp:664-668`). After P2+P3 the
  restart flag/cap serve the failure path ONLY, bounded by the existing cap-25 message
  (`core/reconciler.gd:140-141`, same text as Unreal's `RuitkReconciler.cpp:230`).
- **L-06 — Latch API:** global class `RuitkFail` (new file
  `addons/reactive_ui_toolkit/core/fail.gd`), `static func render(reason: String)` — first
  failure wins — plus an internal consume. Mirrors `Ruitk::FailRender`/`ConsumeRenderFailure`
  (`ruitk-unreal/.../RuitkCoreMisc.cpp:110-133`, header `RuitkCoreMisc.h:109-120`).
- **L-07 — Doom pins itself to sync.** The doom demo's per-frame linear allocator is only safe
  when a render never parks across ticks (`examples/demos/doom/doom_types.gd:391-399` says so
  explicitly). Rather than making the allocator slice-safe, the doom screen forces
  `RuitkConfig.time_slicing = false` for its own lifetime and restores on teardown (slicing buys
  a re-render-every-frame game nothing). §5 P6.
- **L-08 — New suites:** `tests/scheduler_test.gd` (lanes, budgets, defer, slicing) and
  `tests/strict_boundary_test.gd` (strict mode + boundary latch). Both join test.yml and the
  CLAUDE.md suite list (14 → 16 suites).
- **L-09 — Scheduler is engine-idiomatic but algorithm-loyal.** One `RuitkScheduler`
  (new file `addons/reactive_ui_toolkit/core/scheduler.gd`) pumped from `SceneTree.process_frame`
  (Godot's LateUpdate analog), lazily created — **no autoload, no plugin-enable required** (the
  runtime's standing rule, CLAUDE.md "no autoload or plugin-enable is required"). Lane
  algorithm/order/budgets byte-loyal to `RenderScheduler.cs`; Callable equality provides the
  delegate-identity dedup.
- **L-10 — Strict-diagnostics prefix aligns to the reference:** `[Hooks][StrictMode]`
  (Unity `ruitk-unity/Shared/Core/Hooks.cs:160,:573,:607`); the two existing Godot messages
  (`core/hooks.gd:105,:137`) are re-prefixed, and `tests/core_test.gd:420`'s assertion follows.

---

## 2. Where the repo starts — verified anchors (2026-07-31)

Runtime core `addons/reactive_ui_toolkit/core/`:

| Anchor | Line(s) | Role in this campaign |
|---|---|---|
| `reconciler.gd` header divergence notes | 3-4, 18-22 | says "synchronous (non-time-sliced)" and "Fresh fibers each pass (no 2-object double-buffer reuse)" — BOTH stale after this campaign (double-buffering already landed: `_reconcile` 331-343, commit note 692-693). P7 rewrites the header |
| `render()` (mount) | 83-98 | mount is synchronous + cancels parked ticks — **stays exactly as is** |
| `schedule_update_on_fiber` | 101-117 | commit-defer exists (112-114); `_restart = true` on mid-render update (115-116) is what P2 REPLACES with defer |
| `_ensure_tick` / `_tick` | 122-170 | restart handling + cap 25 (137-150, message 141); budget read (153-154: `RuitkConfig.time_slicing` / `frame_budget_ms`); slice loop (155-160) — P1 splits quantum/budget, P2 reworks restart |
| `_park` / `_cancel_pending_tick` | 173-189 | park via one-shot `process_frame` — P1 reroutes the sliced path through the scheduler |
| `_render_component` | 294-305 | the strict-mode double-invoke site (P4); `RuitkDiagnostics.on_render()` at 299 |
| `_begin_error_boundary` | 307-324 | inert structural boundary; `alt == null` counts as reset (312) — P3 adopts Unreal's mount-vs-reset rule |
| `_reconcile` | 335-418 | replacement branch (344-348 — the Basic-trace "replacement" site); eb prop capture (375-379), eb carry (392-394), eb reset (407-408) |
| `_commit_root` | 665-699 | `on_commit()` 667; deferred replay already exists for commit-time updates (695-699) — P2 extends it to render-time updates with coalescing + guards |
| `_commit_placement` / `_commit_update` / `_commit_deletion` | 701-707 / 709-737 / 757-762 | diagnostics hooks 707/737/758 = the Basic/Verbose trace sites |
| `_flush_passive` call | 691 | passive-effect flush stays commit-owned (§5 P1, scheduler does NOT take it over) |
| pool cap const | 59 (`_POOL_CAP_PER_CLASS := 256`) | stays a constant (§0 ruling) |
| `hmr_refresh` forced-sync | 1111-1120 (1116-1119) | HMR flush stays forced-sync — **do not touch** |
| `config.gd` statics | 13-14 (time_slicing false / frame_budget_ms 8.0), 19, 26-27 | P1/P6 targets |
| `diagnostics.gd` | 7 (enabled), 11-12 (capture/messages), 21-25 (the 5 counters), 34-38, 40-44 | gains trace ladder (P5); counters/capture stay Godot-only extras |
| `settings.gd` | 16-22 (KEY_*), 27 (TRI_STATE_HINT), 32-40 (DEFAULTS), 49-60 (register), 75-84 (apply/reapply one-shot), 86-106 (_apply_now), 109-112 (differs-from-default `_changed`), 115-129 (_property_info) | every new knob edits ALL of: KEY_ const, DEFAULTS, `_apply_now`, `_property_info` (+ per-key hint, §4) — the lockstep |
| `fiber.gd` eb fields | 50-57 (eb_active…eb_children), 60 (alternate) | P3 adds `eb_last_error` write path + pending-activation adoption |
| `hooks.gd` | 75 (`_warn_once`), 104-105 + 136-137 (set-in-render warns), 163/179/183 (memo trio, `deps: Array = []`), 193/206 (effects, `deps = null`), 303 (useDeferredValue, `deps = null`) | P5 adds missing-deps warns + prefix alignment |
| `reactive_root.gd` | 22 (`RuitkSettings.apply()`) | the mount-time settings load — unchanged mechanism |

Elsewhere in this repo:

- `examples/demos/doom/doom_types.gd:387-419` — `FrameData` linear allocator; the "safe because
  … time_slicing … is off by default and unused here" claim at 397-399 (L-07).
  Archived provenance: `plans/archive/FINAL_AUDIT_GODOT_OPTIMIZATIONS.md:246-259` (claim at
  255-256) — gets a one-line dated correction in P6 (its safety proof stops holding).
- `examples/demos/slicing/slicing.guitkx` — toggles the global static (line 7); ALSO a contract
  fixture (`tests/contract/fixtures/demos_slicing_slicing.guitkx/.gd`). **Do not edit the demo**
  unless unavoidable; if edited, goldens re-pin via `contract_dump.gd` (flag the diff).
- `tests/demos_test.gd:22-23` — end-of-run cleanup hard-codes `RuitkConfig.time_slicing = false`
  (the slicing demo may leave it flipped). P6 changes cleanup to capture-and-restore.
- `tests/core_test.gd:809-830` — `_test_time_slicing` (slicing already has one smoke); line 830
  restores `false` — P6 makes it capture-and-restore. Line 420 asserts the `[Hooks][Strict]`
  prefix (L-10).
- `tests/settings_test.gd` (181 lines) — register/apply/tri-state/one-shot/no-residue suite;
  `_orig` capture 24-32, restore 46-53, cleanup 170-173 iterate `Settings.DEFAULTS`, so new keys
  flow through mechanically; per-knob assertions are added by hand each phase.
- `addons/reactive_ui_toolkit_editor/editor/ruitk_settings_dialog.gd` — builds one row per
  `runtime.DEFAULTS` key (55-56), so NEW keys appear automatically; BUT every String key gets
  `TRI_STATE_HINT` options (56 → `_add_row` 131-139) — trace_level/environment need per-key
  hints (§4). Write discipline 157-161.
- `tests/guitkx_editor_test.gd` — `_test_settings_dialog` 366+; control-count assert 379-380
  self-adjusts via `DEFAULTS.size()`; SpinBox populate 387-389; tri-state `item_count == 3` 391;
  CHANGELOG byte-mirror tripwire 522-526.
- Docs/README/changelog surfaces (P7): `README.md:429-460` (Settings section, table 443-444);
  `addons/reactive_ui_toolkit/README.md:76-95` (table 83-84); root `CHANGELOG.md:7-30`
  (Unreleased; byte-mirrored to `addons/reactive_ui_toolkit/CHANGELOG.md`);
  `RuitkGodotDocs~/src/pages/UITKX/Config/UitkxConfigPage.tsx:69-78`;
  `Concepts/UitkxConceptsPage.tsx:93` (default false / 8.0 text);
  `Differences/UitkxDifferencesPage.tsx:134` ("optional" slicing);
  `FAQ/FAQPage.tsx:66`; `src/docs.tsx:205,:439` (search-index lines); CLAUDE.md 92 ("Synchronous
  (non-time-sliced) work loop") and 98-100 (fresh-fibers claim).
- CI `.github/workflows/test.yml` — per-suite steps at 77-127 (contract_dump 77, core 85,
  settings 88, style 91, router_match 94, router_spine 97, update 100, demos 103, guitkx 106,
  hmr 109, guitkx_lsp 112, guitkx_editor 115, migrate 121, rename_migrate 127). NOTE:
  `doom_game_test.gd` runs locally per CLAUDE.md but is NOT in CI — keep that shape; the two new
  suites (L-08) DO land in CI.
- Benches: `tests/bench.gd` (N keyed ColorRects, prints fps + ms/frame per N — the primary
  scheduler-phase gate), plus `recon_bench.gd`, `apply_bench.gd`, `microbench.gd`,
  `bench_native.gd`, `bench_compare.gd`.

---

## 3. Reference reading list (mandatory — read BEFORE the phase that ports each)

| Read | For |
|---|---|
| `ruitk-unity/Runtime/Core/RenderScheduler.cs` (all 260 lines) | P1: the entire lane machine — queues+trackers 10-17, default 4.0 19-20, dedup enqueue 45-86, batch defer 54-57 + 88-114, frame flow 116-164 (low-cancel 120-128, normal-gate 131-142, idle 144-161), `ExecuteQueue` 166-204 (budget/2 177, cumulative shared frame-start), batched effects 206-212 + 225-243 (unbudgeted), `PumpNow` 214-223, metrics 245-258 |
| `ruitk-unity/Shared/Core/Fiber/FiberReconciler.cs:14-45, 225-472, 855-911` | P1+P2: `TimeSliceMs` 31; guard flags 22-23; superseded-tree redirect 254-281; detached bail 282-289; commit-defer 302-309; in-flight defer 311-325 (read the whole comment); stale-effect-list discard 349-358; sync-vs-scheduler dispatch 362-373; `WorkLoop` 380-400; `ScheduleRootWork`/`Slice` 405-424; `ProcessWorkUntilDeadline` 429-472; CommitRoot finally replay 878-910 |
| `ruitk-unity/Shared/Core/Fiber/FiberFunctionComponent.cs:14-18, 128-170` | P2: render-depth guard (const 25 at 18; check 140-155; decrement in finally 165-169) |
| `ruitk-unity/Shared/Core/Hooks.cs:130-170, 530-580, 807-830, 965-985, 1007-1025, 1071-1090, 1108-1130, 1209-1230` | P5: `WarnStrict` dedupe 540-543; `WarnMissingDependencies` 551-575 (key format 568, message 573); which hooks pass `treatEmptyAsMissing: true` (UseMemo 976, UseCallback 1082, UseImperativeHandle 1123) vs not (UseLayoutEffect 818, UseDeferredValue 1018, UseEffect 1220); set-in-render text 160/607 |
| `ruitk-unity/Shared/Core/Diagnostics/DiagnosticsConfig.cs` (whole, 34 lines) | P5: `TraceLevel { None, Basic, Verbose }` 11-16, `EnableDiffTracing` 26 — and `UseExceptionBoundaryFlow` 32, the knob you must NOT port |
| `ruitk-unity/Shared/Core/Config/RuitkSettings.cs:40-44` + `Config/RuitkConfig.cs:24, 35-37, 108-121` + `Runtime/Core/RootRenderer.cs:55-75` | P5: trace/diff/env settings surface; `Environment["env"]` read surface for components (RootRenderer 63); internal logs keyed off Verbose (72-73) |
| `ruitk-unreal/Plugins/ReactiveUIToolkit/Source/RuitkCore/Private/RuitkReconciler.cpp:555-691` | P3+P4: strict double-invoke 565-569 + `OnRender()` once at 579; latch consume-after-render 572-577; `BeginErrorBoundary` 591-627 (mount-vs-reset 601-604, pending adoption 595-598); `HandleRenderFailure` 629-672; `AdoptPendingEbActivation` 674-691; runaway messages 100/230 |
| `ruitk-unreal/.../RuitkCore/Private/RuitkCoreMisc.cpp:60-135` + `Public/RuitkCoreMisc.h:100-130` | P3+P4: `IsStrictModeEnabled` shipping force-false 70-77; latch statics + `FailRender` first-wins 120-126 + `ConsumeRenderFailure` 128-133; the doc comment 109 |
| `ruitk-unreal/.../RuitkUMG/Public/RuitkSettings.h:27, 93-101` + `Private/RuitkSettings.cpp:17-22, 99-100` | §4: the sibling settings-surface shape this leg mirrors |

---

## 4. Target settings surface (end state)

| Key (`reactive_ui_toolkit/` + …) | Type | Default | Backing static | New? |
|---|---|---|---|---|
| `runtime/time_slicing` | bool | **true** (flipped in P6; false until then) | `RuitkConfig.time_slicing` | default flip |
| `runtime/time_slice_ms` | float | 2.0 | `RuitkConfig.time_slice_ms` (NEW static) | NEW (P1) |
| `runtime/frame_budget_ms` | float | **4.0** (was 8.0; meaning re-scoped per L-02) | `RuitkConfig.frame_budget_ms` | re-scoped (P1) |
| `runtime/host_node_pool` | bool | true | `RuitkConfig.host_node_pool` | unchanged |
| `runtime/hook_validation` | tri auto/enabled/disabled | auto | `RuitkConfig.enable_hook_validation` | unchanged |
| `runtime/strict_diagnostics` | tri auto/enabled/disabled | auto | `RuitkConfig.enable_strict_diagnostics` | unchanged (gains the missing-deps warn, P5) |
| `runtime/strict_mode` | bool | false | `RuitkConfig.strict_mode` (+ `strict_mode_effective()`, L-04) | NEW (P4) |
| `runtime/environment` | enum auto/development/production | auto | `RuitkConfig.environment` (+ `environment_resolved()`) | NEW (P5) |
| `diagnostics/trace_level` | enum none/basic/verbose | none | `RuitkDiagnostics.trace_level` (int enum, L-03) | NEW (P5) |
| `diagnostics/diff_tracing` | bool | false | `RuitkDiagnostics.diff_tracing` | NEW (P5) |
| `diagnostics/enabled` | bool | false | `RuitkDiagnostics.enabled` | unchanged — **(Godot-only)** |
| `diagnostics/capture` | bool | false | `RuitkDiagnostics.capture` | unchanged — **(Godot-only)** |

Lockstep rule (applies in EVERY phase that touches this table): a knob lands as ONE change across
`config.gd`/`diagnostics.gd` static → `settings.gd` KEY_ const + DEFAULTS + `_apply_now` branch +
`_property_info` → `tests/settings_test.gd` assertions (the `_orig` capture/restore maps at
24-32/46-53 gain the new statics) → dialog hint handling → docs later (P7). The
differs-from-default `_changed` rule (`settings.gd:109-112`) and the one-shot `apply()` guard
(`:75-79`) are NEVER weakened.

Per-key enum hints: today `_property_info` (`settings.gd:115-129`) gives every String key
`TRI_STATE_HINT`, and the dialog does the same (`ruitk_settings_dialog.gd:56`). Add a
`const HINTS := { KEY_TRACE_LEVEL: "none,basic,verbose", KEY_ENVIRONMENT: "auto,development,production" }`
to `settings.gd`, fall back to `TRI_STATE_HINT` for the two tri-states, and have the dialog read
the same per-key hint (pass `runtime.HINTS.get(key, tri_hint)` where it builds OptionButtons).
`guitkx_editor_test.gd` gains item-count/text assertions for both new enums (the pattern at 391-393).

"(Godot-only)" marking: the two diagnostics extras get the literal suffix "(Godot-only)" in the
dialog tooltip and every docs/README table row (§0 last paragraph).

---

## 5. Phases

Each phase ends with: the FULL §7 verify list green, `node scripts/check-machine-paths.mjs`
green, and one commit on the feature branch (commit only — no push without an owner ask).

### P0 — baseline

1. Branch off `origin/dev` (fetch first). Confirm the working tree still contains the
   unified-settings campaign (header note) — if the owner merged it meanwhile, re-verify §2's
   settings/dialog/test anchors against what landed.
2. Run §7 untouched; record results. Run `tests/bench.gd` 3× and record the per-N ms/frame table
   (this is the regression baseline for P1/P2/P6). Also record one run with
   `RuitkConfig.time_slicing = true` (today's 8.0 single-budget behavior) for before/after
   context.

### P1 — scheduler + quantum/budget split (defaults unchanged: time_slicing stays false)

1. **`core/scheduler.gd` (NEW, `class_name RuitkScheduler`)** — port `RenderScheduler.cs`
   faithfully (§0 scheduler paragraph is the checklist; the file is the spec): four
   Array-backed lanes + per-lane Dictionary trackers keyed by Callable (dedup,
   `RenderScheduler.cs:62-84`); `enqueue(callable, priority)`; `begin_batch`/`end_batch`
   deferral of non-High enqueues (`:54-57`, `:88-114`); the per-frame pump implementing EXACTLY
   `:116-164` — Low-cancel when High AND Low non-empty at frame start (count it), High, Normal
   only if High drained (count escalation), Low, Idle only if nothing-ran + queues-empty +
   elapsed < budget/2 with the budget/2 sub-budget, then the UNBUDGETED batched-effects flush;
   `execute_queue` with the SHARED frame-start timestamp (cumulative budget, `:166-204`);
   `enqueue_batched_effect` + `pump_now` (`:206-223`); a `get_metrics()` Dictionary mirroring
   `:245-258`. Budget reads `RuitkConfig.frame_budget_ms` live. Pump wiring per L-09: lazy
   per-SceneTree instance connected to `process_frame`; no autoload; headless-testable by
   pumping manually. GDScript has no try/catch — an action that fails render-side goes through
   the P3 latch instead; do NOT emulate the C# catch (`:192-199`) with anything.
2. **Quantum/budget split in the reconciler:** add `RuitkConfig.time_slice_ms := 2.0`
   (`config.gd`, doc comment updated); `_tick`'s slice loop (`reconciler.gd:155-160`) yields on
   `time_slice_ms` (the quantum — checked AFTER each completed unit, no preemption:
   `FiberReconciler.cs:444-455`), while `frame_budget_ms` moves to the scheduler as the
   per-frame lane budget. `config.gd:14` default changes 8.0 → 4.0 (inert while
   `time_slicing == false` — nothing reads it on the sync path).
3. **Sliced-path rescheduling through the scheduler:** when `time_slicing` is true, a render
   pass runs as a self-re-enqueueing Normal-lane slice action
   (`FiberReconciler.cs:405-424`) instead of `_park`'s one-shot `process_frame` connection
   (`reconciler.gd:173-181`); when false, TODAY'S `call_deferred` single-pass path is untouched
   (§0 knob 1). `render()` mounts stay synchronous (`:83-98` — includes cancelling a parked
   slice; preserve that against the scheduler too). The commit-owned passive-effect flush
   (`_commit_root` → `_flush_passive`, `:691`) is NOT rerouted through
   `enqueue_batched_effect` — behavior-preserving (the scheduler's flush is tested at the
   scheduler level; family wiring parity for effects is NOT in scope).
4. Settings lockstep for `time_slice_ms` + the 4.0 default (§4 rule): `settings.gd` (KEY const,
   DEFAULTS, `_apply_now`, float `_property_info`), `settings_test.gd` (capture/restore +
   apply/no-clobber assertions for the new float; the changed-default row at 108 keeps meaning
   "differs from DEFAULTS", so update its expectation), dialog picks the row up automatically
   (SpinBox, `_ms` suffix — `ruitk_settings_dialog.gd:119-130`).
5. **NEW suite `tests/scheduler_test.gd`** (SceneTree script, `quit(1)` on fail — copy the
   settings_test harness shape): lane priority order; High-starves-Normal escalation count;
   Low-cancel-on-High (entire queue dropped + counted); Idle runs only under the §0 conditions
   and its budget/2 sub-budget; per-lane dedup (same Callable enqueued twice runs once);
   batch begin/end deferral; batched-effects flush runs even when budget exhausted; cumulative
   budget across lanes (fake clock or generous action timings — headless CI is slow, avoid
   tight real-time asserts); slice self-re-enqueue drains a multi-slice render in one pump when
   budget allows (the "2ms slice twice inside 4ms" fact); metrics counters. Sliced-render
   integration: a big tree with `time_slicing = true` commits correctly across pumps; mount is
   never sliced. Add the CI step next to `settings_test` in test.yml (85-90 vicinity) + the
   CLAUDE.md suite list.
6. Bench gate: `tests/bench.gd` vs P0 at DEFAULTS (still sync) — within noise (< ~3% on the
   ms/frame medians). The sync path gained at most one branch; if it regressed, find out why.

Acceptance: §7 green (16-suite list from here on minus the P3 suite not yet present — i.e. all
existing 14 + scheduler_test), bench flat, `time_slicing` default still false, behavior of every
existing suite unchanged.

### P2 — defer-don't-restart + render-depth guard (defaults still unchanged)

1. In `schedule_update_on_fiber` (`reconciler.gd:101-117`): replace the `_restart = true` branch
   (115-116) with the reference's defer — while a pass is in flight or parked
   (`_work_active or _next_unit != null`) and we are not replaying, append to
   `_deferred_updates` and return (`FiberReconciler.cs:311-325` — port the comment's REASONING
   into the GDScript comment: restart starves large trees under sustained per-frame updates and
   leaks already-created hosts). Commit-time defer already exists (112-114) — same queue.
2. Add `_is_replaying_deferred`; after commit, drain the queue with schedule-work suppressed and
   then schedule ONE follow-up render (`FiberReconciler.cs:884-909`; Godot's replay loop at
   `reconciler.gd:695-699` is the seam — it currently re-enters `schedule_update_on_fiber`
   normally, which after this change coalesces via `_ensure_tick`'s tick-pending guard; verify
   ONE `_tick` results, not N).
3. Superseded-tree redirect + detached-fiber bail (`FiberReconciler.cs:254-289`): deferred
   updates captured mid-pass name fibers of the superseded tree; on replay, redirect to the live
   `alternate` twin, re-mark `has_pending_update`/`subtree_has_updates` up the LIVE chain, and
   bail (warn once) on genuinely detached fibers. Godot's `_reconcile` reuse carries
   `has_pending_update` between buddies (388) — pin with a test that a deferred setState on the
   old-generation fiber still re-renders the right component.
4. The mid-pass stale-effect-list invariant: when a REPLAYED update starts the follow-up render,
   the effect list must be rebuilt from scratch (Godot `_begin_render` already resets
   `_first_effect`/`_last_effect` — verify, mirroring `FiberReconciler.cs:349-358`).
5. **Render-depth-25 runaway guard** (`FiberFunctionComponent.cs:16-18`, `:140-155`): a counter
   of CONSECUTIVE follow-up renders caused by updates deferred DURING the render phase
   (setState-in-render loops). Reset when a pass commits without having deferred render-phase
   updates. On exceeding 25: `push_error` with the existing message text
   (`reconciler.gd:141` — keep it; it matches Unreal `RuitkReconciler.cpp:230`), drop the
   queued updates, keep the committed UI. `_restart`/`_restart_count` remain for the P3 failure
   path ONLY (L-05).
6. Tests (into `tests/scheduler_test.gd`): (a) setState during an in-flight sliced pass defers —
   pass commits, exactly ONE follow-up render, both values land; (b) N setStates during one pass
   coalesce into one follow-up; (c) setState during commit (from a layout effect) — same;
   (d) unconditional setState-in-render terminates via the depth guard with the error and a
   stable committed tree; (e) sustained every-frame updates on a tree bigger than one slice
   still commit (the starvation case the reference comment names); (f) existing
   `core_test.gd` re-render/effect/bailout semantics untouched.

Acceptance: §7 green; bench flat vs P0 at defaults; no test forces sync to pass (fixes await
completion instead).

### P3 — error-boundary latch (`RuitkFail`)

1. **`core/fail.gd` (NEW, `class_name RuitkFail`)** per L-06: `static var _reason = null`;
   `static func render(reason: String) -> void` — sets only if unset (FIRST failure wins,
   `RuitkCoreMisc.cpp:120-126`); `static func _consume()` returns-and-clears
   (`:128-133`). Doc comment: the cooperative no-throw path — a failing render CALLS
   `RuitkFail.render(...)` and returns whatever it can (mirror `RuitkCoreMisc.h:109`'s wording).
2. **Consume after every component render:** in `_render_component`'s caller path
   (`reconciler.gd:294-305`), after `Hooks._end()`: if a reason is pending, call
   `_handle_render_failure(fiber, reason)` and discard the output
   (`RuitkReconciler.cpp:572-577` — consume happens per-component, immediately, not at pass
   end).
3. **`_handle_render_failure`** — port `RuitkReconciler.cpp:629-672` exactly: walk WIP parents
   for the nearest `F.Tag.ERROR_BOUNDARY` with `not eb_active` (an active boundary can't
   capture again — React's captured-boundary rule, the comment at 631-633); set `eb_active` +
   `eb_last_error` on the fiber AND its committed twin (`fiber.alternate`, 640-645); when the
   boundary has NO alternate (mount pass), record a pending activation keyed by the
   root-to-boundary key path (646-659) for the restart pass to re-adopt; invoke `eb_handler`
   with the reason (660-663; Godot's handler is captured at `_reconcile:377`); set the restart
   flag (L-05) and `push_error` "render failed: … (caught by error boundary)"; if NO boundary
   exists above, `push_error` the no-boundary message (671) and continue (output already
   discarded).
4. **`_begin_error_boundary` rework** (`reconciler.gd:307-324` → `RuitkReconciler.cpp:591-627`):
   adopt pending activations first (595-598 + `AdoptPendingEbActivation` 674-691 — path-match,
   consume on adopt); mount-vs-reset per 601-604 — `reset_requested` requires an alternate
   (Godot's current `alt == null or …` at 312 is the bug to fix: a mount must not clear a
   just-adopted activation); clear `eb_last_error` on reset. Fallback-vs-children selection
   stays as is (318-321). The pass restart is bounded by the L-05 cap.
5. The imperative activation path (docs say boundaries toggle "imperatively" — `v.gd:175`) keeps
   working; the latch is additive. Update `v.gd:174-177`'s and the reconciler-header's boundary
   comments: structural, cooperative latch via `RuitkFail.render`, still no auto-catch of a real
   GDScript crash (no exceptions — that limitation SURVIVES; README wording in P7).
6. **NEW suite `tests/strict_boundary_test.gd`** (harness shape as before; CI step + CLAUDE.md
   list): child calls `RuitkFail.render` → nearest boundary shows fallback, `on_error` got the
   reason, siblings unaffected; first-failure-wins with two failing children; active boundary's
   fallback failing escalates to the NEXT boundary up; mount-pass failure (boundary and child
   mount together) — pending activation adopted, fallback shows; `reset_key` change clears and
   re-renders children; no boundary → push_error, tree stays; failure loop bounded by the cap;
   works under `time_slicing = true` and false.

Acceptance: §7 green (all 16 suites from here).

### P4 — strict mode

1. `RuitkConfig.strict_mode := false` + `strict_mode_effective()` per L-04 (doc comment cites
   the shipping-force-false reference). Settings lockstep per §4 (bool row; dialog auto).
2. In the component render path (`reconciler.gd:294-305`): when `strict_mode_effective()`, run
   the render closure twice — full `Hooks._begin`/`_end` around EACH invoke, FIRST result
   discarded, second kept (`RuitkReconciler.cpp:565-569`). `RuitkDiagnostics.on_render()` stays
   exactly once per pass (`:579` — after both invokes). Effects must NOT double-run: the hook
   slot model already makes the second `_begin` re-walk existing slots in place (mount appends
   on invoke 1, invoke 2 sees `i < size` and updates — verify against `hooks.gd:190-215`'s
   effect bookkeeping and PIN IT: a mount under strict mode runs each effect once and registers
   it once).
3. Interaction guards: strict double-invoke composes with the P3 latch (a failure raised in
   invoke 1 short-circuits — do not run invoke 2; consume once) and with set-in-render
   diagnostics (the misuse warn may fire on either invoke; `_warn_once` dedupes).
4. Tests (into `strict_boundary_test.gd`): mount + update with strict on — state survives,
   effects run once, `renders` counter increments once per pass while a probe counter inside
   the component saw two calls; strict off = one call; `strict_mode_effective()` is false when
   `OS.is_debug_build()` is false (assert the expression's shape via the settings tri-state
   precedent — the static itself stays true); settings row applies via `reapply()`.

Acceptance: §7 green; bench at defaults flat (strict off = one extra branch).

### P5 — strict-diagnostics missing-deps + trace ladder + diff_tracing + environment

1. **Missing-deps warning** (canonical pair (b), §0 knob 6): port
   `WarnMissingDependencies` (`ruitk-unity/Shared/Core/Hooks.cs:551-575`) as
   `Hooks._warn_missing_deps(state, hook_name, index, deps, treat_empty_as_missing)` gated on
   `RuitkConfig.enable_strict_diagnostics`, deduped through the existing `_warn_once`
   (`hooks.gd:75`) with key `"missing-deps:%s:%d"` (`Hooks.cs:568`) and Unity's message text
   (`:573`), prefix per L-10. Call-site mapping (Unity flags → Godot signatures):
   `useEffect`/`useLayoutEffect`/`useDeferredValue` warn on `deps == null` (their Godot default,
   `hooks.gd:193/206/303` — null = re-runs every render, exactly the message's claim);
   `useMemo`/`useCallback`/`useImperativeHandle` warn on EMPTY deps
   (`treatEmptyAsMissing: true` — `Hooks.cs:976/1082/1123`; their Godot default is `[]`,
   `hooks.gd:163/179/183`). Because useCallback/useImperativeHandle delegate to useMemo
   (`:180/:184`), route through an internal `_memo_impl` so each public hook warns under its OWN
   name exactly once. Re-prefix the two set-in-render messages (`:105/:137`) to
   `[Hooks][StrictMode]` and fix `tests/core_test.gd:420`.
2. **Call-site sweep:** `grep -rn "useMemo(\|useCallback(\|useImperativeHandle(" examples/ addons/`
   — any first-party call now warning gets REAL deps (examples model best practice); suites must
   end green with no unexplained warn spam in output (warnings never fail a suite, but the
   sweep is the acceptance).
3. **Trace ladder:** `RuitkDiagnostics.TraceLevel { NONE, BASIC, VERBOSE }` +
   `static var trace_level := TraceLevel.NONE` + `static var diff_tracing := false` (L-03;
   mirror `DiagnosticsConfig.cs:11-26`). Emission helper on RuitkDiagnostics (print +
   `capture`-aware so tests assert via `messages`). **Basic sites (structural only):**
   placements (`_commit_placement`, by `reconciler.gd:707`), deletions (`_commit_deletion`,
   `:758`), node replacements (`_reconcile`'s non-match branch, `:344-348`), commits
   (`_commit_root`, `:667` — one line per commit with effect counts). **Verbose adds:**
   per-element updates (`_commit_update`, `:737`), per-hook detail (hook kind per slot walk —
   next to `_record` in hooks.gd), portal retargets, component render entries. **diff_tracing
   (independent, OR semantics per §0 knob 9):** diff-decision logs (bailout taken/skipped,
   reuse-vs-replace in `_reconcile`, keyed-list match decisions) fire when
   `diff_tracing OR trace_level == VERBOSE` (the Unity wiring keys internal logs off Verbose —
   `RootRenderer.cs:72-73` — while `diffTracing` stays its own switch, `RuitkSettings.cs:43-44`).
   Hot-path discipline: every site is guarded by a cheap enum/bool check FIRST (the
   `if RuitkDiagnostics.enabled:` pattern at `reconciler.gd:737`); at NONE+false the added cost
   is one comparison. Bench must stay flat.
4. **Environment label:** `RuitkConfig.environment := "auto"` +
   `environment_resolved() -> String` ("development" when `OS.is_debug_build()`, else
   "production"; explicit values pass through). Documented read surface for components (docs
   page in P7; the Unity analog surfaces it to components via the host-context environment —
   `RootRenderer.cs:63`). The library itself NEVER branches on it — enforce by grep in review:
   no `environment` read inside `addons/reactive_ui_toolkit/` outside config/settings/docs.
5. Settings lockstep per §4 for `strict_mode` (done P4), `environment`,
   `diagnostics/trace_level`, `diagnostics/diff_tracing` — including the per-key `HINTS`
   mechanism + dialog hint pass-through + `guitkx_editor_test.gd` enum assertions +
   `settings_test.gd` rows (tri-state-style apply tests for both enums; `_apply_now` maps
   trace_level strings to the enum ints).
6. Tests: core_test gains capture-based assertions — Basic emits on a mount (placement+commit)
   and on a keyed removal (deletion) and on a type swap (replacement); NONE emits nothing;
   VERBOSE ⊇ Basic + an update line; diff logs appear under `diff_tracing=true, trace_level=NONE`
   AND under `diff_tracing=false, trace_level=VERBOSE` (the OR, both directions); missing-deps
   fires once per site per component (dedupe) for each mapped hook and not for supplied deps.

Acceptance: §7 green; bench flat at defaults.

### P6 — THE FLIP + coupling fixes + bench proof

1. `config.gd:13` → `static var time_slicing := true`; `settings.gd` DEFAULTS row follows
   (`KEY_TIME_SLICING: true`). The doc comments in config.gd flip their framing (slicing is the
   default; `false` opts back into single-pass sync).
2. **Coupling fix — doom (L-07):** the doom screen forces sync for its lifetime (mount/unmount
   of `DoomGameScreen` — a `useEffect` that saves, sets false, and restores on cleanup, placed
   in the screen's `.guitkx` setup); rewrite the allocator-safety comment
   (`doom_types.gd:391-399`) to state the ACTUAL invariant ("safe because this screen pins
   time_slicing off; a parked sliced render would read rewound pool records"); append the
   one-line dated correction to `plans/archive/FINAL_AUDIT_GODOT_OPTIMIZATIONS.md` GO-03
   (255-256 vicinity): the 0.14 default flip invalidated "time_slicing is off", the demo now
   pins it. `doom_game_test.gd` + `demos_test.gd` prove it (doom renders green post-flip).
3. **Coupling fix — tests:** `tests/demos_test.gd:22-23` captures `RuitkConfig.time_slicing` at
   `_run()` start and restores THAT (not hard-coded false); same for
   `tests/core_test.gd:809-830`'s restore at 830. Sweep the suites for other hard-coded
   `time_slicing = false` restores (grep) — capture-and-restore everywhere.
4. Suite stabilization under sliced defaults: renders may now take one more pump than before —
   fixes AWAIT settlement (extra `await process_frame` / a shared settle helper), NEVER a
   global force-sync (only the doom pin and per-test explicit opt-outs that TEST the sync path
   are legitimate). HMR stays forced-sync by design (`reconciler.gd:1116-1119`) — untouched.
5. **Bench proof (the scheduler-phase gate):** `tests/bench.gd` 3× at the NEW defaults + 3× with
   `time_slicing = false`; compare to P0. Sync-path numbers within noise of P0; sliced numbers
   recorded in the changelog entry (they are allowed to differ — that's the feature — but
   document them). Run `recon_bench.gd`/`apply_bench.gd` once each as sanity.
6. The slicing demo (`examples/demos/slicing/slicing.guitkx`) needs NO edit (it reads the live
   static) — verify its label reflects ON at launch; contract goldens must NOT move this phase
   (if they did, you edited a fixture source — revert).

Acceptance: §7 green under the flipped default; bench gate met; a plain mount in a fresh scene
behaves visibly identically (mount is sync).

### P7 — docs, dialog polish, changelog, stale claims (the ride-alongs)

1. **Stale-claim fixes (work item 7):** rewrite the `reconciler.gd` header — `:3-4` (no longer
   "synchronous (non-time-sliced)": describe quantum/budget/defer + the sync opt-out) and
   `:18-22` (DELETE the fresh-fibers bullet — double-buffering is reality per `:331-343`; keep
   the no-exceptions bullet, now phrased around the `RuitkFail` latch). CLAUDE.md `:92` (work
   loop description) and `:98-100` (fresh-fibers claim) get the same truth; CLAUDE.md's suite
   list + "The suites:" sentence gain `scheduler_test.gd` + `strict_boundary_test.gd` (16).
2. **Docs site:** `UitkxConfigPage.tsx:69-78` table gains all §4 rows (defaults, tri-states, the
   two enums, "(Godot-only)" marks); `UitkxConceptsPage.tsx:93` (default true, 2.0/4.0 split);
   `UitkxDifferencesPage.tsx:134` (slicing default-on, scheduler parity);
   `FAQPage.tsx:66`; `docs.tsx:205,:439` search-index lines; a short environment-label +
   strict-mode + trace-ladder subsection on the Config page (read surfaces + release-force-off
   note). `npm run build && npm run lint` in `RuitkGodotDocs~`.
3. **READMEs:** root `README.md:429-460` + `addons/reactive_ui_toolkit/README.md:76-95` settings
   tables gain the new rows/defaults; the "Notes & limitations" error-boundary bullet updates to
   the cooperative-latch reality (still no auto-catch of hard crashes);
   `useTransition`/`useDeferredValue`-are-synchronous notes STAY (unchanged by this campaign).
4. **Changelog (loud behavior-change entry):** root `CHANGELOG.md` under `[Unreleased]` — a
   "### Changed — BEHAVIOR" block: time_slicing now ON by default (what users see, how to opt
   out: settings key or `RuitkConfig.time_slicing = false`); frame_budget_ms re-scoped (L-02
   migration story verbatim); new knobs listed; bench numbers from P6.5. Byte-copy to
   `addons/reactive_ui_toolkit/CHANGELOG.md` (the tripwire `guitkx_editor_test.gd:522-526`
   enforces identity — resync via copy, never hand-edit the mirror). Discord lane
   (`plans/DISCORD_CHANGELOG.md`, ≤2000 chars) at release time per the release-process skill.
5. **Versions:** decided at RELEASE, owner-gated, per the release-process skill — this campaign
   is a MINOR for the runtime addon (behavior change: 0.13.0 → 0.14.0 expected) and at least a
   patch for the editor addon (dialog hint change; 0.11.0 → 0.11.1). Do NOT bump or tag inside
   the campaign unless the owner asks.
6. Final full pass of §7 + a fresh-clone-order sanity run (the CLAUDE.md two-pass class-cache
   sequence from scratch).

---

## 6. Test matrix (adds per suite)

| Suite | Adds |
|---|---|
| `tests/scheduler_test.gd` (NEW, P1/P2) | lane order, escalation, Low-cancel, Idle gating + sub-budget, dedup, batching, unbudgeted effect flush, cumulative budget, slice re-enqueue, metrics; defer: in-flight/parked/commit coalescing → ONE follow-up, superseded-tree redirect, detached bail, depth-25 termination, sustained-updates starvation case |
| `tests/strict_boundary_test.gd` (NEW, P3/P4) | latch: nearest boundary, first-wins, active-boundary skip-up, mount pending-activation, reset_key, no-boundary error, cap-bounded loop, sliced+sync; strict: double-invoke/discard-first, effects-once, renders-counter-once, release force-off shape, settings row |
| `tests/settings_test.gd` | every §4 addition: capture/restore maps, apply/no-clobber/enum mapping rows for time_slice_ms, strict_mode, environment, trace_level, diff_tracing; flipped time_slicing default expectations |
| `tests/core_test.gd` | trace-ladder capture assertions (NONE/BASIC/VERBOSE/OR); missing-deps per-hook + dedupe; prefix fix at :420; `_test_time_slicing` restore fix |
| `tests/demos_test.gd` / `tests/doom_game_test.gd` | green under flipped defaults; demos cleanup capture-and-restore; doom sync-pin proven |
| `tests/guitkx_editor_test.gd` | dialog rows for new keys (count self-adjusts), enum hint assertions for trace_level/environment, changelog mirror stays green |
| `tests/hmr_test.gd` | unchanged assertions — HMR forced-sync must still pass under flipped defaults |
| `bench*.gd` | not pass/fail; P0/P1/P2/P6 protocol per §5 |

CI: two new steps in `.github/workflows/test.yml` (same shape as the `settings_test` step at
86-88), placed after `settings_test` and after `demos_test` respectively. `doom_game_test.gd`
stays local-only (current shape — do not add it while "fixing" the workflow).

## 7. Verify commands (run after every phase; never weaken)

```bash
# Godot binary: resolve per CLAUDE.md "Machine-local paths" (.ruitk-local.json / $GODOT_BIN / PATH).
godot --headless --path . --editor --quit || true                       # 1. class-cache (fresh clones/CI)
godot --headless --path . --script res://tests/guitkx_build.gd          # 2. compile .guitkx (two-pass gate)
godot --headless --path . --editor --quit || true                       # 3. re-scan generated class_names
godot --headless --path . --script res://tests/core_test.gd
godot --headless --path . --script res://tests/settings_test.gd
godot --headless --path . --script res://tests/scheduler_test.gd        # NEW (from P1)
godot --headless --path . --script res://tests/strict_boundary_test.gd  # NEW (from P3)
godot --headless --path . --script res://tests/style_test.gd
godot --headless --path . --script res://tests/router_match_test.gd
godot --headless --path . --script res://tests/router_spine_test.gd
godot --headless --path . --script res://tests/update_test.gd
godot --headless --path . --script res://tests/demos_test.gd
godot --headless --path . --script res://tests/doom_game_test.gd
godot --headless --path . --script res://tests/guitkx_test.gd
godot --headless --path . --script res://tests/hmr_test.gd
godot --headless --path . --script res://tests/guitkx_editor_test.gd
godot --headless --path . --script res://tests/guitkx_lsp_test.gd
godot --headless --path . --script res://tests/contract_dump.gd -- --check
godot --headless --path . --script res://tests/guitkx_migrate.gd        # still "migrated 0"
node scripts/check-machine-paths.mjs                                    # machine-local-path gate
# Phase P7 additionally:
cd RuitkGodotDocs~ && npm ci && npm run build && npm run lint
node ide-extensions/scripts/changelog.mjs verify
# Scheduler phases additionally (P0/P1/P2/P6):
godot --headless --path . --script res://tests/bench.gd                 # 3x, record medians
```

## 8. Executor guardrails — the DO-NOT list

- Do NOT port `UseExceptionBoundaryFlow` / any exceptionControlFlow analog
  (`DiagnosticsConfig.cs:32` exists in Unity — it is the removed knob; §0 ruling).
- Do NOT turn pool caps into settings — `_POOL_CAP_PER_CLASS` (`reconciler.gd:59`) and the doom
  pools stay constants (§0 ruling).
- Do NOT slice the mount — `render()` (`reconciler.gd:83-98`) stays synchronous, including its
  parked-tick cancellation.
- Do NOT touch the HMR forced-sync flush (`reconciler.gd:1111-1120`).
- Do NOT weaken the settings bridge: the differs-from-default `_changed` rule
  (`settings.gd:109-112`), the one-shot `apply()` guard (`:75-79`), register()'s
  only-save-when-dirty discipline (`:49-60`), or settings_test's no-residue promise.
- Do NOT make the library branch on `environment` (§0 knob 10) — read-surface only.
- Do NOT double-run effects or double-count `renders` under strict mode (Unreal
  `RuitkReconciler.cpp:565-579` is the arbiter).
- Do NOT reintroduce restart-on-update once P2 lands; the restart flag serves the P3 failure
  path only (L-05).
- Do NOT fix a timing-flaky test by forcing `time_slicing = false` globally — await settlement;
  the only sanctioned pins are doom (L-07) and tests explicitly exercising the sync path.
- Do NOT edit `examples/demos/slicing/slicing.guitkx` (contract-fixture coupling) unless
  unavoidable; goldens re-pin via `contract_dump.gd`, never by hand.
- Do NOT hand-edit the addon CHANGELOG mirror (byte-copy from root; tripwire
  `guitkx_editor_test.gd:522-526`), generated `.gd`/`.uid` files, or anything under
  `tests/contract/golden/`.
- Do NOT write a drive-absolute path into ANY tracked file (`scripts/check-machine-paths.mjs`
  gates it; machine facts go in `.ruitk-local.json`).
- Do NOT commit without an explicit owner ask; never push master/dev; no Co-Authored-By
  trailers; do NOT bump versions or tag — release is owner-gated (§5 P7.5).
- Do NOT relitigate §0. Ambiguity between this plan and the reference sources = read the
  reference again; still ambiguous = STOP AND ASK.

---

## 10. Execution log (append-only; one entry per phase, written with that phase's commit)

### P0 — baseline — DONE (2026-07-31)

Tree at start: `feat/family-parity` == `origin/dev` == 7b38f41 (the unified-settings campaign
landed and was released — runtime 0.14.0, editor 0.12.0 — so §2's "uncommitted" framing is now
"committed"; all anchors re-verified by reading, minor line drift only, shapes unchanged).
Godot 4.7-stable (console binary via `.ruitk-local.json`); no editor held the project, so the
ordered scan steps ran normally.

§7 verify list, untouched tree — ALL GREEN:
core 133/0 · settings 56/0 · style 42/0 · router_match 18/0 · router_spine 37/0 ·
update ALL PASSED · demos 31/0 · doom 179/0 · guitkx ALL PASSED · hmr ALL PASSED (55) ·
guitkx_editor 428/0 · guitkx_lsp 39/0 · contract 66/66 · migrate "migrated 0" ·
machine-path gate green · guitkx_build 49 files, 0 errors.

`tests/bench.gd` 3× at defaults (sync path) — ms/frame (median of 3):

| N | run1 | run2 | run3 | median |
|---|---|---|---|---|
| 300 | 6.897 | 6.899 | 6.897 | 6.897 |
| 750 | 6.936 | 6.893 | 6.893 | 6.893 |
| 1500 | 17.408 | 17.254 | 17.906 | 17.408 |
| 2000 | 37.814 | 37.118 | 38.294 | 37.814 |
| 3000 | 57.219 | 58.254 | 56.635 | 57.219 |

N=300/750 sit on the headless frame-pacing floor (~6.9 ms/frame, ~145 fps) — only N≥1500 rows
are informative for regression comparison. Context run, `time_slicing = true` (today's 8.0
single-budget park loop, temp edit reverted): 6.897 / 6.893 / 12.932 / 17.366 / 26.678 —
NOT comparable 1:1 to sync (a parked pass spreads across frames; fps counts frames, not
commits). Recorded for before/after context only.

### P1 — scheduler + quantum/budget split — DONE (2026-07-31)

Shipped (defaults unchanged — `time_slicing` still false):

- **`core/scheduler.gd` (NEW, `class_name RuitkScheduler`)** — the full RenderScheduler.cs
  port: four Array-backed lanes + per-lane Callable-keyed dedup trackers, batch
  begin/end deferral of non-High enqueues, the exact `LateUpdate` frame flow (Low-cancel
  when High+Low non-empty at frame start, Normal gated on High drained w/ escalation
  count, Idle only on quiet frames under budget/2 with a budget/2 sub-budget), shared
  frame-start cumulative budget in `_execute_queue` (budget 0 disables the check, the
  reference `budgetLimit > 0f` quirk), unbudgeted batched-effects flush, `pump_now`,
  `get_metrics()`. Budget reads `RuitkConfig.frame_budget_ms` live. L-09 wiring: lazy
  per-SceneTree instance via `for_tree()` connected to `process_frame`; a `time_source`
  Callable seam lets tests drive a fake clock. GDScript divergences (documented in-file):
  no per-action try/catch (invalid Callables are skipped-but-counted, the analog of the
  caught C# exception); the effects flush snapshot-swaps (the reference's live-list
  foreach makes reentrant adds a hard error).
- **Quantum/budget split:** `RuitkConfig.time_slice_ms := 2.0` (NEW), `frame_budget_ms`
  8.0 → 4.0 (L-02 re-scope; inert while slicing is off), `_tick`'s slice loop now yields
  on the quantum (usec clock — the 2 ms default is finer than get_ticks_msec's grain).
- **Sliced path through the scheduler:** `_ensure_tick`/`_park` enqueue a
  `_scheduled_slice` Normal-lane action (self-re-enqueueing slice, ScheduleRootWork
  parity) when slicing is on; `_cancel_pending_tick` clears `_tick_pending`, which makes
  any stale queued slice a no-op (`_scheduled_slice` guard — the analog of the reference
  slice's `_nextUnitOfWork == null` early return). Sync path byte-identical
  (call_deferred single pass); mount still synchronous + cancels parked continuations;
  HMR forced-sync untouched.
- **Settings lockstep:** `runtime/time_slice_ms` key (KEY_ const + DEFAULTS + `_apply_now`
  + float `_property_info` row) + the 4.0 frame_budget default; settings_test gains
  capture/restore + apply + no-clobber rows (56 → 64 asserts) and its
  frame-budget "changed" values move off the new default (6.0); guitkx_editor_test float
  rows read defaults from `DEFAULTS` instead of hardcoding 8.0 (dialog itself needed NO
  change — the new float row appears automatically with the `_ms` SpinBox suffix).
- **NEW suite `tests/scheduler_test.gd`** (40 asserts): lane order, per-lane dedup,
  Low-cancel + counters, escalation, cumulative budget, idle sub-budget, batch deferral,
  unbudgeted effects flush, slice self-re-enqueue ("three 2 ms slices fit one 4 ms pump"
  pinned with the fake clock), pump_now, metrics; integration: sliced update commits
  across pumps (quantum 0 + generous budget — no wall-clock asserts), mount never sliced,
  unmount neutralizes a parked slice, sync path commits in one frame. CI step added after
  settings_test in test.yml; CLAUDE.md suite list updated (15 suites; 16 at P3).

Acceptance: full §7 verify green — core 133/0 · settings 64/0 · **scheduler 40/0 (NEW)** ·
style 42/0 · router_match 18/0 · router_spine 37/0 · update PASSED · demos 31/0 ·
doom 179/0 · guitkx PASSED · hmr PASSED (55) · guitkx_editor 428/0 · guitkx_lsp 39/0 ·
contract 66/66 · migrate 0 · machine-path gate green. Bench at unchanged defaults vs P0
(ms/frame medians): 6.897/6.893/16.395/36.992/55.939 vs 6.897/6.893/17.408/37.814/57.219
— every N at-or-below baseline (≤ noise; the sync path gained one branch). `.uid`
sidecars for the two new `.gd` generated by the editor scan and committed.

### P2 — defer-don't-restart + render-depth guard — DONE (2026-07-31)

Shipped (defaults still unchanged):

- **`schedule_update_on_fiber` rework:** the `_restart = true` mid-render branch is gone.
  The function now walks up marking `subtree_has_updates` while finding the target's root
  (FiberReconciler.cs:215-234), then: (a) **superseded-tree redirect** — a target whose
  root is `_root_current.alternate` re-marks its live `alternate` twin + chain (the flag
  would otherwise be clobbered by `_reconcile`'s `has_pending_update` carry from the live
  buddy, :254-281); (b) **detached bail** — unknown root warns once and ignores
  (:282-289); (c) commit-phase defer unchanged; (d) **in-flight defer** — while
  `_work_active or _next_unit != null` and not replaying, append to `_deferred_updates`
  and return (the reference comment's starvation/leak reasoning ported verbatim,
  :311-325).
- **Coalesced replay:** `_commit_root`'s tail drains the queue with
  `_is_replaying_deferred` set (re-marks flags; re-deferral suppressed) — the follow-up
  render coalesces to ONE tick via `_ensure_tick`'s tick-pending guard (:884-909; sliced
  mode lets the still-queued slice action pick the work up, exactly the reference's
  "async mode: do nothing").
- **Render-depth-25 guard** (`_MAX_RENDER_DEPTH`, FiberFunctionComponent.cs:16-18):
  counts CONSECUTIVE commits whose render FNS deferred updates; trip = the existing
  cap-25 push_error text + queued updates dropped + committed UI kept.
  **Bughunt find (fixed):** the first cut counted ANY defer captured while the pass was
  in flight — an external per-frame setState storm on a parked sliced pass (legitimate
  load) tripped the guard and dropped real updates. Fix: `_in_component_render` flag set
  around the component call in `_render_component`; only setState-in-RENDER defers count.
  The storm test now asserts `_render_depth == 0` after 90 frames of sustained load.
- `_restart`/`_restart_count`/cap-25 machinery kept but now DORMANT — the P3 failure path
  (L-05). `_begin_render`'s effect-list reset verified as the stale-effect-list invariant
  (mirrors FiberReconciler.cs:349-358) — no change needed.
- **Tests** (scheduler_test 40 → 56): reentrant setState-in-render defers + N setStates
  coalesce to exactly ONE follow-up (renders==3 pinned); commit-phase (layout-effect)
  setState same; depth guard terminates an unconditional loop at exactly 26 renders with
  stable UI; sustained-storm starvation case (fake-clock jam holds the pass to one unit
  per frame, setState every frame — commits mid-storm, final value lands, depth stays 0);
  the P2.3 superseded-redirect pin (defer lands in the carry-already-passed window, the
  bailing component still re-renders after redirect); detached-fiber bail (white-box
  orphan fiber → warn + ignore).

Acceptance: full §7 verify green — core 133/0 · settings 64/0 · scheduler 56/0 ·
style 42/0 · router_match 18/0 · router_spine 37/0 · update PASSED · demos 31/0 ·
doom 179/0 · guitkx PASSED · hmr PASSED (55) · guitkx_editor 428/0 · guitkx_lsp 39/0 ·
contract 66/66 · migrate 0 · machine-path gate green. Bench at defaults vs P0 (ms/frame
medians, 5 runs on the noisy N=1500 row): 6.897/6.893/17.595/37.561/57.120 vs
6.897/6.893/17.408/37.814/57.219 — ≤1.1% everywhere (within the observed noise band;
N=2000/3000 ±0.2%). No test forces sync to pass — the sliced tests await settlement.

### P3 — error-boundary latch (RuitkFail) — DONE (2026-07-31)

Shipped (defaults unchanged):

- **`core/fail.gd` (NEW, `class_name RuitkFail`)** — the cooperative latch per L-06:
  `static render(reason)` first-failure-wins + internal `_consume()`, doc'd as the
  no-throw path (RuitkCoreMisc.h/.cpp).
- **Reference drift, verified by reading:** the Unreal latch machinery moved past this
  plan's anchors (now RuitkReconciler.cpp:717-844) — `bRestart` became `bPassPoisoned`,
  consumed INSIDE the work loop with an IMMEDIATE `BeginRender()` rebuild (fallback lands
  in the SAME commit, mount and update alike), bounded by a per-pass `ErrorRestarts`
  counter against `MaxErrorRestarts = 25` (RuitkReconciler.h:234), plus abandoned-WIP
  slab reclaim in BeginRender and a dedicated cap message. Ported THAT shape (per the
  §8 ambiguity rule: the reference wins) onto the dormant `_restart`/`_restart_count`
  fields — still their only use (L-05): both work loops (mount `render()` + `_tick`)
  consume the poison via `_consume_error_restart()`. DEVIATION from L-05's message note:
  the cap error is the reference's current dedicated text ("Too many error-boundary
  rebuilds (25). Abandoning the pass.") — the old cap-25 text now belongs to the P2
  depth guard and would mislead ("setState during render?") on the error path.
- **`_handle_render_failure`** — consume-after-every-component-render in
  `_render_component` (output discarded, `on_render` still counts); walk WIP parents for
  the nearest NON-ACTIVE boundary (captured-boundary rule); set `eb_active`+`eb_last_error`
  on the fiber AND its committed twin; mount-pass boundaries (no twin) record a pending
  activation by key-path, re-adopted in `_begin_error_boundary` (adopt-first, then the
  mount-vs-reset rule — `reset_requested` now REQUIRES an alternate, fixing the
  `alt == null`-counts-as-reset bug the plan names); `eb_handler` invoked; no boundary →
  push_error and continue. `_reconcile` reuse now carries `eb_last_error` (Unreal :961);
  pendings clear at commit tail + unmount.
- **`_reclaim_abandoned_wip`** — the BeginRender slab-reclaim analog: severs fibers the
  abandoned walk newly allocated (cycle-breaking + fresh-state dispose) and pools/frees
  their never-placed nodes. **Bughunt find P3-1 (fixed + pinned):** `_try_fast_leaf_list`
  stitches LIVE fibers (in-place reuse, `alternate == null`, committed nodes) into the
  WIP chain — the first reclaim cut severed them, corrupting the live sibling chain. The
  guard skips any fiber whose node is in-tree (or invalid — conservative). The pin is an
  IDENTITY assert (same node instances survive the poisoned pass) because the node pool
  masks a count-only assert — verified red-with-guard-off / green-with-guard-on.
- v.gd + reconciler-header boundary comments rewritten to the latch reality (still no
  auto-catch of a hard GDScript crash).
- **NEW suite `tests/strict_boundary_test.gd` (41 asserts):** latch API first-wins;
  mount-pass pending activation (fallback lands synchronously in the mount commit);
  nearest-boundary + sibling/outer isolation + `on_error` + white-box eb fields;
  first-failure-wins (second failing child never renders); active-boundary escalation
  (failing fallback captured by the NEXT boundary up); reset_key recovery (clears
  eb_active/eb_last_error); no-boundary path (failed component renders empty, siblings
  stay, later renders recover); adopt-miss loop capped at exactly 26 renders/26 on_error
  with nothing committed and clean unmount; the latch under time_slicing true (sliced
  pass rebuild) and false; the P3-1 fast-list identity pin. CI step added after
  demos_test in test.yml; CLAUDE.md suite list now 16.

Acceptance: full §7 verify green — core 133/0 · settings 64/0 · scheduler 56/0 ·
**strict_boundary 41/0 (NEW)** · style 42/0 · router_match 18/0 · router_spine 37/0 ·
update PASSED · demos 31/0 · doom 179/0 · guitkx PASSED · hmr PASSED (55) ·
guitkx_editor 428/0 · guitkx_lsp 39/0 · contract 66/66 · migrate 0 · machine-path gate
green · guitkx_build 49/0.

### P4 — strict mode — DONE (2026-07-31)

Shipped (default OFF — opt-in, per §0 knob 7):

- **`RuitkConfig.strict_mode := false` + `strict_mode_effective()`** (L-04): the static
  round-trips untouched; the READ gates on `OS.is_debug_build()` — the exact
  IsStrictModeEnabled shipping-force-false shape (doc comments cite it).
- **Double-invoke in `_render_component`:** the render call extracted to
  `_invoke_render(fiber, state)` with full `Hooks._begin`/`_end` bracketing per invoke;
  when effective, invoke 2 runs and its result replaces invoke 1's (first discarded,
  RuitkReconciler.cpp RenderComponent's second RunOnce). `RuitkDiagnostics.on_render()`
  stays ONCE per pass after both invokes. Effects register once (verified against
  hooks.gd's slot model: mount appends on invoke 1, invoke 2 re-walks `i < size` in
  place) and run once per commit. Interaction guards: a failure latched by invoke 1
  short-circuits invoke 2 via the new `RuitkFail._pending()` (consumed once);
  set-in-render warns dedupe through `_warn_once` as before.
- **Settings lockstep (§4):** `runtime/strict_mode` — KEY_ const + DEFAULTS false +
  `_apply_now` bool branch + auto bool `_property_info`/dialog row; settings_test 64 → 71
  (capture/restore map, no-keys row, bool property-info row, apply row asserting the
  static round-trips with force-off at the read site). guitkx_editor_test dialog row
  count self-adjusted (no edit).
- **Tests (strict_boundary_test 41 → 59):** effective() shape both ways; mount+update
  double-invoke pin (probe 2 calls/pass, effects 1x + cleanup 1x, `renders` 1x/pass,
  state survives, committed output = invoke 2's); strict-off single-invoke control;
  latch short-circuit (1 call, boundary captures, on_error once); hook-order validation
  accelerated to the FIRST render (impure hook-count component: silent on mount without
  strict, `[Hooks][order] hook count changed` captured on mount with strict).

Acceptance: full §7 verify green — core 133/0 · settings 71/0 · scheduler 56/0 ·
strict_boundary 59/0 · style 42/0 · router_match 18/0 · router_spine 37/0 ·
update PASSED · demos 31/0 · doom 179/0 · guitkx PASSED · hmr PASSED (55) ·
guitkx_editor 428/0 · guitkx_lsp 39/0 · contract 66/66 · migrate 0 · machine-path gate
green. Bench at defaults (strict off): the machine session ran ~2x faster than round 1's
absolute numbers, so the P2 commit was re-benched in a throwaway worktree the SAME
session for an honest baseline — P2 medians 6.897/6.893/12.99/17.74/27.29 vs P3+P4
6.896/6.893/12.56/16.92/26.42 ms/frame: at-or-below baseline at every N (≤ noise). A
commit-cadence probe (N=2000, 100 update frames) pinned renders=100/commits=100 —
the sync path still commits every frame; the absolute delta vs round 1 is machine
state, not semantics.

### P5 — missing-deps + trace ladder + diff_tracing + environment — DONE (2026-07-31)

Shipped (defaults unchanged — the new knobs land off/auto/none):

- **Reference drift, verified by reading the LIVE Unity tree:** its own campaign moved
  mid-flight (M4 `9bb83c0c`, M5 `a574c922`). M4 re-prefixed the strict family
  `[Hooks][StrictMode]` → `[Hooks][Strict]` (Hooks.cs 160/573/607) — per the drift rule the
  NEW prefix is matched family-wide, which the two existing Godot messages AND
  core_test:420 already carry, so **L-10 resolves to a verified no-op** (the reference
  converged onto Godot's spelling; nothing to re-prefix). M5 pinned the trace gates
  inline — structural `!= None`, detail `== Verbose`, diff `diff_tracing OR == Verbose` —
  ported exactly, plus its message shapes (`[Fiber] Delete <type>`,
  `[Fiber] Commit #n effects=m`).
- **Missing-deps warnings:** `Hooks._warn_missing_deps` ports WarnMissingDependencies —
  family key `"missing-deps:%s:%d"`, message text verbatim, gated on
  `enable_strict_diagnostics`, deduped per component per (hook, slot) through the existing
  `_warn_once`. Mapping per plan: useEffect/useLayoutEffect/useDeferredValue warn on
  `null` deps ONLY (`[]` stays a legitimate run-once); the memo trio warns on EMPTY too
  (treatEmptyAsMissing — the Unity params-empty shape). The delegation trap is closed by a
  new `_memo_impl(factory, deps, hook_name)`: useMemo/useCallback/useImperativeHandle each
  warn under their OWN public name while the recorded hook-order kind stays `"memo"` for
  all three (signatures unchanged — no behavioral drift for the order validator).
- **Call-site sweep:** every first-party memo-trio/effect-family call in `examples/` +
  `addons/` already passes real deps — zero fixes; demos_test output carries ZERO
  `[Hooks][Strict]` lines. The one bare `useDeferredValue` (core_test
  `_test_deferred_value`) deliberately exercises value-comparison mode — strict
  diagnostics silenced locally with the rationale inline; the warn itself is pinned in
  `_test_missing_deps`. The risk-list "legit empty-deps memo" case never materialized.
- **Trace ladder (L-03):** `RuitkDiagnostics.TraceLevel { NONE, BASIC, VERBOSE }` +
  `trace_level` + `diff_tracing` + a capture-aware `trace()` (print + `messages`).
  Basic/structural sites: placements (`_commit_placement`), deletions
  (`_commit_deletion` — one line per removed subtree), replacements (`_reconcile`'s
  non-match branch), commit summary (new `_commit_seq`; effects counted BEFORE the commit
  loop consumes the chain, emitted commit-end — the M5 shape). Verbose adds per-element
  updates, portal retargets, component render entries (once per pass, outside the strict
  double-invoke), and per-hook detail in `Hooks._record` (logs per strict invoke — two
  captures happened, the Unity comment's ruling). Diff channel (OR): bailout
  taken/skipped, reuse-vs-replace, keyed move/place/remove (gate hoisted once per keyed
  pass; move/place/remove print the effective reconciliation key). Every site gates on
  the cheap compare FIRST; formatting only after.
- **Environment (knob 10):** `RuitkConfig.environment := "auto"` +
  `environment_resolved()` — explicit labels pass through, auto/unknown resolve off
  `OS.is_debug_build()`. Read-only component surface; grep-proof holds (`environment`
  inside the addon names only config.gd/settings.gd — remaining hits are the unrelated
  "compiler environment" prose in guitkx/plugin).
- **Settings lockstep ×3 keys** (§4): `runtime/environment`, `diagnostics/trace_level`,
  `diagnostics/diff_tracing` (KEY_ + DEFAULTS + `_apply_now` + `_property_info`); NEW
  per-key `HINTS` const (`"none,basic,verbose"` / `"auto,development,production"`) with
  the TRI_STATE_HINT fallback; `_apply_now` maps trace strings onto the enum ints with
  unknown-value `_: pass` arms (a skewed dialog writing tri-state vocabulary is
  harmless). Dialog: per-key hint pass-through via `_hint_for` reading the script
  CONSTANT MAP, so an old runtime without HINTS degrades to the tri-state options — the
  risk-list posture, pinned in guitkx_editor_test with an in-memory stub script.
- **Tests:** settings_test 71 → 103 (capture/restore + no-keys + property-info + apply
  rows for all three knobs; `_test_enum_knobs`: string→enum mapping, unknown-value
  degradation for both enums, `environment_resolved()` all four shapes). core_test
  133 → 161 (`_test_missing_deps`: six warns under their own names, family text, `[]`
  vs `null` split, per-component dedupe, off-gate; `_test_trace_ladder`: NONE silent,
  BASIC mount/keyed-removal/type-swap structural-only, VERBOSE superset + hook detail +
  render entries + the OR's verbose side, diff_tracing-alone independence — diff lines
  with ZERO structural). guitkx_editor_test 428 → 437 (both enum rows' vocabulary +
  populate, diff_tracing CheckBox, `_hint_for` HINTS read + no-HINTS fallback).
- Bughunt find (fixed pre-commit): the keyed-move diff line printed `str(vn.key)` —
  "<null>" for unkeyed children matched positionally; now the effective reconciliation
  key (`_vnode_key`), consistent with the place/remove lines.

Acceptance: full §7 verify green — core 161/0 · settings 103/0 · scheduler 56/0 ·
strict_boundary 59/0 · style 42/0 · router_match 18/0 · router_spine 37/0 ·
update PASSED · demos 31/0 (zero strict-warn spam) · doom 179/0 · guitkx PASSED ·
hmr PASSED (55) · guitkx_editor 437/0 · guitkx_lsp 39/0 · contract 66/66 · migrate 0 ·
machine-path gate green · guitkx_build 49/0 (2 warnings pre-existing on 2d307eb,
verified). Bench at defaults, same-session medians vs 2d307eb (ms/frame):
6.897/6.893/12.151/17.425/26.481 vs 6.897/6.893/12.602/17.178/27.896 — inside the
observed noise band in both directions (N≥1500 swings ±5% run-to-run this session).

### P6 — THE FLIP + coupling fixes + bench proof — DONE (2026-07-31)

Shipped (the behavior change: `time_slicing` defaults ON):

- **The flip:** `config.gd` `time_slicing := true` + the doc comment reframed (slicing is
  the default; `false` is the sync opt-out; mount stays always-synchronous);
  `settings.gd` `DEFAULTS[KEY_TIME_SLICING]: true`.
- **settings_test flipped expectations:** the three hand-written tests whose true/false
  literals inverted meaning — `_test_apply_changed_keys` (changed value is now FALSE),
  `_test_default_value_does_not_clobber` (key true = default; a pre-assigned `false`
  static survives), `_test_one_shot_guard` (reapply applies FALSE) — plus the mechanical
  `_orig`/DEFAULTS loops, which adapted unchanged. 103/0.
- **Coupling fix — doom (L-07):** `doom_game_screen.guitkx` gains the sync-pin effect —
  FIRST hook deliberately, so its post-mount-commit setup runs before
  `use_doom_game`'s mount effect ever schedules a follow-up render: saves
  `RuitkConfig.time_slicing`, forces false, restores on unmount cleanup. The GO-03
  allocator-safety comment (`doom_types.gd`) now states the ACTUAL invariant (pin ↔
  allocator, remove neither without the other; a parked sliced render would read rewound
  pool records); `plans/archive/FINAL_AUDIT_GODOT_OPTIMIZATIONS.md` GO-03 got the dated
  correction. doom_game_test 179/0 and the demos doom smoke prove the pin post-flip.
- **Coupling fix — tests:** `demos_test` captures `time_slicing` at `_run()` start and
  restores THAT (not hard-coded false); `core_test._test_time_slicing` captures/restores
  BOTH statics it touches — the sweep found it also leaked `frame_budget_ms = 0.0` for
  the rest of the suite (inert pre-flip, real leak post-flip; fixed). Sweep confirms
  scheduler/strict_boundary/settings suites already capture-restore.
- **Suite stabilization — ONE fix, await-settlement, no force-sync:** the P5 trace-ladder
  test asserted two frames after a sliced update, but trace print()s are slow on the
  headless console — under VERBOSE the 2 ms quantum expires after a handful of units and
  the pass parks across MANY frames. New `_await_trace_msg` settle helper (bounded 120
  frames; settles on the commit summary — the LAST line of a pass — or on the first
  `[Diff]` line for the trace-NONE arm; level-gated ABSENCE claims stay safe at any
  time). Every other suite passed the flip untouched (HMR forced-sync included).
- **Slicing demo:** NO edit (reads the live static; its label reflects ON at launch);
  contract goldens verified unmoved (66/66).
- **Bench proof** (same session as the P5 numbers): NEW defaults (sliced), medians of 3
  — 6.898/6.896/6.850/9.321/14.666 ms/frame: the per-frame cost now sits at/near the
  4 ms budget floor (N=1500 drops 12.2→6.9, N=3000 26.5→14.7) with commits spread
  across frames — the feature, not a like-for-like speedup (fps counts frames, not
  commits; the P0 context-run caveat). Sync opt-out arm (temp edit, reverted), medians
  of 3 — 6.897/6.893/12.055/16.734/26.223 vs P5-at-sync 6.897/6.893/12.151/17.425/26.481
  and P0 6.897/6.893/17.408/37.814/57.219 (different machine state; P5 is the honest
  same-session baseline): within noise — the sync path is untouched by the flip.
  `recon_bench`/`apply_bench` sanity runs normal.

Acceptance: full §7 verify green under the flipped default — core 161/0 ·
settings 103/0 · scheduler 56/0 · strict_boundary 59/0 · style 42/0 · router_match 18/0 ·
router_spine 37/0 · update PASSED · demos 31/0 · doom 179/0 · guitkx PASSED · hmr PASSED
(55) · guitkx_editor 437/0 · guitkx_lsp 39/0 · contract 66/66 · migrate 0 · machine-path
gate green · guitkx_build 49/0. Mounts remain synchronous everywhere (scheduler_test's
mount-never-sliced pin; every suite's mount asserts unchanged).

### P7 — docs, dialog polish, changelog, stale claims — DONE (2026-07-31) — CAMPAIGN CLOSED

Shipped (docs/metadata only — zero runtime-behavior changes; the one code edit is dialog
tooltip text):

- **Changelog:** root `CHANGELOG.md` gains `## [Unreleased]` (no version — owner-gated at
  release staging): the loud "### Changed — BEHAVIOR: update renders are now time-sliced by
  default" block (flip + what stays the same + the opt-out, the L-02 frame_budget_ms
  re-scope migration story, the P6 bench medians verbatim) plus "### Added" entries for
  scheduler / defer+depth-guard / RuitkFail latch / strict mode / missing-deps / trace
  ladder+diff_tracing / environment / the settings surface. Mirrored byte-identical via
  `cp` (tripwire green).
- **READMEs (root + addon):** settings tables now carry all 12 keys with the flipped/new
  defaults and *(Godot-only)* marks on the two diagnostics extras; a "Time-slicing is ON by
  default" note with the opt-out; prose for strict_mode (release force-off via
  `strict_mode_effective()`), environment (read-only, `environment_resolved()`),
  trace_level/diff_tracing; the Notes & limitations error-boundary bullet rewritten to the
  cooperative-latch reality (hard-crash no-auto-catch limitation kept, as are the
  useTransition/useDeferredValue-are-synchronous notes).
- **Stale claims:** `reconciler.gd` header rewritten — no longer "synchronous
  (non-time-sliced)"; describes quantum/budget/slice-re-enqueue, defer-don't-restart +
  depth-25, the failure-only restart, and the double-buffer reality (fresh-fibers bullet
  DELETED; no-exceptions bullet kept, RuitkFail-phrased). CLAUDE.md: reconciler bullet
  rewritten the same way, fiber bullet now says double-buffered, NEW scheduler.gd/fail.gd
  bullets, Known-constraints + Conventions divergence wording updated (suite list was
  already 16 from P1/P3).
- **Docs site:** Config page — full §4 table (12 rows, types/defaults, the two enum
  vocabularies, (Godot-only) marks) + new "Strict mode" / "Environment label" / "Trace
  ladder & diff tracing" subsections; Concepts — knob list updated (slicing on-by-default
  with the 2.0/4.0 split, strict_mode, environment, trace bullets); Differences —
  rendering-model section now says time-sliced by default + defer-not-restart (no
  priority preemption claim kept); FAQ — overhead answer updated + the depth-guard Q&A
  now quotes the real error text; AdvancedAPI error-boundary + depth-guard sections and
  examples rewritten to the latch/defer reality (the early-`return null` .guitkx shape in
  the new example verified by compiling a scratch file — valid grammar, then removed);
  Components table ErrorBoundary desc; docs.tsx search-index lines for all four pages.
  `npm ci && npm run build && npm run lint` green.
- **Dialog polish (deferred from P5):** the two Godot-only diagnostics keys' tooltips get
  the literal " (Godot-only)" suffix (`_GODOT_ONLY_KEYS` literal strings — skew-safe);
  guitkx_editor_test pins both marks + a canonical-key non-mark (437 → 440).
- **Fresh-clone-order sanity:** `.godot` deleted, the CLAUDE.md ordered sequence re-run
  from scratch — scan → guitkx_build 49/0 → rescan → suites; the two-pass order holds
  post-campaign.

Acceptance: full §7 verify green — core 161/0 · settings 103/0 · scheduler 56/0 ·
strict_boundary 59/0 · style 42/0 · router_match 18/0 · router_spine 37/0 ·
update PASSED · demos 31/0 · doom 179/0 · guitkx PASSED · hmr PASSED (55) ·
guitkx_editor **440/0** · guitkx_lsp 39/0 · contract 66/66 · migrate 0 · machine-path
gate green · guitkx_build 49/0 (2 pre-existing warnings) · docs `npm run build` +
`npm run lint` green · `changelog.mjs verify` green (extension lane untouched) ·
CHANGELOG mirror byte-identical. NO version bumps (owner-gated at release staging).

## 9. Risks / watch-list / STOP-AND-ASK

- **Headless timing flakiness** (scheduler budgets are wall-clock): design scheduler tests
  around forced pumps and generous budgets, not tight real-time windows; a test that only
  passes locally is a fail.
- **The memo-trio missing-deps warn fires on legitimate "compute once" `useMemo(f)` calls**
  (Unity's `treatEmptyAsMissing: true` is deliberate reference behavior). If the P5.2 sweep
  shows first-party code where empty deps are genuinely intended and noisy, do NOT soften the
  rule unilaterally — that is a family-wording question: STOP AND ASK.
- **frame_budget_ms carry-forward (L-02):** a user's persisted ≠8.0 value silently becomes a
  cumulative scheduler budget. Judged benign (intent was "spend up to X ms"); the changelog
  entry is the mitigation. If the owner wants an explicit migration warning at register(),
  STOP AND ASK before inventing one.
- **Defer rework vs Godot's buddy reuse:** `has_pending_update` carry (`reconciler.gd:387-388`)
  plus the superseded-tree redirect is the subtle part — the P2.3 pin test is mandatory, not
  optional hardening.
- **Doom under slicing:** if the L-07 pin proves insufficient (any doom test flakes post-flip),
  do not chase allocator redesign mid-campaign — STOP AND ASK with the failing evidence.
- **Editor-addon dialog + settings skew:** the dialog reads the runtime's DEFAULTS dict
  dynamically (W5 degradation, `ruitk_settings_dialog.gd:52-63`) — an old editor addon with a
  new runtime shows the new keys but uses TRI_STATE_HINT for unknown String enums; the per-key
  HINTS fallback (§4) must be written so that combination degrades to a working control, not a
  crash.
- **Family lockstep:** the Unity and Unreal legs run this same contract as their own campaigns.
  Knob names/defaults in §4 are family-frozen; if either sibling's campaign pins a different
  spelling for a NEW knob before this leg ships, theirs wins for canonical names — renumber
  nothing silently; STOP AND ASK.
