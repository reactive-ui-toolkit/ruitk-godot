import type { FC } from 'react'
import {
  Alert,
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
import {
  EVENTS_CHANGE_EXAMPLE,
  EVENTS_CLICK_EXAMPLE,
  EVENTS_FOCUS_EXAMPLE,
  EVENTS_GEOMETRY_EXAMPLE,
  EVENTS_KEYBOARD_EXAMPLE,
  EVENTS_NATIVE_EXAMPLE,
  EVENTS_POINTER_EXAMPLE,
  EVENTS_SUBMIT_EXAMPLE,
} from './EventsPage.example'

const styles = {
  root: { display: 'flex', flexDirection: 'column', gap: 2 },
  section: { mt: 2 },
  list: { pl: 2 },
} as const

/* ------------------------------------------------------------------ */
/*  on + PascalCase(signal) examples (from host_config.gd)            */
/* ------------------------------------------------------------------ */

type EventRow = { prop: string; signal: string; arg: string; note?: string }

const pointerEvents: EventRow[] = [
  { prop: 'onPressed', signal: 'pressed', arg: '(none)', note: 'BaseButton family' },
  { prop: 'onButtonDown', signal: 'button_down', arg: '(none)' },
  { prop: 'onButtonUp', signal: 'button_up', arg: '(none)' },
  { prop: 'onMouseEntered', signal: 'mouse_entered', arg: '(none)' },
  { prop: 'onMouseExited', signal: 'mouse_exited', arg: '(none)' },
  { prop: 'onGuiInput', signal: 'gui_input', arg: 'InputEvent', note: 'Any Control' },
]

const focusEvents: EventRow[] = [
  { prop: 'onFocusEntered', signal: 'focus_entered', arg: '(none)' },
  { prop: 'onFocusExited', signal: 'focus_exited', arg: '(none)' },
]

const valueEvents: EventRow[] = [
  { prop: 'onToggled', signal: 'toggled', arg: 'bool', note: 'CheckBox / CheckButton / toggle Button' },
  { prop: 'onValueChanged', signal: 'value_changed', arg: 'float', note: 'HSlider / VSlider / SpinBox' },
  { prop: 'onItemSelected', signal: 'item_selected', arg: 'int', note: 'OptionButton / ItemList / Tree' },
  { prop: 'onTextChanged', signal: 'text_changed', arg: 'String', note: 'LineEdit / TextEdit / CodeEdit' },
  { prop: 'onTextSubmitted', signal: 'text_submitted', arg: 'String', note: 'LineEdit — fired on Enter' },
  { prop: 'onTabChanged', signal: 'tab_changed', arg: 'int', note: 'TabBar / TabContainer' },
  { prop: 'onColorChanged', signal: 'color_changed', arg: 'Color', note: 'ColorPicker' },
]

const geometryEvents: EventRow[] = [
  { prop: 'onResized', signal: 'resized', arg: '(none)' },
]

const escapeEvents: EventRow[] = [
  { prop: 'on_<signal>', signal: 'that signal, verbatim', arg: 'signal args', note: 'Escape hatch — any signal' },
]

const allEvents = [
  { label: 'Pointer / Press', rows: pointerEvents },
  { label: 'Focus', rows: focusEvents },
  { label: 'Value & Text', rows: valueEvents },
  { label: 'Geometry', rows: geometryEvents },
  { label: 'Native escape hatch', rows: escapeEvents },
]

/* ------------------------------------------------------------------ */
/*  Main page                                                         */
/* ------------------------------------------------------------------ */

export const EventsPage: FC = () => (
  <Box sx={styles.root}>
    <Typography variant="h4" component="h1" gutterBottom>
      Events &amp; Input Handling
    </Typography>
    <Typography variant="body1" paragraph>
      Event handlers are just props. Under the hood the host config connects each
      handler prop to a Godot <code>signal</code> on the underlying{' '}
      <code>Control</code>, and disconnects it again when the prop is removed or
      the node unmounts — you never touch <code>connect()</code> /{' '}
      <code>disconnect()</code> yourself. There is <strong>one rule</strong>, and
      it covers every signal of every node:
    </Typography>
    <Box component="ul" sx={styles.list}>
      <li>
        <strong>
          <code>on</code> + PascalCase(signal name)
        </strong>{' '}
        — <code>onPressed</code> binds to <code>pressed</code>,{' '}
        <code>onValueChanged</code> to <code>value_changed</code>,{' '}
        <code>onGuiInput</code> to <code>gui_input</code>. There is no alias
        table and no special-cased names: the prop name <em>is</em> the Godot
        signal name, camelCased. If the node has the signal, the rule reaches it.
      </li>
      <li>
        <strong>Native escape hatch</strong> — <code>on_&lt;signal&gt;</code>{' '}
        binds verbatim to the signal of that exact name (e.g.{' '}
        <code>on_gui_input</code>, <code>on_id_pressed</code>,{' '}
        <code>on_item_activated</code>). Equivalent to the camelCase spelling —
        use whichever reads better to you.
      </li>
    </Box>
    <Alert severity="info">
      Coming from 0.8? The React-style aliases (<code>onClick</code>,{' '}
      <code>onChange</code>, <code>onSubmit</code>, <code>onFocus</code>/
      <code>onBlur</code>, <code>onPointer*</code>, <code>onResize</code>) were{' '}
      <strong>removed in 0.9.0</strong> in favor of the loyal-to-Godot rule
      above. See <code>MIGRATION-0.9.md</code> at the repository root for the
      full old-name → new-name mapping.
    </Alert>

    {/* ── Event handler reference ───────────────────────────────── */}
    <Box sx={styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        The rule in practice — common controls
      </Typography>
      <Typography variant="body1" paragraph>
        Any prop that starts with <code>on</code> followed by an uppercase letter
        (<code>onPressed</code>) or with <code>on_</code>{' '}
        (<code>on_gui_input</code>) is treated as an event handler. The camelCase
        name is converted with a plain <code>camelCase → snake_case</code>{' '}
        transform and connected to that signal. The handler receives exactly the
        arguments the Godot signal emits. These are not special cases — just the
        one rule applied to the signals you will use most:
      </Typography>

      {allEvents.map((group) => (
        <Box key={group.label} sx={{ mb: 2 }}>
          <Typography variant="h6" gutterBottom>
            {group.label}
          </Typography>
          <TableContainer component={Paper} variant="outlined">
            <Table size="small">
              <TableHead>
                <TableRow>
                  <TableCell><strong>Prop</strong></TableCell>
                  <TableCell><strong>Godot signal</strong></TableCell>
                  <TableCell><strong>Handler argument</strong></TableCell>
                  <TableCell><strong>Notes</strong></TableCell>
                </TableRow>
              </TableHead>
              <TableBody>
                {group.rows.map((r) => (
                  <TableRow key={r.prop}>
                    <TableCell><code>{r.prop}</code></TableCell>
                    <TableCell><code>{r.signal}</code></TableCell>
                    <TableCell><code>{r.arg}</code></TableCell>
                    <TableCell>
                      {r.note && <Chip label={r.note} size="small" />}
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </TableContainer>
        </Box>
      ))}
    </Box>

    {/* ── Press ─────────────────────────────────────────────────── */}
    <Box sx={styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        Button presses
      </Typography>
      <Typography variant="body1" paragraph>
        <code>onPressed</code> binds to the <code>pressed</code> signal on the{' '}
        <code>BaseButton</code> family (<code>Button</code>, <code>CheckBox</code>,{' '}
        <code>CheckButton</code>, <code>OptionButton</code>, …). Godot&apos;s{' '}
        <code>pressed</code> signal carries no arguments, so the handler takes
        none — read whatever you need from component state or a ref instead.
      </Typography>
      <CodeBlock language="gdscript" code={EVENTS_CLICK_EXAMPLE} />
    </Box>

    {/* ── Value-change signals per control ──────────────────────── */}
    <Box sx={styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        Value changes — each control names its own signal
      </Typography>
      <Typography variant="body1" paragraph>
        There is no polymorphic <code>onChange</code>. Each Godot control has its
        own value/selection signal, and you name it directly: a{' '}
        <code>CheckButton</code> emits <code>toggled</code> (so{' '}
        <code>onToggled</code>), a slider or <code>SpinBox</code> emits{' '}
        <code>value_changed</code> (<code>onValueChanged</code>), an{' '}
        <code>OptionButton</code>, <code>ItemList</code>, or <code>Tree</code>{' '}
        emits <code>item_selected</code> (<code>onItemSelected</code>), a text
        control emits <code>text_changed</code> (<code>onTextChanged</code>), a{' '}
        <code>TabBar</code> / <code>TabContainer</code> emits{' '}
        <code>tab_changed</code> (<code>onTabChanged</code>), and a{' '}
        <code>ColorPicker</code> emits <code>color_changed</code>{' '}
        (<code>onColorChanged</code>). Your handler receives that signal&apos;s
        native argument (a <code>bool</code>, a <code>float</code>, an index, a{' '}
        <code>String</code>, a <code>Color</code>, …).
      </Typography>
      <Alert severity="info" sx={{ mb: 2 }}>
        The explicit name is the documentation: seeing{' '}
        <code>onItemSelected</code> in markup tells you exactly which Godot
        signal fires and what argument arrives — no lookup table needed.
      </Alert>
      <CodeBlock language="gdscript" code={EVENTS_CHANGE_EXAMPLE} />
    </Box>

    {/* ── Text input ────────────────────────────────────────────── */}
    <Box sx={styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        Text input — onTextChanged &amp; onTextSubmitted
      </Typography>
      <Typography variant="body1" paragraph>
        For text controls, <code>onTextChanged</code> binds to{' '}
        <code>text_changed</code> (fires on every keystroke, passing the new{' '}
        <code>String</code>), and <code>onTextSubmitted</code> binds to{' '}
        <code>text_submitted</code> (fires when the user presses Enter). Setting{' '}
        <code>text</code> from state every render is safe — the host config
        preserves the caret position on <code>LineEdit</code> /{' '}
        <code>TextEdit</code>, so a controlled input never jumps to column 0
        mid-typing.
      </Typography>
      <CodeBlock language="gdscript" code={EVENTS_SUBMIT_EXAMPLE} />
    </Box>

    {/* ── Pointer ───────────────────────────────────────────────── */}
    <Box sx={styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        Pointer events
      </Typography>
      <Typography variant="body1" paragraph>
        <code>onMouseEntered</code> / <code>onMouseExited</code> bind to{' '}
        <code>mouse_entered</code> / <code>mouse_exited</code> on any{' '}
        <code>Control</code>, and <code>onButtonDown</code> /{' '}
        <code>onButtonUp</code> bind to a <code>BaseButton</code>&apos;s{' '}
        <code>button_down</code> / <code>button_up</code>. These Godot signals
        pass no arguments. For raw pointer position, buttons, or motion, use{' '}
        <code>onGuiInput</code> (or <code>on_gui_input</code>) and inspect the{' '}
        <code>InputEvent</code> (see below).
      </Typography>
      <CodeBlock language="gdscript" code={EVENTS_POINTER_EXAMPLE} />
    </Box>

    {/* ── Focus ─────────────────────────────────────────────────── */}
    <Box sx={styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        Focus tracking
      </Typography>
      <Typography variant="body1" paragraph>
        <code>onFocusEntered</code> / <code>onFocusExited</code> bind to
        Godot&apos;s <code>focus_entered</code> / <code>focus_exited</code>.
        Combine them with an inline <code>style</code> to give focused controls a
        distinct look.
      </Typography>
      <CodeBlock language="gdscript" code={EVENTS_FOCUS_EXAMPLE} />
    </Box>

    {/* ── Geometry ──────────────────────────────────────────────── */}
    <Box sx={styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        Geometry / resize
      </Typography>
      <Typography variant="body1" paragraph>
        <code>onResized</code> binds to a <code>Control</code>&apos;s{' '}
        <code>resized</code> signal. Like most Godot layout signals it carries no
        payload, so capture the node with a <code>ref</code> and read its{' '}
        <code>size</code> inside the handler.
      </Typography>
      <CodeBlock language="gdscript" code={EVENTS_GEOMETRY_EXAMPLE} />
    </Box>

    {/* ── Keyboard ──────────────────────────────────────────────── */}
    <Box sx={styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        Keyboard input
      </Typography>
      <Typography variant="body1" paragraph>
        Godot Controls do not expose per-key signals. Reach the raw input stream
        with <code>onGuiInput</code> / <code>on_gui_input</code> (the{' '}
        <code>gui_input</code> signal) and match on <code>InputEventKey</code>.
        Make sure the control can take focus (<code>focus_mode</code>) so it
        receives GUI input.
      </Typography>
      <CodeBlock language="gdscript" code={EVENTS_KEYBOARD_EXAMPLE} />
    </Box>

    {/* ── Native escape hatch ───────────────────────────────────── */}
    <Box sx={styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        The native <code>on_&lt;signal&gt;</code> escape hatch
      </Typography>
      <Typography variant="body1" paragraph>
        Any prop written as <code>on_&lt;signal&gt;</code> connects verbatim to
        that signal on the node — the exact snake_case signal name, no case
        transform at all. It reaches everything the camelCase rule reaches:{' '}
        <code>id_pressed</code> on a <code>PopupMenu</code>,{' '}
        <code>item_activated</code> on a <code>Tree</code> or{' '}
        <code>ItemList</code>, <code>gui_input</code> for raw{' '}
        <code>InputEvent</code>s, or any custom signal on your own scene. The
        handler receives exactly the arguments that signal emits.
      </Typography>
      <CodeBlock language="gdscript" code={EVENTS_NATIVE_EXAMPLE} />
      <Alert severity="info" sx={{ mt: 2 }}>
        A handler prop whose value is not a valid <code>Callable</code>, or whose
        resolved signal does not exist on the node, is skipped with a{' '}
        <code>push_warning</code> naming the prop and the signal it tried — so
        typos surface loudly instead of failing silently.
      </Alert>
    </Box>
  </Box>
)
