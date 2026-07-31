# ReactiveUI-Godot — Final Audit: OPTIMIZATIONS & PERFORMANCE (v4 split)

**Date:** 2026-07-06. Companion to `FINAL_AUDIT_GODOT_FINDINGS.md` (correctness bugs live there). IDs are stable across both docs — G-08, G-10, G-11, G-15 moved here unchanged; GO-## items are perf observations promoted from earlier findings text.

**Ground rules:** measure before/after (numbers in the PR); behavior-preserving only — the `scanner-cases.json` / `tests/contract` suites pin behavior, so any contract diff during a perf change is a bug in the change. Mirror discipline still applies where an optimization touches mirrored code paths (but TS mirrors usually need no port — `charCodeAt` is already cheap; the contracts pin behavior, not implementation).

**Runtime verdict up front:** ~~`addons/reactive_ui/core` needed no perf findings~~ — **SUPERSEDED 2026-07-07.** The static-analysis pass missed the runtime hot path because the stress-test benchmark only exercises the reconciler's *cheapest* path (stable keys, plain props). Profiling the Doom demo under a churning-keys + `style={{...}}` workload — the case a real app hits — exposed genuine, measured, fixable reconciler inefficiencies. These are now the **top priority** (§0 below). The tooling-side work (§1–§5) remains valid but is secondary.

---

## 0. CRITICAL — reconciler runtime hot path (DO FIRST) — added 2026-07-07

**Why critical:** the Doom demo (`examples/demos/doom`) runs ~25fps where the Unity original runs 40–60fps, on the SAME algorithm. Root-caused by a head-to-head read of both libraries' reconcilers (Godot `addons/reactive_ui/core` vs Unity `ReactiveUIToolKit/Shared/Core/Fiber`) + a controlled Godot-only measurement. **Not** the raycast, **not** rendering (24 draw calls — GPU is idle), **not** element count (byte-for-byte parity with Unity), **not** memo (both inline the bands; neither memoizes — verified). It is two Godot-library reconciler costs the stress test never triggers.

### Ground-truth measurement (the harness to reproduce for every before/after here)
Reconcile+commit only, 2384 nodes, headless, NO raycast/textures/game-code (a throwaway `SceneTree` script mounting N `V.color_rect` under `ReactiveRoot` and re-rendering via a `useState` setter — recreate it as `tests/recon_bench.gd`, keep permanently):

| Workload | ms/frame | note |
|---|---|---|
| stable keys, position only | ~26 ms | = the stress test; ties Unity |
| + plain props (size, color via `node.set`) | ~26 ms | **plain props are ~free** |
| + `style={{modulate:color}}` dict | ~42 ms | **+16 ms** = the style path (~6.8µs/styled node) |
| churning keys ~14%/frame + rich props | ~98 ms | **+50 ms** = mount/unmount churn (~73µs per mount+unmount pair) |

So the two cost centers are **key churn** and **the `style` dict apply**. Fixes below are ranked by leverage; do them in *ascending risk* order (GO-06 → GO-08 → GO-07 → GO-05) so the safe wins land first and de-risk the harness before the node pool.

### RESULTS ROUND 2 (2026-07-07, after profiling Doom with Godot's Script profiler — the REAL churn fix)
The profiler showed the moving-frame cost is dominated by scene-tree CHURN: `_commit_placement`
(add_child) 9.8ms + `reset_for_pool` (remove_child) 6.3ms + `_reconcile` 15.6ms — because Doom's
floor/ceiling bands are keyed by `slab_id`, which changes every frame the camera moves, so the keyed
path deletes+recreates ~186 band nodes/frame. A research workflow (web + code, adversarially verified)
found: the reconciler ALREADY has an in-place fast path (`_try_fast_leaf_list`) that kills BOTH the
tree churn AND `_reconcile`; the bands just miss it (variable count, mixed ColorRect/TextureRect in one
flat `<Control>`, churning keys). Two changes fix it:

- **GO-09 core: `reuse_by_slot` opt-in** — `_try_fast_leaf_list` gains an `ignore_keys` mode (gated by a
  `reuse_by_slot` prop on the parent, RESERVED in host_config) so a stateless-leaf list whose KEYS churn
  but whose count+type stay stable reconciles BY SLOT (in-place prop UPDATE, no add/remove/free, and it
  adopts the new key to stay on the fast path). Measured on `recon_bench`: churning 2384 ColorRects
  **83ms → 48ms (42% off)**. Contract: childless host leaves with no ref/focus/state (the caller
  asserts it). `+ _test_reuse_by_slot` (asserts node reuse + ZERO churn via diagnostics + opt-in gate).
  Default-off — existing keyed lists byte-identical.
- **Doom restructure**: each churning band group (ceiling/floor/floor-rim/extra-seg/extra-rim) wrapped
  in its OWN stably-keyed `<Control>` container with UNKEYED children. Isolated + single-type + unkeyed
  → the bands reconcile by slot/position (fast-leaf on stable-count frames, index-path reuse of the
  shared prefix with only the count-delta churning otherwise) instead of the whole-viewport keyed churn.
  **Measured: churn ~355 ops/frame → 8 (0 placements, 8 deletions) = 98% reduction; headless moving
  frame ~40ms → 16.0ms (~2.5×).** Element count preserved (2388: +5 group containers). doom/demos/all
  14 suites green. (Note: emits advisory GUITKX0106 "no key" warnings — the unkeyed choice is deliberate
  for slot reuse; a future guitkx tweak could suppress them under a reuse_by_slot/unkeyed container.)

GO-10 (reverse-order deletion) DEFERRED — a free general win for churny lists that DON'T hit the fast
path, but it doesn't help Doom post-restructure (no churn) and is fiddly with mixed component/host
fibers; documented for later.

### RESULTS ROUND 1 (implemented 2026-07-07, measured via `tests/recon_bench.gd`, all 14 CI suites green)
| Fix | Status | Measured | Verdict |
|---|---|---|---|
| **GO-06** style-apply alloc removal | **SHIPPED** | style overhead (C−A) **69ms → 19.6ms (~72% off)** for 2384 styled nodes | **big win** — the alloc-heavy `.get(ch,{})`/`.keys()` were the cost |
| **GO-05** host-node pool | **SHIPPED** (flag `RUIConfig.host_node_pool`, default on) | churn **−2%** for cheap ColorRect, **−8-9%** for Button — scales with node instantiate cost | real, correct, scales with node cost; largest for expensive/custom controls |
| **GO-08** keyed-diff dedup | **SHIPPED** | ~1-3ms of churn | small, clean, correct (mark-and-sweep, no per-frame dicts) |
| **GO-07** placement/reorder | **SKIPPED** | reorder measured at only **2.3ms/frame** | not worth child-order-correctness risk |

**Honest bottom line:** GO-06 is the real win (the style path was doing ~14 throwaway allocations per
styled node per frame). The churn cost is dominated by per-node vnode rebuild + prop-apply + native
scene-tree add/remove — largely inherent to a retained-node reconciler in GDScript; the node pool
(GO-05) shaves the instantiate/free edge (more for heavy nodes). Net: churn-heavy + styled UIs (Doom,
big dynamic lists) get materially faster; static UIs are unaffected (pool no-ops, style fast-path is
strictly cheaper). Also fixed a latent test bug (a stray `quit()` in `_test_signal_rebind` was
skipping the tests after it); added `_test_host_node_pool` (recycle→reuse reset contract) and the
permanent `tests/recon_bench.gd` harness.

### GO-05 — No host-node pool: every churned key destroys+recreates a NATIVE Control (biggest lever)
- **STATUS: SHIPPED 2026-07-07** (see RESULTS table above).

- **Measured share:** the dominant slice of the +50ms churn (~73µs per mount+unmount pair).
- **Root cause:** mount `reconciler.gd:600` → `RUIHost.create_node` (`host_config.gd:27-31`, `ClassDB.instantiate` — a heavyweight native object: a `CanvasItem` with RenderingServer registration); unmount `reconciler.gd:874-878` `_free_host_nodes` → `node.queue_free()` (native destruction). No recycling. Unity's `VisualElement` is a pure managed object (`FiberHostConfig.cs` `adapter.Create()` / `parent.Remove()` — GC reclaims off the hot path), so the identical churn is ~10× cheaper. Unity doesn't even pool elements; managed alloc simply beats native construct/destruct.
- **Fix (production-grade):** a class-keyed host-node free-list on `RUIHost`.
  - `host_config.gd create_node(type)`: `static var _pool := {}` (class → `Array[Node]`); pop+return a recycled instance of that exact class before `ClassDB.instantiate`.
  - `reconciler.gd:877` (`_free_host_nodes`): replace `queue_free()` with `RUIHost.recycle_node(node, fiber.props)` — the fiber carries `.props` (last-applied), so **no per-frame tracking is needed**. `recycle_node` must make the node *indistinguishable from a fresh `instantiate`* (correctness-critical — mount calls `apply_props(node, {}, new)` which does NOT diff-clear stale state):
    1. `remove_child` from parent (eager detach; also fixes GO-07 index math — a deferred `queue_free` node lingers in the parent's child list).
    2. Disconnect all `__rui_events` + `remove_meta("__rui_events")`.
    3. `_remove_custom_draw(node)` (drops `__rui_draw`/`__rui_draw_tramp`, disconnects the `draw` trampoline).
    4. `RUIStyle.apply(node, _effective_style(props), {})` — reuses the existing style-reset path to clear modulate/theme-overrides/styleboxes the style set.
    5. Reset plain props to class defaults: for each non-reserved non-event key in `props`, `node.set(k, ClassDB.class_get_property_default_value(cls, k))` — **cache `(class,key)→default` in a static dict** so it isn't a per-recycle ClassDB lookup.
    6. Remove one-time metas (`__rui_boxw`, `__rui_state_w_*`, `rui_content`).
    7. Push into `_pool[cls]` with a per-class cap (~256); overflow → `queue_free`.
  - `unmount()` (`reconciler.gd:982`): drain the pool (`queue_free` all) so a torn-down root leaks nothing.
- **Correctness invariants / hazards:** (a) recycle only SAME class (per-class pool). (b) The reset in step 5 relies on the deleted fiber's `.props` capturing every plain key ever set on the node — true, because `apply_props` sets from `new_props` and the fiber stores `pending_props`→`props` each commit; a key set once and later omitted is the documented audit-#23 "removed plain prop not reset" case, which the class-default reset now actually *fixes* for pooled nodes. (c) `queue_free` is DEFERRED (frame-end, off the measured window), so the in-window win is the `instantiate` avoidance; the `queue_free` avoidance is a real but off-window frame-time win — **measure the isolated instantiate-vs-recycle delta**, don't assume the full ~20-25ms. (d) A recycled node must have had its `ref` nulled (already done by `_null_refs_recursive` before free) and its passive/layout cleanups run (already done by `_run_cleanups_recursive`) — keep that ordering.
- **Test:** `recon_bench.gd` churning scenario before/after (net win after reset cost); a new `tests/core_test.gd` case that churns keyed host elements with events+style+draw_fn+ref and asserts the recycled node behaves as fresh (no leaked signal, no stale modulate/size, ref nulled); full `core_test`/`demos_test`/`update_test` green; the Doom boot path.

### GO-06 — `RUIStyle.apply` does fixed-shape allocation-heavy work per styled node (safe drop-in, do FIRST)
- **Measured share:** ~half of the +16ms style cost (~6.8µs/styled node → target ~3µs).
- **Root cause (`style.gd:54-69`):** for a style holding one key (`modulate`), `apply` still: allocates **12 throwaway empty Dictionaries** via `old_style.get(ch, {})` / `new_style.get(ch, {})` eager `{}` defaults over 6 `THEME_CHANNELS` × (old+new); allocates **2 Arrays** via `old_style.keys()` / `new_style.keys()`; and does ~16 hash-probes over box/state/theme keys that are never present. Unity diffs a pooled bitmask-tracked typed `Style` in O(set-bits) with zero heap alloc.
- **Fix (behavior-preserving):**
  - `style.gd:55-56`: null-default get (`old_style.get(ch)`), `continue` when both null; only materialize `{}` in the rare branch a channel is actually present (normalize null→`{}` there for `_apply_theme_map`).
  - `style.gd:61,65`: `for k in old_style` / `for k in new_style` (direct dict iteration — no `.keys()` Array; the exact `[perf]` pattern `host_config.gd:55,60` already uses).
  - Optional follow-up (measure first): a cached per-call key classification so the `BOX_KEYS`/`STATE_SLOTS`/`THEME_CHANNELS` probing is O(actual keys) not O(16). Only if profiling after the alloc removal still shows probing cost.
- **Residual (inherent-GDScript, not fixed here):** the style *value* is a Godot Dictionary rebuilt by render code every frame with string-keyed Variant hashing; GDScript has no cheap value-struct. Design-level escape hatch (separate item): steer per-frame `modulate`/`rotation` to PLAIN node props (measured ~free) instead of `style={{...}}`.
- **Test:** `recon_bench.gd` scenario C (style) before/after; `style_test.gd` green (pins behavior); `demos_test.gd`.

### GO-07 — Append-then-full-parent-reorder on every structural frame — SKIPPED (measured negligible)
- **STATUS 2026-07-07: NOT shipped.** Instrumented `_commit_root`'s three phases directly under the
  churn workload (2384 nodes, ~14% churn/frame): deletions ~6ms, effects(place+update) ~26ms,
  **reorder ~2.3ms**. The reorder is already cheap — the `_keys_stable` fast path + structural-only
  `_mark_reorder` gate keep it off the hot path in practice. A ~2.3ms ceiling does not justify the
  risk of restructuring child-ordering (z-order/tab-order correctness). The dominant churn cost is
  the per-node vnode rebuild + prop-apply (render ~43ms + effects ~26ms), which is fundamental, not
  the reorder. Left as-is. Original analysis kept below for the record.
- **Measured share:** part of the +50ms churn.
- **Root cause:** `_commit_placement` (`reconciler.gd:662-668`) always `add_child`s new nodes at the END; then `_enforce_child_order` (`847-861`) allocates a fresh ~2384-entry `ordered` Array (`_collect_host_children`, `863-872`) and does a full O(n) `get_child` scan + `move_child` per misplaced node, for every parent in `_reorder_set`. Unity computes a host-sibling anchor (`GetHostSibling`) and `InsertBefore`s each new node at its final index with NO reorder pass, and never repositions reused survivors.
- **Fix:** `_commit_placement`: resolve a host-sibling anchor (port Unity's `GetHostSibling`) → `add_child` + a single `move_child` to the target index (or `add_sibling`) so new nodes land in place. `_enforce_child_order`: for pure insert/delete, narrow to the dirty index range instead of reallocating the full ordered Array every structural frame. Compose with GO-05's eager `remove_child` (so pending-free nodes don't pollute index math).
- **Test:** `update_test.gd` (keyed reorder/insert/delete — pins ordering behavior) green; `recon_bench.gd` churn before/after; a keyed-shuffle stress in `demos_test.gd`.

### GO-08 — Full keyed path allocates two Dictionaries/frame + redundant `matched` set
- **Measured share:** part of the +50ms churn (~3-6ms; during churn ALL 2384 children run this path, not just the ~334 churning).
- **Root cause (`reconciler.gd:449-475`):** fresh `key_map` (449) + `matched` (454) Dictionaries per call; ~5 Variant/Object-keyed dict ops per child. Unity reuses one `[ThreadStatic] s_childMap` via `Clear()` (zero alloc) and needs no second set — it erases a key on reuse and deletes the map remainder.
- **Fix:** hoist `key_map` to a persistent per-reconciler member (`var _key_map := {}`), `clear()` at the top of the full-keyed branch. Drop the `matched` dict: on a successful reuse `key_map.erase(_vnode_key(vn,i))` instead of `matched[old_match]=true` (461); replace the `matched.has(old_match)` guard (458) with a check that the key still maps (a duplicate-key second use finds it erased → treated as new, same as today); the trailing delete loop (470-475) deletes whatever old fibers remain in `_key_map.values()`. Same match/delete outcome.
- **Re-entrancy check (do before implementing):** confirm `_reconcile_children`'s full-keyed branch is never re-entered before it finishes (it calls `_reconcile`, which creates/updates a fiber but does NOT recurse into `_reconcile_children` — children reconcile later in the work loop). If confirmed, one reused member `_key_map` is safe; if not, keep it local. Per-reconciler member (not `static`) so multiple `ReactiveRoot`s don't share.
- **Test:** `update_test.gd` + `core_test.gd` keyed cases green (duplicate-key, reorder, delete); `recon_bench.gd` churn before/after.

### Not fixable in the library (documented, not attempted)
- **Native scene-tree ops** (`add_child`/`queue_free`/`move_child` fire `ENTER_TREE`/`EXIT_TREE`/`MOVED_IN_PARENT` notifications + container layout invalidation synchronously; Unity batches layout once per frame in the panel pass). This is the half of churn a node pool can't remove — Godot scene-tree architecture, not a library bug. Bounded partial mitigation only (visibility-toggle a parented pooled node instead of reparent, same-parent-same-class only) — do NOT attempt as a general fix.
- **GDScript dict-API + Variant tax** on the per-frame style dict (GO-06 residual). Language speed.

---

## 1. P1 — Scanner character access (the big one)

### G-10 — All GDScript scanners use `src[i]` single-char-String indexing — **DONE, ALL 4 STAGES (2026-07-10)**
- **STATUS:** fully converted to `unicode_at` + int consts across the compiler stack AND the editor
  tokenizer: stage 1 `guitkx_lexer.gd` (hosts the shared `C_*` const table), stage 2
  `guitkx_markup.gd` inner loops (+ G-08), stage 3 `guitkx.gd`'s ~25 scan sites across 26 functions
  plus `guitkx_jsx_scan.gd`, stage 4 `guitkx_tokenizer.gd` (the per-keystroke highlight path; the
  highlighter itself has no char reads — it delegates). Measured (`tests/guitkx_bench.gd`, permanent
  harness, 12.4 KB doom component): full compile **71.96 → ~51-52 ms (-28%)**, `skip_noncode`
  whole-file walk **4.58 → 2.65 ms (-42%)**, tokenizer whole-file tokenize **8.4 → 7.0 ms (-17%)**.
  Verified behavior-preserving: all contract cases; guitkx/core/style/update/demos/doom suites
  green; all 49 example `.guitkx` recompile **byte-identical**; the tokenizer's full token stream
  over all 49 files × both modes is **hash-identical** to pre-conversion. Public String APIs kept
  (`_is_ident(String)` delegates to `_is_ident_code(int)`).
- **Lessons (measured, for future scanner work):** `unicode_at`+int is ~4x faster than
  `s[i]`+String inline, BUT (a) a GDScript `match` with many patterns compiles to LINEAR
  interpreted compares — a 22-arm match made the tokenizer 64% SLOWER than the old
  `String.contains()`; the fix is a `const` int-keyed Dictionary set (`.has` = one C++ hash);
  (b) flatten hot char-class helpers into a single body — nested helper calls cost more than the
  int compares they save; (c) `const L = GlobalClassName` is not a constant expression in 4.7 —
  use `preload()`. TS mirrors deliberately NOT ported (charCodeAt-style access is already cheap in
  JS; the shared contract corpus pins behavior). Adjacent surface NOT in this pass: the editor
  addon's `lsp/` layer (`guitkx_virtual_doc.gd` etc.) has its own `_src[i]` scanners — same recipe
  applies if in-editor LSP latency ever measures hot.
- **Anchors (historical):** `guitkx_lexer.gd` (0 uses of `unicode_at`), `guitkx_markup.gd` (0), most of `guitkx.gd`, `guitkx_tokenizer.gd`/highlighter. In GDScript 4, `s[i]` allocates a fresh 1-char String per access and comparisons are string-compares. These loops run per keystroke (highlighter, live diagnostics), per save (compiler), and per poll tick (watch sweeps).
- **RECIPE:**
  1. Convert the LEXER first (`skip_noncode`, `_skip_string`, `find_matching`, `keyword_at`, `_is_ident`): `var c := src.unicode_at(i)` + int-constant comparisons (named `const` ints at the top: `const C_HASH := 35`, `C_QUOTE := 34`, …).
  2. Run the scanner contract tests after EACH function conversion.
  3. Then `guitkx_markup.gd` inner loops (`_parse_nodes`/`_parse_element`/`_parse_attribute`), `guitkx.gd` hot scanners (`_find_decl`, `_split_return`, `_split_body`, `_validate_*`, `_hook_signature`), and the editor tokenizer/highlighter.
  4. Measure with the method noted at `guitkx_editor_view.gd:13` (~2.1 ms/KB baseline) and update that comment with the new number. Expect an order-of-magnitude reduction in scanner cost.
- **Coordination:** the findings-doc G-01 fix adds `skip_noncode_markup` — write that new function in the `unicode_at` style from day one so it doesn't need a second pass.

## 2. P2 — Parser/compiler algorithmic costs

### G-08 — `_line_of` is O(n²)-with-allocation on element-heavy files — **DONE (2026-07-10)**
- **STATUS:** fixed in BOTH mirrors. `guitkx_markup.gd`: `_line_starts: PackedInt32Array` built once
  per `parse()`, `_line_of` = binary search (substr-count fallback kept for pre-parse calls).
  `markup.ts`: the equivalent per-call O(idx) scan in `lineOf` replaced with lazily-built
  `lineStarts` + the same binary search (this one runs per keystroke in the LSP). Line numbers
  identical (suites + 180 lsp tests + byte-identical corpus).
- **Anchors (historical):** `guitkx_markup.gd _line_of` (l.396): `_src.substr(0, idx).count("\n")` — a full prefix COPY per element node.

### GO-01 — `guitkx.gd compile()` re-scans per tier
- `_split_return`, `FindJsx`-style walks, `_validate_hooks`, `_validate_effect_deps`, and `_hook_signature` each walk setup/body text independently per compile. Compile cadence is per-save (not per keystroke), so this is acceptable today; if profiling after G-10 still shows compile > ~50 ms on large files, share one pass that produces (line starts, hook-call offsets, jsx spans) consumed by all tiers. Do NOT restructure preemptively.

## 3. P2 — Editor addon / sweeps

### G-11 — Poll sweep rewalks the tree per tick (bounded; optional)
- **Anchors:** `guitkx_codegen.gd has_stale()` — dir walk + 1-2 mtime reads per file per tick, early-exiting; plus one small sidecar JSON read per tracked file for the 2107 dangling-refs check (cost documented in-code at l.171-180).
- **RECIPE (only if projects grow into hundreds of components):** cache the walk list; invalidate from the plugin's existing `filesystem_changed` debounce (`plugin.gd _on_fs_settled`). Keep the early-exit ordering (compiler_changed → mtimes → sidecars).

### GO-02 — Editor live pipeline — verified good, keep the invariants
- Debounced (`_debounce` Timer, adaptive from `_last_compile_ms` — P1), live compile size-capped (`MAX_LIVE_COMPILE = 150_000`), `project_bindings()` cached against filesystem shape (~35 ms / 100 files, never per tick). No action; when touching `guitkx_editor_view.gd`, preserve these three properties — they are the addon's responsiveness contract.

## 4. P2 — LSP server startup

### G-15 — Synchronous workspace scan + library load inside `onInitialize` — **DONE (verified 2026-07-10)**
- **STATUS:** fixed — the scan runs behind `connection.onInitialized` (verified in `server.ts`); the
  companion findings G-18 timeout (2s CancellationTokenSource in VS2022 format-on-save) also shipped.
- **Anchors (historical):** `ide-extensions/lsp-server/src/server.ts:95-100` — `scanWorkspace` + `loadLibraries` + `syncAllGuitkxLibraries` ran before the initialize response returned → cold-open LSP latency on big projects; **also the direct enabler of the VS2022 save-hang (findings G-18)** — a save issued during the scan window blocked on the busy server.
- **RECIPE (as executed):** move the three calls into `connection.onInitialized(...)` behind a `workspaceReady` promise; handlers await it or degrade gracefully (they already tolerate empty indices).

## 5. Suggested order & measurement
1. **G-10** lexer conversion (contract-pinned, mechanical, biggest win) — before/after ms/KB in the PR.
2. **G-15** (with findings G-18) — cold-open time-to-first-hover.
3. **G-08** — parse timing on an element-heavy file (generate one with `dev/gen_markup_fixtures.gd`).
4. **G-11 / GO-01** — only with measurements showing need.

## 6. Doom demo — runtime reconciler/game-loop profiling (2026-07-06)

> **SUPERSEDED IN PART (2026-07-10):** the renderer described below (per-column portal ray-walker)
> is no longer the default. A 2D BSP (`examples/demos/doom/doom_bsp.gd`, gated by
> `GameLogic.USE_BSP`, built once per level, cached on `GameState.bsp`) now fills the same
> `columns[]` front-to-back — distance-independent (no MAX_RAY_HOPS cap) and **1.46–2.53× faster
> per frame across L1–L6** (`tests/doom_bsp_bench.gd`; columns match the ray-walker to <1px via
> `tests/doom_bsp_cmp.gd`). The ray-walker remains as the fallback path, so the GO-03/GO-04 notes
> below stay valid for it; GO-03's un-pooled `ColumnInfo` (160/frame) now applies to
> `DoomBSP.render_frame` as well. The "still render-bound in dense views" conclusion (reconciler
> ~11µs/node) is unchanged and remains the open core-library lever.

Measured while diagnosing the interactive "feels jumpy/slow" report during Phase 2 of
`plans/DOOM_GAME_GUITKX_PORT_PLAN.md`. Scope note: unlike sections 1-4 above (all
`.guitkx` tooling/compiler perf), this section is about `addons/reactive_ui/core`'s
runtime reconciler + a specific demo's hot path — kept here since it's the same
"measure before touching anything, behavior-preserving only" discipline this doc
already enforces, not a new document.

**Headline numbers** (`godot --headless`, debug build, no display server —
`examples/demos/doom` mounted standalone, `DoomGameScreen.render` via `ReactiveRoot`):
- Idle (no input): **~18.6 ms/frame (~54 fps)**
- Moving (forward held, occlusion churns every tick): **~40 ms/frame (~25 fps)**
- An earlier ~147 ms/frame reading was a **self-inflicted test bug** (the profiling
  script called `GameLogic.new_game()` — which rebuilds the whole level's sector/portal
  graph — once per loop iteration; not present in real gameplay). Retracted; the
  numbers above are the clean measurement with nothing but the real
  `physics_frame`-driven tick loop running.

### Ruled out (checked, not the cause)
- **Not over-rendering vs. the original.** Read the Unity source's
  `DoomGameScreen.uitkx`/`DoomGameScreenLogic.uitkx` side by side — identical
  per-element keyed strategy (`@foreach` + `key={"cb"+...}` etc.) for the same
  ~2000+ wall/band/sprite/tracer elements every frame, including the same
  not-actually-merged `BuildMergedFloorBands` (its doc comment says "collapses
  into a single wide rect" but the body never extends `ColEnd` past `ColStart` —
  true in the original too, not a porting mistake).
- **Not an O(n²) reconciler diff.** `reconciler.gd` already has a positionally-stable
  fast path (`_keys_stable`) and a hashmap-keyed diff (`key_map`) for the unstable
  lists — both O(n).
- **Not raw Godot node overhead.** Creating/mutating 2384 real Control nodes directly
  (bypassing the reconciler) costs 1-7 ms total, not per element.
- **Not an anomalous reconciler regression.** `tests/bench.gd`'s own synthetic
  benchmark (N keyed ColorRects, position-only updates) measures ~21 ms/frame at
  N=2000. Doom's ~18-22 ms of *actual* reconciler+host-apply work (once the
  contaminated `new_game()` cost is subtracted out) lands in the same ballpark —
  the library performs in line with its own benchmark.

### GO-03 — `build_column_sector` allocates ~17 RefCounted objects/column every tick — DONE (leaf types, 2026-07-06)

**Status: implemented for the leaf records (WallSeg/FloorBand/CeilingBand).** A per-frame
linear allocator lives on `DoomTypes.FrameData` (`_wallseg_pool`/`_floorband_pool`/
`_ceilband_pool` + `reset_pools()` + `take_wallseg/floorband/ceilband()`); each type got a
`reset()` that reproduces `.new()`'s exact defaults, so a recycled instance is
byte-identical to a fresh one. `cast_frame` calls `reset_pools()` at the top; the 13 leaf
`.new()` sites in `build_column_sector`/`cast_frame` became `st.frame.take_*()`. Measured:
`cast_frame` ~18.5ms → **~16.86ms/call** (~1.65ms/frame, ~9% of the raycast cost). Steady
pool sizes from level-1 spawn: 160 wallseg + 1203 floorband + 1005 ceilband (~2368 band
records/frame now recycled). All 144 doom tests + demos/core suites still green (behavior-
preserving). Safe because the reconciler's render (call_deferred `_tick`) fully consumes a
frame before the next tick, and `time_slicing` is off. *(Correction 2026-07-31: the 0.14
family-parity campaign flipped the global `time_slicing` default to ON, invalidating the
"off by default" leg of this proof; DoomGameScreen now pins `time_slicing = false` for its
own lifetime — the L-07 sync-pin effect in `doom_game_screen.guitkx` — which restores the
invariant.)* **Still open:** `ColumnInfo` itself
(1/column = 160/frame) is deliberately NOT pooled yet — its many return sites each set
different subsets of fields, so fill-in-place carries more risk for less gain; revisit if a
heavier level needs it. Original notes below kept for context.

---

### GO-04 — `ray_segment()` returned a Dictionary per line-test — the real cast_frame cost — DONE (2026-07-07)

**The big one for "slow when moving into a new room."** Root-caused by profiling: with a
temporary `SKIP_CAST` toggle, `cast_frame` split cleanly from the render cycle. Open rooms
are *raycast*-bound (few visible nodes but each ray does ~11-30 portal hops because the map
is one-sector-per-tile), and the hop inner loop called `Raycast.ray_segment()`, which
returned a fresh 4-string-key **Dictionary** on every line-of-every-sector-per-hop test —
~7,000-19,000 Dictionary allocations + string-key hashes per frame. The original uses
`out float t, u, bool backside` (zero allocation). Fix: inline the ray-segment math into
`cast()`'s inner loop (same math, u only evaluated once a line beats best_t; behavior-
identical) and pool the per-hop `WallHit` records (pool caps at MAX_RAY_HOPS=16). Measured:
`cast_frame` 16.6→10.4ms at spawn, 13.7→7.0ms in a corridor (37-49% off). **Full mounted
frame in the open room the user complained about: ~40ms → 12.4ms (~25fps → ~80fps CPU).**
All 155 doom + 31 demos + 114 core tests green. `ray_segment()` itself kept (a test pins its
Dictionary API; it's off the hot path now). Anchors: `examples/demos/doom/raycast.gd`
`cast()` inner loop + `_wallhit_pool`.

**Still render-bound in dense views.** At spawn (2383 visible nodes) the frame is ~38ms, of
which ~27ms is render+reconcile+commit — the reconciler's inherent ~11µs/node (matches
`tests/bench.gd`, NOT a Doom bug). Cutting that without reducing element count (which the
demo deliberately keeps high to stress the reconciler) is a core-library task: profile
`host_config.apply_props`/`style.gd`/the diff hot path for per-node waste. Not yet done —
this is the "optimize the core reconciler" lever, separate from the Doom port.

---

### (original) GO-03 — `build_column_sector` allocates ~17 RefCounted objects/column every tick
- **Anchors:** `examples/demos/doom/game_logic.gd:552-1023` (`build_column_sector`) —
  7x `DoomTypes.WallSeg.new()`, 4x `ColumnInfo.new()`, 3x `FloorBand.new()`, 3x
  `CeilingBand.new()` per call, invoked once per ray column (`VIEW_W` = 160) every
  single tick regardless of movement — this is the dominant per-frame cost (`cast_frame`
  alone measures ~18.5 ms, i.e. nearly all of the idle frame budget).
- **Root cause:** the original C# types are `struct`s (stack-allocated, no GC/refcount
  pressure); the plan's struct→class translation (GDScript has no value types) made
  every one of these a heap-allocated `RefCounted`. Measured directly: 160 cols × 17
  allocs × 60 frames as fresh `RefCounted`-derived objects costs **3.6 ms/frame**;
  the identical shape as plain `Dictionary` literals costs **1.0 ms/frame** — so the
  class-vs-struct choice alone is worth ~2.6 ms/frame (~14% of `cast_frame`), and the
  remaining ~15 ms is the actual trig/DDA/occlusion-window math, which is expected to
  be slower in interpreted GDScript than JIT-compiled C# for this kind of tight
  numeric loop and is not something a data-representation change fixes.
- **RECIPE (not yet applied — pooling, deferred per user request 2026-07-06):** give
  `GameState`/`FrameData` a pre-sized pool of `WallSeg`/`ColumnInfo`/`FloorBand`/
  `CeilingBand` objects (indexed by column, reused across ticks — reset fields at the
  top of each `build_column_sector` call instead of `.new()`). Behavior-preserving:
  same objects, same field values, no algorithm change, no visual/element-count
  change — measure `cast_frame` ms/call before/after directly (isolated timing already
  exists as a throwaway pattern in this investigation; make it a permanent entry in
  `tests/bench.gd` or a new `tests/doom_bench.gd` once applied).
- **Open question raised by the user, not yet investigated:** does
  `addons/reactive_ui/core` itself have a similar per-frame `RefCounted`/Dictionary
  allocation pattern in the hot path (`host_config.gd apply_props`, `style.gd apply`,
  fiber creation in `reconciler.gd`) that would benefit ALL demos, not just Doom? Not
  checked yet — worth a follow-up profiling pass before deciding whether pooling is a
  Doom-only fix or a core-library one.
