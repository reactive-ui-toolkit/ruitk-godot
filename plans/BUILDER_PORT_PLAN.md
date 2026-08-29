# Porting the RUITK Builder to Godot — execution plan

**Goal, stated once:** port the RUITK UI Builder **as it exists in Unity today** to
Godot, at **full parity, in one version**. Not a subset, not a staged release.

**Build order is incremental; the delivery is not.** Each checkpoint below is
implemented, self-tested and gated green before the next begins. They are internal
verification points — there is no "v1 then improve".

**Companion:** `plans/BUILDER_PORT_GUIDE.md` — the Unity leg's handoff (WHAT and WHY).
This file is the Godot answer: what exists, what we build, and how each piece is proven.

Written 2026-08-27 against `ruitk-godot @ fix/markup-in-non-component` and
`ruitk-unity @ feat/ruitk-builder` (0.18.1).

---

## 0. Every seam is verified. There are no unknowns left.

The guide names the preview as the thing that "probably determines how much of the
builder is portable", and says to answer it before planning. Answered — by execution,
not reasoning. Everything here was run against this repo.

| # | Probe | Result |
|---|---|---|
| 1 | Compile a `.guitkx` buffer that never touches disk | ✅ |
| 2 | Materialise generated GDScript as a live script, no file | ✅ `reload() == OK` |
| 3 | Mount through the **real** reconciler | ✅ real `VBoxContainer`/`Label`/`Button` |
| 4 | Props + hook state on real nodes | ✅ `"desde memoria"`, `"n=3"` |
| 5 | Re-compile a changed buffer, re-render | ✅ `"n=99"` |
| 6 | **Two-module tree with nothing on disk** | ✅ child rendered through parent |
| 7 | Edit the **child** buffer, re-render through the parent | ✅ `Label` → `Button` |
| 8 | Capture rendered output to PNG | ✅ 1152×648, inspected by eye |
| 9 | **`.style.guitkx` style module compiles + applies** | ✅ `bg=(0.2,0.5,0.8)`, `radius=6` |
| 10 | **Mount inside a real Godot editor process** | ✅ `ALL PASS` — mount, props, state, re-render |

Probe 10 was the last unknown. A temporary `@tool` EditorPlugin compiled an in-memory
buffer, materialised it, mounted it into `EditorInterface.get_editor_main_screen()`,
and re-rendered on `set_root` — all inside `godot --editor`. The probe and its
`project.godot` entry were removed; the file is byte-restored.

**Conclusion: no architectural risk remains.** What is left is volume, not doubt.

---

## 1. Seam audit — Unity vs Godot

| Seam | Unity | Godot — verified | Verdict |
|---|---|---|---|
| **Parse → AST → print** | `Ruitk.Language` DLL | `guitkx_markup.gd` recursive-descent → Dictionary AST; `guitkx_formatter.gd` is **AST-driven re-emit** | ✅ exists |
| **Source positions** | implicit in the C# AST | every node carries `at`; attrs `vat`/`end`; directives `body_at`; offsets **compose** | ✅ better than expected |
| **Language services** | LSP over stdio, 4 custom requests | `addons/…_editor/lsp/` — **in-process GDScript**: schema, workspace, completion, hover, signature, refs, outline | ✅ no IPC |
| **Unsaved-buffer overlay** | purpose-built `SourceOverlay` | `guitkx_workspace.reindex(path, text)` already takes arbitrary text | ✅ exists |
| **Element registry** | `ElementRegistry.RegisteredNames` | `ClassDB` ∪ curated `vocabulary.json` `host_tags` | ✅ exists |
| **In-editor preview** | HMR compiler + domain reload | probes 1–7, **10** | ✅ simpler — Godot has no domain reload to fight |
| **Editor chrome** | `BuilderWindow.cs`, **6321 lines** | main screen registered; `guitkx_editor_view.gd` (1198), `guitkx_code_edit.gd` (560), tokenizer, Problems/References/Search panels | ✅ large head start |
| **Menu entry** | Unity menu item | `plugin.gd` already builds a top-level `Reactive UI Toolkit` `PopupMenu` with a `Project > Tools` fallback | ✅ two-line addition |
| **Runtime discovery** | `RuitkDotnetLocator.cs` | `.ruitk-local.json` chain + `check-machine-paths.mjs` gate | ✅ enforced |

### 1.1 The one language-level constraint — value imports are eager

Component imports lower lazily to `V.fc(V.comp("res://…/child.gd"), …)`. `V.comp` is a
path-keyed cache (`V._comp_cache`, `path::fn`) that only calls `load()` on a miss — so
seeding it makes a virtual path resolve to an in-memory script. That is how probe 6
rendered a tree with nothing on disk.

Value imports (hook / style / util modules) lower to `const Name = preload(path)`, and
**`preload` resolves at parse time and needs a real file**. Unity documents the same
asymmetry, so it is inherent to the language, not a Godot gap.

**D1.** The preview materialises *value-kind* modules to a scratch root inside `res://`
and points the generated `preload` there; component-kind modules stay fully virtual via
the `_comp_cache` seed. Mirrors Unity's `__RuitkBuilderUnsaved__~/`. Bounded: only
imported value modules, only during preview, only under a root the save contract owns.

> Rejected: rewriting value imports to lazy lookups for preview only — it would make the
> preview compile differently from the shipped build, the one thing a preview must not do.

### 1.2 Translation decisions (not gaps)

| | Unity | Godot | Decision |
|---|---|---|---|
| Module kinds | 4 | **5**: component, hook, util, **value**, **module** | Card kinds, badges and the create menu model **five** kinds |
| Style modules | `.style.uitkx`, typed exports | **`.style.guitkx` works today** (probe 9): `export primary := { … }` → `static var`, imported by name | **In scope.** No language change |
| Themes | — | `@uss "res://x.tres"` **and the `@theme` alias**; sets `theme` on the root unless set explicitly; one per file (`GUITKX2210`); accepts `res://`, `uid://`, `~/` | **In scope** |
| Directives | `@if/@else if/@else`, `@foreach`, `@for`, `@while`, `@switch/@case/@default` | `@if/@elif/@else`, `@for`, `@while`, `@match/@case/@default` | Map `@switch`→`@match`, `else if`→`elif`; no `@foreach` (GDScript `for x in y`) |
| Naming | filename encodes kind | basename is **not** identity since 0.10.0 — binding is the first exported decl, `@class_name` overrides | **D3** |
| Unused import | `UITKX2304`, error-tier | `GUITKX2300–2309`, error-tier, strict | "create never adds an import" **transfers unchanged** |
| Reload | C# domain reload | none — `GDScript.reload()` in-process | A whole Unity defect class does not exist here |

**D2 (style application).** Dragging a style module onto an element sets
`style={ Name }` and adds the import — Unity's gesture, verified working. `@uss`/`@theme`
covers whole-subtree theming. `RuitkStyleSheet.register` + `classes={}` is *runtime
registration*, not authoring, and is not part of the builder's surface.

**D3 (folder convention).** Adopt Unity's shape — component owns a folder, children under
`components/`, companions beside — because the argument is about predictability. But kind
is read from the **declaration** (`_enumerate_decls`), never from the filename. The
`.style.` infix is a **builder-level convention**; the compiler is not taught it.

---

## 2. Architecture

```
L0  document model      pure GDScript RefCounted; FileAccess/DirAccess only
L1  graph projection    tree + AST -> cards, rows, edges            (pure, testable)
L2  preview pipeline    buffers -> live scripts -> RuitkRoot        (verified, probes 1-7,10)
L3  canvas view         .guitkx, dogfooded, rendered by our reconciler
L4  chrome              Control-based: panes, menus, inline editor, source field
L5  integration         child item under the "Reactive UI Toolkit" menu
```

L0/L1 are pure and headlessly testable — that is where correctness lives, and where
Unity's 91-assertion `ModelTests` paid off most.

### 2.1 Invariants carried over verbatim (guide §2)

1. **Save-only disk contract** — nothing written until Save, including delete, rename,
   folder move. Sole exception: the preview scratch root (D1), cleared on teardown.
2. **The tree is the model; deletion is absence.** No `pending_delete` flags — Unity's
   entire save-contract defect cluster was "a caller forgot a flag".
3. **Create states placement; wiring states usage.** Applies — our unused import is
   error-tier too.
4. **One ledger, undo across files**, each change keyed by **module id**, not path.
5. **The canvas is dogfooded** `.guitkx`, and inherits our re-render semantics — see R1.

### 2.2 Module identity

Modules keep a stable id and their `.uid` sidecar across rename/move. Save projects a
**move**, never delete+create — churning file identity would break `uid://` references
in scenes.

---

## 3. Checkpoints

Internal gates, not releases. Each is green before the next starts.

| # | Checkpoint | Gate |
|---|---|---|
| **C0** | Document model — `builder_module`, `builder_tree`, `builder_workspace`, `builder_naming`, `builder_specifiers`, `builder_ledger`. Root resolution, moves, orphans, families, specifier arithmetic, cross-file undo | `tests/builder_model_test.gd`, ≥120 pure assertions, no editor |
| **C1** | Graph projection — cards, rows, edges; markup flattening with depth; directive heads/clauses as rows; hook chips; import rows; export entries. Every row carries its line range **and** AST offset | `tests/builder_graph_test.gd` — golden projections over a fixture tree covering all 5 kinds and all 4 directive families |
| **C2** | Preview pipeline — compile in import order, seed `_comp_cache`, scratch for value imports (D1), own frame budget, ~0.3s debounce, keep last good on failure | `tests/builder_preview_test.gd` — probes 1–7 as a suite, plus compile-failure recovery and scratch-cleanup-leaves-nothing |
| **C3** | Canvas — cards, section stack, 3 LOD bands, camera, Bezier edges in a screen-space overlay, anchor-dot column, culling | structural assertions **+ PNG capture per LOD** vs approved references |
| **C4** | Chrome — folder pane, library pane, source pane (reuse `guitkx_code_edit.gd`), diagnostics console (reuse Problems), context menus as an in-panel layer, one floating inline editor | synthetic `InputEvent` tests + PNG capture |
| **C5** | Edit operations — the full structural set through one funnel; drag/drop with the three bands | per-operation before/after buffer assertions; ledger round-trips to byte-identical source |
| **C6** | Save / abort / history / journal — batch write, save-time formatter pass, planned moves + specifier rewrites, delete-to-trash and empty-module prompts, layout keyed by tree **membership** | save/abort/undo matrix on a temp project, asserting exact disk state |
| **C7** | Integration — child item under the `Reactive UI Toolkit` menu; read-only package sources; docs | full battery green; existing suites and gates unperturbed |

### 3.1 Docs work (part of the port, not an afterthought)

Both surfaces are implemented and **taught nowhere**:

- **`.style.guitkx` style modules** — the docs site mentions the concept once, inside a
  code comment. Needs a real Styling section: authoring, importing, applying.
- **`@theme`** — the `@uss` alias appears in neither `vocabulary.json` nor the docs.
- The existing `styling.style.gd` demo is a hand-written `.gd` referenced ambiently. A
  `.style.guitkx` demo should exist so the convention has a shipped example.

---

## 4. Explicitly out of scope

Because Unity does not have them — parity means parity:

- Multi-select (Unity has none)
- Auto-layout / "tidy" (Unity has none)
- Rename-across-files beyond the module rename
- `.uxml` import — no Godot analogue. A `.tscn` → `.guitkx` importer is a separate
  project with its own design.
- Full chrome dogfooding — Unity's chrome is hand-built; ours will be too.

---

## 5. Risk register

| # | Risk | Evidence | Mitigation |
|---|---|---|---|
| **R1** | Pointer capture on re-rendered rows — the dogfooded canvas recreates rows, and our reconciler has the same property | **Downgraded.** The register still tags UB-30/31/32 `OPEN`, but `BuilderDragService.cs` has every fix: `CapturePointer`/`HasPointerCapture`, the ghost chip, and a class doc stating "hit-test from the captured pointer stream — never from render-state closures (UB-31)". **The tags are stale; the code is correct.** | A **solved model to port verbatim**. Still gate C5 on a drag test that re-renders mid-gesture. |
| **R1b** | Re-parenting an **existing** markup row is listed as unreliable | current `UI_BUILDER_CAPABILITIES.md`, Known non-capabilities — narrower than R1: library→canvas drag is fine | One operation to get right, not an architectural constraint. Build last in C5 with its own before/after assertions so ours is verified independently. |
| **R2** | Preview scratch leaks files into the user's project | D1 | Single scratch root, cleared on teardown *and* on open; gate asserts zero residue. |
| **R3** | `V._comp_cache` is global; virtual entries could shadow real files | probe 6 | Namespace virtual paths (`res://__ruitk_builder__/…`), clear on teardown; gate asserts a clean cache after unmount. |
| **R4** | Editor input arbitration — Unity's `StopImmediatePropagation` silently dropped queued handlers (UB-219), presenting as *one key doing nothing* | guide §4.7 | Godot's `accept_event()`/`_gui_input` differs but the hazard class is identical. Decide arbitration up front, document it in one place. |
| **R5** | Volume — Unity is ~20k lines plus seams | file map | Strict layering so L0/L1 land and stay green independently; each checkpoint separately gated. |
| **R6** | The guide is point-in-time and will drift | its own §9/§11 | Verify surprising claims against Unity **code**. Where guide and capabilities file disagree, the capabilities file wins on behaviour. |

---

## 6. Test strategy

Four layers, three fully automated. The aim is that **almost nothing needs your time**.

### 6.1 Pure model — no engine
`extends SceneTree` suites in `tests/`. Path arithmetic, tree ops, orphans,
naming/families, specifier round-trips, ledger undo/redo. Unity has 91 assertions;
target ≥120 given our fifth kind. **Catches the entire save-contract defect class.**

### 6.2 Render + visual capture ✅ proved
Mount through the real reconciler, assert on real Godot nodes — used throughout this
investigation.

**And screenshots work.** Headless has no renderer, but a windowed run captures
`get_viewport().get_texture().get_image().save_png()` — verified at 1152×648 and read
back visually. So every canvas state (each LOD, selection, drag hints, open menus, the
inline editor) gets a reference PNG, approved by you **once**, then diffed automatically
on every later run. I inspect any drift myself before it reaches you.

### 6.3 Interaction
Synthetic `InputEventMouseButton`/`InputEventKey` at the canvas, asserting model and
projection outcomes. Explicitly includes the R1 case: a drag whose gesture triggers a
re-render mid-flight.

### 6.4 What only you can do
1. Open the builder in a real editor once and confirm it opens on a real tree.
2. Approve the reference screenshots, once per visual state.
3. Judge feel — drag responsiveness, zoom comfort, whether menus land where you expect.
4. Confirm the save prompts read correctly before trusting Save on real work.

### 6.5 Continuous gates
Every checkpoint adds its suite to the battery and to `test.yml`. The existing gates
(`contract_dump --check`, corpus hash, machine paths, the three codemod tripwires) stay
green throughout — the builder is additive and must not perturb them.

---

## 7. Reading order on go

1. `Plans~/BUILDER_TREE_MODEL.md` — model rationale + the placement argument in full
2. `Document/*.cs` + `Builder~/ModelTests/` — port L0 against its own tests
3. `Canvas/BuilderGraphService.cs` (1513) — the projection; least portable-looking, most valuable
4. Defect clusters (guide §6) filtered per checkpoint — inline-editor cluster before C4,
   drag cluster before C5
5. `CanvasView.uitkx` (1276) — how much of the canvas our markup expresses
6. `BuilderWindow.cs` by **search only** — 6321 lines of handlers, looked up one at a time

---

## 8. Status

- All ten probes green; **no unverified seams, no architectural doubt**
- Full scope, one version, incremental construction with a gate per checkpoint
- Scope confirmed: style modules, `@uss`/`@theme`, five module kinds, four directive
  families, complete editing surface, save/abort/history/journal, docs
- Placement confirmed: child item under the **Reactive UI Toolkit** menu
- Unity source: ported **as it stands today**; later Unity work is a separate sync

**Not started.** Awaiting go.

<!-- Probes run against ruitk-godot @ fix/markup-in-non-component, Godot 4.7.stable. -->
