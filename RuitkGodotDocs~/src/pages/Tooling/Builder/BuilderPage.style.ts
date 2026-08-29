import type { SxProps, Theme } from '@mui/material'

const root: SxProps<Theme> = {
  display: 'flex',
  flexDirection: 'column',
  gap: 2,
}

const list: SxProps<Theme> = {
  pl: 2,
}

const table: SxProps<Theme> = {
  my: 1,
}

const Styles = { root, list, table }

export default Styles
