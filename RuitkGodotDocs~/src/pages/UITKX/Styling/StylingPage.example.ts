// Code samples for the Styling page. Godot has no USS/CSS — styling is a plain
// `style={ { … } }` Dictionary (RuitkStyle) plus an optional named-bundle layer
// (RuitkStyleSheet + `classes`). All markup is .guitkx; all setup code is GDScript.

export const EXAMPLE_IMPORT = `# Nothing to import. RuitkStyle reads the \`style\` Dictionary on any host
# element automatically — the class_names V, Hooks, RuitkRoot,
# RuitkStyle and RuitkStyleSheet are globally available once the addon is enabled.

<Label text="Hello" style={ {"font_size": 20, "font_color": Color.WHITE} } />`

export const EXAMPLE_BOTH_APIs = `# 1. Inline dict — the everyday form.
<PanelContainer style={ {"bg_color": Color(0.16, 0.17, 0.24), "corner_radius_all": 10, "content_margin_all": 16} } />

# 2. A style module — the real answer for reuse across files.
#    (card.style.guitkx)
export PANEL := { "bg_color": Color(0.16, 0.17, 0.24), "corner_radius_all": 10, "content_margin_all": 16 }

# then, in any .guitkx:
import { PANEL } from "./card.style"
<PanelContainer style={ PANEL } />

# 3. Named bundles via RuitkStyleSheet + the \`classes\` prop (see below).
<PanelContainer classes={ ["card"] } style={ {"content_margin_all": 20} } />   # inline style wins last`

export const EXAMPLE_CONDITIONAL = `# A style dict is a plain GDScript Dictionary — build it with any expression.
var is_hovered = useState(false)
var is_enabled = useState(true)

var button_style = {
    "bg_color": Color(0.3, 0.85, 0.45) if is_hovered[0] else Color(0.2, 0.2, 0.25),
    "corner_radius_all": 8,
    "content_margin_all": 12,
    "modulate": Color(1, 1, 1, 1.0 if is_enabled[0] else 0.5),
}

return (
    <Button text="Save" style={ button_style } disabled={ not is_enabled[0] } />
)`

export const EXAMPLE_INLINE = `# The style dict can be written inline in the attribute — no setup variable needed.
<Label text="Hello"
       style={ {"font_color": Color.GREEN, "font_size": 18} } />`

// ── RuitkStyleSheet — named style bundles (the \`classes\` layer) ─────────────────
// These four were the "USS Stylesheets" examples on the Unity page; on Godot the
// equivalent is RuitkStyleSheet: register a name -> style dict, then reference it
// through the \`classes\` prop. There is NO selector matching / cascade — just an
// ordered dictionary merge (bundles left-to-right, inline \`style\` wins last).

export const EXAMPLE_USS_BASIC = `# Register named style bundles once (e.g. in an autoload or before mount).
RuitkStyleSheet.register("card", {
    "bg_color": Color(0.15, 0.15, 0.18),
    "corner_radius_all": 8,
    "content_margin_all": 12,
})

# Reference the bundle by name via the \`classes\` prop.
Card() -> RuitkVNode {
  return (
    <PanelContainer classes={ ["card"] }>
      <Label text="Styled by the 'card' bundle" style={ {"font_color": Color.WHITE} } />
    </PanelContainer>
  )
}`

export const EXAMPLE_USS_FILE = `# Bulk-register a whole { name -> style } map with RuitkStyleSheet.merge().
# Later keys overwrite earlier ones. A good place: an autoload's _ready().
RuitkStyleSheet.merge({
    "card":    { "bg_color": Color(0.12, 0.12, 0.14), "corner_radius_all": 8, "content_margin_all": 12 },
    "title":   { "font_size": 18, "font_color": Color.WHITE },
    "danger":  { "font_color": Color.RED },
    "muted":   { "font_color": Color(0.6, 0.6, 0.6) },
})`

export const EXAMPLE_USS_MULTIPLE = `# The \`classes\` prop takes an Array — bundles merge left-to-right, so later
# names override earlier ones for any keys they share.
ThemedPanel() -> RuitkVNode {
  return (
    <PanelContainer classes={ ["card", "danger"] }>
      <Label classes={ ["title"] } text="card + danger (danger's font_color wins)" />
    </PanelContainer>
  )
}`

export const EXAMPLE_USS_COMBINED = `# Bundles handle the shared baseline; inline \`style\` handles dynamic, per-render
# values and always wins last in the merge.
Card(is_selected) -> RuitkVNode {
  var highlight = {
      "border_color": Color(0, 0.67, 1) if is_selected else Color(0, 0, 0, 0),
      "border_width_all": 2,
  }
  return (
    <PanelContainer classes={ ["card"] } style={ highlight }>
      <Label text="Baseline from 'card', border from inline style" />
    </PanelContainer>
  )
}`


export const EXAMPLE_STYLE_MODULE = `# card.style.guitkx — a STYLE MODULE. No markup, no component; a look, named.
# It compiles to a sibling card.style.gd, so importing one costs nothing at render time.

export PANEL := {
    "bg_color": Color(0.13, 0.13, 0.16),
    "corner_radius_all": 8,
    "border_width_all": 1,
    "border_color": Color(0.24, 0.24, 0.30),
    "content_margin_all": 12,
}

export HEADING := { "font_size": 20, "font_color": Color(0.0, 0.9, 0.75) }
export BODY    := { "font_color": Color(0.72, 0.72, 0.76) }

# An exported FUNCTION is a parameterised style: one definition that answers for every
# state, instead of one constant per state that drift apart.
export swatch(tint: Color, is_on: bool) -> Dictionary {
    return {
        "bg_color": tint if is_on else Color(tint, 0.25),
        "corner_radius_all": 6,
        "border_width_all": 2,
        "border_color": tint,
    }
}`

export const EXAMPLE_STYLE_MODULE_USE = `# Named imports pull individual exports in…
import { PANEL, HEADING } from "./card.style"

# …or a namespace alias keeps the origin visible at every use site.
import * as Palette from "./card.style"

Card(is_on: bool = true) -> RuitkVNode {
  return (
    <PanelContainer style={ PANEL }>
      <VBoxContainer style={ {"separation": 8} }>
        <Label text="Styled from a module" style={ HEADING } />
        <Label text="Body copy" style={ Palette.BODY } />
        <PanelContainer style={ Palette.swatch(Color(0.4, 0.85, 0.5), is_on) } />
      </VBoxContainer>
    </PanelContainer>
  )
}`

export const EXAMPLE_THEME_DIRECTIVE = `# @uss preloads a Godot Theme and hands it to this component's ROOT element, so
# every Control beneath inherits it — the engine's own cascade, not a second one.
# @theme is the same directive under the name Godot users expect.
@uss "res://ui/dark.tres"

Panel() -> RuitkVNode {
  return (
    # Wears the Theme; sets no style of its own.
    <PanelContainer>
      # The Theme sets the floor, a style dict wins where it speaks.
      <Label text="Overridden" style={ {"font_color": Color.WHITE} } />
    </PanelContainer>
  )
}`
