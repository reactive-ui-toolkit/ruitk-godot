import type { FC } from 'react'
import { useState } from 'react'
import {
  Accordion,
  AccordionDetails,
  AccordionSummary,
  Box,
  Chip,
  Link,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableRow,
  Typography,
} from '@mui/material'
import ExpandMoreIcon from '@mui/icons-material/ExpandMore'
import { CodeBlock } from '../../components/CodeBlock/CodeBlock'
import { getHostElement, type HostElement, type HostProp, type HostSignal } from '../../hostElements'
import { HOST_CONTENT } from '../../hostContent'
import Styles from './ComponentPage.style'

// ---------------------------------------------------------------------------
// Event-prop → Godot-signal resolution (mirrors the host-config binding logic)
// ---------------------------------------------------------------------------

/**
 * Resolve which Godot signal an event prop binds to on a given element.
 * Since 0.9.0 the rule is uniform: `on` + PascalCase(signal name), so
 * `onPressed` → `pressed`, `onValueChanged` → `value_changed`,
 * `onGuiInput` → `gui_input`. Returns the matched signal, or undefined when the
 * element has no such signal (a defensive case — curated `events` shouldn't hit it).
 */
const resolveSignal = (event: string, signals: HostSignal[]): HostSignal | undefined => {
  if (!event.startsWith('on')) return undefined
  // onValueChanged -> value_changed (camelCase → snake_case, minus the `on` prefix).
  const snake = event
    .slice(2)
    .replace(/([a-z0-9])([A-Z])/g, '$1_$2')
    .toLowerCase()
  return signals.find((s) => s.name === snake)
}

/** Format a signal's argument list, e.g. `(int index)` or `()`. */
const formatArgs = (signal: HostSignal | undefined): string => {
  if (!signal || signal.args.length === 0) return '()'
  return `(${signal.args.map((a) => `${a.type} ${a.name}`).join(', ')})`
}

// ---------------------------------------------------------------------------
// Sub-sections
// ---------------------------------------------------------------------------

const EventsTable: FC<{ element: HostElement }> = ({ element }) => (
  <TableContainer>
    <Table size="small">
      <TableHead>
        <TableRow>
          <TableCell sx={{ fontWeight: 700 }}>Event</TableCell>
          <TableCell sx={{ fontWeight: 700 }}>Godot signal</TableCell>
          <TableCell sx={{ fontWeight: 700 }}>Arguments</TableCell>
        </TableRow>
      </TableHead>
      <TableBody>
        {element.events.map((event) => {
          const signal = resolveSignal(event, element.signals)
          return (
            <TableRow key={event}>
              <TableCell>
                <code>{event}</code>
              </TableCell>
              <TableCell>
                {signal ? <code>{signal.name}</code> : <Typography variant="body2" color="text.secondary">—</Typography>}
              </TableCell>
              <TableCell>
                <code>{formatArgs(signal)}</code>
              </TableCell>
            </TableRow>
          )
        })}
      </TableBody>
    </Table>
  </TableContainer>
)

const PropsTable: FC<{ entries: HostProp[] }> = ({ entries }) => (
  <TableContainer>
    <Table size="small">
      <TableHead>
        <TableRow>
          <TableCell sx={{ fontWeight: 700 }}>Property</TableCell>
          <TableCell sx={{ fontWeight: 700 }}>Type</TableCell>
        </TableRow>
      </TableHead>
      <TableBody>
        {entries.map((p) => (
          <TableRow key={p.name}>
            <TableCell>
              <code>{p.name}</code>
            </TableCell>
            <TableCell>
              {p.enum ? (
                <Box sx={{ display: 'flex', flexDirection: 'column', gap: 0.5 }}>
                  <code>{p.type}</code>
                  <Typography variant="caption" color="text.secondary">
                    enum: {p.enum}
                  </Typography>
                </Box>
              ) : (
                <code>{p.type}</code>
              )}
            </TableCell>
          </TableRow>
        ))}
      </TableBody>
    </Table>
  </TableContainer>
)

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------

export const ComponentPage: FC<{ tag: string }> = ({ tag }) => {
  const element = getHostElement(tag)
  const content = HOST_CONTENT[tag]
  const [baseOpen, setBaseOpen] = useState(false)

  if (!element) {
    return (
      <Box sx={Styles.root}>
        <Typography variant="h4" component="h1" gutterBottom>
          {tag}
        </Typography>
        <Typography variant="body1">Unknown host element.</Typography>
      </Box>
    )
  }

  const ownProps = element.props.filter((p) => !p.inherited)
  const inheritedProps = element.props.filter((p) => p.inherited)
  const godotClassUrl = `https://docs.godotengine.org/en/stable/classes/class_${element.godotClass.toLowerCase()}.html`

  return (
    <Box sx={Styles.root}>
      <Box sx={{ display: 'flex', alignItems: 'baseline', gap: 1.5, flexWrap: 'wrap' }}>
        <Typography variant="h4" component="h1" gutterBottom>
          {element.tag}
        </Typography>
        <Typography variant="body2" color="text.secondary" sx={{ whiteSpace: 'nowrap' }}>
          Godot class: <code>{element.godotClass}</code>
        </Typography>
      </Box>

      {content && (
        <Typography variant="body1" paragraph>
          {content.blurb}
        </Typography>
      )}

      {content && (
        <Box sx={Styles.section}>
          <Typography variant="h5" component="h2" gutterBottom>
            Usage
          </Typography>
          <CodeBlock language="jsx" code={content.guitkx} />
        </Box>
      )}

      {element.events.length > 0 && (
        <Box sx={Styles.section}>
          <Typography variant="h5" component="h2" gutterBottom>
            Events
          </Typography>
          <Typography variant="body2" paragraph sx={{ opacity: 0.7 }}>
            Event props are named <code>on</code> + PascalCase(signal name) and bind to the Godot
            signal shown below — the rule works for <em>every</em> signal of the node, not just the
            curated ones here. The native <code>on_&lt;signal&gt;</code> spelling also works,
            verbatim.
          </Typography>
          <EventsTable element={element} />
        </Box>
      )}

      <Box sx={Styles.section}>
        <Box sx={{ display: 'flex', alignItems: 'baseline', gap: 1 }}>
          <Typography variant="h5" component="h2" gutterBottom>
            Properties
          </Typography>
          <Chip label={`${element.props.length} total`} size="small" variant="outlined" />
        </Box>
        <Typography variant="body2" paragraph sx={{ opacity: 0.7 }}>
          Property names are the Godot names (snake_case), set as attributes in markup.
        </Typography>

        {ownProps.length > 0 && <PropsTable entries={ownProps} />}

        {inheritedProps.length > 0 && (
          <Accordion
            expanded={baseOpen}
            onChange={() => setBaseOpen(!baseOpen)}
            disableGutters
            sx={{ mt: 2, boxShadow: 'none', '&:before': { display: 'none' } }}
          >
            <AccordionSummary expandIcon={<ExpandMoreIcon />}>
              <Typography variant="subtitle2">
                Inherited properties ({inheritedProps.length})
              </Typography>
            </AccordionSummary>
            <AccordionDetails>
              <PropsTable entries={inheritedProps} />
            </AccordionDetails>
          </Accordion>
        )}
      </Box>

      <Box sx={Styles.section}>
        <Typography variant="h5" component="h2" gutterBottom>
          Godot reference
        </Typography>
        <Typography variant="body1" paragraph>
          See the{' '}
          <Link href={godotClassUrl} target="_blank" rel="noreferrer">
            {element.godotClass} class reference
          </Link>{' '}
          in the official Godot documentation for the full property, method, and signal surface.
        </Typography>
      </Box>
    </Box>
  )
}
