# Reactive UI Toolkit — Godot (GDScript)

💬 **[Join the Discord][discord-invite]** — questions, feedback, and release announcements.

A **React-style reactive UI library for Godot 4.x**, written in GDScript, authored through
**`.guitkx`** — a JSX-like markup that compiles to GDScript. It's the Godot leg of the
[Reactive UI Toolkit family](https://github.com/reactive-ui-toolkit) — sibling of
[Reactive UI Toolkit — Unity](https://github.com/reactive-ui-toolkit/ruitk-unity) (the C# / Unity
UI Toolkit library) — same mental model, ported to Godot's retained-mode `Control` tree.

You write **function components** in `.guitkx`; a **fiber reconciler** diffs each render against
the last and patches only what changed on the real Godot node tree. State lives in **hooks**, and
saving a `.guitkx` while your game runs under F5 hot-reloads it in place (**Fast Refresh**).

```
Counter() -> RUIVNode {
	var s = useState(0)
	return (
		<VBoxContainer style={ {"separation": 8} }>
			<Label text={ "Count: %d" % s[0] } style={ {"font_size": 28} } />
			<HBoxContainer style={ {"separation": 8} }>
				<Button text="−1" onPressed={ func(): s[1].call(s[0] - 1) } />
				<Button text="+1" onPressed={ func(): s[1].call(func(c): return c + 1) } />
			</HBoxContainer>
		</VBoxContainer>
	)
}
```

> **Status: runtime feature-complete, verified on Godot 4.7 with a green test suite.**
> A fiber reconciler with bailout + keyed reconciliation, **23 hooks** plus a full
> React-Router-style **router** (with its own **17 hooks**), **signals**, **Suspense**, a
> three-layer **style** system, declarative **item-model** controls, media/animation, a
> custom-drawing hatch, and an **open element vocabulary named exactly after the Godot classes** (any instantiable `Node` class is a valid tag). `.guitkx` gets you React-parity markup — early
> returns, prop spread, context handles, control-flow directives — plus **Fast Refresh** (hot
> reload with hook state preserved) and editor tooling in three places: natively inside Godot, in
> VS Code, and in Visual Studio 2022.

Everything below is written the way you should actually author UI with this library: in
**`.guitkx`**. The library's underlying GDScript API (`V.*` factories, `Hooks.*`) is what `.guitkx`
compiles to — it's covered too, but as the escape hatch it's meant to be, not the primary path.

---

## Install

**As a project:** open this folder in Godot 4.x and press Play (runs `examples/main.tscn`, the demo
gallery — every demo is `.guitkx`).

**As an addon in your own project:** two ways —

- **From the Asset Library (in-editor):** open the **AssetLib** tab, search **"Reactive UI Toolkit — Godot"**,
  then **Download → Install** (keep `addons/reactive_ui_toolkit/`). The editor addon ships as a separate
  asset — search **"Reactive UI Toolkit — Godot Editor"** to add it too.
- **Manually:** copy `addons/reactive_ui_toolkit/` into your project's `res://addons/`.

Either way, the runtime is plain GDScript with global `class_name`s (`V`, `Hooks`,
`ReactiveRoot`, ...), so they're available immediately — **no plugin enable required**.

To actually *write* `.guitkx`, enable the plugin (**Project Settings → Plugins → Reactive UI Toolkit — Godot**) —
it watches the filesystem and compiles each `.guitkx` to a sibling `.gd` on save. Then add editor
support for the language itself (pick one, or use both):

- **`addons/reactive_ui_toolkit_editor/`** — a native in-Godot editor tab: syntax highlighting, live
  diagnostics, completion, and hover, no external tools. Copy it in alongside `reactive_ui_toolkit` and
  enable it too.
- **VS Code / Visual Studio 2022 extensions** (`ide-extensions/`) — the same, plus embedded-GDScript
  intelligence inside `{expr}`/setup code (completion, hover, go-to-definition, find-references,
  rename), fully offline. See [IDE tooling](#ide-tooling).

Requires **Godot 4.4+** (the compiler core uses 4.3+ engine APIs and the editor tooling's bundled native analyzer sets a hard 4.4 floor; `FoldableContainer` needs 4.5 but degrades gracefully); verified on **4.7**. Standard build — no C# or `.NET`.

---

## Quick start

1. Put a `Control` in your scene (or use the scene root).
2. Write your first component as a `.guitkx` file, e.g. `res://ui/counter.guitkx`:

```
Counter() -> RUIVNode {
	var s = useState(0)
	return (
		<VBoxContainer>
			<Label text={ "Count: %d" % s[0] } />
			<Button text="+1" onPressed={ func(): s[1].call(func(c): return c + 1) } />
		</VBoxContainer>
	)
}
```

Saving it compiles a sibling `res://ui/counter.gd` (git-ignore this — it's generated) with a real
Godot `class_name` — `Counter`, inferred from the declaration (a component is any callable that
annotates `-> RUIVNode`; the annotation IS the classification) — so you can reference it like any
other class. An `@class_name` directive can override that name; it's rarely needed.

3. Mount it from a plain `.gd` script — this one bootstrap point is the only place raw GDScript is
   unavoidable, the same way a React app still has one `ReactDOM.render` call:

```gdscript
extends Control

var _app: ReactiveRoot   # keep this referenced for the UI's lifetime!

func _ready():
	_app = ReactiveRoot.create(self, V.fc(Counter.render))

func _exit_tree():
	_app.unmount()
```

`ReactiveRoot.create(container, root_vnode)` mounts under `container` and renders. **Hold onto the
returned `ReactiveRoot`** — it owns the reconciler; call `.unmount()` to tear down and run cleanups.
(A `Control`-based `ReactiveRootNode` is also available if you prefer mounting via a scene node.)

From here on, edit `counter.guitkx` while the game runs under F5 and watch it update in place — see
[Fast Refresh](#fast-refresh).

---

## Authoring in `.guitkx`

A `.guitkx` file is a module (0.11.0): a sequence of plain, signature-classified declarations —
components, hooks, utils, and values, in any mix (see
[Files are modules](#files-are-modules)). A component is GDScript **setup code** followed by exactly one
markup `return (...)`. Files reference each other through explicit
[imports](#imports--exports-0100). Canonical formatting is **2-space indentation** (Unity-exact);
the compiler and formatter both enforce it.

### Naming is 1:1 loyal to Godot (0.9.0)

You never learn a second vocabulary (migrating from 0.8? — [MIGRATION-0.9.md](MIGRATION-0.9.md)):

- **Tags are the official Godot class names** — `<VBoxContainer>`, `<PanelContainer>`,
  `<RichTextLabel>` … In fact **any instantiable Godot `Node` class is a valid tag** (validated
  against ClassDB at compile time), so the entire official Control set works from markup.
  `<Panel>` is Godot's `Panel`. Engine names are reserved — a project component that shadows one
  gets a compile warning.
- **Props are the exact Godot property names** — set verbatim on the node.
- **Events are the native signal name with an `on` marker** — `on` + PascalCase(signal):
  `onPressed` → `pressed`, `onValueChanged` → `value_changed`, `onGuiInput` → `gui_input` —
  for **every** signal of **every** node; `on_<signal>` also binds verbatim.
- **Style keys are the exact Godot property / theme-item / StyleBoxFlat names**; enum values are
  Godot's own constants (`Control.SIZE_EXPAND_FILL` or the constant name as a string).

### Imports & exports (0.10.0)

Files say what they depend on, and cross-file resolution is **strict** — referencing another
file's component/hook/util/value without importing it is a compile error that tells you the exact
import line to add (migrating from 0.9? — [MIGRATION-0.10.md](MIGRATION-0.10.md)):

```guitkx
import { StatusChip } from "./status_chip"
import { use_blink } from "~/ui/hud.hooks"

export Panel(level: int = 1) -> RUIVNode {
  var blink = use_blink(0.5)
  return ( <PanelContainer><StatusChip level={level} /></PanelContainer> )
}
```

- **Specifiers** are relative (`./`, `../`) or root-aliased (`~/` — the project UI source root, set
  by a `"root"` key in the nearest `guitkx.config.json`, default `res://`), always **extensionless**.
  `res://`/`uid://` are not valid import specifiers (they stay valid in `@uss`/`@theme` asset
  positions, which also accept `~/`). The full ES surface (0.11.0): named imports,
  `import { remote as local }` renames, `import * as X` namespaces (members via `X.name`;
  component tags via `X.` not yet), `import X from` defaults + `export default Name`, the
  combined forms `import Def, { a, b as c } from` / `import Def, * as X from` (0.11.1 — one
  declaration carrying the default binding plus the named/namespace surface), and deferred
  `export { a, b }` lists. Re-exports (`export { a } from`) stay out for now.
- **`export`** makes a declaration reachable across files; without it a declaration is
  file-private. A file may hold **several** declarations; its binding (`class_name`) is the
  `@class_name` override, else the first exported declaration.
- **Component cycles are legal** (component imports resolve lazily, by path, at first render);
  **value cycles** (hooks/utils/values — eager `const` preloads) are a compile error that prints
  the chain.
- **Migrating an existing project is one command** — idempotent, re-runnable, leaves hand-written
  `class_name` scripts alone (they stay ambient, no import needed):

  ```bash
  godot --headless --path . --script res://addons/reactive_ui_toolkit/dev/migrate_0_11_0.gd
  ```

Import mistakes surface as **`GUITKX2300`–`GUITKX2309`** (unresolved specifier, not exported,
not declared, duplicate, unused, not imported, value cycle, unexported reference, boundary
crossing, misplaced import) plus the 0.11.0 export family **`GUITKX2320`–`GUITKX2327`**
(deprecated wrapper keyword, cross-guards, export-list / default-export mistakes) — see the docs
site's Imports page for the full table.

### Hooks

Call hooks **only** at the top of a component, unconditionally, in a stable order (never in
`if`/loops/lambdas — the compiler rejects this at compile time). The core set:

| Hook | Returns / does |
|---|---|
| `useState(initial)` | `[value, setter]`. `setter.call(v)` or `setter.call(func(old): return new)`. |
| `useReducer(reducer, initial)` | `[state, dispatch]`. |
| `useRef(initial)` | A stable `{ "current": initial }` box (never re-created). |
| `useMemo(factory, deps)` | Cached value; recomputed only when `deps` change. |
| `useCallback(cb, deps)` / `useStableCallback(cb)` | A stable `Callable` while `deps` are unchanged. |
| `useEffect(effect, deps = null)` | Runs after commit when `deps` change (`[]` = once; `null` = every render). `effect` may return a `Callable` cleanup. |
| `useLayoutEffect(effect, deps)` | Like `useEffect` but synchronous, before paint. |
| `useContext(handle)` | The nearest provider's value; re-renders on change. |
| `useSignal(sig, selector)` / `useSignalKey(key)` | Subscribe to a [signal](#signals) store. |
| `useDeferredValue(v)` / `useTransition()` | Defer/triage non-urgent updates (synchronous renderer — see [limitations](#notes--limitations)). |
| `useTween(...)` / `useTweenValue(...)` / `useAnimate(...)` / `useSfx(...)` | Animation + audio helpers. |

…plus `useImperativeHandle`, `useSafeArea`, `createContext`/`provideContext`, and the
stable-callback family — **23 hooks** in all. Bare calls (`useState(...)`) auto-resolve to
`Hooks.useState(...)`. The [router](#router) adds **17 more**, all on `RUIRouter`
(`RUIRouter.useNavigate`, `useLocation`, `useParams`, `useSearchParams`, `useBlocker`, …) — router
hooks stay explicitly qualified.

### Control flow

`@if`/`@elif`/`@else`, `@for`, `@while`, and `@match`/`@case`/`@default` bodies are GDScript **prep
code plus `return ( <markup> )`**, and nest recursively — the same model as ReactiveUIToolKit:

```
@for (it in items) {
	var label = "row %s" % it
	if it == null:
		return null                          # skip this item
	return ( <Label key={ str(it) } text={ label } /> )
}
```

`return null` / a bare `return` are the sanctioned skip-guard forms. A component's markup `return`
can also appear **early**, guarding on a condition, not just as the final statement:

```
Panel(ready: bool = false) -> RUIVNode {
	if not ready:
		return ( <Label text="loading" /> )
	return ( <VBoxContainer>…</VBoxContainer> )
}
```

### Prop spread & context

```
Card() -> RUIVNode {
	var shared = { "custom_minimum_size": Vector2(140, 0), "text": "shared" }
	return ( <Button {...shared} onPressed={ handle } /> )
}
```

Spreads merge left-to-right (later wins), on both host elements and components — just like JSX.
For cross-cutting state, prefer a context **handle** over a bare string key (collision-free, and it
carries a default value):

```gdscript
# accent_context.gd — a module-level handle, shared by every component that imports it
static var HANDLE: RUIContext = preload("res://.../hooks.gd").createContext(Color(0.4, 0.7, 1.0))
```

```
provideContext(AccentContext.HANDLE, accent[0])   # in a provider
useContext(AccentContext.HANDLE)                  # in a consumer
```

### Styling

Godot has no CSS/USS — styling is `Control` properties + `Theme` overrides, and layout is
**container-driven**. `.guitkx`'s `style={ {...} }` prop gives you three layers (see
`core/style.gd` + `core/style_sheet.gd`):

1. **Flat keys — exact Godot names** — `custom_minimum_size`, `size_flags_horizontal`/`_vertical`
   (Godot `SIZE_*` values), `anchors_preset` (`PRESET_*`), `modulate`/`self_modulate`,
   `font_color`/`font_size`/`font_outline_color`, `separation`, `margin_left`/…, `tooltip_text`,
   `rotation` (radians)/`scale`, and **any `StyleBoxFlat` property verbatim** (`bg_color`,
   `border_width_left`, `shadow_size`, …) plus the `*_all` umbrellas named after Godot's own
   setters (`corner_radius_all`, `content_margin_all`, …).
2. **Theme channels** — full `Theme` coverage (colors / constants / fonts / font-sizes / icons /
   styleboxes) plus **per-state `StyleBox` slots** (hover / pressed / focus / disabled / read-only).
3. **`classes={ [...] }`** — named style sets registered with `RUIStyleSheet` (merged left-to-right;
   inline `style` wins). A userland "USS classes" layer.

### Keys

Give each item in a list a `key` so the reconciler tracks identity across re-renders (efficient
add/remove/reorder instead of rebuild):

```
@for (it in items) {
	return ( <Label key={ str(it.id) } text={ it.name } /> )
}
```

### Item models

`<ItemList>` / `<Tree>` / `<TabBar>` / `<OptionButton>` / `<PopupMenu>` take a
declarative `items={ [...] }` prop and reconcile rows **by item identity** (selection/expansion
preserved across renders). Wire changes with the normal `on*` event props. Register adapters for
your own controls via `RUIHost.register_item_adapter(...)`.

### Custom drawing

Draw directly onto any host element — the Godot analogue of Unity's `OnGenerateVisualContent`:

```
<Control draw_fn={ func(canvas): canvas.draw_rect(Rect2(Vector2.ZERO, canvas.size), Color.DARK_SLATE_GRAY) }
         redraw_key={ frame } />
```

`draw_fn` is a `Callable(canvas_item)` run during the node's `draw`. A register-once trampoline
reads the latest callback, so a fresh closure each render never re-subscribes — it repaints only
when the callback identity **or** `redraw_key` changes.

### Files are modules

A file is a module (0.11.0): it may hold any mix of top-level declarations — components, hooks,
utils, and plain **value exports** (`export MAX_ITEMS: int = 5`, compiled to `static var`; treat
them as constants). `export` is the only visibility mechanism; an un-exported declaration is
file-private. Shared logic lives in its own `.guitkx` file (`use_thing() { ... }`, `fmt(x) {
... }`) and consumers import it — named (`import { use_thing } from "./file.hooks"`) or as a
namespace (`import * as Hud from "./hud"`, members via `Hud.fmt(...)`). See the docs site's
Files & Modules page.

### Where `V.*` still shows up

A handful of structural primitives have no markup tag — **`Portal`, `Suspense`, `ErrorBoundary`,
`Memo`, and the router's `Router`/`Routes`/`Route`/`Outlet`/`Navigate`/`NavLink`** aren't Godot
classes, so they're not tags; you reach them via `V.*` inside an embedded `{ expr }` — still
inside your `.guitkx` file, just not as a `<Tag>`:

```
App() -> RUIVNode {
	return (
		<VBoxContainer>
			{ V.suspense({ "fallback": V.fc(Spinner.render), "ready_signal": ready }, [V.fc(Content.render)]) }
		</VBoxContainer>
	)
}
```

Everything else — every host `Control`, every hook, every directive — is a real `.guitkx` tag or
keyword. Reaching for the bare `V.*`/`Hooks.*` GDScript API directly (outside a `.guitkx` file) is
possible — it's the same runtime — but treat it as a fallback for one-off scripts or advanced
internals, not how you author application UI.

### Router

A faithful **React-Router-v6-style** component-tree router: nested/layout routes via
`{ V.outlet() }`, ranked first-match, merged `:params`, splat `*`, `basename`, query strings,
`NavLink`-equivalent active styling, and navigation blockers. The route table itself is configured
via `V.routes(...)`/`V.route(...)` (see [above](#where-v-still-shows-up)); drive it from markup with
the router hooks on `RUIRouter`.

### Signals

A reference-aware `RUISignal` store plus a process-wide, string-keyed `RUISignals` registry —
share state across components without prop-drilling. Read it with `useSignal`/`useSignalKey`.

### Fast Refresh

Save a `.guitkx` while your game runs under F5 and the UI updates **in place**, hook state
preserved — no restart:

- A changed **component** re-renders just its own fibers; a changed **hook/module** re-renders
  just the components that (transitively) import it — falling back to a global re-render only when
  the import graph can't name them (e.g. pre-0.10 files without imports).
- If the hook-call shape changed (added/removed/reordered), that component's state is
  **deliberately reset** instead of risking corruption — React Fast Refresh semantics, backed by a
  compiler-embedded hook-order fingerprint.
- A component created *after* F5 (so it has no registered `class_name` yet) still hot-links in,
  by path, the moment you reference it.
- **Dev-only**: gated on an attached debugger session (F5 from the editor); exported builds carry
  zero HMR code. Renaming a component remounts it (fresh state).

---

## Architecture

Mirrors ReactiveUIToolKit; the design (algorithms) is ported, the code is GDScript.

```
addons/reactive_ui_toolkit/core/
  vnode.gd / v.gd            RUIVNode / V     — UI description + the ~61 factories (incl. V.comp)
  fiber.gd                   RUIFiber         — persistent tree node; current/WIP alternates; hook store
  hooks.gd                   Hooks            — the 23 hooks
  reconciler.gd              RUIReconciler    — render (diff) + two-phase commit; bailout; scheduling
  host_config.gd             RUIHost          — the Godot adapter: nodes, props, signals, items, custom draw
  style.gd / style_sheet.gd  RUIStyle / RUIStyleSheet — declarative style -> Control props / Theme
  signal_store.gd / signal_registry.gd  RUISignal / RUISignals
  suspense.gd                                  — V.suspense boundary
  media.gd                                     — useSfx / useAnimate / V.audio / V.video
  hmr.gd                     RUIHmr           — Fast Refresh runtime (game side)
  router/                    RUIRouter…       — router spine, matcher, ranker, history, location
  reactive_root.gd / reactive_root_node.gd     — mount surfaces
addons/reactive_ui_toolkit/guitkx/    RUIGuitkx…       — the .guitkx lexer/parser/codegen/formatter
addons/reactive_ui_toolkit/editor/                     — editor-side watcher + Fast Refresh push (hmr_debugger.gd)
addons/reactive_ui_toolkit_editor/                     — native in-Godot .guitkx editor tab (separate addon)
ide-extensions/                                — VS Code / VS 2022 extensions + shared language server
```

**Render loop:** a hook setter calls `request_update()`, which **coalesces** to one re-render per
frame. The reconciler builds a work-in-progress fiber tree (running components, dispatching hooks),
diffs it against the committed tree with **component bailout** + keyed child reconciliation, and
commits in two passes — **deletions** then **placements/updates** — then runs **effects**. Hook
state persists via the per-fiber `hooks` array carried to the reused fiber.

**Engine boundary:** only `host_config.gd` + `style.gd` touch concrete Godot APIs — the same seam
that lets React point one reconciler at react-dom or react-native.

**Cross-component references are path-based, not registry-based:** a generated `<Card />` reference
compiles to `V.fc(V.comp("res://ui/card.gd"), …)` — a lazy, cached, path-based resolver — instead of
`Card.render`, so a component created mid-session, an editor rescan lag, or a cyclic component graph
can never break resolution. Hand-written `class_name` components (and your own GDScript expressions)
keep the classic `Foo.render` form.

---

## Diagnostics

The compiler validates as it goes — rules of hooks, duplicate/unstable keys, unknown elements,
directive-header grammar, import resolution, dangling/duplicate component references, asset paths,
and more — **58 `GUITKX####` codes** in total, with "did you mean" hints where it can tell. See the
docs site's Diagnostics reference for the full table; `GUITKX2300`–`GUITKX2309` are the import
family (shared across the ReactiveUI engines), `GUITKX2103` is the one you'll hit migrating pre-0.7
`.guitkx` (directive bodies need `return ( <markup> )` now), and `GUITKX2106`/`GUITKX2107` guard
against a copy-pasted or dangling component reference.

---

## <a id="ide-tooling"></a>IDE tooling

Three ways to get `.guitkx` intelligence, and you can mix them:

| | Native (`reactive_ui_toolkit_editor`) | VS Code / VS 2022 (`ide-extensions/`) |
|---|---|---|
| Syntax highlighting | ✅ | ✅ (self-contained TextMate grammar) |
| Live diagnostics | ✅ | ✅ |
| Tag / attribute / directive completion + hover | ✅ | ✅ |
| Embedded-GDScript intelligence inside `{expr}`/setup (completion, hover, diagnostics) | — | ✅, via [`@gdscript-analyzer/core`](https://www.npmjs.com/package/@gdscript-analyzer/core), fully offline, no running Godot editor |
| Go-to-definition / find-references / rename / signature help | — | ✅ |
| Formatting | ✅ | ✅ |

The native addon needs nothing but Godot itself — enable `addons/reactive_ui_toolkit_editor/` alongside
`reactive_ui_toolkit`. The external extensions need Node bundled in (already handled by the packaged
`.vsix`) — see `ide-extensions/README.md` for building/publishing. The `.guitkx` toolchain and all
IDE support are optional in the sense that the runtime works without them, but writing UI by hand as
raw `V.*`/`Hooks.*` calls is not the intended day-to-day workflow — see
[Authoring in `.guitkx`](#authoring-in-guitkx).

---

## Notes & limitations

- **`V.comp`-addressed structural primitives have no markup tag yet** — `Portal`, `Suspense`,
  `ErrorBoundary`, `Memo`, `Audio`/`Video`, and the router primitives are reached via `V.*` inside an
  embedded expression (see [above](#where-v-still-shows-up)), not a `<Tag>`. Adding tags for these is
  tracked in `plans/`.
- **Removed plain props don't reset to defaults** between renders (style keys, events, refs, and
  custom draw *do* reset). Keep props consistent or set explicit defaults.
- **Error boundaries are structural** — GDScript has no `try`/`catch`, so a boundary can't
  auto-catch a child render crash; it shows its fallback on an imperative toggle / `reset_key`.
- **`useTransition`/`useDeferredValue` are synchronous** (no concurrent renderer) — faithful to the
  Unity reference, but not "true" concurrency.
- **Fast Refresh is dev-only** (gated on an attached debugger session) and does not migrate
  hand-written module `static var`s across a reload (a Godot engine limitation, godot#105667) —
  generated components are statics-free by design.
- Event handler lambdas are re-created each render (events re-wire on change — fine functionally;
  use `useCallback` to stabilize). Custom `draw_fn` uses the register-once trampoline so it does
  **not** re-subscribe.
- **Dependency arrays compare by VALUE, not identity** — `useEffect`/`useMemo`/`useCallback` deps use
  GDScript `==`, which deep-compares `Array`/`Dictionary`, unlike React's per-item `Object.is`. A
  freshly-built but structurally-equal deps array will **not** re-run the effect (a stable behavior
  this library relies on elsewhere), but a large `Array`/`Dictionary` in a deps list is deep-compared
  every render — keep deps small/primitive where you can. (State/signal change-detection is
  identity-based already, matching React; only the deps-array comparison differs.)
- **VS Code and VS 2022 ship together**: both extensions bundle the same `lsp-server` and are
  version-locked to it (0.11.0), published in the same release window as the addon — if you update
  one, update the others.

## Roadmap

- **Markup tags for the remaining `V.*`-only primitives** (`Portal`, `Suspense`, `Router`/`Routes`/
  `Route`, …) so the "escape hatch" list above gets shorter.
- **Native-editor parity** — embedded-GDScript intelligence for `reactive_ui_toolkit_editor`, closing the
  remaining gap with the VS Code/VS 2022 extensions (see `plans/archive/NATIVE_EDITOR_PARITY_PLAN.md`).
- **Docs site** (`ReactiveUIGodotDocs~/`) — a full guide beyond this README; run it locally with
  `cd ReactiveUIGodotDocs~ && npm ci && npm run dev`.
- **Re-exports** (`export { X } from "./x"`) — the imports fast-follow, family-wide.
- **Godot Asset Store / Asset Library distribution** — repo prep (license, icon, export rules) is
  in place; publishing itself is not live yet.

## License

**Free for almost everyone.** Reactive UI Toolkit — Godot ships under the
[Reactive UI Toolkit Community License 1.1](LICENSE): use it, modify it, and ship commercial
games with it at no cost if your company (plus parents/subsidiaries) earned under
**US $250,000** in the last 12 months. Development, evaluation, and education are free
at any company size — the threshold only applies when you *ship*.

Above the threshold, shipping a product takes a commercial license — **$2,000 per
title** (one-time, perpetual) or **$2,500 per studio per year**, your pick; see
[LICENSE-COMMERCIAL.md](LICENSE-COMMERCIAL.md). The same terms and prices exist for
each library in the Reactive UI Toolkit family (Godot, Unity, Unreal).

Two asks of everyone: put **"Made with Reactive UI Toolkit"** in your credits alongside your
other middleware, and don't resell the library itself as a competing product (your
game is never a competing product). Every previously released version keeps the
license it shipped with. Contributions require the one-time [CLA](CLA.md).
Weird case (nonprofit, just-over-the-line, contractor)? Email
<yanivkalfa@gmail.com> — we'd rather you ship with Reactive UI Toolkit than not.

<!--
  Single source of truth for the community Discord invite used in this file — update only here.
  (The docs site has its own single source: ReactiveUIGodotDocs~/src/links.ts.)
-->
[discord-invite]: https://discord.gg/Knedqu4Wyv
