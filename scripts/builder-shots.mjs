#!/usr/bin/env node
/**
 * Screenshots the RUITK Builder in every state the visual gauntlet compares.
 *
 *   node scripts/builder-shots.mjs
 *
 * Writes Images/current/<state>.png, one per state, each paired by name with the Unity reference
 * in Images/reference/<state>.png.
 *
 * WHY AN EDITOR RUN. The builder is editor UI — it wears the editor theme, and the source pane's
 * highlighter deliberately does nothing outside the editor. A standalone capture would photograph
 * a builder nobody ever sees. So this enables a dev-only plugin, runs the editor once, lets it
 * shoot and quit, and puts project.godot back exactly as it was — including when it fails, which
 * is the whole reason the restore is in a finally.
 *
 * GODOT RESOLUTION, in the repo's standard order: $GODOT_BIN → godotBin in .ruitk-local.json →
 * `godot` on PATH. No install location is ever guessed; a miss names all three.
 */
import { spawnSync } from 'node:child_process'
import { existsSync, readFileSync, writeFileSync, mkdirSync, readdirSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const PROJECT = join(ROOT, 'project.godot')
const PLUGIN = 'res://addons/ruitk_builder_shots/plugin.cfg'
const OUT = join(ROOT, 'Images', 'current')

function godotBinary() {
  if (process.env.GODOT_BIN) return process.env.GODOT_BIN
  const local = join(ROOT, '.ruitk-local.json')
  if (existsSync(local)) {
    try {
      const bin = JSON.parse(readFileSync(local, 'utf8')).godotBin
      if (bin) return bin
    } catch {
      /* a malformed local file is not a reason to fail differently than a missing one */
    }
  }
  const probe = spawnSync('godot', ['--version'], { encoding: 'utf8' })
  if (!probe.error) return 'godot'
  console.error(
    'Godot not found. Set $GODOT_BIN, or "godotBin" in .ruitk-local.json (copy\n' +
      '.ruitk-local.example.json), or put `godot` on PATH.'
  )
  process.exit(2)
}

/** Adds the shot plugin to the enabled list, returning the original file text. */
function enablePlugin() {
  const before = readFileSync(PROJECT, 'utf8')
  if (before.includes(PLUGIN)) return before
  const line = /^enabled=PackedStringArray\((.*)\)$/m
  const match = before.match(line)
  if (!match) {
    console.error('project.godot has no [editor_plugins] enabled=PackedStringArray(...) line.')
    process.exit(2)
  }
  const after = before.replace(line, `enabled=PackedStringArray(${match[1]}, "${PLUGIN}")`)
  writeFileSync(PROJECT, after)
  return before
}

const godot = godotBinary()
mkdirSync(OUT, { recursive: true })
const original = enablePlugin()

let code = 1
try {
  console.log(`> ${godot} --path . --editor   (shooting the builder)`)
  const run = spawnSync(godot, ['--path', ROOT, '--editor'], {
    cwd: ROOT,
    encoding: 'utf8',
    timeout: 5 * 60 * 1000,
  })
  const out = `${run.stdout ?? ''}${run.stderr ?? ''}`
  for (const l of out.split('\n')) if (l.startsWith('SHOTS:')) console.log(l)
  if (run.error) console.error(String(run.error))
  code = out.includes('SHOTS: DONE') ? 0 : 1
} finally {
  writeFileSync(PROJECT, original)
}

const shots = existsSync(OUT) ? readdirSync(OUT).filter((f) => f.endsWith('.png')).sort() : []
console.log('')
if (shots.length === 0) {
  console.error('No shots were written. Run the editor by hand to see what it said.')
  process.exit(1)
}
console.log(`${shots.length} shot(s) in Images/current/:`)
for (const s of shots) console.log(`  Images/current/${s}   vs   Images/reference/${s}`)
process.exit(code)
