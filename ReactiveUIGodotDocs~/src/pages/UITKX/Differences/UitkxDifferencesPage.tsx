import type { FC } from 'react'
import { Box, List, ListItem, ListItemText, Typography } from '@mui/material'
import { CodeBlock } from '../../../components/CodeBlock/CodeBlock'
import Styles from '../../Differences/DifferencesPage.style'
import { UITKX_STATE_COUNTER_EXAMPLE } from './UitkxDifferencesPage.example'

export const UitkxDifferencesPage: FC = () => (
  <Box sx={Styles.root}>
    <Typography variant="h4" component="h1" gutterBottom>
      Different from React
    </Typography>
    <Typography variant="body1" paragraph>
      Reactive UI Toolkit borrows React's component-and-hooks mental model, but it runs on Godot with a plain
      GDScript runtime. This section covers the places where your mental model should be adjusted
      rather than re-explaining core concepts. It also notes where it differs from the C# / Unity
      sibling, ReactiveUIToolKit.
    </Typography>

    <Box sx={Styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        Hooks are compiler-resolved, not imported
      </Typography>
      <Typography variant="body1" paragraph>
        Hook names are camelCase and match React's exactly — <code>useState</code>,{' '}
        <code>useEffect</code>, <code>useMemo</code>, <code>useRef</code>, and so on (a
        deliberate breaking change in library 0.4.0 for full naming parity with React). What
        differs is the mechanism, not the spelling: hooks are static methods on the{' '}
        <code>Hooks</code> class, not importable functions, and the bare camelCase form only
        exists inside <code>.guitkx</code> markup — the compiler recognizes a call like{' '}
        <code>useState(…)</code> and rewrites it to <code>Hooks.useState(…)</code>. In plain{' '}
        <code>.gd</code> scripts (or anywhere outside <code>.guitkx</code>), call the fully
        qualified form directly: <code>Hooks.useState(…)</code>.
      </Typography>
    </Box>

    <Box sx={Styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        State updates
      </Typography>
      <Typography variant="body1" paragraph>
        <code>useState</code> keeps React's mental model but returns a two-element{' '}
        <code>Array</code> — <code>[value, setter]</code> — because GDScript has no tuple
        destructuring. You call the setter with either a value or an updater function.
      </Typography>
      <List sx={Styles.list}>
        <ListItem disablePadding>
          <ListItemText primary={<>Read state with <code>s[0]</code> and get the setter with <code>s[1]</code> (commonly aliased: <code>var count = s[0]</code>, <code>var set_count = s[1]</code>).</>} />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary={<>The setter is a <code>Callable</code>. Invoke it with <code>.call(…)</code>: <code>set_count.call(next)</code> or <code>{'set_count.call(func(prev): return prev + 1)'}</code>.</>} />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary={<>Bind a setter directly to <code>onChange</code> by wrapping it: <code>{'onChange={ func(v): set_count.call(v) }'}</code>.</>} />
        </ListItem>
      </List>
      <CodeBlock language="jsx" code={UITKX_STATE_COUNTER_EXAMPLE} />
    </Box>

    <Box sx={Styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        Refs are dictionaries
      </Typography>
      <Typography variant="body1" paragraph>
        <code>useRef(initial)</code> returns a stable <code>{'{ "current": initial }'}</code>{' '}
        dictionary (never re-created). Read and write it with{' '}
        <code>{'my_ref["current"]'}</code>. The <code>ref</code> attribute on a host element accepts
        either such a box or a <code>Callable(node)</code> that receives the live Godot node.
      </Typography>
    </Box>

    <Box sx={Styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        Host set is Godot Controls
      </Typography>
      <Typography variant="body1" paragraph>
        Host elements are Godot <code>Control</code> nodes, not DOM tags or Unity{' '}
        <code>VisualElement</code>s — and the tags are the official Godot class names
        (<code>{'<VBoxContainer>'}</code>/<code>{'<HBoxContainer>'}</code>/
        <code>{'<GridContainer>'}</code>/…). Layout is <strong>container-driven</strong> rather than
        CSS flexbox; there is no USS/UXML. Styling is a <code>style</code> dictionary of{' '}
        <code>Control</code> properties and <code>Theme</code> overrides, and events are Godot signals
        surfaced through <code>on</code> + PascalCase(signal) handlers.
      </Typography>
    </Box>

    <Box sx={Styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        Prop spread and context handles work like React
      </Typography>
      <Typography variant="body1" paragraph>
        Two React ergonomics carry over directly, so you do not need to reach for a Godot-specific
        workaround:
      </Typography>
      <List sx={Styles.list}>
        <ListItem disablePadding>
          <ListItemText primary={<><strong>Prop spread</strong> is supported in <code>.guitkx</code>: <code>{'<Button {...cfg} onPressed={ f } />'}</code> merges a <code>Dictionary</code> of props onto a host element or component, left-to-right with later winning — just like <code>{'{...obj}'}</code> in JSX.</>} />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary={<><strong>Context handles</strong> are supported: <code>Hooks.createContext(default)</code> returns an <code>RUIContext</code> you pass to <code>provideContext</code> / <code>useContext</code> — the parity of React&apos;s <code>createContext</code>, with a built-in default and no string-key collisions. (Bare String keys still work for back-compat.)</>} />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary={<><strong>Event handlers</strong> are named after the Godot signal itself — <code>on</code> + PascalCase(signal name): <code>onPressed</code>, <code>onTextChanged</code>, <code>onValueChanged</code>, <code>onFocusEntered</code>, and so on, for every signal of every node. There are no React alias names (<code>onClick</code>/<code>onChange</code> were removed in 0.9.0 — see <code>MIGRATION-0.9.md</code>); the native <code>on_&lt;signal&gt;</code> spelling remains as a verbatim escape hatch.</>} />
        </ListItem>
      </List>
      <Typography variant="body1" paragraph sx={{ mt: 1 }}>
        Two things stay different because of GDScript itself, not because they are missing features:
      </Typography>
      <List sx={Styles.list}>
        <ListItem disablePadding>
          <ListItemText primary={<>A <code>ref</code> is read and written as <code>{'ref["current"]'}</code>, not <code>ref.current</code> — GDScript <code>Dictionary</code> access has no dot syntax.</>} />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary={<><code>children</code> is a separate render parameter (<code>static func render(props, children)</code>), not <code>props.children</code> — GDScript has no variadic JSX-child sugar.</>} />
        </ListItem>
      </List>
    </Box>

    <Box sx={Styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        Rendering model
      </Typography>
      <Typography variant="body1" paragraph>
        The fiber reconciler runs synchronously and coalesces all updates scheduled in a frame into
        one re-render. There is no React 18-style concurrent rendering.
      </Typography>
      <List sx={Styles.list}>
        <ListItem disablePadding>
          <ListItemText primary="All updates scheduled in a frame are processed together; there is no preemption between high- and low-priority updates." />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary="useTransition and useDeferredValue exist for API parity but are synchronous — they don't provide true concurrency." />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary="Optional cooperative render slicing can be enabled via RUIConfig.time_slicing / RUIConfig.frame_budget_ms, within Godot's runtime constraints." />
        </ListItem>
      </List>
    </Box>

    <Box sx={Styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        Differences from the Unity library
      </Typography>
      <List sx={Styles.list}>
        <ListItem disablePadding>
          <ListItemText primary={<>Hooks are <code>camelCase</code> (matching JS/React) rather than the C# sibling's <code>PascalCase</code> methods, and are returned as arrays/dictionaries, not typed <code>StateSetter&lt;T&gt;</code> delegates.</>} />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary={<>The function-component factory is <code>V.fc</code> (GDScript reserves <code>func</code>), not <code>V.Func</code>.</>} />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary={<>Host elements are Godot <code>Control</code>s (<code>VBoxContainer</code>, <code>LineEdit</code>, <code>PanelContainer</code>, …) rather than UI Toolkit <code>VisualElement</code>s.</>} />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary={<>Styling is a <code>Dictionary</code> of Godot properties + <code>Theme</code> channels, not USS/typed <code>Style</code> objects.</>} />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary={<>Compilation produces a sibling <code>.gd</code> via the editor plugin, not a Roslyn <code>*.g.cs</code> source-generated class.</>} />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary={<>Error boundaries are structural: GDScript has no <code>try</code>/<code>catch</code>, so a boundary shows its fallback on an imperative toggle rather than auto-catching a child render crash.</>} />
        </ListItem>
      </List>
    </Box>
  </Box>
)
