@tool
class_name GuitkxHover
extends RefCounted
## Pure hover-text provider for `.guitkx` markup: given a caret over a tag / attribute / directive,
## returns Markdown describing it (Godot class, property/signal type, directive form). Reuses the
## GuitkxSchema hover builders + GuitkxWorkspace index; UI-free so it is unit-testable headlessly.
## Embedded-GDScript hover is left to the analyzer layer (Phase 4). [Phase 1]

## Curated cards for the built-in hooks (port of the VS Code server's HOOK_HOVER, BUG-V8 —
## signatures mirror core/hooks.gd). Hovering `useState` in a setup line answers with the real
## signature instead of nothing.
const HOOKS := {
	"useState": "**useState**(initial = null) → `[value, setter]`\n\nReactive state: read `s[0]`, set with `s[1].call(v)` (a value or an updater func).",
	"useReducer": "**useReducer**(reducer: Callable, initial = null) → `[state, dispatch]`",
	"useRef": "**useRef**(initial = null) → `{ current }`\n\nA mutable box that persists across renders (setting it does not re-render).",
	"useMemo": "**useMemo**(factory: Callable, deps = []) → value\n\nMemoized value; recomputes only when `deps` change.",
	"useCallback": "**useCallback**(cb: Callable, deps = []) → `Callable`",
	"useImperativeHandle": "**useImperativeHandle**(factory: Callable, deps = [])",
	"useEffect": "**useEffect**(effect: Callable, deps = null)\n\nRun a side effect after commit; return a Callable to clean up. `deps = []` runs once on mount.",
	"useLayoutEffect": "**useLayoutEffect**(effect: Callable, deps = null)\n\nLike `useEffect` but runs synchronously after layout.",
	"createContext": "**createContext**(default = null, name = \"\") → `RUIContext`\n\nA context handle for `provideContext` / `useContext` (object identity — no string-key collisions).",
	"useContext": "**useContext**(key) → value\n\nRead the nearest provided value for a context handle (or string key).",
	"provideContext": "**provideContext**(key, value)\n\nProvide a context value to the subtree below.",
	"useDeferredValue": "**useDeferredValue**(value, deps = null)",
	"useTransition": "**useTransition**() → `[is_pending, start]`",
	"useStableCallback": "**useStableCallback**(cb: Callable) → `Callable`\n\nA stable Callable identity that always invokes the latest `cb`.",
	"useStableFunc": "**useStableFunc**(cb: Callable) → `Callable`",
	"useStableAction": "**useStableAction**(cb: Callable) → `Callable`",
	"useSafeArea": "**useSafeArea**() → `Dictionary`",
	"useSignal": "**useSignal**(sig: RUISignal, selector = null, comparer = null)",
	"useSignalKey": "**useSignalKey**(key: String, initial = null, selector = null, comparer = null)",
	"useTween": "**useTween**(ref, property: String, to, duration: float, deps = [])",
	"useTweenValue": "**useTweenValue**(from, to, duration: float, on_update: Callable, deps = [])",
	"useAnimate": "**useAnimate**(ref, tracks: Array, autoplay = true, deps = [])",
	"useSfx": "**useSfx**(bus = \"Master\") → `Callable`",
}

## Markdown hover for the identifier under char `offset` in `text`, or "" if nothing to say.
static func for_caret(text: String, offset: int) -> String:
	var word := word_at(text, offset)
	if word == "":
		return ""
	if HOOKS.has(word):
		return HOOKS[word]
	var start := _word_start(text, offset)
	var ctx := GuitkxContext.classify(text, start)
	match ctx["kind"]:
		GuitkxContext.KIND_TAG, GuitkxContext.KIND_MARKUP:
			return _tag_hover(word)
		GuitkxContext.KIND_ATTR:
			var h := GuitkxSchema.hover_for_attribute(str(ctx["tag"]), word)
			return h
		GuitkxContext.KIND_DIRECTIVE:
			return GuitkxSchema.hover_for_directive("@" + word)
	# Fallback: the word is a bare tag/component identifier somewhere the classifier read as markup.
	return _tag_hover(word)

## Convert our Markdown subset (**bold**, `code`, newlines) to RichTextLabel BBCode, escaping
## any literal `[` so user text can't inject tags.
static func md_to_bbcode(md: String) -> String:
	var s := md.replace("[", "[lb]")
	var out := ""
	var bold := false
	var code := false
	var i := 0
	while i < s.length():
		if s.substr(i, 2) == "**":
			out += "[/b]" if bold else "[b]"
			bold = not bold
			i += 2
			continue
		if s[i] == "`":
			out += "[/code]" if code else "[code]"
			code = not code
			i += 1
			continue
		out += s[i]
		i += 1
	if bold:
		out += "[/b]"
	if code:
		out += "[/code]"
	return out

static func _tag_hover(word: String) -> String:
	if GuitkxSchema.is_host_tag(word):
		return GuitkxSchema.hover_for_tag(word)
	if GuitkxWorkspace.is_component(word):
		var e := GuitkxWorkspace.lookup(word)
		# M7.1 kind-aware hover: kind + export/default badges from the declaring file's decl
		# table (cached per source hash -- RUIGuitkxResolve.decl_table).
		var badge := "user component"
		var epath := str(e.get("path", ""))
		if epath != "":
			var tbl: Dictionary = RUIGuitkxResolve.decl_table(epath)
			var dd = (tbl["decls"] as Dictionary).get(str(e.get("name", word)))
			if dd is Dictionary:
				badge = "user %s" % str((dd as Dictionary)["kind"])
				if bool((dd as Dictionary)["export"]):
					badge += ", exported"
			if str(tbl.get("default", "")) == str(e.get("name", word)):
				badge += ", default export"
		return "**`<%s>`** — %s (`%s`). Ctrl-click to open its declaration." % [word, badge, epath.get_file()]
	return ""

## The full identifier spanning `offset` (expands both directions over identifier chars).
static func word_at(text: String, offset: int) -> String:
	var s := _word_start(text, offset)
	var e := offset
	while e < text.length() and _is_ident(text.unicode_at(e)):
		e += 1
	return text.substr(s, e - s)

static func _word_start(text: String, offset: int) -> int:
	var i := clampi(offset, 0, text.length())
	while i > 0 and _is_ident(text.unicode_at(i - 1)):
		i -= 1
	return i

static func _is_ident(c: int) -> bool:
	return c == 95 or (c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122)
