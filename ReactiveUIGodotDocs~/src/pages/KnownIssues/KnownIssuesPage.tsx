import type { FC } from 'react'
import { Alert, Box, List, ListItem, ListItemText, Typography } from '@mui/material'
import { CodeBlock } from '../../components/CodeBlock/CodeBlock'
import Styles from './KnownIssuesPage.style'

export const KnownIssuesPage: FC = () => (
  <Box sx={Styles.root}>
    <Typography variant="h4" component="h1" gutterBottom>
      Known Issues
    </Typography>

    {/* ── Hook rules ──────────────────────────────────────────────────────── */}
    <Typography variant="h5" component="h2" sx={Styles.section}>
      Hook Rules
    </Typography>
    <List>
      <ListItem disablePadding>
        <ListItemText primary="Hooks must be called unconditionally at the top of a component. Calling a hook inside @if, @for, @match, or an event handler breaks the call-order-to-slot mapping and causes state to desync. In debug builds RUIConfig.enable_hook_validation detects this and pushes a warning." />
      </ListItem>
      <ListItem disablePadding>
        <ListItemText primary="Hooks are not thread-safe. Call them only on the main thread during the render cycle. Signal values may be read and written from any thread, but useSignal() itself is a hook and follows the hook rules." />
      </ListItem>
    </List>

    {/* ── Render depth ────────────────────────────────────────────────────── */}
    <Typography variant="h5" component="h2" sx={Styles.section}>
      Render-Depth Guard
    </Typography>
    <Typography variant="body1" paragraph>
      The reconciler caps re-render restarts at <strong>25</strong> per commit. If a component
      updates its own state unconditionally during setup (an infinite render loop), the guard
      stops it and logs an error rather than hanging the editor. This is not configurable —
      restructure so state updates happen in event handlers or <code>useEffect</code>, not on
      every render.
    </Typography>

    {/* ── Styling caveats ─────────────────────────────────────────────────── */}
    <Typography variant="h5" component="h2" sx={Styles.section}>
      Styling Caveats
    </Typography>
    <List>
      <ListItem disablePadding>
        <ListItemText primary={<>The StyleBox keys (<code>bg_color</code>, <code>border_color</code>, <code>border_width</code>, <code>corner_radius</code>, <code>pad</code>) only take effect on a control with a primary stylebox slot — Panel, Button, LineEdit/TextEdit, ProgressBar. On a bare <code>Label</code> or a plain box container they warn once and do nothing. Wrap content in a <code>Panel</code> for a background.</>} />
      </ListItem>
      <ListItem disablePadding>
        <ListItemText primary={<>Per-state StyleBox slots vary by control. Button exposes <code>hover</code>/<code>pressed</code>/<code>disabled</code>/<code>focus</code>; LineEdit exposes <code>focus</code>/<code>read_only</code>. Requesting a slot a control lacks warns once and is ignored.</>} />
      </ListItem>
      <ListItem disablePadding>
        <ListItemText primary={<><code>RUIStyleSheet</code> (the <code>classes</code> prop) is an ordered dictionary merge, not a CSS engine — there is no selector matching, specificity, cascade, or inheritance. For real theming use a Godot <code>Theme</code>/<code>StyleBox</code> or <code>theme_type_variation</code>.</>} />
      </ListItem>
    </List>

    {/* ── Resource loading ────────────────────────────────────────────────── */}
    <Typography variant="h5" component="h2" sx={Styles.section}>
      Resource Loading
    </Typography>
    <List>
      <ListItem disablePadding>
        <ListItemText primary={<><code>preload()</code> requires a constant <code>res://</code> path — it resolves at compile time. For a path computed at runtime (a prop, a variable) use <code>load()</code>, which returns <code>null</code> on a missing file. Guard dynamic loads before use.</>} />
      </ListItem>
      <ListItem disablePadding>
        <ListItemText primary={<>The <code>&lt;AudioStreamPlayer&gt;</code> / <code>&lt;VideoStreamPlayer&gt;</code> elements wrap scene nodes and take no children — set <code>stream</code>, <code>autoplay</code>, etc. as props.</>} />
      </ListItem>
    </List>

    {/* ── Tooling ─────────────────────────────────────────────────────────── */}
    <Typography variant="h5" component="h2" sx={Styles.section}>
      Tooling
    </Typography>
    <Typography variant="body1" paragraph>
      Godot&apos;s script editor is an LSP <em>server</em>, not a client, and cannot be pointed at
      an external language server for a custom language. In-editor <code>.guitkx</code>{' '}
      intelligence therefore ships as the dedicated <strong>Reactive UI Toolkit — Godot Editor</strong> addon
      (<code>addons/reactive_ui_editor</code>): a main-screen editor with syntax highlighting,
      live cross-file compiler diagnostics, completion, hover, go-to-definition, find (plus
      project-wide Search in Files), and data-safety guards. What it does <em>not</em> cover yet
      is intelligence <em>inside</em> embedded GDScript (<code>&#123;expr&#125;</code>/setup
      code) — type-aware completion/hover/diagnostics there remain <strong>VS Code</strong> and{' '}
      <strong>Visual Studio</strong>-only until the native analyzer binding lands.
    </Typography>
    <Typography variant="body1" paragraph>
      The in-editor addon targets Godot <strong>4.4+</strong> (hover-symbol APIs), even though the
      runtime itself supports 4.2+.
    </Typography>

    {/* ── Compilation ─────────────────────────────────────────────────────── */}
    <Typography variant="h5" component="h2" sx={Styles.section}>
      Compilation
    </Typography>
    <Typography variant="body1" paragraph>
      A <code>.guitkx</code> file compiles to a sibling <code>.gd</code> on save. If a resource
      path is wrong, the failure surfaces on the generated <code>.gd</code>:
    </Typography>
    <CodeBlock
      language="gdscript"
      code={`# preload path errors surface at parse time on the generated .gd:
Parse Error: Failed to load resource "res://ui/missing.png"`}
    />
    <Typography variant="body1" paragraph>
      Make sure the <code>res://</code> path exists and Godot has imported the source file (a{' '}
      <code>.import</code> sidecar is generated automatically). If the generated <code>.gd</code>{' '}
      looks stale, re-save the <code>.guitkx</code> to re-trigger the compile.
    </Typography>

    <Alert severity="info" sx={{ mt: 2 }}>
      For deeper diagnostics, enable <code>RUIConfig.enable_strict_diagnostics</code> (on by
      default in debug builds) to catch state updates performed during render.
    </Alert>
  </Box>
)
