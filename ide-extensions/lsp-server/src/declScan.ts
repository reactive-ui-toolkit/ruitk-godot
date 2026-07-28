// Shared declaration scanning for `.guitkx` — the SINGLE source of truth for locating the
// `component`/`hook`/`module` header, with optional typo-recovery. Used by the formatter's window
// finder (formatGuitkx.ts), the virtual-doc builder (virtualDoc.ts) and the live declaration linter
// (declarations.ts), so all three degrade IDENTICALLY when the header keyword is misspelled.
//
// THE BUG THIS FIXES: markupWindows / buildVirtualDoc keyed off an EXACT keyword, so a single typo like
// `comssponent` produced no window and no virtual doc — the LSP then skipped markup AND embedded
// analysis and the whole file went dark, surfacing only one "unknown declaration" error. With recovery,
// a near-miss keyword at a real declaration position (`<word> <Name> [(...)] {`) is treated as that
// declaration for ANALYSIS, so the file's markup + embedded code keep being checked. Recovery is
// analysis-only: the formatter never recovers, so it can't silently rewrite a user's typo.

import { skipNoncode, findMatching, isIdent, keywordAt } from "./scanner";

export type DeclKind = "component" | "hook" | "module" | "value" | "util" | "export_list" | "export_default";
// The WRAPPER keywords (deprecated since 0.11.0 -- the G-10 window). Plain declarations are
// signature-classified (E-01) and have no keyword; see scanPlainDecl.
export const DECL_KEYWORDS: ("component" | "hook" | "module")[] = ["component", "hook", "module"];

export interface FoundDecl {
  kind: "" | DeclKind;
  at: number; // wrapper: the KEYWORD position; plain: the NAME position; markers: the `export` keyword
  export?: boolean; // whether the declaration carried an `export` visibility prefix
  start?: number; // the declaration's first char (the `export` prefix when present, else `at`)
  deprecated?: boolean; // true = wrapper-keyword form (0.11.0 deprecation window)
  // Plain-declaration fields (E-01; absent on wrapper rows):
  name?: string;
  nameAt?: number;
  params?: string;
  paramsAt?: number;
  ret?: string;
  bodyOpen?: number; // index of the callable body's `{`
  crossGuard?: boolean; // `use_`-prefixed AND `-> RuitkVNode` (GUITKX2321 -- E-02)
  eqStyle?: "plain" | "typed" | "infer"; // value decls
  valueStart?: number; // value decls: index of the initializer's first char
  typeText?: string; // value decls, typed form
  // Marker rows (E-07/E-09):
  listNames?: { name: string; at: number }[];
  listEnd?: number; // index just past the marker span
}

// Bounded Levenshtein (two-row DP). Kept here as the one implementation the recovery + linter share.
export function editDistance(a: string, b: string): number {
  const la = a.length;
  const lb = b.length;
  if (!la) return lb;
  if (!lb) return la;
  let prev = Array.from({ length: lb + 1 }, (_, i) => i);
  for (let x = 1; x <= la; x++) {
    const curr = [x];
    for (let y = 1; y <= lb; y++) {
      const cost = a[x - 1] === b[y - 1] ? 0 : 1;
      curr[y] = Math.min(prev[y] + 1, curr[y - 1] + 1, prev[y - 1] + cost);
    }
    prev = curr;
  }
  return prev[lb];
}

// The declaration keyword `word` most resembles (edit-distance <= 2, length >= 3 to avoid tiny
// coincidences), or null. An exact keyword returns null here — callers match those directly first.
export function nearestDeclKind(word: string): DeclKind | null {
  const w = word.toLowerCase();
  if (w.length < 3) return null;
  let best: DeclKind | null = null;
  let bestD = 3;
  for (const kw of DECL_KEYWORDS) {
    if (w === kw) return null;
    const d = editDistance(w, kw);
    if (d < bestD) {
      bestD = d;
      best = kw;
    }
  }
  return bestD <= 2 ? best : null;
}

// `<Name> [(...)] [-> Type] {` follows offset `i` (whitespace-skipped): the shape of a declaration head.
// Confirms a near-miss keyword really introduces a declaration, so a stray misspelled identifier
// elsewhere is never mistaken for one.
export function looksLikeDecl(src: string, i: number): boolean {
  const n = src.length;
  i = skipWs(src, i);
  if (i >= n || !isIdent(src[i])) return false; // a name must follow
  while (i < n && isIdent(src[i])) i++;
  i = skipWs(src, i);
  if (src[i] === "(") {
    const c = findMatching(src, i);
    if (c === -1) return false;
    i = skipWs(src, c + 1);
  }
  if (src[i] === "-" && src[i + 1] === ">") {
    i += 2;
    while (i < n && src[i] !== "{" && src[i] !== "\n") i++;
  }
  return src[i] === "{";
}

// Signature-only classification of a plain declaration whose NAME starts at `e` (E-01, no body
// inspection — the exact mirror of guitkx.gd _scan_plain_decl). null when the shape doesn't match
// any plain-decl form. Classification order: value forms first (`=`/`: Type =`/`:=` after the
// name); then `-> RuitkVNode` => component; then a `use_` prefix => hook; else => util.
export function scanPlainDecl(src: string, e: number): FoundDecl | null {
  const n = src.length;
  const ns = e;
  let j = e;
  while (j < n && isIdent(src[j])) j++;
  const name = src.slice(ns, j);
  if (name === "") return null;
  const k = skipNoncodeWs(src, j);
  if (src[k] === ":" && src[k + 1] === "=") {
    return { kind: "value", at: e, name, nameAt: ns, eqStyle: "infer", valueStart: k + 2 };
  }
  if (src[k] === ":") {
    const teq = findTypeEq(src, k + 1);
    if (teq === -1) return null;
    return { kind: "value", at: e, name, nameAt: ns, eqStyle: "typed", valueStart: teq + 1, typeText: src.slice(k + 1, teq).trim() };
  }
  if (src[k] === "=" && src[k + 1] !== "=") {
    return { kind: "value", at: e, name, nameAt: ns, eqStyle: "plain", valueStart: k + 1 };
  }
  // --- callable forms: optional `(params)`, optional `-> Type`, required `{` ---
  let params = "";
  let paramsAt = -1;
  let p = k;
  if (src[p] === "(") {
    const pc = findMatching(src, p);
    if (pc === -1) return null;
    params = src.slice(p + 1, pc);
    paramsAt = p + 1;
    p = skipNoncodeWs(src, pc + 1);
  }
  let ret = "";
  if (src[p] === "-" && src[p + 1] === ">") {
    let rp = p + 2;
    const rs = rp;
    while (rp < n && src[rp] !== "{") rp++;
    ret = src.slice(rs, rp).trim();
    p = rp;
  }
  p = skipNoncodeWs(src, p);
  if (p >= n || src[p] !== "{") return null;
  let kind: DeclKind = "util";
  let crossGuard = false;
  if (ret === "RuitkVNode") {
    kind = "component";
    if (name.startsWith("use_")) crossGuard = true;
  } else if (name.startsWith("use_")) {
    kind = "hook";
  }
  return { kind, at: e, name, nameAt: ns, params, paramsAt, ret, bodyOpen: p, crossGuard };
}

// The `=` ending a `: Type` value annotation from `from` (just past the `:`), or -1 before a bare
// newline. Lexer-aware; `==`/`!=`/`<=`/`>=` are not the assignment. Mirror of guitkx.gd _find_type_eq.
function findTypeEq(src: string, from: number): number {
  const n = src.length;
  let i = skipNoncodeWs(src, from);
  while (i < n) {
    const k = skipNoncode(src, i);
    if (k !== i) {
      i = k;
      continue;
    }
    const c = src[i];
    if (c === "(" || c === "{" || c === "[") {
      const close = findMatching(src, i);
      if (close === -1) return -1;
      i = close + 1;
      continue;
    }
    if (c === "\n") return -1;
    if (c === "=") {
      const prev = i > 0 ? src[i - 1] : "";
      const nxt = i + 1 < n ? src[i + 1] : "";
      if (prev !== "!" && prev !== "<" && prev !== ">" && prev !== "=" && nxt !== "=") return i;
    }
    i++;
  }
  return -1;
}

// The next declaration at/after `from`: a WRAPPER keyword (deprecated window), an E-07/E-09 export
// marker, or a plain signature-classified declaration — the exact mirror of guitkx.gd _find_decl.
// `{ kind: "", at: -1 }` when none; `recover` additionally tries typo'd wrapper keywords.
export function findDecl(src: string, from: number, recover = false): FoundDecl {
  const n = src.length;
  let i = from;
  while (i < n) {
    const k = skipNoncode(src, i);
    if (k !== i) {
      i = k;
      continue;
    }
    const start = i;
    let e = i;
    let hasExport = false;
    if (keywordAt(src, i, "export")) {
      hasExport = true;
      e = skipNoncodeWs(src, i + 6);
      // E-09 deferred export list: `export { a, b }`.
      if (src[e] === "{") {
        const lb = findMatching(src, e);
        if (lb !== -1) {
          const listNames: { name: string; at: number }[] = [];
          let lp = e + 1;
          while (lp < lb) {
            lp = skipNoncodeWs(src, lp);
            if (lp >= lb) break;
            if (src[lp] === ",") {
              lp++;
              continue;
            }
            const lns = lp;
            while (lp < lb && isIdent(src[lp])) lp++;
            if (lp === lns) {
              lp++;
              continue;
            }
            listNames.push({ name: src.slice(lns, lp), at: lns });
          }
          return { kind: "export_list", at: i, export: true, start, deprecated: false, listNames, listEnd: lb + 1 };
        }
      }
      // E-07 default marker: `export default Name`.
      if (keywordAt(src, e, "default")) {
        let dn = skipNoncodeWs(src, e + 7);
        const dns = dn;
        while (dn < n && isIdent(src[dn])) dn++;
        return { kind: "export_default", at: i, export: true, start, deprecated: false, name: src.slice(dns, dn), nameAt: dns, listEnd: dn };
      }
    }
    if (keywordAt(src, e, "component")) return { kind: "component", at: e, export: hasExport, start, deprecated: true };
    if (keywordAt(src, e, "hook")) return { kind: "hook", at: e, export: hasExport, start, deprecated: true };
    if (keywordAt(src, e, "module")) return { kind: "module", at: e, export: hasExport, start, deprecated: true };
    // `import` is a reserved top-level keyword (preamble-only) -- never a plain decl's name.
    const atIdentStart = e < n && isIdent(src[e]) && !/[0-9]/.test(src[e]) && (e === 0 || !isIdent(src[e - 1])) && !keywordAt(src, e, "import");
    if (atIdentStart) {
      const plain = scanPlainDecl(src, e);
      if (plain) {
        plain.export = hasExport;
        plain.start = start;
        plain.deprecated = false;
        return plain;
      }
      let skipTo = e;
      while (skipTo < n && isIdent(src[skipTo])) skipTo++;
      i = skipTo;
      continue;
    }
    i++;
  }
  return recover ? recoverDecl(src, from) : { kind: "", at: -1 };
}

// Skip whitespace AND comments/strings (skipNoncode) but keep advancing over interleaved runs — used
// to reach the decl keyword after an `export` prefix (a comment between the two is legal).
function skipNoncodeWs(src: string, i: number): number {
  for (;;) {
    i = skipWs(src, i);
    const k = skipNoncode(src, i);
    if (k === i) return i;
    i = k;
  }
}

function recoverDecl(src: string, from: number): FoundDecl {
  const n = src.length;
  let i = from;
  while (i < n) {
    const k = skipNoncode(src, i);
    if (k !== i) {
      i = k;
      continue;
    }
    if (isIdent(src[i]) && (i === 0 || !isIdent(src[i - 1]))) {
      const s = i;
      while (i < n && isIdent(src[i])) i++;
      const kind = nearestDeclKind(src.slice(s, i));
      if (kind && looksLikeDecl(src, i)) return { kind, at: s };
      continue;
    }
    i++;
  }
  return { kind: "", at: -1 };
}

function skipWs(src: string, i: number): number {
  const n = src.length;
  while (i < n && (src[i] === " " || src[i] === "\t" || src[i] === "\n" || src[i] === "\r")) i++;
  return i;
}

// Index just past a VALUE declaration's initializer (E-04): brace/bracket/paren-matched when it
// opens with one, else end of line (lexer-aware). Mirror of guitkx.gd _value_end.
export function valueEnd(src: string, from: number): number {
  const n = src.length;
  let j = from;
  // Leading ws INCLUDING newlines, mirroring guitkx.gd _skip_ws_only — an initializer opening on
  // the next line still brace-matches (audit Note B: the two sides must agree on this edge).
  while (j < n && (src[j] === " " || src[j] === "\t" || src[j] === "\n" || src[j] === "\r")) j++;
  if (j >= n) return j;
  const c = src[j];
  if (c === "{" || c === "[" || c === "(") {
    const close = findMatching(src, j);
    return close !== -1 ? close + 1 : -1;
  }
  let i = j;
  while (i < n) {
    const k = skipNoncode(src, i);
    if (k !== i) {
      i = k;
      continue;
    }
    if (src[i] === "\n") return i;
    i++;
  }
  return n;
}

// The `{`…matching-`}` body span of a callable declaration row (wrapper OR plain). Plain rows
// carry their own `bodyOpen`; wrapper rows fall back to the keyword-anchored walk (typo-recovery
// safe: `at` may sit on a misspelled keyword). Component bodies use MARKUP lexis (G-01).
export function declBodyOf(src: string, d: FoundDecl, findMatchingMarkupFn: (s: string, i: number) => number): { start: number; close: number } | null {
  const markup = d.kind === "component";
  if (d.deprecated === false && d.bodyOpen !== undefined) {
    const close = markup ? findMatchingMarkupFn(src, d.bodyOpen) : findMatching(src, d.bodyOpen);
    return close === -1 ? null : { start: d.bodyOpen + 1, close };
  }
  const n = src.length;
  let i = d.at;
  while (i < n && isIdent(src[i])) i++; // the (possibly-misspelled) keyword
  i = skipWs2(src, i);
  while (i < n && isIdent(src[i])) i++; // the declaration name
  i = skipWs2(src, i);
  if (src[i] === "(") {
    const pc = findMatching(src, i);
    if (pc === -1) return null;
    i = skipWs2(src, pc + 1);
  }
  if (src[i] === "-" && src[i + 1] === ">") {
    i += 2;
    while (i < n && src[i] !== "{") i++;
  }
  if (src[i] !== "{") return null;
  const close = markup ? findMatchingMarkupFn(src, i) : findMatching(src, i);
  return close === -1 ? null : { start: i + 1, close };
}

function skipWs2(src: string, i: number): number {
  const n = src.length;
  while (i < n && (src[i] === " " || src[i] === "\t" || src[i] === "\n" || src[i] === "\r")) i++;
  return i;
}

// Index just past a declaration row of ANY kind (the walk-advance mirror of _enumerate_decls'
// `next`), or -1 when the extent can't be determined (unterminated body).
export function declSpanEnd(src: string, d: FoundDecl, findMatchingMarkupFn: (s: string, i: number) => number): number {
  if (d.kind === "value") return d.valueStart !== undefined ? valueEnd(src, d.valueStart) : -1;
  if (d.kind === "export_list" || d.kind === "export_default") return d.listEnd ?? -1;
  const b = declBodyOf(src, d, findMatchingMarkupFn);
  return b ? b.close + 1 : -1;
}
