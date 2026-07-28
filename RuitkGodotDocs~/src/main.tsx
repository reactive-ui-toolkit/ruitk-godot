import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { BrowserRouter } from 'react-router-dom'
import { App } from './App'
import { VersionProvider } from './contexts/VersionContext'

// Mirror Vite's base ('/ruitk-godot/' in prod, '/' in dev) so routes resolve under the GitHub
// Pages project subpath. Strip the trailing slash (react-router wants none), fall back to '/' at root.
const BASENAME = import.meta.env.BASE_URL.replace(/\/$/, '') || '/'

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <BrowserRouter basename={BASENAME}>
      <VersionProvider>
        <App />
      </VersionProvider>
    </BrowserRouter>
  </StrictMode>,
)
