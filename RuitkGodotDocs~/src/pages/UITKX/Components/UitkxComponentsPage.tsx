import type { FC } from 'react'
import {
  Alert,
  Box,
  Chip,
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
import Styles from '../../Components/ComponentPage.style'

const COMPONENT_SAMPLE = `ButtonShowcase() -> RuitkVNode {
  var s = useState(true)
  return (
    <VBoxContainer style={ {"separation": 8} }>
      <Label text={ "Enabled: %s" % s[0] } />
      <Button
        text={ "Disable" if s[0] else "Enable" }
        onPressed={ func(): s[1].call(func(prev): return not prev) }
      />
      <Button
        text="Secondary action"
        disabled={ not s[0] }
        onPressed={ func(): print("Clicked") }
      />
    </VBoxContainer>
  )
}`

// V.*-only primitives (no markup tag) are reached via an embedded { expr } inside an
// otherwise-normal .guitkx component — never as a fictitious <Tag>.
const FRAMEWORK_EXAMPLE = `App() -> RuitkVNode {
  var ready = useState(false)
  return (
    <VBoxContainer>
      { V.suspense(
          { "fallback": V.fc(Spinner.render), "is_ready": useCallback(func(): return ready[0], [ready[0]]) },
          [ V.fc(Content.render) ]) }
    </VBoxContainer>
  )
}`

/* ------------------------------------------------------------------ */
/*  Component catalog                                                  */
/* ------------------------------------------------------------------ */

// `hasTag` defaults to true (a real `<Name>` markup element backed by host_tags in
// vocabulary.json). Set it to `false` for a structural primitive that has NO markup tag yet —
// it can only be reached via its `V.*` factory in an embedded `{ expr }` inside a .guitkx
// component's markup, never written as `<Name>` (the factory name is shown in its place).
type CompEntry = { name: string; desc: string; hasTag?: false; factory?: string }

const containers: CompEntry[] = [
  { name: 'Control', desc: 'Universal base container — the div of Godot UI' },
  { name: 'VBoxContainer', desc: 'Vertical box container' },
  { name: 'HBoxContainer', desc: 'Horizontal box container' },
  { name: 'BoxContainer', desc: 'Box container with a vertical flag (new in 0.9.0)' },
  { name: 'GridContainer', desc: 'Grid layout container' },
  { name: 'MarginContainer', desc: 'Adds padding around children' },
  { name: 'PanelContainer', desc: 'Container with a themed panel background' },
  { name: 'CenterContainer', desc: 'Centers its child' },
  { name: 'ScrollContainer', desc: 'Scrollable container' },
  { name: 'FlowContainer', desc: 'Wrapping flow layout — also HFlowContainer / VFlowContainer (new in 0.9.0)' },
  { name: 'TabContainer', desc: 'Tabbed container' },
  { name: 'SplitContainer', desc: 'Draggable split — also HSplitContainer / VSplitContainer (new in 0.9.0)' },
  { name: 'AspectRatioContainer', desc: 'Keeps child at a fixed aspect ratio' },
  { name: 'FoldableContainer', desc: 'Collapsible container' },
  { name: 'SubViewportContainer', desc: 'Displays a SubViewport (new in 0.9.0)' },
]

const display: CompEntry[] = [
  { name: 'Label', desc: 'Single- or multi-line text' },
  { name: 'RichTextLabel', desc: 'BBCode-formatted text' },
  { name: 'Panel', desc: 'Plain themed rectangle — no layout (new in 0.9.0; the container is PanelContainer)' },
  { name: 'ColorRect', desc: 'Solid colour rectangle' },
  { name: 'TextureRect', desc: 'Displays a Texture2D' },
  { name: 'NinePatchRect', desc: 'Nine-patch texture' },
  { name: 'ReferenceRect', desc: 'Debug outline rectangle (new in 0.9.0)' },
  { name: 'ProgressBar', desc: 'Determinate progress indicator' },
]

const buttons: CompEntry[] = [
  { name: 'Button', desc: 'Standard clickable button' },
  { name: 'CheckBox', desc: 'Checkbox / boolean toggle' },
  { name: 'CheckButton', desc: 'Switch-style boolean toggle' },
  { name: 'OptionButton', desc: 'Dropdown / popup selector' },
  { name: 'MenuButton', desc: 'Button that opens a PopupMenu' },
  { name: 'LinkButton', desc: 'Text-link-style button' },
  { name: 'TextureButton', desc: 'Button drawn from textures' },
]

const textInputs: CompEntry[] = [
  { name: 'LineEdit', desc: 'Single-line text input' },
  { name: 'TextEdit', desc: 'Multi-line text input' },
  { name: 'CodeEdit', desc: 'Code editor input (syntax-aware)' },
  { name: 'SpinBox', desc: 'Numeric input with stepper' },
]

const pickers: CompEntry[] = [
  { name: 'HSlider', desc: 'Horizontal range slider' },
  { name: 'VSlider', desc: 'Vertical range slider' },
  { name: 'HScrollBar', desc: 'Horizontal scroll bar (new in 0.9.0)' },
  { name: 'VScrollBar', desc: 'Vertical scroll bar (new in 0.9.0)' },
  { name: 'ColorPicker', desc: 'Full colour picker' },
  { name: 'ColorPickerButton', desc: 'Button that opens a colour picker' },
  { name: 'VirtualJoystick', desc: 'On-screen touch joystick (new in 0.9.0)' },
]

const dataViews: CompEntry[] = [
  { name: 'ItemList', desc: 'Selectable list, reconciled by item identity' },
  { name: 'Tree', desc: 'Hierarchical tree (item-model control)' },
  { name: 'TabBar', desc: 'Standalone tab strip (item-model control)' },
  { name: 'MenuBar', desc: 'Application-style menu bar' },
]

const media: CompEntry[] = [
  { name: 'AudioStreamPlayer', desc: 'Plays an AudioStream' },
  { name: 'VideoStreamPlayer', desc: 'Plays a VideoStream' },
]

const framework: CompEntry[] = [
  { name: 'Fragment', desc: 'Invisible grouping wrapper (no host node) — <>…</> or <Fragment>' },
  { name: 'Portal', desc: 'Renders children under an external Node target', hasTag: false, factory: 'V.portal' },
  { name: 'Suspense', desc: 'Shows a fallback while async content loads', hasTag: false, factory: 'V.suspense' },
  { name: 'ErrorBoundary', desc: 'Shows a fallback when a child latches a failure (RuitkFail.render) or on an imperative toggle', hasTag: false, factory: 'V.error_boundary' },
  { name: 'Memo', desc: 'Memoized function component (skips unchanged renders)', hasTag: false, factory: 'V.memo' },
]

const router: CompEntry[] = [
  { name: 'Router', desc: 'Provides router context to its subtree', hasTag: false, factory: 'V.router' },
  { name: 'Routes', desc: 'Ranked first-match route switch', hasTag: false, factory: 'V.routes' },
  { name: 'Route', desc: 'A single route definition (path + element)', hasTag: false, factory: 'V.route' },
  { name: 'Outlet', desc: 'Renders the matched nested route', hasTag: false, factory: 'V.outlet' },
  { name: 'NavLink', desc: 'Active-aware navigation link', hasTag: false, factory: 'V.nav_link' },
  { name: 'Link', desc: 'Navigation button', hasTag: false, factory: 'V.link' },
]

type Category = { label: string; rows: CompEntry[]; note?: string; example?: string }

const allCategories: Category[] = [
  { label: 'Containers & Layout', rows: containers },
  { label: 'Display', rows: display },
  { label: 'Buttons & Toggles', rows: buttons },
  { label: 'Text Input', rows: textInputs },
  { label: 'Pickers & Sliders', rows: pickers },
  { label: 'Item-Model Controls', rows: dataViews },
  {
    label: 'Media',
    rows: media,
    note:
      'AudioStreamPlayer and VideoStreamPlayer wrap Godot scene nodes — ' +
      '<AudioStreamPlayer stream={ clip } autoplay /> works like any other element.',
  },
  {
    label: 'Framework Components',
    rows: framework,
    note:
      'Fragment is a real markup element (<>…</> or <Fragment>). Portal, Suspense, ErrorBoundary, ' +
      'and Memo have no markup tag yet — each is reached through the listed factory from an ' +
      "embedded { expr } inside a .guitkx component's markup, for example:",
    example: FRAMEWORK_EXAMPLE,
  },
  {
    label: 'Router',
    rows: router,
    note:
      'None of the router primitives have a markup tag yet — build the provider and route table ' +
      'with the listed factories from an embedded { expr }. Everything else about routing (the 17 ' +
      'router hooks, navigation, params) is ordinary component code. See the Router page for a ' +
      'complete example.',
  },
]

/* ------------------------------------------------------------------ */
/*  Universal structural attributes                                    */
/* ------------------------------------------------------------------ */

type PropRow = { name: string; type: string; desc: string }

const baseProps: PropRow[] = [
  { name: 'key', type: 'Variant', desc: 'Stable identity for keyed reconciliation' },
  { name: 'ref', type: 'Callable | Dictionary', desc: 'Receives the live Godot node (Callable(node) or a { "current": … } box)' },
  { name: 'style', type: 'Dictionary', desc: 'Inline style dictionary (RuitkStyle shorthands + theme channels)' },
  { name: 'classes', type: 'String | Array', desc: 'Named style-set class names registered with RuitkStyleSheet' },
  { name: '<any node property>', type: 'Variant', desc: 'Any property of the underlying Control (text, disabled, editable, …) is set directly' },
  { name: 'on<Signal>', type: 'Callable', desc: 'Event handler — on + PascalCase(signal name) (onPressed, onValueChanged, …) or native on_<signal>' },
]

/* ------------------------------------------------------------------ */
/*  Page                                                               */
/* ------------------------------------------------------------------ */

export const UitkxComponentsPage: FC = () => (
  <Box sx={Styles.root}>
    <Typography variant="h4" component="h1" gutterBottom>
      Components Overview
    </Typography>
    <Typography variant="body1" paragraph>
      Reactive UI Toolkit wraps every Godot <code>Control</code> as a declarative host element you can use in{' '}
      <code>.guitkx</code> markup. From 0.9.0 the element names are <strong>1:1 the official Godot
      class names</strong> — <code>{'<VBoxContainer>'}</code>, <code>{'<Label>'}</code>,{' '}
      <code>{'<PanelContainer>'}</code>. Beyond the curated set,{' '}
      <strong>any instantiable Godot <code>Node</code> class is a valid tag</strong> (an open
      vocabulary resolved via <code>ClassDB</code>) — <code>{'<GraphEdit />'}</code> just works. Use
      distinct PascalCase names for your own components. For the full per-element property
      reference, see the data-driven <strong>Components</strong> reference; this page is the
      conceptual overview.
    </Typography>

    <CodeBlock language="jsx" code={COMPONENT_SAMPLE} />

    {/* ── Categorized component catalog ────────────────────────── */}
    {allCategories.map((cat) => (
      <Box key={cat.label} sx={{ mt: 2 }}>
        <Typography variant="h5" component="h2" gutterBottom>
          {cat.label}
        </Typography>
        <TableContainer component={Paper} variant="outlined">
          <Table size="small">
            <TableHead>
              <TableRow>
                <TableCell><strong>Element</strong></TableCell>
                <TableCell><strong>Description</strong></TableCell>
              </TableRow>
            </TableHead>
            <TableBody>
              {cat.rows.map((c) => (
                <TableRow key={c.name}>
                  <TableCell>
                    {c.hasTag === false ? (
                      <>
                        <code>{c.factory}</code>{' '}
                        <Chip label="no markup tag yet — embedded { expr }" size="small" variant="outlined" />
                      </>
                    ) : (
                      <code>{`<${c.name}>`}</code>
                    )}
                  </TableCell>
                  <TableCell>{c.desc}</TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </TableContainer>
        {cat.note && (
          <Alert severity="info" sx={{ mt: 1 }}>
            {cat.note}
          </Alert>
        )}
        {cat.example && (
          <Box sx={{ mt: 1 }}>
            <CodeBlock language="jsx" code={cat.example} />
          </Box>
        )}
      </Box>
    ))}

    <Alert severity="info" sx={{ mt: 2 }}>
      The catalog above is the <em>curated</em> set. Any other instantiable Godot <code>Node</code>{' '}
      class is a valid tag too — <code>{'<GraphEdit />'}</code>,{' '}
      <code>{'<TextureProgressBar />'}</code>, … — resolved through <code>ClassDB</code> at runtime.
    </Alert>

    {/* ── Universal structural attributes ──────────────────────── */}
    <Box sx={{ mt: 3 }}>
      <Typography variant="h5" component="h2" gutterBottom>
        Universal attributes
      </Typography>
      <Typography variant="body1" paragraph>
        Every host element accepts these attributes in addition to the properties of its underlying
        Godot node:
      </Typography>
      <TableContainer component={Paper} variant="outlined">
        <Table size="small">
          <TableHead>
            <TableRow>
              <TableCell><strong>Attribute</strong></TableCell>
              <TableCell><strong>Type</strong></TableCell>
              <TableCell><strong>Description</strong></TableCell>
            </TableRow>
          </TableHead>
          <TableBody>
            {baseProps.map((p) => (
              <TableRow key={p.name}>
                <TableCell><code>{p.name}</code></TableCell>
                <TableCell><code>{p.type}</code></TableCell>
                <TableCell>{p.desc}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </TableContainer>
      <Alert severity="info" sx={{ mt: 1 }}>
        Event handler names are <code>on</code> + PascalCase(signal name) — <code>onPressed</code>{' '}
        → <code>pressed</code>, <code>onTextChanged</code> → <code>text_changed</code>,{' '}
        <code>onItemSelected</code> → <code>item_selected</code> — and the rule works for every
        signal of every node. See the <strong>Events &amp; Input Handling</strong> page.
      </Alert>
    </Box>

    {/* ── Authoring guidelines ─────────────────────────────────── */}
    <Box sx={{ mt: 3 }}>
      <Typography variant="h5" component="h2" gutterBottom>
        Authoring guidelines
      </Typography>
      <List>
        <ListItem disablePadding>
          <ListItemText primary="Prefer direct tag attributes over hand-building props dictionaries when authoring .guitkx." />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary="Keep setup code small and close to the returned markup tree." />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary="Custom component names must be PascalCase and must not collide with built-in tag names." />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary="A .guitkx file can hold one or more declarations; the generated GDScript class name is inferred from them (an @class_name directive can override it, but rarely needs to)." />
        </ListItem>
      </List>
    </Box>
  </Box>
)
