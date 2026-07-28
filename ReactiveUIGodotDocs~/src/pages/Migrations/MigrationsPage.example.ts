// Code samples for the Migrations page.

export const MIGRATE_0_11_CMD = `godot --headless --path . --script res://addons/reactive_ui_toolkit/dev/migrate_0_11_0.gd`

export const MIGRATE_0_11_BEFORE_AFTER = `# ── score_row.guitkx ──────────────────────────────────────────────
# BEFORE (0.10 — wrapper keywords; still compile this minor, warning GUITKX2320)
export component ScoreRow(label) {
  return ( <Label text={label}/> )
}
export hook use_countdown(start) -> int { … }

# AFTER (0.11 — the codemod writes this for you)
export ScoreRow(label) -> RuitkVNode {       # component: the -> RuitkVNode annotation
  return ( <Label text={label}/> )
}
export use_countdown(start) -> int { … }   # hook: the use_ prefix

# ── hud_utils.guitkx ──────────────────────────────────────────────
# BEFORE (0.10)
export module HudUtils {
  hook fmt(x) -> String { … }
}

# AFTER (0.11) — members hoist to top level; the @class_name preamble directive
# keeps the binding "HudUtils", so HudUtils.fmt(...) callers work unchanged.
# Importers of the module flip to: import * as HudUtils from "./hud_utils"
@class_name HudUtils

export fmt(x) -> String { … }`

export const MIGRATE_0_10_CMD = `godot --headless --path . --script res://addons/reactive_ui_toolkit/dev/migrate_0_10_0.gd`

export const MIGRATE_0_10_BEFORE_AFTER = `# BEFORE (0.9 — implicit cross-file references)
component Panel() {
  var b = HudHooks.use_blink(0.5)
  return ( <StatusChip /> )
}

# AFTER (0.10 — the codemod writes this for you; 0.10-era syntax, see the
# 0.10 → 0.11 section above for the current wrapper-free form)
import { HudHooks } from "./hud.hooks"
import { StatusChip } from "./status_chip"

export component Panel() {
  var b = HudHooks.use_blink(0.5)
  return ( <StatusChip /> )
}`

export const MIGRATE_0_9_CMD = `# dry run first (prints what would change, writes nothing):
godot --headless --path . --script res://addons/reactive_ui_toolkit/dev/migrate_0_9_0.gd -- --dry-run
# then for real:
godot --headless --path . --script res://addons/reactive_ui_toolkit/dev/migrate_0_9_0.gd`

export const MIGRATE_0_9_EXAMPLES = `<VBox>            ->  <VBoxContainer>
<RichText>        ->  <RichTextLabel>
onClick={...}     ->  onPressed={...}
onChange={...}    ->  onValueChanged={...} / onTextChanged={...} (per signal)
"fill": true      ->  "anchors_preset": Control.PRESET_FULL_RECT`
