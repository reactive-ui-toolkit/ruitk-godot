import type { FC } from 'react'
import { AppBar, Toolbar, Chip, Paper, InputBase, Box, IconButton, Link, Typography, Select, MenuItem, SvgIcon } from '@mui/material'
import { Link as RouterLink } from 'react-router-dom'
import SearchIcon from '@mui/icons-material/Search'
import GitHubIcon from '@mui/icons-material/GitHub'
import Styles from './TopBar.style'
import { PACKAGE_VERSION } from '../../version'
import { SUPPORTED_VERSIONS } from '../../versionManifest'
import { useSelectedVersion } from '../../contexts/VersionContext'
import { DISCORD_INVITE_URL } from '../../links'

export type TopBarProps = { onOpenSearch: () => void }

export const TopBar: FC<TopBarProps> = ({ onOpenSearch }) => {
  const { selectedVersion, setSelectedVersion } = useSelectedVersion()

  return (
    <AppBar position="sticky" color="default" elevation={0} sx={Styles.appBar}>
      <Toolbar sx={Styles.toolbar}>
        <Box sx={Styles.left}>
          <Link component={RouterLink} to="/" underline="none" sx={Styles.titleLink}>
            <Box
              component="img"
              src={`${import.meta.env.BASE_URL}logo.png`}
              alt="Reactive UI Toolkit — Godot logo"
              sx={Styles.logo}
            />
            <Typography variant="h6" sx={Styles.title}>
              Reactive UI Toolkit — Godot
            </Typography>
          </Link>
          <Chip label={`v${PACKAGE_VERSION}`} size="small" />
        </Box>
        <Box sx={Styles.center}>
          <Paper sx={Styles.searchPaper} variant="outlined" onClick={onOpenSearch}>
            <SearchIcon fontSize="small" />
            <InputBase placeholder="Search documentation" sx={Styles.inputFlex} readOnly autoFocus />
          </Paper>
        </Box>
        <Box sx={Styles.right}>
          <Select
            value={selectedVersion}
            onChange={(e) => setSelectedVersion(e.target.value)}
            size="small"
            sx={Styles.versionSelect}
          >
            {SUPPORTED_VERSIONS.map((v) => (
              <MenuItem key={v.version} value={v.version}>
                Godot {v.label}+
              </MenuItem>
            ))}
          </Select>
          <IconButton component={Link} href="https://github.com/reactive-ui-toolkit/ruitk-godot" target="_blank" rel="noreferrer">
            <GitHubIcon />
          </IconButton>
          <IconButton component={Link} href={DISCORD_INVITE_URL} target="_blank" rel="noreferrer" aria-label="Join our Discord">
            <SvgIcon viewBox="0 0 24 24">
              <path d="M19.27 5.33C17.94 4.71 16.5 4.26 15 4a.09.09 0 0 0-.07.03c-.18.33-.39.76-.53 1.09a16.09 16.09 0 0 0-4.8 0c-.14-.34-.35-.76-.54-1.09c-.01-.02-.04-.03-.07-.03c-1.5.26-2.93.71-4.27 1.33c-.01 0-.02.01-.03.02c-2.72 4.07-3.47 8.03-3.1 11.95c0 .02.01.04.03.05c1.8 1.32 3.53 2.12 5.24 2.65c.03.01.06 0 .07-.02c.4-.55.76-1.13 1.07-1.74c.02-.04 0-.08-.04-.09c-.57-.22-1.11-.48-1.64-.78c-.04-.02-.04-.08-.01-.11c.11-.08.22-.17.33-.25c.02-.02.05-.02.07-.01c3.44 1.57 7.15 1.57 10.55 0c.02-.01.05-.01.07.01c.11.09.22.17.33.26c.04.03.04.09-.01.11c-.52.31-1.07.56-1.64.78c-.04.01-.05.06-.04.09c.32.61.68 1.19 1.07 1.74c.03.01.06.02.09.01c1.72-.53 3.45-1.33 5.25-2.65c.02-.01.03-.03.03-.05c.44-4.53-.73-8.46-3.1-11.95c-.01-.01-.02-.02-.04-.02zM8.52 14.91c-1.03 0-1.89-.95-1.89-2.12c0-1.17.84-2.12 1.89-2.12c1.06 0 1.9.96 1.89 2.12c0 1.17-.84 2.12-1.89 2.12zm6.97 0c-1.03 0-1.89-.95-1.89-2.12c0-1.17.84-2.12 1.89-2.12c1.06 0 1.9.96 1.89 2.12c0 1.17-.83 2.12-1.89 2.12z" />
            </SvgIcon>
          </IconButton>
        </Box>
      </Toolbar>
    </AppBar>
  )
}
