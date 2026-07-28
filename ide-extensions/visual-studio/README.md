# GUITKX for Visual Studio 2022

VS2022 extension for `.guitkx` (Reactive UI Toolkit — Godot): TextMate colouring via `.pkgdef` +
`ILanguageClient` driving the same shared language server as the VS Code extension
(`ide-extensions/lsp-server`), bundled self-contained with a pinned Node runtime
(`GuitkxVsix/fetch-node.ps1`) so end users need nothing on PATH.

- **Marketplace page**: `GuitkxVsix/overview.md` — **generated** from
  `ide-extensions/changelog.json` by `scripts/changelog.mjs`; don't hand-edit it.
- **Build**: see the *VS2022 extension* section of [../README.md](../README.md)
  (build the lsp-server, bundle it via the vscode `bundle-server.js`, copy into
  `GuitkxVsix/server`, fetch Node, then `msbuild -t:CreateVsixContainer`).
- **Publishing**: automated by `.github/workflows/publish.yml` (`publish-vs2022` job),
  version-gated on the `vs2022-v<version>` tag.

**Status**: **0.10.0**, at feature parity with the VS Code extension (same bundled
`lsp-server`, released in the same window). The parity campaign's record lives in
[`plans/archive/VSCODE_VS2022_PARITY_PLAN.md`](../../plans/archive/VSCODE_VS2022_PARITY_PLAN.md);
the outstanding interactive UI verification pass is tracked in `plans/MASTER_PLAN.md` §1.2.
