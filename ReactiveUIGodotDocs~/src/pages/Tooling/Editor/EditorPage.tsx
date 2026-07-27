import type { FC } from 'react'
import {
  Box,
  List,
  ListItem,
  ListItemText,
  Typography,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableRow,
  Paper,
  Alert,
} from '@mui/material'
import Styles from './EditorPage.style'

const Section: FC<{ title: string; children: React.ReactNode }> = ({ title, children }) => (
  <Box>
    <Typography variant="h5" component="h2" gutterBottom>
      {title}
    </Typography>
    {children}
  </Box>
)

export const EditorPage: FC = () => (
  <Box sx={Styles.root}>
    <Typography variant="h4" component="h1" gutterBottom>
      In-Godot Editor (reactive_ui_editor)
    </Typography>
    <Typography variant="body1" paragraph>
      The <strong>reactive_ui_editor</strong> addon puts a full <code>.guitkx</code> editor
      inside Godot itself — a main-screen tab with syntax highlighting, live compiler
      diagnostics, completion, hover, navigation, refactoring, project-wide search, and
      formatting. Double-clicking a <code>.guitkx</code> in the FileSystem dock opens it there.
      If you prefer VS Code, everything here also exists in the external extension — the two
      share the same compiler, formatter, and diagnostic codes, so a project behaves
      identically in both.
    </Typography>
    <Alert severity="info" sx={{ mb: 1 }}>
      The editor addon <em>depends on</em> the runtime addon: enable{' '}
      <strong>reactive_ui</strong> first, then <strong>reactive_ui_editor</strong>{' '}
      (<strong>Project → Project Settings → Plugins</strong>). With the dependency missing or
      outdated the editor addon disables itself and tells you why, instead of erroring.
    </Alert>

    <Section title="What You Get">
      <TableContainer component={Paper} variant="outlined" sx={Styles.table}>
        <Table size="small">
          <TableHead>
            <TableRow>
              <TableCell><strong>Area</strong></TableCell>
              <TableCell><strong>Details</strong></TableCell>
            </TableRow>
          </TableHead>
          <TableBody>
            <TableRow>
              <TableCell>Highlighting</TableCell>
              <TableCell>
                Theme-matched colours (follows your GDScript editor theme). Host elements and
                your components are distinguished the way Godot splits engine vs user classes;
                embedded <code>{'{expr}'}</code> GDScript gets real keyword/string/number
                colouring.
              </TableCell>
            </TableRow>
            <TableRow>
              <TableCell>Diagnostics</TableCell>
              <TableCell>
                The debounced live compile squiggles <code>GUITKX####</code> errors and
                warnings with gutter icons; clicking the gutter shows the full message
                (including did-you-mean suggestions). The Problems bottom panel lists the
                current file or — via its scope switch — every diagnostic in the project,
                aggregated from the compile sidecars; activating a row jumps to it.
              </TableCell>
            </TableRow>
            <TableRow>
              <TableCell>Completion</TableCell>
              <TableCell>
                Tags (<code>&lt;</code>), attributes (space; snippet-shaped —{' '}
                <code>text=&quot;&quot;</code> lands with the caret inside the quotes),
                attribute values (enum names, <code>true/false</code>, style-dict keys),
                directives (<code>@</code>), <code>Color.</code>-style builtin constants, and
                hook names. Events offer both spellings: <code>on</code> +
                PascalCase(signal name) (<code>onPressed</code>) and the verbatim{' '}
                <code>on_&lt;signal&gt;</code> escape hatch.
              </TableCell>
            </TableRow>
            <TableRow>
              <TableCell>Hover &amp; signature help</TableCell>
              <TableCell>
                Rich tooltips for tags, attributes, directives, and hooks; diagnosed lines show
                their message on hover. Inside an event-handler lambda&apos;s parameter list a
                signature strip shows the bound Godot signal&apos;s parameters, tracking the
                active one as you type.
              </TableCell>
            </TableRow>
            <TableRow>
              <TableCell>Navigation</TableCell>
              <TableCell>
                Ctrl+Click a component tag to jump to its definition (hooks jump into{' '}
                <code>hooks.gd</code>); Shift+F12 lists every reference in a References panel;
                Ctrl+G goes to a line; the outline tree (left pane) jumps to any declaration.
              </TableCell>
            </TableRow>
            <TableRow>
              <TableCell>Rename</TableCell>
              <TableCell>
                F2 renames a component across the whole project — open buffers and files on
                disk — and refuses collisions (host tags, existing components, global classes)
                instead of corrupting.
              </TableCell>
            </TableRow>
            <TableRow>
              <TableCell>Find / Replace / Search</TableCell>
              <TableCell>
                Ctrl+F find with match counter and case toggle, F3/Shift+F3 stepping, Replace
                and Replace-All (one undo step). The &quot;Search .guitkx&quot; bottom panel
                searches every indexed file in the project — Godot&apos;s built-in Search in
                Files deliberately does not see <code>.guitkx</code> (see Notes below).
              </TableCell>
            </TableRow>
            <TableRow>
              <TableCell>Editing verbs</TableCell>
              <TableCell>
                Ctrl+/ comment toggle, Alt+Up/Down move lines, Ctrl+Shift+D duplicate,
                Ctrl+Shift+K delete line, Ctrl+B bookmark (Ctrl+Shift+B cycles), Ctrl+wheel or
                Ctrl+=/−/0 zoom, word-wrap toggle, Enter between <code>&gt;&lt;/</code> splits
                the tag pair with an indented middle line.
              </TableCell>
            </TableRow>
            <TableRow>
              <TableCell>Multi-file</TableCell>
              <TableCell>
                One editor per open file (undo history, caret, scroll, and dirty state survive
                switching), an open-files list with middle-click close, and full session
                restore across editor restarts. Renames/moves/deletes in the FileSystem dock
                retarget or detach open buffers safely.
              </TableCell>
            </TableRow>
            <TableRow>
              <TableCell>Formatting</TableCell>
              <TableCell>
                The Format button runs the same formatter as the VS Code extension and honours
                the nearest <code>guitkx.config.json</code> (printWidth, indentStyle,
                indentSize, singleAttributePerLine, insertSpaceBeforeSelfClose). Format-on-save
                is a Project Setting.
              </TableCell>
            </TableRow>
            <TableRow>
              <TableCell>New File</TableCell>
              <TableCell>
                The New button creates a <code>.guitkx</code> seeded with a component skeleton
                named after the file.
              </TableCell>
            </TableRow>
          </TableBody>
        </Table>
      </TableContainer>
    </Section>

    <Section title="Settings">
      <Typography variant="body1" paragraph>
        Everything is toggleable under <strong>Project → Project Settings →
        reactive_ui_editor</strong> (basic settings, no Advanced toggle needed): syntax
        highlighting, diagnostics, completion, hover, format-on-save, and whether
        double-clicking a <code>.guitkx</code> opens the in-Godot editor at all (turn{' '}
        <code>open_guitkx_in_editor</code> off if you work exclusively in VS Code). Toggles
        apply live — no plugin reload.
      </Typography>
    </Section>

    <Section title="How It Relates to the Watcher">
      <List sx={Styles.list}>
        <ListItem disablePadding>
          <ListItemText primary={<>Saving from the editor writes ONLY the <code>.guitkx</code> text; the <strong>reactive_ui</strong> watcher owns compiling the sibling <code>.gd</code> — the two never fight over the same file, and a running F5 session hot-reloads as usual.</>} />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary={<>Godot&apos;s own save flows are wired in: Save All and the quit-confirmation dialog include unsaved <code>.guitkx</code> buffers, and pressing Play flushes them first so the game runs what&apos;s on screen.</>} />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary={<>Project-level diagnostics the live compile cannot see — duplicate class bindings (GUITKX2106), dangling component references (GUITKX2107) — come from the watcher&apos;s sidecars and overlay into the editor, hash-gated so they never mis-anchor into an edited buffer.</>} />
        </ListItem>
      </List>
    </Section>

    <Section title="Notes & Limitations">
      <TableContainer component={Paper} variant="outlined" sx={Styles.table}>
        <Table size="small">
          <TableHead>
            <TableRow>
              <TableCell><strong>Note</strong></TableCell>
              <TableCell><strong>Details</strong></TableCell>
            </TableRow>
          </TableHead>
          <TableBody>
            <TableRow>
              <TableCell>Search in Files exclusion</TableCell>
              <TableCell>
                The addon actively keeps <code>guitkx</code> OUT of Godot&apos;s
                text-file extensions: letting the built-in Script editor adopt{' '}
                <code>.guitkx</code> files corrupts its persistence caches (they replay as
                boot errors). The addon&apos;s own &quot;Search .guitkx&quot; panel is the
                replacement.
              </TableCell>
            </TableRow>
            <TableRow>
              <TableCell>Very large files</TableCell>
              <TableCell>
                Above ~150K characters the live compile switches to Save-time only (the
                debounce also adapts to measured compile time), keeping typing responsive.
              </TableCell>
            </TableRow>
            <TableRow>
              <TableCell>Deep expression intelligence</TableCell>
              <TableCell>
                The editor download <strong>bundles the reactive_ui_analyzer GDExtension</strong>{' '}
                (it lands at <code>addons/reactive_ui_analyzer/</code>, loads automatically —
                nothing to enable), so embedded GDScript gets the full type-aware treatment out
                of the box: completion on your typed locals, inferred-type hover,{' '}
                <code>GD:</code> diagnostics at the exact expression, go-to-definition (into the
                buffer or real .gd files), references, buffer-scoped rename, and signature help.
                Still feature-detected — remove the folder (or run a platform without a prebuilt
                binary) and the static tier (builtin constants, hook names) keeps working. Newer
                analyzer builds from the{' '}
                <a href="https://github.com/reactive-ui-toolkit/gdscript-analyzer/releases">
                  gdscript-analyzer releases
                </a>{' '}
                can be dropped over the same folder anytime. Exclude the folder from game export
                presets — it is editor-only tooling.
              </TableCell>
            </TableRow>
          </TableBody>
        </Table>
      </TableContainer>
    </Section>
  </Box>
)
