# Reactive UI - Godot - VS2022 (GUITKX)

Editor support for **`.guitkx`**, the JSX-like markup of [ReactiveUI for Godot](https://github.com/reactive-ui-toolkit/ruitk-godot) — a React-style reactive UI library for Godot 4.x.

## Features

- **Syntax highlighting** for the JSX-like markup *and* the embedded GDScript, via a self-contained TextMate grammar.
- **Markup IntelliSense** — completion and hover for host-element tags, structural/common attributes, control-flow directives (`@if`/`@elif`/`@else`/`@for`/`@while`/`@match`/`@case`/`@default`), and per-element event handlers.
- **Embedded-GDScript IntelliSense** — completion, hover, and go-to-definition inside `{expr}`, setup, and control-flow conditions, analyzed **in-process** by the headless [`@gdscript-analyzer/core`](https://www.npmjs.com/package/@gdscript-analyzer/core) so you get real `V.*` / `Hooks.*` / Godot-API intelligence — **no running Godot editor required**, fully offline.
- **Diagnostics** for structural problems.

## Requirements

- None — the language server ships with the extension (a Node.js runtime is bundled). Embedded-GDScript intelligence runs offline; no Godot editor, no TCP/language-server connection required.
