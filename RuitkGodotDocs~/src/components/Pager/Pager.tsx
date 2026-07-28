import type { FC } from 'react'
import { useMemo } from 'react'
import { useLocation, useNavigate } from 'react-router-dom'
import { Box, Button } from '@mui/material'
import { allFlat } from '../../docs'
import Styles from './Pager.style'

export const Pager: FC = () => {
  const nav = useNavigate()
  const { pathname } = useLocation()
  const idx = useMemo(() => allFlat.findIndex((p) => p.path === pathname), [pathname])
  const prev = idx > 0 ? allFlat[idx - 1] : undefined
  const next = idx >= 0 && idx < allFlat.length - 1 ? allFlat[idx + 1] : undefined
  return (
    <Box sx={Styles.root}>
      <span>{prev && <Button onClick={() => nav(prev.path)} variant="text">{'\u2190'} {prev.title}</Button>}</span>
      <span>{next && <Button onClick={() => nav(next.path)} variant="text">{next.title} {'\u2192'}</Button>}</span>
    </Box>
  )
}
