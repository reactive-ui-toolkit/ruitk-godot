import type { FC } from 'react'
import {
  Box,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableRow,
  Typography,
} from '@mui/material'
import Styles from './LicensingPage.style'

export const LicensingPage: FC = () => (
  <Box sx={Styles.root}>
    <Typography variant="h4" component="h1" gutterBottom>
      Licensing
    </Typography>

    <Typography variant="body1" paragraph>
      <strong>ReactiveUI is free for almost everyone.</strong> If you're a student, a hobbyist, a
      jam team, or an indie studio earning under <strong>$250,000 a year</strong> — everything on
      this page reduces to: <em>use it, ship your game, credit "Made with ReactiveUI", pay
      nothing.</em>
    </Typography>

    {/* ── Am I free? ──────────────────────────────────────────────────── */}
    <Typography variant="h5" component="h2" sx={Styles.section}>
      Am I free?
    </Typography>

    <Typography variant="body2" paragraph>
      <strong>Learning, prototyping, game jams, unreleased projects</strong> — free, always, for
      everyone. Even a AAA studio evaluates and develops free; payment only ever applies to{' '}
      <em>shipping</em>.
    </Typography>
    <Typography variant="body2" paragraph>
      <strong>
        Your company (plus its parents/subsidiaries) earned under $250k in the last 12 months
      </strong>{' '}
      — free to ship, commercially, forever. No registration required, no strings beyond the
      credits line.
    </Typography>
    <Typography variant="body2" paragraph>
      <strong>Over $250k and shipping a product</strong> — you need a commercial license. That's
      the whole rule.
    </Typography>

    {/* ── The commercial license ──────────────────────────────────────── */}
    <Typography variant="h5" component="h2" sx={Styles.section}>
      The commercial license
    </Typography>

    <Typography variant="body2" paragraph>
      The same license, same threshold, and same prices exist for each library — Godot, Unity, and
      Unreal — each licensed per product. Pick whichever shape suits you:
    </Typography>

    <TableContainer sx={Styles.table}>
      <Table size="small">
        <TableHead>
          <TableRow>
            <TableCell />
            <TableCell>Per-Title</TableCell>
            <TableCell>Studio</TableCell>
          </TableRow>
        </TableHead>
        <TableBody>
          <TableRow>
            <TableCell>Price</TableCell>
            <TableCell>
              <strong>$2,000</strong> one-time
            </TableCell>
            <TableCell>
              <strong>$2,500</strong> / year
            </TableCell>
          </TableRow>
          <TableRow>
            <TableCell>Covers</TableCell>
            <TableCell>one game, forever (patches, DLC, ports included)</TableCell>
            <TableCell>everything you ship while subscribed</TableCell>
          </TableRow>
          <TableRow>
            <TableCell>Best for</TableCell>
            <TableCell>a studio shipping occasionally</TableCell>
            <TableCell>a studio always shipping</TableCell>
          </TableRow>
          <TableRow>
            <TableCell>After it ends</TableCell>
            <TableCell>n/a — perpetual</TableCell>
            <TableCell>shipped games stay licensed forever</TableCell>
          </TableRow>
        </TableBody>
      </Table>
    </TableContainer>

    <Typography variant="body2" paragraph>
      To purchase, email <a href="mailto:yanivkalfa@gmail.com">yanivkalfa@gmail.com</a> — you get a
      license certificate PDF, the document your producer files for publisher and platform
      paperwork. The full texts live in the repository:{' '}
      <a
        href="https://github.com/reactive-ui-toolkit/ruitk-godot/blob/master/LICENSE"
        target="_blank"
        rel="noreferrer"
      >
        ReactiveUI Community License
      </a>{' '}
      and{' '}
      <a
        href="https://github.com/reactive-ui-toolkit/ruitk-godot/blob/master/LICENSE-COMMERCIAL.md"
        target="_blank"
        rel="noreferrer"
      >
        Commercial License Agreement
      </a>
      .
    </Typography>

    {/* ── The two asks ────────────────────────────────────────────────── */}
    <Typography variant="h5" component="h2" sx={Styles.section}>
      The two asks we make of everyone
    </Typography>

    <Typography variant="body2" paragraph>
      1. <strong>Credits.</strong> Put "Made with ReactiveUI" in your game's credits, wherever you
      credit other middleware. That line is how the project grows.
    </Typography>
    <Typography variant="body2" paragraph>
      2. <strong>Don't resell the library.</strong> You can ship anything you build <em>with</em>{' '}
      ReactiveUI; you can't repackage ReactiveUI itself as a competing UI framework. (Your game is
      never a "competing product" — this clause exists purely so nobody takes the source and sells
      it out from under the project.)
    </Typography>

    {/* ── Common questions ────────────────────────────────────────────── */}
    <Typography variant="h5" component="h2" sx={Styles.section}>
      Common questions
    </Typography>

    <Typography variant="body1" sx={Styles.question}>
      I downloaded an older version — do the new terms apply to me?
    </Typography>
    <Typography variant="body2" paragraph>
      No. Every copy keeps the terms it shipped with. The new license applies from{' '}
      <strong>0.12.0</strong> (Godot) onward — and from the matching releases of the Unity and
      Unreal libraries. (Old versions also stop receiving updates and support, so staying current
      is worth it anyway.)
    </Typography>

    <Typography variant="body1" sx={Styles.question}>
      We're a contractor building a game for a client — whose revenue counts?
    </Typography>
    <Typography variant="body2" paragraph>
      The entity that ships the product. If your client publishes the game, their revenue decides
      the tier; put the license in their name.
    </Typography>

    <Typography variant="body1" sx={Styles.question}>
      We crossed $250k mid-project. Are we in trouble?
    </Typography>
    <Typography variant="body2" paragraph>
      No — you have a 60-day window to pick up a license, and nothing you did before crossing
      needs back-payment. The threshold looks at the 12 months before you ship.
    </Typography>

    <Typography variant="body1" sx={Styles.question}>
      Does the free tier limit features?
    </Typography>
    <Typography variant="body2" paragraph>
      No. Same library, same features, same updates. The only difference is the piece of paper.
    </Typography>

    <Typography variant="body1" sx={Styles.question}>
      We can't afford $2,000 but we're just over the threshold / we're a nonprofit / weird case?
    </Typography>
    <Typography variant="body2" paragraph>
      Email us — <a href="mailto:yanivkalfa@gmail.com">yanivkalfa@gmail.com</a>. We'd rather you
      ship with ReactiveUI than not.
    </Typography>

    <Typography variant="body1" sx={Styles.question}>
      Can I support the project without owing anything?
    </Typography>
    <Typography variant="body2" paragraph>
      Yes, gladly — contributions and tips are always welcome, and shipping your game with a
      credits line (plus telling us about it) is already real support.
    </Typography>

    <Typography variant="body2" paragraph sx={Styles.section}>
      <em>
        The legally binding texts are the ReactiveUI Community License (the repo's{' '}
        <code>LICENSE</code>) and the Commercial License Agreement (
        <code>LICENSE-COMMERCIAL.md</code>). This page summarizes them; where they differ, the
        texts win.
      </em>
    </Typography>
  </Box>
)
