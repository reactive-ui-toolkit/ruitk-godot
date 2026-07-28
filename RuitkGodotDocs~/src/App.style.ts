import type { SxProps } from '@mui/material'

const shell: SxProps = { display: 'grid', gridTemplateRows: 'auto 1fr', height: '100vh' }
const grid: SxProps = { display: 'grid', gridTemplateColumns: '280px 1fr', minHeight: 0 }
const content: SxProps = { p: 3, overflow: 'auto' }
const main: SxProps = { maxWidth: 980 }
const Styles = { shell, grid, content, main }

export default Styles
