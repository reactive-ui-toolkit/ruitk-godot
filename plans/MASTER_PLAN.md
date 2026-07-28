# MASTER PLAN — the single consolidated work-list (Reactive UI Toolkit — Godot)

> **Consolidation of every live plan, 2026-07-14.** The 2026-07 plans audit closed and archived
> eight plans (see `archive/README.md` for the per-plan record); everything still open across all
> of them lives HERE. One row per remaining work item, with status, blocker, and the source plan
> it came from. Living ledgers (`TECH_DEBT.md`, `WIDGET_INVENTORY.md`, `DISCORD_CHANGELOG.md`)
> and the engine-version runbook (`/AUTOMATION.md`) stay separate — they are reference documents,
> not work-lists.

## Where the project stands

Runtime, compiler, formatter, LSP (VS Code + VS2022 + native editor), publishing pipeline, docs
site, and test infrastructure are all **at parity and green** (full matrix: build → suites →
contract → corpus → TS → docs). The **0.10.0 imports leg is complete on
`feat/guitkx-imports`** — grammar, resolver, strict diagnostics (family-frozen
`GUITKX2300–2309`), codemod (tree migrated), HMR, IDE mirrors, docs, versions/changelogs, plus an
18-bug adversarial-hunt fix wave and a full documentation refresh. Nothing below blocks a
release.

## 1. Release-critical (in order)

| # | Item | Status | Blocker / next action | Source |
|---|---|---|---|---|
| 1.1 | **Ship 0.10.0** — PR `feat/guitkx-imports` → `dev`, master fast-forward, **Publish** (addon 0.10.0, editor 0.8.0, VS Code/lsp 0.10.0, VS2022 0.10.0 — skew rule: same window) | branch done, green, unpushed | **owner**: open/merge the PR, press Publish | IMPORT_EXPORT_PLAN (archived) |
| 1.2 | **VS2022 interactive verification checklist** — drive every parity phase through a real VS2022 UI (highlighting, completion, format-on-save, restart, import go-to-def); no session has ever recorded doing it | code shipped & builds (vsix 36.8 MB); verification unexecuted | needs a human at a VS2022 instance (`/field-test-editor`-style session) | VSCODE_VS2022_PARITY_PLAN (archived) |
| 1.3 | **Asset Store / Asset Library listings** — repo prep staged, `publish.yml` auto-post jobs armed by `ASSETLIB_ASSET_ID` / `ASSETLIB_EDITOR_ASSET_ID` repo variables; new-store submission is manual (no API yet) | infra done | **owner**: accounts, listing creation, icon/screenshots pass | ASSET_STORE_PLAN (archived) |

## 2. Family campaign (cross-repo)

| # | Item | Status | Blocker / next action | Source |
|---|---|---|---|---|
| 2.1 | **Unity imports leg (leg 3)** — port the frozen import/export contract to `.uitkx` (`UITKX2300–2309`, same corpus mirror + `corpus-hash.mjs` gate) | not started (by design) | starts only after the 0.10.0 PR merges (campaign order: Unreal → Godot → Unity) | family master plan (Unreal repo) |
| 2.2 | **Re-exports** (`export { X } from "./x"`) — the imports fast-follow, family-wide (frozen decision: not v1) | designed-out of v1 | family-level go; implement in all three legs together | IMPORT_EXPORT_PLAN §1 (archived) |
| 2.3 | **`@class_name` grammar removal + generated-registry privacy end-state** — GDScript's flat global class registry is the one leg where the override is a namespace substitute (Unreal/Unity have real namespaces); the Godot leg retired 0103 emission and the redundant demo usages (0.10.2) but kept the directive itself as the escape hatch | DECIDED: directive KEPT (escape hatch + module-migration binding tool — the 0.11.0 codemod pins every hoisted module's identity with it) | removal revisited post-campaign, owner-triggered | CLASSNAME_CLEANUP_PLAN (archived) + ES_MODULES_EXECUTION_PLAN (archived) |

## 3. Feature work (library)

| # | Item | Status | Blocker / next action | Source |
|---|---|---|---|---|
| 3.1 | **Markup tags for the `V.*`-only structural primitives** — `Portal`, `Suspense`, `ErrorBoundary`, `Memo`, `Audio`/`Video`, router set (`Router`/`Routes`/`Route`/`Outlet`/`NavLink`) — so the README's escape-hatch list shrinks | open, unscoped | design pass: tag grammar for children-as-routes etc. | PARITY_PLAN G2 / README roadmap |
| 3.2 | **Niche adapter decision** — `SubViewport` / `GraphEdit` / `GraphNode`: port dedicated adapters or explicitly defer (Unity sibling shipped its analogue @0.6.3) | undecided | owner decision, then either a small port or a documented defer | PARITY_PLAN G2 (archived) |
| 3.3 | **Native-editor embedded-GDScript depth** — the remaining analyzer wiring so `reactive_ui_toolkit_editor` matches the VS Code extension inside `{expr}`/setup (completion/hover exist; the gap list lives in the editor README "Known limits") | partial (gdext bridge shipped 0.6.0) | scope the remaining queries; medium effort | PARITY_PLAN G1 / README roadmap |

## 4. Performance (measured leftovers — behavior-preserving, benchmark before/after)

| # | Item | Status | Notes | Source |
|---|---|---|---|---|
| 4.1 | **Reconciler per-node overhead lever** (~11µs/node render+diff on the Doom workload) — the open core-library lever after the 0.8.6 batch (GO-05/06/08 shipped) | open | needs a profiling-led pass; biggest remaining runtime win | FINAL_AUDIT_GODOT_OPTIMIZATIONS §6 (archived) |
| 4.2 | GO-01 — `compile()` re-scans the source per tier | open, optional | tooling-side; contract suites pin behavior | same, §2 |
| 4.3 | G-11 — editor poll sweep rewalks the tree per tick | open, optional (bounded) | only matters on very large projects | same, §3 |
| 4.4 | Doom demo `ColumnInfo` pooling tail (GO-03 leaf types done) | open, demo-local | nice-to-have; demo already ~80fps CPU | same, §6 |
| 4.5 | G-09 — optional `same_ref` escape hatch for deps arrays (the by-VALUE deps compare is **documented** in README Notes & limitations) | documented; hatch optional | add only if a real project hits the deep-compare cost | FINAL_AUDIT_GODOT_FINDINGS (archived) |

## 5. Accepted / standing (pointers, not work)

- **`TECH_DEBT.md`** — TD-01 (all-or-nothing child reconciliation gate) and TD-02 (curated style-key
  subset): **open / accepted**, no driving bug; TD-03 (imports follow-ups) resolved 2026-07-12.
- **`WIDGET_INVENTORY.md`** — the authoritative Control-coverage ledger; re-diff per engine version
  (see `/AUTOMATION.md` — the new-Godot-version runbook + `scripts/godot-api-diff.mjs`).
- **`DISCORD_CHANGELOG.md`** — community release log, current through 0.10.0.
- **`family-corpus.hash`** — CI drift-gate data for the family scanner corpus; re-pin only on a
  deliberate, family-mirrored corpus change.

## 6. Closed & archived (2026-07 audit)

Everything below is **done or superseded** — record, not work. Full per-plan notes:
`archive/README.md`.

| Archived plan | Outcome |
|---|---|
| `IMPORT_EXPORT_PLAN.md` | 0.10.0 imports leg — all milestones executed, tree migrated, green |
| `ES_MODULES_EXECUTION_PLAN.md` | 0.11.0 ES-modules leg (Layer 2) — plain signature-classified declarations, value exports, full ES import surface, codemod-modernized tree; family corpus pin pending (Unreal leg in flight) |
| `IMPORTS_LEG_BUGHUNT.md` | 18 verified bugs — all fixed with regression tests |
| `NAMING_LOYALTY_PROPOSAL.md` | 0.9.0 naming loyalty — approved, executed, shipped (PR #70) |
| `FINAL_AUDIT_GODOT_FINDINGS.md` | G-01…G-23 fixed (G-09 hatch → §4.5 here) |
| `FINAL_AUDIT_GODOT_OPTIMIZATIONS.md` | measured perf batches shipped (leftovers → §4 here) |
| `VSCODE_VS2022_PARITY_PLAN.md` | all phases shipped (interactive verification → §1.2 here) |
| `PARITY_PLAN.md` | parity reached; status role superseded by this file (leftovers → §3) |
| `ASSET_STORE_PLAN.md` | research + prep done (owner actions → §1.3 here) |
| `EXTENSION_LISTING_PLAN.md` | marketplace listing overhaul shipped — extensions 0.10.1, distinguishable display names + structured page bodies (Title/Description/Features/Requirements/Changelog) on both marketplaces |
| `CLASSNAME_CLEANUP_PLAN.md` | GUITKX0103 retired + 45 demos' redundant `@class_name` dropped — shipped 0.10.2 (grammar-removal decision deferred → §2.3 here) |
