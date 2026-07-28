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
  CONTEXT_BASIC_EXAMPLE,
  CONTEXT_DYNAMIC_EXAMPLE,
  CONTEXT_HANDLE_API,
  CONTEXT_HANDLE_EXAMPLE,
  CONTEXT_HANDLE_MODULE_EXAMPLE,
  CONTEXT_SHADOWING_EXAMPLE,
  CONTEXT_TYPED_EXAMPLE,
  CONTEXT_VS_SIGNALS,
} from './ContextPage.example'

const styles = {
  root: { display: 'flex', flexDirection: 'column', gap: 2 },
  section: { mt: 2 },
  list: { pl: 2 },
} as const

export const ContextPage: FC = () => (
  <Box sx={styles.root}>
    <Typography variant="h4" component="h1" gutterBottom>
      Context API
    </Typography>
    <Typography variant="body1" paragraph>
      Context lets parent components provide data to any descendant without
      passing it through every intermediate component as props. It is the
      primary mechanism for dependency injection in the reactive tree.
    </Typography>

    {/* ── API ──────────────────────────────────────────────────── */}
    <Box sx={styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        API
      </Typography>
      <Typography variant="body1" paragraph>
        Both <code>provideContext</code> and <code>useContext</code> accept either a{' '}
        <strong>context handle</strong> (from <code>Hooks.createContext(...)</code> — the
        recommended, collision-free form) or a bare <code>String</code> key (back-compat).
      </Typography>
      <CodeBlock language="jsx" code={CONTEXT_HANDLE_API} />
      <List sx={styles.list}>
        <ListItem disablePadding>
          <ListItemText primary={<>A <strong>handle</strong> from <code>createContext</code> is keyed by <strong>object identity</strong>, so distinct handles never collide — even if two unrelated features both think of their value as &quot;theme&quot;.</>} />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary={<><code>provideContext</code> attaches the value to the current component&apos;s fiber node, exposing it to that fiber&apos;s whole subtree.</>} />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary={<><code>useContext</code> walks up the fiber tree to find the nearest provider for that key. It does <strong>not</strong> consume a hook slot.</>} />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary={<>With a handle, <code>useContext</code> returns the handle&apos;s <code>default</code> when no ancestor provides it; with a bare <code>String</code> key it returns <code>null</code>.</>} />
        </ListItem>
      </List>
    </Box>

    {/* ── Context handles (createContext) ─────────────────────── */}
    <Box sx={styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        Context handles (<code>createContext</code>) — recommended
      </Typography>
      <Typography variant="body1" paragraph>
        <code>Hooks.createContext(default_value = null, name = "")</code> returns a{' '}
        <code>RuitkContext</code> handle — the Godot parity of React&apos;s{' '}
        <code>createContext</code>. Declare the handle <strong>once</strong> (as a top-level value
        declaration, or a static in a shared script) and share the <em>same object</em> between the
        provider and every consumer. Because the
        handle&apos;s identity is the map key, it can never collide with an unrelated feature keyed on
        the same word.
      </Typography>
      <List sx={styles.list}>
        <ListItem disablePadding>
          <ListItemText primary={<><strong>No string-key collisions.</strong> Two independent handles are distinct even if both are conceptually a &quot;theme&quot; — object identity, not the string, is what matches.</>} />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary={<><strong>Built-in default.</strong> <code>useContext(handle)</code> returns the handle&apos;s <code>default_value</code> when no provider exists above it, so consumers never have to null-check.</>} />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary={<><strong>Same everywhere.</strong> Provider shadowing, dynamic re-render on value change, and portals all behave identically whether you key on a handle or a String.</>} />
        </ListItem>
      </List>
      <CodeBlock language="jsx" code={CONTEXT_HANDLE_EXAMPLE} />
      <Typography variant="body1" paragraph sx={{ mt: 2 }}>
        When a handle belongs to one component, the tidiest form is a top-level value declaration
        in the same file as the component, with an inline default. The default fills in for
        consumers that render without a provider above them:
      </Typography>
      <CodeBlock language="jsx" code={CONTEXT_HANDLE_MODULE_EXAMPLE} />
      <Alert severity="info" sx={{ mt: 2 }}>
        Bare <code>String</code> keys still work everywhere and remain fully supported for back-compat.
        Handles are simply the recommended form for anything shared across unrelated features.
      </Alert>
    </Box>

    {/* ── Basic example ────────────────────────────────────────── */}
    <Box sx={styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        Basic provider / consumer
      </Typography>
      <CodeBlock language="jsx" code={CONTEXT_BASIC_EXAMPLE} />
    </Box>

    {/* ── Provider shadowing ───────────────────────────────────── */}
    <Box sx={styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        Provider shadowing
      </Typography>
      <Typography variant="body1" paragraph>
        A nested provider for the same key <strong>shadows</strong> the outer
        provider. Each subtree sees its nearest ancestor&apos;s value.
      </Typography>
      <CodeBlock language="jsx" code={CONTEXT_SHADOWING_EXAMPLE} />
    </Box>

    {/* ── Dynamic context + re-renders ─────────────────────────── */}
    <Box sx={styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        Dynamic context values
      </Typography>
      <Typography variant="body1" paragraph>
        When the provided value changes (detected with <code>==</code> value
        equality), all consumers in the subtree are marked dirty and
        automatically schedule a re-render — even through intermediate
        components that would otherwise bail out.
      </Typography>
      <CodeBlock language="jsx" code={CONTEXT_DYNAMIC_EXAMPLE} />
    </Box>

    {/* ── Type-safe keys ───────────────────────────────────────── */}
    <Box sx={styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        Type-safe context keys (string form)
      </Typography>
      <Typography variant="body1" paragraph>
        If you use the back-compat <strong>String</strong> form instead of a handle, define your
        keys as <code>const</code> string values in a small companion <code>.gd</code> script. This
        prevents typos and makes keys discoverable via autocomplete — but note that a{' '}
        <code>createContext</code> handle avoids key collisions entirely and gives you a default
        value for free.
      </Typography>
      <CodeBlock language="jsx" code={CONTEXT_TYPED_EXAMPLE} />
    </Box>

    {/* ── Context vs Signals ───────────────────────────────────── */}
    <Box sx={styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        Context vs Signals
      </Typography>
      <Typography variant="body1" paragraph>
        Both mechanisms share state across components, but they differ in scope
        and lifetime:
      </Typography>
      <CodeBlock language="jsx" code={CONTEXT_VS_SIGNALS} />
    </Box>

    {/* ── Sharing overlay roots ────────────────────────────────── */}
    <Box sx={styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        Sharing overlay roots via context
      </Typography>
      <Typography variant="body1" paragraph>
        A common use of context is to publish a shared target <code>Node</code>{' '}
        (a modal / tooltip / overlay root) that deep descendants portal into.
        The Godot port has no predefined keys — <code>V.portal(target, …)</code>{' '}
        takes the target <code>Control</code> directly — so define your own
        string keys and provide the node captured from a{' '}
        <code>useRef</code> (wired with the <code>ref</code> prop):
      </Typography>
      <CodeBlock language="jsx" code={`# A layout component publishes its overlay root for descendants to portal into.
AppLayout() -> RuitkVNode {
  var overlay_root = useRef(null)
  Hooks.provideContext("overlay_root", overlay_root)   # provide the ref box

  return (
    <VBoxContainer>
      <PageContent />
      # Modals/tooltips get parented under this node via V.portal(...)
      <PanelContainer ref={ overlay_root }
                      style={ {"anchors_preset": Control.PRESET_FULL_RECT, "mouse_filter": "MOUSE_FILTER_IGNORE"} } />
    </VBoxContainer>
  )
}

# A deep descendant reads the ref and portals into it (V.portal has no markup
# tag yet, so it rides an embedded { expr } in the markup return).
Tooltip() -> RuitkVNode {
  var overlay_root = useContext("overlay_root")
  if overlay_root == null or overlay_root["current"] == null:
    return null
  return (
    { V.portal(overlay_root["current"], [
        V.Label({ "text": "I render into the shared overlay root" }),
      ]) }
  )
}`} />
    </Box>

    <Alert severity="info" sx={{ mt: 2 }}>
      <code>useContext</code> does not consume a hook slot — it can technically
      be called conditionally. However, for consistency and readability, keep it
      in the setup code section alongside other hooks.
    </Alert>
  </Box>
)
