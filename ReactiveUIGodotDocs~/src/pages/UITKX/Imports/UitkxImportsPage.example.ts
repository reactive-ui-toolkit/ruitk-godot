// Code samples for the Imports page. Kept in a sibling module so the page component stays prose.

export const EXAMPLE_IMPORT_BASIC = `import { StatusChip } from "./status_chip"
import * as DoomHudStyles from "~/demos/doom/doom_hud_styles"

export Hud(level: int = 1) -> RUIVNode {
	var styles = DoomHudStyles.for_level(level)
	return (
		<PanelContainer>
			<StatusChip label={styles.title} />
		</PanelContainer>
	)
}`

export const EXAMPLE_FORMS = `# 1. Named — bind individual exports by name.
import { fmt, MAX_ITEMS } from "./hud"

# 2. Named with rename — \`remote as local\`. The LOCAL name is what you use here;
#    diagnostics on the clause validate the REMOTE name against the target.
import { Chip as Badge } from "./hud"

# 3. Namespace — ONE eager preload of the whole file; members via Hud.name.
#    Values, utils, and hooks only — <Hud.Tag/> component tags are not supported yet.
import * as Hud from "./hud"

# 4. Default — binds the target's \`export default\` declaration, resolved at
#    compile time and lowered per its kind (a default component stays lazy).
import Panel from "./score_panel"

# 5. Combined (0.11.1) — ONE declaration carrying the default binding PLUS the
#    named or namespace surface, exactly as in ES.
import Fallback, { fmt, Chip as Badge } from "./hud"
import Fallback2, * as Hud2 from "./hud"`

export const EXAMPLE_SPECIFIERS = `import { Card } from "./card"          # sibling file
import { Panel } from "../shared/panel"  # relative, up a directory
import { Theme } from "~/ui/theme"       # ~/ = the project UI source root`

export const EXAMPLE_EXPORT = `# A file may hold several plain declarations; \`export\` makes one reachable
# across files. The binding (the file's class_name) is the @class_name
# override, else the first exported decl.

export Hud() -> RUIVNode {
	return ( <LocalRow /> )
}

LocalRow() -> RUIVNode {      # no export = file-private, unreachable from other files
	return ( <Label text="row" /> )
}

export use_blink(interval: float) -> Dictionary { … }

container := { "separation": 8 }     # value — exported below via the export list
MAX_ITEMS: int = 5

# Deferred export list: a top-level line naming in-file declarations (GUITKX2323
# if a name is not declared here; GUITKX2324 if it is already exported).
export { container, MAX_ITEMS }

# Default marker: at most one per file (a second is GUITKX2327).
export default Hud`

export const EXAMPLE_CONFIG = `{
  "root": "res://ui",
  "formatter": { "printWidth": 120 }
}`

export const EXAMPLE_MIGRATE = `godot --headless --path . --script res://addons/reactive_ui_toolkit/dev/migrate_0_11_0.gd`
