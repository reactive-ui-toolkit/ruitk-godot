class_name CanvasView
extends RefCounted
## AUTO-GENERATED from canvas_view.guitkx -- do not edit.

const __RUI_DECLS := {
	"CanvasView": { "kind": "component", "sig": "", "export": true },
	"CanvasCard": { "kind": "component", "sig": "", "export": true },
	"CanvasCardHeader": { "kind": "component", "sig": "", "export": true },
	"CanvasCardSections": { "kind": "component", "sig": "", "export": true },
	"CanvasCardSection": { "kind": "component", "sig": "", "export": true },
	"CanvasMarkupRow": { "kind": "component", "sig": "", "export": true },
	"CanvasAddChip": { "kind": "component", "sig": "", "export": true },
}

const __RUI_KIND := "mixed"

const __RUI_HOOK_SIG := ""

# component CanvasView
static func render(props: Dictionary, children: Array) -> RuitkVNode:
	var graph = props.get("graph", null)
	var camera = props.get("camera", Vector2.ZERO)
	var zoom = props.get("zoom", 1.0)
	var viewport = props.get("viewport", Vector2(1280, 720))
	var selected = props.get("selected", -1)
	var on_add = props.get("on_add", null)
	var revision = props.get("revision", 0)
	var selected_row_section = props.get("selected_row_section", -1)
	var selected_row_index = props.get("selected_row_index", -1)
	var highlight_names = props.get("highlight_names", null)
	var M = preload("res://addons/reactive_ui_toolkit_editor/builder/canvas/builder_canvas_metrics.gd")
	var lod = M.lod_of(zoom)
	var card_w = M.card_width_for(lod)
	var cards = graph.cards if graph != null else []
	var __cf0: Array = []
	for i in range(cards.size()):
		var c = cards[i]
		# One VIEWPORT of slack: a card built only when it crosses the edge appears a
		# frame late during a pan, and the edge painter has no anchor to land on.
		var near = M.is_near_viewport(c, card_w, camera, zoom, viewport)
		# Position is SCREEN space and scale is the zoom, so the card's own contents are
		# laid out once in card-local units whatever the zoom is -- a layout that had to
		# re-measure every label at every zoom would re-wrap text as the user scrolled.
		var pos = M.world_to_screen(Vector2(c.x, c.y), camera, zoom)
		__cf0.append(V.fc(CanvasCard, { "card": c, "lod": lod, "index": i, "is_selected": i == selected, "at": pos, "zoom": zoom, "near": near, "on_add": on_add, "revision": revision, "sel_section": selected_row_section if i == selected else -1, "sel_row": selected_row_index if i == selected else -1, "highlight_names": highlight_names }, [], c.file_path))
		continue
	return V.Control({ "mouse_filter": Control.MOUSE_FILTER_IGNORE }, [__cf0])

# component CanvasCard
static func CanvasCard(props: Dictionary, children: Array) -> RuitkVNode:
	var card = props.get("card", null)
	var lod = props.get("lod", 1)
	var is_selected = props.get("is_selected", false)
	var at = props.get("at", Vector2.ZERO)
	var zoom = props.get("zoom", 1.0)
	var near = props.get("near", true)
	var index = props.get("index", -1)
	var on_add = props.get("on_add", null)
	var revision = props.get("revision", 0)
	var sel_section = props.get("sel_section", -1)
	var sel_row = props.get("sel_row", -1)
	var highlight_names = props.get("highlight_names", null)
	var P = preload("res://addons/reactive_ui_toolkit_editor/builder/canvas/canvas_palette.gd")
	var M = preload("res://addons/reactive_ui_toolkit_editor/builder/canvas/builder_canvas_metrics.gd")
	var card_w = M.card_width_for(lod)
	var __cf0 = null
	if near:
		for __cf0_once in 1:
			var __cf1 = null
			if M.shows_sections(lod):
				for __cf1_once in 1:
					__cf1 = V.fc(CanvasCardSections, { "card": card, "lod": lod, "index": index, "on_add": on_add, "zoom": zoom, "revision": revision, "sel_section": sel_section, "sel_row": sel_row, "highlight_names": highlight_names })
					continue
			__cf0 = V.PanelContainer({ "name": "card-%d" % index, "position": at, "scale": Vector2(zoom, zoom), "custom_minimum_size": Vector2(card_w, 0), "size": Vector2(card_w, 0), "clip_contents": true, "mouse_filter": Control.MOUSE_FILTER_IGNORE, "style": P.card_box_selected() if is_selected else P.card_box() }, [V.VBoxContainer({ "style": {"separation": 4}, "mouse_filter": Control.MOUSE_FILTER_IGNORE }, [V.fc(CanvasCardHeader, { "card": card, "lod": lod }), __cf1])])
			continue
	else:
		for __cf0_once in 1:
			# A culled card still occupies its estimated height, so nothing reflows when a pan
			# brings it back.
			__cf0 = V.PanelContainer({ "position": at, "scale": Vector2(zoom, zoom), "custom_minimum_size": Vector2(card_w, M.card_height(card)), "mouse_filter": Control.MOUSE_FILTER_IGNORE, "style": P.card_placeholder() }, [V.MarginContainer({ "style": {"margin_left": 10, "margin_top": 10, "margin_right": 10}, "mouse_filter": Control.MOUSE_FILTER_IGNORE }, [V.fc(CanvasCardHeader, { "card": card, "lod": lod })])])
			continue
	return __cf0

# component CanvasCardHeader
static func CanvasCardHeader(props: Dictionary, children: Array) -> RuitkVNode:
	var card = props.get("card", null)
	var lod = props.get("lod", 1)
	var P = preload("res://addons/reactive_ui_toolkit_editor/builder/canvas/canvas_palette.gd")
	var M = preload("res://addons/reactive_ui_toolkit_editor/builder/canvas/builder_canvas_metrics.gd")
	var Model = preload("res://addons/reactive_ui_toolkit_editor/builder/canvas/builder_graph.gd")
	var tint = P.kind_tint(int(card.kind))
	var __cf0 = null
	if card.read_only:
		for __cf0_once in 1:
			__cf0 = V.Label({ "text": "read-only", "style": P.read_only() })
			continue
	return V.PanelContainer({ "style": P.card_header_band(tint), "mouse_filter": Control.MOUSE_FILTER_IGNORE }, [V.HBoxContainer({ "style": {"separation": 6}, "mouse_filter": Control.MOUSE_FILTER_IGNORE }, [V.PanelContainer({ "style": P.kind_badge(tint), "mouse_filter": Control.MOUSE_FILTER_IGNORE }, [V.Label({ "text": Model.kind_word(int(card.kind)), "style": P.pill_badge_text(tint) if lod == M.Lod.PILL else P.kind_badge_text(tint) })]), V.Label({ "text": card.title, "style": P.pill_title() if lod == M.Lod.PILL else P.title() }), __cf0])])

# component CanvasCardSections
static func CanvasCardSections(props: Dictionary, children: Array) -> RuitkVNode:
	var card = props.get("card", null)
	var lod = props.get("lod", 1)
	var index = props.get("index", -1)
	var on_add = props.get("on_add", null)
	var zoom = props.get("zoom", 1.0)
	var revision = props.get("revision", 0)
	var sel_section = props.get("sel_section", -1)
	var sel_row = props.get("sel_row", -1)
	var highlight_names = props.get("highlight_names", null)
	var P = preload("res://addons/reactive_ui_toolkit_editor/builder/canvas/canvas_palette.gd")
	var M = preload("res://addons/reactive_ui_toolkit_editor/builder/canvas/builder_canvas_metrics.gd")
	# ASKED OF THE ONE PREDICATE the height estimate and the hit-test also ask, so the card cannot
	# draw a different set of sections from the ones the mouse can reach.
	var draws_markup = M.draws_section(M.Section.MARKUP, lod)
	var draws_exports = M.draws_section(M.Section.EXPORTS, lod)
	var draws_island = M.draws_section(M.Section.ISLAND, lod)
	var __cf0 = null
	if card.signature != "" and card.kind != 2:
		for __cf0_once in 1:
			__cf0 = V.Label({ "text": card.signature, "style": P.signature(), "clip_text": true, "text_overrun_behavior": TextServer.OVERRUN_TRIM_ELLIPSIS })
			continue
	var __cf1 = null
	if not card.imports.is_empty():
		for __cf1_once in 1:
			var __cf2: Array = []
			for i in range(card.imports.size()):
				var row = card.imports[i]
				__cf2.append(V.PanelContainer({ "name": "row-1-%d" % i, "mouse_filter": Control.MOUSE_FILTER_IGNORE, "style": P.row_selected() if (sel_section == 1 and sel_row == i) else P.row_plain() }, [V.Label({ "text": row.text, "style": P.import_row(), "text_overrun_behavior": TextServer.OVERRUN_TRIM_ELLIPSIS })], str(row.at)))
				continue
			__cf1 = V.fc(CanvasCardSection, { "heading": "IMPORTS" }, [__cf2])
			continue
	var __cf3 = null
	if card.kind != 2:
		for __cf3_once in 1:
			var __cf4: Array = []
			for i in range(card.body.size()):
				var row = card.body[i]
				__cf4.append(V.PanelContainer({ "name": "row-2-%d" % i, "mouse_filter": Control.MOUSE_FILTER_IGNORE, "style": P.row_selected() if (sel_section == 2 and sel_row == i) else P.chip() }, [V.Label({ "text": row.text, "style": P.chip_text(), "text_overrun_behavior": TextServer.OVERRUN_TRIM_ELLIPSIS })], str(row.at)))
				continue
			__cf3 = V.fc(CanvasCardSection, { "heading": "BODY — HOOKS & STATE" }, [V.HFlowContainer({ "style": {"separation": 4}, "mouse_filter": Control.MOUSE_FILTER_IGNORE }, [__cf4, V.fc(CanvasAddChip, { "label": "+ hook", "what": "hook", "index": index, "on_add": on_add }), V.fc(CanvasAddChip, { "label": "+ code", "what": "code", "index": index, "on_add": on_add })])])
			continue
	var __cf5 = null
	if draws_markup and not card.markup.is_empty():
		for __cf5_once in 1:
			var __cf6: Array = []
			for i in range(card.markup.size()):
				var row = card.markup[i]
				__cf6.append(V.PanelContainer({ "name": "row-3-%d" % i, "mouse_filter": Control.MOUSE_FILTER_IGNORE, "style": P.row_selected() if (sel_section == 3 and sel_row == i) else (P.row_highlighted() if M.row_mentions(row, highlight_names) else P.row_plain()) }, [V.fc(CanvasMarkupRow, { "row": row, "zoom": zoom })], str(row.at)))
				continue
			__cf5 = V.fc(CanvasCardSection, { "heading": "RETURN — MARKUP" }, [__cf6])
			continue
	var __cf7 = null
	if draws_exports and card.kind == 2:
		for __cf7_once in 1:
			var __cf8: Array = []
			for i in range(card.export_detail.size()):
				var row = card.export_detail[i]
				__cf8.append(V.PanelContainer({ "name": "row-4-%d" % i, "mouse_filter": Control.MOUSE_FILTER_IGNORE, "style": P.row_selected() if (sel_section == 4 and sel_row == i) else P.row_plain() }, [V.Label({ "text": "  ".repeat(row.depth) + row.text, "style": P.export_row(), "clip_text": true, "text_overrun_behavior": TextServer.OVERRUN_TRIM_ELLIPSIS })], str(row.at) + row.text))
				continue
			__cf7 = V.fc(CanvasCardSection, { "heading": "EXPORTS" }, [__cf8, V.HFlowContainer({ "style": {"separation": 4}, "mouse_filter": Control.MOUSE_FILTER_IGNORE }, [V.fc(CanvasAddChip, { "label": "+ style", "what": "style", "index": index, "on_add": on_add })])])
			continue
	var __cf9 = null
	if draws_island and not card.island_lines.is_empty():
		for __cf9_once in 1:
			var __cf10: Array = []
			for i in range(card.island_lines.size()):
				__cf10.append(V.PanelContainer({ "name": "row-5-%d" % i, "mouse_filter": Control.MOUSE_FILTER_IGNORE, "style": P.row_selected() if (sel_section == 5 and sel_row == i) else P.row_plain() }, [V.Label({ "text": card.island_lines[i], "style": P.island_row(), "clip_text": true, "text_overrun_behavior": TextServer.OVERRUN_TRIM_ELLIPSIS })], str(i)))
				continue
			__cf9 = V.fc(CanvasCardSection, { "heading": "SETUP" }, [__cf10])
			continue
	return V.VBoxContainer({ "style": {"separation": 4}, "mouse_filter": Control.MOUSE_FILTER_IGNORE }, [__cf0, __cf1, __cf3, __cf5, __cf7, __cf9])

# component CanvasCardSection
static func CanvasCardSection(props: Dictionary, children: Array) -> RuitkVNode:
	var heading = props.get("heading", "")
	var P = preload("res://addons/reactive_ui_toolkit_editor/builder/canvas/canvas_palette.gd")
	return V.VBoxContainer({ "style": {"separation": 2}, "mouse_filter": Control.MOUSE_FILTER_IGNORE }, [V.ColorRect({ "color": Color(0.24, 0.24, 0.29, 0.9), "custom_minimum_size": Vector2(0, 1) }), V.Label({ "text": heading, "style": P.section_head() }), (children)])

# component CanvasMarkupRow
static func CanvasMarkupRow(props: Dictionary, children: Array) -> RuitkVNode:
	var row = props.get("row", null)
	var zoom = props.get("zoom", 1.0)
	var P = preload("res://addons/reactive_ui_toolkit_editor/builder/canvas/canvas_palette.gd")
	var M = preload("res://addons/reactive_ui_toolkit_editor/builder/canvas/builder_canvas_metrics.gd")
	var Model = preload("res://addons/reactive_ui_toolkit_editor/builder/canvas/builder_graph.gd")
	var LineKind = Model.LineKind
	var style = P.markup_row()
	if row.kind == LineKind.COMPONENT:
		style = P.component_row()
	elif row.kind == LineKind.DIRECTIVE:
		style = P.directive_row()
	var __cf0 = null
	if row.attrs_text != "" and M.shows_attributes(zoom):
		for __cf0_once in 1:
			__cf0 = V.Label({ "text": row.attrs_text, "style": P.attrs(), "clip_text": true, "text_overrun_behavior": TextServer.OVERRUN_TRIM_ELLIPSIS, "size_flags_horizontal": Control.SIZE_SHRINK_END })
			continue
	return V.HBoxContainer({ "style": {"separation": 6}, "mouse_filter": Control.MOUSE_FILTER_IGNORE }, [V.Label({ "text": "    ".repeat(row.depth) + row.text, "style": style, "clip_text": true, "text_overrun_behavior": TextServer.OVERRUN_TRIM_ELLIPSIS, "size_flags_horizontal": Control.SIZE_EXPAND_FILL }), __cf0])

# component CanvasAddChip
static func CanvasAddChip(props: Dictionary, children: Array) -> RuitkVNode:
	var label = props.get("label", "+")
	var what = props.get("what", "")
	var index = props.get("index", -1)
	var on_add = props.get("on_add", null)
	var P = preload("res://addons/reactive_ui_toolkit_editor/builder/canvas/canvas_palette.gd")
	var target = index
	var kind = what
	var sink = on_add
	return V.Button({ "text": label, "flat": true, "style": P.add_chip(), "onPressed": func(): (sink.call(target, kind) if sink != null else null) })

