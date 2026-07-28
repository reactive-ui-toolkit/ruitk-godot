import type { SxProps } from '@mui/material'

const root: SxProps = {
  display: 'flex',
  flexDirection: 'column',
  gap: 2,
}

const section: SxProps = {
  mt: 2,
}

const table: SxProps = {
  '& th': { fontWeight: 600 },
  '& td, & th': { px: 1.5, py: 0.75, fontSize: '0.875rem' },
  '& code': { fontSize: '0.8125rem', backgroundColor: 'rgba(255,255,255,0.06)', px: 0.5, borderRadius: 0.5 },
}

const Styles = { root, section, table }

export default Styles
