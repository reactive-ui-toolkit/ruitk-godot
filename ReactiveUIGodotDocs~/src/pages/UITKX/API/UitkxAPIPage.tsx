import type { FC } from 'react'
import { Box, List, ListItem, ListItemText, Typography } from '@mui/material'
import Styles from '../../API/APIPage.style'

export const UitkxAPIPage: FC = () => (
  <Box sx={Styles.root}>
    <Typography variant="h4" component="h1" gutterBottom>
      API Reference
    </Typography>
    <Typography variant="body1" paragraph>
      A high-level map of the main global classes (Godot <code>class_name</code>s
      registered by the addon) and where to find things. Everything lives under{' '}
      <code>addons/reactive_ui_toolkit/</code>; copy that folder into a project and the{' '}
      <code>V</code>, <code>Hooks</code>, <code>ReactiveRoot</code>, and related
      class names become globally available.
    </Typography>

    <Box sx={Styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        Core
      </Typography>
      <List sx={Styles.list}>
        <ListItem disablePadding>
          <ListItemText primary={<><code>V</code> — the virtual-node layer that <code>.guitkx</code> markup compiles to. Day to day you meet it in exactly two places: <code>V.fc(render_fn, props)</code> when mounting (wrapping a component&apos;s generated <code>render</code> as the root vnode), and the structural primitives that have no markup tag yet — <code>V.portal</code>, <code>V.suspense</code>, <code>V.error_boundary</code>, <code>V.memo</code>, and the router set — called from an embedded <code>{'{ expr }'}</code> inside markup. (GDScript reserves <code>func</code>, so the component factory is <code>V.fc</code>, not <code>V.func</code>.)</>} />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary={<><code>Hooks</code> — hook functions: <code>useState</code>, <code>useReducer</code>, <code>useEffect</code>, <code>useLayoutEffect</code>, <code>useMemo</code>, <code>useCallback</code>, <code>useRef</code>, <code>useContext</code>, <code>provideContext</code>, <code>useDeferredValue</code>, <code>useTransition</code>, <code>useImperativeHandle</code>, <code>useStableCallback</code>, <code>useStableFunc</code>, <code>useStableAction</code>, <code>useSignal</code>, <code>useSignalKey</code>, <code>useAnimate</code>, <code>useTween</code>, <code>useTweenValue</code>, <code>useSfx</code>, <code>useSafeArea</code>. Config: <code>RUIConfig.enable_hook_validation</code>, <code>RUIConfig.enable_strict_diagnostics</code>.</>} />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary={<><code>ReactiveRoot</code> — mounts a virtual tree under a container Node. <code>ReactiveRoot.create(container, V.fc(render))</code> does the initial render; keep the returned instance referenced. <code>set_root(vnode)</code> re-renders with a new top-level vnode; <code>unmount()</code> runs cleanups and frees mounted nodes.</>} />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary={<><code>ReactiveRootNode</code> — a scene-lifecycle <code>Control</code> that mounts on <code>_ready</code> and unmounts on <code>_exit_tree</code> automatically (no need to hold a reference). Use <code>.setup(component, props)</code> in code, or attach a script that <code>extends ReactiveRootNode</code> and override <code>build()</code>.</>} />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary={<><code>RUIVNode</code> — the immutable virtual-node type produced by <code>V.*</code> and by the <code>.guitkx</code> codegen. You rarely construct it directly.</>} />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary={<><code>RUIReconciler</code> — the fiber reconciler that diffs and commits vnode trees. Owned by <code>ReactiveRoot</code>; you don&apos;t use it directly.</>} />
        </ListItem>
      </List>
    </Box>

    <Box sx={Styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        Host &amp; Styling
      </Typography>
      <List sx={Styles.list}>
        <ListItem disablePadding>
          <ListItemText primary={<><code>RUIHost</code> — the &quot;host config&quot;: the only layer that knows concrete Godot node APIs. Maps element type names (<code>&quot;Button&quot;</code>, <code>&quot;LineEdit&quot;</code>, …) to node creation/prop-application, translates <code>on</code> + PascalCase(signal) handler props (<code>onPressed</code>, <code>onValueChanged</code>, …) to Godot signal connections, and drives declarative item-model adapters. Swapping this file (plus <code>RUIStyle</code>) is what retargets the reconciler at a different host.</>} />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary={<><code>RUIStyle</code> — maps a <code>style</code> Dictionary onto Godot Control properties, size flags, Theme overrides, and StyleBox. The only place that knows Godot styling APIs. See the <strong>Style Helpers</strong> reference for the full key vocabulary.</>} />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary={<><code>RUIStyleSheet</code> — a reusable named style set. A host element&apos;s <code>classes</code> prop merges matching styles (left-to-right), then inline <code>style</code> wins — a plain dictionary merge, no CSS cascade.</>} />
        </ListItem>
      </List>
    </Box>

    <Box sx={Styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        Router
      </Typography>
      <List sx={Styles.list}>
        <ListItem disablePadding>
          <ListItemText primary={<><code>RUIRouter</code> — router hooks and primitives. Hooks: <code>useRouter()</code>, <code>useLocation()</code>, <code>useLocationInfo()</code>, <code>useParams()</code>, <code>useQuery()</code>, <code>useSearchParams()</code>, <code>useNavigationState()</code>, <code>useNavigate(replace?)</code>, <code>useGo()</code>, <code>useCanGo(delta)</code>, <code>useMatches()</code>, <code>useRouteMatch()</code>, <code>useNavigationBase()</code>, <code>useResolvedPath(to)</code>, <code>useOutletContext()</code>, <code>useBlocker(...)</code>, <code>usePrompt(...)</code>.</>} />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary={<>Router primitives (no markup tags yet — called from an embedded <code>{'{ expr }'}</code>): <code>V.router</code>, <code>V.routes</code>, <code>V.route</code>, <code>V.outlet</code>, <code>V.navigate</code>, <code>V.nav_link</code>, <code>V.link</code>.</>} />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary={<><code>RUIHistory</code> — the history abstraction. Supply a custom history to control how locations are stored.</>} />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary={<><code>RUIRouterLocation</code>, <code>RUIRouterPath</code>, <code>RUIRouteMatch</code>, <code>RUIRouteMatcher</code>, <code>RUIRouteRanker</code> — types describing the current location, parsed path, route-matching result, and the ranking/first-match logic shared by <code>V.routes</code> and nested <code>V.route</code>.</>} />
        </ListItem>
      </List>
    </Box>

    <Box sx={Styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        Signals
      </Typography>
      <List sx={Styles.list}>
        <ListItem disablePadding>
          <ListItemText primary={<><code>RUISignal</code> — a reactive value store that lives outside the component tree. Create and share one: <code>var counter := RUISignal.new(0)</code>. API: <code>get_value()</code>, <code>set_value(v)</code>, <code>update(func(old): return new)</code>, <code>subscribe(cb) -&gt; unsubscribe</code>. (Named <code>RUISignal</code> because Godot reserves <code>signal</code>.)</>} />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary={<><code>RUISignals</code> — the process-wide keyed registry. <code>RUISignals.get_or_create(key, initial)</code> returns one shared <code>RUISignal</code> per key; <code>try_get</code>, <code>has</code>, and <code>clear()</code> (drop keyed state on a full session reset).</>} />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary={<>Read signals inside components with <code>useSignal(sig, selector?, comparer?)</code> or <code>useSignalKey(key, initial?, selector?, comparer?)</code>.</>} />
        </ListItem>
      </List>
    </Box>

    <Box sx={Styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        Animation &amp; Media
      </Typography>
      <List sx={Styles.list}>
        <ListItem disablePadding>
          <ListItemText primary={<><code>Hooks.useAnimate(ref, tracks, autoplay, deps)</code> — plays a list of property tracks on a mounted node via a Godot <code>Tween</code>. A fresh tween is built on mount / when deps change; the previous one is killed on cleanup.</>} />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary={<><code>Hooks.useTween(ref, property, to, duration, deps)</code> — smoothly tweens a mounted node&apos;s property when deps change. <code>Hooks.useTweenValue(from, to, duration, on_update, deps)</code> drives <code>on_update(value)</code> each frame (animate without re-rendering).</>} />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary={<><code>RUIMedia</code> — transient one-shot audio via a self-freeing <code>AudioStreamPlayer</code>. <code>Hooks.useSfx(bus)</code> returns a stable <code>func(stream, volume_db, pitch_scale)</code> for event handlers.</>} />
        </ListItem>
      </List>
    </Box>

    <Box sx={Styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        Safe Area
      </Typography>
      <List sx={Styles.list}>
        <ListItem disablePadding>
          <ListItemText primary={<><code>Hooks.useSafeArea()</code> — returns a Dictionary of pixel insets (<code>left</code>, <code>top</code>, <code>right</code>, <code>bottom</code>) from <code>DisplayServer.get_display_safe_area()</code>. Apply them as padding on a container.</>} />
        </ListItem>
      </List>
    </Box>

    <Box sx={Styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        Suspense &amp; Diagnostics
      </Typography>
      <List sx={Styles.list}>
        <ListItem disablePadding>
          <ListItemText primary={<><code>RUISuspense</code> — the suspense boundary implementation behind <code>V.suspense</code>. GDScript can&apos;t throw-to-suspend, so readiness is signal/poll driven (<code>ready_signal</code> or <code>is_ready()</code>) and shows <code>fallback</code> until ready.</>} />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary={<><code>RUIConfig</code> — static configuration flags (hook validation, strict diagnostics), defaulting to <code>OS.is_debug_build()</code>.</>} />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary={<><code>RUIDiagnostics</code> — collects framework warnings/errors (hook-order divergence, set-in-render, unknown host element, etc.) for the editor tooling to surface.</>} />
        </ListItem>
      </List>
    </Box>
  </Box>
)
