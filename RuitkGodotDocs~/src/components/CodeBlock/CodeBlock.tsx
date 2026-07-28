import { Highlight, themes } from 'prism-react-renderer'
import type { Language } from 'prism-react-renderer'
// Registers the GDScript grammar on the shared Prism instance (side-effect) and re-exports it.
import { Prism } from '../../codeLanguages'
import { Box, IconButton, Tooltip, Typography } from '@mui/material'
import ContentCopyIcon from '@mui/icons-material/ContentCopy'
import type { FC } from 'react'
import { useCallback, useState } from 'react'
import Styles from './CodeBlock.style'

type Props = {
  code?: string
  codeRuntime?: string
  codeEditor?: string
  language?: Language
}

export const CodeBlock: FC<Props> = ({ code, codeRuntime, codeEditor, language = 'jsx' }) => {
  const [copied, setCopied] = useState(false)
  const onCopy = useCallback(() => {
    const text = (codeRuntime ?? codeEditor ?? code ?? '').trim()
    navigator.clipboard.writeText(text).then(() => {
      setCopied(true)
      setTimeout(() => setCopied(false), 1200)
    })
  }, [code, codeRuntime, codeEditor])

  const hasTabbed = !!(codeRuntime || codeEditor)
  const [activeMode, setActiveMode] = useState<'runtime' | 'editor'>(
    codeRuntime ? 'runtime' : 'editor'
  )

  const activeCode = (() => {
    if (hasTabbed) {
      if (activeMode === 'runtime') {
        return (codeRuntime ?? codeEditor ?? '').trim()
      }
      return (codeEditor ?? codeRuntime ?? '').trim()
    }
    return (code ?? '').trim()
  })()

  return (
    <Box sx={Styles.wrapper}>
      <Box sx={hasTabbed ? Styles.header : Styles.headerNoTabs}>
        {hasTabbed && (
          <Box sx={Styles.tabs}>
            {codeRuntime && (
              <Box
                sx={activeMode === 'runtime' ? Styles.tabActive : Styles.tab}
                onClick={() => setActiveMode('runtime')}
              >
                <Typography variant="caption">Runtime</Typography>
              </Box>
            )}
            {codeEditor && (
              <Box
                sx={activeMode === 'editor' ? Styles.tabActive : Styles.tab}
                onClick={() => setActiveMode('editor')}
              >
                <Typography variant="caption">Editor</Typography>
              </Box>
            )}
          </Box>
        )}
        <Tooltip title={copied ? 'Copied' : 'Copy'}>
          <IconButton size="small" onClick={onCopy} sx={Styles.copyBtn}>
            <ContentCopyIcon fontSize="inherit" />
          </IconButton>
        </Tooltip>
      </Box>
      <Box sx={Styles.body}>
        <Highlight prism={Prism} theme={themes.oneDark} code={activeCode} language={language}>
          {({ className, style, tokens, getLineProps, getTokenProps }) => (
            <pre className={className} style={{...style, ...Styles.preCustom}}>
              {tokens.map((line, i) => (
                <div key={i} {...getLineProps({ line })}>
                  {line.map((token, key) => (
                    <span key={key} {...getTokenProps({ token })} />
                  ))}
                </div>
              ))}
            </pre>
          )}
        </Highlight>
      </Box>
    </Box>
  )
}
