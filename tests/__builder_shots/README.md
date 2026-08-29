# Builder screenshot fixture

The module tree the visual gauntlet shoots, mirrored 1:1 from the Unity leg's own screenshots
(`Images/reference/`) so a comparison is about LAYOUT and not about content: same folder shape,
same file names, same import graph, same markup nesting. `VisualElement` becomes `Control` and
`Slider` becomes `HSlider` — the engine differs, the structure does not.

`.gdignore` keeps the whole folder out of the compiler's `find_all` sweep, so these files never
compile into the project, never register a `class_name`, and never move the build counts. The
builder reads them with plain `DirAccess`, which ignores the marker, so it opens the tree
normally.

Regenerate the shots with:  node scripts/builder-shots.mjs
