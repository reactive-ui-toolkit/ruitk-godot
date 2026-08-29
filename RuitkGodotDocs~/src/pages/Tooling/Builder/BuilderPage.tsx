import type { FC } from 'react'
import {
  Box,
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
import { CodeBlock } from '../../../components/CodeBlock/CodeBlock'
import Styles from './BuilderPage.style'
import { EXAMPLE_MODULE_KINDS, EXAMPLE_LEDGER, EXAMPLE_SAVE } from './BuilderPage.example'

const Section: FC<{ title: string; id?: string; children: React.ReactNode }> = ({
  title,
  id,
  children,
}) => (
  <Box>
    <Typography id={id} variant="h5" component="h2" gutterBottom>
      {title}
    </Typography>
    {children}
  </Box>
)

export const BuilderPage: FC = () => (
  <Box sx={Styles.root}>
    <Typography variant="h4" component="h1" gutterBottom>
      UI Builder
    </Typography>
    <Typography variant="body1" paragraph>
      The <strong>UI Builder</strong> is a visual editor for a whole <code>.guitkx</code> module
      tree, shipped with the <code>reactive_ui_toolkit_editor</code> addon. Open it from{' '}
      <strong>Reactive UI Toolkit &rarr; Builder&hellip;</strong> in the Godot editor&apos;s main
      menu (or <strong>Project &rarr; Tools &rarr; Reactive UI Toolkit Builder&hellip;</strong> if
      the main-menu bar is not available).
    </Typography>
    <Typography variant="body1" paragraph>
      It shows every module of a tree as a card on an infinite canvas, with the imports between them
      drawn as edges. Cards are not thumbnails &mdash; each one lists the module&apos;s real
      structure: its imports, its signature, its markup tree, its exports. You edit the structure by
      dragging on the card, and the file underneath changes.
    </Typography>
    <Alert severity="info">
      The builder edits <code>.guitkx</code> source and nothing else. There is no builder-only
      project file, no scene format, and no round-trip loss: what it writes is the same text you
      would have typed, formatted by the same formatter the editor and VS Code use. A file the
      builder has touched is an ordinary <code>.guitkx</code> file.
    </Alert>

    <Section title="The tree, not the file" id="tree">
      <Typography variant="body1" paragraph>
        The builder opens a <strong>module tree</strong>: the module you focused plus everything it
        imports, transitively, plus everything in its folder. That is the unit a screen is actually
        built from, and it is why the canvas can draw import edges at all.
      </Typography>
      <CodeBlock language="gdscript" code={EXAMPLE_MODULE_KINDS} />
      <Typography variant="body1" paragraph>
        All five module kinds appear on the canvas, each with its own badge tint and the card
        sections that make sense for it &mdash; a style module shows its exports, a component shows
        its markup tree.
      </Typography>
      <Alert severity="warning" sx={{ mb: 2 }}>
        Modules that live under <code>addons/</code> open <strong>read-only</strong>. A package you
        installed is not yours to rewrite, and a builder that silently edited one would produce a
        diff you did not author and an upgrade that clobbers it.
      </Alert>
    </Section>

    <Section title="The window" id="window">
      <TableContainer component={Paper} sx={Styles.table}>
        <Table size="small">
          <TableHead>
            <TableRow>
              <TableCell>Surface</TableCell>
              <TableCell>What it is for</TableCell>
            </TableRow>
          </TableHead>
          <TableBody>
            <TableRow>
              <TableCell>
                <strong>Folder pane</strong> (top left)
              </TableCell>
              <TableCell>
                The tree as a file list, grouped by folder. Click to focus a module; double-click to
                centre its card.
              </TableCell>
            </TableRow>
            <TableRow>
              <TableCell>
                <strong>Library pane</strong> (bottom left)
              </TableCell>
              <TableCell>
                What can be dropped: host elements, hooks, and the tree&apos;s own components. The
                vocabulary is the compiler&apos;s &mdash; host tags come from the same{' '}
                <code>vocabulary.json</code> the language server reads &mdash; so the palette and the
                compiler can never disagree. Searchable; a curated few lead each section and the rest
                fold away.
              </TableCell>
            </TableRow>
            <TableRow>
              <TableCell>
                <strong>Canvas</strong> (middle)
              </TableCell>
              <TableCell>
                The cards and the import edges. Pan with drag, zoom with the wheel,{' '}
                <strong>Fit</strong> frames everything. Cards render at three levels of detail as you
                zoom out, so a forty-module tree stays legible.
              </TableCell>
            </TableRow>
            <TableRow>
              <TableCell>
                <strong>Source pane</strong> (right)
              </TableCell>
              <TableCell>
                The focused module&apos;s text, in the same editor component the in-Godot{' '}
                <code>.guitkx</code> editor uses &mdash; highlighting, completion, diagnostics.
                Typing here and dragging on the canvas are the same edit path.
              </TableCell>
            </TableRow>
            <TableRow>
              <TableCell>
                <strong>Console</strong> (bottom middle)
              </TableCell>
              <TableCell>
                Compiler diagnostics for every module in the tree, live. Click a row to jump to the
                module that raised it.
              </TableCell>
            </TableRow>
          </TableBody>
        </Table>
      </TableContainer>
      <Typography variant="body1" paragraph>
        Right-clicking a card offers <strong>Open</strong>, <strong>Rename&hellip;</strong> and{' '}
        <strong>Delete</strong>; right-clicking empty canvas offers <strong>Fit to view</strong>.
        Card positions are remembered per tree, keyed by the tree&apos;s membership rather than by a
        file path, so adding a module does not scramble a layout you arranged.
      </Typography>
    </Section>

    <Section title="Editing" id="editing">
      <Typography variant="body1" paragraph>
        Drag an element from the library onto a card and the drop lands in one of three bands on the
        row under the pointer &mdash; <strong>before</strong> it, <strong>inside</strong> it, or{' '}
        <strong>after</strong> it. Dragging a row within a card moves the subtree; dragging one card
        onto another moves the module into that folder.
      </Typography>
      <Typography variant="body1" paragraph>
        Attributes, directive headers (<code>@if</code>, <code>@for</code>, <code>@while</code>,{' '}
        <code>@match</code>) and module names are edited in a single floating inline editor over the
        card. The builder refuses a placement it cannot express rather than writing markup that will
        not compile &mdash; a directive body holds exactly one root, so a sibling drop inside one is
        declined with the reason, not attempted and then reported as <code>GUITKX0108</code>.
      </Typography>
      <Typography variant="body1" paragraph>
        Dropping a component from another module adds the <code>import</code> it needs, in the same
        edit. Renaming a module rewrites the specifier in every file that imports it.
      </Typography>
    </Section>

    <Section title="Undo, save, abort" id="save">
      <Typography variant="body1" paragraph>
        Every change &mdash; a keystroke in the source pane, a drop on the canvas, a rename &mdash;
        goes through one funnel and lands in one <strong>ledger</strong>. Consecutive typing merges
        into a single entry; a gesture that touched two files is one entry containing both.
      </Typography>
      <CodeBlock language="gdscript" code={EXAMPLE_LEDGER} />
      <CodeBlock language="gdscript" code={EXAMPLE_SAVE} />
      <Alert severity="info" sx={{ mb: 2 }}>
        Unsaved work is written to a <strong>crash journal</strong> under <code>user://</code> every
        few seconds, and only while there is unsaved work. If the editor dies, the next open offers
        the tree back. The journal is removed on save and on abort, so its presence means exactly one
        thing.
      </Alert>
      <Typography variant="body1" paragraph>
        A module you created and left empty does not block a save: it stays pending and the console
        says so. Deleting it is your call, and refusing the whole save over one blank file would hold
        every other change hostage to that decision.
      </Typography>
    </Section>

    <Section title="Live preview" id="preview">
      <Typography variant="body1" paragraph>
        The builder compiles as you edit, without writing to your project. Dirty buffers are mirrored
        into a scratch folder, compiled there, and the diagnostics come back to the console &mdash;
        so a module that does not compile yet costs you nothing, and your working tree never holds a
        half-finished generated <code>.gd</code>.
      </Typography>
      <Typography variant="body1" paragraph>
        The round is debounced, and it recompiles only what the change can reach: the module you
        edited, and the importers whose meaning depends on it.
      </Typography>
    </Section>

    <Section title="Notes" id="notes">
      <Box component="ul" sx={Styles.list}>
        <li>
          Requires the <code>reactive_ui_toolkit_editor</code> plugin enabled (Project Settings
          &rarr; Plugins). The runtime addon needs no plugin; the builder is editor tooling.
        </li>
        <li>
          <strong>Format on save</strong> follows the addon setting the <code>.guitkx</code> editor
          uses, and honours a <code>guitkx.config.json</code> walk-up file.
        </li>
        <li>
          Deletions go to the OS trash. Godot has no asset database, so a rename carries the
          module&apos;s companions (<code>.uid</code>, <code>.diags.json</code>, the generated{' '}
          <code>.gd</code> and its <code>.uid</code>) itself.
        </li>
        <li>
          No multi-select and no auto-layout &mdash; deliberately. The builder matches the Unity
          leg&apos;s surface so a team working across both engines learns one tool.
        </li>
      </Box>
    </Section>
  </Box>
)
