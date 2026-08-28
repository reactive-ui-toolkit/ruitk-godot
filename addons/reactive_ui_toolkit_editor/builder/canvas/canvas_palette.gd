@tool
class_name RuitkBuilderCanvasPalette
extends RefCounted
## The canvas palette: every colour and style dictionary a card is drawn with.
##
## A hand-written `@tool` script rather than a `.style.guitkx` module, and that is a deliberate
## exception to the builder's own dogfooding.
##
## A generated `.gd` carries no `@tool`, and a non-tool script's STATIC VARS are never initialised
## in the editor -- `size() == 0`, every lookup silently missing. That is invisible at runtime,
## where a game's scripts do run, and fatal here, where the canvas IS editor code. Static FUNCS of
## a non-tool script still execute, which is why the rest of the canvas can stay `.guitkx`: only
## the DATA had to move.
##
## The shipped `.style.guitkx` example lives under `examples/` instead, where it runs in a game and
## does what it says. Teaching the convention with a module that is inert in the editor would be
## teaching the wrong thing.

static func bg() -> Dictionary:
	return { "bg_color": Color(0.086, 0.086, 0.098) }


## The editor's own monospace face, or null outside the editor.
##
## CODE CONTENT MUST LOOK LIKE CODE. A card's markup rows, its import lines and a style module's
## entries are all source text, and set in the UI font they read as prose -- so a tree of tags
## and a list of labels look the same, and the one thing the canvas is showing is the difference
## between them. The Unity leg sets all of it in mono for exactly this reason.
static func mono() -> Font:
	if not Engine.is_editor_hint():
		return null
	var base := EditorInterface.get_editor_theme() if Engine.has_singleton("EditorInterface") 		or ClassDB.class_exists("EditorInterface") else null
	if base == null:
		return null
	return base.get_font("source", "EditorFonts") if base.has_font("source", "EditorFonts") else null


## A code style with the mono face folded in, when there is one to fold.
static func _code(style: Dictionary) -> Dictionary:
	var face := mono()
	if face != null:
		style["font"] = face
	return style


static func card_box() -> Dictionary:
	return {
		"bg_color": Color(0.137, 0.137, 0.161),
		"corner_radius_all": 10,
		"border_width_all": 1,
		"border_color": Color(0.30, 0.30, 0.36),
		"content_margin_all": 10,
	}


static func card_box_selected() -> Dictionary:
	return {
		"bg_color": Color(0.137, 0.137, 0.161),
		"corner_radius_all": 10,
		"border_width_all": 2,
		"border_color": Color(0.361, 0.588, 0.965),
		"content_margin_all": 10,
	}


static func card_placeholder() -> Dictionary:
	return {
		"bg_color": Color(0.137, 0.137, 0.161),
		"corner_radius_all": 10,
		"border_width_all": 1,
		"border_color": Color(0.30, 0.30, 0.36),
	}


static func title() -> Dictionary:
	return { "font_size": 15, "font_color": Color(0.898, 0.898, 0.937) }


static func pill_title() -> Dictionary:
	return { "font_size": 26, "font_color": Color(0.898, 0.898, 0.937) }


static func signature() -> Dictionary:
	return _code({ "font_size": 11, "font_color": Color(0.588, 0.588, 0.647) })


static func section_head() -> Dictionary:
	return { "font_size": 10, "font_color": Color(0.478, 0.478, 0.545) }


static func import_row() -> Dictionary:
	return _code({ "font_size": 11, "font_color": Color(0.635, 0.729, 0.910) })


static func chip() -> Dictionary:
	return { "bg_color": Color(0.180, 0.220, 0.290), "corner_radius_all": 6, "content_margin_all": 4 }


static func chip_text() -> Dictionary:
	return _code({ "font_size": 11, "font_color": Color(0.749, 0.851, 1.0) })


static func markup_row() -> Dictionary:
	return _code({ "font_size": 11, "font_color": Color(0.831, 0.878, 0.784) })


static func component_row() -> Dictionary:
	return _code({ "font_size": 11, "font_color": Color(0.949, 0.831, 0.639) })


static func directive_row() -> Dictionary:
	return _code({ "font_size": 11, "font_color": Color(0.902, 0.729, 0.949) })


static func attrs() -> Dictionary:
	return _code({ "font_size": 10, "font_color": Color(0.541, 0.573, 0.612) })


static func island_row() -> Dictionary:
	return _code({ "font_size": 10, "font_color": Color(0.612, 0.635, 0.678) })


static func export_row() -> Dictionary:
	return _code({ "font_size": 11, "font_color": Color(0.729, 0.902, 0.835) })


static func read_only() -> Dictionary:
	return { "font_size": 10, "font_color": Color(0.859, 0.678, 0.478) }


## The kind badge's tint, by `RuitkBuilderModule.Kind`. A function of the kind rather than a
## dictionary indexed by it: an unknown kind gets an answer instead of an out-of-bounds.
static func kind_tint(kind: int) -> Color:
	match kind:
		0:
			return Color(0.361, 0.588, 0.965)   # component
		1:
			return Color(0.541, 0.831, 0.678)   # hook
		2:
			return Color(0.925, 0.706, 0.416)   # style
		3:
			return Color(0.729, 0.678, 0.925)   # util
		4:
			return Color(0.588, 0.780, 0.902)   # value
		5:
			return Color(0.831, 0.647, 0.780)   # module
		_:
			return Color(0.549, 0.549, 0.600)   # unknown


## Edge tints. A usage edge and a STYLE usage edge are different relationships and the canvas has
## to say so: an import of a component puts an element in the tree, an import of a style module
## puts a look on one. Drawn the same, a reader has to open both files to tell which is which.
static func edge_component() -> Color:
	# Bright enough to READ AS A CONNECTION. At 0.48/0.55/0.65 the edges were a shade off the
	# canvas ground and behind the cards in weight -- the one thing on the surface that carries
	# the graph's structure was the faintest thing on it.
	return Color(0.42, 0.66, 0.95, 0.95)


static func edge_style() -> Color:
	return Color(0.86, 0.60, 0.98, 0.95)



## The kind badge: a filled chip in the kind's own tint, carrying the kind as a WORD.
##
## A four-pixel colour bar said the same thing to anyone who already knew the colour code, and
## nothing at all to anyone who did not. The legend in the toolbar names the colours; the badge
## names itself, so a card is readable without looking away from it.
static func kind_badge(tint: Color) -> Dictionary:
	return {
		"bg_color": Color(tint, 0.22),
		"corner_radius_all": 4,
		"content_margin_all": 3,
	}


static func kind_badge_text(tint: Color) -> Dictionary:
	return { "font_size": 12, "font_color": tint }


## A "+ hook" / "+ code" / "+ style" chip inside a card.
static func add_chip() -> Dictionary:
	return {
		"font_size": 11,
		"font_color": Color(0.635, 0.729, 0.910),
		"bg_color": Color(0.180, 0.220, 0.290, 0.6),
		"corner_radius_all": 6,
		"content_margin_all": 4,
	}



## The band behind the SELECTED row -- a warm fill and an accent outline.
##
## Selection has to be visible on the row itself, not only in the panes that follow it. Delete acts
## on the selection, and a selection you cannot see is a key you press hoping.
static func row_selected() -> Dictionary:
	return {
		"bg_color": Color(0.361, 0.588, 0.965, 0.20),
		"border_width_all": 1,
		"border_color": Color(0.361, 0.588, 0.965, 0.85),
		"corner_radius_all": 4,
		"content_margin_left": 3,
		"content_margin_right": 3,
	}


## The same row, unselected: no fill, and the SAME margins, so selecting a row does not shift the
## text under it by three pixels.
static func row_plain() -> Dictionary:
	return { "content_margin_left": 3, "content_margin_right": 3 }


## The tinted strip behind a card's identity row.
##
## A card with no banding is one continuous column of text in which the name, the signature and
## every section label carry the same weight -- so the reader has to parse the card to find its
## structure, which is the job the card was supposed to be doing for them.
static func card_header_band(tint: Color) -> Dictionary:
	return {
		"bg_color": Color(tint, 0.10),
		"corner_radius_top_left": 10,
		"corner_radius_top_right": 10,
		"content_margin_all": 8,
	}


## The hairline between one section of a card and the next.
static func section_rule() -> Dictionary:
	return { "color": Color(0.24, 0.24, 0.29, 0.9), "custom_minimum_size": Vector2(0, 1) }



## The badge at the PILL band, where the card is scaled down with the canvas.
##
## Larger than the badge on a full card, because at that band the whole card is drawn at a third
## of its size: a badge sized for 1:1 renders there as a smudge, and the kind word -- the only
## thing besides the name that a pill carries -- becomes unreadable exactly where the reader is
## scanning many cards at once.
static func pill_badge_text(tint: Color) -> Dictionary:
	return { "font_size": 22, "font_color": tint }
