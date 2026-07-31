#!/usr/bin/env node
// Copyright (c) 2026 Yaniv Kalfa. All Rights Reserved.
/**
 * CI gate: no machine-local paths in tracked files. Family invariant, mirrored byte-for-byte across
 * the three Reactive UI Toolkit repos except for the DATA blocks below (the corpus-hash.mjs
 * precedent: same script, per-leg data).
 *
 * WHY THIS EXISTS: the rebrand wave rewrote a repo-folder segment INSIDE a hardcoded absolute path
 * (`…/ReactiveUI-Unreal/…` -> `…/ruitk-unreal/…` in .vscode/launch.json), which silently broke F5
 * for every clone whose folder name differs from the author's. Three independent audits looked at
 * that line, classified it "owner machine path — leave it", and stopped one level too shallow.
 * Judgment missed it three times; a grep cannot. Hence a gate rather than a note.
 *
 * THE INVARIANT: machine facts live in an env var or the gitignored .ruitk-local.json (see the
 * "Machine-local paths" section of CLAUDE.md) — never in a tracked file. Repo locations are DERIVED,
 * never written down: the repo root is this script's `..`, worktrees come from `git worktree list`.
 *
 * Specimen paths in this file are written `<drive>:` rather than with a real drive letter ON PURPOSE:
 * this script is scanned by itself, and a gate whose rules do not apply to the file defining the
 * rules is a permanent blind spot. Do not "fix" them into literal paths.
 *
 * TWO RULES
 *   R1 PERSONAL-ROOT PATHS — a drive-absolute path (`<drive>:\…`, `<drive>:/…`) or an explicit
 *      user-home POSIX path (`/home/<u>/`, `/Users/<u>/`, `/mnt/<d>/`) whose root is NOT in ALLOWED_ROOTS.
 *      Standard shared roots are deliberately legitimate: tool-discovery code SHOULD name
 *      `C:\Program Files\…` when probing for an engine/SDK, and CI workflows SHOULD name their
 *      runner's paths. What is never legitimate is a path that exists only on one person's disk.
 *   R2 PORTABILITY-CRITICAL FILES — the files in PORTABILITY_CRITICAL must contain ZERO
 *      drive-absolute paths regardless of root. They execute on other people's machines and have
 *      variable substitution available (`${workspaceFolder}`, `$(MSBuildThisFileDirectory)`), so an
 *      absolute path there is never the right answer even when it points somewhere standard.
 *
 * EXEMPTIONS are data, not code, and each one carries a `why`. Two classes earn one:
 *   - frozen tiers (archived plans, research, shipped changelog history) — the historical record is
 *     not ours to edit;
 *   - test trees — synthetic fixtures like "<drive>:/proj/Assets/UI" exist precisely to assert
 *     Windows-path handling; they are the thing under test, not a leak.
 * A single line can also opt out with a trailing `path-gate-allow: <reason>` comment — for the rare
 * doc-comment that must show a literal Windows path to explain URI logic. The reason lives next to
 * the code, which beats a growing central list nobody re-reads.
 *
 *   node scripts/check-machine-paths.mjs           check (CI gate; exit 1 on violation)
 *   node scripts/check-machine-paths.mjs --list    print every absolute path found, with verdict
 */
import { readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { resolve, dirname, posix } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');

// ── DATA: per-leg. Everything above this point is identical family-wide. ──────────────────────────

/**
 * Roots that are shared facts about a PLATFORM or a CI RUNNER, not about a person's disk. A path
 * under one of these is allowed to be written down: it means the same thing on every machine of
 * that kind, which is exactly what tool-discovery code needs.
 */
const ALLOWED_ROOT_LITERALS = [
	'C:\\Program Files',
	'C:\\Program Files (x86)',
	'C:\\Windows',
	'C:\\ProgramData',
	'/usr/',
	'/opt/',
	'/tmp/',
	'/var/',
	'/etc/',
];

/**
 * Files and trees the rules do not apply to. Every entry states WHY — an exemption without a
 * reason is how gates rot into decoration.
 */
const EXEMPT = [
	// FROZEN TIERS — the historical record documents what was true then; editing it is a lie.
	{ re: /^plans\/archive\//, why: 'frozen: archived plans' },
	{ re: /^research\//, why: 'frozen: research notes' },
	// TEST TREES — synthetic "<drive>:/proj/x" fixtures are the subject under test, not a leak.
	{ re: /(^|\/)(test|tests|test-fixtures)\//i, why: 'test tree: synthetic path fixtures' },
	{ re: /\.test\.[cm]?[jt]sx?$/, why: 'test file: synthetic path fixtures' },
];

/**
 * Files that must be absolute-path-free no matter what the path points at (rule R2). These are
 * committed configs that run on OTHER people's machines and have variable substitution available.
 */
const PORTABILITY_CRITICAL = [
	/(^|\/)\.vscode\/[^/]+\.json$/,
	/\.csproj$/,
	/\.vcxproj$/,
	/\.sln$/,
	/\.code-workspace$/,
];

// ── ENGINE: identical family-wide. ───────────────────────────────────────────────────────────────

/**
 * Each allowed root is admitted twice: once as written, once with its separators doubled. JS/TS/JSON
 * sources spell a Windows separator `\\`, and the root test compares against raw line text (see
 * underAllowedRoot), which cannot see through the escape — so discovery code that legitimately names
 * a standard root inside a string literal would otherwise be flagged, INCLUDING this script's own
 * root list. Derived rather than hand-typed, so the two spellings cannot drift apart and no root is
 * admitted that the plain list does not already allow.
 */
const ALLOWED_ROOTS = ALLOWED_ROOT_LITERALS.flatMap((r) => [r, r.replace(/\\/g, '\\\\')]);

const BINARY_EXT =
	/\.(png|jpg|jpeg|gif|ico|pdf|zip|vsix|unitypackage|dll|pdb|exe|node|so|dylib|ttf|otf|woff2?|mp3|wav|ogg|mp4|locres|locmeta|uasset|umap|bin|nupkg)$/i;

/**
 * A drive-absolute path. The leading boundary is explicit rather than `\b` on purpose: `\b[A-Za-z]:`
 * also matches the `s:` inside a C++ format string like "%scase %s:\n%s{" (a real false positive
 * found during the census), because `%s` ends on a word char. Requiring the drive letter to sit at a
 * token start — line start, whitespace, quote, bracket, `=`, `,` or the `///` of a file URI — keeps
 * format strings and escape sequences out while still catching every real path.
 */
const DRIVE_ABS = /(?<=^|[\s"'`(\[{=,>]|\/\/\/)([A-Za-z]:[\\/][^\s"'`,;)\]}<>|*?\n]*)/g;

/** An explicit user-home POSIX path. Bare `/foo` is NOT matched: it is far more often a URL path or
 *  a repo-relative path than a filesystem absolute, and a rule that cried wolf there would be
 *  switched off within a week. */
const HOME_ABS = /(?<=^|[\s"'`(\[{=,>]|\/\/\/)((?:\/(?:home|Users|mnt)\/[A-Za-z0-9._-]+)[^\s"'`,;)\]}<>|*?\n]*)/g;

const args = process.argv.slice(2);
const LIST_MODE = args.includes('--list');

const tracked = execFileSync('git', ['ls-files', '-z'], { cwd: REPO_ROOT, maxBuffer: 64 * 1024 * 1024 })
	.toString('utf8')
	.split('\0')
	.filter(Boolean);

const exemptionFor = (file) => EXEMPT.find((e) => e.re.test(file));
const isPortabilityCritical = (file) => PORTABILITY_CRITICAL.some((re) => re.test(file));

/**
 * Allowed-root test runs against the RAW LINE from the match offset, not against the captured hit.
 * Captured hits stop at the first space (otherwise a match would run to end-of-sentence in prose),
 * but two of the roots that matter — `C:\Program Files` and `C:\Program Files (x86)` — contain
 * spaces. Testing the line slice is what lets the standard runner path for vswhere register as the
 * shared platform fact it is, instead of as its space-truncated first token.
 */
const underAllowedRoot = (line, index) => {
	const tail = line.slice(index).replace(/\//g, '\\').toLowerCase();
	return ALLOWED_ROOTS.some((root) => tail.startsWith(root.replace(/\//g, '\\').toLowerCase()));
};

/**
 * A single letter, a colon, then an escape sequence — as emitted by codegen building indented source
 * — is not a path. Real paths continue into a path segment (`<drive>:\node\…` keeps its `n` but is
 * followed by more word characters), so the tell is an escape letter followed by a NON-word char.
 */
const isEscapeSequence = (hit) => /^[A-Za-z]:[\\/][ntr0bfv\\"'](?![A-Za-z0-9_])/.test(hit);

/** Line-level opt-out with a mandatory reason, for doc-comments that must show a literal path. */
const INLINE_ALLOW = /path-gate-allow:\s*\S/;

const violations = [];
const listed = [];

for (const file of tracked) {
	if (BINARY_EXT.test(file)) continue;
	let text;
	try {
		text = readFileSync(resolve(REPO_ROOT, file), 'utf8');
	} catch {
		continue; // unreadable / deleted-but-indexed — not this gate's problem
	}
	if (text.includes('\0')) continue; // binary without a known extension

	const exemption = exemptionFor(file);
	const critical = isPortabilityCritical(file);
	const lines = text.split(/\r?\n/);

	for (let i = 0; i < lines.length; i++) {
		const line = lines[i];
		const inlineAllowed = INLINE_ALLOW.test(line);
		const matches = [...line.matchAll(DRIVE_ABS), ...line.matchAll(HOME_ABS)];
		for (const m of matches) {
			const hit = m[1];
			if (isEscapeSequence(hit)) continue; // string-literal escape, not a path
			const allowed = underAllowedRoot(line, m.index);
			// R2 first: in a portability-critical file, even a standard root is a defect.
			const rule = critical ? 'R2' : allowed ? null : 'R1';
			const skip = exemption ? `exempt (${exemption.why})` : inlineAllowed ? 'exempt (inline path-gate-allow)' : null;
			const verdict = !rule ? 'ok (standard root)' : (skip ?? rule);
			if (LIST_MODE) listed.push({ file, line: i + 1, hit, verdict });
			if (rule && !skip) violations.push({ file, line: i + 1, hit, rule });
		}
	}
}

if (LIST_MODE) {
	for (const l of listed) console.error(`${l.file}:${l.line}  [${l.verdict}]  ${l.hit}`);
	console.error(`\n${listed.length} absolute path(s) found; ${violations.length} would fail the gate.`);
	process.exit(0);
}

if (violations.length === 0) {
	console.error('✓ no machine-local paths in tracked files');
	process.exit(0);
}

console.error('✗ machine-local paths found in tracked files:\n');
for (const v of violations) console.error(`  ${v.file}:${v.line}  [${v.rule}]  ${v.hit}`);
console.error(`
${violations.length} violation(s).

  R1 — a path that exists only on one machine. Move the value to an env var or the gitignored
       .ruitk-local.json (see CLAUDE.md "Machine-local paths"), or derive it: the repo root is
       discoverable, worktrees come from \`git worktree list\`, and tools should be probed on PATH
       and in their standard install roots.
  R2 — a committed config that other people run must not name an absolute path at all. Use
       \${workspaceFolder} (VS Code) or \$(MSBuildThisFileDirectory) (MSBuild).

If a hit is genuinely legitimate, add it to EXEMPT in this script WITH a reason — never widen the
allow-list to make a leak pass.`);
process.exit(1);
