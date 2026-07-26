# ReactiveUI for Godot — C# leg (design + execution plan)

**Status: PROPOSAL — not scheduled.** Owner decision gates in §17. Strategic timing note from the
2026-07-27 investigation stands: this is a quarter-scale campaign serving ~16% of Godot users
(Community Poll 2025, n≈9,600), best started after the licensing rollout produces demand signal.
This document exists so that when the go comes, execution starts from a settled design instead of
a blank page — and so every measurement below (taken 2026-07-27) is on record.

**One-line pitch:** the same `.guitkx` markup and the same React model, with **embedded C#**
instead of embedded GDScript — ReactiveUIToolKit's proven C# toolchain retargeted onto Godot,
living in THIS repo as a fourth deliverable.

---

## 0. Goals / non-goals

**Goals**
- A C#-native ReactiveUI for the Godot .NET build: `.guitkx` components with embedded C#,
  compiled to C# by a Roslyn source generator at `dotnet build` time, rendered by a C# runtime
  port of our reconciler against the real `Control` tree.
- API shape matching the Unity leg's C# surface (`V.Func`, `VirtualNode`, `useState`…) and
  element/prop/event naming matching THIS leg's 1:1 Godot loyalty (`<VBoxContainer>`, `Text`,
  `OnPressed`). Family concepts, native spelling (ES_MODULES_GENERAL_PLAN line 15).
- Same-repo residency: shared grammar, vocabulary, contract corpus, diagnostics numbering,
  docs site, license, release machinery.
- HMR parity with the GDScript leg (save `.guitkx` mid-play → UI updates, state preserved).

**Non-goals**
- No C# API for *authoring without markup* beyond what falls out naturally (`V.*` is public
  anyway, as on Unity).
- No web export story (platform limitation — C# cannot export to web; prototypes only as of
  2026-07). Standard-build GDScript leg remains the answer there.
- No interop bridge to the GDScript runtime (rejected 2026-07-27: `Call()`/`Get`/`Set`
  string-typing, no cross-language inheritance, Variant marshalling per render — worst of both
  worlds).
- The GDScript leg changes ZERO bytes. Standard-build users are unaffected forever.

## 1. Platform facts (verified 2026-07-27)

| Fact | Detail |
|---|---|
| Engine build | C# requires the **.NET build** of Godot (separate download + export templates). Our MIN_GODOT floor stays 4.4; GodotSharp NuGet versions track the engine (4.7.1 current) |
| Runtime | .NET 8+ (Android export needs .NET 9) |
| Platforms | Desktop full; Android/iOS experimental; **web unsupported** for C# |
| Project shape | Game csproj: `<Project Sdk="Godot.NET.Sdk/4.x.x">`. **Library** packages reference the `GodotSharp` NuGet instead and ship as normal NuGet packages — explicitly supported ("external NuGet packages which use the Godot API… can be added and referenced") |
| Source generators | First-class. Godot ships `Godot.SourceGenerators`; user analyzers coexist (removable via csproj `<Analyzer Remove>` if ever needed — not expected, our generator only consumes `.guitkx` AdditionalFiles) |
| Runtime assembly loading | `AssemblyLoadContext` works in editor-run and exported games (known-good pattern; Modot etc.). Unload is unreliable .NET-wide → HMR keeps old contexts alive, same as the Unity leg leaks until restart |
| Editor plugins in C# | Documented as "quite convoluted" → our editor addon stays **GDScript** (§8) |
| C#↔GDScript | No inheritance across languages; stringly `Call/Get/Set` — reason interop bridge was rejected |
| Attributes | `partial` classes mandatory; `[Tool]`, `[GlobalClass]`, `[ModuleInitializer]` (C# 9) all available |
| CI binaries | godotengine releases ship `_mono_` (.NET) editor builds for headless CI |

## 2. Measured inventory — what the family already owns (2026-07-27)

### Unity leg (`C:\Yanivs\GameDev\UnityComponents\Assets\ReactiveUIToolKit`)

| Piece | Size | Engine coupling | Reuse verdict |
|---|---|---|---|
| `ide-extensions~/language-lib` (parser 8.3k, formatter 3.9k, Roslyn glue 3.4k, diagnostics 1.8k, semantic tokens 1k, IntelliSense 0.8k) | 36 files / **21.6k LOC** | `netstandard2.0`, no Unity refs (6 files mention Unity in comments/emitted strings only) | **SHARE — consume as-is** (vocabulary + specifier rules parameterized) |
| `SourceGenerator~` (UitkxGenerator/Pipeline + Emitter/{CSharpEmitter, HookEmitter, ModuleEmitter, ExportsEmitter, PropsResolver, TagResolution, StructureValidator, HooksValidator}) | 25 files / **12.1k LOC** | `netstandard2.0` Roslyn `IIncrementalGenerator`; Unity ONLY in emitted string literals (`L("using UnityEngine;")`) | **FORK + retarget emitters** (~2–3k LOC delta) |
| `ide-extensions~/lsp-server` (OmniSharp + full Roslyn workspaces = embedded-**C#** intelligence) | **13.6k LOC** C# | Engine-agnostic analysis; Unity only in vocabulary | **FORK + vocabulary swap** for the C# leg's IDE story |
| `Editor/` HMR machinery (in-process Roslyn compile → `Assembly.Load` → `__hmr_*` delegate swap → `RefreshRuntime.PerformRefresh()`; `[ModuleInitializer]`-published `Refresh.Family` identity) | **15.8k LOC** (incl. non-HMR editor code) | Compile+swap is pure .NET; watcher/trigger is Unity-editor | **PORT the pattern**, new topology (§8) |
| `Shared/Core` runtime (Fiber 4.4k, Router 2.1k, Refresh 1.1k, root 6.3k…) | 69 files / 16.3k LOC | **NOT clean**: `VisualElement` ×118 in Core; 8/14 fiber files Unity-typed | Reference only — port algorithms from OUR leg instead (below) |
| `Shared/Elements` + `Shared/Props` (54 typed element adapters + 62 typed props classes + `ElementRegistry`) | **30.1k LOC** | Fully Unity | **DISCARD — Godot doesn't need it** (§6) |
| `Runtime/` MonoBehaviour adapter | 536 LOC | Unity | Reference for mount surface |
| `FiberHostConfig` seam (abstract, `object` handles; uGUI backend 6.2k proves a second host) | — | — | **COPY the seam design verbatim** |

### This repo (GDScript leg)

| Piece | Size | Reuse verdict |
|---|---|---|
| Runtime `addons/reactive_ui/core` (reconciler 1146, hooks 596, host_config 543, style 346, v 252, router/signals/suspense/media…) | 26 files / **4.8k LOC** | **PORT to C# — this is the algorithm source of truth** (Godot-faithful semantics: synchronous loop, fresh fibers, documented constraints) |
| `host_config.gd` mapping knowledge: `ClassDB.instantiate(type)` open vocabulary, `node.set(k,v)`, class-default cache, `on`+Pascal→signal (generic, no alias table), items→models, draw_fn trampoline, node recycling | 543 LOC | **The crown jewel** — ports ~1:1 to `Godot.ClassDB` / `GodotObject.Set(StringName, Variant)` / `Connect` |
| `.guitkx` grammar + `vocabulary.json` + ClassDB dump (already shipped in lsp-server) + contract corpus (66 goldens) + diagnostics numbering | — | **SHARED BY CONSTRUCTION** — and the C# *scanner* implementation is already family-corpus-pinned via the Unity leg |
| Editor addon HMR wire: `EditorDebuggerSession` + `rui_hmr:reload` (editor side) / `hmr.gd` apply (game side) | — | **COPY the wire protocol**, new payload (§8) |
| publish.yml (tag-gated lanes), changelog.mjs (multi-lane), test.yml | — | **EXTEND** with a `csharp` lane |

**The core economic fact:** Unity spent 30.1k LOC on Elements/Props because UI Toolkit needs a
typed adapter per element. Godot's reflective `ClassDB` surface does the same job in ~1k — our
GDScript leg proves it in 543+346 lines with an OPEN vocabulary (any instantiable Control).
That single collapse is why this leg is feasible at quarter scale.

## 3. Repo residency + layout (same repo — decided direction)

Why same-repo: (a) grammar/diagnostics lockstep becomes atomic instead of a fourth repo to
drift; (b) `ide-extensions/visual-studio/` means C# already builds in this repo's CI; (c) one
docs site, one license, one tracker. If a split is ever wanted, the subtree lifts out cleanly.

```
ReactiveUI-Godot/
├─ addons/reactive_ui/              # GDScript runtime — UNTOUCHED
├─ addons/reactive_ui_editor/       # GDScript editor addon — UNTOUCHED
├─ addons/reactive_ui_csharp/       # NEW: thin GDScript editor addon — HMR wire only (§8)
│   ├─ plugin.cfg                   #   version source for the addon piece
│   └─ hmr/…                        #   watcher + dotnet driver + debugger-wire push
├─ csharp/                          # NEW — contains a `.gdignore` so the ROOT (standard-build)
│   │                               #   project never imports any of it
│   ├─ ReactiveUITK.Godot/          #   the runtime library → NuGet
│   │   ├─ ReactiveUITK.Godot.csproj   # net8.0; <PackageReference Include="GodotSharp" Version="4.4.*">
│   │   ├─ Core/                    #   VNode, V, Fiber/, Hooks, ReactiveRoot, HostConfig seam
│   │   ├─ Host/                    #   GodotHostConfig, StyleApplier, EventBinder, ItemModels, DrawTrampoline
│   │   ├─ Router/  Signals/  Suspense/  Media/  Refresh/
│   │   └─ ReactiveRootNode.cs      #   [GlobalClass] Node mount surface
│   ├─ ReactiveUITK.Godot.Generator/ #  netstandard2.0 Roslyn IIncrementalGenerator → NuGet (analyzer)
│   │   ├─ …fork of Unity SourceGenerator~ pipeline…
│   │   ├─ Vocabulary/              #   baked vocabulary.json + ClassDB dump (build-time copy from
│   │   │                           #   the repo's single sources — a sync tripwire test enforces)
│   │   └─ build/ReactiveUITK.Godot.Generator.props
│   │        # NuGet-injected MSBuild props: <AdditionalFiles Include="**/*.guitkx" />
│   │        # → replaces Unity's csproj-postprocessor hack; user csproj needs ZERO edits
│   ├─ ReactiveUITK.Godot.Language/ #   fork-point of Unity language-lib (or ProjectReference if
│   │                               #   we vendor it via subtree — §17 decision D4)
│   ├─ Tests.Generator/             #   xUnit: pipeline + emitter snapshot tests (headless, no engine)
│   ├─ Tests.Runtime/               #   runs INSIDE headless .NET-build Godot (§10)
│   └─ demo/                        #   its own project.godot (.NET build) + gallery port
│       ├─ project.godot
│       ├─ Demo.csproj              #   Sdk="Godot.NET.Sdk/4.x" + PackageReference to both packages
│       └─ examples/…               #   counter/todo/router/… mirrors of examples/demos
├─ ide-extensions/
│   ├─ lsp-server/                  # TS server (GDScript-embedded tier) — untouched
│   └─ csharp-lsp/                  # NEW (M6): fork of Unity's C# LSP, vocabulary-swapped
├─ tests/                           # GDScript suites — untouched; + csharp gate scripts
├─ plans/  docs (ReactiveUIGodotDocs~)  ide-extensions/grammar  …shared
```

Key mechanics:
- **`csharp/.gdignore`** hides the whole subtree from the root Godot project's importer — the
  standard-build project stays clean. The C# demo is its own nested Godot project (supported
  pattern), opened separately with a .NET-build editor.
- **Version sources** (four → six deliverables): `csharp/ReactiveUITK.Godot/*.csproj` `<Version>`
  (runtime+generator move in lockstep, one number) and `addons/reactive_ui_csharp/plugin.cfg`.

## 4. The markup language: same `.guitkx`, embedded language = C#

Decision (recommended): **keep the `.guitkx` extension** — the family convention is
extension-per-ENGINE (`.uitkx`/`.uetkx`/`.guitkx`), embedded language is a property of the leg.
Mode detection, in priority order:
1. `guitkx.config.json` walk-up gains `"lang": "csharp" | "gdscript"` (default `gdscript` —
   fully backward compatible).
2. Tooling heuristic: a sibling/ancestor `*.csproj` with the generator package ⇒ csharp.

A project uses ONE mode; mixing legs in one project is out of scope (flagged loudly by both
compilers if both ever see the same tree). The grammar (tags, attrs, directives, imports,
`export`, `@class_name`, comments) is byte-identical — only the embedded-expression language
differs, exactly the Unity↔Godot relationship today, already pinned by the shared corpus.

Component shape (target syntax):

```
import { Theme } from "./theme"

export Counter(int start = 0) -> RuiNode {
    var (count, setCount) = useState(start);
    return (
        <VBoxContainer>
            <Label Text={$"Count: {count}"} Modulate={Theme.Accent} />
            <Button Text="+1" OnPressed={() => setCount(count + 1)} />
        </VBoxContainer>
    );
}
```

Naming rules carried from THIS leg (0.9.0 naming loyalty): tags = exact Godot class names
(open vocabulary); props = exact Godot property names **PascalCase as the C# bindings spell
them** (`Text`, `Modulate`); events = `On` + PascalCase(signal) (`OnPressed` → `pressed`),
`On_<signal>` verbatim escape. Hooks/API casing carried from the UNITY leg (`useState`,
`useEffect`, `V.Func`) — C# family spelling, auto-injected usings in generated code.

## 5. Runtime (`ReactiveUITK.Godot`) — port map

Source of truth = **our GDScript runtime** (Godot-faithful semantics), idioms = Unity's C# leg.

| GDScript source (LOC) | C# target | Notes |
|---|---|---|
| `vnode.gd` (immutable RUIVNode) | `VNode.cs` | Match Unity's `VirtualNode` field shape where identical |
| `v.gd` (71 factories, 252) | `V.cs` | `V.Func`, `V.Fragment`, `V.Text`, `V.H(string, props)` open-vocabulary factory + curated named factories generated FROM `vocabulary.json` (a build step, not hand-written) |
| `reconciler.gd` (1146) | `Fiber/Reconciler.cs` | Same synchronous begin/complete/commit phases, bailout, keyed reconciliation, effect ordering. Godot-documented constraints preserved (structural error boundaries; sync transitions) |
| `fiber.gd` | `Fiber/FiberNode.cs` | C# CAN reuse alternate fibers (Unity does); decision D5: keep fresh-fiber semantics for cross-leg parity of observable behavior, optimize later |
| `hooks.gd` (596, 23 hooks) | `Hooks.cs` | Positional slots, same validation config |
| `host_config.gd` (543) | `Host/GodotHostConfig.cs` | Seam = Unity's abstract `FiberHostConfig` (object handles). Implementation = ClassDB port: `ClassDB.Instantiate(type)`, recycle-with-default-reset via cached `ClassDB.ClassGetPropertyDefaultValue`, `obj.Set(StringName, Variant)` |
| `style.gd`/`style_sheet.gd` (346+) | `Host/StyleApplier.cs` + `Style` typed dict | Port Unity's `Style`/`CssHelpers` ergonomics onto Godot key space (exact property/theme/StyleBoxFlat names) |
| events (in host_config) | `Host/EventBinder.cs` | `On`+Pascal→snake signal, `Callable.From`, disconnect-on-diff; generic over any signal (no alias table) |
| items/draw_fn | `Host/ItemModels.cs`, `Host/DrawTrampoline.cs` | 1:1 |
| `router/` (17 hooks) | `Router/` | Port; Unity `Router/` as C# reference |
| `signal_store/registry` | `Signals/` | |
| `suspense.gd`, `media.gd` | `Suspense/`, `Media/` | Media maps to `AudioStreamPlayer`/`VideoStreamPlayer` same as GDScript leg |
| `reactive_root.gd`/`_node.gd` | `ReactiveRoot.cs` + `[GlobalClass] ReactiveRootNode` | `ReactiveRoot.Create(Control container, VNode root)`; Node variant for scene-first users |
| — (new) | `Refresh/` | Unity's `Refresh.Family` + `RefreshRuntime` identity model, needed for HMR swap (§8) |

Estimate: 4.8k GDScript → **~8–10k C#** (types + docs headers inflate; Refresh/ is additive).

## 6. Host layer — why 30k becomes ~1.2k

Unity: closed `ElementRegistry` of 54 hand-written typed adapters + 62 typed props classes,
because `VisualElement` subclasses have bespoke, non-uniform APIs.
Godot: every Control property is settable via `GodotObject.Set`, every signal connectable by
name, every class instantiable via `ClassDB` — our GDScript leg's whole host is 543 LOC with
an **open vocabulary** (any ClassDB Node class is a valid tag, curated set only for IDE
metadata). The C# port keeps exactly this: no adapters, no registry, no per-element props
classes. Typed niceties (e.g. `Style`) sit ABOVE the generic applier, not instead of it.
Perf note: `Set(StringName, Variant)` marshals per call — same cost class the GDScript leg
already pays via `node.set()`; the diffing model means only changed keys are applied. StringName
caching (static interning of prop/signal names, as Godot's own generators do with
`PropertyName.*`) is the one C#-specific optimization to build in from day one.

## 7. Source generator (`ReactiveUITK.Godot.Generator`)

Fork of Unity's `SourceGenerator~` (IIncrementalGenerator, 12.1k LOC), with:
- **Input**: `.guitkx` as `AdditionalFiles` — injected by the NuGet package's
  `build/*.props` (standard MSBuild). This REPLACES Unity's `UitkxCsprojPostprocessor` (Unity
  rewrites csproj constantly; Godot doesn't touch the user's csproj — cleaner on our side).
- **TagResolution retarget**: `BuiltinTyped/BuiltinDictionary` collapse into two kinds —
  curated-known tag → `V.<Name>(props…)` named factory; unknown-but-plausible tag →
  `V.H("Name", …)` (open vocabulary, runtime-validated — mirrors `V.h`). The generator cannot
  query ClassDB (no engine at compile time), so it bakes the **ClassDB dump** we already ship
  for the TS LSP + `vocabulary.json` (single-source; copy step + byte-sync tripwire, same
  pattern as the existing vocabulary sync test).
- **Emitter retarget**: emitted preamble becomes `using Godot;` + our namespaces; expression
  holes stay verbatim C# (unchanged machinery); props emit into `Style`/dictionary paths per §6;
  `[ModuleInitializer]` Family registration kept for HMR.
- **Diagnostics**: GUITKX numbering (shared vocabulary.json severities), not UITKX — the
  numbering is the family contract; messages reuse the family-registered wordings.
- Peer-file model (imports/exports across `.guitkx`) carries over intact — it's the same
  ES-modules layer 2 the whole family shares (E-01…E-12).

Output shape (per Unity precedent): `partial class Counter` + `public static VNode Render(…)`
+ `__Exports` container for values/hooks + Family handles. `.guitkx.g.cs` never lands on disk
(generator output), so **nothing generated is committed** — unlike Unreal (committed `.inl`)
and like Unity.

## 8. HMR — design (the part that needs real engineering)

Unity's pipeline, re-plumbed for Godot's two-process topology:

```
[Godot editor process — addons/reactive_ui_csharp (GDScript, @tool)]
  1. FileSystemWatcher on **/*.guitkx (mode=csharp projects only)
  2. On save during a debugger-attached play session:
     shell out to `dotnet build csharp-hmr.csproj` — a generated micro-project that
     compiles ONLY the changed file's generated C# against the project's last-built
     assemblies (Unity does this with in-process Roslyn; we use the dotnet CLI —
     no Roslyn shipping inside the addon, ~2–4s cold / <1s warm)
  3. EditorDebuggerSession.send_message("rui_hmr:reload_cs", [dll_path, swap_manifest])
[Game process — ReactiveUITK.Godot Refresh/]
  4. C# runtime debugger-message handler receives the path
  5. new AssemblyLoadContext(isCollectible: true).LoadFromAssemblyPath(dll)
  6. Swap __hmr_* delegate fields / Family handles → RefreshRuntime.PerformRefresh()
     (state preserved via positional hook slots, exactly the family rule; hook-shape
     edits reset that component with a notice — Unity 0.14-era behavior)
  7. Old ALCs intentionally stay alive (unload is unreliable) — leak until stop, same as Unity
```

Fallbacks and edges: no play session → nothing to do (next `dotnet build` picks it up);
`[ModuleInitializer]` fires on ALC load giving fresh Family handles; the debugger wire and
message dedup reuse the GDScript leg's proven `hmr_debugger.gd` patterns verbatim. The
editor addon stays GDScript (sidesteps "C# editor plugins are convoluted" entirely) — it
never touches C# types, only paths and the wire.

## 9. IDE tooling

- **Grammar/TextMate**: the existing `guitkx.tmLanguage.json` gains a C#-embedded injection
  variant (the Unity grammar is the donor; markup scopes identical).
- **LSP**: decision D3 — recommended: fork **Unity's C# LSP server** (13.6k, OmniSharp + Roslyn
  workspaces) as `ide-extensions/csharp-lsp`, swap vocabulary + specifier rules + ClassDB dump.
  It already does embedded-C# intelligence (virtual-doc → Roslyn), which our TS server cannot
  (its embedded tier is GDScript-analyzer-native). The VS Code extension learns to pick the
  server by project mode (`lang` from guitkx.config.json). The TS server stays untouched for
  GDScript-mode projects.
- **In-Godot editor view**: the `reactive_ui_editor` addon's `.guitkx` view/tokenizer works on
  markup + treats embedded code lexically — usable as-is for C# mode minus embedded
  intelligence; full parity is a non-goal for v1 (VS Code/VS2022/Rider are the C# audience's
  editors anyway).
- Specifier path completion (GAP-ISO-2) lands with the Unreal-derived spec (nearest-first,
  replace-not-append) in whichever server ships it first.

## 10. Tests + parity

| Suite | Runner | What |
|---|---|---|
| `Tests.Generator` | xUnit, pure .NET (CI-cheap) | Fork of Unity's generator tests: pipeline, emitter snapshots, diagnostics — the bulk of coverage, no engine needed |
| Scanner/corpus | already covered | The C# `.guitkx` scanner is Unity's `language-lib`, ALREADY pinned by the family corpus (`family-corpus.hash`) — zero new gate needed until we add C#-specific cases |
| `Tests.Runtime` | headless **.NET-build** Godot: `godot --headless --path csharp/demo --script`-equivalent C# test entry (a `[Tool]` SceneTree bootstrap; mirrors `tests/*.gd` quit(code) pattern) | reconciler/hooks/host behavior on real Controls |
| **Cross-leg parity suite** | both runtimes | The rot-prevention gate: a shared table of scenarios (mount/diff/keyed moves/bailout/effect order/null render) executed by `tests/core_test.gd` AND `Tests.Runtime`, asserting identical observable sequences. New infrastructure, ~1–2k, non-negotiable for a two-runtime repo |
| Demo battery | headless .NET Godot | `demos_test` equivalent over `csharp/demo` |

## 11. Packaging + distribution

- **NuGet** (the .NET-idiomatic channel): `ReactiveUITK.Godot` (runtime) +
  `ReactiveUITK.Godot.Generator` (analyzer package with the props injection).
  ⚠ **NAMING: `ReactiveUI` on NuGet is TAKEN** — the well-known Rx MVVM framework. We cannot
  use bare `ReactiveUI.*` ids without collision/confusion (and their brand). `ReactiveUITK.*`
  matches the Unity family name and is the recommended id root (decision D1).
- **AssetLib / Godot Asset Store**: one new listing for `addons/reactive_ui_csharp` (the HMR
  addon) with an explicit ".NET build required; library installs via NuGet" description; the
  demo zip attached to GitHub releases.
- **GitHub releases**: `csharp-v*` tag lane in publish.yml → `dotnet pack` + `nuget push` +
  addon zip. Changelog: new `csharp` lane in `changelog.json` (the machinery is already
  multi-lane); root CHANGELOG stays the GDScript library's (separate deliverable, own file
  `csharp/CHANGELOG.md` mirrored like the others).
- **License**: ReactiveUI Community License 1.0, same as everything (a NuGet `PackageLicenseFile`
  entry carries it).

## 12. CI

- `test.yml`: new `csharp` job, **path-filtered** (`csharp/**`, `addons/reactive_ui_csharp/**`,
  shared vocabulary/corpus paths) so GDScript-only PRs pay nothing. Steps: setup-dotnet →
  `dotnet test Tests.Generator` → download `_mono_` Godot build → import/build demo →
  `Tests.Runtime` + parity suite.
- Sync tripwires (same house pattern): vocabulary.json ↔ generator-baked copy byte-identical;
  ClassDB dump ↔ generator copy; corpus hash unchanged unless family-bumped.

## 13. Versioning

Two new lanes: `ReactiveUITK.Godot` NuGet version (runtime+generator lockstep) starting
**0.1.0**, and `reactive_ui_csharp` plugin.cfg. Both patch-by-default per house policy;
independent of the GDScript lanes.

## 14. Docs + positioning

- Docs site: a "C# " section (getting started with the .NET build, csproj setup, the same
  teaching pages with C# holes) — the versionManifest machinery is engine-version-based and
  applies unchanged.
- README: reposition from "no C#/.NET needed" to "GDScript-native AND C#-native; the standard
  build needs no .NET" — the current selling point survives, scoped to the GDScript leg.
- Migration story: none needed (new audience), but a "GDScript leg vs C# leg — which?" page
  (web export / hot-reload nuances / team language) prevents mis-adoption.

## 15. Milestones (each gated like every campaign: build green + suites + changelog staged)

| M | Deliverable | Est. new/changed LOC |
|---|---|---|
| M0 | Scaffold: `csharp/` tree + `.gdignore`, csprojs, CI job, vocabulary/dump sync tripwires, demo project boots empty | ~500 + config |
| M1 | Core port: VNode/V/Fiber/Hooks + `Tests.Runtime` bootstrap green headless | ~4k |
| M2 | Host layer: GodotHostConfig/Style/Events/items/draw; counter demo renders + interacts | ~1.5k |
| M3 | Generator retarget end-to-end: `.guitkx`→C#→running demo; `Tests.Generator` snapshot suite ported | ~3k delta |
| M4 | Subsystems: Router/Signals/Suspense/Media + **cross-leg parity suite** | ~4k |
| M5 | HMR: addon + dotnet driver + wire + ALC swap; mid-play edit demo | ~2.5k |
| M6 | IDE: csharp-lsp fork + VS Code mode routing + grammar injection | ~2k delta |
| M7 | Docs + gallery port + "which leg" page | content |
| M8 | Packaging: NuGet publish lane, AssetLib listing, changelog lane, release 0.1.0 | config |

Sequenced M0→M3 first (proves the thesis end-to-end on the counter demo before the long tail).
Rough shape: comparable to the Unreal Phase-0→2 arc, i.e. a quarter-scale campaign.

## 16. Risks

| Risk | Mitigation |
|---|---|
| Runtime parity rot between the two Godot legs | The parity suite (§10) is a required gate from M4 on; behavior changes must land in both or be documented divergences |
| Family lockstep cost grows (4th toolchain) | Same-repo residency + shared corpus/vocabulary make grammar changes atomic for both Godot legs; the C# scanner is Unity's, already family-gated |
| HMR ALC leaks / swap edge cases | Accepted-by-design leak (family precedent); Unity's delegate-trampoline design is 2 legs proven; hook-shape edits reset state per the family rule |
| Generator vocabulary staleness vs engine versions | The ClassDB dump already has an update runbook (`add-godot-version` skill) — extend it to refresh the generator's baked copy |
| NuGet name/brand collision with ReactiveUI (MVVM) | Use `ReactiveUITK.*`; never bare `ReactiveUI` ids (D1) |
| Demand uncertainty (~16% × Godot) | This plan stays parked until the licensing rollout yields signal (§0); M0–M3 alone can serve as a cheap validating spike if a paying customer asks |

## 17. Open owner decisions

- **D1 — Naming**: NuGet id root `ReactiveUITK.*` (recommended) vs something new; display name
  "Reactive UI for Godot (C#)".
- **D2 — Go/timing**: parked until monetization signal, or green-lit earlier.
- **D3 — LSP base**: fork Unity's C# server (recommended) vs teaching the TS server a Roslyn
  sidecar.
- **D4 — language-lib consumption**: vendored fork under `csharp/` (recommended: repo stays
  self-contained) vs cross-repo reference to the Unity tree.
- **D5 — fiber allocation**: fresh-fibers (GDScript-leg parity, recommended for v1) vs Unity's
  double-buffer reuse.
- **D6 — hooks casing**: `useState` (Unity C# leg spelling, recommended — family API reuse)
  vs .NET-conventional `UseState` (Unreal spelling). Family precedent exists for both; pick one
  and pin it in the corpus.
