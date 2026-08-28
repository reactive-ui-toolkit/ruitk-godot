@tool
class_name RuitkBuilderDrag
extends RefCounted
## One drag gesture, from press to release.
##
## THE GESTURE OWNS ITS OWN STATE, and resolves the drop from the POINTER STREAM -- never from
## whatever the canvas happens to be showing when the button comes up. That is the whole design.
##
## The canvas is rendered by the reconciler, so a card is re-created whenever its module changes
## -- and a module changes DURING a drag, because the preview recompiles as the user works. A
## drop resolved from the row objects captured at press time would be resolving against rows that
## no longer exist; resolved from the live node tree, it would be resolving against a tree that
## has moved. The Unity leg's drag defect cluster is entirely this shape, and every fix there is
## another rule about which of the two stale answers to prefer.
##
## Here the gesture carries what it needs -- what is being dragged, and what it was over last --
## and re-resolves the target by POSITION against the current graph at the moment of the drop. A
## re-render between press and release changes nothing it depends on.

const Graph = preload("res://addons/reactive_ui_toolkit_editor/builder/canvas/builder_graph.gd")
const Metrics = preload("res://addons/reactive_ui_toolkit_editor/builder/canvas/builder_canvas_metrics.gd")
const Edits = preload("res://addons/reactive_ui_toolkit_editor/builder/edits/builder_edits.gd")

## What is being dragged.
enum Source {
	NONE,
	## A palette entry: an element tag, a hook, or a component from the tree.
	LIBRARY,
	## A markup row already on a card -- a re-parent.
	ROW,
	## A whole module, from the folder pane or another card. Dropped on an element it applies a
	## style; dropped on a card it adds an import.
	MODULE,
}

var source: Source = Source.NONE

## What is being dragged, in the source's own terms: a tag name, a module path, or the offset of
## the row being moved.
var payload := ""

## The card the drag STARTED on, by module id -- stable across a re-projection, which the path is
## not once a rename lands mid-gesture.
var from_card_id := ""

## The offset of the row being moved, for a ROW drag. An offset, not a row object: the object is
## from a projection that may already be gone.
var from_row_at := -1

## The row's INDEX in its card's markup at press time -- the fallback when a text change under
## the gesture has shifted every offset.
var from_row_index := -1

var started := false
var pressed_at := Vector2.ZERO

## How far the pointer must travel before a press becomes a drag. Below it the gesture is a
## click, and treating every click as a one-pixel drag makes selection impossible.
const DRAG_THRESHOLD := 4.0


func begin(kind: Source, what: String, card_id: String, row_at: int, row_index: int,
		at: Vector2) -> void:
	source = kind
	payload = what
	from_card_id = card_id
	from_row_at = row_at
	from_row_index = row_index
	pressed_at = at
	started = false


## Whether the pointer has moved far enough to be a drag rather than a click.
func consider(at: Vector2) -> bool:
	if source == Source.NONE:
		return false
	if not started and pressed_at.distance_to(at) >= DRAG_THRESHOLD:
		started = true
	return started


func is_active() -> bool:
	return source != Source.NONE and started


func cancel() -> void:
	source = Source.NONE
	payload = ""
	from_card_id = ""
	from_row_at = -1
	from_row_index = -1
	started = false


## Where a pointer position lands, resolved against the graph AS IT IS NOW:
## { card, card_index, row, section, band, placement, found }.
##
## Everything is looked up by POSITION at call time. Nothing captured at press time is used to
## find the target, so a re-render between press and release cannot make this answer stale.
static func resolve(graph: Graph, screen: Vector2, camera: Vector2,
		zoom: float) -> Dictionary:
	var miss := { "found": false, "card": null, "card_index": -1, "row": null,
		"section": Metrics.Section.MARKUP, "band": 1, "placement": Edits.Placement.INSIDE }
	if graph == null:
		return miss
	var world := Metrics.screen_to_world(screen, camera, zoom)
	var lod := Metrics.lod_of(zoom)
	var width := Metrics.card_width_for(lod)
	for i in range(graph.cards.size() - 1, -1, -1):
		var card := graph.cards[i]
		# THE DRAWN height, which is what the user is aiming at. `card_height` is the full-card
		# estimate the layout is keyed on, and at any layer that draws less than everything it
		# describes a rectangle taller than the card on screen -- so a drop into the empty space
		# below a card resolved onto it.
		var rect := Rect2(card.x, card.y, width, Metrics.drawn_height(card, lod))
		if not rect.has_point(world):
			continue
		var hit := Metrics.row_hit(card, world - rect.position, lod)
		var row: Graph.Line = null
		if bool(hit["found"]):
			row = _row_of(card, int(hit["section"]), int(hit["index"]))
		return {
			"found": true,
			"card": card,
			"card_index": i,
			"row": row,
			"section": hit["section"],
			"band": hit["band"],
			"placement": _placement_of(int(hit["band"]), card, int(hit["section"]),
				int(hit["index"])),
		}
	return miss


## THE CARET IS A POSITION IN THE LISTED TREE, and the edit lands there.
##
##   top band     -> before this row, as a sibling
##   middle band  -> inside it, as its last child
##   bottom band  -> if the NEXT LISTED ROW IS DEEPER, become that row's first child; the gap
##                   under a row is visually the gap before its first child, and the listing is
##                   flattened, so those are the same place on screen. Otherwise it means after
##                   this row's whole block, which is also the same place on screen.
static func _placement_of(band: int, card: Graph.Card = null, section := -1,
		index := -1) -> Edits.Placement:
	match band:
		0:
			return Edits.Placement.BEFORE
		2:
			if _next_listed_is_deeper(card, section, index):
				return Edits.Placement.FIRST_CHILD
			return Edits.Placement.AFTER
		_:
			return Edits.Placement.INSIDE


## Whether the row listed after `index` is nested inside it.
static func _next_listed_is_deeper(card: Graph.Card, section: int, index: int) -> bool:
	if card == null or section != int(Metrics.Section.MARKUP):
		return false
	if index < 0 or index + 1 >= card.markup.size():
		return false
	return card.markup[index + 1].depth > card.markup[index].depth


static func _row_of(card: Graph.Card, section: int, index: int) -> Graph.Line:
	var rows: Array[Graph.Line] = []
	match section:
		Metrics.Section.IMPORTS:
			rows = card.imports
		Metrics.Section.BODY:
			rows = card.body
		Metrics.Section.MARKUP:
			rows = card.markup
		Metrics.Section.EXPORTS:
			rows = card.export_detail
		_:
			return null
	return rows[index] if index >= 0 and index < rows.size() else null


## The row a ROW drag started on, found in the CURRENT graph.
##
## By OFFSET first, then by INDEX. Neither alone is enough, and holding the row object is worse
## than both: the projection it came from is very likely gone by the time the drop lands.
##
##   - The offset is exact while the text has not moved, which is the usual case -- a re-render
##     mid-drag comes from the preview recompiling, and that changes no text.
##   - The index survives a text change that shifted every offset, which is what an edit from
##     somewhere else does.
##   - When neither finds it, the gesture is genuinely stale and the drop is REFUSED. Refusing is
##     the safe answer; guessing at the nearest row moves something the user did not point at.
func source_row(graph: Graph) -> Graph.Line:
	var card := source_card(graph)
	if card == null:
		return null
	if from_row_at >= 0:
		for row in card.markup:
			if row.at == from_row_at:
				return row
	if from_row_index >= 0 and from_row_index < card.markup.size():
		return card.markup[from_row_index]
	return null


func source_card(graph: Graph) -> Graph.Card:
	if graph == null:
		return null
	var index := graph.index_of_id(from_card_id)
	return graph.cards[index] if index >= 0 else null


## The markup a LIBRARY drag inserts. An element and a component are spelled the same way -- a
## tag is a tag -- so one template covers both.
static func markup_for(tag: String) -> String:
	# SEEDED, not bare. Ported from the Unity leg's `SeededTag`: a `<Label />` with no text is an
	# invisible element, so dropping one produces a card row and nothing on screen, and the user
	# has to guess whether the drop worked. A tag whose whole point is its text starts with some.
	match tag:
		"Label":
			return "<Label text=\"New label\" />"
		"Button":
			return "<Button text=\"Click\" />"
		"LineEdit":
			return "<LineEdit placeholder_text=\"...\" />"
		"CheckBox":
			return "<CheckBox text=\"Option\" />"
	return "<%s />" % tag
