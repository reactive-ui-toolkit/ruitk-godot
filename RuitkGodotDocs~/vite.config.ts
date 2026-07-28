import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import fs from 'node:fs'
import path from 'node:path'

// ─────────────────────────────────────────────────────────────────────────────
// Build-time data generation for the Godot docs.
//
// Unlike the Unity docs (which parse C# `Props/*.cs`), the Godot host elements are
// data: their props/signals come from the bundled ClassDB dump and the guitkx schema
// that the LSP already ships. This config reads those SAME sources so the docs never
// drift from the tooling, and injects them as compile-time constants:
//   __PACKAGE_VERSION__  — addon version from addons/reactive_ui_toolkit/plugin.cfg
//   __GODOT_MIN__        — the minimum supported Godot minor (floor)
//   __HOST_ELEMENTS__    — per host tag: { tag, godotClass, factory, events, props[], signals[] }
//   __HOST_TAGS__        — ordered list of host tags (nav order = schema order)
//   __STYLE_KEYS__/__STRUCTURAL_ATTRS__/__COMMON_ATTRS__/__DIRECTIVES__ — from the schema
// ─────────────────────────────────────────────────────────────────────────────

const repoRoot = path.resolve(process.cwd(), '..')
const readJson = (rel: string) =>
  JSON.parse(fs.readFileSync(path.join(repoRoot, rel), 'utf-8').replace(/^\uFEFF/, ''))

// ── addon version (plugin.cfg: version="0.3.0") ──────────────────────────────
function readAddonVersion(): string {
  try {
    const cfg = fs.readFileSync(path.join(repoRoot, 'addons', 'reactive_ui_toolkit', 'plugin.cfg'), 'utf-8')
    const m = cfg.match(/version\s*=\s*"([^"]+)"/)
    return m ? m[1] : '0.0.0'
  } catch {
    return '0.0.0'
  }
}

// ── ClassDB dump (own-only members per class; base-flatten here) ─────────────
type ClassProp = { name: string; type: string; enum?: string }
type ClassSignal = { name: string; args: { name: string; type: string }[] }
type ClassEntry = { base?: string; properties?: ClassProp[]; signals?: ClassSignal[] }

const classdb: Record<string, ClassEntry> = (() => {
  try {
    return readJson(path.join('ide-extensions', 'lsp-server', 'classdb', 'godot-control.json')).classes || {}
  } catch {
    return {}
  }
})()

/** Base-flattened members of `cls` (own wins on shadow), tagging each with whether it's inherited. */
function flatProps(cls: string): (ClassProp & { inherited: boolean })[] {
  const out: (ClassProp & { inherited: boolean })[] = []
  const seen = new Set<string>()
  const own = new Set((classdb[cls]?.properties ?? []).map((p) => p.name))
  let c: string | undefined = cls
  let guard = 0
  while (c && classdb[c] && guard++ < 50) {
    for (const p of classdb[c].properties ?? [])
      if (!seen.has(p.name)) {
        seen.add(p.name)
        out.push({ ...p, inherited: !own.has(p.name) })
      }
    c = classdb[c].base
  }
  return out
}

function flatSignals(cls: string): ClassSignal[] {
  const out: ClassSignal[] = []
  const seen = new Set<string>()
  let c: string | undefined = cls
  let guard = 0
  while (c && classdb[c] && guard++ < 50) {
    for (const s of classdb[c].signals ?? [])
      if (!seen.has(s.name) && !s.name.startsWith('_')) {
        seen.add(s.name)
        out.push(s)
      }
    c = classdb[c].base
  }
  return out
}

// ── guitkx schema (host tags + curated React events + attrs + style keys) ────
const schema = (() => {
  try {
    return readJson(path.join('ide-extensions', 'grammar', 'guitkx-schema.json'))
  } catch {
    return { hostElements: [], structuralAttributes: [], commonAttributes: [] }
  }
})()

type SchemaTag = { tag: string; godotClass: string; factory: string; events?: string[] }

const hostElements: Record<string, unknown> = {}
const hostTags: string[] = []
for (const t of (schema.hostElements ?? []) as SchemaTag[]) {
  hostTags.push(t.tag)
  hostElements[t.tag] = {
    tag: t.tag,
    godotClass: t.godotClass,
    factory: t.factory,
    events: t.events ?? [],
    props: flatProps(t.godotClass),
    signals: flatSignals(t.godotClass),
  }
}

// https://vite.dev/config/
export default defineConfig({
  // GitHub Pages PROJECT site: served from /ruitk-godot/. Asset URLs are base-prefixed and the
  // router basename mirrors this (see src/main.tsx). Switch both to '/' for a custom domain.
  base: '/ruitk-godot/',
  plugins: [react()],
  define: {
    __PACKAGE_VERSION__: JSON.stringify(readAddonVersion()),
    __GODOT_MIN__: JSON.stringify('4.2'),
    __HOST_ELEMENTS__: JSON.stringify(hostElements),
    __HOST_TAGS__: JSON.stringify(hostTags),
    __STRUCTURAL_ATTRS__: JSON.stringify(schema.structuralAttributes ?? []),
    __COMMON_ATTRS__: JSON.stringify(schema.commonAttributes ?? []),
    __CONTROL_FLOW__: JSON.stringify(schema.controlFlow ?? []),
    __PREAMBLE_DIRECTIVES__: JSON.stringify(schema.preambleDirectives ?? []),
  },
  css: {
    postcss: './postcss.config.cjs',
  },
})
