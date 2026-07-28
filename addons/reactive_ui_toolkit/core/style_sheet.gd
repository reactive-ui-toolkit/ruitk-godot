class_name RUIStyleSheet
extends RefCounted
## A tiny userland "stylesheet" registry (Phase 7.11) — the reduced-scope analog of UITKX's USS
## classes (decision #3). It maps a class name to a plain style Dictionary (the same shape RUIStyle
## consumes). A host element's `classes: ["card", "primary"]` prop is resolved against this registry
## at apply time and merged left-to-right, with the element's inline `style` winning last.
##
## Deliberately NOT a CSS engine: there is no selector matching, specificity, cascade, or
## inheritance — just an ordered dictionary merge. For real theming, use Godot's Theme/StyleBox
## (via `style`) or `theme_type_variation`; this is sugar for sharing named style bundles.
##
##   RUIStyleSheet.register("card", { "bg_color": Color(0.15,0.15,0.18), "corner_radius_all": 8, "content_margin_all": 12 })
##   RUIStyleSheet.merge({ "danger": { "font_color": Color.RED }, "muted": { "font_color": Color.GRAY } })
##   V.PanelContainer({ "classes": ["card", "danger"], "style": { "content_margin_all": 16 } }, [...])   # overrides card

static var _sheets: Dictionary = {}

## Register (or replace) the style bundle for a single class name.
static func register(name: String, style: Dictionary) -> void:
	_sheets[name] = style

## Bulk-register a { name -> style } map (later keys overwrite earlier ones).
static func merge(map: Dictionary) -> void:
	for k in map:
		_sheets[str(k)] = map[k]

## The style Dictionary registered for `name`, or null if none.
static func resolve(name: String):
	return _sheets.get(name)

static func has(name: String) -> bool:
	return _sheets.has(name)

static func names() -> Array:
	return _sheets.keys()

static func clear() -> void:
	_sheets.clear()
