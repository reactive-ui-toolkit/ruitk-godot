# Godot Control inventory — every official Control class, accounted for

**Coverage target: ALL official runtime Control classes registered in ClassDB** (Godot
**4.7-stable**, the version this repo is verified on — 76 Control-derived classes from a live
`ClassDB.get_inheriters_from_class("Control")` dump, run headless against this project on
2026-07-11), plus the non-Control scene nodes the library deliberately wraps (audio/video/popup).
Editor-module Controls (`ClassDB.class_get_api_type() == EDITOR`) are out of scope, the same way
the Unreal port (plans/MASTER_PLAN.md D-33 there) excludes editor-module Slate widgets.

This file is the authoritative tracking artifact: **every Control class from the dump appears in
exactly one table.** A class with no row here is a dump bug, not a scope decision. Re-run the dump
against every new Godot minor and diff this file — a new engine Control must land a row here in
the same PR that bumps the verified engine version.

**Structural coverage note (read first).** Unlike the Unity/Unreal siblings, this port has a
*generic host path*: `V.h("AnyClassName", props)` instantiates any ClassDB class, plain props are
applied verbatim via `node.set(prop, value)` (exact Godot property names), any signal is reachable
via `on_<signal>` / `onPascalCase`, and any theme item is reachable via the six generic style
channels (`colors`/`constants`/`fonts`/`font_sizes`/`icons`/`styleboxes`). So *capability*
coverage is already ~100%. What this inventory tracks is the **curated** surface: a named `V.*`
factory, a `.guitkx` tag, IDE metadata (completion/hover/events), item-model adapters, and tests.

**Naming rule (APPROVED + SHIPPED in 0.9.0, see plans/NAMING_LOYALTY_PROPOSAL.md):** element tag
= the official Godot class name, verbatim — and ANY instantiable ClassDB Node class is a valid
tag (open vocabulary, emitted as `V.h`); factories match tags verbatim (`V.VBoxContainer`); props
= exact Godot property names; events = `on` + PascalCase(signal name); style keys = the exact
Godot property / theme-item / StyleBoxFlat names.

Statuses: `SHIPPED` (named factory + tag + demo/test coverage on dev) · `BATCH-1` (0.9.x
production line — everyday set) · `BATCH-2` (long tail / needs a dedicated design) · `BASE`
(instantiable base class — reachable generically, no named row needed) · `ABSTRACT` (cannot
instantiate — nothing to wrap) · `SPECIAL` (covered by a dedicated mechanism, not a plain
element) · `EDITOR` (editor-module — excluded by scope decision).

---

## Shipped — 44 Control classes + 2 non-Control nodes

Tags below are the **shipped 0.9.0 names** (= Godot class names). "own props / own signals /
theme items" are the class's own (non-inherited) counts from the 4.7 ClassDB/ThemeDB dump — the
surface the generic passthrough reaches; the *Adapter / special-case* column records everything
that is NOT plain passthrough.

| Godot class | Tag (0.9.0) | own props / signals / theme items | Adapter / special-case notes |
|---|---|---|---|
| Control | `Control` | 58 / 12 / 0 | the base leaf; `draw_fn`/`redraw_key` custom-draw trampoline applies to any CanvasItem |
| VBoxContainer | `VBoxContainer` | 0 / 0 / 1 | |
| HBoxContainer | `HBoxContainer` | 0 / 0 / 1 | |
| GridContainer | `GridContainer` | 1 / 0 / 2 | |
| MarginContainer | `MarginContainer` | 0 / 0 / 4 | capacity warn: lays out 1 child |
| PanelContainer | `PanelContainer` | 0 / 0 / 1 | primary stylebox slot `panel`; capacity warn: 1 child |
| CenterContainer | `CenterContainer` | 1 / 0 / 0 | capacity warn: 1 child |
| ScrollContainer | `ScrollContainer` | 12 / 2 / 6 | capacity warn: 1 child |
| HFlowContainer | `HFlowContainer` | 0 / 0 / 2 | |
| VFlowContainer | `VFlowContainer` | 0 / 0 / 2 | |
| TabContainer | `TabContainer` | 11 / 7 / 30 | |
| HSplitContainer | `HSplitContainer` | 0 / 0 / 6 | capacity warn: 2 children |
| VSplitContainer | `VSplitContainer` | 0 / 0 / 6 | capacity warn: 2 children |
| AspectRatioContainer | `AspectRatioContainer` | 4 / 0 / 0 | capacity warn: 1 child |
| FoldableContainer | `FoldableContainer` | 8 / 1 / 18 | capacity warn: 1 child |
| Label | `Label` | 22 / 0 / 12 | text-folding tag (all-text children → `text` prop); `V.text()` leaf |
| RichTextLabel | `RichTextLabel` | 30 / 4 / 33 | text-folding tag |
| ColorRect | `ColorRect` | 1 / 0 / 0 | |
| TextureRect | `TextureRect` | 5 / 0 / 0 | |
| NinePatchRect | `NinePatchRect` | 9 / 1 / 0 |  |
| HSeparator | `HSeparator` | 0 / 0 / 2 | |
| VSeparator | `VSeparator` | 0 / 0 / 2 | |
| Button | `Button` | 13 / 0 / 24 | text-folding tag; primary stylebox slot `normal`; state slots hover/pressed/disabled/focus |
| CheckBox | `CheckBox` | 0 / 0 / 28 | as Button |
| CheckButton | `CheckButton` | 0 / 0 / 28 | as Button |
| OptionButton | `OptionButton` | 8 / 2 / 23 | **items adapter**: `{text, icon, disabled, id}`, selection preserved by identity. Not mapped in the adapter (recorded): separators, per-item tooltips (reachable imperatively via `ref`) |
| MenuButton | `MenuButton` | 2 / 1 / 15 | popup content via `ref` + PopupMenu adapter |
| LinkButton | `LinkButton` | 9 / 0 / 10 | text-folding tag |
| TextureButton | `TextureButton` | 10 / 0 / 0 | |
| LineEdit | `LineEdit` | 36 / 4 / 18 | controlled-input caret preservation on `text`; primary stylebox `normal`; state slot `read_only` |
| TextEdit | `TextEdit` | 47 / 7 / 24 | controlled-input caret preservation on `text` |
| CodeEdit | `CodeEdit` | 22 / 5 / 48 | inherits TextEdit handling |
| SpinBox | `SpinBox` | 8 / 0 / 31 | |
| HSlider | `HSlider` | 0 / 0 / 10 | |
| VSlider | `VSlider` | 0 / 0 / 10 | |
| ProgressBar | `ProgressBar` | 4 / 0 / 7 | primary stylebox slot `background` |
| TextureProgressBar | `TextureProgressBar` | 16 / 0 / 0 |  |
| ColorPicker | `ColorPicker` | 12 / 3 / 27 |  |
| ColorPickerButton | `ColorPickerButton` | 3 / 3 / 16 |  |
| TabBar | `TabBar` | 14 / 8 / 29 | **items adapter**: `{text, icon, disabled}`, current tab preserved by identity. Not mapped (recorded): per-tab tooltips, close/right buttons — reach via `ref` |
| ItemList | `ItemList` | 18 / 5 / 24 | **items adapter**: `{text, icon, disabled, selectable, id}`, selection preserved as a multiset by identity. Not mapped (recorded): per-item tooltips, custom fg/bg colors, per-item metadata beyond `id` |
| Tree | `Tree` | 16 / 15 / 77 | **items adapter**: hierarchical `{id, text, children, collapsed}` + `columns`/`hide_root`; expansion+selection preserved by `id`. Not mapped (recorded): multi-column cell content, per-cell icons/buttons/editable cells/custom draw, column titles — reach via `ref` |
| MenuBar | `MenuBar` | 6 / 0 / 15 | menus are child PopupMenus |
| VideoStreamPlayer | `VideoStreamPlayer` | 10 / 1 / 0 | `V.VideoStreamPlayer` (media subsystem); childless |
| — AudioStreamPlayer *(Node, not Control)* | `AudioStreamPlayer` | 10 / 1 / 0 | `V.AudioStreamPlayer` (media subsystem, + `useSfx` for one-shots); childless |
| — PopupMenu *(Window, not Control)* | *(no tag)* | 14 / 4 / 37 | **items adapter only** (reached via MenuButton/OptionButton `ref` or `V.h`): `{text, id, disabled, checkable, checked, separator}`. Not mapped (recorded): icons, submenus, radio items, accelerators/shortcuts, tooltips |

**Shipped-element prop/signal/theme coverage — the recorded decisions:**

1. **Properties: 100% by passthrough.** Every registered property of every shipped class is
   settable as a plain prop with its exact Godot name (`node.set`). The only interceptions are
   `text` on LineEdit/TextEdit (caret preservation — deliberate, name-loyal) and the framework
   props (`key`, `ref`, `style`, `classes`, `items`, `draw_fn`, `redraw_key`, `reuse_by_slot`),
   which are reserved and never applied to the node. *Known constraint (kept, faithful to
   reference): a removed plain prop is not reset to its class default on the next render;
   events/style/refs/draw are.*
2. **Signals: 100% by passthrough.** Any signal of any element is bindable via `on_<signal>`
   (verbatim) or `onPascalCase` (generic camel→snake). The 11 React-style aliases
   (`onClick`, polymorphic `onChange`, `onInput`, `onSubmit`, `onFocus`, `onBlur`,
   `onPointerDown/Up/Enter/Leave`, `onResize`) are the naming-loyalty deviation — removal proposed
   in plans/NAMING_LOYALTY_PROPOSAL.md. IDE event completion currently lists only curated aliases
   on 17 tags; 0.9.0 derives completions for *every* signal of *every* tag from the bundled
   ClassDB dump (which already carries signals).
3. **Theme/style: 100% by the generic channels.** All 700+ theme items across shipped classes are
   reachable via `colors`/`constants`/`fonts`/`font_sizes`/`icons`/`styleboxes`. The *flat* style
   shorthands cover a curated subset; the box builder writes only the class's **primary** stylebox
   slot (PanelContainer/Panel→`panel`, Button family & LineEdit/TextEdit→`normal`,
   ProgressBar→`background`; others warn once) and the per-state slots `hover`/`pressed`/`focus`/
   `disabled`/`read_only` (already the exact Godot theme item names). Non-loyal flat keys
   (`tooltip`, `clip`, `pivot`, `outline_color`, `pad`, degree-based `rotation`, size-flag
   aliases) are renamed/re-specified in the naming proposal.
4. **Item-model controls:** the five adapters intentionally map the *declarative-safe* subset of
   item fields (tables above). Everything else on items is imperative-API-only in Godot
   (`set_item_*`) and is reachable via `ref` — a recorded decision, not a gap. Adapters are
   user-extensible via `RUIHost.register_item_adapter`.

---

## Batch 1 — SHIPPED with 0.9.0 (named factory + tag + IDE metadata; exercised by the
## open-vocabulary/instantiation tests — per-widget demos ride the gallery backlog)

| Godot class | Notes |
|---|---|
| Panel | plain themed rectangle. The pre-0.9 `Panel` tag meant PanelContainer — **repointed at 0.9.0**; the codemod rewrites old usages |
| ReferenceRect | debug outline rect — trivial leaf |
| HScrollBar / VScrollBar | standalone scrollbars (Range subclasses); `onValueChanged` |
| SubViewportContainer | 3D-in-UI / viewport embedding; pairs with a docs recipe |
| BoxContainer | instantiable base with `vertical` prop — the official generic box |
| FlowContainer | instantiable base with `vertical` prop |
| SplitContainer | instantiable base with `vertical` prop; capacity 2 |
| VirtualJoystick | new Control in Godot 4.7 — touch joystick |

## Batch 2 — long tail / needs a dedicated design

| Godot class | Notes |
|---|---|
| GraphEdit | node-graph surface — needs a slot/port story (connections, popups); the family's biggest remaining design |
| GraphNode / GraphFrame / GraphElement | GraphEdit children (GraphElement is their instantiable base) — same design |
| Window *(Node, not Control)* | true OS/embedded windows — a mount-surface story (`ReactiveRoot`-in-window + portals), like Unreal's `SWindow` SPECIAL row |
| Popup / PopupPanel *(Windows)* | popup surfaces — ride the Window story |
| AcceptDialog / ConfirmationDialog / FileDialog *(Windows)* | dialog family — declarative open/result props on top of the Window story |

## Bases & abstract — nothing to wrap (recorded)

| Class | Why |
|---|---|
| Container | instantiable but layoutless base — useful only for custom containers; reachable via `V.h("Container")` |
| Range | instantiable value-model base of sliders/progress/spinbox — renders nothing itself |
| BaseButton | abstract (`can_instantiate == false`) base of the button family |
| Slider | abstract base of HSlider/VSlider |
| Separator | abstract base of HSeparator/VSeparator |
| ScrollBar | abstract base of H/VScrollBar |

## Editor-module — excluded by scope decision (api_type == EDITOR, none instantiable)

`EditorDock`, `EditorInspector`, `EditorProperty`, `EditorResourcePicker`, `EditorScriptPicker`,
`EditorSpinSlider`, `EditorToaster`, `FileSystemDock`, `ScriptEditor`, `ScriptEditorBase`,
`OpenXRBindingModifierEditor`, `OpenXRInteractionProfileEditor`,
`OpenXRInteractionProfileEditorBase` — editor chrome, not game UI; the same exclusion every
sibling port makes.

---

**Count check (4.7-stable dump):** 44 shipped + 9 Batch-1 (H/VScrollBar share a row) + 4 Batch-2
Graph classes + 6 bases/abstract + 13 editor = **76 Control classes** ✓ (Window-family Batch-2
rows are Node/Window classes tracked here deliberately; AudioStreamPlayer and PopupMenu are the
two non-Control nodes the library wraps).

**Process:** each Batch-1/2 element ships through the component pipeline (factory + tag +
vocabulary entry → IDE metadata → adapter if item-model → demo/test → docs row), then its row
moves into "Shipped". The dump script lives with the audit (see also
`addons/reactive_ui_toolkit/dev/classdb_dump.gd`, which feeds the IDE's bundled ClassDB); re-run and diff
on every engine bump.
