---
name: field-test-editor
description: Run the local field-test loop for the Godot native editor (reactive_ui_toolkit + reactive_ui_toolkit_editor + bundled analyzer) — the AI prepares, fixes, verifies, and applies; the user tests in a real Godot editor; repeat until the bug is dead.
---

# Field-test loop for the native Godot editor

You (the AI) do everything except the actual in-editor testing. The human tests, reports, and
decides "fixed" or "persists". Loop until fixed. Production-grade fixes only — root cause, never a
bandaid.

## Environment facts (verify, don't assume, if anything fails)

- **Live tree** (where the user tests): `C:\Yanivs\GameDev\ReactiveUI\ReactiveUI-Gadot`. NEVER
  edit it while the user's Godot is open without telling them; NEVER kill their Godot process.
- **Work tree** (where you develop): `C:\Yanivs\GameDev\ReactiveUI\RG-work` (a worktree of the
  same repo). All branches/commits happen here. Base branches on `origin/dev`.
- **Godot binary** (not on PATH): `C:\Yanivs\daniela test\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe`
  — use the `_console` exe, and ALWAYS redirect output to a file (`cmd /c "...godot... > out.txt 2>&1"`);
  piping through `head`/`Select-Object` block-buffers and hides everything.
- The analyzer GDExtension lives at `addons/reactive_ui_toolkit_analyzer/` (gitignored; local dll install).
  A fresh/changed `.gdextension` is only seen by headless scripts AFTER one
  `--headless --editor --quit` scan (it must enter `.godot/extension_list.cfg`). Moving the folder
  to disable it must move it OUTSIDE the project (a rename inside res:// still gets discovered).

## The loop

1. **Reproduce & fix** (in RG-work, on a feature branch off `origin/dev`):
   research the root cause first; write/extend a test that catches it when possible
   (`tests/guitkx_editor_test.gd` sections print per-section markers — keep that so hangs name
   their culprit).
2. **Verify before handing over** — all of:
   ```
   godot --headless --path . --script res://tests/guitkx_build.gd
   godot --headless --path . --editor --quit          (boot check — plugins actually load)
   godot --headless --path . --script res://tests/guitkx_lsp_test.gd
   godot --headless --path . --script res://tests/guitkx_editor_test.gd   (382 with analyzer / 364 without)
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
