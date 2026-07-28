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
  KEY_BASIC_EXAMPLE,
  KEY_INDEX_ANTIPATTERN,
  KEY_REORDER_EXAMPLE,
  KEY_RESET_EXAMPLE,
} from './RefAndKeyGuide.example'

const styles = {
  root: { display: 'flex', flexDirection: 'column', gap: 2 },
  section: { mt: 2 },
  list: { pl: 2 },
} as const

export const KeyGuidePage: FC = () => (
  <Box sx={styles.root}>
    <Typography variant="h4" component="h1" gutterBottom>
      Keys Guide
    </Typography>
    <Typography variant="body1" paragraph>
      Keys help the reconciler identify which elements changed, moved, or were
      removed in a list. They are critical for performance and correctness when
      rendering dynamic collections.
    </Typography>

    {/* ── Why keys matter ──────────────────────────────────────── */}
    <Box sx={styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        Why keys matter
      </Typography>
      <List sx={styles.list}>
        <ListItem disablePadding>
          <ListItemText primary="Without keys, the reconciler matches children by index — reordering destroys and recreates the Godot Control nodes." />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary="With keys, the reconciler matches by identity — nodes move in the scene tree instead of being recreated." />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary="Stable keys preserve component state (hooks, refs) across re-renders." />
        </ListItem>
      </List>
    </Box>

    {/* ── Basic usage ──────────────────────────────────────────── */}
    <Box sx={styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        Basic usage
      </Typography>
      <CodeBlock language="jsx" code={KEY_BASIC_EXAMPLE} />
    </Box>

    {/* ── Choosing good keys ───────────────────────────────────── */}
    <Box sx={styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        Choosing good keys
      </Typography>
      <List sx={styles.list}>
        <ListItem disablePadding>
          <ListItemText primary="Use a stable, unique ID from your data (database ID, UUID, unique name)." />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary={<>Avoid using the loop index as key — it breaks when items are inserted, removed, or reordered.</>} />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary={<>Prefer string keys. Call <code>str(...)</code> on numeric IDs.</>} />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary="Keys only need to be unique among siblings, not globally." />
        </ListItem>
      </List>
      <CodeBlock language="jsx" code={KEY_INDEX_ANTIPATTERN} />
    </Box>

    {/* ── Reordering ───────────────────────────────────────────── */}
    <Box sx={styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        Reordering lists
      </Typography>
      <Typography variant="body1" paragraph>
        When items are reordered, stable keys let the reconciler move existing{' '}
        <code>Control</code> nodes instead of destroying and recreating them.
        This preserves per-node state and is significantly faster for large
        lists.
      </Typography>
      <CodeBlock language="jsx" code={KEY_REORDER_EXAMPLE} />
    </Box>

    {/* ── Key as reset mechanism ───────────────────────────────── */}
    <Box sx={styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        Using key to reset state
      </Typography>
      <Typography variant="body1" paragraph>
        Changing a component&apos;s <code>key</code> forces a full unmount and
        remount — all hooks reset to their initial values. This is useful when
        you want a clean slate (e.g., switching between different user
        profiles).
      </Typography>
      <CodeBlock language="jsx" code={KEY_RESET_EXAMPLE} />
    </Box>

    <Alert severity="info" sx={{ mt: 2 }}>
      You only need keys inside <code>@for</code> or any code that produces a
      dynamic list of siblings. Static markup doesn&apos;t need keys.
    </Alert>
  </Box>
)
