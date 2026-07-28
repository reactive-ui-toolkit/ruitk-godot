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

const Styles = { root, section, question }

export default Styles
