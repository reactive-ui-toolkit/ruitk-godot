# Branch rulesets — the canonical family pair

`protect-dev.json` + `protect-master.json` are the versioned family standard, identical across the
Reactive UI Toolkit repos (Godot / Unity / Unreal legs). They are not applied automatically: import
each one via **Settings > Rules > Rulesets > New ruleset > Import a ruleset** on GitHub, and re-import
after any change here so the repo settings and this folder never drift.

What they enforce:

- **Protect dev** — no deletion, no force-push, changes land by PR (merge commits only, 0 required
  approvals), and the PR must pass the four required status checks: `gates`, `tests`, `extensions`,
  `docs`.
- **Protect master** — no deletion, no force-push. No PR/check requirements: master only ever
  advances by fast-forward from dev after dev's checks already passed.

The four required check names are **load-bearing**: they must match the four job `name:` fields in
`.github/workflows/test.yml` exactly (the family CI contract — every leg exposes exactly these four
contexts). Renaming a job or a context on one side without the other either orphans the protection
(check never reports, PRs blocked forever) or stops protecting anything.
