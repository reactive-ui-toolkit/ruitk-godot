import type { FC } from 'react'
import {
  Alert,
  Box,
  Paper,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableRow,
  Typography,
} from '@mui/material'
import { CodeBlock } from '../../../components/CodeBlock/CodeBlock'
import {
  EXAMPLE_BASIC,
  EXAMPLE_RELATIVE,
  EXAMPLE_SHORTHAND,
  EXAMPLE_INLINE,
  EXAMPLE_USS,
} from './AssetsPage.example'

const section = { mt: 4 }

export const AssetsPage: FC = () => (
  <Box>
    <Typography variant="h4" component="h1" gutterBottom>
      Assets &amp; Resources
    </Typography>
    <Typography variant="body1" paragraph>
      ReactiveUI uses Godot&apos;s native resource system — there is no separate asset
      importer or registry. You reference textures, fonts, themes, styleboxes, audio streams,
      and packed scenes by their <code>res://</code> path and pull them in with{' '}
      <code>preload()</code> (compile time) or <code>load()</code> (runtime). The resulting
      resource drops straight into <code>.guitkx</code> markup, an attribute expression, or a{' '}
      <code>style</code> dictionary.
    </Typography>

    <Alert severity="info" sx={{ mb: 2 }}>
      Godot imports assets automatically the moment they land in the project folder — a{' '}
      <code>.import</code> file is generated beside each source file. You never call an import
      API or register anything; <code>preload()</code> / <code>load()</code> just work.
    </Alert>

    {/* ── preload vs load ──────────────────────────────────── */}
    <Box sx={section}>
      <Typography variant="h5" component="h2" gutterBottom id="preload-vs-load">
        preload() vs load()
      </Typography>
      <Typography variant="body1" paragraph>
        <code>preload()</code> takes a <strong>constant</strong> <code>res://</code> path and
        resolves it at compile time — the resource is baked into the export and there is no
        runtime disk hit. <code>load()</code> takes any <code>String</code> expression and
        resolves at runtime — use it when the path is dynamic (a prop, a computed value).
      </Typography>
      <CodeBlock language="gdscript" code={EXAMPLE_BASIC} />
    </Box>

    {/* ── res:// paths ─────────────────────────────────────── */}
    <Box sx={section}>
      <Typography variant="h5" component="h2" gutterBottom id="res-paths">
        res:// Paths
      </Typography>
      <Typography variant="body1" paragraph>
        Resource paths are absolute from the project root and always start with{' '}
        <code>res://</code>. Keeping assets near the component that uses them is a matter of
        folder layout — Godot does not resolve paths relative to the <code>.guitkx</code> file.
      </Typography>
      <CodeBlock language="gdscript" code={EXAMPLE_RELATIVE} />
    </Box>

    {/* ── A texture anywhere a Texture2D fits ──────────────── */}
    <Box sx={section}>
      <Typography variant="h5" component="h2" gutterBottom id="reuse">
        One Resource, Many Slots
      </Typography>
      <Typography variant="body1" paragraph>
        A loaded resource is a plain value — pass it wherever the corresponding Godot type is
        expected. A <code>Texture2D</code>, for example, fits{' '}
        <code>TextureRect.texture</code>, <code>Button.icon</code>,{' '}
        <code>TextureButton.texture_normal</code>, or the <code>icons</code> theme channel of a{' '}
        <code>style</code> dict.
      </Typography>
      <CodeBlock language="gdscript" code={EXAMPLE_SHORTHAND} />
    </Box>

    {/* ── Inline usage ─────────────────────────────────────── */}
    <Box sx={section}>
      <Typography variant="h5" component="h2" gutterBottom id="inline">
        Inline Usage
      </Typography>
      <Typography variant="body1" paragraph>
        You can call <code>preload()</code> or <code>load()</code> directly inside an attribute
        expression — no setup variable needed.
      </Typography>
      <CodeBlock language="gdscript" code={EXAMPLE_INLINE} />
    </Box>

    {/* ── Theme resources ──────────────────────────────────── */}
    <Box sx={section}>
      <Typography variant="h5" component="h2" gutterBottom id="theme-resource">
        Theme Resources
      </Typography>
      <Typography variant="body1" paragraph>
        A Godot <code>Theme</code> (<code>.tres</code>) is just another resource. Preload it and
        hand it to a subtree via the <code>theme</code> prop — every descendant inherits it.
        This is the idiomatic way to apply a full design system, complementary to per-element{' '}
        <code>style</code> overrides.
      </Typography>
      <CodeBlock language="gdscript" code={EXAMPLE_USS} />
      <Typography variant="body2" paragraph sx={{ mt: 1, opacity: 0.7 }}>
        For a single StyleBox instead of a whole Theme, drop a <code>.stylebox.tres</code> into
        the <code>styleboxes</code> theme channel of a <code>style</code> dict — or let{' '}
        <code>RuitkStyle</code> build one from <code>bg_color</code> / <code>border_*</code> /{' '}
        <code>pad</code> for you. See the <strong>Styling</strong> page.
      </Typography>
    </Box>

    {/* ── Resource types ───────────────────────────────────── */}
    <Box sx={section}>
      <Typography variant="h5" component="h2" gutterBottom id="resource-types">
        Common Resource Types
      </Typography>
      <Typography variant="body1" paragraph>
        <code>preload()</code> / <code>load()</code> infer the resource type from the file. These
        are the types you will reach for most often in UI:
      </Typography>
      <TableContainer component={Paper} variant="outlined" sx={{ mb: 2 }}>
        <Table size="small">
          <TableHead>
            <TableRow>
              <TableCell><strong>Extensions</strong></TableCell>
              <TableCell><strong>Godot type</strong></TableCell>
              <TableCell><strong>Where it goes</strong></TableCell>
            </TableRow>
          </TableHead>
          <TableBody>
            <TableRow>
              <TableCell><code>.png .jpg .webp .svg</code></TableCell>
              <TableCell><code>Texture2D</code></TableCell>
              <TableCell><code>TextureRect.texture</code>, <code>Button.icon</code>, <code>icons</code> channel</TableCell>
            </TableRow>
            <TableRow>
              <TableCell><code>.ttf .otf .woff .woff2 .fnt</code></TableCell>
              <TableCell><code>FontFile</code></TableCell>
              <TableCell><code>font</code> style key / <code>fonts</code> channel</TableCell>
            </TableRow>
            <TableRow>
              <TableCell><code>.tres .theme</code> (Theme)</TableCell>
              <TableCell><code>Theme</code></TableCell>
              <TableCell><code>theme</code> prop on any element</TableCell>
            </TableRow>
            <TableRow>
              <TableCell><code>.tres</code> (StyleBox)</TableCell>
              <TableCell><code>StyleBox</code></TableCell>
              <TableCell><code>styleboxes</code> channel of a <code>style</code> dict</TableCell>
            </TableRow>
            <TableRow>
              <TableCell><code>.ogg .wav .mp3</code></TableCell>
              <TableCell><code>AudioStream</code></TableCell>
              <TableCell><code>&lt;AudioStreamPlayer&gt;</code></TableCell>
            </TableRow>
            <TableRow>
              <TableCell><code>.tscn .scn</code></TableCell>
              <TableCell><code>PackedScene</code></TableCell>
              <TableCell>Escape hatch — instance and mount inside a <code>ref</code> callback</TableCell>
            </TableRow>
            <TableRow>
              <TableCell><code>.tres .res</code></TableCell>
              <TableCell><code>Resource</code> (custom)</TableCell>
              <TableCell>Your own data resources, passed as props</TableCell>
            </TableRow>
          </TableBody>
        </Table>
      </TableContainer>
    </Box>

    {/* ── Missing / wrong paths ────────────────────────────── */}
    <Box sx={section}>
      <Typography variant="h5" component="h2" gutterBottom id="diagnostics">
        Missing &amp; Wrong Paths
      </Typography>
      <Typography variant="body1" paragraph>
        Godot validates resource paths for you. A bad <code>preload()</code> path is a{' '}
        <strong>parse error</strong> — the <code>.guitkx</code> compiler surfaces it on the
        generated <code>.gd</code>, and the IDE extension flags it inline. A bad{' '}
        <code>load()</code> path fails at runtime and returns <code>null</code>, so guard dynamic
        loads.
      </Typography>
      <TableContainer component={Paper} variant="outlined" sx={{ mb: 2 }}>
        <Table size="small">
          <TableHead>
            <TableRow>
              <TableCell><strong>Call</strong></TableCell>
              <TableCell><strong>When the path is bad</strong></TableCell>
            </TableRow>
          </TableHead>
          <TableBody>
            <TableRow>
              <TableCell><code>preload(&quot;res://missing.png&quot;)</code></TableCell>
              <TableCell>Compile-time / parse error — build fails, IDE squiggle</TableCell>
            </TableRow>
            <TableRow>
              <TableCell><code>load(some_path)</code></TableCell>
              <TableCell>Returns <code>null</code> at runtime — check before use</TableCell>
            </TableRow>
          </TableBody>
        </Table>
      </TableContainer>
      <CodeBlock
        language="gdscript"
        code={`# Guard a dynamic load so a missing file can't crash the render:\nvar tex = load(image_path)\nif tex == null:\n    tex = preload("res://ui/placeholder.png")`}
      />
    </Box>

    {/* ── Why no registry ──────────────────────────────────── */}
    <Box sx={section}>
      <Typography variant="h5" component="h2" gutterBottom id="no-registry">
        No Asset Registry Needed
      </Typography>
      <Typography variant="body1" paragraph>
        Godot already ships a caching resource loader: repeated <code>load()</code> /{' '}
        <code>preload()</code> of the same path return the same cached instance. There is no
        registry to sync, no import step to trigger, and no runtime codegen. Resources are just
        values you pass around like any other GDScript object.
      </Typography>
      <Alert severity="success">
        Because it is all native Godot, everything works identically in the editor, in exported
        builds, and under hot-reload — nothing special to configure.
      </Alert>
    </Box>
  </Box>
)
