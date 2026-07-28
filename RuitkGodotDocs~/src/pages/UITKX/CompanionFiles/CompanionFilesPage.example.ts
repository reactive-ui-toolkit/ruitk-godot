export const EXAMPLE_UITKX = `import { use_player_animation } from "./PlayerCard.hooks"
import * as PlayerCardStyle from "./PlayerCard.style"
import * as PlayerCardUtils from "./PlayerCard.utils"

export PlayerCard(player: Dictionary) -> RuitkVNode {
  var anim = use_player_animation(player)
  var health_color = PlayerCardStyle.HEALTH_GREEN \\
    if player.health > player.max_health / 2 \\
    else PlayerCardStyle.DAMAGE_RED

  return (
    <VBoxContainer>
      <Label text={ player.name } />
      <Label text={ PlayerCardUtils.format_health(player.health, player.max_health) }
             style={ {"font_color": health_color, "modulate": Color(1, 1, 1, anim.opacity)} } />
      <Label text={ PlayerCardUtils.rank_label(player.rank) } />
    </VBoxContainer>
  )
}`

export const EXAMPLE_GENERATED_CLASS = `# Auto-generated sibling: PlayerCard.gd (simplified)
class_name PlayerCard          # ← the binding: @class_name override, else first exported decl
extends RefCounted
## AUTO-GENERATED from PlayerCard.guitkx -- do not edit.

static func render(props: Dictionary, children: Array) -> RuitkVNode:
    var player = props.get("player")   # ← from the component parameter
    ...`

export const EXAMPLE_DIRECTORY = `res://ui/PlayerCard/
  PlayerCard.guitkx            # the component        -> PlayerCard.gd
  PlayerCard.hooks.guitkx      # hook exports         -> PlayerCard.hooks.gd (optional)
  PlayerCard.style.guitkx      # value exports        -> PlayerCard.style.gd (optional)
  PlayerCard.utils.guitkx      # util exports         -> PlayerCard.utils.gd (optional)`

export const EXAMPLE_MIXED = `# hud.guitkx — one file, several kinds of declarations. The signature classifies
# each one; \`export\` alone decides what other files can see.

export MAX_SLOTS: int = 5                       # value  (compiles to static var)

accent := { "font_color": Color(1, 0.8, 0) }    # value  — no export: file-private

export use_blink(interval: float) -> bool {     # hook   (the use_ prefix)
  var on = Hooks.useState(true)
  Hooks.useEffect(func():
    var t := Time.get_ticks_msec()
    return Callable()
  , [interval])
  return on[0]
}

format_slot(i: int) -> String {                 # util   — file-private helper
  return "Slot %d" % i
}

export Hud() -> RuitkVNode {                      # component (the -> RuitkVNode annotation)
  var blink = use_blink(0.5)
  return (
    <VBoxContainer>
      <SlotRow />
    </VBoxContainer>
  )
}

SlotRow() -> RuitkVNode {                         # component — file-private
  return ( <Label text={ format_slot(0) } style={ accent } /> )
}`

export const EXAMPLE_HOOKS = `# PlayerCard.hooks.guitkx — hooks are plain top-level declarations; the
# use_ prefix is what classifies them.
export use_player_animation(player: Dictionary) -> Dictionary {
  var opacity = Hooks.useState(1.0)
  var flashing = Hooks.useState(false)

  Hooks.useEffect(func():
    if player.health <= 0:
      flashing[1].call(true)
      opacity[1].call(0.5)
    return Callable()
  , [player.health])

  return { "opacity": opacity[0], "flashing": flashing[0] }
}`

export const EXAMPLE_STYLES = `# PlayerCard.style.guitkx — value exports compile to static var on the
# generated class. Treat them as constants.
export HEALTH_GREEN := Color(0.2, 0.8, 0.3)
export DAMAGE_RED   := Color(0.9, 0.2, 0.2)
export AVATAR_SIZE  := 64.0

export CARD := {
  "bg_color": Color(0.10, 0.10, 0.18),
  "corner_radius_all": 8,
  "content_margin_all": 8,
  "separation": 8,
}

# Consumers import the whole file as a namespace:
#   import * as PlayerCardStyle from "./PlayerCard.style"
#   ... style={ PlayerCardStyle.CARD }`

export const EXAMPLE_UTILS = `# PlayerCard.utils.guitkx — utils are any other callable: no use_ prefix,
# no -> RuitkVNode annotation.
export RANK_DIAMOND := 3
export RANK_GOLD    := 2
export RANK_SILVER  := 1
export RANK_BRONZE  := 0

export format_health(current: int, max: int) -> String {
  return "%d / %d HP" % [current, max]
}

export rank_label(rank: int) -> String {
  match rank:
    RANK_DIAMOND: return "★ Diamond"
    RANK_GOLD:    return "● Gold"
    RANK_SILVER:  return "○ Silver"
    _:            return "· Bronze"
}`

export const EXAMPLE_CLASS_NAME = `# hud_utils.guitkx — @class_name pins the file's binding and global identity.
# Old \`module HudUtils { … }\` files migrate to exactly this shape, so
# hand-written HudUtils.fmt(...) callers keep working unchanged.
@class_name HudUtils

export fmt(x: float) -> String {
  return "%0.1f" % x
}

export use_tick() -> int {
  var t = Hooks.useState(0)
  return t[0]
}`

export const EXAMPLE_STANDALONE = `# SharedColors.guitkx — a standalone value file, not tied to any component.
export GOLD   := Color(1.0, 0.84, 0.0)
export SILVER := Color(0.75, 0.75, 0.75)`
