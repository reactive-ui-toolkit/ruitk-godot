// End-to-end smoke test: spawn the server over stdio, run the LSP handshake, open a .guitkx doc,
// and request completion at a tag-name and an attribute-name position. Asserts the markup-side
// intelligence works without a Godot editor (the embedded-GDScript proxy path degrades gracefully).
const cp = require("child_process");
const path = require("path");
const fs = require("fs");
const os = require("os");
const { srcHash } = require("../out/diagsSidecar");

const server = cp.spawn("node", [path.join(__dirname, "..", "out", "server.js"), "--stdio"]);
let buf = Buffer.alloc(0);
let contentLength = -1;
const waiters = new Map();
const diagnostics = {};

server.stdout.on("data", (d) => {
  buf = Buffer.concat([buf, d]);
  while (true) {
    if (contentLength < 0) {
      const e = buf.indexOf("\r\n\r\n");
      if (e < 0) return;
      const m = /Content-Length:\s*(\d+)/i.exec(buf.slice(0, e).toString());
      contentLength = m ? +m[1] : 0;
      buf = buf.slice(e + 4);
    }
    if (buf.length < contentLength) return;
    const msg = JSON.parse(buf.slice(0, contentLength).toString());
    buf = buf.slice(contentLength);
    contentLength = -1;
    if (msg.id !== undefined && waiters.has(msg.id)) {
      waiters.get(msg.id)(msg);
      waiters.delete(msg.id);
    } else if (msg.method === "textDocument/publishDiagnostics") {
      diagnostics[msg.params.uri] = msg.params.diagnostics;
    }
  }
});

let id = 0;
function send(msg) {
  const j = JSON.stringify({ jsonrpc: "2.0", ...msg });
  server.stdin.write(`Content-Length: ${Buffer.byteLength(j)}\r\n\r\n${j}`);
}
function request(method, params) {
  const myId = ++id;
  return new Promise((res) => {
    waiters.set(myId, res);
    send({ id: myId, method, params });
  });
}
function notify(method, params) {
  send({ method, params });
}

function fail(m) {
  console.error("SMOKE FAIL:", m);
  server.kill();
  process.exit(1);
}

(async () => {
  await request("initialize", { processId: process.pid, rootUri: null, capabilities: {}, initializationOptions: { enableEmbeddedAnalysis: false } });
  notify("initialized", {});

  const uri = "file:///tmp/Counter.guitkx";
  const text = "component Counter() {\n\treturn (\n\t\t<VBoxContainer>\n\t\t\t<La\n\t\t</VBoxContainer>\n\t)\n}\n";
  notify("textDocument/didOpen", { textDocument: { uri, languageId: "guitkx", version: 1, text } });

  // completion at the "<La" position (line 3, after "\t\t\t<La" => char 6)
  const tagRes = await request("textDocument/completion", { textDocument: { uri }, position: { line: 3, character: 6 } });
  const tagItems = Array.isArray(tagRes.result) ? tagRes.result : tagRes.result?.items ?? [];
  if (!tagItems.some((i) => i.label === "Label")) fail("tag completion did not include Label: " + JSON.stringify(tagItems.slice(0, 5)));
  console.log(`tag completion OK (${tagItems.length} items, includes Label)`);

  // completion at an attribute position: "<Button " then request
  const uri2 = "file:///tmp/B.guitkx";
  const text2 = "component B() {\n\treturn ( <Button  /> )\n}\n";
  notify("textDocument/didOpen", { textDocument: { uri: uri2, languageId: "guitkx", version: 1, text: text2 } });
  const attrRes = await request("textDocument/completion", { textDocument: { uri: uri2 }, position: { line: 1, character: 18 } });
  const attrItems = Array.isArray(attrRes.result) ? attrRes.result : attrRes.result?.items ?? [];
  const has = (n) => attrItems.some((i) => i.label === n);
  if (!has("text")) fail("attr completion missing ClassDB prop 'text': " + JSON.stringify(attrItems.slice(0, 8).map((i) => i.label)));
  if (!has("disabled")) fail("attr completion missing inherited ClassDB prop 'disabled'");
  if (!has("onPressed")) fail("attr completion missing Button loyal event handler onPressed: " + JSON.stringify(attrItems.filter((i) => /^on/.test(i.label)).map((i) => i.label)));
  if (!has("key")) fail("attr completion missing structural 'key'");
  console.log(`attr completion OK (${attrItems.length} items, ClassDB props text/disabled + loyal event onPressed + key)`);

  // duplicate-key diagnostic (markupDiagnostics)
  const uri3 = "file:///tmp/Dup.guitkx";
  const text3 = 'component Dup() {\n\treturn (\n\t\t<VBoxContainer>\n\t\t\t<Label key="x" />\n\t\t\t<Label key="x" />\n\t\t</VBoxContainer>\n\t)\n}\n';
  notify("textDocument/didOpen", { textDocument: { uri: uri3, languageId: "guitkx", version: 1, text: text3 } });
  await new Promise((r) => setTimeout(r, 400));
  const d = diagnostics[uri3] || [];
  if (!d.some((x) => x.message.includes("GUITKX0104"))) fail("dup-key diagnostic missing: " + JSON.stringify(d));
  console.log(`dup-key diagnostic OK (${d.length} diags, includes GUITKX0104)`);

  // live loop single-root rule (GUITKX0108) — Phase D form: the directive body RETURNS its markup
  const uriLoop = "file:///tmp/Loop.guitkx";
  const textLoop = 'component Loop(items: Array) {\n\treturn (\n\t\t<VBoxContainer>\n\t\t\t@for (it in items) {\n\t\t\t\treturn (\n\t\t\t\t<Label text={ str(it) } key={ it } />\n\t\t\t\t<Label text="dup" />\n\t\t\t\t)\n\t\t\t}\n\t\t</VBoxContainer>\n\t)\n}\n';
  notify("textDocument/didOpen", { textDocument: { uri: uriLoop, languageId: "guitkx", version: 1, text: textLoop } });
  await new Promise((r) => setTimeout(r, 400));
  const dLoop = diagnostics[uriLoop] || [];
  if (!dLoop.some((x) => x.message.includes("GUITKX0108"))) fail("live loop single-root diagnostic missing: " + JSON.stringify(dLoop));
  console.log("loop single-root diagnostic OK (live GUITKX0108)");

  // Phase D migration rule: the pre-0.7 bare-markup directive body flags GUITKX2103 live
  const uriLegacy = "file:///tmp/Legacy.guitkx";
  notify("textDocument/didOpen", { textDocument: { uri: uriLegacy, languageId: "guitkx", version: 1, text: 'component L(items: Array) {\n\treturn ( <VBoxContainer>@for (it in items) { <Label text={ str(it) } /> }</VBoxContainer> )\n}\n' } });
  await new Promise((r) => setTimeout(r, 400));
  const dLegacy = diagnostics[uriLegacy] || [];
  if (!dLegacy.some((x) => x.message.includes("GUITKX2103"))) fail("live legacy-body diagnostic missing: " + JSON.stringify(dLegacy));
  console.log("legacy directive-body diagnostic OK (live GUITKX2103)");

  // The inverse gate the 0.8.0 field capture proved missing: a CORRECT Phase D body — GD prep code
  // (with a `<` comparison), a `return null` guard, and a single-root markup return — must produce
  // ZERO diagnostics. The retired pre-Phase-D scanner pass parsed the body as bare markup and
  // flagged `return (`/`)` as extra roots ("GUITKX0108 ... (got 3)") on every migrated file.
  // Plain E-01 spelling (0.11.0): the wrapper form would carry its G-10 deprecation warning, and
  // this gate asserts a fully-clean file.
  const uriClean = "file:///tmp/CleanBody.guitkx";
  const textClean =
    'CleanBody(items: Array) -> RuitkVNode {\n\treturn (\n\t\t<VBoxContainer>\n\t\t\t@for (it in items) {\n\t\t\t\tvar label = "row " + str(it)\n\t\t\t\tif it < 3:\n\t\t\t\t\treturn null\n\t\t\t\treturn (\n\t\t\t\t\t<Label text={ label } key={ str(it) } />\n\t\t\t\t)\n\t\t\t}\n\t\t</VBoxContainer>\n\t)\n}\n';
  notify("textDocument/didOpen", { textDocument: { uri: uriClean, languageId: "guitkx", version: 1, text: textClean } });
  await new Promise((r) => setTimeout(r, 400));
  const dClean = diagnostics[uriClean] || [];
  if (dClean.length > 0) fail("correct directive body must be diagnostic-free, got: " + JSON.stringify(dClean));
  console.log("clean directive-body OK (prep code + return-null guard + single-root return, 0 diags)");

  // live missing-return rule (GUITKX2101) — a component without `return ( ... )` used to be silent
  const uriNr = "file:///tmp/NoRet.guitkx";
  notify("textDocument/didOpen", { textDocument: { uri: uriNr, languageId: "guitkx", version: 1, text: "component NoRet() {\n\tvar a = useState(0)\n}\n" } });
  await new Promise((r) => setTimeout(r, 400));
  const dNr = diagnostics[uriNr] || [];
  if (!dNr.some((x) => x.message.includes("GUITKX2101") && x.message.includes("return"))) fail("live missing-return diagnostic missing: " + JSON.stringify(dNr));
  console.log("missing-return diagnostic OK (live GUITKX2101)");

  // go-to-definition: <A/> in module member B resolves to component A's declaration
  const uri4 = "file:///tmp/Mod.guitkx";
  const text4 = "module Mod {\n\tcomponent A() { return (<Label />) }\n\tcomponent B() { return (<A />) }\n}\n";
  notify("textDocument/didOpen", { textDocument: { uri: uri4, languageId: "guitkx", version: 1, text: text4 } });
  await new Promise((r) => setTimeout(r, 200));
  const aCol = text4.split("\n")[2].indexOf("<A") + 1;
  const defRes = await request("textDocument/definition", { textDocument: { uri: uri4 }, position: { line: 2, character: aCol } });
  const locs = Array.isArray(defRes.result) ? defRes.result : defRes.result ? [defRes.result] : [];
  if (!locs.length || locs[0].range.start.line !== 1) fail("go-to-def did not resolve <A/> to component A (line 1): " + JSON.stringify(defRes.result));
  console.log(`go-to-def OK (<A/> -> declaration at line ${locs[0].range.start.line})`);

  // find-references: A is referenced by <A/> in B, plus its declaration
  const refRes = await request("textDocument/references", { textDocument: { uri: uri4 }, position: { line: 2, character: aCol }, context: { includeDeclaration: true } });
  const refs = refRes.result || [];
  if (refs.length < 2) fail("references for A expected >=2 (decl + <A/> use): " + JSON.stringify(refs));
  console.log(`references OK (${refs.length} locations for A)`);

  // rename A -> Card across the file (decl + <A/> use)
  const renRes = await request("textDocument/rename", { textDocument: { uri: uri4 }, position: { line: 2, character: aCol }, newName: "Card" });
  const fileEdits = ((renRes.result && renRes.result.changes) || {})[uri4] || [];
  if (fileEdits.length < 2 || !fileEdits.every((e) => e.newText === "Card")) fail("rename A->Card edits wrong: " + JSON.stringify(renRes.result));
  console.log(`rename OK (${fileEdits.length} edits, all -> Card)`);

  // documentSymbol: module Mod with members A, B nested
  const symRes = await request("textDocument/documentSymbol", { textDocument: { uri: uri4 } });
  const mod = (symRes.result || []).find((s) => s.name === "Mod");
  if (!mod || !mod.children || mod.children.length !== 2) fail("documentSymbol wrong: " + JSON.stringify(symRes.result));
  console.log(`documentSymbol OK (module Mod with ${mod.children.length} members)`);

  // unknown-element did-you-mean: <Labl/> is a near-miss of host <Label>
  const uri5 = "file:///tmp/Typo.guitkx";
  const text5 = "component Typo() {\n\treturn ( <Labl /> )\n}\n";
  notify("textDocument/didOpen", { textDocument: { uri: uri5, languageId: "guitkx", version: 1, text: text5 } });
  await new Promise((r) => setTimeout(r, 300));
  const d5 = diagnostics[uri5] || [];
  if (!d5.some((x) => x.message.includes("GUITKX0105") && x.message.includes("Label"))) fail("did-you-mean missing for <Labl>: " + JSON.stringify(d5));
  console.log("did-you-mean OK (<Labl> -> suggests Label)");

  // in-process formatting: a messy doc returns a canonical edit (no Godot binary)
  const uri6 = "file:///tmp/Fmt.guitkx";
  const text6 = 'component Z(){\nreturn ( <VBoxContainer><Label text="hi"/></VBoxContainer> )\n}\n';
  notify("textDocument/didOpen", { textDocument: { uri: uri6, languageId: "guitkx", version: 1, text: text6 } });
  const fmtRes = await request("textDocument/formatting", { textDocument: { uri: uri6 }, options: { tabSize: 4, insertSpaces: false } });
  const edits = fmtRes.result || [];
  // Phase D: the canonical style is spaces-2 (Unity-exact) -- markup sits at level 2 = four spaces
  if (!edits.length || !edits[0].newText.includes("    <VBoxContainer>") || !edits[0].newText.includes('<Label text="hi" />')) fail("in-process formatting edit wrong: " + JSON.stringify(fmtRes.result));
  console.log("formatting OK (in-process, no Godot binary, canonical edit)");

  // semantic tokens: <Label> host (type) + <A> component (class) in the module file
  const stRes = await request("textDocument/semanticTokens/full", { textDocument: { uri: uri4 } });
  const stData = (stRes.result && stRes.result.data) || [];
  if (stData.length < 10 || stData.length % 5 !== 0) fail("semanticTokens malformed: " + JSON.stringify(stData));
  console.log(`semantic tokens OK (${stData.length / 5} tokens, host vs component)`);

  // signature help: on_pressed={ func(| ) } on a host Button -> Button.pressed signature
  const uri7 = "file:///tmp/Sig.guitkx";
  const text7 = "component S(){\n\treturn ( <Button on_pressed={ func(): pass } /> )\n}\n";
  notify("textDocument/didOpen", { textDocument: { uri: uri7, languageId: "guitkx", version: 1, text: text7 } });
  const sigCol = text7.split("\n")[1].indexOf("func(") + 5;
  const sigRes = await request("textDocument/signatureHelp", { textDocument: { uri: uri7 }, position: { line: 1, character: sigCol } });
  const sigs = (sigRes.result && sigRes.result.signatures) || [];
  if (!sigs.length || !sigs[0].label.startsWith("pressed(")) fail("signatureHelp wrong: " + JSON.stringify(sigRes.result));
  console.log(`signature help OK (${sigs[0].label})`);

  // compiler diagnostics sidecar: a hash-matching sidecar surfaces compiler-only diagnostics, and goes
  // stale (suppressed) once the buffer diverges
  const scText = "component W() {\n\treturn ( <Label /> )\n}\n";
  const scFsPath = path.join(os.tmpdir(), "GuitkxSidecar.guitkx");
  fs.writeFileSync(scFsPath + ".diags.json", JSON.stringify({ src_hash: srcHash(scText), diagnostics: [{ code: "GUITKX0106", severity: "warning", message: "GUITKX0106 (warning): element in @for has no key" }] }));
  const scUri = "file:///" + scFsPath.replace(/\\/g, "/");
  notify("textDocument/didOpen", { textDocument: { uri: scUri, languageId: "guitkx", version: 1, text: scText } });
  await new Promise((r) => setTimeout(r, 300));
  if (!(diagnostics[scUri] || []).some((d) => d.message.includes("GUITKX0106"))) fail("compiler sidecar not surfaced: " + JSON.stringify(diagnostics[scUri]));
  notify("textDocument/didChange", { textDocument: { uri: scUri, version: 2 }, contentChanges: [{ text: scText + "\n# edited\n" }] });
  await new Promise((r) => setTimeout(r, 300));
  if ((diagnostics[scUri] || []).some((d) => d.message.includes("GUITKX0106"))) fail("stale sidecar should be suppressed after edit");
  fs.unlinkSync(scFsPath + ".diags.json");
  console.log("compiler sidecar OK (surfaced on hash match, suppressed when stale)");

  // 0.8.2: the sidecar lands SECONDS AFTER the save (the addon's watch poll compiles ~2s later),
  // long after the save-time validation read the previous one -- the server must re-validate on
  // the sidecar's own change event or a compiler-only error NEVER squiggles (field capture
  // 2026-07-04: GUITKX0105 in the Godot dock, nothing in VS Code). Simulate the client watcher:
  // write a fresh sidecar matching the CURRENT buffer, send only didChangeWatchedFiles.
  const scEdited = scText + "\n# edited\n";
  fs.writeFileSync(scFsPath + ".diags.json", JSON.stringify({ src_hash: srcHash(scEdited), diagnostics: [{ code: "GUITKX0105", severity: "error", message: "GUITKX0105: unknown element <VdsBs>" }] }));
  notify("workspace/didChangeWatchedFiles", { changes: [{ uri: scUri + ".diags.json", type: 2 }] });
  await new Promise((r) => setTimeout(r, 300));
  if (!(diagnostics[scUri] || []).some((d) => d.message.includes("GUITKX0105"))) fail("post-save sidecar write not re-validated: " + JSON.stringify(diagnostics[scUri]));
  fs.unlinkSync(scFsPath + ".diags.json");
  notify("workspace/didChangeWatchedFiles", { changes: [{ uri: scUri + ".diags.json", type: 3 }] });
  await new Promise((r) => setTimeout(r, 300));
  if ((diagnostics[scUri] || []).some((d) => d.message.includes("GUITKX0105"))) fail("deleted sidecar should clear the compiler diagnostics");
  console.log("sidecar watch OK (post-save write re-validates without a document event, deletion clears)");

  console.log("SMOKE PASSED");
  server.kill();
  process.exit(0);
})();
