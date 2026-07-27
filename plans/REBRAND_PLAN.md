# Rebrand plan — "Reactive UI Toolkit" umbrella + org migration (Godot repo leg)

**Status: PLAN — awaiting Phase-0 ratification (owner).** Sequencing decision (owner,
2026-07-27): the C# leg is ON HOLD; the family rebrands and moves to the GitHub org FIRST,
then work continues under the new identity.

**EXECUTOR CONTRACT (read first — this plan is written for mechanical execution):**
- Every step names an exact file, the exact OLD string, the exact NEW string, and a
  verification command. Execute steps IN ORDER within a phase.
- If a step's OLD string is not found EXACTLY as written: **STOP that step and report** — do
  not improvise, do not fuzzy-match, do not substitute a "close enough" string.
- NEVER run a repo-wide find/replace. Only per-file, per-string edits as instructed. The
  Tier-2 "DO NOT TOUCH" list (§3) exists because blind replacement breaks the product.
- After each group, run that group's verification. After Phase 3, run the FULL gate battery
  (§6.G). Nothing is pushed except to a feature branch; the owner PRs (house branch flow).
- All console/browser steps are marked **[OWNER]** — the executor lists them, never attempts
  them.

---

## 0. Scope

Covers end-to-end: GitHub org creation, repo transfer + rename, and the COMPLETE in-repo
rename of the Godot (GDScript) leg — every file, folder, extension listing, docs page, log
string, changelog surface, license text, template, and workflow. Unity / Unreal /
gdscript-analyzer get sibling plans (§8) — this document is the Godot repo's leg plus all
org-level operations.

Found during research and folded in as a **bugfix riding this wave**: both AssetLib
auto-post templates still declare `"cost": "MIT"` — never updated in the Community-License
relicense. Fixed in §6.B12.

## 1. Name Registry (single source of truth for every replacement)

The executor uses ONLY these mappings. TBD rows block execution until the owner ratifies
Phase 0 (§2).

| # | Context | OLD (exact) | NEW (exact) |
|---|---|---|---|
| N1 | Umbrella brand | — | `Reactive UI Toolkit` |
| N2 | GitHub org | `yanivkalfa` (as repo owner) | `reactive-ui-toolkit` |
| N3 | This repo's name | `ReactiveUI-Godot` | **TBD-R1** (rec: `godot`) |
| N4 | Repo URL root | `https://github.com/yanivkalfa/ReactiveUI-Godot` | `https://github.com/reactive-ui-toolkit/<N3>` |
| N5 | Library display name | `Reactive UI` / `ReactiveUI for Godot` / `Reactive UI (React for Godot)` | **TBD-R2** (rec: `Reactive UI Toolkit — Godot`) |
| N6 | Editor addon display name | `Reactive UI Editor` | **TBD-R2** (rec: `Reactive UI Toolkit — Godot Editor`) |
| N7 | License product name | `ReactiveUI for Godot` | **TBD-R3** (rec: `Reactive UI Toolkit — Godot`) |
| N8 | License credit line | `Made with ReactiveUI` | **TBD-R4** (rec: keep as-is — see R4) |
| N9 | VS Code ext display | `GUITKX (Godot - VS Code)` | **TBD-R5** (rec: `GUITKX (Godot - VS Code) — Reactive UI Toolkit`) |
| N10 | VS2022 ext display | `GUITKX (Godot - VS2022)` | **TBD-R5** (same pattern) |
| N11 | Docs site title | `ReactiveUI for Godot — Documentation` | `<N5> — Documentation` |
| N12 | Pages base path | `/ReactiveUI-Godot/` | `/<N3>/` |
| N13 | Author fields | `ReactiveUIToolKit` (plugin.cfg author) | **TBD-R6** (rec: `Reactive UI Toolkit`) |
| N14 | AssetLib runtime listing title | `Reactive UI (React for Godot)` | **TBD-R7** (rec: `<N5> (React-style UI)`) |
| N15 | AssetLib editor listing title | `Reactive UI Editor` | `<N6>` |

**NOT names (identifiers — never touched, §3 Tier 2):** `reactive_ui` folders/paths, `RUI*`
class prefixes, `.guitkx`, `GUITKX####` diagnostic codes, marketplace IDs/publishers
(`ReactiveUITK`, `GuitkxVsix.ReactiveUITK`, `guitkx`), npm-internal package names
(`guitkx`, `guitkx-language-server`, `reactiveui-godot-docs`), `@gdscript-analyzer/core`,
Discord invite URL.

## 2. Phase 0 — owner ratification (blocks everything) **[OWNER]**

| # | Decision | Options + recommendation |
|---|---|---|
| R1 | Repo names in the org | `godot` / `unity` / `unreal` / `godot-csharp` (rec — short, umbrella does the branding) vs keeping current names moved as-is. Affects N3/N4/N12 and the Pages URL |
| R2 | Product display names | Ratify N5/N6 exact strings |
| R3 | License product name | Ratify N7. NOTE: changing LICENSE text = the change ships with the NEXT RELEASE (per-copy license semantics, same rule as the relicense); the legal terms are unchanged — only the product-name label and copyright line. Low risk, but it IS a license-file edit |
| R4 | Credit line | `Made with ReactiveUI` — keep (rec: it's short, brand-adjacent, and changing it alters an obligation wording in every LICENSE + the commercial agreement + docs/FAQ) vs update to `Made with Reactive UI Toolkit` |
| R5 | Extension identity strategy | RE-VERIFIED (2026-07-27, microsoft/vscode #92996 + #59918 + publisher-migration writeups): `displayName` = freely mutable, ships with next publish, zero loss. Extension **identifier** (`publisher.name`) and **publisher ID** = HARD immutable — confirmed. Publisher **display name** is editable in the Marketplace manage portal (ID stays in URLs) — verify on login **[OWNER]**. Owner direction: republish if hard-capped → it is, so choose: **(a) display-name-only** (keep `ReactiveUITK`/`guitkx` ids; zero loss; brand carried by display strings) vs **(b) full republish** under a new publisher id (e.g. `reactive-ui-toolkit`): new listings on VS Code Marketplace + Open VSX + VS Marketplace (2 extensions × 3 stores), install counts/ratings reset to zero, old listings manually deprecated (displayName → `[DEPRECATED — use <new>] …` + README pointer; optionally request VS Code's official deprecation-with-migration flagging via a microsoft/vscode issue so the IDE auto-suggests the replacement). Rec: (a) now, (b) only if the owner wants the ids themselves clean — decide here |
| R6 | Author-field string | Ratify N13 |
| R7 | AssetLib listing titles | Ratify N14/N15 |
| R8 | `gdscript-analyzer` repo | **RESOLVED (owner, 2026-07-27): move to the org as-is, no rename.** B15 becomes mandatory: update the download URLs in publish.yml + vscode packaging to the org path (redirects would cover it, but explicit is house style) |
| R9 | Logo/icon refresh | `icon.png` (repo + AssetLib + extension icons) — rebrand now or keep art (rec: keep art, defer visual identity; it's orthogonal and blocks nothing) |
| R10 | Identifier-conversion scope | Owner challenged the Tier-2 freeze ("everything should be converted"). Full analysis in §3a + the complete conversion procedure priced in **Annex B**. Rec: KEEP identifiers — `reactive_ui`/`RUI` literally abbreviate "Reactive UI", which the umbrella retains, so they are ON-brand; converting them is a breaking API + language-grammar change (user components' `-> RUIVNode` is the component-classification token) for zero brand gain. Ratify: keep (rec) vs full conversion (execute Annex B as its own campaign) |

## 3. Inventory census (measured 2026-07-27) + the tier model

| String | Files | Occurrences | Tier |
|---|---|---|---|
| `Reactive UI` (display) | 33 | 111 | Tier 1 — display, per-file edits §6.B |
| `ReactiveUI` (compound: `ReactiveUI for Godot`, `ReactiveUI-Godot`, `ReactiveUIToolKit`, `ReactiveUIGodotDocs~`) | 118 | 352 | MIXED — URL/name occurrences Tier 1; folder `ReactiveUIGodotDocs~` Tier 2-optional (Annex A); Unity-repo references in comments Tier 3 |
| `reactive_ui` (paths, folders, code) | 139 | 612 | **Tier 2 — DO NOT TOUCH** |
| `RUI*` class prefix | 118 .gd files | — | **Tier 2 — DO NOT TOUCH** |
| `yanivkalfa` (URLs) | 27 | 46 | Tier 1 — URL swap §6.A |
| `ReactiveUI-Godot` (URLs/paths) | 33 | 53 | Tier 1 (inside URLs) + N12 base path |
| `ReactiveUITK` (publisher/author ids) | 14 | 24 | MIXED — publisher ids Tier 2 (R5 constraint); author display fields Tier 1 |
| `GUITKX` | 146 | — | **Tier 2 — language/diagnostic brand, unchanged** (display-name suffixes only via N9/N10) |

**Tier definitions:**
- **Tier 1 — brand surfaces (CHANGE):** display names, descriptions, URLs, titles, license
  product labels, listing metadata, workflow release names.
- **Tier 2 — identifiers (KEEP, pending R10):** addon folder names (`addons/reactive_ui`,
  `addons/reactive_ui_editor`, `addons/reactive_ui_analyzer`) and every `res://` path;
  `RUI*` global class names; `.guitkx` extension + `GUITKX####` codes; marketplace
  publisher/extension IDs (hard-immutable, R5); npm-internal names; `@gdscript-analyzer/core`;
  Discord invite. Rationale in §3a; the full-conversion procedure is priced in Annex B.
- **Tier 3 — historical record (NEVER CHANGE except URLs):** CHANGELOG **entry bodies**
  (they describe releases as they shipped — e.g. "Update to **Reactive UI 0.12.1**" stays),
  Discord changelog past entries, MIGRATION-0.10/0.11 doc bodies, plans/archive/**. LIVE
  URLs inside them ARE updated (a link is a functional reference, not history) — §6.A covers
  this explicitly.

### 3a. Why Tier-2 identifiers should NOT convert (the R10 analysis)

The owner asked: "everything should be converted — what am I missing?" Three things, in
descending order of weight:

1. **They already spell the new brand.** `reactive_ui` and the `RUI` prefix are literal
   abbreviations of "Reactive UI" — the exact words the umbrella KEEPS. There is no stale
   brand to scrub; converting trades `reactive_ui` for something like `reactive_ui_toolkit`
   — longer, same meaning. The family already treats short prefixes as native spelling, not
   brand surfaces: Unity's namespaces are `ReactiveUITK.*`, Unreal's are `RUI::`/`FRui`,
   and none of those change in the umbrella rebrand either.
2. **`-> RUIVNode` is grammar, not just a name.** Since ES-modules (E-01), a declaration IS
   a component *because* its return annotation reads `-> RUIVNode`. That token lives in
   EVERY user component file, in the compiler's classifier, in the TS mirrors' classifier,
   in the editor tooling, and in the 66 family contract goldens. Renaming it is a breaking
   language-grammar change: a codemod for every user project, a four-repo corpus re-pin,
   and a docs/teaching-example sweep — a full campaign by itself.
3. **Folder renames break updates in place.** AssetLib/store updates ADD files, they don't
   delete: a user updating past a folder rename ends up with BOTH `addons/reactive_ui` and
   the new folder side by side → duplicate global `class_name` registrations → parse errors
   until they hand-delete the old folder. Every existing project needs a manual migration
   step, for zero functional gain.

None of this is impossible — Annex B holds the complete conversion procedure with costs —
it is simply a poor trade. The brand lives in display names, listings, URLs, docs, and
licenses (Tier 1, ALL converted by this plan); the identifiers are the API, and the API
already says Reactive UI.

## 4. Phase 1 — org creation + reservations **[OWNER]**

1. Create GitHub org `reactive-ui-toolkit` (Free plan is sufficient). Owner account =
   org owner. (Already planned per 2026-07-27 decision; if the name is taken, STOP — the
   whole registry shifts.)
2. Org settings: default repo permissions, disable org-wide projects/wiki if unused. Enable
   "Verified" domain later if a family domain is adopted (Unity leg already owns
   `reactiveuitoolkit.info` — candidate umbrella domain, decide in the family wave).
3. Reserve nothing else yet (NuGet prefix reservation belongs to the C# leg's M0, on hold).

## 5. Phase 2 — repo transfer + rename (mechanics)

**What GitHub preserves on transfer (verified behavior):** issues, PRs, releases, tags,
stars, watchers, forks link, Actions history + **repo-level secrets and variables** (the
AssetLib auto-post credentials ride along), deploy keys, webhooks, branch protection AND
rulesets. **Redirects:** git operations and web URLs on the old path redirect permanently —
including through a subsequent rename — until/unless the old name is reused. **Never create
a new repo named `ReactiveUI-Godot` under `yanivkalfa`** (it would sever the redirects).

**What breaks and must be handled:**
- **GitHub Pages URL changes** (no redirect): `yanivkalfa.github.io/ReactiveUI-Godot` →
  `reactive-ui-toolkit.github.io/<N3>`. Handled by §6.C (vite base) + a docs redeploy + the
  URL sweep (§6.A). If anything external points at the old Pages URL, it 404s — owner should
  check Discord pins / store listings for docs links **[OWNER]**.
- Local clones keep working via redirect, but update anyway (§5 step 4).

**Steps:**
1. **[OWNER]** GitHub → repo Settings → Danger Zone → "Transfer ownership" →
   `reactive-ui-toolkit`. Confirm.
2. **[OWNER]** In the org: Settings → rename repo to **N3** (if R1 chose a new name).
3. **[OWNER]** Verify post-transfer: Actions enabled, secrets present
   (`ASSETLIB_*`, marketplace PATs — Settings → Secrets), rulesets intact ("Protect dev +
   master"), Pages source still set (branch `documentations`).
4. Executor: update local remotes (this machine):
   `git remote set-url origin https://github.com/reactive-ui-toolkit/<N3>.git` in the repo
   working copy. The `blackout-backups/` mirrors keep their recorded old URLs — they are
   archives; do NOT modify them.
5. Executor: verify `git fetch origin` works and `git ls-remote` shows master/dev.

## 6. Phase 3 — the in-repo rename (feature branch `rebrand/umbrella`, one commit per group)

Branch from current master. House flow: push the branch; owner PRs into dev → master.

### Group A — repository URL swap (46 occurrences, 27 files)

For EACH file below, replace EVERY occurrence of
`https://github.com/yanivkalfa/ReactiveUI-Godot` with
`https://github.com/reactive-ui-toolkit/<N3>` (and the two non-URL forms noted inline).
Historical-entry URLs ARE included (Tier-3 exception: live links update).

Files (from census — verify count with the command at the end of this group):
1. `.asset-template.json.hb` — 3 URLs (`browse_url`, `issues_url`, `icon_url` — icon_url
   also contains `/ReactiveUI-Godot/` in the raw.githubusercontent path: full line becomes
   `https://raw.githubusercontent.com/reactive-ui-toolkit/<N3>/master/icon.png`)
2. `.asset-template-editor.json.hb` — same 3 fields
3. `.github/ISSUE_TEMPLATE/config.yml`
4. `.github/workflows/publish.yml` — URL occurrences ONLY in this group (display names are
   B14; the `gdscript-analyzer` URL is B15/R8)
5. `CHANGELOG.md` + 13. `addons/reactive_ui/CHANGELOG.md` — edit ROOT, then re-copy the
   mirror: `cp CHANGELOG.md addons/reactive_ui/CHANGELOG.md` (byte-identity gate §6.G)
6. `CLAUDE.md`
7. `LICENSE-COMMERCIAL.md`
8. `README.md`
9. `ReactiveUIGodotDocs~/src/components/TopBar/TopBar.tsx`
10. `ReactiveUIGodotDocs~/src/pages/Licensing/LicensingPage.tsx` — 2 URLs
11. `ReactiveUIGodotDocs~/src/pages/Migrations/MigrationsPage.tsx`
12. `ReactiveUIGodotDocs~/src/pages/Tooling/Editor/EditorPage.tsx`
14. `addons/reactive_ui/README.md` — 2 URLs
15. `addons/reactive_ui_editor/README.md`
16. `addons/reactive_ui_editor/CHANGELOG.md` — GENERATED: do NOT hand-edit; fixed via
    B10-regeneration after `ide-extensions/changelog.json` (17) is edited
17. `ide-extensions/changelog.json` — historical entries' URLs; then regenerate all outputs
    (B10)
18. `ide-extensions/lsp-server/src/server.ts`
19. `ide-extensions/visual-studio/CHANGELOG.md` — GENERATED (B10)
20. `ide-extensions/visual-studio/GuitkxVsix/overview-template.md`
21. `ide-extensions/visual-studio/GuitkxVsix/publishManifest.json` — `"repo"` field
22. `ide-extensions/visual-studio/GuitkxVsix/source.extension.vsixmanifest` — inside
    `<Description>`
23. `ide-extensions/vscode/CHANGELOG.md` — GENERATED (B10)
24. `ide-extensions/vscode/README.md` — GENERATED (B10)
25. `ide-extensions/vscode/package.json` — `"repository"` block + `description`
26. `ide-extensions/vscode/readme-template.md`
27. `plans/HISTORY_RESET_STATE.md` — the restore-procedure URLs (a FUNCTIONAL runbook — the
    push commands must target the live repo; redirects make old URLs work, but update anyway)

Verify:
`git grep -c "yanivkalfa/ReactiveUI-Godot"` → expected: 0 in tracked non-generated files
BEFORE regeneration; 0 everywhere after B10.
`git grep -l "yanivkalfa"` → expected remaining: NONE except (a) `plans/` historical
archives if any mention the account contextually, (b) the gdscript-analyzer URL if R8 =
leave personal (that URL lives in `publish.yml` + is fetched during vscode packaging).

### Group B — display names, licenses, listings (per-file exact edits)

**B1 `addons/reactive_ui/plugin.cfg`:** `name="Reactive UI"` → `name="<N5>"`;
`author="ReactiveUIToolKit"` → `author="<N13>"`. Description: keep (accurate), UNLESS R2
ratifies new wording.
**B2 `addons/reactive_ui_editor/plugin.cfg`:** `name="Reactive UI Editor"` → `name="<N6>"`;
author → `<N13>`; in description, `Depends on the 'Reactive UI' addon` → `Depends on the
'<N5>' addon` (folder path in the same sentence stays `addons/reactive_ui`).
**B3 `README.md`:** H1 `# Reactive UI — Godot (GDScript)` → `# <N5> (GDScript)`; scan body
for `Reactive UI` display occurrences (git grep -n "Reactive UI" README.md) and update each
EXCEPT inside code blocks/paths; the License section's `ReactiveUI Community License` name
stays (it is the license's proper name — R3 covers only the PRODUCT label).
**B4 `addons/reactive_ui/README.md`:** H1 `# Reactive UI (React for Godot)` → `# <N5>`;
body display strings likewise.
**B5 `addons/reactive_ui_editor/README.md`:** H1 `# Reactive UI Editor` → `# <N6>`.
**B6 LICENSE set (4 byte-identical copies — edit ROOT `LICENSE`, then copy):** per R3, all
occurrences of the product label `ReactiveUI for Godot` → `<N7>` — lines 1 (copyright), 10
(Required Notice), 19 (commercial pointer), 106-107 (attribution alternative). If R4 =
change, also `Made with ReactiveUI` → the ratified string (2 spots + the summary paragraph).
Then: `cp LICENSE addons/reactive_ui/LICENSE && cp LICENSE addons/reactive_ui_editor/LICENSE
&& cp LICENSE ide-extensions/vscode/LICENSE && cp LICENSE
ide-extensions/visual-studio/GuitkxVsix/LICENSE.txt` (5 files total, byte-identical).
**B7 `LICENSE-COMMERCIAL.md`:** `ReactiveUI for Godot` → `<N7>` (§header sentence);
credit-line spot per R4; `ReactiveUI Community License` (license proper name) stays.
**B8 `CLA.md`:** `the ReactiveUI family of projects` → `the Reactive UI Toolkit family of
projects`.
**B9 `ide-extensions/vscode/package.json`:** `"displayName": "GUITKX (Godot - VS Code)"` →
`"<N9>"`; `description` — `(ReactiveUI for Godot)` → `(<N5>)` (URL already done in A25).
`"publisher": "ReactiveUITK"` — **DO NOT TOUCH** (R5 constraint). `"name": "guitkx"` — DO
NOT TOUCH.
**B10 Templates + regeneration (order matters):**
   1. `ide-extensions/vscode/readme-template.md` — display strings: H1/brand mentions
      `Reactive UI - Godot` per N5/N9 (grep the file; every display occurrence).
   2. `ide-extensions/visual-studio/GuitkxVsix/overview-template.md` — same treatment.
   3. `ide-extensions/changelog.json` — URLs (A17) only; entry BODIES stay (Tier 3).
   4. Regenerate ALL outputs:
      `node ide-extensions/scripts/changelog.mjs extract --ide vscode --out ide-extensions/vscode/CHANGELOG.md`
      `node ide-extensions/scripts/changelog.mjs extract --ide vs2022 --out ide-extensions/visual-studio/CHANGELOG.md`
      `node ide-extensions/scripts/changelog.mjs extract --ide editor --out addons/reactive_ui_editor/CHANGELOG.md`
      `node ide-extensions/scripts/changelog.mjs extract-overview --ide vscode --template ide-extensions/vscode/readme-template.md --out ide-extensions/vscode/README.md`
      `node ide-extensions/scripts/changelog.mjs verify` → must print all-green.
**B11 `ide-extensions/visual-studio/GuitkxVsix/source.extension.vsixmanifest`:**
`<DisplayName>GUITKX (Godot - VS2022)</DisplayName>` → `<N10>`; Description's
`(ReactiveUI for Godot)` → `(<N5>)`. `Identity Id` and `Publisher` — **DO NOT TOUCH**.
**B12 Asset templates:** the MIT-cost bugfix was **HOTFIXED AHEAD of this wave** (branch
`fix/assetlib-cost-proprietary`, 2026-07-27): `"cost": "Proprietary"` — the exact API value
per godot-asset-library `src/constants.php` (the UI renders it "Proprietary (see LICENSE
file)"). Remaining rename work in BOTH `.asset-template.json.hb` and
`.asset-template-editor.json.hb`:
   - `"title": "Reactive UI (React for Godot)"` → `"<N14>"`; editor template
     `"title": "Reactive UI Editor"` → `"<N15>"`
   - descriptions: `the Reactive UI (React for Godot) addon` → `the <N5> addon` (2 spots in
     the editor template); `REQUIRES the Reactive UI (React for Godot) addon` likewise —
     folder names `reactive_ui`/`reactive_ui_editor`/`reactive_ui_analyzer` in those
     sentences stay EXACTLY as they are.
**B13 Docs site:** `ReactiveUIGodotDocs~/index.html` title →
`<N5> — Documentation`; `TopBar.tsx` — `alt="ReactiveUI for Godot logo"` → `alt="<N5>
logo"`, visible text `ReactiveUI for Godot` → `<N5>` (URL done in A9);
`ReactiveUIGodotDocs~/package.json` `"name"` — DO NOT TOUCH (internal). Sweep remaining
display strings: `grep -rn "ReactiveUI for Godot\|Reactive UI" ReactiveUIGodotDocs~/src
--include="*.tsx" --include="*.ts"` and update DISPLAY occurrences only (teaching-code
samples referencing `RUI*` classes or `res://addons/reactive_ui` stay).
**B14 `.github/workflows/publish.yml`:** release display names — `name: Reactive UI ${{ … }}`
→ `name: <N5> ${{ … }}` and `name: Reactive UI Editor ${{ … }}` → `name: <N6> ${{ … }}`;
the release-body line `_Requires the [Reactive UI](…) addon` → `_Requires the [<N5>](<N4>)
addon`.
**B15 analyzer URLs (R8 RESOLVED — repo moves as-is, no rename):**
`https://github.com/yanivkalfa/gdscript-analyzer/…` →
`https://github.com/reactive-ui-toolkit/gdscript-analyzer/…` in `publish.yml` (line ~244:
the release-download URL) AND wherever vscode packaging fetches it — locate every spot
first: `git grep -n "yanivkalfa/gdscript-analyzer"` and update each. (Redirects would
cover the old URLs; explicit update is house style.) Prereq: the **[OWNER]** transfer of
`gdscript-analyzer` to the org in Phase 2.
**B16 `ide-extensions/lsp-server/package.json`:** description `(ReactiveUI for Godot
markup)` → `(<N5> markup)`. `"name"` — DO NOT TOUCH.
**B17 `CLAUDE.md`:** update the repo-description phrasing (`the Godot sibling of the C#/Unity
ReactiveUIToolKit` → wording per N1/N5 with org URL) — keep all PATHS/commands untouched.
**B18 `examples/demos/gallery.guitkx`:** the gallery header label `text="Reactive UI"` →
`text="<N5>"` (generated `.gd` is gitignored; the build sweep in §6.G revalidates).
**B19 Licensing docs page** (`ReactiveUIGodotDocs~/src/pages/Licensing/LicensingPage.tsx`):
display mentions of the product per N5/N7; the phrase `ReactiveUI Community License` (proper
name) stays; `Made with ReactiveUI` per R4.

### Group C — Pages base path (only if R1 renamed the repo)

`ReactiveUIGodotDocs~/vite.config.ts` line ~111: `base: '/ReactiveUI-Godot/',` →
`base: '/<N3>/',`. Docs redeploy happens via the next Publish run's deploy-docs job
**[OWNER triggers Publish]** or a manual docs build push.

### Group D — version bumps + changelogs (the rename wave is a RELEASE)

All four artifacts ship new bytes (names in manifests/licenses/listings) ⇒ per house policy
each bumps + gets changelog entries. Recommended: MINOR for the runtime (user-visible
identity change) — final numbers decided at execution (next free versions):
1. Bump `addons/reactive_ui/plugin.cfg`, `addons/reactive_ui_editor/plugin.cfg`,
   `ide-extensions/vscode/package.json` + `ide-extensions/lsp-server/package.json` (+ both
   locks via `npm --prefix <dir> install --package-lock-only`), vsixmanifest `Version`.
2. Lane A: new section at top of root `CHANGELOG.md` — announce the umbrella rebrand, org
   move (old links redirect), the AssetLib license-field fix, explicitly state "no code
   changes; no folder, class, or file-extension changes — projects update untouched". Then
   `cp CHANGELOG.md addons/reactive_ui/CHANGELOG.md`.
3. Lane B: `changelog.mjs add --scope shared … --vscode <ver> --vs2022 <ver>` + `--scope
   editor … --editor <ver>` (message files, UTF-8, per the release-process skill) →
   re-extract all four outputs → `verify`.
4. Discord entry in `plans/DISCORD_CHANGELOG.md` (≤2000 chars, count with the awk gate).
5. `plans/HISTORY_RESET_STATE.md` + `plans/BUGS_FOUND.md` + `plans/CSHARP_LEG_PLAN.md`:
   already URL-updated in A; no other edits.

### Group E — internal docs sweep

`git grep -ln "ReactiveUI for Godot\|Reactive UI (React for Godot)" -- plans/ docs 2>/dev/null`
— for each hit OUTSIDE `plans/archive/` (Tier 3), update display strings per registry.
`plans/archive/**` stays byte-frozen.

### Group F — the leftovers audit (expected-remaining list)

After A–E, these greps define DONE:
- `git grep -c "yanivkalfa"` → 0, OR exactly the gdscript-analyzer URLs if R8=stay.
- `git grep -l "ReactiveUI for Godot"` → 0.
- `git grep -l "Reactive UI (React for Godot)"` → 0.
- `git grep -n "Reactive UI"` → remaining occurrences ONLY in: historical CHANGELOG/Discord
  entry bodies, `plans/archive/**`, MIGRATION-0.10/0.11 bodies, and compound Tier-2 strings.
  Each remaining hit must be justifiable by that list; anything else = missed step.
- `git grep -c "reactive_ui"` → UNCHANGED от baseline 612 ± the plugin.cfg description
  tweaks (B2 keeps folder mentions!) — this grep PROVES no identifier was touched.
- `ReactiveUIGodotDocs~` folder name unchanged (Annex A if the owner wants it renamed).

### Group G — full verification battery (all must pass before push)

1. `node ide-extensions/scripts/changelog.mjs verify`
2. Godot battery (binary path per CLAUDE/memory): editor scan → `guitkx_build.gd` (49/0
   expected) → editor scan → `guitkx_test.gd` ALL → `guitkx_editor_test.gd` 402+/0 (includes
   changelog mirror + LICENSE presence tripwires) → `core_test.gd` → `demos_test.gd` 31/0
   (validates B18) → `hmr_test.gd` → `contract_dump.gd -- --check` (66 goldens — proves no
   grammar surface was touched)
3. lsp-server: `npm run build && node --test out/test/*.test.js && node scripts/smoke.js`
4. Docs: `npm run build && npm run lint` in `ReactiveUIGodotDocs~`
5. Push branch `rebrand/umbrella` ONLY. **[OWNER]** PR → dev → checks → merge →
   fast-forward master.

## 7. Phase 4 — consoles + stores **[OWNER]** (after the merge + Publish run)

1. **Publish run** (workflow_dispatch on master): ships the renamed artifacts — releases get
   the new display names; marketplace pages pick up new DisplayNames/READMEs; AssetLib
   auto-post edits ride with the new templates (including the `cost` fix).
2. **Classic AssetLib** (both listings): verify/edit in the dashboard — title (N14/N15),
   description, browse/issues/icon URLs, and the **License field → Proprietary (see LICENSE
   file)** (the researched dropdown value). May trigger moderator re-review — expected.
3. **New Godot Asset Store**: update listing names/URLs in the publisher dashboard.
4. **VS Code Marketplace / Open VSX / VS Marketplace**: no manual action beyond the publish —
   display names ship with the new versions; publisher IDs unchanged by design.
5. **Discord**: post the rename entry; update any pinned links to the new Pages URL.
6. **GitHub org/repo cosmetics**: repo description + website field, org profile README,
   topics.

## 8. Phase 5 — family siblings (each gets its own plan of THIS shape)

| Repo | Key identity surfaces (pre-scouted) | Plan |
|---|---|---|
| `yanivkalfa/ReactiveUIToolKit` (Unity) | UPM name `com.reactiveuitoolkit` (ALREADY umbrella-aligned — keep), repo name → org/<unity>, domain `reactiveuitoolkit.info` (candidate umbrella docs domain), extension ids `UitkxVsix.ReactiveUITK` + publisher (unrenameable), Rider plugin id, Discord changelog, LICENSE.md product label | sibling plan TBD |
| `yanivkalfa/ReactiveUI-Unreal` | repo name → org/<unreal>, `Plugins/ReactiveUI/` folder = Tier 2 (uplugin identity — DO NOT rename), fab-listing template, VERSIONING.md, LICENSE product label, extension ids | sibling plan TBD |
| `yanivkalfa/gdscript-analyzer` | R8 RESOLVED: transfer to the org as-is (no rename, no content changes); URL updates here via B15 | Phase-2 transfer **[OWNER]** |
| Private: `licensing-internal/`, `blackout-backups/` | references to old URLs are archival — leave | none |

Ordering: Godot leg first (this plan), then Unity + Unreal sibling plans generated the same
way (census → registry → per-file steps), then org profile/domain decisions.

## 9. Aftermath

- Update `licensing-internal/BLACKOUT_STATE.md` header with the new repo URL (archive note,
  one line). Memory files updated by the assistant.
- The parked GitHub support ticket: no action (repo transfer preserves it; if support ever
  resumes, the repo reference redirects).
- Old Pages URL: dead by design — checked in Phase 4.5 for dangling references.
- The C# leg plan already assumes the org; when un-held it starts from the new identity.

## 10. Rollback + safety

- Phase 2 is reversible: transfer back to the personal account restores the old URL space
  (redirects then flip). NEVER reuse freed names for anything else.
- Phase 3 is one git branch — revert = don't merge.
- Phase 4 store edits are individually re-editable.
- The ONE irreversible-ish surface: publishing marketplace versions with new display names —
  and display names remain freely editable afterward, so even that is soft.

## Annex B (OPTIONAL — executes ONLY if R10 = full conversion; a separate campaign, not part of the rebrand wave)

The complete identifier-conversion procedure, priced honestly. Do NOT attempt inside the
rename wave — it is a breaking release with its own migration.

**B-1 Folder renames** (`addons/reactive_ui` → new, `addons/reactive_ui_editor` → new;
`addons/reactive_ui_analyzer` implicates the analyzer repo's packaging too):
`git mv` + rewrite all ~612 `res://addons/reactive_ui…` occurrences (mechanical, per-file) +
`plugin.cfg` dependency description + publish.yml packaging paths + AssetLib templates +
docs. **User migration:** store updates do not delete old folders → shipped migration note +
a `dev/` cleanup script ("delete addons/reactive_ui after enabling the new plugin");
duplicate-class parse errors are the failure mode if skipped. Version: MAJOR-feeling minor;
release notes must lead with it.

**B-2 `RUI*` class-prefix rename** (the expensive one): pick new prefix; rename ~118 files'
`class_name` declarations + every reference; **grammar impact:** `-> RUIVNode` is the E-01
component classifier — compiler (`guitkx.gd`), TS mirrors (`declScan.ts`, `virtualDoc.ts`),
editor addon, and the 66 contract goldens all encode it → four-repo family corpus re-pin
required; **user impact:** every component signature in every user project → ship a codemod
(extend `guitkx_migrate.gd` patterns) + compatibility shims for one minor
(`class_name RUIVNode extends <NewName>` stub scripts keep old spellings compiling, with a
deprecation warning); docs/teaching examples sweep (~30 docs pages); vocabulary.json +
schema references. Estimated: a HALF-CAMPAIGN (comparable to the ES-modules deprecation
window mechanics) for zero functional gain. This is why §3a recommends keeping identifiers.

**B-3 npm-internal names** (`guitkx`, `guitkx-language-server`, `reactiveui-godot-docs`):
safe to rename anytime (unpublished) — pure churn; bundle into B-1 if executed.

## Annex A (OPTIONAL, owner opt-in) — renaming the `ReactiveUIGodotDocs~` folder

Not recommended (pure churn), but if desired: new name e.g. `Docs~`. Reference list to
update: `.github/workflows/publish.yml` (4 occurrences: working-directory ×2, cp line,
comment), `CLAUDE.md` (docs commands + table), `README.md` (~line 482 docs bullet),
`.github/workflows/test.yml` (grep first: `grep -n "ReactiveUIGodotDocs" .github/workflows/test.yml`),
`plans/**` mentions (grep), and `git mv ReactiveUIGodotDocs~ <new>`. Verify: docs build +
publish.yml dry-read + `git grep -c "ReactiveUIGodotDocs"` → 0.
