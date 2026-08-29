# Porting the RUITK Builder to Godot — source-of-truth guide

> **Audience.** An agent working in `ruitk-godot`, who knows the Godot leg well
> and does not know the Unity leg. This document is the Unity leg's side of the
> conversation: what the builder IS, what it does, why it does it that way, and
> exactly which file to read for each answer.
>
> **This is not a plan.** It deliberately does not say how the Godot port should
> be structured — that judgement needs the Godot codebase, which is yours. It
> gives you the complete behavioural contract plus the implementation's
> hard-won constraints, so your investigation starts from facts rather than
> from reading 20k lines of C#.
>
> **Status of the Unity implementation:** shipped in package `0.17.0`
> (first release) and substantially extended through `0.18.1`. Roughly 20,000
> lines under `Builder/`, plus seams in four other subsystems. About 221
> tracked defects, ~200 fixed; the register is the single most valuable file
> here after the code itself.

---

## 0. Where the Unity leg lives

Both legs are siblings under the same parent directory, so every path below is
written relative to **this repo's root**:

```
reactive-ui-toolkit/
  ruitk-godot/     <- you are here
  ruitk-unity/     <- the implementation this guide describes
```

So `../ruitk-unity/Builder/Editor/BuilderWindow.cs` resolves from a normal
side-by-side checkout. If your clone is laid out differently, adjust the prefix
once; every reference below shares it.

Remote: `github.com/reactive-ui-toolkit/ruitk-unity` (branch `feat/ruitk-builder`
carries the newest work; `master` carries the released state).

### The three documents to read before the code

| File | What it gives you |
|---|---|
| `../ruitk-unity/plans/UI_BUILDER_CAPABILITIES.md` | The portable behaviour contract, written expressly so the builder can be rebuilt for another engine without reading Unity source. **422 lines. Read it first.** |
| `../ruitk-unity/Plans~/UI_BUILDER_BUGS.md` | ~221 numbered defects with root causes. This is where the expensive lessons are. |
| `../ruitk-unity/Plans~/BUILDER_TREE_MODEL.md` | The document model rewrite, and the settled placement convention. |

> **Relationship between the two.** `UI_BUILDER_CAPABILITIES.md` is the
> BEHAVIOUR contract and is current as of 2026-08-27 — it was refreshed
> alongside this guide, and the Unity leg has a skill requiring it to stay that
> way. It deliberately carries no file paths, no implementation detail and no
> defect history. This guide is the complement: the same surface plus where
> each piece lives, which seams it depends on, and which mistakes cost time.
> Read that file first for WHAT, this one for WHERE and WHY.

---

## 1. What the builder is, in one paragraph

An in-editor visual editor for `.uitkx` component trees. It shows a pannable,
zoomable **canvas of cards** — one card per file in the tree — wired by
**import edges**, with a **folder tree** and a searchable **library** down the
left, and a **live preview** stacked over a **bidirectional source editor** on
the right. Every gesture lands as a text edit on an in-memory buffer. Nothing
reaches disk until Save. The user is always looking at real source they own.

The framing used in the docs is **near-zero-code, not no-code**: structure,
markup, styling and wiring are point-and-click; hook bodies and handlers are
typed. There is no proprietary format at any point — a card *is* a file.

---

## 2. The five load-bearing invariants

Everything else is detail. If the Godot port keeps only these, it will behave
like the Unity one; if it breaks any of them, it will diverge in ways users
notice immediately.

### 2.1 The save-only disk contract

Nothing reaches disk until **Save**. Every edit — including **deletion**,
**rename**, and **folder moves** — is a pending change on an in-memory tree.
**Abort** discards everything; closing without saving changes nothing.

- Read: `../ruitk-unity/Builder/Editor/Document/BuilderWorkspace.cs` (the
  document layer; owns the contract)
- Violated once and it hurt: **UB-88** (deletion bypassed it), **UB-111**
  (creation wrote immediately), **UB-87** (Delete destroyed sample files).

### 2.2 The tree is the model; disk is a projection

`BuilderTree` holds every module of one tree in memory. Save computes a **pure
diff** against the last projection and performs it. Crucially:

> **Deletion is absence.** A module is deleted by not being in the tree, not
> by a `pendingDelete` flag. Likewise "unlocated" is *derived* from where a
> module sits, never a flag a caller sets.

This replaced a flag-based design where every new call site had to remember to
set the right flags — and the one that forgot (the create flow for the second
module) produced **UB-178**, where files were silently written somewhere Unity
could not see them.

- Read: `../ruitk-unity/Builder/Editor/Document/BuilderTree.cs` (409 lines),
  `BuilderModule.cs` (213), `BuilderWorkspace.cs` (828)
- Design record: `../ruitk-unity/Plans~/BUILDER_TREE_MODEL.md`
- Headless tests: `../ruitk-unity/Builder~/ModelTests/` — 91 assertions over
  the pure model with **no engine dependency**. This is the piece most worth
  copying structurally: it let the model be verified without opening the editor.

### 2.3 Create states placement; wiring states usage

Creating a module **never** adds an import.

The reason is not aesthetic. In this language an import with no usage is
`UITKX2304`, which is **error-tier** — an unused import stops the whole project
compiling the moment the file is saved. So a create that added an import would
also have to add a *usage*, and to do that it would have to guess where a style
applies or which element a hook belongs to. That is a decision only the author
has. So create places the file and stops; the user wires it by dragging.

- Design record: `../ruitk-unity/Plans~/BUILDER_TREE_MODEL.md` §"Placement,
  settled 2026-08-25"
- **Check whether Godot's leg has an equivalent error-tier unused-import
  diagnostic.** If it does not, this constraint may relax — but the
  predictability argument stands on its own.

### 2.4 One ledger, undo across files

A user gesture is one entry, even when it touches four files. A per-file undo
stack cannot express "rename this module and every importer's specifier", so
there is a single ordered **action ledger** with atomic cross-file undo/redo.
Each change remembers which **module** it belongs to, not only which path — so
a replay still finds it after a rename moved that path.

- Read: `../ruitk-unity/Builder/Editor/Document/BuilderActionLedger.cs` (352)
- Origin: **UB-73**.

### 2.5 The canvas is dogfooded

The card canvas is itself written in `.uitkx` and rendered by the real
reconciler — `../ruitk-unity/Builder/Editor/Canvas/CanvasView.uitkx` (1276
lines) with `canvasStyles.style.uitkx` (394). The surrounding chrome (window
shell, panes, source field, menus, overlays) is hand-built C#.

This was deliberate: the builder is the framework's own stress test. It also
means **the canvas inherits the framework's re-render semantics**, which is a
live hazard — see §8.3.

---

## 3. File map of the Unity implementation

All paths under `../ruitk-unity/Builder/Editor/`. Line counts are a rough guide
to where the complexity sits.

### Shell and entry

| File | Lines | Purpose |
|---|---|---|
| `BuilderWindow.cs` | 6321 | The window shell. Hosts the workspace, owns the toolbar, panes, splitters, keyboard, all menu handlers and every structural edit funnel. **The single biggest file; start here for any "what happens when I…" question.** |
| `BuilderMenu.cs` | 79 | Entry points. Double-click on an asset is deliberately left alone — the context item is the only asset route in. |
| `BuilderNewFileDialog.cs` | 82 | New-file planning + name validation. |
| `BuilderPalette.cs` | 42 | Single source of truth for chrome colours. |
| `BuilderSaveMetrics.cs` | 38 | Save-batch / reload instrumentation. |

### Document model (engine-agnostic — port this first)

| File | Lines | Purpose |
|---|---|---|
| `Document/BuilderTree.cs` | 409 | The tree. Root resolution, moves, orphan computation. |
| `Document/BuilderWorkspace.cs` | 828 | Document layer for one open tree; owns the save-only contract, import reconciliation, folder creation/pruning. |
| `Document/BuilderModule.cs` | 213 | One module: text, current path, disk path. Touches no I/O. |
| `Document/BuilderActionLedger.cs` | 352 | Cross-file undo/redo ledger + History panel data. |
| `Document/BuilderNaming.cs` | 76 | The family convention (see §4.3). |
| `Document/BuilderSpecifiers.cs` | 66 | Import specifier ↔ path, kept as a pair because they are only correct together. |
| `Document/BuilderReloadJournal.cs` | 127 | Crash cover: the tree dumped to JSON **outside** the project assets. |

### Canvas

| File | Lines | Purpose |
|---|---|---|
| `Canvas/CanvasView.uitkx` | 1276 | The canvas itself, in the framework's own markup. |
| `Canvas/canvasStyles.style.uitkx` | 394 | Its typed styles. |
| `Canvas/BuilderCanvasHost.cs` | 1058 | Loads the graph, overlays persisted layout, mounts the view, owns camera/zoom and hit-testing. |
| `Canvas/BuilderGraphService.cs` | 1513 | Projects the tree into the canvas model: root resolution, classification, markup row flattening, edge derivation. |
| `Canvas/BuilderCanvasDrawing.cs` | 1306 | Edge painting (Bezier, screen-space overlay) + shared card metrics. |
| `Canvas/BuilderCanvasConfig.cs` | 347 | Per-tree layout persistence (see §4.9). |
| `Canvas/BuilderGraphModel.cs` | 158 | Node kinds. |

### Panes

| File | Lines | Purpose |
|---|---|---|
| `Controls/CodeField.cs` | 1394 | The source pane: coloured read mode, transparent-ink edit mode, diagnostics console. |
| `Preview/BuilderPreviewPane.cs` | 1343 | Live preview mount mechanics, props knobs, click-through. |
| `Preview/BuilderRenderScheduler.cs` | 140 | The preview's **own** budgeted scheduler — never the global editor one. |
| `Compile/BuilderPreviewCompiler.cs` | 460 | In-process compile of the current buffers, in import-graph order. |
| `Library/BuilderLibraryPane.cs` | 778 | Searchable palette; drag source. |
| `Library/BuilderFolderPane.cs` | 456 | The folder tree — a second projection of the same modules. |
| `Library/BuilderDragService.cs` | 223 | Drag lifecycle: arm, threshold, ghost, hit-test, drop. |

### Controls

| File | Lines | Purpose |
|---|---|---|
| `Controls/BuilderContextMenu.cs` | 415 | Plain context menus, drawn as a **layer in the builder's own panel**. Read its class doc — it records three rejected designs. |
| `Controls/BuilderSearchMenu.cs` | 551 | Searchable menus + name prompts. |
| `Controls/BuilderInlineEditorOverlay.cs` | 308 | **The** inline editor — one floating panel serving every editable surface. |
| `Controls/BuilderCursor.cs` | 42 | Pointer affordances. |

### Language / LSP seams

| File | Lines | Purpose |
|---|---|---|
| `Lsp/BuilderLspClient.cs` | 595 | LSP client: spawns the server over stdio with Content-Length framing. |
| `Lsp/BuilderLspService.cs` | 63 | Session-scoped owner of the **one** shared client. Never per-window. |
| `Lsp/BuilderSchemaCache.cs` | 140 | Typed-attribute vocabulary for menus. |
| `Lsp/RuitkDotnetLocator.cs` | 202 | Runtime discovery chain (env var → local config → PATH → standard roots). |
| `Lang/BuilderLanguage.cs` | 144 | Typed facade over the language DLL for hot-path parse/print — anything that must not pay an LSP round trip. |
| `Lang/BuilderStyleSurface.cs` | 163 | Style-key vocabulary, **reflected from the real typed Style surface** so a menu can never offer a key the type lacks. |
| `Lang/BuilderText.cs` | 47 | Buffer-text primitives shared by every edit path. |

---

## 4. Feature inventory

Each item names the behaviour, then where to read it.

### 4.1 Entry points

1. **Menu item** → opens empty on a start screen ("Start a UI") offering the
   four module kinds. The tree lives entirely in memory; the first Save asks
   for a folder.
2. **Right-click a `.uitkx` asset → "Open in RUITK UI Builder"** → resolves the
   file's tree root and opens the whole connected tree, not just that file.
3. **Right-click a `.uxml` asset → "Convert UXML to UITKX"** → one-way import.

Double-clicking an asset still opens the external editor. Deliberate.
→ `BuilderMenu.cs`

### 4.2 The canvas

**Cards.** One per module. Four kinds — component, style module, hook module,
util module — each with an accent colour and badge. Sections top to bottom:
title bar, signature (name + full props signature, syntax-coloured), IMPORTS,
BODY (hooks & state), RETURN (markup rows); style/util cards show per-export
entries instead. Position is dragged by the **title bar only** (the body is not
a drag handle) and persisted per tree.

**Zoom layers (LOD).** Three bands, driven by zoom, selectable from a labelled
toolbar dropdown:

| Layer | Label | Zoom preset | LOD threshold | Card width | Shows |
|---|---|---|---|---|---|
| 1 | Architecture | 0.30 | `< 0.32` | 300 | Name + kind pill, and edges. The architecture diagram. |
| 2 | Cards | 0.75 | `< 0.80` | 340 | Signature, imports, hook chips, markup rows. |
| 3 | Edit | 1.25 | `>= 0.80` | 430 | Adds per-row attributes, code islands, directive badges, style entries — and this is the layer where things are clickable-to-edit. |

Zoom range **0.10 – 2.2**; wheel zooms about the cursor; `Ctrl+wheel` over a
scrolling section zooms the canvas instead of scrolling that section. Drag on
empty canvas pans. One mapping table keeps labels, presets and the active index
from drifting (**UB-40**).
→ `BuilderCanvasHost.cs` (`LodOf`), `BuilderCanvasDrawing.cs`
(`ZoomMin`/`ZoomMax`/`CardWidthFor`), `BuilderWindow.cs` (`s_layerLabels`,
`s_layerZooms`)

**Edges.** Bezier, one per import row plus one per markup row that instantiates
another module. Anchor dots sit in a column **on the card's right border**, one
per referencing row; each edge leaves its own dot and arrives at the target
card's top-left, so a curve never crosses the card's own content and every dot
has a visible line (**UB-103**, **UB-107**). Painted in a **screen-space
overlay** so stroke weight is constant at every zoom.
→ `BuilderCanvasDrawing.cs`

**Culling.** Cards more than one viewport outside the visible rect render as a
sized empty box. Pure performance; invisible except as responsiveness
(**UB-81**).

### 4.3 Folder structure and naming — **newer than the capabilities doc**

A component owns a folder named after it. Its children live in a `components/`
folder inside it. Its **companions** — style and hook modules — sit *beside* it,
not below.

```
Assets/UI/NewComponent/
  NewComponent.uitkx            <- tree ROOT
  newComponent.style.uitkx      <- companion
  useNewComponent.hooks.uitkx   <- companion
  components/
    LeftSide/
      LeftSide.uitkx
      leftSide.style.uitkx
    RightSide/
      RightSide.uitkx
      components/
        Badge/Badge.uitkx       <- nests the same way at any depth
```

| Kind | File name | Placement |
|---|---|---|
| Component | `PascalCase.uitkx` | own folder, under parent's `components/` |
| Style module | `camelCase.style.uitkx` | beside its component |
| Hook module | `useSomething.hooks.uitkx` | beside its component |
| Util module | `camelCase.uitkx` | beside; defaults to the tree root (shared until proven otherwise) |

**Families.** `NewComponent.uitkx`, `newComponent.style.uitkx` and
`useNewComponent.hooks.uitkx` are one family — same name, three roles, one
folder. A new companion is routed into its component's folder wherever that
component lives. Because companions are siblings rather than pooled,
`Card/button.style.uitkx` and `Panel/button.style.uitkx` coexist.
→ `Document/BuilderNaming.cs`

**Where a new module is born** — determined by *where you right-click*, never by
what is focused:

| Right-click on | Component | Style / hook / util |
|---|---|---|
| Empty canvas | tree root: `Root/components/Name/Name.uitkx` | tree root: `Root/` (unless the name matches a family, which redirects) |
| A component card | **child**: `Parent/components/Name/Name.uitkx` | **sibling**: `Parent/` |
| A companion card | no create menu — a style module has no children | — |

> **Why not focus-relative:** the shipped 0.17.0 rule placed new modules
> relative to the focus, and creating a module also focuses it. Three
> components created in a row therefore nested three deep. The structure
> recorded the order of the user's clicks rather than anything about their UI.
> This is worth not re-deriving. → `BuilderWindow.cs` `BirthPathFor`

**What moves a module.** Nothing, unless a gesture says so. Removing an import
does not move a file. A **drag in the folder tree** re-files by type (component
→ `Target/components/Name/`, companion → `Target/`) and rewrites the specifiers
of everything that already imports it, each from its own position. It adds and
removes **no** imports.

> A rule considered and **rejected**: having a shared module climb to the
> closest common parent as more things use it. In a deep tree it moves files
> out from under the user.

### 4.4 Reading a tree

- The tree is discovered from the focus file by walking imports. The **language
  server** supplies the on-disk inventory and, for untouched modules, what they
  import — a cheap cache derived from the same text. For anything the builder
  holds differently from disk (created, renamed, or merely edited) the server
  is stale **by definition**, and that module's own buffer is parsed instead.
  A module is therefore wired into the tree the moment its import is typed,
  with no file behind it.
- Card content is parsed from the **real AST**, never regex: signature,
  exports, imports, hook calls, markup structure, and all five directive
  families (`@if`/`@else if`/`@else`, `@foreach`, `@for`, `@while`,
  `@switch`/`@case`/`@default`).
- Directive heads and clauses render as their own badged rows, children
  indented beneath.
- Hook chips show the hook name and the state names it returns; hovering one
  highlights every usage in the markup rows **and** the source pane.

→ `Canvas/BuilderGraphService.cs`

### 4.5 Editing

Every canvas edit is a text edit on the buffer, through **one funnel** that
re-parses the card, re-syncs the language server, and records an undo entry.

**Inline editors.** One floating editor serves every surface: attribute values,
directive headers, hook chips, style entries, code islands (multiline), element
rows. It carries syntax colouring, `Ctrl+Space` completion mapped to the exact
file position, and overlay diagnostics. It takes the **size and position of the
thing it edits** at any zoom. Enter commits (`Ctrl+Enter` in a code island),
Escape cancels, clicking away commits. Escape on an editor the builder *seeded*
(a fresh wrap or clause) also undoes the seeding. Focus never selects the whole
text, so the first keystroke cannot wipe it (**UB-97**).
→ `Controls/BuilderInlineEditorOverlay.cs` — and **UB-76, 84, 92, 99, 100, 101,
106, 108** are all this one control. Budget for it.

**Structural operations** (all from context menus):
- Add attribute — searchable, typed from the schema for native elements and
  from declared props for components; free-text fallback.
- Remove attribute — by name, or by emptying its value.
- Add child element — searchable element list.
- Wrap in… — the five directives, seeded **compile-clean** (`@if (true)`,
  `@for (int i = 0; i < 1; i++)`, `@while (false)`, `@switch (0)` + `@case 0:`)
  then the header editor opens (**UB-72**).
- Clause management — `@else`/`@else if` on an `@if`; `@case`/`@default` on a
  `@switch`. New cases insert **above** `@default`; new labels are the next
  unused integer (**UB-71**).
- Unwrap a single-clause directive, keeping its children.
- Add hook / add code — BODY carries `+ hook` (seeds `useState`) and `+ code`
  (seeds a plain statement) chips, both opening the inline editor, so custom
  body logic never requires the source pane (**UB-117**).
- Add style/util export; add style entry with searchable keys and value helpers
  (`Px`/`Pct`/`Hex`/`Rgba`/flex/justify/align/font/text/display/position).
- Apply a style module by dragging it onto an **element row**: sets the
  element's `style` attribute to the chosen export and adds the import if
  missing, as **one** undoable action. Multiple exports → asks which. Dropped on
  the card instead, it adds the import alone.
- **Rename module** — renames the export, the file, the folder when the module
  owns one, and every importer's specifier and binding across the tree,
  including importers never opened. A component that owns its folder takes the
  **whole folder** with it — sub-components, companions, and files the builder
  does not manage — as a single move, so child asset identities survive. Pending
  like everything else; one undo reverses the whole rename; the saved card
  layout follows it out and back.
- Import `.uxml` — one-way conversion; the result arrives as a pending module.
- Create module — see §4.3.

**Menus.** Rebuilt as a **layer in the builder's own panel** rather than a
native popup window: real submenus, the builder's own styling, nothing to lose
focus to, and full keyboard drive (arrows, Enter, Right opens a submenu, Left/
Escape backs out one level, Escape again closes). Long vocabularies — style
keys, elements — keep a **searchable** form instead, which a plain dropdown
cannot express. Three designs were tried and rejected before this; the rejected
ones and why are in the class doc.
→ `Controls/BuilderContextMenu.cs`, `Controls/BuilderSearchMenu.cs`

### 4.6 Drag and drop

Drop target is decided by **band within the row**: `< 30%` = before, `> 70%` =
after, middle = inside.

- **middle band** — tinted outlined box over the row: appended **inside** as its
  last child.
- **bottom band** — dashed caret in the gap under the row: if the next listed
  row is deeper, the element becomes that row's **first child**; otherwise it
  lands after the row's whole block. Both are the same point on screen
  (**UB-110** — the caret must mean what the drop does).
- **top band** — dashed caret above: inserted before it as a sibling.

Hooks drop onto BODY; style/util modules drop onto a card and add the import.
Existing markup rows drag to reorder or re-parent, moving their whole line range
with re-indentation; directive heads move their entire block.

Mechanics: arm on pointer-down, 5px travel threshold before it counts as a drag,
a ghost chip (`PickingMode.Ignore`, offset +14/+10 from the cursor), hit-test
from the **captured pointer stream** — never from render-state closures
(**UB-31**).
→ `Library/BuilderDragService.cs`, `BuilderCanvasHost.cs` (`HitTest`),
`BuilderWindow.cs` (`OnCanvasRowDrop`)

> **⚠ Known open defect.** Moving an *existing* element into another element is
> reported as "hard to impossible", while adding the same element from the
> library works well. Not root-caused as of 0.18.1. The move path now reports
> every outcome (including refusals, which used to be silent) so the next
> attempt produces evidence. **Do not assume the Unity drag model is correct
> here** — see §8.3 for the leading suspicion.

### 4.7 Selection and keyboard

Exactly one thing is selected at a time: a card, a markup row, or a line-backed
item (hook chip, import row, code island, style entry). Selection is always
visible — a warm band and accent outline.

| Key | Action |
|---|---|
| `Delete` | removes the selection: an element row, a directive clause, a whole directive block, a hook/import/island/entry line range, or — falling through to the card — the module itself |
| `Escape` | cancels the innermost active edit, then clears the selection |
| `Ctrl+S` | save |
| `Ctrl+Z` / `Ctrl+Shift+Z` / `Ctrl+Y` | undo / redo |
| `Ctrl+Click` (preview) | jump to the component that rendered that element |

Delete and Escape are inert while a text surface holds focus, so Delete still
deletes characters inside an editor. All builder shortcuts are consumed by the
window and never reach the host editor's globals (**UB-89**).

> **⚠ Portable hazard, worth reading before you write any key handling.** The
> window registers `KeyDownEvent` on the panel root and consumes with
> `StopImmediatePropagation`, which in UI Toolkit also drops callbacks still
> queued **on that same element** — so any handler registered later (a menu, an
> overlay) silently never runs for a consumed key. It presented as *one key
> doing nothing while its neighbours worked* (**UB-219**). Whatever the Godot
> equivalent is, decide the arbitration model up front rather than discovering
> it. → `BuilderWindow.cs` `ConsumeKey`, and its registration site — both carry
> the warning in place.

### 4.8 Save, abort, history, crash cover

**Save** formats every dirty buffer through the AST formatter (a deliberate
save-time pass, not per keystroke), then writes them in **one batch** — one
script reload for the batch instead of one per file, and **zero** reloads when
hot-reload mode is active. It performs planned moves and the import-specifier
rewrites that keep them consistent.

It **asks first** about anything irreversible:
- Deletion: names every file, and they go to the OS trash rather than being
  erased (**UB-88**).
- Empty modules: an empty `.uitkx` is not an empty file but a **broken** one —
  the language requires a top-level declaration, so the project stops compiling
  on the next import. Clearing a module while working is fine; *writing* it is
  where the builder stops and asks (**UB-206**).

**A brand-new tree** has no folder, so the first Save asks once and moves the
whole pending tree before writing. Until then modules live at a **provisional
root the asset database cannot see**:
`<project>/Assets/__RuitkBuilderUnsaved__~/` — the trailing `~` is the Unity
convention for "ignore this folder", chosen so a half-finished tree can never be
picked up by a compile. The relocation is **planned in full** first, so a name
collision cancels the whole move rather than leaving half the tree in the new
folder (**UB-120**, **UB-178**).
→ `BuilderWorkspace.UnsavedRoot`, `BuilderWindow.ResolveUnsavedLocation`

**Abort** discards every unsaved buffer and puts **paths** back as well as text:
a renamed module returns to its old name, and a module that rode along inside a
renamed folder returns with it.

**History panel** lists every action, newest first, with a live cursor; clicking
a row replays whole entries to that point — the same path undo/redo use, so a
jump across a rename or a delete moves the tree and not just the text. Redo is
truncated by new work.

**Crash cover.** The tree is journalled while working (throttled) and dumped
unthrottled before a domain reload — to
`<project>/UserSettings/RuitkBuilderTree.json`, **outside** the assets, because
it must survive what serialization cannot. If the builder ever comes up empty
beside a journal, it offers the work back; a clean session leaves no journal.
→ `Document/BuilderReloadJournal.cs`

**Trace** toggle: a running log of what the preview pipeline considered for
rebuild, what it rebuilt, and why. Off by default. This was added because a
four-round guessing loop (**UB-203**) became solvable the moment it produced
evidence — see §8.1.

### 4.9 Layout persistence

Card positions and the camera are **per-user preferences, not project content**,
so they live outside the assets:
`<project>/UserSettings/ReactiveUIToolkit/Builder/<sha1-8>.json`, one file per
tree.

- Written **immediately** on drag, not on Save — a layout is not project
  content, so it is outside the save-only contract.
- A slot is **decided once and then remembered**. The default layout is a
  breadth-first walk whose answer depends on the node *set*, so without this,
  adding one module moved every card the user had never dragged (**UB-180**).
- Renaming, moving or re-filing carries the layout with the files.
- The tree is identified by **membership**, not by its derived root: the root is
  computed from folder structure, so a re-filed folder can elect a different
  head and the by-root lookup misses entirely (**UB-221**).

→ `Canvas/BuilderCanvasConfig.cs`

### 4.10 Source pane

Full file with syntax colouring, line banding, and a diagnostics console.
Bidirectional: editing re-parses into the model and updates the card; canvas
edits regenerate the source. Colouring comes from language-server semantic
tokens (markup structure plus merged C# classification) with a **lexical
fallback** so identifiers, types, members, calls and numbers are always coloured
even when tokens are unavailable. Edit mode keeps the coloured listing visible
under a **transparent-ink input**, so text stays coloured while being typed —
this is the trick worth stealing. `Ctrl+Space` completes; `Ctrl+Enter` applies.
Clicking a markup row scrolls the pane to that line (vertically only —
**UB-86**). The console is scrollable, selectable, holds every diagnostic, and
supports `Ctrl+A`/`Ctrl+C` plus copy-all (**UB-77**).
→ `Controls/CodeField.cs`

### 4.11 Preview pane

Live-renders the focused component by compiling the current **buffers**
in-process (in import-graph order) and mounting the result through the **real
reconciler** — same adapters, same typed styles that ship in the game. It runs
on its **own frame-budgeted scheduler**, never the global editor one, because
the global queues are process-wide statics with no time budget.

Primitive props become **knobs**. `Ctrl+Click` an element maps it to the
component that rendered it. Compile failures are reported loudly and the last
good preview is kept rather than showing a stale tree silently (**UB-15**).
Hook modules show their signature and consumers instead of a preview. Edits
debounce ~0.3s before recompiling.
→ `Preview/BuilderPreviewPane.cs`, `Preview/BuilderRenderScheduler.cs`,
`Compile/BuilderPreviewCompiler.cs`

### 4.12 Library pane

Searchable palette in sections: native elements (from the schema), hooks,
custom components, style modules, util modules, hook modules. Entries drag onto
the canvas. Double-clicking a workspace entry **frames** its card — solves the
zoom so the card fills the viewport, then centres. `+ new` creates at the tree
root.
→ `Library/BuilderLibraryPane.cs`

### 4.13 Diagnostics

Three tiers, merged into the source console and the card overlays:

1. Structural parse/validation diagnostics (`UITKX####`).
2. Unknown element / unknown attribute checks, resolved against the schema
   **unioned with the runtime element registry** — so a registered element is
   never reported unknown because the schema lags (**UB-75**). There is a
   session-once drift warning when the two disagree.
3. Compile errors from the preview compile.

### 4.14 Read-only sources

Files in immutable packages open read-only: they render on the canvas and in the
preview but cannot be edited or saved.

---

## 5. External seams the builder depends on

The builder is not self-contained. Each of these is a place where the Godot leg
must have *something*, and the shape of what it has will drive the port more
than anything in `Builder/` itself.

| Seam | Unity implementation | What the builder needs from it |
|---|---|---|
| **Language services** | `Ruitk.Language` DLL, referenced directly | Parse to AST, print AST back to text, format. Hot path — must not pay IPC. → `Lang/BuilderLanguage.cs` |
| **Language server** | `.uitkx` LSP over stdio, one shared instance per session | Four custom requests: `ruitk/schema`, `ruitk/hooks`, `ruitk/componentProps`, `ruitk/workspaceGraph` (with import-specifier resolution and an **unsaved-buffer overlay** so open-editor content is visible to element/props/graph intelligence). Plus standard completion/hover/semantic-tokens/diagnostics. → `Lsp/` |
| **Element registry** | `ElementRegistry.RegisteredNames` | The runtime truth about what can render, unioned with the schema for tier-2 diagnostics. |
| **Hot module replacement** | `Editor/HMR/UitkxHmrCompiler` + a `SourceOverlay` seam | Compile the **unsaved buffer** rather than the file on disk. This seam exists solely for the builder. |
| **Reconciler + host** | `EditorRootRendererUtility`, `VNodeHostRenderer` | Mount a component tree into an editor-owned surface, and map a rendered element back to its owning component (a `Family` walk plus a source attribute). |
| **Runtime discovery** | `Lsp/RuitkDotnetLocator.cs` | `$RUITK_DOTNET` → `.ruitk-local.json` → bundled → PATH → standard roots, erroring with all of them named. The repo's canonical chain. |

> **The single highest-risk seam is the preview.** It needs to compile
> *in-memory buffers* and mount them through the real renderer, in the editor,
> without a full domain reload. Whatever Godot's equivalent is (or whether one
> exists) probably determines how much of the builder is portable. Investigate
> this **before** committing to a plan.

---

## 6. The defect register — read this, it is the cheapest lesson available

`../ruitk-unity/Plans~/UI_BUILDER_BUGS.md` holds ~221 entries. Do not read it
end to end; read these clusters, because each one cost multiple rounds:

| Cluster | Ids | Lesson |
|---|---|---|
| Preview correctness | UB-190, 194, 198, 202, **203**, 205 | See §8.1. |
| Save contract | UB-87, 88, 111, 120, **178**, 204, 206 | Every one is "a caller forgot to set a flag". Fixed structurally by §2.2. |
| Canvas layout | UB-180, 185, **220**, **221** | Layout keyed by a *derived, unstable* identity. See §4.9. |
| Inline editor | UB-76, 84, 92, 97, 99, 100, 101, 106, 108 | One control, nine defects. Sizing, focus and zoom are the hard parts. |
| Drag/drop | UB-30, 31, 32, 109, 110, and the open move defect | Feedback and caret-means-what-it-does. |
| Menus | UB-122, 126, 215, 216, 217, 218, **219** | Keyboard, submenus, and the key-arbitration hazard in §4.7. |

---

## 7. Known non-capabilities

Recorded so the port does not go looking for them:

- The canvas is dogfooded `.uitkx`; the surrounding chrome is hand-built. Full
  dogfooding is a planned future pass, not a shipped state.
- **No multi-select.** Exactly one thing is selected at a time.
- **No automatic graph layout** ("tidy"). Card positions are manual and
  persisted.
- No rename-across-files refactor from the canvas beyond the module rename in
  §4.5.
- `@uss` / asset references added since the last Save resolve only after saving
  — the asset cache is disk-gated. This is the one acknowledged preview
  limitation.
- Moving an existing element into another element is unreliable (§4.6).

---

## 8. Three things the Unity leg got wrong, so you can skip them

### 8.1 Ask "what is no longer valid", not "what changed"

The most expensive defect in the campaign (**UB-203**) took four rounds. Style
edits never rendered in the preview. Three real, separate defects were found and
fixed on the way — none was the cause. The actual cause: the hot-swap unit
builder only inlined an imported module's exports when the type existed in no
referenceable assembly, and a style module saved *once* always exists there, so
the importer bound to the **saved** copy forever.

Two lessons, both structural:

1. **The tell was in the report and was read past.** "Never applies" is a
   different question from "applies late". When a symptom and a hypothesis
   disagree on kind, the hypothesis is wrong.
2. **Instrument before guessing.** The Trace toggle (§4.8) converted an
   unfalsifiable guessing loop into evidence and found the answer on its first
   run. Build the observability *before* the third hypothesis, not after.

The same shape recurs across the register: the right question was rarely "what
changed" — it was "what is no longer valid", "what moved", "what is no longer
addressable".

### 8.2 Guard the point of decision, not the call site

Nearly every save-contract defect (UB-87/88/111/120/178) was a caller failing to
set a flag. The fix that ended the class was not more careful callers; it was
deriving the state (§2.2). When you find yourself adding a guard to a third call
site, the model is wrong.

### 8.3 A dogfooded canvas inherits the framework's re-render semantics

The canvas being a real component is excellent for dogfooding and is a live
hazard for **pointer interaction**. Rows are recreated by re-render, and a
pointer capture taken on a row element is only as stable as that element. This
is the leading unproven suspicion behind the open drag defect in §4.6: pressing
a row calls several state setters (selection, row index, line key) which trigger
a re-render *on the very gesture that arms the drag*.

If Godot's reactive layer has the same property, **capture on a stable host**
(the canvas container) rather than on the volatile row, and resolve the target
by hit-test. Decide this before building drag, not after.

---

## 9. What this guide adds over `UI_BUILDER_CAPABILITIES.md`

Both files were brought current on 2026-08-27, so they no longer disagree.
They divide as follows:

| | `UI_BUILDER_CAPABILITIES.md` | this guide |
|---|---|---|
| Scope | behaviour a user can observe | behaviour + implementation + rationale |
| File paths | none, deliberately | throughout (§3) |
| Seams and dependencies | none | §5 |
| Defect history | none (lives in the register) | §6, §8 |
| Rejected designs and why | rarely | §2, §4.3, §8 |
| Maintenance | required by a skill, per commit | point-in-time; verify against code |

The practical consequence: `UI_BUILDER_CAPABILITIES.md` will stay accurate as
the Unity leg moves; this guide will not. **When they disagree, that file is
right about behaviour and this one is still useful for where to look** — but
confirm any surprising claim against the code, because both are documentation
and only the code is the artifact.
## 10. Suggested order of investigation

Not a plan — a reading order that front-loads the decisions that constrain
everything else.

1. **`UI_BUILDER_CAPABILITIES.md`** end to end (422 lines). Behaviour, no code.
2. **§5 of this file**, then determine what the Godot leg has for each seam.
   Answer the preview question first (§5, final note) — it has the largest
   blast radius.
3. **`Builder~/ModelTests/`** and `Document/`. The document model is
   engine-agnostic and is the natural first port; the tests come with it.
4. **`Plans~/BUILDER_TREE_MODEL.md`** for the model's rationale and the
   placement convention's full argument.
5. **`CanvasView.uitkx`** to see how much of the canvas is expressible in the
   framework's own markup, since that determines how much transfers.
6. **The defect clusters in §6**, filtered to whatever you are about to build.
7. `BuilderWindow.cs` last, and by search rather than by reading — it is 6321
   lines and is mostly handlers you will want to look up one at a time.

---

## 11. Keeping this current

The Unity leg has a skill that requires `plans/UI_BUILDER_CAPABILITIES.md` to be
updated in the same commit as any user-noticeable change under `Builder/`
(`../ruitk-unity/.claude/skills/uibuilder-capabilities/`). That discipline
slipped during the 2026-08 campaign, which is why §9 exists.

If you need a fact this guide does not have, prefer, in order: the code, the
defect register, then the capabilities file — and treat any date-stamped
document as a claim to verify rather than a fact.

<!-- Written 2026-08-27 against ruitk-unity @ feat/ruitk-builder, package 0.18.1. -->
