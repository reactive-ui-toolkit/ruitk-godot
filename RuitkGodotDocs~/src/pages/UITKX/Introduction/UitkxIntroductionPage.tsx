import type { FC } from 'react'
import { Box, List, ListItem, ListItemText, Typography } from '@mui/material'
import { CodeBlock } from '../../../components/CodeBlock/CodeBlock'
import Styles from '../../Introduction/IntroductionPage.style'

const QUICK_SAMPLE = `CounterCard() -> RuitkVNode {
  var s = useState(0)
  return (
    <VBoxContainer>
      <Label text={ "Count: %d" % s[0] } />
      <Button text="+" onPressed={ func(): s[1].call(s[0] + 1) } />
    </VBoxContainer>
  )
}`

export const UitkxIntroductionPage: FC = () => (
  <Box sx={Styles.root}>
    <Typography variant="h4" component="h1" gutterBottom>
      Reactive UI Toolkit — Godot
    </Typography>
    <Typography variant="body1" paragraph>
      Reactive UI Toolkit is a React-style UI framework for Godot 4.x, and <code>.guitkx</code> is its
      authoring language. You write function-style components in <code>.guitkx</code> files, use
      hooks for state and effects, and the toolkit reconciles the resulting virtual tree onto Godot{' '}
      <code>Control</code> nodes. There is no JavaScript engine or bridge layer — everything is plain
      GDScript running on Godot's retained-mode scene tree.
    </Typography>

    <CodeBlock language="jsx" code={QUICK_SAMPLE} />

    <Typography variant="h5" component="h2" gutterBottom>
      Highlights
    </Typography>
    <List>
      <ListItem disablePadding>
        <ListItemText primary="Function-style .guitkx components with camelCase hooks and typed props" />
      </ListItem>
      <ListItem disablePadding>
        <ListItemText primary="A fiber reconciler that diffs and batches updates onto the Godot Control tree" />
      </ListItem>
      <ListItem disablePadding>
        <ListItemText primary="Router and Signals utilities that work naturally inside .guitkx" />
      </ListItem>
      <ListItem disablePadding>
        <ListItemText primary="Compiles to a sibling .gd file — no runtime codegen, standard Godot build" />
      </ListItem>
    </List>
  </Box>
)
