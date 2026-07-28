@tool
class_name GuitkxLineIndex
extends RefCounted
## The byte↔character boundary between GDScript strings and the native analyzer
## (parity plan §8 risk #1: "a LineIndex-equivalent must be ported to GDScript and used at EVERY
## boundary or diagnostics/completions mis-anchor").
##
## GDScript `String` indexes by UNICODE CODE POINT (so does CodeEdit's caret column — verified
## empirically by the headless probe in tests/guitkx_editor_test.gd); the analyzer speaks UTF-8
## BYTE offsets (half-open ranges, 0-based lines). These converters are deliberately stateless
## statics over the text: editor queries are one conversion per keystroke on ≤150K documents,
## where a substr+utf8 walk is microseconds — no cache to invalidate, nothing to go stale.

## UTF-8 byte offset of character offset `char_off` in `text` (clamped to [0, byte length]).
static func char_to_byte(text: String, char_off: int) -> int:
	if char_off <= 0:
		return 0
	if char_off >= text.length():
		return text.to_utf8_buffer().size()
	return text.substr(0, char_off).to_utf8_buffer().size()

## Character offset of UTF-8 byte offset `byte_off` in `text`. A byte offset INSIDE a multi-byte
## character resolves to that character's index (analyzer ranges always land on boundaries; this
## is a safety clamp, not an expected path).
static func byte_to_char(text: String, byte_off: int) -> int:
	if byte_off <= 0:
		return 0
	var buf := text.to_utf8_buffer()
	if byte_off >= buf.size():
		return text.length()
	var chars := 0
	var i := 0
	while i < byte_off:
		var b := buf[i]
		var step := 1
		if b >= 0xF0:
			step = 4
		elif b >= 0xE0:
			step = 3
		elif b >= 0xC0:
			step = 2
		if i + step > byte_off:
			break  # byte_off points inside this character
		i += step
		chars += 1
	return chars
