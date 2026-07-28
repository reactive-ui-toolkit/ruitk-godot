import type { FC } from 'react'
import { useState } from 'react'
import { Link as RouterLink, Route, Routes } from 'react-router-dom'
import { Box, CssBaseline, Link, ThemeProvider, Typography } from '@mui/material'
import { allFlat } from './docs'
import { TopBar } from './components/TopBar/TopBar'
import { Sidebar } from './components/Sidebar/Sidebar'
import { Pager } from './components/Pager/Pager'
import { SearchModal } from './components/SearchModal/SearchModal'
import Styles from './App.style'
import { theme } from './theme'


export const App: FC = () => {
  const [searchOpen, setSearchOpen] = useState(false)
  return (
    <ThemeProvider theme={theme}>
      <CssBaseline />
      <Box sx={Styles.shell}>
        <TopBar onOpenSearch={() => setSearchOpen(true)} />
        <Box sx={Styles.grid}>
          <Sidebar />
          <Box sx={Styles.content}>
            <Routes>
              {allFlat.map((p) => (
                <Route key={p.id} path={p.path} element={<Box component="main" sx={Styles.main}>{p.element()}<Pager /></Box>} />
              ))}
              <Route path="*" element={<><Typography variant="h5" gutterBottom>Not Found</Typography><Link component={RouterLink} to="/">Go to Introduction</Link></>} />
            </Routes>
          </Box>
        </Box>
      </Box>
      <SearchModal open={searchOpen} onClose={() => setSearchOpen(false)} />
    </ThemeProvider>
  )
}
