@tool
class_name RuitkBuilderCanvasMetrics
extends RefCounted
## Every number the canvas measures with, in ONE place: the LOD bands, the card widths, the row
## heights, the height estimate the cull and the edge painter both need, and the camera
## transform.
##
## ONE `lod_of`. The Unity leg has two -- the view decides the bands at 0.45 / 1.05 and the host
## decides them at 0.32 / 0.80 -- so between those thresholds the card the view drew and the card
## the camera measured were different widths. A canvas cannot have two answers to "how wide is a
## card right now"; every consumer here asks this file.
##
## Pure: no nodes, no drawing, no state. That is what makes the cull, the layout and the camera
## provable without an editor.

const Graph = preload("res://addons/reactive_ui_toolkit_editor/builder/canvas/builder_graph.gd")
const Module = preload("res://addons/reactive_ui_toolkit_editor/builder/document/builder_module.gd")


## Zoom bounds. A view property only -- nothing about the graph, the layout or the model depends
## on the zoom, so these can move without touching anything else.
const ZOOM_MIN := 0.10
const ZOOM_MAX := 2.2

## Level of detail. L0 is a pill -- title and kind, nothing else; L1 adds the signature, imports
## and hook chips; L2 adds the markup tree with its attributes and the code island.
enum Lod { PILL, SECTIONS, FULL }

## The band edges. Below the first, a card is a pill; below the second, it shows its sections;
## above, everything.
##
## The FULL band starts below 1:1 on purpose. It used to start above it, which made 100% zoom --
## where a user actually works, and where the layer selector says "Edit" -- the band that shows
## everything EXCEPT the markup. The card was at its largest and carrying the least, and reaching
## the markup meant zooming past the point where a second card fits on screen.
const LOD_PILL_BELOW := 0.45
const LOD_SECTIONS_BELOW := 0.75

## Card width per LOD. A pill is narrower because it holds a title; the full card is wider
## because it is the only one that rides the attribute run on a markup row.
const CARD_WIDTH_PILL := 300.0
const CARD_WIDTH_SECTIONS := 340.0
const CARD_WIDTH_FULL := 430.0

## The gutter between columns of the seeded layout, and between a card and the next row.
const CARD_GUTTER := 48.0

# Row and section metrics, in card-local units.
const HEADER_H := 38.0
const PILL_H := 72.7
const SIGNATURE_LEAD_H := 15.0
const SIGNATURE_LINE_H := 17.4
const SECTION_OVERHEAD_H := 34.5
const IMPORT_ROW_H := 19.7
const MARKUP_ROW_H := 22.4
const CHIP_ROW_H := 34.7
const ISLAND_ROW_H := 17.4
const CARD_PADDING := 24.0
const CHIP_PADDING := 30.0

## Advance width of the monospace face the card rows use, at their own size. Every code-bearing
## surface on a card is monospace, so a character count is a reliable width.
const MONO_ADVANCE := 7.2
const CHIP_MONO_ADVANCE := 6.9

## Where an edge meets a card: down from the card's top edge, in card-local units.
const EDGE_ANCHOR_Y := 18.0

## The vertical pitch between anchor dots down the card's left column.
const ANCHOR_PITCH := IMPORT_ROW_H


## The LOD a zoom is in. THE definition -- see the class note.
static func lod_of(zoom: float) -> Lod:
	if zoom < LOD_PILL_BELOW:
		return Lod.PILL
	return Lod.SECTIONS if zoom < LOD_SECTIONS_BELOW else Lod.FULL


static func card_width_for(lod: Lod) -> float:
	match lod:
		Lod.PILL:
			return CARD_WIDTH_PILL
		Lod.SECTIONS:
			return CARD_WIDTH_SECTIONS
		_:
			return CARD_WIDTH_FULL


static func clamp_zoom(zoom: float) -> float:
	return clampf(zoom, ZOOM_MIN, ZOOM_MAX)


## Whether a card shows its section stack at this LOD.
static func shows_sections(lod: Lod) -> bool:
	return lod != Lod.PILL


## Whether a card shows its markup tree and code island at this LOD.
## Whether the markup rows carry their attribute runs.
##
## A LEVEL BEYOND `shows_detail`. Showing every attribute the moment the markup appears makes the
## edit layer and the zoomed layer carry identical information, and sets the card's width from its
## longest attribute run -- which is what pushed the tree wider than the canvas.
static func shows_attributes(zoom: float) -> bool:
	return zoom >= ATTRIBUTE_ZOOM


## The zoom at which a markup row starts carrying its attributes.
const ATTRIBUTE_ZOOM := 1.2


static func shows_detail(lod: Lod) -> bool:
	return lod == Lod.FULL


# ── Camera ───────────────────────────────────────────────────────────────────────────

## World point -> screen point, under a camera offset and zoom.
static func world_to_screen(world: Vector2, camera: Vector2, zoom: float) -> Vector2:
	return world * zoom + camera


## Screen point -> world point. The inverse, and it has to BE the inverse: a right-click that
## creates a card places it at the world coordinates of the click, and a disagreement here puts
## the new card somewhere the user did not point.
static func screen_to_world(screen: Vector2, camera: Vector2, zoom: float) -> Vector2:
	if zoom <= 0.0:
		return screen
	return (screen - camera) / zoom


## The camera that keeps `anchor` (a SCREEN point) over the same world point while the zoom
## changes -- what a scroll-wheel zoom has to do, or the canvas slides out from under the cursor.
static func zoom_about(camera: Vector2, from_zoom: float, to_zoom: float, anchor: Vector2) -> Vector2:
	var world := screen_to_world(anchor, camera, from_zoom)
	return anchor - world * to_zoom


# ── Card height ──────────────────────────────────────────────────────────────────────

## The card's height at the TALLEST layout, so the gutter survives every zoom.
##
## Measured once and memoised on the card: the cull consults it for every card on every render,
## and the inputs only change when the card is re-projected -- which resets it.
static func card_height(card: Graph.Card) -> float:
	if card == null:
		return PILL_H
	if card.cached_height <= 0.0:
		card.cached_height = estimate_card_height(card)
	return card.cached_height


## Which section of a card a row belongs to. What a hit-test answers with, and what a drop
## handler dispatches on -- a row in MARKUP takes an element, a row in IMPORTS does not.
enum Section { SIGNATURE, IMPORTS, BODY, MARKUP, EXPORTS, ISLAND }


## The card's sections, top to bottom, as [{ section, top, height, rows, row_height }] in
## card-local units.
##
## ONE description, read by BOTH the height estimate and the hit-test. Written twice they drift,
## and the symptom is a drop that lands on the row above the one under the cursor -- which reads
## as the drag being imprecise rather than as two functions disagreeing.
##
## Measured at the SECTIONS layout whatever the LOD, because that is what the saved layout is
## keyed on: a card that changed height with the zoom would reflow the whole canvas on a scroll.
static func section_stack(card: Graph.Card) -> Array:
	var out: Array = []
	if card == null:
		return out
	var inner := CARD_WIDTH_SECTIONS - CARD_PADDING
	# A component or a hook has a body section even when it is empty -- the card offers to add
	# the first hook there, and an affordance the card declines to show cannot be clicked.
	var has_body := card.kind == Module.Kind.COMPONENT or card.kind == Module.Kind.HOOK
	var top := HEADER_H

	if not card.signature.is_empty():
		var lines := wrap_lines(card.signature.length(), inner, MONO_ADVANCE)
		out.append(_section_row(Section.SIGNATURE, top, SIGNATURE_LEAD_H, lines, SIGNATURE_LINE_H))
		top += SIGNATURE_LEAD_H + lines * SIGNATURE_LINE_H
	if not card.imports.is_empty():
		out.append(_section_row(Section.IMPORTS, top, SECTION_OVERHEAD_H,
			card.imports.size(), IMPORT_ROW_H))
		top += SECTION_OVERHEAD_H + card.imports.size() * IMPORT_ROW_H
	if not card.body.is_empty() or has_body:
		var chips := _chip_rows(card, inner, has_body)
		out.append(_section_row(Section.BODY, top, SECTION_OVERHEAD_H, chips, CHIP_ROW_H))
		top += SECTION_OVERHEAD_H + chips * CHIP_ROW_H
	if not card.markup.is_empty():
		out.append(_section_row(Section.MARKUP, top, SECTION_OVERHEAD_H,
			card.markup.size(), MARKUP_ROW_H))
		top += SECTION_OVERHEAD_H + card.markup.size() * MARKUP_ROW_H
	if not card.export_detail.is_empty():
		out.append(_section_row(Section.EXPORTS, top, SECTION_OVERHEAD_H,
			card.export_detail.size(), MARKUP_ROW_H))
		top += SECTION_OVERHEAD_H + card.export_detail.size() * MARKUP_ROW_H
	if not card.island_lines.is_empty():
		out.append(_section_row(Section.ISLAND, top, SECTION_OVERHEAD_H,
			card.island_lines.size(), ISLAND_ROW_H))
	return out


static func _section_row(section: Section, top: float, lead: float, rows: int,
		row_height: float) -> Dictionary:
	return {
		"section": section,
		"top": top,
		"lead": lead,
		"rows": rows,
		"row_height": row_height,
		"height": lead + rows * row_height,
	}


static func estimate_card_height(card: Graph.Card) -> float:
	if card == null:
		return PILL_H
	var height := HEADER_H
	for entry in section_stack(card):
		height += float((entry as Dictionary)["height"])
	return height


## How many rows the chip run wraps to. Chips flow, so the count is a function of their widths,
## not of how many there are; the trailing entry is the "+ hook" affordance a body always offers.
static func _chip_rows(card: Graph.Card, inner: float, has_body: bool) -> int:
	var chip_max := CARD_WIDTH_SECTIONS - CHIP_PADDING
	var used := 0.0
	var rows := 1
	for i in range(card.body.size() + 1):
		var w := 0.0
		if i == card.body.size():
			w = 71.0 if has_body else 0.0
		else:
			w = minf(chip_max, 25.0 + card.body[i].text.length() * CHIP_MONO_ADVANCE)
		if w <= 0.0:
			continue
		if used > 0.0 and used + w > inner:
			rows += 1
			used = w
		else:
			used += w
	return rows


## How many lines a run of `chars` monospace characters wraps to in `available` width.
static func wrap_lines(chars: int, available: float, advance: float) -> int:
	if chars <= 0:
		return 1
	var per_line: int = maxi(1, int(available / advance))
	return (chars + per_line - 1) / per_line


# ── Culling ──────────────────────────────────────────────────────────────────────────

## Whether a card is close enough to the viewport to be worth building.
##
## ONE VIEWPORT of slack on every side, not zero: a card built only when it crosses the edge
## appears a frame late during a pan, and the edge painter measures cards it can find -- a card
## that is not there yet has no anchor, so the edge into it has nowhere to land.
##
## A card that is culled still occupies its estimated height, so the layout does not reflow when
## a pan brings it back.
static func is_near_viewport(card: Graph.Card, card_width: float,
		camera: Vector2, zoom: float, viewport: Vector2) -> bool:
	if card == null or viewport.x <= 0.0 or viewport.y <= 0.0 or zoom <= 0.0:
		return true
	var left := card.x * zoom + camera.x
	var top := card.y * zoom + camera.y
	var right := left + card_width * zoom
	var bottom := top + card_height(card) * zoom
	return right >= -viewport.x and left <= viewport.x * 2.0 \
		and bottom >= -viewport.y and top <= viewport.y * 2.0


## The world rectangle every card occupies, for a fit-to-view. Empty when there are no cards.
static func content_bounds(graph: Graph, lod: Lod) -> Rect2:
	if graph == null or graph.cards.is_empty():
		return Rect2()
	var width := card_width_for(lod)
	var bounds := Rect2(graph.cards[0].x, graph.cards[0].y, width, card_height(graph.cards[0]))
	for card in graph.cards:
		bounds = bounds.merge(Rect2(card.x, card.y, width, card_height(card)))
	return bounds


## The camera and zoom that fit the whole graph into `viewport`, with a margin.
static func fit_to_view(graph: Graph, viewport: Vector2, margin := 40.0) -> Dictionary:
	var bounds := content_bounds(graph, Lod.SECTIONS)
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0 or viewport.x <= 0.0 or viewport.y <= 0.0:
		return { "camera": Vector2.ZERO, "zoom": 1.0 }
	var usable := viewport - Vector2(margin, margin) * 2.0
	var zoom := clamp_zoom(minf(usable.x / bounds.size.x, usable.y / bounds.size.y))
	var camera := viewport * 0.5 - (bounds.position + bounds.size * 0.5) * zoom
	return { "camera": camera, "zoom": zoom }


# ── Anchors ──────────────────────────────────────────────────────────────────────────

## Where an edge leaves a card: the right edge of the import ROW it comes from, so a card with
## four imports has four distinct departure points rather than four lines out of one.
static func edge_source_anchor(card: Graph.Card, import_index: int,
		card_width: float) -> Vector2:
	# ON THE IMPORT ROW, when the card is showing its import rows.
	#
	# A fixed offset from the card top put every anchor in the header, so at the section and full
	# bands all of a card's edges left from the same point and the card's own IMPORTS list -- the
	# thing each edge actually comes from -- had nothing beside it. The section stack already
	# knows where that list starts and how tall a row is; asking it is the difference between an
	# edge attached to a line and an edge attached to a box.
	var y := card.y + EDGE_ANCHOR_Y + maxi(0, import_index) * ANCHOR_PITCH
	for entry in section_stack(card):
		var section := entry as Dictionary
		if int(section["section"]) != int(Section.IMPORTS):
			continue
		y = card.y + float(section["top"]) + SECTION_OVERHEAD_H 			+ (float(maxi(0, import_index)) + 0.5) * IMPORT_ROW_H
		break
	return Vector2(card.x + card_width, y)


## Where an edge arrives: the left edge of the target card, at its own anchor line.
static func edge_target_anchor(card: Graph.Card) -> Vector2:
	return Vector2(card.x, card.y + EDGE_ANCHOR_Y)


## The two control points of the edge curve. Pulled horizontally by a fraction of the span, with
## a floor, so a short back-edge still bows out instead of collapsing into the cards it joins.
static func edge_control_points(from: Vector2, to: Vector2, zoom: float) -> Array[Vector2]:
	# THE PULL FOLLOWS THE DOMINANT DIRECTION. Pulling horizontally always was right when levels
	# were columns and every child sat to the right; with levels as rows, most children sit BELOW
	# and slightly left, so a rightward pull out of the source and a leftward pull into the target
	# doubles the curve back through itself -- the knot of loops the canvas was drawing.
	var span := to - from
	if absf(span.y) > absf(span.x):
		var vertical: float = maxf(40.0 / maxf(zoom, 0.001), absf(span.y) * 0.45)
		return [from + Vector2(0.0, vertical), to - Vector2(0.0, vertical)]
	var pull: float = maxf(40.0 / maxf(zoom, 0.001), absf(span.x) * 0.45)
	return [from + Vector2(pull, 0.0), to - Vector2(pull, 0.0)]


## A point on the edge curve at `t` in [0, 1] -- the cubic the overlay strokes, exposed so a
## hit-test and the painter cannot disagree about where the line actually is.
static func edge_point(from: Vector2, to: Vector2, zoom: float, t: float) -> Vector2:
	var controls := edge_control_points(from, to, zoom)
	var u := 1.0 - t
	return from * (u * u * u) \
		+ controls[0] * (3.0 * u * u * t) \
		+ controls[1] * (3.0 * u * t * t) \
		+ to * (t * t * t)


# ── Row hit-testing ──────────────────────────────────────────────────────────────────

## THE THREE BANDS. A drop resolves by where in a row's height it landed: the top third means
## "before this row", the bottom third "after it", and the middle -- the widest target, because
## it is the commonest intent -- means "inside it".
const BAND_EDGE := 1.0 / 3.0


## Which row of a card a card-local point is over: { section, index, band, found }.
##
## `found` is false for a point over the header, over a section's heading, or past the last row --
## all of which are places a drop has no row to attach to, and all of which are different from
## "row zero", which is what a hit-test that clamped would say.
##
## Read from `section_stack`, so the hit-test and the height model cannot disagree about where a
## row is -- a disagreement there reads as an imprecise drag rather than as a defect.
static func row_hit(card: Graph.Card, card_local: Vector2) -> Dictionary:
	var miss := { "found": false, "section": Section.MARKUP, "index": -1, "band": 1 }
	if card == null or card_local.y < 0.0:
		return miss
	for entry in section_stack(card):
		var e := entry as Dictionary
		var top := float(e["top"])
		var height := float(e["height"])
		if card_local.y < top or card_local.y >= top + height:
			continue
		var into := card_local.y - top - float(e["lead"])
		if into < 0.0:
			return miss   # over the section's own heading
		var row_height := float(e["row_height"])
		var index := int(into / row_height)
		if index >= int(e["rows"]):
			return miss
		var fraction := fmod(into, row_height) / row_height
		var band := 1
		if fraction < BAND_EDGE:
			band = 0
		elif fraction > 1.0 - BAND_EDGE:
			band = 2
		return { "found": true, "section": e["section"], "index": index, "band": band }
	return miss


## The card-local point a SCREEN point falls on, for a card at its own position and zoom.
static func card_local_of(card: Graph.Card, screen: Vector2, camera: Vector2, zoom: float) -> Vector2:
	return screen_to_world(screen, camera, zoom) - Vector2(card.x, card.y)
