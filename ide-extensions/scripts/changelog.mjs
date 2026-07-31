#!/usr/bin/env node
/**
 * Centralized changelog management for the GUITKX tooling family: the VS Code and
 * VS2022 extensions AND the Godot editor addon (`addons/reactive_ui_toolkit_editor`). The
 * `reactive_ui_toolkit` runtime library deliberately stays OUT of this system — its changelog
 * is hand-written keep-a-changelog (root CHANGELOG.md, byte-identically mirrored into
 * the addon; a GDScript test enforces the mirror).
 *
 * Source of truth: ide-extensions/changelog.json.
 * The per-target CHANGELOG.md files are generated from it via `extract` and COMMITTED
 * — they are NOT publish-time artifacts. `verify` (run by the changelog-sync CI job on
 * every push/PR) fails the build the moment a committed file drifts from the json, so
 * the flow is always: `add` → `extract` each target → commit all of it together.
 *
 * The editor addon's file is a CUTOVER: entries from 0.6.3 onward render from the
 * json; everything below the LEGACY_MARKER line is its frozen pre-cutover history,
 * preserved byte-verbatim by extract/verify (see readLegacyTail).
 *
 * Commands:
 *   add              — Append a changelog entry
 *   extract          — Generate a target's CHANGELOG.md (stdout or --out)
 *   extract-overview — Generate VS Marketplace overview.md (stdout or --out)
 *   import           — Import entries from an existing markdown changelog
 *
 * Run `node ide-extensions/scripts/changelog.mjs` with no args for full usage.
 *
 * Ported from ReactiveUIToolKit's scripts/changelog.mjs (retargeted to ide-extensions/).
 */
import { readFileSync, writeFileSync, existsSync } from 'fs';
import { resolve, dirname, relative } from 'path';
import { fileURLToPath } from 'url';
import { createHash } from 'crypto';

const __dirname = dirname(fileURLToPath(import.meta.url));
const IDE_ROOT = resolve(__dirname, '..'); // ide-extensions/
const REPO_ROOT = resolve(IDE_ROOT, '..');
const CHANGELOG_PATH = resolve(IDE_ROOT, 'changelog.json');
// Changelog targets ("ides" for historical reasons): the two IDE extensions + the
// Godot editor addon. Each is a valid --scope and a valid version flag (--vscode /
// --vs2022 / --editor X.Y.Z).
const KNOWN_IDES = ['vscode', 'vs2022', 'editor'];

// ── helpers ──────────────────────────────────────────────────────────────────

function readChangelog() {
  try {
    return JSON.parse(readFileSync(CHANGELOG_PATH, 'utf8'));
  } catch {
    return { entries: [] };
  }
}

function writeChangelog(data) {
  writeFileSync(CHANGELOG_PATH, JSON.stringify(data, null, 2) + '\n', 'utf8');
}

function today() {
  return new Date().toISOString().slice(0, 10);
}

function parseArgs(argv) {
  const args = {};
  for (let i = 0; i < argv.length; i++) {
    if (argv[i].startsWith('--')) {
      const key = argv[i].slice(2);
      const next = argv[i + 1];
      if (next && !next.startsWith('--')) {
        args[key] = next;
        i++;
      } else {
        args[key] = true;
      }
    }
  }
  return args;
}

function output(text, args) {
  if (args.out) {
    writeFileSync(resolve(args.out), text, 'utf8');
    console.error(`Wrote ${resolve(args.out)}`);
  } else {
    process.stdout.write(text);
  }
}

// ── add ──────────────────────────────────────────────────────────────────────

/**
 * Detect tell-tale signs of CP1252→UTF-8 mojibake in a message string.
 * On Windows, invoking this script through PowerShell or cmd transcodes argv
 * to the active code page (typically CP1252) before Node receives it, so
 * characters like `—`, `’`, curly quotes, and ellipsis arrive corrupted
 * (`â€"`, `â€™`, `â€¦`, …). We refuse to write such content to the JSON.
 *
 * Also catches the silent truncation when a message contains `"…"` (PowerShell
 * strips embedded double-quotes from argv): use --message-file instead.
 */
function detectArgvCorruption(message) {
  if (/Â[-¿]/.test(message)
   || /Ã[-¿]/.test(message)
   || /â€/.test(message)
   || /â‚/.test(message)
   || /ï¿½/.test(message)
  ) {
    return 'looks like CP1252→UTF-8 mojibake (e.g. "â€"" instead of "—"). '
      + 'PowerShell/cmd transcoded argv. Use --message-file <utf8-file> instead.';
  }
  if (message.includes('�')) {
    return 'contains the Unicode replacement character (U+FFFD). '
      + 'Use --message-file <utf8-file> instead.';
  }
  return null;
}

/** Read message text from --message-file (UTF-8) or --message (argv). */
function readMessageArg(args) {
  if (args['message-file']) {
    const p = resolve(args['message-file']);
    if (!existsSync(p)) {
      console.error(`Message file not found: ${p}`);
      process.exit(1);
    }
    return readFileSync(p, 'utf8').replace(/\r\n/g, '\n').replace(/\n+$/, '');
  }
  if (args.message && args.message !== true) {
    return args.message;
  }
  return null;
}

function cmdAdd(args) {
  const scope = args.scope;
  const message = readMessageArg(args);

  if (!scope || !message) {
    console.error(
      'Usage: add --scope <shared|vscode|vs2022|editor>\n' +
      '           (--message "text" | --message-file <path>)\n' +
      '           [--vscode X.Y.Z] [--vs2022 X.Y.Z] [--editor X.Y.Z] [--date YYYY-MM-DD]\n' +
      '\n' +
      'A `shared` message lands in the changelog of every target the entry lists a\n' +
      'version for. Prefer --message-file for any non-ASCII content (em-dashes,\n' +
      'quotes, etc.) — PowerShell/cmd transcode argv through the active code page\n' +
      'and corrupt UTF-8.'
    );
    process.exit(1);
  }

  const corruption = detectArgvCorruption(message);
  if (corruption) {
    console.error(`Refusing to add: message ${corruption}`);
    process.exit(1);
  }

  if (scope !== 'shared' && !KNOWN_IDES.includes(scope)) {
    console.error(`Unknown scope: ${scope}. Use: shared, ${KNOWN_IDES.join(', ')}`);
    process.exit(1);
  }

  const versions = {};
  for (const ide of KNOWN_IDES) {
    if (args[ide]) versions[ide] = args[ide];
  }
  if (Object.keys(versions).length === 0) {
    console.error('Provide at least one target version: --vscode X.Y.Z, --vs2022 X.Y.Z, --editor X.Y.Z');
    process.exit(1);
  }

  const date = args.date || today();
  const data = readChangelog();

  let entry = data.entries.find(e =>
    e.date === date &&
    Object.entries(versions).every(([k, v]) => e.versions[k] === v)
  );

  if (!entry) {
    entry = { date, versions };
    data.entries.unshift(entry); // newest first
  }

  if (!entry[scope]) entry[scope] = [];
  entry[scope].push(message);

  writeChangelog(data);
  const verStr = Object.entries(versions).map(([k, v]) => `${k} ${v}`).join(', ');
  console.error(`Added to ${scope} in ${date} entry (${verStr})`);
}

// ── extract ──────────────────────────────────────────────────────────────────

/**
 * Per-target header block for the generated CHANGELOG.md. vscode/vs2022 keep the
 * historical bare header (changing it would churn every committed file); the editor
 * addon's states its cutover contract.
 */
const HEADERS = {
  editor: [
    '# Changelog',
    '',
    'All notable changes to the **Reactive UI Toolkit — Godot Editor** Godot addon are documented here.',
    'This addon versions independently of the `reactive_ui_toolkit` runtime library. Entries from',
    '0.6.3 onward are generated from `ide-extensions/changelog.json` (the single source',
    'shared with the GUITKX IDE extensions) — add entries via `changelog.mjs add --scope',
    'editor`, then regenerate this file with `extract`; never edit it by hand. The history',
    'below the marker line predates the cutover and is preserved verbatim.',
  ].join('\n'),
};

/**
 * The editor addon's pre-cutover history is kept byte-verbatim below this marker in
 * its committed CHANGELOG.md. extract/verify treat everything from the marker down as
 * an opaque tail: extract re-emits it unchanged, verify compares against it unchanged.
 * (The tail is therefore not drift-guarded — it is frozen history, not a live surface.)
 */
const LEGACY_MARKER = '<!-- changelog.mjs cutover: entries above are generated from ide-extensions/changelog.json; the history below is frozen and preserved verbatim. -->';

function readLegacyTail(filePath) {
  if (!existsSync(filePath)) return '';
  const txt = readFileSync(filePath, 'utf8').replace(/\r\n/g, '\n');
  const at = txt.indexOf(LEGACY_MARKER);
  return at === -1 ? '' : txt.slice(at).trimEnd() + '\n';
}

function sha256(text) {
  return createHash('sha256').update(text, 'utf8').digest('hex');
}

/**
 * The tail lives in the committed file itself, so a plain read-back is self-consistent
 * by construction — a hand-edit BELOW the marker would sail through verify. To close
 * that hole, changelog.json pins each cutover target's frozen tail with a sha256
 * (`legacyTailHashes`). extract and verify both refuse a tail that doesn't match, so
 * vandalized history can neither pass CI nor be laundered into a "regenerated" file.
 * Deliberate history corrections are made by updating the pinned hash alongside the edit.
 */
function readLegacyTailChecked(data, ide) {
  const relPath = CHANGELOG_FILES[ide];
  if (!relPath) return '';
  const tail = readLegacyTail(resolve(IDE_ROOT, relPath));
  const pinned = (data.legacyTailHashes || {})[ide];
  if (pinned) {
    const disp = displayPath(relPath);
    if (!tail) {
      console.error(`✗ ${disp}: the frozen legacy history (below the cutover marker) is MISSING.`);
      console.error(`  Restore the file from git — the marker line and everything below it are pinned.`);
      process.exit(1);
    }
    const got = sha256(tail);
    if (got !== pinned) {
      console.error(`✗ ${disp}: the frozen legacy history (below the cutover marker) was MODIFIED.`);
      console.error(`  Restore it from git. If this change to frozen history is deliberate, update`);
      console.error(`  legacyTailHashes.${ide} in ide-extensions/changelog.json to: ${got}`);
      process.exit(1);
    }
  }
  return tail;
}

/**
 * Render the CHANGELOG.md text for a target from the changelog data.
 * The SAME rendering is used by `extract` (writes it) and `verify` (checks it) —
 * one implementation, so the two can never drift from each other the way the
 * committed CHANGELOG.md files drifted from changelog.json (see `verify`'s doc
 * comment for the incident this guards against).
 */
function renderChangelog(data, ide, version) {
  const relevant = data.entries.filter(e => e.versions && e.versions[ide]);
  const filtered = version ? relevant.filter(e => e.versions[ide] === version) : relevant;

  const lines = [HEADERS[ide] ?? '# Changelog', ''];
  for (const entry of filtered) {
    const ver = entry.versions[ide];
    lines.push(`## [${ver}] - ${entry.date}`);
    const messages = [...(entry.shared || []), ...(entry[ide] || [])];
    for (const msg of messages) lines.push(`- ${msg}`);
    lines.push('');
  }
  return lines.join('\n');
}

/**
 * Full committed-file content for a target: rendered entries + (for targets with a
 * cutover) the frozen legacy tail read from the CANONICAL committed path — so
 * `extract --out <canonical path>` round-trips and `verify` checks the same bytes.
 */
function renderFull(data, ide) {
  const rendered = renderChangelog(data, ide);
  const tail = readLegacyTailChecked(data, ide);
  return tail ? rendered + '\n' + tail : rendered;
}

function cmdExtract(args) {
  const ide = args.ide;
  if (!ide) {
    console.error(`Usage: extract --ide <${KNOWN_IDES.join('|')}> [--version X.Y.Z] [--out file]`);
    process.exit(1);
  }

  const data = readChangelog();
  // --version extracts a single release's notes (no header tail); the plain form
  // regenerates the full committed file including any frozen legacy tail.
  output(args.version ? renderChangelog(data, ide, args.version) : renderFull(data, ide), args);
}

// ── verify ───────────────────────────────────────────────────────────────────

/**
 * The committed CHANGELOG.md for each target, relative to IDE_ROOT (ide-extensions/).
 * `vs2022`'s is never regenerated by any CI/publish step today (only vscode's is,
 * in `.github/workflows/publish.yml`), so it is exactly as prone to drift — this
 * check covers all targets the same way. The editor addon's lives outside
 * ide-extensions/ (it ships inside the Godot addon; publish.yml extracts its release
 * body from the file's top `## [` section, which the generated format preserves).
 */
const CHANGELOG_FILES = {
  vscode: 'vscode/CHANGELOG.md',
  vs2022: 'visual-studio/CHANGELOG.md',
  editor: '../addons/reactive_ui_toolkit_editor/CHANGELOG.md',
};

/**
 * Marketplace-body targets that are GENERATED + COMMITTED (unlike vs2022's overview.md,
 * which is publish-time-only and never checked into git). Each entry is checked only when
 * its template file exists, so adding a template for a new target wires the drift gate for
 * free — no verify-side change needed.
 */
const OVERVIEW_TARGETS = {
  vscode: { template: 'vscode/readme-template.md', output: 'vscode/README.md' },
};

/** Repo-relative display path (for hints/messages), forward slashes on every OS. */
function displayPath(relToIdeRoot) {
  return relative(REPO_ROOT, resolve(IDE_ROOT, relToIdeRoot)).replace(/\\/g, '/');
}

/**
 * Guards the exact failure mode that shipped GUITKX 0.6.0-0.8.4: engineers bumped
 * `ide-extensions/vscode/CHANGELOG.md` by hand (or added entries to it without a
 * matching `changelog.mjs add`), so `changelog.json` — the documented single
 * source of truth — silently fell 14 versions behind what was actually released.
 * The Marketplace "Changelog" tab reads the CHANGELOG.md bundled into whatever
 * VSIX was last actually published, which is regenerated FROM changelog.json at
 * publish time — so a stale changelog.json means the next publish ships a
 * changelog that is wrong (or the discrepancy is masked until publish exposes it).
 *
 * Run in CI on every push/PR (the `gates` job in `.github/workflows/test.yml`): fails
 * loudly, with a diff, the moment changelog.json and a committed CHANGELOG.md
 * disagree — instead of silently at the next publish.
 */
function cmdVerify(args) {
  const ides = args.ide ? [args.ide] : Object.keys(CHANGELOG_FILES);
  const data = readChangelog();
  let ok = true;

  for (const ide of ides) {
    const relPath = CHANGELOG_FILES[ide];
    if (!relPath) {
      console.error(`Unknown target for verify: ${ide}. Use: ${Object.keys(CHANGELOG_FILES).join(', ')}`);
      process.exit(1);
    }

    const filePath = resolve(IDE_ROOT, relPath);
    const disp = displayPath(relPath);
    const expected = renderFull(data, ide);

    if (!existsSync(filePath)) {
      console.error(`✗ ${disp}: missing (expected it to be generated from changelog.json)`);
      ok = false;
      continue;
    }

    const actual = readFileSync(filePath, 'utf8').replace(/\r\n/g, '\n');
    if (actual.trimEnd() !== expected.trimEnd()) {
      console.error(`✗ ${disp} is out of sync with changelog.json.`);
      console.error(`  Regenerate it: node ide-extensions/scripts/changelog.mjs extract --ide ${ide} --out ${disp}`);
      console.error(`  (If changelog.json itself is missing entries, add them first with the 'add' command —`);
      console.error(`   never hand-edit ${disp}.)`);
      ok = false;
    } else {
      console.error(`✓ ${disp} matches changelog.json`);
    }
  }

  // Generated-and-committed marketplace bodies (e.g. vscode/README.md) — same drift gate
  // as the CHANGELOGs above, only when the target has opted in via a template file.
  for (const ide of ides) {
    const target = OVERVIEW_TARGETS[ide];
    if (!target) continue;
    const templatePath = resolve(IDE_ROOT, target.template);
    if (!existsSync(templatePath)) continue;

    const outPath = resolve(IDE_ROOT, target.output);
    const disp = displayPath(target.output);
    const expected = renderOverview(data, ide, readFileSync(templatePath, 'utf8'));

    if (!existsSync(outPath)) {
      console.error(`✗ ${disp}: missing (expected it to be generated from ${displayPath(target.template)} + changelog.json)`);
      console.error(`  Generate it: node ide-extensions/scripts/changelog.mjs extract-overview --ide ${ide} --template ${displayPath(target.template)} --out ${disp}`);
      ok = false;
      continue;
    }

    const actual = readFileSync(outPath, 'utf8').replace(/\r\n/g, '\n');
    if (actual.trimEnd() !== expected.trimEnd()) {
      console.error(`✗ ${disp} is out of sync with ${displayPath(target.template)} + changelog.json.`);
      console.error(`  Regenerate it: node ide-extensions/scripts/changelog.mjs extract-overview --ide ${ide} --template ${displayPath(target.template)} --out ${disp}`);
      console.error(`  (Never hand-edit ${disp} — edit the template, then regenerate.)`);
      ok = false;
    } else {
      console.error(`✓ ${disp} matches ${displayPath(target.template)} + changelog.json`);
    }
  }

  if (!ok) {
    console.error('\nchangelog verify FAILED — see above.');
    process.exit(1);
  }
  console.error('\nchangelog verify OK.');
}

// ── extract-overview ─────────────────────────────────────────────────────────

/**
 * Render a marketplace-page body: a template's content plus a generated `## Changelog`
 * section from the changelog data. Shared by `extract-overview` (writes it) and `verify`
 * (checks committed generated bodies, e.g. vscode/README.md) — one implementation, so the
 * two can never drift from each other.
 */
function renderOverview(data, ide, templateContent) {
  const relevant = data.entries.filter(e => e.versions && e.versions[ide]);

  const changelogLines = ['## Changelog', ''];
  for (const entry of relevant) {
    const ver = entry.versions[ide];
    changelogLines.push(`### [${ver}] - ${entry.date}`);
    const messages = [...(entry.shared || []), ...(entry[ide] || [])];
    for (const msg of messages) changelogLines.push(`- ${msg}`);
    changelogLines.push('');
  }

  return templateContent.trimEnd() + '\n\n' + changelogLines.join('\n');
}

function cmdExtractOverview(args) {
  const ide = args.ide;
  const template = args.template;

  if (!ide || !KNOWN_IDES.includes(ide) || !template) {
    console.error(`Usage: extract-overview --ide <${KNOWN_IDES.join('|')}> --template <path> [--out file]`);
    process.exit(1);
  }

  const templatePath = resolve(template);
  if (!existsSync(templatePath)) {
    console.error(`Template not found: ${templatePath}`);
    process.exit(1);
  }

  const data = readChangelog();
  const templateContent = readFileSync(templatePath, 'utf8');
  output(renderOverview(data, ide, templateContent), args);
}

// ── import ───────────────────────────────────────────────────────────────────

function cmdImport(args) {
  const ide = args.ide;
  const file = args.file;
  if (!ide || !file) {
    console.error('Usage: import --ide <vscode|vs2022> --file <path-to-CHANGELOG.md>');
    process.exit(1);
  }

  const filePath = resolve(file);
  if (!existsSync(filePath)) {
    console.error(`File not found: ${filePath}`);
    process.exit(1);
  }

  const content = readFileSync(filePath, 'utf8');
  const data = readChangelog();
  const SKIP = new Set(['skip', 'skip-no-new-entry', 'already set', 're-publish']);
  const versionRe = /^#{2,3}\s*\[([^\]]+)\]\s*-?\s*(\d{4}-\d{2}-\d{2})?/;
  let curVer = null, curDate = null;

  for (const line of content.split('\n')) {
    const m = line.match(versionRe);
    if (m) { curVer = m[1]; curDate = m[2] || 'unknown'; continue; }
    if (curVer && line.startsWith('- ')) {
      const msg = line.slice(2).trim();
      if (!msg || SKIP.has(msg)) continue;
      let entry = data.entries.find(e => e.versions && e.versions[ide] === curVer);
      if (!entry) { entry = { date: curDate, versions: { [ide]: curVer } }; data.entries.push(entry); }
      if (!entry[ide]) entry[ide] = [];
      if (!entry[ide].includes(msg)) entry[ide].push(msg);
    }
  }

  data.entries.sort((a, b) => {
    const da = a.date === 'unknown' ? '0000-00-00' : a.date;
    const db = b.date === 'unknown' ? '0000-00-00' : b.date;
    if (da !== db) return da > db ? -1 : 1;
    const aMax = Math.max(...Object.values(a.versions).map(v => parseFloat(v.split('.').pop()) || 0));
    const bMax = Math.max(...Object.values(b.versions).map(v => parseFloat(v.split('.').pop()) || 0));
    return bMax - aMax;
  });

  writeChangelog(data);
  const count = data.entries.filter(e => e.versions && e.versions[ide]).length;
  console.error(`Imported ${count} ${ide} entries from ${file}`);
}

// ── main ─────────────────────────────────────────────────────────────────────

const [command, ...rest] = process.argv.slice(2);
const args = parseArgs(rest);

switch (command) {
  case 'add':              cmdAdd(args); break;
  case 'extract':          cmdExtract(args); break;
  case 'extract-overview': cmdExtractOverview(args); break;
  case 'import':           cmdImport(args); break;
  case 'verify':           cmdVerify(args); break;
  default:
    console.log(
`Usage: node ide-extensions/scripts/changelog.mjs <command> [options]

Targets: vscode, vs2022, editor (the Godot editor addon). The reactive_ui_toolkit runtime
library is NOT managed here — its changelog is hand-written (root CHANGELOG.md,
mirrored byte-identically into addons/reactive_ui_toolkit/).

Commands:
  add              Add a changelog entry
  extract          Generate a target's CHANGELOG.md
  extract-overview Generate a marketplace-page body (template + changelog section)
  import           Import entries from existing markdown changelog
  verify           Check every committed CHANGELOG.md / generated body matches
                   changelog.json (CI gate)

Examples:
  add --scope shared --message "Fix: server crash" --vscode 0.1.1 --vs2022 0.1.1
  add --scope shared --message-file CHANGES.txt --vscode 0.2.0 --vs2022 0.2.0
  add --scope vscode --message "Fix: debounce" --vscode 0.1.1
  add --scope editor --message-file NOTES.txt --editor 0.6.4
  extract --ide vscode --out ide-extensions/vscode/CHANGELOG.md
  extract --ide editor --out addons/reactive_ui_toolkit_editor/CHANGELOG.md
  extract-overview --ide vscode --template ide-extensions/vscode/readme-template.md --out ide-extensions/vscode/README.md
  extract-overview --ide vs2022 --template ide-extensions/visual-studio/GuitkxVsix/overview-template.md --out overview.md
  import --ide vscode --file ide-extensions/vscode/CHANGELOG.md

Tips:
  • After add: run extract for EVERY target the entry names, and commit the
    regenerated files with changelog.json — the changelog-sync CI job fails on drift.
  • ide-extensions/vscode/README.md is GENERATED (from readme-template.md) and COMMITTED —
    same drift rule as the CHANGELOGs; never hand-edit it. vs2022's overview.md is
    publish-time only (never committed), so verify doesn't check it.
  • Prefer --message-file for any non-ASCII content (em-dashes, quotes, code chars).
    PowerShell/cmd on Windows transcode argv through CP1252 and strip embedded quotes —
    --message-file reads UTF-8 verbatim and avoids both pitfalls.`
    );
}
