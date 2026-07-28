import type { FC } from 'react'
import { useEffect, useMemo, useRef, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { Dialog, DialogContent, Paper, InputBase, List, ListItemButton, ListItemText, Typography, Box, IconButton } from '@mui/material'
import SearchIcon from '@mui/icons-material/Search'
import CloseIcon from '@mui/icons-material/Close'
import { getFilteredFlat } from '../../docs'
import { useSelectedVersion } from '../../contexts/VersionContext'
import { getStyleSearchTerms } from '../../versionManifest'
import { getRenderedText } from '../../searchIndex'
import Styles from './SearchModal.style'

export type SearchModalProps = { open: boolean; onClose: () => void }

export const SearchModal: FC<SearchModalProps> = ({ open, onClose }) => {
  const nav = useNavigate()
  const { selectedVersion } = useSelectedVersion()
  const flat = useMemo(() => getFilteredFlat(selectedVersion), [selectedVersion])
  const [q, setQ] = useState('')
  const [sel, setSel] = useState(0)
  const inputRef = useRef<HTMLInputElement>(null)
  useEffect(() => {
    if (open) {
      const t = setTimeout(() => inputRef.current?.focus(), 50)
      return () => clearTimeout(t)
    }
  }, [open])
  const handleClose = () => {
    setQ('')
    setSel(0)
    onClose()
  }
  const styleTerms = useMemo(() => getStyleSearchTerms(selectedVersion), [selectedVersion])
  const results = useMemo(() => {
    const needle = q.trim().toLowerCase()
    if (!needle) return [] as typeof flat
    const words = needle.split(/\s+/).filter(Boolean)
    return flat.filter((p) => {
      const extra = p.canonicalId === 'styling' ? styleTerms : ''
      const haystack = [p.title, (p.keywords || []).join(' '), p.searchContent || '', getRenderedText(p), extra].join(' ').toLowerCase()
      return words.every((w) => haystack.includes(w))
    })
  }, [flat, q, styleTerms])
  // Reset the highlighted row to the top whenever the result set changes. Done DURING render
  // (React's "adjust state when a prop changes" pattern) instead of in an effect, which would
  // cascade a second render. `results` is a fresh array each time its useMemo deps change.
  const [prevResults, setPrevResults] = useState(results)
  if (prevResults !== results) {
    setPrevResults(results)
    setSel(0)
  }
  return (
    <Dialog open={open} onClose={handleClose} fullWidth maxWidth="md">
      <DialogContent sx={Styles.content}>
        <Box sx={Styles.header}>
          <Paper sx={Styles.inputPaper} variant="outlined">
            <SearchIcon />
            <InputBase
              inputRef={inputRef}
              placeholder="Search documentation"
              value={q}
              onChange={(e) => setQ(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === 'Escape') handleClose()
                if (e.key === 'ArrowDown') { e.preventDefault(); setSel((i) => Math.min(i + 1, results.length - 1)) }
                if (e.key === 'ArrowUp') { e.preventDefault(); setSel((i) => Math.max(i - 1, 0)) }
                if (e.key === 'Enter' && results[sel]) { handleClose(); nav(results[sel].path) }
              }}
              sx={{ flex: 1 }}
            />
          </Paper>
          <IconButton onClick={handleClose} aria-label="Close search"><CloseIcon /></IconButton>
        </Box>
        <List>
          {results.map((r, i) => (
            <ListItemButton key={r.id} selected={i === sel} onClick={() => { handleClose(); nav(r.path) }}>
              <ListItemText primary={r.title} secondary={(r.keywords || []).join(', ')} />
            </ListItemButton>
          ))}
          {q && results.length === 0 && <Typography sx={Styles.noResults} color="text.secondary">No results</Typography>}
        </List>
      </DialogContent>
    </Dialog>
  )
}
