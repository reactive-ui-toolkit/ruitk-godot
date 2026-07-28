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
} from '@mui/material'
import { CodeBlock } from '../../../components/CodeBlock/CodeBlock'
import Styles from '../../GettingStarted/GettingStartedPage.style'
import {
  EXAMPLE_UITKX,
  EXAMPLE_GENERATED_CLASS,
  EXAMPLE_DIRECTORY,
  EXAMPLE_MIXED,
  EXAMPLE_HOOKS,
  EXAMPLE_STYLES,
  EXAMPLE_UTILS,
  EXAMPLE_CLASS_NAME,
  EXAMPLE_STANDALONE,
} from './CompanionFilesPage.example'

export const CompanionFilesPage: FC = () => (
  <Box sx={Styles.root}>
    <Typography variant="h4" component="h1" gutterBottom>
      Files &amp; Modules
    </Typography>
    <Typography variant="body1" paragraph>
      Since 0.11.0, <strong>a <code>.guitkx</code> file IS a module</strong> — the ES-module model.
      A file holds any number of plain top-level declarations (components, hooks, utils, values,
      in any mix), <code>export</code> is the only visibility mechanism, and every file compiles to
      a <strong>sibling <code>.gd</code> class</strong> — <code>class_name</code>,{' '}
      <code>extends RefCounted</code>, and a static member per declaration.
    </Typography>
    <Typography variant="body1" paragraph>
      There are no wrapper keywords: what a declaration <em>is</em> is read from its signature
      alone. <code>Name(params) {'-> RuitkVNode { … }'}</code> is a component, a{' '}
      <code>use_</code>-prefixed callable is a hook, any other callable is a util, and{' '}
      <code>name := expr</code> is a value.
    </Typography>

    <Typography variant="h5" component="h2" gutterBottom>
      Per-file scope &amp; export
    </Typography>
    <Typography variant="body1" paragraph>
      Every declaration is scoped to its file. Prefixing it with <code>export</code> makes it
      importable from other files; without <code>export</code> it is <strong>file-private</strong> —
      unreachable cross-file, invisible to imports, and free to be renamed or deleted without
      breaking anyone. One file may mix all four kinds:
    </Typography>
    <CodeBlock language="jsx" code={EXAMPLE_MIXED} />
    <Typography variant="body2" paragraph>
      Values compile to <code>static var</code> on the generated class (GDScript cannot verify
      constant-foldability at parse time, so <code>const</code> is not an option) —{' '}
      <strong>treat them as constants</strong>; mutating an imported value is undefined behavior
      across hot-reloads.
    </Typography>

    <Typography variant="h5" component="h2" gutterBottom>
      Binding identity &amp; <code>@class_name</code>
    </Typography>
    <Typography variant="body1" paragraph>
      The generated class needs one global <code>class_name</code> (GDScript has no namespaces).
      That <strong>binding</strong> is inferred: an <code>@class_name</code> override if present,
      else the <strong>first exported declaration&apos;s name</strong>, else the first
      declaration&apos;s name. For most files you never think about it — the file&apos;s main
      exported component names the class.
    </Typography>
    <Typography variant="body1" paragraph>
      <code>@class_name</code> remains as the <strong>binding / interop escape hatch</strong>: it
      pins the class name explicitly, which is exactly how pre-0.11 <code>module M {'{ … }'}</code>{' '}
      files migrate — members hoist to top level and <code>@class_name M</code> keeps the global
      identity, so hand-written <code>M.member(...)</code> callers keep working unchanged:
    </Typography>
    <CodeBlock language="jsx" code={EXAMPLE_CLASS_NAME} />

    <Typography variant="h5" component="h2" gutterBottom>
      A component file and its neighbors
    </Typography>
    <Typography variant="body1" paragraph>
      Splitting a feature across sibling files is a convention, not a mechanism — each file is just
      a module. Here is a component that imports hooks, styles, and utilities from its neighbors:
    </Typography>
    <CodeBlock language="jsx" code={EXAMPLE_UITKX} />

    <Typography variant="h5" component="h2" gutterBottom>
      Generated class
    </Typography>
    <Typography variant="body1" paragraph>
      On save, the plugin creates a sibling GDScript class from the <code>.guitkx</code> file. For
      the example above, the generator produces:
    </Typography>
    <CodeBlock language="gdscript" code={EXAMPLE_GENERATED_CLASS} />

    <Typography variant="h5" component="h2" gutterBottom>
      Directory layout
    </Typography>
    <Typography variant="body1" paragraph>
      Each source produces one sibling <code>.gd</code>. The dotted suffixes (
      <code>.hooks.</code>, <code>.style.</code>, <code>.utils.</code>) are naming conventions
      only — the compiler treats every <code>.guitkx</code> identically:
    </Typography>
    <CodeBlock language="jsx" code={EXAMPLE_DIRECTORY} />

    <Typography variant="h5" component="h2" gutterBottom>
      What goes in which file
    </Typography>
    <TableContainer component={Paper} variant="outlined" sx={{ mb: 2 }}>
      <Table size="small">
        <TableHead>
          <TableRow>
            <TableCell><strong>File</strong></TableCell>
            <TableCell><strong>Typical declarations</strong></TableCell>
            <TableCell><strong>Purpose</strong></TableCell>
          </TableRow>
        </TableHead>
        <TableBody>
          <TableRow>
            <TableCell><code>MyComponent.guitkx</code></TableCell>
            <TableCell>components (<code>{'-> RuitkVNode'}</code>)</TableCell>
            <TableCell>UI markup + setup code</TableCell>
          </TableRow>
          <TableRow>
            <TableCell><code>MyComponent.hooks.guitkx</code></TableCell>
            <TableCell>hooks (<code>use_*</code>)</TableCell>
            <TableCell>Custom hooks — reusable state logic</TableCell>
          </TableRow>
          <TableRow>
            <TableCell><code>MyComponent.style.guitkx</code></TableCell>
            <TableCell>values (<code>name := …</code>)</TableCell>
            <TableCell>Style dictionaries, colours, sizes</TableCell>
          </TableRow>
          <TableRow>
            <TableCell><code>MyComponent.utils.guitkx</code></TableCell>
            <TableCell>utils + values</TableCell>
            <TableCell>Pure helper / formatting functions and shared constants</TableCell>
          </TableRow>
        </TableBody>
      </Table>
    </TableContainer>
    <Typography variant="body2" paragraph>
      What <em>is</em> enforced is the wiring: mark a declaration <code>export</code> and{' '}
      <code>import</code> it where it&apos;s used (see the Imports &amp; Exports page) — an implicit
      cross-file reference is a compile error that tells you the exact import to add.
    </Typography>

    <Typography variant="h5" component="h2" gutterBottom>
      Hooks — reusable state logic
    </Typography>
    <Typography variant="body1" paragraph>
      A hook is any top-level callable whose name starts with <code>use_</code> — the prefix is the
      classification, no keyword involved. Hook bodies are pure GDScript — they can call{' '}
      <code>Hooks.useState</code>, <code>Hooks.useEffect</code>, <code>Hooks.useMemo</code>, and any
      other built-in hook. Use <code>{'-> ReturnType'}</code> to declare the return type:
    </Typography>
    <CodeBlock language="jsx" code={EXAMPLE_HOOKS} />

    <Typography variant="h5" component="h2" gutterBottom>
      Values — styles and constants
    </Typography>
    <Typography variant="body1" paragraph>
      Value exports gather styles, colours, and sizes. Import a value file as a namespace (
      <code>import * as PlayerCardStyle from &quot;./PlayerCard.style&quot;</code>) to keep the
      familiar dotted access:
    </Typography>
    <CodeBlock language="jsx" code={EXAMPLE_STYLES} />

    <Typography variant="h5" component="h2" gutterBottom>
      Utils — helper functions
    </Typography>
    <CodeBlock language="jsx" code={EXAMPLE_UTILS} />

    <Typography variant="h5" component="h2" gutterBottom>
      Standalone shared files
    </Typography>
    <Typography variant="body1" paragraph>
      Not everything has to be tied to a component. A standalone file of value exports is useful
      for constants shared across multiple components:
    </Typography>
    <CodeBlock language="jsx" code={EXAMPLE_STANDALONE} />

    <Typography variant="h5" component="h2" gutterBottom>
      File renames are semantic
    </Typography>
    <Typography variant="body1" paragraph>
      Because a file&apos;s <strong>identity is its path</strong>, renaming a file changes module
      identity: importers&apos; specifiers must update (the editor addon cleans up the old outputs
      and the next sweep flags stale specifiers with <code>GUITKX2300</code>), and the hot-reload
      identity of its file-private members changes too — their state resets on the next reload.
      These are accepted, documented semantics of the file-as-module model.
    </Typography>

    <Typography variant="h5" component="h2" gutterBottom>
      Compile &amp; hot-reload
    </Typography>
    <List>
      <ListItem disablePadding>
        <ListItemText primary="The editor plugin watches EditorFileSystem. When you save a .guitkx file, it compiles the source to its sibling .gd (Foo.guitkx → Foo.gd)." />
      </ListItem>
      <ListItem disablePadding>
        <ListItemText
          primary={
            <>
              While the game is running under <strong>F5</strong>, that compile also drives{' '}
              <strong>Fast Refresh</strong>: the generated script reloads in place and the
              runtime re-renders exactly the components whose script changed — hook state
              survives unless the edit changed a component&apos;s hook-call shape, which is a
              deliberate reset.
            </>
          }
        />
      </ListItem>
      <ListItem disablePadding>
        <ListItemText
          primary={
            <>
              A file of hooks, utils, or values reloads the same way, but since any component may
              call into it, editing one triggers a <em>global</em> re-render — every mounted
              component re-runs (state preserved), not just the one file that changed.
            </>
          }
        />
      </ListItem>
      <ListItem disablePadding>
        <ListItemText primary="A diagnostics sidecar (Foo.guitkx.diags.json) is written alongside the .gd; the IDE tooling reads it for errors and warnings." />
      </ListItem>
      <ListItem disablePadding>
        <ListItemText primary="Generated .gd files are marked AUTO-GENERATED … do not edit — edit the .guitkx source and let the plugin regenerate." />
      </ListItem>
    </List>
    <Typography variant="body2" paragraph sx={{ mt: 1 }}>
      Fast Refresh only runs while a play session is attached to the editor (F5) — see{' '}
      <strong>Hot Reload (Fast Refresh)</strong> under Tooling for the full mechanism, the
      per-hook state table, and its limitations.
    </Typography>

    <Typography variant="h5" component="h2" gutterBottom>
      When not to split files
    </Typography>
    <List>
      <ListItem disablePadding>
        <ListItemText primary="Simple components — if a component has no shared styles or types, one file with one declaration is perfect." />
      </ListItem>
      <ListItem disablePadding>
        <ListItemText
          primary={
            <>
              Small helpers — for code that only one component uses, prefer a file-private util (no{' '}
              <code>export</code>) in the same file, or plain setup code before{' '}
              <code>return ()</code>.
            </>
          }
        />
      </ListItem>
    </List>
  </Box>
)
