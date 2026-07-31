---
name: machine-local-paths
description: The machine-local path invariant and its CI gate (scripts/check-machine-paths.mjs) — what it forbids, how to run it CORRECTLY (untracked files are invisible to it), the four legitimate ways to answer a violation, where machine facts live (.ruitk-local.json), and the copy-to-a-differently-named-folder portability test. Use when the gate fails, when adding or editing a .vscode config / script / workflow, after any rename or repo-wide sweep, when wiring a new external tool, or when moving/renaming the checkout.
---

# Machine-local paths

## The invariant

**No tracked file may name a path that exists only on one machine.** Repo locations are DERIVED, never
written down. External tools are PROBED, with an override chain. The irreducible machine values live in
one gitignored file. A CI gate enforces it.

Why it exists: the 0.13.0 rebrand sweep rewrote a repo-folder segment *inside* a hardcoded absolute
path in a `.vscode/launch.json`, silently breaking F5 for every clone whose folder name differed from
the author's. Three independent audits read that line, classified it "owner machine path — leave it",
and moved on. Judgment missed it three times, so this is a gate, not a note.

## The two rules

- **R1 — personal roots.** A drive-absolute path (`<drive>:\…`) or an explicit user-home POSIX path
  (`/home/<u>/`, `/Users/<u>/`, `/mnt/<d>/`) whose root is not in `ALLOWED_ROOTS`. Shared platform and
  CI roots (`C:\Program Files\…`, `/usr/…`) are **deliberately legal** — tool-discovery code *should*
  name them; they mean the same thing on every machine of that kind.
- **R2 — portability-critical files.** `.vscode/*.json` (at any depth), `*.csproj`, `*.sln`,
  `*.code-workspace` must contain **zero** drive-absolute paths, even standard ones. They run on other
  people's machines and have `${workspaceFolder}` available, so an absolute path is never right there.

## Running it

```bash
node scripts/check-machine-paths.mjs          # the gate (exit 1 on violation)
node scripts/check-machine-paths.mjs --list   # every absolute path found, with a verdict each
```

**THE TRAP — new files are invisible.** The gate enumerates `git ls-files`, i.e. tracked files only.
A brand-new file you just wrote is untracked, so the gate skips it and reports green — then turns red
on the commit that adds it. When your change ADDS files, test post-commit reality:

```bash
git add -N <the new files>      # index them without staging content
node scripts/check-machine-paths.mjs
git reset                       # put the index back
```

Both sibling repos' first gate runs passed only because of this blind spot. Always `-N` first.

## A violation has exactly four legitimate answers

1. **Derive it.** The repo root is discoverable (`git rev-parse --show-toplevel`, or a script's own
   `..`); worktrees come from `git worktree list`; VS Code configs use `${workspaceFolder}`. Most
   "machine facts" about *this repo* are not facts at all — they are lookups someone wrote down.
2. **Probe + override.** For an external tool: `$ENV_VAR` → `.ruitk-local.json` → PATH and standard
   install roots → an error naming all three rungs. Never a bare literal.
3. **Exempt it, with a reason.** Add an entry to `EXEMPT` in the gate carrying a `why` string. Earned
   only by frozen tiers (`plans/archive/**`, `research/**`, shipped changelog bodies) and test trees
   (synthetic `"<drive>:/proj/x"` fixtures are the subject under test, not a leak).
4. **Mark the line.** A trailing `path-gate-allow: <reason>` comment, for the rare doc-comment that
   must show a literal Windows path to explain URI logic. The reason lives next to the code.

**Never widen `ALLOWED_ROOTS` to make a violation pass.** That converts one leak into a permanent
class of leaks.

## Machine facts: `.ruitk-local.json`

Gitignored; copy `.ruitk-local.example.json` and fill it in. **Nothing may require it to exist** —
discovery must still work without it. This leg's only irreducible value is the Godot binary
(`godotBin`), resolved `$GODOT_BIN` → this file → `godot` on PATH → stop and ask. Prefer the
`_console` exe on Windows; the plain `.exe` detaches and prints nothing.

Note the bundled analyzer at `addons/reactive_ui_toolkit_analyzer/` is itself gitignored and
machine-installed — it is not a path fact, it is a local artifact.

## The portability acceptance test

The gate proves no tracked file names a one-machine path. This proves the tree actually *works*
somewhere else — including pending, uncommitted edits, which a `git clone` cannot see:

```bash
mkdir -p <scratch>/zzz-different-name
tar --exclude=node_modules --exclude=.godot --exclude=dist --exclude=out -cf - . \
  | tar -C <scratch>/zzz-different-name -xf -      # keep .git — the gate needs it
cd <scratch>/zzz-different-name
git add -N scripts/check-machine-paths.mjs .ruitk-local.example.json .vscode
node scripts/check-machine-paths.mjs               # must be green HERE
grep -c "C:" .vscode/launch.json .vscode/tasks.json   # must be 0
```

Deliberately name the copy something the repo has never been called.

## Scar tissue

- **`robocopy` failing silently produced a fake green.** When the copy failed, the following `cd`
  failed too, so the gate ran in the ORIGINAL folder and printed ✓. Always confirm `pwd` inside the
  copy before trusting its result. `tar | tar` (above) works in Git Bash; robocopy needed
  `cygpath -w` and still failed.
- **The gate scans itself.** Specimen paths in it are written `<drive>:` on purpose — a gate whose
  rules don't apply to the file defining the rules is a permanent blind spot. Don't "fix" them into
  literal drive letters, and don't add a self-exemption.
- **Escaped backslashes.** JS/TS/JSON spell a Windows separator `\\`. The root test compares against
  raw line text, so each allowed root is admitted twice (plain + doubled), derived in the engine
  section — not hand-typed.
- **Space-containing roots.** `C:\Program Files (x86)\…` — captured hits stop at the first space, so
  the allowed-root check tests the raw line from the match offset, not the captured hit.
- **`x:\n` is not a path.** Codegen emitting indented source (`"if x:\n\t\t…"`) looks drive-absolute.
  Filtered by rule: an escape letter followed by a non-word character.
- Stale claims rot: a comment in `.vscode/launch.json` once described a sibling repo's bug as
  present-tense after it was fixed, and the gate caught it under R2 because the comment quoted the
  path. Keep cross-repo statements out of configs.
