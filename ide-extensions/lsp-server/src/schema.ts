// guitkx vocabulary for markup-side completion/hover. The tag NAME set comes from the shared
// vocabulary.json (T0.3 — a byte-identical copy of addons/reactive_ui_toolkit/guitkx/vocabulary.json, the
// single source of truth guitkx.gd also loads; vocab.test.ts enforces the sync). This file keeps
// the per-tag METADATA (godotClass, events) and DERIVES alias entries (VBoxContainer,
// RichTextLabel, …) from the vocabulary, so every tag the compiler accepts gets completion/hover
// and can never be false-flagged unknown. Per-control Godot properties are NOT enumerated here —
// those come from a bundled ClassDB dump (see classdb.ts).

import vocabulary from "./vocabulary.json";

export const VOCABULARY: {
  directives: string[];
  hooks: string[];
  host_tags: Record<string, string>;
  v_factories: string[];
  renamed_tags?: Record<string, string>; // 0.9.0: pre-0.9 shorthand -> official class name (rename hints only)
  severities: Record<string, string>; // T3.2: single severity source per code
  live: string[]; // T3.3: codes the live tier computes (stale sidecar entries for these drop)
} = vocabulary;

export interface TagInfo {
  tag: string;
  godotClass: string;
  factory: string;
  events?: string[];
}

export interface AttrInfo {
  name: string;
  type: string;
  detail: string;
}

// 0.9.0 naming loyalty (MIGRATION-0.9.md): tags ARE the official Godot class names, factories
// match tags verbatim, and events are the native signal with an `on` marker. This list mirrors
// grammar/guitkx-schema.json's hostElements (the curated everyday set); ANY instantiable ClassDB
// Node class is additionally a valid tag (open vocabulary — validated against the bundled dump).
const BASE_TAGS: TagInfo[] = [
  // T2.2: the named alias of `<>...</>` (Unity parity, case-insensitive at the parser). Groups
  // children without a container node; accepts only `key`.
  { tag: "Fragment", godotClass: "Fragment", factory: "V.fragment" },
  { tag: "Control", godotClass: "Control", factory: "V.Control", events: ["onGuiInput", "onResized", "onMouseEntered", "onMouseExited", "onFocusEntered", "onFocusExited"] },
  { tag: "VBoxContainer", godotClass: "VBoxContainer", factory: "V.VBoxContainer" },
  { tag: "HBoxContainer", godotClass: "HBoxContainer", factory: "V.HBoxContainer" },
  { tag: "BoxContainer", godotClass: "BoxContainer", factory: "V.BoxContainer" },
  { tag: "GridContainer", godotClass: "GridContainer", factory: "V.GridContainer" },
  { tag: "MarginContainer", godotClass: "MarginContainer", factory: "V.MarginContainer" },
  { tag: "PanelContainer", godotClass: "PanelContainer", factory: "V.PanelContainer" },
  { tag: "CenterContainer", godotClass: "CenterContainer", factory: "V.CenterContainer" },
  { tag: "ScrollContainer", godotClass: "ScrollContainer", factory: "V.ScrollContainer", events: ["onScrollStarted", "onScrollEnded"] },
  { tag: "FlowContainer", godotClass: "FlowContainer", factory: "V.FlowContainer" },
  { tag: "HFlowContainer", godotClass: "HFlowContainer", factory: "V.HFlowContainer" },
  { tag: "VFlowContainer", godotClass: "VFlowContainer", factory: "V.VFlowContainer" },
  { tag: "TabContainer", godotClass: "TabContainer", factory: "V.TabContainer", events: ["onTabChanged", "onTabSelected"] },
  { tag: "SplitContainer", godotClass: "SplitContainer", factory: "V.SplitContainer", events: ["onDragged"] },
  { tag: "HSplitContainer", godotClass: "HSplitContainer", factory: "V.HSplitContainer", events: ["onDragged"] },
  { tag: "VSplitContainer", godotClass: "VSplitContainer", factory: "V.VSplitContainer", events: ["onDragged"] },
  { tag: "AspectRatioContainer", godotClass: "AspectRatioContainer", factory: "V.AspectRatioContainer" },
  { tag: "FoldableContainer", godotClass: "FoldableContainer", factory: "V.FoldableContainer", events: ["onFoldingChanged"] },
  { tag: "SubViewportContainer", godotClass: "SubViewportContainer", factory: "V.SubViewportContainer" },
  { tag: "Label", godotClass: "Label", factory: "V.Label" },
  { tag: "RichTextLabel", godotClass: "RichTextLabel", factory: "V.RichTextLabel", events: ["onMetaClicked"] },
  { tag: "Panel", godotClass: "Panel", factory: "V.Panel" },
  { tag: "ColorRect", godotClass: "ColorRect", factory: "V.ColorRect" },
  { tag: "TextureRect", godotClass: "TextureRect", factory: "V.TextureRect" },
  { tag: "NinePatchRect", godotClass: "NinePatchRect", factory: "V.NinePatchRect", events: ["onTextureChanged"] },
  { tag: "ReferenceRect", godotClass: "ReferenceRect", factory: "V.ReferenceRect" },
  { tag: "HSeparator", godotClass: "HSeparator", factory: "V.HSeparator" },
  { tag: "VSeparator", godotClass: "VSeparator", factory: "V.VSeparator" },
  { tag: "Button", godotClass: "Button", factory: "V.Button", events: ["onPressed", "onToggled", "onButtonDown", "onButtonUp"] },
  { tag: "CheckBox", godotClass: "CheckBox", factory: "V.CheckBox", events: ["onToggled", "onPressed"] },
  { tag: "CheckButton", godotClass: "CheckButton", factory: "V.CheckButton", events: ["onToggled", "onPressed"] },
  { tag: "OptionButton", godotClass: "OptionButton", factory: "V.OptionButton", events: ["onItemSelected", "onItemFocused"] },
  { tag: "MenuButton", godotClass: "MenuButton", factory: "V.MenuButton", events: ["onAboutToPopup"] },
  { tag: "LinkButton", godotClass: "LinkButton", factory: "V.LinkButton", events: ["onPressed"] },
  { tag: "TextureButton", godotClass: "TextureButton", factory: "V.TextureButton", events: ["onPressed", "onToggled"] },
  { tag: "LineEdit", godotClass: "LineEdit", factory: "V.LineEdit", events: ["onTextChanged", "onTextSubmitted"] },
  { tag: "TextEdit", godotClass: "TextEdit", factory: "V.TextEdit", events: ["onTextChanged"] },
  { tag: "CodeEdit", godotClass: "CodeEdit", factory: "V.CodeEdit", events: ["onTextChanged", "onCodeCompletionRequested"] },
  { tag: "SpinBox", godotClass: "SpinBox", factory: "V.SpinBox", events: ["onValueChanged"] },
  { tag: "HSlider", godotClass: "HSlider", factory: "V.HSlider", events: ["onValueChanged", "onDragStarted", "onDragEnded"] },
  { tag: "VSlider", godotClass: "VSlider", factory: "V.VSlider", events: ["onValueChanged", "onDragStarted", "onDragEnded"] },
  { tag: "HScrollBar", godotClass: "HScrollBar", factory: "V.HScrollBar", events: ["onValueChanged", "onScrolling"] },
  { tag: "VScrollBar", godotClass: "VScrollBar", factory: "V.VScrollBar", events: ["onValueChanged", "onScrolling"] },
  { tag: "ProgressBar", godotClass: "ProgressBar", factory: "V.ProgressBar", events: ["onValueChanged"] },
  { tag: "TextureProgressBar", godotClass: "TextureProgressBar", factory: "V.TextureProgressBar", events: ["onValueChanged"] },
  { tag: "ColorPicker", godotClass: "ColorPicker", factory: "V.ColorPicker", events: ["onColorChanged"] },
  { tag: "ColorPickerButton", godotClass: "ColorPickerButton", factory: "V.ColorPickerButton", events: ["onColorChanged", "onPopupClosed"] },
  { tag: "VirtualJoystick", godotClass: "VirtualJoystick", factory: "V.VirtualJoystick" },
  { tag: "TabBar", godotClass: "TabBar", factory: "V.TabBar", events: ["onTabChanged", "onTabSelected", "onTabClosePressed"] },
  { tag: "ItemList", godotClass: "ItemList", factory: "V.ItemList", events: ["onItemSelected", "onItemActivated", "onMultiSelected"] },
  { tag: "Tree", godotClass: "Tree", factory: "V.Tree", events: ["onItemSelected", "onItemActivated", "onItemCollapsed"] },
  { tag: "MenuBar", godotClass: "MenuBar", factory: "V.MenuBar" },
  { tag: "AudioStreamPlayer", godotClass: "AudioStreamPlayer", factory: "V.AudioStreamPlayer", events: ["onFinished"] },
  { tag: "VideoStreamPlayer", godotClass: "VideoStreamPlayer", factory: "V.VideoStreamPlayer", events: ["onFinished"] },
];

// Every vocabulary tag as a TagInfo: hand-maintained BASE_TAGS carry the metadata; aliases from
// vocabulary.host_tags that BASE_TAGS doesn't name (VBoxContainer -> vbox, …) clone the canonical
// entry with the alias as tag AND godotClass (the long form IS the Godot class name).
export const HOST_TAGS: TagInfo[] = (() => {
  const byFactory = new Map<string, TagInfo>();
  for (const t of BASE_TAGS) if (!byFactory.has(t.factory)) byFactory.set(t.factory, t);
  const known = new Set(BASE_TAGS.map((t) => t.tag));
  const out = [...BASE_TAGS];
  for (const [alias, factory] of Object.entries(VOCABULARY.host_tags)) {
    if (known.has(alias)) continue;
    const base = byFactory.get(`V.${factory}`);
    if (base) out.push({ ...base, tag: alias, godotClass: alias });
  }
  return out;
})();

export const STRUCTURAL_ATTRS: AttrInfo[] = [
  { name: "key", type: "Variant", detail: "Reconciler key — stabilises identity across re-renders/reorders." },
  { name: "ref", type: "Callable|Array", detail: "Forwarded ref — receives the underlying Godot Control once mounted." },
  { name: "style", type: "Dictionary", detail: "Inline style overrides (theme/StyleBox properties)." },
];

export const COMMON_ATTRS: AttrInfo[] = [
  { name: "name", type: "String", detail: "Node name." },
  { name: "visible", type: "bool", detail: "Whether the Control is visible." },
  { name: "tooltip_text", type: "String", detail: "Tooltip shown on hover." },
  { name: "mouse_filter", type: "int", detail: "Control.MouseFilter (0 STOP, 1 PASS, 2 IGNORE)." },
  { name: "size_flags_horizontal", type: "int", detail: "Container size flags (horizontal)." },
  { name: "size_flags_vertical", type: "int", detail: "Container size flags (vertical)." },
  { name: "custom_minimum_size", type: "Vector2", detail: "Minimum size hint." },
];

export interface DirectiveInfo {
  label: string;
  insert: string;
  detail: string;
}

export const PREAMBLE_DIRECTIVES: DirectiveInfo[] = [
  { label: "@class_name", insert: "@class_name ", detail: "Override the generated class name." },
  // T2.3: implemented -- preloads the Theme and applies it to the component's root element
  // (theme prop) unless one is set explicitly. Component files only; one per file.
  { label: "@uss", insert: '@uss "', detail: 'Preload a Theme for the root element: @uss "res://theme.tres" (Unity @uss parity).' },
  { label: "@theme", insert: '@theme "', detail: 'Godot-idiomatic alias of @uss: preload a Theme for the root element.' },
];

export const CONTROL_FLOW: DirectiveInfo[] = [
  { label: "@if", insert: "@if (${1:cond}) {\n\t$0\n}", detail: "Conditional branch." },
  { label: "@elif", insert: "@elif (${1:cond}) {\n\t$0\n}", detail: "Else-if branch." },
  { label: "@else", insert: "@else {\n\t$0\n}", detail: "Fallback branch." },
  { label: "@for", insert: "@for (${1:x} in ${2:xs}) {\n\t$0\n}", detail: "Loop over a collection." },
  { label: "@while", insert: "@while (${1:cond}) {\n\t$0\n}", detail: "While loop." },
  { label: "@match", insert: "@match (${1:value}) {\n\t@case (${2:v}) { $0 }\n\t@default { }\n}", detail: "Pattern match." },
  { label: "@case", insert: "@case (${1:v}) {\n\t$0\n}", detail: "A match arm." },
  { label: "@default", insert: "@default {\n\t$0\n}", detail: "Default match arm." },
];

export function findTag(name: string): TagInfo | undefined {
  return HOST_TAGS.find((t) => t.tag === name);
}

// Style-dict keys understood by RuitkStyle (addons/reactive_ui_toolkit/core/style.gd) — offered inside a
// `style={ {…} }` (or `*_style`) dictionary, where Godot's own LSP has no vocabulary.
// 0.9.0: every key is the exact Godot property / theme-item / StyleBoxFlat name (mirrors
// grammar/guitkx-schema.json styleKeys). Any StyleBoxFlat property is additionally accepted
// verbatim by the runtime box builder.
export const STYLE_KEYS: AttrInfo[] = [
  { name: "bg_color", type: "Color", detail: "StyleBoxFlat.bg_color (primary StyleBox fill)." },
  { name: "border_color", type: "Color", detail: "StyleBoxFlat.border_color." },
  { name: "border_width_all", type: "int", detail: "StyleBoxFlat set_border_width_all (per-side border_width_left/… also accepted)." },
  { name: "corner_radius_all", type: "int", detail: "StyleBoxFlat set_corner_radius_all (per-corner corner_radius_top_left/… also accepted)." },
  { name: "content_margin_all", type: "float", detail: "StyleBoxFlat set_content_margin_all (per-side content_margin_left/… also accepted)." },
  { name: "expand_margin_all", type: "float", detail: "StyleBoxFlat set_expand_margin_all (per-side expand_margin_left/… also accepted)." },
  { name: "hover", type: "Dictionary", detail: "Per-state StyleBox for the hover theme slot." },
  { name: "pressed", type: "Dictionary", detail: "Per-state StyleBox for the pressed theme slot." },
  { name: "focus", type: "Dictionary", detail: "Per-state StyleBox for the focus theme slot." },
  { name: "disabled", type: "Dictionary", detail: "Per-state StyleBox for the disabled theme slot." },
  { name: "read_only", type: "Dictionary", detail: "Per-state StyleBox for the read_only theme slot." },
  { name: "colors", type: "Dictionary", detail: "Theme color overrides { name: Color }." },
  { name: "constants", type: "Dictionary", detail: "Theme constant overrides { name: int }." },
  { name: "fonts", type: "Dictionary", detail: "Theme font overrides { name: Font }." },
  { name: "font_sizes", type: "Dictionary", detail: "Theme font-size overrides { name: int }." },
  { name: "icons", type: "Dictionary", detail: "Theme icon overrides { name: Texture2D }." },
  { name: "styleboxes", type: "Dictionary", detail: "Theme StyleBox overrides { name: StyleBox }." },
  { name: "custom_minimum_size", type: "Vector2", detail: "Control.custom_minimum_size." },
  { name: "min_width", type: "float", detail: "Extension: custom_minimum_size.x (a dict can't set .x)." },
  { name: "min_height", type: "float", detail: "Extension: custom_minimum_size.y." },
  { name: "anchors_preset", type: "int|String", detail: "Control anchor preset (Control.PRESET_FULL_RECT / \"PRESET_FULL_RECT\" / …)." },
  { name: "size_flags_horizontal", type: "int|String", detail: "Control.size_flags_horizontal (Control.SIZE_EXPAND_FILL / \"SIZE_EXPAND_FILL\" / …)." },
  { name: "size_flags_vertical", type: "int|String", detail: "Control.size_flags_vertical." },
  { name: "modulate", type: "Color", detail: "CanvasItem.modulate." },
  { name: "self_modulate", type: "Color", detail: "CanvasItem.self_modulate." },
  { name: "rotation", type: "float", detail: "Control.rotation (radians — Godot's own semantics)." },
  { name: "scale", type: "Vector2", detail: "Control.scale." },
  { name: "pivot_offset", type: "Vector2", detail: "Control.pivot_offset." },
  { name: "visible", type: "bool", detail: "Control.visible." },
  { name: "clip_contents", type: "bool", detail: "Control.clip_contents." },
  { name: "mouse_filter", type: "int|String", detail: "Control.mouse_filter (MOUSE_FILTER_STOP/PASS/IGNORE)." },
  { name: "tooltip_text", type: "String", detail: "Control.tooltip_text." },
  { name: "z_index", type: "int", detail: "CanvasItem.z_index." },
  { name: "font_color", type: "Color", detail: "font_color theme override." },
  { name: "font", type: "Font", detail: "font theme override." },
  { name: "font_size", type: "int", detail: "font_size theme override." },
  { name: "font_outline_color", type: "Color", detail: "font_outline_color theme override." },
  { name: "outline_size", type: "int", detail: "outline_size theme constant." },
  { name: "separation", type: "int", detail: "separation theme constant (containers)." },
  { name: "h_separation", type: "int", detail: "h_separation theme constant." },
  { name: "v_separation", type: "int", detail: "v_separation theme constant." },
  { name: "margin_left", type: "int", detail: "margin_left theme constant (MarginContainer)." },
  { name: "margin_top", type: "int", detail: "margin_top theme constant (MarginContainer)." },
  { name: "margin_right", type: "int", detail: "margin_right theme constant (MarginContainer)." },
  { name: "margin_bottom", type: "int", detail: "margin_bottom theme constant (MarginContainer)." },
];

// Common built-in constants for `<Type>.<member>` completion inside {expr} — a static fallback for the
// most-used ones; Godot's own LSP (when running) supplies the full set. [audit #3]
export const BUILTIN_MEMBERS: Record<string, string[]> = {
  Color: [
    "WHITE", "BLACK", "TRANSPARENT", "RED", "GREEN", "BLUE", "YELLOW", "CYAN", "MAGENTA", "GRAY",
    "DARK_GRAY", "LIGHT_GRAY", "ORANGE", "PURPLE", "PINK", "BROWN", "GOLD", "LIME_GREEN", "SKY_BLUE",
    "AQUA", "NAVY_BLUE", "TEAL", "MAROON", "SILVER", "CRIMSON",
  ],
  Vector2: ["ZERO", "ONE", "INF", "LEFT", "RIGHT", "UP", "DOWN"],
  Vector2i: ["ZERO", "ONE", "MIN", "MAX", "LEFT", "RIGHT", "UP", "DOWN"],
  Vector3: ["ZERO", "ONE", "INF", "LEFT", "RIGHT", "UP", "DOWN", "FORWARD", "BACK"],
};
