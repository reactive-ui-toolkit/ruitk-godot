// Faithful TypeScript port of addons/reactive_ui_toolkit/guitkx/guitkx_markup.gd (the markup recursive-descent
// parser). It MUST produce node shapes byte-identical to the GDScript parser; the in-process formatter
// (formatGuitkx.ts) re-emits from this AST, kept identical to guitkx_formatter.gd via a shared golden
// fixture corpus asserted on both sides (the same discipline as scanner.ts === guitkx_lexer.gd). Built
// only on scanner.ts primitives — no second lexer.
//
// POSITIONS (T0.2): every node carries `at` — the character offset of its first character in the `src`
// string given to parseMarkup(). Extracted-substring fields carry a companion offset into the SAME
// `src`: attr `vat` (value text start; -1 for bool), expr `vat` (code start), control-flow
// `body_at`/`else_body_at`/`default_body_at` (body text start; -1 when absent), attr `end` (one past
// the attribute's last character). Offsets compose: a consumer re-parsing a `body_markup` substring
// rebases the nested offsets by adding the node's `body_at`. Parse errors carry `error_at` the same
// way. This file and guitkx_markup.gd are line-for-line mirrors — change BOTH or neither.
//
// Node shapes (the `t` tag discriminates), matching guitkx_markup.gd:
//   { t:"el",    at, tag, attrs:[{name,kind,value,at,vat,end}], children, line }   kind: "str"|"expr"|"bool"|"spread"
//   { t:"frag",  at, children }
//   { t:"text",  at, value }
//   { t:"expr",  at, vat, code }
//   { t:"if",    at, branches:[{cond, body_markup, body_at}], else_body, else_body_at }
//   { t:"for",   at, header, body_markup, body_at }
//   { t:"while", at, header, body_markup, body_at }
//   { t:"match", at, subject, cases:[{value, body_markup, body_at}], default_body, default_body_at }

import { skipString, findMatching, findMatchingMarkup, keywordAt } from "./scanner";

export interface Attr {
  name: string;
  kind: "str" | "expr" | "bool" | "spread" | "comment";
  value: string;
  at: number;
  vat: number;
  end: number;
}
export type MarkupNode =
  | { t: "el"; at: number; tag: string; attrs: Attr[]; children: MarkupNode[]; line: number }
  | { t: "frag"; at: number; children: MarkupNode[]; named?: string; attrs?: Attr[] }
  | { t: "text"; at: number; value: string }
  | { t: "expr"; at: number; vat: number; code: string }
  | { t: "comment"; at: number; raw: string }
  | { t: "if"; at: number; branches: { cond: string; body_markup: string; body_at: number }[]; else_body: string | null; else_body_at: number }
  | { t: "for"; at: number; header: string; body_markup: string; body_at: number }
  | { t: "while"; at: number; header: string; body_markup: string; body_at: number }
  | { t: "match"; at: number; subject: string; cases: { value: string; body_markup: string; body_at: number }[]; default_body: string | null; default_body_at: number };

export interface ParseResult {
  nodes: MarkupNode[];
  error: string; // legacy "CODE: message" string ("" when clean)
  error_code: string;
  error_msg: string;
  error_at: number; // offset into `src`, -1 when clean
}

export function parseMarkup(src: string, start: number, end: number): ParseResult {
  return new MarkupParser(src).parse(start, end);
}

class MarkupParser {
  private src: string;
  private err = "";
  private errCode = "";
  private errMsg = "";
  private errAt = -1;
  // [G-08] Line-start offsets of src (entry k = index where line k begins; entry 0 = 0), built
  // lazily on first lineOf() so lineOf is a binary search instead of an O(idx) scan per element.
  private lineStarts: number[] | null = null;
  constructor(src: string) {
    this.src = src;
  }

  parse(start: number, end: number): ParseResult {
    this.err = "";
    this.errCode = "";
    this.errMsg = "";
    this.errAt = -1;
    const r = this.parseNodes(start, end);
    return { nodes: r.nodes, error: this.err, error_code: this.errCode, error_msg: this.errMsg, error_at: this.errAt };
  }

  private fail(code: string, msg: string, at: number): void {
    this.errCode = code;
    this.errMsg = msg;
    this.err = `${code}: ${msg}`;
    this.errAt = at;
  }

  // Returns { nodes, next } where `next` is where parsing stopped — on an unconsumed `</` (close tag
  // belongs to the caller) or at `end`. The caller locates the close tag from `next` with no weaker
  // second walk (which a `<`/`>` inside an embedded {expr} could fool).
  private parseNodes(start: number, end: number): { nodes: MarkupNode[]; next: number } {
    const nodes: MarkupNode[] = [];
    let i = start;
    while (i < end && this.err === "") {
      i = this.skipWs(i, end);
      if (i >= end) break;
      const c = this.src[i];
      if (c === "<") {
        // T2.1: `<!-- ... -->` comment (checked before `</` -- both start with `<`).
        if (i + 3 < end && this.src.slice(i, i + 4) === "<!--") {
          const hce = this.src.indexOf("-->", i + 4);
          if (hce === -1 || hce + 3 > end) {
            this.fail("GUITKX0304", "unclosed `<!--` comment", i);
            break;
          }
          nodes.push({ t: "comment", at: i, raw: this.src.slice(i, hce + 3) });
          i = hce + 3;
          continue;
        }
        if (i + 1 < end && this.src[i + 1] === "/") break; // closing tag belongs to the caller
        const r = this.parseElement(i, end);
        if (this.err !== "") break;
        nodes.push(r.node!);
        i = r.next;
      } else if (c === "/" && i + 1 < end && (this.src[i + 1] === "/" || this.src[i + 1] === "*")) {
        // T2.1: `// line` / `/* block */` comments at node-start position only -- a `//` inside an
        // ongoing text run (e.g. a URL) stays text because parseText never stops at `/`.
        if (this.src[i + 1] === "/") {
          const le = this.src.indexOf("\n", i);
          const stop = le === -1 || le > end ? end : le;
          nodes.push({ t: "comment", at: i, raw: this.src.slice(i, stop) });
          i = stop;
        } else {
          const bce = this.src.indexOf("*/", i + 2);
          if (bce === -1 || bce + 2 > end) {
            this.fail("GUITKX0304", "unclosed `/*` comment", i);
            break;
          }
          nodes.push({ t: "comment", at: i, raw: this.src.slice(i, bce + 2) });
          i = bce + 2;
        }
      } else if (c === "@") {
        const r = this.parseDirective(i, end);
        if (this.err !== "") break;
        nodes.push(r.node!);
        i = r.next;
      } else if (c === "{") {
        const close = findMatching(this.src, i);
        if (close === -1 || close >= end) {
          this.fail("GUITKX0304", "unclosed `{` expression", i);
          break;
        }
        const code = this.src.slice(i + 1, close).trim();
        nodes.push({ t: "expr", at: i, vat: this.skipWs(i + 1, close), code });
        i = close + 1;
      } else {
        const r = this.parseText(i, end);
        if (r.node !== null) nodes.push(r.node);
        i = r.next;
      }
    }
    return { nodes, next: i };
  }

  private parseElement(openI: number, end: number): { node: MarkupNode | null; next: number } {
    let i = openI + 1;
    const line = this.lineOf(openI);
    const nameStart = i;
    while (i < end && isTagChar(this.src[i])) i++;
    const tag = this.src.slice(nameStart, i);
    // A `<` must be directly followed by a tag name, or `>` for a fragment. Whitespace/other after `<`
    // is an invalid/empty tag name (not a silent fragment). [BUG-V4] (mirror of guitkx_markup.gd)
    if (tag === "" && (i >= end || this.src[i] !== ">")) {
      this.fail("GUITKX0300", "invalid tag name -- `<` must be followed by a tag name, or `<>` for a fragment", openI);
      return { node: null, next: end };
    }
    // T3.5: a tag cannot start with a digit (`<9foo/>` used to parse and emit a nonsense call).
    if (tag !== "" && tag[0] >= "0" && tag[0] <= "9") {
      this.fail("GUITKX0300", `tag name cannot start with a digit (<${tag}>)`, openI);
      return { node: null, next: end };
    }
    const attrs: Attr[] = [];
    while (i < end) {
      i = this.skipWs(i, end);
      if (i >= end) {
        this.fail("GUITKX0303", `unexpected EOF in <${tag}>`, openI);
        return { node: null, next: end };
      }
      const c = this.src[i];
      if (c === "/" && i + 1 < end && this.src[i + 1] === ">") {
        return { node: this.mkEl(tag, attrs, [], line, openI), next: i + 2 };
      }
      if (c === ">") {
        i += 1;
        break;
      }
      const ar = this.parseAttribute(i, end);
      if (this.err !== "") return { node: null, next: end };
      attrs.push(ar.attr!);
      i = ar.next;
    }
    const cr = this.parseNodes(i, end);
    if (this.err !== "") return { node: null, next: end };
    const children = cr.nodes;
    const j = cr.next;
    // G-04: `j + 1 >= end` must fail on its own -- see guitkx_markup.gd's comment.
    if (j >= end || this.src[j] !== "<" || j + 1 >= end || this.src[j + 1] !== "/") {
      this.fail("GUITKX0301", `unclosed tag <${tag}>`, openI);
      return { node: null, next: end };
    }
    // j points at "</": read the close name to ">" (a close tag holds no {expr}/strings)
    const ce = this.src.indexOf(">", j);
    if (ce === -1 || ce >= end) {
      this.fail("GUITKX0303", `malformed closing tag for <${tag}>`, j);
      return { node: null, next: end };
    }
    const closeName = this.src.slice(j + 2, ce).trim();
    if (closeName !== tag) {
      this.fail("GUITKX0302", `mismatched tag </${closeName}> (expected </${tag}>)`, j);
      return { node: null, next: end };
    }
    return { node: this.mkEl(tag, attrs, children, line, openI), next: ce + 1 };
  }

  private mkEl(tag: string, attrs: Attr[], children: MarkupNode[], line: number, at: number): MarkupNode {
    if (tag === "") return { t: "frag", at, children };
    // T2.2 (Unity parity): <Fragment> is a named alias of <>, resolved case-insensitively at the
    // resolver level in Unity (PropsResolver). The author's spelling + attrs are kept so the
    // formatter round-trips and the emitter can honor `key` (V.fragment's second arg).
    if (tag.toLowerCase() === "fragment") return { t: "frag", at, children, named: tag, attrs };
    return { t: "el", at, tag, attrs, children, line };
  }

  private parseAttribute(start: number, end: number): { attr: Attr | null; next: number } {
    let i = start;
    // spread attribute `{...expr}` (React `{...obj}`): merged into props at codegen. kind "spread".
    if (this.src[i] === "{") {
      // T2.1: `{/* comment */}` inside an attribute list (Unity parity). Scanned for `*/` directly
      // (not findMatching -- comment text may hold unbalanced braces), then the closing `}`.
      const probe = this.skipWs(i + 1, end);
      if (probe + 1 < end && this.src[probe] === "/" && this.src[probe + 1] === "*") {
        const ce2 = this.src.indexOf("*/", probe + 2);
        if (ce2 === -1 || ce2 + 2 > end) {
          this.fail("GUITKX0304", "unclosed comment in attribute list", i);
          return { attr: null, next: end };
        }
        const after = this.skipWs(ce2 + 2, end);
        if (after >= end || this.src[after] !== "}") {
          this.fail("GUITKX0303", "attribute comment must close with `*/}`", i);
          return { attr: null, next: end };
        }
        return { attr: { name: "", kind: "comment", value: this.src.slice(i, after + 1), at: i, vat: -1, end: after + 1 }, next: after + 1 };
      }
      const sclose = findMatching(this.src, i);
      if (sclose === -1 || sclose >= end) {
        this.fail("GUITKX0304", "unclosed `{` in spread attribute", i);
        return { attr: null, next: end };
      }
      const inner = this.src.slice(i + 1, sclose).trim();
      if (!inner.startsWith("...")) {
        this.fail("GUITKX0300", "expected `...spread` or an attribute name", i);
        return { attr: null, next: end };
      }
      const svat = this.skipWs(this.skipWs(i + 1, sclose) + 3, sclose); // first char of the expr after `...`
      return { attr: { name: "", kind: "spread", value: inner.slice(3).trim(), at: i, vat: svat, end: sclose + 1 }, next: sclose + 1 };
    }
    const ns = i;
    while (i < end && isAttrNameChar(this.src[i])) i++;
    const name = this.src.slice(ns, i);
    const nameEnd = i;
    if (name === "") {
      this.fail("GUITKX0300", "unexpected token in attributes", i);
      return { attr: null, next: end };
    }
    // T3.5: `<Foo.Bar/>` used to silently parse as tag Foo + boolean attr `.Bar`.
    if (name.startsWith(".") || name.startsWith("-")) {
      this.fail("GUITKX0300", `unexpected \`${name[0]}\` in attributes -- dotted/namespaced tags are not supported`, ns);
      return { attr: null, next: end };
    }
    i = this.skipWs(i, end);
    if (i >= end || this.src[i] !== "=") {
      return { attr: { name, kind: "bool", value: "true", at: ns, vat: -1, end: nameEnd }, next: i };
    }
    i += 1; // past "="
    i = this.skipWs(i, end);
    if (i >= end) {
      this.fail("GUITKX0303", `missing attribute value for '${name}'`, ns);
      return { attr: null, next: end };
    }
    const c = this.src[i];
    if (c === '"' || c === "'") {
      const se = skipString(this.src, i);
      // T3.5: an unterminated string used to truncate silently at the newline.
      if (se <= i + 1 || se > end || this.src[se - 1] !== c) {
        this.fail("GUITKX0300", `unterminated string in attribute '${name}'`, i);
        return { attr: null, next: end };
      }
      const val = this.src.slice(i + 1, se - 1);
      return { attr: { name, kind: "str", value: val, at: ns, vat: i + 1, end: se }, next: se };
    }
    if (c === "{") {
      const close = findMatching(this.src, i);
      if (close === -1 || close >= end) {
        this.fail("GUITKX0304", `unclosed \`{\` in attribute '${name}'`, i);
        return { attr: null, next: end };
      }
      const code = this.src.slice(i + 1, close).trim();
      return { attr: { name, kind: "expr", value: code, at: ns, vat: this.skipWs(i + 1, close), end: close + 1 }, next: close + 1 };
    }
    this.fail("GUITKX0300", `attribute '${name}' value must be a string or {expr}`, i);
    return { attr: null, next: end };
  }

  private parseText(start: number, end: number): { node: MarkupNode | null; next: number } {
    // T2.4 (Unity MT parity): text stops only at `<` or `@`; braces inside a run are LITERAL text
    // ({expr} is a node-start construct -- see parseNodes). The compiler warns GUITKX0150 on
    // brace-bearing text so pre-T2.4 interpolation habits surface instead of silently rendering "{n}".
    let i = start;
    while (i < end && this.src[i] !== "<" && this.src[i] !== "@") i++;
    const raw = this.src.slice(start, i);
    if (raw.trim() === "") return { node: null, next: i };
    return { node: { t: "text", at: start, value: raw.trim() }, next: i };
  }

  // --- control-flow directives ---
  private parseDirective(at: number, end: number): { node: MarkupNode | null; next: number } {
    if (keywordAt(this.src, at + 1, "if")) return this.parseIf(at, end);
    if (keywordAt(this.src, at + 1, "for")) return this.parseLoop(at, end, "for", 4);
    if (keywordAt(this.src, at + 1, "while")) return this.parseLoop(at, end, "while", 6);
    if (keywordAt(this.src, at + 1, "match")) return this.parseMatch(at, end);
    this.fail("GUITKX0305", "unknown @directive", at);
    return { node: null, next: end };
  }

  private readParen(i: number, end: number): { text: string; next: number } {
    i = this.skipWs(i, end);
    if (i >= end || this.src[i] !== "(") {
      this.fail("GUITKX2506", "directive expects `(...)`", i);
      return { text: "", next: end };
    }
    const close = findMatching(this.src, i);
    if (close === -1 || close >= end) {
      this.fail("GUITKX0304", "unclosed `(` in directive", i);
      return { text: "", next: end };
    }
    return { text: this.src.slice(i + 1, close).trim(), next: close + 1 };
  }

  private readBraceBody(i: number, end: number): { text: string; next: number; at: number } {
    i = this.skipWs(i, end);
    if (i >= end || this.src[i] !== "{") {
      this.fail("GUITKX0303", "directive expects `{ ... }` body", i);
      return { text: "", next: end, at: -1 };
    }
    // G-01: a directive BODY is markup, not GDScript -- findMatchingMarkup keeps `#` literal and
    // `//`/`/* */`/`<!-- -->` as comments (see scanner.ts's docstring).
    const close = findMatchingMarkup(this.src, i);
    if (close === -1 || close >= end) {
      this.fail("GUITKX0304", "unclosed `{` directive body", i);
      return { text: "", next: end, at: -1 };
    }
    return { text: this.src.slice(i + 1, close), next: close + 1, at: i + 1 };
  }

  private parseIf(at: number, end: number): { node: MarkupNode | null; next: number } {
    const branches: { cond: string; body_markup: string; body_at: number }[] = [];
    let elseBody: string | null = null;
    let elseBodyAt = -1;
    let i = at + 3; // past "@if"
    const p = this.readParen(i, end);
    if (this.err !== "") return { node: null, next: end };
    const b = this.readBraceBody(p.next, end);
    if (this.err !== "") return { node: null, next: end };
    branches.push({ cond: p.text, body_markup: b.text, body_at: b.at });
    i = b.next;
    while (true) {
      const k = this.skipWs(i, end);
      // T3.5: the `@` itself must be verified -- a commented `#elif` used to become a real branch.
      if (k >= end || this.src[k] !== "@") break;
      if (k + 5 <= end && keywordAt(this.src, k + 1, "elif")) {
        const pe = this.readParen(k + 5, end);
        if (this.err !== "") return { node: null, next: end };
        const be = this.readBraceBody(pe.next, end);
        if (this.err !== "") return { node: null, next: end };
        branches.push({ cond: pe.text, body_markup: be.text, body_at: be.at });
        i = be.next;
      } else if (k + 5 <= end && keywordAt(this.src, k + 1, "else")) {
        const bb = this.readBraceBody(k + 5, end);
        if (this.err !== "") return { node: null, next: end };
        elseBody = bb.text;
        elseBodyAt = bb.at;
        i = bb.next;
        break;
      } else {
        break;
      }
    }
    return { node: { t: "if", at, branches, else_body: elseBody, else_body_at: elseBodyAt }, next: i };
  }

  private parseLoop(at: number, end: number, kind: "for" | "while", kwlen: number): { node: MarkupNode | null; next: number } {
    const p = this.readParen(at + kwlen, end);
    if (this.err !== "") return { node: null, next: end };
    const b = this.readBraceBody(p.next, end);
    if (this.err !== "") return { node: null, next: end };
    return { node: { t: kind, at, header: p.text, body_markup: b.text, body_at: b.at } as MarkupNode, next: b.next };
  }

  private parseMatch(at: number, end: number): { node: MarkupNode | null; next: number } {
    const p = this.readParen(at + 6, end); // past "@match"
    if (this.err !== "") return { node: null, next: end };
    let bi = this.skipWs(p.next, end);
    if (bi >= end || this.src[bi] !== "{") {
      this.fail("GUITKX0303", "@match expects `{ ... }` with @case/@default arms", bi);
      return { node: null, next: end };
    }
    // G-01: @case/@default arm bodies are markup -- see findMatchingMarkup's docstring.
    const bclose = findMatchingMarkup(this.src, bi);
    if (bclose === -1 || bclose >= end) {
      this.fail("GUITKX0304", "unclosed @match body", bi);
      return { node: null, next: end };
    }
    const cases: { value: string; body_markup: string; body_at: number }[] = [];
    let defaultBody: string | null = null;
    let defaultBodyAt = -1;
    let j = bi + 1;
    while (j < bclose) {
      j = this.skipWs(j, bclose);
      if (j >= bclose) break;
      if (this.src[j] === "@" && keywordAt(this.src, j + 1, "case")) {
        const cp = this.readParen(j + 5, bclose);
        if (this.err !== "") return { node: null, next: end };
        const cb = this.readBraceBody(cp.next, bclose);
        if (this.err !== "") return { node: null, next: end };
        cases.push({ value: cp.text, body_markup: cb.text, body_at: cb.at });
        j = cb.next;
      } else if (this.src[j] === "@" && keywordAt(this.src, j + 1, "default")) {
        const db = this.readBraceBody(j + 8, bclose);
        if (this.err !== "") return { node: null, next: end };
        defaultBody = db.text;
        defaultBodyAt = db.at;
        j = db.next;
      } else {
        this.fail("GUITKX2506", "@match body expects @case (...) { } or @default { }", j);
        return { node: null, next: end };
      }
    }
    return { node: { t: "match", at, subject: p.text, cases, default_body: defaultBody, default_body_at: defaultBodyAt }, next: bclose + 1 };
  }

  // --- helpers ---
  private skipWs(i: number, end: number): number {
    while (i < end && (this.src[i] === " " || this.src[i] === "\t" || this.src[i] === "\n" || this.src[i] === "\r")) i++;
    return i;
  }

  private lineOf(idx: number): number {
    // [G-08] Binary search over lazily-built line starts -- was an O(idx) scan per element.
    if (this.lineStarts === null) {
      const starts = [0];
      let nl = this.src.indexOf("\n", 0);
      while (nl !== -1) {
        starts.push(nl + 1);
        nl = this.src.indexOf("\n", nl + 1);
      }
      this.lineStarts = starts;
    }
    const ls = this.lineStarts;
    let lo = 0;
    let hi = ls.length - 1;
    while (lo < hi) {
      const mid = (lo + hi + 1) >> 1;
      if (ls[mid] <= idx) lo = mid;
      else hi = mid - 1;
    }
    return lo + 1;
  }
}

function isTagChar(c: string): boolean {
  return c === "_" || (c >= "a" && c <= "z") || (c >= "A" && c <= "Z") || (c >= "0" && c <= "9");
}
function isAttrNameChar(c: string): boolean {
  return isTagChar(c) || c === "-" || c === ".";
}
