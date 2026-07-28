import type { FC } from 'react'
import {
  Box,
  Chip,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableRow,
  Typography,
} from '@mui/material'
import Styles from '../Reference/UitkxReferencePage.style'

type Sev = 'Error' | 'Warning' | 'Hint'
type DiagRow = { code: string; sev: Sev; title: string; fix: React.ReactNode }

const sevColor: Record<Sev, 'error' | 'warning' | 'info'> = {
  Error: 'error',
  Warning: 'warning',
  Hint: 'info',
}

const DiagTable: FC<{ rows: DiagRow[] }> = ({ rows }) => (
  <TableContainer>
    <Table size="small" sx={Styles.table}>
      <TableHead>
        <TableRow>
          <TableCell>Code</TableCell>
          <TableCell>Severity</TableCell>
          <TableCell>Title</TableCell>
          <TableCell>How to fix</TableCell>
        </TableRow>
      </TableHead>
      <TableBody>
        {rows.map((r) => (
          <TableRow key={r.code}>
            <TableCell>
              <Chip label={r.code} size="small" color={sevColor[r.sev]} variant="outlined" />
            </TableCell>
            <TableCell>
              <Chip label={r.sev} size="small" color={sevColor[r.sev]} />
            </TableCell>
            <TableCell>{r.title}</TableCell>
            <TableCell>{r.fix}</TableCell>
          </TableRow>
        ))}
      </TableBody>
    </Table>
  </TableContainer>
)

/* ── Parser diagnostics (GUITKX0300–0306) ───────────────────────────── */
const parserRows: DiagRow[] = [
  { code: 'GUITKX0300', sev: 'Error', title: 'Unexpected / missing token', fix: <>Malformed attributes, a missing declaration name, or an attribute value that is neither a string nor a <code>{'{expr}'}</code>. Check the syntax near the reported line.</> },
  { code: 'GUITKX0301', sev: 'Error', title: 'Unclosed tag', fix: <>Add a matching closing tag, or use self-closing syntax (<code>{'<Foo />'}</code>).</> },
  { code: 'GUITKX0302', sev: 'Error', title: 'Mismatched closing tag', fix: <>The closing tag name must match the opening tag (<code>{'</Foo>'}</code> for <code>{'<Foo>'}</code>).</> },
  { code: 'GUITKX0303', sev: 'Error', title: 'Missing block / unexpected EOF', fix: <>A declaration, directive, or <code>@match</code> is missing its <code>{'{ ... }'}</code> body (or the file ended mid-tag). Close the block.</> },
  { code: 'GUITKX0304', sev: 'Error', title: 'Unclosed brace / paren', fix: <>An unclosed <code>{'{expr}'}</code>, <code>(...)</code> param list, <code>return (</code>, directive body, or <code>@match</code> body. Balance the delimiters.</> },
  { code: 'GUITKX0305', sev: 'Warning', title: 'Unknown @directive', fix: <>Valid directives: <code>@if</code>, <code>@else</code>, <code>@for</code>, <code>@while</code>, <code>@match</code>, <code>@case</code>, <code>@default</code> (and the file directives <code>@class_name</code>, <code>@extends</code>, <code>@use</code>).</> },
  { code: 'GUITKX2506', sev: 'Error', title: 'Directive shape error', fix: <>A directive expects <code>(...)</code>, or an <code>@match</code> body expects <code>@case (...) {'{ }'}</code> / <code>@default {'{ }'}</code> arms. Fix the directive header.</> },
]

/* ── Structural / semantic diagnostics (GUITKX2101–0113) ─────────────── */
const structuralRows: DiagRow[] = [
  { code: 'GUITKX2101', sev: 'Error', title: 'No declaration / no markup return', fix: <>The file has no top-level declaration, or a component has neither a final <code>return ( ... )</code> nor a top-level <code>return null</code>. A component with a <strong>top-level</strong> <code>return null</code> and no markup return is legal (v0.12.1+, React semantics — it renders nothing); a body whose only <code>return null</code> is nested inside a conditional still errors, because the fall-through path would return nothing. Add the declaration / a final return.</> },
  { code: 'GUITKX2102', sev: 'Error', title: 'Final return is not markup', fix: <>The component&apos;s FINAL top-level <code>return</code> must be <code>return ( {'<markup>'} )</code> — an element, <code>{'<>…</>'}</code> fragment, @directive, or <code>{'{expr}'}</code>. Early and conditional <em>markup</em> returns are legal (v0.6+, React-style: <code>if not ready: return ( {'<Label />'} )</code> renders when hit); <code>return null</code> guards and plain value returns are ordinary GDScript.</> },
  { code: 'GUITKX0107', sev: 'Hint', title: 'Unreachable code after a markup return', fix: <>An <strong>unconditional</strong> <code>return ( {'<markup>'} )</code> makes every statement after it dead — including a now-unreachable final return. The editor dims the dead code; delete it or make the earlier return conditional.</> },
  { code: 'GUITKX2508', sev: 'Error', title: 'Malformed directive header', fix: <><code>@for</code> expects <code>({'<identifier>'} in {'<expression>'})</code>; <code>@if</code> / <code>@while</code> / <code>@match</code> / <code>@case</code> expect a single expression (an unbracketed <code>:</code> can never be one — <code>@for (i in 2: int5)</code> is the classic mistake).</> },
  { code: 'GUITKX2103', sev: 'Error', title: 'Directive body without a return (pre-0.7 grammar)', fix: <>Since 0.7 a directive body is a <em>code block</em>: preparation GDScript plus <code>return ( {'<markup>'} )</code> — exactly like ReactiveUIToolKit for Unity, nesting included. Wrap the body&apos;s markup in <code>return ( … )</code>, or migrate a whole project in one shot with <code>dev/migrate_directive_bodies.gd</code>. <code>return null</code> skips the item in loops / renders nothing in branches.</> },
  { code: 'GUITKX2104', sev: 'Error', title: 'Hook called inside a directive body', fix: <>Hooks must run unconditionally, in component order, every render — a call inside <code>@if</code> / <code>@for</code> / <code>@case</code> runs conditionally or per-iteration and corrupts the hook sequence. Call the hook in setup and reference the result in the body.</> },
  { code: 'GUITKX2106', sev: 'Error', title: 'Duplicate class binding', fix: <>Two <code>.guitkx</code> files bind the same class — usually a copied file that hasn&apos;t been renamed yet (the watcher compiles the copy within seconds). The original keeps compiling; the copy produces <em>no output</em> until you rename its <code>@class_name</code> / component, so a duplicate <code>class_name</code> can never reach the project.</> },
  { code: 'GUITKX2107', sev: 'Error', title: 'Referenced component no longer exists', fix: <>A component this file references was deleted or renamed (its generated <code>.gd</code> is gone). Remove or update the dangling tag, or restore/rename the component back — the next sweep heals the file automatically once every reference resolves again. Until then the last good code keeps running.</> },
  { code: 'GUITKX0104', sev: 'Warning', title: 'Duplicate sibling key', fix: <>Ensure each sibling element has a unique <code>key</code> value.</> },
  { code: 'GUITKX0106', sev: 'Warning', title: 'Loop element missing key', fix: <>An element inside <code>@for</code> / <code>@while</code> has no <code>key</code>. Add <code>key={'{...}'}</code> with a stable unique identifier so reordered children reconcile correctly.</> },
  { code: 'GUITKX0108', sev: 'Error', title: 'Multiple root elements', fix: <>A component must return exactly one root element. Wrap siblings in a container (<code>{'<VBoxContainer>'}</code>, <code>{'<HBoxContainer>'}</code>) or a fragment (<code>{'<>…</>'}</code>).</> },
  { code: 'GUITKX2504', sev: 'Error', title: 'Invalid module (deprecated wrapper)', fix: <>A deprecated <code>module</code> wrapper block has no declarations, or is nested inside another. Fires only while the 0.11.0 deprecation window keeps the wrapper parsing — run the 0.11.0 codemod to hoist module members to top level.</> },
  { code: 'GUITKX2505', sev: 'Error', title: 'Duplicate declaration', fix: <>Two declarations in the same file (or in a deprecated <code>module</code> block) share a name. Rename one.</> },
  { code: 'GUITKX0026', sev: 'Error', title: 'Statement used in an embedded expression', fix: <>A statement (e.g. a control-flow directive) cannot be lowered inside an embedded <code>{'{expr}'}</code> / JSX-value. Lift it to the top-level markup return, or use <code>.map()</code> for lists.</> },
]

/* ── Import diagnostics (GUITKX2300–2309, 0.10.0) ────────────────────── */
// The family-frozen import block, shared verbatim (modulo prefix) with ReactiveUI for
// Unreal (UETKX23xx) and Unity (UITKX23xx). All error-tier since 0.11.1 (2304 was a warning).
const importRows: DiagRow[] = [
  { code: 'GUITKX2300', sev: 'Error', title: 'Unknown import specifier', fix: <>No <code>.guitkx</code> file exists at the specifier&apos;s path. Specifiers are extensionless and relative (<code>./</code>, <code>../</code>) or root-aliased (<code>~/</code>); <code>res://</code> / <code>uid://</code> are not valid import specifiers. Check the path and the <code>root</code> key in <code>guitkx.config.json</code>.</> },
  { code: 'GUITKX2301', sev: 'Error', title: 'Not exported by the target', fix: <>The name is declared in the target file but not marked <code>export</code> — file-private declarations are unreachable cross-file. Add <code>export</code> to its declaration.</> },
  { code: 'GUITKX2302', sev: 'Error', title: 'Not declared in the target', fix: <>The target file has no declaration with this name. Check the spelling, or import it from the file that actually declares it.</> },
  { code: 'GUITKX2303', sev: 'Error', title: 'Duplicate import', fix: <>The same name is imported twice (possibly from two different files). Remove one.</> },
  { code: 'GUITKX2304', sev: 'Error', title: 'Unused import', fix: <>The imported name is never referenced in this file. Remove the import (or use it). An error since 0.11.1 (was a warning), consistent with the other import diagnostics.</> },
  { code: 'GUITKX2305', sev: 'Error', title: 'Referenced but not imported', fix: <>Cross-file resolution is strict — the message contains the exact <code>import {'{ X }'} from &quot;…&quot;</code> line to add. Hand-written <code>class_name</code> scripts are ambient and never need an import.</> },
  { code: 'GUITKX2306', sev: 'Error', title: 'Value-import cycle', fix: <>Values, utils, hooks, and <code>* as</code> namespace imports are eager <code>const</code> preloads, so an import cycle among them is a load-order error (the message prints the chain). Break the chain, or restructure so the cyclic edge is a <em>component</em> reference — component imports are lazy and may cycle freely.</> },
  { code: 'GUITKX2307', sev: 'Error', title: 'Used like a component/hook but no file exports it', fix: <>A component-like tag matches no host element, no import, and no <code>.guitkx</code> export (and isn&apos;t a near-miss of one). Create/export the component and import it, or fix the name.</> },
  { code: 'GUITKX2308', sev: 'Error', title: 'Import crosses the project boundary', fix: <>The specifier resolves above <code>res://</code> (a <code>../</code> chain or a <code>~/</code> root that escapes the project). Imports are project-scoped in v1 — keep the target inside <code>res://</code>.</> },
  { code: 'GUITKX2309', sev: 'Error', title: 'Import after the first declaration', fix: <>Imports are preamble-only. Move the <code>import</code> line above the first declaration.</> },
]

/* ── Declaration & export diagnostics (GUITKX2320–2327, 0.11.0) ──────── */
const declarationRows: DiagRow[] = [
  { code: 'GUITKX2320', sev: 'Warning', title: 'Deprecated wrapper keyword', fix: <>A <code>component</code> / <code>hook</code> / <code>module</code> wrapper keyword (pre-0.11 syntax). It still compiles for this deprecation window — one warning per declaration — and is removed in a later minor. Run the codemod: <code>godot --headless --path . --script res://addons/reactive_ui_toolkit/dev/migrate_0_11_0.gd</code>.</> },
  { code: 'GUITKX2321', sev: 'Error', title: 'use_* callable returns RuitkVNode', fix: <>A <code>use_</code>-prefixed callable is classified as a hook, but its return annotation is <code>RuitkVNode</code> — did you mean a component? Rename it PascalCase without the prefix (component), or change the return type (hook).</> },
  { code: 'GUITKX2322', sev: 'Hint', title: 'Reserved — not emitted by the Godot leg', fix: <>The family code for a value-export type-inference failure. GDScript is dynamically typed, so it cannot fire here; the number is reserved for cross-family alignment and never emitted.</> },
  { code: 'GUITKX2323', sev: 'Error', title: 'Export of a non-declaration', fix: <><code>export default Name</code> or <code>export {'{ a, b }'}</code> names something that is not a top-level declaration in this file. Fix the name, or declare it.</> },
  { code: 'GUITKX2324', sev: 'Error', title: 'Duplicate export', fix: <>The name is already exported (e.g. an inline <code>export</code> prefix plus an <code>export {'{ … }'}</code> list entry). Remove one.</> },
  { code: 'GUITKX2325', sev: 'Error', title: 'Import alias collision', fix: <>An import alias (<code>as local</code>, a namespace <code>* as X</code>, or a default binding) collides with an in-file declaration or another import. Rename the alias.</> },
  { code: 'GUITKX2326', sev: 'Error', title: 'No default export in the target', fix: <><code>import X from &quot;./x&quot;</code> requires the target to declare <code>export default</code>. Add one there, or switch to the suggested named import (<code>import {'{ X }'} from &quot;./x&quot;</code>).</> },
  { code: 'GUITKX2327', sev: 'Error', title: 'Duplicate export default', fix: <>A file may mark at most one declaration as its default. Remove the extra <code>export default</code> line.</> },
]

/* ── Language-server diagnostics (GUITKX0105, GUITKX0109) ────────────── */
// Editor-only: emitted live by the language server (VS Code / VS 2022 extension).
// They have no compile-time equivalent and are never written to the sibling
// <file>.guitkx.diags.json — the compiler only knows about parser/structural codes.
const languageServerRows: DiagRow[] = [
  { code: 'GUITKX0105', sev: 'Error', title: 'Unknown element (did-you-mean)', fix: <>A PascalCase tag (<code>{'<Labl>'}</code>) matches no host element or project component, but is a near-miss of a known one. Rename it to the suggestion (<code>{'<Label>'}</code>), or define / import the component. Host tags come from the schema; component tags come from the project&apos;s <code>.guitkx</code> index.</> },
  { code: 'GUITKX0109', sev: 'Error', title: 'Unknown attribute on host element', fix: <>An attribute is not a valid property, signal handler, or structural attr of the host element&apos;s Godot class (checked against the bundled ClassDB dump; a suggestion is offered on a near-miss). Fix the spelling, or move it onto a <em>component</em> tag — components accept arbitrary props. Native <code>on_&lt;signal&gt;</code> handlers and <code>style</code> / <code>classes</code> / <code>key</code> / <code>ref</code> are always allowed.</> },
]

/* ── Runtime hook validation (GUITKX0013) ────────────────────────────── */
const runtimeRows: DiagRow[] = [
  { code: 'GUITKX0013', sev: 'Warning', title: 'Hook called conditionally / in a block', fix: <>Hooks must run unconditionally at the top of setup — never inside an <code>@if</code> / loop / nested lambda. The runtime hook-order validator (gated by <code>RuitkConfig.enable_hook_validation</code>) also detects an order / count change across renders and reports it via <code>RuitkDiagnostics</code> + <code>push_error</code>.</> },
]

export const UitkxDiagnosticsPage: FC = () => (
  <Box sx={Styles.root}>
    <Typography variant="h4" component="h1" gutterBottom>
      Diagnostics Reference
    </Typography>
    <Typography variant="body1" paragraph>
      Every diagnostic code emitted by the <code>.guitkx</code> compiler and the
      language server, with severity, meaning, and how to fix it. Compile-time
      diagnostics are written to a sibling <code>&lt;file&gt;.guitkx.diags.json</code>{' '}
      and surfaced as <code>push_error</code> / <code>push_warning</code> in the
      Godot output; the same checks run live in the editor extension.
    </Typography>

    {/* ── Parser Diagnostics ────────────────────────────────────────────── */}
    <Typography variant="h5" component="h2" sx={Styles.section}>
      Parser Diagnostics
    </Typography>
    <Typography variant="body2" paragraph>
      Emitted when the lexer / parser encounters malformed markup syntax.
    </Typography>
    <DiagTable rows={parserRows} />

    {/* ── Structural / Semantic Diagnostics ─────────────────────────────── */}
    <Typography variant="h5" component="h2" sx={Styles.section}>
      Structural &amp; Semantic Diagnostics
    </Typography>
    <Typography variant="body2" paragraph>
      Emitted after parsing, when validating the file&apos;s declarations and the
      reconciliation keys.
    </Typography>
    <DiagTable rows={structuralRows} />
    <Typography variant="body2" paragraph sx={{ mt: 1 }}>
      <strong>GUITKX0103</strong> (<em>component name differs from file name</em>) is retired as of
      0.10.2 — imports made filename identity meaningless, since a declaration&apos;s binding is now
      inferred (<code>@class_name</code> override, else the first exported declaration, else the
      first declaration) rather than required to match the file. The code number stays reserved and
      is never reused; older sidecars may still contain it.
    </Typography>

    {/* ── Import Diagnostics ────────────────────────────────────────────── */}
    <Typography variant="h5" component="h2" sx={Styles.section}>
      Import Diagnostics (0.10.0)
    </Typography>
    <Typography variant="body2" paragraph>
      Emitted while resolving <code>import {'{ … }'} from &quot;…&quot;</code> — the
      family-frozen <code>2300–2309</code> block, shared with ReactiveUI for Unreal
      and Unity. See the Imports &amp; Exports page for the grammar and the
      migration codemod.
    </Typography>
    <DiagTable rows={importRows} />

    {/* ── Declaration & Export Diagnostics ──────────────────────────────── */}
    <Typography variant="h5" component="h2" sx={Styles.section}>
      Declaration &amp; Export Diagnostics (0.11.0)
    </Typography>
    <Typography variant="body2" paragraph>
      The <code>2320–2327</code> band, added with the ES-modules release: plain
      signature-classified declarations, value exports, and the full import
      surface (rename / namespace / default / export lists).
    </Typography>
    <DiagTable rows={declarationRows} />
    <Typography variant="body2" paragraph sx={{ mt: 1 }}>
      <strong>GUITKX2203</strong> (<em>hook missing the <code>use_</code> naming prefix</em>) is
      retired as of 0.11.0 — without wrapper keywords the <code>use_</code> prefix <em>is</em> the
      classification, so a helper without it is simply a util and warrants no warning. The number
      stays reserved and is never reused; during the deprecation window it still fires only on
      deprecated <code>hook</code> wrapper declarations.
    </Typography>

    {/* ── Language-Server Diagnostics ───────────────────────────────────── */}
    <Typography variant="h5" component="h2" sx={Styles.section}>
      Language-Server Diagnostics
    </Typography>
    <Typography variant="body2" paragraph>
      Emitted live by the editor extension&apos;s language server (VS Code / Visual
      Studio) as you type. These are editor-only — they have no compile-time
      equivalent and are not written to <code>&lt;file&gt;.guitkx.diags.json</code>.
    </Typography>
    <DiagTable rows={languageServerRows} />

    {/* ── Runtime hook validation ───────────────────────────────────────── */}
    <Typography variant="h5" component="h2" sx={Styles.section}>
      Runtime Hook Validation
    </Typography>
    <Typography variant="body2" paragraph>
      Emitted at runtime (in debug builds by default) when hooks are used in a
      way that breaks the positional-slot model.
    </Typography>
    <DiagTable rows={runtimeRows} />
  </Box>
)
