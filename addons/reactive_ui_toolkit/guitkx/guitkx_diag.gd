class_name RUIGuitkxDiag
extends RefCounted
## Structured diagnostics for the .guitkx compiler (SYNTAX_PARITY_EXECUTION_PLAN T0.2). ONE shape
## everywhere: { code, severity, message, offset, length } where `offset`/`length` are CHARACTER
## positions into the ORIGINAL .guitkx source (offset -1 = "whole file"; surfaces fall back to the
## top of the file). Severity is compiler-domain (ERROR/WARNING/HINT) and each surface maps it
## (push_error vs push_warning, LSP DiagnosticSeverity, gutter icon). Line/col are NOT stored --
## they are derived at the surface via line_col(), so they can never drift from the offset.
##
## `message` holds the human text WITHOUT the code prefix; format() is the single canonical
## renderer every GD surface shares ("path:LINE:COL: CODE (warning): message", 1-based).

const ERROR := 0
const WARNING := 1
const HINT := 2

static func make(code: String, severity: int, message: String, offset: int = -1, length: int = 0) -> Dictionary:
	return { "code": code, "severity": severity, "message": message, "offset": offset, "length": maxi(0, length) }

static func is_error(d) -> bool:
	return d is Dictionary and int((d as Dictionary).get("severity", ERROR)) == ERROR

static func has_error(diags: Array) -> bool:
	for d in diags:
		if is_error(d):
			return true
	return false

static func severity_name(severity: int) -> String:
	match severity:
		WARNING:
			return "warning"
		HINT:
			return "hint"
		_:
			return "error"

## Shift a body-relative diagnostic to a source-absolute one (no-op for offset -1 / negative base).
static func rebase(d: Dictionary, base: int) -> Dictionary:
	if base >= 0 and int(d.get("offset", -1)) >= 0:
		d["offset"] = int(d["offset"]) + base
	return d

## 0-based { line, col } of a character offset in `source` (clamped to the source).
static func line_col(source: String, offset: int) -> Dictionary:
	var line := 0
	var col := 0
	var lim := clampi(offset, 0, source.length())
	for i in lim:
		if source[i] == "\n":
			line += 1
			col = 0
		else:
			col += 1
	return { "line": line, "col": col }

## Canonical one-line rendering. With `source`, positions render 1-based ("3:14: "); `path` prefixes.
static func format(d: Dictionary, source: String = "", path: String = "") -> String:
	var loc := ""
	var off := int(d.get("offset", -1))
	if source != "" and off >= 0:
		var lc := line_col(source, off)
		loc = "%d:%d" % [int(lc["line"]) + 1, int(lc["col"]) + 1]
	var prefix := ""
	if path != "" and loc != "":
		prefix = "%s:%s: " % [path, loc]
	elif path != "":
		prefix = "%s: " % path
	elif loc != "":
		prefix = "%s: " % loc
	var sev := int(d.get("severity", ERROR))
	var sev_tag := "" if sev == ERROR else " (%s)" % severity_name(sev)
	return "%s%s%s: %s" % [prefix, str(d.get("code", "")), sev_tag, str(d.get("message", ""))]
