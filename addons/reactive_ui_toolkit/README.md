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
- **License:** ReactiveUI Community License 1.0 (`LICENSE`, in this folder) — free to use and to ship in your games if your company earned under US $250k in the last 12 months; above that, shipping needs a commercial license ($2,000/title or $2,500/studio/year — see the repo's `LICENSE-COMMERCIAL.md`). Credit "Made with ReactiveUI"; not to be redistributed or sold as a competing product

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
Hello() -> RUIVNode {
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
var root := RUIReconciler.create_root(self)
root.render(V.fc(V.comp("res://hello.gd"), {}))
```

With a game running (F5), edits to `.guitkx` hot-reload in place — state included.

Split the UI across files with imports (`export` marks what other files may use; resolution is
strict, and the error tells you the exact import to add):

```
import { Hello } from "./hello"

export Screen() -> RUIVNode {
  return ( <PanelContainer><Hello /></PanelContainer> )
}
```

Migrating a pre-0.10 project is one idempotent command (ships with the addon):

```
godot --headless --path . --script res://addons/reactive_ui_toolkit/dev/migrate_0_11_0.gd
```

## What's in the box

- `core/` — the reactive engine: V factories, virtual nodes, hooks, fiber reconciler, signals,
  router, Fast Refresh runtime.
- `guitkx/` — the `.guitkx` compiler, import resolver, migration codemod, formatter, lexer, and
  diagnostics (GUITKX#### codes).
- `plugin.gd` — the editor watcher: compiles `.guitkx` on save, sweeps orphaned outputs, pushes
  hot reloads to running games.

Everything is plain GDScript — no native binaries, no dependencies.
