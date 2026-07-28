# ES-Modules Redesign — FAMILY GENERAL PLAN (engine-agnostic)

> Owner-approved 2026-07-17. This document is COPIED VERBATIM into all three repos
> (Unity `Plans~/`, Unreal `plans/`, Godot `plans/`) and accompanied in each by an
> engine-specific `ES_MODULES_EXECUTION_PLAN.md`. The execution plan may add engine
> detail; it may NOT contradict this document. Conflicts = stop and ask the owner.

## 0. Goal (one paragraph)

Complete the family's transition to true ES-module semantics: **a file IS a module**,
with per-file scope, plain `export`-prefixed declarations (no `component` / `hook` /
`module` wrapper keywords), signature-driven classification, exactly ONE visibility
mechanism (imports), and the full ES import surface (named, `* as`, default,
rename-on-import, deferred export lists). Each engine spells declarations in its own
native language idiom (C# / C++ / GDScript) — uniform CONCEPTS, native SPELLING.

## 1. Where each repo starts (verified 2026-07-17)

- **Unreal (.uetkx)** — reference implementation for strict imports: already has no
  ambient visibility, export-opt-in privacy (`RuiPriv_<file>` namespaces), mixed
  declarations, PascalCase components ENFORCED (2100), `Use`-prefix hooks (2203),
  frozen family diagnostics 2300–2315, migration codemod, cycle rules. Still has:
  wrapper keywords, no value exports, named-imports-only.
- **Godot (.guitkx)** — shipped the same strict-import leg in 0.10.0 (preload-based
  value imports, lazy `V.comp` component refs, binding = one `class_name` per file,
  privacy = no `class_name`). Still has: wrapper keywords, no value exports,
  named-imports-only.
- **Unity (.uitkx)** — the laggard: still has ambient same-folder visibility,
  companion partial-class merging (`X.style.uitkx` merges into component `X`),
  folder-shared (not per-file) namespaces. Its execution plan therefore contains an
  extra catch-up layer the other two don't need.

## 2. LOCKED DECISIONS (do not re-litigate in execution plans)

- **G-01 — File = module.** A file's exports are its entire public surface. Module
  identity derives from the file path. Renaming a file changes module identity (and
  hot-reload identity of its private members) — documented, accepted semantic.
- **G-02 — One visibility mechanism.** Cross-file references between markup files
  require an import. No same-folder ambience, no companion merging, no name-glob
  magic. (Hand-written NATIVE code — `.cs`/`.h`/`.gd` — remains ambient per its own
  language rules and is never policed; family rule A4 carries forward.)
- **G-03 — Wrapper keywords removed.** `component X {}` / `hook useX {}` /
  `module M {}` are replaced by plain declarations. Classification is read from the
  SIGNATURE ALONE (parse-time, no body inspection, no semantic analysis):
  - **markup-node return type** (`VirtualNode` / `FRuiNode` / `RuitkVNode` per engine)
    ⇒ **component**; PascalCase name ENFORCED (error — tags require it).
  - **`use`-prefixed name** (each engine's casing convention: `useX` C#-camel,
    `UseX` C++-Pascal, `use_x` GDScript-snake) ⇒ **hook**.
  - **next token after name is `=`** ⇒ value export.
  - anything else ⇒ util function.
  Cross-guards are errors: use-prefixed + markup-node return ("did you mean a
  component?"); markup-node return + non-PascalCase.
- **G-04 — Declarations are typed in the engine's native idiom.** Unity/C#:
  `export Style container = new Style {...}` / `export string F(int x) {...}` /
  `export VirtualNode Panel(string t) {...}` (type-first). Unreal/C++: same
  type-first shapes with C++ types. Godot/GDScript: `-> Type` return annotations
  (already shipped grammar) + `: Type =` value annotations; markup-node return
  annotation classifies components. Type-inference sugar is allowed ONLY where the
  initializer names the type (e.g. C# `export container = new Style {...}`).
- **G-05 — Full ES import surface** *(SUPERSEDES the family lock "named exports
  only" — owner decision 2026-07-17)*:
  named `import { a, b } from "./x"`; rename `import { a as b }`;
  namespace `import * as X from "./x"`; default `import X from "./x"` +
  `export default <Name>;`; deferred lists `export { a, b };` (mixable with inline
  `export`). Re-exports (`export { a } from "./x"`) remain DEFERRED (unchanged).
  Specifiers stay extensionless `./ ../ ~/` only; preamble-only; module-boundary
  rule (2308) unchanged.
- **G-06 — Privacy is real.** Un-exported declarations are file-private: emitted so
  they are compile-time-invisible outside the file (per-file namespace / no
  class_name / private members). Runtime registries must be keyed by
  FILE-QUALIFIED identity for private members so same-named privates in different
  files can never collide (Unreal folds this fix into its execution plan — the
  TD-026 gap closes, not carried forward).
- **G-07 — Escape hatches stay, engine-symmetric.** Unity: components keep emitting
  `partial class` so hand-written `.cs` can extend them. Godot: `@class_name`
  directive stays (collision/interop hatch). Unreal: host-include `import "@X.h"`
  stays. Hatches are for interop, not everyday use; docs say so.
- **G-08 — Eager/lazy is kind-driven (Godot parity rule).** Component references
  are lazy (cycles legal, family-wide, preserved via each engine's existing
  mechanism); value/hook references may be eager where the engine requires it,
  keeping the TDZ-style cycle error (2306) semantics identical family-wide.
- **G-09 — Hot-reload identity keys on (file identity + declared name)** for private
  members and on the exported name (already unique via 2106) for exports. Hook/
  component state preservation semantics must NOT regress; a signature change
  still resets state per existing rules.
- **G-10 — Deprecation window.** Old syntax keeps parsing for ONE minor version with
  deprecation diagnostics (new codes from the reserved family block — execution
  plans allocate from **2320–2329**, identical meanings/wording family-wide, engine
  prefix only). Each repo ships an idempotent codemod (pattern: tidy →
  export-normalize → rewrite wrappers to plain declarations → insert/fix imports →
  zero-diagnostics compile gate) in the SAME release. Removal happens in a later
  minor, owner-triggered.
- **G-11 — Versioning: minor bump per repo.** Unity package 0.8.x→0.9.0; Unreal
  plugin 0.11.0→0.12.0; Godot runtime addon 0.10.x→0.11.0. IDE extensions bump per
  their own lanes. No 1.0 claims.
- **G-12 — Full sync surface is part of DONE.** Every execution plan must include,
  as gated milestones: parser+emitters(all layers)+formatter+codemod; IDE grammar
  (TextMate), schema, LSP/mirror parsers, completions/hover/go-to-def/rename;
  hot-reload pipeline; ALL changelogs of that repo (each lane, incl. Discord ≤2000
  ASCII chars/entry where applicable); migration guide; docs-site pages (imports,
  companion/concepts pages rewritten); version bumps; family corpus
  (`family-corpus.hash`) updated IN LOCKSTEP across the three repos — grammar
  changes land as corpus cases with normalized TKX codes, and the pinned hash must
  match in all three repos at the end of the campaign.
- **G-13 — Rollout order: Unreal → Godot → Unity** (same as the imports leg:
  reference first, then ports), BUT plans are written so legs can proceed in
  parallel once the corpus cases for the new grammar are agreed and pinned.

## 3. Reference dialect example (Unity C# — other engines transliterate)

```jsx
import { FormatTime } from "../Shared/TimeUtils"

export Style container = new Style { Padding = 10f };
export int MaxItems = 5;
export theme = new Style { BackgroundColor = ColorGray };   // inference: `new T`

export string FormatScore(int score) { return $"Score: {score}"; }

export (int value, Action reset) useCountdown(int start) {
  var (value, setValue) = useState(start);
  Action reset = () => setValue(start);
  return (value, reset);
}

Style rowStyle = new Style { MarginTop = 2f };               // local — private

export VirtualNode ScoreRow(string label) {
  return ( <Label text={label} style={rowStyle} /> );
}

VirtualNode ScorePanel(string title) {
  var (count, reset) = useCountdown(MaxItems);
  return (
    <VisualElement style={container}>
      <Label text={FormatScore(count)} />
      <ScoreRow label={FormatTime()} />
    </VisualElement>
  );
}

export default ScorePanel;
```

Lowering (Unity): per-file namespace (folder path + file stem); one static
`__Exports` container class for values/utils/hooks; one `partial class` per
component; named import ⇒ `using static <ns>.__Exports;` (bare names, ES
semantics); `* as X` ⇒ `using X = <ns>.__Exports;`; default ⇒ alias to the
default-marked symbol. Unreal/Godot execution plans define their equivalents
against their existing emission primitives.

## 4. What each execution plan MUST contain (structure contract)

Following each repo's own plan conventions (Unreal `MASTER_PLAN` style D-decisions +
M-milestones; Godot `IMPORT_EXPORT_PLAN` style M0–M8 + verify-command blocks; Unity
`SAMPLES_NAMESPACE_MODERNIZATION_PLAN` style verbatim appendices):
1. Locked-decisions echo (G-01..G-13) + engine-local decisions with IDs.
2. Verified file:line anchors for EVERY touch point (parser, emitters, resolver,
   formatter, codemod, HMR, LSP mirrors, grammar/schema, tests, changelogs, docs).
3. Milestones, each ending green on an exact copy-pasteable verify-command list;
   research → develop → test → bughunt → fix → commit per milestone; never weaken
   a gate; no push unless the owner asks.
4. New-diagnostic table (2320–2329 allocations) with exact messages.
5. Codemod spec (idempotent, zero-diagnostics gate) + migration guide outline.
6. Committed-generated-output flag list (goldens, vocabularies, fixtures, corpus).
7. Deprecation-window behavior matrix (old syntax × new syntax × mixed files).
8. Full sync-surface checklist (G-12) as explicit milestone items.
9. Guardrails ("what NOT to do") + error-signature table for the executing agent.
10. Risks/watch-list; anything ambiguous = STOP AND ASK, never guess.
