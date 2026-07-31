---
name: field-test-editor
description: Run the local field-test loop for the Godot native editor (reactive_ui_toolkit + reactive_ui_toolkit_editor + bundled analyzer) — the AI prepares, fixes, verifies, and applies; the user tests in a real Godot editor; repeat until the bug is dead.
---

# Field-test loop for the native Godot editor

You (the AI) do everything except the actual in-editor testing. The human tests, reports, and
decides "fixed" or "persists". Loop until fixed. Production-grade fixes only — root cause, never a
bandaid.

## Environment facts (verify, don't assume, if anything fails)

- **Live tree** `<live>` (where the user tests): **the repo checkout you are in** — the user's Godot
  editor has this folder open. NEVER edit it while their Godot is open without telling them; NEVER
  kill their Godot process.
- **Work tree** `<work>` (where you develop): a second worktree of this same repo. Get it from
  `git worktree list` — it is the entry whose path is not `<live>`. If there is none, create one as a
  sibling of the checkout: `git worktree add ../<checkout-name>-work -b <branch> origin/dev`. All
  branches/commits happen in `<work>`, and branches are based on `origin/dev`.
- **Godot binary** `<godot>` — resolve in this order, first hit wins, and re-resolve rather than
  remembering a path across sessions:
  1. `$GODOT_BIN`;
  2. `godotBin` in `.ruitk-local.json` at the repo root (gitignored — copy it from
     `.ruitk-local.example.json`);
  3. `godot` on PATH.
  If all three miss, STOP and ask the user to set one — do **not** guess an install location. Prefer
  the `_console` exe on Windows (the plain `.exe` detaches and prints nothing), and ALWAYS redirect
  output to a file (`cmd /c "<godot> ... > out.txt 2>&1"`); piping through `head`/`Select-Object`
  block-buffers and hides everything.
- The analyzer GDExtension lives at `addons/reactive_ui_toolkit_analyzer/` (gitignored; local dll install).
  A fresh/changed `.gdextension` is only seen by headless scripts AFTER one
  `--headless --editor --quit` scan (it must enter `.godot/extension_list.cfg`). Moving the folder
  to disable it must move it OUTSIDE the project (a rename inside res:// still gets discovered).

## The loop

1. **Reproduce & fix** (in `<work>`, on a feature branch off `origin/dev`):
   research the root cause first; write/extend a test that catches it when possible
   (`tests/guitkx_editor_test.gd` sections print per-section markers — keep that so hangs name
   their culprit).
2. **Verify before handing over** — all of:
   ```
   <godot> --headless --path . --script res://tests/guitkx_build.gd
   <godot> --headless --path . --editor --quit        (boot check — plugins actually load)
   <godot> --headless --path . --script res://tests/guitkx_lsp_test.gd
   <godot> --headless --path . --script res://tests/guitkx_editor_test.gd  (382 with analyzer / 364 without)
   ```
   Suites do NOT run `_enter_tree` — the boot check is not optional.
3. **Commit** on the feature branch (the loop is a standing ask to commit; author is the user —
   no Co-Authored-By).
4. **Apply locally** so the user can test: if the live tree is clean, `git -C <live> fetch origin
   && git -C <live> checkout <branch>` (ask before switching their checkout); otherwise copy the
   changed `addons/reactive_ui_toolkit/**` / `addons/reactive_ui_toolkit_editor/**` files over. Then tell the user
   to **restart their Godot editor** (plugin scripts don't hot-swap reliably).
5. **User tests.** Ask for: what they did, what they saw, the Output panel text (they often paste
   it into a scratch file like `<live>\errors` — read it).
6. **Fixed?** Merge flow: PR feature→dev (user clicks), then `git push origin origin/dev:master`
   fast-forward. Changelog + version bump per the dev-process skill BEFORE the PR.
   **Persists?** Go to 1 with the new evidence. Never re-try the same theory twice — get more
   instrumentation instead (temporary print probes are fine; remove before commit).

## Store-zip fidelity test (when the change affects packaging)

Test what a store user gets: download `reactive_ui_toolkit-<ver>.zip` + `reactive_ui_toolkit_editor-<ver>.zip`
from GitHub releases into a FRESH Godot project (create it, close the editor, unzip so
`addons/reactive_ui_toolkit`, `addons/reactive_ui_toolkit_editor`, `addons/reactive_ui_toolkit_analyzer` all exist,
reopen). Enable `reactive_ui_toolkit` then `reactive_ui_toolkit_editor` in Project Settings → Plugins. Expect the
green Output banner `native analyzer <ver> detected`; a yellow note means the bundle is broken.
