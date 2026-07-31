#!/usr/bin/env node
// Copyright (c) 2026 Yaniv Kalfa. All Rights Reserved.
/**
 * The family Discord-changelog pipeline: one script, three commands, driving this leg's
 * DISCORD_CHANGELOG.md. Family invariant, mirrored byte-for-byte across the three Reactive UI
 * Toolkit repos except for the DATA block below (the check-machine-paths.mjs precedent: shared
 * ENGINE, per-leg DATA).
 *
 * The changelog file is the source of truth; the DISCORD CHANNEL HISTORY is the ledger. A release
 * entry's `## [<version>]` header is both its identity in the file and its dedup key in the
 * channel (owner ruling: no footer markers — the header IS the key). `post` is therefore
 * idempotent: it scans the channel's recent messages for the `[<version>]` substring and
 * green-no-ops when the entry is already up, so the publish job can be re-run standalone at will.
 *
 * Entry grammar (matches every shipped entry across all three legs):
 *   ## [<version>] - <YYYY-MM-DD>
 * with a hyphen, en dash, or em dash before the date; <version> is a semver, optionally
 * word-prefixed (`[Tooling 0.10.1]`). The VERSION IN BRACKETS is the identity — the date is
 * validated for shape only. An entry runs to the next `## ` heading (non-entry `## ` sections,
 * like a pinned announcement post, are ignored); a trailing `---` separator between entries is
 * not part of the message.
 *
 * verify enforces, per entry: <= 2000 characters (Discord's message cap), no masked
 * `[text](url)` links (they do not render as links in a plain Discord message), and no duplicate
 * version headers (a duplicate would corrupt the dedup ledger).
 *
 *   node scripts/discord-changelog.mjs verify                 format + caps gate (CI `gates` job)
 *   node scripts/discord-changelog.mjs preview <version>      print the exact message body + count
 *   node scripts/discord-changelog.mjs post <version> [--dry-run]
 *       post the entry to this leg's channel (publish.yml `discord` job). Requires
 *       DISCORD_BOT_TOKEN. --dry-run runs the full ledger check and prints the decision only.
 */
import { readFileSync, existsSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');

// ── DATA: per-leg. Everything above this point is identical family-wide. ──────────────────────────

/** This leg's name, used only in messages so an error names the repo it came from. */
const REPO_LABEL = 'ruitk-godot';

/** The family Discord server channel this leg's release notes post to. */
const CHANNEL_ID = '1532108206568898773';

/** The leg's Discord changelog, repo-relative. */
const CHANGELOG_PATH = 'plans/DISCORD_CHANGELOG.md';

/**
 * Shipped entries that predate the cap gate and exceed it (posted manually, split across
 * messages, before this pipeline existed). The historical record is not ours to edit, so they
 * are grandfathered BY NAME — verify still prints them as a note, the cap still binds every
 * other entry, and `post` refuses an oversize body regardless of this list.
 */
const OVERSIZE_SHIPPED = [];

// ── ENGINE: identical family-wide. ───────────────────────────────────────────────────────────────

/** Discord's hard per-message character cap. */
const MESSAGE_CAP = 2000;

/** How deep the ledger scan reaches into the channel history (100 per page; releases are rare). */
const LEDGER_SCAN_LIMIT = 300;

/**
 * An entry header. The bracket holds the identity; the date separator accepts the hyphen the
 * files use today plus en/em dash (both header eras exist in house prose). Date shape only —
 * the version is the identity, so a miswritten date must not orphan a shipped entry.
 */
const HEADER_LINE = /^## \[/;
const HEADER_GRAMMAR = /^## \[([^\]\n]+)\]\s*[-–—]\s*(\d{4}-\d{2}-\d{2})\s*$/;
const VERSION_KEY = /^(?:[A-Za-z][A-Za-z0-9 ]*\s)?\d+\.\d+\.\d+$/;

/** A masked markdown link — `[text](target)`. Discord renders these literally in plain messages. */
const MASKED_LINK = /\[[^\]\n]*\]\([^)\n]*\)/;

function fail(msg) {
	console.error(msg);
	process.exit(1);
}

/**
 * Parse the changelog into entries. An entry starts at a `## [` line and runs to the next `## `
 * heading or EOF. `## ` headings without a bracket (announcement sections) close the previous
 * entry but start none. The trailing `---` separator (plus surrounding blank lines) is stripped
 * from the body — it delimits entries in the FILE, it is not part of the MESSAGE.
 */
function parseChangelog() {
	const file = resolve(REPO_ROOT, CHANGELOG_PATH);
	if (!existsSync(file)) fail(`✗ missing ${CHANGELOG_PATH} (${REPO_LABEL})`);
	const lines = readFileSync(file, 'utf8').split(/\r?\n/);

	const entries = [];
	let cur = null;
	const close = () => {
		if (!cur) return;
		const body = cur.bodyLines;
		while (body.length && body[body.length - 1].trim() === '') body.pop();
		if (body.length && body[body.length - 1].trim() === '---') {
			body.pop();
			while (body.length && body[body.length - 1].trim() === '') body.pop();
		}
		cur.body = body.join('\n');
		entries.push(cur);
		cur = null;
	};

	for (let i = 0; i < lines.length; i++) {
		const line = lines[i];
		if (line.startsWith('## ')) {
			close();
			if (HEADER_LINE.test(line)) {
				const m = line.match(HEADER_GRAMMAR);
				cur = {
					header: line,
					line: i + 1,
					key: m ? m[1] : null, // null = malformed header; verify reports it
					grammarOk: m !== null && VERSION_KEY.test(m[1]),
					bodyLines: [line],
				};
				if (m && !cur.grammarOk) cur.key = m[1]; // keep the identity for dup checks anyway
			}
		} else if (cur) {
			cur.bodyLines.push(line);
		}
	}
	close();
	return entries;
}

/** Character count the way Discord counts: Unicode code points of the exact message body. */
const charCount = (s) => [...s].length;

function verify() {
	const entries = parseChangelog();
	const findings = [];
	const notes = [];
	const seen = new Map(); // key -> first line

	for (const e of entries) {
		const id = e.key ? `[${e.key}]` : e.header;
		if (!e.grammarOk) {
			findings.push(
				`${CHANGELOG_PATH}:${e.line}  ${id}  header does not match the entry grammar ` +
					'`## [<version>] - <YYYY-MM-DD>` (version = semver, optional word prefix; hyphen or en/em dash before the date)'
			);
		}
		if (e.key) {
			if (seen.has(e.key)) {
				findings.push(
					`${CHANGELOG_PATH}:${e.line}  ${id}  duplicate version header (first at line ${seen.get(e.key)}) — ` +
						'the version in brackets is an entry\'s identity AND the channel dedup key, so it must be unique'
				);
			} else {
				seen.set(e.key, e.line);
			}
		}
		const n = charCount(e.body);
		if (n > MESSAGE_CAP) {
			if (e.key && OVERSIZE_SHIPPED.includes(e.key)) {
				notes.push(`${CHANGELOG_PATH}:${e.line}  ${id}  ${n} chars — grandfathered by name (OVERSIZE_SHIPPED; shipped pre-gate, posted split)`);
			} else {
				findings.push(
					`${CHANGELOG_PATH}:${e.line}  ${id}  entry is ${n} chars — over Discord's ${MESSAGE_CAP}-char message cap by ${n - MESSAGE_CAP}`
				);
			}
		}
		for (let i = 0; i < e.bodyLines.length; i++) {
			const hit = e.bodyLines[i].match(MASKED_LINK);
			if (hit) {
				findings.push(
					`${CHANGELOG_PATH}:${e.line + i}  ${id}  masked link ${JSON.stringify(hit[0])} — ` +
						'masked [text](url) links do not render in plain Discord messages; use the bare URL'
				);
			}
		}
	}

	for (const n of notes) console.error(`  note: ${n}`);
	if (findings.length > 0) {
		console.error(`✗ discord changelog: ${findings.length} finding(s) in ${CHANGELOG_PATH} (${REPO_LABEL}):\n`);
		for (const f of findings) console.error(`  ${f}`);
		process.exit(1);
	}
	console.error(`✓ discord changelog: ${entries.length} entries OK (${CHANGELOG_PATH}, all <= ${MESSAGE_CAP} chars, no masked links, no duplicate versions)`);
}

function findEntry(version) {
	const entries = parseChangelog();
	const e = entries.find((x) => x.key === version);
	if (!e) {
		const known = entries.slice(0, 8).map((x) => x.key).filter(Boolean).join(', ');
		fail(`✗ no [${version}] entry in ${CHANGELOG_PATH} (${REPO_LABEL}). Newest entries: ${known}`);
	}
	return e;
}

function preview(version) {
	const e = findEntry(version);
	process.stdout.write(e.body + '\n');
	console.error(`\n✓ [${version}] — ${charCount(e.body)} chars (cap ${MESSAGE_CAP})`);
}

/** One 429 retry per request; every other non-OK status surfaces with the fix spelled out. */
async function discordFetch(url, options, what) {
	for (let attempt = 0; attempt < 2; attempt++) {
		const res = await fetch(url, options);
		if (res.status === 429) {
			let after = Number(res.headers.get('retry-after'));
			if (!Number.isFinite(after) || after <= 0) {
				const body = await res.json().catch(() => ({}));
				after = Number(body.retry_after) || 1;
			}
			console.error(`  rate limited (429) while ${what} — retrying once in ${after}s`);
			await new Promise((r) => setTimeout(r, Math.ceil(after * 1000)));
			continue;
		}
		if (res.status === 401) {
			fail(`✗ Discord rejected the token (401) while ${what} — DISCORD_BOT_TOKEN is missing/rotated/not a bot token.`);
		}
		if (res.status === 403) {
			fail(
				`✗ Discord refused access (403) while ${what} — the bot lacks permissions on channel ${CHANNEL_ID} ` +
					`(${REPO_LABEL}'s channel). Fix: in the server, grant the bot View Channel + Read Message History` +
					' (+ Send Messages to post) on that channel.'
			);
		}
		if (res.status === 404) {
			fail(
				`✗ channel ${CHANNEL_ID} not found (404) while ${what} — the channelId in this script's DATA block is ` +
					`wrong for ${REPO_LABEL}, or the bot is not in the family Discord server.`
			);
		}
		if (!res.ok) {
			fail(`✗ Discord API error ${res.status} while ${what}: ${await res.text().catch(() => '')}`);
		}
		return res;
	}
	fail(`✗ still rate limited after one retry while ${what} — re-run in a minute.`);
}

/** The ledger check: does any recent channel message already contain `[<version>]`? */
async function findPostedMessage(version, headers) {
	const needle = `[${version}]`;
	let before = null;
	let scanned = 0;
	while (scanned < LEDGER_SCAN_LIMIT) {
		const url =
			`https://discord.com/api/v10/channels/${CHANNEL_ID}/messages?limit=100` +
			(before ? `&before=${before}` : '');
		const res = await discordFetch(url, { headers }, 'reading the channel history');
		const msgs = await res.json();
		if (!Array.isArray(msgs) || msgs.length === 0) break;
		for (const m of msgs) {
			if (typeof m.content === 'string' && m.content.includes(needle)) return m;
		}
		scanned += msgs.length;
		before = msgs[msgs.length - 1].id;
		if (msgs.length < 100) break;
	}
	return null;
}

async function post(version, dryRun) {
	const token = process.env.DISCORD_BOT_TOKEN;
	if (!token) {
		fail('✗ DISCORD_BOT_TOKEN is not set — post (and its --dry-run ledger check) needs the bot token.');
	}
	const e = findEntry(version);
	const n = charCount(e.body);
	if (n > MESSAGE_CAP) {
		fail(`✗ [${version}] is ${n} chars — over Discord's ${MESSAGE_CAP}-char cap; shorten the entry (verify catches this in CI).`);
	}

	const headers = {
		Authorization: `Bot ${token}`,
		'User-Agent': 'DiscordBot (https://github.com/reactive-ui-toolkit, 1.0)',
	};

	const existing = await findPostedMessage(version, headers);
	if (existing) {
		console.error(`✓ [${version}] already posted — skipping (message ${existing.id}, ${existing.timestamp ?? 'timestamp unknown'})`);
		return;
	}
	if (dryRun) {
		console.error(`✓ dry-run: [${version}] not posted yet — would post ${n} chars to channel ${CHANNEL_ID} (${REPO_LABEL}). Nothing was sent.`);
		return;
	}

	const res = await discordFetch(
		`https://discord.com/api/v10/channels/${CHANNEL_ID}/messages`,
		{
			method: 'POST',
			headers: { ...headers, 'Content-Type': 'application/json' },
			body: JSON.stringify({ content: e.body }),
		},
		'posting the release note'
	);
	const msg = await res.json();
	console.error(`✓ posted [${version}] (${n} chars) to channel ${CHANNEL_ID} (${REPO_LABEL}) — message ${msg.id}`);
}

const args = process.argv.slice(2);
const cmd = args[0];

switch (cmd) {
	case 'verify':
		verify();
		break;
	case 'preview':
		if (!args[1]) fail('✗ usage: discord-changelog.mjs preview <version>');
		preview(args[1]);
		break;
	case 'post': {
		if (!args[1] || args[1] === '--dry-run') fail('✗ usage: discord-changelog.mjs post <version> [--dry-run]');
		const dryRun = args.includes('--dry-run');
		await post(args[1], dryRun);
		break;
	}
	default:
		fail(
			'✗ usage: discord-changelog.mjs <verify | preview <version> | post <version> [--dry-run]>\n' +
				`  verify   format + caps gate over ${CHANGELOG_PATH}\n` +
				'  preview  print the exact message body that would post, plus its char count\n' +
				'  post     idempotent channel post (DISCORD_BOT_TOKEN required; --dry-run = decision only)'
		);
}
