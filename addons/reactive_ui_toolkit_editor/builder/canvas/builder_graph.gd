@tool
class_name RuitkBuilderGraph
extends RefCounted
## The canvas model for one open tree: a CARD per module, a ROW per meaningful line inside it,
## and an EDGE per import. Pure data -- nothing here draws, measures or reads a file.
##
## The projection is total. Every module in the tree gets a card, and every import line gets a
## row whether or not it resolves anywhere: a card is the editing surface, so an elided tail
## would be unselectable, undroppable and un-right-clickable. The Unity leg learned this the
## hard way -- membership there was once "the component connected to the focus", so a module
## whose only import had just been broken vanished from the canvas mid-edit.
##
## SPANS, NOT JUST LINES. Every row carries the absolute character offset of what it came from
## as well as its line range. The Unity leg has lines alone, because its parser does not surface
## positions; ours does, so an edit can replace exactly the span a row represents instead of
## rewriting whole lines and hoping nothing else shared them.
##
## Cross-file references go through preload CONSTS, never the global `class_name`s these files
## also declare -- see `builder_module.gd` for why.

const Module = preload("res://addons/reactive_ui_toolkit_editor/builder/document/builder_module.gd")
const Paths = preload("res://addons/reactive_ui_toolkit_editor/builder/document/builder_paths.gd")


## What a row IS, for colouring and for what a click on it does.
enum LineKind {
	PLAIN,       ## setup code, a style entry, anything with no special handling
	IMPORT,      ## an import row -- carries an anchor dot and, usually, an edge
	HOOK,        ## a hook call in setup, shown as a chip
	ELEMENT,     ## a host element in the markup tree
	COMPONENT,   ## a user component in the markup tree
	DIRECTIVE,   ## a directive head or continuation clause
	EXPORT,      ## an export header or entry in the detail section
	TEXT,        ## literal text between elements
	EXPRESSION,  ## a `{expr}` child slot
}


## The badge a row shows, and what a drop on it means. An ENUM rather than the Unity leg's magic
## integers: the same value means one thing here, and a new badge cannot silently collide with a
## directive code.
enum Badge {
	NONE,
	# Directive heads and their continuations. A continuation is structurally bound to its head
	# and is never draggable on its own.
	IF, ELIF, ELSE, FOR, WHILE, MATCH, CASE, DEFAULT,
	# Import rows: which anchor dot the card draws.
	IMPORT_PLAIN, IMPORT_HOOKS, IMPORT_STYLE,
	## A theme or asset directive (`@uss` / `@theme`). A row with no graph node behind it, so no
	## anchor dot and no edge -- it names a resource, not a module.
	IMPORT_ASSET,
	# Affordances the card offers rather than facts about the source.
	ADD_ENTRY, ADD_STYLE, ADD_EXPORT,
	## The head of a util module's body island, and of a style module's export block.
	UTIL_BODY, STYLE_HEADER,
}


## One rendered line inside a card section.
class Line extends RefCounted:
	var text: String = ""
	var depth: int = 0
	var kind: LineKind = LineKind.PLAIN

	## Attribute display text for an element row (`text="hi" style={s}`), and the same split into
	## per-attribute pairs -- the inline editor edits one value at a time.
	##
	## On an IMPORT row these carry the row's own list instead: `attrs_text` is the specifier and
	## `attr_pairs` the LOCAL names the import binds, which is what the edge carries and what a
	## reference search starts from.
	var attrs_text: String = ""
	var attr_pairs: PackedStringArray = PackedStringArray()

	## 1-based inclusive source range. `end_line` is 0 for a single-line row.
	var source_line: int = 0
	var end_line: int = 0

	## Absolute character offsets into the module's buffer: `at` is the row's first character,
	## `end_at` one past its last (0 when the row is synthetic, like an affordance).
	var at: int = 0
	var end_at: int = 0

	## The element's tag closes itself (`<Label … />`), so it has no closing tag and cannot take
	## a child without being re-opened.
	var self_closing: bool = false

	var badge: Badge = Badge.NONE

	## Badge label on a directive HEAD row (`@if` / `@for` / `@else`). A directive clause is a row
	## of its own -- the badge does not ride the clause's first element row.
	var badge_text: String = ""

	## Full directive header text (`@for (var item in items)`) -- what the inline badge editor
	## seeds from -- and the 1-based line it sits on.
	var directive_text: String = ""
	var directive_line: int = 0

	## Directive head rows only: the 1-based line the construct closes on. On the construct head
	## (`clause_index` 0) this is the WHOLE construct's final close -- the move/delete range; on a
	## continuation clause it is that clause's own boundary -- the delete-clause range.
	var close_line: int = 0

	## Directive head rows only: 0 = construct head (`@if` / a loop / `@match` -- draggable,
	## carries the whole block); >0 = a structurally bound continuation (`@elif` / `@else` /
	## `@case` / `@default` -- never draggable on its own).
	var clause_index: int = 0

	## Verbatim (trimmed) source text of the line this row came from -- what a chip's inline
	## editor seeds from.
	var source_text: String = ""

	## The row's own name, where it has one: an element's tag, an import's specifier, a hook's
	## name. Kept apart from `text`, which is for display and may be decorated.
	var name: String = ""

	## The same row with its offsets moved by `delta`.
	##
	## An edit that removes text ahead of a row invalidates that row's span, and re-projecting to
	## find out where it went is both expensive and circular when the edit is not finished yet --
	## a move is a cut and a paste, and the paste needs the target's position AFTER the cut.
	func shifted(delta: int) -> Line:
		var copy := Line.new()
		copy.text = text
		copy.depth = depth
		copy.kind = kind
		copy.attrs_text = attrs_text
		copy.attr_pairs = attr_pairs
		copy.source_line = source_line
		copy.end_line = end_line
		copy.at = at + delta
		copy.end_at = end_at + delta
		copy.self_closing = self_closing
		copy.badge = badge
		copy.badge_text = badge_text
		copy.directive_text = directive_text
		copy.directive_line = directive_line
		copy.close_line = close_line
		copy.clause_index = clause_index
		copy.source_text = source_text
		copy.name = name
		return copy


## One file card on the canvas.
class Card extends RefCounted:
	var file_path: String = ""

	## The owning module's stable id. Cards are addressed by INDEX for edges and by id for
	## anything that has to survive the module being renamed -- a saved position, a selection.
	var module_id: String = ""

	var title: String = ""
	var signature: String = ""

	## What a module hands back, when that is not obvious from the signature row -- a hook
	## module's returned shape, carried separately so the signature row stays one line.
	var exposed_signature: String = ""

	var kind: Module.Kind = Module.Kind.UNKNOWN
	var read_only: bool = false

	## Canvas position. Seeded by the layout pass and then owned by the saved layout.
	var x: float = 0.0
	var y: float = 0.0

	## Memoised card height for the viewport cull. Zero means "not computed"; re-projecting a
	## card resets it.
	var cached_height: float = 0.0

	var exports: PackedStringArray = PackedStringArray()
	var imports: Array[Line] = []
	var body: Array[Line] = []
	var markup: Array[Line] = []

	## Style/util export detail: header rows, entry rows, and the affordances that add to them.
	var export_detail: Array[Line] = []

	## Setup-code lines that are not hook calls, shown as the card's code island, and the 1-based
	## inclusive source range they occupy (0 = none) -- an island edit replaces exactly that range.
	var island_lines: PackedStringArray = PackedStringArray()
	var island_start_line: int = 0
	var island_end_line: int = 0

	func clear_detail() -> void:
		exports = PackedStringArray()
		imports = []
		body = []
		markup = []
		export_detail = []
		island_lines = PackedStringArray()
		island_start_line = 0
		island_end_line = 0
		cached_height = 0.0


## One import edge. Indices into the card list; a BROKEN edge keeps `to_index` at -1 rather than
## disappearing, because the import row is real even when what it points at is not there yet.
class Edge extends RefCounted:
	var from_index: int = -1
	var to_index: int = -1
	var specifier: String = ""
	var names: PackedStringArray = PackedStringArray()
	var target_kind: Module.Kind = Module.Kind.UNKNOWN

	func is_broken() -> bool:
		return to_index < 0


var root_path: String = ""
var cards: Array[Card] = []
var edges: Array[Edge] = []


func index_of(file_path: String) -> int:
	var k := Paths.key(file_path)
	for i in range(cards.size()):
		if Paths.key(cards[i].file_path) == k:
			return i
	return -1


## Lookup by the module's stable id -- the addressing that survives a rename. A saved card
## position keyed on the path moves the card to the back of the canvas the moment the module is
## renamed; keyed on the id, it does not move at all.
func index_of_id(module_id: String) -> int:
	if module_id.is_empty():
		return -1
	for i in range(cards.size()):
		if cards[i].module_id == module_id:
			return i
	return -1


func card_of(file_path: String) -> Card:
	var i := index_of(file_path)
	return cards[i] if i >= 0 else null


## Every edge that STARTS at a card.
func edges_from(card_index: int) -> Array[Edge]:
	var out: Array[Edge] = []
	for e in edges:
		if e.from_index == card_index:
			out.append(e)
	return out


## Every edge that ENDS at a card -- who depends on it, which is what a delete has to warn about.
func edges_to(card_index: int) -> Array[Edge]:
	var out: Array[Edge] = []
	for e in edges:
		if e.to_index == card_index:
			out.append(e)
	return out





## The module kind as the word a card shows on its badge.
##
## The card's own vocabulary, not the file suffix: a reader sees "component" and "styles", which
## is what the toolbar legend calls them too, so the badge and the key agree.
static func kind_word(kind: int) -> String:
	match kind:
		0:
			return "component"
		1:
			return "hooks"
		2:
			return "styles"
		3:
			return "utils"
		4:
			return "value"
		5:
			return "module"
		_:
			return "module"
