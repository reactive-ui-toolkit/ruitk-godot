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
- API shape matching the Unity leg's C# surface (`V.Func`, `VirtualNode`-equivalent, `useState`…)
  and element/prop/event naming matching THIS leg's 1:1 Godot loyalty (`<VBoxContainer>`, `Text`,
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
- No wrapper-keyword grammar, ever: the leg is born post-ES-modules — plain E-01 declarations
  only, no deprecation window, no migration codemods (there is no legacy to migrate).
- No render-allocation pooling in v1 (per-render closures/dicts allocate; Unity leg ships the
  same posture — measure first, optimize later).
- The GDScript leg changes ZERO bytes. Standard-build users are unaffected forever.

## 1. Platform facts (verified 2026-07-27)

| Fact | Detail |
|---|---|
| Engine build | C# requires the **.NET build** of Godot (separate download + export templates). Our MIN_GODOT floor stays 4.4; GodotSharp NuGet versions track the engine (4.7.1 current) |
| Runtime | .NET 8+ (Android export needs .NET 9) |
| Platforms | Desktop full; Android/iOS experimental (iOS = NativeAOT ⇒ our shipped code must be AOT-safe, §7); **web unsupported** for C# |
| Project shape | Game csproj: `<Project Sdk="Godot.NET.Sdk/4.x.x">`. **Library** packages reference the `GodotSharp` NuGet instead and ship as normal NuGet packages — explicitly supported ("external NuGet packages which use the Godot API… can be added and referenced") |
| Source generators | First-class. Godot ships `Godot.SourceGenerators`; user analyzers coexist (removable via csproj `<Analyzer Remove>` if ever needed — not expected, our generator only consumes `.guitkx` AdditionalFiles) |
| Runtime assembly loading | `AssemblyLoadContext` works in editor-run and exported games (known-good pattern; Modot etc.). Unload is unreliable .NET-wide → HMR keeps old contexts alive, same as the Unity leg leaks until restart |
| Build output path | The game assembly lands under `.godot/mono/temp/bin/<Config>/<AssemblyName>.dll` — the HMR compile references it (§8) |
| Preprocessor symbols | Godot defines `GODOT`, `TOOLS` (editor builds), config symbols (`DEBUG`) — used to strip HMR receiver from release builds (§8) |
| Editor plugins in C# | Documented as "quite convoluted" → our editor addon stays **GDScript** (§8) |
| C#↔GDScript | No inheritance across languages; stringly `Call/Get/Set` — reason interop bridge was rejected |
| Attributes | `partial` classes mandatory; `[Tool]`, `[GlobalClass]`, `[ModuleInitializer]` (C# 9) all available |
| GodotObject lifetime | Freed nodes leave dangling C# wrappers — every reconciler touch guards `GodotObject.IsInstanceValid` (the GDScript leg's `is_instance_valid` discipline, ported) |
| CI binaries | godotengine releases ship `_mono_` (.NET) editor builds for headless CI |

## 2. Measured inventory — what the family already owns (2026-07-27)

### Unity leg (`C:\Yanivs\GameDev\UnityComponents\Assets\ReactiveUIToolKit`)

| Piece | Size | Engine coupling | Reuse verdict |
|---|---|---|---|
| `ide-extensions~/language-lib` (parser 8.3k, formatter 3.9k, Roslyn glue 3.4k, diagnostics 1.8k, semantic tokens 1k, IntelliSense 0.8k) | 36 files / **21.6k LOC** | `netstandard2.0`, no Unity refs (6 files mention Unity in comments/emitted strings only) | **SHARE — consume as-is** (vocabulary + specifier rules parameterized) |
| `SourceGenerator~` (UitkxGenerator/Pipeline + Emitter/{CSharpEmitter, HookEmitter, ModuleEmitter, ExportsEmitter, PropsResolver, TagResolution, StructureValidator, HooksValidator, StaticReadonlyStripper}) | 25 files / **12.1k LOC** | `netstandard2.0` Roslyn `IIncrementalGenerator`; Unity ONLY in emitted string literals (`L("using UnityEngine;")`) | **FORK + retarget emitters** (~2–3k LOC delta) |
| `ide-extensions~/lsp-server` (OmniSharp + full Roslyn workspaces = embedded-**C#** intelligence) | **13.6k LOC** C# | Engine-agnostic analysis; Unity only in vocabulary | **FORK + vocabulary swap** for the C# leg's IDE story |
| `Editor/` HMR machinery (in-process Roslyn compile → `Assembly.Load` → `__hmr_*` delegate swap → `RefreshRuntime.PerformRefresh()`; `[ModuleInitializer]`-published `Refresh.Family` identity; `HmrStaticReadonlyStripper`) | **15.8k LOC** (incl. non-HMR editor code) | Compile+swap is pure .NET; watcher/trigger is Unity-editor | **PORT the pattern**, new topology (§8) |
| `Shared/Core` runtime (Fiber 4.4k, Router 2.1k, Refresh 1.1k, root 6.3k…) | 69 files / 16.3k LOC | **NOT clean**: `VisualElement` ×118 in Core; 8/14 fiber files Unity-typed | Reference only — port algorithms from OUR leg instead (below) |
| `Shared/Elements` + `Shared/Props` (54 typed element adapters + 62 typed props classes + `ElementRegistry`) | **30.1k LOC** | Fully Unity | **DISCARD — Godot doesn't need it** (§6) |
| `Runtime/` MonoBehaviour adapter | 536 LOC | Unity | Reference for mount surface |
| `FiberHostConfig` seam (abstract, `object` handles; uGUI backend 6.2k proves a second host) | — | — | **COPY the seam design verbatim** |
| Hard-won HMR emission lessons (0.14 field campaign): values lower as **inline functions** so edits apply (TB-15); stable shim + content-hashed body so old closures can't run wrong-layout code (TB-21/23); hook-shape edit ⇒ clean state reset (TB-13) | — | — | **CARRY INTO THE GENERATOR FROM DAY 1** (§7, §8) |

### This repo (GDScript leg)

| Piece | Size | Reuse verdict |
|---|---|---|
| Runtime `addons/reactive_ui/core` (reconciler 1146, hooks 596, host_config 543, style 346, v 252, router/signals/suspense/media/config/diagnostics…) | 26 files / **4.8k LOC** | **PORT to C# — this is the algorithm source of truth** (Godot-faithful semantics; synchronous commit with OPTIONAL time-sliced render phase via `RUIConfig.time_slicing`) |
| `host_config.gd` mapping knowledge: `ClassDB.instantiate(type)` open vocabulary, `node.set(k,v)`, class-default cache, `on`+Pascal→signal (generic, no alias table), items→models, draw_fn trampoline, node recycling | 543 LOC | **The crown jewel** — ports ~1:1 to `Godot.ClassDB` / `GodotObject.Set(StringName, Variant)` / `Connect` |
| `.guitkx` grammar + `vocabulary.json` + ClassDB dump (already shipped in lsp-server) + contract corpus (66 goldens) + diagnostics numbering | — | **SHARED BY CONSTRUCTION** — and the C# *scanner* implementation is already family-corpus-pinned via the Unity leg |
| Editor addon HMR wire: `EditorDebuggerSession` + `rui_hmr:reload` (editor side) / `hmr.gd` apply (game side), session loop + dedup | — | **COPY the wire protocol**, new payload (§8) |
| publish.yml (tag-gated lanes), changelog.mjs (multi-lane), test.yml, `add-godot-version` skill (ClassDB dump refresh runbook) | — | **EXTEND** with a `csharp` lane / generator-dump refresh step |

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
│   ├─ .editorconfig                #   C# style for the whole subtree
│   ├─ ReactiveUITK.Godot/          #   the runtime library → NuGet
│   │   ├─ ReactiveUITK.Godot.csproj   # net8.0; <PackageReference Include="GodotSharp" …> (§11 floor policy)
│   │   ├─ Core/                    #   VNode, V, Fiber/, Hooks, Config, Diagnostics, ReactiveRoot, HostConfig seam
│   │   ├─ Host/                    #   GodotHostConfig, StyleApplier, VariantConvert, EventBinder,
│   │   │                           #   ItemModels, DrawTrampoline, ThemeApplier (@uss/@theme)
│   │   ├─ Router/  Signals/  Suspense/  Media/  Refresh/
│   │   └─ ReactiveRootNode.cs      #   [GlobalClass] Node mount surface
│   ├─ ReactiveUITK.Godot.Generator/ #  netstandard2.0 Roslyn IIncrementalGenerator → NuGet (analyzer)
│   │   ├─ …fork of Unity SourceGenerator~ pipeline…
│   │   ├─ Vocabulary/              #   baked vocabulary.json + ClassDB dump (build-time copy from
│   │   │                           #   the repo's single sources — a byte-sync tripwire test enforces)
│   │   └─ build/ReactiveUITK.Godot.Generator.props
│   │        # NuGet-injected MSBuild props:
│   │        #   <AdditionalFiles Include="**/*.guitkx" Exclude=".godot/**;bin/**;obj/**;addons/**" />
│   │        #   <AdditionalFiles Include="**/guitkx.config.json" />   ← the generator needs the
│   │        #   config for `~/` root resolution + lang mode; user csproj needs ZERO edits
│   ├─ ReactiveUITK.Godot.Language/ #   vendored fork of Unity language-lib (D4) + PINNED-COMMIT
│   │                               #   drift-check script vs the Unity tree (§12)
│   ├─ Tests.Generator/             #   xUnit: pipeline + emitter snapshot tests (headless, no engine)
│   ├─ Tests.Runtime/               #   runs INSIDE headless .NET-build Godot (§10)
│   └─ demo/                        #   its own project.godot (.NET build) + gallery subset (§14)
│       ├─ project.godot
│       ├─ Demo.csproj              #   Sdk="Godot.NET.Sdk/4.x" + PackageReference to both packages
│       └─ examples/…
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
- `.gitignore` additions: `csharp/**/bin/`, `csharp/**/obj/`, `csharp/demo/.godot/`,
  `csharp/demo/**/*.guitkx.g.cs` never exists (generator output is in-memory only).

## 4. The markup language: same `.guitkx`, embedded language = C#

Decision (recommended): **keep the `.guitkx` extension** — the family convention is
extension-per-ENGINE (`.uitkx`/`.uetkx`/`.guitkx`), embedded language is a property of the leg.
Mode detection, in priority order:
1. `guitkx.config.json` walk-up gains `"lang": "csharp" | "gdscript"` (default `gdscript` —
   fully backward compatible).
2. Tooling heuristic: a sibling/ancestor `*.csproj` with the generator package ⇒ csharp.

A project uses ONE mode; mixing legs in one project is out of scope (flagged loudly by both
compilers if both ever see the same tree). The grammar (tags, attrs, directives, imports,
`export`, comments) is byte-identical — only the embedded-expression language differs, exactly
the Unity↔Godot relationship today, already pinned by the shared corpus.

**Formatter/indentation (new):** GDScript-mode `.guitkx` is TAB-indented (embedded GDScript
requires tabs). C#-mode has no such constraint, and the Unity leg's canonical style is
spaces-2. The formatter is already option-driven on both implementations — the rule becomes:
**canonical style is per MODE** (`lang: csharp` ⇒ spaces-2 default, tabs ⇒ gdscript), with
`guitkx.config.json` overrides as today. The C# canonical style is pinned by the Tests.Generator
formatter snapshots (D8 confirms the default).

**E-01 signature classification, C# spelling** (mirrors the Unity leg exactly):
- component: `Name(params) -> RuiNode { … }` (the return-type annotation IS the classification)
- hook: `useX(params)[ -> T] { … }` (camelCase `use` prefix)
- util: any other callable declaration
- value: `Type name = expr;` / `var name = expr;` (initializer-classified)
- `export` marks cross-file visibility; full ES import surface (named/renamed/`* as`/default/
  combined) identical to the family.

**Directives:** `@if/@elif/@else/@for/@while/@match/@case/@default` unchanged (bodies are C#
prep + `return ( <markup> )`, the Phase-D family grammar). `@uss`/`@theme` carries over with a
Godot meaning identical to the GDScript leg (a `Theme` resource applied to the component root —
`Host/ThemeApplier`). `@class_name` is GDScript-specific and is NOT part of C# mode; its C#
counterpart is `@namespace` (below). This is the ONE deliberate grammar asymmetry between the
two Godot legs; the corpus encodes it as mode-gated cases.

**Namespace derivation (new — was missing):** generated classes need namespaces. Unity derives
file-keyed namespaces from folders relative to the owning `.asmdef` + file stem, with a
`@namespace` override. Godot has no asmdef; the anchor becomes **folders relative to the
csproj** (RootNamespace + relative path segments), same override directive. Import lowering
emits the target's derived namespace; renames of FOLDERS therefore change identity exactly as
on Unity (documented, not a surprise). (D9 confirms this vs a flat single-namespace scheme.)

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
`On_<signal>` verbatim escape. Hooks/API casing per D6 (recommended: Unity spelling,
`useState`, auto-injected usings in generated code).

## 5. Runtime (`ReactiveUITK.Godot`) — port map

Source of truth = **our GDScript runtime** (Godot-faithful semantics), idioms = Unity's C# leg.

| GDScript source (LOC) | C# target | Notes |
|---|---|---|
| `vnode.gd` (immutable RUIVNode) | `VNode.cs` | Match Unity's `VirtualNode` field shape where identical |
| `v.gd` (71 factories, 252) | `V.cs` | `V.Func`, `V.Fragment`, `V.Text`, `V.H(string, props)` open-vocabulary factory + curated named factories GENERATED from `vocabulary.json` (a build step, not hand-written) |
| `reconciler.gd` (1146) | `Fiber/Reconciler.cs` | Same begin/complete/commit phases, bailout, keyed reconciliation, effect ordering, coalesced one-re-render-per-frame. Optional time-sliced render phase (`Config.TimeSlicing`) ports too; commit stays atomic. **Props equality for bailout defined explicitly** (Unity's helpers as reference — reference-equality fast path + shallow structural compare; document it, don't leave it to `Equals` accidents) |
| `fiber.gd` | `Fiber/FiberNode.cs` | D5 RESOLVED: Unity's double-buffer alternates (`FiberNode.Alternate`) — the C#-natural design; GDScript's fresh-fibers was a GC/cycles workaround, not family semantics. Observable behavior identical (parity-suite scope) |
| `hooks.gd` (596, 23 hooks) | `Hooks.cs` | Positional slots, same validation config |
| `config.gd` (RUIConfig) + `diagnostics.gd` | `Core/Config.cs`, `Core/Diagnostics.cs` | Hook-validation / strict-diagnostics / time-slicing toggles — was missing from the v1 table |
| `host_config.gd` (543) | `Host/GodotHostConfig.cs` | Seam = Unity's abstract `FiberHostConfig` (object handles). Implementation = ClassDB port: `ClassDB.Instantiate(type)`, recycle-with-default-reset via cached `ClassDB.ClassGetPropertyDefaultValue`, `obj.Set(StringName, Variant)`, `IsInstanceValid` guards throughout |
| — (new) | `Host/VariantConvert.cs` | The C#-specific layer GDScript never needed: prop values → `Variant` (`Variant.From<T>`, Godot collections, `Callable.From` for delegates), with clear errors for non-marshallable types. StringName interning table for every prop/signal name touched (mirrors Godot's own `PropertyName.*` codegen pattern) — built in from day one |
| `style.gd`/`style_sheet.gd` (346+) | `Host/StyleApplier.cs` + `Style` typed dict | Port Unity's `Style`/`CssHelpers` ergonomics onto Godot key space (exact property/theme/StyleBoxFlat names); engine-version-gated keys guard via `ClassDB.ClassExists`/property probe (FoldableContainer pattern) |
| `@uss`/`@theme` wiring | `Host/ThemeApplier.cs` | Theme resource on the root element — parity with GDScript leg |
| events (in host_config) | `Host/EventBinder.cs` | `On`+Pascal→snake signal, `Callable.From`, disconnect-on-diff, generic over any signal (no alias table). **Lifetime note:** connected lambdas capture component scope — the binder owns disconnect on unmount/diff so freed nodes never hold C# closures (and vice versa) |
| items/draw_fn | `Host/ItemModels.cs`, `Host/DrawTrampoline.cs` | 1:1 |
| `router/` (17 hooks) | `Router/` | Port; Unity `Router/` as C# reference |
| `signal_store/registry` | `Signals/` | |
| `suspense.gd`, `media.gd` | `Suspense/`, `Media/` | Media maps to `AudioStreamPlayer`/`VideoStreamPlayer` same as GDScript leg |
| `reactive_root.gd`/`_node.gd` | `ReactiveRoot.cs` + `[GlobalClass] ReactiveRootNode` | `ReactiveRoot.Create(Control container, VNode root)`; the root owns the **frame pump** (`_Process`/`CallDeferred` scheduling of the coalesced re-render — the GDScript leg's request_update loop, spelled in C#) |
| — (new) | `Refresh/` | Unity's `Refresh.Family` + `RefreshRuntime` identity model, needed for HMR swap (§8); compiled into game builds under `#if DEBUG`, no-op in release |

**Error boundaries (D7 RESOLVED — auto-catch):** the C# leg implements TRUE React error
boundaries, exactly as the Unity leg does (verified: `FiberReconciler` catches render
exceptions → `FindNearestErrorBoundary` → fallback activation, including the HMR
old-body-also-failed path — port that whole mechanism). The GDScript leg's STRUCTURAL
boundaries are the engine-imposed divergence (no exceptions in GDScript) and are recorded as
such in the documented-divergences table; the parity suite excludes this scenario by design.
`useTransition`/`useDeferredValue` stay synchronous (family rule).

Estimate: 4.8k GDScript → **~8–10k C#** (types + docs headers inflate; Refresh/ and
VariantConvert are additive).

## 6. Host layer — why 30k becomes ~1.2k

Unity: closed `ElementRegistry` of 54 hand-written typed adapters + 62 typed props classes,
because `VisualElement` subclasses have bespoke, non-uniform APIs.
Godot: every Control property is settable via `GodotObject.Set`, every signal connectable by
name, every class instantiable via `ClassDB` — our GDScript leg's whole host is 543 LOC with
an **open vocabulary** (any ClassDB Node class is a valid tag, curated set only for IDE
metadata). The C# port keeps exactly this: no adapters, no registry, no per-element props
classes. Typed niceties (e.g. `Style`) sit ABOVE the generic applier, not instead of it.
Perf posture: `Set(StringName, Variant)` marshals per call — the same cost class the GDScript
leg already pays via `node.set()`; diffing applies only changed keys; StringName interning
(§5) removes the string-alloc half. GC pressure from per-render closures/dicts is accepted
for v1 (non-goal §0) with `stat`-style counters in `Diagnostics` so it's measurable.

## 7. Source generator (`ReactiveUITK.Godot.Generator`)

Fork of Unity's `SourceGenerator~` (IIncrementalGenerator, 12.1k LOC), with:
- **Input**: `.guitkx` + `guitkx.config.json` as `AdditionalFiles`, injected by the NuGet
  package's `build/*.props` (standard MSBuild) with excludes for `.godot/**`, `bin/**`,
  `obj/**`, `addons/**`. This REPLACES Unity's `UitkxCsprojPostprocessor` (Unity rewrites
  csproj constantly; Godot doesn't touch the user's csproj — cleaner on our side). The config
  file supplies `~/` root resolution and confirms `lang: csharp`.
- **Scope rule (v1):** imports resolve within ONE compilation (the csproj's AdditionalFiles
  set). Multi-project games consume other assemblies' components as normal C# (`using` the
  generated classes) — `.guitkx` `import` across csproj boundaries is out of scope and
  diagnosed clearly (GUITKX2305 with a "different project" hint).
- **TagResolution retarget**: Unity's five kinds collapse — curated-known tag →
  `V.<Name>(props…)` named factory; unknown-but-plausible tag → `V.H("Name", …)` (open
  vocabulary, runtime-validated — mirrors `V.h`). The generator cannot query ClassDB (no
  engine at compile time), so it bakes the **ClassDB dump** we already ship for the TS LSP +
  `vocabulary.json` (single-source; copy step + byte-sync tripwire, same pattern as the
  existing vocabulary sync test; refresh folded into the `add-godot-version` skill).
- **Emitter retarget**: emitted preamble becomes `using Godot;` + our namespaces + the
  auto-injected hook usings; expression holes stay verbatim C# (unchanged machinery); props
  emit through `Style`/dictionary paths per §6.
- **HMR-safe emission from day 1** (Unity 0.14 lessons, non-negotiable):
  - **values lower as inline functions/getters, never `static readonly` fields** — otherwise
    HMR edits silently don't apply (TB-15); `StaticReadonlyStripper` comes along in the fork;
  - **stable `<Name>_Impl` shim + content-hashed `<Name>_Body_<hash>`** owning all lambdas —
    old closures can never run wrong-layout code after a swap (TB-21/23);
  - `[ModuleInitializer]`-published Family handles for identity.
- **AOT safety**: emitted code and the runtime use no `Reflection.Emit`, no runtime codegen —
  delegates + static calls only (iOS/NativeAOT clean). Reflection exists ONLY in the HMR swap
  path, which is `#if DEBUG`-gated out of release builds.
- **Diagnostics**: GUITKX numbering (shared vocabulary.json severities); **Roslyn IS the
  delivery channel** — errors/warnings surface in `dotnet build`, the IDE Problems panel, and
  the Godot editor's build output natively. No `.diags.json` sidecars on this leg at all (a
  genuine simplification vs the GDScript leg; the editor-addon sidecar overlay is N/A).
- **Namespace derivation** per §4; `@namespace` override honored.
- Peer-file model (imports/exports) carries over intact — same ES-modules Layer 2 (E-01…E-12).

Output shape (per Unity precedent): `partial class Counter` + `public static VNode Render(…)`
+ `__Exports` container for values/hooks + Family handles. Nothing generated is committed
(unlike Unreal's `.inl`; like Unity).

## 8. HMR — design (the part that needs real engineering)

Unity's pipeline, re-plumbed for Godot's two-process topology:

```
[Godot editor process — addons/reactive_ui_csharp (GDScript, @tool)]
  1. FileSystemWatcher on **/*.guitkx (mode=csharp projects only)
  2. On save during a debugger-attached play session:
     shell out to `dotnet build` of a generated micro-project
     (addons/reactive_ui_csharp/hmr/.rui-hmr.csproj, gitignored) that compiles ONLY the
     changed file's generated C# against:
       - .godot/mono/temp/bin/Debug/<AssemblyName>.dll   (the game's last build)
       - the ReactiveUITK.Godot + GodotSharp references from the project's own restore
     (Unity does this with in-process Roslyn; we use the dotnet CLI — no Roslyn shipping
     inside the addon; ~2–4s cold / <1s warm)
  3. EditorDebuggerSession.send_message("rui_hmr:reload_cs", [dll_path, swap_manifest])
     — session loop + dedup + "-> N session(s)" logging lifted from hmr_debugger.gd
[Game process — ReactiveUITK.Godot Refresh/ (#if DEBUG)]
  4. C# runtime debugger-message handler receives the path
  5. new AssemblyLoadContext(isCollectible: true).LoadFromAssemblyPath(dll)
  6. Swap __hmr_* delegate fields / Family handles → RefreshRuntime.PerformRefresh()
     (state preserved via positional hook slots; hook-shape edits reset that component
     with a notice — the family rule, TB-13)
  7. Old ALCs intentionally stay alive (unload is unreliable) — leak until stop, same as Unity
```

Edge handling (all with Unity/GDScript-leg precedent):
- **Stale-build gate**: HMR requires a successful prior `dotnet build`; the addon checks the
  output dll's mtime on play start and triggers a build (or warns) if the project is stale.
- **No play session** → do nothing; the next normal build picks the change up (the generator
  runs in every `dotnet build` — there is NO compile-on-save watcher on this leg at all
  outside HMR; that's a simplification vs the GDScript addon, not a gap).
- **Compile errors** during HMR → addon toast/log with the Roslyn output verbatim; one
  coalesced notification on rapid saves (TB-26 lesson).
- **Multiple play sessions** → push to every active session (existing wire behavior).
- **Value edits** propagate because of function-lowering (§7); consumer recompiles ride the
  same importer-cascade logic the family already implements (refresh_roots equivalent).

## 9. IDE tooling

- **Grammar/TextMate**: the existing `guitkx.tmLanguage.json` gains a C#-embedded injection
  variant (the Unity grammar is the donor; markup scopes identical).
- **LSP**: D3 — recommended: fork **Unity's C# LSP server** (13.6k, OmniSharp + Roslyn
  workspaces) as `ide-extensions/csharp-lsp`, swap vocabulary + specifier rules + ClassDB dump.
  It already does embedded-C# intelligence (virtual-doc → Roslyn), which our TS server cannot
  (its embedded tier is GDScript-analyzer-native). The VS Code extension picks the server by
  project mode (`lang` from guitkx.config.json). The TS server stays untouched for
  GDScript-mode projects. Specifier path completion ships with the Unreal-derived spec
  (nearest-first, replace-not-append — GAP-ISO-2) from day 1.
- **VS2022**: same VSIX pattern as today, bundling the C# server for csharp-mode projects.
- **Rider**: the C# audience skews Rider-heavy and the Unity leg HAS a Rider plugin lane
  (1.3.0). Deferred to post-v1 (D10) — retargeting Unity's Rider plugin is the known path.
- **In-Godot editor view**: the `reactive_ui_editor` addon's `.guitkx` view/tokenizer works on
  markup + treats embedded code lexically — usable as-is for C# mode minus embedded
  intelligence; full parity is a non-goal for v1 (VS Code/VS2022/Rider are the C# audience's
  editors anyway). Compiler diagnostics reach the Godot editor via the build panel natively
  (Roslyn channel, §7).
- **Third-party notices**: csharp-lsp ships OmniSharp/Roslyn — NOTICES file added (M8).

## 10. Tests + parity

| Suite | Runner | What |
|---|---|---|
| `Tests.Generator` | xUnit, pure .NET (CI-cheap) | Fork of Unity's generator tests: pipeline, emitter snapshots (including the HMR-emission shape: shims, hashed bodies, value-as-function), formatter canonical-style snapshots, diagnostics |
| Scanner/corpus | already covered | The C# `.guitkx` scanner is Unity's `language-lib`, ALREADY pinned by `family-corpus.hash`; mode-gated cases (e.g. `@class_name` vs `@namespace` asymmetry) added at the next family corpus wave |
| `Tests.Runtime` | headless **.NET-build** Godot (a bootstrap Node/SceneTree entry mirroring `tests/*.gd` quit(code) pattern) | reconciler/hooks/host/style/events on real Controls; IsInstanceValid/lifetime cases; Variant conversion table |
| **Cross-leg parity suite** | both runtimes | The rot-prevention gate: a **shared data-driven scenario table** (JSON checked in once, consumed by `tests/core_test.gd` AND `Tests.Runtime`) asserting identical observable sequences — mount/diff order, keyed moves, bailout hits, effect ordering, null render, unmount cleanups. Documented divergences (D7 error boundaries) are excluded BY the table, so an accidental divergence cannot hide behind a deliberate one. New infrastructure ~1–2k, non-negotiable from M4 |
| Demo battery | headless .NET Godot | `demos_test` equivalent over `csharp/demo` |
| Addon tests | GDScript | `reactive_ui_csharp` watcher/driver logic with a stubbed dotnet driver (mirrors guitkx_editor_test patterns) |

## 11. Packaging + distribution

- **NuGet**: `ReactiveUITK.Godot` (runtime) + `ReactiveUITK.Godot.Generator` (analyzer package
  with the props injection). Bare `ReactiveUI.*` ids are OFF the table (taken on NuGet by the
  Rx MVVM framework). Package metadata: license file (Community License), icon, README,
  SourceLink + snupkg symbols (cheap, expected by .NET users).
- **GodotSharp floor policy (new — D11)**: build against the FLOOR version (GodotSharp 4.4.x)
  so the package runs on every supported engine; newer-engine features (e.g. 4.5's
  FoldableContainer) are runtime-guarded via ClassDB probes exactly like the GDScript leg —
  never compile-time references above the floor. CI tests floor AND latest engine (§12).
  Revisit multi-targeting only if a future engine minor breaks binary compat.
- **AssetLib / Godot Asset Store**: one new listing for `addons/reactive_ui_csharp` (the HMR
  addon) with an explicit ".NET build required; library installs via NuGet" description; the
  demo zip attached to GitHub releases.
- **GitHub releases**: `csharp-v*` tag lane in publish.yml → `dotnet pack` + `nuget push`
  (new `NUGET_API_KEY` secret) + addon zip. Changelog: new `csharp` lane in `changelog.json`
  extracting to `csharp/CHANGELOG.md`; changelog.mjs verify gains the target; root
  CHANGELOG.md remains the GDScript library's.
- **License**: ReactiveUI Community License 1.0 across all of it; CLA unchanged.

## 12. CI + sync discipline

- `test.yml`: new `csharp` job, **path-filtered** (`csharp/**`, `addons/reactive_ui_csharp/**`,
  shared vocabulary/corpus/grammar paths) so GDScript-only PRs pay nothing. Steps:
  setup-dotnet → `dotnet test Tests.Generator` → download `_mono_` Godot (FLOOR version) →
  `Tests.Runtime` + parity + demo battery → repeat runtime tests on LATEST engine (matrix).
- **Sync tripwires** (house pattern, all byte-compare):
  - `vocabulary.json` ↔ generator-baked copy;
  - ClassDB dump ↔ generator copy;
  - parity-scenario JSON ↔ both consumers reference the same file (no copies);
  - **vendored language-lib drift-check**: a script comparing `csharp/ReactiveUITK.Godot.Language/`
    against a PINNED Unity-repo commit hash recorded in the tree — family fixes (like the
    null-only scanner change or specifier completion) sync by bumping the pin deliberately,
    never by silent divergence. Same spirit as `family-corpus.hash`.
- `.editorconfig` under `csharp/` from M0 so style never churns later.

## 13. Versioning

Two new lanes: `ReactiveUITK.Godot` NuGet version (runtime+generator lockstep) starting
**0.1.0**, and `addons/reactive_ui_csharp/plugin.cfg`. Both patch-by-default per house policy;
independent of the GDScript lanes. The engine floor (4.4) and verified-engine list ride the
same `add-godot-version` runbook as everything else.

## 14. Docs + positioning

- Docs site: a "C#" section — getting started with the .NET build, csproj + NuGet setup, the
  same teaching pages with C# holes, HMR page, and the **"GDScript leg vs C# leg — which?"**
  page (web export, hot-reload nuance, team language, platform matrix) to prevent
  mis-adoption. A **"documented divergences"** table (D7 etc.) lives here too.
- README: reposition from "no C#/.NET needed" to "GDScript-native AND C#-native; the standard
  build needs no .NET" — the current selling point survives, scoped to the GDScript leg.
- Demo/gallery scope for v1 (bounded on purpose): counter, todo, keyed, styling, context,
  router, signals, effect-order, portal, suspense — i.e. the teaching core, NOT the full
  45-demo gallery and NOT the Doom port (both are post-v1 stretch; Doom would be a strong
  marketing piece for the C# audience later).

## 15. Milestones (each gated like every campaign: build green + suites + changelog staged)

| M | Deliverable | Est. new/changed LOC |
|---|---|---|
| M0 | Scaffold: `csharp/` tree + `.gdignore` + `.editorconfig` + gitignore, csprojs, CI job, ALL sync tripwires (vocab/dump/language-lib pin), demo project boots empty | ~500 + config |
| M1 | Core port: VNode/V/Fiber/Hooks/Config/Diagnostics + `Tests.Runtime` bootstrap green headless | ~4k |
| M2 | Host layer: GodotHostConfig/VariantConvert/Style/Theme/Events/items/draw; counter demo renders + interacts | ~2k |
| M3 | Generator retarget end-to-end: `.guitkx`→C#→running demo; namespace derivation; HMR-safe emission shape; `Tests.Generator` snapshot suite ported | ~3k delta |
| M4 | Subsystems: Router/Signals/Suspense/Media + error-boundary decision implemented + **cross-leg parity suite** | ~4k |
| M5 | HMR: addon + dotnet driver + wire + ALC swap + stale-build gate; mid-play edit demo | ~2.5k |
| M6 | IDE: csharp-lsp fork + VS Code mode routing + grammar injection + specifier completion spec | ~2k delta |
| M7 | Docs + demo subset + "which leg" page + divergences table | content |
| M8 | Packaging: NuGet publish lane (+secret), AssetLib listing, changelog lane, NOTICES, release 0.1.0 | config |

Sequenced M0→M3 first (proves the thesis end-to-end on the counter demo before the long tail).
Rough shape: comparable to the Unreal Phase-0→2 arc, i.e. a quarter-scale campaign.

## 16. Risks

| Risk | Mitigation |
|---|---|
| Runtime parity rot between the two Godot legs | Data-driven parity suite (§10) required from M4; divergences must be table-listed or they fail the gate |
| Family lockstep cost grows (4th toolchain) | Same-repo residency + shared corpus/vocabulary make grammar changes atomic for both Godot legs; the C# scanner is Unity's, already family-gated; vendored-lib PIN makes sync deliberate |
| Vendored language-lib silently diverges from Unity | Pinned-commit drift-check in CI (§12) |
| HMR ALC leaks / swap edge cases | Accepted-by-design leak (family precedent); delegate-trampoline emission proven on 2 legs; stale-build gate; hook-shape reset rule |
| GodotSharp binary compat across engine minors | Floor-build policy + floor/latest CI matrix (D11); runtime ClassDB probes for newer-engine features |
| Node lifetime vs C# wrappers (freed-node crashes) | IsInstanceValid discipline in host + lifetime cases in Tests.Runtime |
| GC pressure from per-render allocations | Accepted v1 posture + Diagnostics counters; pooling is a measured later step |
| Generator vocabulary/dump staleness vs engine versions | `add-godot-version` skill extended to refresh the baked copies (tripwired) |
| NuGet name/brand collision with ReactiveUI (MVVM) | `ReactiveUITK.*` ids; never bare `ReactiveUI` |
| Demand uncertainty (~16% × Godot) | Plan parked until licensing signal (§0); M0–M3 doubles as a cheap validating spike |

## 17. Owner decisions

**Governing directive (owner, 2026-07-27): "as close as it can be to Unity parity."** That
resolves D1, D3–D9 to the Unity-parity option; parity claims verified in Unity source where
they were assumptions (error boundaries DO auto-catch — `FiberReconciler.cs` catch→
`FindNearestErrorBoundary`; fibers DO double-buffer — `FiberNode.Alternate`). Scope note:
parity means API/toolchain/semantics — the ELEMENT vocabulary stays Godot-native (tags are
Godot class names; it renders Controls, not VisualElements), exactly as `.uetkx` tags are
Slate-native.

| # | Decision | Resolution |
|---|---|---|
| D1 | Package naming | **RESOLVED**: `ReactiveUITK.Godot` / `.Generator` (family name; bare `ReactiveUI` is taken on NuGet) |
| D2 | Go / timing | **OPEN** — parked vs scheduled (not a parity question) |
| D3 | LSP base | **RESOLVED**: fork Unity's C# server |
| D4 | language-lib consumption | **RESOLVED**: vendored Unity fork + pinned-commit drift check |
| D5 | Fiber allocation | **RESOLVED**: Unity's double-buffer alternates (verified: `FiberNode.Alternate`). The GDScript leg's fresh-fibers is a GDScript-imposed divergence, not family design; observable behavior identical, parity suite unaffected. §5 table updated |
| D6 | Hooks casing | **RESOLVED**: `useState` (Unity C# spelling); pinned in corpus at the next family wave |
| D7 | Error boundaries | **RESOLVED**: TRUE auto-catch (verified: Unity does exactly this, incl. the HMR old-body-failed path). The documented-divergences table now describes the GDScript leg as the diverging one (engine-imposed) |
| D8 | C#-mode canonical formatting | **RESOLVED**: spaces-2 (Unity-exact), config-overridable |
| D9 | Namespace derivation | **RESOLVED**: file-keyed from csproj-relative folders + `@namespace` override (Unity model) |
| D10 | Rider plugin | **OPEN** — Unity parity implies Rider *eventually* (the family lane exists at 1.3.0); question is v1 scope vs post-v1 |
| D11 | GodotSharp reference policy | **OPEN** — Godot-specific, no Unity analog: floor (4.4) + runtime probes + floor/latest CI matrix (recommended) vs multi-targeting per engine minor |
