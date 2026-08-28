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

## The band edges, from the capability reference §2:
##
##   Layer 1 — Architecture   preset 0.30   applies below 0.32
##   Layer 2 — Cards          preset 0.75   applies below 0.80
##   Layer 3 — Edit           preset 1.25   applies at 0.80 and above
##
## These are the reference's numbers, not ones invented here. The values I had (0.45 / 0.75) put
## the working zoom in the wrong band and made the layer selector disagree with what was drawn.
const LOD_PILL_BELOW := 0.32
const LOD_SECTIONS_BELOW := 0.80

## The zoom each layer jumps to when chosen by name.
const LAYER_PRESETS := [0.30, 0.75, 1.25]

## What a tree with no saved layout opens at: Layer 2, where a card shows its shape without
## showing every attribute in it.
const DEFAULT_ZOOM := 0.75

## Card width per LOD. A pill is narrower because it holds a title; the full card is wider
## because it is the only one that rides the attribute run on a markup row.
const CARD_WIDTH_PILL := 300.0
const CARD_WIDTH_SECTIONS := 340.0
## Narrower than it was. At 430 the widest thing on a card was the blank half to the right of
## its content -- and with attributes now a zoom deeper, nothing on the card needs that width.
const CARD_WIDTH_FULL := 360.0

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


## WHETHER A LAYER DRAWS THIS SECTION. The single definition, read by the height estimate, the
## hit-test AND the view.
##
## Written in three places it drifted, and the symptom was the worst kind: `drawn_height` stopped
## the card above its markup while `row_hit` went on reporting markup rows below that, so on every
## card the lower half was DEAD TO THE MOUSE. `card_at` said "no card here", and with it went the
## row click, the row menu, and every drop that resolves through a card -- which is to say adding
## an element, dragging one onto a card, and re-parenting a row all failed together while dragging
## the card by its title bar kept working, because the title bar is inside the short rect.
##
## The bands are the capability reference's §2:
##   Layer 1 — Architecture: a pill. Name and kind, nothing else.
##   Layer 2 — Cards:        signature, imports, hook chips, MARKUP ROWS.
##   Layer 3 — Edit:         adds attributes, code islands and style entry lines.
## Whether a card HAS a BODY section at all.
##
## The model said "not card.body.is_empty() or kind is COMPONENT/HOOK"; the view said
## `card.kind != 2`, which is every kind except STYLE. For a util, a value or a plain module the
## two disagreed about whether the section EXISTS -- and this file's whole reason for being is
## that the height estimate and the hit-test read ONE description. Written twice, they drifted,
## which is the failure its own class comment warns about.
static func has_body_section(card: Graph.Card) -> bool:
	if card == null:
		return false
	# A component or a hook has one even when it is empty -- the card offers to add the first hook
	# there, and an affordance the card declines to show cannot be clicked.
	return not card.body.is_empty() 		or card.kind == Module.Kind.COMPONENT or card.kind == Module.Kind.HOOK


## Whether a card shows a SIGNATURE row.
static func has_signature_section(card: Graph.Card) -> bool:
	return card != null and not card.signature.is_empty() and card.kind != Module.Kind.STYLE


## Whether a card has an EXPORTS block -- the entry list a style, util or value module carries.
##
## The view gated this on `card.kind == 2` (STYLE alone) while the stack builds it from
## `export_detail`, so a util or value module's exports were never drawn AT ANY ZOOM while the
## metrics reserved height for them and the hit-test addressed rows inside that height.
static func has_exports_section(card: Graph.Card) -> bool:
	return card != null and not card.export_detail.is_empty()


static func draws_section(section: int, lod: Lod) -> bool:
	if lod == Lod.PILL:
		return false
	if section == int(Section.EXPORTS) or section == int(Section.ISLAND):
		return shows_detail(lod)
	return true


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


## The height the card is actually DRAWN at, in the given band.
##
## `card_height` answers with the tallest layout on purpose -- the gutter between rows has to
## survive every zoom, so the layout reserves the full-band height whatever is showing. Anything
## that asks "where is this card ON SCREEN" needs the other answer, and asking the wrong one put
## the edge anchors and the click rectangle a long way below a pill: dots floating under cards,
## and clicks landing on a card whose visible edge was a hundred pixels above the pointer.
static func drawn_height(card: Graph.Card, lod: Lod) -> float:
	if card == null:
		return PILL_H
	if lod == Lod.PILL:
		# PILL_H, NOT HEADER_H. A pill draws at 73 units and this reported 38, so the bottom half
		# of every Architecture-layer card was dead to the mouse -- the same
		# model-disagrees-with-the-view defect as CANVAS-01, in the one band the measured
		# hit-test cannot help with, because a pill has no rows to measure.
		return PILL_H
	var height := HEADER_H
	for entry in section_stack(card):
		var section := entry as Dictionary
		if not draws_section(int(section["section"]), lod):
			continue
		height += float(section["height"])
	return height


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
	var top := HEADER_H

	if has_signature_section(card):
		var lines := wrap_lines(card.signature.length(), inner, MONO_ADVANCE)
		out.append(_section_row(Section.SIGNATURE, top, SIGNATURE_LEAD_H, lines, SIGNATURE_LINE_H))
		top += SIGNATURE_LEAD_H + lines * SIGNATURE_LINE_H
	if not card.imports.is_empty():
		out.append(_section_row(Section.IMPORTS, top, SECTION_OVERHEAD_H,
			card.imports.size(), IMPORT_ROW_H))
		top += SECTION_OVERHEAD_H + card.imports.size() * IMPORT_ROW_H
	if has_body_section(card):
		var chips := _chip_rows(card, inner, has_body_section(card))
		out.append(_section_row(Section.BODY, top, SECTION_OVERHEAD_H, chips, CHIP_ROW_H))
		top += SECTION_OVERHEAD_H + chips * CHIP_ROW_H
	if not card.markup.is_empty():
		out.append(_section_row(Section.MARKUP, top, SECTION_OVERHEAD_H,
			card.markup.size(), MARKUP_ROW_H))
		top += SECTION_OVERHEAD_H + card.markup.size() * MARKUP_ROW_H
	if has_exports_section(card):
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


## The camera and zoom that FRAME one card: solve the zoom so the card fills the viewport, then
## centre on it (capability reference §10).
##
## What double-clicking a library entry does. Distinct from `fit_to_view`, which frames the whole
## graph -- on a tree of twenty modules that leaves every card too small to read, which is exactly
## the situation someone hunting for one module by name is in.
##
## Measured at the SECTIONS layout, then clamped: a card is drawn at whatever band the solved zoom
## lands in, and solving against the band's own height would be circular.
static func frame_card(card: Graph.Card, viewport: Vector2, margin := 60.0) -> Dictionary:
	if card == null or viewport.x <= 0.0 or viewport.y <= 0.0:
		return { "camera": Vector2.ZERO, "zoom": 1.0 }
	# THE WIDTH DECIDES THE ZOOM, not the smaller of the two axes. Fitting the height as well means
	# a long card frames itself tiny -- 40 markup rows solved to the minimum zoom, which is the
	# Architecture band, so "show me this card" answered with a pill. Unity found and fixed this
	# once already.
	var usable := viewport - Vector2(margin, margin) * 2.0
	var zoom := clamp_zoom(usable.x / card_width_for(Lod.SECTIONS))
	# Twice, because the width itself depends on the band the zoom lands in. Three bands, so it
	# converges immediately.
	zoom = clamp_zoom(usable.x / card_width_for(lod_of(zoom)))
	var lod := lod_of(zoom)
	var size := Vector2(card_width_for(lod), maxf(drawn_height(card, lod), 1.0))
	var camera := Vector2(
		viewport.x * 0.5 - (card.x + size.x * 0.5) * zoom,
		viewport.y * 0.5 - (card.y + size.y * 0.5) * zoom)
	# A CARD TALLER THAN THE VIEWPORT IS ALIGNED TO ITS TOP. Centring one vertically puts its name
	# off-screen, which is the half a reader needs most.
	if size.y * zoom > viewport.y:
		camera.y = margin - card.y * zoom
	return { "camera": camera, "zoom": zoom }


# ── Anchors ──────────────────────────────────────────────────────────────────────────

## Where an edge leaves a card: the right edge of the import ROW it comes from, so a card with
## four imports has four distinct departure points rather than four lines out of one.
static func edge_source_anchor(card: Graph.Card, import_index: int,
		card_width: float, lod := Lod.FULL, section := Section.IMPORTS) -> Vector2:
	# ON THE ROW IT LEAVES FROM, when the card is showing that row.
	#
	# A fixed offset from the card top put every anchor in the header, so at the section and full
	# bands all of a card's edges left from the same point and the card's own rows -- the things
	# each edge actually comes from -- had nothing beside them. The section stack already knows
	# where each list starts and how tall a row is; asking it is the difference between an edge
	# attached to a line and an edge attached to a box.
	var y := card.y + EDGE_ANCHOR_Y + maxi(0, import_index) * ANCHOR_PITCH
	# A PILL HAS NO ROWS to anchor on, so every edge leaves from its single header line. Walking
	# the section stack there put the anchor where the imports WOULD be if the card were open --
	# a dot hanging in space below a pill, joined to a curve that appeared to start at nothing.
	if lod == Lod.PILL:
		return Vector2(card.x + card_width, card.y + HEADER_H * 0.5)
	for entry in section_stack(card):
		var spec := entry as Dictionary
		if int(spec["section"]) != int(section):
			continue
		var pitch := float(spec.get("row_height", IMPORT_ROW_H))
		y = card.y + float(spec["top"]) + SECTION_OVERHEAD_H 			+ (float(maxi(0, import_index)) + 0.5) * pitch
		break
	return Vector2(card.x + card_width, y)


## The index of the row that IS the component's return root, or -1.
##
## Keyed on the first NON-DIRECTIVE row, never on literal index 0: a directive wrapping the root
## takes index 0 and the root becomes row 1.
static func first_element_row(card: Graph.Card) -> int:
	if card == null:
		return -1
	for i in card.markup.size():
		if (card.markup[i] as Graph.Line).kind != Graph.LineKind.DIRECTIVE:
			return i
	return -1


## Whether a markup row references any of `names` -- what makes it a USAGE of a hook's state.
##
## Matched on WORD BOUNDARIES, so `count` does not light up a row mentioning `counter`. Asked of
## the row's projected text and its attribute run together, because a state name is used in an
## attribute far more often than in a tag.
static func row_mentions(row: Graph.Line, names) -> bool:
	if row == null or names == null:
		return false
	var list := names as PackedStringArray
	if list.is_empty():
		return false
	var haystack := row.text + " " + row.attrs_text
	for name in list:
		var word := str(name)
		if word.is_empty():
			continue
		var at := haystack.find(word)
		while at >= 0:
			var before_ok := at == 0 or not _is_word_char(haystack[at - 1])
			var after := at + word.length()
			var after_ok := after >= haystack.length() or not _is_word_char(haystack[after])
			if before_ok and after_ok:
				return true
			at = haystack.find(word, at + 1)
	return false


static func _is_word_char(ch: String) -> bool:
	return ch == "_" or (ch >= "0" and ch <= "9") 		or (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z")


## Whether a world point is on a card's TITLE BAR -- the band a card is dragged by.
##
## CARDS ARE DRAGGED BY THE TITLE BAR (capability reference §2), not from anywhere on their face.
## A card is mostly rows, and every row is a click target of its own -- selecting it, opening its
## menu, starting a re-parent drag. Making the whole card a drag handle means any of those
## gestures, off by four pixels, silently moves the card instead.
##
## A PILL IS ALL TITLE: at that band the card has no rows to compete with, and requiring the top
## 38 world-units of a card drawn at a third of its size would leave a handle a few pixels tall.
static func on_title_bar(card: Graph.Card, world: Vector2, card_width: float,
		lod := Lod.FULL) -> bool:
	if card == null:
		return false
	if world.x < card.x or world.x > card.x + card_width:
		return false
	if lod == Lod.PILL:
		return world.y >= card.y and world.y <= card.y + drawn_height(card, lod)
	return world.y >= card.y and world.y <= card.y + HEADER_H


## Where an edge arrives: the TOP-LEFT CORNER of the target card.
##
## The reference's own choice (capability reference §2), and it is the one that stays readable as
## a card grows: a fixed offset down the left border lands mid-card once the card is tall, so the
## curve crosses the card's own rows on its way in and the arrival point moves every time the
## module gains a hook. The corner is the one point on a card that does not move when its content
## changes.
static func edge_target_anchor(card: Graph.Card) -> Vector2:
	return Vector2(card.x, card.y)


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
static func row_hit(card: Graph.Card, card_local: Vector2, lod := Lod.FULL) -> Dictionary:
	var miss := { "found": false, "section": Section.MARKUP, "index": -1, "band": 1 }
	if card == null or card_local.y < 0.0:
		return miss
	# TOPS ARE RE-ACCUMULATED FOR THIS LOD. `section_stack` describes the full card, so a section
	# the layer does not draw is not merely skipped -- everything below it also sits that much
	# higher on screen, and hit-testing against the full-card tops would report the row above or
	# below the one under the cursor.
	var top_at := HEADER_H
	for entry in section_stack(card):
		var e := entry as Dictionary
		if not draws_section(int(e["section"]), lod):
			continue
		var top := top_at
		top_at += float(e["height"])
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
		# TWO ROWS HAVE NO SIDES, so their bands are coerced to INSIDE rather than refused
		# downstream. A component returns one node, so nothing can go beside its return root; a
		# continuation clause belongs to its head, so nothing can go beside that either. Refusing
		# the drop instead -- which is what happened -- reads as the drag being broken, when the
		# only wrong part was which third of the row the cursor was over.
		if int(e["section"]) == int(Section.MARKUP) and band != 1:
			if index == first_element_row(card):
				band = 1
			else:
				var row: Graph.Line = card.markup[index]
				if row.kind == Graph.LineKind.DIRECTIVE and row.clause_index > 0:
					band = 1
		return { "found": true, "section": e["section"], "index": index, "band": band }
	return miss


## The card-local point a SCREEN point falls on, for a card at its own position and zoom.
static func card_local_of(card: Graph.Card, screen: Vector2, camera: Vector2, zoom: float) -> Vector2:
	return screen_to_world(screen, camera, zoom) - Vector2(card.x, card.y)
