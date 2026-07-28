# ReactiveUI — Technical Debt Register

Known, deliberately-unfixed defects across the ReactiveUI family (the Godot port here and the
upstream C#/Unity ReactiveUIToolKit). Each entry names the root cause, the reason it's still open,
and what a production-grade fix looks like — so a future fix starts from evidence, not rediscovery.

---

## TD-01 — Child reconciliation is an all-or-nothing gate, not React's per-child algorithm

**Where:** Unity `Shared/Core/Fiber/FiberChildReconciliation.cs:50` (the gate) and
`CanReuseFiber` at `:249-254` (type-only reuse). Godot analogue: `_any_keyed` at
`addons/reactive_ui_toolkit/core/reconciler.gd:1006`.

**The defect (Unity).** The decision between keyed and index reconciliation is made **once for the
whole sibling set by sniffing only the first child's key**:

```csharp
// Check first child for keys (React convention: all-or-nothing keyed within a sibling set)
if (newChildren.Count > 0 && !string.IsNullOrEmpty(newChildren[0]?.Key))
    ReconcileChildrenWithKeys(...);   // whole list keyed
else
    ReconcileChildrenByIndex(...);    // whole list by position; keys NEVER read
```

The comment misattributes this to React. "All children keyed or none" is a **dev-time lint
guideline** (React only *warns*); it is **not** how React's runtime reconciles. React's
`reconcileChildrenArray` is **per-child, two-pass**: (1) a lockstep pass that reuses by position
only while keys match and **breaks on the first key mismatch**, then (2) a map pass that matches
the remaining tail by `key ?? index`. Unity's file already contains both halves
(`ReconcileChildrenByIndex` ≈ pass 1, `ReconcileChildrenWithKeys` ≈ pass 2) but **branches to one
or the other** instead of running them in sequence — and its index half is weaker than React's
pass 1 because `CanReuseFiber` checks **type only, never key**.

**Failure mode.** A mixed sibling list whose **first child is unkeyed but later children are
keyed** routes the entire list to the index path, so the keyed children are reconciled **by
position with their keys ignored**. On reorder, a fiber's state/focus/animation is handed to
whatever child now sits at its slot — **identity silently lost**. (The inverse — first child
keyed, rest unkeyed — routes all to the keyed path, giving unkeyed children synthetic index keys.)

**Why it is load-bearing (do not "just fix" it).** The Unity DoomGame sample's 3D viewport is
exactly this shape: an **unkeyed Sky at index 0** followed by **keyed floor/ceiling bands** whose
key embeds a per-frame-changing `SlabId`. Because of the first-child gate those keys are never
read, so the bands reconcile by slot and reuse in place — smooth. **Fix the reconciler to be
truly per-child React and the bands' changing `SlabId` keys start getting honored: key mismatch
every frame → delete + recreate → churn. Same ~186 nodes/frame we hit in Godot. So the core bug
is load-bearing for Doom's performance — the sample is fast *because* the reconciler is broken.**
"react-unity would be even faster if the bug were fixed" is backwards: **fixing it makes Doom
slower**, and you'd then need the structural hardening on top just to get back to where it is now.

**Godot port status (different, safer approximation).** Godot's gate is `_any_keyed` — **any**
keyed child promotes the whole list to the keyed path (unkeyed siblings get index-fallback keys).
This is still all-or-nothing, not true per-child React, but it errs toward **honoring** keys
rather than **dropping** them, so it cannot silently lose a keyed child's identity the way Unity's
gate does. This is precisely why the identical markup **churned in Godot but not Unity**, and it's
documented as a faithful-port divergence. The Godot Doom port is hardened structurally (isolated
unkeyed containers per band group) so it does not depend on the gate for performance.

**Production-grade fix (applies to either core).** Stop gating and implement React's actual
`reconcileChildrenArray`: run the lockstep-with-key-break pass, then the map pass for the tail,
**per child**. The pieces already exist in the Unity file; it's a matter of sequencing them
instead of branching. **Caveats:** it's a separate repo (Unity), it's a meaningful rewrite of the
hottest path in the reconciler, and — per the load-bearing note above — **landing it alone
regresses the Doom sample**, so it'd have to ship together with the sample hardening (drop the
`SlabId` identity from the band keys, or isolate the band lists into their own unkeyed containers,
the same fix applied in the Godot port).

**Status:** open / accepted. No observed bug is driving it in either port today (Godot's gate
fails safe; Unity's is masked by the sample shape). Track before any reconciler rewrite so the
Doom perf regression is anticipated, not discovered.

---

## TD-02 — `style` key whitelist is a curated subset, not full CanvasItem/Control coverage

**Where:** `addons/reactive_ui_toolkit/core/style.gd` — the `_apply_key` / `_reset` `match` (the friendly
shorthands) + `BOX_KEYS` + `THEME_CHANNELS`.

**Context (why this is a ledger entry, not a bug).** `style={{…}}` keys are a hand-maintained
whitelist, **by design** (see the file header). Nothing is *inaccessible*: (a) any node property is
settable as a plain element attribute via `host_config.gd`'s generic `node.set(k, v)`, and (b) the
six generic theme channels (`colors`/`constants`/`fonts`/`font_sizes`/`icons`/`styleboxes`) give
100% theme-item reach. The whitelist only decides which properties get a **friendly shorthand** and
**reset-on-removal** semantics — plain props do NOT reset when omitted between renders (the
audit-#23 behavior); style keys DO. So "missing from `style`" means "no shorthand + no auto-reset,"
never "impossible."

**Recently closed (2026-07-10).** Added `material` + `texture_filter` (routes the Doom wall shader
+ nearest filter through `style` so the dict stays reference-stable for the keyed reconcile — the
material object identity doesn't change, only its uniforms), then their natural companions
`texture_repeat` (pairs with `texture_filter`) and `z_as_relative` (pairs with the existing
`z_index` — the Doom HUD-isolation code explicitly hit its absence and had to lean on the `true`
default).

**Deliberately deferred (accepted gap).** Reasonable `style` shorthands not added, because each is
already settable as a plain attribute and none blocks anything:
- **Candidates worth a shorthand later:** `mouse_default_cursor_shape` (CSS `cursor`), `focus_mode`
  (focusability — reset default is per-control, so fiddly), `size_flags_stretch_ratio` (flex-grow),
  `theme_type_variation` (a theme "class").
- **Niche / skip:** `clip_children` (distinct from the existing `clip` = `clip_contents`),
  `custom_maximum_size`, `layout_direction`, `theme` (whole resource), `top_level`,
  `show_behind_parent`, `grow_horizontal`/`grow_vertical` (different from `grow_h`/`grow_v`, which
  are size-flags).
- **Accessibility** (`accessibility_name`/`_description`/`_live`/… — Godot 4.4+): a separate
  category; deserves its own pass if a11y lands on the roadmap.

**Production-grade fix, if ever wanted.** Add each deferred key exactly like the ones above — one
`_apply_key` arm + one `_reset` arm with the class default. No architecture change; the whitelist
is intentionally additive. Enum-valued keys (cursor/focus_mode/texture_repeat) should also accept a
friendly string, following the existing `_mouse_filter` / `_size_flag` string→enum helpers.

**Status:** open / accepted. Curated 90%-shorthand set over 100% generic reach; the deferred keys
are convenience, not capability. (Runtime-addon `style` API grew by 4 keys unreleased — a patch bump
+ one CHANGELOG line at next Publish covers it; deliberately not bumped on the feature branch.)

## TD-03 — Imports leg (0.10.0): deferred IDE-polish + docs page

The import/export leg (plans/IMPORT_EXPORT_PLAN.md) shipped its runtime + compiler + resolver +
codemod + strict resolution + HMR + version/changelog release plumbing, all green. Deferred as
follow-ups (none affect the migrated tree's correctness, the CI matrix, or shippability):

- **Docs site Imports page** (`ReactiveUIGodotDocs~/src/pages/UITKX/`): the grammar/strictness/
  codemod/`~/` narrative page + `CompanionFiles`/`Config`/`Diagnostics` touch-ups. The changelogs
  (root + Discord) and MIGRATION notes cover the release; the site build is green (its `lint` was
  already failing pre-leg on unrelated existing pages — setState-in-effect, unused var, whitespace).
- **M7 cross-file IDE navigation**: go-to-def / find-refs THROUGH an import specifier
  (`guitkx_refs.gd` + `server.ts`) and multi-decl outline export badges. The correctness-critical
  M7 piece (imported names resolve in embedded analysis; 23xx surface from the sidecar; import/
  export highlight as syntax) shipped, so migrated files don't red-squiggle.
- **VS2022 `.vsix` rebuild**: version bumped (2.1.0) + changelog regenerated; the binary rebuild via
  `ide-extensions/visual-studio/build-local.ps1` happens at the release/Publish step.

**Status:** RESOLVED (2026-07-12). All three items shipped in the same leg: the docs-site
"Imports & Exports" page (registered in the nav; docs `build` + `lint` green — the four pre-existing
lint errors were fixed too); cross-file go-to-definition through import specifiers/names +
outline `export` badges (`importNav.ts` + `server.ts`, node --test 182/182); and the VS2022 `.vsix`
rebuild — verified by an actual `msbuild … -t:CreateVsixContainer -p:Configuration=Release` producing
GuitkxVsix.vsix (36.8 MB), which also caught a version bug (the VSIX manifest SCHEMA version must stay
2.0.0; the extension `Identity` version is the one that moves — now 0.10.0, tracking the lsp-server).
