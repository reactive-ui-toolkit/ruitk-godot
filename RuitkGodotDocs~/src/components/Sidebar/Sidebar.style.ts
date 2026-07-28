import type { SxProps } from '@mui/material'

const root: SxProps = {
  width: 280,
  borderRight: 1,
  borderColor: 'divider',
  height: '100%',
  overflow: 'auto',
  '&::-webkit-scrollbar': {
    width: 8,
  },
  '&::-webkit-scrollbar-track': {
    backgroundColor: 'transparent',
  },
  '&::-webkit-scrollbar-thumb': {
    backgroundColor: 'rgba(25,118,210,0.4)',
    borderRadius: 999,
    border: '2px solid transparent',
    backgroundClip: 'padding-box',
  },
  '&::-webkit-scrollbar-thumb:hover': {
    backgroundColor: 'rgba(25,118,210,0.7)',
  },
  scrollbarWidth: 'thin',
  scrollbarColor: 'rgba(25,118,210,0.6) transparent',
}
const childItem: SxProps = { pl: 4 }
const sectionTitle: SxProps = { fontWeight: 700 }
const subgroupHeader: SxProps = {
  pl: 4,
  pt: 1,
  pb: 0.5,
  fontSize: 11,
  textTransform: 'uppercase',
  letterSpacing: 0.5,
  color: 'text.secondary',
}
const subgroupDivider: SxProps = { mt: 0.5, mb: 0.5, opacity: 0.4 }

const Styles = { root, childItem, sectionTitle, subgroupHeader, subgroupDivider }

export default Styles
