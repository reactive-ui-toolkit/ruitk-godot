# Bugs found after the "Reactive UI Toolkit" rename

Audit of branch `rebrand/umbrella` @ `2601bf4` (audited in a worktree of this repo at that sha),
against `6b0db56` (pre-rebrand merge-base). **Findings only — nothing was fixed or committed.**

The already-green battery (49/0 build, all GD suites, 402 editor, 55 hmr, 66/66 contract, 194/194
lsp, docs build+lint, three codemod tripwires, leftover-token greps, CI on PR #90) was not re-run.
This audit targets what those gates structurally cannot see: semantics behind correctly-renamed
tokens, packaging/distribution paths CI never exercises, and documents that are individually
token-clean but collectively wrong.

Items marked **[verified]** were reproduced by executing something (the codemod against a purpose-built
adversarial project, `git archive`, Godot 4.7 resource round-trips), not by reading.

**Severity key:** `HIGH` = user-visible failure on the happy path · `MED` = wrong/contradictory
shipped information, or a silent state loss · `LOW` = cosmetic, latent, or contrived-input only.

Summary: **1 HIGH, 6 MED, 8 LOW.** The HIGH one blocks the migration this whole release depends on.

> **SUPERVISOR VERIFICATION (2026-07-28):** every finding below was independently re-verified
> against the tree — all 15 factual anchors CONFIRMED (H-6/H-7's quoted strings are line-wrapped
> in the sources but present verbatim). **Nothing deleted; all findings are valid and cleared for
> the fix pass.** Fixes must NOT be committed — the supervisor reviews the diffs first.

---

## H-1 · The one-command migration is missing from every Asset Library install — `HIGH` **[verified]**

**Where:** [.gitattributes:22-23](../.gitattributes#L22-L23) · [.asset-template.json.hb:8-9](../.asset-template.json.hb#L8-L9) ·
[MIGRATION-0.13.md:31-33](../MIGRATION-0.13.md#L31-L33) · [README.md:52-53](../README.md#L52-L53) ·
[RuitkGodotDocs~/src/pages/Migrations/MigrationsPage.tsx:25-27](../RuitkGodotDocs~/src/pages/Migrations/MigrationsPage.tsx#L25-L27)

`.gitattributes` export-ignores the runtime addon's `dev/` folder:

```
22:/addons/reactive_ui_toolkit/dev export-ignore
23:/addons/reactive_ui_toolkit/dev/** export-ignore
```

`.asset-template.json.hb` publishes the runtime listing with `"download_provider": "GitHub"` +
`"download_commit": "{{ commit }}"` — the classic Asset Library's *Download Commit* provider, which
serves GitHub's `/archive/<sha>.zip`. That archive is a `git archive`, and `git archive` honours
`export-ignore`.

**Verified:**

```
$ git archive HEAD | tar -t | grep -c "addons/reactive_ui_toolkit/dev/"
0
$ git archive HEAD | tar -t | grep "migrate_0_13_0"
(no output — ABSENT from git archive)
```

So every user who installs the runtime addon through the in-editor **AssetLib** tab — the path
[README.md:52](../README.md#L52) lists *first*, and the path `MIGRATION-0.13.md:28-29` names ("install
the 0.13.0 runtime … from the store or the release zips") — receives an addon with **no `dev/`
folder at all**. The centrepiece command of the entire rebrand,

```
godot --headless --path . --script res://addons/reactive_ui_toolkit/dev/migrate_0_13_0.gd
```

fails immediately with a "cannot open file" error.

**Why this is wrong:** 0.13.0 is explicitly a *clean break with no compatibility window*
([MIGRATION-0.13.md:6-7](../MIGRATION-0.13.md#L6-L7)) — the codemod is not optional, it is the only
sanctioned upgrade route, and it is unreachable for a whole install channel. The docs site states
flatly that codemods "ship inside the addon (`addons/reactive_ui_toolkit/dev/`)"
([MigrationsPage.tsx:26](../RuitkGodotDocs~/src/pages/Migrations/MigrationsPage.tsx#L26)); for AssetLib
installs that is false.

**Note on provenance:** the mechanism is *pre-existing* — the allowlist `.gitattributes` landed in
0.12.0 and the old tree stripped `addons/reactive_ui/dev` identically (confirmed: `git archive
6b0db56 addons/reactive_ui` yields no `dev/`). 0.13.0 is where it becomes critical, because this is
the first release whose upgrade is *mandatory and universal*. The GitHub **release zip** is fine —
`publish.yml:140` zips the working tree, which includes `dev/`. Only the AssetLib/`git archive`
channel is affected.

---

## H-2 · Asset Library editor listing advertises a dependency floor the code rejects — `MED`

**Where:** [.asset-template-editor.json.hb:3](../.asset-template-editor.json.hb#L3) vs
[addons/reactive_ui_toolkit_editor/ruitk_editor_deps.gd:15](../addons/reactive_ui_toolkit_editor/ruitk_editor_deps.gd#L15)

The editor listing description says:

> REQUIRES the Reactive UI Toolkit — Godot addon, **0.8.4 or newer**: enable `reactive_ui_toolkit`
> first, then `reactive_ui_toolkit_editor`

but the code enforces:

```gdscript
15:const MIN_REACTIVE_UI := "0.13.0"
```

**Why it is wrong:** the rebrand sweep updated the *names* inside this sentence (`reactive_ui` →
`reactive_ui_toolkit`, and the product label) but left the *version number* at its pre-rebrand
value. It cannot be right by construction: 0.8.4 predates both the `addons/reactive_ui_toolkit`
path and the `Ruitk*` class names this editor consumes, and `ruitk_editor_deps.gd:11-14` says so in
its own comment ("0.13.0 is the rebrand floor … nothing older can ever be found here"). A user who
trusts the listing, installs runtime 0.12.1 + editor 0.11.0, and enables the plugin gets a hard
refusal: *"Reactive UI Toolkit — Godot 0.12.1 is installed, but this editor needs 0.13.0 or newer."*

This ships to the classic AL the moment `assetlib-editor-update` is armed. A token-grep cannot see
it — every token in the sentence is already correct.

---

## H-3 · Editor Project Settings silently reset; old keys orphaned in `project.godot` — `MED` **[verified]**

**Where:** [addons/reactive_ui_toolkit_editor/editor/ruitk_editor_settings.gd:11](../addons/reactive_ui_toolkit_editor/editor/ruitk_editor_settings.gd#L11) ·
[addons/reactive_ui_toolkit/dev/migrate_0_13_0.gd:62-66](../addons/reactive_ui_toolkit/dev/migrate_0_13_0.gd#L62-L66) ·
[MIGRATION-0.13.md](../MIGRATION-0.13.md) (omission)

The settings group changed:

```gdscript
# before (6b0db56, rui_editor_settings.gd:11)
const GROUP := "reactive_ui_editor/"
# after (ruitk_editor_settings.gd:11)
const GROUP := "reactive_ui_toolkit_editor/"
```

These are **`ProjectSettings` keys persisted in the user's `project.godot`** — the file's own
docstring says so: *"Settings live in project.godot, so they travel with the project."*

The codemod does not migrate them. `PATH_RENAMES` entries are all `addons/`-prefixed
(`migrate_0_13_0.gd:63-65`), so a `[reactive_ui_editor]` section never matches, and
`migrate_all` applies *path rules only* to `project.godot` (`migrate_0_13_0.gd:96-103`).

**Verified** — ran the shipped codemod against a project whose `project.godot` contained:

```ini
[editor_plugins]
enabled=PackedStringArray("res://addons/reactive_ui/plugin.cfg", "res://addons/reactive_ui_editor/plugin.cfg")

[reactive_ui_editor]
format_on_save=false
diagnostics_enabled=false
```

Result: the `enabled=` list migrated correctly, and the `[reactive_ui_editor]` block came through
**completely untouched**.

**Consequence:** every user who turned a feature *off* (`format_on_save`, `diagnostics_enabled`,
`highlighting_enabled`, `completion_enabled`, `hover_enabled`, `open_guitkx_in_editor`) silently gets
it back **on** after upgrading — `is_enabled()` defaults to `true` for the new, absent keys
(`ruitk_editor_settings.gd:50-51`) and `register_all()` then writes the new group in, leaving the
project file carrying both a dead section and a live one. Nothing warns; no test covers it;
`MIGRATION-0.13.md` never mentions ProjectSettings at all.

*Format-on-save flipping itself back on unannounced is the one that will actually bite someone.*

---

## H-4 · "terms unchanged" is claimed on six surfaces where a binding clause did change — `MED`

**Where:** [LICENSE:105-108](../LICENSE#L105-L108) vs
[addons/reactive_ui_toolkit_editor/CHANGELOG.md:11](../addons/reactive_ui_toolkit_editor/CHANGELOG.md#L11) ·
[ide-extensions/changelog.json:9](../ide-extensions/changelog.json#L9) ·
[ide-extensions/changelog.json:19](../ide-extensions/changelog.json#L19) ·
[ide-extensions/vscode/CHANGELOG.md:4](../ide-extensions/vscode/CHANGELOG.md#L4) ·
[ide-extensions/visual-studio/CHANGELOG.md:4](../ide-extensions/visual-studio/CHANGELOG.md#L4) ·
[ide-extensions/vscode/README.md:49](../ide-extensions/vscode/README.md#L49) (generated from
`changelog.json`, so it inherits the wording) · [MIGRATION-0.13.md:85](../MIGRATION-0.13.md#L85) (omission)

The `## Attribution` clause changed substantively between 1.0 and 1.1:

```diff
-you must include the line "Made with ReactiveUI" (or "ReactiveUI for
+you must include the line "Made with Reactive UI Toolkit" (or "Reactive UI Toolkit —
 Godot") in the product's credits, about screen, or accompanying documentation
```

This is a **binding obligation on every licensee**, not a title. A shipped game whose credits screen
reads "Made with ReactiveUI" no longer satisfies the 1.1 attribution clause once it upgrades.

The runtime changelog **gets this right** — [CHANGELOG.md:35-38](../CHANGELOG.md#L35-L38) explicitly
discloses `(credit line: "Made with Reactive UI Toolkit"); terms otherwise unchanged`. The other six
surfaces reduce it to a bare **"(terms unchanged)"**, which is inaccurate.

`MIGRATION-0.13.md` is worse by omission: it is the document a migrating user reads, it has an
"Unchanged, deliberately" section, and it never tells them their credits string must change. Line 85
("Every previously released version keeps the license and names it shipped with") covers the *past*
but says nothing about the obligation going *forward*.

---

## H-5 · Shipped addon README's first mount example calls an API that does not exist — `MED` **[verified]**

**Where:** [addons/reactive_ui_toolkit/README.md:49-50](../addons/reactive_ui_toolkit/README.md#L49-L50)

```gdscript
var root := RuitkReconciler.create_root(self)
root.render(V.fc(V.comp("res://hello.gd"), {}))
```

**Verified:** `RuitkReconciler` has no `create_root`. The only `create_root` in the codebase is
`RuitkRouteMatch.create_root(loc: String)` ([core/router/route_match.gd:15](../addons/reactive_ui_toolkit/core/router/route_match.gd#L15)),
which is unrelated. `RuitkRoot`'s actual surface
([core/reactive_root.gd](../addons/reactive_ui_toolkit/core/reactive_root.gd)) is
`static create(container, root_vnode)` / `set_root()` / `unmount()` — there is no `render()` either.
The correct form is the one the root README already uses at
[README.md:106](../README.md#L106): `RuitkRoot.create(self, V.fc(...))`.

**Provenance:** pre-existing — `6b0db56:addons/reactive_ui/README.md` had the identical broken snippet
as `RUIReconciler.create_root`. The rename faithfully swept a token inside code that was already
wrong, which is exactly why greps and suites both stayed green. Flagging it because this is the
**first code sample in the addon that ships to every user**, and 0.13.0 re-ships it.

---

## H-6 · Editor README's "drop in a newer analyzer" instruction now creates a second folder — `MED`

**Where:** [addons/reactive_ui_toolkit_editor/README.md:124-126](../addons/reactive_ui_toolkit_editor/README.md#L124-L126)

> A newer analyzer can be dropped in at any time by unzipping a `reactive-ui-analyzer-*.zip` from
> [gdscript-analyzer releases](...) **over the same folder**.

The analyzer repo is deliberately unrenamed (R8), and its zip still extracts to
`addons/reactive_ui_analyzer/` — `publish.yml` says so in its own comment and compensates with an
explicit rename:

```yaml
247:  # The analyzer repo (unrenamed, R8) still ships the folder as addons/reactive_ui_analyzer —
248:  # move it to the toolkit name this repo bundles and feature-detects.
249:  mv addons/reactive_ui_analyzer addons/reactive_ui_toolkit_analyzer
```

CI performs that `mv`; **the user following the README does not**. Unzipping "over the same folder"
therefore creates a *second* folder alongside `addons/reactive_ui_toolkit_analyzer/`, leaving two
`gdscript_analyzer.gdextension` descriptors both registering the class `GdscriptAnalyzer`. The
instruction needs the rename step, or the sentence needs to name the real destination.

**Checked and NOT a bug (recording so it isn't re-investigated):** the `mv` itself is safe. I read the
real descriptor at `RG-work/addons/reactive_ui_analyzer/gdscript_analyzer.gdextension` — its
`[libraries]` entries are **relative** (`bin/gdscript_gdext.windows.x86_64.dll`, …), not
`res://`-absolute, so relocating the folder does not break GDExtension loading. Detection is
`ClassDB.class_exists(&"GdscriptAnalyzer")`
([lsp/guitkx_analyzer_bridge.gd:36](../addons/reactive_ui_toolkit_editor/lsp/guitkx_analyzer_bridge.gd#L36)),
which is path-agnostic.

---

## H-7 · The documented "symptom" of skipping the delete step does not actually occur — `MED` **[verified]**

**Where:** [MIGRATION-0.13.md:49-51](../MIGRATION-0.13.md#L49-L51) ·
[CHANGELOG.md:30-32](../CHANGELOG.md#L30-L32) ·
[addons/reactive_ui_toolkit_editor/CHANGELOG.md:11](../addons/reactive_ui_toolkit_editor/CHANGELOG.md#L11) ·
[ide-extensions/changelog.json:9](../ide-extensions/changelog.json#L9) ·
[addons/reactive_ui_toolkit/dev/migrate_0_13_0.gd:16](../addons/reactive_ui_toolkit/dev/migrate_0_13_0.gd#L16)

Five surfaces tell the user the same thing — that if they skip deleting the old addon folders,
**"duplicate `class_name` parse errors are the symptom."** `MIGRATION-0.13.md:47-49` builds the whole
argument on it: *"after updating you have BOTH `addons/reactive_ui` and `addons/reactive_ui_toolkit`
side by side, and both declare the same global classes."*

**Verified — it does not happen.** I built the exact scenario (0.12.1 and 0.13.0 addon generations
installed side by side, both `core/v.gd` files present and both declaring `class_name V`) and ran a
fresh headless editor scan:

```
$ grep -h "^class_name" .../reactive_ui/core/v.gd .../reactive_ui_toolkit/core/v.gd
class_name V
class_name V

$ godot --headless --path . --editor --quit   # after rm -rf .godot
UID duplicate warnings ......... 39
class_name errors/warnings ...... 0
```

Zero diagnostics mentioning `class_name`. The **actual** observed symptom is 39 ×
`WARNING: UID duplicate detected between res://addons/reactive_ui_toolkit/core/<f>.gd and
res://addons/reactive_ui/core/<f>.gd` — a consequence of UIDs being correctly preserved across the
folder rename, and something **no** document mentions.

Resolution is silent rather than erroring: the global class cache ends up holding only
`res://addons/reactive_ui_toolkit/core/v.gd` and `…/hooks.gd`, i.e. the new addon wins (it sorts
after `reactive_ui`, so it registers last). No user-visible complaint either way.

**Why this is wrong:** the guidance points users at a signal that never appears. Someone who skips
step 1, sees no `class_name` error, and concludes they are fine will leave a full stale addon copy in
their project indefinitely — carried into export presets, duplicated in go-to-definition and the
editor addon's project scan, and emitting 39 warnings every scan. The instruction is right; its
stated justification and its stated symptom are both wrong.

**Scope of my check:** headless `--editor --quit` on Godot 4.7 only. I did not verify the GUI Errors
dock, which could conceivably surface something headless does not. Either way the UID warnings are
undocumented and the claim "both declare the same global classes" is inaccurate on its face — only
`V`, `Hooks`, and the 25 unchanged `Guitkx*` names overlap; the `RUI*` and `Ruitk*` sets are disjoint
by construction.

---

## L-1 · Neither README mentions the 0.13 rename or its codemod — `LOW`

**Where:** [README.md:177-183](../README.md#L177-L183) · [addons/reactive_ui_toolkit/README.md:66-70](../addons/reactive_ui_toolkit/README.md#L66-L70)

Both READMEs still present `migrate_0_11_0.gd` as *the* migration command and never reference
`MIGRATION-0.13.md` or `migrate_0_13_0.gd` — after the largest breaking change in the project's
history. Their bodies are fully swept to `Ruitk*` spellings, so a reader sees new names with no
explanation of how to get there.

The addon README compounds it: line 66 reads *"Migrating a pre-0.10 project is one idempotent
command"* and then prints the **0.11** codemod — a pre-0.10 project needs `migrate_0_10_0.gd` first.
(That mismatch predates the rebrand.)

---

## L-2 · Codemod path rules are unanchored — rewrite `addons/reactive_ui` in any string context — `LOW` **[verified]**

**Where:** [addons/reactive_ui_toolkit/dev/migrate_0_13_0.gd:62-66](../addons/reactive_ui_toolkit/dev/migrate_0_13_0.gd#L62-L66),
[:112-118](../addons/reactive_ui_toolkit/dev/migrate_0_13_0.gd#L112-L118)

`_compile_pairs` builds `\baddons/reactive_ui\b` with no `res://` anchor, so the rule fires on any
occurrence of that literal.

**Verified** — from the adversarial run:

```gdscript
const R = "user://addons/reactive_ui/save.dat"
# becomes:
const R = "user://addons/reactive_ui_toolkit/save.dat"
```

A `user://` data path, a URL, or prose in a docstring gets silently rewritten. Contrived, hence LOW —
but it is a real false-positive class, and the codemod writes files in place.

**Verified safe in the same run** (the traps that *don't* fire, worth recording): user classes
containing a renamed name are untouched (`MyRUIHostAdapter`, `MyRUIHost.new()`, `RUIHostExtra`); a
user's own `addons/reactive_ui_widgets/` path is untouched (the `\b` guard works because `_` is a word
char); `.tscn`/`.tres` `path=` refs and `project.godot`'s `enabled=` list migrate correctly; and a
second run reports **`migrated 0`** — idempotency holds.

---

## L-3 · The rename tripwire only guards `examples/` — `LOW`

**Where:** [tests/guitkx_rename_migrate.gd:12](../tests/guitkx_rename_migrate.gd#L12)

```gdscript
var res := Migrate.migrate_all("res://examples")
```

Stale `RUI*` spellings or `addons/reactive_ui` paths reintroduced in `tests/`, `scripts/`, `dev/`, or
root-level `.gd` are invisible to the gate. (It matches the scope of the 0.10/0.11 tripwires, which
are identically `res://examples`-scoped, so this is consistency rather than regression — but the
0.13 wave touched 277 files well outside `examples/`, so the mismatch between blast radius and guard
radius is wider here.) Note also that `_walk` deliberately skips `addons/`
([migrate_0_13_0.gd:162](../addons/reactive_ui_toolkit/dev/migrate_0_13_0.gd#L162)), so the tripwire can
never guard the addon sources themselves.

---

## L-4 · Class renames are never applied to `.tscn`/`.tres` — latent, currently unreachable — `LOW` **[verified]**

**Where:** [addons/reactive_ui_toolkit/dev/migrate_0_13_0.gd:68-71](../addons/reactive_ui_toolkit/dev/migrate_0_13_0.gd#L68-L71),
[:92](../addons/reactive_ui_toolkit/dev/migrate_0_13_0.gd#L92)

`with_classes` is true only for `CODE_EXTS` (`gd`, `guitkx`); scene/resource files get path rules only.

Godot **does** persist global class names into `.tres`. Verified by round-tripping a real resource
through Godot 4.7:

```
[gd_resource type="Resource" script_class="RUIStyleSheetProbe" format=3]
```

My adversarial `.tres` carrying `script_class="RUIStyleSheet"` survived the codemod unchanged.

**Currently harmless, and I want to be precise about why:** all 36 renamed classes are `RefCounted`
(verified for `style_sheet`, `style`, `config`, `component_state`, `context`, `diagnostics`), so none
can be saved as a `.tres`, and packed scenes reference node scripts by **path only** — verified by
packing and saving a scene whose node script had a global `class_name`:

```
[node name="Root" type="Control" parent="."]
script = ExtResource("1_ku22l")     # no script_class attribute
```

So there is no reachable path today. Recording it as a latent gap: the moment any `Ruitk*` class
becomes a `Resource`, this codemod silently under-migrates.

---

## L-5 · `CLA.md` is half-renamed — `LOW`

**Where:** [CLA.md:1](../CLA.md#L1), [CLA.md:3](../CLA.md#L3) vs [CLA.md:11](../CLA.md#L11)

```
1:# ReactiveUI Contributor License Agreement
3:The ReactiveUI family offers commercial licenses over the combined work, so
...
11:Thank you for contributing to the Reactive UI Toolkit family of projects ("the
```

The title and opening rationale keep the old brand while the body below the `---` uses the new one —
the same document contradicts itself. `CLA.md` is live (contributors accept it) and is not on the
intentionally-unchanged list.

---

## L-6 · Stale export path in `export_presets.cfg` — `LOW`

**Where:** [export_presets.cfg:14](../export_presets.cfg#L14)

```ini
export_path="build/ReactiveUI-Gadot.exe"
```

Still the old (and typo'd) name. Dev-only — `export_presets.cfg` is export-ignored and not shipped —
so cosmetic, but it is a genuine miss of the rename sweep.

---

## L-7 · Em-dash collision makes the product name read as a sentence break — `LOW`

**Where:** [RuitkGodotDocs~/README.md:1](../RuitkGodotDocs~/README.md#L1) ·
[.claude/skills/new-component/SKILL.md:3](../.claude/skills/new-component/SKILL.md#L3), [:6](../.claude/skills/new-component/SKILL.md#L6)

```
# Reactive UI Toolkit — Godot — documentation site
description: Create a new .guitkx component for Reactive UI Toolkit — Godot — file placement, ...
```

The product name now *contains* an em-dash, so appending an em-dash clause produces `— Godot —`,
which parses as an aside rather than a title plus qualifier. Mechanically correct tokens, degraded
prose. Rephrase (`… — Godot: documentation site`) rather than re-token.

---

## L-8 · The new rename tripwire is wired into `test.yml` but not into the Publish gate — `LOW` **[verified]**

**Where:** [.github/workflows/publish.yml:116-134](../.github/workflows/publish.yml#L116-L134) vs
[.github/workflows/test.yml:66-114](../.github/workflows/test.yml#L66-L114)

The wave added `tests/guitkx_rename_migrate.gd` and gated it in `test.yml:113-114`. The
`release-addon` job's "Verify tests pass" step was not updated. Enumerated:

```
test.yml runs 15 suites; publish.yml release-addon runs 11.
Only in test.yml: contract_dump.gd, guitkx_migrate.gd, guitkx_modernize.gd, guitkx_rename_migrate.gd
```

So a release can be cut without the rename tripwire — or the contract-golden freshness check — ever
running in the Publish workflow.

**Mitigating:** `publish.yml` already omitted the other two codemod tripwires and `contract_dump`
before this wave, so the new omission is *consistent* with existing intent rather than a regression;
and `test.yml` gates every push/PR to `master`/`dev`, so anything reaching a release has normally been
checked. Flagging it because Publish is the last gate before artifacts go out, it has not run since
the rename, and the tripwire this wave introduced is the one designed to catch exactly the class of
mistake this wave could make.

---

## Judged NOT bugs (recorded so they are not re-investigated)

- **`MIGRATION-0.13.md:48` "both declare the same global classes"** — inaccurate as written, but folded
  into **H-7** rather than filed separately, since it is the same sentence.
- **`LICENSE-COMMERCIAL.md:12`** and **`LicensingPage.tsx:106,191`** refer to "the Reactive UI Toolkit
  Community License" with no version, while `LICENSE` is now 1.1. Version-less references stay correct
  as the license evolves; deliberate-looking, not a defect.
- **`RuitkGodotDocs~/index.html:6` `href="/logo.png"`** — root-absolute, but Vite base-prefixes
  public-dir asset URLs in `index.html` at build time, and the value is unchanged from before the
  rebrand (only the base's value changed). Not rename-induced.
- **`plugin.cfg author=` changed from the owner's name to `"Reactive UI Toolkit"`** — within group b's
  ratified "authors" scope, not an accidental sweep of a person attribution.
- **`test.yml` never runs `doom_game_test.gd`** (listed as a suite in `CLAUDE.md`) — pre-existing and
  unrelated to the rename.
- **`guitkx_codegen.gd:261-267` compiler-fingerprint list omits `resolve`/`config`/`codegen`/`formatter`**
  — pre-existing design. The rename does change the fingerprint (paths + contents), which invalidates
  every `.diags.json` sidecar and forces one full recompile; that is expected and benign.

---

## Checked and clean (so the next pass can skip them)

- **36-pair class table is complete.** Cross-checked `CLASS_RENAMES` against every `class_name` in
  `6b0db56:addons/**`: 34 `RUI*` + `ReactiveRoot` + `ReactiveRootNode`. `RUIGuitkx` is real — it is
  only invisible to `grep '^class_name'` because `guitkx/guitkx.gd` begins with a UTF-8 BOM.
- **No shadowing risk in the rename table.** `\b…\b` whole-word matching makes the "longest-first"
  ordering unnecessary but harmless (`RUISignal` cannot match inside `RUISignals`, etc.).
- **UIDs preserved across the folder rename** (`core/vnode.gd`, `core/reconciler.gd`, `core/v.gd`
  sidecars byte-identical to `6b0db56`), so existing `uid://` references in user scenes still resolve.
  *Correct behaviour, but it has an undocumented flip side during the both-installed window — see **H-7**.*
- **No core file basenames changed** — `reactive_root.gd` / `reactive_root_node.gd` kept their names,
  so user `preload()`/`ext_resource` paths only needed the folder rewrite the codemod performs.
- **Meta keys deliberately untouched** (`rui_content`, `__rui_events`, `__rui_draw`, `__rui_pool_old`,
  `__rui_boxw`, `__rui_capw`) and consistent between code and docs — no doc claims a `ruitk_` spelling.
- **`.gitattributes` allowlist correctly re-pointed** to the new folder names (the H-1 issue is the
  pre-existing `dev/` rule, not a rename miss).
- **Version coherence:** runtime `plugin.cfg` 0.13.0 · editor `plugin.cfg` 0.11.0 · vscode 0.13.0 ·
  lsp-server 0.13.0 · vsixmanifest 0.13.0 · changelog.json lanes all agree.
- **All 5 LICENSE copies byte-identical** (md5 `44cfc79f…`, including the differently-named
  `GuitkxVsix/LICENSE.txt`) and correctly retitled 1.1.
- **GD↔TS classifier parity:** the only functional class-name *string* comparisons are
  `guitkx.gd:529` (`ret == "RuitkVNode"`) and `declScan.ts:145` (`ret === "RuitkVNode"`) — both renamed
  in lockstep. No group/signal/EditorSettings-theme keys were bent by the rename.
- **No hardcoded addon-path filters** in `plugin.gd` / `hmr.gd` / codegen beyond the preload and
  compiler-fingerprint lists, all consistently updated.
- **Codemod handles MIGRATION-0.13.md's stated order.** Ran it in a project holding *both* addon
  generations (0.12.1 + 0.13.0 side by side, as a store update leaves them): it completed cleanly and
  migrated correctly despite duplicate `class_name V`/`Hooks` in the project. The documented
  update → codemod → delete-old-folders sequence works. *(That same scenario is what surfaced **H-7** —
  the sequence is fine; the document's description of what goes wrong if you skip step 3 is not.)*
- **VS2022 TextMate grammar's single `RuitkVNode` mention** (vs. three in the VS Code grammar) is a
  pre-existing divergence, not a rename miss — the old file had exactly one `RUIVNode` too.
- **Docs `/ruitk-godot/` Pages base** matches the new repo slug, and `main.tsx`'s router basename
  derives from `BASE_URL`, so the two cannot drift.

---

## Suggested triage order

1. **H-1** — blocks the release's mandatory upgrade path for AssetLib users. Cheapest fix is
   un-ignoring `dev/` (or shipping the codemod outside `dev/`); either way it should land before
   Publish runs.
2. **H-2** — one number in `.asset-template-editor.json.hb`; wrong the moment the AL job is armed.
3. **H-3** — needs a codemod rule for the `project.godot` settings section plus a line in
   `MIGRATION-0.13.md`.
4. **H-7** — correct the symptom text on five surfaces (and mention the 39 UID warnings) so users can
   actually tell whether they skipped the delete step.
5. **H-4** — wording on six surfaces; **H-5** — three lines in the shipped addon README;
   **H-6** — one sentence.
6. The `L-*` items at leisure.

Fastest single win: **H-2**, **H-5**, **H-6** and the **H-4** wording are pure text edits. **H-1** and
**H-3** are the two that need a real decision.

---

## Fix pass

Executed 2026-07-28 on `rebrand/umbrella`, **uncommitted** (supervisor reviews `git diff` first).
All 15 findings addressed. Per-finding disposition:

| # | Disposition | Where |
|---|---|---|
| **H-1** | FIXED — the two `dev` export-ignore lines removed from `.gitattributes` (cheapest direction, per ruling); comment replaced with a NOTE explaining why `dev/` must stay in the archive. Verified: `git archive` now carries 21 `dev/` entries incl. `migrate_0_13_0.gd`; the editor addon is still correctly excluded (0 entries). | `.gitattributes:19-25` |
| **H-2** | FIXED — dependency floor `0.8.4` → `0.13.0`, matching `ruitk_editor_deps.gd:15`. Only the version number in the description changed; every marketplace identity field untouched. | `.asset-template-editor.json.hb:3` |
| **H-3** | FIXED — codemod gained `SECTION_RENAMES` + `_migrate_sections`/`_cut_section`/`_merge_ini_bodies`/`_ini_key`, applied to `project.godot` only. Collision-aware: if the 0.11.0 editor plugin already wrote a fresh `[reactive_ui_toolkit_editor]`, the OLD values win and the two sections merge into one. `MIGRATION-0.13.md` gained a bullet naming all six toggles; the 0.13.0 changelog entry now names the settings rewrite. Verified on two purpose-built projects (plain + collision): values preserved, one section out, `migrated 0` on re-run. | `migrate_0_13_0.gd:70-78,109-118,163-236` · `MIGRATION-0.13.md:40-47` · `CHANGELOG.md:27-36` |
| **H-4** | FIXED — "(terms unchanged)" replaced with the binding-clause disclosure on all six surfaces. The two generated-lane surfaces were edited in `ide-extensions/changelog.json` (source of truth) and regenerated via `changelog.mjs extract` ×3 + `extract-overview`; `verify` green, exactly one line changed per generated file (HISTORY bodies untouched). `MIGRATION-0.13.md` gained a dedicated "The one licence change that binds you" section. | `changelog.json:9,19` → 4 generated files · `MIGRATION-0.13.md:96-107` · `CHANGELOG.md:37-43` |
| **H-5** | FIXED — the non-existent `RuitkReconciler.create_root(...)` / `.render(...)` pair replaced with the real `RuitkRoot.create(self, V.fc(...))` mount, in the same `_ready`/`_exit_tree` shape the root README uses. | `addons/reactive_ui_toolkit/README.md:47-61` |
| **H-6** | FIXED — the drop-in instruction now names the real destination and the required rename (`addons/reactive_ui_analyzer` → `addons/reactive_ui_toolkit_analyzer`), states why the analyzer repo keeps the old name, what unzipping as-is would produce, and why relocating is safe. | `addons/reactive_ui_toolkit_editor/README.md:124-132` |
| **H-7** | FIXED on **six** surfaces — the five enumerated plus `MigrationsPage.tsx`, which the audit's grep missed because the phrase is split across JSX `{' '}` boundaries. Every one now states the real symptom (`UID duplicate detected` warnings, 39 in a stock install), explains the UID-preservation cause, and warns that the shared class names resolve *silently* in the new addon's favour — so a clean Errors dock is not evidence the delete step was done. | `MIGRATION-0.13.md:47-61` · `CHANGELOG.md:27-36` (+addon mirror) · `changelog.json:9` → editor `CHANGELOG.md:11` · `migrate_0_13_0.gd:13-17` · `MigrationsPage.tsx:48-58` |
| **L-1** | FIXED — root README gained an "Upgrading from 0.12.x" block in Install (command + delete step + `MIGRATION-0.13.md` link) and the imports bullet now says which codemod it is; the addon README gained a full `## Upgrading` section and an ordered `0.10 → 0.11 → 0.13` chain, which also retires the "pre-0.10 project is one command" mismatch. | `README.md:57-68,187-196` · `addons/reactive_ui_toolkit/README.md:76-94` |
| **L-2** | FIXED — path rules are now anchored by zero-width lookbehind: `(?:(?<=res://)|(?<=\./)|(?<![A-Za-z0-9_:/.]))addons/…\b`. Verified against the audit's own adversarial file: `user://addons/reactive_ui/save.dat` and a GitHub URL are left alone, while `res://`, `../`, bare-quoted and `project.godot` forms all still migrate and `reactive_ui_widgets` stays untouched. Idempotent. | `migrate_0_13_0.gd:120-131` |
| **L-3** | FIXED — tripwire scope widened from `res://examples` to `res://`, so `tests/`, `scripts/`, `research/`, root-level `.gd` and `project.godot` are guarded. 274 files scanned, `migrated 0`, exit 0 on the clean tree. `addons/` remains structurally unreachable (`_walk` skips it) — documented in the file header. | `tests/guitkx_rename_migrate.gd:2-16,19` |
| **L-4** | FIXED (latent gap closed) — class renames now apply to `.tscn`/`.tres`, but *only* inside the `script_class="…"` attribute, so no arbitrary scene string content is at risk. Verified with a `.tres` carrying `script_class="RUIStyleSheet"` → `"RuitkStyleSheet"`; a packed scene with no such attribute is unaffected. | `migrate_0_13_0.gd:133-144,180-183` |
| **L-5** | FIXED — title and opening rationale rebranded to match the body below the `---`. | `CLA.md:1,3` |
| **L-6** | FIXED — `build/ReactiveUI-Gadot.exe` → `build/ruitk-godot.exe` (repo slug; no spaces/em-dash in a filename). | `export_presets.cfg:14` |
| **L-7** | FIXED by rephrasing, not re-tokening — `— Godot — documentation site` → `— Godot: documentation site`; the skill description likewise; the skill's H1 recast as "Writing a component for Reactive UI Toolkit — Godot". Swept the tree for other `Godot —` collisions: the two remaining hits are ordinary prose, not product-name collisions. | `RuitkGodotDocs~/README.md:1` · `.claude/skills/new-component/SKILL.md:3,6` |
| **L-8** | FIXED — `publish.yml`'s `release-addon` verify step now mirrors `test.yml`: `contract_dump.gd -- --check` inserted after the build (same position as `test.yml`) and the three codemod tripwires appended, with a comment recording the parity rule. `release-editor-addon`'s deliberately narrower editor-only battery left alone (not in scope, and intentional). | `.github/workflows/publish.yml:118-141` |

### Not findings, fixed anyway (2 — flagged for supervisor judgment)

- **Shipped addon README's licence bullet was still `ReactiveUI Community License 1.0` + `Credit "Made with ReactiveUI"`.** Same defect class as H-4 (a stale binding credit line) on the same shipped file as H-5, so it was corrected to 1.1 + "Made with Reactive UI Toolkit". `addons/reactive_ui_toolkit/README.md:13`
- **`dev/` added to the addon README's "What's in the box".** Consequence of H-1: the folder now ships through both channels, so the contents list should name it. `addons/reactive_ui_toolkit/README.md:83-85`

### Verification run

`corpus-hash --check` unchanged (`917dd8cd…`) · `changelog.mjs verify` green (4/4) · rename tripwire
274 files / `migrated 0` / exit 0 · codemod idempotency on two adversarial projects (`migrated 0`
on the second pass of each) · `git archive` carries `dev/` · `guitkx_editor_test` 402/402 (this is
the suite that enforces the root↔addon CHANGELOG byte-mirror) · docs `npm run lint` + `npm run
build` clean · root and addon `CHANGELOG.md` md5-identical.

### Deliberately NOT done

- Nothing committed or pushed, per instruction.
- `plans/`, frozen changelog HISTORY bodies, marketplace identity/display fields, and
  `LICENSE` itself were not touched.
- The 0.10/0.11 tripwires keep their `res://examples` scope — only the 0.13 tripwire was widened,
  as ruled.
- The codemod still does **not** rewrite `ProjectSettings.get_setting("reactive_ui_editor/…")`
  string literals in user `.gd`/`.guitkx` code. Scope was ruled to `project.godot` handling, and a
  bare-string rule there is a false-positive risk with no verified failing case.
