// Workspace component index (Phase 6b) for go-to-definition / find-references on <Tag> references.
// Keyed by BINDING IDENTITY = (@class_name override) ?? (component decl name) — NOT basename: a
// cross-file <Foo/> compiles to V.fc(Foo.render, ...) where `Foo` is the generated class_name, which
// the @class_name preamble can override (the decl name may even differ — GUITKX0103). Module members
// bind by their member name (intra-module). Multi-valued byName + byUri eviction (Unity's model) so a
// copy+rename never deletes a live declarant.

import { skipNoncode, findMatching, findMatchingMarkup, keywordAt, isIdent } from "./scanner";
import { findDecl, valueEnd, declBodyOf } from "./declScan";
import { isTagBoundary } from "./refs";
import { readdirSync, readFileSync } from "fs";
import { join } from "path";

export interface DeclInfo {
  kind: "component" | "hook" | "module" | "member" | "value" | "util";
  kw: "component" | "hook" | "module" | ""; // the wrapper keyword ("" = plain E-01 declaration)
  deprecated?: boolean; // true = wrapper-keyword form (0.11.0 deprecation window)
  crossGuard?: boolean; // plain decl: use_-prefixed AND -> RuitkVNode (GUITKX2321)
  name: string;
  binding: string;
  module?: string;
  nameStart: number;
  nameEnd: number;
  declStart: number; // offset of the component/hook/module keyword (for documentSymbol range)
  declEnd: number; // offset just past the closing `}` (or nameEnd if bodyless) — also bounds a module's members
  export?: boolean; // carried an `export` visibility prefix (0.10.0 imports leg); undefined = not exported
  // First component with an `@class_name` override: the override identifier's offsets, so a rename can
  // rewrite the directive in lockstep with the decl name + every `<Tag>` usage (BUG-4). Undefined otherwise.
  classNameStart?: number;
  classNameEnd?: number;
}

interface ClassNameRef {
  text: string;
  start: number;
  end: number;
}

/** All top-level + module-member declarations (not just the first), mirroring the compiler dispatch. */
export function scanDeclarations(src: string): DeclInfo[] {
  const override = readClassName(src);
  return scanRange(src, 0, src.length, override, undefined);
}

function scanRange(src: string, start: number, end: number, override: ClassNameRef | null, mod: string | undefined): DeclInfo[] {
  // ES-modules leg: declarations are SIGNATURE-classified (plain E-01 forms have no keyword), so
  // the scan consumes the shared findDecl (declScan.ts -- the mirror of guitkx.gd _find_decl)
  // instead of a keyword walk. Wrapper rows keep their keyword in `kw`; export markers
  // (`export { ... }` / `export default X`) apply their marks onto the named decls, mirroring
  // guitkx.gd apply_export_markers, and are not indexed themselves.
  const out: DeclInfo[] = [];
  const listedNames: string[] = [];
  const defaultNames: string[] = [];
  let i = start;
  let firstComponent = true;
  while (i < end) {
    const d = findDecl(src, i, false);
    if (d.kind === "" || d.at >= end) break;
    const wrapper = d.deprecated !== false;
    if (d.kind === "export_list") {
      for (const ln of d.listNames ?? []) listedNames.push(ln.name);
      i = d.listEnd ?? d.at + 6;
      continue;
    }
    if (d.kind === "export_default") {
      if (d.name) defaultNames.push(d.name);
      i = d.listEnd ?? d.at + 6;
      continue;
    }
    if (d.kind === "value") {
      const ve = d.valueStart !== undefined ? valueEnd(src, d.valueStart) : -1;
      const nmS = d.nameAt ?? d.at;
      const nmE = nmS + (d.name ?? "").length;
      out.push({
        kind: "value", kw: "", deprecated: false, name: d.name ?? "", binding: d.name ?? "", module: mod,
        nameStart: nmS, nameEnd: nmE, declStart: d.start ?? d.at, declEnd: ve !== -1 ? ve : nmE,
        export: d.export || undefined,
      });
      i = ve !== -1 ? ve : nmE;
      continue;
    }
    if (!wrapper) {
      // Plain callable (component/hook/util).
      const body = declBodyOf(src, d, findMatchingMarkup);
      const nmS = d.nameAt ?? d.at;
      const nmE = nmS + (d.name ?? "").length;
      const isComp = d.kind === "component";
      const useOverride = isComp && !mod && firstComponent && override != null;
      if (isComp) firstComponent = false;
      out.push({
        kind: mod && (d.kind === "component" || d.kind === "hook") ? "member" : (d.kind as DeclInfo["kind"]),
        kw: "", deprecated: false, crossGuard: d.crossGuard || undefined,
        name: d.name ?? "", binding: useOverride ? override!.text : (d.name ?? ""), module: mod,
        nameStart: nmS, nameEnd: nmE, declStart: d.start ?? d.at, declEnd: body ? body.close + 1 : nmE,
        export: d.export || undefined,
        classNameStart: useOverride ? override!.start : undefined,
        classNameEnd: useOverride ? override!.end : undefined,
      });
      i = body ? body.close + 1 : nmE + 1;
      continue;
    }
    // Wrapper row (deprecation window) -- the shipped walk shape.
    const kw = d.kind as "component" | "hook" | "module";
    const kind: DeclInfo["kind"] = kw === "module" ? "module" : mod ? "member" : kw;
    const declStart = d.at;
    const j = skipWs(src, d.at + kw.length);
    const nm = readIdent(src, j);
    if (nm.text === "") {
      i = j + 1;
      continue;
    }
    const isComp = kw === "component";
    const useOverride = isComp && !mod && firstComponent && override != null;
    const binding = useOverride ? override!.text : nm.text;
    if (isComp) firstComponent = false;
    const body = readBody(src, nm.end, isComp);
    const declEnd = body ? body.end + 1 : nm.end;
    out.push({
      kind, kw, deprecated: true, name: nm.text, binding, module: mod, nameStart: nm.start, nameEnd: nm.end, declStart, declEnd,
      export: d.export || undefined,
      classNameStart: useOverride ? override!.start : undefined,
      classNameEnd: useOverride ? override!.end : undefined,
    });
    if (kw === "module" && body) out.push(...scanRange(src, body.start, body.end, null, nm.text));
    i = declEnd;
  }
  // Apply the E-07/E-09 export marks (a listed/defaulted decl reads as exported -- M1.3).
  for (const d2 of out) {
    if (!d2.module && (listedNames.includes(d2.name) || defaultNames.includes(d2.name))) d2.export = true;
  }
  return out;
}

function readClassName(src: string): ClassNameRef | null {
  const n = src.length;
  let i = 0;
  while (i < n) {
    i = skipWs(src, i);
    const k = skipNoncode(src, i);
    if (k !== i) {
      i = k;
      continue;
    }
    if (src.startsWith("@class_name", i) && (i + 11 >= n || /\s/.test(src[i + 11]))) {
      // Read the override on the SAME line (skip only spaces/tabs, never a newline), matching the
      // compiler's read-to-EOL — so a bare `@class_name` does not grab the following `component`
      // keyword as the override (which a rename would then rewrite, BUG-4).
      let p = i + 11;
      while (p < n && (src[p] === " " || src[p] === "\t")) p++;
      const id = readIdent(src, p);
      return id.text ? { text: id.text, start: id.start, end: id.end } : null;
    }
    if (keywordAt(src, i, "component") || keywordAt(src, i, "hook") || keywordAt(src, i, "module")) break;
    if (keywordAt(src, i, "import")) {
      // skip the whole import statement (its specifier string is skipped by skipNoncode above)
      let le = src.indexOf("\n", i);
      if (le === -1) le = n;
      i = le;
      continue;
    }
    if (src[i] === "@") {
      // Any other @-directive line (@uss/@theme) — skip it whole, keeping the scan ORDER-AGNOSTIC
      // (the 0.10.0 rule: @class_name may sit before or after other preamble lines). Without this,
      // the plain-decl break below fired on the directive WORD and a trailing @class_name was lost.
      let le2 = src.indexOf("\n", i);
      if (le2 === -1) le2 = n;
      i = le2;
      continue;
    }
    if (isIdent(src[i]) && (i === 0 || !isIdent(src[i - 1]))) break; // a plain E-01 decl head
    i++;
  }
  return null;
}

// `markupBody`: true for a "component" declaration (its body mixes GDScript setup with a markup
// return -- G-01, see scanner.ts findMatchingMarkup). false for "hook"/"module" (pure/mixed
// GDScript -- see virtualDoc.ts readDeclBody's docstring for why module stays GDScript-lexis too).
function readBody(src: string, from: number, markupBody = false): { start: number; end: number } | null {
  const n = src.length;
  let j = from;
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
  return { start: j + 1, end: close };
}

function skipWs(src: string, i: number): number {
  while (i < src.length && /\s/.test(src[i])) i++;
  return i;
}
function readIdent(src: string, i: number): { text: string; start: number; end: number } {
  const start = i;
  while (i < src.length && isIdent(src[i])) i++;
  return { text: src.slice(start, i), start, end: i };
}

// --- the index ---

export interface IndexEntry {
  uri: string;
  binding: string;
  name: string;
  kind: string;
  module?: string;
  export?: boolean;
  nameStart: number;
  nameEnd: number;
  classNameStart?: number;
  classNameEnd?: number;
}

export class WorkspaceIndex {
  private byName = new Map<string, IndexEntry[]>();
  private byUri = new Map<string, IndexEntry[]>();
  ready = false;

  reindex(rawUri: string, text: string): void {
    const uri = normalizeUri(rawUri);
    this.evict(uri);
    let decls: DeclInfo[];
    try {
      decls = scanDeclarations(text);
    } catch {
      return; // parse-failure tolerant: keep nothing rather than corrupt the index
    }
    // 0.10.0 MIXED-DECL: the compiler now compiles EVERY top-level declaration (components, hooks,
    // modules) plus module members -- not just the first. Index them all so cross-file go-to-def,
    // find-references, and tag completion resolve the 2nd+ declaration of a mixed file too. (The old
    // T1.3 first-only filter reflected the pre-mixed "one decl per file, rest is a 2105 error" model.)
    const entries: IndexEntry[] = decls.map((d) => ({
      uri,
      binding: d.binding,
      name: d.name,
      kind: d.kind,
      module: d.module,
      export: d.export,
      nameStart: d.nameStart,
      nameEnd: d.nameEnd,
      classNameStart: d.classNameStart,
      classNameEnd: d.classNameEnd,
    }));
    this.byUri.set(uri, entries);
    for (const e of entries) {
      const arr = this.byName.get(e.binding) ?? [];
      arr.push(e);
      this.byName.set(e.binding, arr);
    }
  }

  evict(rawUri: string): void {
    const uri = normalizeUri(rawUri);
    const prev = this.byUri.get(uri);
    if (!prev) return;
    this.byUri.delete(uri);
    for (const e of prev) {
      const arr = this.byName.get(e.binding);
      if (!arr) continue;
      const left = arr.filter((x) => x.uri !== uri);
      if (left.length) this.byName.set(e.binding, left);
      else this.byName.delete(e.binding);
    }
  }

  lookup(name: string): IndexEntry[] {
    return this.byName.get(name) ?? [];
  }
  has(name: string): boolean {
    return this.byName.has(name);
  }
  names(): string[] {
    return [...this.byName.keys()];
  }
  entriesFor(uri: string): IndexEntry[] {
    return this.byUri.get(normalizeUri(uri)) ?? [];
  }
  uris(): string[] {
    return [...this.byUri.keys()];
  }
}

// T4.5 — the virtual library mirroring a `.guitkx`'s compiled bindings. Fed to the GDScript
// analyzer (server.syncGuitkxLibrary) so cross-file references resolve on a fresh clone, where the
// real generated sibling `.gd` is git-ignored. This REPLACES the old `vetoGuitkxDeclared`
// suppression: the veto dropped UNDEFINED_FUNCTION/IDENTIFIER for ANY index-known name, so a typo
// colliding with a `.guitkx` binding was silent — declaring the binding for real makes resolution
// honest both ways (the real name resolves; `usse_state` stays an error). Member stubs are
// VARIADIC (`...args`) so the analyzer's arity checking can never false-fire through a stub, and
// Variant-typed (the seam claims nothing). `null` when the file declares nothing indexable.
export function guitkxVirtualLibText(entries: IndexEntry[]): string | null {
  const candidates = entries.filter((e) => e.kind !== "member");
  if (candidates.length === 0 || !/^[A-Za-z_][A-Za-z0-9_]*$/.test(candidates[0].binding)) return null;
  // Mirror the compiler's binding rule (first EXPORTED top-level decl, else the first) and its
  // VALUE-binding exception (F5 round 2): the real compiled .gd emits NO class_name when the
  // binding decl is a value (`class_name something` + `static var something` made every bare
  // self-reference resolve to the class type), so the mirror must not register that phantom
  // global class either. Member statics still emit — preload-based resolution keys on the
  // library's res path, class_name or not.
  const bindingEntry = candidates.find((e) => e.export) ?? candidates[0];
  const bindingIsComponent = bindingEntry.kind === "component";
  const emitClass = bindingEntry.kind !== "value" && /^[A-Za-z_][A-Za-z0-9_]*$/.test(bindingEntry.binding);
  const lines = [
    "# @generated by the guitkx language server — virtual mirror of the sibling .guitkx's",
    "# compiled bindings (the real generated .gd is git-ignored on a fresh clone).",
  ];
  if (emitClass) lines.push(`class_name ${bindingEntry.binding}`);
  lines.push("");
  if (bindingIsComponent) lines.push("static func render(...args): return null");
  // Every OTHER declaration mirrors the compiled .gd's statics — wrapper-module members AND the
  // new-mode plain declarations (0.11.1 field wave: a member-only new-mode file mirrored an EMPTY
  // class, so its exports never existed in the analysis while the real compiled .gd had them all;
  // the Unity sibling shipped the same fix for its __Exports container). Values mirror as
  // `static var` (data, not callable); callables stay variadic so arity checks can't false-fire.
  const seen = new Set<string>([bindingIsComponent ? "render" : ""]);
  for (const m of entries) {
    if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(m.name)) continue;
    if (m === bindingEntry && bindingIsComponent) continue; // the binding component IS `render`
    if ((emitClass && m.name === bindingEntry.binding) || seen.has(m.name)) continue;
    seen.add(m.name);
    if (m.kind === "value") lines.push(`static var ${m.name}`);
    else lines.push(`static func ${m.name}(...args): return null`);
  }
  return lines.join("\n") + "\n";
}

/** Recursively walk a project dir, indexing every .guitkx (skips dot-dirs like .godot/.git). */
export function scanWorkspace(index: WorkspaceIndex, rootPath: string): void {
  if (rootPath) walk(rootPath, index);
  index.ready = true;
}

function walk(dir: string, index: WorkspaceIndex): void {
  let entries;
  try {
    entries = readdirSync(dir, { withFileTypes: true });
  } catch {
    return;
  }
  for (const e of entries) {
    if (e.name.startsWith(".")) continue;
    const p = join(dir, e.name);
    if (e.isDirectory()) walk(p, index);
    else if (e.name.endsWith(".guitkx")) {
      try {
        index.reindex(pathToUri(p), readFileSync(p, "utf8"));
      } catch {
        /* unreadable file — skip */
      }
    }
  }
}

export function pathToUri(p: string): string {
  let n = p.replace(/\\/g, "/");
  if (!n.startsWith("/")) n = "/" + n;
  return normalizeUri("file://" + encodeURI(n).replace(/[?#]/g, (c) => "%" + c.charCodeAt(0).toString(16)));
}

// Canonicalize a file URI so disk-walked paths and editor URIs key the same index entry: lowercase the
// Windows drive letter and encode its colon as %3A (VS Code's form, e.g. file:///c%3A/Users/...).
export function normalizeUri(uri: string): string {
  const m = /^file:\/\/\/([A-Za-z])(?::|%3[Aa])(\/.*)$/.exec(uri);
  return m ? `file:///${m[1].toLowerCase()}%3A${m[2]}` : uri;
}

/** Component <Tag> identity under `offset`, or null. PascalCase only (lowercase = host factory). */
export function componentTagAt(src: string, offset: number): string | null {
  let s = offset;
  let e = offset;
  while (s > 0 && isIdent(src[s - 1])) s--;
  while (e < src.length && isIdent(src[e])) e++;
  if (s === e) {
    // Cursor isn't inside an identifier — it sits on the `<`, the closing-tag `/`, or whitespace
    // between them (common with a mouse-driven ctrl+click on a tab-indented tag, where F12 with a
    // caret inside the name would have worked). Look RIGHT to the following tag name so navigation,
    // find-references, and rename all work from the tag opener too.
    let p = offset;
    if (src[p] === "<") p++;
    if (src[p] === "/") p++;
    while (p < src.length && (src[p] === " " || src[p] === "\t")) p++;
    s = p;
    e = p;
    while (e < src.length && isIdent(src[e])) e++;
    if (s === e) return null;
  }
  const name = src.slice(s, e);
  if (!/^[A-Z]/.test(name)) return null;
  let b = s - 1;
  const closing = src[b] === "/";
  if (closing) b--;
  while (b > 0 && (src[b] === " " || src[b] === "\t")) b--;
  if (src[b] !== "<") return null;
  // An opening `<Name` must sit at a tag boundary so a GDScript comparison `a < Name` (cursor on the
  // `<` or inside the PascalCase RHS) is not mistaken for a tag; a closing `</Name>` is unambiguous.
  return closing || isTagBoundary(src, b) ? name : null;
}

export function offsetToPosition(text: string, offset: number): { line: number; character: number } {
  let line = 0;
  let last = 0;
  for (let i = 0; i < offset && i < text.length; i++) {
    if (text[i] === "\n") {
      line++;
      last = i + 1;
    }
  }
  return { line, character: offset - last };
}
