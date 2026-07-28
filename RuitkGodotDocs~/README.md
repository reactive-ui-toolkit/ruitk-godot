# Reactive UI Toolkit — Godot: documentation site

A clone of the ReactiveUIToolKit (Unity) docs site, retargeted to the Godot port. React 19 + Vite
(rolldown) + MUI v7 + react-router + prism-react-renderer, deployed to GitHub Pages (SPA).

Status: **WIP scaffold.** The shell (TopBar / Sidebar / CodeBlock / SearchModal / Pager / theme /
routing) is cloned from the Unity site; the content is being ported Unity → Godot.

## Port model (Unity → Godot)
The library is a faithful React-style port, so the docs are too — same structure/concepts, only:
- syntax: C# / `.uitkx`  →  GDScript / `.guitkx`
- host elements: Unity UITK (Button, Label, VisualElement…)  →  Godot `Control` nodes (Button, Label,
  Panel, VBoxContainer…), driven data-first from the schema + `ide-extensions/vscode/classdb/godot-control.json`
- version selector: Unity versions  →  Godot 4.2–4.5
- hooks / router / signals / Suspense / custom-rendering: same API, GDScript snippets from `examples/`

## Remaining retargets (tracked)
- `vite.config.ts`: currently parses the Unity package.json + C# `Props/*.cs`; retarget to read the Godot
  plugin.cfg version + generate prop tables from the schema + ClassDB dump.
- `src/docs.tsx`, `src/pages/**`, `*.example.ts`: port content to Godot.
- `src/versionManifest.ts`: Godot version availability.
- `public/CNAME`: set once the docs domain is decided.

## Dev
`npm install` then `npm run dev`. Build: `npm run build` (emits `dist/`, copies `index.html`→`404.html`).
