import type { FC } from 'react'
import { Alert, Box, Typography } from '@mui/material'
import { CodeBlock } from '../../../components/CodeBlock/CodeBlock'
import Styles from '../../GettingStarted/GettingStartedPage.style'
import { PORTAL_BASIC, PORTAL_TARGET } from './UitkxPortalPage.example'

export const UitkxPortalPage: FC = () => (
  <Box sx={Styles.root}>
    <Typography variant="h4" component="h1" gutterBottom>
      Portal
    </Typography>
    <Typography variant="body1" paragraph>
      <code>V.portal</code> renders its children under a different Godot{' '}
      <code>Node</code> — outside the normal component hierarchy — instead of the
      component&apos;s own container. This is useful for modals, tooltips, and
      overlays that need to visually escape their parent&apos;s clipping or draw
      order.
    </Typography>
    <Alert severity="warning" sx={{ mb: 2 }}>
      Unlike most of the library, <code>Portal</code> has <strong>no markup tag</strong> —{' '}
      <code>{'<Portal>'}</code> is not a recognized <code>.guitkx</code> element. Build it with{' '}
      <code>V.portal(target, children)</code> in your component&apos;s setup code, then render the
      result from an embedded <code>{'{ expr }'}</code> inside the returned markup, as shown below.
    </Alert>

    <Typography variant="h5" component="h2" gutterBottom>
      Signature
    </Typography>
    <CodeBlock language="gdscript" code={`# V is the vnode factory. target is any live Godot Node to parent into.
static func portal(target: Node, children = null, key = null) -> RuitkVNode`} />

    <Typography variant="h5" component="h2" gutterBottom>
      Basic usage
    </Typography>
    <Typography variant="body1" paragraph>
      Provide a live <code>Node</code> as the portal target. The children are
      reconciled and parented under that node, but they stay part of{' '}
      <em>this</em> component&apos;s tree — hooks, effects, and context all work
      as if they rendered inline. In the example below the modal is declared in
      the left column but mounted into the right-hand panel.
    </Typography>
    <CodeBlock language="gdscript" code={PORTAL_BASIC} />

    <Typography variant="h5" component="h2" gutterBottom>
      Getting a target node
    </Typography>
    <Typography variant="body1" paragraph>
      Unlike the Unity reference&apos;s <code>PortalContextKeys</code>, Godot has
      no predefined portal slots — the target is just a <code>Node</code>. The
      two common ways to get one are to capture a node rendered elsewhere in the
      same tree with a <code>ref</code>, or to reach an overlay node that lives
      outside the reactive tree (for example a <code>CanvasLayer</code> in your
      scene) through the mount viewport or an autoload.
    </Typography>
    <CodeBlock language="gdscript" code={PORTAL_TARGET} />

    <Alert severity="info" sx={{ mt: 2 }}>
      A ref-captured target only exists after the first commit, so gate the
      portal behind a &quot;mounted&quot; flag set in a mount effect (as shown
      above) — otherwise the target is still <code>null</code> on the very first
      render.
    </Alert>

    <Alert severity="info" sx={{ mt: 2 }}>
      Portal children participate in the normal reactive lifecycle (hooks,
      effects, context) even though they render into a different part of the
      node tree — the same guarantee React portals give.
    </Alert>
  </Box>
)
