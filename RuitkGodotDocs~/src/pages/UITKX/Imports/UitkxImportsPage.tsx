import type { FC } from 'react'
import { Box, Typography, Table, TableBody, TableCell, TableContainer, TableHead, TableRow, Paper } from '@mui/material'
import { CodeBlock } from '../../../components/CodeBlock/CodeBlock'
import Styles from '../../GettingStarted/GettingStartedPage.style'
import {
  EXAMPLE_IMPORT_BASIC,
  EXAMPLE_FORMS,
  EXAMPLE_SPECIFIERS,
  EXAMPLE_EXPORT,
  EXAMPLE_CONFIG,
  EXAMPLE_MIGRATE,
} from './UitkxImportsPage.example'

export const UitkxImportsPage: FC = () => (
  <Box sx={Styles.root}>
    <Typography variant="h4" component="h1" gutterBottom>
      Imports &amp; Exports
    </Typography>
    <Typography variant="body1" paragraph>
      A <code>.guitkx</code> file is a module: it declares the other files it depends on with{' '}
      <code>import</code> lines, and marks what other files may use with <code>export</code>.
      Cross-file resolution is <strong>strict</strong>: referencing another file&apos;s component,
      hook, util, or value without importing it is an error that tells you the exact import to add.
      Since 0.11.0 the import surface is the full ES set — named (with rename), namespace, and
      default imports, plus deferred export lists and a default-export marker.
    </Typography>

    <Typography variant="h5" component="h2" gutterBottom sx={{ mt: 3 }}>
      Importing
    </Typography>
    <Typography variant="body1" paragraph>
      Imports go in the file preamble (before the first declaration), in any order relative to{' '}
      <code>@class_name</code> / <code>@uss</code>:
    </Typography>
    <CodeBlock language="jsx" code={EXAMPLE_IMPORT_BASIC} />
    <Typography variant="body1" paragraph sx={{ mt: 2 }}>
      Specifiers are <strong>relative</strong> (<code>./</code>, <code>../</code>) or{' '}
      <strong>root-aliased</strong> (<code>~/</code>), and always <strong>extensionless</strong>{' '}
      (<code>.guitkx</code> is implied). Engine-native <code>res://</code> / <code>uid://</code> are
      not valid import specifiers — they remain valid in <code>@uss</code> / <code>@theme</code>{' '}
      asset positions, which also accept <code>~/</code>.
    </Typography>
    <CodeBlock language="jsx" code={EXAMPLE_SPECIFIERS} />

    <Typography variant="h5" component="h2" gutterBottom sx={{ mt: 3 }}>
      The import forms
    </Typography>
    <CodeBlock language="jsx" code={EXAMPLE_FORMS} />
    <Typography variant="body1" paragraph sx={{ mt: 2 }}>
      Notes on the newer forms (0.11.0):
    </Typography>
    <Typography component="ul" variant="body2">
      <li>
        <strong>Rename</strong> (<code>{'import { remote as local }'}</code>) binds the local name;
        the diagnostics on the clause (<code>GUITKX2301</code>/<code>2302</code>) validate the{' '}
        <em>remote</em> name. An alias that collides with an in-file declaration or another import
        is <code>GUITKX2325</code>.
      </li>
      <li>
        <strong>Namespace</strong> (<code>import * as X</code>) is <em>one</em> eager preload of the
        target file; members are reached as <code>X.name</code>. It covers values, utils, and hooks
        only — <code>{'<X.Tag/>'}</code> namespace <em>component tags</em> are not supported yet.
      </li>
      <li>
        <strong>Default</strong> (<code>import X from &quot;./x&quot;</code>) binds the
        target&apos;s <code>export default</code> declaration, resolved at compile time and lowered
        per its kind — a default <em>component</em> stays lazy. If the target has no default
        export, that&apos;s <code>GUITKX2326</code> (the message suggests the named-import fix).
      </li>
      <li>
        <strong>Combined</strong> (<code>{'import Def, { a, b as c } from "./x"'}</code> /{' '}
        <code>import Def, * as X from &quot;./x&quot;</code>, 0.11.1) is <em>one</em> declaration
        carrying the default binding plus the named or namespace surface, exactly as in ES. Every
        part lowers independently, and a duplicate binding across the parts (
        <code>{'import a, { b as a }'}</code>) is <code>GUITKX2325</code>.
      </li>
      <li>
        <strong>Re-exports</strong> (<code>{'export { a } from "./x"'}</code>) are{' '}
        <em>not</em> supported — deferred to a later release.
      </li>
    </Typography>

    <Typography variant="h5" component="h2" gutterBottom sx={{ mt: 3 }}>
      Exporting &amp; multiple declarations
    </Typography>
    <Typography variant="body1" paragraph>
      Add <code>export</code> to make a declaration reachable from other files. A single file may
      hold <strong>several</strong> plain top-level declarations — components, hooks, utils, and
      values together. The file&apos;s binding (its generated <code>class_name</code>) is the{' '}
      <code>@class_name</code> override, else the first exported declaration. Declarations without{' '}
      <code>export</code> are file-private. Besides the inline prefix, a top-level{' '}
      <code>{'export { a, b }'}</code> line exports in-file declarations after the fact, and{' '}
      <code>export default Name</code> marks at most one declaration as the file&apos;s default:
    </Typography>
    <CodeBlock language="jsx" code={EXAMPLE_EXPORT} />

    <Typography variant="h5" component="h2" gutterBottom sx={{ mt: 3 }}>
      Eager vs lazy
    </Typography>
    <TableContainer component={Paper} sx={{ mb: 2 }}>
      <Table size="small">
        <TableHead>
          <TableRow>
            <TableCell>Imported thing</TableCell>
            <TableCell>Lowering</TableCell>
            <TableCell>Cycles</TableCell>
          </TableRow>
        </TableHead>
        <TableBody>
          <TableRow>
            <TableCell>Component (named or default)</TableCell>
            <TableCell><strong>Lazy</strong> — resolved by path at first render (<code>V.comp</code>)</TableCell>
            <TableCell><strong>Legal</strong> — component cycles may reference each other freely</TableCell>
          </TableRow>
          <TableRow>
            <TableCell>Value / util / hook (named or default), and every <code>* as</code> namespace</TableCell>
            <TableCell><strong>Eager</strong> — a <code>const</code> preload at load time</TableCell>
            <TableCell><strong>Error</strong> — a cycle among them is <code>GUITKX2306</code> (the chain is printed)</TableCell>
          </TableRow>
        </TableBody>
      </Table>
    </TableContainer>

    <Typography variant="h5" component="h2" gutterBottom sx={{ mt: 3 }}>
      The <code>~/</code> root
    </Typography>
    <Typography variant="body1" paragraph>
      <code>~/</code> resolves against your project&apos;s UI source root — the <code>root</code>{' '}
      key in the nearest <code>guitkx.config.json</code> (walking up from the file), defaulting to{' '}
      <code>res://</code>. The nearest config wins with no merge.
    </Typography>
    <CodeBlock language="json" code={EXAMPLE_CONFIG} />

    <Typography variant="h5" component="h2" gutterBottom sx={{ mt: 3 }}>
      Migrating an existing project
    </Typography>
    <Typography variant="body1" paragraph>
      A one-command codemod modernizes a whole project to the 0.11.0 surface: it removes the
      deprecated <code>component</code> / <code>hook</code> / <code>module</code> wrapper keywords
      (adding <code>{'-> RuitkVNode'}</code> to components and hoisting module members under{' '}
      <code>@class_name</code>), and flips importers of former modules to{' '}
      <code>import * as</code>. It is idempotent and re-runnable, and it leaves hand-written{' '}
      <code>class_name</code> scripts alone (they are ambient). See the Migrations page.
    </Typography>
    <CodeBlock language="bash" code={EXAMPLE_MIGRATE} />

    <Typography variant="h5" component="h2" gutterBottom sx={{ mt: 3 }}>
      Diagnostics
    </Typography>
    <Typography variant="body1" paragraph>
      Import and export mistakes surface as <code>GUITKX2300</code>–<code>GUITKX2309</code> (the
      0.10.0 block) and <code>GUITKX2320</code>–<code>GUITKX2327</code> (the 0.11.0 band):
    </Typography>
    <TableContainer component={Paper} sx={{ mb: 2 }}>
      <Table size="small">
        <TableHead>
          <TableRow>
            <TableCell>Code</TableCell>
            <TableCell>Meaning</TableCell>
          </TableRow>
        </TableHead>
        <TableBody>
          {[
            ['GUITKX2300', 'Unknown import specifier — no file at that path'],
            ['GUITKX2301', 'Name is not exported by the target — add `export`'],
            ['GUITKX2302', 'Name is not declared in the target file'],
            ['GUITKX2303', 'Duplicate import of the same name'],
            ['GUITKX2304', 'Unused import (an error since 0.11.1)'],
            ['GUITKX2305', 'Referenced but not imported — add the import'],
            ['GUITKX2306', 'Value-import cycle (prints the chain)'],
            ['GUITKX2307', 'Used like a component/hook but no file exports it'],
            ['GUITKX2308', 'Import crosses a module/root boundary'],
            ['GUITKX2309', 'Import must appear before the first declaration'],
            ['GUITKX2320', 'Deprecated wrapper keyword (warning; one per decl) — run the 0.11.0 codemod'],
            ['GUITKX2321', 'use_-prefixed callable returns RuitkVNode — did you mean a component?'],
            ['GUITKX2322', 'Reserved — not emitted by the Godot leg (family code for value-export type-inference failure)'],
            ['GUITKX2323', 'export default / export { … } names something that is not a top-level decl in this file'],
            ['GUITKX2324', 'Name already exported (duplicate export)'],
            ['GUITKX2325', 'Import alias collides with an in-file declaration or another import'],
            ['GUITKX2326', 'Target has no default export (suggests the named-import fix)'],
            ['GUITKX2327', 'Duplicate export default'],
          ].map(([code, meaning]) => (
            <TableRow key={code}>
              <TableCell><code>{code}</code></TableCell>
              <TableCell>{meaning}</TableCell>
            </TableRow>
          ))}
        </TableBody>
      </Table>
    </TableContainer>
  </Box>
)
