# Migrating to 0.13.0 — the Reactive UI Toolkit rename

0.13.0 is the family umbrella rebrand: the library is now **Reactive UI Toolkit — Godot**, one
leg of the [Reactive UI Toolkit](https://github.com/reactive-ui-toolkit) family (Godot, Unity,
Unreal). It is a **complete rename — names only, zero behavior changes**: the addon folders and
the `RUI*` global class prefix convert, and there is **no compatibility window** (a clean
break; one command migrates a whole project). `V` and `Hooks` are unchanged — they are the
family-parity names, identical across all three engines. The `.guitkx` extension, the
`GUITKX####` diagnostic codes, and the `guitkx` tooling names are all unchanged (the language
keeps its name).

## What renamed

| Surface | Old | New |
|---|---|---|
| Runtime addon folder | `addons/reactive_ui` | `addons/reactive_ui_toolkit` |
| Editor addon folder | `addons/reactive_ui_editor` | `addons/reactive_ui_toolkit_editor` |
| Bundled analyzer folder | `addons/reactive_ui_analyzer` | `addons/reactive_ui_toolkit_analyzer` |
| Class prefix (34 classes) | `RUI*` | `Ruitk*` — e.g. `RUIVNode` → `RuitkVNode` |
| Mount surfaces | `ReactiveRoot` / `ReactiveRootNode` | `RuitkRoot` / `RuitkRootNode` |
| Repository | `github.com/yanivkalfa/ReactiveUI-Godot` | `github.com/reactive-ui-toolkit/ruitk-godot` (old URLs redirect) |

The component classifier is now **`-> RuitkVNode`** — every component signature in every
`.guitkx` file changes spelling, which is exactly what the codemod does for you.

## The one command

Update the addons first (install the 0.13.0 runtime + 0.11.0 editor from the store or the
release zips), then:

```bash
godot --headless --path . --script res://addons/reactive_ui_toolkit/dev/migrate_0_13_0.gd
```

Idempotent and re-runnable (a second run reports `migrated 0`). It rewrites, whole-word and
whole-project (skipping `addons/` itself):

- the 36 class renames across `.guitkx` and hand-written `.gd` (`RUIVNode` → `RuitkVNode`,
  `ReactiveRoot.create(...)` → `RuitkRoot.create(...)`, …);
- the addon folder paths across `.gd`, `.guitkx`, `.tscn`, `.tres`, and `project.godot`'s
  `enabled=` plugin list;
- the editor addon's **Project Settings** section in `project.godot`
  (`[reactive_ui_editor]` → `[reactive_ui_toolkit_editor]`). Those toggles — `format_on_save`,
  `diagnostics_enabled`, `highlighting_enabled`, `completion_enabled`, `hover_enabled`,
  `open_guitkx_in_editor` — are persisted project settings that default to ON, so without this
  rewrite anything you had switched OFF would silently come back on. If the new editor plugin
  already wrote a fresh section before you ran the codemod, your old values win and the two
  sections are merged into one.

Commit before running; review the diff after.

## The manual steps (do not skip #1)

1. **Delete the old addon folders.** Store/AssetLib updates ADD files — they never delete: after
   updating you have BOTH `addons/reactive_ui` and `addons/reactive_ui_toolkit` side by side.
   **The symptom is a scan full of UID-duplicate warnings**, one per core file:

   ```
   WARNING: UID duplicate detected between res://addons/reactive_ui_toolkit/core/v.gd
   and res://addons/reactive_ui/core/v.gd.
   ```

   (UIDs are deliberately preserved across the rename so your existing `uid://` references keep
   resolving; the flip side is that a leftover copy collides with every one of them — 39 warnings
   in a stock install.) Note that you will **not** get an error for the handful of class names
   the two copies really do share (`V`, `Hooks`, the `Guitkx*` set — the `RUI*` and `Ruitk*` sets
   are disjoint by construction): Godot resolves that silently, and the new addon wins. So a
   clean-looking Errors dock is *not* evidence that you finished this step — check that the
   folders are gone. Delete the old `addons/reactive_ui`, `addons/reactive_ui_editor`, and
   `addons/reactive_ui_analyzer` folders by hand (the zips/store now ship only the new names).
2. **Re-enable the plugins if they got disabled.** The plugin identity is its `plugin.cfg`
   path, which changed — check *Project → Project Settings → Plugins* for
   **Reactive UI Toolkit — Godot** (and the Editor addon if you use it). The codemod rewrites
   `project.godot`'s `enabled=` list, so usually this is already done — verify once.
3. **Rebuild the generated `.gd` outputs.** The compiler now emits `-> RuitkVNode` (and the
   editor addon recompiles on focus-in), so re-save your `.guitkx` files or run your project's
   build sweep once; generated `.gd` are derived files, so a full rebuild is always safe.

## The full class table (36 renames)

`RUIGuitkxCodegen→RuitkGuitkxCodegen` · `RUIGuitkxFormatter→RuitkGuitkxFormatter` ·
`RUIGuitkxResolve→RuitkGuitkxResolve` · `RUIGuitkxMigrate→RuitkGuitkxMigrate` ·
`RUIGuitkxMarkup→RuitkGuitkxMarkup` · `RUIGuitkxJsxScan→RuitkGuitkxJsxScan` ·
`RUIGuitkxLexer→RuitkGuitkxLexer` · `RUIGuitkxConfig→RuitkGuitkxConfig` ·
`RUIGuitkxDiag→RuitkGuitkxDiag` · `RUIGuitkx→RuitkGuitkx` ·
`RUIRouterLocation→RuitkRouterLocation` · `RUIRouterPath→RuitkRouterPath` ·
`RUIRouteMatcher→RuitkRouteMatcher` · `RUIRouteRanker→RuitkRouteRanker` ·
`RUIRouteMatch→RuitkRouteMatch` · `RUIRouter→RuitkRouter` ·
`RUIStyleSheet→RuitkStyleSheet` · `RUIStyle→RuitkStyle` · `RUISignals→RuitkSignals` ·
`RUISignal→RuitkSignal` · `RUIComponentState→RuitkComponentState` ·
`RUIEditorSettings→RuitkEditorSettings` · `RUIEditorDeps→RuitkEditorDeps` ·
`RUIConfig→RuitkConfig` · `RUIContext→RuitkContext` · `RUIDiagnostics→RuitkDiagnostics` ·
`RUIFiber→RuitkFiber` · `RUIHistory→RuitkHistory` · `RUIHmr→RuitkHmr` · `RUIHost→RuitkHost` ·
`RUIMedia→RuitkMedia` · `RUIReconciler→RuitkReconciler` · `RUISuspense→RuitkSuspense` ·
`RUIVNode→RuitkVNode` · `ReactiveRootNode→RuitkRootNode` · `ReactiveRoot→RuitkRoot`

## The one licence change that binds you: the credit line

The bundled licence is retitled **Reactive UI Toolkit Community License 1.1**. Its terms are
unchanged with a single exception — the **Attribution** clause moved with the product name. Where
1.0 required the line `"Made with ReactiveUI"`, 1.1 requires:

> "Made with Reactive UI Toolkit" (or "Reactive UI Toolkit — Godot")

in your product's credits, about screen, or accompanying documentation. If you ship a product
whose credits already read "Made with ReactiveUI", **update that string** when you upgrade — it no
longer satisfies the clause. Nothing else about the licence changed: same revenue threshold, same
free tier, same commercial terms.

## Unchanged, deliberately

- **`V` and `Hooks`** — the authoring surface stays byte-identical across the family.
- **`.guitkx`**, the **`GUITKX####`** diagnostic codes, and the `guitkx` tool/package names —
  the language brand is not part of this rename.
- The IDE extension identities (`guitkx`, publisher `ReactiveUITK`) — only the content under
  them updated.
- Every previously released version keeps the license and names it shipped with.
