---
name: release-process
description: The ReactiveUI-Godot release runbook — version bumps, the two-lane changelog system (hand-written library lane vs script-generated tooling lane), Discord notes, verification gates, and the merge→fast-forward→Publish flow. Use when preparing, staging, or publishing a release of any artifact in this repo.
---

# Release process (ReactiveUI-Godot)

Everything a release needs, in order. The repo holds four independently-versioned
deliverables; a release touches only the ones whose shipped code changed — check with
`git diff origin/master --stat` against `addons/reactive_ui/`, `addons/reactive_ui_editor/`,
and `ide-extensions/` before deciding what bumps.

## 0. Versioning policy

**Patch by default** (`x.y.Z` — bump only Z). Minor for genuinely additive milestones,
major/0.x-minor only for breaking changes. Behavior-invisible changes to shipped code
(perf, refactors) still get a patch bump + changelog line — shipped code never changes
silently.

| Artifact | Version lives in |
|---|---|
| Runtime addon (`reactive_ui`) | `addons/reactive_ui/plugin.cfg` → `version=` |
| Editor addon (`reactive_ui_editor`) | `addons/reactive_ui_editor/plugin.cfg` → `version=` |
| VS Code extension | `ide-extensions/vscode/package.json` |
| lsp-server (bundled into both extensions) | `ide-extensions/lsp-server/package.json` |
| VS2022 extension | `ide-extensions/visual-studio/GuitkxVsix/source.extension.vsixmanifest` (`Version="…"` — keep it equal to the lsp-server version) |

The two IDE extensions + lsp-server almost always bump together (they ship the same
server). Any change under `ide-extensions/lsp-server/src/` means BOTH extensions bump,
even if their client code is untouched — repackaging is how server fixes reach users.

## 1. Changelogs — two lanes, two enforcement mechanisms

### Lane A — the runtime library (hand-written, mirrored)

1. Write the new `## [X.Y.Z] — YYYY-MM-DD` section at the top of **root `CHANGELOG.md`**,
   keep-a-changelog style (`### Added` / `### Changed` / `### Fixed`, intro line first).
2. Mirror it: `cp CHANGELOG.md addons/reactive_ui/CHANGELOG.md` — the copies must be
   **byte-identical** (a tripwire in `tests/guitkx_editor_test.gd` enforces this; run it).
3. Examples/demos are NOT part of the addon package — root-changelog entries cover the
   addon surface (core, guitkx compiler, style, router…), not `examples/`.

### Lane B — the tooling family (script-generated from one json)

`ide-extensions/changelog.json` is the single source for **vscode, vs2022, AND the Godot
editor addon** (since editor 0.6.3). The committed `CHANGELOG.md` files are *generated
build products with a drift guard* — they are NOT publish-time artifacts. The flow is
always add → extract → commit together:

```bash
# 1. Write the message to a UTF-8 file first (NEVER inline for text with em-dashes/quotes:
#    PowerShell/cmd transcode argv through the code page and corrupt it; the script refuses mojibake)
node ide-extensions/scripts/changelog.mjs add --scope shared \
  --message-file /path/to/msg.txt --vscode 0.8.9 --vs2022 0.8.9 --date YYYY-MM-DD
node ide-extensions/scripts/changelog.mjs add --scope editor \
  --message-file /path/to/ed.txt --editor 0.6.4 --date YYYY-MM-DD

# 2. Regenerate EVERY target the entries name — this is the step that gets forgotten
node ide-extensions/scripts/changelog.mjs extract --ide vscode --out ide-extensions/vscode/CHANGELOG.md
node ide-extensions/scripts/changelog.mjs extract --ide vs2022 --out ide-extensions/visual-studio/CHANGELOG.md
node ide-extensions/scripts/changelog.mjs extract --ide editor --out addons/reactive_ui_editor/CHANGELOG.md

# 3. Gate locally before pushing — the changelog-sync CI job runs exactly this
node ide-extensions/scripts/changelog.mjs verify
```

Semantics: `--scope shared` messages land in every target the entry lists a version for;
`--scope vscode|vs2022|editor` messages land only in that target's file. Same
scope+versions+date accumulate into one entry (multiple messages → multiple bullets).
The editor addon's file has a **cutover marker** — its pre-0.6.3 history below the marker
is frozen verbatim (extract/verify re-emit it untouched); never move or edit the marker.

### Marketplace listing surfaces (what extension users SEE — know before touching)

Every marketplace-visible string has exactly one source; edit the source, never the output:

| Surface | VS Code | VS2022 |
|---|---|---|
| List/page title | `ide-extensions/vscode/package.json` → `displayName` | `GuitkxVsix/source.extension.vsixmanifest` → `<DisplayName>` |
| Short description | package.json `description` | vsixmanifest `<Description>` |
| Page body | `ide-extensions/vscode/README.md` — GENERATED + COMMITTED at edit time from `vscode/readme-template.md` by `changelog.mjs extract-overview`; packaged into every platform .vsix and also the Open VSX page | `GuitkxVsix/overview.md` — generated at publish time from `overview-template.md` by `changelog.mjs extract-overview` (publish.yml step) |
| Changelog tab/section | appended into README.md by extract-overview (embedded inline, not a separate CHANGELOG.md tab) | appended into overview.md by extract-overview |

- Naming scheme (family-wide, 2026-07-16): display name = `GUITKX (Godot - VS Code)` /
  `GUITKX (Godot - VS2022)`; body H1 = `Reactive UI Toolkit — Godot - <IDE> (GUITKX)`; body order =
  Title → Description → Features → Requirements → Changelog. Execution details:
  `plans/archive/EXTENSION_LISTING_PLAN.md`.
- A LISTING-ONLY change still bumps both extensions (patch) + a Lane B entry — shipped bytes change.
- Where a body file is generated (`vscode/README.md` from `readme-template.md`; VS2022's
  `overview.md` from `overview-template.md`): edit the TEMPLATE, re-run extract-overview, commit
  template + output together (vscode's is drift-gated by `changelog.mjs verify`'s
  `OVERVIEW_TARGETS` check — vs2022's overview.md is publish-time-only and never committed, so
  it isn't).

### Discord (community note)

Add an entry at the top of `plans/DISCORD_CHANGELOG.md`, matching the existing entries'
shape: `## [X.Y.Z] - date`, bold-lead paragraphs, an `Update to **Reactive UI Toolkit X.Y.Z** …`
line, and a `**Tooling:** …` footer for the extension/editor versions. **Hard limit
≤ 2000 characters** per entry (Discord message cap) — count it:
`awk '/^---$/{exit} {n+=length($0)+1} END{print n}' plans/DISCORD_CHANGELOG.md`.
It is not posted automatically — paste it into Discord after publishing.

## 2. Verification gates before committing

- `node ide-extensions/scripts/changelog.mjs verify` — all generated changelogs in sync.
- `godot --headless --path . --script res://tests/guitkx_editor_test.gd` — includes the
  root↔addon changelog byte-identity tripwire.
- The affected code suites (per dev-process; typically already green before release prep).
- Sanity: the editor release body = the top `## [` section of its CHANGELOG.md
  (`awk '/^## \[/{n++} n==1' addons/reactive_ui_editor/CHANGELOG.md`) — publish.yml
  extracts exactly that, so eyeball it once.

## 3. Commit, merge, fast-forward

1. Commit the release prep (bumps + changelogs together) on the feature branch; push.
   Message style: `release: reactive_ui X.Y.Z, editor A.B.C, guitkx extensions D.E.F -- changelogs + version bumps`.
2. PR into `dev` (campaigns are 1 branch / 1 PR; the PR title becomes the squash title).
   Wait for green — the required checks include changelog-sync.
3. After merge, fast-forward master (master is release-only):
   ```bash
   git fetch origin
   git push origin origin/dev:master
   ```

## 4. Publish

- **The Publish button**: `.github/workflows/publish.yml` via workflow_dispatch (user
  runs it — never trigger it yourself). Every job is idempotent and **version-gated by
  tag** (`v*`, `editor-v*`, `vscode-v*`, `vs2022-v*`): a job skips when its tag already
  exists, so un-bumped artifacts simply don't release. Publish regenerates the vscode
  CHANGELOG and the vs2022 overview from changelog.json as a belt — the committed files
  are already verified in sync.
- **Classic Asset Library**: auto-posts version edits via the assetlib jobs (armed by the
  `ASSETLIB_ASSET_ID` / `ASSETLIB_EDITOR_ASSET_ID` repo variables + secrets).
- **New Godot Asset Store**: manual — add the new version in the publisher dashboard
  (no API yet).
- **Discord**: paste the prepared entry.

## Scar tissue (why these steps exist)

- **"extract + commit" is mandatory, not optional**: changelog.json once fell 14 versions
  behind the published changelogs; the changelog-sync CI job exists because of it, and it
  WILL fail your PR if you `add` without `extract`-ing every named target.
- **`--message-file`, not `--message`**, for anything beyond plain ASCII — argv
  transcoding corrupts em-dashes/curly quotes and PowerShell strips embedded `"`.
- **The library mirror is byte-identical, not approximately identical** — regenerate with
  `cp`, never by re-typing.
- **A perf-only change still ships** (new bytes in the artifact) — bump + one changelog
  line, e.g. "tokenizes ~17% faster, output hash-identical".
- Release bodies parse the changelog's **top `## [` section** — keep that heading shape.
