// Build the synthetic GDScript "virtual document" handed to @gdscript-analyzer/core, plus a source map.
// SCOPE-AWARE (Phase 4 §2): models Unity's VirtualDocumentGenerator — emit the REAL control-flow
// structure (`for x in xs:`, `if cond:`, `match subj:`) so loop/branch variables are in scope, with
// each embedded `{expr}` (attribute or child) as a `var _eN = (expr)` check INSIDE its block,
// recursively nested. Hook names are pre-declared as in-scope stubs so `useState(...)` resolves.
// Markup/glue is never copied, so Godot only ever parses real GDScript. Embedded code is spliced
// VERBATIM (length-preserving), so the offset SourceMap round-trips 1:1 and survives future rewrites.

import { skipNoncode, skipString, findMatching, findMatchingMarkup, keywordAt } from "./scanner";
import { findDecl, FoundDecl, valueEnd } from "./declScan";
import { SourceMap } from "./sourceMap";
import { neutralizeMarkup, neutralizeSetupMarkup } from "./jsxScan";

export interface VirtualDoc {
  text: string;
  map: SourceMap;
}

// One stub per public hook, emitted at CLASS level as a real static wrapper func — NOT a
// `var useState = Hooks.useState` local. A local alias types as a bare Callable, so a call through it
// erased the hook's whole signature: arity, param types, and above all the `## @return-tuple(...)`
// shape (hooks.gd) that makes `useState(0)[1]` a checkable Callable for the analyzer. A wrapper func
// carries all of it, resolves for bare calls inside render()/__hook() (own-class static), and keeps
// go-to-definition chaining (`Hooks.<name>` appears on the stub line — see server.ts hookStubRhsOffset).
// `params`/`ret` MUST stay byte-identical to the hooks.gd declarations — asserted by the
// "hook stub signatures match hooks.gd" parity test in core.test.ts.
export const HOOK_STUBS: { name: string; params: string; args: string; ret: string; tuple?: string }[] = [
  { name: "useState", params: "initial = null", args: "initial", ret: " -> Array", tuple: "Variant, Callable" },
  { name: "useReducer", params: "reducer: Callable, initial = null", args: "reducer, initial", ret: " -> Array", tuple: "Variant, Callable" },
  { name: "useRef", params: "initial = null", args: "initial", ret: " -> Dictionary" },
  { name: "useMemo", params: "factory: Callable, deps: Array = []", args: "factory, deps", ret: " -> Variant" },
  { name: "useCallback", params: "cb: Callable, deps: Array = []", args: "cb, deps", ret: " -> Callable" },
  { name: "useImperativeHandle", params: "factory: Callable, deps: Array = []", args: "factory, deps", ret: " -> Variant" },
  { name: "useEffect", params: "effect: Callable, deps = null", args: "effect, deps", ret: " -> void" },
  { name: "useLayoutEffect", params: "effect: Callable, deps = null", args: "effect, deps", ret: " -> void" },
  { name: "createContext", params: "default_value = null, ctx_name: String = \"\"", args: "default_value, ctx_name", ret: " -> RuitkContext" },
  { name: "useContext", params: "key", args: "key", ret: "" },
  { name: "provideContext", params: "key, value", args: "key, value", ret: " -> void" },
  { name: "useDeferredValue", params: "value, deps = null", args: "value, deps", ret: "" },
  { name: "useTransition", params: "", args: "", ret: " -> Array", tuple: "bool, Callable" },
  { name: "useStableCallback", params: "cb: Callable", args: "cb", ret: " -> Callable" },
  { name: "useStableFunc", params: "cb: Callable", args: "cb", ret: " -> Callable" },
  { name: "useStableAction", params: "cb: Callable", args: "cb", ret: " -> Callable" },
  { name: "useSafeArea", params: "", args: "", ret: " -> Dictionary" },
  { name: "useSignal", params: "sig: RuitkSignal, selector = null, comparer = null", args: "sig, selector, comparer", ret: "" },
  { name: "useSignalKey", params: "key: String, initial = null, selector = null, comparer = null", args: "key, initial, selector, comparer", ret: "" },
  { name: "useTween", params: "ref: Dictionary, property: String, to, duration: float, deps: Array = []", args: "ref, property, to, duration, deps", ret: " -> void" },
  { name: "useTweenValue", params: "from, to, duration: float, on_update: Callable, deps: Array = []", args: "from, to, duration, on_update, deps", ret: " -> void" },
  { name: "useAnimate", params: "ref: Dictionary, tracks: Array, autoplay := true, deps: Array = []", args: "ref, tracks, autoplay, deps", ret: " -> void" },
  { name: "useSfx", params: "bus := \"Master\"", args: "bus", ret: " -> Callable" },
];

interface Ctx {
  src: string;
  gen: string;
  map: SourceMap;
  counter: number;
}

export function buildVirtualDoc(src: string): VirtualDoc {
  const ctx: Ctx = { src, gen: "extends RefCounted\n", map: new SourceMap(), counter: 0 };
  // Recover from a misspelled header keyword (`comssponent Foo {`) so embedded GDScript is still
  // analyzed instead of emitting an empty class — the whole-file-goes-dark bug. [declScan]
  const first = findDecl(src, 0, true);
  if (first.kind === "") return { text: ctx.gen, map: ctx.map };
  declareImportStubs(ctx);
  declareHookStubs(ctx);
  // ES-modules leg: a file is a SEQUENCE of declarations (mixed-decl since 0.10.0; the whole
  // modernized tree is multi-decl) — walk and emit EVERY top-level decl, not just the first.
  // The FIRST component keeps the bare `render` name (the compiler's binding-component rule is
  // close enough for analysis); later components emit under their decl names, exactly like
  // guitkx.gd _compile_mixed. Values emit as `static var` with their initializer MAPPED.
  let i = 0;
  let firstComp = true;
  const n = src.length;
  while (i < n) {
    const d = findDecl(src, i, true);
    if (d.kind === "") break;
    let next = -1;
    if (d.kind === "module") {
      emitModuleMembers(ctx, d.at);
      const mb = readDeclBody(ctx.src, d.at);
      next = mb ? mb.start + mb.text.length + 1 : -1;
    } else if (d.kind === "component") {
      emitDeclFunc(ctx, "component", d.at, firstComp ? "" : `_${ctx.counter++}`, d);
      firstComp = false;
      const cb = readDeclBody(ctx.src, d.deprecated === false ? (d.bodyOpen ?? d.at) : d.at, true);
      next = cb ? cb.start + cb.text.length + 1 : -1;
    } else if (d.kind === "hook" || d.kind === "util") {
      emitDeclFunc(ctx, "hook", d.at, `_${ctx.counter++}`, d);
      const hb = readDeclBody(ctx.src, d.deprecated === false ? (d.bodyOpen ?? d.at) : d.at);
      next = hb ? hb.start + hb.text.length + 1 : -1;
    } else if (d.kind === "value") {
      emitValueDecl(ctx, d);
      next = d.valueStart !== undefined ? valueEnd(src, d.valueStart) : -1;
    } else if (d.kind === "export_list" || d.kind === "export_default") {
      next = d.listEnd ?? -1;
    }
    if (next === -1 || next <= i) break;
    i = next;
  }
  return { text: ctx.gen, map: ctx.map };
}

// E-01 value declaration -> `static var <name>[: Type] = <initializer>` with the initializer
// spliced VERBATIM and source-mapped, so references inside it (imported consts, other values)
// get real analysis; multi-line initializers copy through with their newlines.
function emitValueDecl(ctx: Ctx, d: FoundDecl): void {
  if (!d.name || d.valueStart === undefined) return;
  const ve = valueEnd(ctx.src, d.valueStart);
  if (ve === -1) return;
  const typed = d.eqStyle === "typed" && d.typeText ? `: ${d.typeText}` : "";
  const eq = d.eqStyle === "infer" ? " := " : typed !== "" ? " = " : " = ";
  ctx.gen += `static var ${d.name}${typed}${eq}`;
  const text = ctx.src.slice(d.valueStart, ve).trim();
  const gs = ctx.gen.length;
  ctx.gen += text;
  ctx.map.addSpan(d.valueStart + (ctx.src.slice(d.valueStart, ve).length - ctx.src.slice(d.valueStart, ve).trimStart().length), gs, text.length);
  ctx.gen += "\n";
}

// One module member = one static func. The module body used to be fed WHOLE through the component
// path, so member headers (`component A() {`) landed in the generated .gd as "statements" — parse
// noise, and (with UNDEFINED_* armed) false errors mapped onto user code. Suffixes keep sibling
// names unique; a top-level component/hook keeps the bare `render`/`__hook` name.
function emitModuleMembers(ctx: Ctx, moduleAt: number): void {
  const body = readDeclBody(ctx.src, moduleAt);
  if (!body) return;
  const to = body.start + body.text.length;
  let i = body.start;
  while (i < to) {
    const d = findDecl(ctx.src, i, true);
    if (d.kind === "" || d.at >= to) break;
    const b = readDeclBody(ctx.src, d.at, d.kind === "component");
    if (d.kind === "module") emitModuleMembers(ctx, d.at);
    else if (d.kind === "component" || d.kind === "hook" || d.kind === "util") emitDeclFunc(ctx, d.kind === "component" ? "component" : "hook", d.at, `_${ctx.counter++}`, d);
    i = b ? b.start + b.text.length + 1 : d.at + 1;
  }
}

function emitDeclFunc(ctx: Ctx, kind: "component" | "hook", at: number, suffix: string, d?: FoundDecl): void {
  // Plain rows (E-01) carry their own name/body anchor; the keyword-anchored readers below expect
  // a keyword at `at`, which a plain decl doesn't have -- feed them the name position (their
  // "skip the keyword token" step then skips the NAME, so name reads use d.name instead).
  const plain = d !== undefined && d.deprecated === false;
  const body = readDeclBody(ctx.src, plain ? (d!.bodyOpen ?? at) : at, kind === "component");

  if (kind === "hook") {
    if (!body) return;
    // The hook is emitted under its REAL declared name, exactly like the compiler (guitkx.gd
    // _compile_hook / _compile_module): a sibling module member legally calls it bare (`use_z(1)` —
    // the compiler deliberately skips aliasing module-local hooks), so a mangled `__hook_N` name
    // turned every such call into a false UNDEFINED_FUNCTION. Params are spliced VERBATIM and
    // mapped — a hook body reads its params, so without them in scope every read would be a false
    // UNDEFINED_IDENTIFIER (and hover/goto on one, dead). The `-> Hint` survives like the compiler's
    // _ret_suffix (tuple-style `-> (a, b)` is dropped — GDScript has no tuple type).
    const name = plain ? (d!.name ?? "") : readDeclName(ctx.src, at);
    const params = readParamsSpan(ctx.src, at);
    ctx.gen += `static func ${name !== "" ? name : `__hook${suffix}`}(`;
    if (params && params.text.trim() !== "") {
      const gs = ctx.gen.length;
      ctx.gen += params.text;
      ctx.map.addSpan(params.start, gs, params.text.length);
    }
    ctx.gen += `)${retSuffix(ctx.src, at)}:\n`;
    // Map the hook body per line (see emitVerbatimBlock) so hover/completion/definition resolve
    // inside it regardless of re-indentation or CRLF line endings.
    emitVerbatimBlock(ctx, body.start, body.start + body.text.length, 1);
    if (!hasStatement(body.text)) ctx.gen += "\tpass\n";
    return;
  }

  // A top-level component compiles to `static func render(...)` (guitkx.gd _emit); module member
  // components compile under their REAL names (`_emit_func(c["name"], ...)`) — mirror both, so a
  // sibling expr referencing a member component by name resolves instead of false-flagging.
  const compName = suffix === "" ? "render" : (plain ? (d!.name ?? "") : readDeclName(ctx.src, at)) || `render${suffix}`;
  ctx.gen += `static func ${compName}(props: Dictionary, children: Array) -> RuitkVNode:\n`;
  if (!body) {
    ctx.gen += "\tpass\n";
    return;
  }
  const propVars = paramNames(readParams(ctx.src, at));
  for (const name of propVars) ctx.gen += `\tvar ${name} = props.get("${name}")\n`;
  const split = splitReturn(ctx.src, body.start, body.start + body.text.length);

  // setup verbatim (mapped, one line at a time so the per-line indent never shifts an expr offset).
  // A2: markup inside setup — an early/demoted markup return like `return <s></a>`, which
  // splitReturn leaves in the setup span — is neutralized first (length+newline-preserving), so
  // the analyzer never parses raw `<Tag>` as GDScript (the 0.6.0 field noise spray: SYNTAX +
  // UNDEFINED_IDENTIFIER + STANDALONE_EXPRESSION on the markup island).
  const setupHasStmt = split.setupEnd > body.start && hasStatement(ctx.src.slice(body.start, split.setupEnd));
  if (split.setupEnd > body.start) {
    emitVerbatimBlock(ctx, body.start, split.setupEnd, 1, neutralizeSetupMarkup(ctx.src.slice(body.start, split.setupEnd)));
  }
  // scope-aware markup
  const emitted = emitMarkup(ctx, split.markupStart, split.markupEnd, 1);
  // `pass` when nothing above counts as a statement — prop destructures do, comment-only setup
  // does not (a func body of only comments is invalid GDScript).
  if (!emitted && !setupHasStmt && propVars.length === 0) ctx.gen += "\tpass\n";
}

// True when the block has at least one real statement line (not blank, not a `#` comment) — then the
// wrapper func needs no trailing `pass`. An unconditional `pass` after a body ending in `return`
// produced an UNREACHABLE_CODE warning that mapped onto the user's closing lines.
function hasStatement(block: string): boolean {
  return block.split("\n").some((l) => {
    const t = l.trim();
    return t !== "" && !t.startsWith("#");
  });
}

// --- scope-aware markup emitter -------------------------------------------------------------

const CONTROL_PAREN = ["if", "elif", "for", "while", "match", "case"];

// Walk markup [start,end) linearly at GDScript `indent`. A `<Tag>` adds no GDScript scope, so its
// children stay at the same indent (walked by this same loop); only control-flow adds scope (via
// emitControl, which recurses at indent+1). Returns true if any statement was emitted.
function emitMarkup(ctx: Ctx, start: number, end: number, indent: number): boolean {
  const src = ctx.src;
  let i = start;
  let any = false;
  while (i < end) {
    const c = src[i];
    if (c === '"' || c === "'") {
      i = skipString(src, i);
      continue;
    }
    if (c === "@") {
      const kw = readWord(src, i + 1);
      if (kw === "if" || kw === "for" || kw === "while" || kw === "match") {
        i = emitControl(ctx, i, kw, end, indent);
        any = true;
        continue;
      }
      i++;
      continue;
    }
    if (c === "<") {
      if (src[i + 1] === "/") {
        const gt = src.indexOf(">", i);
        i = gt === -1 || gt >= end ? end : gt + 1;
        continue;
      }
      if (/[A-Za-z_]/.test(src[i + 1] || "")) {
        const r = emitTagAttrs(ctx, i, end, indent);
        if (r.emitted) any = true;
        i = r.next;
        continue;
      }
      i++;
      continue;
    }
    if (c === "{") {
      const close = findMatching(src, i);
      if (close !== -1 && close < end) {
        // T2.1: a `{/* comment */}` hole is markup commentary, not a GDScript expression.
        if (src.slice(i + 1, close).trim().startsWith("/*")) {
          i = close + 1;
          continue;
        }
        emitExpr(ctx, i + 1, close, indent);
        any = true;
        i = close + 1;
        continue;
      }
    }
    i++;
  }
  return any;
}

// Emit a tag's `={expr}` attribute checks at `indent`; return the index past `>`/`/>` (children are
// walked by the caller's loop, same indent).
function emitTagAttrs(ctx: Ctx, lt: number, end: number, indent: number): { next: number; emitted: boolean } {
  const src = ctx.src;
  let i = lt + 1;
  while (i < end && /[A-Za-z0-9_]/.test(src[i])) i++; // tag name
  let emitted = false;
  while (i < end) {
    while (i < end && /\s/.test(src[i])) i++;
    if (i >= end) break;
    if (src[i] === "/" && src[i + 1] === ">") return { next: i + 2, emitted };
    if (src[i] === ">") return { next: i + 1, emitted };
    const an = i;
    while (i < end && /[A-Za-z0-9_.\-]/.test(src[i])) i++;
    if (i === an) {
      i++;
      continue;
    }
    while (i < end && /\s/.test(src[i])) i++;
    if (src[i] === "=") {
      i++;
      while (i < end && /\s/.test(src[i])) i++;
      if (src[i] === '"' || src[i] === "'") i = skipString(src, i);
      else if (src[i] === "{") {
        const close = findMatching(src, i);
        if (close !== -1 && close < end) {
          // T2.1: skip `{/* comment */}` attribute-list holes (not GDScript).
          if (!src.slice(i + 1, close).trim().startsWith("/*")) {
            emitExpr(ctx, i + 1, close, indent);
            emitted = true;
          }
          i = close + 1;
        } else i++;
      }
    }
  }
  return { next: end, emitted };
}

// Emit a control-flow block: `for <header>:` / `if <cond>:` / `match <subj>:` with the body's
// exprs nested at indent+1. Returns the index past the directive.
function emitControl(ctx: Ctx, at: number, kw: string, end: number, indent: number): number {
  const src = ctx.src;
  const pad = "\t".repeat(indent);
  // read (header)
  let p = at + 1 + kw.length;
  while (p < end && /\s/.test(src[p])) p++;
  if (src[p] !== "(") return p;
  const pc = findMatching(src, p);
  if (pc === -1 || pc >= end) return p;
  const headerStart = p + 1;
  const headerText = src.slice(headerStart, pc).trim();
  // body { ... }
  let b = pc + 1;
  while (b < end && /\s/.test(src[b])) b++;
  if (src[b] !== "{") return pc + 1;
  // G-01: the directive BODY is markup -- see scanner.ts findMatchingMarkup's docstring.
  const bclose = findMatchingMarkup(src, b);
  if (bclose === -1 || bclose >= end) return pc + 1;

  if (kw === "match") {
    ctx.gen += `${pad}match ${mapInline(ctx, headerStart, headerText)}:\n`;
    emitMatchArms(ctx, b + 1, bclose, indent + 1);
  } else {
    const keyword = kw === "elif" ? "if" : kw; // first-pass @if; elif/else handled in caller chain
    ctx.gen += `${pad}${keyword} ${mapInline(ctx, headerStart, headerText)}:\n`;
    const inner = emitMarkup(ctx, b + 1, bclose, indent + 1);
    if (!inner) ctx.gen += `${"\t".repeat(indent + 1)}pass\n`;
  }
  // @elif / @else chain
  let i = bclose + 1;
  while (i < end) {
    let k = i;
    while (k < end && /\s/.test(src[k])) k++;
    if (src[k] === "@" && keywordAt(src, k + 1, "elif")) {
      let ep = k + 5;
      while (ep < end && /\s/.test(src[ep])) ep++;
      if (src[ep] !== "(") break;
      const epc = findMatching(src, ep);
      if (epc === -1) break;
      const cond = src.slice(ep + 1, epc).trim();
      let eb = epc + 1;
      while (eb < end && /\s/.test(src[eb])) eb++;
      // G-01: directive BODY is markup.
      const ebc = findMatchingMarkup(src, eb);
      if (ebc === -1) break;
      ctx.gen += `${pad}elif ${mapInline(ctx, ep + 1, cond)}:\n`;
      if (!emitMarkup(ctx, eb + 1, ebc, indent + 1)) ctx.gen += `${"\t".repeat(indent + 1)}pass\n`;
      i = ebc + 1;
    } else if (src[k] === "@" && keywordAt(src, k + 1, "else")) {
      let eb = k + 5;
      while (eb < end && /\s/.test(src[eb])) eb++;
      // G-01: directive BODY is markup.
      const ebc = findMatchingMarkup(src, eb);
      if (ebc === -1) break;
      ctx.gen += `${pad}else:\n`;
      if (!emitMarkup(ctx, eb + 1, ebc, indent + 1)) ctx.gen += `${"\t".repeat(indent + 1)}pass\n`;
      i = ebc + 1;
    } else break;
  }
  return i;
}

function emitMatchArms(ctx: Ctx, start: number, end: number, indent: number): void {
  const src = ctx.src;
  const pad = "\t".repeat(indent);
  let i = start;
  let emittedArm = false;
  while (i < end) {
    while (i < end && /\s/.test(src[i])) i++;
    if (i >= end) break;
    if (src[i] === "@" && keywordAt(src, i + 1, "case")) {
      let p = i + 5;
      while (p < end && /\s/.test(src[p])) p++;
      if (src[p] !== "(") break;
      const pc = findMatching(src, p);
      if (pc === -1) break;
      const val = src.slice(p + 1, pc).trim();
      let b = pc + 1;
      while (b < end && /\s/.test(src[b])) b++;
      // G-01: @case's arm BODY is markup.
      const bclose = findMatchingMarkup(src, b);
      if (bclose === -1) break;
      ctx.gen += `${pad}${mapInline(ctx, p + 1, val)}:\n`;
      if (!emitMarkup(ctx, b + 1, bclose, indent + 1)) ctx.gen += `${"\t".repeat(indent + 1)}pass\n`;
      emittedArm = true;
      i = bclose + 1;
    } else if (src[i] === "@" && keywordAt(src, i + 1, "default")) {
      let b = i + 8;
      while (b < end && /\s/.test(src[b])) b++;
      // G-01: @default's arm BODY is markup.
      const bclose = findMatchingMarkup(src, b);
      if (bclose === -1) break;
      ctx.gen += `${pad}_:\n`;
      if (!emitMarkup(ctx, b + 1, bclose, indent + 1)) ctx.gen += `${"\t".repeat(indent + 1)}pass\n`;
      emittedArm = true;
      i = bclose + 1;
    } else i++;
  }
  if (!emittedArm) ctx.gen += `${pad}_:\n${"\t".repeat(indent + 1)}pass\n`;
}

// Emit `var _eN = (<expr>)` at `indent`, mapping the expr text verbatim.
// T5.1: markup NESTED inside the expression (`open and <Panel/>`, `xs.map(func(x): return <Row/>)`)
// used to be spliced raw -- the analyzer parsed `<` as an operator and sprayed syntax noise over the
// island (the G7/G8 noise source). jsxScan.neutralizeMarkup replaces each markup range with `null`
// padded to the SAME length, so the expression stays valid GDScript and the 1:1 offset map holds.
function emitExpr(ctx: Ctx, start: number, end: number, indent: number): void {
  const text = ctx.src.slice(start, end);
  const trimmed = text.replace(/^\s+/, "");
  const lead = text.length - trimmed.length;
  if (trimmed.trim() === "") return;
  const prefix = `${"\t".repeat(indent)}var _e${ctx.counter++} = (`;
  ctx.gen += prefix;
  const gs = ctx.gen.length;
  ctx.gen += neutralizeMarkup(trimmed);
  ctx.map.addSpan(start + lead, gs, trimmed.length);
  ctx.gen += ")\n";
}

// Splice an inline expression (a condition/header/match value) into the current line, mapped.
function mapInline(ctx: Ctx, srcStart: number, text: string): string {
  const gs = ctx.gen.length;
  ctx.map.addSpan(srcStart, gs, text.length);
  return text;
}

// Emit a verbatim source block [start,end) at `indent`, mapping it PER LINE. Re-indentation changes a
// line's length (dedent to the common leading whitespace, then re-indent to `indent`) and blank lines
// collapse, so a single whole-block span would drift and — with a trailing blank line or CRLF — be
// dropped entirely (the old all-or-nothing length guard). Instead we map each non-blank line's CODE
// (everything after the common prefix) on its own span. Line-ending agnostic: a trailing CR is stripped
// from both the generated text and the mapped length, so CRLF .guitkx files round-trip exactly.
// `override`, when given, replaces the emitted CONTENT (it must be length- and newline-preserving,
// e.g. neutralizeSetupMarkup's output) while all offsets/mapping still track the real source — the
// same contract emitExpr uses for neutralized expressions, applied block-wide.
function emitVerbatimBlock(ctx: Ctx, start: number, end: number, indent: number, override?: string): void {
  const text = override !== undefined && override.length === end - start ? override : ctx.src.slice(start, end);
  const rawLines = text.split("\n");
  // Depth-based reindent (mirror guitkx.gd _reindent_setup): normalise mixed tabs/spaces so the
  // virtual .gd is valid GDScript. A line indented `\t  ` (tab + 2 spaces) renders like `\t\t` but is
  // byte-different; a naive common-prefix strip leaves that mismatch and the analyser reports a
  // phantom "unindent doesn't match". A tab counts as one unit, the space-unit is the smallest
  // leading-space run, and depth = round(cols / unit). Anchored to the FIRST non-blank NON-COMMENT
  // line (in valid GDScript the body's base level), NOT the shallowest: a min-depth anchor let one
  // outlier-shallow line raise every other line a level (over-indented with no preceding `:` —
  // invalid virtual .gd), and a comment anchor would mis-shift real code (GDScript allows a comment
  // at any indentation). A line shallower than the anchor clamps to `indent` tabs. Each line's own
  // leading whitespace is glue — only the code after it is mapped, at its depth-tab level.
  const unit = indentUnit(rawLines);
  let anchor = -1;
  let anchorAny = -1;
  const depths: number[] = [];
  for (const raw of rawLines) {
    const l = raw.endsWith("\r") ? raw.slice(0, -1) : raw;
    const t = l.trim();
    if (t === "") { depths.push(-1); continue; }
    const d = indentDepth(l, unit);
    depths.push(d);
    if (anchorAny === -1) anchorAny = d;
    if (anchor === -1 && !t.startsWith("#")) anchor = d;
  }
  if (anchor === -1) anchor = anchorAny; // comment-only block
  let srcOff = start; // absolute source offset of the current line's first char
  for (let k = 0; k < rawLines.length; k++) {
    const raw = rawLines[k];
    const code = raw.endsWith("\r") ? raw.slice(0, -1) : raw; // strip CR for gen + mapping
    if (code.trim() !== "") {
      const leadLen = code.match(/^[\t ]*/)![0].length;
      const level = indent + Math.max(0, depths[k] - anchor);
      ctx.gen += "\t".repeat(level);
      const genCodeStart = ctx.gen.length;
      ctx.gen += code.slice(leadLen);
      ctx.map.addSpan(srcOff + leadLen, genCodeStart, code.length - leadLen);
    }
    if (k < rawLines.length - 1) ctx.gen += "\n";
    srcOff += raw.length + 1; // + the "\n" consumed by split
  }
  if (!ctx.gen.endsWith("\n")) ctx.gen += "\n";
}

// Inferred space-indent width: the minimum POSITIVE DIFFERENCE between distinct leading-space
// widths — not the minimum width (that's the base offset; dividing by it folds nesting levels
// together, the Phase D corruption find). One distinct width = old min-width behavior; tab-only
// source keeps unit 1 (a tab = one level). Mirrors guitkx.gd _indent_unit.
function indentUnit(rawLines: string[]): number {
  const widths = new Set<number>();
  for (const raw of rawLines) {
    const l = raw.endsWith("\r") ? raw.slice(0, -1) : raw;
    const lead = l.match(/^[\t ]*/)![0];
    let sp = 0;
    for (const c of lead) if (c === " ") sp++;
    if (sp > 0) widths.add(sp);
  }
  if (widths.size === 0) return 1;
  const sorted = [...widths].sort((a, b) => a - b);
  let unit = sorted[0];
  for (let i = 1; i < sorted.length; i++) {
    const d = sorted[i] - sorted[i - 1];
    if (d > 0 && d < unit) unit = d;
  }
  return Math.max(unit, 1);
}

// Indentation depth of a line in whole levels: tab = `unit` columns, space = 1 column, rounded.
function indentDepth(l: string, unit: number): number {
  const lead = l.match(/^[\t ]*/)![0];
  let cols = 0;
  for (const c of lead) cols += c === "\t" ? unit : 1;
  return Math.round(cols / unit);
}

// Class-level static wrapper funcs (see HOOK_STUBS). All stub text is unmapped glue, so any analyzer
// diagnostic inside a stub line is dropped by the toSource() null-filter — stubs can never squiggle
// user code. Void hooks get a bare-call body (a `-> void` func can't `return` a value); everything
// else forwards with `return` so the annotated return type has a returning path.
// 0.10.0 imports leg: declare every preamble-imported name as a permissive static member so embedded
// GDScript analysis resolves `Name.member(...)` references (the compiler lowers value imports to
// `const Name = preload(...)`; here the identifier only needs to EXIST + be Variant). These are
// unmapped header inserts, so the length-preserving source map is unaffected -- imported names never
// red-squiggle in a migrated file, and imports stay OPTIONAL syntax (no strict diagnostics here).
function declareImportStubs(ctx: Ctx): void {
  const seen = new Set<string>();
  const add = (nm: string): void => {
    if (/^[A-Za-z_]\w*$/.test(nm) && !seen.has(nm)) {
      seen.add(nm);
      ctx.gen += `static var ${nm}\n`;
    }
  };
  // named clauses (a `remote as local` rename binds the LOCAL name -- E-08). The optional
  // leading group is the COMBINED form's default binding (`import Def, { a } from`, 0.11.1
  // field wave): every part of a combined declaration must yield its stub, or the imported
  // name has no declaration in the analysis and the editor squiggles a clean build.
  const importRe = /^[ \t]*import[ \t]*(?:([A-Za-z_]\w*)[ \t]*,[ \t]*)?\{([^}]*)\}[ \t]*from/gm;
  let m: RegExpExecArray | null;
  while ((m = importRe.exec(ctx.src)) !== null) {
    if (m[1]) add(m[1]);
    for (const raw of m[2].split(",")) {
      const clause = raw.trim();
      const asM = /^[A-Za-z_]\w*[ \t]+as[ \t]+([A-Za-z_]\w*)$/.exec(clause);
      add(asM ? asM[1] : clause);
    }
  }
  // `* as X` namespace (with the optional combined default) + bare default locals (G-05).
  const nsRe = /^[ \t]*import[ \t]*(?:([A-Za-z_]\w*)[ \t]*,[ \t]*)?\*[ \t]*as[ \t]+([A-Za-z_]\w*)[ \t]+from/gm;
  while ((m = nsRe.exec(ctx.src)) !== null) {
    if (m[1]) add(m[1]);
    add(m[2]);
  }
  const defRe = /^[ \t]*import[ \t]+([A-Za-z_]\w*)[ \t]+from/gm;
  while ((m = defRe.exec(ctx.src)) !== null) add(m[1]);
}

function declareHookStubs(ctx: Ctx): void {
  for (const h of HOOK_STUBS) {
    if (h.tuple) ctx.gen += `## @return-tuple(${h.tuple})\n`;
    const call = `Hooks.${h.name}(${h.args})`;
    ctx.gen += `static func ${h.name}(${h.params})${h.ret}: ${h.ret === " -> void" ? call : `return ${call}`}\n`;
  }
}

// --- declaration / window helpers (mirror guitkx.gd) ----------------------------------------

// `markupBody`: true for a "component" declaration, whose body mixes GDScript setup with a markup
// return (needs findMatchingMarkup -- G-01: a plain GDScript scan misreads `#`/`//`/`/* */`/
// `<!-- -->` inside that markup and can close the body early). false for "hook"/"module", whose
// bodies are pure GDScript (a module's own top-level content is a MIX of hook -- GDScript -- and
// component -- markup -- declarations, so it stays GDScript-lexis too, same as guitkx.gd
// _compile_module/_parse_hook_at).
function readDeclBody(src: string, declAt: number, markupBody = false): { text: string; start: number } | null {
  const n = src.length;
  let j = declAt;
  while (j < n && src[j] !== "{") {
    const k = skipNoncode(src, j);
    if (k !== j) {
      j = k;
      continue;
    }
    if (src[j] === "(") {
      const pc = findMatching(src, j);
      if (pc === -1) return null;
      j = pc + 1;
      continue;
    }
    j++;
  }
  if (j >= n || src[j] !== "{") return null;
  const close = markupBody ? findMatchingMarkup(src, j) : findMatching(src, j);
  if (close === -1) return null;
  return { text: src.slice(j + 1, close), start: j + 1 };
}

interface ReturnSplit {
  setupEnd: number;
  markupStart: number;
  markupEnd: number;
}

// T1.4 (Unity useLastReturn parity): the window is the LAST top-level markup return, mirroring
// guitkx.gd _split_return / formatGuitkx.ts splitReturn -- first token on its line, line depth <=
// the body's anchor depth. Statement-level returns (in if:/lambdas) stay in the analyzed setup.
function splitReturn(src: string, start: number, end: number): ReturnSplit {
  const lines = src.slice(start, end).split("\n");
  const unit = indentUnit(lines);
  let anchor = -1;
  let anchorAny = -1;
  for (const raw of lines) {
    const l = raw.endsWith("\r") ? raw.slice(0, -1) : raw;
    const t = l.trim();
    if (t === "") continue;
    const d = indentDepth(l, unit);
    if (anchorAny === -1) anchorAny = d;
    if (!t.startsWith("#")) {
      anchor = d;
      break;
    }
  }
  if (anchor === -1) anchor = anchorAny;
  let chosen: ReturnSplit | null = null;
  let i = start;
  while (i < end) {
    const k = skipNoncode(src, i);
    if (k !== i) {
      i = k;
      continue;
    }
    if (keywordAt(src, i, "return")) {
      let p = i + 6;
      while (p < end && /\s/.test(src[p])) p++;
      const ls = Math.max(start, src.lastIndexOf("\n", i - 1) + 1);
      const lead = src.slice(ls, i);
      const topLevel = lead.trim() === "" && indentDepth(lead, unit) <= anchor;
      let eol = src.indexOf("\n", i);
      if (eol === -1 || eol > end) eol = end;
      if (src[p] === "(") {
        // G-01: the `return ( ... )` window is markup, not GDScript -- see findMatchingMarkup.
        const close = findMatchingMarkup(src, p);
        // A half-typed `return (`: keep analysing the setup ABOVE the return (empty markup window)
        // instead of abandoning the whole body — mid-keystroke intelligence stays alive.
        if (close === -1 || close >= end) return { setupEnd: i, markupStart: end, markupEnd: end };
        if (topLevel) chosen = { setupEnd: i, markupStart: p + 1, markupEnd: close };
        i = close + 1;
        continue;
      }
      if (src[p] === "<") {
        if (topLevel) chosen = { setupEnd: i, markupStart: p, markupEnd: end };
        i = eol;
        continue;
      }
      if (keywordAt(src, p, "null")) {
        i = p + 4;
        continue;
      }
      i = topLevel ? eol : i + 6;
      continue;
    }
    i++;
  }
  return chosen ?? { setupEnd: end, markupStart: end, markupEnd: end };
}

function readWord(src: string, i: number): string {
  let j = i;
  while (j < src.length && /[A-Za-z_]/.test(src[j])) j++;
  return src.slice(i, j);
}

// The declared name following the (possibly misspelled) keyword at `at`, or "" when absent.
function readDeclName(src: string, at: number): string {
  const n = src.length;
  let i = at;
  while (i < n && /[A-Za-z0-9_]/.test(src[i])) i++; // the keyword token
  while (i < n && (src[i] === " " || src[i] === "\t")) i++;
  const s = i;
  while (i < n && /[A-Za-z0-9_]/.test(src[i])) i++;
  return src.slice(s, i);
}

// The declaration's ` -> Hint` suffix, mirroring guitkx.gd _ret_suffix: empty when there is no hint,
// and a tuple-style `-> (a, b)` is dropped (GDScript has no tuple type).
function retSuffix(src: string, declAt: number): string {
  const n = src.length;
  let j = declAt;
  while (j < n && src[j] !== "{" && src[j] !== "\n") {
    if (src[j] === "(") {
      const pc = findMatching(src, j);
      if (pc === -1) return "";
      j = pc + 1;
      continue;
    }
    if (src[j] === "-" && src[j + 1] === ">") {
      let e = j + 2;
      while (e < n && src[e] !== "{") e++;
      const hint = src.slice(j + 2, e).trim();
      return hint === "" || hint.startsWith("(") ? "" : ` -> ${hint}`;
    }
    j++;
  }
  return "";
}

// The `(...)` parameter list of a component/hook declaration (between the name and the body `{`),
// with its source offset so the text can be spliced into the virtual doc MAPPED (hook signatures).
// Stops at a `->` return hint: params always precede it, so a params-less declaration with a
// parenthesized hint (`hook use_pair -> (int, Callable) { … }`) must not eat the hint as params —
// the compiler parses it the same way (guitkx.gd _parse_hook_at reads params before the hint).
function readParamsSpan(src: string, declAt: number): { text: string; start: number } | null {
  const n = src.length;
  let j = declAt;
  while (j < n && src[j] !== "(" && src[j] !== "{") {
    if (src[j] === "-" && src[j + 1] === ">") return null;
    const k = skipNoncode(src, j);
    if (k !== j) {
      j = k;
      continue;
    }
    j++;
  }
  if (src[j] !== "(") return null;
  const pc = findMatching(src, j);
  if (pc === -1) return null;
  return { text: src.slice(j + 1, pc), start: j + 1 };
}

function readParams(src: string, declAt: number): string {
  return readParamsSpan(src, declAt)?.text ?? "";
}

// Parameter names from a params string ("a: int = 0, b: String") — split on top-level commas, take
// the identifier before any `:` type-hint or `=` default. NONCODE-AWARE (mirrors the GDScript
// authority's _split_top_commas/_find_top): strings, comments and bracket groups are skipped, so a
// comma/colon inside a default like `label: String = "a, b"` or `"x:y"` never mis-splits. [audit #26]
function paramNames(params: string): string[] {
  if (params.trim() === "") return [];
  const out: string[] = [];
  const n = params.length;
  let start = 0;
  let i = 0;
  const push = (chunk: string) => {
    // Strip the type hint (`: …`) and default (`= …`), finding the boundary noncode-aware.
    let endName = chunk.length;
    let j = 0;
    while (j < chunk.length) {
      const k = skipNoncode(chunk, j);
      if (k !== j) {
        j = k;
        continue;
      }
      const cc = chunk[j];
      if (cc === "(" || cc === "[" || cc === "{") {
        const m = findMatching(chunk, j);
        j = m === -1 ? chunk.length : m + 1;
        continue;
      }
      if (cc === "=" || cc === ":") {
        endName = j;
        break;
      }
      j++;
    }
    const name = chunk.slice(0, endName).trim();
    if (/^[A-Za-z_][A-Za-z0-9_]*$/.test(name)) out.push(name);
  };
  while (i < n) {
    const k = skipNoncode(params, i);
    if (k !== i) {
      i = k;
      continue;
    }
    const ch = params[i];
    if (ch === "(" || ch === "[" || ch === "{") {
      const m = findMatching(params, i);
      i = m === -1 ? i + 1 : m + 1;
      continue;
    }
    if (ch === ",") {
      push(params.slice(start, i));
      start = i + 1;
    }
    i++;
  }
  push(params.slice(start));
  return out;
}
