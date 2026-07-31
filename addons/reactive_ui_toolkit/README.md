# Reactive UI Toolkit — Godot

React-style reactive UI for Godot 4, in plain GDScript: function components, hooks
(`useState` / `useEffect` / `useMemo` / …), a fiber reconciler with keyed reconciliation and
bailouts, a router, typed styling — and the **`.guitkx`** JSX-like markup language with
**ES-module semantics** (`import { StatusChip } from "./status_chip"`, `import * as Hud`, `export default`, plain signature-classified declarations)
that compiles to plain `.gd` at save time and hot-reloads running games (Fast Refresh with
hook-state preservation).

- **Repository / full documentation:** https://github.com/reactive-ui-toolkit/ruitk-godot
- **Issues:** https://github.com/reactive-ui-toolkit/ruitk-godot/issues
- **Changelog:** `CHANGELOG.md` (in this folder)
- **License:** Reactive UI Toolkit Community License 1.1 (`LICENSE`, in this folder) — free to use and to ship in your games if your company earned under US $250k in the last 12 months; above that, shipping needs a commercial license ($2,000/title or $2,500/studio/year — see the repo's `LICENSE-COMMERCIAL.md`). Credit "Made with Reactive UI Toolkit" (or "Reactive UI Toolkit — Godot"); not to be redistributed or sold as a competing product

## Install

1. Get the addon, either way:
   - **From the Asset Library:** open the **AssetLib** tab in the editor, search **"Reactive UI Toolkit — Godot"**,
     then **Download → Install** (keep the `addons/reactive_ui_toolkit/` folder).
   - **Manually:** copy `addons/reactive_ui_toolkit/` into your project's `res://addons/`.
2. Enable **Reactive UI Toolkit — Godot** under *Project → Project Settings → Plugins*.
3. Optional but recommended: the **Reactive UI Toolkit — Godot Editor** addon (a separate Asset Library entry —
   search **"Reactive UI Toolkit — Godot Editor"**) adds an in-editor `.guitkx` authoring experience — highlighting,
   live diagnostics, completion, hover, go-to-definition. VS Code users get the same (plus
   embedded-GDScript analysis) from the **GUITKX** extension on the marketplace.

Requires **Godot 4.4+** (tested on 4.7).

## Quick start

Create `hello.guitkx` anywhere in your project:

```
Hello() -> RuitkVNode {
  var count = useState(0)
  return (
    <VBoxContainer style={ {"separation": 8} }>
      <Label text={ "clicked %d times" % count[0] } />
      <Button text="click me" onPressed={ func(): count[1].call(count[0] + 1) } />
    </VBoxContainer>
  )
}
```

Saving it generates a sibling `hello.gd` (the addon's watcher compiles automatically). Mount it
from any scene script:

```gdscript
extends Control

var _app: RuitkRoot   # keep this referenced for the UI's lifetime!

func _ready():
	_app = RuitkRoot.create(self, V.fc(V.comp("res://hello.gd"), {}))

func _exit_tree():
	_app.unmount()
```

`RuitkRoot.create(container, root_vnode)` mounts under `container` and renders; `.unmount()`
tears down and runs cleanups.

With a game running (F5), edits to `.guitkx` hot-reload in place — state included.

Split the UI across files with imports (`export` marks what other files may use; resolution is
strict, and the error tells you the exact import to add):

```
import { Hello } from "./hello"

export Screen() -> RuitkVNode {
  return ( <PanelContainer><Hello /></PanelContainer> )
}
```

## Settings

The runtime's tunables live in *Project → Project Settings* under the **Reactive Ui Toolkit**
group (registered by either plugin, shown as basic settings):

| Key | Default | Applies to |
|---|---|---|
| `reactive_ui_toolkit/runtime/time_slicing` | `false` | `RuitkConfig.time_slicing` |
| `reactive_ui_toolkit/runtime/frame_budget_ms` | `8.0` | `RuitkConfig.frame_budget_ms` |
| `reactive_ui_toolkit/runtime/host_node_pool` | `true` | `RuitkConfig.host_node_pool` |
| `reactive_ui_toolkit/runtime/hook_validation` | `auto` | `RuitkConfig.enable_hook_validation` |
| `reactive_ui_toolkit/runtime/strict_diagnostics` | `auto` | `RuitkConfig.enable_strict_diagnostics` |
| `reactive_ui_toolkit/diagnostics/enabled` | `false` | `RuitkDiagnostics.enabled` |
| `reactive_ui_toolkit/diagnostics/capture` | `false` | `RuitkDiagnostics.capture` |

The two validators are tri-states: **`auto`** keeps the compiled default (`OS.is_debug_build()` —
on while developing, off in exported games), `enabled`/`disabled` force them. Settings are read
once at first mount and work in exported games; only values you *changed* apply, so assigning the
statics directly from code (`RuitkConfig.time_slicing = true` in a `_ready`) still works exactly
as documented. An `override.cfg` next to `project.godot` gives per-machine overrides.

## Upgrading

**From 0.12.x or earlier — read this first.** 0.13.0 is the *Reactive UI Toolkit* rename: names
only, zero behavior changes, but a clean break with no compatibility window. `addons/reactive_ui*`
became `addons/reactive_ui_toolkit*` and the `RUI*` global class prefix became `Ruitk*`
(`RUIVNode` → `RuitkVNode`, `ReactiveRoot` → `RuitkRoot`, …). `V` and `Hooks` are unchanged. One
idempotent command rewrites a whole project, and it ships inside this addon:

```
godot --headless --path . --script res://addons/reactive_ui_toolkit/dev/migrate_0_13_0.gd
```

Then **delete the old `addons/reactive_ui`, `addons/reactive_ui_editor` and
`addons/reactive_ui_analyzer` folders by hand** — store/AssetLib updates add files, they never
delete. See **MIGRATION-0.13.md** in the repository for the full guide and the 36-name table.

Older projects upgrade in order, each command idempotent and in the same `dev/` folder:
`migrate_0_10_0.gd` (the imports/`export` model) → `migrate_0_11_0.gd` (ES-module syntax) →
`migrate_0_13_0.gd` (the rename above).

## What's in the box

- `core/` — the reactive engine: V factories, virtual nodes, hooks, fiber reconciler, signals,
  router, Fast Refresh runtime.
- `guitkx/` — the `.guitkx` compiler, import resolver, migration codemod, formatter, lexer, and
  diagnostics (GUITKX#### codes).
- `plugin.gd` — the editor watcher: compiles `.guitkx` on save, sweeps orphaned outputs, pushes
  hot reloads to running games.
- `dev/` — the shipped migration codemods (`migrate_0_13_0.gd` and friends) plus small maintenance
  scripts. Nothing here is loaded at runtime; they are headless `--script` runners you invoke by
  hand.

Everything is plain GDScript — no native binaries, no dependencies.
