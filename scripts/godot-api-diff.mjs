#!/usr/bin/env node
/**
 * ClassDB API diff between two Godot versions — the Godot analog of the Unity toolkit's
 * `unity-api-diff.ps1` (see AUTOMATION.md). Input: two JSON dumps produced by
 * `addons/reactive_ui_toolkit/dev/classdb_dump.gd`, one per Godot binary:
 *
 *   <old-godot> --headless --path . --script res://addons/reactive_ui_toolkit/dev/classdb_dump.gd -- res://old.json
 *   <new-godot> --headless --path . --script res://addons/reactive_ui_toolkit/dev/classdb_dump.gd -- res://new.json
 *   node scripts/godot-api-diff.mjs old.json new.json [--json report.json]
 *
 * Reports, for the Control subtree the library cares about: added/removed CLASSES (new tags —
 * usable immediately via the open ClassDB vocabulary; curate per AUTOMATION.md), added/removed
 * PROPERTIES (props + style keys are verbatim, so they work at runtime immediately; the bundled
 * LSP dump must be regenerated for completion), added/removed SIGNALS (events are derived live,
 * `on` + PascalCase(signal) — the LSP dump regen picks them up), and enum-hint changes.
 * ClassDB reflection — no web scraping, no HTML parsing.
 */
import { readFileSync, writeFileSync, existsSync } from 'fs';

function usage(msg) {
  if (msg) console.error('✗ ' + msg);
  console.error('usage: node scripts/godot-api-diff.mjs <old.json> <new.json> [--json <report.json>]');
  process.exit(1);
}

const args = process.argv.slice(2);
const jsonIdx = args.indexOf('--json');
const jsonOut = jsonIdx !== -1 ? args.splice(jsonIdx, 2)[1] : null;
if (args.length !== 2) usage();
for (const p of args) if (!existsSync(p)) usage(`missing dump: ${p}`);

const [oldDump, newDump] = args.map((p) => JSON.parse(readFileSync(p, 'utf8')));
for (const [label, d] of [['old', oldDump], ['new', newDump]]) {
  if (!d.classes || typeof d.classes !== 'object') usage(`${label} dump has no "classes" — regenerate it with classdb_dump.gd`);
}

const byName = (arr) => new Map((arr ?? []).map((x) => [x.name, x]));
const report = { oldGodot: oldDump.godot ?? '?', newGodot: newDump.godot ?? '?', addedClasses: [], removedClasses: [], changedClasses: {} };

const oldClasses = oldDump.classes;
const newClasses = newDump.classes;

for (const name of Object.keys(newClasses)) {
  if (!(name in oldClasses)) report.addedClasses.push(name);
}
for (const name of Object.keys(oldClasses)) {
  if (!(name in newClasses)) report.removedClasses.push(name);
}
for (const name of Object.keys(newClasses)) {
  const o = oldClasses[name];
  if (!o) continue;
  const n = newClasses[name];
  const oProps = byName(o.properties), nProps = byName(n.properties);
  const oSigs = byName(o.signals), nSigs = byName(n.signals);
  const entry = { addedProperties: [], removedProperties: [], changedEnums: [], addedSignals: [], removedSignals: [] };
  for (const [pn, pv] of nProps) {
    if (!oProps.has(pn)) entry.addedProperties.push({ name: pn, type: pv.type, ...(pv.enum ? { enum: pv.enum } : {}) });
    else if ((oProps.get(pn).enum ?? '') !== (pv.enum ?? '')) entry.changedEnums.push({ name: pn, old: oProps.get(pn).enum ?? '', new: pv.enum ?? '' });
  }
  for (const pn of oProps.keys()) if (!nProps.has(pn)) entry.removedProperties.push(pn);
  for (const [sn, sv] of nSigs) if (!oSigs.has(sn)) entry.addedSignals.push({ name: sn, args: (sv.args ?? []).map((a) => `${a.name}: ${a.type}`).join(', ') });
  for (const sn of oSigs.keys()) if (!nSigs.has(sn)) entry.removedSignals.push(sn);
  if (Object.values(entry).some((v) => v.length)) report.changedClasses[name] = entry;
}

report.addedClasses.sort();
report.removedClasses.sort();

// ── human-readable summary ────────────────────────────────────────────────────
const pascalToEvent = (sig) => 'on' + sig.split('_').map((w) => w.charAt(0).toUpperCase() + w.slice(1)).join('');
console.log(`ClassDB diff: Godot ${report.oldGodot} -> ${report.newGodot}\n`);
if (report.addedClasses.length) {
  console.log(`ADDED CLASSES (${report.addedClasses.length}) — valid tags immediately (open vocabulary); curate per AUTOMATION.md:`);
  for (const c of report.addedClasses) console.log(`  + <${c}>   (base: ${newClasses[c].base})`);
  console.log();
}
if (report.removedClasses.length) {
  console.log(`REMOVED CLASSES (${report.removedClasses.length}) — check curated schema/docs/examples for references:`);
  for (const c of report.removedClasses) console.log(`  - <${c}>`);
  console.log();
}
const changed = Object.keys(report.changedClasses).sort();
if (changed.length) {
  console.log(`CHANGED CLASSES (${changed.length}):`);
  for (const c of changed) {
    const e = report.changedClasses[c];
    console.log(`  ${c}`);
    for (const p of e.addedProperties) console.log(`    + prop   ${p.name}: ${p.type}${p.enum ? ` (enum: ${p.enum})` : ''}`);
    for (const p of e.removedProperties) console.log(`    - prop   ${p}`);
    for (const p of e.changedEnums) console.log(`    ~ enum   ${p.name}: "${p.old}" -> "${p.new}"`);
    for (const s of e.addedSignals) console.log(`    + signal ${s.name}(${s.args})   -> event ${pascalToEvent(s.name)}`);
    for (const s of e.removedSignals) console.log(`    - signal ${s}`);
  }
  console.log();
}
if (!report.addedClasses.length && !report.removedClasses.length && !changed.length) {
  console.log('No API differences in the Control subtree.');
}
if (jsonOut) {
  writeFileSync(jsonOut, JSON.stringify(report, null, 2) + '\n');
  console.log(`wrote ${jsonOut}`);
}
