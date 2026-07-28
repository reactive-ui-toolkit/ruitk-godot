import { test } from "node:test";
import assert from "node:assert";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { findMatching, findMatchingMarkup, skipNoncode, skipNoncodeMarkup, keywordAt } from "../scanner";
import { SourceMap, offsetToPosition, positionToOffset } from "../sourceMap";
import { buildVirtualDoc } from "../virtualDoc";
import { declarationDiags } from "../declarations";
import { scanDeclarations, WorkspaceIndex, componentTagAt, guitkxVirtualLibText } from "../workspaceIndex";
import { classProperties, classSignals } from "../classdb";
import { eventCompletionsFor, resolveSignalName, validEventAttrs, isEventAttr } from "../events";
import { formatGuitkx, fmtAttr, FmtOptions, markupWindows, missingReturnComponents, unreachableRegions, setupSpans } from "../formatGuitkx";
import { windowStructureDiags, hookContextDiags } from "../liveMarkup";
import { findDecl } from "../declScan";
import { tokenEquivalent, reflowEmbedded } from "../reflowEmbedded";
import { scanTagRefs } from "../refs";
import { buildSemanticTokens, encodeTokens, TOKEN_TYPES } from "../semanticTokens";
import { classifyContext } from "../context";
import { normalizeUri } from "../workspaceIndex";
import { srcHash } from "../diagsSidecar";
import { parseMarkup } from "../markup";
import { AnalyzerAdapter } from "../analyzerAdapter";

test("findMatching balances braces, skipping strings/comments", () => {
  const s = '{ a = "}" # }\n ; b }';
  assert.equal(findMatching(s, 0), s.length - 1);
});

test("scanDeclarations keys component binding by @class_name override", () => {
  const src = "@class_name Fancy\ncomponent Card(title: String) {\n\treturn ( <Label /> )\n}\n";
  const decls = scanDeclarations(src);
  assert.equal(decls.length, 1);
  assert.equal(decls[0].name, "Card");
  assert.equal(decls[0].binding, "Fancy"); // tag-binding identity, NOT basename/decl-name
});

test("scanDeclarations enumerates module members with enclosing module", () => {
  const src = "module M {\n component A() { return (<Label />) }\n component B() { return (<A />) }\n}\n";
  const names = scanDeclarations(src).map((d) => d.name);
  assert.ok(names.includes("M") && names.includes("A") && names.includes("B"));
  assert.equal(scanDeclarations(src).find((d) => d.name === "A")!.module, "M");
});

test("componentTagAt resolves PascalCase tags and ignores lowercase host factories", () => {
  const a = "return (<Card />)";
  assert.equal(componentTagAt(a, a.indexOf("Card") + 1), "Card");
  const b = "return (<VBoxContainer />)";
  assert.equal(componentTagAt(b, b.indexOf("vbox") + 1), null);
});

test("WorkspaceIndex multi-valued lookup + eviction", () => {
  const idx = new WorkspaceIndex();
  idx.reindex("file:///X.guitkx", "component Card() { return (<Label />) }");
  assert.equal(idx.lookup("Card").length, 1);
  idx.evict("file:///X.guitkx");
  assert.equal(idx.lookup("Card").length, 0);
});

test("parseMarkup is structurally identical to the GDScript parser over the shared markup corpus", () => {
  const corpus = JSON.parse(readFileSync(join(__dirname, "..", "..", "test-fixtures", "markup-cases.json"), "utf8"));
  assert.ok(corpus.length >= 13, "markup corpus should have the generated cases");
  for (const c of corpus) {
    const r = parseMarkup(c.input, 0, c.input.length);
    assert.equal(r.error, c.error, `parser error for '${c.name}'`);
    // deep-equal is key-order-independent (GDScript JSON.stringify sorts keys; TS does not)
    assert.deepStrictEqual(r.nodes, JSON.parse(c.tree), `parser node tree for '${c.name}'`);
  }
});

test("parseMarkup handles a `<`/`>` comparison inside a child {expr} (the structural-fix bug class)", () => {
  assert.equal(parseMarkup("<Label>{ a < b }</Label>", 0, 24).error, ""); // was GUITKX0301
  assert.equal(parseMarkup("<Label v={a > b}/>", 0, 18).error, "");
  assert.equal(parseMarkup("<VBox><HBox></VBox>", 0, 19).error.startsWith("GUITKX0302"), true); // still errors
});

test("formatGuitkx is byte-identical to the GDScript formatter over the shared golden corpus", () => {
  const corpus = JSON.parse(readFileSync(join(__dirname, "..", "..", "test-fixtures", "formatter-cases.json"), "utf8"));
  assert.ok(corpus.length >= 9, "corpus should have the generated cases");
  for (const c of corpus) {
    assert.equal(formatGuitkx(c.input).text, c.expected, `formatter case '${c.name}' must match GDScript output`);
    assert.equal(formatGuitkx(c.expected).text, c.expected, `formatter case '${c.name}' must be idempotent`);
  }
});

test("G-05: fmtAttr flags o._unsafeStrAttr for a str value with an embedded quote (parser can't produce this today; safety-net test)", () => {
  const o = { printWidth: 100, indentStyle: "space", indentSize: 2, singleAttributePerLine: false, insertSpaceBeforeSelfClose: true } as FmtOptions;
  fmtAttr({ name: "text", kind: "str", value: "safe", at: 0, vat: 0, end: 0 }, o);
  assert.equal(o._unsafeStrAttr, undefined, "a normal str attr must not flag unsafe");
  fmtAttr({ name: "text", kind: "str", value: 'has " inside', at: 0, vat: 0, end: 0 }, o);
  assert.equal(o._unsafeStrAttr, true, "an embedded quote must flag unsafe");
});

test("G-06: formatGuitkx.fellBack distinguishes a parse-error fallback from an already-canonical file", () => {
  const broken = 'component Broken {\n  return (\n    <Label text="x"\n  )\n}\n'; // unclosed tag
  const r1 = formatGuitkx(broken);
  assert.equal(r1.text, broken, "verbatim on parse error");
  assert.equal(r1.fellBack, true, "parse error must report fellBack");

  const empty = "";
  const r2 = formatGuitkx(empty);
  assert.equal(r2.fellBack, false, "nothing-to-format is not a syntax-error fallback");

  const canonical = 'component Ok {\n  return (\n    <Label text="x" />\n  )\n}\n';
  const r3 = formatGuitkx(canonical);
  assert.equal(r3.changed, false);
  assert.equal(r3.fellBack, false, "an already-canonical file must not report fellBack");
});

test("scanTagRefs: jsx-as-value ref after a value keyword counts; a comparison does not", () => {
  assert.equal(scanTagRefs("x = cond if c else <Card />", "Card").length, 1); // else <Card/> is a ref
  assert.equal(scanTagRefs("if a < Card: pass", "Card").length, 0); // `a < Card` is a comparison
  assert.equal(scanTagRefs('<VBox><Card key="x" /></VBox>', "Card").length, 1); // plain child ref
});

test("buildSemanticTokens only scans markup windows — a `<` in setup GDScript is never mis-tokenized", () => {
  // `a<B` in the setup would, under a whole-doc scan, be read as a `<B` tag and spew bogus tokens.
  const src = 'component X() {\n\tvar t = a<B\n\treturn (\n\t\t<Label text="hi" />\n\t)\n}\n';
  const data = buildSemanticTokens(src, () => false);
  assert.equal(data.length, 10); // exactly 2 tokens — <Label> + text — setup excluded
  assert.equal(data[3], TOKEN_TYPES.indexOf("type")); // host 'type' (Label)
  assert.equal(data[8], TOKEN_TYPES.indexOf("property")); // 'property' (attr name `text`)
});

test("normalizeUri canonicalizes the Windows drive so disk + editor URIs key the same entry", () => {
  assert.equal(normalizeUri("file:///C:/a/b.guitkx"), "file:///c%3A/a/b.guitkx");
  assert.equal(normalizeUri("file:///c%3A/a/b.guitkx"), "file:///c%3A/a/b.guitkx");
  assert.equal(normalizeUri("file:///tmp/x.guitkx"), "file:///tmp/x.guitkx"); // non-Windows untouched
});

test("srcHash iterates code points (astral-plane safe) and stays stable for ASCII", () => {
  assert.equal(srcHash("hello"), 1335831723); // matches the GDScript src_hash cross-check
  assert.equal(typeof srcHash("emoji 😀 here"), "number"); // no surrogate-pair miscount / crash
});

test("gdformat reflow safety net: token-equivalence ignores whitespace/quote, rejects structural change", () => {
  assert.ok(tokenEquivalent("var a=b+c", "var a = b + c")); // whitespace only -> equivalent
  assert.ok(tokenEquivalent("x = 'hi'", 'x = "hi"')); // quote style -> equivalent
  assert.ok(!tokenEquivalent("[a, b]", "[a, b,]")); // trailing comma -> rejected (conservative)
  assert.ok(!tokenEquivalent("a + b", "a - b")); // operator change -> rejected
  // G-17: a comment is part of the token stream now -- trailing whitespace inside it still doesn't
  // count, but its CONTENT does, so a formatter bug that deletes/mangles a comment is rejected.
  assert.ok(tokenEquivalent("var a = 1 # note", "var a = 1 # note   "), "trailing ws inside a comment is insignificant");
  assert.ok(!tokenEquivalent("var a = 1 # note", "var a = 1"), "a DROPPED comment must be rejected, not silently equivalent");
  assert.ok(!tokenEquivalent("var a = 1 # note", "var a = 1 # different"), "a MANGLED comment must be rejected");
});

test("reflowEmbedded reflows embedded GDScript via the analyzer formatter, token-equivalently (BUG-1)", () => {
  const az = new AnalyzerAdapter();
  const fmt = (gd: string) => az.formatGd(gd);
  // `var a=1` (no spaces) — the analyzer's gdscript-fmt should normalize it the same as in a real .gd.
  const formatted = "component X {\n\tvar a=1\n\treturn (\n\t\t<Label />\n\t)\n}\n";
  const out = reflowEmbedded(formatted, fmt);
  assert.ok(tokenEquivalent(formatted, out), "reflow only changes whitespace/quote style, never tokens");
  // a no-op formatter leaves the document untouched (the safety/identity path)
  assert.equal(reflowEmbedded(formatted, () => null), formatted, "a formatter that declines leaves the region as-is");
  // G-17: a formatter that drops a comment (simulating a gdscript-fmt bug) must be rejected --
  // the region stays exactly as authored, comment included.
  const withComment = "component Y {\n\tvar a = 1 # keep me\n\treturn (\n\t\t<Label />\n\t)\n}\n";
  const dropCommentFmt = (gd: string) => gd.replace(/ # keep me/, "");
  assert.equal(reflowEmbedded(withComment, dropCommentFmt), withComment, "a comment-dropping reflow must be rejected, region left untouched");
});

test("classdb dump base-flattens Button props (text + inherited disabled) and signals", () => {
  const props = classProperties("Button").map((p) => p.name);
  assert.ok(props.includes("text")); // own
  assert.ok(props.includes("disabled")); // inherited from BaseButton
  assert.ok(classSignals("Button").some((s) => s.name === "pressed"));
});

test("skipNoncode skips line comments and strings", () => {
  assert.equal(skipNoncode("# c\nx", 0), 3);
  assert.equal(skipNoncode('"ab"x', 0), 4);
  assert.equal(skipNoncode('"""a\nb"""x', 0), 9);
  assert.equal(skipNoncode("xyz", 0), 0);
});

test("skipNoncode handles node-path string prefixes with a token-boundary guard", () => {
  assert.equal(skipNoncode('$"a/b"x', 0), 6); // $"a/b" node-path string skipped
  assert.equal(skipNoncode('%"u"x', 0), 4); // %"u" unique-name string skipped
  assert.equal(skipNoncode('&"n"', 0), 4); // &"n" StringName
  assert.equal(skipNoncode('^"p"', 0), 4); // ^"p" NodePath
  // operators after a value must NOT be treated as a string prefix
  assert.equal(skipNoncode('a%"f"', 1), 1); // % after 'a' -> format operator, not skipped
  assert.equal(skipNoncode('b&"x"', 1), 1); // & after 'b' -> bitwise op, not skipped
  // R is no longer a prefix (byte-identity with guitkx_lexer.gd)
  assert.equal(skipNoncode('R"x"', 0), 0);
});

test("scanner stays byte-identical with the GDScript lexer (shared fixture)", () => {
  const fx = JSON.parse(readFileSync(join(__dirname, "..", "..", "test-fixtures", "scanner-cases.json"), "utf8"));
  for (const c of fx.skipNoncode)
    assert.equal(skipNoncode(c.input, c.at), c.expect, `skipNoncode(${JSON.stringify(c.input)}, ${c.at})`);
  for (const c of fx.findMatching)
    assert.equal(findMatching(c.input, c.at), c.expect, `findMatching(${JSON.stringify(c.input)}, ${c.at})`);
});

test("G-01: skipNoncodeMarkup/findMatchingMarkup stay byte-identical with the GDScript lexer (shared fixture)", () => {
  const fx = JSON.parse(readFileSync(join(__dirname, "..", "..", "test-fixtures", "scanner-cases.json"), "utf8"));
  for (const c of fx.skipNoncodeMarkup)
    assert.equal(skipNoncodeMarkup(c.input, c.at), c.expect, `skipNoncodeMarkup(${JSON.stringify(c.input)}, ${c.at})`);
  for (const c of fx.findMatchingMarkup)
    assert.equal(findMatchingMarkup(c.input, c.at), c.expect, `findMatchingMarkup(${JSON.stringify(c.input)}, ${c.at})`);
});

test("keywordAt respects identifier boundaries", () => {
  assert.ok(keywordAt("component X", 0, "component"));
  assert.ok(!keywordAt("components", 0, "component"));
  assert.ok(!keywordAt("xcomponent", 1, "component"));
});

test("SourceMap round-trips offsets within a span", () => {
  const m = new SourceMap();
  m.addSpan(10, 50, 5);
  assert.equal(m.toGenerated(12), 52);
  assert.equal(m.toSource(52), 12);
  assert.equal(m.toGenerated(100), null);
  assert.equal(m.toSource(5), null);
});

test("offset <-> position helpers agree", () => {
  const text = "ab\ncde\nf";
  const pos = offsetToPosition(text, 5); // 'd' on line 1
  assert.deepEqual(pos, { line: 1, character: 2 });
  assert.equal(positionToOffset(text, pos), 5);
});

test("virtualDoc splices setup + {expr} with a correct round-trip mapping", () => {
  const src = [
    "component Counter(start: int = 0) {",
    "\tvar s = useState(start)",
    "\treturn (",
    "\t\t<Label text={ str(s[0]) } />",
    "\t)",
    "}",
  ].join("\n");
  const { text, map } = buildVirtualDoc(src);
  assert.ok(text.includes("static func render(props: Dictionary, children: Array)"), "has render scaffold");
  assert.ok(text.includes("var s = useState(start)"), "setup spliced verbatim");
  assert.ok(text.includes("str(s[0])"), "expr spliced");
  const exprIdx = src.indexOf("str(s[0])") + 1; // inside the expr
  const genIdx = map.toGenerated(exprIdx);
  assert.notEqual(genIdx, null, "source offset maps into generated");
  assert.equal(map.toSource(genIdx!), exprIdx, "generated maps back to source");
});

test("virtualDoc normalises mixed tab/space setup indentation to pure tabs (no phantom unindent)", () => {
  // `\t  ` (tab + 2 spaces) renders like `\t\t` but is byte-different; a naive dedent carries that
  // mismatch into the analyser as a phantom "unindent doesn't match". The virtual .gd must be tab-only.
  const src = "component X {\n\t\tvar a = useState(0)\n\t  var b = useState(0)\n\treturn ( <Label /> )\n}\n";
  const { text } = buildVirtualDoc(src);
  for (const line of text.split("\n")) {
    const lead = line.match(/^[\t ]*/)![0];
    assert.ok(!lead.includes(" "), `virtual doc must indent with tabs only, got ${JSON.stringify(line)}`);
  }
  assert.ok(text.includes("var b = useState(0)"), "the mixed-indent setup line is still present");
});

test("virtualDoc: one outlier-shallow setup line does not shift the rest (first-line anchor)", () => {
  // A min-depth anchor let `var b` at column 0 push `var a`/`if` one level deeper — an over-indented
  // statement with no preceding `:` = invalid virtual .gd and a whole diagnostic cascade. [BUG: G1]
  const src = "component X {\n\tvar a = useState(0)\nvar b = 1\n\tif a[0]:\n\t\tb += 1\n\treturn ( <Label /> )\n}\n";
  const { text } = buildVirtualDoc(src);
  assert.ok(text.includes("\n\tvar a = useState(0)"), `normal lines stay at body level, got ${JSON.stringify(text)}`);
  assert.ok(text.includes("\n\tvar b = 1"), "outlier line clamps up to body level");
  assert.ok(text.includes("\n\tif a[0]:"), "if header stays at body level");
  assert.ok(text.includes("\n\t\tb += 1"), "nested depth is preserved");
});

// The LSP "floor": a misspelled declaration keyword used to make the whole file go dark (no markup
// window -> no analysis, no diagnostics). declarationDiags reports it live instead of silence.
test("declarationDiags flags a misspelled `component` keyword (GUITKX2101)", () => {
  // E-01: a typo followed by a real plain-decl shape (`X { ... }` is a paramless util) reads as
  // junk-before-decl (2105), mirroring the compiler; the pure typo (no decl anywhere) keeps 2101.
  const shadowed = declarationDiags("@class_name X\ncomssponent X {\n\treturn ( <Label /> )\n}\n");
  assert.ok(shadowed.some((x) => x.code === "GUITKX2105"), `got ${JSON.stringify(shadowed)}`);
  const d = declarationDiags("@class_name X\ncomssponent X\n");
  assert.ok(d.some((x) => x.code === "GUITKX2101" && /did you mean 'component'/.test(x.message)), `got ${JSON.stringify(d)}`);
});

test("declarationDiags flags a mistyped @class_name value (GUITKX0300)", () => {
  const d = declarationDiags("@class_name 9bad\ncomponent X {\n\treturn ( <Label /> )\n}\n");
  assert.ok(d.some((x) => x.code === "GUITKX0300"), `got ${JSON.stringify(d)}`);
});

test("declarationDiags: a fully typo'd header still reports something, never silence", () => {
  const d = declarationDiags("@clasaas_name X\ncomssponent X {\n\treturn ( <Label /> )\n}\n");
  assert.ok(d.length > 0 && d.some((x) => x.code === "GUITKX0300") && d.some((x) => x.code === "GUITKX2105"), `got ${JSON.stringify(d)}`);
});

// G3: a component whose closed body has NO markup return used to be silent live (no markup window →
// every window tier skips it; the virtual doc just emits `pass`) — only the post-save sidecar showed it.
test("missingReturnComponents flags a component with no markup return (live GUITKX2101)", () => {
  const src = "component NoRet() {\n\tvar a = useState(0)\n}\n";
  const hits = missingReturnComponents(src);
  assert.equal(hits.length, 1, `got ${JSON.stringify(hits)}`);
  assert.equal(src.slice(hits[0].start, hits[0].end), "component NoRet", "span anchors the declaration head");
});

test("missingReturnComponents: a lone `return null` guard still counts as missing", () => {
  assert.equal(missingReturnComponents("component G(show: bool) {\n\tif not show:\n\t\treturn null\n}\n").length, 1);
});

test("missingReturnComponents: a TOP-LEVEL `return null` is the legal null-only component (React semantics)", () => {
  // plain E-01 form
  assert.equal(missingReturnComponents("Gone() -> RUIVNode {\n\treturn null\n}\n").length, 0, "null-only plain component");
  // wrapper form, with a conditional guard above the final top-level null
  assert.equal(missingReturnComponents("component Gone(a: bool) {\n\tif a:\n\t\treturn null\n\treturn null\n}\n").length, 0, "null-only wrapper component");
  // the guard-only shape (nested null, fall-through) stays MISSING — totality still enforced
  assert.equal(missingReturnComponents("component Bad(a: bool) {\n\tif a:\n\t\treturn null\n\tvar x = 1\n}\n").length, 1, "fall-through body still flagged");
});

test("formatter: a null-only component formats without inventing a markup return, idempotently", () => {
  const src = "export Gone(active: bool) -> RUIVNode {\n\tif active:\n\t\treturn null\n\treturn null\n}\n";
  const once = formatGuitkx(src).text;
  assert.ok(!once.includes("return (\n"), `no empty markup window invented:\n${once}`);
  assert.ok(once.includes("return null"), "body's own returns preserved");
  assert.equal(formatGuitkx(once).text, once, "idempotent");
});

test("missingReturnComponents stays silent on valid components, hooks, and in-progress typing", () => {
  assert.equal(missingReturnComponents("component Ok() {\n\treturn ( <Label /> )\n}\n").length, 0, "valid component");
  assert.equal(missingReturnComponents("hook use_x() {\n\tvar s = useState(0)\n\treturn s\n}\n").length, 0, "hooks never have markup returns");
  // an unclosed `return (` is the compiler's GUITKX0304 (unclosed paren), not a missing return —
  // flagging it would squiggle every component mid-keystroke.
  assert.equal(missingReturnComponents("component Typing() {\n\treturn (\n}\n").length, 0, "half-typed return (");
  assert.equal(missingReturnComponents("component Open() {\n\tvar a = 1\n").length, 0, "unclosed body is transient");
});

test("missingReturnComponents finds module-member components (and only the broken one)", () => {
  const src = "module M {\n\tcomponent A() { return (<Label />) }\n\tcomponent B() {\n\t\tvar x = 1\n\t}\n}\n";
  const hits = missingReturnComponents(src);
  assert.equal(hits.length, 1, `got ${JSON.stringify(hits)}`);
  assert.equal(src.slice(hits[0].start, hits[0].end), "component B");
});

test("declarationDiags stays silent for a valid header (no false positives)", () => {
  // A wrapper header now carries exactly the G-10 deprecation warning (2320) and no errors;
  // the plain E-01 spelling is fully clean.
  const d = declarationDiags("@class_name X\ncomponent X {\n\treturn ( <Label /> )\n}\n");
  assert.equal(d.filter((x) => x.severity !== "warning").length, 0, `got ${JSON.stringify(d)}`);
  assert.ok(d.some((x) => x.code === "GUITKX2320"), `got ${JSON.stringify(d)}`);
  assert.equal(declarationDiags("@class_name X\nX() -> RUIVNode {\n\treturn ( <Label /> )\n}\n").length, 0);
});

test("declarationDiags flags a misspelled @class_name DIRECTIVE (@clasaas_name -> GUITKX0300)", () => {
  const d = declarationDiags("@clasaas_name X\ncomponent X {\n\treturn ( <Label /> )\n}\n");
  assert.ok(
    d.some((x) => x.code === "GUITKX0300" && /did you mean '@class_name'/.test(x.message)),
    `got ${JSON.stringify(d)}`,
  );
});

// ES-modules: a file is a SEQUENCE of declarations -- a second decl is LEGAL; only junk after the
// LAST declaration is 2105.
test("T1.3: declarationDiags flags content after the LAST top-level declaration (GUITKX2105)", () => {
  const two = "component A() {\n\treturn ( <Label /> )\n}\ncomponent B() {\n\treturn ( <Label /> )\n}\n";
  assert.equal(declarationDiags(two).filter((x) => x.code === "GUITKX2105").length, 0, "a second decl is legal");
  const junk = "component A() {\n\treturn ( <Label /> )\n}\nvar oops = 1\n";
  const d = declarationDiags(junk);
  assert.ok(d.some((x) => x.code === "GUITKX2105"), `got ${JSON.stringify(d)}`);
});

test("T1.3: trailing comments after the declaration stay clean (no 2105)", () => {
  const d = declarationDiags("component A() {\n\treturn ( <Label /> )\n}\n# note\n");
  assert.equal(d.filter((x) => x.code === "GUITKX2105").length, 0, `got ${JSON.stringify(d)}`);
});

test("mixed-decl: the index holds EVERY top-level declaration (BH-05)", () => {
  const idx = new WorkspaceIndex();
  idx.reindex("file:///t/A.guitkx", "export component A() {\n\treturn ( <Label /> )\n}\nexport component B() {\n\treturn ( <Label /> )\n}\n");
  // 0.10.0 compiles both, so both must be indexed for cross-file go-to-def / find-refs / completion.
  assert.ok(idx.has("A") && idx.has("B"), "both top-level decls indexed");
});

test("T1.3: module members still index (the compiler compiles them)", () => {
  const idx = new WorkspaceIndex();
  idx.reindex("file:///t/M.guitkx", "module M {\n\tcomponent A() { return ( <Label /> ) }\n\thook use_y() { return 2 }\n}\n");
  assert.ok(idx.has("M") && idx.has("A") && idx.has("use_y"), "module + both members indexed");
});

// T1.5 (G5): the live tier used to compute markup parse errors then DISCARD them, and never
// checked lowercase tags at all -- `return <s></a>` squiggled nothing while typing.
test("T1.5: window parse errors surface live (<s></a> -> GUITKX0302)", () => {
  const src = "component S() {\n\treturn ( <s></a> )\n}\n";
  const d = windowStructureDiags(src, markupWindows(src));
  assert.ok(d.some((x) => x.code === "GUITKX0302"), `got ${JSON.stringify(d)}`);
});

test("T1.5: unknown lowercase tag fires live with a did-you-mean", () => {
  const src = 'component T() {\n\treturn ( <VBoxContainer><lable text="x" /></VBoxContainer> )\n}\n';
  const d = windowStructureDiags(src, markupWindows(src));
  const hit = d.find((x) => x.code === "GUITKX0105");
  assert.ok(hit && /did you mean <Label>/.test(hit.message), `got ${JSON.stringify(d)}`);
  assert.equal(src.slice(hit!.start, hit!.end), "lable");
});

test("T1.5: unknown tag inside an @if body fires (bodies re-parse with composed offsets)", () => {
  const src = "component B() {\n\treturn ( <VBoxContainer>@if (true) { return ( <lable /> ) }</VBoxContainer> )\n}\n";
  const d = windowStructureDiags(src, markupWindows(src));
  const hit = d.find((x) => x.code === "GUITKX0105");
  assert.ok(hit, `got ${JSON.stringify(d)}`);
  assert.equal(src.slice(hit!.start, hit!.end), "lable");
});

test("T1.5: a broken @if body's parse error surfaces live (bodies are opaque to the window parse)", () => {
  const src = "component B() {\n\treturn ( <VBoxContainer>@if (true) { return ( <Broken> ) }</VBoxContainer> )\n}\n";
  const d = windowStructureDiags(src, markupWindows(src));
  const hit = d.find((x) => x.code === "GUITKX0301");
  assert.ok(hit, `got ${JSON.stringify(d)}`);
  assert.equal(src.slice(hit!.start, hit!.start + 7), "<Broken");
});

test("T1.5: PascalCase tags and known factories stay clean in the vocabulary check", () => {
  const src = "component P() {\n\treturn ( <VBoxContainer><Card /><Label text=\"ok\" /></VBoxContainer> )\n}\n";
  assert.equal(windowStructureDiags(src, markupWindows(src)).length, 0);
});

// T2.4: mid-text braces are literal under the Unity text model -- warn live so migrating authors notice.
test("T2.4: literal braces in text fire the GUITKX0150 migration warning live", () => {
  const src = "component T(n: int = 3) {\n\treturn ( <VBoxContainer><Label>Count: {n} items</Label></VBoxContainer> )\n}\n";
  const d = windowStructureDiags(src, markupWindows(src));
  const hit = d.find((x) => x.code === "GUITKX0150");
  assert.ok(hit && hit.severity === "warning", `got ${JSON.stringify(d)}`);
});

test("T2.6: live naming checks -- 2100 PascalCase error, 2203 use_ warning", () => {
  const d = declarationDiags("component my_widget() {\n\treturn ( <Label /> )\n}\n");
  assert.ok(d.some((x) => x.code === "GUITKX2100"), `got ${JSON.stringify(d)}`);
  const dh = declarationDiags("hook make_thing() {\n\treturn 1\n}\n");
  const hit = dh.find((x) => x.code === "GUITKX2203");
  assert.ok(hit && hit.severity === "warning", `got ${JSON.stringify(dh)}`);
});

test("T2.6: junk before the first declaration is 2105 live (comments/directives skipped)", () => {
  const d = declarationDiags("var oops = 1\ncomponent A() {\n\treturn ( <Label /> )\n}\n");
  assert.ok(d.some((x) => x.code === "GUITKX2105"), `got ${JSON.stringify(d)}`);
  const clean = declarationDiags("# header\n@class_name A\ncomponent A() {\n\treturn ( <Label /> )\n}\n");
  assert.equal(clean.filter((x) => x.severity !== "warning").length, 0, `got ${JSON.stringify(clean)}`);
});

// T2.5: the live routine is the compiler's _validate_hooks ported line-for-line -- same fixtures
// as guitkx_test.gd _test_t25_hook_contexts so the two implementations cannot drift unnoticed.
test("T2.5: hook context codes 0013/0014/0015/0016 fire live over setup spans", () => {
  const mk = (setup: string): string => `component H(c: bool = true, xs: Array = []) {\n${setup}\treturn ( <Label text="x" /> )\n}\n`;
  const codes = (src: string): string[] => hookContextDiags(src, setupSpans(src)).map((d) => d.code);
  assert.deepEqual(codes(mk("\tfor x in xs:\n\t\tvar s = useState(0)\n")), ["GUITKX0014"]);
  assert.deepEqual(codes(mk("\tmatch c:\n\t\ttrue:\n\t\t\tvar s = useState(0)\n")), ["GUITKX0015"]);
  assert.deepEqual(codes(mk("\tvar f = func():\n\t\tvar s = useState(0)\n")), ["GUITKX0016"]);
  assert.deepEqual(codes(mk("\tif c: var s = useState(0)\n")), ["GUITKX0013"]);
  assert.deepEqual(codes(mk("\tvar s = useState(0)\n\tvar my_useState_thing = 1\n")), []);
  // hook declaration bodies are spans too
  assert.deepEqual(codes("hook use_bad(c: bool = false) {\n\tif c:\n\t\tvar s = useState(0)\n\treturn 1\n}\n"), ["GUITKX0013"]);
});

test("T2.5: hook CALL in a markup expression is 0016 live; a hook RESULT is not", () => {
  const bad = 'component A() {\n\treturn ( <Label text={ str(useState(0)[0]) } /> )\n}\n';
  assert.ok(windowStructureDiags(bad, markupWindows(bad)).some((d) => d.code === "GUITKX0016"));
  const ok = 'component OK() {\n\tvar s = useState(0)\n\treturn ( <Label text={ str(s[0]) } on_pressed={ s[1] } /> )\n}\n';
  assert.equal(windowStructureDiags(ok, markupWindows(ok)).filter((d) => d.code === "GUITKX0016").length, 0);
});

test("T2.1/T2.2: comments and <Fragment> stay clean live", () => {
  const src = "component C() {\n\treturn (\n\t\t// note\n\t\t<Fragment>\n\t\t\t<Label {/* why */} text=\"a\" />\n\t\t\t<!-- html -->\n\t\t</Fragment>\n\t)\n}\n";
  assert.equal(windowStructureDiags(src, markupWindows(src)).length, 0);
});

// Error-recovery: a near-miss keyword at a real declaration position is treated as that declaration
// (analysis-only) so a typo'd header no longer blacks out markup + embedded checks. [declScan]
test("findDecl: E-01 classification routes a typo'd wrapper to the plain decl that follows it", () => {
  // `comssponent Foo {` -- under signature classification, `Foo {` is a REAL paramless util
  // declaration; the typo'd word is junk before it (the compiler's 2105), not a recovered header.
  const d1 = findDecl("comssponent Foo {\n}\n", 0, true);
  assert.equal(d1.kind, "util");
  assert.equal(d1.name, "Foo");
  const d2 = findDecl("moduel Foo {\n}\n", 0, true);
  assert.equal(d2.kind, "util");
  // a stray statement like `var content = 5` classifies its tail (`content = 5`) as a VALUE
  // decl -- the compiler view; declarationDiags then flags the leading `var` as 2105 junk.
  const dv = findDecl("var content = 5" + String.fromCharCode(10), 0, true);
  assert.equal(dv.kind, "value");
  assert.equal(dv.name, "content");
  // the formatter path (recover=false) classifies identically -- plain decls need no recovery
  assert.equal(findDecl("comssponent Foo {\n}\n", 0, false).kind, "util");
});

test("markupWindows: a typo'd wrapper classifies as a util (no window -- matches the compiler); malformed tags keep theirs", () => {
  // E-01: `comssponent Card() {` reads as junk + a plain UTIL `Card()` (no -> RUIVNode), so there
  // is no markup window -- byte-for-byte the compiler's view (contract fixture t05, promoted from
  // pending when the two sides converged). Embedded analysis still covers the body as a util.
  assert.equal(markupWindows("comssponent Card() {\n\treturn (\n\t\t<VBox />\n\t)\n}\n").length, 0);
  // the PLAIN spelling of the same component has its window
  assert.equal(markupWindows("Card() -> RUIVNode {\n\treturn (\n\t\t<VBox />\n\t)\n}\n").length, 1);
  // a malformed `<  a>` tag inside the markup no longer collapses the whole window (structural span)
  assert.equal(markupWindows("component C() {\n\treturn (\n\t\t<VBox>\n\t\t\t<  a>\n\t\t</VBox>\n\t)\n}\n").length, 1);
});

test("buildVirtualDoc emits a body for a typo'd header (embedded analysis survives as a util)", () => {
  // E-01: the typo'd wrapper classifies `Card()` as a plain util -- its body is still analyzed
  // (the never-go-dark guarantee holds through classification now, not recovery).
  const { text } = buildVirtualDoc("comssponent Card() {\n\tvar s = useState(0)\n\treturn ( <Label /> )\n}\n");
  assert.ok(/static func Card/.test(text) && text.includes("var s = useState(0)"), text);
});

test("buildVirtualDoc declares imported names so embedded analysis resolves them (imports leg)", () => {
  const src =
    'import { DoomGameScreenHooks } from "./doom_game_screen.hooks"\n' +
    'import { StatusChip } from "./status_chip"\n' +
    "\nexport component Panel() {\n\tvar d = DoomGameScreenHooks.use_x()\n\treturn ( <StatusChip /> )\n}\n";
  const { text } = buildVirtualDoc(src);
  assert.ok(/static var DoomGameScreenHooks\b/.test(text), "imported value name declared: " + text);
  assert.ok(/static var StatusChip\b/.test(text), "imported component name declared");
  assert.ok(text.includes("DoomGameScreenHooks.use_x()"), "the qualified reference survives in the body");
});

test("importAt detects the specifier vs an imported name under the cursor (imports leg)", async () => {
  const { importAt } = await import("../importNav");
  const src = 'import { StatusChip, Hud } from "./widgets"\n\nexport component A() { return ( <StatusChip /> ) }\n';
  const onName = src.indexOf("StatusChip");
  const onSecond = src.indexOf("Hud");
  const onSpec = src.indexOf("./widgets") + 2;
  assert.deepEqual(importAt(src, onName), { kind: "name", spec: "./widgets", name: "StatusChip" });
  assert.deepEqual(importAt(src, onSecond), { kind: "name", spec: "./widgets", name: "Hud" });
  assert.deepEqual(importAt(src, onSpec), { kind: "spec", spec: "./widgets" });
  // a position inside the component body is NOT an import hit.
  assert.equal(importAt(src, src.indexOf("<StatusChip") + 1), null);
});

test("virtualDoc extracts @if/@for conditions", () => {
  const src = [
    "component L(items: Array = []) {",
    "\treturn (",
    "\t\t<VBox>",
    "\t\t\t@if (items.size() > 0) { <Label /> }",
    "\t\t\t@for (it in items) { <Label text={ it } /> }",
    "\t\t</VBox>",
    "\t)",
    "}",
  ].join("\n");
  const { text } = buildVirtualDoc(src);
  assert.ok(text.includes("items.size() > 0"), "@if condition extracted");
  assert.ok(text.includes("it in items"), "@for header extracted");
});

test("virtualDoc is scope-aware (loop var visible to its {expr})", () => {
  const src = [
    "component L(items: Array = []) {",
    "\treturn (",
    "\t\t<VBox>",
    "\t\t\t@for (it in items) { <Label text={ it.name } /> }",
    "\t\t</VBox>",
    "\t)",
    "}",
  ].join("\n");
  const { text } = buildVirtualDoc(src);
  const lines = text.split("\n");
  const forLine = lines.find((l) => l.includes("for it in items:"));
  const exprLine = lines.find((l) => l.includes("it.name"));
  assert.ok(forLine, "emits `for it in items:`");
  assert.ok(exprLine, "emits the loop-var {expr}");
  const lead = (s: string) => s.match(/^\t*/)![0].length;
  assert.ok(lead(exprLine!) > lead(forLine!), "the {expr} is nested INSIDE the for block (loop var in scope)");
});

test("cross-file goto: a Hooks.<hook> reference resolves INTO the library file (binding-reported uri)", () => {
  // The §7(a) headline: with the addon library loaded (res:// path + `class_name Hooks`), a
  // `Hooks.useRef` reference in the virtual doc resolves cross-file to the real hooks.gd — and the
  // adapter reports the target by URI (the binding enriches each navigation target's FileId with its
  // uri) with its range in THAT file's text. The server chains a bare `useRef` to this RHS; here we
  // drive both steps.
  const az = new AnalyzerAdapter();
  const hooksUri = "file:///proj/addons/reactive_ui_toolkit/core/hooks.gd";
  const hooks = "class_name Hooks\nstatic func useRef(initial = null) -> Dictionary:\n\treturn {}\n";
  az.loadLibrary(hooksUri, hooks, "res://addons/reactive_ui_toolkit/core/hooks.gd");

  const vUri = "file:///proj/x.__guitkx_virtual.gd";
  const vtext =
    "extends RefCounted\n" +
    "static func render(props, children):\n" +
    "\tvar useRef = Hooks.useRef\n" +
    "\tvar _e0 = (useRef(0))\n" +
    "\tpass\n";
  az.sync(vUri, vtext);

  // (1) The bare `useRef(0)` in the embedded expr resolves to the in-scope hook STUB (same file).
  const bareUse = vtext.indexOf("useRef(0)") + 1;
  const localDefs = az.definitionsAt(vUri, vtext, bareUse);
  assert.ok(localDefs.length >= 1, "bare useRef resolves to the local stub");
  assert.equal(localDefs[0].uri, vUri, "the stub lives in the virtual doc (same file)");

  // (2) The stub's RHS `Hooks.useRef` resolves CROSS-FILE to the real method in hooks.gd.
  const rhs = vtext.indexOf("Hooks.useRef") + "Hooks.".length;
  const libDefs = az.definitionsAt(vUri, vtext, rhs);
  const d = libDefs.find((x) => x.uri === hooksUri);
  assert.ok(d, `Hooks.useRef should point at the library file, got ${JSON.stringify(libDefs)}`);
  assert.equal(hooks.slice(d!.range.start, d!.range.end), "useRef", "range lands on hooks.gd's useRef decl");
});

// The wrapper stubs are only sound while their signatures are byte-identical to hooks.gd — drift
// would surface as false arg-type/arity errors inside virtual docs. This is the drift tripwire.
test("hook wrapper stubs match hooks.gd declarations byte-for-byte (params, return, @return-tuple)", () => {
  const hooksGd = readFileSync(join(__dirname, "..", "..", "..", "..", "addons", "reactive_ui_toolkit", "core", "hooks.gd"), "utf8");
  const decls = new Map<string, { params: string; ret: string; tuple: string | null }>();
  const gdLines = hooksGd.split("\n");
  for (let i = 0; i < gdLines.length; i++) {
    const m = /^static func ([A-Za-z_]\w*)\((.*)\)( -> [A-Za-z_]\w*)?:/.exec(gdLines[i]);
    if (!m) continue;
    let tuple: string | null = null;
    for (let j = i - 1; j >= 0 && gdLines[j].startsWith("##"); j--) {
      const t = /@return-tuple\(([^)]*)\)/.exec(gdLines[j]);
      if (t) {
        tuple = t[1];
        break;
      }
    }
    decls.set(m[1], { params: m[2], ret: m[3] ?? "", tuple });
  }

  const { text } = buildVirtualDoc("component X() {\n\treturn (<Label />)\n}\n");
  const vLines = text.split("\n");
  let stubCount = 0;
  for (let i = 0; i < vLines.length; i++) {
    const m = /^static func ([A-Za-z_]\w*)\((.*)\)( -> [A-Za-z_]\w*)?: (?:return )?Hooks\.\1\(/.exec(vLines[i]);
    if (!m) continue;
    stubCount++;
    const d = decls.get(m[1]);
    assert.ok(d, `stub '${m[1]}' has no matching hooks.gd declaration`);
    assert.equal(m[2], d!.params, `stub '${m[1]}' params drifted from hooks.gd`);
    assert.equal(m[3] ?? "", d!.ret, `stub '${m[1]}' return annotation drifted from hooks.gd`);
    const tag = i > 0 ? /^## @return-tuple\(([^)]*)\)$/.exec(vLines[i - 1]) : null;
    assert.equal(tag ? tag[1] : null, d!.tuple, `stub '${m[1]}' @return-tuple tag drifted from hooks.gd`);
  }
  assert.equal(stubCount, 23, "all 23 hooks have wrapper stubs");
  for (const [name] of decls) {
    if (/^use[A-Z]/.test(name) || name === "createContext" || name === "provideContext") {
      assert.ok(
        vLines.some((l) => l.startsWith(`static func ${name}(`)),
        `hooks.gd hook '${name}' is missing a wrapper stub — add it to HOOK_STUBS`
      );
    }
  }
});

// The 0.5.3 wiring end-to-end, against the REAL analyzer + the REAL hooks.gd: (1) a typo'd bare hook
// call fires UNDEFINED_FUNCTION once the workspace is declared complete, mapped back to the .guitkx
// source; (2) a valid bare hook call stays silent; (3) the `## @return-tuple` shape flows through the
// wrapper stub — `s[1]` projects to Callable via constant-index on the tuple.
test("analyzer e2e: workspace-complete arms UNDEFINED_FUNCTION for a typo'd hook, valid hooks stay silent", () => {
  const az = new AnalyzerAdapter();
  const hooksUri = "file:///proj/addons/reactive_ui_toolkit/core/hooks.gd";
  const hooksGd = readFileSync(join(__dirname, "..", "..", "..", "..", "addons", "reactive_ui_toolkit", "core", "hooks.gd"), "utf8");
  az.loadLibrary(hooksUri, hooksGd, "res://addons/reactive_ui_toolkit/core/hooks.gd");
  az.setWorkspaceComplete(true);

  const bad = "component X() {\n\tvar s = usseState(0)\n\treturn (<Label text={ str(s) } />)\n}\n";
  const vBad = buildVirtualDoc(bad);
  const badUri = "file:///proj/bad.__guitkx_virtual.gd";
  az.sync(badUri, vBad.text);
  const undef = az.diagnosticsAt(badUri, vBad.text).filter((d) => d.code === "UNDEFINED_FUNCTION");
  assert.ok(undef.length >= 1, "usseState(0) should fire UNDEFINED_FUNCTION with a complete workspace");
  const s = vBad.map.toSource(undef[0].range.start);
  assert.notEqual(s, null, "the diagnostic maps back into the .guitkx source");
  assert.equal(bad.slice(s!, s! + "usseState".length), "usseState", "…and lands on the typo");

  // The ORIGINAL bug, verbatim user shape (analyzer 0.5.4: initializer narrowing + builtin member
  // misses as errors): an UNTYPED `var s = useState(0)` local projects `s[1]` as a Callable, and
  // the typo'd setter method is an UNDEFINED_METHOD error mapped onto the typo. This also pins the
  // bundled analyzer version — a lockfile downgrade below 0.5.4 fails here.
  const casll = "component Z() {\n\tvar s = useState(0)\n\ts[1].casll(1)\n\treturn (<Label text={ str(s[0]) } />)\n}\n";
  const vCasll = buildVirtualDoc(casll);
  const casllUri = "file:///proj/casll.__guitkx_virtual.gd";
  az.sync(casllUri, vCasll.text);
  const um = az.diagnosticsAt(casllUri, vCasll.text).filter((d) => d.code === "UNDEFINED_METHOD");
  assert.ok(um.length >= 1, "s[1].casll(1) through an untyped local must fire UNDEFINED_METHOD (core 0.5.4+)");
  const us = vCasll.map.toSource(um[0].range.start);
  assert.equal(casll.slice(us!, us! + "casll".length), "casll", "…mapped onto the typo'd setter method");

  const good = "component Y() {\n\tvar s := useState(0)\n\tvar setter := s[1]\n\treturn (<Label text={ str(s[0]) } />)\n}\n";
  const vGood = buildVirtualDoc(good);
  const goodUri = "file:///proj/good.__guitkx_virtual.gd";
  az.sync(goodUri, vGood.text);
  const goodDiags = az.diagnosticsAt(goodUri, vGood.text);
  assert.ok(
    !goodDiags.some((d) => d.code.startsWith("UNDEFINED_")),
    `valid useState must not false-flag, got ${JSON.stringify(goodDiags)}`
  );
  // A3: `s := useState(0)` carries Ty::Tuple(Variant, Callable) through the wrapper stub, so the
  // constant index `s[1]` projects to Callable — visible as the inlay type hint on `setter`.
  const hints = az.inlayHintsAt(goodUri, vGood.text);
  const setterDecl = vGood.text.indexOf("var setter");
  const setterHint = hints.find((h) => h.offset > setterDecl && h.offset < setterDecl + "var setter :".length + 1);
  assert.ok(setterHint, `expected an inlay type hint on 'setter', got ${JSON.stringify(hints)}`);
  assert.ok(setterHint!.label.includes("Callable"), `setter should project to Callable, got '${setterHint!.label}'`);
});

test("module virtual doc emits one static func per member, under its REAL name — headers never leak", () => {
  const src =
    'module Widgets {\n\tcomponent A() { return (<Label text="a" />) }\n\tcomponent B() {\n\t\tvar s := useState(0)\n\t\treturn (<A />)\n\t}\n\thook use_z(n: int) {\n\t\tvar s := useState(n)\n\t\treturn s\n\t}\n}\n';
  const { text } = buildVirtualDoc(src);
  // The compiler emits module members under their declared names (`_emit_func(c["name"],…)`,
  // `static func use_z(…)`), and sibling code legally references them bare — mirror it exactly.
  assert.ok(text.includes("static func A(props"), "member component A under its real name");
  assert.ok(text.includes("static func B(props"), "member component B under its real name");
  assert.ok(text.includes("static func use_z(n: int):"), "member hook under its real name, params verbatim");
  assert.ok(!text.includes("component A"), "member headers must not appear in the generated GDScript");
});

test("hook declarations: `-> Hint` survives (like _ret_suffix), tuple-style hints are dropped, params never eaten", () => {
  assert.ok(buildVirtualDoc("hook use_a(n: int) -> Array {\n\treturn [n]\n}\n").text.includes("static func use_a(n: int) -> Array:"));
  // a params-less hook with a PARENTHESIZED hint: the `( … )` belongs to the hint, not the params
  const v = buildVirtualDoc("hook use_pair -> (int, Callable) {\n\treturn [1, func(): pass]\n}\n");
  assert.ok(v.text.includes("static func use_pair():"), `tuple-style hint dropped and not parsed as params, got ${JSON.stringify(v.text.match(/static func use_pair.*$/m))}`);
});

// The workspace-complete arming made two emission gaps VISIBLE as false errors: (1) a module body fed
// whole through the component path turned member headers into "statements" (UNDEFINED_IDENTIFIER on
// `component`, UNDEFINED_FUNCTION on `A()`); (2) the __hook scaffold dropped the hook's own params, so
// every param read was "undefined". Both fixed at the emitter; this pins them against the real analyzer.
test("analyzer e2e: module members and hook params never false-flag; a typo in a member still fires", () => {
  const az = new AnalyzerAdapter();
  const hooksGd = readFileSync(join(__dirname, "..", "..", "..", "..", "addons", "reactive_ui_toolkit", "core", "hooks.gd"), "utf8");
  az.loadLibrary("file:///proj/addons/reactive_ui_toolkit/core/hooks.gd", hooksGd, "res://addons/reactive_ui_toolkit/core/hooks.gd");
  az.setWorkspaceComplete(true);

  const mod = 'module Widgets {\n\tcomponent A() { return (<Label text="a" />) }\n\tcomponent B() {\n\t\tvar s := useState(0)\n\t\treturn (<A />)\n\t}\n}\n';
  const vMod = buildVirtualDoc(mod);
  az.sync("file:///proj/mod.__guitkx_virtual.gd", vMod.text);
  const modBad = az
    .diagnosticsAt("file:///proj/mod.__guitkx_virtual.gd", vMod.text)
    .filter((d) => d.code.startsWith("UNDEFINED_") || d.code === "GDSCRIPT_SYNTAX");
  assert.equal(modBad.length, 0, `module members must not false-flag, got ${JSON.stringify(modBad)}`);

  const hk = "hook use_counter(start: int = 0) {\n\tvar s := useState(start)\n\treturn [s[0], s[1]]\n}\n";
  const vHk = buildVirtualDoc(hk);
  assert.ok(vHk.text.includes("static func use_counter(start: int = 0):"), "hook emitted under its real name, params verbatim");
  az.sync("file:///proj/hk.__guitkx_virtual.gd", vHk.text);
  const hkDiags = az.diagnosticsAt("file:///proj/hk.__guitkx_virtual.gd", vHk.text);
  assert.ok(!hkDiags.some((d) => d.code.startsWith("UNDEFINED_")), `hook params must be in scope, got ${JSON.stringify(hkDiags)}`);
  assert.ok(!hkDiags.some((d) => d.code === "UNREACHABLE_CODE"), "no trailing-pass UNREACHABLE_CODE after a returning body");

  const bad = "module M {\n\tcomponent C() {\n\t\tvar s = usseState(0)\n\t\treturn (<Label />)\n\t}\n}\n";
  const vBad = buildVirtualDoc(bad);
  az.sync("file:///proj/modbad.__guitkx_virtual.gd", vBad.text);
  const undef = az.diagnosticsAt("file:///proj/modbad.__guitkx_virtual.gd", vBad.text).filter((d) => d.code === "UNDEFINED_FUNCTION");
  assert.ok(undef.length >= 1, "a typo'd hook call inside a module member still fires");
  const s = vBad.map.toSource(undef[0].range.start);
  assert.equal(bad.slice(s!, s! + 9), "usseState", "…mapped onto the member's typo");

  // A sibling member's bare call to a module-local hook is LEGAL guitkx (the compiler deliberately
  // leaves it unaliased and emits the hook under its real name) — it must never flag.
  const sib = "module M2 {\n\thook use_z(n: int) {\n\t\tvar s := useState(n)\n\t\treturn s\n\t}\n\tcomponent B() {\n\t\tvar s := use_z(1)\n\t\treturn (<Label text={ str(s) } />)\n\t}\n}\n";
  const vSib = buildVirtualDoc(sib);
  az.sync("file:///proj/sib.__guitkx_virtual.gd", vSib.text);
  const sibUndef = az.diagnosticsAt("file:///proj/sib.__guitkx_virtual.gd", vSib.text).filter((d) => d.code.startsWith("UNDEFINED_"));
  assert.equal(sibUndef.length, 0, `bare sibling-hook call must resolve, got ${JSON.stringify(sibUndef)}`);
});

test("reindent anchor skips comment lines — an over-indented leading comment cannot shift real code", () => {
  // A comment is legal at ANY indentation in GDScript. Anchoring on one dragged every code line off
  // its true base: the virtual doc/generated .gd went invalid and Format Document dedented a
  // statement out of its `if` block (source corruption). All four mirrored reindenters skip comments
  // when picking the anchor; this covers the vdoc + TS formatter (the GD suite covers its mirrors).
  const src = "component X() {\n\t\t# over-indented note\n\tvar a := useState(0)\n\tif a[0]:\n\t\ta[1].call(1)\n\treturn (<Label />)\n}\n";
  const { text } = buildVirtualDoc(src);
  assert.ok(text.includes("\n\tvar a := useState(0)"), "code anchors at body level, not at the comment");
  assert.ok(text.includes("\n\tif a[0]:"), "if header at body level");
  assert.ok(text.includes("\n\t\ta[1].call(1)"), "the if body stays nested");
  const fmt = formatGuitkx(src).text;
  // Phase D: the formatter default is spaces-2 — the invariant is the RELATIVE nesting (the if body
  // one level deeper than its header), pinned in the default style.
  assert.ok(fmt.includes("  if a[0]:\n    a[1].call(1)"), `formatter must not dedent the if body, got ${JSON.stringify(fmt)}`);
});

test("guitkxVirtualLibText mirrors a .guitkx's compiled bindings (T4.5 — replaced the veto)", () => {
  // The analyzer only sees .gd files; a .guitkx-declared class's generated sibling .gd is
  // git-ignored (fresh clone / before the first Godot compile). Instead of vetoing UNDEFINED_*
  // for index-known names (which also hid real typos that collided with a binding), the binding
  // is DECLARED to the analyzer as a virtual library — resolution is honest both ways.
  const wi = new WorkspaceIndex();
  wi.reindex("file:///proj/demo_hooks.guitkx", "module DemoHooks {\n\thook use_x() {\n\t\treturn 1\n\t}\n}\n");
  const lib = guitkxVirtualLibText(wi.entriesFor("file:///proj/demo_hooks.guitkx"));
  assert.ok(lib, "a module produces a virtual library");
  assert.ok(lib!.includes("class_name DemoHooks"), `the binding is a real class_name: ${lib}`);
  // Member stubs are VARIADIC so the analyzer's arity checking can never false-fire through one.
  assert.ok(lib!.includes("static func use_x(...args): return null"), `variadic member stub: ${lib}`);

  // A component's library exposes the compiled render entry too; @class_name overrides win.
  const wc = new WorkspaceIndex();
  wc.reindex("file:///proj/card.guitkx", "@class_name FancyCard\ncomponent Card {\n\treturn ( <Label text=\"x\" /> )\n}\n");
  const clib = guitkxVirtualLibText(wc.entriesFor("file:///proj/card.guitkx"));
  assert.ok(clib!.includes("class_name FancyCard"), `override binding wins: ${clib}`);
  assert.ok(clib!.includes("static func render(...args): return null"), `component exposes render: ${clib}`);

  // Nothing indexable -> no library (the caller closes any previous one).
  assert.equal(guitkxVirtualLibText([]), null);
});

test("virtualDoc paramNames is noncode-aware (comma/colon inside a string default does not mis-split)", () => {
  // [audit #26] A default value containing a comma or colon inside a string must not break the split,
  // so EVERY param still gets an in-scope stub for completion/hover.
  const src = [
    'component C(label: String = "a, b", path: String = "x:y", n: int = 0) {',
    "\treturn ( <Label text={ label } /> )",
    "}",
  ].join("\n");
  const { text } = buildVirtualDoc(src);
  assert.ok(text.includes('var label = props.get("label")'), "param `label` stub present (string default with comma)");
  assert.ok(text.includes('var path = props.get("path")'), "param `path` stub present (string default with colon)");
  assert.ok(text.includes('var n = props.get("n")'), "param `n` after a comma-in-string default still survives");
});

// --- embedded-GDScript references / rename / signature-help / inlay (analyzer-backed) ---

const VDOC =
  "extends RefCounted\n" +
  "static func render(props: Dictionary, children: Array) -> Variant:\n" +
  "\tvar count := 1\n" +
  "\tvar doubled := count + count\n" +
  "\treturn doubled\n";

test("referencesAt: a local embedded var resolves all its in-file references (same virtual-doc uri)", () => {
  const az = new AnalyzerAdapter();
  const vUri = "file:///proj/y.__guitkx_virtual.gd";
  az.sync(vUri, VDOC);
  const at = VDOC.indexOf("count") + 1;
  const refs = az.referencesAt(vUri, VDOC, at);
  assert.ok(refs.length >= 2, `expected >=2 references to count, got ${refs.length}`);
  assert.ok(refs.every((r) => r.uri === vUri), "every reference is in this file's virtual doc");
  assert.ok(refs.every((r) => VDOC.slice(r.range.start, r.range.end) === "count"), "ranges land on `count`");
});

test("renameAt: renaming a local embedded var returns an ok envelope with in-file edits only", () => {
  const az = new AnalyzerAdapter();
  const vUri = "file:///proj/y.__guitkx_virtual.gd";
  az.sync(vUri, VDOC);
  const res = az.renameAt(vUri, VDOC, VDOC.indexOf("count") + 1, "amount");
  assert.ok("ok" in res, `expected an ok envelope, got ${JSON.stringify(res)}`);
  if ("ok" in res) {
    assert.ok(res.ok.every((fe) => fe.uri === vUri), "edits stay in this file (correct-or-refuse)");
    const edits = res.ok.flatMap((fe) => fe.edits);
    assert.ok(edits.length >= 2, `expected >=2 edits, got ${edits.length}`);
    assert.ok(edits.every((e) => e.newText === "amount"), "every edit writes the new name");
  }
});

test("signatureHelpAt + inlayHintsAt return well-formed shapes over the virtual doc (no crash)", () => {
  const az = new AnalyzerAdapter();
  const vUri = "file:///proj/z.__guitkx_virtual.gd";
  const vtext = VDOC.replace("\treturn doubled\n", "\treturn str(count)\n");
  az.sync(vUri, vtext);
  const hints = az.inlayHintsAt(vUri, vtext);
  assert.ok(Array.isArray(hints), "inlayHintsAt returns an array");
  assert.ok(
    hints.every((h) => typeof h.offset === "number" && typeof h.label === "string" && typeof h.kind === "number"),
    "each inlay hint is well-formed",
  );
  const sig = az.signatureHelpAt(vUri, vtext, vtext.indexOf("str(") + 4);
  assert.ok(sig === null || Array.isArray(sig.signatures), "signatureHelpAt returns null or a SignatureHelp");
});

test("documentSymbolsAt: outlines a real .gd file (class/func/var) with in-bounds char ranges", () => {
  const az = new AnalyzerAdapter();
  const uri = "file:///proj/player.gd";
  const src = "class_name Player\nvar hp := 10\nfunc take_damage(amount: int) -> void:\n\thp -= amount\n";
  az.sync(uri, src);
  const syms = az.documentSymbolsAt(uri, src);
  assert.ok(syms.length >= 1, `expected symbols, got ${JSON.stringify(syms)}`);
  const wellFormed = (s: any): boolean =>
    typeof s.name === "string" &&
    typeof s.kind === "number" &&
    s.range.start >= 0 &&
    s.range.end <= src.length &&
    (s.children ?? []).every(wellFormed);
  assert.ok(syms.every(wellFormed), "every symbol is well-formed with in-bounds ranges");
  const names = (s: any): string[] => [s.name, ...(s.children ?? []).flatMap(names)];
  const all = syms.flatMap(names);
  assert.ok(all.includes("take_damage"), `outline should include the func, got ${all.join(", ")}`);
});

test("formatAt + semanticTokensAt over a real .gd (analyzer-backed, well-formed)", () => {
  const az = new AnalyzerAdapter();
  const uri = "file:///proj/fmt.gd";
  const src = "func  f(a: int):\n\tvar x := a + 1\n\treturn x\n";
  az.sync(uri, src);
  // format: a tidied full-document string (or null if unknown/unchanged)
  const formatted = az.formatAt(uri);
  assert.ok(formatted === null || (typeof formatted === "string" && formatted.length > 0), "formatAt returns tidied text or null");
  // semantic tokens: a flat delta-encoded array (length a multiple of 5), token types within the legend
  const data = az.semanticTokensAt(uri, src);
  assert.ok(Array.isArray(data) && data.length % 5 === 0, "semanticTokensAt is a 5-tuple-aligned array");
  assert.ok(data.length > 0, "real code yields some tokens");
  for (let i = 3; i < data.length; i += 5) assert.ok(data[i] >= 0 && data[i] < TOKEN_TYPES.length, "token type index is within the unified legend");
});

test("codeActionsAt returns well-formed quick-fixes over the virtual doc (no crash)", () => {
  const az = new AnalyzerAdapter();
  const vUri = "file:///proj/c.__guitkx_virtual.gd";
  az.sync(vUri, VDOC);
  const actions = az.codeActionsAt(vUri, VDOC, VDOC.indexOf("count") + 1);
  assert.ok(Array.isArray(actions), "codeActionsAt returns an array");
  assert.ok(
    actions.every((a) => typeof a.title === "string" && (a.kind === null || typeof a.kind === "string") && Array.isArray(a.edits)),
    "each action is well-formed (title + optional kind + per-file edits)",
  );
});

// --- regression tests for the BUG_V1 fixes ---

test("BUG-5: a setup-block offset round-trips even with CRLF + a trailing blank line", () => {
  // The old whole-block length guard dropped the setup span whenever reindent changed any length —
  // which a trailing whitespace-only line (and CRLF) always does. Per-line mapping fixes it.
  const src = ["component C {", "\tvar n = useState(3)", "\tvar g = use_st", "\treturn (", "\t\t<Label />", "\t)", "}"].join("\r\n");
  const { map } = buildVirtualDoc(src);
  for (const needle of ["useState", "use_st"]) {
    const at = src.indexOf(needle) + 1; // inside the setup identifier
    const gen = map.toGenerated(at);
    assert.notEqual(gen, null, `setup offset for '${needle}' maps into the virtual doc`);
    assert.equal(map.toSource(gen!), at, `and back to the same source offset for '${needle}'`);
  }
});

test("BUG-3: componentTagAt resolves when the cursor sits on the tag opener '<' (and closing '</')", () => {
  const a = "\t<Card idx={ 1 } />";
  assert.equal(componentTagAt(a, a.indexOf("<")), "Card"); // cursor ON the '<'
  assert.equal(componentTagAt(a, a.indexOf("Card") + 2), "Card"); // inside the name (regression: still works)
  assert.equal(componentTagAt("</Card>", 0), "Card"); // on the '<' of a closing tag
  assert.equal(componentTagAt("\t<zbox />", "\t<zbox />".indexOf("<")), null); // lowercase tag ignored
});

test("BUG-4: scanDeclarations + the index carry the @class_name override offsets for an atomic rename", () => {
  const src = "@class_name Fancy\ncomponent Card() {\n\treturn (<Label />)\n}\n";
  const d = scanDeclarations(src)[0];
  assert.equal(d.binding, "Fancy");
  assert.equal(src.slice(d.classNameStart!, d.classNameEnd!), "Fancy", "override token located");
  assert.equal(src.slice(d.nameStart, d.nameEnd), "Card", "decl name token located");
  const idx = new WorkspaceIndex();
  idx.reindex("file:///X.guitkx", src);
  const e = idx.lookup("Fancy")[0];
  assert.equal(src.slice(e.classNameStart!, e.classNameEnd!), "Fancy", "index entry carries the override offsets");
  // a component with NO override leaves the offsets undefined
  assert.equal(scanDeclarations("component Card() { return (<Label />) }")[0].classNameStart, undefined);
});

test("BUG-7: a blank slot inside a @for body is markup; a setup statement is embedded", () => {
  const markupSrc = "component C(n: int = 0) {\n\treturn (\n\t\t@for (i in n) {\n\t\t\tHERE\n\t\t}\n\t)\n}\n";
  assert.equal(classifyContext(markupSrc, markupSrc.indexOf("HERE")).kind, "markup");
  const setupSrc = "component C() {\n\tvar g = use_st\n\treturn (<Label />)\n}\n";
  assert.equal(classifyContext(setupSrc, setupSrc.indexOf("use_st") + 6).kind, "embedded");
});

test("BUG-2: semanticTokensRawAt yields raw in-legend tokens; encodeTokens sorts a merged set", () => {
  const az = new AnalyzerAdapter();
  const uri = "file:///proj/st.gd";
  const src = "func f(a: int):\n\tvar x := a + 1\n\treturn x\n";
  az.sync(uri, src);
  const raw = az.semanticTokensRawAt(uri, src);
  assert.ok(Array.isArray(raw) && raw.length > 0, "raw tokens present");
  assert.ok(raw.every((t) => t.end > t.start && t.type >= 0 && t.type < TOKEN_TYPES.length), "well-formed, in-legend");
  // encodeTokens must order an out-of-order (markup + embedded) merge before delta-encoding
  const data = encodeTokens([
    { line: 2, char: 0, len: 3, type: 0, mods: 0 },
    { line: 0, char: 4, len: 2, type: 1, mods: 0 },
  ]);
  assert.deepEqual(data.slice(0, 5), [0, 4, 2, 1, 0], "first emitted token is the line-0 one (proves the sort)");
  assert.equal(data[5], 2, "next token's delta-line is 0 -> 2");
});

test("BUG-3 (review): a GDScript comparison `a < Bcd` is not mistaken for a tag (cursor on '<' or in the name)", () => {
  const s = "x = a < Bcd";
  assert.equal(componentTagAt(s, s.indexOf("<")), null, "cursor on the comparison '<'");
  assert.equal(componentTagAt(s, s.indexOf("Bcd") + 1), null, "cursor inside the PascalCase RHS");
  const t = "return ( <Card /> )";
  assert.equal(componentTagAt(t, t.indexOf("<C")), "Card", "a real tag at a value boundary still resolves");
});

test("BUG-4 (review): a bare `@class_name` grabs no override (not the following `component` keyword)", () => {
  const d = scanDeclarations("@class_name\ncomponent Card() { return (<Label />) }")[0];
  assert.equal(d.binding, "Card", "binding falls back to the decl name, NOT 'component'");
  assert.equal(d.classNameStart, undefined, "no override token, so a rename can't rewrite the keyword");
});

// ── 0.9.0 loyal event names (events.ts, mirroring host_config.gd) ────────────────────────────────

test("isEventAttr recognizes on<Pascal> + native on_<signal>, rejects non-events", () => {
  for (const yes of ["onPressed", "onValueChanged", "onMouseEntered", "on_pressed", "on_gui_input"])
    assert.ok(isEventAttr(yes), `${yes} is an event handler`);
  for (const no of ["onclick", "on", "onward", "text", "disabled", "one_line"])
    assert.ok(!isEventAttr(no), `${no} is NOT an event handler`);
});

test("resolveSignalName: on<Pascal> lowers to snake_case, native escape hatch verbatim", () => {
  const btn = classSignals("Button");
  const has = (list: { name: string }[]) => (s: string) => list.some((x) => x.name === s);
  assert.equal(resolveSignalName("onPressed", has(btn)), "pressed");
  assert.equal(resolveSignalName("on_gui_input", has(btn)), "gui_input"); // native: verbatim
  assert.equal(resolveSignalName("onValueChanged", has(btn)), "value_changed"); // generic camel->snake
  assert.equal(resolveSignalName("onFocusEntered", has(btn)), "focus_entered");
  assert.equal(resolveSignalName("onTextSubmitted", has(btn)), "text_submitted");
});

test("the removed React aliases lower generically — no polymorphic table (0.9.0)", () => {
  const has = (cls: string) => (s: string) => classSignals(cls).some((x) => x.name === s);
  // onChange no longer resolves per control: it lowers to a literal (nonexistent) `change`.
  assert.equal(resolveSignalName("onChange", has("LineEdit")), "change");
  assert.equal(resolveSignalName("onChange", has("OptionButton")), "change");
  assert.equal(resolveSignalName("onClick", has("Button")), "click");
  // The loyal spellings reach each control's real signal.
  assert.equal(resolveSignalName("onTextChanged", has("LineEdit")), "text_changed");
  assert.equal(resolveSignalName("onItemSelected", has("OptionButton")), "item_selected");
  assert.equal(resolveSignalName("onTabChanged", has("TabBar")), "tab_changed");
});

test("eventCompletionsFor(Button) derives on<Pascal> for every signal; no private signals", () => {
  const evs = eventCompletionsFor(classSignals("Button"));
  const byLabel = new Map(evs.map((e) => [e.label, e.signal]));
  assert.equal(byLabel.get("onPressed"), "pressed");
  assert.equal(byLabel.get("onToggled"), "toggled");
  assert.equal(byLabel.get("onButtonDown"), "button_down");
  assert.equal(byLabel.get("onMouseEntered"), "mouse_entered");
  assert.equal(byLabel.get("onFocusEntered"), "focus_entered");
  assert.equal(byLabel.get("onResized"), "resized");
  assert.ok(!byLabel.has("onClick"), "removed React aliases are NOT offered");
  assert.ok(!evs.some((e) => e.label.startsWith("on_")), "completions are canonical on<Pascal>, not native");
  assert.ok(!evs.some((e) => e.signal.startsWith("_")), "private `_`-prefixed signals are filtered out");
});

test("validEventAttrs accepts BOTH the canonical on<Pascal> and the native on_<signal> for did-you-mean", () => {
  const valid = new Set(validEventAttrs(classSignals("Button")));
  assert.ok(valid.has("onPressed"), "canonical on<Pascal> accepted");
  assert.ok(valid.has("on_pressed"), "native escape hatch still accepted (non-breaking)");
  assert.ok(!valid.has("onClick"), "removed React alias is NOT valid");
});

test("semantic tokens tag an event attribute (onPressed) as an `event`, not a property", () => {
  const src = 'component X() {\n\treturn (\n\t\t<Button text="hi" onPressed={_f} />\n\t)\n}\n';
  const data = buildSemanticTokens(src, () => false);
  // decode [dLine,dChar,len,type,mods] quintuples and collect the token TYPES emitted
  const types: number[] = [];
  for (let i = 0; i < data.length; i += 5) types.push(data[i + 3]);
  assert.ok(types.includes(TOKEN_TYPES.indexOf("event")), "onPressed emitted with the `event` token type");
});

// ── prop spread `{...obj}` (parser + formatter mirror of the GDScript compiler) ──────────────────

test("parseMarkup parses `{...spread}` into a spread-kind attr (name empty, value = inner expr)", () => {
  const src = "<Card {...base} title={ t } />";
  const r = parseMarkup(src, 0, src.length);
  assert.equal(r.error, "");
  const el = r.nodes[0] as Extract<(typeof r.nodes)[number], { t: "el" }>;
  assert.equal(el.attrs.length, 2);
  assert.deepStrictEqual(el.attrs[0], { name: "", kind: "spread", value: "base", at: 6, vat: 10, end: 15 });
  assert.equal(el.attrs[1].name, "title");
  assert.equal(el.attrs[1].kind, "expr");
});

test("parseMarkup: a `{` attribute without `...` is an error (only spread is allowed there)", () => {
  assert.ok(parseMarkup("<Card { base } />", 0, 17).error.startsWith("GUITKX0300"));
  assert.equal(parseMarkup("<Card {...a.b.c} />", 0, 19).error, ""); // dotted member spread is fine
});

test("formatGuitkx preserves `{...spread}` attributes and stays idempotent", () => {
  const src = "component C() {\n\treturn (\n\t\t<Card {...base} title={ t } />\n\t)\n}\n";
  const out = formatGuitkx(src).text;
  assert.ok(out.includes("{...base}"), "spread attribute preserved");
  assert.ok(out.includes("title={ t }"), "explicit attr still formatted");
  assert.equal(formatGuitkx(out).text, out, "formatting is idempotent over a spread");
});

// ---- T4.4/T4.5/T4.6 -- the analyzer halves (some assertions need core 0.6+ — shipped — and are gated on
// the new setWarningOverride method so this suite stays green against the registry 0.5.4 too) ----

// eslint-disable-next-line @typescript-eslint/no-var-requires
const CORE_HAS_OVERRIDE = typeof (require("@gdscript-analyzer/core").AnalysisHandle.prototype as any).setWarningOverride === "function";

test("live PascalCase 0105 fires only against a known-components universe (T4.5 ungate)", () => {
  const src = 'component C {\n\treturn ( <Cardz text="x" /> )\n}\n';
  const wins = markupWindows(src);
  const ungated = windowStructureDiags(src, wins);
  assert.ok(!ungated.some((d) => d.code === "GUITKX0105"), "null universe (scan not finished) stays silent");
  const known = new Set(["Card", "DemoHooks"]);
  const hit = windowStructureDiags(src, wins, known).find((d) => d.code === "GUITKX0105");
  assert.ok(hit, "unknown PascalCase flags against the universe");
  assert.ok(hit!.message.includes("did you mean <Card>"), `suggestion expected: ${hit!.message}`);
  const okSrc = 'component C {\n\treturn ( <Card text="x" /> )\n}\n';
  assert.ok(
    !windowStructureDiags(okSrc, markupWindows(okSrc), known).some((d) => d.code === "GUITKX0105"),
    "a known component is silent"
  );
  const fragSrc = "component C {\n\treturn ( <Fragment><Card /></Fragment> )\n}\n";
  assert.ok(
    !windowStructureDiags(fragSrc, markupWindows(fragSrc), known).some((d) => d.code === "GUITKX0105"),
    "<Fragment> is structural, never an unknown component"
  );
});

test("A5: directive-header grammar fires GUITKX2508 live (field: `@for (i in 2: int5)` passed silently)", () => {
  const fires = (src: string): boolean => windowStructureDiags(src, markupWindows(src)).some((x) => x.code === "GUITKX2508");
  const bad = 'component H {\n\treturn ( <VBoxContainer>@for (i in 2: int5) { <Label key={ str(i) } text="x" /> }</VBoxContainer> )\n}\n';
  assert.ok(fires(bad), "statement garbage after `in` flags");
  const good = 'component H {\n\treturn ( <VBoxContainer>@for (i in 25) { <Label key={ str(i) } text="x" /> }</VBoxContainer> )\n}\n';
  assert.ok(!fires(good), "a range loop over an int is legal");
  const dict = 'component H {\n\treturn ( <VBoxContainer>@for (kv in {"a": 1}) { <Label key={ str(kv) } text="x" /> }</VBoxContainer> )\n}\n';
  assert.ok(!fires(dict), "dict colons are bracketed, not top-level");
  const noIn = 'component H {\n\treturn ( <VBoxContainer>@for (garbage) { <Label key={ str(1) } text="x" /> }</VBoxContainer> )\n}\n';
  assert.ok(fires(noIn), "a header without ` in ` flags");
  const emptyIf = 'component H {\n\treturn ( <VBoxContainer>@if () { <Label text="x" /> }</VBoxContainer> )\n}\n';
  assert.ok(fires(emptyIf), "an empty @if condition flags");
  const okIf = 'component H {\n\treturn ( <VBoxContainer>@if (a and b) { <Label text="x" /> }</VBoxContainer> )\n}\n';
  assert.ok(!fires(okIf), "a real condition stays clean");
});

test("Phase C: early markup returns are live WINDOWS (legal + full markup intelligence), not errors", () => {
  // A conditional early markup return yields a second window, in source order before the final one.
  const nested = "component D {\n\tvar ready = useState(false)\n\tif not ready[0]:\n\t\treturn ( <Label text=\"w\" /> )\n\treturn ( <VBoxContainer /> )\n}\n";
  const wins = markupWindows(nested);
  assert.equal(wins.length, 2, JSON.stringify(wins));
  assert.ok(nested.slice(wins[0].start, wins[0].end).includes("<Label"), "the early window is the guard's markup");
  assert.ok(nested.slice(wins[1].start, wins[1].end).includes("<VBoxContainer"), "the final window follows");
  // ...which means a typo INSIDE the early return now squiggles live.
  const typo = "component D {\n\tif true:\n\t\treturn ( <lable text=\"w\" /> )\n\treturn ( <VBoxContainer /> )\n}\n";
  const d = windowStructureDiags(typo, markupWindows(typo));
  assert.ok(d.some((x) => x.code === "GUITKX0105" && x.message.includes("lable")), JSON.stringify(d));
  // The sanctioned guard and plain value returns still produce nothing.
  const guard = "component E {\n\tif true:\n\t\treturn null\n\tvar f = func(x):\n\t\treturn (x + 1)\n\treturn ( <VBoxContainer /> )\n}\n";
  assert.equal(markupWindows(guard).length, 1, "null guards and value returns are not windows");
  // Nested-only markup returns (no FINAL markup return) still report missing-return -- some
  // render() paths would return nothing, so 2101 stands on both sides.
  const nestedOnly = "component G {\n\tif true:\n\t\treturn ( <Label /> )\n}\n";
  assert.equal(missingReturnComponents(nestedOnly).length, 1);
});

test("Phase C: an unconditional early markup return dims everything after it (Unity Site-B parity)", () => {
  const src = "component U {\n\treturn ( <Label /> )\n\tvar x = 1\n\treturn ( <VBoxContainer /> )\n}\n";
  const r = unreachableRegions(src);
  assert.equal(r.length, 1, JSON.stringify(r));
  const dimmed = src.slice(r[0].start, r[0].end);
  assert.ok(dimmed.includes("var x = 1"), `setup after the early return dims: ${dimmed}`);
  assert.ok(dimmed.includes("<VBoxContainer />"), `the (dead) final return dims too: ${dimmed}`);
  // A CONDITIONAL early return dims nothing extra -- only the legacy after-final-return region.
  const cond = "component V {\n\tif true:\n\t\treturn ( <Label /> )\n\treturn ( <VBoxContainer /> )\n\tvar tail = 1\n}\n";
  const rc = unreachableRegions(cond);
  assert.equal(rc.length, 1, JSON.stringify(rc));
  assert.ok(cond.slice(rc[0].start, rc[0].end).includes("var tail = 1"), "only the after-final tail dims");
});

test("live 0105 exempts vocabulary host tags from the component-universe check (0.6.0 field regression)", () => {
  // Host tags are PascalCase too -- with an armed universe that (correctly) does not contain
  // them, <HBox>/<Button>/<Label> and vocabulary aliases like <VBoxContainer> must stay clean;
  // the 0.6.0 storm was this branch checking only `known` and never findTag().
  const src = 'component C {\n\treturn ( <HBoxContainer><Button text="b" /><Label text="l" /><VBoxContainer /></HBoxContainer> )\n}\n';
  const known = new Set(["SomeComp"]);
  const d = windowStructureDiags(src, markupWindows(src), known);
  assert.ok(!d.some((x) => x.code === "GUITKX0105"), `host tags stay clean against an armed universe: ${JSON.stringify(d)}`);
  // A typo'd host tag still flags -- and the suggestion pool now includes host tags themselves.
  const typo = "component C {\n\treturn ( <HBoxContainerr /> )\n}\n";
  const hit = windowStructureDiags(typo, markupWindows(typo), known).find((x) => x.code === "GUITKX0105");
  assert.ok(hit, "a typo'd host tag still flags against the universe");
  assert.ok(hit!.message.includes("did you mean <HBoxContainer>"), `host-tag suggestion expected: ${hit!.message}`);
});

test("T4.5 e2e: a fed virtual library resolves the binding; a typo still flags", () => {
  const az = new AnalyzerAdapter();
  az.upsertLibrary(
    "file:///proj/demo_hooks.guitkx.__guitkx_lib.gd",
    "class_name DemoHooks\n\nstatic func use_x(...args): return null\n",
    "res://demo_hooks.gd"
  );
  az.setWorkspaceComplete(true);
  const vUri = "file:///proj/y.__guitkx_virtual.gd";
  const good = "extends RefCounted\nstatic func render(props, children):\n\tvar a = DemoHooks.use_x(1, 2)\n\treturn a\n";
  az.sync(vUri, good);
  const codes = az.diagnosticsAt(vUri, good).map((d) => d.code);
  assert.ok(!codes.includes("UNDEFINED_IDENTIFIER"), `the .guitkx binding resolves for real: ${codes}`);
  assert.ok(!codes.includes("TOO_MANY_ARGUMENTS"), `the variadic stub is arity-transparent: ${codes}`);
  // The veto era would have silenced this too had it collided with an indexed name -- now a
  // genuinely unknown identifier always flags.
  const typo = good.replace(/DemoHooks/g, "DemoHoks");
  az.sync(vUri, typo);
  const typoCodes = az.diagnosticsAt(vUri, typo).map((d) => d.code);
  assert.ok(typoCodes.includes("UNDEFINED_IDENTIFIER"), `a typo'd binding still flags: ${typoCodes}`);
});

test("T4.4 e2e: analyzer DiagnosticTags cross the adapter (core 0.6+)", () => {
  if (!CORE_HAS_OVERRIDE) return; // only a pre-0.6 core lacks these (the pinned dep has them)
  const az = new AnalyzerAdapter();
  const uri = "file:///proj/unused.gd";
  const src = "func f() -> void:\n\tvar unused = 1\n";
  az.sync(uri, src);
  const unused = az.diagnosticsAt(uri, src).find((d) => d.code === "UNUSED_VARIABLE");
  assert.ok(unused, "UNUSED_VARIABLE fires");
  assert.deepEqual(unused!.tags, [1], `Unnecessary (1) crosses so the editor dims: ${JSON.stringify(unused)}`);
});

test("G8 e2e: a broken lambda initializer reports the syntax error, never a cascading UNDEFINED (core 0.6+)", () => {
  if (!CORE_HAS_OVERRIDE) return; // only a pre-0.6 core lacks the fix (the pinned dep has it)
  const az = new AnalyzerAdapter();
  az.setWorkspaceComplete(true);
  const vUri = "file:///proj/g8.__guitkx_virtual.gd";
  const src = "extends RefCounted\nstatic func render(props, children):\n\tvar toggle = func(broken: pass\n\tprint(toggle)\n";
  az.sync(vUri, src);
  const codes = az.diagnosticsAt(vUri, src).map((d) => d.code);
  assert.ok(codes.includes("GDSCRIPT_SYNTAX"), `the real problem (the syntax error) is reported: ${codes}`);
  assert.ok(!codes.includes("UNDEFINED_IDENTIFIER"), `no false UNDEFINED_IDENTIFIER on top (G8): ${codes}`);
});

test("T4.6 e2e: the engine-defaults profile keeps UNSAFE_* silent (core 0.6+)", () => {
  if (!CORE_HAS_OVERRIDE) return; // only a pre-0.6 core lacks the method (the pinned dep has it)
  const az = new AnalyzerAdapter(); // the constructor selects "engine-defaults"
  const uri = "file:///proj/unsafe.gd";
  const src = "func f(n: Node) -> void:\n\tn.some_fn()\n";
  az.sync(uri, src);
  const codes = az.diagnosticsAt(uri, src).map((d) => d.code);
  assert.ok(!codes.includes("UNSAFE_METHOD_ACCESS"), `Godot ships UNSAFE_* as ignore -- so do we: ${codes}`);
});

// ES-modules rename depth: import clauses (incl. the REMOTE half of `remote as local` renames)
// and the declaring file's export markers rewrite in lockstep with a declaration rename.
test("rename: import-clause remote halves + export markers rewrite (E-08/E-07/E-09)", () => {
  const { scanImportClauseRefs, scanExportMarkerRefs } = require("../refs");
  const app = 'import { Chip, Icon as Glyph } from "./chip"\nimport { Chip as Badge } from "./chip"\nimport { Chip } from "./other"\n';
  const hits = scanImportClauseRefs(app, "Chip", (spec: string) => spec === "./chip");
  assert.equal(hits.length, 2, "both ./chip clauses hit; the ./other clause (different file) does not");
  for (const h of hits) assert.equal(app.slice(h.start, h.end), "Chip", "each hit lands exactly on the remote token");
  // `Icon as Glyph` — renaming Icon hits the remote, never the local alias.
  const iconHits = scanImportClauseRefs(app, "Icon", () => true);
  assert.equal(iconHits.length, 1);
  assert.equal(app.slice(iconHits[0].start, iconHits[0].end), "Icon");
  const glyphHits = scanImportClauseRefs(app, "Glyph", () => true);
  assert.equal(glyphHits.length, 0, "the local alias is not a remote reference");
  // Export markers in the declaring file.
  const decl = 'Chip() -> RUIVNode {\n\treturn ( <Label /> )\n}\nexport { Chip, other }\nexport default Chip\n';
  const marks = scanExportMarkerRefs(decl, "Chip");
  assert.equal(marks.length, 2, "list entry + default marker both rewrite");
  for (const h of marks) assert.equal(decl.slice(h.start, h.end), "Chip");
  assert.equal(scanExportMarkerRefs(decl, "other").length, 1, "sibling list entries match independently");
});

// Audit regression: the @class_name preamble scan is ORDER-AGNOSTIC (0.10.0 rule) — an @uss/@theme
// line BEFORE @class_name must not abort the scan at the directive word (the plain-decl break).
test("readClassName survives @uss before @class_name (order-agnostic preamble)", () => {
  const src = '@uss "res://theme.tres"\n@class_name Themed\nT() -> RUIVNode {\n\treturn ( <Label /> )\n}\n';
  const d = scanDeclarations(src);
  assert.deepEqual(d.map((x) => x.binding), ["Themed"], JSON.stringify(d));
});

// G-05 clause navigation: importAt resolves every clause shape; a rename clause navigates by its
// REMOTE name (the declaration that exists in the target file).
test("importAt covers named/rename/namespace/default clause shapes", () => {
  const { importAt } = require("../importNav");
  const src = 'import { a, b as c } from "./x"\nimport * as NS from "./y"\nimport Def from "./z"\n';
  const onA = importAt(src, src.indexOf("a,"));
  assert.deepEqual({ kind: onA?.kind, name: onA?.name, spec: onA?.spec }, { kind: "name", name: "a", spec: "./x" });
  const onRename = importAt(src, src.indexOf("b as"));
  assert.equal(onRename?.name, "b", "a rename clause navigates to the REMOTE declaration");
  const onNs = importAt(src, src.indexOf("NS"));
  assert.deepEqual({ kind: onNs?.kind, spec: onNs?.spec }, { kind: "spec", spec: "./y" });
  const onDef = importAt(src, src.indexOf("Def"));
  assert.deepEqual({ kind: onDef?.kind, spec: onDef?.spec }, { kind: "spec", spec: "./z" });
});

// ── ES combined import forms + 0.11.1 field wave ────────────────────────────────────────────────

// Combined `import Def, { … } from` / `import Def, * as NS from`: one declaration carrying the
// default binding PLUS the named/namespace surface. Every consumer that used to treat the clause
// shapes as mutually exclusive must see every part.

test("importAt handles the combined clause shapes (0.11.1)", () => {
  const { importAt } = require("../importNav");
  const src = 'import isEven, { getSomething } from "./utils"\nimport D2, * as NS from "./more"\n';
  const onName = importAt(src, src.indexOf("getSomething"));
  assert.deepEqual({ kind: onName?.kind, name: onName?.name, spec: onName?.spec }, { kind: "name", name: "getSomething", spec: "./utils" });
  const onDef = importAt(src, src.indexOf("isEven"));
  assert.deepEqual({ kind: onDef?.kind, spec: onDef?.spec }, { kind: "spec", spec: "./utils" });
  const onNs = importAt(src, src.indexOf("NS"));
  assert.deepEqual({ kind: onNs?.kind, spec: onNs?.spec }, { kind: "spec", spec: "./more" });
});

test("buildVirtualDoc stubs EVERY part of a combined import (editor resolution, field wave)", () => {
  const src =
    'import isEven, { getSomething as fetch } from "./utils"\n' +
    'import D2, * as NS from "./more"\n' +
    "\nexport C() -> RUIVNode {\n\tvar a = fetch()\n\treturn ( <Label /> )\n}\n";
  const { text } = buildVirtualDoc(src);
  assert.ok(/static var isEven\b/.test(text), "combined default binding declared: " + text);
  assert.ok(/static var fetch\b/.test(text), "renamed LOCAL of the named part declared");
  assert.ok(/static var D2\b/.test(text), "combined default before `* as` declared");
  assert.ok(/static var NS\b/.test(text), "star alias of the combined form declared");
  // Same-name pin (Unity ref 9451bc9b): a default alias that KEEPS the default-exported member's
  // name plus a second import binding the same local must never double-declare the stub — one
  // resolution path only.
  const sameName =
    'import is_even, { get_something } from "./utils"\n' +
    'import { is_even } from "./more"\n' +
    "\nexport C2() -> RUIVNode {\n\tvar a = is_even()\n\treturn ( <Label /> )\n}\n";
  const gen2 = buildVirtualDoc(sameName).text;
  const stubCount = (gen2.match(/static var is_even\b/g) ?? []).length;
  assert.equal(stubCount, 1, "same local across imports declares exactly ONE stub: " + gen2);
});

test("scanImportClauseRefs sees named clauses inside a combined import", () => {
  const { scanImportClauseRefs } = require("../refs");
  const text = 'import Def, { fmt, Chip as Badge } from "./hud"\n';
  const refs = scanImportClauseRefs(text, "Chip", () => true);
  assert.equal(refs.length, 1, JSON.stringify(refs));
  assert.equal(text.slice(refs[0].start, refs[0].end), "Chip");
});

test("importBraceAt arms the brace context for bare AND combined prefixes (field wave)", () => {
  const { importBraceAt } = require("../importNav");
  const bare = 'import { } from "./utils"\n';
  const c1 = importBraceAt(bare, bare.indexOf("}"));
  assert.ok(c1 && c1.def === null && c1.spec === "./utils", JSON.stringify(c1));
  const combined = 'import isEven, {} from "./utils"\n';
  const c2 = importBraceAt(combined, combined.indexOf("}"));
  assert.ok(c2 && c2.def === "isEven" && c2.spec === "./utils", JSON.stringify(c2));
  const listed = 'import isEven, { getSomething, a as b } from "./utils"\n';
  const c3 = importBraceAt(listed, listed.indexOf("}") - 1);
  assert.deepEqual(c3?.already, ["getSomething", "a", "b"], "names AND aliases join the exclusion set");
  assert.equal(importBraceAt(combined, 3), null, "a caret before the brace is not the context");
  const dict = "export C() -> RUIVNode {\n\tvar x = { }\n\treturn ( <Label /> )\n}\n";
  assert.equal(importBraceAt(dict, dict.indexOf("{ }") + 1), null, "a GDScript dict brace is not an import list");
});

test("importBindingTokens colors imported bindings by the KIND of the export they bind", () => {
  const { importBindingTokens, importKindTokenOf } = require("../semanticTokens");
  const target = [
    "export Card() -> RUIVNode {",
    "\treturn ( <Label /> )",
    "}",
    "",
    "export use_blink() {",
    "\treturn 1",
    "}",
    "",
    "export fmt() {",
    "\treturn 2",
    "}",
    "",
    "container := 8",
    "export { container }",
    "export default fmt",
  ].join("\n");
  const src = 'import fmt2, { Card, use_blink, container as c } from "./target"\nimport D2, * as NS from "./target"\n';
  const classify = (text: string) => {
    const m = new Map<string, number>();
    for (const d of scanDeclarations(text)) {
      const t = importKindTokenOf(d.kind);
      if (t !== undefined && !m.has(d.name)) m.set(d.name, t);
    }
    return m;
  };
  const toks = importBindingTokens(src, () => target, classify);
  const FN = TOKEN_TYPES.indexOf("function");
  const VAR = TOKEN_TYPES.indexOf("variable");
  const CLS = TOKEN_TYPES.indexOf("class");
  const at = (line: number, char: number) => toks.find((t: { line: number; char: number }) => t.line === line && t.char === char);
  assert.equal(at(0, 7)?.type, FN, "combined default `fmt2` takes the default export's kind (util -> function): " + JSON.stringify(toks));
  assert.equal(at(0, 15)?.type, CLS, "component import colors like a component tag");
  assert.equal(at(0, 21)?.type, FN, "hook import colors as a function");
  assert.equal(at(0, 32)?.type, VAR, "value import colors as a variable");
  assert.equal(at(0, 45)?.type, VAR, "the rename ALIAS takes the remote's kind");
  assert.equal(at(1, 7)?.type, FN, "combined default before `* as` keeps the default kind");
  assert.equal(at(1, 16)?.type, VAR, "a star alias is a plain variable binding");
  assert.deepEqual(importBindingTokens(src, () => null, classify), [], "unresolvable targets degrade silently");
});

test("guitkxVirtualLibText mirrors new-mode member exports (values/utils/hooks — field wave)", () => {
  // A member-only/mixed NEW-MODE file used to mirror an (near-)empty class: only wrapper-module
  // members and the top component's `render` were emitted, so a peer's value/util/hook exports
  // never existed in the analysis while the real compiled .gd declares them all as statics.
  const wi = new WorkspaceIndex();
  wi.reindex(
    "file:///proj/hud.guitkx",
    "export Hud() -> RUIVNode {\n\treturn ( <Label /> )\n}\n\nexport use_x() {\n\treturn 1\n}\n\nexport fmt() {\n\treturn 2\n}\n\nval := 1\nexport { val }\n"
  );
  const lib = guitkxVirtualLibText(wi.entriesFor("file:///proj/hud.guitkx"));
  assert.ok(lib, "a new-mode file produces a virtual library");
  assert.ok(lib!.includes("class_name Hud"), lib!);
  assert.ok(lib!.includes("static func render(...args): return null"), "top component still mirrors render");
  assert.ok(lib!.includes("static func use_x(...args): return null"), "new-mode hook export mirrored");
  assert.ok(lib!.includes("static func fmt(...args): return null"), "new-mode util export mirrored");
  assert.ok(lib!.includes("static var val"), "new-mode value export mirrored as data");

  // VALUE-binding rule (F5 round 2): a file whose binding (first exported decl) is a VALUE
  // compiles to a .gd with NO class_name (the compiler's same-name self-reference fix) — the
  // mirror must not register the phantom global class, while the member statics still emit.
  const wv = new WorkspaceIndex();
  wv.reindex(
    "file:///proj/vals.guitkx",
    "export something := 42\n\nexport get_something() {\n\treturn something\n}\n"
  );
  const vlib = guitkxVirtualLibText(wv.entriesFor("file:///proj/vals.guitkx"));
  assert.ok(vlib, "a value-bound file still produces a library (preload-resolved)");
  assert.ok(!vlib!.includes("class_name"), "no phantom global class for a value binding: " + vlib);
  assert.ok(vlib!.includes("static var something"), "the binding value itself mirrors as data");
  assert.ok(vlib!.includes("static func get_something(...args): return null"), "sibling util mirrors");
});

test("formatter preserves combined import lines byte-for-byte (round-trip + idempotence)", () => {
  const src =
    'import isEven, { fmt } from "./utils"\n' +
    'import D, * as NS from "./x"\n' +
    "\nexport C() -> RUIVNode {\n\treturn ( <Label /> )\n}\n";
  const out = formatGuitkx(src);
  assert.ok(out.text.includes('import isEven, { fmt } from "./utils"'), "named part must not be dropped: " + out.text);
  assert.ok(out.text.includes('import D, * as NS from "./x"'), "star part must not be dropped");
  assert.equal(formatGuitkx(out.text).text, out.text, "idempotent over combined imports");
});
