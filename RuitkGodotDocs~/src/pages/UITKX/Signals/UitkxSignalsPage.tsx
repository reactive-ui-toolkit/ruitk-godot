import type { FC } from 'react'
import { Alert, Box, List, ListItem, ListItemText, Typography } from '@mui/material'
import { CodeBlock } from '../../../components/CodeBlock/CodeBlock'
import Styles from '../../Signals/SignalsPage.style'
import {
  UITKX_SIGNALS_COMPONENT_EXAMPLE,
  UITKX_SIGNALS_INSTANCE_EXAMPLE,
  UITKX_SIGNALS_RUNTIME_EXAMPLE,
} from './UitkxSignalsPage.example'

export const UitkxSignalsPage: FC = () => (
  <Box sx={Styles.root}>
    <Typography variant="h4" component="h1" gutterBottom>
      Signals
    </Typography>
    <Typography variant="body1" paragraph>
      A <code>RuitkSignal</code> is a lightweight reactive value store that lives <em>outside</em> the
      component tree. Components subscribe to it with <code>useSignal(...)</code> and re-render
      when the value — or a selected slice of it — changes. It is the ideal tool whenever you want a
      single source of truth shared across components without prop-drilling (selection, filters,
      global preferences, player stats).
    </Typography>
    <Alert severity="info" sx={{ mb: 2 }}>
      It is named <code>RuitkSignal</code>, not <code>Signal</code>, because Godot already uses
      &quot;signal&quot; for its own event mechanism. Do not confuse the two — a{' '}
      <code>RuitkSignal</code> is a store you read with a hook; a Godot <code>signal</code> is what
      event props connect to.
    </Alert>

    <Box sx={Styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        Concepts
      </Typography>
      <List sx={Styles.list}>
        <ListItem disablePadding>
          <ListItemText primary={<>Create a standalone store with <code>RuitkSignal.new(initial)</code> and share the instance (an autoload, a <code>static var</code>, …).</>} />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary={<>Or use the process-wide registry: <code>RuitkSignals.get_or_create(key, initial)</code> lazily creates one shared signal per string key, so any component anywhere that reads the same key sees the same store.</>} />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary={<>Update with <code>signal.update(func(old): return next)</code> or <code>signal.set_value(next)</code>. Both notify subscribers only when the value actually changes.</>} />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary={<>Read outside components with <code>signal.get_value()</code> and <code>signal.subscribe(cb)</code> (which returns an unsubscribe <code>Callable</code>); inside components use <code>useSignal(...)</code>.</>} />
        </ListItem>
      </List>
    </Box>

    <Box sx={Styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        Runtime access
      </Typography>
      <Typography variant="body1" paragraph>
        Outside of components, work with the signal directly. The registry is a static
        (process-global) dictionary, so keyed signals outlive the components that read them — that
        is the point (shared app state). Call <code>RuitkSignals.clear()</code> on a full session
        reset if you want to drop keyed state.
      </Typography>
      <CodeBlock language="gdscript" code={UITKX_SIGNALS_RUNTIME_EXAMPLE} />
    </Box>

    <Box sx={Styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        Using signals in components
      </Typography>
      <Typography variant="body1" paragraph>
        Use <code>useSignal(...)</code> to read a signal and re-render when it changes. You can
        project a slice of a larger value with the selector argument, and supply a custom equality{' '}
        <code>comparer</code> to control when a change counts.
      </Typography>
      <List sx={Styles.list}>
        <ListItem disablePadding>
          <ListItemText primary={<><code>useSignal(sig)</code> — subscribe and re-render on change.</>} />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary={<><code>useSignal(sig, selector)</code> — project a slice with <code>selector(value)</code>; re-render only when the selected slice changes.</>} />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary={<><code>useSignal(sig, selector, comparer)</code> — custom equality via <code>comparer(old, new) -&gt; bool</code>.</>} />
        </ListItem>
        <ListItem disablePadding>
          <ListItemText primary={<><code>useSignalKey(key, initial, selector, comparer)</code> — the same, but resolves the shared signal from the registry by key.</>} />
        </ListItem>
      </List>
      <CodeBlock language="gdscript" code={UITKX_SIGNALS_COMPONENT_EXAMPLE} />
      <Typography variant="body1" paragraph sx={{ mt: 2 }}>
        A standalone instance shared via a top-level value declaration works the same way — and the
        selector lets a component re-render only for the slice it cares about:
      </Typography>
      <CodeBlock language="gdscript" code={UITKX_SIGNALS_INSTANCE_EXAMPLE} />
    </Box>

    <Box sx={Styles.section}>
      <Typography variant="h5" component="h2" gutterBottom>
        Change detection — build a new collection to notify
      </Typography>
      <Typography variant="body1" paragraph>
        Change-detection is reference-aware (identity comparison, like GDScript reference
        equality): value types (<code>int</code>, <code>float</code>,{' '}
        <code>String</code>, <code>Vector2</code>, …) compare by value, while reference types
        (<code>Array</code>, <code>Dictionary</code>, <code>Object</code>) compare by{' '}
        <strong>identity</strong>. So replacing a collection with a freshly-built equal one{' '}
        <em>does</em> notify (a new reference), but mutating the same dictionary in place and
        setting it back does <em>not</em>. Build a new collection to signal a change — or pass a
        custom <code>comparer</code> to <code>useSignal</code> if you must detect in-place
        mutation.
      </Typography>
    </Box>
  </Box>
)
