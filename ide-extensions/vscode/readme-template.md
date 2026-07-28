# Reactive UI Toolkit — Godot - VS Code (GUITKX)

Language support for **`.guitkx`**, the JSX-like markup of
[Reactive UI Toolkit — Godot](https://github.com/reactive-ui-toolkit/ruitk-godot) — a React-style reactive
UI library for Godot 4.x — plus a full, headless GDScript language service for your plain `.gd`
files. Everything runs **in-process via
[gdscript-analyzer](https://github.com/reactive-ui-toolkit/gdscript-analyzer)**: no running Godot editor,
no TCP connection, works fully offline.

## Features

- **Syntax highlighting** for `.guitkx` — hand-tuned TextMate grammar; embedded GDScript inside
  `{expr}`, setup blocks, and `@if`/`@for` conditions gets real GDScript colouring.
- **Markup IntelliSense** — completion and hover for tags, attributes, attribute values,
  directives, hooks, and events (React-style aliases like `onPressed` plus the verbatim
  `on_<signal>` escape hatch), plus live diagnostics for structural markup errors and dangling
  component references as you type.
- **Formatting** — the same formatter the in-Godot editor uses, configured by a Prettier-style
  `guitkx.config.json` walk-up (`printWidth`, `indentStyle`, `indentSize`,
  `singleAttributePerLine`, `insertSpaceBeforeSelfClose`); Format on Save is on by default for
  `.guitkx`. When [gdformat](https://github.com/Scony/godot-gdscript-toolkit) is installed,
  embedded GDScript is reflowed too — semantics-guarded, so formatting never changes behavior.
- **Embedded-GDScript IntelliSense** — the GDScript *inside* your markup is projected into a
  synthetic virtual document with a length-preserving source map and analyzed by
  gdscript-analyzer, so `{expr}` and setup code get typed completion, hover, and go-to-definition
  at the exact right positions.
- **Full `.gd` language service** — with `guitkx.enableGdscriptAnalysis` (on by default) your
  plain `.gd` files get the analyzer's whole surface, headless: diagnostics, completion, hover,
  navigation, project-wide rename, formatting, semantic highlighting, inlay hints, code actions,
  and document symbols.
- **Configurable** — `guitkx.enableEmbeddedAnalysis`, `guitkx.enableGdscriptAnalysis`, and
  `guitkx.useGdformat` toggle each analysis layer independently; this extension's `.gd` analysis
  runs alongside the godot-tools extension — disable godot-tools' language server, or turn this
  extension's off, to avoid duplicate diagnostics.
- **Shares its compiler with the in-Godot editor** — the **Reactive UI Toolkit — Godot Editor** addon is a native
  in-Godot `.guitkx` editor with the same language features; both editors share the same compiler,
  formatter, and diagnostic codes, and the runtime addon (`reactive_ui_toolkit`) compiles `.guitkx` to
  plain `.gd` on save with hot reload (Fast Refresh).

## Requirements

- None — everything ships in the extension. The language server runs on VS Code's own built-in
  Node runtime (no Node.js install needed), and embedded-GDScript intelligence is fully offline:
  no Godot editor, no TCP/language-server connection required.
