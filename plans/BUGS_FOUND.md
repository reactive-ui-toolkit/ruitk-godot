# Bugs & gaps found — import-isolation audit (2026-07-25)

Findings from an owner-requested audit: "do same-named exports in two files collide?", the
import grammar surface (quotes / default exports / renames), and a cross-check of two
completion defects reported on the Unity leg. Investigation only — nothing fixed yet.

## Verified working (no action)

- **Import isolation is real.** Resolution is path-scoped end to end: a specifier resolves
  relative to the importing file (`guitkx_resolve.resolve_specifier`), the imported name is
  validated against the *target file's* export table only (GUITKX2301/2302), and the
  lowering is a hashed per-file const — `const __RUI_IMP_<hash> = preload("<target>.gd")`
  with member access through it (verified by live probe). No global name registry is
  consulted; two files exporting the same name never interact. Same name imported twice
  into one file = GUITKX2303; import alias colliding with a local declaration = GUITKX2325.
  Component-name duplicates across files are correctly rejected (GUITKX2106 —
  incumbent-wins, real GDScript global-`class_name` constraint; `@class_name` is the
  escape hatch).
- **Quotes:** import specifiers accept BOTH `'…'` and `"…"` on every tier — compiler
  (`guitkx.gd` accepts `"` or `'` at the spec position), TS mirrors (all `IMPORT_*` regexes
  use `["']`), TextMate grammar (`single-quoted-string` include), editor addon (spec regex
  `["']([^"']+)["']`). Parity intact. *(Minor: no test/corpus case exercises a
  single-quoted specifier — worth one case in the contract corpus someday.)*
- **Default exports:** supported — `export default Name` (E-07/E-09 markers; duplicate
  default = GUITKX2327) and `import X from "spec"` (G-05), tested.
- **Rename imports:** supported — `import { a as b }`, `import * as X`, combined
  `import Def, { a as b }`; aliased-const lowering; rename-refactor traverses import
  clauses. Tested.

## BUG-ISO-1 — false GUITKX2106 collision between value-first files (FIXED — staged for 0.12.1)

> **Status: FIXED (2026-07-25).** `project_bindings` now computes the binding's KIND in the
> same pass as its name (`_binding_info`) and exempts value-kind bindings from the dupe
> arbitration + class→path table. Regression pinned in `tests/guitkx_test.gd` (twin value
> files both compile, no class_name emitted, importer preloads its resolved path; the
> component-dupe incumbent-wins test stays green). Full battery green: guitkx_test ALL,
> build 49/0, hmr 55, editor 402/0, demos 31/0. Changelog staged under `[0.12.1] — Unreleased`.
> **Family check still open:** verify the Unity/Unreal arbitration mirrors for the same
> over-fire (their value-binding legs) — not yet audited.

**Repro (live-probed):** two files whose FIRST exported declaration is a value with the
same name —

```
# a_vals.guitkx          # z_vals.guitkx
export speed := 10       export speed := 99
```

`compile_all` flags `z_vals.guitkx` with **GUITKX2106** and refuses to write its `.gd`
(incumbent-wins arbitration). Any import from the loser then breaks (missing target).

**Why it's a false positive:** GUITKX2106 exists to prevent two files emitting the same
global `class_name`. But since the 0.12.0 value/class fix, a VALUE-bound file emits **no
`class_name` at all** (`guitkx.gd`: "A VALUE binding never emits class_name … a value
identity has no global-class consumer") — so no GDScript-level conflict exists. The
arbitration (`project_bindings` → `_binding_name` in `guitkx_codegen.gd`) still groups
files purely by binding name with no kind exemption, so the guard over-fires.

**Realistic trigger:** two style/constants companion files that both begin with the same
export, e.g. `export accent := …` — the alphabetically-later file silently stops
compiling.

**Fix shape (when picked up):** exempt value-kind bindings from the `by_class` dupe
grouping (their `.gd` has no class to collide; key their identity tables — HMR link,
sidecar — by path instead). Check every consumer of `project_bindings()["bindings"]`
for assumptions. **Family check required:** Unity and Unreal mirror this arbitration —
verify whether their value-binding legs have the same over-fire.

**Regression test to add:** the probe scenario above (two value-first same-name files →
both compile, no 2106) + the existing component-dupe test stays green.

## GAP-ISO-2 — no import-specifier path completion (parity gap; Unity's two defects N/A here)

The Unity leg reported two defects in its import-path completion (inside the `from "…"`
string): (1) the path suggestion list is unordered — should be nearest-first by path
distance from the importing file; (2) accepting a suggestion while a prefix like `./` is
already typed APPENDS instead of REPLACES, producing `././SomeComponent…`.

**Godot status: the feature does not exist at all**, so neither defect reproduces:
- External LSP: `onCompletion` handles import-brace names, tags, attrs, directives,
  markup, embedded — there is NO `importSpec` context; a caret inside the `from` string
  offers nothing.
- In-editor addon (`guitkx_completion.gd`): same — brace-name completion only; the spec
  regex is used to *read* an existing specifier, never to complete paths.

**Action (when picked up):** implement specifier path completion on both tiers, with the
two Unity defects designed out from the start — (a) results ordered nearest-first
(same-dir files, then walking outward, `~/` root entries last), (b) the accepted item must
REPLACE the typed partial specifier via a proper TextEdit range covering the full string
contents, never insert at caret. Family-wide: the fix for (a)/(b) on Unity/Unreal and the
new Godot implementation should share the ordering + replace-range spec so all three legs
behave identically.
