// TypeScript port of the .guitkx GDScript-lexis scanner (addons/reactive_ui_toolkit/guitkx/guitkx_lexer.gd).
// Everything that finds balanced regions or extracts embedded-GDScript spans routes through
// skipNoncode first so braces/quotes/comments inside the embedded code never confuse balancing.
// GDScript lexis: `#` line comments; "..."/'...'/triple-quoted strings; r"/&"/^" prefixes; no C#.

export function isIdent(c: string): boolean {
  return c === "_" || (c >= "a" && c <= "z") || (c >= "A" && c <= "Z") || (c >= "0" && c <= "9");
}

/** If `i` sits at a comment or string literal, return the index just past it; else return `i`. */
export function skipNoncode(src: string, i: number): number {
  const n = src.length;
  if (i >= n) return i;
  const c = src[i];
  if (c === "#") {
    let j = i + 1;
    while (j < n && src[j] !== "\n") j++;
    return j;
  }
  // string, with optional one-char prefix r"" / &"" / ^"" / $"" / %"", only at a TOKEN START
  // (not when the char is an operator after a value). Must stay byte-identical with guitkx_lexer.gd.
  let qAt = i;
  if (c === "r" || c === "&" || c === "^" || c === "$" || c === "%") {
    if (i + 1 < n && (src[i + 1] === '"' || src[i + 1] === "'") && (i === 0 || !isValueEnd(src[i - 1]))) qAt = i + 1;
  }
  if (qAt < n && (src[qAt] === '"' || src[qAt] === "'")) return skipString(src, qAt);
  return i;
}

/** True if `c` can end a value/operand, so a following r/&/^/$/% is an operator, not a string prefix. */
function isValueEnd(c: string): boolean {
  return isIdent(c) || c === ")" || c === "]" || c === '"' || c === "'";
}

/** `i` points at a quote. Skip the string (triple-quoted + escapes). Returns index past close. */
export function skipString(src: string, i: number): number {
  const n = src.length;
  const q = src[i];
  if (i + 2 < n && src[i + 1] === q && src[i + 2] === q) {
    let j = i + 3;
    while (j < n) {
      if (src[j] === "\\") {
        j += 2;
        continue;
      }
      if (src[j] === q && j + 2 < n && src[j + 1] === q && src[j + 2] === q) return j + 3;
      j++;
    }
    return n;
  }
  let k = i + 1;
  while (k < n) {
    const ch = src[k];
    if (ch === "\\") {
      k += 2;
      continue;
    }
    if (ch === q) return k + 1;
    if (ch === "\n") return k;
    k++;
  }
  return n;
}

/** Index of the matching close delimiter for the opener at `openI`, skipping noncode; -1 if none. */
export function findMatching(src: string, openI: number): number {
  const n = src.length;
  const stack: string[] = [];
  let i = openI;
  while (i < n) {
    const j = skipNoncode(src, i);
    if (j !== i) {
      i = j;
      continue;
    }
    const c = src[i];
    if (c === "(" || c === "{" || c === "[") {
      stack.push(c);
    } else if (c === ")" || c === "}" || c === "]") {
      if (stack.length === 0) return -1;
      const top = stack.pop()!;
      if ((c === ")" && top !== "(") || (c === "}" && top !== "{") || (c === "]" && top !== "[")) return -1;
      if (stack.length === 0) return i;
    }
    i++;
  }
  return -1;
}

// [G-01 fix] Markup-lexis noncode skip: comments are `//` (to EOL), `/* ... */`, and
// `<!-- ... -->`; `#` is NOT a comment (it is a literal character in markup text, e.g. a color
// literal or a stray "Score #3"). Strings are still "..."/'...' (incl. triple-quoted, escapes) via
// skipString -- no r""/&""/^""/$""/%"" prefix detection, since that is a GDScript-code convention,
// not a markup one. Used by findMatchingMarkup for spans whose content is primarily MARKUP
// (component/directive bodies, the `return ( ... )` window) rather than a GDScript statement.
// Must stay byte-identical with guitkx_lexer.gd skip_noncode_markup.
export function skipNoncodeMarkup(src: string, i: number): number {
  const n = src.length;
  if (i >= n) return i;
  const c = src[i];
  if (c === "/" && i + 1 < n && src[i + 1] === "/") {
    let j = i + 2;
    while (j < n && src[j] !== "\n") j++;
    return j;
  }
  if (c === "/" && i + 1 < n && src[i + 1] === "*") {
    const close = src.indexOf("*/", i + 2);
    return close !== -1 ? close + 2 : n;
  }
  if (c === "<" && i + 3 < n && src[i + 1] === "!" && src[i + 2] === "-" && src[i + 3] === "-") {
    const close = src.indexOf("-->", i + 4);
    return close !== -1 ? close + 3 : n;
  }
  if (c === '"' || c === "'") return skipString(src, i);
  return i;
}

// [G-01 fix] Mode-aware counterpart to findMatching for spans whose content mixes MARKUP with
// embedded GDScript ({expr} attribute/child holes, directive/@case headers, setup/prelude
// statements, `return (...)` windows) -- e.g. a directive body, a component body, or the
// `return ( ... )` window itself. The naive GDScript-lexis findMatching treats a literal `#` in
// markup text (or a markup `//`/`/* */`/`<!-- -->` comment) as GDScript lexis, silently
// miscounting the delimiters it is meant to balance (G-01).
//
// [G-23 fix] Content mode is tracked PER DELIMITER-STACK LEVEL, not globally:
//   - `{` opens a BODY level (component/directive body: GDScript prelude statements mixed with
//     markup) -- including `openI` itself when it is a `{`. Within a BODY level the lexis is
//     LINE-CLASSIFIED (isMarkupLine): a line whose first non-ws char is `<`, `{`, `//`, `/*`,
//     or a directive `@keyword` scans as markup (`#` literal); any other line is GDScript prelude
//     and scans as code (`#` = comment). This is what fixes G-23 -- a `(`/`{` inside a prelude
//     `#`/`##` comment no longer desyncs the stack (previously the prelude was scanned as markup,
//     so the comment's `(` opened a code island whose closing `)` on the NEXT comment line was
//     then comment-skipped -- unclosed forever).
//   - `(` after a bare `return` keyword opens a MARKUP level (the return window) -- including
//     `openI` itself when it is a `(`. MARKUP levels always scan with markup lexis regardless of
//     line shape (`return ( <Label>Score #3</Label> )` on a prelude-classified line keeps `#3`
//     literal). Any other `(` is a directive/@case header and opens a CODE level; `{` not
//     following a header-close/`@else`/`@default` is an `{expr}` island -- CODE as well. A `[`
//     inherits the current level's mode (markup text brackets stay markup; prelude array
//     literals scan as code, so their `#` comments are comments).
//   - CODE levels use ordinary GDScript lexis via skipNoncode all the way down -- real GDScript
//     has no markup/code ambiguity internally. A header/case-value close re-arms "the next `{`
//     is a body".
// (A bare `(` in literal markup text, matching neither keyword, is a pre-existing, out-of-scope
// edge case -- it defaults to a header, the more common construct.)
// Must stay byte-identical with guitkx_lexer.gd find_matching_markup.
const MODE_BODY = 0;
const MODE_MARKUP = 1;
const MODE_CODE = 2;

export function findMatchingMarkup(src: string, openI: number): number {
  const n = src.length;
  const delims: string[] = [src[openI]];
  const modes: number[] = [src[openI] === "{" ? MODE_BODY : MODE_MARKUP];
  let expectBody = false;
  let expectMarkupParen = false;
  // [G-23] Per-line classification state for BODY levels (see docstring).
  let lineStart = src.lastIndexOf("\n", openI) + 1;
  let lineEnd = src.indexOf("\n", openI);
  if (lineEnd === -1) lineEnd = n;
  let lineMarkup = isMarkupLine(src, lineStart, lineEnd);
  let i = openI + 1;
  while (i < n) {
    while (i > lineEnd) {
      lineStart = lineEnd + 1;
      lineEnd = src.indexOf("\n", lineStart);
      if (lineEnd === -1) lineEnd = n;
      lineMarkup = isMarkupLine(src, lineStart, lineEnd);
    }
    const mode = modes[modes.length - 1];
    const inCode = mode === MODE_CODE;
    const markupLexis = mode === MODE_MARKUP || (mode === MODE_BODY && lineMarkup);
    const j = markupLexis ? skipNoncodeMarkup(src, i) : skipNoncode(src, i);
    if (j !== i) {
      i = j;
      continue;
    }
    const c = src[i];
    if (c === " " || c === "\t" || c === "\n" || c === "\r") {
      i++;
      continue;
    }
    if (!inCode) {
      if (c === "@" && keywordAt(src, i + 1, "else")) {
        expectBody = true;
        expectMarkupParen = false;
        i += 5; // "@else"
        continue;
      }
      if (c === "@" && keywordAt(src, i + 1, "default")) {
        expectBody = true;
        expectMarkupParen = false;
        i += 8; // "@default"
        continue;
      }
      if (c === "r" && keywordAt(src, i, "return")) {
        expectMarkupParen = true;
        expectBody = false;
        i += 6; // "return"
        continue;
      }
      if (c === "(") {
        delims.push(c);
        modes.push(expectMarkupParen ? MODE_MARKUP : MODE_CODE);
        expectBody = false;
        expectMarkupParen = false;
        i++;
        continue;
      }
      if (c === "{") {
        delims.push(c);
        modes.push(expectBody ? MODE_BODY : MODE_CODE);
        expectBody = false;
        expectMarkupParen = false;
        i++;
        continue;
      }
      if (c === "[") {
        delims.push(c);
        modes.push(mode); // inherit -- markup text brackets stay markup, prelude arrays stay code
        expectBody = false;
        expectMarkupParen = false;
        i++;
        continue;
      }
      if (c === ")" || c === "}" || c === "]") {
        if (delims.length === 0) return -1;
        const top = delims.pop()!;
        modes.pop();
        if ((c === ")" && top !== "(") || (c === "}" && top !== "{") || (c === "]" && top !== "[")) return -1;
        if (delims.length === 0) return i;
        i++;
        continue;
      }
      expectBody = false;
      expectMarkupParen = false;
      i++;
      continue;
    } else {
      if (c === "(" || c === "{" || c === "[") {
        delims.push(c);
        modes.push(MODE_CODE);
        i++;
        continue;
      }
      if (c === ")" || c === "}" || c === "]") {
        if (delims.length === 0) return -1;
        const top = delims.pop()!;
        modes.pop();
        if ((c === ")" && top !== "(") || (c === "}" && top !== "{") || (c === "]" && top !== "[")) return -1;
        if (delims.length === 0) return i;
        if (modes[modes.length - 1] !== MODE_CODE) expectBody = top === "(";
        i++;
        continue;
      }
      i++;
      continue;
    }
  }
  return -1;
}

// [G-23] Line classification for BODY levels: does this line's content read as markup (elements,
// expr children, markup comments, directives) rather than a GDScript prelude statement? Decided
// by the first non-ws char -- the same convention the compiler's body splitter applies to parts.
// Must stay byte-identical with guitkx_lexer.gd _is_markup_line.
function isMarkupLine(src: string, ls: number, le: number): boolean {
  let k = ls;
  while (k < le) {
    const c = src[k];
    if (c === " " || c === "\t" || c === "\r") {
      k++;
      continue;
    }
    if (c === "<" || c === "{") return true;
    if (c === "/" && k + 1 < le && (src[k + 1] === "/" || src[k + 1] === "*")) return true;
    if (c === "@") {
      return (
        keywordAt(src, k + 1, "if") ||
        keywordAt(src, k + 1, "elif") ||
        keywordAt(src, k + 1, "else") ||
        keywordAt(src, k + 1, "for") ||
        keywordAt(src, k + 1, "while") ||
        keywordAt(src, k + 1, "match") ||
        keywordAt(src, k + 1, "case") ||
        keywordAt(src, k + 1, "default")
      );
    }
    return false;
  }
  return false;
}

/** True if `word` starts at `i` and is bounded by non-identifier chars (a real keyword). */
export function keywordAt(src: string, i: number, word: string): boolean {
  const n = src.length;
  const wl = word.length;
  if (i + wl > n) return false;
  if (src.substr(i, wl) !== word) return false;
  if (i > 0 && isIdent(src[i - 1])) return false;
  if (i + wl < n && isIdent(src[i + wl])) return false;
  return true;
}
