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
import Styles from './HmrPage.style'

const Section: FC<{ title: string; children: React.ReactNode }> = ({ title, children }) => (
  <Box>
    <Typography variant="h5" component="h2" gutterBottom>
      {title}
    </Typography>
    {children}
  </Box>
)

export const HmrPage: FC = () => (
  <Box sx={Styles.root}>
    <Typography variant="h4" component="h1" gutterBottom>
      Hot Reload (Fast Refresh)
    </Typography>
    <Typography variant="body1" paragraph>
      Since <strong>0.8.0</strong>, editing a <code>.guitkx</code> file while your game runs
      under <strong>F5</strong> updates the running UI in place — new markup and logic appear
      within a couple of seconds, and <strong>hook state is preserved</strong>: a counter keeps
      its count while you restyle its label. Editing while only the editor is open keeps the
      generated scripts fresh for the next run, exactly as before.
    </Typography>
    <Alert severity="info" sx={{ mb: 1 }}>
      Godot&apos;s built-in &quot;Synchronize Script Changes&quot; can not drive this: it only
      fires for scripts saved in the <em>built-in</em> script editor, never for files written
      by a compiler (godot#72825). The library therefore ships its own push: the watcher tells
      each running play session exactly which generated <code>.gd</code> files it just
      produced, over the debugger connection that F5 already gives you.
    </Alert>

    <Section title="Quick Start">
      <List sx={Styles.list}>
        <ListItem disablePadding>
          <ListItemText primary={<>Enable the <strong>reactive_ui_toolkit</strong> editor plugin (<strong>Project → Project Settings → Plugins</strong>) and run your game with <strong>F5</strong> (from the editor — that&apos;s what creates the debugger session).</>} />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary={<>Edit and save any <code>.guitkx</code> — from VS Code, the in-Godot editor, anything that writes the file.</>} />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary={<>Watch the Output: <code>[guitkx] compiled -&gt; …</code> then <code>[guitkx] hot-reloaded 1 script(s) -&gt; 1 component(s) re-rendered in 12 ms</code>. The running UI is already showing the change.</>} />
        </ListItem>
      </List>
    </Section>

    <Section title="How It Works">
      <Typography variant="body1" paragraph>
        Two halves, meeting over the debugger protocol:
      </Typography>
      <List sx={Styles.list}>
        <ListItem disablePadding>
          <ListItemText primary={<><strong>Editor:</strong> the watcher (<code>plugin.gd</code>) notices the save (2&nbsp;s poll + filesystem events), compiles <code>Foo.guitkx</code> → sibling <code>Foo.gd</code>, and pushes the paths of everything that compiled <em>and parses</em> to every active play session (<code>editor/hmr_debugger.gd</code>, message <code>rui_hmr:reload</code>). A game is never asked to load a script the engine would reject.</>} />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary={<><strong>Game:</strong> <code>RUIHmr</code> (<code>core/hmr.gd</code>) reloads each script <em>in place</em> — <code>source_code</code> + <code>reload(keep_state = true)</code> on the same GDScript resource. Method-reference Callables like <code>DemoBox.render</code> keep their identity <em>and</em> dispatch the new code, so the reconciler&apos;s fiber matching still recognises every mounted component — that is why hook state survives.</>} />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary={<><strong>Re-render:</strong> a reload alone changes nothing on screen (the reconciler&apos;s bailout would keep serving its cached output), so the runtime marks exactly the fibers whose component script changed and flushes synchronously — one atomic swap-and-commit inside the debugger callback, no frame where old handlers meet new code.</>} />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary={<><strong>Report:</strong> the game replies with what it did (scripts reloaded, components re-rendered, milliseconds, state resets), printed in the editor Output next to the sweep lines.</>} />
        </ListItem>
      </List>
    </Section>

    <Section title="State Across a Reload">
      <Typography variant="body1" paragraph>
        Reactive state lives in each component&apos;s <code>RUIComponentState</code> (a
        positional array of hook slots) held by the reconciler, <em>not</em> on the script. A
        refresh runs the new <code>render</code> body against the existing slots:
      </Typography>
      <TableContainer component={Paper} variant="outlined" sx={Styles.table}>
        <Table size="small">
          <TableHead>
            <TableRow>
              <TableCell><strong>Hook</strong></TableCell>
              <TableCell><strong>Behaviour after a hot reload</strong></TableCell>
            </TableRow>
          </TableHead>
          <TableBody>
            <TableRow>
              <TableCell><code>useState</code> / <code>useReducer</code></TableCell>
              <TableCell>Current values retained; setter / dispatch identity stable.</TableCell>
            </TableRow>
            <TableRow>
              <TableCell><code>useRef</code></TableCell>
              <TableCell>The <code>{'{ "current": … }'}</code> box is preserved.</TableCell>
            </TableRow>
            <TableRow>
              <TableCell><code>useEffect</code> / <code>useLayoutEffect</code></TableCell>
              <TableCell>Factory refreshed with the new closure; re-runs (after cleanup) when deps change.</TableCell>
            </TableRow>
            <TableRow>
              <TableCell><code>useMemo</code> / <code>useCallback</code></TableCell>
              <TableCell>Recomputed with the new body when deps change; cached value survives otherwise.</TableCell>
            </TableRow>
            <TableRow>
              <TableCell><code>useContext</code></TableCell>
              <TableCell>Stateless — always reflects the latest provider value.</TableCell>
            </TableRow>
            <TableRow>
              <TableCell><code>useSignal</code> / <code>useSignalKey</code></TableCell>
              <TableCell>Subscription persists; re-binds if the signal instance changed.</TableCell>
            </TableRow>
          </TableBody>
        </Table>
      </TableContainer>
      <Alert severity="success" sx={{ mt: 2 }}>
        <strong>Changed hook shape? Deliberate reset, not corruption.</strong> Every compiled
        component embeds its ordered hook-call fingerprint (<code>__RUI_HOOK_SIG</code>). If an
        edit adds, removes, or reorders hooks, the runtime detects the changed fingerprint
        across the reload and <em>resets that component&apos;s state</em> (running its effect
        cleanups first) — React Fast Refresh semantics. Components whose shape did not change
        keep their state.
      </Alert>
    </Section>

    <Section title="Hook, Util & Value Files">
      <List sx={Styles.list}>
        <ListItem disablePadding>
          <ListItemText primary={<><strong>Files of hooks, utils, or values</strong> (e.g. <code>MyComponent.hooks.guitkx</code>) reload the same way — but since any component may call into them, such a change triggers a <em>global</em> re-render (every mounted component re-runs, state preserved).</>} />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary={<><strong>New components</strong> just work: the sweep compiles them, and a running game picks them up the first time something renders them (never-loaded scripts are read fresh from disk).</>} />
        </ListItem>
      </List>
    </Section>

    <Section title="Limitations">
      <TableContainer component={Paper} variant="outlined" sx={Styles.table}>
        <Table size="small">
          <TableHead>
            <TableRow>
              <TableCell><strong>Limitation</strong></TableCell>
              <TableCell><strong>Details</strong></TableCell>
            </TableRow>
          </TableHead>
          <TableBody>
            <TableRow>
              <TableCell>Dev-only by construction</TableCell>
              <TableCell>
                Everything is gated on an attached debugger session
                (<code>EngineDebugger.is_active()</code>). Exported builds and games launched
                outside the editor carry zero HMR behaviour.
              </TableCell>
            </TableRow>
            <TableRow>
              <TableCell>Compile errors keep the last good UI</TableCell>
              <TableCell>
                A <code>GUITKX####</code> error means nothing is pushed for that file — the
                running game keeps its last good code, the dock and VS Code show the error,
                and the next clean save resumes hot reload (state intact).
              </TableCell>
            </TableRow>
            <TableRow>
              <TableCell>Renaming a component remounts it</TableCell>
              <TableCell>A new <code>class_name</code> is a new script — fresh state (same as Unity). The old generated <code>.gd</code> is cleaned up by the next sweep (0.8.1).</TableCell>
            </TableRow>
            <TableRow>
              <TableCell>Brand-new components hot-<em>link</em></TableCell>
              <TableCell>
                Godot registers global <code>class_name</code>s at launch, so a component
                created <em>after</em> F5 is unresolvable by name — the runtime detects this
                and links it by path instead (an injected <code>preload</code> const), keeping
                the session and its state. The Output says
                <code> (1 new component(s) linked live)</code>. Only classes from <em>outside</em>{' '}
                the guitkx pipeline (hand-written <code>class_name</code> scripts added
                mid-run) still need a restart.
              </TableCell>
            </TableRow>
            <TableRow>
              <TableCell><code>static var</code> in hand-written modules</TableCell>
              <TableCell>
                Values are not migrated across reloads (Godot #105667). Generated components
                are statics-free by design, so this only affects hand-written code.
              </TableCell>
            </TableRow>
            <TableRow>
              <TableCell>Latency is poll-dominated</TableCell>
              <TableCell>Save → screen is ≈2–3 s, mostly the watcher&apos;s 2 s poll; the reload + re-render itself is milliseconds.</TableCell>
            </TableRow>
          </TableBody>
        </Table>
      </TableContainer>
    </Section>

    <Section title="Troubleshooting">
      <Typography variant="h6" component="h3" gutterBottom>
        The running game doesn&apos;t update
      </Typography>
      <List sx={Styles.list}>
        <ListItem disablePadding>
          <ListItemText primary={<>The game must be launched with <strong>F5 from the editor</strong> — a standalone run has no debugger session, so there is no channel to push over.</>} />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary={<>Check the Output for the pair of lines: <code>[guitkx] compiled -&gt; …</code> (the sweep) and <code>[guitkx] hot-reloaded …</code> (the game&apos;s report). Compiled but not hot-reloaded usually means the generated script failed the parse check — fix the reported error.</>} />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary={<>No <code>[guitkx] sweep:</code> line at all after the editor starts? The plugin isn&apos;t running — re-enable it in <strong>Project Settings → Plugins</strong>.</>} />
        </ListItem>
      </List>

      <Typography variant="h6" component="h3" gutterBottom sx={{ mt: 2 }}>
        State was lost after an edit
      </Typography>
      <List sx={Styles.list}>
        <ListItem disablePadding>
          <ListItemText primary={<>That&apos;s the deliberate reset: the edit changed the component&apos;s hook shape (the Output line says <code>… (1 state reset: hook shape changed)</code>). Same-shape edits preserve state.</>} />
        </ListItem>
      </List>
    </Section>
  </Box>
)
