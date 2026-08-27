# Changelog

All notable changes to the **Reactive UI Toolkit — Godot Editor** Godot addon are documented here.
This addon versions independently of the `reactive_ui_toolkit` runtime library. Entries from
0.6.3 onward are generated from `ide-extensions/changelog.json` (the single source
shared with the GUITKX IDE extensions) — add entries via `changelog.mjs add --scope
editor`, then regenerate this file with `extract`; never edit it by hand. The history
below the marker line predates the cutover and is preserved verbatim.

## [0.13.0] - 2026-08-27
- **The UI Builder** — a visual editor for a whole `.guitkx` module tree, on the editor's own menu (**Reactive UI Toolkit → Builder...**, degrading to **Project → Tools → Reactive UI Toolkit Builder...** where the main-menu bar cannot be found). It opens the focused module plus everything it imports, transitively, plus its folder, and draws each module as a card on an infinite canvas with the imports between them as Bezier edges. Cards are not thumbnails: each lists the module's real structure — imports, signature, markup tree, exports, setup islands — at three levels of detail as you zoom, so a forty-module tree stays legible. All five module kinds are shown and editable (component, hook, style, util, value); modules under `addons/` open read-only.
- **Editing is structural, and it writes `.guitkx`.** Drag a host element, a hook, or one of the tree's own components from the library pane onto a card and the drop lands in one of three bands on the row under the pointer — before it, inside it, or after it. Dragging a row moves the subtree; dragging one card onto another moves the module into that folder. Attributes, directive headers (`@if`/`@elif`/`@else`, `@for`, `@while`, `@match`/`@case`/`@default`) and module names edit in a floating inline editor over the card. Dropping a component from another module adds the `import` it needs in the same edit; renaming a module rewrites the specifier in every file that imports it. A placement that cannot be expressed is refused with a reason rather than written and then reported — a directive body holds exactly one root, so a sibling drop inside one is declined instead of producing GUITKX0108.
- **One funnel, one ledger.** A keystroke in the source pane, a drop on the canvas and a replayed undo all take the same path, so they produce the same ledger entry, the same preview round and the same re-projection. Consecutive typing merges into one entry; a gesture that touched two files is one entry containing both, and undo walks all of it or none. The library's vocabulary is the compiler's — host tags come from the same `vocabulary.json` the language server reads and hooks from the compiler's own list — so the palette cannot offer a name the compiler has never heard of.
- **Nothing touches disk until Save.** Save formats every dirty buffer (honouring the format-on-save setting and any `guitkx.config.json`), writes them in one pass, carries planned renames across the module's companions (`.uid`, `.diags.json`, the generated `.gd` and its `.uid` — Godot has no asset database to do it for you), rewrites importers' specifiers, and sends deletions to the OS trash. Abort discards every buffer and returns the tree to what is on disk. A module you created and left blank stays pending and says so in the console rather than blocking the save.
- **Live preview without writing to your project.** Dirty buffers are mirrored into a scratch folder and compiled there, debounced, recompiling only what the change can reach — the edited module and the importers whose meaning depends on it. Diagnostics for the whole tree land in the builder's console, clickable to the module that raised them. Unsaved work is journalled under `user://` every few seconds, and only while there is unsaved work, so a crashed editor offers the tree back on the next open.
- The canvas itself is written in `.guitkx` and rendered by the reconciler — the largest, busiest, most re-rendered surface in the project runs on the library it is a builder for.
- **Docs:** new **Tooling → UI Builder** page, and the Styling page now teaches `.style.guitkx` style modules (authoring, importing, applying, the eager-import cycle rule) and the `@uss`/`@theme` directive. The gallery ships a **Style modules** demo — the first shipped example of a `.style.guitkx` module and of `@uss`.
- Known limitation, now documented: a generated `.gd` is not a `@tool` script, and Godot never runs a non-tool script's `static var` initialisers in the editor — so a style module read from `@tool` editor code comes back empty. Runtime and Fast Refresh are unaffected. Export a function instead of a value when editor code has to read it.

## [0.12.0] - 2026-07-31
- One settings dialog (rides the library 0.14.0 settings + family-parity wave — family design: one settings screen per leg, on the plugin's own menu surface): a top-level "Reactive UI Toolkit" menu injected into the editor's main menu bar (Settings...; degrades automatically to Project > Tools > "Reactive UI Toolkit Settings..." on a build where the bar cannot be found) and the new Settings button in the ReactiveUITK main-screen toolbar open the same dialog — a Runtime section with the runtime addon's twelve `reactive_ui_toolkit/*` keys (shown whenever that addon is installed; this plugin also seeds their registration, so enabling either addon alone suffices) and an Editor section with this addon's six `reactive_ui_toolkit_editor/*` toggles. It is now the primary settings UI, but storage is unchanged: the dialog reads and writes the same native Project Settings keys, saving only values that actually changed, so Project > Project Settings remains a live mirror and `override.cfg` per-machine overrides keep working. With the runtime addon absent the dialog degrades to the Editor section alone.
- Dialog coverage for the 0.14.0 family-parity knobs: enum-valued String keys now populate their dropdowns from the runtime's per-key hint vocabularies instead of assuming every String key is an auto/enabled/disabled tri-state — `diagnostics/trace_level` offers none/basic/verbose and `runtime/environment` offers auto/development/production, degrading gracefully to the tri-state vocabulary against an older runtime addon that publishes no hints — the new `runtime/time_slice_ms` spin row, `runtime/strict_mode` toggle, and `diagnostics/diff_tracing` checkbox land as regular rows, and the two keys that exist only on this leg (`diagnostics/enabled`, `diagnostics/capture`) are marked "(Godot-only)" in their tooltips, matching the family docs.

## [0.11.0] - 2026-07-28
- Reactive UI Toolkit rebrand (rides the library 0.13.0 — see MIGRATION-0.13.md): the addon folder is now `addons/reactive_ui_toolkit_editor`, the bundled analyzer folder `addons/reactive_ui_toolkit_analyzer`, its classes are `Ruitk*`-prefixed, and it depends on the renamed `addons/reactive_ui_toolkit` runtime. The display name is "Reactive UI Toolkit — Godot Editor" and the bundled license is retitled Reactive UI Toolkit Community License 1.1 — terms unchanged except the binding Attribution clause, whose required credit line follows the product name and is now "Made with Reactive UI Toolkit" (or "Reactive UI Toolkit — Godot"). Zero behavior changes. After updating, delete the old `addons/reactive_ui_editor` and `addons/reactive_ui_analyzer` folders by hand (store updates never delete — the symptom is a scan full of `UID duplicate detected` warnings, one per core file; the handful of class names the two copies share resolve silently in the new addon's favour, so a clean Errors dock does NOT mean the step was done), and re-enable the plugin if the rename left it disabled. Your Project Settings survive the move: the library's 0.13.0 codemod renames the persisted `[reactive_ui_editor]` section in project.godot to `[reactive_ui_toolkit_editor]`, so any toggle you had switched off — format_on_save, diagnostics_enabled, … — stays off instead of silently reverting to its ON default.

## [0.10.1] - 2026-07-25
- Null-only components (library 0.12.1, React semantics) ride the compiler into the in-editor tier: a component whose body has a top-level `return null` and no markup return compiles on save, renders nothing at runtime, and the unreachable-code dimmer skips it. A nested-only `return null` (conditional guard with a fall-through path) is still GUITKX2101, unchanged.

## [0.10.0] - 2026-07-18
- ES combined import forms (library 0.12.0) ride the compiler into the in-editor tier: `import Def, { a, b as c } from` / `import Def, * as X from` parse, compile, highlight, and resolve like every other form.
- Import-brace completion: Ctrl+Space inside `import { | } from "./file"` offers the target's exported declarations (kind-tagged), excluding names already listed — including inside the combined `import Def, { | }` form, where the default binding and the export it already binds are excluded as noise.
- The in-editor virtual document now declares every preamble-imported name as a permissive stub (the port of the external LSP's declareImportStubs was missing), so embedded references to imported names — named, renamed, `* as`, default, and every part of a combined import — resolve in the native-analyzer tier instead of going dark.
- BREAKING (library 0.12.0): GUITKX2304 (unused import) is now error-tier — the Problems dock and inline squiggles render unused imports red, and the compile-on-save sweep fails the file until the import is deleted or used. Findings span the whole binding token in every import form.
- License: the editor addon ships under the ReactiveUI Community License 1.0 from this release (previously PolyForm Shield 1.0.0) — free under US $250,000 trailing-12-month revenue, commercial license above that ($2,000 per title or $2,500 per studio per year — LICENSE-COMMERCIAL.md in the repo). The addon's bundled LICENSE carries the new text; no functional changes. Previously published versions keep the license they shipped with.

## [0.9.0] - 2026-07-18
- ES modules 0.11.0 (rides the library 0.11.0 — see MIGRATION-0.11.md): plain, signature-classified declarations replace the `component`/`hook`/`module` wrapper keywords — `Name(p) -> RUIVNode {}` is a component, `use_x(p) {}` a hook, any other callable a util, `name := expr` a value export — and the import surface grows to the full ES set (`{ a as b }` renames, `* as X` namespaces, default imports/exports, deferred `export { … }` lists). Highlighting, the tokenizer, the workspace/declaration index, outline, live header diagnostics, markup windows, and the virtual-doc analyzer all classify the plain forms; wrapper syntax keeps working for the deprecation window with a live GUITKX2320 warning, and the new 232x diagnostics (2321 cross-guard, 2323–2327 export/import-marker errors) surface live. The TextMate grammar and schema teach the new forms; `as`/`default`/`from` join the keyword faces.

## [0.8.1] - 2026-07-14
- Godot version floor gated: the editor addon now checks the running Godot FIRST in its dependency handshake and refuses politely below 4.4 (the bundled native analyzer is a GDExtension with compatibility_minimum = "4.4", so it cannot load on older engines). Pairs with reactive_ui 0.10.1, which gates its .guitkx watcher the same way.

## [0.8.0] - 2026-07-11
- 0.10.0 imports leg (rides the library 0.10.0): the editor addon recognizes the new `import { … } from "…"` preamble and the `export` declaration prefix — highlighting, tokenizer, and the workspace/declaration index are import/export-aware, and multi-declaration `.guitkx` files index every declaration. The compiler-driven 23xx import diagnostics surface live from the sidecar. Recompile-on-save keeps resolving imports each sweep; HMR re-renders only the component importers of a changed hook/module.

## [0.7.0] - 2026-07-11
- 0.9.0 naming loyalty support (BREAKING vocabulary, rides the library 0.9.0 — see MIGRATION-0.9.md): the bundled guitkx-schema.json is rewritten to the loyal vocabulary (54 curated elements, tags = official Godot class names, factories = V.ClassName, loyal per-element events, exact style keys); event intelligence is now derived LIVE from ClassDB — on + PascalCase(signal) for every signal of every class (the REACT_EVENTS alias table is gone); host-tag recognition gains the open vocabulary (any instantiable ClassDB Node class highlights and completes as a host element, matching the compiler).

## [0.6.3] - 2026-07-10
- Syntax highlighting tokenizes ~17% faster. The per-line tokenizer (the per-keystroke path behind every visible line's colouring) now reads characters via `unicode_at` + integer comparisons instead of single-char-String indexing, classifies symbols through a constant int-keyed set instead of a per-char string scan, and keeps its char-code table local (cross-script constant access is a runtime lookup in GDScript). The emitted token stream is hash-identical to 0.6.2 across the whole example corpus -- purely faster, no visual change.
- Live compiles and diagnostics inherit the runtime compiler's ~28% speed-up and its comment-desync fix (see `reactive_ui` 0.8.7's changelog) -- pairs best with `reactive_ui` 0.8.7+.

<!-- changelog.mjs cutover: entries above are generated from ide-extensions/changelog.json; the history below is frozen and preserved verbatim. -->

## [0.6.2] — 2026-07-06

### Fixed
- When a format-on-save falls back to leaving the buffer untouched because the file has a syntax
  error the formatter can't safely reflow around, the editor now tells you: a one-time-per-path
  modal ("*&lt;file&gt; has syntax errors -- format skipped.*") instead of silently no-op'ing, so a
  stale, unformatted file doesn't read as "already formatted."

## [0.6.1] — 2026-07-05

**The native analyzer is now bundled.** The editor download ships the `reactive_ui_analyzer`
GDExtension inside the same zip — one download, zero extra steps: unzip into your project,
enable `reactive_ui_editor`, and embedded-GDScript intelligence is on. (Previously a separate,
optional download from the analyzer's releases.)

### Changed
- The release zip now contains **both** `addons/reactive_ui_editor/` and
  `addons/reactive_ui_analyzer/` (analyzer 0.6.1 — Windows x86_64, Linux x86_64/arm64, macOS
  universal). The publish pipeline downloads the pinned analyzer release, refuses to package
  unless the descriptor and every platform binary are present, and runs the editor suites
  against the bundle before releasing (the analyzer actually loads on the CI runner).
- The analyzer keeps its own folder and stays **feature-detected**: deleting
  `addons/reactive_ui_analyzer/` (or running a platform without a prebuilt binary) degrades
  gracefully to the markup-only experience — now announced by a soft yellow Output note instead
  of silence, since with bundling absence is unusual rather than the default.
- Docs: install instructions and store listings describe the bundle; the analyzer folder should
  be excluded from game export presets (editor-only tooling), and macOS users keep the one-line
  de-quarantine step from the analyzer README.

## [0.6.0] — 2026-07-05

**Embedded-GDScript intelligence (plan M3).** The editor's last frontier: the GDScript *inside*
your markup — `{expr}` values, setup lines, hook bodies — now gets **type-aware** completion,
hover, diagnostics, go-to-definition, find-references, rename, and signature help, powered by a
native in-process binding of [gdscript-analyzer](https://github.com/reactive-ui-toolkit/gdscript-analyzer).
No server, no Node, no configuration.

### Added
- **The `reactive_ui_analyzer` companion addon** (a separate, optional download from the
  analyzer's GitHub releases): prebuilt GDExtension binaries exposing the full analyzer as one
  `GdscriptAnalyzer` class. This editor **feature-detects** it — installed, everything below
  turns on (the Output says so once per session); absent, the editor is exactly the 0.5.0
  markup-only experience. Windows x86_64 / Linux x86_64+arm64 / macOS universal, Godot 4.4+.
- **Virtual documents**: each buffer projects its embedded GDScript into a synthetic `.gd`
  (scope-aware — real `if`/`for`/`match` structure so loop/branch variables resolve; hook calls
  resolve through class-level stubs pinned byte-identical to `hooks.gd`; markup is neutralized,
  never parsed as GDScript), with a length-preserving offset source map, mirroring the VS Code
  server's virtualDoc/sourceMap pair — the third implementation of the same contract.
- **Type-aware completion** inside expressions and setup code: `b.` on a `Button` local offers
  the real engine surface (member kinds, typed details), merged after the markup tier's items.
- **Type-aware hover**: the inferred type/signature leads the card (`**Button**`), engine docs
  follow; markup hover keeps priority over tags/attributes.
- **Embedded diagnostics**: analyzer syntax/type errors squiggle at their exact `.guitkx`
  position, prefixed `GD:` in Problems rows; anything anchored in virtual-doc glue is dropped —
  scaffolding can never squiggle user code.
- **Go-to-definition / references / rename for embedded symbols**: same-file hits remap into the
  buffer; definitions into real `.gd` files open in Godot's own Script editor at the right line;
  F2 on an embedded local renames it buffer-scoped as one undo step (analyzer-gated, refuses
  cross-file/glue-touching edits); Shift+F12 lists embedded references in the References panel.
- **Signature help everywhere**: the G4 strip now also resolves calls inside embedded GDScript
  (builtins, engine methods, your functions) with active-parameter tracking.
- **Byte-exact boundary**: a `LineIndex` port converts CodeEdit's code-point columns to the
  analyzer's UTF-8 byte offsets at every call — multibyte text (emoji, accents) cannot
  mis-anchor results (pinned by tests).

### Notes
- The analyzer session feeds every project `.gd` once per editor session (cross-file types —
  your classes, autoloads, the runtime's `RUIVNode`/`Hooks` — resolve inside expressions) and
  re-feeds regenerated siblings when the watcher recompiles.
- Requires `reactive_ui` 0.8.4+ (unchanged from 0.5.0).

## [0.5.0] — 2026-07-05

**Daily-driver parity (plan M2).** Everything the VS Code extension can do for `.guitkx`, the
in-Godot editor now does natively — plus the workflow features a code editor is judged by once
you live in it: multi-file sessions, project-wide search, rename, outline, replace, signature
help. Requires the `reactive_ui` runtime addon 0.8.4+.

### Added
- **Multi-file editing** — one editor per open file: undo history, caret, scroll, decorations,
  and dirty/conflict state all survive switching. An open-files list (click switches,
  middle-click closes) sits above a **document outline** (components ◆, hooks ƒ, modules ▣ and
  their funcs — activate to jump). Sessions **restore across editor restarts** (open files,
  current tab, carets, zoom, wrap) via Godot's own layout store; Save All, the quit confirm,
  and Play flush every dirty buffer, not just the current one.
- **References + rename** — Shift+F12 lists every use of a component (declaration ◆, tags,
  `@class_name` bindings) in a References bottom panel; F2 renames project-wide across open
  buffers AND files on disk, refusing collisions (host tags, existing components, global
  classes) instead of corrupting. Ctrl+hover/Ctrl+click also resolves **hook names** into
  `hooks.gd`.
- **Project-scope Problems** — the Problems panel gains a Current File / Project switch;
  Project aggregates every compile sidecar in the workspace (including the sweep-only
  GUITKX2106 duplicate-binding / GUITKX2107 dangling-reference verdicts) with line-resolved,
  clickable rows. Rows now lead with their `[GUITKX####]` code and carry full-message tooltips.
- **Project-wide search** — a "Search .guitkx" bottom panel (plain-text, match-case toggle, one
  row per matching line, activate to open+jump). This is the promised replacement for Godot's
  Search in Files, which deliberately cannot see `.guitkx` (letting the built-in Script editor
  adopt those files corrupts its persistence caches).
- **Find-bar Replace / Replace All** — Replace swaps the selected match and steps; Replace All
  rewrites every match as ONE undo step, string-level so a replacement containing the query can
  never loop.
- **Signature help** — inside an event-handler lambda (`on_toggled={ func (…)` or a React alias
  like `onChange=`), a strip above the caret shows the bound Godot signal's parameters from the
  live ClassDB, bolding the active one as you type across commas. Esc dismisses.
- **Sidecar diagnostics overlay** — the watcher's project-level codes (2106/2107) appear in the
  buffer hash-gated exactly like the VS Code merge: anchored while the buffer matches the last
  compile, collapsed to a single line-0 hint once it diverges (never mis-anchored into edits).
- **Completion, tier 2** — attribute VALUES complete: enum properties offer their hint names,
  bools offer true/false, and `style={ {"…` offers all 46 RUIStyle keys; `Color.` /
  `Vector2.`-style builtin constants and hook names complete in embedded code; every signal is
  offered in both spellings (`onClick` aliases + verbatim `on_<signal>`).
- **Snippet-shaped inserts** — attributes insert `name=""` / `name={}` and parenthesised
  directives insert `@if ()`-style tails; confirming with Enter/Tab lands the caret INSIDE the
  pair, and a `"` immediately arms value completion. (CodeEdit has no tab-stops; accepted.)
- **New File** — a toolbar button seeds a `.guitkx` with a component skeleton named after the
  file and opens it.
- **Editing verbs** — Ctrl+/ comment toggle (selection-aware, one undo step), Ctrl+G go-to-line,
  Alt+Up/Down move lines, Ctrl+Shift+D duplicate, Ctrl+Shift+K delete line, Ctrl+B bookmark +
  Ctrl+Shift+B cycle (built-in bookmark gutter), Ctrl+wheel / Ctrl+=/−/0 zoom (shared across
  files), a word-wrap toggle, and Enter between `>` and `</` splits the tag pair with an
  indented middle line.
- **Formatter config** — formatting honours the nearest `guitkx.config.json` (walk-up, nearest
  wins: printWidth, indentStyle, indentSize, singleAttributePerLine, insertSpaceBeforeSelfClose)
  so one project formats identically here and in VS Code.

### Changed
- **Highlighting** — embedded `{expr}` GDScript now sub-highlights for real (keywords, strings,
  numbers; `<` is an operator there, `name=` an assignment); host tags and component tags split
  colours the way Godot splits engine vs user classes (base_type_color vs user_type_color).
- **Hint-tier diagnostics** render as Problems rows only — no gutter icon, no line tint — so
  hints stop shouting like errors.

### Fixed
- The dirty-switch prompt is gone: switching files can no longer lose work by design (every
  file keeps its own editor), so the prompt had nothing left to guard.

## [0.4.0] — 2026-07-05

The store-readiness milestone (parity plan M1) plus a hard field-testing round: the editor stops
losing work, stops lying, gains the daily-driver features a code editor is judged by in its first
five minutes — and survived a two-day torture campaign of save-spam, rename storms, deletes, and
git restores.

### Added
- **Go-to-definition** — Ctrl+click a component tag jumps to its declaration, cross-file (the
  hover text has promised this since 0.3.0; now it's true).
- **Find bar** — Ctrl+F (seeded from the selection), all-match highlight, match counter,
  F3/Shift+F3 stepping with wrap in both directions, case toggle, Esc to close.
- **Rich hover** — cards render as formatted text at show time (the old native-tooltip path
  stacked two delays and often needed a second hover pass), and hovering a **diagnosed line puts
  the error message — including its did-you-mean — right in the card**. Clicking a gutter icon
  opens the full diagnostic in a popup at the mouse instead of a line lost in Output.
- **Hook signature cards** — hovering `useState`, `useEffect`, `provideContext`, … in setup code
  shows the real signature (all 23 built-in hooks; previously the editor said nothing there).
- **Scan-tier unknown-component errors** — the compiler's own unknown-tag check lives in its emit
  phase, so the classic typo (open tag changed, close tag now mismatched = parse error) masked the
  one error that explained it. A parse-independent scan now flags unknown tags with a did-you-mean
  even while the file doesn't parse.
- **Ctrl+S saves the file** while the editor tab is visible (it used to fall through to Godot's
  Save Scene, leaving the buffer silently unsaved). Godot's **Save All**, **quit confirmation**,
  and **Play** now also see the buffer: unsaved `.guitkx` changes join the quit dialog, and
  pressing Play flushes first so the game runs what's on screen.
- **Dirty tracking + guards** — `*` in the file label; switching files with unsaved edits prompts
  Save/Discard/Cancel; double-clicking the file already being edited no longer clobbers the buffer.
- **External-change safety** — a clean buffer auto-reloads when the file changes on disk (window
  focus); a dirty buffer gets an explicit Overwrite/Reload choice at Save. Renaming/moving the open
  file in the dock retargets the buffer (Save no longer resurrects the old filename); deleting it
  marks the buffer detached and Save asks before recreating. Failed writes raise a dialog.
- **Cross-file diagnostics** — the live compile now receives the project's component universe, so
  unknown `<Component />` tags error with a did-you-mean exactly like the watcher build; the index
  and bindings follow external file changes automatically.
- **Editor substrate** — line numbers, code folding + fold gutter, minimap, current-line /
  occurrence / matching-bracket highlights, `<` auto-closes to `>`, automatic indent on Enter,
  caret blink, smooth scroll, scroll-past-end, print-width ruler.

### Fixed
- **The one that explained everything: the `.guitkx` resource loader now survives script reloads.**
  Godot removes all custom format loaders on every script-reload cycle (which the Reactive UI
  watcher triggers on each save, by regenerating a `.gd`) and re-adds only global-class ones — the
  old manually-registered loader silently died minutes into every session. Everything downstream
  followed: failed loads got cached (permanent red ✕ in the dock, "no file opens anymore"), and
  routing fell through to the built-in Script editor, which session-restored `.guitkx` ghosts as
  boot errors forever. The loader is now a global class the engine owns and re-adds itself.
- **Dock renames clean up after themselves** — renaming a `.guitkx` left its generated `.gd`
  under the old name until the watcher's next sweep, long enough for rapid renames to stack
  duplicate `class_name` declarations. The old outputs are now removed synchronously in the
  rename event (hand-written `.gd` files are untouchable, as in the watcher's own sweep).
- **A deleted-then-restored file heals** — `git restore` (or un-deleting) used to leave the buffer
  stuck on "(deleted on disk)"; a clean buffer now reloads automatically the moment the file is
  back, and detach no longer falsely marks the buffer as edited.
- **A momentarily-unreadable file can no longer poison the session** — the loader never returns a
  load error (failures get cached as a permanent red ✕); reloads update the cached resource in
  place so every holder keeps one coherent object.
- **`.guitkx` is deliberately NOT in Godot's Search-in-Files extensions** — that registration let
  the built-in Script editor adopt the files and endlessly session-restore them; an addon-native
  project search replaces it in an upcoming release.
- **Hover never fired** — `symbol_tooltip_on_hover` was never enabled, so the 0.3.0 hover feature
  was unreachable. It works now.
- **An untouched empty tab no longer greets you with a red "missing declaration" icon.**
- **Undo survived nothing** — Format (and format-on-save, which is default-on) replaced the buffer
  via `text =`, wiping the undo history on every save. Formatting is now a single undoable edit
  with the caret preserved.
- **The editor typed tabs/4 while the formatter wrote spaces/2**, mixing indentation on every
  format cycle. The editor now types exactly what the formatter emits (spaces, 2), and tab glyphs
  are drawn so any legacy mix is visible.
- **Unsaved scratch buffers self-reported a name mismatch** (GUITKX0103) against the placeholder
  basename; a pathless buffer now derives its identity from its own declaration.
- Big files no longer freeze the editor on every typing pause — the compile debounce stretches
  with measured compile time (0.3s floor, 2s cap), and the live-compile guard tightened.

### Dependencies
- Requires **Reactive UI 0.8.1+**; the plugin now checks on enable and shows a friendly dialog
  (instead of a raw script error) when the runtime addon is missing, incomplete, or too old.

## [0.3.0] — 2026-07-04

- **Native markup intelligence — completion and hover, right inside the Godot editor, no VS Code
  required.** Five new pure-logic modules (`lsp/guitkx_schema.gd`, `guitkx_context.gd`,
  `guitkx_completion.gd`, `guitkx_hover.gd`, `guitkx_workspace.gd`), headlessly tested (39 checks,
  `tests/guitkx_lsp_test.gd`), wired into `GuitkxCodeEdit`:
  - **Completion** on `<` (host tags + your own project's components), inside an attribute list
    (structural attributes, React-style event names resolved to the real Godot signal via
    `ClassDB`, plain properties), and after `@` (directives) — driven by
    `data/guitkx-schema.json` plus **live `ClassDB`** lookups, so it always matches the running
    engine version rather than a bundled snapshot.
  - **Hover** for tags, attributes, and directives, plus your own components (resolved against a
    project-wide index that's re-scanned on save) — shown as a native `CodeEdit` tooltip
    (Godot 4.4+).
  - Both are independently toggleable (`completion_enabled` / `hover_enabled` under
    **Project Settings → `reactive_ui_editor/`**), default **on**, apply live.
- Embedded-GDScript intelligence inside `{expr}`/setup code is still **not** covered — that layer
  stays VS Code / VS 2022-only (`ide-extensions/`, via `@gdscript-analyzer/core`). See
  `plans/GODOT_ANALYZER_INTEGRATION_PLAN.md` and `plans/NATIVE_EDITOR_PARITY_PLAN.md` for the
  remaining gap (go-to-definition, find-references, rename, signature help, semantic tokens).

## [0.2.0] — 2026-07-01

- **Unreachable code is dimmed.** Code after a component's markup `return (...)` is faded in the editor
  (parity with the compiler's `GUITKX0114` and Unity's `UITKX0107`).
- **Richer live diagnostics for free.** The editor renders `RUIGuitkx.compile()` diagnostics, so it now
  surfaces the new compiler validations live: single-root `@for`/`@while` bodies (`GUITKX0108`), duplicate
  expression keys (`GUITKX0104`), `@class_name` validation, invalid tag names, misspelled-keyword hints,
  and unreachable-code warnings.
- **Fix:** stop re-adding `CodeEdit`'s built-in `{ } ( ) [ ] " "` auto-brace pairs — they threw four
  "auto brace completion open key already exists" errors on editor load.

## [0.1.0] — 2026-07-01

- Initial release: a main-screen `.guitkx` editor (`@tool` `EditorPlugin`) with lexer-driven syntax
  highlighting, live compiler diagnostics (gutter icons + a bottom **Problems** panel), Open / Save /
  Format, double-click routing via a toggle-able `ResourceFormatLoader`, and default-on settings under
  `reactive_ui_editor/`. Depends on the `reactive_ui` addon for the `.guitkx` compiler/formatter.
