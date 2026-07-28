import type { SxProps } from '@mui/material'

const root: SxProps = {
  display: 'flex',
  flexDirection: 'column',
  gap: 2,
}

const section: SxProps = {
  mt: 3,
}

const question: SxProps = {
  mt: 2,
  fontWeight: 600,
}

const table: SxProps = {
  mt: 1,
  mb: 1,
  maxWidth: 640,
}

const Styles = { root, section, question, table }

export default Styles
