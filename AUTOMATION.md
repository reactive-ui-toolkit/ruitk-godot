# Automation & AI Tooling

How this project keeps up when **Godot itself moves forward** — the sibling of the Unity
toolkit's `AUTOMATION.md` (`ReactiveUIToolKit/AUTOMATION.md`), adapted to Godot's reflection
surface (ClassDB instead of .NET assemblies).

The library is deliberately **open-vocabulary**, so most engine growth needs *zero code*:

| Godot adds… | What happens with no action | What curation adds |
|---|---|---|
| a new `Control` class | it's already a valid tag (`<NewControl>` validates against live ClassDB; lowers via `V.h`) | a curated schema entry (completion/hover), a docs component page |
| a property | props are set **verbatim** — works immediately | LSP completion (bundled dump regen), docs |
| a signal | events are derived live — `onNewSignal` just works | LSP completion (bundled dump regen) |
| a theme / StyleBoxFlat property | style keys are **verbatim** — works immediately | docs Styling catalog entry |

What does NOT update itself: the **bundled ClassDB dump** the VS Code/VS2022 language server
completes from, the **curated schema** (the ~54 hand-picked elements with rich hover docs), the
**docs site**, and the **CI / verified-on version stamps**. That's what the runbook below covers.

## When a New Godot Version is Released

### For AI (Claude Code)

```
/add-godot-version Godot 4.8 has been released
```

The skill (`.claude/skills/add-godot-version/SKILL.md`) walks discovery → classification →
implementation → verification, using the same steps as the human runbook below.

### For Humans

1. **Dump ClassDB under both versions** (each Godot binary must be runnable; the dump script
   ships in the addon):

   ```bash
   <old-godot> --headless --path . --script res://addons/reactive_ui_toolkit/dev/classdb_dump.gd -- res://classdb-old.json
   <new-godot> --headless --path . --script res://addons/reactive_ui_toolkit/dev/classdb_dump.gd -- res://classdb-new.json
   ```

2. **Diff them** — ClassDB reflection, no web scraping:

   ```bash
   node scripts/godot-api-diff.mjs classdb-old.json classdb-new.json --json diff-report.json
   ```

   The report lists every added/removed Control class, property (with enum-hint changes), and
   signal (with the derived `onPascalCase` event name).

3. **Follow the checklist** below for each category the diff surfaced.

## The Checklist

**Always (any new engine version):**

- [ ] Regenerate the bundled LSP ClassDB dump **with the new Godot**:
      `godot --headless --path . --script res://addons/reactive_ui_toolkit/dev/classdb_dump.gd`
      → `ide-extensions/lsp-server/classdb/godot-control.json` (drives VS Code/VS2022 attribute +
      event completion and `GUITKX0109` validation).
- [ ] Bump CI: `GODOT_VERSION` in `.github/workflows/test.yml`.
- [ ] Update the verified-on stamps: root `README.md` ("verified on **X**"),
      `addons/reactive_ui_toolkit/README.md` ("tested on X"), `CLAUDE.md`.
- [ ] Docs site: add the version to `SUPPORTED_VERSIONS` in
      `RuitkGodotDocs~/src/versionManifest.ts`.
- [ ] Run the full verify matrix (`CLAUDE.md` → Commands; all suites + contract + TS + docs).

**Per new Control class (from the diff):**

- [ ] Decide: leave as open-vocabulary (works already), or **curate**. Curating means:
      `vocabulary.json` `host_tags` (BOTH copies: `addons/reactive_ui_toolkit/guitkx/` +
      `ide-extensions/lsp-server/src/`, byte-identical — a test enforces it), regenerate
      `guitkx_vocabulary.gen.gd` (`dev/gen_vocabulary.gd`), the curated schema
      `guitkx-schema.json` (BOTH copies: `addons/reactive_ui_toolkit_editor/data/` +
      `ide-extensions/grammar/`), a `V.<ClassName>` factory in `core/v.gd` (the `v_factories`
      reflection tripwire pins the list), and a docs component page + `ELEMENT_VERSIONS` entry
      with `sinceGodot`.
- [ ] Record it in `plans/WIDGET_INVENTORY.md` (the naming-loyalty ledger of every Control).

**Per new property / signal:** nothing beyond the dump regen (verbatim props / derived events);
add docs entries (`STYLE_PROPERTY_VERSIONS`, Styling catalog) only for style-relevant additions.

**Per REMOVED / renamed API (rare, engine-breaking):**

- [ ] Grep the curated schema, `vocabulary.json`, `v.gd`, examples, and docs for the old name;
      follow the 0.9.0 naming-loyalty precedent (loud rename diagnostics via `renamed_tags`).

**Family guardrail:** the `.guitkx` **grammar** is engine-agnostic and family-frozen — a Godot
version bump must never change scanner/import grammar behavior. The corpus gate
(`node scripts/corpus-hash.mjs --check`, pinned in `plans/family-corpus.hash`) enforces this in CI;
if it drifts during an engine update, the update is wrong, not the hash.

## Folder Layout

| Path | What | Audience |
|------|------|----------|
| `.claude/skills/add-godot-version/SKILL.md` | Claude Code skill — full runbook | AI |
| `addons/reactive_ui_toolkit/dev/classdb_dump.gd` | ClassDB dump script (run per Godot binary) | Both |
| `scripts/godot-api-diff.mjs` | Dump differ (added/removed classes, props, signals) | Both |
| `plans/WIDGET_INVENTORY.md` | The Control-coverage ledger (naming-loyalty audit) | Human |
| `RuitkGodotDocs~/src/versionManifest.ts` | Docs version manifest (single source of truth) | Both |

---

## Documentation Website Versioning

The docs site has a version-aware system driven by
`RuitkGodotDocs~/src/versionManifest.ts` (the same design as the Unity docs site):

- `SUPPORTED_VERSIONS` — the version dropdown; first entry = floor, last = latest.
- `ELEMENT_VERSIONS` / `STYLE_PROPERTY_VERSIONS` / `PAGE_VERSIONS` — `sinceGodot` tags for
  anything added after the floor; untagged = always available. `isAvailableIn()` filters,
  `getVersionBadge()` renders the "4.8+" chips.

When adding a new Godot version to docs: add the `SUPPORTED_VERSIONS` entry, tag any new
elements/style keys/pages with `sinceGodot`, give each new curated element a **full component
page** (usage example, props, events) — not just a table row — and verify with
`cd RuitkGodotDocs~ && npm run build && npm run lint`.
