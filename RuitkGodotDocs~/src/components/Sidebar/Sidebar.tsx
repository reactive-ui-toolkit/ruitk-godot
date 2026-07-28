import type { FC } from 'react'
import { useLocation, Link as RouterLink } from 'react-router-dom'
import { Box, List, ListItemButton, ListItemText, Collapse, Divider, Typography } from '@mui/material'
import ExpandLess from '@mui/icons-material/ExpandLess'
import ExpandMore from '@mui/icons-material/ExpandMore'
import { useState, useMemo } from 'react'
import { getFilteredSections } from '../../docs'
import { useSelectedVersion } from '../../contexts/VersionContext'
import Styles from './Sidebar.style'

export const Sidebar: FC = () => {
  const location = useLocation()
  const { selectedVersion } = useSelectedVersion()
  const sections = useMemo(() => getFilteredSections(selectedVersion), [selectedVersion])
  const displaySections = sections.flatMap((sec) =>
    sec.title === 'Components' && sec.pages.some((p) => p.group)
      ? [
          {
            ...sec,
            id: 'components-common',
            title: 'Common Components',
            pages: sec.pages.filter((p) => p.group === 'basic'),
          },
          {
            ...sec,
            id: 'components-uncommon',
            title: 'Uncommon Components',
            pages: sec.pages.filter((p) => p.group === 'advanced' || !p.group),
          },
        ]
      : [sec],
  )

  const [open, setOpen] = useState<Record<string, boolean>>(() => {
    const init: Record<string, boolean> = {}
    displaySections.forEach((sec, idx) => (init[sec.id] = idx === 0))
    return init
  })

  return (
    <Box sx={Styles.root}>
      <Box sx={{ px: 2, py: 1.5 }}>
        <Typography variant="overline" color="text.secondary">
          Docs
        </Typography>
      </Box>
      <List disablePadding>
        {displaySections.map((sec) => {
          const expanded = !!open[sec.id]
          const isLeafSection = sec.pages.length === 1
          const firstPage = sec.pages[0]

          if (isLeafSection) {
            return (
              <Box key={sec.id}>
                <ListItemButton
                  component={RouterLink}
                  to={firstPage.path}
                  selected={location.pathname === firstPage.path}
                >
                  <ListItemText
                    primary={
                      <Typography sx={Styles.sectionTitle}>
                        {sec.title}
                      </Typography>
                    }
                  />
                </ListItemButton>
                <Divider />
              </Box>
            )
          }

          return (
            <Box key={sec.id}>
              <ListItemButton onClick={() => setOpen({ ...open, [sec.id]: !open[sec.id] })}>
                <ListItemText
                  primary={
                    <Typography sx={Styles.sectionTitle}>
                      {sec.title}
                    </Typography>
                  }
                />
                {expanded ? <ExpandLess /> : <ExpandMore />}
              </ListItemButton>
              <Collapse in={expanded} timeout="auto" unmountOnExit>
                <List disablePadding>
                  {sec.pages.map((p) => (
                    <ListItemButton
                      key={p.id}
                      component={RouterLink}
                      to={p.path}
                      selected={location.pathname === p.path}
                      sx={Styles.childItem}
                    >
                      <ListItemText primary={p.title} />
                    </ListItemButton>
                  ))}
                </List>
              </Collapse>
              <Divider />
            </Box>
          )
        })}
      </List>
    </Box>
  )
}
