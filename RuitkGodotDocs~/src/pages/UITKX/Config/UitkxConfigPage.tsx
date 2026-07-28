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
      All configuration options for the GUITKX editor extension and formatter.
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
