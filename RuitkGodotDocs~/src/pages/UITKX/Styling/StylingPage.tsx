import { useMemo, useState } from 'react'
import type { FC } from 'react'
import {
  Accordion,
  AccordionSummary,
  AccordionDetails,
  Box,
  Chip,
  TextField,
  Typography,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableRow,
  Paper,
  Alert,
  Link,
} from '@mui/material'
import ExpandMoreIcon from '@mui/icons-material/ExpandMore'
import { CodeBlock } from '../../../components/CodeBlock/CodeBlock'
import Styles from '../../GettingStarted/GettingStartedPage.style'
import { STYLE_PROPERTY_CATALOG, CATEGORY_ORDER } from './stylePropertyCatalog'
import type { PropertyCard, PropertyCategory } from './stylePropertyCatalog'
import {
  EXAMPLE_IMPORT,
  EXAMPLE_BOTH_APIs,
  EXAMPLE_CONDITIONAL,
  EXAMPLE_INLINE,
  EXAMPLE_USS_BASIC,
  EXAMPLE_USS_FILE,
  EXAMPLE_USS_MULTIPLE,
  EXAMPLE_USS_COMBINED,
  EXAMPLE_STYLE_MODULE,
  EXAMPLE_STYLE_MODULE_USE,
  EXAMPLE_THEME_DIRECTIVE,
} from './StylingPage.example'

/** Single collapsible style-key card. */
const PropertyCardView: FC<{ card: PropertyCard }> = ({ card }) => (
  <Accordion disableGutters variant="outlined" sx={{ mb: 1 }}>
    <AccordionSummary expandIcon={<ExpandMoreIcon />}>
      <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
        <Typography variant="subtitle1" component="h3" sx={{ fontWeight: 600 }}>
          <code>{card.key}</code>
        </Typography>
        <Chip label={card.category} size="small" color="info" variant="outlined" />
        {card.compound && <Chip label="compound" size="small" variant="outlined" />}
      </Box>
    </AccordionSummary>
    <AccordionDetails>
      <Typography variant="body2" color="text.secondary" sx={{ mb: 1 }}>
        {card.description}
      </Typography>
      <Typography variant="body2" sx={{ mb: 1 }}>
        Value type: <code>{card.type}</code>
      </Typography>
      <Typography variant="body2" sx={{ mb: 1 }}>
        Maps to: <code>{card.godotMapping}</code>
      </Typography>
      <CodeBlock language="gdscript" code={`style={ {"${card.key}": ${card.example}} }`} />
    </AccordionDetails>
  </Accordion>
)

export const StylingPage: FC = () => {
  const [search, setSearch] = useState('')

  // Godot style keys are not version-gated. Sort by category order, then by key,
  // then filter by the search box.
  const cards = useMemo(() => {
    const q = search.toLowerCase().trim()
    const catRank = (c: PropertyCategory) => {
      const i = CATEGORY_ORDER.indexOf(c)
      return i === -1 ? CATEGORY_ORDER.length : i
    }
    return STYLE_PROPERTY_CATALOG
      .slice()
      .sort((a, b) => {
        const ca = catRank(a.category)
        const cb = catRank(b.category)
        if (ca !== cb) return ca - cb
        return a.key.localeCompare(b.key)
      })
      .filter(
        (c) =>
          !q ||
          c.key.toLowerCase().includes(q) ||
          c.category.toLowerCase().includes(q) ||
          c.description.toLowerCase().includes(q) ||
          c.godotMapping.toLowerCase().includes(q),
      )
  }, [search])

  return (
  <Box sx={Styles.root}>
    <Typography variant="h4" component="h1" gutterBottom>
      Styling
    </Typography>
    <Typography variant="body1" paragraph>
      Godot has no USS/CSS. In ReactiveUI you style any host element by passing a{' '}
      <strong><code>style</code> Dictionary</strong> — <code>style={'{{ … }}'}</code> — and the{' '}
      <strong><code>RuitkStyle</code></strong> layer maps it onto Godot <code>Control</code>{' '}
      properties, size flags, and <code>Theme</code> / <code>StyleBox</code> overrides. It is the
      only place that knows Godot styling APIs, so you never touch <code>add_theme_*_override</code>{' '}
      or build a <code>StyleBoxFlat</code> by hand.
    </Typography>

    <Alert severity="info" sx={{ mb: 3 }}>
      <code>RuitkStyle</code> and <code>RuitkStyleSheet</code> are global{' '}
      <code>class_name</code>s — available anywhere once the <code>reactive_ui_toolkit</code> addon is
      enabled. You rarely call them directly; the <code>style</code> and <code>classes</code> props
      do the work.
    </Alert>

    {/* ── Three layers ──────────────────────────────────────── */}
    <Typography variant="h5" component="h2" gutterBottom>
      Three layers of coverage
    </Typography>
    <Typography variant="body1" paragraph>
      A style dict blends three levels of explicitness, from the common 90% to full theme reach.
      From 0.9.0 every key is the <strong>literal Godot name</strong> — the property, theme item,
      or <code>StyleBoxFlat</code> property it sets:
    </Typography>
    <Box component="ol" sx={{ pl: 3, mb: 2 }}>
      <li>
        <strong>Control properties &amp; theme items</strong> —{' '}
        <code>custom_minimum_size</code>, <code>size_flags_horizontal</code>,{' '}
        <code>font_size</code>, <code>font_color</code>, <code>separation</code>,{' '}
        <code>modulate</code>, <code>rotation</code> (radians, Godot semantics),{' '}
        <code>tooltip_text</code>, and more. Each maps 1:1 to the Control property or theme
        override of the same name. (<code>min_width</code> / <code>min_height</code> are kept as
        documented extensions.)
      </li>
      <li>
        <strong>StyleBox builder</strong> — <code>bg_color</code>, <code>border_color</code>,{' '}
        <code>border_width_all</code>, <code>corner_radius_all</code>, and{' '}
        <code>content_margin_all</code> combine into a single <code>StyleBoxFlat</code> applied to
        the control&apos;s primary stylebox slot (PanelContainer, Button, LineEdit, ProgressBar).
        The <code>*_all</code> keys mirror Godot&apos;s own <code>set_*_all</code> setters, and{' '}
        <em>any</em> <code>StyleBoxFlat</code> property is accepted verbatim.
      </li>
      <li>
        <strong>Generic theme channels</strong> — <code>colors</code>, <code>constants</code>,{' '}
        <code>fonts</code>, <code>font_sizes</code>, <code>icons</code>, and{' '}
        <code>styleboxes</code> reach <em>any</em> theme item of <em>any</em> control by exact name
        (100% coverage).
      </li>
    </Box>

    <CodeBlock language="gdscript" code={EXAMPLE_IMPORT} />

    {/* ── StyleBox from one dict ────────────────────────────── */}
    <Typography variant="h5" component="h2" gutterBottom sx={{ mt: 4 }}>
      A StyleBox from one dict
    </Typography>
    <Typography variant="body1" paragraph>
      The box keys build a single <code>StyleBoxFlat</code>. This one dict gives a panel a
      background, rounded corners, a border, and inner padding:
    </Typography>
    <CodeBlock
      language="gdscript"
      code={`<PanelContainer style={ {\n    "bg_color": Color(0.16, 0.17, 0.24),\n    "corner_radius_all": 10,\n    "border_width_all": 2,\n    "border_color": Color(0.4, 0.5, 0.85),\n    "content_margin_all": 16,\n} } />`}
    />
    <Alert severity="warning" sx={{ mt: 1, mb: 2 }}>
      The box keys need a control with a primary stylebox slot (PanelContainer / Panel / Button /
      LineEdit / ProgressBar). Requesting them on a bare <code>Label</code> or a box container
      warns once and does nothing — use a <code>PanelContainer</code> wrapper for the background.
    </Alert>

    {/* ── Three ways to reuse ───────────────────────────────── */}
    <Typography variant="h5" component="h2" gutterBottom sx={{ mt: 4 }}>
      Three ways to author a style
    </Typography>
    <Typography variant="body1" paragraph>
      Inline for one-offs, a shared constant for reuse across a file, or a named bundle for reuse
      across the whole app:
    </Typography>
    <CodeBlock language="gdscript" code={EXAMPLE_BOTH_APIs} />

    {/* ── Style modules ─────────────────────────────────────── */}
    <Typography id="style-modules" variant="h5" component="h2" gutterBottom sx={{ mt: 4 }}>
      Style modules (<code>.style.guitkx</code>)
    </Typography>
    <Typography variant="body1" paragraph>
      A <strong>style module</strong> is a <code>.guitkx</code> file whose name carries the{' '}
      <code>.style</code> infix and whose declarations are all <code>export</code>ed values. It
      holds no markup and no component — it is where a look lives. The compiler emits a sibling{' '}
      <code>.gd</code>, so importing one costs nothing at render time.
    </Typography>
    <Typography variant="body1" paragraph>
      Why a module rather than a literal at the use site: a style that appears in three markup
      blocks has to be changed in three places, and the third one is how &ldquo;all the cards look
      the same&rdquo; quietly stops being true. Naming it once also makes the intent readable —{' '}
      <code>PANEL</code> says what it is; the dict says how it was built.
    </Typography>
    <CodeBlock language="gdscript" code={EXAMPLE_STYLE_MODULE} />

    <Typography variant="h6" component="h3" gutterBottom sx={{ mt: 3 }}>
      Importing and applying
    </Typography>
    <Typography variant="body1" paragraph>
      Style modules are imported like any other module — named imports for the handful you use, or{' '}
      <code>import * as Alias</code> when you would rather see where a value came from at every use
      site. The specifier is the file path <em>without</em> the <code>.guitkx</code> extension:{' '}
      <code>&quot;./card.style&quot;</code>, <code>&quot;../shared/card.style&quot;</code>, or{' '}
      <code>&quot;~/ui/card.style&quot;</code> from the project root.
    </Typography>
    <CodeBlock language="gdscript" code={EXAMPLE_STYLE_MODULE_USE} />
    <Alert severity="info" sx={{ mt: 1, mb: 2 }}>
      Value imports are <strong>eager</strong> — they lower to a <code>const</code> preload — so a
      cycle between two style modules is an error (<code>GUITKX2306</code>), unlike component
      imports, which resolve lazily and may cycle. Referencing a name you did not import is{' '}
      <code>GUITKX2305</code>; importing one you never use is <code>GUITKX2304</code>.
    </Alert>
    <Alert severity="warning" sx={{ mb: 2 }}>
      A generated <code>.gd</code> is not a <code>@tool</code> script, and Godot never runs a
      non-tool script&apos;s <code>static var</code> initialisers <em>in the editor</em>. A style
      module read from <code>@tool</code> editor code therefore comes back empty — silently. This
      only affects editor-time code; at runtime, and in the <code>.guitkx</code> hot-reload path,
      style modules behave normally. Export a <em>function</em> instead of a value if an editor
      plugin has to read it.
    </Alert>

    {/* ── @uss / @theme ─────────────────────────────────────── */}
    <Typography id="uss-directive" variant="h5" component="h2" gutterBottom sx={{ mt: 4 }}>
      Whole-subtree looks: <code>@uss</code> / <code>@theme</code>
    </Typography>
    <Typography variant="body1" paragraph>
      A style dict decorates one element. A Godot <code>Theme</code> resource decorates a whole
      subtree, and <code>@uss</code> is how a <code>.guitkx</code> file attaches one: it preloads
      the resource and hands it to the component&apos;s <strong>root element</strong>, which every
      Control beneath inherits through Godot&apos;s own theme cascade.{' '}
      <code>@theme</code> is an alias — the same directive under the name Godot users reach for
      first.
    </Typography>
    <CodeBlock language="gdscript" code={EXAMPLE_THEME_DIRECTIVE} />
    <Box component="ul" sx={{ pl: 3, mb: 2 }}>
      <li>
        Preamble only — before the first declaration, alongside <code>import</code> and{' '}
        <code>@class_name</code>.
      </li>
      <li>
        <strong>One per file</strong>: a root control holds a single <code>Theme</code>. A second
        one is <code>GUITKX2210</code>.
      </li>
      <li>
        Component files only, and the root must be a single <em>element</em> — a fragment or an
        array root has nothing to receive the theme.
      </li>
      <li>
        A root that sets <code>theme</code> itself wins; <code>@uss</code> never overwrites an
        explicit prop.
      </li>
      <li>
        Accepts <code>res://</code>, <code>uid://</code> and <code>~/</code> paths. The{' '}
        <code>~/</code> root is the same one <code>guitkx.config.json</code> defines for imports.
      </li>
    </Box>
    <Alert severity="info" sx={{ mb: 2 }}>
      The two compose the way they do in the engine: the <code>Theme</code> sets the floor, a{' '}
      <code>style</code> dict on an element wins where it speaks. Reach for <code>@uss</code> for
      a project-wide look authored in Godot&apos;s theme editor, and for a style module for the
      per-element overrides that live with your components. See the{' '}
      <strong>Style modules</strong> demo in the gallery (
      <code>examples/demos/style_module/</code>) for both together.
    </Alert>

    {/* ── Jump links ────────────────────────────────────────── */}
    <Box sx={{ display: 'flex', gap: 1, flexWrap: 'wrap', mb: 2, mt: 4 }}>
      <Chip label="Key reference" component="a" href="#key-reference" clickable size="small" />
      <Chip label="Style modules" component="a" href="#style-modules" clickable size="small" />
      <Chip label="@uss / @theme" component="a" href="#uss-directive" clickable size="small" />
      <Chip label="Patterns" component="a" href="#patterns" clickable size="small" />
      <Chip label="Per-state styles" component="a" href="#per-state" clickable size="small" />
      <Chip label="Theme channels" component="a" href="#theme-channels" clickable size="small" />
      <Chip label="Named bundles" component="a" href="#stylesheets" clickable size="small" />
    </Box>

    {/* ── Key reference ─────────────────────────────────────── */}
    <Typography id="key-reference" variant="h4" component="h2" gutterBottom>
      Style-key reference
    </Typography>
    <Typography variant="body1" paragraph>
      Every key understood by <code>RuitkStyle</code>. Click a card to see its Godot mapping and an
      example value. Anything not listed here (anchors, offsets, arbitrary <code>Control</code>{' '}
      properties) is a plain prop on the element, not part of <code>style</code>.
    </Typography>

    <TextField
      size="small"
      placeholder="Filter keys…"
      value={search}
      onChange={(e) => setSearch(e.target.value)}
      sx={{ mb: 2, maxWidth: 360 }}
      fullWidth
    />

    {cards.map((card) => (
      <PropertyCardView key={card.key} card={card} />
    ))}

    {cards.length === 0 && (
      <Typography variant="body2" color="text.secondary" sx={{ mb: 2 }}>
        No keys match &quot;{search}&quot;.
      </Typography>
    )}

    {/* ── Patterns ──────────────────────────────────────────── */}
    <Typography id="patterns" variant="h4" component="h2" gutterBottom sx={{ mt: 4 }}>
      Patterns
    </Typography>

    <Typography variant="h5" component="h2" gutterBottom>
      Conditional styles
    </Typography>
    <Typography variant="body1" paragraph>
      A style dict is a plain GDScript <code>Dictionary</code> — build it with ternaries,{' '}
      <code>if</code>/<code>else</code>, or any expression, typically from hook state:
    </Typography>
    <CodeBlock language="gdscript" code={EXAMPLE_CONDITIONAL} />

    <Typography variant="h5" component="h2" gutterBottom>
      Inline styles
    </Typography>
    <CodeBlock language="gdscript" code={EXAMPLE_INLINE} />

    {/* ── Per-state styles ──────────────────────────────────── */}
    <Typography id="per-state" variant="h4" component="h2" gutterBottom sx={{ mt: 4 }}>
      Per-state StyleBox slots
    </Typography>
    <Typography variant="body1" paragraph>
      Godot retains hover / pressed / focus / disabled / read_only states natively — no event
      wiring. Nest a style dict under the matching key and RuitkStyle builds a{' '}
      <code>StyleBoxFlat</code> for that slot:
    </Typography>
    <CodeBlock
      language="gdscript"
      code={`<Button text="Hover me" style={ {\n    "bg_color": Color(0.2, 0.2, 0.25),\n    "corner_radius_all": 8,\n    "content_margin_all": 12,\n    "hover":   { "bg_color": Color(0.3, 0.6, 0.9) },\n    "pressed": { "bg_color": Color(0.2, 0.45, 0.75) },\n} } />`}
    />
    <Alert severity="info" sx={{ mt: 1, mb: 2 }}>
      Available slots vary by control — Button has <code>hover</code> / <code>pressed</code> /{' '}
      <code>disabled</code> / <code>focus</code>; LineEdit has <code>focus</code> /{' '}
      <code>read_only</code>. Requesting a slot a control lacks warns once and is ignored.
    </Alert>

    {/* ── Theme channels ────────────────────────────────────── */}
    <Typography id="theme-channels" variant="h4" component="h2" gutterBottom sx={{ mt: 4 }}>
      Generic theme channels
    </Typography>
    <Typography variant="body1" paragraph>
      When a shorthand does not exist for the theme item you need, the six channels reach any theme
      item of any control by its exact Godot name. Each channel is a{' '}
      <code>{'{ name: value }'}</code> map:
    </Typography>
    <TableContainer component={Paper} variant="outlined" sx={{ mb: 2 }}>
      <Table size="small">
        <TableHead>
          <TableRow>
            <TableCell><strong>Channel</strong></TableCell>
            <TableCell><strong>Value type</strong></TableCell>
            <TableCell><strong>Applies via</strong></TableCell>
          </TableRow>
        </TableHead>
        <TableBody>
          <TableRow><TableCell><code>colors</code></TableCell><TableCell><code>Color</code></TableCell><TableCell><code>add_theme_color_override</code></TableCell></TableRow>
          <TableRow><TableCell><code>constants</code></TableCell><TableCell><code>int</code></TableCell><TableCell><code>add_theme_constant_override</code></TableCell></TableRow>
          <TableRow><TableCell><code>fonts</code></TableCell><TableCell><code>Font</code></TableCell><TableCell><code>add_theme_font_override</code></TableCell></TableRow>
          <TableRow><TableCell><code>font_sizes</code></TableCell><TableCell><code>int</code></TableCell><TableCell><code>add_theme_font_size_override</code></TableCell></TableRow>
          <TableRow><TableCell><code>icons</code></TableCell><TableCell><code>Texture2D</code></TableCell><TableCell><code>add_theme_icon_override</code></TableCell></TableRow>
          <TableRow><TableCell><code>styleboxes</code></TableCell><TableCell><code>StyleBox</code></TableCell><TableCell><code>add_theme_stylebox_override</code></TableCell></TableRow>
        </TableBody>
      </Table>
    </TableContainer>
    <CodeBlock
      language="gdscript"
      code={`<Label text="outlined text" style={ {\n    "font_size": 24,\n    "colors": {\n        "font_color": Color(1, 1, 1),\n        "font_outline_color": Color(0.2, 0.2, 0.6),\n    },\n    "constants": { "outline_size": 4 },\n} } />`}
    />

    {/* ── Named bundles (RuitkStyleSheet) ─────────────────────── */}
    <Typography id="stylesheets" variant="h5" component="h2" sx={{ mt: 6 }} gutterBottom>
      Named style bundles (RuitkStyleSheet)
    </Typography>
    <Typography variant="body1" paragraph>
      <code>RuitkStyleSheet</code> is a tiny userland registry — the reduced-scope analogue of USS
      classes. It maps a class name to a plain style dict (the same shape <code>RuitkStyle</code>{' '}
      consumes). A host element&apos;s <code>classes</code> prop resolves against the registry and
      merges left-to-right, with the element&apos;s inline <code>style</code> winning last.
    </Typography>
    <Alert severity="info" sx={{ mb: 2 }}>
      This is deliberately <strong>not</strong> a CSS engine: there is no selector matching,
      specificity, cascade, or inheritance — just an ordered dictionary merge. For real theming,
      use Godot&apos;s <code>Theme</code>/<code>StyleBox</code> (via <code>style</code>) or a{' '}
      <code>theme_type_variation</code>.
    </Alert>

    <Typography variant="h6" component="h3" sx={{ mt: 3 }} gutterBottom>
      Registering bundles
    </Typography>
    <Typography variant="body1" paragraph>
      Register a single bundle with <code>RuitkStyleSheet.register(name, style)</code>, or bulk-register
      a map with <code>RuitkStyleSheet.merge(map)</code> — a good fit for an autoload&apos;s{' '}
      <code>_ready()</code>.
    </Typography>
    <CodeBlock language="gdscript" code={EXAMPLE_USS_BASIC} />

    <Typography variant="h6" component="h3" sx={{ mt: 3 }} gutterBottom>
      Bulk registration
    </Typography>
    <CodeBlock language="gdscript" code={EXAMPLE_USS_FILE} />

    <Typography variant="h6" component="h3" sx={{ mt: 3 }} gutterBottom>
      Multiple classes
    </Typography>
    <Typography variant="body1" paragraph>
      The <code>classes</code> prop takes an Array of names — they merge in order, so later names
      override earlier ones for any shared keys.
    </Typography>
    <CodeBlock language="gdscript" code={EXAMPLE_USS_MULTIPLE} />

    <Typography variant="h6" component="h3" sx={{ mt: 3 }} gutterBottom>
      Combining bundles + inline style
    </Typography>
    <Typography variant="body1" paragraph>
      Bundles handle the shared baseline; inline <code>style</code> handles dynamic, per-render
      values and always wins last in the merge.
    </Typography>
    <CodeBlock language="gdscript" code={EXAMPLE_USS_COMBINED} />

    <Alert severity="info" sx={{ mt: 2 }}>
      <strong>Specificity:</strong> the merge order is bundles (left-to-right) then inline{' '}
      <code>style</code>. There is no cascade or inheritance — the last dict to set a key wins.
    </Alert>

    {/* ── Table of contents ─────────────────────────────────── */}
    <Paper variant="outlined" sx={{ p: 2, mt: 6 }}>
      <Typography variant="h6" gutterBottom>
        Table of contents
      </Typography>
      <Box component="ul" sx={{ m: 0, pl: 2 }}>
        <li><Link href="#key-reference">Style-key reference</Link></li>
        <li><Link href="#patterns">Patterns</Link></li>
        <li><Link href="#per-state">Per-state StyleBox slots</Link></li>
        <li><Link href="#theme-channels">Generic theme channels</Link></li>
        <li><Link href="#stylesheets">Named style bundles (RuitkStyleSheet)</Link></li>
      </Box>
    </Paper>
  </Box>
  )
}
