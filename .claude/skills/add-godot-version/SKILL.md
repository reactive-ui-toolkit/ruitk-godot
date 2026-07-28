---
name: add-godot-version
description: Runbook for bringing the library up to a newly released Godot version — dump + diff ClassDB between the old and new binaries, classify every added/removed Control class/property/signal, apply the AUTOMATION.md checklist (bundled LSP dump, curated schema, docs versionManifest, CI + verified-on stamps), and verify the full matrix. Use when the user says a new Godot version is out or asks to support/verify one.
---

# Add a Godot version

The library is open-vocabulary (new classes/props/signals work at runtime with zero code), so this
runbook is about the CURATED surfaces: the bundled LSP completion data, the hand-picked schema, the
docs site, and the version stamps. The checklist of record is **`AUTOMATION.md`** (repo root) —
this skill is the process for executing it.

## 1. Discovery — diff the engine, don't guess

1. Locate both Godot binaries (the currently-verified one and the new one). If the new one isn't
   installed, stop and ask the user for its path.
2. Dump ClassDB under each (the script ships in the addon):
   ```bash
   <old-godot> --headless --path . --script res://addons/reactive_ui_toolkit/dev/classdb_dump.gd -- res://classdb-old.json
   <new-godot> --headless --path . --script res://addons/reactive_ui_toolkit/dev/classdb_dump.gd -- res://classdb-new.json
   ```
3. Diff: `node scripts/godot-api-diff.mjs classdb-old.json classdb-new.json --json diff-report.json`.
   Delete the three temp files when done (they are not committed).

## 2. Classification — for each diff line, decide the tier

- **Added class** → works already as a tag. Curate (schema + `V.*` factory + docs page) only if it
  is a mainstream UI Control a user would reach for; propose the curation list to the user before
  implementing. Always record it in `plans/WIDGET_INVENTORY.md`.
- **Added property/signal** → zero code; picked up by the bundled-dump regen. Style-relevant
  additions get docs Styling-catalog entries.
- **Removed/renamed API** → engine-breaking; follow the 0.9.0 naming-loyalty precedent
  (`renamed_tags` in `vocabulary.json` for loud rename hints) and sweep examples/docs.

## 3. Implementation — AUTOMATION.md "The Checklist", in order

Work top to bottom; the both-copies rules matter (vocabulary.json ×2 byte-identical + regenerated
`guitkx_vocabulary.gen.gd`; `guitkx-schema.json` ×2). Version stamps: CI `GODOT_VERSION`, root
README "verified on", addon README "tested on", CLAUDE.md, docs `SUPPORTED_VERSIONS`.

## 4. Verification — the full matrix, on the NEW Godot

Run every suite in `CLAUDE.md` → Commands with the new binary (build → class-cache scan → suites →
contract `--check`), plus the TS gates (`lsp-server` tests + smoke, `corpus-hash.mjs --check` —
which must NOT drift on an engine bump) and the docs build + lint. A regression on the new engine
that passes on the old one is a finding to fix, not to skip.

## 5. Ship

House rules apply (dev-process skill): feature branch, per-milestone commits, changelog entries
for every touched artifact (release-process skill), version bumps patch-by-default. Do not commit
or push without the user's go.
