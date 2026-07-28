// T5.1: byte-discipline port of addons/reactive_ui_toolkit/guitkx/guitkx_jsx_scan.gd — same function and
// variable names, same boundary set (incl. T3.5's `or`), same {end:-1} unbalanced contract. Finds
// markup nested INSIDE an embedded GDScript expression (`cond if c else <A/>`, `is_open and
// <Panel/>`, `items.map(func(it): return <Row/>)`). Change BOTH files or neither.
//
// The hard problem is telling a markup `<` from a less-than operator. Like uitkx we DON'T do general
// disambiguation — a POSITION-GATED whitelist: a `<` begins markup ONLY when it follows
// (whitespace-skipped) a boundary token that can only be followed by an expression, AND the char
// after `<` is a tag-name start (letter/`_`) or `>` (fragment).

import { skipNoncode, skipNoncodeMarkup, findMatching, keywordAt, isIdent } from "./scanner";

export interface MarkupRange {
  start: number;
  end: number; // -1 = unbalanced: markup opens but never closes (owns the rest of the expression)
  op: string; // "" | "and" | "&&" | "or"
  op_pos: number;
}

export function findMarkupRanges(src: string, start: number, end: number): MarkupRange[] {
  const out: MarkupRange[] = [];
  const delim: string[] = []; // ( [ { stack, for the dict-`:` rule
  let i = start;
  // markup at the very start of the expression (e.g. an attr value that IS markup)
  const s0 = skipWs(src, start, end);
  if (markupAt(src, s0, end)) {
    const e0 = findElementEnd(src, s0, end);
    if (e0 === -1) return [{ start: s0, end: -1, op: "", op_pos: start }];
    out.push({ start: s0, end: e0, op: "", op_pos: start });
    i = e0;
  }
  while (i < end) {
    const j = skipNoncode(src, i);
    if (j !== i) {
      i = j;
      continue;
    }
    const c = src[i];
    if (c === "(" || c === "[") {
      delim.push(c);
      i = tryAt(src, i + 1, end, "", i, out, i + 1);
      continue;
    }
    if (c === "{") {
      delim.push(c);
      i += 1;
      continue;
    }
    if (c === ")" || c === "]" || c === "}") {
      if (delim.length) delim.pop();
      i += 1;
      continue;
    }
    if (c === ",") {
      i = tryAt(src, i + 1, end, "", i, out, i + 1);
      continue;
    }
    if (c === "=" && isSimpleAssign(src, i, end)) {
      i = tryAt(src, i + 1, end, "", i, out, i + 1);
      continue;
    }
    if (c === "&" && i + 1 < end && src[i + 1] === "&") {
      i = tryAt(src, i + 2, end, "&&", i, out, i + 2);
      continue;
    }
    if (c === ":" && delim.length && delim[delim.length - 1] === "{" && !isColonOp(src, i, end)) {
      i = tryAt(src, i + 1, end, "", i, out, i + 1);
      continue;
    }
    if ((c === "r" || c === "e" || c === "a" || c === "o") && isIdentBoundary(src, i)) {
      // keyword boundaries: return / else / and / or (T3.5 mirrors Unity's operator set)
      if (keywordAt(src, i, "return")) {
        i = tryAt(src, i + 6, end, "", i, out, i + 6);
        continue;
      }
      if (keywordAt(src, i, "else")) {
        i = tryAt(src, i + 4, end, "", i, out, i + 4);
        continue;
      }
      if (keywordAt(src, i, "and")) {
        i = tryAt(src, i + 3, end, "and", i, out, i + 3);
        continue;
      }
      if (keywordAt(src, i, "or")) {
        i = tryAt(src, i + 2, end, "or", i, out, i + 2);
        continue;
      }
    }
    i += 1;
  }
  return out;
}

// Peek for markup at the next ws-skipped position; if found, record [p, elem_end) (with the boundary
// op + its position) and return elem_end so the caller jumps past it. Markup that never closes is
// recorded as { end: -1 } and ends the scan. Otherwise return `fallback` (advance by one token).
function tryAt(src: string, after: number, end: number, op: string, opPos: number, out: MarkupRange[], fallback: number): number {
  const p = skipWs(src, after, end);
  if (markupAt(src, p, end)) {
    const e = findElementEnd(src, p, end);
    if (e === -1) {
      out.push({ start: p, end: -1, op, op_pos: opPos });
      return end;
    }
    out.push({ start: p, end: e, op, op_pos: opPos });
    return e;
  }
  return fallback;
}

export function markupAt(src: string, i: number, end: number): boolean {
  if (i >= end || src[i] !== "<") return false;
  if (i + 1 >= end) return false;
  const c = src[i + 1];
  return c === ">" || c === "_" || (c >= "a" && c <= "z") || (c >= "A" && c <= "Z");
}

// From a `<` at `open`, the index just past the outermost element close. Tracks tag depth, routing
// strings/comments + balanced `{…}` attribute/child holes through the lexer. -1 if unbalanced.
// Exported for Phase C: splitReturnEx bounds a bare early `return <Tag/>`'s markup window with it.
export function findElementEnd(src: string, open: number, end: number): number {
  let depth = 0;
  let i = open;
  while (i < end) {
    // G-01: walks tag names/text/attributes -- markup lexis, so `#` in child text stays literal
    // and `//`/`/* */`/`<!-- -->` are comments. `{…}` holes still route through findMatching below.
    const j = skipNoncodeMarkup(src, i);
    if (j !== i) {
      i = j;
      continue;
    }
    const c = src[i];
    if (c === "{") {
      const close = findMatching(src, i); // skip an attr/child {…} hole whole
      if (close === -1 || close >= end) return -1;
      i = close + 1;
      continue;
    }
    if (c === "<") {
      if (i + 1 < end && src[i + 1] === "/") {
        depth -= 1;
        const gt = src.indexOf(">", i);
        if (gt === -1 || gt >= end) return -1;
        i = gt + 1;
        if (depth === 0) return i;
        continue;
      }
      if (i + 1 < end && src[i + 1] === ">") {
        depth += 1; // fragment open <>
        i += 2;
        continue;
      }
      if (markupAt(src, i, end)) {
        const t = scanOpenTag(src, i, end);
        if (t.gt === -1) return -1;
        i = t.gt + 1;
        if (t.selfClosing) {
          if (depth === 0) return i;
        } else depth += 1;
        continue;
      }
    }
    i += 1;
  }
  return -1;
}

// Scan an opening tag from its `<` to its terminating `>` / `/>`, treating every attribute `{…}`
// hole and quoted string as opaque.
function scanOpenTag(src: string, lt: number, end: number): { gt: number; selfClosing: boolean } {
  let i = lt + 1;
  while (i < end && isIdent(src[i])) i += 1; // tag name
  while (i < end) {
    // G-01: markup lexis over the attribute list (see findElementEnd).
    const j = skipNoncodeMarkup(src, i);
    if (j !== i) {
      i = j;
      continue;
    }
    const c = src[i];
    if (c === "{") {
      const close = findMatching(src, i);
      if (close === -1 || close >= end) return { gt: -1, selfClosing: false };
      i = close + 1;
      continue;
    }
    if (c === "/" && i + 1 < end && src[i + 1] === ">") return { gt: i + 1, selfClosing: true };
    if (c === ">") return { gt: i, selfClosing: false };
    i += 1;
  }
  return { gt: -1, selfClosing: false };
}

// --- token helpers ---
function skipWs(src: string, i: number, end: number): number {
  while (i < end && (src[i] === " " || src[i] === "\t" || src[i] === "\n" || src[i] === "\r")) i += 1;
  return i;
}

function isIdentBoundary(src: string, i: number): boolean {
  return i === 0 || !isIdent(src[i - 1]);
}

// A `=` is a simple assignment (not ==, <=, >=, !=, :=, +=, -=, *=, /=, %=, &=, |=, ^=).
function isSimpleAssign(src: string, i: number, end: number): boolean {
  if (i + 1 < end && src[i + 1] === "=") return false;
  if (i === 0) return true;
  const p = src[i - 1];
  return !(p === "=" || p === "!" || p === "<" || p === ">" || p === ":" || p === "+" || p === "-" || p === "*" || p === "/" || p === "%" || p === "&" || p === "|" || p === "^");
}

// A `:` that is `::` or `:=` is an operator, not a dict separator.
function isColonOp(src: string, i: number, end: number): boolean {
  if (i + 1 < end && (src[i + 1] === ":" || src[i + 1] === "=")) return true;
  if (i > 0 && src[i - 1] === ":") return true;
  return false;
}

// T5.1: neutralize nested markup inside an expression for the ANALYZER, length-preservingly --
// each markup range becomes `null` padded with spaces to the exact original length, so the
// virtual-doc's 1:1 offset map still round-trips. `<A/>` is the 4-char minimum, so `null` always fits.
export function neutralizeMarkup(expr: string): string {
  const ranges = findMarkupRanges(expr, 0, expr.length);
  if (ranges.length === 0) return expr;
  let out = "";
  let prev = 0;
  for (const r of ranges) {
    if (r.start < prev) continue; // nested inside an already-replaced range
    const re = r.end === -1 ? expr.length : r.end;
    out += expr.slice(prev, r.start);
    out += ("null" + " ".repeat(Math.max(0, re - r.start - 4))).slice(0, re - r.start);
    prev = re;
  }
  out += expr.slice(prev);
  return out;
}

// A2 (0.6.0 field regression): neutralize markup anywhere in a SETUP block — an early/demoted
// markup return (`return <s></a>` before the final markup return) or a markup value. Length- AND
// newline-preserving, unlike neutralizeMarkup, because virtualDoc splices setup verbatim with a
// per-line source map: every `\n` byte survives, every other byte in a markup range becomes a
// space, and `null` lands on the first line segment of the range wide enough to hold it. A
// neutralized `return <s></a>` therefore reads `return null` — real GDScript, and an unconditional
// early return keeps its parity-correct unreachable-after-return signal (Unity dims the same way).
export function neutralizeSetupMarkup(block: string): string {
  const ranges = findMarkupRanges(block, 0, block.length);
  if (ranges.length === 0) return block;
  const out = block.split("");
  let prev = 0;
  for (const r of ranges) {
    if (r.start < prev) continue;
    const re = r.end === -1 ? block.length : r.end;
    let placed = false;
    let i = r.start;
    while (i < re) {
      let segEnd = block.indexOf("\n", i);
      if (segEnd === -1 || segEnd > re) segEnd = re;
      for (let k = i; k < segEnd; k++) out[k] = " ";
      if (!placed && segEnd - i >= 4) {
        out[i] = "n";
        out[i + 1] = "u";
        out[i + 2] = "l";
        out[i + 3] = "l";
        placed = true;
      }
      i = segEnd + 1;
    }
    prev = re;
  }
  return out.join("");
}
