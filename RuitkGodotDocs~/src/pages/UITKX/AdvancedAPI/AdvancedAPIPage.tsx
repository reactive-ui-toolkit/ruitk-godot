import type { FC } from 'react'
import {
  Alert,
  Box,
  List,
  ListItem,
  ListItemText,
  Paper,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableRow,
  Typography,
} from '@mui/material'
import { CodeBlock } from '../../../components/CodeBlock/CodeBlock'
import {
  DEPTH_GUARD_EXAMPLE,
  ELEMENT_REGISTRY_EXAMPLE,
  ERROR_PATTERNS_EXAMPLE,
  FLUSHSYNC_EXAMPLE,
  HOSTCONTEXT_EXAMPLE,
  PROPTYPES_EXAMPLE,
  SCHEDULER_EXAMPLE,
  SNAPSHOT_EXAMPLE,
  VIRTUALNODE_EXAMPLE,
} from './AdvancedAPIPage.example'

const styles = {
  root: { display: 'flex', flexDirection: 'column', gap: 2 },
  section: { mt: 3 },
  list: { pl: 2 },
} as const

/* ------------------------------------------------------------------ */
/*  Custom-draw props table                                            */
/* ------------------------------------------------------------------ */

type PropRow = { prop: string; type: string; desc: string }

const drawProps: PropRow[] = [
  { prop: 'draw_fn', type: 'Callable(canvas_item)', desc: "Issues the node's draw_* calls, invoked via the node's 'draw' signal" },
  { prop: 'redraw_key', type: 'any', desc: 'Bump to repaint (queue_redraw) the same callback without re-subscribing' },
  { prop: 'ref', type: 'useRef box', desc: 'After commit, ref["current"] is the underlying Godot Control' },
  { prop: '__memo_eq', type: 'Callable(old, new) -> bool', desc: 'Custom props equality; return true to skip the re-render' },
]

/* ------------------------------------------------------------------ */
/*  Batching / priority table                                          */
/* ------------------------------------------------------------------ */

type PriorityRow = { name: string; when: string; desc: string }

const priorities: PriorityRow[] = [
  { name: 'Batched (default)', when: 'Setters in a handler', desc: 'Coalesced into one commit on the next process_frame' },
  { name: 'Deferred', when: 'useDeferredValue', desc: 'Low-priority follow-up frame — urgent update paints first' },
  { name: 'Sliced', when: 'Large subtree re-renders', desc: 'Work can continue across a parked process_frame tick' },
]

/* ------------------------------------------------------------------ */
/*  Node kinds table                                                   */
/* ------------------------------------------------------------------ */

type NodeTypeRow = { name: string; desc: string }

const nodeTypes: NodeTypeRow[] = [
  { name: 'Host element', desc: 'A Godot Control (Button, Label, …) — V.Button / V.Label / V.h' },
  { name: 'Function component', desc: 'A user render fn — V.fc(render, props) / V.memo(...)' },
  { name: 'Fragment', desc: 'Invisible grouping wrapper — V.fragment([...])' },
  { name: 'Portal', desc: 'Renders children under a different target Node — V.portal(target, [...])' },
  { name: 'Suspense', desc: 'Shows fallback until ready (signal/poll driven) — V.suspense(...)' },
  { name: 'Error boundary', desc: 'Shows fallback when activated; resets on reset_key — V.error_boundary(...)' },
]

/* ------------------------------------------------------------------ */
/*  Page                                                               */
/* ------------------------------------------------------------------ */

export const AdvancedAPIPage: FC = () => (
  <Box sx={styles.root}>
    <Typography variant="h4" component="h1" gutterBottom>
      Advanced API Reference
    </Typography>
    <Typography variant="body1" paragraph>
      This page covers advanced patterns that most users won&apos;t need for
      everyday <code>.guitkx</code> development: memoization and custom props
      equality, refs into Godot nodes, the frame scheduler, stable callbacks,
      error boundaries, the render-depth guard, custom drawing, item-model host
      elements, and building trees with the <code>V</code> factory directly.
    </Typography>

    {/* ── Memoization & props equality ─────────────────────────── */}
    <Box sx={styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        Memoization &amp; custom props equality
      </Typography>
      <Typography variant="body1" paragraph>
        Every function component already bails its re-render when its props are
        unchanged (shallow <code>==</code>). For a custom comparison, pass a{' '}
        <code>__memo_eq</code> Callable in props — the reconciler consults it to
        decide whether to skip the child. Inside a component, use{' '}
        <code>useMemo</code> to cache derived values and <code>useCallback</code>{' '}
        to stabilise a Callable&apos;s identity.
      </Typography>
      <CodeBlock language="jsx" code={PROPTYPES_EXAMPLE} />
    </Box>

    {/* ── Refs to Godot nodes ──────────────────────────────────── */}
    <Box sx={styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        Refs into Godot nodes
      </Typography>
      <Typography variant="body1" paragraph>
        A <code>useRef(null)</code> box wired to the <code>ref</code> prop
        captures the underlying Godot <code>Control</code> after commit. Read{' '}
        <code>ref[&quot;current&quot;]</code> to call any node method imperatively
        (scroll position, focus, animation targets). Do this from{' '}
        <code>useLayoutEffect</code> when you need it before the frame paints.
      </Typography>
      <CodeBlock language="jsx" code={HOSTCONTEXT_EXAMPLE} />

      <List sx={styles.list}>
        <ListItem disablePadding>
          <ListItemText primary={<>The ref box is stable and never re-created; <code>ref[&quot;current&quot;]</code> is <code>null</code> before the first commit.</>} />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary={<>Prefer state for anything the UI should react to — refs are an imperative escape hatch.</>} />
        </ListItem>
      </List>
    </Box>

    {/* ── Frame scheduler / batching ───────────────────────────── */}
    <Box sx={styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        Frame scheduler &amp; batching
      </Typography>
      <Typography variant="body1" paragraph>
        The reconciler schedules render work on the SceneTree&apos;s{' '}
        <code>process_frame</code> signal — there is no manual scheduler API.
        Multiple setters fired from one event handler coalesce into a single
        re-render committed next frame.
      </Typography>

      <TableContainer component={Paper} variant="outlined" sx={{ mb: 2 }}>
        <Table size="small">
          <TableHead>
            <TableRow>
              <TableCell><strong>Mode</strong></TableCell>
              <TableCell><strong>Triggered by</strong></TableCell>
              <TableCell><strong>Behaviour</strong></TableCell>
            </TableRow>
          </TableHead>
          <TableBody>
            {priorities.map((r) => (
              <TableRow key={r.name}>
                <TableCell><code>{r.name}</code></TableCell>
                <TableCell>{r.when}</TableCell>
                <TableCell>{r.desc}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </TableContainer>

      <CodeBlock language="jsx" code={SCHEDULER_EXAMPLE} />
    </Box>

    {/* ── Stable callbacks ─────────────────────────────────────── */}
    <Box sx={styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        Stable callbacks
      </Typography>
      <Typography variant="body1" paragraph>
        <code>useStableCallback</code> (0-arg) and <code>useStableAction</code>{' '}
        (1-arg) return a wrapper whose identity <strong>never</strong> changes
        across renders but that always calls the latest closure. Use them for
        handlers wired once to a Godot signal or handed to a child, so a fresh
        closure each render doesn&apos;t re-subscribe.
      </Typography>
      <CodeBlock language="jsx" code={FLUSHSYNC_EXAMPLE} />

      <Alert severity="info" sx={{ mt: 1 }}>
        <code>useCallback</code> changes identity when deps change;{' '}
        <code>useStableCallback</code> never does. Reach for the stable
        variants when you truly need a constant identity.
      </Alert>
    </Box>

    {/* ── Error boundaries ─────────────────────────────────────── */}
    <Box sx={styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        Error boundaries
      </Typography>
      <Typography variant="body1" paragraph>
        <code>V.error_boundary</code> shows a <code>fallback</code> and resets
        when its <code>reset_key</code> changes. Because GDScript has no
        try/catch, it cannot <strong>auto-catch</strong> a hard render-time
        crash (bad index, call on null) — that documented parity limitation
        survives. The cooperative path: a failing render{' '}
        <em>calls</em> <code>RuitkFail.render(reason)</code> and returns early —
        the nearest boundary shows its fallback in the same commit and receives
        the reason via <code>on_error</code>. Imperative activation
        (<code>&quot;active&quot;: true</code>) also works.
      </Typography>
      <CodeBlock language="jsx" code={ERROR_PATTERNS_EXAMPLE} />
    </Box>

    {/* ── Render depth guard ───────────────────────────────────── */}
    <Box sx={styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        Render depth guard
      </Typography>
      <Typography variant="body1" paragraph>
        A state update made <em>during</em> a render is deferred and replayed
        after commit as one follow-up render. The reconciler counts consecutive
        follow-ups; past <strong>25</strong> — usually caused by calling a setter
        unconditionally in a component&apos;s setup body — the guard drops the
        queued updates and keeps the committed UI instead of freezing the editor
        or game (&quot;Too many re-renders (setState during render?)&quot;).
      </Typography>
      <CodeBlock language="jsx" code={DEPTH_GUARD_EXAMPLE} />
    </Box>

    {/* ── Custom drawing ───────────────────────────────────────── */}
    <Box sx={styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        Custom drawing (draw_fn &amp; redraw_key)
      </Typography>
      <Typography variant="body1" paragraph>
        Two reserved props let you paint a Control&apos;s canvas declaratively —
        the Godot analogue of Unity&apos;s <code>OnGenerateVisualContent</code> +{' '}
        <code>RedrawKey</code>. A register-once trampoline reads the latest{' '}
        <code>draw_fn</code> from meta, so a fresh closure each render never
        re-subscribes; it repaints only when the callback identity or{' '}
        <code>redraw_key</code> changes.
      </Typography>

      <TableContainer component={Paper} variant="outlined" sx={{ mb: 2 }}>
        <Table size="small">
          <TableHead>
            <TableRow>
              <TableCell><strong>Prop</strong></TableCell>
              <TableCell><strong>Type</strong></TableCell>
              <TableCell><strong>Description</strong></TableCell>
            </TableRow>
          </TableHead>
          <TableBody>
            {drawProps.map((r) => (
              <TableRow key={r.prop}>
                <TableCell><code>{r.prop}</code></TableCell>
                <TableCell><code>{r.type}</code></TableCell>
                <TableCell>{r.desc}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </TableContainer>

      <CodeBlock language="jsx" code={SNAPSHOT_EXAMPLE} />
    </Box>

    {/* ── Host elements & item-model adapters ──────────────────── */}
    <Box sx={styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        Host elements &amp; item-model adapters
      </Typography>
      <Typography variant="body1" paragraph>
        <code>RuitkHost</code> is the only layer that knows concrete Godot node
        APIs. Item-model controls (<code>ItemList</code>, <code>OptionButton</code>,{' '}
        <code>TabBar</code>, <code>Tree</code>, <code>MenuBar</code>) are
        declarative: pass an <code>items</code> prop and the adapter rebuilds the
        control&apos;s model when it changes. Reach any Control without a named{' '}
        factory via the generic <code>V.h(&quot;GodotClassName&quot;, props, children)</code>.
      </Typography>
      <CodeBlock language="jsx" code={ELEMENT_REGISTRY_EXAMPLE} />

      <Alert severity="info" sx={{ mt: 1 }}>
        Userland can register an adapter for a custom item-model control via{' '}
        <code>RuitkHost.register_item_adapter(name, adapter)</code> — useful for
        third-party controls that need declarative item rebuilding.
      </Alert>
    </Box>

    {/* ── RuitkVNode / V factory ─────────────────────────────────── */}
    <Box sx={styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        RuitkVNode &amp; the V factory
      </Typography>
      <Typography variant="body1" paragraph>
        <code>RuitkVNode</code> is the immutable node type representing the virtual
        tree. In <code>.guitkx</code> files the codegen emits <code>V.*</code>{' '}
        calls for you; in pure GDScript you build trees directly with the{' '}
        <code>V</code> factory.
      </Typography>

      <TableContainer component={Paper} variant="outlined" sx={{ mb: 2 }}>
        <Table size="small">
          <TableHead>
            <TableRow>
              <TableCell><strong>Node kind</strong></TableCell>
              <TableCell><strong>Description</strong></TableCell>
            </TableRow>
          </TableHead>
          <TableBody>
            {nodeTypes.map((r) => (
              <TableRow key={r.name}>
                <TableCell><code>{r.name}</code></TableCell>
                <TableCell>{r.desc}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </TableContainer>

      <CodeBlock language="jsx" code={VIRTUALNODE_EXAMPLE} />
    </Box>
  </Box>
)
