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


static func card_box() -> Dictionary:
	return {
		"bg_color": Color(0.137, 0.137, 0.161),
		"corner_radius_all": 10,
		"border_width_all": 1,
		"border_color": Color(0.188, 0.188, 0.220),
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
		"border_color": Color(0.188, 0.188, 0.220),
	}


static func title() -> Dictionary:
	return { "font_size": 15, "font_color": Color(0.898, 0.898, 0.937) }


static func pill_title() -> Dictionary:
	return { "font_size": 26, "font_color": Color(0.898, 0.898, 0.937) }


static func signature() -> Dictionary:
	return { "font_size": 11, "font_color": Color(0.588, 0.588, 0.647) }


static func section_head() -> Dictionary:
	return { "font_size": 10, "font_color": Color(0.478, 0.478, 0.545) }


static func import_row() -> Dictionary:
	return { "font_size": 11, "font_color": Color(0.635, 0.729, 0.910) }


static func chip() -> Dictionary:
	return { "bg_color": Color(0.180, 0.220, 0.290), "corner_radius_all": 6, "content_margin_all": 4 }


static func chip_text() -> Dictionary:
	return { "font_size": 11, "font_color": Color(0.749, 0.851, 1.0) }


static func markup_row() -> Dictionary:
	return { "font_size": 11, "font_color": Color(0.831, 0.878, 0.784) }


static func component_row() -> Dictionary:
	return { "font_size": 11, "font_color": Color(0.949, 0.831, 0.639) }


static func directive_row() -> Dictionary:
	return { "font_size": 11, "font_color": Color(0.902, 0.729, 0.949) }


static func attrs() -> Dictionary:
	return { "font_size": 10, "font_color": Color(0.541, 0.573, 0.612) }


static func island_row() -> Dictionary:
	return { "font_size": 10, "font_color": Color(0.612, 0.635, 0.678) }


static func export_row() -> Dictionary:
	return { "font_size": 11, "font_color": Color(0.729, 0.902, 0.835) }


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
	return Color(0.482, 0.545, 0.647, 0.85)


static func edge_style() -> Color:
	return Color(0.831, 0.647, 0.925, 0.85)



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
	return { "font_size": 10, "font_color": tint }


## A "+ hook" / "+ code" / "+ style" chip inside a card.
static func add_chip() -> Dictionary:
	return {
		"font_size": 11,
		"font_color": Color(0.635, 0.729, 0.910),
		"bg_color": Color(0.180, 0.220, 0.290, 0.6),
		"corner_radius_all": 6,
		"content_margin_all": 4,
	}
