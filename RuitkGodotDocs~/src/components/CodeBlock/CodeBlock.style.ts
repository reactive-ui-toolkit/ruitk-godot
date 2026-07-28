import type { SxProps } from '@mui/material'

const wrapper: SxProps = {
  borderRadius: 1,
  overflow: 'hidden',
  border: 1,
  borderColor: 'divider',
  bgcolor: 'background.paper',
}

const header: SxProps = {
  display: 'flex',
  alignItems: 'center',
  justifyContent: 'space-between',
  px: 1.5,
  py: 0.5,
  borderBottom: 1,
  borderColor: 'divider',
  bgcolor: 'rgba(255,255,255,0.02)',
}

const headerNoTabs: SxProps = {
  display: 'flex',
  alignItems: 'center',
  justifyContent: 'flex-end',
  px: 1.5,
  py: 0.5,
  borderBottom: 1,
  borderColor: 'divider',
  bgcolor: 'rgba(255,255,255,0.02)',
}

const tabs: SxProps = {
  display: 'flex',
  alignItems: 'center',
  gap: 0.5,
}

const tab: SxProps = {
  px: 1,
  py: 0.25,
  borderRadius: 999,
  fontSize: 12,
  color: 'text.secondary',
  cursor: 'pointer',
}

const tabActive: SxProps = {
  px: 1,
  py: 0.25,
  borderRadius: 999,
  fontSize: 12,
  bgcolor: 'primary.main',
  color: '#0b0f1a',
  cursor: 'pointer',
}

const copyBtn: SxProps = {
  color: 'text.secondary',
}

const body: SxProps = {
  p: 0,
  // Slightly lighter, more neutral gray for code background
  bgcolor: '#21252e',
}

const preCustom = {
  margin: 0,
  padding: 10,
}

const Styles = { wrapper, header, headerNoTabs, tabs, tab, tabActive, copyBtn, body, preCustom }

export default Styles
