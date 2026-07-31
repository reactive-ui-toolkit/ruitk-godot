# Reactive UI Toolkit — Godot Editor

In-editor authoring for `.guitkx` files, right inside the Godot editor: a **main-screen,
multi-file editor** with syntax highlighting (embedded-expression sub-highlighting included),
live compiler diagnostics with file and project scope, completion with snippet inserts, hover,
signature help, go-to-definition, find-references, project-wide rename and search, a document
outline, find/replace, session restore, and the data-safety guardrails you'd expect from a real
editor (per-file dirty tracking, external-change detection, rename/delete follow-up,
undo-surviving format).

This is the sibling of the **Reactive UI Toolkit — Godot** runtime addon (`addons/reactive_ui_toolkit`) and **depends on it** —
it reuses that addon's `.guitkx` compiler (`RuitkGuitkx`), formatter (`RuitkGuitkxFormatter`) and lexer
primitives (`RuitkGuitkxLexer`). Install/enable **Reactive UI Toolkit — Godot first** (0.13.0 or newer — the plugin
checks and tells you politely instead of erroring if it's missing or too old).

## Install

1. Copy both `addons/reactive_ui_toolkit/` and `addons/reactive_ui_toolkit_editor/` into your project's `res://addons/`.
2. Enable both under **Project → Project Settings → Plugins** (Reactive UI, then Reactive UI Toolkit — Godot Editor).
   In this repository both are already enabled in `project.godot`.

Requires **Godot 4.4+**.

## What it does

- A **ReactiveUITK** tab appears in the main-screen bar (next to 2D / 3D / Script / AssetLib).
- **Double-click a `.guitkx`** in the FileSystem dock (or use the **Open** / **New** buttons) to edit
  it here. **Multi-file**: every open file keeps its own editor — undo history, caret, scroll, and
  dirty state survive switching; an open-files list (middle-click closes) and a **document outline**
  (activate to jump) sit in the left pane; your session (open files, current tab, carets, zoom, wrap)
  **restores across editor restarts**.
- **Syntax highlighting** for tags, attributes, `{expr}` regions, strings, `#` comments, keywords and
  `@directives`, themed to match your editor's GDScript colors — host tags and your components get
  the engine-vs-user class colour split, and **embedded `{expr}` GDScript sub-highlights** for real
  (keywords/strings/numbers) — plus line numbers, code folding, minimap, bookmarks,
  current-line/occurrence/bracket highlights, and a ruler at the formatter's print width.
- **Import-aware (0.10.0)**: `import { … } from "…"` and `export` are first-class syntax;
  multi-declaration files index every declaration; and the import diagnostics
  (`GUITKX2300`–`GUITKX2309` — unresolved specifier, not exported, value-import cycle, …) surface
  exactly like the build's.
- **Live diagnostics**: on each (debounced) edit the file is compiled with `RuitkGuitkx.compile` — with
  the full project's component universe, so an unknown `<Component />` errors (with a did-you-mean)
  exactly like the build. Errors/warnings show as **gutter icons + line tints** and in a bottom
  **Problems** panel whose scope switch flips between the **current file and the whole project**
  (aggregated from the compile sidecars, including the sweep-only duplicate-binding /
  dangling-reference verdicts, hash-gated into the open buffer so they never mis-anchor). Rows lead
  with their `GUITKX####` code; click one to jump. Hints stay out of the gutter. Big files
  automatically stretch the compile debounce instead of stuttering.
- **Completion** on `<` (host tags + your own project's components, from a project-wide index that
  follows external file changes), inside an attribute list (structural attributes, React-style event
  names AND the verbatim `on_<signal>` spelling, resolved via live `ClassDB`, plain properties),
  for **attribute values** (enum hint names, true/false, the 46 style-dict keys), after `@`
  (directives), and in embedded code (`Color.`-style builtin constants, hook names). Inserts are
  **snippet-shaped** — confirming `text=""` / `onPressed={}` / `@if ()` lands the caret inside the pair.
- **Hover** for tags, attributes, directives, hooks, and your own components; **signature help**
  shows the bound signal's parameters (active one bolded) while you type an event-handler lambda.
- **Navigation & refactoring**: Ctrl+click a component tag (or hook name) jumps to its declaration,
  cross-file; **Shift+F12** lists every reference in a References panel; **F2 renames** a component
  project-wide (open buffers and disk), refusing collisions; **Ctrl+G** goes to a line.
- **Find / Replace**: Ctrl+F opens the find bar (all-match highlight, match count, F3/Shift+F3 with
  wrap, case toggle, **Replace and Replace-All** as one undo step). Project-wide text search lives in
  the **Search .guitkx** bottom panel — `.guitkx` is deliberately NOT registered into Godot's Search
  in Files (that route lets the built-in Script editor adopt and endlessly session-restore `.guitkx`
  files; the addon panel is the replacement).
- **Editing verbs**: Ctrl+/ comment toggle, Alt+Up/Down move lines, Ctrl+Shift+D duplicate,
  Ctrl+Shift+K delete line, Ctrl+B / Ctrl+Shift+B bookmarks, Ctrl+wheel or Ctrl+=/−/0 zoom, word
  wrap toggle, and Enter between `></` splits the tag pair with an indented middle line.
- **Ctrl+S saves the `.guitkx`** while the tab is visible; Godot's own Save All / quit-confirmation /
  Play flows flush **every dirty buffer** (unsaved changes join the quit dialog; pressing Play saves
  first so the game runs what's on screen).
- **Your work is protected**: per-file dirty state; if a file changed on disk a clean buffer
  auto-reloads on focus while a dirty one gets an explicit Overwrite/Reload choice at Save; renaming
  or moving files in the FileSystem dock retargets open buffers (Save never resurrects the old
  filename); deleting one marks its buffer detached and Save asks before recreating; failed writes
  raise a dialog, not just a console line.
- **Save** writes only the `.guitkx`; the Reactive UI Toolkit — Godot addon's own watcher regenerates the sibling `.gd`
  (and, if a game is running under F5, hot-reloads it in place — see Fast Refresh in the root README).
- **Format** (button or format-on-save) runs `RuitkGuitkxFormatter` — never corrupts (verbatim on parse
  error), applies as **one undoable edit** (Ctrl+Z survives), and honours the nearest
  **`guitkx.config.json`** (printWidth, indentStyle, indentSize, singleAttributePerLine,
  insertSpaceBeforeSelfClose) so a project formats identically here and in VS Code.

## Settings

The top-level **Reactive UI Toolkit ▸ Settings...** menu (added to the editor's main menu bar;
falls back automatically to **Project ▸ Tools ▸ Reactive UI Toolkit Settings...** if the menu bar
cannot be injected) — or the **Settings** button in the
ReactiveUITK main-screen toolbar — opens the settings dialog, the primary UI: an **Editor**
section with the toggles below, plus a **Runtime** section for the runtime addon's
`reactive_ui_toolkit/*` tunables (see the root README's Settings section; it appears whenever
the runtime addon is installed). Storage is native Project Settings, so **Project → Project
Settings → `reactive_ui_toolkit_editor/`** keeps working as a mirror of the same keys.

All default **on**; toggle any off. Highlighting, completion, hover, diagnostics and format-on-save
apply **live**. `open_guitkx_in_editor` is structural (it registers a resource loader that reroutes the
double-click) and applies after you **re-enable the addon**.

| Setting | Default | Effect |
|---|---|---|
| `highlighting_enabled` | on | `.guitkx` syntax highlighting |
| `diagnostics_enabled` | on | live compile + gutter/Problems diagnostics |
| `completion_enabled` | on | tag / attribute / directive completion |
| `hover_enabled` | on | tag / attribute / directive / component hover |
| `open_guitkx_in_editor` | on | double-click a `.guitkx` opens it here (off: it opens in the Inspector) |
| `format_on_save` | on | run the formatter when saving |

Note: `.guitkx` files stay visible in the FileSystem dock even while this addon is disabled — the
format's resource loader is a global class the engine registers on its own (that is also what keeps
it alive across Godot's script-reload cycles).

## Embedded GDScript intelligence (bundled native layer)

The editor download **bundles the `reactive_ui_toolkit_analyzer` GDExtension** (prebuilt binaries for
Windows x86_64, Linux x86_64/arm64, and macOS universal) in the same zip — it lands at
`addons/reactive_ui_toolkit_analyzer/`, loads automatically, and needs no enabling. With it, the
GDScript *inside* your markup gets the full type-aware treatment: completion on your typed
locals (`b.` on a `Button` offers the real engine surface), inferred-type hover, syntax/type
diagnostics squiggled at the exact expression (`GD:` codes in Problems), go-to-definition (into
this buffer or into real `.gd` files via Godot's Script editor), find-references, buffer-scoped
F2 rename, and signature help inside calls.

The layer is still **feature-detected** (`ClassDB.class_exists("GdscriptAnalyzer")`): delete the
folder — or run a platform without a prebuilt binary — and the editor is exactly the markup-only
experience above, fully supported (a yellow Output note says so once per session). Under the
hood each buffer projects its embedded GDScript into a scope-aware virtual `.gd` with a
length-preserving source map (the same virtualDoc/sourceMap contract the VS Code server uses),
and every offset crosses the boundary through a byte-exact LineIndex, so multibyte text can't
mis-anchor results.

Two operational notes: **exclude `addons/reactive_ui_toolkit_analyzer/` from game export presets** (it
is editor-only tooling — keep the native libraries out of shipped builds), and on **macOS** the
bundled dylib is unsigned — the analyzer folder's README has the one-line de-quarantine command.
A newer analyzer can be dropped in at any time — with one rename. Download a
`reactive-ui-analyzer-*.zip` from
[gdscript-analyzer releases](https://github.com/reactive-ui-toolkit/gdscript-analyzer/releases) and
unzip it somewhere: that repo is a standalone project, deliberately outside the Reactive UI Toolkit
rename, so its archive still extracts to **`addons/reactive_ui_analyzer/`**. Rename that folder to
**`addons/reactive_ui_toolkit_analyzer/`** and copy it over the bundled one (release packaging does
the same `mv`). Unzipping it as-is instead would leave *two* analyzer folders side by side, both
registering the `GdscriptAnalyzer` class. The GDExtension is relocatable — its library entries are
folder-relative and detection is `ClassDB.class_exists("GdscriptAnalyzer")` — so the rename is safe.

## Known limits (vs. the VS Code / VS 2022 extensions)

- CodeEdit has no snippet tab-stops, so multi-field templates (beyond the caret-in-pair inserts)
  don't exist here.
- Analyzer-backed inlay hints aren't rendered (CodeEdit has no inline-hint API).
