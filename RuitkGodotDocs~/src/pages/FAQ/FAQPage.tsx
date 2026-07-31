import type { FC } from 'react'
import { Box, Typography } from '@mui/material'
import Styles from './FAQPage.style'

export const FAQPage: FC = () => (
  <Box sx={Styles.root}>
    <Typography variant="h4" component="h1" gutterBottom>
      Frequently Asked Questions
    </Typography>

    {/* ── General ──────────────────────────────────────────────────────── */}
    <Typography variant="h5" component="h2" sx={Styles.section}>
      General
    </Typography>

    <Typography variant="body1" sx={Styles.question}>
      What is ReactiveUI?
    </Typography>
    <Typography variant="body2" paragraph>
      ReactiveUI is a React-style UI framework for Godot, written in GDScript. You build
      interfaces from <strong>function components</strong> and <strong>hooks</strong>, and a
      fiber reconciler diffs a virtual tree against the live Godot <code>Control</code> tree,
      applying only the minimal changes. It ships as a Godot addon whose runtime lives entirely
      in <code>addons/reactive_ui_toolkit/</code>.
    </Typography>

    <Typography variant="body1" sx={Styles.question}>
      What is <code>.guitkx</code>?
    </Typography>
    <Typography variant="body2" paragraph>
      <code>.guitkx</code> is the markup language you author components in — JSX-style tags,
      hooks, and control flow (<code>@if</code>, <code>@for</code>, <code>@match</code>) in one
      file. A <code>@tool</code> editor plugin compiles each <code>.guitkx</code> into a sibling{' '}
      <code>.gd</code> render function on save. Under the hood it compiles to plain calls against
      the <code>V</code> factory and <code>Hooks</code> API — see below for when to reach for
      those directly instead.
    </Typography>

    <Typography variant="body1" sx={Styles.question}>
      Which Godot versions are supported?
    </Typography>
    <Typography variant="body2" paragraph>
      Godot <strong>4.4</strong> and above (the 4.x <code>Control</code> / <code>Theme</code> /{' '}
      <code>StyleBox</code> APIs the framework builds on). The runtime is pure GDScript with no
      GDExtension dependency, so it runs anywhere the Godot editor and its export templates run.
    </Typography>

    <Typography variant="body1" sx={Styles.question}>
      How is this different from plain Godot Control nodes?
    </Typography>
    <Typography variant="body2" paragraph>
      You describe <em>what</em> the UI should look like for the current state and let the
      reconciler figure out the node operations. State lives in hooks (<code>useState</code>,{' '}
      <code>useReducer</code>, <code>useSignal</code>) instead of being scattered across node
      references and manual <code>show()</code>/<code>hide()</code>/<code>queue_free()</code> calls.
      Under the hood it is still ordinary Godot <code>Control</code> nodes — nothing exotic.
    </Typography>

    <Typography variant="body1" sx={Styles.question}>
      Does it add runtime overhead?
    </Typography>
    <Typography variant="body2" paragraph>
      Rendering only runs when state changes — there is no per-frame diff of a static UI. Each
      update diffs the affected subtree and applies the minimal set of node changes. Update
      renders are <strong>time-sliced by default</strong>: large render phases are chunked
      across frames under a per-frame budget, so one big update can&apos;t stall a frame — the
      commit stays atomic and the initial mount is always synchronous. Set{' '}
      <code>RuitkConfig.time_slicing = false</code> for a strictly synchronous single-pass render
      per update. For typical menus and HUDs the overhead is negligible either way.
    </Typography>

    <Typography variant="body1" sx={Styles.question}>
      When should I use it — and when not?
    </Typography>
    <Typography variant="body2" paragraph>
      Reach for it for state-heavy, frequently-changing UI: menus, inventories, settings screens,
      HUDs, editor tools. For a handful of static labels and a button, a hand-built scene is
      simpler. It composes fine with the rest of your game — mount reactive roots only where the
      declarative model pays off.
    </Typography>

    {/* ── Authoring ────────────────────────────────────────────────────── */}
    <Typography variant="h5" component="h2" sx={Styles.section}>
      Authoring
    </Typography>

    <Typography variant="body1" sx={Styles.question}>
      How do I mount a component?
    </Typography>
    <Typography variant="body2" paragraph>
      Call <code>RuitkRoot.create(container, V.fc(MyComponent.render))</code> from a script on
      the <code>Control</code> that should host the UI (typically in <code>_ready()</code>), and
      call <code>unmount()</code> on the returned root in <code>_exit_tree()</code>. The container
      is any Godot <code>Control</code> or <code>Node</code>.
    </Typography>

    <Typography variant="body1" sx={Styles.question}>
      What do event handlers look like?
    </Typography>
    <Typography variant="body2" paragraph>
      The handler name is the Godot signal name: <code>on</code> + PascalCase(signal) —{' '}
      <code>onPressed</code> for <code>pressed</code>, <code>onTextChanged</code> for{' '}
      <code>text_changed</code>, <code>onValueChanged</code> for <code>value_changed</code>,{' '}
      <code>onGuiInput</code> for <code>gui_input</code>. One rule, every signal of every node —
      there is no alias table. The native <code>on_&lt;signal&gt;</code> form (e.g.{' '}
      <code>on_pressed</code>) also works, verbatim. (The 0.8 React aliases like{' '}
      <code>onClick</code>/<code>onChange</code> were removed in 0.9.0 — see{' '}
      <code>MIGRATION-0.9.md</code> at the repo root.)
    </Typography>

    <Typography variant="body1" sx={Styles.question}>
      Can I use plain GDScript inside a component?
    </Typography>
    <Typography variant="body2" paragraph>
      Yes. The setup code above the <code>return</code> is ordinary GDScript — declare variables,
      call methods, load resources, read game state. Attribute values inside markup accept any
      GDScript expression via the <code>{'{expr}'}</code> braces.
    </Typography>

    <Typography variant="body1" sx={Styles.question}>
      Why must hooks be called at the top level?
    </Typography>
    <Typography variant="body2" paragraph>
      Hooks (<code>useState</code>, <code>useEffect</code>, <code>useSignal</code>, …) are
      matched to storage slots by call order. They must be called unconditionally at the top of
      the component — never inside <code>@if</code>, <code>@for</code>, or an event handler — so
      the order is identical on every render. In debug builds{' '}
      <code>RuitkConfig.enable_hook_validation</code> detects order mismatches and warns loudly.
    </Typography>

    <Typography variant="body1" sx={Styles.question}>
      How do I share state across components?
    </Typography>
    <Typography variant="body2" paragraph>
      For local state use <code>useState</code> / <code>useReducer</code>. For app-wide state
      use <strong>signals</strong>: create a <code>RuitkSignal</code> store, then read it in any
      component with the <code>useSignal</code> hook — every subscriber re-renders when the value
      changes, with no prop-drilling. Context (<code>useContext</code>) is available for
      scoped-tree sharing.
    </Typography>

    {/* ── Styling & Assets ─────────────────────────────────────────────── */}
    <Typography variant="h5" component="h2" sx={Styles.section}>
      Styling &amp; Assets
    </Typography>

    <Typography variant="body1" sx={Styles.question}>
      How do I style elements — is there CSS/USS?
    </Typography>
    <Typography variant="body2" paragraph>
      No — Godot has no USS/CSS, and neither does this library. You pass a{' '}
      <code>style</code> Dictionary on any element and <code>RuitkStyle</code> maps it onto Godot{' '}
      <code>Control</code> properties, size flags, and <code>Theme</code>/<code>StyleBox</code>{' '}
      overrides (e.g. <code>{'{ "bg_color": Color(0.1,0.1,0.18), "corner_radius_all": 8, "content_margin_all": 12 }'}</code>).
      For shared bundles, register named styles with <code>RuitkStyleSheet</code> and reference them
      through the <code>classes</code> prop. See the <em>Styling</em> page.
    </Typography>

    <Typography variant="body1" sx={Styles.question}>
      How do I load textures, fonts, and themes?
    </Typography>
    <Typography variant="body2" paragraph>
      With Godot&apos;s native <code>preload()</code> / <code>load()</code> on a{' '}
      <code>res://</code> path. The resulting <code>Texture2D</code>, <code>FontFile</code>,{' '}
      <code>Theme</code>, or <code>StyleBox</code> goes straight into markup, an attribute, or a{' '}
      <code>style</code> dict. There is no separate asset importer or registry — see the{' '}
      <em>Assets</em> page.
    </Typography>

    {/* ── Editor & Tooling ─────────────────────────────────────────────── */}
    <Typography variant="h5" component="h2" sx={Styles.section}>
      Editor &amp; Tooling
    </Typography>

    <Typography variant="body1" sx={Styles.question}>
      Do I need any external editor to use the library?
    </Typography>
    <Typography variant="body2" paragraph>
      No. The <code>.guitkx</code> → <code>.gd</code> compiler runs inside the Godot editor as a{' '}
      <code>@tool</code> plugin, so components compile on save regardless of where you type. An
      external editor extension only adds the authoring experience — highlighting, completion,
      diagnostics — on top.
    </Typography>

    <Typography variant="body1" sx={Styles.question}>
      Which editors have <code>.guitkx</code> language support?
    </Typography>
    <Typography variant="body2" paragraph>
      Godot itself does, out of the box: the <strong>reactive_ui_toolkit_editor</strong> addon
      (<code>addons/reactive_ui_toolkit_editor/</code>) is a native in-editor plugin with syntax
      highlighting, live diagnostics, completion, and hover built directly into the Godot
      editor — no external tools required. <strong>VS Code</strong> and{' '}
      <strong>Visual Studio</strong> extensions add the same markup intelligence plus one thing
      the in-editor addon doesn&apos;t cover yet: deep analysis of the embedded GDScript inside{' '}
      <code>{'{expr}'}</code> and setup code, via a language server that embeds the Rust GDScript
      analyzer.
    </Typography>

    <Typography variant="body1" sx={Styles.question}>
      Does editing a <code>.guitkx</code> file require restarting my game?
    </Typography>
    <Typography variant="body2" paragraph>
      No. While the game is running under <strong>F5</strong>, saving a <code>.guitkx</code>{' '}
      hot-reloads it into the live session within a couple of seconds — hook state is preserved
      (a counter keeps its count) unless the edit changed the component&apos;s hook-call shape, in
      which case that component&apos;s state deliberately resets. This is dev-only: it requires
      the debugger session F5 gives you, so exported builds carry none of it. See{' '}
      <strong>Hot Reload (Fast Refresh)</strong> under Tooling for the full mechanism and its
      limits.
    </Typography>

    <Typography variant="body1" sx={Styles.question}>
      Can I write components without <code>.guitkx</code> at all?
    </Typography>
    <Typography variant="body2" paragraph>
      You can, but <code>.guitkx</code> is the recommended way to author components day to day —
      it compiles straight to the <code>V</code>/<code>Hooks</code> calls described above, so
      nothing is hidden. Writing those calls by hand is the underlying implementation and stays
      fully supported as an escape hatch: for structural primitives that have no markup tag
      (<code>Portal</code>, <code>Suspense</code>, <code>ErrorBoundary</code>, <code>Memo</code>,{' '}
      <code>Audio</code>, <code>Video</code>, router configuration), or for one-off/advanced
      scripts where a whole <code>.guitkx</code> file would be overkill.
    </Typography>

    {/* ── Troubleshooting ──────────────────────────────────────────────── */}
    <Typography variant="h5" component="h2" sx={Styles.section}>
      Troubleshooting
    </Typography>

    <Typography variant="body1" sx={Styles.question}>
      My UI stopped updating after I changed state — why?
    </Typography>
    <Typography variant="body2" paragraph>
      Re-render is triggered by calling a state setter, not by mutating a value in place. Use the
      setter returned from <code>useState</code> (<code>state[1].call(new_value)</code>) rather
      than reassigning the underlying variable, and set signal values through the store so
      subscribers are notified.
    </Typography>

    <Typography variant="body1" sx={Styles.question}>
      I get a hook-order warning in the console — what does it mean?
    </Typography>
    <Typography variant="body2" paragraph>
      A hook was called conditionally, so the call order differs between renders. Move every hook
      to the top level of the component, before any <code>@if</code>/<code>@for</code>/return, so
      they run in the same order every time. This validation is on in debug builds via{' '}
      <code>RuitkConfig.enable_hook_validation</code>.
    </Typography>

    <Typography variant="body1" sx={Styles.question}>
      Godot logs &quot;Too many re-renders (setState during render?)&quot; — what happened?
    </Typography>
    <Typography variant="body2" paragraph>
      A component updated its own state unconditionally during setup, creating an infinite
      render loop: each setState during a render is deferred and replayed after commit as a
      follow-up render, and after 25 consecutive follow-ups the reconciler drops the queued
      updates and keeps the last committed UI. Move the state update into an event handler or a{' '}
      <code>useEffect</code> instead of running it every render.
    </Typography>

    <Typography variant="body1" sx={Styles.question}>
      A style like <code>bg_color</code> has no effect — why?
    </Typography>
    <Typography variant="body2" paragraph>
      The StyleBox keys (<code>bg_color</code>, <code>border_*</code>, <code>corner_radius</code>,{' '}
      <code>pad</code>) need a control with a primary stylebox slot — <code>Panel</code>,{' '}
      <code>Button</code>, <code>LineEdit</code>, <code>ProgressBar</code>. On a bare{' '}
      <code>Label</code> or a plain box container they warn once and do nothing. Wrap the content
      in a <code>Panel</code> to get a background.
    </Typography>
  </Box>
)
