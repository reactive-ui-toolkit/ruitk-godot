@tool
class_name RuitkBuilderContextMenu
extends EditorContextMenuPlugin
## "Open in RUITK Builder" on a `.guitkx` in the FileSystem dock.
##
## The Godot analogue of the Unity leg's `Assets/Open in RUITK UI Builder` context item, and the
## answer to the question the start screen asks: it tells the user to open an existing tree from
## the FileSystem dock, and until now there was no way to do that from anywhere. The builder could
## only be opened on whatever the `.guitkx` editor happened to have, which on a fresh project is
## nothing — so an existing tree was unreachable by every route the UI mentions.
##
## Offered ONLY for `.guitkx`: an item that appears on every asset and does nothing for most of
## them is noise in a menu people use constantly.

## Emitted with the file the user chose. The plugin opens the builder on it; this class knows
## nothing about windows.
signal open_requested(file_path: String)

const Paths = preload("res://addons/reactive_ui_toolkit_editor/builder/document/builder_paths.gd")

const ITEM := "Open in RUITK Builder"


func _popup_menu(paths: PackedStringArray) -> void:
	for path in paths:
		if Paths.ends_with_ci(str(path), Paths.SUFFIX_PLAIN):
			add_context_menu_item(ITEM, _on_chosen)
			return


func _on_chosen(paths: Variant) -> void:
	# The callback is handed whatever the dock had selected; the first `.guitkx` in it is the one
	# the item was offered for.
	if paths is PackedStringArray or paths is Array:
		for path in paths:
			if Paths.ends_with_ci(str(path), Paths.SUFFIX_PLAIN):
				open_requested.emit(str(path))
				return
	elif paths is String and Paths.ends_with_ci(str(paths), Paths.SUFFIX_PLAIN):
		open_requested.emit(str(paths))
