import { createTheme } from '@mui/material'

export const theme = createTheme({
  palette: {
    mode: 'dark',
    background: {
      // Slightly lighter/greyer so content stands out
      default: '#181c26',
      paper: '#202532',
    },
    divider: '#343a4c',
    // Godot-flavoured: the engine's blue as the primary, a warm orange as the accent.
    primary: { main: '#54a3d8' },
    secondary: { main: '#ff9c5b' },
    text: {
      primary: '#e5e9f5',
      secondary: '#a0a8c0',
    },
  },
  shape: { borderRadius: 8 },
  typography: {
    fontSize: 14,
    body1: {
      lineHeight: 1.3,
      color: '#a0a8c0',
    },
    body2: {
      lineHeight: 1.3,
      color: '#a0a8c0',
    },
    h4: {
      fontSize: 28,
      fontWeight: 600,
      letterSpacing: 0.2,
      color: '#e5e9f5',
    },
    h5: {
      fontSize: 20,
      fontWeight: 600,
      letterSpacing: 0.15,
      marginTop: 16,
      color: '#e5e9f5',
    },
  },
  components: {
    MuiCssBaseline: {
      styleOverrides: {
        code: {
          fontFamily:
            'ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace',
          backgroundColor: '#202532',
          borderRadius: 4,
          padding: '2px 6px',
          border: '1px solid #343a4c',
          fontSize: '0.85em',
        },
      },
    },
  },
})
