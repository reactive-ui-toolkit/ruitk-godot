import type { FC } from 'react'
import {
  Box,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableRow,
  Typography,
} from '@mui/material'
import { CodeBlock } from '../../../components/CodeBlock/CodeBlock'
import Styles from '../Reference/UitkxReferencePage.style'

const GUITKX_CONFIG = `{
  "root": "res://ui",
  "formatter": {
    "printWidth": 100,
    "indentStyle": "space",
    "indentSize": 2,
    "singleAttributePerLine": false,
    "insertSpaceBeforeSelfClose": true
  }
}`

export const UitkxConfigPage: FC = () => (
  <Box sx={Styles.root}>
    <Typography variant="h4" component="h1" gutterBottom>
      Configuration Reference
    </Typography>
    <Typography variant="body1" paragraph>
      All configuration options for the Reactive UI Toolkit runtime, the GUITKX
      editor extension, and the formatter.
    </Typography>

    {/* ── Runtime settings (Godot Project Settings) ─────────────────────── */}
    <Typography variant="h5" component="h2" sx={Styles.section}>
      Runtime Settings (Project Settings)
    </Typography>
    <Typography variant="body2" paragraph>
      The runtime&apos;s tunables are native Godot Project Settings. The primary
      way to edit them is the <strong>Reactive UI Toolkit Settings</strong> dialog
      — the top-level <strong>Reactive UI Toolkit ▸ Settings...</strong> menu (with an
      automatic <strong>Project ▸ Tools</strong> fallback) or the{' '}
      <strong>Settings</strong> toolbar button in the ReactiveUITK main screen
      (editor addon) — which reads and writes the same keys; the native{' '}
      <strong>Project → Project Settings</strong> dialog (group{' '}
      <strong>Reactive Ui Toolkit</strong>, either addon registers it) remains a
      mirror of the same storage. Values load once at first mount
      (<code>RuitkRoot.create</code>) and are readable in exported games. Only
      settings you <em>changed</em> are applied, so assigning the{' '}
      <code>RuitkConfig</code> / <code>RuitkDiagnostics</code> statics directly
      from code still works and is never clobbered. For per-machine overrides,
      put the keys in an <code>override.cfg</code> beside{' '}
      <code>project.godot</code>.
    </Typography>
    <TableContainer>
      <Table size="small" sx={Styles.table}>
        <TableHead>
          <TableRow>
            <TableCell>Setting</TableCell>
            <TableCell>Type</TableCell>
            <TableCell>Default</TableCell>
            <TableCell>Applies to</TableCell>
          </TableRow>
        </TableHead>
        <TableBody>
          <TableRow>
            <TableCell><code>reactive_ui_toolkit/runtime/time_slicing</code></TableCell>
            <TableCell>boolean</TableCell>
            <TableCell><code>true</code></TableCell>
            <TableCell><code>RuitkConfig.time_slicing</code> — update renders are sliced across frames (the default since 0.14); <code>false</code> restores the synchronous single-pass render per update. Mounts are always synchronous; the commit is atomic either way.</TableCell>
          </TableRow>
          <TableRow>
            <TableCell><code>reactive_ui_toolkit/runtime/time_slice_ms</code></TableCell>
            <TableCell>float</TableCell>
            <TableCell><code>2.0</code></TableCell>
            <TableCell><code>RuitkConfig.time_slice_ms</code> — the render-phase quantum: the work loop yields after this much elapsed time (checked after each completed unit).</TableCell>
          </TableRow>
          <TableRow>
            <TableCell><code>reactive_ui_toolkit/runtime/frame_budget_ms</code></TableCell>
            <TableCell>float</TableCell>
            <TableCell><code>4.0</code></TableCell>
            <TableCell><code>RuitkConfig.frame_budget_ms</code> — the scheduler&apos;s per-frame budget, cumulative across all lanes (a 2 ms slice can run twice inside it). Re-scoped in 0.14: it was the single-render park budget (default 8.0).</TableCell>
          </TableRow>
          <TableRow>
            <TableCell><code>reactive_ui_toolkit/runtime/host_node_pool</code></TableCell>
            <TableCell>boolean</TableCell>
            <TableCell><code>true</code></TableCell>
            <TableCell><code>RuitkConfig.host_node_pool</code> — recycle leaf Controls across keyed-list churn.</TableCell>
          </TableRow>
          <TableRow>
            <TableCell><code>reactive_ui_toolkit/runtime/strict_mode</code></TableCell>
            <TableCell>boolean</TableCell>
            <TableCell><code>false</code></TableCell>
            <TableCell><code>RuitkConfig.strict_mode</code> — double-invoke render fns with the first result discarded (see below). Forced off in release builds.</TableCell>
          </TableRow>
          <TableRow>
            <TableCell><code>reactive_ui_toolkit/runtime/hook_validation</code></TableCell>
            <TableCell>enum</TableCell>
            <TableCell><code>auto</code></TableCell>
            <TableCell><code>RuitkConfig.enable_hook_validation</code> — rules-of-hooks checks.</TableCell>
          </TableRow>
          <TableRow>
            <TableCell><code>reactive_ui_toolkit/runtime/strict_diagnostics</code></TableCell>
            <TableCell>enum</TableCell>
            <TableCell><code>auto</code></TableCell>
            <TableCell><code>RuitkConfig.enable_strict_diagnostics</code> — misuse warnings: state updates during render and missing dependency arrays.</TableCell>
          </TableRow>
          <TableRow>
            <TableCell><code>reactive_ui_toolkit/runtime/environment</code></TableCell>
            <TableCell>enum</TableCell>
            <TableCell><code>auto</code></TableCell>
            <TableCell><code>RuitkConfig.environment</code> — <code>auto</code> / <code>development</code> / <code>production</code>; a read-only label for your components (see below).</TableCell>
          </TableRow>
          <TableRow>
            <TableCell><code>reactive_ui_toolkit/diagnostics/trace_level</code></TableCell>
            <TableCell>enum</TableCell>
            <TableCell><code>none</code></TableCell>
            <TableCell><code>RuitkDiagnostics.trace_level</code> — <code>none</code> / <code>basic</code> / <code>verbose</code> trace ladder (see below).</TableCell>
          </TableRow>
          <TableRow>
            <TableCell><code>reactive_ui_toolkit/diagnostics/diff_tracing</code></TableCell>
            <TableCell>boolean</TableCell>
            <TableCell><code>false</code></TableCell>
            <TableCell><code>RuitkDiagnostics.diff_tracing</code> — reconciler diff-decision logs, independent of the trace ladder (also on whenever <code>trace_level</code> is <code>verbose</code>).</TableCell>
          </TableRow>
          <TableRow>
            <TableCell><code>reactive_ui_toolkit/diagnostics/enabled</code></TableCell>
            <TableCell>boolean</TableCell>
            <TableCell><code>false</code></TableCell>
            <TableCell><code>RuitkDiagnostics.enabled</code> — count renders, commits, placements, updates, deletions. <strong>(Godot-only)</strong></TableCell>
          </TableRow>
          <TableRow>
            <TableCell><code>reactive_ui_toolkit/diagnostics/capture</code></TableCell>
            <TableCell>boolean</TableCell>
            <TableCell><code>false</code></TableCell>
            <TableCell><code>RuitkDiagnostics.capture</code> — record diagnostic messages for tests / overlays. <strong>(Godot-only)</strong></TableCell>
          </TableRow>
        </TableBody>
      </Table>
    </TableContainer>
    <Typography variant="body2" paragraph>
      The two validator <code>enum</code> settings are tri-states: <code>auto</code>{' '}
      keeps the compiled <code>OS.is_debug_build()</code> default (on while
      developing, off in exported release builds); <code>enabled</code> /{' '}
      <code>disabled</code> force the flag regardless of build type. The two{' '}
      <strong>(Godot-only)</strong> keys are leg-specific extras — the Unity and
      Unreal legs of the family don&apos;t have them.
    </Typography>

    {/* ── Strict mode / environment / trace ladder ──────────────────────── */}
    <Typography variant="h6" component="h3" sx={Styles.section}>
      Strict mode
    </Typography>
    <Typography variant="body2" paragraph>
      Opt-in (<code>strict_mode</code>, default off): every component render
      function runs <strong>twice</strong> per pass with the first result
      discarded — React StrictMode&apos;s impure-render flusher (hidden state in a
      render body surfaces as a visible double effect), and hook-order validation
      catches shape bugs on the <em>first</em> render. Effects are{' '}
      <strong>not</strong> double-invoked and diagnostics count the render once.
      It is <strong>forced off in exported release builds</strong> regardless of
      the stored setting — the read surface is{' '}
      <code>RuitkConfig.strict_mode_effective()</code>; the stored value
      round-trips untouched.
    </Typography>
    <Typography variant="h6" component="h3" sx={Styles.section}>
      Environment label
    </Typography>
    <Typography variant="body2" paragraph>
      <code>environment</code> is a <strong>read-only surface for your
      components</strong> — call <code>RuitkConfig.environment_resolved()</code>{' '}
      to get <code>&quot;development&quot;</code> or{' '}
      <code>&quot;production&quot;</code> (<code>auto</code> resolves off{' '}
      <code>OS.is_debug_build()</code>; explicit values pass through), e.g. to
      gate a debug overlay. The library itself never branches on it.
    </Typography>
    <Typography variant="h6" component="h3" sx={Styles.section}>
      Trace ladder &amp; diff tracing
    </Typography>
    <Typography variant="body2" paragraph>
      <code>trace_level</code> is a ladder: <code>basic</code> logs{' '}
      <strong>structural</strong> events only (placements, deletions, node
      replacements, commit summaries); <code>verbose</code> adds per-element
      updates, portal retargets, component render entries, and per-hook detail.{' '}
      <code>diff_tracing</code> is an <strong>independent</strong> switch for the
      reconciler&apos;s diff-decision logs (bailout taken/skipped,
      reuse-vs-replace, keyed-list match decisions): it fires on its own at any
      trace level, and <code>verbose</code> lights it too. With everything off
      the cost is a single comparison per site. Output goes to the console and —
      when <code>diagnostics/capture</code> is on — into{' '}
      <code>RuitkDiagnostics.messages</code>.
    </Typography>

    {/* ── VS Code / editor settings ─────────────────────────────────────── */}
    <Typography variant="h5" component="h2" sx={Styles.section}>
      Editor Extension Settings
    </Typography>
    <Typography variant="body2" paragraph>
      The GUITKX language extension provides syntax highlighting and language
      intelligence for <code>.guitkx</code> markup, plus headless{' '}
      <code>gdscript-analyzer</code> intelligence for the embedded GDScript — no
      running Godot editor required. These settings live under the{' '}
      <code>guitkx.*</code> namespace.
    </Typography>
    <TableContainer>
      <Table size="small" sx={Styles.table}>
        <TableHead>
          <TableRow>
            <TableCell>Setting</TableCell>
            <TableCell>Type</TableCell>
            <TableCell>Default</TableCell>
            <TableCell>Description</TableCell>
          </TableRow>
        </TableHead>
        <TableBody>
          <TableRow>
            <TableCell><code>guitkx.enableEmbeddedAnalysis</code></TableCell>
            <TableCell>boolean</TableCell>
            <TableCell><code>true</code></TableCell>
            <TableCell>
              Provide completion, hover, and go-to-definition for embedded
              GDScript (<code>{'{expr}'}</code> and setup blocks) via the
              in-process <code>gdscript-analyzer</code>.
            </TableCell>
          </TableRow>
          <TableRow>
            <TableCell><code>guitkx.enableGdscriptAnalysis</code></TableCell>
            <TableCell>boolean</TableCell>
            <TableCell><code>true</code></TableCell>
            <TableCell>
              Analyze plain <code>.gd</code> files with{' '}
              <code>gdscript-analyzer</code> (diagnostics, completion, hover,
              navigation, project-wide rename, formatting, semantic highlighting,
              inlay hints, code actions, document symbols) — all headless. Runs
              alongside the <code>godot-tools</code> extension; disable one of the
              two to avoid duplicate diagnostics.
            </TableCell>
          </TableRow>
          <TableRow>
            <TableCell><code>guitkx.useGdformat</code></TableCell>
            <TableCell>boolean</TableCell>
            <TableCell><code>true</code></TableCell>
            <TableCell>
              When <code>gdformat</code> (gdscript-toolkit) is installed, also
              reflow the embedded GDScript when formatting a{' '}
              <code>.guitkx</code>. Safe: any change beyond whitespace / quote
              style is rejected, so it never alters code semantics. Markup
              formatting works regardless.
            </TableCell>
          </TableRow>
        </TableBody>
      </Table>
    </TableContainer>
    <Typography variant="body2" paragraph>
      The extension also contributes a <strong>GUITKX: Restart Language
      Server</strong> command (<code>guitkx.restartLanguageServer</code>) for
      recovering from a stuck analyzer.
    </Typography>

    {/* ── Editor defaults for [guitkx] ─────────────────────────────────── */}
    <Typography variant="h5" component="h2" sx={Styles.section}>
      Editor Defaults
    </Typography>
    <Typography variant="body2" paragraph>
      The extension automatically applies these editor defaults to{' '}
      <code>.guitkx</code> files. Canonical <code>.guitkx</code> formatting is{' '}
      <strong>2-space indentation</strong> (Unity-exact, matching the shipped
      samples); the compiler&apos;s reindent is depth-based, so tab-indented
      sources still compile.
    </Typography>
    <TableContainer>
      <Table size="small" sx={Styles.table}>
        <TableHead>
          <TableRow>
            <TableCell>Setting</TableCell>
            <TableCell>Value</TableCell>
            <TableCell>Reason</TableCell>
          </TableRow>
        </TableHead>
        <TableBody>
          <TableRow>
            <TableCell><code>editor.defaultFormatter</code></TableCell>
            <TableCell><code>ReactiveUITK.guitkx</code></TableCell>
            <TableCell>Uses the GUITKX formatter for <code>.guitkx</code> files</TableCell>
          </TableRow>
          <TableRow>
            <TableCell><code>editor.formatOnSave</code></TableCell>
            <TableCell><code>true</code></TableCell>
            <TableCell>Auto-format on save (recommended)</TableCell>
          </TableRow>
          <TableRow>
            <TableCell><code>editor.insertSpaces</code></TableCell>
            <TableCell><code>true</code></TableCell>
            <TableCell>Spaces, matching the 2-space canonical indent</TableCell>
          </TableRow>
          <TableRow>
            <TableCell><code>editor.tabSize</code></TableCell>
            <TableCell><code>2</code></TableCell>
            <TableCell>Visual width of one indent level</TableCell>
          </TableRow>
          <TableRow>
            <TableCell><code>editor.autoIndent</code></TableCell>
            <TableCell><code>full</code></TableCell>
            <TableCell>Full auto-indent for nested markup + embedded code</TableCell>
          </TableRow>
          <TableRow>
            <TableCell><code>editor.detectIndentation</code></TableCell>
            <TableCell><code>false</code></TableCell>
            <TableCell>Do not override the 2-space default from file content</TableCell>
          </TableRow>
        </TableBody>
      </Table>
    </TableContainer>

    {/* ── guitkx.config.json ───────────────────────────────────────────── */}
    <Typography variant="h5" component="h2" sx={Styles.section}>
      Project configuration (<code>guitkx.config.json</code>)
    </Typography>
    <Typography variant="body2" paragraph>
      Drop a <code>guitkx.config.json</code> at or above the file (a
      Prettier-style walk-up — the <strong>nearest</strong> one found, walking up
      to the project root, wins; configs are <strong>not merged</strong>, so a
      formatter-only config in a subdirectory shadows an ancestor that set{' '}
      <code>root</code>). No file is needed; the defaults apply when none is
      found. Unknown keys are ignored, and a malformed file falls back to the
      defaults.
    </Typography>
    <CodeBlock language="json" code={GUITKX_CONFIG} />
    <Typography variant="h6" component="h3" sx={Styles.section}>
      <code>root</code> — the <code>~/</code> import root (0.10.0)
    </Typography>
    <Typography variant="body2" paragraph>
      The top-level <code>root</code> key sets the project UI source root that{' '}
      <code>~/</code> import specifiers (and <code>~/</code> asset paths in{' '}
      <code>@uss</code>/<code>@theme</code>) resolve against. Default:{' '}
      <code>res://</code>. A <code>res://…</code> value is used verbatim; any
      other value is taken relative to the config file&apos;s own directory. With{' '}
      <code>{'"root": "res://ui"'}</code>, the specifier <code>~/cards/badge</code>{' '}
      resolves to <code>res://ui/cards/badge.guitkx</code>. See the Imports &amp;
      Exports page.
    </Typography>
    <Typography variant="h6" component="h3" sx={Styles.section}>
      <code>formatter</code>
    </Typography>
    <TableContainer>
      <Table size="small" sx={Styles.table}>
        <TableHead>
          <TableRow>
            <TableCell>Key</TableCell>
            <TableCell>Default</TableCell>
            <TableCell>Meaning</TableCell>
          </TableRow>
        </TableHead>
        <TableBody>
          <TableRow>
            <TableCell><code>printWidth</code></TableCell>
            <TableCell><code>100</code></TableCell>
            <TableCell>Soft column limit; a tag&apos;s attribute list wraps when the single line would exceed it.</TableCell>
          </TableRow>
          <TableRow>
            <TableCell><code>indentStyle</code></TableCell>
            <TableCell><code>"space"</code></TableCell>
            <TableCell>
              <code>"space"</code> or <code>"tab"</code>. The 2-space default is
              Unity-exact and matches the shipped samples; the compiler&apos;s
              depth-based reindent keeps the embedded GDScript correct either
              way.
            </TableCell>
          </TableRow>
          <TableRow>
            <TableCell><code>indentSize</code></TableCell>
            <TableCell><code>2</code></TableCell>
            <TableCell>Spaces per level when <code>indentStyle</code> is <code>"space"</code> (ignored for tabs).</TableCell>
          </TableRow>
          <TableRow>
            <TableCell><code>singleAttributePerLine</code></TableCell>
            <TableCell><code>false</code></TableCell>
            <TableCell>Force every attribute onto its own line.</TableCell>
          </TableRow>
          <TableRow>
            <TableCell><code>insertSpaceBeforeSelfClose</code></TableCell>
            <TableCell><code>true</code></TableCell>
            <TableCell>Emit <code>{'<Foo />'}</code> (space before <code>{'/>'}</code>) vs <code>{'<Foo/>'}</code>.</TableCell>
          </TableRow>
        </TableBody>
      </Table>
    </TableContainer>
  </Box>
)
