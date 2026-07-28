import type { SxProps, Theme } from '@mui/material'

const root: SxProps<Theme> = {
  display: 'flex',
  flexDirection: 'column',
  gap: 2,
}

const list: SxProps<Theme> = {
  pl: 2,
}

const section: SxProps<Theme> = {
  display: 'flex',
  flexDirection: 'column',
  gap: 1,
}

const Styles = { root, list, section }

export default Styles
