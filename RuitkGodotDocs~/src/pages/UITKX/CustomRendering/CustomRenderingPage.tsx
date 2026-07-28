import type { FC } from 'react'
import {
  Alert,
  Box,
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
  CUSTOM_RENDERING_HELPERS_EXAMPLE,
  CUSTOM_RENDERING_PAINTER_EXAMPLE,
  CUSTOM_RENDERING_RAW_MESH_EXAMPLE,
  CUSTOM_RENDERING_REDRAW_KEY_EXAMPLE,
  CUSTOM_RENDERING_SIGNATURE_EXAMPLE,
} from './CustomRenderingPage.example'

const styles = {
  root: { display: 'flex', flexDirection: 'column', gap: 2 },
  section: { mt: 2 },
} as const

/* ------------------------------------------------------------------ */
/*  Prop reference                                                    */
/* ------------------------------------------------------------------ */

type AttrRow = { name: string; type: string; desc: string }

const attributes: AttrRow[] = [
  {
    name: 'draw_fn',
    type: 'Callable(canvas_item)',
    desc: 'Custom draw callback. Runs during the node’s "draw" signal and receives the node (a CanvasItem); issue Godot draw_* calls on it (draw_rect, draw_line, draw_polyline, draw_circle, draw_texture, …). Ignored with a push_warning on nodes that are not CanvasItems.',
  },
  {
    name: 'redraw_key',
    type: 'any',
    desc: 'Change this value to force a repaint without changing the callback reference. Pair it with a stable callback (useStableCallback / useStableAction). Leaving it unchanged never forces a repaint on its own.',
  },
]

const AttrTable: FC = () => (
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
        {attributes.map((a) => (
          <TableRow key={a.name}>
            <TableCell><code>{a.name}</code></TableCell>
            <TableCell><code>{a.type}</code></TableCell>
            <TableCell>{a.desc}</TableCell>
          </TableRow>
        ))}
      </TableBody>
    </Table>
  </TableContainer>
)

/* ------------------------------------------------------------------ */
/*  Main page                                                         */
/* ------------------------------------------------------------------ */

export const CustomRenderingPage: FC = () => (
  <Box sx={styles.root}>
    <Typography variant="h4" component="h1" gutterBottom>
      Custom Rendering
    </Typography>
    <Typography variant="body1" paragraph>
      Any host element that is a <code>CanvasItem</code> (which is every{' '}
      <code>Control</code>) accepts a <code>draw_fn</code> prop — a declarative
      binding for Godot&apos;s <code>_draw</code> / <code>draw</code> mechanism.
      Use it to draw your own vector shapes, charts, gauges, or sprites directly
      into an element while the rest of your UI stays fully reactive. The
      callback receives the node and runs during its <code>draw</code> signal.
      This is the Godot analogue of the Unity reference&apos;s{' '}
      <code>onGenerateVisualContent</code> + <code>redrawKey</code>.
    </Typography>

    {/* ── Prop reference ───────────────────────────────────────── */}
    <Box sx={styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        Props
      </Typography>
      <AttrTable />
      <CodeBlock language="gdscript" code={CUSTOM_RENDERING_SIGNATURE_EXAMPLE} />
    </Box>

    {/* ── How repaints work ────────────────────────────────────── */}
    <Box sx={styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        How repainting works
      </Typography>
      <Typography variant="body1" paragraph>
        Godot only re-runs a node&apos;s draw code when it is told to repaint
        (<code>queue_redraw</code>). The host config handles that for you: it
        registers a single trampoline on the node&apos;s <code>draw</code> signal
        exactly once, and that trampoline always reads the <em>latest</em>{' '}
        <code>draw_fn</code> from the node&apos;s meta — so a fresh closure each
        render never re-subscribes. The node is repainted when the callback&apos;s{' '}
        <strong>identity changes</strong> between renders, or when{' '}
        <code>redraw_key</code> changes. A fresh inline lambda is a new callable
        every render, so by default the canvas redraws whenever its owner
        re-renders — the same reactive model as any other prop.
      </Typography>
      <Alert severity="info" sx={{ mb: 2 }}>
        Treat the node as <strong>read-only</strong> inside{' '}
        <code>draw_fn</code>. It runs during Godot&apos;s paint phase, not during
        your render, so do not set state, change styles, or add children from
        inside it — read the node&apos;s <code>size</code> and draw.
      </Alert>
    </Box>

    {/* ── Vector drawing ───────────────────────────────────────── */}
    <Box sx={styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        Vector drawing
      </Typography>
      <Typography variant="body1" paragraph>
        Inside <code>draw_fn</code> you have the full Godot canvas drawing API on
        the node: <code>draw_line</code>, <code>draw_polyline</code>,{' '}
        <code>draw_rect</code>, <code>draw_circle</code>,{' '}
        <code>draw_colored_polygon</code>, <code>draw_texture</code>,{' '}
        <code>draw_string</code>, and so on. Drive them from component state and
        the drawing updates reactively.
      </Typography>
      <CodeBlock language="gdscript" code={CUSTOM_RENDERING_PAINTER_EXAMPLE} />
    </Box>

    {/* ── Helper file best practice ────────────────────────────── */}
    <Box sx={styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        Keep draw bodies in a helper file
      </Typography>
      <Typography variant="body1" paragraph>
        The example above calls <code>DrawHelpers.polygon</code> rather than
        inlining a multi-statement lambda. Keeping draw bodies as exported utils
        in a sibling <code>.guitkx</code> helper file (imported with{' '}
        <code>import * as DrawHelpers from &quot;./draw_helpers&quot;</code>, or a
        plain <code>.gd</code>) is the recommended pattern: the markup stays a
        simple single-expression lambda, the draw code gets full editor tooling,
        and the <code>.guitkx</code> file formats cleanly. Each function just
        needs to match <code>func(canvas: CanvasItem)</code> (plus any extra
        arguments you close over).
      </Typography>
      <CodeBlock language="gdscript" code={CUSTOM_RENDERING_HELPERS_EXAMPLE} />
    </Box>

    {/* ── State-driven drawing ─────────────────────────────────── */}
    <Box sx={styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        State-driven drawing
      </Typography>
      <Typography variant="body1" paragraph>
        Because a fresh inline <code>draw_fn</code> is a new callable each render,
        anything the closure captures from state is reflected the next time the
        owner re-renders — no manual invalidation needed.
      </Typography>
      <CodeBlock language="gdscript" code={CUSTOM_RENDERING_RAW_MESH_EXAMPLE} />
    </Box>

    {/* ── redraw_key + stable callbacks ────────────────────────── */}
    <Box sx={styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        Controlling repaints with redraw_key
      </Typography>
      <Typography variant="body1" paragraph>
        When drawing is expensive, stabilise the callback so it is <strong>not</strong>{' '}
        reallocated each render — use <code>useStableCallback</code> (0-arg) or{' '}
        <code>useStableAction</code> (1-arg), which keep a stable identity while
        always invoking the latest closure body. With a stable reference the node
        no longer repaints on every render; instead, bump <code>redraw_key</code>{' '}
        exactly when you want a fresh frame.
      </Typography>
      <CodeBlock language="gdscript" code={CUSTOM_RENDERING_REDRAW_KEY_EXAMPLE} />
      <Alert severity="info" sx={{ mb: 2 }}>
        For a continuous animation that repaints without re-rendering, capture
        the node with a <code>ref</code> and call{' '}
        <code>queue_redraw()</code> on it from a ticker (or drive a property with{' '}
        <code>useTween</code>). <code>redraw_key</code> is for discrete,
        on-demand repaints.
      </Alert>
    </Box>

    {/* ── Runtime / export builds ──────────────────────────────── */}
    <Box sx={styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        Runtime and exported games
      </Typography>
      <Typography variant="body1" paragraph>
        The canvas drawing API lives on <code>CanvasItem</code>, a core engine
        type — nothing here is editor-only. <code>draw_fn</code> and{' '}
        <code>redraw_key</code> behave identically in the editor and in an
        exported game, with no gating.
      </Typography>
      <Alert severity="info" sx={{ mb: 2 }}>
        When the <code>draw_fn</code> prop is removed (or set to an invalid
        callable), the host disconnects the trampoline, clears the draw meta, and
        queues one final repaint to erase what was drawn — so toggling custom
        drawing off leaves the node clean.
      </Alert>
    </Box>
  </Box>
)
