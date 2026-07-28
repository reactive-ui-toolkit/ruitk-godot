---
name: dev-process
description: The house development methodology for ReactiveUI projects (Godot + Unity + analyzer) — research→develop→test→bughunt→fix→commit→repeat, production-grade only, plus the changelog and version-bump rules every change must follow.
---

# Development process & methodology

## The loop

**research → develop → test → bughunt → fix → commit → repeat.**

- **Research first**: read the actual code and docs, reproduce the problem, name the root cause.
  No fix ships on a theory that hasn't been observed.
- **Production-grade, long-term solutions only. Never a patch, never a bandaid.** If the correct
  fix is deeper (shared infrastructure, an emitter, a contract), fix it there — special-casing on
  top of shared machinery is the smell that the fix is at the wrong altitude.
- **Test before handing over**: run the affected suites AND the boot/e2e path (unit suites don't
  execute editor `_enter_tree`; CLIs and generators have their own smoke tests). A change isn't
  done until the checks that would catch its regression exist.
- **Never weaken a lint, test, or CI gate to get green.** If a gate fails, the code is wrong.
- Campaigns run **1 branch, 1 PR**: feature → `dev` (PR, title = squash title), then master is a
  **fast-forward** of dev (`git push origin origin/dev:master`) — master is release-only.
- Git authorship belongs to the user: no `Co-Authored-By`, no commits/pushes beyond what the task
  established.

## Changelogs — every artifact you touched gets one, before release

| Artifact | Changelog | How |
|---|---|---|
| RG runtime addon (`addons/reactive_ui_toolkit`) | `addons/reactive_ui_toolkit/CHANGELOG.md` | Hand-write; it must stay a **byte-identical mirror** of root `CHANGELOG.md` (a test enforces it) |
| RG editor addon (`addons/reactive_ui_toolkit_editor`) | `ide-extensions/changelog.json` (single source, since 0.6.3) | `changelog.mjs add --scope editor --editor X.Y.Z --message-file …` then `extract --ide editor --out addons/reactive_ui_toolkit_editor/CHANGELOG.md` and **commit both** — pre-0.6.3 history is a frozen verbatim tail below the cutover marker |
| VS Code + VS2022 extensions | `ide-extensions/changelog.json` (single source) | `changelog.mjs add --scope <shared\|vscode\|vs2022> --vscode X.Y.Z --vs2022 X.Y.Z --message-file …` then `extract` **each target and commit the regenerated files with the json** — the changelog-sync CI job (`changelog.mjs verify`) fails on drift; never hand-edit a generated `CHANGELOG.md`/`overview.md` |
| gdscript-analyzer crates | per-crate `crates/*/CHANGELOG.md` | release-plz/git-cliff generates from Conventional Commit PR titles — the squash title IS the changelog line |
| Unity ReactiveUIToolKit | root `CHANGELOG.md` (+ per-extension under `ide-extensions~`) | `scripts/changelog.mjs`-assisted, same single-source idea |
| Community | `plans/DISCORD_CHANGELOG.md` | Notable releases get a Discord-formatted entry at the top (≤2000 chars) |

## Version bumps — where versions live

- **Policy: patch by default** (bump the last digit). Minor only for genuinely additive milestones,
  major/0.x-minor only for breaking. On 0.x, `feat` = patch (analyzer repo enforces this via
  release-plz config).
- Bump locations per artifact: RG runtime → `addons/reactive_ui_toolkit/plugin.cfg`; RG editor →
  `addons/reactive_ui_toolkit_editor/plugin.cfg`; VS Code ext → `ide-extensions/vscode/package.json`;
  VS2022 ext → `GuitkxVsix/source.extension.vsixmanifest` (keep it tracking the bundled
  lsp-server version); lsp-server → `ide-extensions/lsp-server/package.json`; analyzer →
  workspace `Cargo.toml` (release-plz PR does it); Unity package → `package.json`.
- **Release mechanics**: RG publishes via the **Publish button** (`publish.yml`,
  workflow_dispatch; every job is idempotent — skips when its `v*`/`editor-v*`/`vscode-v*`/
  `vs2022-v*` tag exists). Analyzer publishes via release-plz Release PR → single `v<ver>` tag →
  napi/wasm/dist/gdext workflows (dep-only or bindings-only changes need a hand-rolled release
  PR — release-plz only sees `crates/**`). Store listings: classic AL auto-posts via the
  assetlib jobs (armed by `ASSETLIB_ASSET_ID` / `ASSETLIB_EDITOR_ASSET_ID` repo variables); the
  new Asset Store is a manual version-add until it has an API.

## Definition of done for any change

1. Root cause named; fix at the right altitude.
2. Tests/suites green, including the e2e/boot path; new regression coverage where feasible.
3. Changelog entry in every touched artifact + version bump staged.
4. Docs updated when behavior/UX changed (README(s), docs site, store descriptions if user-facing).
5. Committed on a feature branch with a clear message; PR into dev; user merges; master fast-forwarded.
