# GUITKX IDE tooling

Editor support for `.guitkx` — the JSX-like markup of **Reactive UI Toolkit — Godot**. Three layers, one
shared language server:

```
grammar/        TextMate grammar (guitkx.tmLanguage.json) + schema (guitkx-schema.json)
lsp-server/     TypeScript language server (stdio). Markup intelligence + headless embedded GDScript
vscode/         VS Code extension (grammar + language config + LSP client)
visual-studio/  VS2022 extension (TextMate grammar via .pkgdef + ILanguageClient -> same LSP server)
```

## How it works

`.guitkx` is two languages in one file: JSX-like **markup** and embedded **GDScript** (setup,
`{expr}`, `@if`/`@for` conditions). The tooling splits them:

- **Highlighting** — a TextMate grammar (`grammar/guitkx.tmLanguage.json`), self-contained
  (hand-rolled GDScript leaf rules, no dependency on the godot-tools grammar). Used by both VS Code
  and VS2022 (VS never drives coloring over LSP, so the grammar is required there too).
- **Markup intelligence** (tag / attribute / directive completion + hover) — answered locally by the
  language server from the schema (`grammar/guitkx-schema.json`, embedded in `lsp-server/src/schema.ts`).
- **Import intelligence (0.10.0, full ES surface 0.11.0)** — `import { … } from "…"` / `export`
  are first-class syntax, including `import { remote as local }` renames, `import * as X`
  namespaces, default imports, `export default`, and `export { … }` lists;
  go-to-definition works **through** an import (F12 on a specifier opens the target file, on an
  imported name jumps to its declaration — `./ ../ ~/` resolved exactly like the compiler,
  including the `guitkx.config.json` `"root"` key); imported names resolve during embedded analysis
  (no false "undefined identifier" squiggles); the workspace index covers every declaration of a
  multi-declaration file; the outline badges `export`ed declarations; and the compiler's
  `GUITKX2300`–`GUITKX2309` import diagnostics (plus the 0.11.0 `GUITKX2320`–`GUITKX2327`
  export family) surface from the `.diags` sidecar. Cross-file resolution is strict since
  0.10.0 — the shipped codemod migrates older projects in one command.
- **Embedded-GDScript intelligence** (completion/hover/go-to-definition inside `{expr}`/setup/conditions)
  — the server builds a synthetic `.gd` **virtual document** with a length-preserving **source map**
  (Volar's technique, hand-rolled), then analyzes it **in-process** with
  [`@gdscript-analyzer/core`](https://www.npmjs.com/package/@gdscript-analyzer/core) — a headless
  GDScript static analyzer ("Roslyn for Godot") — and maps the result back. **No running Godot editor
  and no TCP connection are required**, so it works fully offline; markup features work regardless.
- **Plain-`.gd` language service** (`guitkx.enableGdscriptAnalysis`, default on) — the same in-process
  analyzer serves ordinary GDScript files too: diagnostics, completion, hover, navigation,
  project-wide rename, formatting, semantic highlighting, inlay hints, code actions, and document
  symbols. Coexists with godot-tools (disable one side's `.gd` diagnostics to avoid duplicates).

The same language features also exist **natively inside Godot**: the `reactive_ui_editor` addon
(`addons/reactive_ui_editor`, outside this folder) is a full in-Godot `.guitkx` editor sharing the
compiler/formatter/diagnostic codes, with the analyzer bundled as a GDExtension since editor 0.6.1.

The language server is **TypeScript** (not C#): the embedded language is GDScript and the analyzer
ships as an npm package (a napi native addon), so VS Code (the primary Godot audience) gets a
zero-runtime Node server. VS2022 drives the same server over stdio.

## Formatter configuration (`guitkx.config.json`)

Canonical `.guitkx` formatting is **2-space indentation** (Unity-exact; the compiler's reindent is
depth-based, so tab-indented sources still compile). To override the formatter, drop a
`guitkx.config.json` at or above the file being formatted (Prettier-style walk-up — the first one
found, walking up to the filesystem root, wins):

```json
{
  "formatter": {
    "printWidth": 100,
    "indentStyle": "space",
    "indentSize": 2,
    "singleAttributePerLine": false,
    "insertSpaceBeforeSelfClose": true
  }
}
```

| Key | Default | Meaning |
|---|---|---|
| `printWidth` | `100` | Soft column limit; a tag's attribute list wraps when the single line would exceed it. |
| `indentStyle` | `"space"` | `"space"` or `"tab"`. The 2-space default matches the Unity sibling and the shipped samples. |
| `indentSize` | `2` | Spaces per level when `indentStyle` is `"space"` (ignored for tabs). |
| `singleAttributePerLine` | `false` | Force every attribute onto its own line. |
| `insertSpaceBeforeSelfClose` | `true` | Emit `<Foo />` (space before `/>`) vs `<Foo/>`. |

The analogue of ReactiveUIToolKit's `uitkx.config.json`. Unknown keys are ignored; a malformed file
falls back to the defaults. (No config file is needed — the defaults above apply when none is found.)

## Build & run

```bash
# language server
cd lsp-server && npm install && npm run build && node --test out/test/*.test.js && node scripts/smoke.js

# VS Code extension (dev: F5 in VS Code, or package a .vsix)
cd ../vscode && npm install && npm run build
node scripts/bundle-server.js          # bundle the server (+ this machine's analyzer .node) into ./server
npx --yes @vscode/vsce package         # -> guitkx.vsix ; also publishable to Open VSX via ovsx
```

`@vscode/vsce` / `ovsx` are NOT project dependencies (they're publishing tools that pull in a large
Azure/MSAL tree) — the scripts invoke them via `npx`, so a contributor's `npm install` stays small.

**Cross-platform packaging.** The bundled language server is a native napi addon (`@gdscript-analyzer/core`),
so a `.vsix` is **platform-specific**. The local `bundle-server.js` above bundles only the builder's own
`.node` (fine for F5/dev). The release CI (`publish.yml` → `publish-vscode`) instead runs a matrix:
each leg installs the target's `@gdscript-analyzer/core-<triple>` binary, runs
`node scripts/bundle-server.js --target <vsce-target>` (bundling only that platform's addon), and
`vsce package --target <vsce-target>` → one platform-specific `.vsix` per platform
(win32-x64, win32-arm64, linux-x64, linux-arm64, darwin-x64, darwin-arm64 — the triples the analyzer
currently publishes; alpine/musl join as the analyzer's napi matrix grows).

**VS2022 extension** (needs VS2022 + the "Visual Studio extension development" workload):

```powershell
cd lsp-server; npm install; npm run build; cd ..\vscode; npm install; node scripts/bundle-server.js
Copy-Item -Recurse -Force vscode\server visual-studio\GuitkxVsix\server
powershell -ExecutionPolicy Bypass -File visual-studio\GuitkxVsix\fetch-node.ps1   # bundles node.exe (~80 MB)
# then build the VSIX in VS2022 (or msbuild GuitkxVsix.csproj -t:CreateVsixContainer -p:Configuration=Release)
```

The VS2022 extension is **self-contained**: `fetch-node.ps1` drops a pinned Windows Node runtime into
`server\node.exe`, and `GuitkxLanguageClient` launches `server\node.exe server.js` — so **end users do
NOT need Node on PATH** (it falls back to a PATH `node` only if the bundle is somehow missing). This is
why the VS2022 `.vsix` is ~80 MB. (VS Code needs no bundled Node — it runs the server in its own host.)

Embedded-GDScript intelligence ({expr}/setup completion, hover, go-to-definition) is analyzed in-process
by **gdscript-analyzer** — no running Godot editor required. Toggle it with the
`guitkx.enableEmbeddedAnalysis` setting (default on).

## Publishing

Releases are automated. The changelog source of truth is **`changelog.json`**; per-extension
`CHANGELOG.md` + the VS2022 `overview.md` are generated from it by `scripts/changelog.mjs`. See
[VERSIONING.md](VERSIONING.md) for the release process and [PUBLISHING.md](PUBLISHING.md) for manual steps.

**Never hand-edit a generated `CHANGELOG.md`.** Add entries with
`node scripts/changelog.mjs add --scope <shared|vscode|vs2022> --message "..." --vscode X.Y.Z [--vs2022 X.Y.Z]`,
then regenerate with `extract` (see below) and commit the result. CI (`changelog-sync` in
`ide-extensions.yml`) runs `node scripts/changelog.mjs verify` on every push/PR and fails if a
committed `CHANGELOG.md` doesn't match what `changelog.json` would generate — this is exactly the
check that would have caught `changelog.json` silently falling 14 releases behind a hand-edited
`vscode/CHANGELOG.md` (0.6.0→0.8.4), which is what actually happened.

- **CI:** `.github/workflows/publish.yml` (`workflow_dispatch`, shared with the runtime addon's own
  release + the docs-site deploy) — its `publish-vscode` / `publish-vs2022` jobs are version-gated per
  extension (skip if the `vscode-v*` / `vs2022-v*` tag exists), publish the VS Code extension to the
  **VS Marketplace** + **Open VSX**, and the VS2022 extension via **VsixPublisher**, then tag + upload
  artifacts.
- **Local:** `scripts/publish-extension.ps1` (VS Code) and `scripts/publish-vsix.ps1` (VS2022).

**Secret matrix** (GitHub repo secrets / local `publisher-secrets.json` keys):

| Secret | `publisher-secrets.json` key | Target | How to get it |
|---|---|---|---|
| `VSCE_PAT` | `vscePatToken` | VS Code Marketplace | Azure DevOps PAT, *Marketplace → Manage* scope ([docs](https://aka.ms/vscode-create-publisher)) |
| `OVSX_TOKEN` | `ovsxToken` | Open VSX | open-vsx.org access token |
| `VS_MARKETPLACE_TOKEN` | `vsMarketplaceToken` | Visual Studio Marketplace | Azure DevOps PAT for the VS Marketplace |

`publisher-secrets.json` is git-ignored — never commit it.

## Status

| Layer | State |
|-------|-------|
| Grammar + schema | Done (valid JSON, adapted from the shipping Unity grammar) |
| Language server — markup completion/hover, structural diagnostics, dangling-reference detection | Done + tested (`npm test`, `smoke.js`) |
| Language server — embedded GDScript (completion/hover/goto/diagnostics) | Done — headless, in-process via `@gdscript-analyzer/core` (no Godot editor, no TCP) |
| VS Code extension | **0.11.0** — grammar, LSP client, format-on-save, sidecar + workspace-index watching, plain-`.gd` analyzer LSP, gdformat integration, ES-module import intelligence |
| VS2022 extension | **0.11.0** — at feature parity with VS Code (same shared `lsp-server`, released in the same window; parity record: [`plans/archive/VSCODE_VS2022_PARITY_PLAN.md`](../plans/archive/VSCODE_VS2022_PARITY_PLAN.md)). Outstanding: the interactive UI verification pass (`plans/MASTER_PLAN.md` §1.2) |
| Publishing + changelogs | Automated via `publish.yml`, but **`changelog.json` had drifted behind the hand-edited `vscode/CHANGELOG.md`** (now reconciled) — keep using `scripts/changelog.mjs add` so future releases don't diverge again |
