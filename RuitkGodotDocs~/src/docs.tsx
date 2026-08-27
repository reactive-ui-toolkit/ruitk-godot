import type { ReactElement } from 'react'
import type { Page as LegacyPage } from './pages'
import { pages as legacySections } from './pages'
import { PAGE_VERSIONS, isAvailableIn, compareVersions } from './versionManifest'
import { KnownIssuesPage } from './pages/KnownIssues/KnownIssuesPage'
import { RoadmapPage } from './pages/Roadmap/RoadmapPage'
import { UitkxAPIPage } from './pages/UITKX/API/UitkxAPIPage'
import { UitkxComponentsPage } from './pages/UITKX/Components/UitkxComponentsPage'
import { CompanionFilesPage } from './pages/UITKX/CompanionFiles/CompanionFilesPage'
import { UitkxImportsPage } from './pages/UITKX/Imports/UitkxImportsPage'
import { MigrationsPage } from './pages/Migrations/MigrationsPage'
import { UitkxConceptsPage } from './pages/UITKX/Concepts/UitkxConceptsPage'
import { UitkxConfigPage } from './pages/UITKX/Config/UitkxConfigPage'
import { UitkxDebuggingPage } from './pages/UITKX/Debugging/UitkxDebuggingPage'
import { UitkxDiagnosticsPage } from './pages/UITKX/Diagnostics/UitkxDiagnosticsPage'
import { UitkxDifferencesPage } from './pages/UITKX/Differences/UitkxDifferencesPage'
import { UitkxGettingStartedPage } from './pages/UITKX/GettingStarted/UitkxGettingStartedPage'
import { UitkxIntroductionPage } from './pages/UITKX/Introduction/UitkxIntroductionPage'
import { UitkxReferencePage } from './pages/UITKX/Reference/UitkxReferencePage'
import { UitkxRouterPage } from './pages/UITKX/Router/UitkxRouterPage'
import { UitkxSignalsPage } from './pages/UITKX/Signals/UitkxSignalsPage'
import { UitkxPortalPage } from './pages/UITKX/Portal/UitkxPortalPage'
import { UitkxSuspensePage } from './pages/UITKX/Suspense/UitkxSuspensePage'
import { HmrPage } from './pages/Tooling/HMR/HmrPage'
import { EditorPage } from './pages/Tooling/Editor/EditorPage'
import { BuilderPage } from './pages/Tooling/Builder/BuilderPage'
import { FAQPage } from './pages/FAQ/FAQPage'
import { LicensingPage } from './pages/Licensing/LicensingPage'
import { StylingPage } from './pages/UITKX/Styling/StylingPage'
import { AssetsPage } from './pages/UITKX/Assets/AssetsPage'
import { EventsPage } from './pages/UITKX/Events/EventsPage'
import { CustomRenderingPage } from './pages/UITKX/CustomRendering/CustomRenderingPage'
import { HooksGuidePage } from './pages/UITKX/Hooks/HooksGuidePage'
import { ContextPage } from './pages/UITKX/Context/ContextPage'
import { HooksAPIPage } from './pages/UITKX/HooksAPI/HooksAPIPage'
import { CssHelpersReferencePage } from './pages/UITKX/CssHelpersRef/CssHelpersReferencePage'
import { RefGuidePage } from './pages/UITKX/Guides/RefGuidePage'
import { KeyGuidePage } from './pages/UITKX/Guides/KeyGuidePage'
import { AdvancedAPIPage } from './pages/UITKX/AdvancedAPI/AdvancedAPIPage'

export type DocPage = {
  id: string
  canonicalId: string
  title: string
  path: string
  keywords?: string[]
  searchContent?: string
  group?: 'basic' | 'advanced'
  sinceGodot?: string
  element: () => ReactElement
}

export type DocSection = {
  id: string
  title: string
  pages: DocPage[]
}

const componentPages = legacySections.find((section) => section.id === 'components')?.pages ?? []

export const sections: DocSection[] = [
  {
    id: 'intro',
    title: 'Introduction',
    pages: [
      {
        id: 'introduction',
        canonicalId: 'introduction',
        title: 'Introduction',
        path: '/',
        keywords: ['introduction', 'markup', 'godot', 'guitkx'],
        searchContent: 'reactive ui for godot react-style ui framework godot 4.x guitkx authoring language function-style components .guitkx hooks state effects reconcile fiber reconciler control nodes gdscript retained-mode scene tree component countercard useState return label button onPressed vbox highlights camelCase hooks typed props diffs batches updates router signals utilities compiles to sibling .gd file no runtime codegen no javascript engine standard godot build var s useState',
        element: () => <UitkxIntroductionPage />,
      },
    ],
  },
  {
    id: 'getting-started',
    title: 'Getting Started',
    pages: [
      {
        id: 'getting-started-page',
        canonicalId: 'install',
        title: 'Install & Setup',
        path: '/getting-started',
        keywords: ['install', 'setup', 'component', 'addon'],
        searchContent: 'getting started reactive ui for godot function-style .guitkx components compiler produces sibling .gd class no boilerplate install copy addons/reactive_ui_toolkit folder enable plugin project settings plugins create a guitkx component setup code returned markup codegen emits static render mount RuitkRoot.create V.fc RuitkRootNode setup _ready _exit_tree unmount class_name inferred from declaration no filename convention HelloWorld component var s useState return VBoxContainer Label Hello reactive godot Button Increment onPressed s[1].call s[0] + 1 splitting into files optional hooks styles utils values export import res://addons/reactive_ui_toolkit extends RefCounted render props children RuitkVNode',
        element: () => <UitkxGettingStartedPage />,
      },
    ],
  },
  {
    id: 'imports',
    title: 'Imports & Exports',
    pages: [
      {
        id: 'imports-page',
        canonicalId: 'imports',
        title: 'Imports & Exports',
        path: '/imports',
        keywords: ['import', 'export', 'specifier', 'strict', 'codemod', 'root', 'cycle', 'module-scoped'],
        searchContent: 'imports exports import { Name } from specifier relative ./ ../ root ~/ extensionless .guitkx implied ES import surface named rename remote as local namespace import * as default import export list export { a b } export default re-exports deferred export declaration reachable cross-file binding class_name first exported multiple declarations mixed component hook util value file-private strict resolution error GUITKX2300 2301 2302 2303 2304 2305 2306 2307 2308 2309 2320 2321 2322 2323 2324 2325 2326 2327 unresolved not exported not declared duplicate unused defined but not imported value-import cycle chain used but unexported boundary module-scoped preamble deprecated wrapper keyword migration codemod migrate_0_11_0.gd idempotent ~/ root guitkx.config.json root key res:// lazy by path component cycles legal eager preload value cycle error no default export alias collision duplicate export default',
        element: () => <UitkxImportsPage />,
      },
    ],
  },
  {
    id: 'migrations',
    title: 'Migrations',
    pages: [
      {
        id: 'migrations-page',
        canonicalId: 'migrations',
        title: 'Migrations',
        path: '/migrations',
        keywords: ['migration', 'migrate', 'upgrade', 'codemod', 'breaking', '0.9', '0.10', '0.11'],
        searchContent: 'migrations migrate upgrade breaking release codemod dry-run idempotent 0.8 to 0.9 naming loyalty renames VBox VBoxContainer RichText RichTextLabel onClick onPressed onChange onValueChanged fill anchors_preset migrate_0_9_0.gd MIGRATION-0.9.md 0.9 to 0.10 imports exports strict cross-file resolution export declaration import lines migrate_0_10_0.gd MIGRATION-0.10.md ambient class_name hand-written scripts run in order 0.10 to 0.11 ES modules wrapper keywords component hook module removed signature classification RuitkVNode annotation use_ prefix util value export module hoist @class_name namespace import * as default export GUITKX2320 migrate_0_11_0.gd MIGRATION-0.11.md',
        element: () => <MigrationsPage />,
      },
    ],
  },
  {
    id: 'companion-files',
    title: 'Files & Modules',
    pages: [
      {
        id: 'companion-files-page',
        canonicalId: 'companion-files',
        title: 'Files & Modules',
        path: '/companion-files',
        keywords: ['files', 'modules', 'export', 'file-private', 'class_name', 'hook', 'styles', 'utils', 'values'],
        searchContent: 'files modules a file is a module ES modules per-file scope export file-private visibility plain declarations signature classification component hook util value binding identity @class_name escape hatch interop first exported declaration file rename module identity directory layout compiler produces sibling .gd class PlayerCard.hooks.guitkx custom hooks reusable state logic use_ prefix Hooks.useState Hooks.useEffect PlayerCard.style.guitkx value exports static var Color colours sizes namespace import import * as PlayerCard.utils.guitkx pure helper formatting functions format_health standalone shared files SharedColors extends RefCounted auto-generated sibling class_name .guitkx.diags.json hot reload',
        element: () => <CompanionFilesPage />,
      },
    ],
  },
  {
    id: 'styling',
    title: 'Styling',
    pages: [
      {
        id: 'styling-page',
        canonicalId: 'styling',
        title: 'Styling',
        path: '/styling',
        keywords: ['style', 'style dict', 'RuitkStyle', 'RuitkStyleSheet', 'theme', 'StyleBox', 'layout', 'colors', 'size flags'],
        searchContent: 'styling style dictionary RuitkStyle maps onto godot control properties size flags theme overrides stylebox no uss no css cascade inline style dict classes prop RuitkStyleSheet register merge named style set left-to-right merge inline style wins StyleBoxFlat bg_color border_color border_width_all corner_radius_all content_margin_all any styleboxflat property verbatim set_border_width_all set_corner_radius_all set_content_margin_all shadow_color shadow_size per-state slots hover pressed focus disabled read_only theme channels colors constants fonts font_sizes icons styleboxes add_theme_color_override add_theme_constant_override add_theme_font_override add_theme_font_size_override add_theme_icon_override add_theme_stylebox_override sizing min_width min_height custom_minimum_size anchors_preset PRESET_FULL_RECT size_flags_horizontal size_flags_vertical SIZE_EXPAND_FILL SIZE_SHRINK_CENTER transform modulate self_modulate rotation radians scale pivot_offset z_index visibility visible clip_contents mouse_filter MOUSE_FILTER_STOP MOUSE_FILTER_PASS MOUSE_FILTER_IGNORE tooltip_text text font font_color font font_size font_outline_color outline_size container spacing separation h_separation v_separation margin_left margin_top margin_right margin_bottom Theme StyleBox Color Vector2 Font Texture2D',
        element: () => <StylingPage />,
      },
    ],
  },
  {
    id: 'assets',
    title: 'Assets & Stylesheets',
    pages: [
      {
        id: 'assets-page',
        canonicalId: 'assets',
        title: 'Assets & Stylesheets',
        path: '/assets',
        keywords: ['asset', 'texture', 'font', 'theme', 'resource', 'image', 'audio', 'stylebox'],
        searchContent: 'asset loading preload load compile-time runtime res:// resource path Texture2D FontFile Theme StyleBox AudioStream PackedScene Resource TextureRect texture Button icon TextureButton texture_normal AudioStreamPlayer theme prop style dict channels icons fonts styleboxes supported file types png jpg webp svg ttf otf woff woff2 fnt tres theme ogg wav mp3 tscn scn .import godot importer',
        element: () => <AssetsPage />,
      },
    ],
  },
  {
    id: 'components-overview',
    title: 'Components Overview',
    pages: [
      {
        id: 'components-overview-page',
        canonicalId: 'uitkx-components-overview',
        title: 'Components Overview',
        path: '/components',
        keywords: ['components', 'intrinsic tags', 'host elements', 'custom components'],
        searchContent: 'components overview categorized catalog intrinsic tags host elements godot class names 1:1 Control VBoxContainer HBoxContainer BoxContainer GridContainer MarginContainer PanelContainer CenterContainer ScrollContainer FlowContainer TabContainer SplitContainer AspectRatioContainer FoldableContainer SubViewportContainer Label RichTextLabel Panel ColorRect TextureRect NinePatchRect ReferenceRect ProgressBar Button CheckBox CheckButton OptionButton MenuButton LinkButton TextureButton LineEdit TextEdit CodeEdit SpinBox HSlider VSlider HScrollBar VScrollBar ColorPicker ColorPickerButton VirtualJoystick ItemList Tree TabBar MenuBar AudioStreamPlayer VideoStreamPlayer router tags Router Routes Route Outlet NavLink Link structural Fragment Portal Suspense ErrorBoundary Memo custom components pascalcase names godot control open vocabulary ClassDB any node class GraphEdit universal attributes key ref style classes onPressed onToggled onItemSelected onValueChanged onTextChanged onTextSubmitted onFocusEntered onFocusExited several declarations per file',
        element: () => <UitkxComponentsPage />,
      },
    ],
  },
  {
    id: 'component-reference',
    title: 'Components',
    pages: componentPages.map((page: LegacyPage) => ({
      id: page.id,
      canonicalId: page.id,
      title: page.title,
      path: page.path,
      keywords: page.keywords,
      group: page.group,
      sinceGodot: page.sinceGodot,
      element: page.element,
    })),
  },
  {
    id: 'concepts',
    title: 'Concepts & Environment',
    pages: [
      {
        id: 'concepts-page',
        canonicalId: 'concepts-and-environment',
        title: 'Concepts & Environment',
        path: '/concepts',
        keywords: ['concepts', 'environment', 'reconciler', 'config'],
        searchContent: 'concepts and environment react-style component model reactive ui for godot components hooks markup reconciliation scheduling authoring rules intrinsic tag names custom components distinct names function-style components setup code first single returned markup tree state setters called as callables s[1].call a file is a module plain declarations signature classification component RuitkVNode annotation hook use_ prefix util value export RuitkConfig time_slicing on by default time_slice_ms frame_budget_ms strict_mode strict_mode_effective environment environment_resolved development production enable_hook_validation enable_strict_diagnostics RuitkDiagnostics enabled capture messages report reset trace_level diff_tracing trace ladder basic verbose RuitkScheduler runtime diagnostics fiber reconciler keyed child reconciliation component bailout request_update rendering pipeline author generate mount reconcile commit effects component lifecycle mount update unmount RuitkRoot unmount Control RuitkVNode routing signals safe-area helpers event handlers onPressed onButtonDown onValueChanged onItemSelected on PascalCase signal name style classes ref key',
        element: () => <UitkxConceptsPage />,
      },
    ],
  },
  {
    id: 'differences',
    title: 'Different from React',
    pages: [
      {
        id: 'differences-page',
        canonicalId: 'different-from-react',
        title: 'Different from React',
        path: '/differences',
        keywords: ['react', 'hooks', 'rendering', 'state', 'gdscript'],
        searchContent: 'different from react component-and-hooks mental model reactive ui for godot gdscript runtime control nodes godot signals scheduling model snake_case hooks useState useEffect useMemo useRef Hooks.useState auto-prefixed state updates array destructuring value setter s[0] s[1] .call updater func(prev) return prev + 1 useRef box current key ref callable rendering model fiber reconciler time-sliced by default four-lane scheduler render quantum frame budget defer replay after commit sync opt-out per frame process_frame no start_transition no priority preemption batched updates passive effects slice render work container-driven layout VBoxContainer HBoxContainer GridContainer no uss no uxml V.fc function-component factory no try catch in gdscript apis differ from browser react conventions no onChange event handlers on PascalCase signal name onPressed onTextChanged mapped to godot signals',
        element: () => <UitkxDifferencesPage />,
      },
    ],
  },
  {
    id: 'tooling',
    title: 'Tooling',
    pages: [
      {
        id: 'router-page',
        canonicalId: 'router',
        title: 'Router',
        path: '/tooling/router',
        keywords: ['router', 'routes', 'navigation', 'outlet', 'nav_link', 'navigate', 'redirect', 'basename', 'index route', 'layout route'],
        searchContent: 'router lightweight in-memory router inspired by react router v6 routing authored directly in markup Router Routes Route Outlet NavLink Navigate Link V.router V.routes V.route V.outlet V.navigate V.nav_link V.link routed child components routing context subtree basename URL prefix ranked first-match-wins ranking dynamic params :params splats layout route nested routes index route case_sensitive exact element wrapper Outlet render slot useOutletContext typed context descendants NavLink active state active_style end Navigate declarative redirect replace state RuitkRouter hooks setup imperative navigation history RuitkHistory RuitkRouterLocation RuitkRouteMatch useNavigate pushes replaces locations useGo useCanGo back forward useLocation useLocationInfo useParams useQuery useSearchParams query setter preserves path useNavigationState useRouteMatch useMatches breadcrumbs match chain useNavigationBase useResolvedPath pure path resolver useBlocker usePrompt confirmation dialog intercept transitions unsaved guarded state relative paths outlets parent match declarative route composition to label path context initial',
        element: () => <UitkxRouterPage />,
      },
      {
        id: 'signals-page',
        canonicalId: 'signals',
        title: 'Signals',
        path: '/tooling/signals',
        keywords: ['signals', 'RuitkSignal', 'shared state', 'reactive'],
        searchContent: 'signals RuitkSignal lightweight reactive value store lives outside component tree single source of truth RuitkSignal.new get_value set_value update subscribe unsubscribe RuitkSignals process-wide keyed registry get_or_create try_get has clear keyed by string useSignal useSignalKey subscribe re-render selector comparer project slice custom equality reference-aware change detection value types vs reference types named RuitkSignal because godot reserves signal counter Increment Reset shared app-wide state',
        element: () => <UitkxSignalsPage />,
      },
      {
        id: 'hmr-page',
        canonicalId: 'hmr',
        title: 'Hot Module Replacement',
        path: '/tooling/hmr',
        keywords: ['live reload', 'hot reload', 'live editing', 'instant preview'],
        searchContent: 'live reload hot reload edit .guitkx files save updates running ui godot editor without manual rebuild rides godot gdscript hot-reload no separate hmr subsystem compiles to real sibling .gd script quick start enable reactive_ui_toolkit editor plugin project settings plugins how it works @tool EditorPlugin plugin.gd EditorFileSystem filesystem_changed compiles all guitkx res:// RuitkGuitkxCodegen lexed parsed lowered render props children EditorFileSystem update_file godot recompiles hot-reloads script mtime staleness guard re-entry guard state across reload RuitkComponentState positional array hook slots reconciler useState useReducer retained useRef box preserved useEffect useLayoutEffect useMemo useCallback useContext useStableCallback useStableAction useSignal useSignalKey useDeferredValue hook util value files global re-render compile_all new components preload RuitkRoot.create V.fc mounting hook state persists limitations GUITKX compile error stub push_error per-script granularity troubleshooting [guitkx] compiled output panel .guitkx.diags.json push_warning hook-order validator RuitkConfig.enable_hook_validation RuitkDiagnostics',
        element: () => <HmrPage />,
      },
      {
        id: 'editor-page',
        canonicalId: 'editor',
        title: 'In-Godot Editor',
        path: '/tooling/editor',
        keywords: ['editor', 'ide', 'addon', 'diagnostics', 'completion', 'rename', 'search'],
        searchContent: 'in-godot editor reactive_ui_toolkit_editor addon main-screen guitkx editor double-click filesystem dock open syntax highlighting theme-matched host component tag colours embedded expression sub-highlighting live compiler diagnostics gutter icons did-you-mean problems bottom panel project scope sidecar aggregation GUITKX codes completion tags attributes snippet caret inside quotes attribute values enum true false style-dict keys directives Color builtin constants hook names onPressed on_signal both spellings hover tooltips signature help event lambda parameter strip navigation ctrl+click go to definition shift+f12 references panel ctrl+g go to line outline tree declarations f2 rename project-wide collision refusing find replace replace-all one undo step search .guitkx bottom panel project-wide comment toggle move lines duplicate delete bookmark zoom word wrap enter between tags multi-file open list session restore retarget detach format guitkx.config.json printWidth indentStyle format-on-save new file component skeleton project settings reactive_ui_toolkit_editor toggles open_guitkx_in_editor watcher sibling gd save all quit confirmation play flush GUITKX2106 GUITKX2107 hash-gated overlay search in files exclusion script editor adoption 150k live compile adaptive debounce native analyzer roadmap',
        element: () => <EditorPage />,
      },
      {
        id: 'builder-page',
        canonicalId: 'builder',
        title: 'UI Builder',
        path: '/tooling/builder',
        keywords: ['builder', 'visual editor', 'canvas', 'drag and drop', 'module tree', 'cards'],
        searchContent: 'ui builder visual editor guitkx module tree canvas cards import edges infinite canvas reactive ui toolkit menu builder open plugin reactive_ui_toolkit_editor project tools module tree transitive imports folder five module kinds component hook style util value badge tint read-only addons package sources folder pane library pane host elements hooks components vocabulary.json source pane guitkx code edit highlighting completion diagnostics console problems jump to module pan zoom wheel fit to view level of detail LOD culling anchor dots bezier edges layout remembered per tree membership drag drop three bands before inside after move subtree move module folder attributes directive headers @if @for @while @match inline editor rename module specifier rewrite ensure import GUITKX0108 one root ledger undo redo typing merge one entry two files save abort batch write format on save planned moves companions .uid .diags.json generated .gd delete to trash blank module pending crash journal user:// recovery live preview scratch mirror debounce focus closure importers recompile no writes to project no multi-select no auto-layout unity parity guitkx.config.json',
        element: () => <BuilderPage />,
      },
      {
        id: 'portal-page',
        canonicalId: 'portal',
        title: 'Portal',
        path: '/tooling/portal',
        keywords: ['portal', 'modal', 'overlay', 'tooltip'],
        searchContent: 'portal render children under different target node outside component hierarchy escape node tree modals tooltips overlays clipping stacking V.portal target children key Node CanvasLayer ref-captured target overlay node mounted flag reactive lifecycle preserved useState useRef useEffect provideContext useContext',
        element: () => <UitkxPortalPage />,
      },
      {
        id: 'suspense-page',
        canonicalId: 'suspense',
        title: 'Suspense',
        path: '/tooling/suspense',
        keywords: ['suspense', 'loading', 'async', 'fallback'],
        searchContent: 'suspense loading fallback async await ready_signal is_ready V.suspense children RuitkSuspense signal mode poll mode boundary godot signal ResourceLoaderThreaded readiness flipping stale driver swapping async sources useState useRef useEffect useMemo useCallback gdscript cannot throw-to-suspend loading state pattern',
        element: () => <UitkxSuspensePage />,
      },
    ],
  },
  {
    id: 'guides',
    title: 'Guides',
    pages: [
      {
        id: 'events-page',
        canonicalId: 'events',
        title: 'Events & Input Handling',
        path: '/guides/events',
        keywords: ['events', 'input', 'click', 'pointer', 'focus', 'change', 'signals'],
        searchContent: 'events input handling on plus PascalCase signal name one rule every signal every node onPressed onButtonDown onButtonUp onMouseEntered onMouseExited onFocusEntered onFocusExited onToggled onValueChanged onItemSelected onTextChanged onTextSubmitted onTabChanged onColorChanged onGuiInput onResized mapped to godot signals native escape hatch on_<signal> on_gui_input on_id_pressed on_item_activated pressed button_down button_up mouse_entered mouse_exited focus_entered focus_exited item_selected value_changed text_changed tab_changed toggled color_changed text_submitted resized gui_input id_pressed item_activated no onChange no onClick removed 0.9.0 MIGRATION-0.9.md InputEvent InputEventKey Control Button CheckBox CheckButton OptionButton LineEdit TextEdit HSlider PanelContainer Tree PopupMenu ColorRect BaseButton handler receives signal arguments directly Callable controlled input caret position preservation focus_mode camelCase snake_case transform',
        element: () => <EventsPage />,
      },
      {
        id: 'custom-rendering-page',
        canonicalId: 'custom-rendering',
        title: 'Custom Rendering',
        path: '/guides/custom-rendering',
        keywords: ['custom rendering', 'draw_fn', 'redraw_key', 'canvas', 'draw', '_draw'],
        searchContent: 'custom rendering declarative draw_fn redraw_key props callable canvas_item CanvasItem godot _draw draw signal draw_line draw_polyline draw_rect draw_circle draw_colored_polygon draw_texture draw_string draw_arc queue_redraw size Vector2 Rect2 Color PackedVector2Array Control Panel register-once trampoline reads latest closure from meta repaints only when callback identity or redraw_key changes useState useStableAction useStableCallback useRef read-only inside draw_fn continuous animation ticker useTween paint phase charts gauges sprites state-driven drawing declarative custom draw escape hatch module static func',
        element: () => <CustomRenderingPage />,
      },
      {
        id: 'hooks-guide-page',
        canonicalId: 'hooks-guide',
        title: 'Hooks Guide',
        path: '/guides/hooks',
        keywords: ['hooks', 'useState', 'useEffect', 'useRef', 'useMemo', 'useReducer'],
        searchContent: 'hooks guide useState useReducer useEffect useLayoutEffect useMemo useCallback useRef useContext provideContext useDeferredValue useImperativeHandle useStableFunc useStableAction useStableCallback state setter functional updater func(old) return new reducer dispatch dependency array shallow comparison cleanup Callable mount unmount synchronous before paint memoization stable callback identity mutable ref box current dictionary control ref grab_focus context provider consumer shadowing deferred value imperative handle positional-slot model hook slot RuitkConfig.enable_hook_validation RuitkConfig.enable_strict_diagnostics hook rules unconditional top level Hooks.useState auto-prefixed',
        element: () => <HooksGuidePage />,
      },
      {
        id: 'context-page',
        canonicalId: 'context',
        title: 'Context API',
        path: '/guides/context',
        keywords: ['context', 'provider', 'consumer', 'useContext', 'provideContext'],
        searchContent: 'context api useContext Hooks.provideContext provider consumer string key type-safe key constants companion .gd module AppContextKeys THEME LOCALE AUTH nested provider shadowing subtree fiber subtree visibility dependency injection context vs signals RuitkSignal useSignalKey scope lifetime dynamic context value re-renders when value changes == comparison useContext does not consume a hook slot provideContext exposes value to fiber subtree',
        element: () => <ContextPage />,
      },
      {
        id: 'ref-guide-page',
        canonicalId: 'ref-guide',
        title: 'Refs Guide',
        path: '/guides/refs',
        keywords: ['ref', 'useRef', 'useImperativeHandle', 'control ref'],
        searchContent: 'refs guide useRef ref box dictionary current mutable value container persists across renders mutating does not trigger re-render stable box never re-created control ref capture underlying godot node grab_focus size auto-focus pattern useLayoutEffect timing useImperativeHandle imperative handle custom API object handle dictionary callables render counter previous value tracking ScrollContainer scroll_vertical Tween handles parent child ref passing',
        element: () => <RefGuidePage />,
      },
      {
        id: 'key-guide-page',
        canonicalId: 'key-guide',
        title: 'Keys Guide',
        path: '/guides/keys',
        keywords: ['key', 'list', 'reconciler', 'reorder', 'identity'],
        searchContent: 'keys guide key prop reconciler element matching identity preservation dynamic collection rendering @for loop stable unique identifier reorder vs recreation move elements index antipattern reset state unmount remount siblings performance correctness preserve component state hooks refs per-node state preservation control node creation destruction scene tree node movement',
        element: () => <KeyGuidePage />,
      },
    ],
  },
  {
    id: 'api',
    title: 'API',
    pages: [
      {
        id: 'api-page',
        canonicalId: 'api-reference',
        title: 'API Reference',
        path: '/api',
        keywords: ['api', 'hooks', 'runtime', 'classes'],
        searchContent: 'api reference map global classes class_name registered by addon addons/reactive_ui_toolkit core V RuitkVNode V.fc mounting V.memo V.portal V.suspense V.error_boundary no markup tag yet embedded expr Hooks useState useReducer useEffect useLayoutEffect useMemo useCallback useRef useContext provideContext useDeferredValue useTransition useImperativeHandle useStableCallback useStableFunc useStableAction useSignal useSignalKey useAnimate useTween useTweenValue useSfx useSafeArea RuitkConfig.enable_hook_validation RuitkConfig.enable_strict_diagnostics RuitkRoot RuitkRoot.create set_root unmount RuitkRootNode setup build RuitkReconciler fiber reconciler RuitkHost RuitkStyle RuitkStyleSheet style classes host styling RuitkRouter useRouter useLocation useLocationInfo useParams useQuery useSearchParams useNavigationState useNavigate useGo useCanGo useMatches useRouteMatch useNavigationBase useResolvedPath useOutletContext useBlocker usePrompt V.router V.routes V.route V.outlet V.navigate V.nav_link V.link RuitkHistory RuitkRouterLocation RuitkRouterPath RuitkRouteMatch RuitkRouteMatcher RuitkRouteRanker RuitkSignal RuitkSignals get_or_create try_get has clear get_value set_value update subscribe RuitkMedia useSfx safe area DisplayServer.get_display_safe_area RuitkSuspense ready_signal is_ready fallback RuitkConfig RuitkDiagnostics',
        element: () => <UitkxAPIPage />,
      },
      {
        id: 'hooks-api-page',
        canonicalId: 'hooks-api',
        title: 'Hooks API Reference',
        path: '/api/hooks',
        keywords: ['hooks', 'api', 'signatures', 'Callable', 'Dictionary', 'ref box'],
        searchContent: 'hooks api reference exact signatures Hooks class addons/reactive_ui_toolkit/core/hooks.gd auto-prefixed useState useReducer useEffect useLayoutEffect useMemo useCallback useDeferredValue useRef useImperativeHandle useContext provideContext useStableCallback useStableFunc useStableAction useTransition useSignal useSignalKey useTween useTweenValue useAnimate useSfx useSafeArea return array [value, set] [state, dispatch] ref box current dictionary functional updater func(old) return new reducer state action deps dependency array Callable RuitkSignal selector comparer Tween bus stream volume_db pitch_scale safe area insets left top right bottom RuitkConfig.enable_hook_validation RuitkConfig.enable_strict_diagnostics plain gdscript values arrays dictionaries callables',
        element: () => <HooksAPIPage />,
      },
      {
        id: 'csshelpers-ref-page',
        canonicalId: 'csshelpers-reference',
        title: 'CssHelpers Reference',
        path: '/api/csshelpers',
        keywords: ['style helpers', 'style dict', 'RuitkStyle', 'StyleBox', 'theme', 'size flags'],
        searchContent: 'style helpers reference style dictionary keys RuitkStyle core/style.gd godot control props size flags theme overrides stylebox no uss no css literal godot names stylebox keys bg_color border_color border_width_all corner_radius_all content_margin_all any StyleBoxFlat property verbatim set_border_width_all set_corner_radius_all set_content_margin_all shadow_color shadow_size per-state slots hover pressed focus disabled read_only theme channels colors constants fonts font_sizes icons styleboxes add_theme_color_override add_theme_constant_override add_theme_font_override add_theme_font_size_override add_theme_icon_override add_theme_stylebox_override sizing min_width min_height custom_minimum_size anchors_preset PRESET_FULL_RECT size_flags_horizontal size_flags_vertical SIZE_EXPAND_FILL transform modulate self_modulate rotation radians scale pivot_offset z_index visibility visible clip_contents mouse_filter MOUSE_FILTER_STOP MOUSE_FILTER_PASS MOUSE_FILTER_IGNORE tooltip_text text font font_color font font_size outline_size font_outline_color separation h_separation v_separation margin_left margin_top margin_right margin_bottom MarginContainer RuitkStyleSheet classes prop merge left-to-right inline style wins plain dictionary merge no cascade MIGRATION-0.9.md Color Vector2 Font Texture2D StyleBox',
        element: () => <CssHelpersReferencePage />,
      },
      {
        id: 'advanced-api-page',
        canonicalId: 'advanced-api',
        title: 'Advanced API Reference',
        path: '/api/advanced',
        keywords: ['__memo_eq', 'RuitkHost', 'scheduler', 'error boundary', 'render depth guard', 'draw_fn', 'RuitkVNode'],
        searchContent: 'advanced api reference memoization custom props equality __memo_eq Callable old new bool shallow == useMemo useCallback refs into godot nodes useRef box current control node imperative useLayoutEffect frame scheduler batching SceneTree process_frame signal batched deferred useDeferredValue sliced no manual scheduler api stable callbacks useStableCallback useStableAction identity never changes signal subscribe once error boundaries V.error_boundary fallback reset_key on_error no try catch gdscript no auto-catch parity limitation render depth guard 25 consecutive re-renders infinite loop setter in setup body custom drawing draw_fn redraw_key canvas_item queue_redraw register-once trampoline host elements item-model adapters RuitkHost ItemList OptionButton TabBar Tree MenuBar items prop register_item_adapter V.h generic host RuitkVNode immutable virtual node V factory function component fragment portal suspense error boundary node kinds',
        element: () => <AdvancedAPIPage />,
      },
    ],
  },
  {
    id: 'reference-guides',
    title: 'Reference & Guides',
    pages: [
      {
        id: 'language-reference',
        canonicalId: 'language-reference',
        title: 'Language Reference',
        path: '/reference',
        keywords: ['directives', 'syntax', 'control flow', 'expressions'],
        searchContent: 'guitkx language reference directives syntax control flow expressions compiles to sibling gdscript .gd class plain declarations signature classification component -> RuitkVNode annotation hook use_ prefix util value := export export default export list preamble directives @class_name MyButton override generated gdscript class_name @uss res://ui/theme.tres associate Theme StyleBox resource path function-style components Name() -> RuitkVNode typed parameters default props dictionary render props children var s useState return VBoxContainer Label text Button onPressed markup control flow @if @elif @else @for @while @match @case @default bare markup no return wrapper statement-level {expr} markup child gdscript expression RuitkVNode array string null attr={expr} attribute value literal plain string onXxx event handler Callable connected to mapped signal # line comment fragment <> </> invisible wrapper structural attributes key ref style event handlers on plus PascalCase signal name onPressed pressed onTextSubmitted text_submitted onFocusEntered focus_entered onFocusExited focus_exited onButtonDown onResized resized onValueChanged value_changed onItemSelected item_selected onTabChanged tab_changed onToggled toggled on_<signal> escape hatch modules hooks Hooks.useState Hooks.useEffect rules gotchas hook calls unconditional top level single root element class_name inferred override else first exported declaration else first declaration @class_name optional rarely needed',
        element: () => <UitkxReferencePage />,
      },
      {
        id: 'diagnostics',
        canonicalId: 'diagnostics',
        title: 'Diagnostics',
        path: '/diagnostics',
        keywords: ['diagnostics', 'errors', 'warnings', 'codes'],
        searchContent: 'diagnostics reference diagnostic code guitkx compiler language server severity meaning fix compile time .guitkx files sibling .guitkx.diags.json push_error push_warning godot output parser diagnostics GUITKX0300 unexpected missing token GUITKX0301 unclosed tag GUITKX0302 mismatched closing tag GUITKX0303 missing block unexpected eof GUITKX0304 unclosed brace paren GUITKX0305 unknown @directive GUITKX2506 directive shape error structural semantic diagnostics GUITKX2101 no declaration no markup return GUITKX0103 retired component name differs from file name GUITKX0104 duplicate sibling key GUITKX0106 loop element missing key GUITKX0108 multiple root elements GUITKX2504 invalid module deprecated wrapper GUITKX2505 duplicate declaration GUITKX0026 statement in embedded expression declaration export diagnostics GUITKX2320 deprecated wrapper keyword GUITKX2321 use_ returns RuitkVNode GUITKX2322 reserved not emitted GUITKX2323 export non-declaration GUITKX2324 duplicate export GUITKX2325 import alias collision GUITKX2326 no default export GUITKX2327 duplicate export default GUITKX2203 retired language server diagnostics editor extension GUITKX0105 unknown element did you mean suggestion GUITKX0109 unknown attribute on host element classdb runtime hook validation GUITKX0013 hook called conditionally in block positional-slot model hook-order validator RuitkConfig.enable_hook_validation RuitkDiagnostics push_error component hook module @if @for @while @match @case @default @class_name @extends @use',
        element: () => <UitkxDiagnosticsPage />,
      },
      {
        id: 'config',
        canonicalId: 'configuration',
        title: 'Configuration',
        path: '/config',
        keywords: ['config', 'settings', 'vscode', 'extension', 'formatter'],
        searchContent: 'configuration reference options guitkx editor extension formatter settings guitkx.enableEmbeddedAnalysis guitkx.enableGdscriptAnalysis guitkx.useGdformat guitkx.restartLanguageServer gdscript-analyzer headless embedded gdscript analysis gdformat gdscript-toolkit godot-tools editor defaults editor.defaultFormatter ReactiveUITK.guitkx editor.formatOnSave editor.insertSpaces false tabs editor.tabSize 4 editor.autoIndent full editor.detectIndentation false formatter configuration guitkx.config.json prettier-style walk-up printWidth indentStyle tab space indentSize singleAttributePerLine insertSpaceBeforeSelfClose',
        element: () => <UitkxConfigPage />,
      },
      {
        id: 'debugging',
        canonicalId: 'debugging',
        title: 'Debugging Guide',
        path: '/debugging',
        keywords: ['debugging', 'troubleshooting', 'logs', 'generated code'],
        searchContent: 'debugging guide diagnose fix common issues inspecting generated code .guitkx sibling .gd guitkx compiler render props children V.* factory calls .guitkx.diags.json diagnostics json @tool editor plugin push_error push_warning godot output GUITKX diagnostic codes remote scene tree debugger tab debugger panel breakpoint gdscript-analyzer embedded language server GUITKX restart language server output channel [guitkx] guitkx.useGdformat editor.defaultFormatter ReactiveUITK.guitkx missing completions stale diagnostics formatter issues format-on-save reporting bugs',
        element: () => <UitkxDebuggingPage />,
      },
    ],
  },
  {
    id: 'faq',
    title: 'FAQ',
    pages: [
      {
        id: 'faq-page',
        canonicalId: 'faq-page',
        title: 'FAQ',
        path: '/faq',
        keywords: ['faq', 'frequently asked questions', 'help'],
        searchContent: 'frequently asked questions what is reactiveui react-style ui framework for godot gdscript function components hooks fiber reconciler control tree addon addons/reactive_ui_toolkit what is .guitkx markup language jsx-style tags @if @for @match @tool editor plugin compiles sibling .gd render function V factory which godot versions supported godot 4.4 and above 4.x Control Theme StyleBox no gdextension different from plain control nodes useState useReducer useSignal runtime overhead only on state change time-slicing on by default RuitkConfig.time_slicing sync opt-out atomic commit mount always synchronous component RuitkRoot.create V.fc unmount _ready _exit_tree event handlers on plus PascalCase signal name onPressed onTextChanged onValueChanged onTextSubmitted onFocusEntered onFocusExited onButtonDown onGuiInput map to godot signals on_<signal> escape hatch MIGRATION-0.9.md plain gdscript setup {expr} hooks top level unconditional RuitkConfig.enable_hook_validation share state RuitkSignal useSignal useContext styling style dict RuitkStyle no uss no css RuitkStyleSheet classes preload load res:// Texture2D FontFile Theme StyleBox editors vs code visual studio language server rust gdscript analyzer in-editor godot addon roadmap too many re-renders setState during render depth 25 bg_color corner_radius_all content_margin_all panelcontainer button lineedit progressbar stylebox slot',
        element: () => <FAQPage />,
      },
    ],
  },
  {
    id: 'licensing',
    title: 'Licensing',
    pages: [
      {
        id: 'licensing-page',
        canonicalId: 'licensing-page',
        title: 'Licensing',
        path: '/licensing',
        keywords: ['license', 'licensing', 'pricing', 'commercial', 'free tier'],
        searchContent:
          'licensing license free tier 250k threshold reactiveui community license 1.0 commercial license per-title 2000 studio 2500 per year revenue funding trailing 12 months ship commercially credits made with reactiveui noncompete competing product reselling old versions keep their terms grandfather contractor client revenue 60-day cure window nonprofit edge case certificate pdf publisher platform paperwork LICENSE LICENSE-COMMERCIAL.md CLA contributor license agreement',
        element: () => <LicensingPage />,
      },
    ],
  },
  {
    id: 'known-issues',
    title: 'Known Issues',
    pages: [
      {
        id: 'known-issues-page',
        canonicalId: 'known-issues-page',
        title: 'Known Issues',
        path: '/known-issues',
        keywords: ['issues', 'limitations', 'known issues'],
        searchContent: 'known issues hook rules unconditional top level @if @for @match event handler call-order-to-slot mapping desync RuitkConfig.enable_hook_validation hooks not thread-safe main thread render cycle useSignal render-depth guard 25 re-render restarts infinite loop setup useEffect styling caveats stylebox keys bg_color border_color border_width_all corner_radius_all content_margin_all primary stylebox slot PanelContainer Button LineEdit TextEdit ProgressBar bare Label warns once per-state slots hover pressed disabled focus read_only RuitkStyleSheet classes ordered dictionary merge no cascade no selector no specificity Theme StyleBox theme_type_variation resource loading preload constant res:// path compile time load runtime null missing file AudioStreamPlayer VideoStreamPlayer no children tooling godot script editor lsp server not client in-editor addon roadmap vs code visual studio @tool plugin on-save compilation 4.4+ stdio subprocess runtime 4.2+ compilation sibling .gd parse error failed to load resource .import RuitkConfig.enable_strict_diagnostics state updates during render',
        element: () => <KnownIssuesPage />,
      },
    ],
  },
  {
    id: 'roadmap',
    title: 'Roadmap',
    pages: [
      {
        id: 'roadmap-page',
        canonicalId: 'roadmap-page',
        title: 'Roadmap',
        path: '/roadmap',
        keywords: ['roadmap', 'future', 'plans'],
        searchContent: 'roadmap completed core runtime fiber reconciler synchronous atomic two-phase commit keyed reconciliation bailout full hook set useState useReducer useEffect useMemo useRef useContext useSignal useTween host elements godot controls styling RuitkStyle style dicts RuitkStyleSheet named bundles signals RuitkSignal app-wide state client-side router routes outlet navigate nav_link Fragment Portal Suspense error-boundary tooling .guitkx markup language @tool compiler sibling .gd render function vs code visual studio extensions LSP rust gdscript analyzer documentation site planned native godot-editor addon 4.4+ loyal-to-godot event names on plus PascalCase signal onPressed onValueChanged onTextSubmitted on_<signal> MIGRATION-0.9.md custom-draw escape hatch _draw open tag vocabulary ClassDB more host elements godot asset library versioned releases CI sample gallery starter templates under consideration GDExtension backend component testing utilities snapshot tree assertions performance diagnostics overlay',
        element: () => <RoadmapPage />,
      },
    ],
  },
]

// ---------------------------------------------------------------------------
// Flat page lists
// ---------------------------------------------------------------------------

export const allFlat: DocPage[] = sections.flatMap((section) => {
  if (section.title === 'Components') {
    const common = section.pages.filter((page) => page.group === 'basic')
    const uncommon = section.pages.filter((page) => page.group === 'advanced' || !page.group)
    return [...common, ...uncommon]
  }
  return section.pages
})

// ---------------------------------------------------------------------------
// Version-aware filtering
// ---------------------------------------------------------------------------

/** Check if a page is available for the given Godot version. */
const isPageAvailable = (page: DocPage, selectedVersion: string): boolean => {
  if (page.sinceGodot) {
    return compareVersions(page.sinceGodot, selectedVersion) <= 0
  }
  const pv = PAGE_VERSIONS[page.canonicalId]
  return isAvailableIn(pv, selectedVersion)
}

/** Filter sections to only include pages available in the selected version. */
export const getFilteredSections = (selectedVersion: string): DocSection[] =>
  sections
    .map((section) => ({
      ...section,
      pages: section.pages.filter((page) => isPageAvailable(page, selectedVersion)),
    }))
    .filter((section) => section.pages.length > 0)

/** Flat page list filtered by version — for search and sidebar. */
export const getFilteredFlat = (selectedVersion: string): DocPage[] =>
  getFilteredSections(selectedVersion).flatMap((section) => {
    if (section.title === 'Components') {
      const common = section.pages.filter((page) => page.group === 'basic')
      const uncommon = section.pages.filter((page) => page.group === 'advanced' || !page.group)
      return [...common, ...uncommon]
    }
    return section.pages
  })
