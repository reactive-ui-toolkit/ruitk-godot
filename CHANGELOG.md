# Changelog

All notable changes to **Reactive UI for Godot** are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/), and this
project adheres to [Semantic Versioning](https://semver.org/).

## [0.12.1] — 2026-07-25

### Added

- **Null-only components (React semantics).** A component whose body contains a top-level
  `return null` and no markup return is now legal — it renders nothing, exactly as in
  React (the runtime always supported this: a null render maps to an empty child list).
  The body compiles verbatim (hooks still alias — effect-only components are the use
  case), the formatter re-emits it without inventing a markup window, the editor's
  unreachable-code dimmer skips it, and the extensions' live GUITKX2101 check exempts it
  (embedded-GDScript intelligence inside such bodies already worked). Totality is still
  enforced: a body whose only `return null` is nested (a conditional guard with a
  fall-through path) keeps GUITKX2101, and a top-level non-markup value return keeps
  GUITKX2102. Family alignment: the other engines' legs already accept this shape; the
  shared contract-corpus case lands with the pending family corpus re-pin.

### Fixed

- **Two files whose first export is a same-named VALUE no longer false-collide
  (GUITKX2106).** The duplicate-binding arbitration guards the global `class_name`
  namespace, but a value-bound file emits no `class_name` at all (the 0.12.0 value/class
  rule) — so two files both starting with e.g. `export accent := …` had nothing to collide
  on, yet the alphabetically-later one was refused compilation with GUITKX2106 and its
  `.gd` never written, silently breaking any importer. Value-kind bindings are now exempt
  from the dupe arbitration and the class→path table (their identity stays path-keyed:
  sidecars sit beside the file, and importers preload by resolved path — a value is never
  a tag and never lowered through `V.comp`). Component-name duplicates still arbitrate
  exactly as before (incumbent wins, GUITKX2106 on the copy), pinned by the existing test;
  the new regression pins the twin-value case end to end, importer included.

## [0.12.0] — 2026-07-18

### Changed — License: PolyForm Shield 1.0.0 → ReactiveUI Community License 1.0

From this release, Reactive UI for Godot ships under the **ReactiveUI Community
License 1.0** (`LICENSE`): free to use, modify, and ship commercially for any company
under **US $250,000** gross revenue plus funding in the trailing 12 months; above that,
shipping a product requires a commercial license — **$2,000 per title** (perpetual) or
**$2,500 per studio per year** — see `LICENSE-COMMERCIAL.md` (new). Development,
evaluation, and education stay free at any company size; the obligation attaches only
to shipping. The license asks every shipped product for a "Made with ReactiveUI"
credits line, and carries the noncompete forward (reselling the library as a competing
product remains prohibited — a game built with it is never a competing product). Every
previously released version keeps the license it shipped with. Also new: `CLA.md`
(contributor license agreement, required for outside contributions), and the VS2022
extension now ships the license inside the VSIX. No code or feature changes in this
entry — same library, all features, for everyone.

### Changed — BREAKING: GUITKX2304 (unused import) is now an ERROR

Severity bump, owner-directed and family-wide (Unity/Unreal match): an unused imported
binding — named, `* as`, default, or any part of a combined import — now **fails the
compile** like every other import diagnostic, in the build sweep, the editor addon, and
the IDE extensions alike. Builds that carried unused imports as warnings must delete
(or use) them. The promotion is safe from false positives: the "used" reference scan
now over-approximates harder — every identifier outside the import statements counts,
string/comment/markup-text mentions included — so a firing 2304 means the binding truly
appears nowhere. (The previous GDScript-lexis scan could be derailed by markup text: an
apostrophe in "don't" or a literal `#` opened a phantom string/comment that swallowed a
real `{expr}` reference later on the same line — a false 2304 that would have been an
error-tier build breaker; fixed before the flip and pinned by test.) Findings anchor on
the whole binding token (alias offset + length) in every form.

### Added

- **ES combined import forms**: `import Def, { a, b as c } from "./file"` and
  `import Def, * as X from "./file"` — one declaration carrying the default binding plus
  the named/namespace surface, exactly as in ES. Every part yields its lowering (default
  bridge + named rewrites + namespace preload from the one declaration), every part
  contributes its value edge to the GUITKX2306 cycle graph, a duplicate binding across
  the parts (`import a, { b as a }`) is GUITKX2325, and the formatter preserves the whole
  line byte-for-byte. Colored in the grammar and both LSP tiers; the codemod's `* as`
  flip keeps a combined clause's default binding.

### Fixed — 0.11.0 field wave

- **Unused `* as` / default imports are now flagged (GUITKX2304).** The unused-import
  reference scan skipped only the braced `import { … }` line shape, so a namespace or
  default import's own binding self-counted on its import line and an unused one was
  never reported. Every preamble walk now shares one canonical import-span skip
  (`RUIGuitkx.import_end`) covering every form. Bare value references
  (`text={container}`) still count as uses, and the unused parts of a COMBINED import
  are flagged individually (an unreferenced default alongside a used named part names
  the default) — both pinned by test.
- **A VALUE binding no longer emits `class_name`.** A file whose first exported
  declaration is a value (`export something := 42`) emitted
  `class_name something` + `static var something` — inside that class every bare
  self-reference (`return something`) resolved to the CLASS TYPE, so the generated
  `.gd` failed to compile the moment any importer preloaded it. The binding stays the
  file's table/sidecar identity; a value identity has no global-class consumer (never a
  tag, never callable — cross-file access is preload-const-based). The LSP's virtual
  library mirrors the rule.
- **Same-name default audit (Unity parity):** `import is_something_even, { … } from`
  where the default alias KEEPS the default-exported member's name cannot become
  ambiguous in this dialect — every member import lowers through ONE deduped preload
  const plus a per-local rewrite (no container/bridge duality) — now pinned by test
  end-to-end (single const, dot-guarded `X.member` access, dependency chain compiles).

## [0.11.0] — 2026-07-18

**ES modules: a file IS a module.** The family-wide Layer-2 redesign lands: plain,
signature-classified declarations replace the `component` / `hook` / `module` wrapper
keywords, value exports arrive, and the import surface grows to the full ES set. One
codemod migrates a whole project; the old syntax keeps compiling for this minor with a
deprecation warning and is removed in a later minor. See **MIGRATION-0.11.md**.

- **Plain declarations, classified by signature alone**: `Name(p) -> RUIVNode {}` is a
  component (the annotation IS the classification; PascalCase enforced), `use_x(p) {}` a
  hook, any other callable a util, and `name := expr` / `name: T = expr` / `name = expr`
  a value (emitted as `static var` — GDScript cannot verify const-foldability at parse
  time; treat imported values as constants). A `use_`-prefixed callable returning
  `RUIVNode` is the new cross-guard error **GUITKX2321**.
- **Value exports** are new everywhere (no prior `.guitkx` surface could export a plain
  constant). They are eager preload edges: value-import cycles stay the hard error
  GUITKX2306; component references stay lazy (`V.comp`) and may cycle.
- **Full ES import surface** (supersedes 0.10.0 named-only): `import { a as b }` renames
  (diagnostics validate the REMOTE name), `import * as X` namespaces (one eager preload;
  members as `X.name`; component tags via `X.` not yet), `import X from` defaults
  (resolved at compile time to the target's `export default` decl, lowered per kind),
  deferred `export { a, b }` lists and `export default Name`. Re-exports stay deferred.
  New diagnostics **GUITKX2323–2327** (undeclared marker name, duplicate export, import
  alias collision, no default export, duplicate default); **GUITKX2322** is registered to
  its family meaning but never emitted by this leg (dynamically-typed dialect).
- **Deprecation window (one minor)**: wrapper declarations still compile through the
  byte-frozen legacy paths with one **GUITKX2320** warning per decl. **GUITKX2203**
  (hook-naming warning) retires with them — under signature classification the `use_`
  prefix IS what makes a hook, so a helper without it is simply a util. The codemod
  `dev/migrate_0_11_0.gd` rewrites a whole project (idempotent): wrappers to plain
  declarations, modules hoisted to top level (+`@class_name M` so binding/global identity
  survives — the escape hatch doing its job; it stays, permanently), and module importers
  flipped to `import * as M`. All 49 bundled demos are modernized with it.
- Generated mixed files gain `const __RUI_DEFAULT := "<name>"` (the default-export mark)
  and `__RUI_DECLS` rows now carry the `value`/`util` kinds; the diagnostics sidecar is
  schema v4 (exports rows with the new kinds + the file-level `default`, both covered by
  the reverse-edge staleness hash). Fast Refresh treats value/util changes exactly like
  hook/module changes (targeted importer refresh, no state reset on a value edit), and
  the HMR const-injector now also skips `static var` declarations.
- Fixed: a dot-preceded identifier (`X.entries(`) counted as a free reference of
  `entries` in the canonical reference scan — a member access is a use of the QUALIFIER
  only. Latent since 0.10.0; surfaced by module hoisting (spurious self-imports on the
  codemod's second run).
- Editor addon + IDE mirrors moved off wrapper-keyword regexes onto the compiler's own
  declaration scan (workspace index, outline, live header diagnostics, markup windows,
  virtual docs, formatter, TextMate grammar, schema); the t05 typo-header contract
  fixture is PROMOTED from pending — both sides now classify it identically.

## [0.10.2] — 2026-07-16

**`GUITKX0103` retired; demos and docs now model pure imports/exports.** Since 0.10.0 a
declaration's binding is *inferred* (`@class_name` override, else the first exported
declaration, else the first declaration) rather than required to match the file — the
warning that flagged a mismatch was a pre-imports convention check whose purpose died
when name-based resolution went away.

- **`GUITKX0103` ("component X differs from file name Y") no longer fires.** Its emission
  site is removed from the compiler; the diagnostic number stays reserved in the vocabulary
  (never reused — old sidecars still render it) and its docs table row moves to a short
  "Retired" note.
- **The 45 bundled demos drop their redundant `@class_name` directives** — every one of
  them equaled the component's own name, kept only to silence the now-retired warning.
  Verified byte-for-byte: the generated `.gd` for every demo is identical before and after
  (binding is inferred to the same name either way).
- **`@class_name` itself is unchanged** — it remains a documented, optional override for
  the rare case of a name collision on GDScript's flat global class registry. The README
  quick start and the docs site's teaching examples were swept to match: they show plain
  imports/exports and only mention `@class_name` where it's actually doing something.
- **Fixed: the `GUITKX2107` dangling-reference heal no longer depends on directory walk
  order.** A reference whose generated `.gd` was missing but whose **source `.guitkx`
  exists** was wrongly treated as dangling — so restoring a deleted component healed its
  dependents only if the filesystem happened to walk the component first (it does on NTFS,
  not necessarily on Linux — caught by CI). Dangling now means output **and** source gone,
  matching the diagnostic's own wording; the sweep heal and the watch poll share the
  predicate.

## [0.10.1] — 2026-07-14

**Godot version floor made explicit and gated.** The supported minimum is **Godot 4.4**
(evidence-based: the compiler core uses 4.3+ engine APIs, and the editor addon's bundled
native analyzer is a GDExtension with `compatibility_minimum = "4.4"`; `FoldableContainer`
needs 4.5 but is guarded and degrades gracefully). Verified on 4.7.

- Both plugins now **refuse politely on an unsupported engine** instead of failing on a
  missing API mid-sweep: the runtime addon disables its `.guitkx` watcher with a clear
  `push_error` (the runtime's global classes still load — that needs no plugin), and the
  editor addon surfaces the reason in its dependency dialog.
- Every documented claim aligned to the 4.4 floor (README, docs site version dropdown, FAQ).

## [0.10.0] — 2026-07-12

**Imports & mixed declarations.** `.guitkx` files now declare cross-file dependencies
explicitly and may hold several declarations. Cross-file resolution is **strict**: an
implicit reference to another component/hook/module is an error — import it.

- **`import { Name, … } from "specifier"`** in the preamble. Specifiers are relative
  (`./`, `../`) or root-aliased (`~/`, the project UI source root from a new `"root"` key
  in `guitkx.config.json`, default `res://`); they are extensionless (`.guitkx` implied).
  Engine-native `res://` / `uid://` are not valid import specifiers (they remain valid in
  `@uss` / `@theme` asset positions, which now also accept `~/`). **Named exports only.**
- **`export`** marks a declaration reachable across files. A file may now hold **multiple**
  top-level declarations (components, hooks, modules); the binding = `@class_name` override,
  else the first exported declaration. Non-exported declarations are file-private. Component
  imports stay lazy (`V.comp`), so cross-file component **cycles are legal**; value imports
  (hooks/modules) are eager `const` preloads and a value-import **cycle is an error** that
  prints the chain.
- **New diagnostics GUITKX2300–2309** (family-frozen): unresolved specifier, not-exported,
  not-declared, duplicate import, unused import, defined-but-not-imported, value-cycle,
  used-but-unexported, boundary crossing, import-after-first-declaration.
- **Migration codemod** — run once, `godot --headless --path . --script
  res://addons/reactive_ui/dev/migrate_0_10_0.gd`: it exports every declaration and writes the import lines
  for each file's cross-file references. Idempotent and re-runnable. The bundled examples
  (including the Doom demo) ship migrated. Full guide: [MIGRATION-0.10.md](MIGRATION-0.10.md).
- The generated-script parse check is now a **two-pass, counted CI gate** (a value import
  preloading a not-yet-written sibling no longer false-fails), and Fast Refresh re-renders
  only the component importers of a changed hook/module instead of the whole tree.

## [0.9.0] — 2026-07-11

**BREAKING — naming is now 1:1 loyal to Godot.** Every user-facing name is the official
Godot name: tags are class names, factories match tags verbatim, events are the native
signal with an `on` marker, style keys are the exact property/theme/StyleBoxFlat names.
No compatibility shims — a codemod migrates your project and every removed name fails
loudly with the exact replacement. **Read [MIGRATION-0.9.md](MIGRATION-0.9.md).**
Decision record: `plans/NAMING_LOYALTY_PROPOSAL.md` + `plans/WIDGET_INVENTORY.md` (every
official Godot 4.7 Control class accounted for).

### Changed
- **Tags are the official Godot class names.** The shorthand tags (`VBox`, `HBox`,
  `Grid`, `Margin`, `Panel`, `Center`, `Scroll`, `Tabs`, `RichText`) and lowercase
  element tags (`<vbox>`, `<label>`) are removed; write `<VBoxContainer>`, `<Label>`, ….
  **`<Panel>` now creates Godot's actual `Panel`** (the pre-0.9 alias meant
  `PanelContainer` — the codemod rewrites old usages). A removed tag compiles to a
  GUITKX0105 error carrying the exact rename.
- **`V.*` element factories match tags verbatim** — `V.vbox` → `V.VBoxContainer`,
  `V.button` → `V.Button`, `V.rich_text` → `V.RichTextLabel`, `V.audio` →
  `V.AudioStreamPlayer`, … (all 46, no exceptions). Structural factories stay lowercase
  (`fc`, `comp`, `memo`, `h`, `text`, `fragment`, `portal`, `suspense`,
  `error_boundary`, and the router set).
- **Events: the React aliases are removed.** The canonical form is `on` +
  PascalCase(signal) — `onPressed`, `onValueChanged`, `onTextSubmitted` — which reaches
  ANY signal of ANY node (this generic path already existed; it is now the only camelCase
  path). `on_<signal>` still binds verbatim. Removed: `onClick`, the polymorphic
  `onChange`, `onInput`, `onSubmit`, `onFocus`/`onBlur`, `onPointerDown/Up/Enter/Leave`,
  `onResize` — each emits a runtime warning naming its exact replacement for one release.
- **Style keys are the exact Godot names.** Renamed: `min_size` →
  `custom_minimum_size`, `clip` → `clip_contents`, `tooltip` → `tooltip_text`, `pivot`
  → `pivot_offset`, `color` → `font_color`, `outline_color` → `font_outline_color`,
  `expand_h`/`grow_h`/`h_align` → `size_flags_horizontal` (and the `_v` family →
  `size_flags_vertical`), `fill` → `anchors_preset`, `pad` → `content_margin_all`,
  `border_width` → `border_width_all`, `corner_radius` → `corner_radius_all`, `margin`
  → the four exact `margin_left/top/right/bottom` theme constants. Enum-valued keys take
  Godot's own constants (`Control.SIZE_EXPAND_FILL`) or the exact constant name as a
  case-insensitive string — the invented short strings (`"grow"`, `"stop"`, …) are gone.
  **Style `rotation` is now radians** (Godot's own `Control.rotation` semantics; the
  codemod wraps old degree values in `deg_to_rad(...)`). Kept extensions, explicitly
  documented: `min_width`/`min_height` (the `.x`/`.y` of `custom_minimum_size`).

### Added
- **Open tag vocabulary: any instantiable Godot `Node` class is a valid tag.** The
  compiler validates against ClassDB and emits `V.h("ClassName", …)`, so the entire
  official Control set works from markup — `<GraphEdit />` just works. Engine names are
  reserved: a project component shadowing a Godot class gets the new GUITKX0151 warning.
- **9 new curated elements** (named factory + tag + IDE metadata): `Panel`,
  `ReferenceRect`, `HScrollBar`, `VScrollBar`, `SubViewportContainer`, `BoxContainer`,
  `FlowContainer`, `SplitContainer`, and `VirtualJoystick` (new in Godot 4.7).
- **The StyleBox builder accepts any `StyleBoxFlat` property verbatim**
  (`border_width_left`, `corner_radius_top_left`, `shadow_size`, `skew`,
  `expand_margin_*`, …) plus the `*_all` umbrellas named after Godot's own setters
  (`set_border_width_all` → `border_width_all`, …) — full StyleBoxFlat coverage with
  zero maintained vocabulary.
- **A migration codemod** — `addons/reactive_ui/dev/migrate_0_9_0.gd` rewrites a
  project's `.guitkx` and hand-written `.gd` in place (dry-run mode, per-element
  `onChange` resolution, behavior-preserving `deg_to_rad` wrapping) and reports the few
  sites that need a human. Usage: [MIGRATION-0.9.md](MIGRATION-0.9.md).

### Fixed
- **A style/prop value that changes type between renders no longer crashes the diff.**
  GDScript raises on `int != String` Variant comparisons; the style and plain-prop
  diffs now compare `typeof` first. Reachable pre-0.9 with any prop that switched types
  across renders; made likely by enum keys accepting ints and constant-name strings.
## [0.8.7] — 2026-07-10

Four new `style` keys, a compiler correctness fix for a whole family of
comment-related miscompiles, and a measured compiler speed-up.

### Added
- **`material`, `texture_filter`, `texture_repeat`, and `z_as_relative` style keys.**
  All four CanvasItem properties are now recognized inside `style={ {...} }` with full
  reset-on-removal semantics (a removed key restores the class default), completing
  their natural pairs: `z_index` ↔ `z_as_relative`, `texture_filter` ↔ `texture_repeat`.
  `material` in particular lets a pooled `ShaderMaterial` ride the style dict with a
  stable identity, so per-frame uniform changes never force a reconcile — the pattern
  the Doom demo's wall shader uses.

### Fixed
- **A parenthetical comment split across two `#`/`##` lines inside a component or
  directive body's setup code no longer desyncs brace matching.** The body scanner
  treated setup code as markup (where `#` is literal text), so a `(` inside one comment
  line opened a phantom code island whose `)` on the *next* comment line was then
  comment-skipped — never closing, and surfacing as a bogus `GUITKX0304` "unclosed
  component body" anchored at the component's own `{`, arbitrarily far from the actual
  comment. Content mode is now tracked per delimiter-stack level with per-line
  classification inside bodies: prelude statements (and their `#` comments) scan as
  GDScript, markup-shaped lines and `return ( ... )` windows keep markup lexis
  (`<Label>Score #3</Label>` stays literal). Also fixes the same desync from keyword
  bait (`# early return (see docs`) and `#` comments inside multi-line array literals.

### Changed
- **The `.guitkx` compiler is ~28% faster per compile.** Every scanner hot loop
  (lexer, markup parser, body splitters/validators, markup-in-expression detection)
  now reads characters via `unicode_at` + integer comparisons instead of `s[i]`
  single-char-String indexing (which allocates a fresh String per access), and the
  markup parser's per-element line lookup is a binary search over a prebuilt
  line-start table instead of an O(n) prefix copy. Generated output is byte-identical
  across the whole example corpus; this is purely compile-time speed (per save, and
  per keystroke for live diagnostics).

## [0.8.6] — 2026-07-08

A reconciler and style-layer performance pass, plus a packaging fix so an Asset
Library install ships only the addon.

### Added
- **`reuse_by_slot` host prop.** Opt-in on a parent whose keyed leaf children are
  positionally stable — a per-frame list whose keys encode *data identity* rather
  than order. Those children then reconcile by slot (reused and patched in place)
  instead of being torn down and recreated when their keys change. This is the
  React-correct way to express slot reuse without dropping key semantics elsewhere.
- **`RUIConfig.host_node_pool`** (default `true`). Destroyed leaf host nodes are
  recycled through a per-class pool and re-diffed on reuse, instead of freed and
  recreated, cutting node churn on lists that add and remove frequently.

### Changed
- **Keyed child reconciliation is now mark-and-sweep.** The full-keyed path no longer
  allocates a per-frame key map and matched-set; it reuses a member key map plus a
  per-fiber `matched_pass` flag and sweeps unmatched fibers in a single pass.
- **`Style.apply` allocates far less.** It no longer builds throwaway per-node
  dictionaries and key arrays for unchanged theme channels (eager `{}` defaults and
  `.keys()` copies removed), substantially reducing per-styled-node overhead.

### Fixed
- **Asset Library / `git archive` install no longer ships repo tooling.** The
  `.gitattributes` export map was a denylist and had gone stale, so a Download-Commit
  install leaked `.claude/`, a stray `discordpost` note, and `export_presets.cfg` into
  the user's project. It is now an allowlist — only `addons/reactive_ui` ships — so new
  top-level files can never silently leak into an install again. ([#67])

[#67]: https://github.com/yanivkalfa/ReactiveUI-Godot/issues/67

## [0.8.5] — 2026-07-06

A correctness-focused pass from a full compiler/formatter/HMR audit. No API changes.

### Fixed
- **Markup-lexis brace/paren matching.** Every scan that locates a directive body, a
  component body, a `@match` body, or the `return ( ... )` window used plain
  GDScript lexis (`#` = comment) even though that content is markup — a literal `#`
  in element text (`<Label>Score #3</Label>`, a hex color, …) or a markup comment
  (`//`/`/* */`/`<!-- -->`) containing `}`/`)` could miscount the delimiters the scan
  was balancing, silently shifting where a body was believed to end (a miscompile,
  not just a parse error). These scans now use markup lexis by default, switching to
  GDScript lexis inside `{expr}` islands and directive/`@case` headers, and back to
  markup for a `return ( ... )` nested inside a directive/`@case` body.
- **Formatter no longer corrupts triple-quoted strings.** Re-anchoring an embedded
  GDScript block re-indented and collapsed double-spaces on every line, including
  lines inside an open `"""`/`'''` string — silently changing the string's runtime
  value. Lines inside an open multi-line string are now detected and emitted
  byte-verbatim.
- **Formatter no longer drops blank lines inside a directive body's prep code.** A
  segment splitter dropped every blank line outright while its sibling preserved
  interior ones as a bare newline; the two now agree (leading/trailing structural
  blanks are still trimmed, interior ones are kept).
- **A truncated closing tag at the very end of a markup window** (`<Box><` with
  nothing after it) used to pass a bounds guard that then scanned past the window
  looking for `>`, producing a confusing error instead of a clean "unclosed tag" one.
- **`format()` can now tell "formatted" from "fell back to verbatim".** Both used to
  return `ok:true` with the source unchanged, so a syntax error that skipped
  formatting looked identical to an already-canonical file. A new `fell_back` field
  distinguishes them; the in-editor formatter now warns once per file when it fires.
- **An attribute value containing an embedded `"` falls back to verbatim** instead of
  re-emitting an unescaped (and therefore corrupting) `name="value"`. Not reachable
  through the parser today (it can't produce such a value), but a defensive guard
  against a future escape-syntax change that forgets to teach the formatter to
  re-escape.
- **`@uss`/`@theme` no longer false-flags a `uid://` resource path as missing.**
  `FileAccess.file_exists` doesn't understand Godot 4.4+ uid-based resource
  references; the asset-existence check now defers straight to
  `ResourceLoader.exists`, which resolves both `uid://` and `res://` correctly.
- **Fast Refresh's module-vs-component classification is no longer a source-text
  guess.** `RUIHmr` used to decide "component vs. module/hook" by checking whether a
  reloaded script's source contained the literal text `static func render(` — a
  module whose own comment or string text happened to contain that substring could
  be misclassified, silently skipping the global re-render every other component
  needs when a shared module/hook changes. Generated components now carry an
  unambiguous `const __RUI_KIND := "component"` marker (read via
  `get_script_constant_map()`, like the existing `__RUI_HOOK_SIG`); the old
  source-text check remains only as a fallback for scripts that predate this fix.

### Documented
- **Hook dependency-array comparison is value-based, not identity-based, by design.**
  `useEffect`/`useMemo`/`useCallback` deps use GDScript `==` (deep-compares
  `Array`/`Dictionary`), diverging from React's per-item `Object.is` — documented at
  the source and in the README's Notes & limitations, including the perf tradeoff
  (a large deps array is deep-compared every render) and the escape hatch shape if
  it's ever needed.

## [0.8.4] — 2026-07-05

Compiler/watcher hardening shipped alongside **Reactive UI Editor 0.5.0** (the M2
"daily-driver parity" milestone of the in-Godot editor — see its own changelog). No
API changes.

### Changed
- **Per-call compile refs.** The compiler's component-reference accumulator (the
  `refs` map persisted into each `.diags.json` sidecar for dangling-reference
  detection, GUITKX2107) is no longer a static — `compile()` owns a per-call
  dictionary threaded through the emit context. The old static was safe only under an
  unstated "compiles never interleave" invariant; per-call makes re-entrancy and
  future threading structurally a non-issue. Sidecar output is unchanged.

### Fixed
- **Watcher error lines now carry a clickable path.** `push_error` dock entries
  navigate to the watcher's own script, not your `.guitkx`; the watcher now also
  prints a linkified `res://` line next to them (successes always had one). Line-level
  navigation for the same diagnostics lives in the editor addon's Problems panel,
  Project scope.
- **Recreated files report their errors again.** The watcher's per-file
  "last reported errors" memory is cleared for sources that no longer exist, so a
  file deleted and later recreated with the same broken content reports its errors
  instead of being suppressed by the stale entry.

## [0.8.3] — 2026-07-05

**The addon is now fully self-contained for store installs.** First user feedback on the Asset
Library listing, implemented: a store download no longer places README/CHANGELOG/LICENSE at your
project root (where they could collide with your own files) — `addons/reactive_ui/` carries its
own addon-focused `README.md`, a mirrored `CHANGELOG.md`, and its `LICENSE`, and the repository
root copies are excluded from release archives. No runtime code changes.

Ships alongside the new **Reactive UI Editor 0.4.0** (a separate asset): the in-Godot `.guitkx`
editor grew go-to-definition, find, cross-file diagnostics, rich hover, and a long list of
data-safety guarantees — see its own changelog in `addons/reactive_ui_editor/CHANGELOG.md`.

## [0.8.2] — 2026-07-04

**Deleting a component's whole folder is now caught by the watch poll, not just by the next save.**
Field re-test of 0.8.1's dangling-reference guard: deleting a component's *folder* removes its
generated outputs along with it, so no orphaned `.gd` survives for `has_stale` to notice, and a
dependent file isn't mtime-stale either — the 2-second poll stayed cold, and `GUITKX2107` only fired
on an unrelated save or editor focus-in.

### Fixed
- **The watch poll now reads each tracked file's sidecar references every tick** and goes hot the
  moment a dependency's state stops matching reality in either direction — unflagged-but-missing
  (needs the `GUITKX2107` flag) or flagged-but-restored (needs the heal recompile) — settling again
  once every state matches, so it never spins. Cost is one small JSON read per tracked file per
  tick, alongside the existing mtime pass.
- Pairs with `ide-extensions` LSP **0.8.6**, which fixes the matching VS Code-side gaps (the dynamic
  file-glob watcher never actually received folder-delete events; it's a single `**` watcher now).

## [0.8.1] — 2026-07-04

**Renaming or deleting a `.guitkx` no longer leaks its generated outputs.** Field capture,
minutes into 0.8.0: renaming `components/deep_tree.guitkx` left the old generated
`deep_tree.gd` behind — still declaring `class_name DemoDeepTree`, now a **duplicate** of the
real demo's global class, breaking resolution project-wide. The sweep (and the watch poll) now
detect generated outputs whose source is gone — identified by the `AUTO-GENERATED` header, so
hand-written scripts are never touched — and remove the whole family (`.gd`, sidecar, `.uid`s),
with a dock line per removal. Empty reads (editor scan window) never count as an orphan verdict.

### Added
- **`GUITKX2106` — duplicate class binding.** Copy-pasting a `.guitkx` used to poison the
  project *instantly*: the watch poll compiled the copy before you could rename it, producing a
  second `.gd` with the same `class_name`. Now the incumbent keeps compiling and the copy
  errors (`class \`X\` is already bound by <path> — rename this component`) with **no output
  written** — a duplicate class can never reach disk, and everything converges the moment you
  rename the copy.

- **Generated code no longer depends on the global class registry — components reference each
  other by path.** `<Card />` now compiles to `V.fc(V.comp("res://ui/card.gd"), …)` — a lazy,
  cached, path-based resolver — instead of `Card.render`. This removes an entire failure class
  at the root: a component created seconds ago mid-play-session, a game launched before the
  class existed, the editor's own rescan lag, and Godot's built-in "Synchronize Script Changes"
  loading a young reference — none of them can choke anymore, because the generated script
  parses with zero registry knowledge. Lazy loading also makes self-recursive and cyclic
  component graphs safe by construction. Hand-written `class_name` components and user
  expressions (`DemoHello.render` in your own code) keep the classic global-name form.
- **Brand-new components hot-link into a running game.** Godot registers global `class_name`s
  at launch, so a component created *after* F5 is unresolvable by name — the hot reload now
  detects the failure and retries with the class **linked by path** (an injected `preload`
  const, using the sweep's class→file map), keeping the session and all its state. Create a
  component, reference it, save: it appears in the running UI —
  `(1 new component(s) linked live)` in the Output. After the next restart the global registers
  and the linking naturally no-ops. Only classes from outside the guitkx pipeline still need a
  restart. (The push is deliberately **not** gated on the editor-side parse check anymore — that
  check fails transiently for exactly this case while the *editor's* registry catches up; the
  game's per-file isolation and the injection retry own the risk.)
- **`GUITKX2107` — deleting or renaming a referenced component errors at the dangling tag.**
  Dependents aren't mtime-stale, so nothing used to flag them — the first symptom was a runtime
  load failure at the next launch. Every compile now records the components a file references
  (in its sidecar); the sweep that removes a vanished component's outputs flags every dependent
  **in the same pass** — dock line, sidecar, VS Code squiggle at the tag — while its last good
  code keeps running (in the editor *and* in a live game, same as any compile error). Restore
  the component, or edit the reference away, and the next sweep heals the file automatically.
  The VS Code server (0.8.3+) pairs with it live: open documents re-validate whenever the
  component universe changes, and a deleted generated class is un-harvested instead of
  suppressing the unknown-component check forever. Re-saving a flagged-but-unchanged dependent
  is recognized as known-broken content (not stale), so the watch poll settles instead of
  sweeping every 2 seconds forever.

## [0.8.0] — 2026-07-04

**Runtime Fast Refresh (hot reload) — edit a `.guitkx` while your game runs under F5 and the
UI updates in place, hook state preserved.** Unity-toolkit parity, Godot-native mechanics: the
watcher pushes freshly-compiled scripts into the running session over the debugger protocol,
the game reloads them **in place** (`source_code` + `reload(keep_state=true)` — Callable
identity survives, so fiber matching keeps every component's hooks), and exactly the affected
components re-render (a synchronous, unsliced flush inside the debugger callback — no frame
where old handlers meet new code).

### Added
- **`core/hmr.gd` (`RUIHmr`)** — the game-side runtime: reload batches with per-file error
  isolation (a broken file keeps its last good code and is reported; the rest of the batch
  still swaps), empty-read holds, byte-identical skips, and component vs hooks-module
  classification (module change ⇒ **global** re-render, since any component may call it).
- **`editor/hmr_debugger.gd`** — the editor side: pushes each sweep's output (only scripts
  that passed the post-write parse check) to every active play session, and prints the game's
  report next to the sweep lines:
  `[guitkx] hot-reloaded 1 script(s) -> 1 component(s) re-rendered in 12 ms`.
- **`__RUI_HOOK_SIG`** — every compiled component embeds its ordered hook-call fingerprint.
  Same shape ⇒ state survives the swap; changed shape (hook added/removed/reordered) ⇒ that
  component's state **deliberately resets** (effect cleanups included) instead of silently
  corrupting — React Fast Refresh semantics.
- A live-root registry on the reconciler + `hmr_refresh` (targeted dirty-marking that defeats
  the bailout cache — the reason a reload alone never repainted anything).
- `tests/hmr_test.gd` (30 checks) incl. a real compiler→reload→reset end-to-end; suite wired
  into CI.

### Notes & limits
- Dev-only by construction: everything is gated on an attached debugger session
  (`EngineDebugger.is_active()`); exported/standalone builds carry zero HMR behavior.
- Renaming a component remounts it (fresh state) — same as Unity. `static var`s in
  hand-written modules are not migrated across reloads (Godot #105667); generated components
  are statics-free by design.
- Requires the game to be launched from the editor (F5). Save → screen latency is dominated
  by the 2 s watch poll.

## [0.7.2] — 2026-07-04

**THE "Godot never recompiles" root cause — static initializers don't run in the editor.**
GDScript `static var` initializers do not reliably execute during the editor's early script
indexing: `_VOCAB_PATH` read as `""` (its bare type default) instead of the vocabulary path, which
diverted production into the test-seam file-read branch, tried to read a file at path `""`, and
**held every compile of every editor session forever** — while headless runs (tests, CI, probes),
where statics initialize normally, stayed green. Proven with an instrumented editor run
(`path=<> len=0 is_default=false`) and the same run compiles cleanly with the fix.

### Fixed
- An empty vocabulary path now means DEFAULT: the embedded vocabulary const serves, no file is
  read, nothing holds. Only an explicit non-empty override (the test seam) reads a file.
- **Diagnostics from setup-value markup anchor correctly.** Hook aliasing ran BEFORE the markup
  splice, so every inserted `Hooks.` prefix (6 chars) shifted every later diagnostic offset —
  two `useState` calls pushed a `GUITKX0105` onto the *closing* tag instead of the opening one
  (both in the Godot dock and, via the sidecar, in VS Code). The splice now parses the original
  source first and aliasing runs on the spliced output; generated output is byte-identical
  (contract goldens unchanged), only the anchors move to where the error actually is.
- `filesystem_changed` sweeps that arrive DURING the editor's first scan are deferred to scan-end
  (mid-scan `FileAccess` flakes; generated classes aren't registered yet, so dependent
  parse-checks false-error).
- Held-only sweep retries no longer print a summary line per retry (the one-per-episode hold
  notice already announces them).

## [0.7.1] — 2026-07-04

**The watcher now provably notices your saves.** Field capture 2026-07-04: a `.guitkx` saved from
VS Code was never recompiled — editor focus-in and `filesystem_changed` were the only triggers,
and neither reliably fires for an external save. Worse, a sweep that found nothing stale printed
nothing, so "plugin dead" and "nothing to do" were indistinguishable from the Output panel.

### Fixed
- **Standing watch poll (2s)**: the plugin polls a cheap read-only staleness predicate
  (`has_stale`) and sweeps the moment any `.guitkx` changes on disk — no focus dance, no editor
  restart, saves picked up within ~2 seconds.
- **Same-second saves are seen**: mtimes are whole seconds, so a save landing in the same second
  as the last compile tied on mtime and was silently skipped until the next edit; mtime ties are
  now broken by content (the sidecar's `src_hash`), which is deterministic and never busy-loops.
- **Known-broken files don't churn**: a file whose current content already produced an error
  sidecar is hash-skipped by the poll — but its persisted errors are **re-surfaced on every
  sweep**, so a fresh editor session re-reports a still-broken file instead of staying silent
  (the dock dedup is what prevents spam, never silence).
- **Sidecars rewrite only when the verdict changes** (the LSP watches them for changes).

### Added
- **Sweep proof-of-life**: the first sweep of a session always prints
  `[guitkx] sweep: N .guitkx tracked -- X compiled, Y error(s), Z held`; later sweeps print it
  whenever they did work. A silent Output after startup now *means* the plugin is not running.
- A visible heartbeat while the initial sweep waits out the editor's first filesystem scan.

## [0.7.0] — 2026-07-04

**Directive bodies are code blocks — full Unity convergence (BREAKING).** A directive body
(`@if/@elif/@else`, `@for`, `@while`, `@case/@default`) is no longer bare markup children: it is
GDScript **preparation code plus `return ( <markup> )`**, exactly like ReactiveUIToolKit for
Unity — and it nests recursively:

```
@for (it in items) {
	var label = "row %s" % it
	if it == null:
		return null          # skip this item
	return ( <Label key={ str(it) } text={ label } /> )
}
```

### Breaking
- **The pre-0.7 bare-markup body errors with `GUITKX2103`** ("a directive body returns its
  markup — write `return ( <markup> )`"), live in the editor and at compile. Migrate a project
  in one shot: `godot --headless --path . --script
  res://addons/reactive_ui/dev/migrate_directive_bodies.gd -- res://<your-ui-dir>` (all bundled
  examples are migrated).
- **`.guitkx` canonical formatting is now spaces at width 2** (Unity-exact; "tab is 2 spaces").
  `dev/reformat_all.gd` sweeps a project; the VS Code extension formats on save.

### Added
- **Prep code in directive bodies**, per-iteration scoping, `return null` / bare `return`
  skip-guards, value returns (`return node_var`), and **markup values in prep statements and in
  component setup** (`var badge = ( <HBox>…</HBox> )` — directives inside included), lowered in
  place. Bodies run in the real function scope, so mutations behave like Unity's closures.
- **`GUITKX2104`**: a hook call inside a directive body is an error (Unity HooksValidator
  parity) — hooks must run unconditionally in setup.
- Runtime-proven 4-level nesting (`@for → @if/@else → @for → @if` with prep vars at every
  level): the kitchen-sink acceptance test renders its exact expected node tree.

### IDE
- VS Code extension **0.8.0** / language server **0.8.0**: the live tier, formatter (byte-parity
  corpus), and diagnostics all speak the new grammar; format-on-save ships enabled for
  `[guitkx]` with the spaces-2 defaults.

## [0.6.2] — 2026-07-03

**Scan-window completeness + instant GDScript feedback.** Field follow-up to 0.6.1: a stale
`.guitkx` could still survive a cold editor open uncompiled, because the startup sweep ran
inside the first filesystem scan where **mtime reads return 0** — every file looked fresh, the
sweep silently found nothing to do, and nothing retried. And a guitkx-legal typo (an unknown
identifier in an expression) produced no error anywhere until the generated `.gd` was first
loaded at play time.

### Fixed
- **The initial sweep waits out the editor's first scan** (`is_scanning()` poll) and runs the
  moment the filesystem is actually readable — no more silent no-op cold opens.
- **Zero mtimes count as stale** and **an empty source read of an existing file is held**
  (env-hold + auto-retry), never treated as clean or as a failed compile — an empty flake read
  can no longer skip a stale file or delete a healthy sibling `.gd`.

### Added
- **Generated `.gd` files are parse-checked immediately** after every compile (throwaway
  `GDScript`, resource cache untouched): unknown identifiers and type errors in `.guitkx`
  expressions now land in the editor dock at compile time — Unity parity with the Roslyn
  compile surfacing generated-C# errors instantly. `compile_file` reports it as `gd_parse_ok`.

## [0.6.1] — 2026-07-03

**Cold-open recovery.** A real-project field capture showed a cold Godot open holding every
`.guitkx` compile behind `GUITKX2507` ("vocabulary.json could not be loaded") for hours: in a
repo with `node_modules`/docs trees the editor's first filesystem scan — during which ALL
`FileAccess` reads return empty — runs for minutes, and nothing retried without a user edit.
An earlier upgrade sweep in that state had also consumed the force-recompile marker while
compiling nothing, leaving old-compiler sidecars ("unknown element `<HBox>`" on every host tag)
pinned forever.

### Fixed
- **The vocabulary is embedded in the compiler** (`guitkx_vocabulary.gen.gd`, generated from
  `vocabulary.json` by `dev/gen_vocabulary.gd`, drift-tested in `guitkx_test.gd`): production
  no longer file-reads at all, so the scan window cannot hold compiles. `vocabulary.json` stays
  the single source of truth, shared byte-identical with the LSP.
- **Held compiles auto-retry:** if a sweep ever does meet a not-ready environment, the plugin
  re-runs it every 2 s until it recovers — "retrying on the next compile" no longer waits for a
  user edit or an editor focus change.
- **The per-file `GUITKX2507` wall is gone:** environment-held files are announced once per
  episode, never one red dock line per file per sweep (`compile_all` now returns them as
  `held`, separate from `errors`).
- **The compiler-changed force-recompile survives the scan window:** the fingerprint marker is
  refreshed only when the forced sweep actually ran, and the fingerprint itself now reports
  "unknowable" when a source reads back empty — a scan-window read can neither consume the
  pending force nor persist a garbage fingerprint. Previously an upgrade followed by a cold
  open could strand outputs and sidecars written by the old compiler.
- **`.gdignore`** added to `ide-extensions/`, `ReactiveUIGodotDocs~/`, `plans/`, `research/`:
  the editor no longer scans `node_modules`/docs trees (first scan: minutes → seconds), and the
  codegen sweep skips them too.

### IDE
- VS Code extension **0.7.1**: pressing Enter after a closing tag (`</VBox>`) no longer indents
  one level too deep. Language server unchanged (0.7.0).

## [0.6.0] — 2026-07-03

**Early markup returns — the Unity way** (the minor bump: a new language capability).
A component can now `return ( <markup> )` anywhere, not just as its final statement:

```
component Panel(ready: bool = false) {
	if not ready:
		return ( <Label text="loading" /> )
	return (
		<VBox>…</VBox>
	)
}
```

### Added
- **Early and conditional markup returns are legal** and compile to scope-correct GDScript —
  lowered in place at the return's own indentation through a per-return line buffer, so control
  flow inside the returned markup (`@if`/`@for`) lands INSIDE the guard block, never hoisted past
  a scope boundary. Runtime-verified: both paths of a compiled guard render.
- **Live tier:** every early markup return is a full markup WINDOW — parse errors, unknown-tag
  did-you-means, key checks, and highlighting all work inside the guard (contract fixtures
  t04/t14 flipped legal; new t21 pins the two-window shape end-to-end).
- An UNCONDITIONAL early markup return dims everything after it as unreachable (`GUITKX0107`
  hint), including the now-dead final return — Unity's Site-B dim, mirrored live.

### Changed
- **`GUITKX2102` narrows to Unity semantics:** the only remaining error is "the FINAL top-level
  return is not markup". The 0.5.1-era live 2102 on early returns is gone (they're windows now),
  and 2102 left the vocabulary `live` list — it is compiler-only again.
- `GUITKX2101` stands: a component still needs a FINAL top-level markup return — conditional
  markup returns alone would leave `render()` paths that return nothing.

### IDE
- VS Code extension **0.7.0** / language server **0.7.0**; diagnostics docs page gains the
  GUITKX2102 and GUITKX2508 rows.

## [0.5.1] — 2026-07-03

**The field-triage release** — every defect from the first real-project test of 0.5.0 + extension
0.6.0, root-caused and fixed compiler + live tier in lockstep (`plans/FIELD_TRIAGE_FIX_PLAN.md`).

### Fixed
- **Live `GUITKX0105` no longer flags host elements.** The live PascalCase component check
  consulted only the project universe and never the vocabulary, so `<HBox>`/`<Button>`/`<Label>`
  (and every alias like `<VBoxContainer>`) lit up as "unknown component" the moment the workspace
  scan finished. Host tags are now exempt via the same predicate hover uses, and a typo'd host
  tag suggests the host tag itself (`<HBoxx>` → did you mean `<HBox>`?).
- **Markup in setup no longer sprays analyzer noise.** An early markup return (`return <s></a>`
  before the final one) leaked verbatim into the embedded-GDScript document — four bogus
  diagnostics on the line (syntax error, undefined identifier, standalone expression,
  unreachable). Setup-embedded markup is neutralized length- and newline-preservingly; the
  statement stays a real `return null`, so the correct Unity-parity unreachable-after-return dim
  survives.
- **`GUITKX2102` fires live and says what it means.** Early/conditional markup returns were
  compiler-only — with the Godot editor closed they appeared only as a stale sidecar entry at a
  drifting offset, never updating as you typed. The check now runs live (2102 joined the
  vocabulary `live` list), and the message is honest on both sides: only returning **markup**
  early is banned — `return null` guards and plain value returns were always legal.
- **Stale compiler diagnostics collapse instead of drifting.** While the buffer diverges from the
  last compile, compiler-only sidecar entries used to re-publish on every keystroke with clamped
  offsets, piling up at shifted positions until a Godot recompile. They collapse into one
  file-level note naming the codes, and re-anchor on the next compile.
- **The cold-open error wall is gone.** During the editor's first filesystem scan, `res://` reads
  of `vocabulary.json` come back empty for the whole scan window, and every per-file compile
  logged three red lines (~250 on this repo). The loader never parses an empty read (which alone
  removes Godot's own "Parse JSON failed" line), tries the absolute OS path as a best-effort
  fallback, and logs ONE hold notice per episode plus one recovery line. Generated outputs are
  kept throughout (0.5.0's guard). A pristine-clone cold open now prints two warning lines total.

### Added
- **`GUITKX2508` — directive-header grammar (compiler + live, identical rule).**
  `@for (i in 2: int5)` used to pass every tier silently; only Godot's own parser choked on the
  generated `for i in 2: int5:`. Headers are validated now: `@for` needs
  `<identifier> in <expression>`, and `@if`/`@while`/`@match`/`@case` need a single expression
  (an unbracketed `:` can never be one). Contract fixture `t20_bad_for_header` pins it.

### IDE
- VS Code extension **0.6.1** / language server **0.6.1** — see `ide-extensions/vscode/CHANGELOG.md`.
- `vsce` packaging is guarded: prepublish verifies the bundled server is complete and current
  (a local `vsce publish` without a fresh bundle could ship a server missing `vocabulary.json` —
  dead on startup with MODULE_NOT_FOUND).

## [0.5.0] — 2026-07-03

**The `.uitkx` syntax & diagnostics parity release.** `.guitkx` now matches Unity
ReactiveUIToolKit's grammar feature-for-feature, its diagnostic codes are renumbered onto
Unity's shared numbering (the minor bump), and the embedded-GDScript analysis is upgraded to
gdscript-analyzer 0.6 with Godot's own verbatim messages.

### Changed — **diagnostic codes renumbered** (breaking for anything matching code strings)

| old | new | meaning |
|---|---|---|
| `GUITKX0102` | `GUITKX2101` | missing/unknown declaration (the conditional-markup-return half is `GUITKX2102`) |
| `GUITKX0107` | `GUITKX0109` | moved per the shared table |
| `GUITKX0114` | `GUITKX0107` | unreachable code after the component's return (hint + dimming) |
| `GUITKX0113` | `GUITKX0026` | duplicate key (now an error) |
| `GUITKX0110` | `GUITKX2504` | structure error (shared 25xx Godot-reserved block) |
| `GUITKX0112` | `GUITKX2505` | structure error |
| `GUITKX0306` | `GUITKX2506` | Godot-specific parse error (different meaning than Unity's 0306) |

Kept: `0103 0104 0105 0106 0108 0013 0300–0305`. New (Unity numbers): `0014–0016 0018 0019
0111 0120 0121 0150 2100 2102 2105 2203 2210`; Godot-reserved `2504–2507`. One severity per
code everywhere, driven by `vocabulary.json`'s `severities` table (duplicate keys error;
unreachable code is a dimmed hint).

### Added
- **Unity-parity grammar:** markup comments (`//`, `/* */`, `<!-- -->`, and `{/* */}` in
  attribute lists), `<Fragment key={ ... }>`, the Unity text model (mid-text braces are
  literal; `GUITKX0150` migration warning), rules-of-hooks as errors (conditional / loop /
  match / lambda contexts + hook calls inside markup expressions), PascalCase/`use_` naming
  checks, effect-deps / binder-as-key / unused-param / asset-path checks (`0018 0019 0111
  0120 0121`), and a working `@uss` / `@theme` directive that preloads a Theme onto the root.
- **Live tier:** markup parse errors, unknown lowercase tags with did-you-mean, and unknown
  PascalCase components (checked against the full project universe) all squiggle while typing.
- `examples/demos/directives/` — every directive, all comment forms, `<Fragment key>`, `@uss`,
  spread-with-key; doubles as a grammar contract fixture.

### Changed
- **The compiler is fail-loud:** an error can never coexist with a successful compile; a broken
  `.guitkx` deletes its stale sibling `.gd` instead of letting the editor run code that no
  longer matches the source; the **last top-level markup return** is the component's output
  (Unity `useLastReturn` parity) and early/conditional markup returns are precise errors.
- **Embedded GDScript analysis bundles gdscript-analyzer 0.6:** Godot's verbatim 4.7 message
  texts (probed against the real binary), `Too few/many arguments` + invalid-argument errors on
  resolved calls, unreachable/unused code dims in the editor (LSP DiagnosticTags), diagnostics
  carry a real `code` + a link to the analyzer's Warning Reference, and the warning profile
  matches the engine's defaults (the `UNSAFE_*` family stays opt-in, like Godot itself).
- Names declared in sibling `.guitkx` files now feed the analyzer as **virtual libraries**
  (replacing a suppression hack) — cross-file references resolve on a fresh clone, and a typo
  colliding with a `.guitkx` name is no longer silently forgiven.

### Fixed
- The five filed silent-tooling bugs (G5–G9): unknown-tag pairs, unreachable-after-return
  flagging/dimming, the `fsunc():` typo silently accepted, the false `UNDEFINED_IDENTIFIER`
  cascade on a broken lambda initializer, and the `@for`-only missing-return miss.
- The vocabulary now loads lazily and self-heals; an unreadable vocabulary is an environment
  error (`GUITKX2507`) that **preserves** generated output instead of stale-deleting it (the
  editor's first filesystem scan used to wipe every generated `.gd` on a fresh clone).
- Parser hardening: commented `#elif` ghost branches, digit/dotted tags, unterminated attribute
  strings, directive token boundaries, `or`-fallback markup in expressions.

## [0.4.3] — 2026-07-02

Compiler indentation-anchor fixes and analyzer-ready hook typing.

### Fixed
- **One outlier setup line no longer breaks the whole generated `.gd`.** The depth-based reindenter
  anchored the block to its *shallowest* line, so a single accidentally-shallow line (say, a statement
  pasted at column 0) pushed every other line a level deeper — an over-indented statement with no
  preceding `:`, i.e. "expected an expression" plus the whole cascade of bogus follow-on errors. The
  reindenter (compiler + formatter, byte-identical with the IDE mirrors) now anchors to the **first
  non-blank, non-comment line** and clamps shallower outliers up to the body level.
- **An over-indented leading `#` comment no longer shifts real code.** Comments are legal at any
  indentation in GDScript; anchoring on one could dedent an `if` body out of its block (invalid
  generated `.gd`, and Format Document rewrote the source the same wrong way). Comments are skipped
  when picking the anchor; `_validate_hooks` uses the same anchor rule, so a shallow outlier no longer
  fakes a `GUITKX0013` "hook called conditionally" and commented-out hook calls no longer count.
- **A comment-only hook body now compiles to valid GDScript.** Comments are not statements, so the
  emitted function needed a trailing `pass`; both the top-level and module hook emitters add it.

### Added
- **`## @return-tuple(...)` doc tags on `useState`, `useReducer`, and `useTransition`.** Inert comments
  to Godot; the gdscript-analyzer (0.5.3+) reads them as fixed-shape return types, so `s := useState(0)`
  makes `s[1]` a typed, checkable `Callable` in the IDE extensions and the analyzer CLI.

## [0.4.2] — 2026-07-02

Editor-plugin reliability (shipped with IDE extensions 0.5.3).

### Fixed
- **External `.guitkx` edits recompile without restarting Godot.** The plugin recompiles on editor
  focus-in (a `.guitkx`-only external edit doesn't reliably flip Godot's `filesystem_changed`), with an
  mtime staleness guard keeping the pass cheap.
- **Errors-dock spam.** Diagnostics are de-duplicated (Godot's Errors dock is append-only) and a
  "resolved" line is printed when a previously-failing file compiles clean.

## [0.4.1] — 2026-07-02

Compiler robustness: forgiving indentation and reliable regeneration.

### Fixed
- **Mixed tabs and spaces in a component's `setup` no longer break compilation.** A line indented with,
  say, a tab + two spaces renders identically to two tabs, so the difference is invisible — yet the old
  reindenter compared indentation by raw characters and emitted GDScript with inconsistent indentation
  (an "unindent doesn't match" downstream) plus a spurious `GUITKX0013` "hook in a block". The compiler
  now measures indentation by **depth** (a tab and the inferred space-unit each count as one level), so
  mixed tabs/spaces normalize to consistent, valid GDScript. A genuine hook-in-a-block still warns.
- **Generated `.gd` now regenerate when the compiler itself changes, not only when the `.guitkx` is
  newer.** The staleness check was mtime-only, so after updating the library a sibling `.gd` that was
  newer than its source (but produced by the *old* compiler) was skipped forever — the editor kept
  loading stale output. `compile_all` now fingerprints the compiler pipeline and forces a full
  regeneration when it changes (stored in a machine-local `.godot` marker).

## [0.4.0] — 2026-07-01

Hooks go camelCase (full React parity) plus a round of compiler validation fixes.

### Breaking
- **Hooks are now camelCase, with no snake_case aliases.** `use_state`→`useState`, `use_effect`→`useEffect`,
  `use_ref`→`useRef`, `use_memo`→`useMemo`, `use_callback`→`useCallback`, `use_reducer`→`useReducer`,
  `use_context`→`useContext`, `create_context`→`createContext`, `provide_context`→`provideContext`,
  `use_layout_effect`→`useLayoutEffect`, `use_imperative_handle`→`useImperativeHandle`,
  `use_deferred_value`→`useDeferredValue`, `use_transition`→`useTransition`,
  `use_stable_callback`/`use_stable_func`/`use_stable_action`→`useStableCallback`/`useStableFunc`/`useStableAction`,
  `use_safe_area`→`useSafeArea`, `use_signal`→`useSignal`, `use_signal_key`→`useSignalKey`,
  `use_tween`→`useTween`, `use_tween_value`→`useTweenValue`, `use_animate`→`useAnimate`, `use_sfx`→`useSfx`.

- **Router hooks are camelCase too** (they were missed in the first pass) — **17 hooks on `RUIRouter`**:
  `use_navigate`→`useNavigate`, `use_location`→`useLocation`, `use_params`→`useParams`,
  `use_search_params`→`useSearchParams`, `use_blocker`→`useBlocker`, `use_query`→`useQuery`,
  `use_matches`→`useMatches`, `use_router`→`useRouter`, `use_go`/`use_can_go`→`useGo`/`useCanGo`,
  `use_navigation_state`/`use_navigation_base`→`useNavigationState`/`useNavigationBase`,
  `use_route_match`→`useRouteMatch`, `use_outlet_context`→`useOutletContext`,
  `use_resolved_path`→`useResolvedPath`, `use_location_info`→`useLocationInfo`, `use_prompt`→`usePrompt`.

  **Migration:** rename the **23 core hook tokens** and the **17 `RUIRouter.*` router hooks** (snake→camel)
  across your `.guitkx` and `.gd` files. The compiler auto-prefixes bare calls for **all 23** core hooks
  (previously only 11 auto-prefixed to `Hooks.*`); router hooks stay explicitly qualified as `RUIRouter.*`.

### Compiler
- **`@for`/`@while` bodies must contain a single root element** (`GUITKX0108`) — wrap siblings in a
  fragment `<>…</>`, matching the top-level render-root rule.
- **Duplicate keys are detected for expression keys** (`key={ str(i) }`), not only literal `key="x"`
  (`GUITKX0104`).
- **`@class_name` is validated** as a single identifier (`GUITKX0300`) instead of flowing into a broken
  generated `.gd`.
- **Misspelled declaration keywords** get a "did you mean 'component'?" hint (`GUITKX0102`).
- **`<` followed by whitespace** (e.g. `<  a>`) is reported as an invalid tag name, not silently parsed as
  a fragment.
- **Unreachable code after the markup return** is flagged (`GUITKX0114`), with line ranges so editors can
  dim it.

### Examples
- New **prop spread** and **context handle** demos in the gallery (previously feature-complete but undemoed).

### Docs
- **README refreshed** to match the library — examples and the hooks/router tables now use the camelCase
  hooks + React-style events, the pinned version is dropped, and the counts are corrected
  (**23 core hooks · 17 router hooks · ~60 `V.*` factories**).

## [0.3.0] — 2026-07-01

React-parity event handlers, prop spread, and context handles — the markup gets meaningfully closer to React.

### Runtime
- **React-style event handlers.** Wire events with camelCase names — `onClick` (→ Godot `pressed`),
  `onChange` (polymorphic: binds whichever of `item_selected` / `value_changed` / `text_changed` /
  `tab_changed` / `toggled` the control actually has), `onSubmit` (→ `text_submitted`), `onFocus` /
  `onBlur`, `onPointerDown` / `onPointerUp` / `onPointerEnter` / `onPointerLeave`, `onResize`, and any
  `onXxxYyy` → the `xxx_yyy` signal. The native `on_<signal>` spelling still works as an escape hatch to
  any Godot signal, so nothing breaks.
- **Prop spread `{...obj}`.** Spread a dictionary of props onto any element — `<Button {...cfg}
  onClick={ f } />` — exactly like React. Spreads merge with explicit props left-to-right (later wins),
  order-preserving, on both host elements and components.
- **Context handles.** `Hooks.create_context(default)` returns an `RUIContext` handle; pass it to
  `provide_context` / `use_context` instead of a bare string key to avoid cross-feature key collisions
  (the handle's object identity is the map key) and to receive a default value when no ancestor provides
  it. String keys still work (back-compat).

### IDE extensions
- **GUITKX VS Code 0.4.0 / VS 2022 0.4.0** teach the editor the React event names — completion (offered
  per control), hover showing the bound Godot signal + its arguments, signature help, unknown-attribute
  validation, and semantic highlighting — and recognize prop spread `{...obj}` in markup (highlighted,
  never flagged as unknown, preserved by the formatter).

## [0.2.2] — 2026-06-30

Custom drawing on any element, a README that finally matches the library, and a much smarter IDE.

### Runtime
- **Custom drawing.** A `draw_fn` prop (a `Callable(canvas_item)`) on any host element issues the node's
  `draw_*` calls during its `draw` signal; an optional `redraw_key` forces a repaint without changing the
  callback. A register-once trampoline reads the latest callback, so a fresh closure each render never
  re-subscribes — the Godot analogue of Unity's `OnGenerateVisualContent` / `RedrawKey`.

### Docs
- The README is rewritten to reflect the real surface — 21 hooks, ~14 router hooks, 63 `V.*` factories,
  router / signals / Suspense / item-model adapters / custom drawing / IDE tooling — instead of the old
  "MVP / 10 host elements" framing.

### IDE extensions
- **GUITKX VS Code 0.3.0 / VS 2022 0.3.0** now drive **plain `.gd`** files through gdscript-analyzer —
  diagnostics, completion, hover, navigation, project-wide rename, formatting, and semantic tokens — in
  addition to `.guitkx` markup + embedded GDScript (which gained find-references, rename, signature help,
  inlay hints, and code actions). On by default; bundles `@gdscript-analyzer/core` 0.5.2.

## [0.2.1] — 2026-06-22

A `.guitkx` toolchain fix, plus the demo gallery rewritten in markup.

### Compiler (.guitkx)
- **Hook return-type hints are preserved.** `hook foo(...) -> Array { … }` now emits
  `static func foo(...) -> Array:` instead of dropping the hint, so a caller's `var xs := foo()`
  type-inference compiles (it previously errored with "cannot infer the type of …"). Tuple-style
  `-> (a, b)` is still dropped (GDScript has no tuple type).

### Examples
- The demo gallery (`examples/`) is now authored entirely in `.guitkx` markup — one `component`
  per file (sub-components are sibling files; `module` is used only for hook / registry files),
  mirroring the ReactiveUIToolKit sample layout. The generated sibling `.gd` are git-ignored and
  regenerated by the editor plugin (and by CI before the class-cache scan).

### IDE extensions
- **Shared language server — VS Code 0.2.4 + VS 2022 0.2.4** (both bundle the same Node server, so
  these apply to both): forces tab indentation; **preserves authored blank lines** + **collapses
  embedded-GDScript whitespace** (`==␣␣␣null` → `== null`) when formatting; reports unknown elements
  (GUITKX0105) and unknown attributes (GUITKX0107) as **errors**; offers **style-dict key** +
  **built-in constant** (`Color.WHITE`) completion; forwards **go-to-definition** on GDScript symbols
  to Godot's LSP; and reads a project **`guitkx.config.json`** for formatter options.
- **VS Code only**: the 0.2.2 packaging/activation fix (the VSIX was shipping without
  `vscode-languageclient`, so the extension never activated) + format-on-save defaults + a
  self-closing-tag Enter-indentation fix (0.2.4). See `plans/IDE_EXTENSION_ISSUES.md` for the full list.

### Formatter (`guitkx_formatter.gd`)
- Mirrors the LSP formatter: preserves an authored blank line at setup-block boundaries and collapses
  runs of 2+ spaces in embedded GDScript (outside strings/comments). Byte-identical to the TS formatter.

## [0.2.0] — 2026-06-22

A breadth + correctness release: the router is rewritten into a full React-Router-style
component-tree spine, several runtime features land (Suspense, a signal registry, item-model
adapters, a styling `classes` layer, media + animation hooks), the `.guitkx` compiler gains inline
control-flow lowering, and a project-wide review fixed 20 confirmed bugs.

### Added
- **Component-tree router** (faithful port of ReactiveUIToolKit's router): `V.route`, `V.routes`
  (a ranked first-match switch that ALSO accepts the legacy `routes` table), `V.outlet` (nested /
  layout routes), `V.navigate` (declarative redirect), and `V.nav_link` (active-aware styling).
  Nested routes with merged `:params`, leaf-exactness (a leaf route consumes the whole path; a
  layout matches a prefix), splat `*`, `basename`, query strings, and navigation blockers. New
  hooks: `use_navigate`/`use_location`/`use_query`/`use_params`/`use_matches`/`use_resolved_path`/
  `use_search_params`/`use_go`/`use_can_go`/`use_blocker`/`use_prompt`, plus a nested-`<Router>`
  guard. The legacy `routes`-table API and the navigate-only context-split optimization are preserved.
- **Location model** — `RUIRouterLocation {path, query, state}`; history stores full locations and
  supports `go`/`can_go` + blockers; `use_location()` is basename-relative.
- **Suspense** — `V.suspense` (signal-await / frame-poll readiness; GDScript has no throw-to-suspend).
- **Signal registry** — `RUISignals` (process-wide string-keyed shared signals) + `use_signal_key`.
- **Text** — `V.text` + raw-String children auto-wrap to Labels; text-bearing hosts fold all-text
  children into the `text` prop.
- **`V.memo`** + an optional `props.__memo_eq` comparer.
- **Item-model adapter registry** — declarative `items` generalized to `ItemList`/`Tree`/`TabBar`/
  `OptionButton`/`PopupMenu`, selection/expansion preserved by item identity; `register_item_adapter`
  for custom controls.
- **Styling** — per-state StyleBox slots (`hover`/`pressed`/`focus`/`disabled`/`read_only`); a
  userland `classes: [...]` layer (`RUIStyleSheet`, ordered dict merge, inline `style` wins).
- **Hooks** — a real `use_deferred_value` (next-frame deferral); `use_animate` (Tween multi-track);
  `use_sfx` + `RUIMedia` one-shot audio; `V.audio` / `V.video` host elements.
- **Dev diagnostics** — hook-order validation + a state-update-during-render guard (debug-gated).

### Compiler (.guitkx)
- **Inline control-flow in expressions** — `@if`/`@elif`/`@else` and `@for` inside an embedded
  `{expression}` / lambda return now lower to a ternary / `.map` instead of hoisting render-level
  statements that couldn't see lambda locals (which produced invalid GDScript). `@while`/`@match`
  in an expression report `GUITKX0113`.
- Fixed: a member call on a non-Hooks receiver (`obj.use_state(...)`) is no longer auto-prefixed
  with `Hooks.`; a `module` declaring a component and a hook of the SAME name is now rejected; a
  conditional `return null` guard before the real markup return no longer fails the compile.

### Fixed (project-wide review)
- `classes`-only elements (no inline `style`) no longer error on re-render and now re-apply the
  resolved class style.
- `use_signal` re-binds its signal/selector/comparer every render (no longer frozen at mount).
- `<Outlet/>` falls back to its own children when a nested route stops matching (no stale slot).
- `ReactiveRoot.render()` / scheduling after `unmount()` no longer null-dereferences.
- `use_state`/`use_reducer` and `RUISignal` change-detection use reference equality for collections
  (Object.is), so a freshly-built equal Array/Dictionary still re-renders / notifies.
- Item adapters re-select at most the original number of duplicate-text items (and the right one).
- `use_can_go` re-renders on navigation; Suspense re-subscribes when its readiness source changes;
  `RUIMedia` one-shots no longer leak for looping streams; `use_query`/`use_params` return copies.

### Notes
Verified on Godot 4.7. Full suite green: core 91 / style 25 / guitkx / router (18 + 37) / demos 28 /
update / LSP 31. IDE extensions bump to VS Code 0.2.0 / VS 2022 0.2.0 (LSP + formatter fixes).

## [0.1.0] — 2026-06-20

First public version of the GDScript port of ReactiveUIToolKit — a React-style reactive
UI library for Godot 4.x (function components, hooks, a fiber reconciler, and a typed
style layer). Verified on Godot 4.7 (106 headless asserts green).

### Added
- **Core runtime** — virtual node tree (`RUIVNode`/`V`), fiber reconciler with
  current/work-in-progress alternates, two-phase begin/complete + post-order effect list,
  component **bailout**, **two-pass passive effects**, sync **layout effects**, **context**,
  **fragments**, **portals**, **keyed reconciliation**, deferred-updates-in-commit, and a
  structural **error boundary** (GDScript has no try/catch, so auto-catch is a documented limit).
- **19 hooks** — `use_state`, `use_reducer`, `use_ref`, `use_memo`, `use_callback`,
  `use_effect`, `use_layout_effect`, `use_context`, `use_signal`, `use_tween`/`use_tween_value`, …
- **Host layer** — ~50 `V.*` element factories; a generic adapter instantiates any of Godot's
  Control classes via `ClassDB`; declarative item-model adapters for `ItemList`/`Tree`
  (rebuild on change, preserve selection/expansion); controlled-input caret preservation.
- **Style layer** (`RUIStyle`) — friendly shorthands + a `StyleBoxFlat` builder + generic theme
  channels (colors/constants/fonts/font_sizes/icons/styleboxes = full Theme coverage).
- **Reactive store** (`RUISignal`), **router** (history/matcher/`V.router`/`routes`/`link`),
  **diagnostics** counters, **time-slicing**, and a `ReactiveRootNode` mount node.
- **Demo gallery** (`examples/`) — 24 demos incl. a **library stress test** and a **native
  stress test** (raw `ColorRect`s, no reconciler) for an in-game A/B of the reconcile cost.
- **CI/tests** — headless test suites (`tests/`), throughput + native-vs-library benchmarks
  (`tests/bench.gd`, `tests/bench_native.gd`, `tests/bench_compare.gd`, `tests/microbench.gd`).

### Performance
Three optimization rounds against an N-bouncing-boxes stress test (all general, not
stress-test-specific; correctness-neutral, all suites green):
- **Round 1 — fiber double-buffering.** The reconciler reuses each fiber's `alternate`
  instead of allocating a fresh fiber per element per frame, and drops the per-frame
  whole-tree sever (subtrees are released only on real deletion/unmount). In-game 1500 boxes:
  **~21 → ~33 fps**.
- **Round 2 — reconciler hot-path.** Eliminated the per-frame child-list array (walk the
  sibling chain), added a keyed positional fast-path for stable lists, an `is_same()` identity
  short-circuit before the prop deep-compare, inlined tag checks, and a shared empty children
  array. ~12% further.
- **Round 3 — call-inlining (GDScript is function-call-overhead bound).** Inlined the vnode
  factory and the hot reconcile/commit call chain (leaf fast-path, effect append, key-compare,
  begin-work). 1500-box reconcile **~23 → ~18 ms** (overhead vs native −22%).
- **Round 4 — fast-list path (the big structural win).** A stable list of host *leaves* (same
  count/keys/order, every child a childless host element) now bypasses the entire per-child
  fiber traversal: child fibers are reused in place and only the *changed* rows are diffed +
  committed (per-row bail-out, à la `React.memo` + Solid/Svelte fine-grained updates). Cuts
  reconcile-traversal **8.5 → 3.3 ms** and 1500-box reconcile **~18 → ~12.7 ms** (−31%);
  throughput roughly doubled (1500 boxes ~38 → ~69 fps headless). Mostly-static lists become
  nearly free. Backed by deep research into the GDScript interpreter — the remaining gap to
  native is GDScript interpretation itself; true native parity would need a small batched
  GDExtension (a documented, optional future step), not a rendering-path change.

### Notes
- A typed/pooled props layer was prototyped and measured against the native `Dictionary`;
  in pure GDScript the native dict wins (it's a C++ type), so the library stays on dicts.
  The experiment lives on the `typed-props` branch for reference.
