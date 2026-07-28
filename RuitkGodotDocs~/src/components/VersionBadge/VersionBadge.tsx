import type { FC } from 'react'
import { Chip } from '@mui/material'
import type { FeatureVersion } from '../../versionManifest'
import { getVersionBadge } from '../../versionManifest'

interface VersionBadgeProps {
  feature: FeatureVersion | undefined
}

/** Small chip displaying "6.3+" for non-floor features. Renders nothing for floor features. */
export const VersionBadge: FC<VersionBadgeProps> = ({ feature }) => {
  const label = getVersionBadge(feature)
  if (!label) return null
  return (
    <Chip
      label={label}
      size="small"
      variant="outlined"
      color="info"
      sx={{ ml: 0.5, height: 20, fontSize: '0.7rem' }}
    />
  )
}
