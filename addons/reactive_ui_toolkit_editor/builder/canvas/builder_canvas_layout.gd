@tool
class_name RuitkBuilderCanvasLayout
extends RefCounted
## Where each card sits, and where the camera is looking -- per tree, remembered between
## sessions.
##
## Positions are keyed RELATIVE to the tree root, so a tree that moves wholesale keeps its
## layout. The file lives under `user://`, which is outside the project: Godot never imports it,
## it survives deleting `.godot/`, and it is per-user rather than per-checkout, which is what a
## window layout should be.
##
## A LAYOUT IS ADOPTED, NEVER RECOMPUTED. The seeded layout is a breadth-first walk over the
## whole graph, so its answer depends on the card SET -- and a layout recomputed on every mount
## therefore moves every card the user never dragged the moment one module is added. That is not
## a layout, it is a reshuffle. A slot is decided once and then written down.
##
## A tree is identified by WHO IS IN IT, not by which member is currently its head. The root is
## derived -- from where the modules sit and which owns the top folder -- so a save that re-files
## a folder can resolve a different module as root; addressed by root alone, the tree then looks
## like one nobody has ever laid out, and the mount mints a fresh default column over the top of
## the real one.

const Paths = preload("res://addons/reactive_ui_toolkit_editor/builder/document/builder_paths.gd")
const Self = preload("res://addons/reactive_ui_toolkit_editor/builder/canvas/builder_canvas_layout.gd")
const Graph = preload("res://addons/reactive_ui_toolkit_editor/builder/canvas/builder_graph.gd")

const LAYOUT_DIR := "user://ruitk_builder/layouts"

var root_path := ""
var members := PackedStringArray()
var positions := {}
var camera := Vector2.ZERO
var zoom := 1.0

## Whether this layout came from a SAVED view -- a camera and zoom someone actually left the
## canvas at -- rather than from the defaults of a layout that has never been written.
##
## A flag rather than a sentinel zoom, because the default has to stay a usable 1.0 for every
## consumer that just reads it. Asking `zoom <= 0.0` instead, which is what the window did, is a
## question a fresh layout answers "no" to -- so the whole "no saved layout" path, the framing and
## then the Layer 2 default, was unreachable code and a new tree always opened cornered at 1:1.
var has_saved_view := false
var saved_at := ""

## Layout files this one has outgrown, because the tree root moved and the file is NAMED after
## the root. Removed on the next save, so a renamed tree does not leave a stale layout behind for
## the by-membership scan to keep finding.
var _retired := {}


static func file_for(root: String) -> String:
	var key := Paths.key(root).sha1_text().substr(0, 16)
	return LAYOUT_DIR.path_join(key + ".json")


## The layout stored under exactly this root, or null.
static func load_for_root(root: String) -> Self:
	return _read(file_for(root))


## The layout that already covers this SET of modules -- the one sharing the most members with
## the graph, newest breaking a tie so a stale file from an earlier shape cannot outrank the live
## one. null when nothing overlaps.
static func load_for_members(member_paths: PackedStringArray) -> Self:
	var wanted := {}
	for member in member_paths:
		var k := Paths.key(member)
		if not k.is_empty():
			wanted[k] = true
	if wanted.is_empty():
		return null

	var best: Self = null
	var best_overlap := 0
	var best_saved := ""
	var d := DirAccess.open(LAYOUT_DIR)
	if d == null:
		return null
	for file in d.get_files():
		if not file.ends_with(".json"):
			continue
		var candidate := _read(LAYOUT_DIR.path_join(file))
		if candidate == null:
			continue
		var overlap := 0
		for member in candidate.members:
			if wanted.has(Paths.key(member)):
				overlap += 1
		if overlap == 0:
			continue
		if overlap > best_overlap or (overlap == best_overlap and candidate.saved_at > best_saved):
			best = candidate
			best_overlap = overlap
			best_saved = candidate.saved_at
	return best


## The layout for a graph: the one that covers its membership if there is one, else the one filed
## under its root, else a fresh one. In that order, because membership is the stable identity.
static func for_graph(graph: Graph) -> Self:
	var member_paths := PackedStringArray()
	for card in graph.cards:
		member_paths.append(card.file_path)
	var found := load_for_members(member_paths)
	if found == null:
		found = load_for_root(graph.root_path)
	if found == null:
		found = Self.new()
	found.root_path = graph.root_path
	return found


func save(timestamp: String) -> bool:
	DirAccess.make_dir_recursive_absolute(LAYOUT_DIR)
	saved_at = timestamp
	var target := file_for(root_path)
	var f := FileAccess.open(target, FileAccess.WRITE)
	if f == null:
		push_warning("[builder] could not write the canvas layout: %s"
			% error_string(FileAccess.get_open_error()))
		return false
	f.store_string(JSON.stringify(to_dict(), "\t"))
	f.close()
	for stale in _retired.keys():
		if str(stale) != target and FileAccess.file_exists(str(stale)):
			DirAccess.remove_absolute(str(stale))
	_retired.clear()
	return true


## Moves every card the layout knows about to its remembered slot, and records the membership.
func apply_to(graph: Graph) -> void:
	members = PackedStringArray()
	for card in graph.cards:
		members.append(card.file_path)
		var stored: Variant = positions.get(_rel_key(card.file_path))
		if stored is Array and (stored as Array).size() == 2:
			card.x = float((stored as Array)[0])
			card.y = float((stored as Array)[1])


## Writes down the slot of every card that does not have one yet, and reports whether any were
## new -- so the caller knows whether the layout needs saving.
func adopt_unplaced(graph: Graph) -> bool:
	var added := false
	for card in graph.cards:
		var key := _rel_key(card.file_path)
		if positions.has(key):
			continue
		positions[key] = [card.x, card.y]
		added = true
	return added


## Records where everything is right now: every card's slot, and the camera.
func capture_from(graph: Graph, camera_at: Vector2, zoom_at: float) -> void:
	camera = camera_at
	zoom = zoom_at
	has_saved_view = true
	members = PackedStringArray()
	for card in graph.cards:
		members.append(card.file_path)
		positions[_rel_key(card.file_path)] = [card.x, card.y]


## Places one card, for a card created at the point the user right-clicked rather than at the
## next default slot.
func set_position(file_path: String, at: Vector2) -> void:
	positions[_rel_key(file_path)] = [at.x, at.y]


## Follows a module, or a whole folder, to a new location so a rename does not throw the layout
## away.
##
## Positions are keyed relative to the root and the FILE is named after the root, so a rename can
## move the keys and the file name at once -- which is why renaming a folder-owning component
## loses the whole layout otherwise: every member path changes, so neither the by-root lookup nor
## the by-membership scan can find it again. Each key is resolved back to an absolute path, moved,
## and re-keyed against the new root.
func repath(old_path: String, new_path: String, is_folder: bool) -> void:
	var from := Paths.canon(old_path)
	var to := Paths.canon(new_path)
	if from.is_empty() or to.is_empty() or Paths.same(from, to):
		return

	# Resolved against the OLD root, before it moves out from under them.
	var carried: Array = []
	for key in positions:
		carried.append([_moved(_absolute_of(str(key)), from, to, is_folder), positions[key]])

	var previous_root := Paths.canon(root_path)
	var moved_root := _moved(previous_root, from, to, is_folder)
	if not moved_root.is_empty() and not Paths.same(moved_root, previous_root):
		_retired[file_for(root_path)] = true
		root_path = moved_root

	positions = {}
	for entry in carried:
		var abs := str((entry as Array)[0])
		if not abs.is_empty():
			positions[_rel_key(abs)] = (entry as Array)[1]

	var moved_members := PackedStringArray()
	for member in members:
		var moved := _moved(Paths.canon(member), from, to, is_folder)
		moved_members.append(member if moved.is_empty() else moved)
	members = moved_members


static func _moved(path: String, from: String, to: String, is_folder: bool) -> String:
	if path.is_empty():
		return path
	if not is_folder:
		return to if Paths.same(path, from) else path
	if not Paths.is_under(path, from) or Paths.same(path, from):
		return path
	return Paths.canon(to.path_join(path.substr(Paths.canon(from).length() + 1)))


## A stored key back to the absolute path it names. Keys are root-relative for members of the
## tree and absolute for anything else, which is exactly what `_rel_key` produces.
func _absolute_of(key: String) -> String:
	if key.begins_with("res://") or key.begins_with("user://"):
		return Paths.canon(key)
	var root_dir := Paths.canon(root_path).get_base_dir()
	return Paths.canon(root_dir.path_join(key))


func _rel_key(file_path: String) -> String:
	var root_dir := Paths.canon(root_path).get_base_dir()
	var full := Paths.canon(file_path)
	if not root_dir.is_empty() and Paths.is_under(full, root_dir):
		return full.substr(root_dir.length() + 1).to_lower()
	return full.to_lower()


# ── Serialization ────────────────────────────────────────────────────────────────────

func to_dict() -> Dictionary:
	return {
		"root_path": root_path,
		"members": Array(members),
		"positions": positions,
		"camera": [camera.x, camera.y],
		"zoom": zoom,
		"saved_at": saved_at,
	}


static func from_dict(d: Dictionary) -> Self:
	var layout := Self.new()
	layout.root_path = str(d.get("root_path", ""))
	for member in (d.get("members", []) as Array):
		layout.members.append(str(member))
	var stored: Variant = d.get("positions", {})
	if stored is Dictionary:
		for key in (stored as Dictionary):
			var value: Variant = (stored as Dictionary)[key]
			if value is Array and (value as Array).size() == 2:
				layout.positions[str(key)] = [float((value as Array)[0]), float((value as Array)[1])]
	var cam: Variant = d.get("camera", [0.0, 0.0])
	if cam is Array and (cam as Array).size() == 2:
		layout.camera = Vector2(float((cam as Array)[0]), float((cam as Array)[1]))
	layout.zoom = float(d.get("zoom", 1.0))
	layout.saved_at = str(d.get("saved_at", ""))
	return layout


static func _read(path: String) -> Self:
	if not FileAccess.file_exists(path):
		return null
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		push_warning("[builder] canvas layout at %s is not readable -- ignoring it" % path)
		return null
	var stored := from_dict(parsed)
	if stored != null:
		stored.has_saved_view = true
	return stored


## Removes every stored layout. For tests, and for a "forget my layouts" action.
static func clear_all() -> void:
	var d := DirAccess.open(LAYOUT_DIR)
	if d == null:
		return
	for file in d.get_files():
		DirAccess.remove_absolute(LAYOUT_DIR.path_join(file))
