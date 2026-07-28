@tool
class_name GuitkxSourceMap
extends RefCounted
## Bidirectional, offset-based source map between a .guitkx document and the synthetic .gd
## "virtual document" handed to the native analyzer (GdscriptAnalyzer). Each span is
## length-preserving: embedded GDScript text (a {expr}, a setup line, an @if condition) is spliced
## into the virtual doc VERBATIM, so an offset inside a mapped span translates by a constant
## delta. Port of the TS server's sourceMap.ts (ide-extensions/lsp-server) — the third
## implementation of the same contract (Unity SourceMap.cs, sourceMap.ts, this).
##
## Offsets here are CHARACTER offsets in both documents (GDScript String indexing); the analyzer
## boundary converts to UTF-8 bytes via GuitkxLineIndex at the call site.

# Each span: Vector3i(source_start, gen_start, length).
var _spans: Array[Vector3i] = []

## Record that source[source_start .. +length] was copied verbatim to gen[gen_start .. +length].
func add_span(source_start: int, gen_start: int, length: int) -> void:
	if length <= 0:
		return
	_spans.append(Vector3i(source_start, gen_start, length))

## Map a .guitkx offset to the generated .gd offset, or -1 if not inside any embedded span.
## (TS returns null; GDScript uses -1 — every caller treats < 0 as unmapped.)
func to_generated(source_offset: int) -> int:
	for s in _spans:
		if source_offset >= s.x and source_offset <= s.x + s.z:
			return s.y + (source_offset - s.x)
	return -1

## Map a generated .gd offset back to the .guitkx offset, or -1 if it lands in glue code.
func to_source(gen_offset: int) -> int:
	for s in _spans:
		if gen_offset >= s.y and gen_offset <= s.y + s.z:
			return s.x + (gen_offset - s.y)
	return -1

func span_count() -> int:
	return _spans.size()
