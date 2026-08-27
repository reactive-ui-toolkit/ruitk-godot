# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A **React-style reactive UI library for Godot 4.x, written in plain GDScript** — the Godot leg of the
**Reactive UI Toolkit** family, sibling of the C#/Unity
[Reactive UI Toolkit — Unity](https://github.com/reactive-ui-toolkit/ruitk-unity). Function components
return a virtual tree; a fiber reconciler diffs each render and patches only what changed on the real
Godot `Control` tree. State lives in hooks.

The repo actually holds **four independently-versioned deliverables**, each with its own version and
release gate (see `.github/workflows/publish.yml`):

| Deliverable | Location | Language | Version source |
|---|---|---|---|
| The runtime addon | `addons/reactive_ui_toolkit/` | GDScript | `plugin.cfg` |
| The in-Godot-editor `.guitkx` plugin | `addons/reactive_ui_toolkit_editor/` | GDScript | `plugin.cfg` |
| VS Code + VS2022 `.guitkx` extensions | `ide-extensions/` | TypeScript / C# | `package.json` / `.vsixmanifest` |
| Docs site | `RuitkGodotDocs~/` | React + Vite | `package.json` |

`RuitkGodotDocs~` is named with a trailing `~` so the Godot importer skips it (it's a Node/Vite
project, not Godot content).

## Commands

### Runtime tests (headless GDScript — the primary test loop)

Godot has no compile step; "tests" are `tests/*.gd` scripts run under `--headless`, each `quit()`ing
non-zero on failure. Run them exactly like CI (`.github/workflows/test.yml`), **in this order**:

```bash
# 1. Build the class-name cache FIRST on a fresh clone: guitkx_build's two-pass parse gate
#    reload()s every generated .gd, whose global class_name references (V, Hooks, RuitkVNode, ...)
#    only resolve once .godot/global_script_class_cache.cfg exists (49/49 false parse fails without).
godot --headless --path . --editor --quit || true
# 2. Compile every examples/**/*.guitkx to its sibling .gd (the generated .gd is git-ignored)
godot --headless --path . --script res://tests/guitkx_build.gd
# 3. Re-scan so the just-generated .gd class_names register for the suites
godot --headless --path . --editor --quit || true
# 4. Run a suite (this is also how you run a SINGLE test file)
godot --headless --path . --script res://tests/core_test.gd
```

(On a working tree that already has a `.godot` cache, step 1 is a no-op and the old
build-then-scan habit still works — the strict order only matters on a fresh clone / CI.)

The suites: `core_test.gd` (reconciler/hooks/effects/bailout/context/keyed), `settings_test.gd`
(the `reactive_ui_toolkit/*` Project Settings bridge), `scheduler_test.gd` (the four-lane
`RuitkScheduler` — lanes/budgets/batching — plus sliced-render integration),
`strict_boundary_test.gd` (the cooperative `RuitkFail` error-boundary latch + strict mode), `style_test.gd`,
`router_match_test.gd` + `router_spine_test.gd`, `update_test.gd` (diff), `demos_test.gd` (renders
every demo — the real check that generated `.gd` render without error), `doom_game_test.gd` (the
Doom demo end-to-end), `guitkx_test.gd` (compiler + codegen + imports/resolver/codemod),
`hmr_test.gd` (Fast Refresh), `guitkx_editor_test.gd` + `guitkx_lsp_test.gd` (editor addon),
`builder_model_test.gd` + `builder_graph_test.gd` + `builder_preview_test.gd` +
`builder_canvas_test.gd` + `builder_chrome_test.gd` + `builder_edits_test.gd` + `builder_save_test.gd` (the RUITK
Builder — the document model,
the canvas projection with
golden markup trees, the preview pipeline end to end, the canvas metrics/layout/host, and the
panes with the single edit funnel, every structural edit as a before/after string, and the
save/abort/undo matrix against exact disk state),
`builder_view_build.gd` (the addon's own `.guitkx` output is committed and must stay fresh),
`contract_dump.gd -- --check` (GD↔TS grammar goldens). `tests/guitkx_migrate.gd` runs the 0.10.0
import codemod over `examples/` (idempotent — a clean tree reports 0 migrated). `bench*.gd` /
`microbench.gd` are benchmarks, not pass/fail tests.

### IDE tooling (TypeScript language server + VS Code extension)

```bash
cd ide-extensions/lsp-server && npm ci && npm run build && node --test out/test/*.test.js && node scripts/smoke.js
cd ide-extensions/vscode     && npm ci && npm run build          # F5 in VS Code to debug
```

`@vscode/vsce` and `ovsx` are invoked via `npx` (not deps) to keep `npm install` small. The bundled
language server embeds a native napi addon (`@gdscript-analyzer/core`), so a packaged `.vsix` is
**platform-specific**. See `ide-extensions/README.md` for packaging, the VS2022 build, and publishing.

### Docs site

```bash
cd RuitkGodotDocs~ && npm ci && npm run dev     # or: npm run build / npm run lint
```

## Architecture

### Runtime (`addons/reactive_ui_toolkit/core/`)

The library exposes global `class_name`s — **no autoload or plugin-enable is required to use the
runtime**; the classes are available as soon as the files exist. Enabling the plugin only adds the
`.guitkx` compile-on-save integration.

- **`v.gd` (`V`) / `vnode.gd` (`RuitkVNode`)** — the ~71 `V.*` factories and the immutable UI
  description. **Naming is 1:1 loyal to Godot (0.9.0, plans/archive/NAMING_LOYALTY_PROPOSAL.md +
  MIGRATION-0.9.md):** element factories are named exactly after the Godot class they create
  (`V.Button`, `V.VBoxContainer`); tags = official class names (any instantiable ClassDB Node
  class is a valid tag); events = `on` + PascalCase(signal) (`onPressed`); style keys = exact
  Godot property/theme/StyleBoxFlat names. Only structural factories are lowercase — `V.fc` is
  the function-component factory (GDScript reserves `func`, so it's not `V.func`).
- **`hooks.gd` (`Hooks`)** — the 23 hooks. Call only at the top of a render, in a stable order.
- **`reconciler.gd` (`RuitkReconciler`)** — the fiber reconciler. **Render phase** (`begin_work`
  reconciles children + runs components descending, `complete_work` diffs/creates host nodes + builds
  the post-order effect list ascending) → **commit phase** (deletions → placement/update/layout effects
  → enforce child order → swap current↔wip → passive effects). Update renders are **time-sliced by
  default** (family parity): the loop yields on the `RuitkConfig.time_slice_ms` quantum and continues as a
  self-re-enqueueing `RuitkScheduler` Normal-lane slice under the cumulative `frame_budget_ms` budget;
  `time_slicing = false` opts back into the synchronous single pass. Mounts and HMR flushes are always
  synchronous; the commit is atomic either way. A hook setter calls `request_update()`, which
  **coalesces to one re-render per frame**; updates arriving mid-pass are **deferred and replayed after
  commit as one follow-up render** (never a restart — only a `RuitkFail` render failure restarts a
  pass; setState-in-render loops cap at depth 25). Bailout skips re-running a component whose
  props/state/context/children are unchanged.
- **`fiber.gd` (`RuitkFiber`)** — persistent tree node carrying the per-fiber `hooks` array (how hook
  state survives across renders). Fibers are double-buffered (each pass reuses the committed tree's
  ping-pong `alternate` buddies); cycles are severed explicitly for GC.
- **`scheduler.gd` (`RuitkScheduler`)** — the four-lane (High/Normal/Low/Idle) frame scheduler behind
  sliced renders (per-lane Callable dedup, Low-cancel under High pressure, Idle only on quiet frames,
  unbudgeted batched-effects flush). Lazy per-`SceneTree`, pumped from `process_frame` — no autoload.
- **`fail.gd` (`RuitkFail`)** — the cooperative render-failure latch: a failing render calls
  `RuitkFail.render(reason)` (GDScript can't throw) and the reconciler unwinds to the nearest error
  boundary.
- **`host_config.gd` (`RuitkHost`) + `style.gd`/`style_sheet.gd`** — **the only files that touch concrete
  Godot APIs.** This is the engine-boundary seam (the same one that lets React point a reconciler at
  react-dom vs react-native). `RuitkHost` maps props→node properties, `on<Pascal>`/`on_<signal>`→Godot
  signals (generic — no alias table), declarative `items`→item-model controls, and `draw_fn`→a
  register-once custom-draw trampoline.
- **Subsystems:** `router/` (React-Router-v6-style, +17 hooks on `RuitkRouter`), `signal_store.gd` +
  `signal_registry.gd` (`RuitkSignal`/`RuitkSignals` cross-component state), `suspense.gd`, `media.gd`
  (`useSfx`/`useAnimate`/`V.audio`/`V.video`), `context.gd`, `diagnostics.gd`.
- **Mount surfaces:** `reactive_root.gd` (`RuitkRoot.create(container, root_vnode)` — hold the
  returned object for the UI's lifetime; `.unmount()` runs cleanups) and `reactive_root_node.gd`.

**Known runtime constraints** (see README "Notes & limitations"): removed *plain* props don't reset to
defaults between renders (style/events/refs/draw *do* reset); error boundaries are cooperative (no
try/catch in GDScript — a failing render *calls* `RuitkFail.render(reason)` to reach the nearest
boundary; a hard GDScript crash still can't be auto-caught); `useTransition`/`useDeferredValue`
are synchronous. Preserve these behaviors — they're faithful-to-reference, not bugs.

### `.guitkx` toolchain

`.guitkx` is a JSX-like markup: **two languages in one file** — markup plus embedded GDScript (setup,
`{expr}`, `@if`/`@for`). It compiles to a sibling `.gd`.

- **Compiler (`addons/reactive_ui_toolkit/guitkx/`)** — pure GDScript: `guitkx_lexer.gd` → `guitkx_markup.gd` /
  `guitkx_jsx_scan.gd` → `guitkx_codegen.gd` (`RuitkGuitkxCodegen`, the entry point:
  `compile_file` / `compile_all` / `find_all`) → `guitkx_formatter.gd`.
- **Imports (0.10.0):** a file is a SEQUENCE of declarations; `export` marks cross-file visibility;
  `import { Name } from "./spec"` (also `../`, `~/` from `guitkx_config.gd`'s `"root"` walk-up) is
  resolved by `guitkx_resolve.gd` — component imports lower LAZILY through `V.comp(path, func)`
  (cycles legal), hook/module imports become eager `const` preloads (cycles = GUITKX2306).
  Cross-file resolution is STRICT (unimported ref = GUITKX2305); the import diagnostics are the
  family-frozen `GUITKX2300–2309`. `guitkx_migrate.gd` is the idempotent migration codemod
  (shipped runner: `dev/migrate_0_10_0.gd`). The build/sweep is TWO-PASS (write all `.gd`, then
  parse-check) so value-import preloads never false-fail, and a changed export table re-compiles
  importers in the same sweep (`export_hash` in the `.diags.json` v3 sidecar).
- **In-Godot-editor plugin (`addons/reactive_ui_toolkit_editor/`)** — watches the filesystem and recompiles
  each `.guitkx`→`.gd`. It recompiles on **editor focus-in** (not just `filesystem_changed`) because a
  `.guitkx`-only external edit doesn't reliably flip Godot's changed flag; an mtime staleness guard
  keeps that cheap, and diagnostics are de-duplicated (Godot's Errors dock is append-only). Also hosts
  the in-editor `.guitkx` view, tokenizer/highlighter, and a headless LSP layer (`lsp/`).
- **RUITK Builder (`addons/reactive_ui_toolkit_editor/builder/`)** — the visual editor for a
  `.guitkx` tree, ported from the Unity leg (`plans/BUILDER_PORT_PLAN.md`). `document/` is the
  model layer: a tree of modules held **in memory**, with disk as a projection computed at Save
  (nothing is written until then — delete, rename and folder moves included). Deletion is
  ABSENCE: a module leaves the tree and Save finds the orphan by diffing the last projection,
  so there are no pending-intent lists for a consumer to forget to join. Everything here is
  pure or `FileAccess`-only and headlessly testable; its files reference each other through
  **preload consts**, never global `class_name`s, because `ProjectSettings.save()` truncates
  the editor class cache to what the running process loaded. `canvas/` projects that model into
  what the canvas draws — a card per module, a row per line, an edge per import — entirely from
  the compiler's own analysis (`analyzed_decls`, `decl_structure`, `scan_imports`,
  `RuitkGuitkxJsxScan.element_end`), so a row's span is exactly what the compiler compiled.
  `preview/` renders it: the whole tree is **mirrored** to `res://__ruitk_builder_preview__~/`
  (the `~` makes Godot's importer skip it) and compiled there through the real compiler at real
  paths, so the preview cannot compile differently from the build. Dirty means *changed since
  last built*, not *unsaved*; a failure skips only its dependents; a broken edit keeps the last
  good render. Cleared on teardown and on open. `canvas/` also holds the surface itself: one
  `builder_canvas_metrics.gd` every consumer measures with (the Unity leg has two LOD definitions
  and they disagree), a screen-space `_draw` overlay for the Bezier edges, a host that owns the
  camera — and `canvas_view.guitkx`, the card layer, **dogfooded**: the builder's own busiest
  surface is written in the language the builder edits and rendered by this reconciler. Its
  generated `.gd` is COMMITTED (an installed addon needs its canvas before the compile-on-scan
  sweep runs) and gated fresh by `tests/builder_view_build.gd`. Pixels are covered by
  `tests/builder_canvas_capture.gd`, which needs a window and so runs by hand, not in CI.
- **External IDE extensions (`ide-extensions/`)** — a shared TypeScript language server + a TextMate
  grammar, driven by both VS Code and VS2022. Markup intelligence is answered locally from the schema;
  embedded-GDScript intelligence builds a synthetic `.gd` virtual document with a length-preserving
  source map and analyzes it **in-process via `@gdscript-analyzer/core`** — no running Godot editor,
  no TCP, fully offline.

**Generated `.gd` files are git-ignored** (`examples/**/*.gd`, minus a few hand-written exceptions
listed in `.gitignore`). Always edit the `.guitkx` source, never the generated `.gd`. `.guitkx` is
**tab-indented** (the embedded GDScript and the compiler both require tabs); override the formatter via
a `guitkx.config.json` walk-up file.

### Examples

`examples/` is **not shipped** — the addon in `addons/reactive_ui_toolkit/` is self-contained. `examples/app.gd`
(→ `examples/main.tscn`, the project's main scene) mounts the demo gallery. Open the project in Godot 4.x
and press Play to explore.

## Conventions

- **Faithful port.** Algorithms/behavior mirror Reactive UI Toolkit — Unity (the C#/Unity library); the code is
  GDScript. When in doubt about intended semantics, that library is the reference. GDScript divergences
  (no exceptions — the `RuitkFail` latch is the substitute) are documented at the top of the relevant
  core file.
- Requires Godot **4.4+** (compiler core uses 4.3+ APIs; the editor addon's bundled analyzer GDExtension has `compatibility_minimum = "4.4"` — both plugins gate on `MIN_GODOT`); verified on **4.7**. Standard build — no C#/.NET.
- `plans/` holds design/porting docs; `research/` holds background notes. `CHANGELOG.md` (runtime) and
  `ide-extensions/changelog.json` (the source of truth for extension changelogs) track releases.

## Machine-local paths

No tracked file names a path that exists only on one machine; the gate
`node scripts/check-machine-paths.mjs` enforces it in the engine-free gates job.

- **Repo locations are derived, never written down** — `${workspaceFolder}` in VS Code configs, the
  script's own `..` in Node tooling, `git worktree list` for worktrees. A committed absolute path
  breaks every clone whose folder name differs, which is exactly how the 0.13.0 wave broke F5.
- **Tools are probed, then overridden** — resolution order `$ENV_VAR` → `.ruitk-local.json` → PATH +
  standard install roots → an error naming all three. Standard roots (`C:\Program Files\…`, `/usr/…`)
  MAY appear in discovery code and CI workflows: they mean the same thing on every machine of that
  kind, and the gate allows them.
- **`.ruitk-local.json`** holds this machine's irreducible values (here: the Godot binary), is
  gitignored, and is copied from `.ruitk-local.example.json`.
