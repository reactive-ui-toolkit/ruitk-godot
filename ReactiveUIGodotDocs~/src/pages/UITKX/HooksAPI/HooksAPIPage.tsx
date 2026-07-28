import type { FC } from 'react'
import {
  Box,
  Chip,
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

const styles = {
  root: { display: 'flex', flexDirection: 'column', gap: 2 },
  section: { mt: 2 },
} as const

type HookSig = {
  name: string
  signature: string
  returns: string
  category: string
  note?: string
}

const hooks: HookSig[] = [
  // State
  {
    name: 'useState',
    signature: '(initial = null)',
    returns: '[value, set]',
    category: 'State',
    note: 'set accepts a value or func(old) -> new',
  },
  {
    name: 'useReducer',
    signature: '(reducer: Callable, initial = null)',
    returns: '[state, dispatch]',
    category: 'State',
    note: 'reducer(state, action) -> new_state',
  },
  // Effects
  {
    name: 'useEffect',
    signature: '(effect: Callable, deps = null)',
    returns: 'void',
    category: 'Effects',
    note: 'Passive — runs after commit',
  },
  {
    name: 'useLayoutEffect',
    signature: '(effect: Callable, deps = null)',
    returns: 'void',
    category: 'Effects',
    note: 'Synchronous — runs before paint',
  },
  // Memoization
  {
    name: 'useMemo',
    signature: '(factory: Callable, deps: Array = [])',
    returns: 'value',
    category: 'Memoization',
  },
  {
    name: 'useCallback',
    signature: '(cb: Callable, deps: Array = [])',
    returns: 'Callable',
    category: 'Memoization',
    note: 'useMemo(func(): return cb, deps)',
  },
  {
    name: 'useDeferredValue',
    signature: '(value, deps = null)',
    returns: 'deferred_value',
    category: 'Memoization',
    note: 'Lags one frame at low priority',
  },
  // Refs
  {
    name: 'useRef',
    signature: '(initial = null)',
    returns: '{ "current": initial }',
    category: 'Refs',
    note: 'Stable box; wire to the ref prop for a Control',
  },
  {
    name: 'useImperativeHandle',
    signature: '(factory: Callable, deps: Array = [])',
    returns: 'handle',
    category: 'Refs',
    note: 'Alias of useMemo(factory, deps)',
  },
  // Context
  {
    name: 'Hooks.createContext',
    signature: '(default_value = null, name = "")',
    returns: 'RUIContext',
    category: 'Context',
    note: 'Handle for provide/useContext (React createContext)',
  },
  {
    name: 'useContext',
    signature: '(handle_or_key)',
    returns: 'value | default | null',
    category: 'Context',
    note: 'Handle or String; handle returns its default when unprovided; no hook slot',
  },
  {
    name: 'Hooks.provideContext',
    signature: '(handle_or_key, value)',
    returns: 'void',
    category: 'Context',
    note: 'Handle (recommended) or String; exposes value to this fiber’s subtree',
  },
  // Stable functions
  {
    name: 'useStableCallback',
    signature: '(cb: Callable)',
    returns: 'Callable',
    category: 'Stable functions',
    note: '0-arg; identity never changes',
  },
  {
    name: 'useStableFunc',
    signature: '(cb: Callable)',
    returns: 'Callable',
    category: 'Stable functions',
    note: 'Alias of useStableCallback',
  },
  {
    name: 'useStableAction',
    signature: '(cb: Callable)',
    returns: 'Callable',
    category: 'Stable functions',
    note: '1-arg; identity never changes',
  },
  // Concurrency
  {
    name: 'useTransition',
    signature: '()',
    returns: '[is_pending, start_transition]',
    category: 'Concurrency',
    note: 'Synchronous renderer: is_pending is always false',
  },
  // Signals
  {
    name: 'useSignal',
    signature: '(sig: RUISignal, selector = null, comparer = null)',
    returns: 'value | slice',
    category: 'Signals',
    note: 'Subscribe + re-render; optional selector/comparer',
  },
  {
    name: 'useSignalKey',
    signature: '(key: String, initial = null, selector = null, comparer = null)',
    returns: 'value | slice',
    category: 'Signals',
    note: 'Process-wide keyed signal (RUISignals registry)',
  },
  // Animation / Media
  {
    name: 'useTween',
    signature: '(ref: Dictionary, property: String, to, duration: float, deps: Array = [])',
    returns: 'void',
    category: 'Animation & Media',
    note: 'Tweens a mounted node property via Godot Tween',
  },
  {
    name: 'useTweenValue',
    signature: '(from, to, duration: float, on_update: Callable, deps: Array = [])',
    returns: 'void',
    category: 'Animation & Media',
    note: 'Drives on_update(value); animate without re-render',
  },
  {
    name: 'useAnimate',
    signature: '(ref: Dictionary, tracks: Array, autoplay := true, deps: Array = [])',
    returns: 'void',
    category: 'Animation & Media',
    note: 'Plays property tracks on a node via a Tween',
  },
  {
    name: 'useSfx',
    signature: '(bus := "Master")',
    returns: 'Callable',
    category: 'Animation & Media',
    note: 'Returns func(stream, volume_db, pitch_scale) one-shot player',
  },
  // Platform
  {
    name: 'useSafeArea',
    signature: '()',
    returns: '{ left, top, right, bottom }',
    category: 'Platform',
    note: 'Device safe-area insets (pixels)',
  },
]

const categories = [...new Set(hooks.map((h) => h.category))]

const categoryColors: Record<string, 'primary' | 'secondary' | 'success' | 'warning' | 'info' | 'error'> = {
  State: 'primary',
  Effects: 'secondary',
  Memoization: 'success',
  Refs: 'info',
  Context: 'warning',
  'Stable functions': 'error',
  Concurrency: 'success',
  Signals: 'primary',
  'Animation & Media': 'secondary',
  Platform: 'info',
}

export const HooksAPIPage: FC = () => (
  <Box sx={styles.root}>
    <Typography variant="h4" component="h1" gutterBottom>
      Hooks API Reference
    </Typography>
    <Typography variant="body1" paragraph>
      Complete reference of every hook exposed by the <code>Hooks</code> class
      (<code>addons/reactive_ui_toolkit/core/hooks.gd</code>). In <code>.guitkx</code>{' '}
      markup, bare camelCase calls like <code>useState</code> are auto-prefixed
      to <code>Hooks.useState</code>; in plain GDScript they are static
      methods, e.g. <code>Hooks.useState(0)</code>. Hooks return plain GDScript
      values — Arrays, Dictionaries, and <code>Callable</code>s — not custom
      types.
    </Typography>

    {categories.map((cat) => (
      <Box key={cat} sx={styles.section}>
        <Typography variant="h5" component="h2" gutterBottom>
          {cat}
        </Typography>
        <TableContainer component={Paper} variant="outlined">
          <Table size="small">
            <TableHead>
              <TableRow>
                <TableCell><strong>Hook</strong></TableCell>
                <TableCell><strong>Parameters</strong></TableCell>
                <TableCell><strong>Returns</strong></TableCell>
                <TableCell><strong>Notes</strong></TableCell>
              </TableRow>
            </TableHead>
            <TableBody>
              {hooks
                .filter((h) => h.category === cat)
                .map((h, i) => (
                  <TableRow key={`${h.name}-${i}`}>
                    <TableCell>
                      <code>{h.name}</code>
                    </TableCell>
                    <TableCell><code>{h.signature}</code></TableCell>
                    <TableCell><code>{h.returns}</code></TableCell>
                    <TableCell>
                      {h.note && (
                        <Chip
                          label={h.note}
                          size="small"
                          color={categoryColors[cat] ?? 'default'}
                          variant="outlined"
                        />
                      )}
                    </TableCell>
                  </TableRow>
                ))}
            </TableBody>
          </Table>
        </TableContainer>
      </Box>
    ))}

    {/* ── Return shapes ────────────────────────────────────────── */}
    <Box sx={styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        Return shapes
      </Typography>

      <Typography variant="h6" gutterBottom>
        useState / useReducer
      </Typography>
      <CodeBlock
        language="jsx"
        code={`# useState -> [value, set]
var count = useState(0)
count[0]                      # current value
count[1].call(5)             # set to a value
count[1].call(func(c): return c + 1)   # functional updater (reads latest)

# useReducer -> [state, dispatch]
var r = useReducer(reducer, 0)
r[0]                          # current state
r[1].call("inc")             # dispatch an action`}
      />

      <Typography variant="h6" gutterBottom sx={{ mt: 2 }}>
        useRef box
      </Typography>
      <CodeBlock
        language="jsx"
        code={`# A stable Dictionary box; mutating .current never re-renders.
var box = useRef(0)
box["current"] += 1

# Wire the same box to a host element's ref prop to capture its Control.
var node_ref = useRef(null)   # after commit: node_ref["current"] is the Control`}
      />

      <Typography variant="h6" gutterBottom sx={{ mt: 2 }}>
        useSafeArea insets
      </Typography>
      <CodeBlock
        language="jsx"
        code={`# Dictionary of pixel insets from DisplayServer.get_display_safe_area().
{ "left": int, "top": int, "right": int, "bottom": int }`}
      />
    </Box>

    {/* ── Configuration ────────────────────────────────────────── */}
    <Box sx={styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        Configuration
      </Typography>
      <Typography variant="body1" paragraph>
        Runtime validation is controlled by static flags on <code>RUIConfig</code>{' '}
        (both default to <code>OS.is_debug_build()</code>):
      </Typography>
      <CodeBlock
        language="jsx"
        code={`static var RUIConfig.enable_hook_validation     # hook-order mismatch detection
static var RUIConfig.enable_strict_diagnostics  # state-update-during-render warning`}
      />
    </Box>
  </Box>
)
