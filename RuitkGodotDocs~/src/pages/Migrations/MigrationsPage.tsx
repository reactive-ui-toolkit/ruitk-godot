import type { FC } from 'react'
import { Box, Link, Typography } from '@mui/material'
import { CodeBlock } from '../../components/CodeBlock/CodeBlock'
import Styles from '../GettingStarted/GettingStartedPage.style'
import {
  MIGRATE_0_13_CMD,
  MIGRATE_0_13_EXAMPLES,
  MIGRATE_0_11_CMD,
  MIGRATE_0_11_BEFORE_AFTER,
  MIGRATE_0_10_CMD,
  MIGRATE_0_10_BEFORE_AFTER,
  MIGRATE_0_9_CMD,
  MIGRATE_0_9_EXAMPLES,
} from './MigrationsPage.example'

const REPO = 'https://github.com/reactive-ui-toolkit/ruitk-godot/blob/master'

export const MigrationsPage: FC = () => (
  <Box sx={Styles.root}>
    <Typography variant="h4" component="h1" gutterBottom>
      Migrations
    </Typography>
    <Typography variant="body1" paragraph>
      Every breaking release ships a <strong>codemod</strong> that rewrites your project in place —
      run one command, review the diff, done. The codemods ship inside the addon
      (<code>addons/reactive_ui_toolkit/dev/</code>), are idempotent (safe to re-run), and never touch your
      hand-written <code>.gd</code> scripts&apos; logic. The full step-by-step guides live in the
      repository; this page is the quick path.
    </Typography>

    {/* ── 0.12 → 0.13 ────────────────────────────────────────────────── */}
    <Typography variant="h5" component="h2" gutterBottom sx={{ mt: 3 }}>
      0.12 → 0.13 — the Reactive UI Toolkit rename
    </Typography>
    <Typography variant="body1" paragraph>
      0.13 is the family umbrella rebrand — a <strong>complete rename with zero behavior
      changes</strong>. The addon folders rename (<code>addons/reactive_ui</code> →{' '}
      <code>addons/reactive_ui_toolkit</code>; the editor and analyzer folders follow), and every{' '}
      <code>RUI*</code> global class becomes <code>Ruitk*</code> — 36 whole-word renames including
      the mount surfaces <code>ReactiveRoot</code> → <code>RuitkRoot</code> and{' '}
      <code>ReactiveRootNode</code> → <code>RuitkRootNode</code> — so the component classifier
      annotation is <code>{'-> RuitkVNode'}</code>. <code>V</code> and <code>Hooks</code> are
      unchanged (the family-parity authoring surface), and so are <code>.guitkx</code> and the{' '}
      <code>GUITKX####</code> diagnostic codes. The codemod is whole-project and idempotent:
    </Typography>
    <CodeBlock language="bash" code={MIGRATE_0_13_CMD} />
    <CodeBlock language="jsx" code={MIGRATE_0_13_EXAMPLES} />
    <Typography variant="body1" paragraph sx={{ mt: 2 }}>
      Then <strong>delete the old <code>addons/reactive_ui*</code> folders by hand</strong> — store
      updates never delete, so both folder generations sit side by side and duplicate global{' '}
      <code>class_name</code> parse errors are the symptom of skipping this — and re-save your{' '}
      <code>.guitkx</code> files (or run your build sweep) so the generated <code>.gd</code>{' '}
      re-emit with the new names. Full class table and notes:{' '}
      <Link href={`${REPO}/MIGRATION-0.13.md`} target="_blank" rel="noopener">
        MIGRATION-0.13.md
      </Link>
      .
    </Typography>

    {/* ── 0.10 → 0.11 ────────────────────────────────────────────────── */}
    <Typography variant="h5" component="h2" gutterBottom sx={{ mt: 3 }}>
      0.10 → 0.11 — ES modules: a file IS a module
    </Typography>
    <Typography variant="body1" paragraph>
      0.11 replaces the <code>component</code> / <code>hook</code> / <code>module</code> wrapper
      keywords with <strong>plain, signature-classified declarations</strong>: a callable annotated{' '}
      <code>{'-> RuitkVNode'}</code> is a component, a <code>use_</code>-prefixed callable is a hook,
      any other callable is a util, and <code>name := expr</code> is a value export (the full
      classification table lives on the <strong>.guitkx Language Reference</strong> page, under
      Declarations). It also opens the full ES import surface — rename, namespace
      (<code>* as</code>), default imports, and <code>{'export { … }'}</code> /{' '}
      <code>export default</code>. The old wrappers still compile for this minor with one{' '}
      <code>GUITKX2320</code> warning per declaration, and are removed in a later minor. The
      codemod is whole-project and idempotent:
    </Typography>
    <CodeBlock language="bash" code={MIGRATE_0_11_CMD} />
    <CodeBlock language="jsx" code={MIGRATE_0_11_BEFORE_AFTER} />
    <Typography variant="body1" paragraph sx={{ mt: 2 }}>
      <code>module M {'{ … }'}</code> files hoist their members to top level with{' '}
      <code>@class_name M</code> preserving the binding (dotted <code>M.member(...)</code> callers
      keep working), and importers of a former module flip to <code>import * as M</code> — the
      codemod does both for you. Commit before running; review the diff after. Full story, value
      exports, and the new <code>2320–2327</code> diagnostics:{' '}
      <Link href={`${REPO}/MIGRATION-0.11.md`} target="_blank" rel="noopener">
        MIGRATION-0.11.md
      </Link>{' '}
      — grammar reference on the Imports &amp; Exports and Files &amp; Modules pages.
    </Typography>

    {/* ── 0.9 → 0.10 ─────────────────────────────────────────────────── */}
    <Typography variant="h5" component="h2" gutterBottom sx={{ mt: 3 }}>
      0.9 → 0.10 — imports &amp; exports
    </Typography>
    <Typography variant="body1" paragraph>
      0.10 made cross-file references explicit and strict: referencing another file&apos;s
      declaration requires an <code>import</code>, and the target must be <code>export</code>ed.
      The codemod exports every declaration and writes the import lines for each file&apos;s
      references (the before/after below is shown in 0.10-era wrapper syntax, as the codemod wrote
      it at the time):
    </Typography>
    <CodeBlock language="bash" code={MIGRATE_0_10_CMD} />
    <CodeBlock language="jsx" code={MIGRATE_0_10_BEFORE_AFTER} />
    <Typography variant="body1" paragraph sx={{ mt: 2 }}>
      Hand-written <code>class_name</code> scripts stay <em>ambient</em> (no import needed), and
      anything that still errors afterwards tells you the exact line to add. Details, edge cases,
      and the after-migration error table:{' '}
      <Link href={`${REPO}/MIGRATION-0.10.md`} target="_blank" rel="noopener">
        MIGRATION-0.10.md
      </Link>{' '}
      — grammar reference on the Imports &amp; Exports page.
    </Typography>

    {/* ── 0.8 → 0.9 ──────────────────────────────────────────────────── */}
    <Typography variant="h5" component="h2" gutterBottom sx={{ mt: 3 }}>
      0.8 → 0.9 — naming is 1:1 loyal to Godot
    </Typography>
    <Typography variant="body1" paragraph>
      0.9 renamed the whole vocabulary to the official Godot names — tags are class names,
      events are <code>on</code> + PascalCase(signal), style keys are the exact property/theme
      names. The codemod has a dry-run mode; everything it can&apos;t rewrite safely it lists for
      you, and every removed name fails loudly with its exact replacement:
    </Typography>
    <CodeBlock language="bash" code={MIGRATE_0_9_CMD} />
    <CodeBlock language="jsx" code={MIGRATE_0_9_EXAMPLES} />
    <Typography variant="body1" paragraph sx={{ mt: 2 }}>
      Full rename tables and the manual-review list:{' '}
      <Link href={`${REPO}/MIGRATION-0.9.md`} target="_blank" rel="noopener">
        MIGRATION-0.9.md
      </Link>
      .
    </Typography>

    <Typography variant="body2" paragraph sx={{ mt: 2 }}>
      Upgrading across several? Run the codemods in order: 0.9 first, then 0.10, then 0.11, then
      0.13.
    </Typography>
  </Box>
)
