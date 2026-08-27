export const EXAMPLE_MODULE_KINDS = `MyScreen.guitkx          # component  — markup + a render function
MyScreen.hooks.guitkx    # hook      — use_* functions, reusable state logic
MyScreen.style.guitkx    # style     — exported look: dicts, and functions that build them
MyScreen.utils.guitkx    # util      — pure helpers
shared_config.guitkx     # value     — exported constants only`

export const EXAMPLE_LEDGER = `# Every gesture lands as a text edit on a buffer, and the ledger stores both sides.
# Undo replays the "before" of every change in one entry — a drop that also added an
# import is ONE action, not two, so undoing it never leaves a half-authored file.

  entry  "Insert <Label> inside <VBoxContainer>"
    change  EDIT    MyScreen.guitkx        before -> after
    change  EDIT    MyScreen.style.guitkx  before -> after`

export const EXAMPLE_SAVE = `# Nothing touches disk until Save. Then, in one pass:
#   1. every dirty buffer is formatted (if format-on-save is on) and written
#   2. planned renames move the .guitkx AND its companions:
#        MyScreen.guitkx  MyScreen.guitkx.uid  MyScreen.guitkx.diags.json
#        MyScreen.gd      MyScreen.gd.uid
#   3. importers of a moved module have their specifiers rewritten
#   4. deletions go to the OS trash, never straight to unlink
#
# Abort discards every buffer and returns the tree to what is on disk.`
