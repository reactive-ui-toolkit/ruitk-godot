import type { FC } from 'react'
import {
  Alert,
  Box,
  List,
  ListItem,
  ListItemText,
  Typography,
} from '@mui/material'
import { CodeBlock } from '../../../components/CodeBlock/CodeBlock'
import {
  HOOKS_CONTEXT_EXAMPLE,
  HOOKS_DEFERRED_EXAMPLE,
  HOOKS_DEPENDENCY_RULES,
  HOOKS_IMPERATIVE_EXAMPLE,
  HOOKS_USECALLBACK_EXAMPLE,
  HOOKS_USEEFFECT_EXAMPLE,
  HOOKS_USELAYOUTEFFECT_EXAMPLE,
  HOOKS_USEMEMO_EXAMPLE,
  HOOKS_USEREDUCER_EXAMPLE,
  HOOKS_USEREF_EXAMPLE,
  HOOKS_USESTATE_EXAMPLE,
  HOOKS_STABLE_EXAMPLE,
} from './HooksGuidePage.example'

const styles = {
  root: { display: 'flex', flexDirection: 'column', gap: 2 },
  section: { mt: 2 },
  list: { pl: 2 },
} as const

export const HooksGuidePage: FC = () => (
  <Box sx={styles.root}>
    <Typography variant="h4" component="h1" gutterBottom>
      Hooks Guide
    </Typography>
    <Typography variant="body1" paragraph>
      Hooks let you use state, effects, context, and other framework features
      inside function-style <code>.guitkx</code> components. This page covers
      every hook in depth, with patterns and examples. In markup, bare{' '}
      camelCase calls like <code>useState</code> are auto-prefixed to{' '}
      <code>Hooks.useState</code>; the static methods live on the{' '}
      <code>Hooks</code> class.
    </Typography>

    <Alert severity="info" sx={{ mt: 1 }}>
      Hook calls must be <strong>unconditional</strong> and at the{' '}
      <strong>top level</strong> of your component&apos;s setup code (before{' '}
      <code>return</code>). Never call hooks inside <code>@if</code>,{' '}
      <code>@for</code>, nested lambdas, or other control blocks — the
      positional-slot model relies on a stable call order.
    </Alert>

    {/* ── useState ────────────────────────────────────────────── */}
    <Box sx={styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        useState
      </Typography>
      <CodeBlock language="jsx" code={`useState(initial = null) -> [value, set]`} />
      <Typography variant="body1" paragraph>
        Returns a two-element Array: the current value and a stable setter{' '}
        <code>Callable</code>. The setter accepts either a direct value or a
        functional updater <code>func(old) -&gt; new</code>. Functional updaters
        are safer when batching multiple updates because they always read the
        latest state. Setting an <em>equal</em> value bails out (no re-render).
      </Typography>
      <CodeBlock language="jsx" code={HOOKS_USESTATE_EXAMPLE} />
    </Box>

    {/* ── useReducer ──────────────────────────────────────────── */}
    <Box sx={styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        useReducer
      </Typography>
      <CodeBlock language="jsx" code={`useReducer(reducer: Callable, initial = null) -> [state, dispatch]
# reducer(state, action) -> new_state`} />
      <Typography variant="body1" paragraph>
        Preferred over <code>useState</code> when state transitions depend on
        the previous state and an action. The reducer is a pure function:{' '}
        <code>func(state, action) -&gt; new_state</code>. The returned{' '}
        <code>dispatch</code> identity is stable across renders.
      </Typography>
      <CodeBlock language="jsx" code={HOOKS_USEREDUCER_EXAMPLE} />
    </Box>

    {/* ── useEffect ───────────────────────────────────────────── */}
    <Box sx={styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        useEffect
      </Typography>
      <CodeBlock language="jsx" code={`useEffect(effect: Callable, deps = null) -> void`} />
      <Typography variant="body1" paragraph>
        Runs a passive effect <strong>after</strong> commit (two-pass: all
        cleanups, then all setups). The effect body may return a cleanup{' '}
        <code>Callable</code> that runs before the next effect or on unmount.
        Return <code>Callable()</code> (an empty Callable) if no cleanup is
        needed.
      </Typography>
      <Typography variant="h6" gutterBottom>
        Dependency rules
      </Typography>
      <CodeBlock language="jsx" code={HOOKS_DEPENDENCY_RULES} />
      <CodeBlock language="jsx" code={HOOKS_USEEFFECT_EXAMPLE} />
    </Box>

    {/* ── useLayoutEffect ────────────────────────────────────── */}
    <Box sx={styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        useLayoutEffect
      </Typography>
      <CodeBlock language="jsx" code={`useLayoutEffect(effect: Callable, deps = null) -> void`} />
      <Typography variant="body1" paragraph>
        Identical to <code>useEffect</code> but fires <strong>synchronously</strong>{' '}
        during commit, before the frame paints (cleanup-then-setup per fiber).
        Use it when you need to read a Control&apos;s layout (its{' '}
        <code>size</code>) or mutate a node before the user sees the frame. Same
        dependency semantics as <code>useEffect</code>.
      </Typography>
      <CodeBlock language="jsx" code={HOOKS_USELAYOUTEFFECT_EXAMPLE} />
    </Box>

    {/* ── useMemo ─────────────────────────────────────────────── */}
    <Box sx={styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        useMemo
      </Typography>
      <CodeBlock language="jsx" code={`useMemo(factory: Callable, deps: Array = []) -> value`} />
      <Typography variant="body1" paragraph>
        Returns a cached value. The factory re-runs only when a dependency
        changes (shallow, per-element comparison). Use it to avoid recomputing
        expensive derived data on every render.
      </Typography>
      <CodeBlock language="jsx" code={HOOKS_USEMEMO_EXAMPLE} />
    </Box>

    {/* ── useCallback ─────────────────────────────────────────── */}
    <Box sx={styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        useCallback
      </Typography>
      <CodeBlock language="jsx" code={`useCallback(cb: Callable, deps: Array = []) -> Callable`} />
      <Alert severity="warning" sx={{ mb: 1 }}>
        <code>useCallback(cb, deps)</code> is <code>useMemo(func(): return cb, deps)</code>:
        it returns the same <code>Callable</code> instance while deps are
        unchanged. If you need a callback whose identity <em>never</em> changes
        but that always calls the latest closure, use{' '}
        <code>useStableCallback</code> / <code>useStableAction</code> instead.
      </Alert>
      <Typography variant="body1" paragraph>
        Returns a stable <code>Callable</code> whose identity only changes when a
        dependency changes. Useful for passing callbacks to child components
        without triggering unnecessary re-renders.
      </Typography>
      <CodeBlock language="jsx" code={HOOKS_USECALLBACK_EXAMPLE} />
    </Box>

    {/* ── useRef ──────────────────────────────────────────────── */}
    <Box sx={styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        useRef &amp; Control refs
      </Typography>
      <CodeBlock language="jsx" code={`useRef(initial = null) -> { "current": initial }`} />
      <List sx={styles.list}>
        <ListItem disablePadding>
          <ListItemText primary={<><code>useRef(value)</code> returns a stable Dictionary box with a <code>&quot;current&quot;</code> entry. It is never re-created. Changing <code>ref[&quot;current&quot;]</code> does <strong>not</strong> trigger a re-render.</>} />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary={<>Pass a <code>useRef(null)</code> box to the <code>ref</code> prop of a host element. After commit, <code>ref[&quot;current&quot;]</code> is the underlying Godot <code>Control</code> node.</>} />
        </ListItem>
      </List>
      <CodeBlock language="jsx" code={HOOKS_USEREF_EXAMPLE} />
    </Box>

    {/* ── Context ──────────────────────────────────────────────── */}
    <Box sx={styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        useContext &amp; provideContext
      </Typography>
      <CodeBlock language="jsx" code={`Hooks.createContext(default_value = null, name = "") -> RuitkContext   # recommended
useContext(handle_or_key)             # nearest provided value, or the handle's default
Hooks.provideContext(handle_or_key, value) -> void`} />
      <Typography variant="body1" paragraph>
        Context lets you pass data down the component tree without threading
        props through every level. Both <code>provideContext</code> and{' '}
        <code>useContext</code> accept either a <strong>context handle</strong> (from{' '}
        <code>Hooks.createContext(...)</code> — recommended) or a bare String key
        (back-compat). <code>provideContext</code> makes a value available to the
        current fiber&apos;s subtree; <code>useContext</code> reads it.
      </Typography>
      <List sx={styles.list}>
        <ListItem disablePadding>
          <ListItemText primary={<>Prefer a handle from <code>Hooks.createContext(default)</code> — it is keyed by object identity, so it can never collide with an unrelated feature&apos;s key, and it gives every consumer a default value for free. Bare String keys still work for back-compat but can collide.</>} />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary="Nested providers shadow outer providers for the same key, whether it's a handle or a String." />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary="When a provided value changes, all consumers in the subtree are marked dirty and automatically re-render." />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary="useContext does not consume a hook slot (context reads are kept out of the positional slot array)." />
        </ListItem>
      </List>
      <CodeBlock language="jsx" code={HOOKS_CONTEXT_EXAMPLE} />
      <Alert severity="info" sx={{ mt: 1 }}>
        See the dedicated <strong>Context API</strong> page for the full{' '}
        <code>createContext</code> handle walkthrough and advanced patterns
        (shadowing, performance, when to prefer signals).
      </Alert>
    </Box>

    {/* ── useDeferredValue ───────────────────────────────────── */}
    <Box sx={styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        useDeferredValue
      </Typography>
      <CodeBlock language="jsx" code={`useDeferredValue(value, deps = null) -> deferred_value`} />
      <Typography variant="body1" paragraph>
        Returns a copy of <code>value</code> that may lag one frame behind. On
        the render where <code>value</code> changes it returns the{' '}
        <strong>previous</strong> value, then commits the new value on a
        low-priority next-frame tick (re-rendering once). This lets an urgent
        update (like typing into a <code>LineEdit</code>) paint immediately while
        expensive derived work (like filtering a large list) catches up a frame
        later. Pass <code>deps</code> to gate on a key instead of the value
        itself.
      </Typography>
      <CodeBlock language="jsx" code={HOOKS_DEFERRED_EXAMPLE} />
    </Box>

    {/* ── useImperativeHandle ────────────────────────────────── */}
    <Box sx={styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        useImperativeHandle
      </Typography>
      <CodeBlock language="jsx" code={`useImperativeHandle(factory: Callable, deps: Array = []) -> handle`} />
      <Typography variant="body1" paragraph>
        Builds an imperative API object (typically a Dictionary of{' '}
        <code>Callable</code>s) that a child exposes to its parent. It is{' '}
        <code>useMemo(factory, deps)</code> under the hood — the handle is
        recomputed only when dependencies change. Publish it to a parent&apos;s{' '}
        <code>useRef</code> box (passed down as a prop) from a layout effect.
      </Typography>
      <CodeBlock language="jsx" code={HOOKS_IMPERATIVE_EXAMPLE} />
    </Box>

    {/* ── Stable function helpers ──────────────────────────────── */}
    <Box sx={styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        Stable function helpers
      </Typography>
      <CodeBlock language="jsx" code={`useStableCallback(cb: Callable) -> Callable   # 0-arg
useStableFunc(cb: Callable) -> Callable        # alias of useStableCallback
useStableAction(cb: Callable) -> Callable      # 1-arg`} />
      <Typography variant="body1" paragraph>
        These hooks return a wrapper whose identity <strong>never changes</strong>{' '}
        across renders. The wrapper always calls through to the latest closure
        body. Use them for event handlers passed to child components or wired to
        Godot signals via the <code>on*</code> props.
      </Typography>
      <CodeBlock language="jsx" code={HOOKS_STABLE_EXAMPLE} />
    </Box>

    {/* ── Configuration properties ─────────────────────────────── */}
    <Box sx={styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        Hook configuration
      </Typography>
      <Typography variant="body1" paragraph>
        <code>RuitkConfig</code> exposes static flags that control runtime
        validation (default: debug/editor only):
      </Typography>
      <List sx={styles.list}>
        <ListItem disablePadding>
          <ListItemText
            primary={<><code>RuitkConfig.enable_hook_validation</code> — validates that hooks are called in the same order every render, and pushes an error on the first divergence.</>}
          />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText
            primary={<><code>RuitkConfig.enable_strict_diagnostics</code> — enables additional checks such as warning when state is set during render.</>}
          />
        </ListItem>
      </List>
    </Box>
  </Box>
)
