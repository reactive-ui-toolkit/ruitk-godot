// Live declaration validation for `.guitkx` — the "floor" the LSP was missing. The markup and
// embedded-GDScript passes both key off a valid `component`/`hook`/`module` header (markupWindows
// finds the `return(...)` of one). A single typo like `comssponent` yields NO window, so the LSP
// used to skip ALL analysis and report NOTHING — the whole file went dark silently. This validates
// the header itself, mirroring guitkx.gd compile() preamble + _find_decl / _nearest_decl_keyword,
// so a mistyped keyword / `@class_name` is reported live without a running Godot editor.
//
// Offset-based (no LSP types) so it stays unit-testable; server.ts wraps the results into Diagnostics.

import { skipNoncode, isIdent } from "./scanner";
import { scanDeclarations } from "./workspaceIndex";
import { editDistance, findDecl } from "./declScan";

export interface DeclDiag {
  start: number;
  end: number;
  code: string;
  message: string;
  severity?: "warning"; // absent = error
}

const DECL_KWS = ["component", "hook", "module"];

// The first top-level identifier and the declaration keyword it most resembles (edit distance <= 3),
// for a "did you mean 'component'?" hint. null if none is close.
export function nearestDeclKeyword(src: string): { word: string; kw: string; start: number; end: number } | null {
  let i = 0;
  while (i < src.length) {
    const k = skipNoncode(src, i);
    if (k !== i) { i = k; continue; }
    if (src[i] === "@") { // a directive line (e.g. a mistyped @class_name) — skip past it
      const nl = src.indexOf("\n", i);
      i = nl === -1 ? src.length : nl + 1;
      continue;
    }
    if (isIdent(src[i])) {
      const s = i;
      while (i < src.length && isIdent(src[i])) i++;
      const word = src.slice(s, i);
      let best = "", bestD = 99;
      for (const kw of DECL_KWS) {
        const d = editDistance(word.toLowerCase(), kw);
        if (d < bestD) { bestD = d; best = kw; }
      }
      // T5.2: ONE shared threshold with declScan.ts nearestDeclKind -- edit-dist <= 2, length >= 3.
      return best && bestD <= 2 && word.length >= 3 ? { word, kw: best, start: s, end: i } : null;
    }
    i++;
  }
  return null;
}

// GUITKX0300 (`@class_name` value) + GUITKX2101 (misspelled / missing declaration).
export function declarationDiags(src: string): DeclDiag[] {
  const out: DeclDiag[] = [];

  // Preamble directive `@class_name <Ident>`: validate the value. A near-miss directive like
  // `@clasaas_name` is flagged as a typo (GUITKX0300) instead of being silently ignored — it would
  // otherwise produce NO diagnostic at all, one of the mistakes that used to slip through.
  // T3.5 (§5.1 item 5): skip COMMENTS, not just whitespace, so a file-header comment doesn't hide
  // the @class_name validation.
  let p = 0;
  while (p < src.length) {
    const k = skipNoncode(src, p);
    if (k !== p) {
      p = k;
      continue;
    }
    if (/[ \t\r\n]/.test(src[p])) {
      p++;
      continue;
    }
    break;
  }
  if (src[p] === "@") {
    let w = p + 1;
    while (w < src.length && /[A-Za-z0-9_]/.test(src[w])) w++;
    const directive = src.slice(p + 1, w);
    if (directive === "class_name") {
      let le = src.indexOf("\n", p);
      if (le === -1) le = src.length;
      let raw = src.slice(w, le);
      const hash = raw.indexOf("#");
      if (hash !== -1) raw = raw.slice(0, hash);
      const val = raw.trim();
      if (val === "" || !/^[A-Za-z_][A-Za-z0-9_]*$/.test(val)) {
        out.push({
          start: p,
          end: le,
          code: "GUITKX0300",
          message: `GUITKX0300: \`@class_name\` value must be a single valid identifier (got '${val}').`,
        });
      }
    } else if (directive.length >= 4 && editDistance(directive.toLowerCase(), "class_name") <= 3) {
      out.push({
        start: p,
        end: w,
        code: "GUITKX0300",
        message: `GUITKX0300: unknown directive '@${directive}' — did you mean '@class_name'?`,
      });
    }
  }

  // No valid component/hook/module declaration -> flag the nearest misspelled keyword, else say none
  // was found. Either way the author learns the header is broken instead of getting silence.
  const decls = scanDeclarations(src);
  if (decls.length === 0) {
    const near = nearestDeclKeyword(src);
    if (near) {
      out.push({
        start: near.start,
        end: near.end,
        code: "GUITKX2101",
        message: `GUITKX2101: unknown declaration '${near.word}' — did you mean '${near.kw}'?`,
      });
    } else {
      out.push({
        start: 0,
        end: Math.min(src.length, 1),
        code: "GUITKX2101",
        message: "GUITKX2101: no `component`, `hook`, or `module` declaration found.",
      });
    }
  }

  // T1.3 live mirror of the compiler's GUITKX2105 -- ES-modules leg: a file is a SEQUENCE of
  // declarations, so only content BETWEEN/AFTER decl spans (never a following declaration or an
  // export marker) is junk. Mirrors _compile_mixed's sequence check: walk each inter-decl gap and
  // the tail, skipping the E-07/E-09 markers (legal top-level lines the index doesn't record).
  const first = decls.find((d) => d.kind !== "member");
  const tops = decls.filter((d) => d.kind !== "member" && !d.module).sort((a, b) => a.declStart - b.declStart);
  const junkInGap = (from: number, to: number): number => {
    let junk = firstRealAfter(src, from);
    while (junk !== -1 && junk < to && src.startsWith("export", junk)) {
      const d2 = findDecl(src, junk, false);
      if ((d2.kind === "export_list" || d2.kind === "export_default") && d2.listEnd !== undefined) {
        junk = firstRealAfter(src, d2.listEnd);
        continue;
      }
      break;
    }
    return junk !== -1 && junk < to ? junk : -1;
  };
  if (tops.length > 0) {
    const gaps: { from: number; to: number }[] = [];
    for (let g = 1; g < tops.length; g++) gaps.push({ from: tops[g - 1].declEnd, to: tops[g].declStart });
    gaps.push({ from: tops[tops.length - 1].declEnd, to: src.length });
    for (const gap of gaps) {
      const junk = junkInGap(gap.from, gap.to);
      if (junk === -1) continue;
      let le = src.indexOf("\n", junk);
      if (le === -1 || le > gap.to) le = Math.min(gap.to, src.length);
      out.push({
        start: junk,
        end: Math.max(junk + 1, le),
        code: "GUITKX2105",
        message: "GUITKX2105: invalid content between declarations",
      });
      break; // one report, like the compiler's first-error stop
    }
    // T2.6: real content BEFORE the first declaration (a stray statement; a misspelled directive
    // already gets its own 0300 above, so `@...` lines are skipped here — and `import` lines are
    // preamble, never junk).
    if (first) {
      let p2 = 0;
      while (p2 < first.declStart) {
        const k = skipNoncode(src, p2);
        if (k !== p2) {
          p2 = k;
          continue;
        }
        if (/[ \t\r\n]/.test(src[p2])) {
          p2++;
          continue;
        }
        if (src[p2] === "@") {
          const nl = src.indexOf("\n", p2);
          p2 = nl === -1 ? src.length : nl + 1;
          continue;
        }
        if (src.startsWith("import", p2) && !isIdent(src[p2 + 6] ?? "")) {
          const nl = src.indexOf("\n", p2);
          p2 = nl === -1 ? src.length : nl + 1;
          continue;
        }
        break;
      }
      if (p2 < first.declStart) {
        let le2 = src.indexOf("\n", p2);
        if (le2 === -1 || le2 > first.declStart) le2 = first.declStart;
        out.push({
          start: p2,
          end: Math.max(p2 + 1, le2),
          code: "GUITKX2105",
          message: `GUITKX2105: invalid content before the \`${first.kw !== "" ? first.kw : first.kind}\` declaration`,
        });
      }
    }
  }

  // T2.6 naming (Unity 2100/2203) + ES-modules (2320/2321): PascalCase components (both forms);
  // 2203 fires ONLY on deprecated hook wrappers (E-03 -- under E-01 the use_ prefix IS the
  // classification, a helper without it is simply a util); one 2320 deprecation warning per
  // wrapper decl; 2321 on the use_-prefixed-returns-RuitkVNode cross-guard (E-02).
  for (const d of decls) {
    const isComp = d.kind === "component" || (d.kind === "member" && d.kw === "component");
    if (isComp && d.name !== "" && !/^[A-Z]/.test(d.name) && !d.crossGuard) {
      out.push({
        start: d.nameStart,
        end: d.nameEnd,
        code: "GUITKX2100",
        message: `GUITKX2100: component name \`${d.name}\` must be PascalCase`,
      });
    }
    if (d.kw === "hook" && d.deprecated !== false && d.name !== "" && !d.name.startsWith("use_")) {
      out.push({
        start: d.nameStart,
        end: d.nameEnd,
        code: "GUITKX2203",
        message: `GUITKX2203: hook name \`${d.name}\` should start with \`use_\``,
        severity: "warning",
      });
    }
    if (d.deprecated === true && d.kw !== "" && !d.module) {
      out.push({
        start: d.declStart,
        end: d.declStart + d.kw.length,
        code: "GUITKX2320",
        message: `GUITKX2320: the \`${d.kw}\` wrapper keyword is deprecated -- write a plain declaration (the codemod rewrites it: dev/migrate_0_11_0.gd); the wrapper is removed in a later minor`,
        severity: "warning",
      });
    }
    if (d.crossGuard) {
      out.push({
        start: d.nameStart,
        end: d.nameEnd,
        code: "GUITKX2321",
        message: `GUITKX2321: \`${d.name}\` is \`use_\`-prefixed but returns a markup node -- did you mean a component? (components are PascalCase and return RuitkVNode)`,
      });
    }
  }
  return out;
}

// First real (non-whitespace, non-comment) offset at/after `from`, or -1. Mirrors guitkx.gd _first_real.
function firstRealAfter(src: string, from: number): number {
  let i = from;
  while (i < src.length) {
    const k = skipNoncode(src, i);
    if (k !== i) {
      i = k;
      continue;
    }
    if (!/[ \t\r\n]/.test(src[i])) return i;
    i++;
  }
  return -1;
}
