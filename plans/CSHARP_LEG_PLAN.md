# Reactive UI Toolkit — Godot (C#) — design + execution plan

**Status: PLAN, not scheduled.** D2 (go/timing) is owner-triggered; only D2 remains open.
Umbrella branding (owner, 2026-07-27): everything in the family rebrands under **Reactive UI
Toolkit** (GitHub org `reactive-ui-toolkit`); this deliverable's display name is
**"Reactive UI Toolkit — Godot (C#)"**, and it lives in its **own repo under the org**
(D12 RESOLVED — §3). Governing technical directive (owner, 2026-07-27): **as close as possible
to Unity parity** — every design choice below defaults to the Unity leg's answer unless Godot
physically forbids it; the two load-bearing parity facts were verified in Unity source, not
assumed (§17 D5/D7). When the repo is born, THIS plan file moves there with it.

**One-line pitch:** the same `.guitkx` markup and the same React model, with **embedded C#**
instead of embedded GDScript — the Unity leg's proven C# toolchain retargeted onto Godot.

---

## 0. Goals / non-goals

**Goals**
- A C#-native Reactive UI for the Godot .NET build: `.guitkx` components with embedded C#,
  compiled to C# by a Roslyn source generator at `dotnet build` time, rendered by a C# runtime
  port of our reconciler against the real `Control` tree.
- **Unity-parity API**: public types/classes mirror the Unity leg 1:1 wherever engine-neutral
  (`VirtualNode`, `V`, `V.Func`, `useState`, `FiberHostConfig`, `Style`/`CssHelpers`…), and the
  embedded-C# declaration grammar is BYTE-COMPATIBLE with `.uitkx` (same scanner, same corpus).
  Element/prop/event naming stays Godot-loyal (`<VBoxContainer>`, `Text`, `OnPressed`) — the
  vocabulary is per-engine, exactly as `.uetkx` tags are Slate-native.
- Shared grammar, vocabulary, contract corpus, diagnostics numbering, docs, license, release
  discipline with the rest of the family (mechanics depend on residency, §3).
- HMR parity with the family (save `.guitkx` mid-play → UI updates, state preserved).

**Non-goals**
- No authoring API beyond what falls out naturally (`V.*` is public anyway, as on Unity).
- No web export story (platform limitation — C# cannot export to web as of 2026-07; prototypes
  only). The GDScript leg remains the answer there.
- No interop bridge to the GDScript runtime (rejected 2026-07-27: `Call()`/`Get`/`Set`
  string-typing, no cross-language inheritance, Variant marshalling per render).
- No wrapper-keyword grammar, ever: the leg is born post-ES-modules — plain E-01 declarations
  only, no deprecation window, no migration codemods (no legacy exists).
- No render-allocation pooling in v1 (Unity leg ships the same posture — measure first).
- The GDScript leg changes ZERO bytes. Standard-build users are unaffected forever.

## 1. Platform facts (verified 2026-07-27)

| Fact | Detail |
|---|---|
| Engine build | C# requires the **.NET build** of Godot (separate download + export templates). Floor **4.4** (D11 RESOLVED — same as the GDScript leg); GodotSharp NuGet versions track the engine (4.7.1 current) |
| Runtime | .NET 8+ (Android export needs .NET 9) |
| Platforms | Desktop full; Android/iOS experimental (iOS = NativeAOT ⇒ shipped code must be AOT-safe, §7); **web unsupported** for C# |
| Project shape | Game csproj: `<Project Sdk="Godot.NET.Sdk/4.x.x">`. **Library** packages reference the `GodotSharp` NuGet and ship as normal NuGet packages — explicitly supported |
| Source generators | First-class; Godot's own `Godot.SourceGenerators` coexists with user analyzers |
| Runtime assembly loading | `AssemblyLoadContext` works in editor-run and exported games; unload is unreliable .NET-wide → HMR keeps old contexts alive (Unity-leg posture) |
| Build output path | Game assembly lands under `.godot/mono/temp/bin/<Config>/<AssemblyName>.dll` — the HMR compile references it (§8) |
| Preprocessor symbols | `GODOT`, `TOOLS` (editor), `DEBUG` — used to strip the HMR receiver from release builds (§8) |
| Editor plugins in C# | Documented as "quite convoluted" → our editor addon stays **GDScript** (§8) |
| C#↔GDScript | No inheritance across languages; stringly `Call/Get/Set` — why the bridge was rejected |
| Attributes | `partial` mandatory; `[Tool]`, `[GlobalClass]`, `[ModuleInitializer]` available |
| GodotObject lifetime | Freed nodes leave dangling C# wrappers — every reconciler touch guards `GodotObject.IsInstanceValid` (ports the GDScript leg's discipline) |
| CI binaries | godotengine releases ship `_mono_` (.NET) editor builds for headless CI |

## 2. Measured inventory — what the family already owns (2026-07-27)

### Unity leg (`…\ReactiveUIToolKit`)

| Piece | Size | Engine coupling | Reuse verdict |
|---|---|---|---|
| `ide-extensions~/language-lib` (parser 8.3k, formatter 3.9k, Roslyn glue 3.4k, diagnostics 1.8k, semantic tokens 1k, IntelliSense 0.8k) | 36 files / **21.6k LOC** | `netstandard2.0`, no Unity refs | **SHARE — consume as-is** (vocabulary + specifier rules parameterized) |
| `SourceGenerator~` (IIncrementalGenerator pipeline + Emitter/{CSharpEmitter, HookEmitter, ModuleEmitter, ExportsEmitter, PropsResolver, TagResolution, StructureValidator, HooksValidator, StaticReadonlyStripper}) | 25 files / **12.1k LOC** | Unity ONLY in emitted string literals | **FORK + retarget emitters** (~2–3k LOC delta) |
| `ide-extensions~/lsp-server` (OmniSharp + Roslyn workspaces = embedded-**C#** intelligence) | **13.6k LOC** | Engine-agnostic analysis | **FORK + vocabulary swap** (D3 RESOLVED) |
| `Editor/` HMR machinery (Roslyn compile → `Assembly.Load` → `__hmr_*` delegate swap → `RefreshRuntime.PerformRefresh()`; `[ModuleInitializer]` Family identity; static-readonly stripper) | **15.8k LOC** (incl. non-HMR) | Compile+swap pure .NET; trigger Unity-editor | **PORT the pattern**, new topology (§8) |
| `Shared/Core` runtime (Fiber 4.4k incl. `FiberNode.Alternate` double-buffer + auto-catch error boundaries, Router 2.1k, Refresh 1.1k, root 6.3k…) | 69 files / 16.3k LOC | `VisualElement` ×118 — NOT copyable | **Primary REFERENCE**; algorithms + C# idioms + class names come from here (D5/D7) |
| `Shared/Elements` + `Shared/Props` (54 typed adapters + 62 props classes + `ElementRegistry`) | **30.1k LOC** | Fully Unity | **DISCARD — Godot doesn't need it** (§6) |
| `Runtime/` MonoBehaviour adapter | 536 LOC | Unity | Mount-surface reference |
| `FiberHostConfig` seam (abstract, `object` handles; uGUI backend 6.2k proves a second host) | — | — | **COPY verbatim** |
| HMR emission lessons (0.14): values lower as **inline functions** (TB-15); stable shim + content-hashed body (TB-21/23); hook-shape edit ⇒ clean reset (TB-13) | — | — | **DAY-1 GENERATOR MANDATES** (§7, §8) |

### Godot GDScript leg (this repo)

| Piece | Size | Reuse verdict |
|---|---|---|
| Runtime `addons/reactive_ui/core` (reconciler 1146, hooks 596, host_config 543, style 346, v 252, router/signals/suspense/media/config/diagnostics…) | 26 files / **4.8k LOC** | **Godot-semantics source** (what maps to which Control/theme/signal); algorithm shape defers to Unity where they differ (D5/D7) |
| `host_config.gd` mapping knowledge: `ClassDB.instantiate` open vocabulary, `node.set(k,v)`, class-default recycle cache, `on`+Pascal→signal (no alias table), items→models, draw_fn trampoline | 543 LOC | **The crown jewel** — ports ~1:1 to `Godot.ClassDB` / `GodotObject.Set(StringName, Variant)` / `Connect` |
| `.guitkx` grammar + `vocabulary.json` + ClassDB dump (already shipped for the TS LSP) + contract corpus (66 goldens) + GUITKX numbering | — | **SHARED BY CONSTRUCTION** — the C# *scanner* is Unity's, already family-corpus-pinned |
| Editor addon HMR wire: `EditorDebuggerSession` `rui_hmr:*` messages, session loop + dedup + logging | — | **COPY the wire**, new payload (§8) |
| publish.yml (tag-gated lanes), changelog.mjs (multi-lane), test.yml, `add-godot-version` skill (ClassDB dump refresh) | — | **EXTEND** (mechanics depend on residency §3) |

**The core economic fact:** Unity spent 30.1k LOC on Elements/Props because UI Toolkit needs a
typed adapter per element. Godot's reflective `ClassDB` surface does the same job in ~1.2k with
an OPEN vocabulary — our GDScript leg proves it in 543+346 lines. That collapse is why this leg
is feasible at quarter scale.

## 3. Residency — RESOLVED (D12): dedicated repo under the org

**Decision (owner, 2026-07-27): a new repo** — e.g. `reactive-ui-toolkit/ruitk-godot-csharp` (owner
names it). Rationale, re-examined and confirmed: the C# leg shares **zero code files** with the
GDScript repo (runtime = Unity-Core port, compiler = Unity's generator, LSP = Unity's server,
addon = new) — it shares *contracts* (grammar, vocabulary, dump, corpus, numbering), and those
already sync across three repos via pins; a fourth consumer is incremental. The GDScript repo's
"pure GDScript, no .NET" identity stays clean; repo-per-product matches the org umbrella; fresh
history under the org. The one real coupling — the VS Code/VS2022 extensions serve BOTH Godot
legs — is solved by the family's existing artifact-bundling pattern (§9).

**What stays in the GDScript repo:** the GUITKX extensions (gaining C#-mode routing, §9);
`vocabulary.json` + the ClassDB dump as **source of truth** (the C# repo pins them by hash);
the parity-scenario JSON source (§10); the "which leg?" docs page. Future option once the org
exists: a `family-contract` repo holding corpus + vocabulary sources that all four product
repos pin — natural end-state, not needed for v1.

```
(dedicated-repo layout — reactive-ui-toolkit/ruitk-godot-csharp)
godot-csharp/
├─ addons/reactive_ui_csharp/       # thin GDScript editor addon — HMR wire only (§8);
│   ├─ plugin.cfg                   #   AssetLib/Store listing zips THIS folder from THIS repo
│   └─ hmr/…                        #   watcher + dotnet driver + debugger-wire push
├─ src/
│   ├─ ReactiveUIToolkit.Godot/     #   runtime library → NuGet
│   │   ├─ ReactiveUIToolkit.Godot.csproj  # net8.0; GodotSharp 4.4.x (D11)
│   │   ├─ Core/                    #   VirtualNode, V, Fiber/, Hooks, Config, Diagnostics,
│   │   │                           #   FiberHostConfig seam, ReactiveRoot
│   │   ├─ Host/                    #   GodotHostConfig, VariantConvert, StyleApplier,
│   │   │                           #   ThemeApplier, EventBinder, ItemModels, DrawTrampoline
│   │   ├─ Router/  Signals/  Suspense/  Media/  Refresh/
│   │   └─ ReactiveRootNode.cs      #   [GlobalClass] Node mount surface
│   ├─ ReactiveUIToolkit.Godot.Generator/  # netstandard2.0 Roslyn generator → NuGet (analyzer)
│   │   ├─ …fork of Unity SourceGenerator~ pipeline…
│   │   ├─ Vocabulary/              #   baked vocabulary.json + ClassDB dump (PIN-synced from
│   │   │                           #   the GDScript repo — hash recorded, CI-checked)
│   │   └─ build/ReactiveUIToolkit.Godot.Generator.props
│   │        # NuGet-injected MSBuild:
│   │        #   <AdditionalFiles Include="**/*.guitkx" Exclude=".godot/**;bin/**;obj/**;addons/**"/>
│   │        #   <AdditionalFiles Include="**/guitkx.config.json"/>  ← `~/` root + lang mode;
│   │        #   user csproj needs ZERO edits (replaces Unity's csproj-postprocessor hack)
│   ├─ ReactiveUIToolkit.Godot.Language/   # vendored Unity language-lib fork + PINNED-COMMIT
│   │                                      #   drift check (§12)
│   └─ csharp-lsp/                  #   fork of Unity's C# LSP server (§9) — released as a
│                                   #   binary artifact the GDScript repo's extensions bundle
├─ tests/
│   ├─ Tests.Generator/             #   xUnit (no engine)
│   └─ Tests.Runtime/               #   headless .NET-build Godot (§10)
├─ demo/                            #   own project.godot (.NET build) + gallery subset (§14)
│   ├─ project.godot
│   ├─ Demo.csproj                  #   Sdk="Godot.NET.Sdk/4.x" + PackageReferences
│   └─ examples/…
├─ Docs~/                           #   own docs site (family pattern — every repo has one)
├─ plans/  scripts/  .github/workflows/  .editorconfig  CHANGELOG.md  DISCORD lane  …
```

**Born-repo checklist** (things a NEW repo needs that same-repo would have inherited — all M0):
instantiated LICENSE ("Reactive UI Toolkit — Godot (C#)" product name) + LICENSE-COMMERCIAL.md
+ CLA.md + CONTRIBUTING.md; README; `dev`/`master` branch model + protect rulesets (admin
bypass, same as siblings); issue templates; changelog machinery (fork `scripts/changelog.mjs`
per the Unreal precedent) + `plans/DISCORD_CHANGELOG.md` lane; publish.yml + test.yml; the
pin files (`family-corpus.hash`, vocabulary/dump pins, language-lib commit pin, parity-JSON
pin); `.gdignore` is NOT needed (no standard-build project here — the demo IS the only Godot
project). `.gitignore`: `**/bin|obj`, `demo/.godot/`, HMR scratch. Version sources: the
csprojs' `<Version>` (runtime+generator lockstep) and `addons/reactive_ui_csharp/plugin.cfg`.

## 4. The markup language: same `.guitkx`, embedded language = C# (Unity grammar, byte-compatible)

**Extension**: keep `.guitkx` — family convention is extension-per-ENGINE; embedded language is
a property of the leg. Mode detection: (1) `guitkx.config.json` gains `"lang": "csharp" |
"gdscript"` (default `gdscript` — fully backward compatible); (2) tooling heuristic: an
ancestor csproj with the generator package ⇒ csharp. One mode per project; both compilers flag
a mixed tree loudly.

**The embedded-C# grammar IS `.uitkx`'s grammar** — same scanner, same declaration shapes,
already family-corpus-pinned. Concretely (E-01, C# spelling — return-type-FIRST, not the
GDScript/Unreal arrow):

- component: `export VirtualNode Name(params) { … }` (return type IS the classification)
- hook: `export (int, Action) useCounter(int initial = 0) { … }` (camelCase `use` prefix)
- util: any other callable declaration
- value: `export Style CardStyle = new Style { … };` (initializer-classified)
- full ES import surface (named/renamed/`* as`/default/combined) identical family-wide.

**Directives**: `@if/@elif/@else/@for/@while/@match/@case/@default` unchanged (bodies = C#
prep + `return ( <markup> );`, Phase-D family grammar). `@uss`/`@theme` carries the GDScript
leg's Godot meaning (a `Theme` resource applied to the root — `Host/ThemeApplier`).
`@namespace` (Unity's directive) replaces GDScript-only `@class_name` — the ONE deliberate
mode asymmetry between the Godot legs, encoded as mode-gated corpus cases.

**Namespace derivation (D9 RESOLVED — Unity model):** file-keyed namespaces derived from
folders relative to the csproj (RootNamespace + path segments) + file stem; `@namespace`
overrides. Folder renames change identity exactly as on Unity (documented).

**Formatter (D8 RESOLVED):** canonical style is per MODE — C# mode = spaces-2 (Unity-exact),
GDScript mode = tabs (embedded GDScript requires them). Config-overridable as today; pinned by
Tests.Generator formatter snapshots.

Component shape (target syntax — note Unity-style declarations):

```
import { Theme } from "./theme"

export VirtualNode Counter(int start = 0) {
    var (count, setCount) = useState(start);
    return (
        <VBoxContainer>
            <Label Text={$"Count: {count}"} Modulate={Theme.Accent} />
            <Button Text="+1" OnPressed={() => setCount(count + 1)} />
        </VBoxContainer>
    );
}
```

Naming rules: tags = exact Godot class names (open vocabulary); props = exact Godot property
names in the C# bindings' PascalCase (`Text`, `Modulate`); events = `On`+PascalCase(signal)
(`OnPressed` → `pressed`), `On_<signal>` verbatim escape. Hooks/API = Unity spelling
(`useState`, D6 RESOLVED), auto-injected usings in generated code.

## 5. Runtime (`ReactiveUIToolkit.Godot`) — port map

**API parity rule (from the directive):** public type/class/member names mirror the Unity leg
1:1 wherever engine-neutral — `VirtualNode`, `V`, `V.Func`, `FiberHostConfig`, `Style`,
`CssHelpers`, hook names/signatures. Godot-specific surfaces (mount, host, engine hooks like
`useTween`/`useSfx`) follow the GDScript leg's Godot loyalty.

| Source | C# target | Notes |
|---|---|---|
| `vnode.gd` / Unity `VNode.cs` | `Core/VirtualNode.cs` | Unity's type, field-for-field where engine-neutral |
| `v.gd` (71 factories) / Unity `V.cs` | `Core/V.cs` | `V.Func`, `V.Fragment`, `V.Text`, `V.H(string, props)` open-vocabulary factory + curated named factories GENERATED from `vocabulary.json` (build step) |
| `reconciler.gd` + Unity `FiberReconciler.cs` | `Fiber/Reconciler.cs` | Unity's algorithm shape (incl. **auto-catch error boundaries** — D7 RESOLVED, port `FindNearestErrorBoundary`/`TryActivateErrorBoundary` + the HMR old-body-failed path) over Godot's commit semantics; coalesced one-re-render-per-frame; optional time-sliced render phase (`Config.TimeSlicing`), atomic commit. **Props equality for bailout defined explicitly** (Unity's helpers) |
| `fiber.gd` + Unity `FiberNode.cs` | `Fiber/FiberNode.cs` | **D5 RESOLVED: Unity's `Alternate` double-buffer** (fresh-fibers was a GDScript GC workaround). Observable behavior identical — parity-suite scope |
| `hooks.gd` (23 hooks) | `Core/Hooks.cs` | Positional slots; Unity casing; Godot-specific hooks (`useTween`, `useSfx`, `useAnimate`, `useSafeArea`, `useSignal`…) keep GDScript-leg semantics |
| `config.gd` + `diagnostics.gd` | `Core/Config.cs`, `Core/Diagnostics.cs` | Hook-validation / strict / time-slicing toggles + alloc/render counters (perf posture measurable) |
| `host_config.gd` (543) | `Host/GodotHostConfig.cs` | Seam = Unity's abstract `FiberHostConfig` (object handles). Impl = ClassDB port: `ClassDB.Instantiate`, recycle-with-default-reset via cached `ClassGetPropertyDefaultValue`, `Set(StringName, Variant)`, `IsInstanceValid` guards throughout |
| — (new) | `Host/VariantConvert.cs` | Prop values → `Variant` (`Variant.From<T>`, Godot collections, `Callable.From` for delegates) with clear errors for non-marshallable types; **StringName interning** for every prop/signal name (mirrors Godot's `PropertyName.*` codegen) |
| `style.gd`/`style_sheet.gd` | `Host/StyleApplier.cs` + Unity's `Style`/`CssHelpers` types | Unity ergonomics over Godot key space (exact property/theme/StyleBoxFlat names); above-floor keys runtime-probed (FoldableContainer pattern, D11) |
| `@uss`/`@theme` wiring | `Host/ThemeApplier.cs` | Theme resource on root — GDScript-leg parity |
| events | `Host/EventBinder.cs` | `On`+Pascal→snake signal; **arity adapters** — `Callable.From` needs concrete delegate shapes, so the binder provides typed bridges for 0..N-arg signals + a trampoline fallback for unusual signatures; disconnect-on-diff/unmount so freed nodes never hold closures |
| items/draw_fn | `Host/ItemModels.cs`, `Host/DrawTrampoline.cs` | 1:1 |
| `router/` (17 hooks) | `Router/` | Unity `Router/` as the C# reference |
| `signal_store/registry` | `Signals/` | |
| `suspense.gd` + Unity suspense | `Suspense/` | **Task-based** (Unity's `pendingTask`/`isReady`/`fallback` mapping + `FiberSuspenseSuspendException` pattern) |
| `media.gd` | `Media/` | `AudioStreamPlayer`/`VideoStreamPlayer`, GDScript-leg semantics |
| `reactive_root*.gd` / Unity `RootRenderer` | `Core/ReactiveRoot.cs` + `[GlobalClass] ReactiveRootNode` | `ReactiveRoot.Create(Control container, VirtualNode root)`; the root owns the frame pump (`_Process`/`CallDeferred` scheduling of coalesced re-renders) |
| Unity `Refresh/` | `Refresh/` | Family handles + `RefreshRuntime`; compiled under `#if DEBUG`, no-op in release |

Estimate: **~8–10k C#** new (types + docs headers inflate; Refresh/VariantConvert additive).

## 6. Host layer — why 30k becomes ~1.2k

Unity needs a typed adapter per element (UI Toolkit APIs are bespoke per class). Godot's
reflective surface — `ClassDB` instantiate, `Set` by StringName, `Connect` by name — lets ONE
generic applier serve an OPEN vocabulary (any instantiable Control), proven at 543+346 LOC in
the GDScript leg. No adapters, no registry, no per-element props classes; typed niceties
(`Style`) sit ABOVE the generic applier. Perf posture: diff applies changed keys only;
StringName interning removes the string-alloc half; per-render closure/dict GC pressure is
accepted v1 (counters in `Diagnostics`).

## 7. Source generator (`ReactiveUIToolkit.Godot.Generator`)

Fork of Unity's `SourceGenerator~` (IIncrementalGenerator, 12.1k LOC), with:
- **Input**: `.guitkx` + `guitkx.config.json` as `AdditionalFiles` via the NuGet package's
  `build/*.props` (excludes `.godot/**`, `bin/**`, `obj/**`, `addons/**`). Replaces Unity's
  csproj-postprocessor; user csproj stays untouched. Roslyn pin: `Microsoft.CodeAnalysis` at
  the lowest version the IDE matrix requires (Unity pins 4.3.1; re-verify against current
  VS/Godot SDK floor at M0).
- **Scope rule (v1)**: imports resolve within ONE compilation. Cross-csproj consumption =
  normal C# `using` of generated classes; `.guitkx` `import` across projects is out of scope,
  diagnosed with a "different project" hint on GUITKX2305.
- **TagResolution retarget**: curated-known tag → `V.<Name>(…)`; unknown-but-plausible →
  `V.H("Name", …)` (open vocabulary, runtime-validated). The generator bakes the **ClassDB
  dump** + `vocabulary.json` (byte-sync tripwired; refreshed by the `add-godot-version` skill).
- **Emitter retarget**: preamble `using Godot;` + our namespaces + auto-injected hook usings;
  expression holes verbatim C#; props through §6 paths; namespaces per §4.
- **HMR-safe emission from day 1** (Unity 0.14 mandates): values lower as inline
  functions/getters (TB-15, `StaticReadonlyStripper` in the fork); stable `<Name>_Impl` shim +
  content-hashed `<Name>_Body_<hash>` owning all lambdas (TB-21/23); `[ModuleInitializer]`
  Family handles.
- **AOT safety**: no `Reflection.Emit`, no runtime codegen anywhere shipped; reflection exists
  only in the `#if DEBUG` HMR swap path.
- **Diagnostics**: GUITKX numbering; **Roslyn IS the delivery channel** — `dotnet build`, IDE
  Problems, Godot build panel. NO `.diags.json` sidecars on this leg (genuine simplification).

Output shape (Unity precedent): `partial class Counter` + `public static VirtualNode Render(…)`
+ `__Exports` container + Family handles. Nothing generated is committed.

## 8. HMR — design

```
[Godot editor process — addons/reactive_ui_csharp (GDScript, @tool)]
  1. FileSystemWatcher on **/*.guitkx (csharp-mode projects only)
  2. On save during a debugger-attached play session:
     `dotnet build` of a generated micro-project (hmr/.rui-hmr.csproj, gitignored)
     compiling ONLY the changed file's generated C# against:
       .godot/mono/temp/bin/Debug/<AssemblyName>.dll + the project's own restored refs
     (dotnet CLI located via PATH/DOTNET_ROOT — the .NET build already requires the SDK;
      ~2–4s cold / <1s warm; no Roslyn ships inside the addon)
  3. EditorDebuggerSession.send_message("rui_hmr:reload_cs", [dll_path, swap_manifest])
     — session loop + dedup + "-> N session(s)" logging lifted from hmr_debugger.gd
[Game process — Refresh/ (#if DEBUG)]
  4. Debugger-message handler receives the path
  5. new AssemblyLoadContext(isCollectible: true).LoadFromAssemblyPath(dll)
  6. Swap __hmr_* delegates / Family handles → RefreshRuntime.PerformRefresh()
     (positional-slot state preservation; hook-shape edit ⇒ clean reset + notice, TB-13)
  7. Old ALCs stay alive by design (unload unreliable) — leak until stop, Unity posture
```

Edges (all with family precedent): stale-build gate on play start (mtime check, build or
warn); no play session ⇒ nothing to do (the generator runs in every `dotnet build` — there is
NO compile-on-save watcher outside HMR on this leg); HMR compile errors ⇒ one coalesced
toast/log with Roslyn output (TB-26); multi-session push; value edits propagate via
function-lowering + importer-cascade recompiles.

## 9. IDE tooling (cross-repo by design)

- **No new marketplace listings**: the existing GUITKX VS Code/VS2022 extensions (GDScript
  repo) gain the C# MODE — grammar injection variant (C#-embedded scopes; Unity grammar is the
  donor) + server routing by `lang` (TS server for gdscript-mode, C# server for csharp-mode).
  Listing copy updates to say both languages.
- **The bundling mechanism** (the one real cross-repo seam, precedented): the `csharp-lsp`
  server lives in the C# repo and is released as a versioned binary artifact; the GDScript
  repo's extension packaging FETCHES it at build time — exactly how the Unreal extension
  bundles clangd (`fetch-clangd.mjs`) and our VS Code extension bundles the napi analyzer. A
  pinned server version in the extension repo makes the dependency explicit.
- **Release choreography** (recorded so it can't surprise anyone): a C#-mode tooling change =
  (1) csharp-lsp release in the C# repo → (2) extension re-bundle + patch bump + Lane B entry
  in the GDScript repo. Two PRs, two repos, one user-visible update.
- **csharp-lsp** (D3 RESOLVED): fork of Unity's server (OmniSharp + Roslyn workspaces),
  vocabulary + specifier rules + ClassDB dump swapped. Specifier path completion ships with the
  family spec (nearest-first, replace-not-append — GAP-ISO-2) from day 1.
- **Rider** (D10 RESOLVED): always AFTER v1 — retarget the Unity Rider lane (1.3.0) when
  demanded.
- **In-Godot editor view**: markup-tier only for C# mode (tokenizer works lexically); embedded
  intelligence is a non-goal for v1 — the C# audience lives in VS Code/VS2022/Rider. Compiler
  diagnostics reach the Godot editor natively via the build panel (Roslyn channel).
- **NOTICES** file for the OmniSharp/Roslyn dependencies (M8).

## 10. Tests + parity

| Suite | Runner | What |
|---|---|---|
| `Tests.Generator` | xUnit, pure .NET | Fork of Unity's generator tests: pipeline, emitter snapshots (incl. HMR emission shape: shims/hashed bodies/value-as-function), formatter canonical-style snapshots, diagnostics |
| Scanner/corpus | already covered | The C# scanner is Unity's `language-lib`, pinned by `family-corpus.hash`; mode-gated cases (`@class_name` vs `@namespace`) land at the next family corpus wave |
| `Tests.Runtime` | headless .NET-build Godot (bootstrap entry mirroring `tests/*.gd` quit(code)) | reconciler/hooks/host/style/events on real Controls; lifetime (`IsInstanceValid`) cases; VariantConvert table; error-boundary auto-catch |
| **Cross-leg parity suite** | both Godot runtimes | Shared **data-driven scenario JSON** (single file, both consumers) asserting identical observable sequences — mount/diff order, keyed moves, bailout hits, effect ordering, null render, unmount cleanups. Documented divergences (error boundaries — the GDScript leg is the diverging one) excluded BY the table. Non-negotiable from M4 |
| Demo battery | headless .NET Godot | `demos_test` equivalent over `csharp/demo` |
| Addon tests | GDScript | `reactive_ui_csharp` watcher/driver with a stubbed dotnet driver |

## 11. Packaging + branding

- **Branding (owner, 2026-07-27)**: umbrella **Reactive UI Toolkit**, GitHub org
  `reactive-ui-toolkit`, display name **"Reactive UI Toolkit — Godot (C#)"**.
- **NuGet**: `ReactiveUIToolkit.Godot` (runtime) + `ReactiveUIToolkit.Godot.Generator`
  (analyzer + props). Bare `ReactiveUI.*` stays off the table (taken — Rx MVVM framework).
  **Reserve the `ReactiveUIToolkit.*` NuGet prefix** (needs a first published package + prefix
  reservation application) — cheap squat protection, worth doing early regardless of D2.
  Metadata: license file (Community License), icon, README, SourceLink + snupkg.
- **Engine floor (D11 RESOLVED)**: build against GodotSharp **4.4**; above-floor features
  runtime-probed; CI tests floor AND latest (§12). Multi-targeting only if an engine minor ever
  breaks binary compat.
- **AssetLib / Godot Asset Store — how the stores handle C# (researched 2026-07-27)**: the
  stores are FILE DELIVERY only — a zip of repo files, no compilation, no dependency
  resolution. Loose `.cs` addons do work (the user's next `dotnet build` compiles them), BUT
  (a) an addon **cannot declare NuGet dependencies** (open godot-proposals #9074), and (b) a
  Roslyn **analyzer cannot ship as loose source** — the generator must be an analyzer
  reference, which via the store would mean DLLs in the zip + hand-edited csproj lines: the
  exact hack our NuGet `build/*.props` design eliminates. The C# ecosystem norm (Chickensoft
  et al.) is NuGet-first. Therefore: **NuGet = the library + generator (primary channel);
  store = the thin GDScript HMR addon only** (its listing: ".NET build required; install the
  library via NuGet" + link), zipped from the C# repo. Demo zip on GitHub releases. Optional
  post-v1 fallback for NuGet-averse users (runtime-as-source addon + generator DLLs + three
  documented csproj lines) is possible but is a support-burden channel — not in v1.
- **Release lanes**: `csharp-v*` tag lane in publish.yml → `dotnet pack` + `nuget push` (new
  `NUGET_API_KEY` secret) + addon zip. Changelog: `csharp` lane in changelog.json extracting to
  `csharp/CHANGELOG.md` (verify-gated).
- **Org-rebrand touchpoints** (the umbrella move is its own operation, but this plan inherits
  it): repo URLs in extension manifests/READMEs/docs links, AssetLib listing URLs, license
  contact lines, `MoreInfo`/homepage fields — all flip to `github.com/reactive-ui-toolkit/*`
  when the org migration happens (GitHub redirects old URLs). This leg should be born under
  the org if D2 lands after the migration.

## 12. CI + sync discipline

- The C# repo's `test.yml`: setup-dotnet → `dotnet test Tests.Generator` → `_mono_` Godot
  FLOOR (4.4) → Tests.Runtime + parity + demo battery → repeat the runtime tier on the LATEST
  engine (matrix). Plus addon GDScript tests. The GDScript repo's CI is UNCHANGED except the
  extension-packaging step that fetches the pinned csharp-lsp artifact (§9).
- **Pin discipline** (all recorded hashes, all CI-checked — the 4-repo family mechanism):
  `family-corpus.hash` (scanner behavior); vocabulary.json + ClassDB dump pinned FROM the
  GDScript repo (source of truth) with a sync script; **vendored language-lib pinned to a
  recorded Unity-repo commit** with a drift-check — family fixes sync by bumping pins
  deliberately, never by silent divergence; parity-scenario JSON pinned from the GDScript repo
  (§10). Inside the C# repo, generator-baked copies byte-sync against its pinned inputs.
- `.editorconfig` from M0.

## 13. Versioning

Two new lanes: the NuGet `<Version>` (runtime+generator lockstep) starting **0.1.0**, and
`addons/reactive_ui_csharp/plugin.cfg`. Patch-by-default per house policy. Engine floor 4.4 +
verified-engine list ride the `add-godot-version` runbook.

## 14. Docs + positioning

- The C# repo gets its **own docs site** (`Docs~/` — the family pattern; every product repo
  has one): .NET-build getting started, csproj + NuGet setup, teaching pages with C# holes,
  HMR page, and the **documented-divergences table** (error boundaries: GDScript leg =
  structural, engine-imposed; C# leg = auto-catch like Unity).
- The GDScript repo's docs gain one page: **"GDScript leg vs C# leg — which?"** (web export,
  hot-reload nuance, team language, platform matrix), cross-linked from both sites; its README
  gains a pointer ("prefer C#? → Reactive UI Toolkit — Godot (C#)"). Its own positioning
  ("pure GDScript, standard build, no .NET") is UNCHANGED — that's half the point of D12.
- v1 demo scope (bounded): counter, todo, keyed, styling, context, router, signals,
  effect-order, portal, suspense. Full 45-demo gallery + Doom port = post-v1 stretch (Doom is
  the marketing piece for the C# audience later).

## 15. Milestones (each gated: build green + suites + changelog staged)

| M | Deliverable | Est. |
|---|---|---|
| M0 | **Repo birth + scaffold**: the born-repo checklist (§3 — license set, CLA, branch model + rulesets, changelog machinery, workflows, pins) + tree + `.editorconfig`/gitignore + csprojs + CI + demo boots empty + **NuGet id/prefix + org-name reservations** | ~500 + config |
| M1 | Core port: VirtualNode/V/Fiber(Alternate)/Hooks/Config/Diagnostics + Tests.Runtime bootstrap green | ~4k |
| M2 | Host layer: GodotHostConfig/VariantConvert/Style/Theme/Events(arity)/items/draw; counter demo interacts | ~2k |
| M3 | Generator retarget end-to-end: `.guitkx`→C#→running demo; namespaces; HMR-safe emission; Tests.Generator ported | ~3k delta |
| M4 | Subsystems: Router/Signals/Suspense(Task)/Media + auto-catch boundaries + **parity suite** | ~4k |
| M5 | HMR: addon + dotnet driver + wire + ALC swap + stale-build gate; mid-play edit demo | ~2.5k |
| M6 | IDE: csharp-lsp fork + extension mode routing + grammar injection + specifier completion | ~2k delta |
| M7 | Docs + demo subset + "which leg" + divergences table | content |
| M8 | Packaging: NuGet lane (+secret), AssetLib listing, changelog lane, NOTICES, release 0.1.0 | config |

M0→M3 first — proves the thesis on the counter demo before the long tail. Overall: a
quarter-scale campaign (Unreal Phase-0→2 shaped).

## 16. Risks

| Risk | Mitigation |
|---|---|
| Runtime parity rot between the Godot legs | Data-driven parity suite from M4; divergences must be table-listed or the gate fails |
| Family lockstep cost (4th toolchain, 4th repo) | The pin mechanism already syncs 3 repos; this adds one consumer; C# scanner already family-gated; language-lib pin makes sync deliberate |
| Cross-repo extension choreography (csharp-lsp release → extension re-bundle) | Precedented artifact-bundling (clangd pattern) + pinned server version + the two-PR choreography written down in §9 |
| Vendored language-lib silent divergence | Pinned-commit drift check in CI |
| HMR ALC leaks / swap edges | Accepted-by-design leak (family posture); proven trampoline emission; stale-build gate; hook-shape reset rule |
| GodotSharp binary compat across minors | Floor-build (4.4) + floor/latest CI matrix; runtime probes for newer features |
| Freed-node crashes (C# wrappers) | IsInstanceValid discipline + lifetime tests |
| GC pressure from per-render allocations | Accepted v1 + Diagnostics counters; pooling later, measured |
| Vocabulary/dump staleness per engine version | `add-godot-version` skill refreshes baked copies (tripwired) |
| Org rebrand mid-flight | URL touchpoints listed (§11); GitHub redirects; born-under-org if D2 lands post-migration |
| Demand uncertainty (~16% × Godot) | D2 owner-gated; M0–M3 doubles as a cheap validating spike |

## 17. Owner decisions — final state

**Governing directive: Unity parity** (owner, 2026-07-27) — resolved D1, D3–D9. Verified in
Unity source where load-bearing: error boundaries auto-catch (`FiberReconciler` →
`FindNearestErrorBoundary`); fibers double-buffer (`FiberNode.Alternate`). Parity scope =
API/toolchain/semantics; element vocabulary stays Godot-native.

| # | Decision | State |
|---|---|---|
| D1 | Naming | **RESOLVED**: umbrella **Reactive UI Toolkit** (org `reactive-ui-toolkit`); display "Reactive UI Toolkit — Godot (C#)"; NuGet `ReactiveUIToolkit.Godot` / `.Generator` (+prefix reservation) |
| D2 | Go / timing | **OWNER-TRIGGERED** — plan may still evolve until then |
| D3 | LSP base | **RESOLVED**: fork Unity's C# server |
| D4 | language-lib | **RESOLVED**: vendored Unity fork + pinned-commit drift check |
| D5 | Fiber allocation | **RESOLVED**: Unity's `Alternate` double-buffer (verified) |
| D6 | Hooks casing | **RESOLVED**: `useState` (Unity spelling); corpus-pinned at next family wave |
| D7 | Error boundaries | **RESOLVED**: TRUE auto-catch (verified — Unity does exactly this); GDScript leg recorded as the engine-imposed divergence |
| D8 | C#-mode formatting | **RESOLVED**: spaces-2 canonical (Unity-exact), config-overridable |
| D9 | Namespaces | **RESOLVED**: file-keyed csproj-relative + `@namespace` (Unity model) |
| D10 | Rider | **RESOLVED**: always after v1 |
| D11 | Engine floor | **RESOLVED**: 4.4, same as the GDScript leg; floor-built package + runtime probes |
| D12 | Residency | **RESOLVED**: dedicated repo under the org (e.g. `reactive-ui-toolkit/ruitk-godot-csharp`) — zero shared code files with the GDScript repo, contracts sync via the proven 3-repo pin mechanism, extension coupling solved by artifact bundling (clangd precedent), GDScript repo's no-.NET identity preserved. §3 has the layout + born-repo checklist |
