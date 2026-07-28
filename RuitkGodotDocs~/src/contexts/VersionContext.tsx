import { createContext, useContext, useState, useCallback, type FC, type ReactNode } from 'react'
import { LATEST_VERSION, SUPPORTED_VERSIONS } from '../versionManifest'

const STORAGE_KEY = 'ruitk-selected-godot-version'

function loadPersistedVersion(): string {
  try {
    const stored = localStorage.getItem(STORAGE_KEY)
    if (stored && SUPPORTED_VERSIONS.some((v) => v.version === stored)) return stored
  } catch { /* SSR / private browsing */ }
  return LATEST_VERSION.version
}

interface VersionContextValue {
  selectedVersion: string
  setSelectedVersion: (version: string) => void
}

const VersionContext = createContext<VersionContextValue>({
  selectedVersion: LATEST_VERSION.version,
  setSelectedVersion: () => {},
})

export const VersionProvider: FC<{ children: ReactNode }> = ({ children }) => {
  const [selectedVersion, setRaw] = useState(loadPersistedVersion)

  const setSelectedVersion = useCallback((version: string) => {
    setRaw(version)
    try { localStorage.setItem(STORAGE_KEY, version) } catch { /* ignore */ }
  }, [])

  return (
    <VersionContext.Provider value={{ selectedVersion, setSelectedVersion }}>
      {children}
    </VersionContext.Provider>
  )
}

// Colocating the provider + its consumer hook is idiomatic for a React context module; the
// fast-refresh "only export components" rule doesn't apply to a context accessor.
// eslint-disable-next-line react-refresh/only-export-components
export const useSelectedVersion = () => useContext(VersionContext)
