import type { FC } from 'react'
import { Box, List, ListItem, ListItemText, Typography } from '@mui/material'
import Styles from '../../Concepts/ConceptsPage.style'

export const UitkxConceptsPage: FC = () => (
  <Box sx={Styles.root}>
    <Typography variant="h4" component="h1" gutterBottom>
      Concepts & Environment
    </Typography>
    <Typography variant="body1" paragraph>
      Reactive UI Toolkit brings a React-like component model to Godot. You write components, use hooks to
      manage state, and a fiber reconciler diffs each render against the last and patches only what
      changed on the real Godot <code>Control</code> tree.
    </Typography>
    <Typography variant="body1" paragraph>
      Where Godot imposes different constraints (container-driven layout, the signal-based event
      model, or a retained-mode scene tree), the library deliberately diverges from React to provide
      a more idiomatic Godot experience. Routing, signals, and safe-area helpers are examples of
      features that don't exist in core React but are important here.
    </Typography>
    <Typography variant="body1" paragraph>
      The package ships with a demo set under <code>examples/demos/</code> — each demo is a{' '}
      <code>.guitkx</code> component. Open <code>examples/main.tscn</code> in Godot to see real-world
      usage of components, hooks, routing, signals, and more.
    </Typography>

    <Box sx={Styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        Core authoring rules
      </Typography>
      <List sx={Styles.list}>
        <ListItem disablePadding>
          <ListItemText primary="Intrinsic host tag names are the Godot class names (VBoxContainer, Button, Label, …) and any instantiable Godot Node class is a valid tag; custom components should use distinct names." />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary="Function-style components are the only form: setup code first (GDScript statements + hook calls), then a single returned markup tree." />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary="useState returns a [value, setter] array; you update state by calling the setter, e.g. s[1].call(s[0] + 1)." />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary="A .guitkx file is a module holding plain top-level declarations, classified by signature: a callable annotated -> RuitkVNode is a component, a use_-prefixed callable is a hook, any other callable is a util, and name := expr is a value. export marks what other files may import." />
        </ListItem>
      </List>
    </Box>

    <Box sx={Styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        Host elements are Godot Controls
      </Typography>
      <Typography variant="body1" paragraph>
        Every host tag maps to a concrete Godot <code>Control</code>, and every one accepts the same
        universal structural attributes plus any property of the underlying node. The universal
        attributes available on <code>{'<Button>'}</code>, <code>{'<Label>'}</code>,{' '}
        <code>{'<VBoxContainer>'}</code>, and all other host elements are:
      </Typography>
      <Typography component="ul" variant="body2">
        <li><code>key</code> — stable identity for keyed reconciliation</li>
        <li><code>ref</code> — a <code>Callable(node)</code> or <code>{'{ "current": … }'}</code> box that receives the live node</li>
        <li><code>style</code> — an inline style dictionary (see the <strong>Styling</strong> pages)</li>
        <li>
          Any Godot property of the node — <code>text</code>, <code>editable</code>,{' '}
          <code>disabled</code>, <code>placeholder_text</code>, etc. — is set directly
        </li>
        <li>
          Event handlers named <code>on</code> + PascalCase(signal name): <code>onPressed</code> →{' '}
          <code>pressed</code>, <code>onTextChanged</code> → <code>text_changed</code>,{' '}
          <code>onValueChanged</code> → <code>value_changed</code>,{' '}
          <code>onGuiInput</code> → <code>gui_input</code> — one rule that reaches every signal of
          every node (the native <code>on_&lt;signal&gt;</code> spelling is also accepted)
        </li>
      </Typography>
    </Box>

    <Box sx={Styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        Diagnostics & configuration
      </Typography>
      <Typography variant="body2" paragraph>
        Two static classes control runtime behavior and tracing. The primary way to set them is
        the <strong>Reactive UI Toolkit Settings</strong> dialog (the top-level{' '}
        <strong>Reactive UI Toolkit</strong> menu — <strong>Project ▸ Tools</strong> as fallback —
        with the editor addon enabled) — the same{' '}
        <code>reactive_ui_toolkit/runtime/*</code> and{' '}
        <code>reactive_ui_toolkit/diagnostics/*</code> keys stay editable natively under{' '}
        <strong>Project → Project Settings → Reactive Ui Toolkit</strong> (see the Configuration
        Reference), loaded once at first mount and readable in exported games. Setting the fields
        from code (for example in an autoload or <code>_ready</code>) still works — only settings
        you <em>changed</em> are applied, so a direct assignment is never clobbered.
      </Typography>
      <List sx={Styles.list}>
        <ListItem disablePadding>
          <ListItemText primary={<><code>RuitkConfig.time_slicing</code> — opt into cooperative render slicing (default <code>false</code>). <code>RuitkConfig.frame_budget_ms</code> sets the per-frame budget (default <code>8.0</code>).</>} />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary={<><code>RuitkConfig.enable_hook_validation</code> — rules-of-hooks checks (defaults to <code>OS.is_debug_build()</code>).</>} />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary={<><code>RuitkConfig.enable_strict_diagnostics</code> — stricter diagnostics in debug builds (defaults to <code>OS.is_debug_build()</code>).</>} />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary={<><code>RuitkDiagnostics.enabled = true</code> — start counting renders, commits, placements, updates, and deletions. Read them with <code>RuitkDiagnostics.report()</code> and clear with <code>RuitkDiagnostics.reset()</code>.</>} />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary={<><code>RuitkDiagnostics.capture = true</code> — collect emitted messages into <code>RuitkDiagnostics.messages</code> for inspection in tests or an overlay.</>} />
        </ListItem>
      </List>
      <Typography variant="body2" paragraph>
        In Project Settings the two validation flags are tri-states (<code>auto</code> /{' '}
        <code>enabled</code> / <code>disabled</code>): <code>auto</code> keeps the compiled{' '}
        <code>OS.is_debug_build()</code> default; the other two force the flag regardless of build
        type.
      </Typography>
    </Box>

    <Box sx={Styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        Rendering pipeline
      </Typography>
      <Typography variant="body1" paragraph>
        Understanding the pipeline helps you read error messages and diagnose performance:
      </Typography>
      <Typography component="ol" variant="body2">
        <li>
          <strong>Author</strong> — You write <code>.guitkx</code> markup with setup code and a{' '}
          <code>return (...)</code> statement.
        </li>
        <li>
          <strong>Generate</strong> — On save, the editor plugin compiles each <code>.guitkx</code>{' '}
          file into a sibling <code>.gd</code> class with a{' '}
          <code>static func render(props, children) -&gt; RuitkVNode</code> method.
        </li>
        <li>
          <strong>Mount</strong> — <code>V.fc(Component.render)</code> wraps the generated method as
          an <code>RuitkVNode</code>. <code>RuitkRoot.create</code> (or{' '}
          <code>RuitkRootNode</code>) mounts it under a <code>Control</code>.
        </li>
        <li>
          <strong>Reconcile</strong> — A hook setter calls <code>request_update()</code>, which
          coalesces to one re-render per frame. The fiber reconciler builds a work-in-progress tree
          and diffs it against the committed tree, with component bailout and keyed child
          reconciliation.
        </li>
        <li>
          <strong>Commit</strong> — Patches are applied in two passes — deletions, then placements
          and updates — creating, removing, and prop-diffing Godot <code>Control</code> nodes.
        </li>
        <li>
          <strong>Effects</strong> — After commit, cleanup functions from the previous render run,
          then new <code>useEffect</code> / <code>useLayoutEffect</code> callbacks fire.
        </li>
      </Typography>
    </Box>

    <Box sx={Styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        Component lifecycle
      </Typography>
      <Typography component="ul" variant="body2">
        <li>
          <strong>Mount</strong> — build the <code>RuitkVNode</code> tree → create the{' '}
          <code>Control</code> nodes → run effects.
        </li>
        <li>
          <strong>Update</strong> — re-render → diff → patch → run cleanup → run new effects.
        </li>
        <li>
          <strong>Unmount</strong> — run all cleanup functions → remove the <code>Control</code>{' '}
          nodes from the tree (<code>RuitkRoot.unmount()</code>).
        </li>
      </Typography>
    </Box>
  </Box>
)
