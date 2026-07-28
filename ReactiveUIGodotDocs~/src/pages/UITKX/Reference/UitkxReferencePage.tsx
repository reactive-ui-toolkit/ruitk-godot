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
import Styles from './UitkxReferencePage.style'

const DIRECTIVE_HEADER_EXAMPLE = `@class_name MyButton
@uss "res://ui/theme.tres"

export MyButton(label: String = "Click") -> RUIVNode {
  return (
    <Button text={ label } onPressed={ func(): print("clicked") } />
  )
}`

const FUNCTION_STYLE_EXAMPLE = `Counter(label: String = "Count") -> RUIVNode {
  var s = useState(0)
  var count = s[0]
  return (
    <VBoxContainer>
      <Label text={ "%s: %d" % [label, count] } />
      <Button text="+" onPressed={ func(): s[1].call(count + 1) } />
    </VBoxContainer>
  )
}`

const CONTROL_FLOW_EXAMPLE = `<VBoxContainer>
  @if (is_logged_in) {
    return ( <Label text="Welcome back!" /> )
  } @elif (is_guest) {
    return ( <Label text="Browsing as guest" /> )
  } @else {
    return ( <Button text="Log in" onPressed={ func(): login() } /> )
  }

  @for (item in items) {
    var color = Color.GREEN if item.active else Color.GRAY
    return ( <Label key={ item.id } text={ item.name.to_upper() }
      style={ {"font_color": color} } /> )
  }

  @for (i in count) {
    return ( <Label key={ str(i) } text={ "Row %d" % i } /> )
  }

  @match (mode) {
    @case ("dark")  { return ( <Label text="Dark mode" /> ) }
    @case ("light") { return ( <Label text="Light mode" /> ) }
    @default        { return ( <Label text="Unknown mode" /> ) }
  }
</VBoxContainer>`

const EARLY_RETURN_EXAMPLE = `StatusPanel(ready: bool = false) -> RUIVNode {
  if not ready:
    return ( <Label text="Loading…" /> )
  return (
    <VBoxContainer>
      <Label text="Ready!" />
    </VBoxContainer>
  )
}`

const PROP_SPREAD_EXAMPLE = `Toolbar(cfg: Dictionary = {}) -> RUIVNode {
  var base := { "text": "Save", "disabled": false }

  return (
    <VBoxContainer>
      # Spread a variable of props, then add an explicit handler.
      <Button {...base} onPressed={ func(): save() } />

      # Explicit prop first, spread overrides it (later wins).
      <Button text="Placeholder" {...cfg} />

      # Spread first as defaults; the trailing onPressed always wins.
      <Button {...cfg} text="Cancel" onPressed={ func(): cancel() } />

      # Spread works on components too.
      <Card {...base} title={ "Details" } />
    </VBoxContainer>
  )
}`

const EXPRESSION_EXAMPLE = `<Label text={ "Count: %d" % count } />
<Button onPressed={ func(): s[1].call(count + 1) } />
<VBoxContainer>
  { my_custom_node }
  { a_node if cond else b_node }
  # This is a line comment
</VBoxContainer>

// A raw expression (instead of markup) can be the whole return body:
{ V.router({ "initial": "/" }, [V.fc(App.render)]) }`

export const UitkxReferencePage: FC = () => (
  <Box sx={Styles.root}>
    <Typography variant="h4" component="h1" gutterBottom>
      .guitkx Language Reference
    </Typography>
    <Typography variant="body1" paragraph>
      Complete reference for the <code>.guitkx</code> markup language — declarations, directives,
      control flow, and expressions. A <code>.guitkx</code> file compiles to a sibling GDScript{' '}
      <code>.gd</code> class.
    </Typography>

    {/* ── Declarations ─────────────────────────────────────────────── */}
    <Typography variant="h5" component="h2" sx={Styles.section}>
      Declarations
    </Typography>
    <Typography variant="body2" paragraph>
      A <code>.guitkx</code> file is a module: a sequence of <strong>plain top-level
      declarations</strong>, several per file in any mix. There are no wrapper keywords (0.11.0) —
      what a declaration <em>is</em> is classified from its <strong>signature</strong> alone. Each
      becomes a static member of the generated class. Prefix a declaration with{' '}
      <code>export</code> to make it importable from other files — without it the declaration is
      file-private. A top-level <code>{'export { a, b }'}</code> line exports in-file declarations
      after the fact, and <code>export default Name</code> marks at most one declaration as the
      file&apos;s default (see the Imports &amp; Exports page).
    </Typography>
    <TableContainer>
      <Table size="small" sx={Styles.table}>
        <TableHead>
          <TableRow>
            <TableCell>You write</TableCell>
            <TableCell>It is</TableCell>
            <TableCell>Because</TableCell>
          </TableRow>
        </TableHead>
        <TableBody>
          <TableRow>
            <TableCell><code>Name(params) -&gt; RUIVNode {'{ … }'}</code></TableCell>
            <TableCell><strong>Component</strong> — compiles to <code>static func render(props, children)</code></TableCell>
            <TableCell>the <code>-&gt; RUIVNode</code> return annotation <em>is</em> the classification (PascalCase name enforced, <code>GUITKX2100</code>)</TableCell>
          </TableRow>
          <TableRow>
            <TableCell><code>use_name(params) [-&gt; T] {'{ … }'}</code></TableCell>
            <TableCell><strong>Hook</strong> — reusable state logic (may call <code>Hooks.*</code>)</TableCell>
            <TableCell>the <code>use_</code> prefix</TableCell>
          </TableRow>
          <TableRow>
            <TableCell><code>name(params) [-&gt; T] {'{ … }'}</code></TableCell>
            <TableCell><strong>Util</strong> — a plain helper function</TableCell>
            <TableCell>any other callable</TableCell>
          </TableRow>
          <TableRow>
            <TableCell><code>name := expr</code> / <code>name: Type = expr</code> / <code>name = expr</code></TableCell>
            <TableCell><strong>Value</strong> — compiles to <code>static var</code>; treat as a constant</TableCell>
            <TableCell>the <code>=</code> after the name</TableCell>
          </TableRow>
        </TableBody>
      </Table>
    </TableContainer>
    <Typography variant="body2" paragraph sx={{ mt: 1 }}>
      Two consequences worth internalizing: a component <strong>must</strong> annotate{' '}
      <code>-&gt; RUIVNode</code> (a PascalCase callable without it is a util and its{' '}
      <code>{'<Tag>'}</code> stops resolving), and a <code>use_</code>-prefixed callable that
      returns <code>RUIVNode</code> is the cross-guard error <code>GUITKX2321</code> (&quot;did you
      mean a component?&quot;). The pre-0.11 <code>component</code> / <code>hook</code> /{' '}
      <code>module</code> wrapper keywords still compile for one deprecation window with warning{' '}
      <code>GUITKX2320</code> — run the 0.11.0 codemod (see Migrations).
    </Typography>

    {/* ── Preamble Directives ──────────────────────────────────────── */}
    <Typography variant="h5" component="h2" sx={Styles.section}>
      Preamble Directives
    </Typography>
    <Typography variant="body2" paragraph>
      The preamble is everything before the first declaration: <code>import</code> lines and the{' '}
      <code>@</code>-directives, in any order. Directives configure the generated GDScript class.
    </Typography>
    <TableContainer>
      <Table size="small" sx={Styles.table}>
        <TableHead>
          <TableRow>
            <TableCell>Directive</TableCell>
            <TableCell>Syntax</TableCell>
            <TableCell>Description</TableCell>
          </TableRow>
        </TableHead>
        <TableBody>
          <TableRow>
            <TableCell><code>import</code></TableCell>
            <TableCell><code>import {'{ Name, … }'} from &quot;./file&quot;</code></TableCell>
            <TableCell>Bring another file&apos;s <code>export</code>ed declarations into scope. Specifiers are extensionless: <code>./</code> / <code>../</code> relative, or <code>~/</code> from the config <code>root</code>. All ES forms since 0.11.0 — named (<code>{'{ a, b as c }'}</code>), namespace (<code>* as X</code>), and default. See the Imports &amp; Exports page.</TableCell>
          </TableRow>
          <TableRow>
            <TableCell><code>@class_name</code></TableCell>
            <TableCell><code>@class_name MyButton</code></TableCell>
            <TableCell>Optional override for the generated GDScript <code>class_name</code> (defaults to the first exported declaration&apos;s name, else the first declaration&apos;s) — the binding / interop escape hatch, rarely needed: a name collision with a hand-written class, or keeping a hoisted pre-0.11 <code>module</code>&apos;s dotted callers (<code>M.member(...)</code>) working.</TableCell>
          </TableRow>
          <TableRow>
            <TableCell><code>@uss</code></TableCell>
            <TableCell><code>@uss "res://ui/theme.tres"</code></TableCell>
            <TableCell>Preload a <code>Theme</code> and apply it to the component's root element (unless it sets <code>theme</code> itself). One per file; component files only. Accepts <code>res://</code>, <code>uid://</code>, and <code>~/</code> paths. <code>@theme</code> is an alias.</TableCell>
          </TableRow>
        </TableBody>
      </Table>
    </TableContainer>
    <CodeBlock language="jsx" code={DIRECTIVE_HEADER_EXAMPLE} />

    {/* ── Function-Style Components ──────────────────────────────────── */}
    <Typography variant="h5" component="h2" sx={Styles.section}>
      Function-Style Components
    </Typography>
    <Typography variant="body2" paragraph>
      A component is a plain declaration whose signature ends in <code>-&gt; RUIVNode</code>, with
      optional typed parameters. Parameters are read from the <code>props</code> dictionary in the
      generated <code>render</code> method (with the declared default when a prop is absent).
    </Typography>
    <TableContainer>
      <Table size="small" sx={Styles.table}>
        <TableHead>
          <TableRow>
            <TableCell>Feature</TableCell>
            <TableCell>Syntax</TableCell>
          </TableRow>
        </TableHead>
        <TableBody>
          <TableRow>
            <TableCell>Declaration</TableCell>
            <TableCell><code>Name() -&gt; RUIVNode {'{ … }'}</code></TableCell>
          </TableRow>
          <TableRow>
            <TableCell>With parameters</TableCell>
            <TableCell><code>Name(label: String = "default") -&gt; RUIVNode {'{ … }'}</code></TableCell>
          </TableRow>
          <TableRow>
            <TableCell>Setup code</TableCell>
            <TableCell>GDScript statements + hook calls before <code>return</code></TableCell>
          </TableRow>
          <TableRow>
            <TableCell>Return</TableCell>
            <TableCell><code>return ( &lt;markup /&gt; )</code> — a single root, or a raw <code>{'{ expr }'}</code></TableCell>
          </TableRow>
          <TableRow>
            <TableCell>Early / conditional return</TableCell>
            <TableCell><code>if not ready: return ( &lt;Label text="loading" /&gt; )</code> — legal anywhere in setup, not just as the final statement (v0.6+)</TableCell>
          </TableRow>
        </TableBody>
      </Table>
    </TableContainer>
    <CodeBlock language="jsx" code={FUNCTION_STYLE_EXAMPLE} />
    <Typography variant="body2" paragraph sx={{ mt: 2 }}>
      A component&apos;s setup code can <code>return ( {'<markup>'} )</code> anywhere, not just as the
      final statement — an early or conditional markup return renders immediately when it&apos;s hit
      (v0.6+, React-style: a loading guard, an early-exit branch, and so on).
    </Typography>
    <CodeBlock language="jsx" code={EARLY_RETURN_EXAMPLE} />
    <Typography variant="body2" paragraph sx={{ mt: 1 }}>
      Code after an <strong>unconditional</strong> markup return is unreachable and dimmed by the
      editor (<code>GUITKX0107</code>). The compiler only requires the component&apos;s{' '}
      <strong>FINAL</strong> top-level <code>return</code> to be markup (<code>GUITKX2102</code>) —{' '}
      <code>return null</code> guards and plain value returns elsewhere are ordinary GDScript.
    </Typography>

    {/* ── Markup Control Flow ────────────────────────────────────────── */}
    <Typography variant="h5" component="h2" sx={Styles.section}>
      Markup Control Flow
    </Typography>
    <TableContainer>
      <Table size="small" sx={Styles.table}>
        <TableHead>
          <TableRow>
            <TableCell>Directive</TableCell>
            <TableCell>Syntax</TableCell>
            <TableCell>Notes</TableCell>
          </TableRow>
        </TableHead>
        <TableBody>
          <TableRow>
            <TableCell><code>@if / @elif / @else</code></TableCell>
            <TableCell><code>@if (cond) {'{ … }'} @elif (cond) {'{ … }'} @else {'{ … }'}</code></TableCell>
            <TableCell>Conditional rendering</TableCell>
          </TableRow>
          <TableRow>
            <TableCell><code>@for</code></TableCell>
            <TableCell><code>@for (item in list) {'{ … }'}</code></TableCell>
            <TableCell>Loop — direct children should have a <code>key</code></TableCell>
          </TableRow>
          <TableRow>
            <TableCell><code>@while</code></TableCell>
            <TableCell><code>@while (cond) {'{ … }'}</code></TableCell>
            <TableCell>While loop</TableCell>
          </TableRow>
          <TableRow>
            <TableCell><code>@match / @case / @default</code></TableCell>
            <TableCell><code>@match (val) {'{ @case ("a") { … } @default { … } }'}</code></TableCell>
            <TableCell>Compiles to a GDScript <code>match</code> statement</TableCell>
          </TableRow>
        </TableBody>
      </Table>
    </TableContainer>
    <CodeBlock language="jsx" code={CONTROL_FLOW_EXAMPLE} />
    <Typography variant="body2" paragraph sx={{ mt: 2 }}>
      A directive body is a <strong>code block</strong>: GDScript preparation statements followed by{' '}
      <code>return ( {'<markup>'} )</code>, and it nests recursively — exactly like ReactiveUIToolKit
      for Unity. <code>return null</code> (or a bare <code>return</code>) is the sanctioned way to
      skip a <code>@for</code> iteration or render nothing from a branch; a directive{' '}
      <code>return</code> must yield exactly one root element (<code>GUITKX0108</code>), and calling
      a hook inside a directive body is a compile error (<code>GUITKX2104</code>) — hooks must run
      unconditionally in setup. Control-flow directives are still{' '}
      <strong>statement-level</strong>: <code>@if</code>, <code>@for</code>, and <code>@match</code>{' '}
      appear directly among markup children, not inside a <code>{'{ expr }'}</code> value. For
      inline conditional values, use a GDScript ternary (<code>a if cond else b</code>) inside a{' '}
      <code>{'{ … }'}</code> expression instead.
    </Typography>
    <Box sx={{ my: 2, p: 2, borderLeft: '4px solid', borderColor: 'warning.main', bgcolor: 'action.hover' }}>
      <Typography variant="subtitle2" sx={{ fontWeight: 600, mb: 1 }}>
        Breaking change (0.7.0): directive bodies used to be bare markup
      </Typography>
      <Typography variant="body2" sx={{ mb: 0 }}>
        Before 0.7.0, a directive body held bare markup children with no <code>return</code> wrapper.
        That form no longer compiles — it now fails with <code>GUITKX2103</code> (&quot;a directive
        body returns its markup — write{' '}
        <code>return ( {'<markup>'} )</code>&quot;), reported live in the editor and at compile time.
        Migrate a whole project in one shot: <code>godot --headless --path . --script
        res://addons/reactive_ui_toolkit/dev/migrate_directive_bodies.gd -- res://&lt;your-ui-dir&gt;</code>.
      </Typography>
    </Box>

    {/* ── Expressions & Values ───────────────────────────────────────── */}
    <Typography variant="h5" component="h2" sx={Styles.section}>
      Expressions & Values
    </Typography>
    <TableContainer>
      <Table size="small" sx={Styles.table}>
        <TableHead>
          <TableRow>
            <TableCell>Syntax</TableCell>
            <TableCell>Example</TableCell>
            <TableCell>Description</TableCell>
          </TableRow>
        </TableHead>
        <TableBody>
          <TableRow>
            <TableCell><code>{'{ expr }'}</code></TableCell>
            <TableCell><code>{'<VBoxContainer>{ my_node }</VBoxContainer>'}</code></TableCell>
            <TableCell>
              A GDScript expression in <strong>markup-child</strong> position. It may evaluate to an{' '}
              <code>RUIVNode</code>, an <code>Array</code> of vnodes (rendered as siblings), a{' '}
              <code>String</code> (rendered as a label), or <code>null</code> (renders nothing).
            </TableCell>
          </TableRow>
          <TableRow>
            <TableCell><code>{'attr={ expr }'}</code></TableCell>
            <TableCell><code>{'text={ "Count: %d" % count }'}</code></TableCell>
            <TableCell>A GDScript expression as an attribute value</TableCell>
          </TableRow>
          <TableRow>
            <TableCell><code>"literal"</code></TableCell>
            <TableCell><code>text="hello"</code></TableCell>
            <TableCell>Plain string attribute</TableCell>
          </TableRow>
          <TableRow>
            <TableCell><code>{'onXxx={ func: … }'}</code></TableCell>
            <TableCell><code>{'onPressed={ func(): do_it() }'}</code></TableCell>
            <TableCell>An event handler — a <code>Callable</code> connected to the mapped signal</TableCell>
          </TableRow>
          <TableRow>
            <TableCell><code>{'{...obj}'}</code></TableCell>
            <TableCell><code>{'<Button {...cfg} onPressed={ f } />'}</code></TableCell>
            <TableCell>
              Prop spread — merges a <code>Dictionary</code> of props onto the element (React&apos;s{' '}
              <code>{'{...obj}'}</code>). See <strong>Prop spread</strong> below.
            </TableCell>
          </TableRow>
          <TableRow>
            <TableCell><code>name</code> (bare)</TableCell>
            <TableCell><code>disabled</code></TableCell>
            <TableCell>Boolean shorthand — a valueless attribute is <code>true</code>.</TableCell>
          </TableRow>
          <TableRow>
            <TableCell><code>{'// … /* … */ <!-- … -->'}</code></TableCell>
            <TableCell><code>{'// TODO'}</code></TableCell>
            <TableCell>Markup comments (Unity-parity set): <code>{'//'}</code> line, <code>{'/* */'}</code> block, <code>{'<!-- -->'}</code>, and <code>{'{/* … */}'}</code> inside attribute lists. <code>#</code> is not a markup comment — it stays GDScript-only (setup and expressions).</TableCell>
          </TableRow>
          <TableRow>
            <TableCell><code>{'<>…</>'}</code></TableCell>
            <TableCell><code>{'<>'}{'<Label /><Label />'}{'</>'}</code></TableCell>
            <TableCell>Fragment — groups multiple elements without a host node</TableCell>
          </TableRow>
        </TableBody>
      </Table>
    </TableContainer>
    <CodeBlock language="jsx" code={EXPRESSION_EXAMPLE} />

    {/* ── Structural attributes ──────────────────────────────────────── */}
    <Typography variant="h5" component="h2" sx={Styles.section}>
      Structural Attributes
    </Typography>
    <Typography variant="body2" paragraph>
      These three attributes are accepted on every host element, alongside any property of the
      underlying Godot node and the <code>on*</code> event handlers.
    </Typography>
    <TableContainer>
      <Table size="small" sx={Styles.table}>
        <TableHead>
          <TableRow>
            <TableCell>Attribute</TableCell>
            <TableCell>Example</TableCell>
            <TableCell>Description</TableCell>
          </TableRow>
        </TableHead>
        <TableBody>
          <TableRow>
            <TableCell><code>key</code></TableCell>
            <TableCell><code>{'key={ item.id }'}</code></TableCell>
            <TableCell>Stable identity for keyed reconciliation (required on loop children).</TableCell>
          </TableRow>
          <TableRow>
            <TableCell><code>ref</code></TableCell>
            <TableCell><code>{'ref={ my_ref }'}</code></TableCell>
            <TableCell>A <code>{'{ "current": … }'}</code> box or <code>Callable(node)</code> that receives the live node.</TableCell>
          </TableRow>
          <TableRow>
            <TableCell><code>style</code></TableCell>
            <TableCell><code>{'style={ {"separation": 8} }'}</code></TableCell>
            <TableCell>Inline style dictionary (see the <strong>Styling</strong> pages).</TableCell>
          </TableRow>
        </TableBody>
      </Table>
    </TableContainer>

    {/* ── Event handlers ─────────────────────────────────────────────── */}
    <Box sx={{ my: 3, p: 2, borderLeft: '4px solid', borderColor: 'info.main', bgcolor: 'action.hover' }}>
      <Typography variant="subtitle2" sx={{ fontWeight: 600, mb: 1 }}>
        Event handler attributes
      </Typography>
      <Typography variant="body2" paragraph sx={{ mb: 1 }}>
        Event handlers follow one rule — <code>on</code> + PascalCase(signal name) — and it works
        for every signal of every node: <code>onPressed</code> → <code>pressed</code>,{' '}
        <code>onTextSubmitted</code> → <code>text_submitted</code>,{' '}
        <code>onFocusEntered</code> → <code>focus_entered</code>,{' '}
        <code>onValueChanged</code> → <code>value_changed</code>,{' '}
        <code>onItemSelected</code> → <code>item_selected</code>,{' '}
        <code>onGuiInput</code> → <code>gui_input</code>. The prop name <em>is</em> the Godot
        signal name, camelCased — there is no alias table (the 0.8 React-style aliases such as{' '}
        <code>onClick</code> and the polymorphic <code>onChange</code> were removed in 0.9.0; see{' '}
        <code>MIGRATION-0.9.md</code> at the repository root). The native{' '}
        <code>on_&lt;signal&gt;</code> spelling is also accepted, verbatim, as an escape hatch.
      </Typography>
    </Box>

    {/* ── Prop spread ────────────────────────────────────────────────── */}
    <Typography variant="h5" component="h2" sx={Styles.section}>
      Prop Spread <code>{'{...obj}'}</code>
    </Typography>
    <Typography variant="body2" paragraph>
      Spread a <code>Dictionary</code> of props onto an element with <code>{'{...obj}'}</code>, exactly
      like React&apos;s spread. It works on <strong>host elements and components alike</strong>, and{' '}
      <code>obj</code> is any GDScript expression that evaluates to a <code>Dictionary</code> — a
      literal, a prop, a variable, or a hook result.
    </Typography>
    <Typography variant="body2" paragraph>
      Spreads and explicit attributes merge <strong>left-to-right, later wins</strong>, preserving
      source order. So <code>{'<Button text="Hi" {...cfg} onPressed={ f } />'}</code> lets{' '}
      <code>cfg</code> override the literal <code>text</code>, while the trailing{' '}
      <code>onPressed</code> always wins over any <code>onPressed</code> inside <code>cfg</code>. Put a
      spread <em>last</em> to have it win, or <em>first</em> to treat it as defaults that explicit
      props override.
    </Typography>
    <CodeBlock language="jsx" code={PROP_SPREAD_EXAMPLE} />
    <Typography variant="body2" paragraph sx={{ mt: 1 }}>
      A spread merges the ordered segments into a single props <code>Dictionary</code> at render
      time. Elements with no spread keep the plain dictionary-literal fast path unchanged.
    </Typography>

    {/* ── Hooks, Utils & Values ──────────────────────────────────────── */}
    <Typography variant="h5" component="h2" sx={Styles.section}>
      Hooks, Utils &amp; Values
    </Typography>
    <Typography variant="body2" paragraph>
      Reusable logic is just more top-level declarations — a file <em>is</em> a module. Custom
      hooks are <code>use_</code>-prefixed callables (which may call built-in hooks via{' '}
      <code>Hooks.*</code>), utils are any other callable, and values hold constants and style
      dictionaries. <code>@class_name</code> pins the file&apos;s binding when you need the dotted{' '}
      <code>PlayerCard.member</code> form. See the <strong>Files &amp; Modules</strong> page for
      the full model.
    </Typography>
    <CodeBlock language="jsx" code={`@class_name PlayerCard

export HEALTH_GREEN := Color(0.2, 0.8, 0.3)

export format_health(current: int, max: int) -> String {
  return "%d / %d HP" % [current, max]
}

export use_flash(active: bool) -> bool {
  var s = Hooks.useState(false)
  Hooks.useEffect(func():
    s[1].call(active)
    return Callable()
  , [active])
  return s[0]
}`} />

    {/* ── Rules & Gotchas ────────────────────────────────────────────── */}
    <Typography variant="h5" component="h2" sx={Styles.section}>
      Rules & Gotchas
    </Typography>
    <Typography component="ul" variant="body2">
      <li><code>@class_name</code> and <code>@uss</code> must appear in the preamble, before the first declaration.</li>
      <li>A component must annotate <code>-&gt; RUIVNode</code> — that annotation is what classifies it as a component; a <code>use_</code> prefix classifies a hook (a <code>use_*</code> callable returning <code>RUIVNode</code> is <code>GUITKX2321</code>).</li>
      <li>Hook calls must be unconditional at component top level — not inside a directive body (<code>@if</code>, <code>@for</code>, <code>@case</code>, etc.), or it&apos;s <code>GUITKX2104</code>.</li>
      <li>A directive body is a code block: GDScript prep statements followed by <code>return ( {'<markup>'} )</code>, nesting recursively. The pre-0.7 bare-markup form is a compile error (<code>GUITKX2103</code>).</li>
      <li>Direct children of <code>@for</code> need a <code>key</code> attribute for stable reconciliation.</li>
      <li>A component's FINAL top-level return must be markup (a single root element, or a single raw <code>{'{ expr }'}</code>); earlier <code>return</code>s may conditionally return markup too (v0.6+).</li>
      <li>The generated <code>class_name</code> is inferred — an <code>@class_name</code> override, else the first <code>export</code>ed declaration&apos;s name, else the first declaration&apos;s — it does not need to match the file name.</li>
      <li><code>@match</code> is a statement-level directive; it can't be embedded inside a <code>{'{ expr }'}</code> attribute or child value.</li>
    </Typography>
  </Box>
)
