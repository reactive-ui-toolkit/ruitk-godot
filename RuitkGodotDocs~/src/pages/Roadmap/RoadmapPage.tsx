import type { FC } from 'react'
import { Box, Chip, List, ListItem, ListItemText, Typography } from '@mui/material'
import Styles from './RoadmapPage.style'

export const RoadmapPage: FC = () => (
  <Box sx={Styles.root}>
    <Typography variant="h4" component="h1" gutterBottom>
      Roadmap
    </Typography>
    <Typography variant="body1" paragraph>
      Reactive UI Toolkit — Godot is under active development. Below is a high-level view of what is
      done and what is planned. Priorities may shift based on community feedback.
    </Typography>

    <Typography variant="h5" component="h2" gutterBottom sx={{ mt: 2 }}>
      Completed — core runtime
    </Typography>
    <List>
      <ListItem disablePadding>
        <ListItemText primary={<><Chip label="Done" size="small" color="success" sx={{ mr: 1 }} />Fiber reconciler — synchronous render with atomic two-phase commit, keyed reconciliation, and bailout</>} />
      </ListItem>
      <ListItem disablePadding>
        <ListItemText primary={<><Chip label="Done" size="small" color="success" sx={{ mr: 1 }} />Full hook set — useState, useReducer, useEffect, useMemo, useRef, useContext, useSignal, useTween</>} />
      </ListItem>
      <ListItem disablePadding>
        <ListItemText primary={<><Chip label="Done" size="small" color="success" sx={{ mr: 1 }} />~60 curated host elements named 1:1 after Godot classes (containers, buttons, inputs, item-model controls, media), plus an open tag vocabulary — any instantiable Godot Node class via ClassDB (0.9.0)</>} />
      </ListItem>
      <ListItem disablePadding>
        <ListItemText primary={<><Chip label="Done" size="small" color="success" sx={{ mr: 1 }} />Styling redesigned for Godot — RuitkStyle style dicts (Control props + size flags + Theme/StyleBox) and RuitkStyleSheet named bundles</>} />
      </ListItem>
      <ListItem disablePadding>
        <ListItemText primary={<><Chip label="Done" size="small" color="success" sx={{ mr: 1 }} />Signals (RuitkSignal) for app-wide state, plus the client-side router (routes, outlet, navigate, nav_link)</>} />
      </ListItem>
      <ListItem disablePadding>
        <ListItemText primary={<><Chip label="Done" size="small" color="success" sx={{ mr: 1 }} />Fragment, Portal, Suspense, and error-boundary components</>} />
      </ListItem>
      <ListItem disablePadding>
        <ListItemText primary={<><Chip label="Done" size="small" color="success" sx={{ mr: 1 }} />Loyal-to-Godot event handlers (0.9.0) — on + PascalCase(signal name) works for every signal of every node (onPressed, onValueChanged, onGuiInput, …), with on_&lt;signal&gt; as a verbatim escape hatch. Replaces the earlier React-parity aliases (onClick, onChange, …); see MIGRATION-0.9.md</>} />
      </ListItem>
      <ListItem disablePadding>
        <ListItemText primary={<><Chip label="Done" size="small" color="success" sx={{ mr: 1 }} />Prop spread <code>{'{...obj}'}</code> in .guitkx and context handles via Hooks.createContext (React createContext parity)</>} />
      </ListItem>
    </List>

    <Typography variant="h5" component="h2" gutterBottom sx={{ mt: 2 }}>
      Completed — tooling
    </Typography>
    <List>
      <ListItem disablePadding>
        <ListItemText primary={<><Chip label="Done" size="small" color="success" sx={{ mr: 1 }} />.guitkx markup language + @tool compiler that emits a sibling .gd render function on save</>} />
      </ListItem>
      <ListItem disablePadding>
        <ListItemText primary={<><Chip label="Done" size="small" color="success" sx={{ mr: 1 }} />VS Code and Visual Studio extensions — highlighting, completion, hover, diagnostics, formatting (LSP embeds the Rust GDScript analyzer)</>} />
      </ListItem>
      <ListItem disablePadding>
        <ListItemText primary={<><Chip label="Done" size="small" color="success" sx={{ mr: 1 }} />Fast Refresh (hot reload) — saving a .guitkx while the game runs under F5 updates the live UI in place, hook state preserved; dev-only, zero footprint in exported builds</>} />
      </ListItem>
      <ListItem disablePadding>
        <ListItemText primary={<><Chip label="Done" size="small" color="success" sx={{ mr: 1 }} />Native Godot-editor addon (reactive_ui_toolkit_editor) — a full .guitkx editor inside Godot: highlighting, live diagnostics, completion, hover, signature help, go-to-definition, references, rename, outline, project search, multi-file sessions, formatting</>} />
      </ListItem>
      <ListItem disablePadding>
        <ListItemText primary={<><Chip label="Done" size="small" color="success" sx={{ mr: 1 }} />Native GDExtension analyzer backend (reactive_ui_toolkit_analyzer, bundled with the editor addon) — type-aware completion, hover, diagnostics, navigation, rename, and signature help for the GDScript inside .guitkx expressions; feature-detected, in-process, zero config</>} />
      </ListItem>
      <ListItem disablePadding>
        <ListItemText primary={<><Chip label="In progress" size="small" color="info" sx={{ mr: 1 }} />This documentation site (ported from the Unity docs, rewritten for Godot)</>} />
      </ListItem>
    </List>

    <Typography variant="h5" component="h2" gutterBottom sx={{ mt: 2 }}>
      Planned
    </Typography>
    <List>
      <ListItem disablePadding>
        <ListItemText primary={<><Chip label="Planned" size="small" color="info" sx={{ mr: 1 }} />Custom-draw escape hatch — declarative custom rendering for elements that need _draw()-level control</>} />
      </ListItem>
      <ListItem disablePadding>
        <ListItemText primary={<><Chip label="Planned" size="small" color="info" sx={{ mr: 1 }} />More host elements as Godot adds Controls, and coverage for any that need a newer engine version</>} />
      </ListItem>
      <ListItem disablePadding>
        <ListItemText primary={<><Chip label="Planned" size="small" color="info" sx={{ mr: 1 }} />Distribution via the Godot Asset Library, versioned releases, and CI</>} />
      </ListItem>
      <ListItem disablePadding>
        <ListItemText primary={<><Chip label="Planned" size="small" color="info" sx={{ mr: 1 }} />Sample gallery and starter templates covering common UI patterns</>} />
      </ListItem>
    </List>

    <Typography variant="h5" component="h2" gutterBottom sx={{ mt: 2 }}>
      Under consideration
    </Typography>
    <List>
      <ListItem disablePadding>
        <ListItemText primary={<><Chip label="Exploring" size="small" color="warning" sx={{ mr: 1 }} />Component testing utilities (snapshot-style tree assertions)</>} />
      </ListItem>
      <ListItem disablePadding>
        <ListItemText primary={<><Chip label="Exploring" size="small" color="warning" sx={{ mr: 1 }} />Render-count and performance diagnostics overlay for tuning large trees</>} />
      </ListItem>
    </List>
  </Box>
)
