import type { SxProps } from '@mui/material'

const appBar: SxProps = { borderBottom: 1, borderColor: 'divider' }
const toolbar: SxProps = { display: 'flex', alignItems: 'center', gap: 2 }

const left: SxProps = { display: 'flex', alignItems: 'center', gap: 1.25 }
const logo: SxProps = { width: 28, height: 28, borderRadius: 1 }
const titleLink: SxProps = {
  display: 'flex',
  alignItems: 'center',
  gap: 0.75,
  color: 'inherit',
  textDecoration: 'none',
}
const title: SxProps = { fontWeight: 600, letterSpacing: 0.3 }

const center: SxProps = { flex: 1, display: 'flex', justifyContent: 'center' }
const searchPaper: SxProps = { p: '2px 8px', display: 'flex', alignItems: 'center', gap: 1, width: 360, cursor: 'text' }
const inputFlex: SxProps = { flex: 1 }

const right: SxProps = { ml: 1, display: 'flex', alignItems: 'center', gap: 1 }

const versionSelect: SxProps = { minWidth: 120, fontSize: '0.8125rem' }

const Styles = { appBar, toolbar, left, logo, titleLink, title, center, searchPaper, inputFlex, right, versionSelect }

export default Styles
