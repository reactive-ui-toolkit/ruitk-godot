import type { FC } from 'react'
import { Alert, Box, Typography } from '@mui/material'
import { CodeBlock } from '../../../components/CodeBlock/CodeBlock'
import Styles from '../../GettingStarted/GettingStartedPage.style'
import { SUSPENSE_CALLBACK, SUSPENSE_SIGNAL } from './UitkxSuspensePage.example'

export const UitkxSuspensePage: FC = () => (
  <Box sx={Styles.root}>
    <Typography variant="h4" component="h1" gutterBottom>
      Suspense
    </Typography>
    <Typography variant="body1" paragraph>
      <code>V.suspense</code> shows a fallback node while an asynchronous
      operation completes, then renders its children once the operation is ready.
    </Typography>
    <Alert severity="warning" sx={{ mb: 2 }}>
      Unlike most of the library, <code>Suspense</code> has <strong>no markup tag</strong> —{' '}
      <code>{'<Suspense>'}</code> is not a recognized <code>.guitkx</code> element. Call{' '}
      <code>V.suspense(props, children)</code> from an embedded <code>{'{ expr }'}</code> inside a{' '}
      normal <code>.guitkx</code> component instead, e.g.{' '}
      <code>{'<VBoxContainer>{ V.suspense({...}, [...]) }</VBoxContainer>'}</code>.
    </Alert>
    <Alert severity="info" sx={{ mb: 2 }}>
      GDScript has no throw-to-suspend (React&apos;s mechanism relies on throwing
      a promise). So this <code>Suspense</code> is a plain function component
      driven by either an awaited Godot <code>Signal</code> or a per-frame poll —
      not an exception. There is no <code>SuspendUntil</code> hook; readiness
      comes entirely from the props below.
    </Alert>

    <Typography variant="h5" component="h2" gutterBottom>
      Props
    </Typography>
    <CodeBlock language="gdscript" code={`V.suspense({
  "fallback":     <RuitkVNode>,   # shown while not ready (optional; renders nothing if omitted)
  "ready_signal": <Signal>,     # a Godot Signal — awaited ONCE; readiness flips when it fires
  "is_ready":     func() -> bool,  # checked immediately, then polled each frame if no signal
}, [ ...the real content ])`} />
    <Typography variant="body1" paragraph>
      Provide <code>ready_signal</code> <em>or</em> <code>is_ready</code> (a
      signal takes precedence). If <code>is_ready()</code> already returns{' '}
      <code>true</code> on the first check, the boundary becomes ready
      synchronously and never shows the fallback.
    </Typography>

    <Typography variant="h5" component="h2" gutterBottom>
      Poll mode — is_ready
    </Typography>
    <Typography variant="body1" paragraph>
      Pass a <code>func() -&gt; bool</code> that returns <code>true</code> when
      loading is complete. It is checked once immediately and then polled every
      frame until it becomes true. Wrap it in <code>useCallback</code> so the
      boundary does not tear down and re-subscribe the poller on every render.
    </Typography>
    <CodeBlock language="gdscript" code={SUSPENSE_CALLBACK} />

    <Typography variant="h5" component="h2" gutterBottom>
      Signal mode — ready_signal
    </Typography>
    <Typography variant="body1" paragraph>
      Pass a Godot <code>Signal</code> directly. The boundary <code>await</code>s
      it once; the fallback is shown until the signal fires. This is the natural
      fit for Godot&apos;s many completion signals (threaded resource loads,
      HTTP requests, tweens, custom loaders).
    </Typography>
    <CodeBlock language="gdscript" code={SUSPENSE_SIGNAL} />

    <Alert severity="info" sx={{ mt: 2 }}>
      Swapping <code>ready_signal</code> / <code>is_ready</code> from a parent
      tears down the stale driver and subscribes to the new one — so a boundary
      can point at a fresh async source without leaking the previous poller or
      awaiter.
    </Alert>
  </Box>
)
