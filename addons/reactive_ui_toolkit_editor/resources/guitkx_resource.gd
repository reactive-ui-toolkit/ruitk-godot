@tool
class_name GuitkxResource
extends Resource
## A text-backed Resource wrapping a single .guitkx source file (the Dialogic timeline.gd pattern).
##
## Its only job is to carry the raw source text so a double-clicked .guitkx in the FileSystem dock
## routes through the editor plugin's `_handles(object is GuitkxResource)` / `_edit` into the
## main-screen editor. The on-disk file stays plain .guitkx text — this Resource is never itself
## serialized to disk (the editor saves the .guitkx via FileAccess and lets the reactive_ui_toolkit watcher
## regenerate the sibling .gd).

# @export_storage: serialization-safe without appearing in the Inspector. Nothing in the normal
# flow ever ResourceSaver-saves this, but if user code sticks one in an @export slot or a .tres,
# the text must round-trip rather than silently vanish (parity plan L7).
@export_storage var source: String = ""

func from_text(text: String) -> void:
	source = text

func as_text() -> String:
	return source
