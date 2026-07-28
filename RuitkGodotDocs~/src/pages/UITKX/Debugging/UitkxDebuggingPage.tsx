import type { FC } from 'react'
import { Box, Typography } from '@mui/material'
import { CodeBlock } from '../../../components/CodeBlock/CodeBlock'
import Styles from '../Reference/UitkxReferencePage.style'

const GENERATED_FILE_PATH = `# Each Foo.guitkx compiles to a SIBLING Foo.gd next to it:
#   res://ui/Counter.guitkx  ->  res://ui/Counter.gd
#
# The .gd is a real GDScript source file Godot's compiler owns — so it is fully
# inspectable, steppable, and hot-reloadable. Open it in the Godot script editor
# (or your external editor) to read exactly what your markup lowered to.`

const DIAGS_JSON = `# Compile diagnostics are written next to the source:
#   res://ui/Counter.guitkx.diags.json
#
# e.g. { "diagnostics": [], "src_hash": 2321798135 }
# A non-empty "diagnostics" array lists the GUITKX#### codes for that file.`

export const UitkxDebuggingPage: FC = () => (
  <Box sx={Styles.root}>
    <Typography variant="h4" component="h1" gutterBottom>
      Debugging Guide
    </Typography>
    <Typography variant="body1" paragraph>
      How to diagnose and fix common issues when working with{' '}
      <code>.guitkx</code>.
    </Typography>

    {/* ── Inspecting generated code ──────────────────────────────────────── */}
    <Typography variant="h5" component="h2" sx={Styles.section}>
      Inspecting Generated Code
    </Typography>
    <Typography variant="body2" paragraph>
      Unlike a source generator that hides its output, the <code>.guitkx</code>{' '}
      compiler emits a plain sibling <code>.gd</code> file that Godot compiles
      normally. There is nothing special to attach to — it is just GDScript. To
      inspect it:
    </Typography>
    <Typography component="ol" variant="body2">
      <li>Open the sibling <code>.gd</code> file next to your <code>.guitkx</code> in the Godot script editor (or any editor).</li>
      <li>Read the generated <code>render(props, children)</code> function to see exactly which <code>V.*</code> factory calls your markup produced.</li>
      <li>The <code>@tool</code> editor plugin regenerates the <code>.gd</code> on every save and nudges the Godot filesystem so it hot-reloads.</li>
    </Typography>
    <CodeBlock language="gdscript" code={GENERATED_FILE_PATH} />

    {/* ── Reading diagnostics ─────────────────────────────────────────────── */}
    <Typography variant="h5" component="h2" sx={Styles.section}>
      Reading Compile Diagnostics
    </Typography>
    <Typography variant="body2" paragraph>
      When a <code>.guitkx</code> fails to compile, the plugin writes a{' '}
      <code>.guitkx.diags.json</code> next to the source and calls{' '}
      <code>push_error</code> / <code>push_warning</code> in the Godot output with
      the <code>GUITKX####</code> code and message. On an error the emitted{' '}
      <code>.gd</code> is a stub that <code>push_error</code>s with the mapped
      location, so a broken file surfaces loudly rather than silently doing
      nothing.
    </Typography>
    <CodeBlock language="gdscript" code={DIAGS_JSON} />

    {/* ── Breakpoints & stack traces ─────────────────────────────────────── */}
    <Typography variant="h5" component="h2" sx={Styles.section}>
      Breakpoints &amp; Stack Traces
    </Typography>
    <Typography variant="body2" paragraph>
      Breakpoints cannot be set in <code>.guitkx</code> files directly — set them
      in the generated <code>.gd</code>:
    </Typography>
    <Typography component="ol" variant="body2">
      <li>Open the sibling <code>.gd</code> in the Godot script editor.</li>
      <li>Set breakpoints in the generated <code>render</code> body or in any setup / effect / event-handler code — the Godot debugger hits them normally while the app runs.</li>
      <li>Because the setup code you wrote in the <code>.guitkx</code> is copied into the <code>.gd</code> verbatim, the stack frames and local variables you see match what you authored.</li>
    </Typography>
    <Typography variant="body2" paragraph>
      To inspect the live node tree the reconciler produces, use Godot&apos;s{' '}
      <strong>Remote</strong> scene tree (the Remote tab in the Scene dock while
      the game runs) and the <strong>Debugger</strong> panel — the mounted
      Controls are ordinary nodes, so everything (properties, layout, signals) is
      visible there.
    </Typography>

    {/* ── Language server logs ────────────────────────────────────────────── */}
    <Typography variant="h5" component="h2" sx={Styles.section}>
      Language Server Logs
    </Typography>
    <Typography variant="body2" paragraph>
      The editor extension runs a headless language server (embedding{' '}
      <code>gdscript-analyzer</code>) for both markup and embedded GDScript. If
      completion, hover, or diagnostics go stale, run the{' '}
      <strong>GUITKX: Restart Language Server</strong> command from the command
      palette. In VS Code, its output appears in the Output panel under the{' '}
      <strong>GUITKX</strong> channel — useful for diagnosing missing completions,
      stale diagnostics, or analyzer crashes.
    </Typography>

    {/* ── Formatter issues ────────────────────────────────────────────────── */}
    <Typography variant="h5" component="h2" sx={Styles.section}>
      Formatter Issues
    </Typography>
    <Typography variant="body2" paragraph>
      If formatting produces unexpected results:
    </Typography>
    <Typography component="ol" variant="body2">
      <li>
        <strong>Check for syntax errors first</strong> — the formatter needs
        valid <code>.guitkx</code>. Fix any red squiggles before formatting.
      </li>
      <li>
        <strong>Confirm the default formatter</strong> — for{' '}
        <code>[guitkx]</code> files, <code>editor.defaultFormatter</code> should
        be <code>ReactiveUITK.guitkx</code>.
      </li>
      <li>
        <strong>Remember the canonical indent is 2 spaces</strong> —{' '}
        <code>.guitkx</code> formats to 2-space indentation by default. Drop a{' '}
        <code>guitkx.config.json</code> to change <code>indentStyle</code>,{' '}
        <code>printWidth</code>, or attribute wrapping (see the Configuration
        reference).
      </li>
      <li>
        <strong>Embedded reflow needs gdformat</strong> — reflow of the embedded
        GDScript only happens when <code>gdformat</code> is installed and{' '}
        <code>guitkx.useGdformat</code> is on. Any change beyond whitespace /
        quote style is rejected, so it never alters semantics.
      </li>
    </Typography>

    {/* ── Reporting bugs ──────────────────────────────────────────────────── */}
    <Typography variant="h5" component="h2" sx={Styles.section}>
      Reporting Bugs
    </Typography>
    <Typography variant="body2" paragraph>
      When reporting an issue, include:
    </Typography>
    <Typography component="ol" variant="body2">
      <li>The minimal <code>.guitkx</code> that reproduces the problem (and the generated <code>.gd</code> if the bug is in codegen).</li>
      <li>The exact error message or <code>GUITKX####</code> code (from the output or the <code>.diags.json</code>).</li>
      <li>Your Godot version, editor (VS Code / Rider / Visual Studio), and extension version.</li>
      <li>Language server output if relevant (see above).</li>
    </Typography>
  </Box>
)
