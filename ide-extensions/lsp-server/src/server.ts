// guitkx language server. Markup intelligence (tag/attribute/directive completion + hover) is
// answered locally from the schema; embedded-GDScript intelligence ({expr}, setup, conditions) is
// answered by @gdscript-analyzer/core (a headless GDScript analyzer) over a virtual `.gd` document +
// source map — no running Godot editor required. Diagnostics are a light structural pass (unbalanced
// tags/braces). Transport: stdio (VS Code client + VS2022 ILanguageClient both speak this).

import {
  createConnection,
  TextDocuments,
  ProposedFeatures,
  InitializeParams,
  TextDocumentSyncKind,
  CompletionItem,
  CompletionItemKind,
  InsertTextFormat,
  Hover,
  MarkupKind,
  Diagnostic,
  DiagnosticSeverity,
  DiagnosticTag,
  Location,
  DocumentSymbol,
  SymbolKind,
  TextEdit,
  SignatureHelp,
  InlayHint,
  CodeAction,
  DidChangeWatchedFilesNotification,
  FileChangeType,
} from "vscode-languageserver/node";
import { TextDocument } from "vscode-languageserver-textdocument";

import { classifyContext, CursorContext } from "./context";
import { buildVirtualDoc } from "./virtualDoc";
import { offsetToPosition } from "./sourceMap";
import { skipString, skipNoncodeMarkup, findMatching, findMatchingMarkup, isIdent } from "./scanner";
import { declarationDiags } from "./declarations";
import { windowStructureDiags, hookContextDiags } from "./liveMarkup";
import { uriToProjectPath } from "./guitkxFormat";
import { formatGuitkx, FmtOptions, markupWindows, unreachableRegions, missingReturnComponents, unclosedReturns, loadFormatterConfig, setupSpans, splitBody } from "./formatGuitkx";
import { dirname, join, relative, resolve, isAbsolute } from "path";
import { pathToFileURL } from "url";
import { importAt, importBraceAt, ImportBraceContext, resolveSpecifier } from "./importNav";
import { reflowEmbedded } from "./reflowEmbedded";
import { hasDump, classProperties, classSignals } from "./classdb";
import { eventCompletionsFor, resolveSignalName, validEventAttrs, isEventAttr } from "./events";
import { WorkspaceIndex, scanWorkspace, componentTagAt, offsetToPosition as offsetToPos, scanDeclarations, guitkxVirtualLibText, normalizeUri, pathToUri } from "./workspaceIndex";
import { scanTagRefs, scanImportClauseRefs, scanExportMarkerRefs } from "./refs";
import { markupTokens, encodeTokens, importBindingTokens, importKindTokenOf, Tok, TOKEN_TYPES, TOKEN_MODIFIERS } from "./semanticTokens";
import { srcHash, readSidecar } from "./diagsSidecar";
import { cpToUtf16 } from "./codePoints";
import { readFileSync, readdirSync, statSync, existsSync, watch as fsWatch } from "fs";
import { AnalyzerAdapter, AdapterSymbol } from "./analyzerAdapter";
import {
  HOST_TAGS,
  STRUCTURAL_ATTRS,
  COMMON_ATTRS,
  PREAMBLE_DIRECTIVES,
  CONTROL_FLOW,
  findTag,
  STYLE_KEYS,
  BUILTIN_MEMBERS,
  VOCABULARY,
} from "./schema";

const connection = createConnection(ProposedFeatures.all);
const documents = new TextDocuments(TextDocument);
const index = new WorkspaceIndex();
const analyzer = new AnalyzerAdapter();
let projectPath = "";
let embeddedReflow = true;
let embeddedEnabled = true;
let gdscriptAnalysisEnabled = true;
let canWatchFiles = false;

// G-12: the single place that resolves `guitkx.*` settings (+ legacy aliases) into the server's
// module-level toggles -- shared by onInitialize (first read) and onDidChangeConfiguration (live
// updates), so a setting toggled without a restart takes effect exactly the same way it did at
// startup. `opts` is either InitializeParams.initializationOptions or the `guitkx` section of a
// workspace/didChangeConfiguration notification -- both are a flat bag of the same option names.
function applyGuitkxOptions(opts: any): void {
  // `embeddedReflow` runs embedded GDScript through the analyzer's formatter (so it matches a real .gd
  // file); `useGdformat` is the legacy name for the same toggle.
  if (typeof opts.embeddedReflow === "boolean") embeddedReflow = opts.embeddedReflow;
  else if (typeof opts.useGdformat === "boolean") embeddedReflow = opts.useGdformat;
  // `enableEmbeddedAnalysis` toggles embedded-GDScript intelligence (completion/hover/definition
  // inside {expr}/setup). `enableGodotProxy` is the legacy name, still honored.
  if (typeof opts.enableEmbeddedAnalysis === "boolean") embeddedEnabled = opts.enableEmbeddedAnalysis;
  else if (typeof opts.enableGodotProxy === "boolean") embeddedEnabled = opts.enableGodotProxy;
  // G-20: `enableGdscriptAnalysis` gates plain-`.gd` analysis SERVER-SIDE too (VS Code already
  // gates client-side by not registering the `.gd` selector; VS2022 has no such mechanism, so this
  // is the only gate it gets -- see isGdAnalysisEnabled below).
  if (typeof opts.enableGdscriptAnalysis === "boolean") gdscriptAnalysisEnabled = opts.enableGdscriptAnalysis;
}

connection.onInitialize((params: InitializeParams) => {
  canWatchFiles = !!params.capabilities.workspace?.didChangeWatchedFiles?.dynamicRegistration;
  const opts = (params.initializationOptions as any) || {};
  applyGuitkxOptions(opts);
  const rootUri = params.rootUri || (params.workspaceFolders?.[0]?.uri ?? "");
  projectPath = uriToProjectPath(rootUri);
  // Feed project.godot to the analyzer (enables [autoload] singleton resolution). Best-effort.
  try {
    analyzer.setProjectConfig(readFileSync(join(projectPath, "project.godot"), "utf8"));
  } catch {
    /* no project.godot here — embedded analysis still works per-file */
  }
  scanWorkspace(index, projectPath);
  // Load the project's addon `.gd` libraries (e.g. ReactiveUI's `core/hooks.gd` with `class_name
  // Hooks`) into the analyzer so embedded code resolves cross-file — enabling go-to-definition into
  // the real library files (`useRef` -> hooks.gd, `V.create` -> v.gd). Best-effort, once.
  loadLibraries();
  // T4.5: every indexed .guitkx also feeds its compiled BINDINGS as a virtual library (after
  // loadLibraries, so a real generated sibling .gd on disk wins and the virtual one is skipped).
  syncAllGuitkxLibraries();
  return {
    capabilities: {
      textDocumentSync: TextDocumentSyncKind.Incremental,
      // (workspace-completeness is armed in onInitialized, after the .gd watcher registers)
      completionProvider: { triggerCharacters: ["<", "@", ".", " ", "_"] },
      hoverProvider: true,
      documentFormattingProvider: true,
      documentRangeFormattingProvider: true,
      definitionProvider: true,
      referencesProvider: true,
      renameProvider: { prepareProvider: true },
      documentSymbolProvider: true,
      signatureHelpProvider: { triggerCharacters: ["(", ","] },
      inlayHintProvider: true,
      codeActionProvider: true,
      semanticTokensProvider: {
        legend: { tokenTypes: TOKEN_TYPES, tokenModifiers: TOKEN_MODIFIERS },
        full: true,
      },
    },
  };
});

// Arm the analyzer's absence-based UNDEFINED_FUNCTION / UNDEFINED_IDENTIFIER diagnostics (core
// 0.5.3+). They only fire when the analyzer PROVABLY holds the whole project — a partial view can
// never prove a typo'd name is defined nowhere — so the claim is made strictly after (a) SOME file
// watcher is live: the client's (dynamic registration — VS Code) or the in-process fs.watch fallback
// (VS2022's client cannot register watchers; Node's recursive fs.watch exists exactly on the
// platforms VS2022 runs on), (b) a fresh loadLibraries() pass ran AFTER the watcher went live (a
// `.gd` created between the init-time load and watcher activation would otherwise be invisible
// forever), and (c) that pass read every file it found (an unreadable file = a name we cannot prove
// absent). With neither watcher available, UNDEFINED_* stay silent — the pre-0.5.3 behavior.
connection.onInitialized(() => {
  if (!projectPath) return;
  if (!canWatchFiles) {
    startNativeWatcher();
    return;
  }
  connection.client
    .register(DidChangeWatchedFilesNotification.type, {
      // "**" and not per-extension globs: FOLDER events only get delivered for patterns that
      // match the folder path itself, and deleting a component's directory arrives as exactly
      // one such event (field capture 2026-07-04: with file-only globs the folder-deletion
      // handler was correct and UNREACHABLE in production). handleWatchedPath routes cheaply;
      // irrelevant file events fall through a couple of string checks.
      watchers: [{ globPattern: "**" }],
    })
    .then(() => armWorkspaceComplete())
    .catch(() => startNativeWatcher()); // client refused — try the in-process fallback
});

// G-12: re-read `guitkx.*` on a live settings change (no restart needed). The VS Code client
// synchronizes the `guitkx` section (see extension.ts's `synchronize.configurationSection`), so
// `change.settings.guitkx` is the same flat option bag onInitialize saw. Toggling e.g.
// enableEmbeddedAnalysis flips embedded hover/completion on the next request; VS2022 pushes the
// same shape whenever GuitkxSettings changes (see GuitkxLanguageClient.CustomMessageTarget).
connection.onDidChangeConfiguration((change) => {
  const settings = (change.settings as any)?.guitkx;
  if (settings) applyGuitkxOptions(settings);
});

function armWorkspaceComplete(): void {
  if (!loadLibraries()) return; // incomplete scan — never over-claim
  analyzer.setWorkspaceComplete(true);
  // The component universe (indexed .guitkx bindings + harvested .gd class_names) is complete
  // too — arm the live PascalCase unknown-component check (GUITKX0105, ungated by T4.5).
  componentUniverseReady = true;
  // Diagnostics published before arming were computed with UNDEFINED_* disarmed — re-publish
  // every open document so files opened at startup get the armed pass too.
  for (const doc of documents.all()) publishDiagnosticsFor(doc);
}

// The project's `.gd` `class_name`s, harvested during the library walks. This set used to be
// grow-only ("a stale entry can only suppress, never false-flag") — safe when every .gd was
// hand-written, WRONG once .gd files are generated: deleting/renaming a component removed its
// script, but the leftover name kept suppressing the live unknown-component check forever
// (field capture 2026-07-04: dangling <ThirdComponent /> references stayed squiggle-free).
// The path→class map keeps the set honest: a deleted .gd un-harvests its name unless another
// file still declares it.
const gdClassNames = new Set<string>();
const gdClassByPath = new Map<string, string>(); // keys normalized via normFsPath
let componentUniverseReady = false;
// Map keys must survive the different path spellings the harvest sources produce (library walk
// vs watcher events vs sibling derivation): lowercase + single separator form.
function normFsPath(p: string): string {
  return p.toLowerCase().replace(/\//g, "\\");
}
function harvestClassName(fsPath: string, text: string): void {
  const key = normFsPath(fsPath);
  const m = /^[ \t]*class_name[ \t]+([A-Za-z_][A-Za-z0-9_]*)/m.exec(text);
  const next = m ? m[1] : null;
  const prev = gdClassByPath.get(key);
  if (prev && prev !== next) {
    gdClassByPath.delete(key);
    if (![...gdClassByPath.values()].includes(prev)) gdClassNames.delete(prev);
  }
  if (next) {
    gdClassByPath.set(key, next);
    gdClassNames.add(next);
  }
}
function unharvestClassName(fsPath: string): void {
  const key = normFsPath(fsPath);
  const prev = gdClassByPath.get(key);
  if (!prev) return;
  gdClassByPath.delete(key);
  if (![...gdClassByPath.values()].includes(prev)) gdClassNames.delete(prev);
}

// Cross-file re-validation: a .guitkx or .gd appearing/changing/vanishing can flip diagnostics
// in every OPEN document (a component universe change arms or clears unknown-component
// squiggles), but document events only fire for the edited file itself — so schedule a
// coalesced re-publish of all open docs after workspace-shape changes (100 ms absorbs the
// event storms of bulk deletes/renames).
let republishTimer: ReturnType<typeof setTimeout> | null = null;
function scheduleRepublish(): void {
  if (republishTimer) clearTimeout(republishTimer);
  republishTimer = setTimeout(() => {
    republishTimer = null;
    for (const doc of documents.all()) publishDiagnosticsFor(doc);
  }, 100);
}

// In-process watcher fallback for clients without dynamic watcher registration. fs.watch storms
// during saves (multiple change/rename events per write), so events coalesce per path for 200 ms.
// Recursive fs.watch is unavailable on Linux — there we stay disarmed rather than over-claim.
let fsEventTimers = new Map<string, NodeJS.Timeout>();
function startNativeWatcher(): void {
  if (process.platform !== "win32" && process.platform !== "darwin") return;
  try {
    fsWatch(projectPath, { recursive: true }, (_ev, fname) => {
      if (!fname) return;
      const fsPath = join(projectPath, String(fname));
      const prev = fsEventTimers.get(fsPath);
      if (prev) clearTimeout(prev);
      fsEventTimers.set(
        fsPath,
        setTimeout(() => {
          fsEventTimers.delete(fsPath);
          handleWatchedPath(fsPath, !existsSync(fsPath));
        }, 200)
      );
    });
  } catch {
    return; // recursive watch unavailable — leave the workspace partial (UNDEFINED_* disarmed)
  }
  armWorkspaceComplete();
}

// Keep the analyzer's project view — and therefore the workspace-completeness claim — true while the
// server runs: a `.gd` created/edited/deleted outside an open editor tab is re-fed (or dropped), a
// `.guitkx` event keeps the workspace index (declared-name veto, tag completion) fresh, a
// folder-level event (VS Code coalesces bulk deletes/renames into one event for the directory) evicts
// or rescans the whole subtree, and a ROOT project.godot edit re-feeds the [autoload] table (nested
// project.godot files — demo projects inside the workspace — must not clobber the root config). URIs
// are re-derived from the filesystem path so they hit the same keys loadLibraries() used, regardless
// of client URI normalization.
connection.onDidChangeWatchedFiles((params) => {
  for (const ev of params.changes) {
    handleWatchedPath(uriToProjectPath(ev.uri), ev.type === FileChangeType.Deleted);
  }
});

function handleWatchedPath(fsPath: string, deleted: boolean): void {
  if (fsPath.endsWith(".guitkx.diags.json")) {
    // The Godot watcher writes the compiler sidecar a couple of SECONDS after the save that
    // triggered it (the addon's watch poll), long after this server's save-time validation read
    // the previous one. Without re-validating on the sidecar's own change event, a compiler-only
    // diagnostic (e.g. GUITKX0105 in setup-value markup, which the live tier does not scan yet)
    // could NEVER surface: no later document event re-reads it, and the next keystroke diverges
    // the buffer hash, which suppresses compiler entries by design (field capture 2026-07-04:
    // 0105 in the Godot dock, no squiggle in VS Code). Deletion re-validates too — a removed
    // sidecar means the verdict was cleared.
    const src = fsPath.slice(0, -".diags.json".length).toLowerCase();
    for (const doc of documents.all()) {
      if (uriToProjectPath(doc.uri).toLowerCase() === src) {
        publishDiagnosticsFor(doc);
        break;
      }
    }
    return;
  }
  if (fsPath.endsWith("project.godot")) {
    if (resolve(fsPath) !== resolve(join(projectPath, "project.godot"))) return;
    try {
      analyzer.setProjectConfig(readFileSync(fsPath, "utf8"));
    } catch {
      /* deleted or unreadable — keep the last-known config */
    }
    return;
  }
  if (fsPath.endsWith(".guitkx")) {
    reindexGuitkxFile(fsPath, deleted);
    return;
  }
  if (!fsPath.endsWith(".gd")) {
    // Possibly a directory event: a deleted folder must evict EVERYTHING underneath it — VS
    // Code coalesces bulk deletes into ONE folder event, so no per-file events ever arrive.
    // Analyzer libraries were always closed here; the .guitkx index entries and harvested
    // generated classes were NOT (field capture 2026-07-04: deleting a component's FOLDER left
    // its consumers squiggle-free until an unrelated save).
    if (deleted) {
      analyzer.closeUnder(pathToFileURL(fsPath).toString() + "/");
      const prefix = normFsPath(fsPath) + "\\";
      for (const uri of index.uris()) {
        let p: string;
        try {
          p = uriToProjectPath(uri);
        } catch {
          continue;
        }
        if (normFsPath(p).startsWith(prefix)) {
          index.evict(uri);
          syncGuitkxLibrary(uri);
        }
      }
      for (const key of [...gdClassByPath.keys()]) {
        if (key.startsWith(prefix)) unharvestClassName(key);
      }
      scheduleRepublish();
      return;
    }
    let isDir = false;
    try {
      isDir = statSync(fsPath).isDirectory();
    } catch {
      return;
    }
    if (isDir) {
      for (const f of gdFilesUnder(fsPath)) upsertLibraryFile(f);
      scanWorkspace(index, fsPath);
      scheduleRepublish(); // a moved-in folder can clear (or arm) other docs' diagnostics
    }
    return;
  }
  if (deleted) {
    analyzer.close(pathToFileURL(fsPath).toString());
    unharvestClassName(fsPath); // a generated component's class must not suppress 0105 forever
    resyncSiblingGuitkxLibrary(fsPath); // the generated .gd vanished -> the virtual twin returns
    scheduleRepublish();
    return;
  }
  upsertLibraryFile(fsPath);
  resyncSiblingGuitkxLibrary(fsPath); // the generated .gd appeared -> the virtual twin retires
  scheduleRepublish();
}

// A watched `.gd` may be the GENERATED sibling of an indexed `.guitkx` — its appearance/removal
// flips which of the two (real file vs virtual library) the analyzer should hold.
function resyncSiblingGuitkxLibrary(gdFsPath: string): void {
  const guitkxUri = pathToFileURL(gdFsPath.replace(/\.gd$/i, ".guitkx")).toString();
  if (index.entriesFor(guitkxUri).length) syncGuitkxLibrary(guitkxUri);
}

// Keep the workspace index in step with on-disk `.guitkx` changes. An OPEN document's buffer is the
// source of truth (onDidChangeContent reindexes it) — a stale disk event must not stomp it.
function reindexGuitkxFile(fsPath: string, deleted: boolean): void {
  if (resPathFor(fsPath) === null) return; // outside the project / hidden dirs
  const uri = pathToFileURL(fsPath).toString();
  if (deleted) {
    // Evict EVEN when the document is open: VS Code keeps a deleted file's tab alive, but the
    // component no longer exists on disk -- consumers must squiggle immediately, not after the
    // user happens to save something (field capture 2026-07-04). The open buffer keeps its own
    // diagnostics; if the user re-saves it, the created-file event re-indexes it right back.
    index.evict(uri);
    // Un-harvest the generated sibling's class NOW instead of waiting ~2s for Godot's orphan
    // sweep to delete the .gd (whose deletion event would do it) -- the live unknown-component
    // squiggle should appear on the watcher tick, not on the compiler's schedule.
    unharvestClassName(fsPath.replace(/\.guitkx$/i, ".gd"));
    syncGuitkxLibrary(uri); // no entries left -> closes the virtual library
    scheduleRepublish(); // open docs referencing the vanished component must squiggle NOW
    return;
  }
  if (documents.get(uri)) return; // an OPEN document's buffer is the source of truth for edits
  try {
    index.reindex(uri, readFileSync(fsPath, "utf8"));
    syncGuitkxLibrary(uri);
    scheduleRepublish(); // a new/renamed component can clear (or arm) other docs' diagnostics
  } catch {
    /* unreadable mid-write — the next event retries */
  }
}

// T4.5 — feed one indexed .guitkx's compiled bindings to the analyzer as a virtual library (see
// guitkxVirtualLibText for the rationale; it replaced the vetoGuitkxDeclared suppression). The
// REAL generated sibling .gd wins whenever it exists on disk — loadLibraries/the watcher feed it,
// and the virtual twin is closed so the analyzer's class_name registry never sees a duplicate.
function syncGuitkxLibrary(rawUri: string): void {
  const uri = normalizeUri(rawUri);
  const libUri = uri + ".__guitkx_lib.gd";
  let siblingGd: string;
  try {
    siblingGd = uriToProjectPath(uri).replace(/\.guitkx$/i, ".gd");
  } catch {
    return; // not a file:// uri — nothing to mirror
  }
  const resPath = resPathFor(siblingGd);
  const text = resPath !== null && !existsSync(siblingGd) ? guitkxVirtualLibText(index.entriesFor(uri)) : null;
  if (text === null) analyzer.close(libUri);
  else analyzer.upsertLibrary(libUri, text, resPath as string);
}

function syncAllGuitkxLibraries(): void {
  for (const uri of index.uris()) syncGuitkxLibrary(uri);
}

// Feed one on-disk `.gd` into the analyzer (create or update), keyed identically to loadLibraries().
function upsertLibraryFile(fsPath: string): void {
  const resPath = resPathFor(fsPath);
  if (resPath === null) return;
  try {
    const text = readFileSync(fsPath, "utf8");
    harvestClassName(fsPath, text);
    analyzer.upsertLibrary(pathToFileURL(fsPath).toString(), text, resPath);
  } catch {
    /* unreadable mid-write — the next change event retries */
  }
}

// The res:// path for an absolute file path, or null when the file is not project content: outside
// the project root (other drive, UNC, `..`) or under a hidden dir (res://.godot/** etc.).
function resPathFor(fsPath: string): string | null {
  const rel = relative(projectPath, fsPath).replace(/\\/g, "/");
  if (rel.startsWith("..") || isAbsolute(rel)) return null;
  const res = "res://" + rel;
  return res.startsWith("res://.") ? null : res;
}

// --- formatting (textDocument/formatting + rangeFormatting) — in-process, no Godot binary needed ---

function formatOptsFor(uri: string): Partial<FmtOptions> {
  // Phase D: Unity-exact default — SPACES at width 2. G-19: this is the canon BOTH editors' typing
  // defaults must match too (VS Code's `[guitkx]` configurationDefaults in package.json, VS2022's
  // GuitkxEditorDefaults) — keep all three in lockstep, or every format-on-save churns the whole
  // file's indentation against what the user just typed. Embedded-GDScript reflow converts
  // gdscript-fmt's tab depth to the same unit, so the old mixed-indent hazard is handled at the
  // splice. A project guitkx.config.json (walk-up, like Prettier / uitkx.config.json) overrides
  // printWidth / indentStyle / indentSize / wrapping.
  let dir = "";
  try {
    dir = dirname(uriToProjectPath(uri));
  } catch {
    dir = "";
  }
  return { indentStyle: "space", indentSize: 2, ...(dir ? loadFormatterConfig(dir) : {}) };
}

// In-process markup format (formatGuitkx) + embedded-GDScript reflow through the analyzer's formatter —
// the SAME gdscript-fmt that drives plain .gd files — so embedded code formats identically (BUG-1).
function formatFull(src: string, opts: Partial<FmtOptions>): { text: string; changed: boolean; fellBack: boolean } {
  const fg = formatGuitkx(src, opts);
  const unit = opts.indentStyle === "tab" ? "\t" : " ".repeat(opts.indentSize ?? 2);
  const text = embeddedReflow ? reflowEmbedded(fg.text, (gd) => analyzer.formatGd(gd), unit) : fg.text;
  return { text, changed: text !== src, fellBack: fg.fellBack };
}

// G-06: a format request that fell back to verbatim (a syntax error, not an already-canonical
// file) used to look exactly like "nothing to do" -- the user never learned formatting was
// silently skipped. Warned once per URI per session (not on every keystroke-triggered format of
// the same still-broken file) via the standard LSP window/showMessage, so both VS Code and VS2022
// surface it without editor-specific plumbing.
const formatFallbackWarned = new Set<string>();
function warnFormatFallbackOnce(uri: string): void {
  if (formatFallbackWarned.has(uri)) return;
  formatFallbackWarned.add(uri);
  connection.window.showWarningMessage(`GUITKX: ${uri.split("/").pop()} has syntax errors -- format skipped.`);
}

connection.onDocumentFormatting((params) => {
  const doc = documents.get(params.textDocument.uri);
  if (!doc) return [];
  const src = doc.getText();
  if (isGd(params.textDocument.uri)) {
    if (!isGdAnalysisEnabled()) return [];
    analyzer.sync(params.textDocument.uri, src);
    const formatted = analyzer.formatAt(params.textDocument.uri);
    return formatted === null || formatted === src
      ? []
      : [{ range: { start: { line: 0, character: 0 }, end: doc.positionAt(src.length) }, newText: formatted }];
  }
  const r = formatFull(src, formatOptsFor(params.textDocument.uri));
  if (r.fellBack) warnFormatFallbackOnce(params.textDocument.uri);
  if (!r.changed) return [];
  return [{ range: { start: { line: 0, character: 0 }, end: doc.positionAt(src.length) }, newText: r.text }];
});

connection.onDocumentRangeFormatting((params) => {
  const doc = documents.get(params.textDocument.uri);
  if (!doc) return [];
  const src = doc.getText();
  if (isGd(params.textDocument.uri)) {
    if (!isGdAnalysisEnabled()) return [];
    analyzer.sync(params.textDocument.uri, src);
    const e = analyzer.formatRangeAt(params.textDocument.uri, src, doc.offsetAt(params.range.start), doc.offsetAt(params.range.end));
    return e ? [{ range: { start: doc.positionAt(e.start), end: doc.positionAt(e.end) }, newText: e.newText }] : [];
  }
  const r = formatFull(src, formatOptsFor(params.textDocument.uri));
  if (r.fellBack) warnFormatFallbackOnce(params.textDocument.uri);
  if (!r.changed) return [];
  // Whole-doc format, then return the single minimal line-hunk (common prefix/suffix diff). The whole
  // minimal hunk is emitted when it intersects the requested range (it may extend slightly past the
  // selection — it is still the minimal edit; we never touch lines outside the changed region).
  const o = src.split("\n");
  const f = r.text.split("\n");
  let start = 0;
  while (start < o.length && start < f.length && o[start] === f[start]) start++;
  let oEnd = o.length;
  let fEnd = f.length;
  while (oEnd > start && fEnd > start && o[oEnd - 1] === f[fEnd - 1]) {
    oEnd--;
    fEnd--;
  }
  if (oEnd <= params.range.start.line || start > params.range.end.line) return [];
  // join with "\n" and add a trailing newline only when the hunk does NOT reach the document's last
  // line (else formatGuitkx's always-present final "\n" would inject a spurious blank line).
  const newText = f.slice(start, fEnd).join("\n") + (oEnd < o.length ? "\n" : "");
  return [{ range: { start: { line: start, character: 0 }, end: { line: oEnd, character: 0 } }, newText }];
});

// --- completion ---

connection.onCompletion(async (params): Promise<CompletionItem[]> => {
  const doc = documents.get(params.textDocument.uri);
  if (!doc) return [];
  const src = doc.getText();
  const offset = doc.offsetAt(params.position);
  if (isGd(params.textDocument.uri)) {
    if (!isGdAnalysisEnabled()) return [];
    analyzer.sync(params.textDocument.uri, src);
    return analyzer.completionsAt(params.textDocument.uri, src, offset);
  }
  // Import-brace completion (0.11.1 field wave): a caret inside `import { | } from "./x"` —
  // including the COMBINED `import Def, { | } from` — offers the target's exported declaration
  // names. Checked before classifyContext: an import line is preamble, not markup/embedded code.
  const braceCtx = importBraceAt(src, offset);
  if (braceCtx) return importBraceCompletions(params.textDocument.uri, braceCtx);
  const ctx = classifyContext(src, offset);

  switch (ctx.kind) {
    case "tagName":
      return [
        ...HOST_TAGS.map((t) => ({
          label: t.tag,
          kind: CompletionItemKind.Class,
          detail: `${t.factory} (${t.godotClass})`,
          documentation: `Host element — Godot ${t.godotClass}.`,
        })),
        ...componentNames().map((n) => ({ label: n, kind: CompletionItemKind.Class, detail: "component" })),
      ];
    case "attrName": {
      const items: CompletionItem[] = [];
      // structural attrs are valid on every element
      for (const a of STRUCTURAL_ATTRS)
        items.push({ label: a.name, kind: CompletionItemKind.Property, detail: a.type, documentation: a.detail });
      const tag = ctx.tag ? findTag(ctx.tag) : undefined;
      if (tag && hasDump()) {
        // HOST element: every Control property of its godotClass, from the ClassDB dump
        for (const p of classProperties(tag.godotClass))
          items.push({ label: p.name, kind: CompletionItemKind.Property, detail: `${p.type} (${tag.godotClass})` });
        // React-style event handlers (onClick / onChange / onPointer* / …) resolved from the class's
        // signals; `onChange` is polymorphic. The native on_<signal> spelling stays valid too. (events.ts)
        for (const ev of eventCompletionsFor(classSignals(tag.godotClass)))
          items.push({ label: ev.label, kind: CompletionItemKind.Event, detail: ev.detail });
      } else if (tag) {
        // dump not available: fall back to the static common-attrs + schema events
        for (const a of COMMON_ATTRS)
          items.push({ label: a.name, kind: CompletionItemKind.Property, detail: a.type, documentation: a.detail });
        for (const ev of tag.events ?? [])
          items.push({ label: ev, kind: CompletionItemKind.Event, detail: "Callable" });
      }
      // (a PascalCase component tag has no godotClass -> only structural attrs)
      return items;
    }
    case "directive":
      return [...PREAMBLE_DIRECTIVES, ...CONTROL_FLOW].map((d) => ({
        label: d.label,
        kind: CompletionItemKind.Keyword,
        detail: d.detail,
        insertText: d.insert,
        insertTextFormat: InsertTextFormat.Snippet,
      }));
    case "markup":
      return [
        ...HOST_TAGS.map((t) => ({ label: "<" + t.tag, kind: CompletionItemKind.Class, detail: t.factory })),
        ...componentNames().map((n) => ({ label: "<" + n, kind: CompletionItemKind.Class, detail: "component" })),
        ...CONTROL_FLOW.map((d) => ({
          label: d.label,
          kind: CompletionItemKind.Keyword,
          insertText: d.insert,
          insertTextFormat: InsertTextFormat.Snippet,
          detail: d.detail,
        })),
      ];
    case "embedded": {
      // style={ {…} } dict -> RuitkStyle keys (the GDScript analyzer has no vocabulary for these).
      if (inStyleDict(src, offset))
        return STYLE_KEYS.map((a) => ({ label: a.name, kind: CompletionItemKind.Property, detail: a.type, documentation: a.detail }));
      // `<Type>.<frag>` built-in constants (Color.WHITE, …) as a static fallback, merged with Godot's.
      const builtin = builtinMemberCompletions(src, offset);
      const proxied = await forwardCompletion(params.textDocument.uri, src, offset);
      if (builtin.length === 0) return proxied;
      const seen = new Set(proxied.map((p) => p.label));
      return [...builtin.filter((b) => !seen.has(b.label)), ...proxied];
    }
  }
});

// Indexed component bindings that can appear as a `<Tag>`: PascalCase and not a host element. Hooks
// (snake_case) are naturally excluded; module-member components are included. (BUG-7)
function componentNames(): string[] {
  return index.names().filter((n) => /^[A-Z]/.test(n) && !findTag(n));
}

// The target's exported declaration names for a caret inside an import brace list, minus what the
// line already binds. With a COMBINED default binding present (`import Def, { | }`), the default
// alias AND the target's default-export name join the exclusion set — re-suggesting the member the
// default already binds is noise. Degrades to [] when the target is unresolvable.
function importBraceCompletions(uri: string, ctx: ImportBraceContext): CompletionItem[] {
  if (!ctx.spec) return [];
  let fsPath: string;
  try {
    fsPath = uriToProjectPath(uri);
  } catch {
    return [];
  }
  const target = resolveSpecifier(ctx.spec, fsPath, projectPath);
  if (!target) return [];
  let targetText: string;
  try {
    targetText = readFileSync(target, "utf8");
  } catch {
    return [];
  }
  const already = new Set(ctx.already);
  if (ctx.def) {
    already.add(ctx.def);
    const dm = /^[ \t]*export[ \t]+default[ \t]+([A-Za-z_]\w*)/m.exec(targetText);
    if (dm) already.add(dm[1]);
  }
  const items: CompletionItem[] = [];
  for (const d of scanDeclarations(targetText)) {
    if (!d.export || d.module || already.has(d.name)) continue;
    already.add(d.name);
    items.push({
      label: d.name,
      kind: d.kind === "component" ? CompletionItemKind.Class : d.kind === "value" ? CompletionItemKind.Variable : CompletionItemKind.Function,
      detail: d.kind,
    });
  }
  return items;
}

// '{' positions enclosing `offset` (string/comment-aware), innermost last.
function openBraceStack(src: string, offset: number): number[] {
  const stack: number[] = [];
  let i = 0;
  while (i < offset) {
    const c = src[i];
    if (c === '"' || c === "'") {
      i = skipString(src, i);
      continue;
    }
    if (c === "#") {
      while (i < offset && src[i] !== "\n") i++;
      continue;
    }
    if (c === "{") stack.push(i);
    else if (c === "}") stack.pop();
    i++;
  }
  return stack;
}

// True when the cursor sits inside a `style={ {…} }` (or `*_style`) DICT — where the keys are
// RuitkStyle's, not Godot's. Requires an inner dict (not the bare `style={ref}` value, preceded by `=`).
function inStyleDict(src: string, offset: number): boolean {
  const stack = openBraceStack(src, offset);
  if (stack.length === 0) return false;
  let j = stack[stack.length - 1] - 1;
  while (j >= 0 && /\s/.test(src[j])) j--;
  if (src[j] === "=") return false; // innermost brace IS the attr value (a ref/expr), not a dict
  for (let s = stack.length - 1; s >= 0; s--) {
    let k = stack[s] - 1;
    while (k >= 0 && /\s/.test(src[k])) k--;
    if (src[k] !== "=") continue;
    k--;
    while (k >= 0 && /\s/.test(src[k])) k--;
    const e = k + 1;
    while (k >= 0 && /[A-Za-z0-9_]/.test(src[k])) k--;
    const name = src.slice(k + 1, e);
    return name === "style" || name.endsWith("_style");
  }
  return false;
}

// `<Type>.<frag>` built-in constant completion (Color.WHITE, Vector2.ZERO, …).
function builtinMemberCompletions(src: string, offset: number): CompletionItem[] {
  let i = offset;
  while (i > 0 && /[A-Za-z0-9_]/.test(src[i - 1])) i--;
  if (i === 0 || src[i - 1] !== ".") return [];
  let j = i - 1;
  const e = j;
  while (j > 0 && /[A-Za-z0-9_]/.test(src[j - 1])) j--;
  const members = BUILTIN_MEMBERS[src.slice(j, e)];
  if (!members) return [];
  const type = src.slice(j, e);
  return members.map((m) => ({ label: m, kind: CompletionItemKind.Constant, detail: `${type}.${m}` }));
}

function forwardCompletion(uri: string, src: string, offset: number): CompletionItem[] {
  if (!embeddedEnabled) return []; // embedded-GDScript intelligence disabled by the client
  const { text, map } = buildVirtualDoc(src);
  const genOffset = map.toGenerated(offset);
  if (genOffset === null) return [];
  const vUri = uri.replace(/\.guitkx$/, ".__guitkx_virtual.gd");
  analyzer.sync(vUri, text);
  // The analyzer answers from the virtual `.gd`; items carry no positions (GDScript symbols are
  // position-free), so we use them as-is. Byte<->char conversion is handled inside the adapter.
  return analyzer.completionsAt(vUri, text, genOffset);
}

// --- hover ---

// BUG-V8: curated hover for the built-in hooks — the analyzer only sees the virtual-doc stub as
// `Callable`, so hovering a hook name returned nothing useful. Signatures mirror core/hooks.gd.
const HOOK_HOVER: Record<string, string> = {
  useState: "**useState**(initial = null) → `[value, setter]`\n\nReactive state: read `s[0]`, set with `s[1].call(v)` (a value or an updater func).",
  useReducer: "**useReducer**(reducer: Callable, initial = null) → `[state, dispatch]`",
  useRef: "**useRef**(initial = null) → `{ current }`\n\nA mutable box that persists across renders (setting it does not re-render).",
  useMemo: "**useMemo**(factory: Callable, deps = []) → value\n\nMemoized value; recomputes only when `deps` change.",
  useCallback: "**useCallback**(cb: Callable, deps = []) → `Callable`",
  useImperativeHandle: "**useImperativeHandle**(factory: Callable, deps = [])",
  useEffect: "**useEffect**(effect: Callable, deps = null)\n\nRun a side effect after commit; return a Callable to clean up. `deps = []` runs once on mount.",
  useLayoutEffect: "**useLayoutEffect**(effect: Callable, deps = null)\n\nLike `useEffect` but runs synchronously after layout.",
  createContext: "**createContext**(default = null, name = \"\") → `RuitkContext`\n\nA context handle for `provideContext` / `useContext` (object identity — no string-key collisions).",
  useContext: "**useContext**(key) → value\n\nRead the nearest provided value for a context handle (or string key).",
  provideContext: "**provideContext**(key, value)\n\nProvide a context value to the subtree below.",
  useDeferredValue: "**useDeferredValue**(value, deps = null)",
  useTransition: "**useTransition**() → `[is_pending, start]`",
  useStableCallback: "**useStableCallback**(cb: Callable) → `Callable`\n\nA stable Callable identity that always invokes the latest `cb`.",
  useStableFunc: "**useStableFunc**(cb: Callable) → `Callable`",
  useStableAction: "**useStableAction**(cb: Callable) → `Callable`",
  useSafeArea: "**useSafeArea**() → `Dictionary`",
  useSignal: "**useSignal**(sig: RuitkSignal, selector = null, comparer = null)",
  useSignalKey: "**useSignalKey**(key: String, initial = null, selector = null, comparer = null)",
  useTween: "**useTween**(ref, property: String, to, duration: float, deps = [])",
  useTweenValue: "**useTweenValue**(from, to, duration: float, on_update: Callable, deps = [])",
  useAnimate: "**useAnimate**(ref, tracks: Array, autoplay = true, deps = [])",
  useSfx: "**useSfx**(bus = \"Master\") → `Callable`",
};

connection.onHover(async (params): Promise<Hover | null> => {
  try {
    const doc = documents.get(params.textDocument.uri);
    if (!doc) return null;
    const src = doc.getText();
    const offset = doc.offsetAt(params.position);
    if (isGd(params.textDocument.uri)) {
      if (!isGdAnalysisEnabled()) return null;
      analyzer.sync(params.textDocument.uri, src);
      const c = analyzer.hoverAt(params.textDocument.uri, src, offset);
      return c ? { contents: c } : null;
    }
    const ctx = classifyContext(src, offset);

    if (ctx.kind === "tagName" || ctx.kind === "attrName") return markupHover(src, offset, ctx);
    if (ctx.kind === "embedded" && embeddedEnabled) {
      // BUG-V8: a curated signature for a hook identifier beats the analyzer's bare `Callable`.
      const hw = wordRangeAt(src, offset);
      const hword = src.slice(hw.start, hw.end);
      if (HOOK_HOVER[hword]) return md(HOOK_HOVER[hword]);
      const { text, map } = buildVirtualDoc(src);
      const genOffset = map.toGenerated(offset);
      if (genOffset === null) return null;
      const vUri = params.textDocument.uri.replace(/\.guitkx$/, ".__guitkx_virtual.gd");
      analyzer.sync(vUri, text);
      const contents = analyzer.hoverAt(vUri, text, genOffset);
      if (contents) return { contents };
    }
    return null;
  } catch {
    return null; // hover is best-effort; never throw out of the handler
  }
});

// Markup hover. Resolve the FULL identifier under the cursor (not the truncated word-before) against a
// host element, a workspace component, or — for an attribute — the enclosing host tag's ClassDB
// property/signal dump, mirroring completion. The old path only matched a host tag at the exact end of
// its name and never consulted ClassDB, so real attributes and component tags hovered to nothing (BUG-6).
function markupHover(src: string, offset: number, ctx: CursorContext): Hover | null {
  const w = wordRangeAt(src, offset);
  const word = src.slice(w.start, w.end);
  if (!word) return null;
  if (ctx.kind === "tagName") {
    const tag = findTag(word);
    if (tag) return md(`**<${word}>** — host element · Godot \`${tag.godotClass}\`.`);
    if (index.has(word)) {
      const e = index.lookup(word)[0];
      const kind = e.kind === "member" ? "component" : e.kind;
      const sig = componentSignature(e);
      return md(`**<${word}>** — user ${kind} \`${word}${sig}\`. Press F12 / ctrl+click to open its declaration.`);
    }
    return null;
  }
  // attrName — resolve against the enclosing host tag's ClassDB props/signals, then structural/common.
  const host = ctx.tag ? findTag(ctx.tag) : undefined;
  if (host && hasDump()) {
    // Event handler? Resolve either spelling (React onClick/onChange/… or native on_<signal>) to its
    // underlying Godot signal on this control's class. (events.ts)
    const sigs = classSignals(host.godotClass);
    const signalName = resolveSignalName(word, (s) => sigs.some((x) => x.name === s));
    if (signalName !== undefined) {
      const sig = sigs.find((s) => s.name === signalName);
      if (sig) return md(`**${word}** — Godot signal \`${sig.name}(${sig.args.map((a) => `${a.name}: ${a.type}`).join(", ")})\` on \`${host.godotClass}\`.`);
    }
    const prop = classProperties(host.godotClass).find((p) => p.name === word);
    if (prop) return md(`**${word}**: \`${prop.type}\` — property on \`${host.godotClass}\`.`);
  }
  const attr = [...STRUCTURAL_ATTRS, ...COMMON_ATTRS].find((a) => a.name === word);
  if (attr) return md(`**${attr.name}**: \`${attr.type}\` — ${attr.detail}`);
  return null;
}

function md(value: string): Hover {
  return { contents: { kind: MarkupKind.Markdown, value } };
}

// --- diagnostics (light structural pass) ---

documents.onDidChangeContent((change) => publishDiagnosticsFor(change.document));

function publishDiagnosticsFor(doc: TextDocument): void {
  if (isGd(doc.uri)) {
    // G-20: empty (not skipped) -- clears any diagnostics from before the setting was turned off.
    connection.sendDiagnostics({ uri: doc.uri, diagnostics: isGdAnalysisEnabled() ? gdDiagnostics(doc.uri, doc.getText()) : [] });
    return;
  }
  index.reindex(doc.uri, doc.getText());
  syncGuitkxLibrary(doc.uri);
  const live = [
    ...declarationDiagnostics(doc),
    ...structuralDiagnostics(doc),
    ...markupDiagnostics(doc),
    ...missingReturnDiagnostics(doc),
    ...unclosedReturnDiagnostics(doc),
    ...unreachableDiagnostics(doc),
    ...embeddedDiagnostics(doc),
  ];
  connection.sendDiagnostics({ uri: doc.uri, diagnostics: mergeCompilerSidecar(doc, live) });
}


// The generated Warning Reference for the analyzer's codes — one table page; linked from every
// warning-code diagnostic via LSP codeDescription (T4.6: the code is a real Diagnostic.code now,
// not a prefix folded into the message).
const GD_WARNING_DOCS = "https://reactive-ui-toolkit.github.io/gdscript-analyzer/reference/warnings.html";

// The LSP `code`/`codeDescription`/`tags` fields for an analyzer diagnostic (T4.4/T4.6). Syntax
// errors get the bare code (no reference entry); `tags` carries the analyzer's LSP numbers
// (1 = Unnecessary -> editors dim the range) and is absent on a pre-tags core (<= 0.5.4).
function gdCodeFields(d: { code: string; tags?: number[] }): Partial<Diagnostic> {
  const out: Partial<Diagnostic> = {};
  if (d.code) {
    out.code = d.code;
    if (d.code !== "GDSCRIPT_SYNTAX") out.codeDescription = { href: GD_WARNING_DOCS };
  }
  if (d.tags?.length) out.tags = d.tags as Diagnostic["tags"];
  return out;
}

// Embedded-GDScript type/parse diagnostics from @gdscript-analyzer/core, mapped back into the .guitkx
// source. Safe to surface: the analyzer's seam design resolves an unknown cross-file symbol (a library
// call like `useState`, a `V.*`/`Hooks.*` reference whose .gd we haven't loaded) to the Unknown seam,
// which NEVER warns — so this adds real diagnostics (INTEGER_DIVISION, TYPE_MISMATCH, syntax errors)
// with no false positives. Diagnostics that land in generated glue (toSource === null) are dropped.
function embeddedDiagnostics(doc: TextDocument): Diagnostic[] {
  if (!embeddedEnabled) return [];
  const src = doc.getText();
  const { text, map } = buildVirtualDoc(src);
  const vUri = doc.uri.replace(/\.guitkx$/, ".__guitkx_virtual.gd");
  analyzer.sync(vUri, text);
  // The markup tier owns everything after the component's return (GUITKX0107 dims the whole
  // region); the analyzer's own UNREACHABLE_CODE over the same lines would double-report (T4.4).
  const deadRegions = unreachableRegions(src);
  const out: Diagnostic[] = [];
  for (const d of analyzer.diagnosticsAt(vUri, text)) {
    let s = map.toSource(d.range.start);
    let e = map.toSource(d.range.end);
    if (s === null || e === null) continue; // a diagnostic in generated glue, not user code
    if (s > e) [s, e] = [e, s];
    if (d.code === "UNREACHABLE_CODE" && deadRegions.some((r) => s >= r.start && s < r.end)) continue;
    out.push({
      severity: d.severity,
      range: { start: offsetToPosition(src, s), end: offsetToPosition(src, e) },
      message: d.message,
      source: "gdscript",
      ...gdCodeFields(d),
    });
  }
  return out;
}

// Surface the compiler's full diagnostic catalog (from the on-save Foo.guitkx.diags.json sidecar) in
// VS Code without a running editor. Only when the sidecar still matches the buffer (source hash).
// v2 sidecars (T0.2) carry char offsets, so entries get PRECISE ranges via positionAt and are deduped
// against the live tier by (code, line) — a live GUITKX0104 on element A no longer suppresses the
// compiler's 0104 on a different line. Position-less entries (off -1, incl. normalized v1 sidecars)
// anchor to the first line and fall back to code-only dedupe (their line carries no information).
function mergeCompilerSidecar(doc: TextDocument, live: Diagnostic[]): Diagnostic[] {
  const sc = readSidecar(uriToProjectPath(doc.uri));
  const text = doc.getText();
  if (!sc) return live;
  if (sc.src_hash !== srcHash(text)) {
    // T3.3 → A6 (0.6.0 field triage): while the buffer diverges from the last compile, entries for
    // codes the live tier ALSO computes are dropped (the live tier owns them). Compiler-only codes
    // used to be re-published per entry with offsets CLAMPED into the edited text — after a few
    // keystrokes they piled up at drifted/EOF positions and never cleared, because a recompile
    // needs the Godot editor. They now collapse into ONE file-level Information note naming the
    // codes; the positioned squiggles return when a recompile refreshes the sidecar.
    const liveSet = new Set(VOCABULARY.live);
    let staleCount = 0;
    const staleCodes: string[] = [];
    for (const d of sc.diagnostics) {
      if (!d.code || liveSet.has(d.code)) continue;
      staleCount++;
      if (!staleCodes.includes(d.code)) staleCodes.push(d.code);
    }
    if (staleCount === 0) return live;
    const firstLineLen = (text.indexOf("\n") + 1 || text.length + 1) - 1;
    return [
      ...live,
      {
        severity: DiagnosticSeverity.Information,
        range: { start: { line: 0, character: 0 }, end: { line: 0, character: Math.max(1, firstLineLen) } },
        message: `${staleCount} compiler diagnostic(s) from the last compile (${staleCodes.join(", ")}) are stale while the buffer is edited -- they re-anchor when the Godot editor next compiles this file`,
        source: "guitkx (compiler, stale)",
      },
    ];
  }
  const liveCodes = new Set<string>();
  const liveCodeLines = new Set<string>();
  for (const d of live) {
    const m = /GUITKX\d+/.exec(d.message);
    if (m) {
      liveCodes.add(m[0]);
      liveCodeLines.add(`${m[0]}@${d.range.start.line}`);
    }
  }
  const firstLineLen = (text.indexOf("\n") + 1 || text.length + 1) - 1;
  const extra: Diagnostic[] = [];
  for (const d of sc.diagnostics) {
    if (!d.code) continue;
    // Sidecar offsets are Unicode CODE POINTS (GDScript String indices); positionAt takes UTF-16.
    const off = d.off >= 0 ? cpToUtf16(text, d.off) : -1;
    const endOff = d.off >= 0 ? cpToUtf16(text, d.off + Math.max(1, d.len)) : -1;
    const positioned = off >= 0 && off <= text.length;
    const range = positioned
      ? { start: doc.positionAt(off), end: doc.positionAt(Math.min(text.length, Math.max(off + 1, endOff))) }
      : { start: { line: 0, character: 0 }, end: { line: 0, character: Math.max(1, firstLineLen) } };
    if (positioned ? liveCodeLines.has(`${d.code}@${range.start.line}`) : liveCodes.has(d.code)) continue;
    extra.push({
      severity: d.severity === 1 ? DiagnosticSeverity.Warning : d.severity === 2 ? DiagnosticSeverity.Hint : DiagnosticSeverity.Error,
      range,
      code: d.code, // the GUITKX#### identity as a real Diagnostic.code (also click-through-able)
      // v2 AND v3 store bare messages -- compose the code prefix (matching the live tier's style);
      // v1 messages already embed the code. `>= 2` (not `=== 2`) so the v3 bump kept the prefix (BH-04).
      message: sc.v >= 2 ? `${d.code}: ${d.message}` : d.message,
      source: "guitkx (compiler)",
    });
  }
  return extra.length ? [...live, ...extra] : live;
}

documents.onDidClose((e) => {
  // keep the on-disk entry: re-scan from disk so the index reflects the saved file, not the closed buffer
  const p = uriToProjectPath(e.document.uri);
  try {
    index.reindex(e.document.uri, readFileSync(p, "utf8"));
  } catch {
    index.evict(e.document.uri);
  }
  // The closed buffer's squiggles are stale the instant it closes (based on its last-edited
  // content, not necessarily what's on disk) -- clear them from the Problems panel instead of
  // leaving them to linger until the file is reopened and re-analyzed.
  connection.sendDiagnostics({ uri: e.document.uri, diagnostics: [] });
});

// --- go-to-definition: <Foo/> -> the component/module-member declaration ---

connection.onDefinition(async (params) => {
  const doc = documents.get(params.textDocument.uri);
  if (!doc) return null;
  const src = doc.getText();
  const offset = doc.offsetAt(params.position);
  if (isGd(params.textDocument.uri)) return isGdAnalysisEnabled() ? gdDefinition(params.textDocument.uri, src, offset) : null;
  // A <Component/> tag, the `component`/member decl name, or its `@class_name` token -> the declaration,
  // from the workspace index. Using bindingUnderCursor (not just componentTagAt) means F12 / ctrl+click
  // works from a usage AND from the declaration itself / the @class_name directive, instead of falling
  // through to the analyzer and surfacing VS Code's "no definition found".
  const name = bindingUnderCursor(params.textDocument.uri, src, offset);
  if (name) {
    const entries = index.lookup(name);
    if (entries.length)
      return entries.map((e) => {
        const targetText = documents.get(e.uri)?.getText() ?? readTextForUri(e.uri);
        return { uri: e.uri, range: { start: offsetToPos(targetText, e.nameStart), end: offsetToPos(targetText, e.nameEnd) } };
      });
  }
  // 0.10.0: click-through on an import specifier or an imported name -> the target .guitkx file (and,
  // for a name, its declaration). Resolves ./ ../ ~/ exactly like the compiler.
  const imp = importAt(src, offset);
  if (imp) {
    const target = resolveSpecifier(imp.spec, uriToProjectPath(params.textDocument.uri), projectPath);
    if (target) {
      const targetUri = pathToFileURL(target).href;
      const tText = documents.get(targetUri)?.getText() ?? readTextForUri(targetUri);
      if (imp.kind === "name" && imp.name) {
        const d = scanDeclarations(tText).find((x) => x.name === imp.name || x.binding === imp.name);
        if (d) return [{ uri: targetUri, range: { start: offsetToPos(tText, d.nameStart), end: offsetToPos(tText, d.nameEnd) } }];
      }
      return [{ uri: targetUri, range: { start: offsetToPos(tText, 0), end: offsetToPos(tText, 0) } }];
    }
  }
  // Otherwise an embedded-GDScript symbol -> resolve via @gdscript-analyzer/core; return cross-file (library)
  // locations (e.g. `useRef` -> core/hooks.gd). Same-file (virtual-doc) hits are skipped for now.
  return forwardDefinition(params.textDocument.uri, src, offset);
});

function forwardDefinition(uri: string, src: string, offset: number): Location[] | null {
  if (!embeddedEnabled) return null;
  const { text, map } = buildVirtualDoc(src);
  const genOffset = map.toGenerated(offset);
  if (genOffset === null) return null;
  const vUri = uri.replace(/\.guitkx$/, ".__guitkx_virtual.gd");
  analyzer.sync(vUri, text);
  const out: Location[] = [];
  // Push a library `.gd` def (its range is in that file's own text). Used both directly and for the
  // chained hook-stub target.
  const pushLibrary = (libUri: string, r: { start: number; end: number }) => {
    const t = analyzer.textOf(libUri) ?? "";
    out.push({ uri: libUri, range: { start: offsetToPosition(t, r.start), end: offsetToPosition(t, r.end) } });
  };
  for (const d of analyzer.definitionsAt(vUri, text, genOffset)) {
    // (1) A cross-file target in a project library `.gd` (e.g. `V.create` -> v.gd) -> a direct Location.
    if (d.uri && d.uri !== vUri) {
      pushLibrary(d.uri, d.range);
      continue;
    }
    // (2) A virtual-doc target that maps back into the .guitkx source -> a Location in the source.
    const s = map.toSource(d.range.start);
    const e = map.toSource(d.range.end);
    if (s !== null && e !== null) {
      out.push({ uri, range: { start: offsetToPosition(src, s), end: offsetToPosition(src, e) } });
      continue;
    }
    // (3) A target in generated glue — most usefully a hook wrapper stub
    // `static func useRef(...): return Hooks.useRef(...)`. Chain ONCE through the `Hooks.<name>`
    // in its body to the real library definition (`core/hooks.gd`).
    const rhs = hookStubRhsOffset(text, d.range.start);
    if (rhs === null) continue;
    for (const cd of analyzer.definitionsAt(vUri, text, rhs)) {
      if (cd.uri && cd.uri !== vUri) pushLibrary(cd.uri, cd.range);
    }
  }
  return out.length ? out : null;
}

// The char offset of `<name>` in a `Hooks.<name>` reference on the same line as `lhsOffset` — the
// forwarding body of a generated hook wrapper stub (`static func <name>(...): return Hooks.<name>(...)`).
// `null` if that line carries no `Hooks.` ref.
function hookStubRhsOffset(vText: string, lhsOffset: number): number | null {
  const lineStart = vText.lastIndexOf("\n", lhsOffset) + 1;
  let lineEnd = vText.indexOf("\n", lhsOffset);
  if (lineEnd === -1) lineEnd = vText.length;
  const m = /\bHooks\.([A-Za-z_][A-Za-z0-9_]*)/.exec(vText.slice(lineStart, lineEnd));
  return m ? lineStart + m.index + "Hooks.".length : null;
}

// Every `.gd` file under `dir` (recursive); a missing/unreadable dir or entry yields nothing but is
// recorded in `err` — the completeness claim needs to know the scan was partial.
function gdFilesUnder(dir: string, out: string[] = [], err?: { failed: boolean }): string[] {
  let entries: string[];
  try {
    entries = readdirSync(dir);
  } catch {
    if (err) err.failed = true;
    return out;
  }
  for (const name of entries) {
    const p = join(dir, name);
    let isDir = false;
    try {
      isDir = statSync(p).isDirectory();
    } catch {
      if (err) err.failed = true;
      continue;
    }
    if (isDir) gdFilesUnder(p, out, err);
    else if (name.endsWith(".gd")) out.push(p);
  }
  return out;
}

// Load the project's `.gd` files into the analyzer (with `res://` paths) so both embedded `.guitkx`
// code AND plain `.gd` editing resolve `class_name`s / `preload`s / autoloads cross-file. Walks the
// whole project (skipping the `.godot` cache + hidden dirs), not just `addons/`. Returns false when
// ANY file or directory could not be read — the workspace-completeness claim (which arms the
// absence-based UNDEFINED_* diagnostics) must never be made over a partial scan.
function loadLibraries(): boolean {
  if (!projectPath) return false;
  const err = { failed: false };
  for (const file of gdFilesUnder(projectPath, [], err)) {
    const resPath = resPathFor(file);
    if (resPath === null) continue; // hidden dirs (res://.godot/** etc.) are intentionally skipped
    try {
      const text = readFileSync(file, "utf8");
      harvestClassName(file, text);
      analyzer.upsertLibrary(pathToFileURL(file).toString(), text, resPath);
    } catch {
      err.failed = true; // unreadable .gd — a name we cannot prove absent
    }
  }
  return !err.failed;
}

// The analyzer may report `res://` URIs (preload / res-path resolution); VS Code needs a real file:// URI.
function resToFileUri(uri: string): string {
  if (uri.startsWith("res://") && projectPath) return pathToFileURL(join(projectPath, uri.slice("res://".length))).toString();
  return uri;
}

function readTextForUri(uri: string): string {
  try {
    return readFileSync(uriToProjectPath(uri), "utf8");
  } catch {
    return "";
  }
}

function textForUri(uri: string): string {
  return documents.get(uri)?.getText() ?? readTextForUri(uri);
}

// The `(params)` signature of a component declaration (read from its file), e.g. "(idx, append)" — or
// "" when it takes none. Shown in hover so a <Tag>'s props read like a function signature.
function componentSignature(e: { uri: string; nameEnd: number }): string {
  const text = textForUri(e.uri);
  let i = e.nameEnd;
  while (i < text.length && /\s/.test(text[i])) i++;
  if (text[i] !== "(") return "";
  const close = findMatching(text, i);
  if (close === -1) return "";
  return text.slice(i, close + 1).replace(/\s+/g, " ");
}

// The component binding under the cursor — a <Foo/> tag, a component/member declaration name, OR its
// `@class_name` override token (so navigation / find-references / rename all work from the declaration
// AND the @class_name directive, not just from a usage).
function bindingUnderCursor(uri: string, src: string, offset: number): string | null {
  const tag = componentTagAt(src, offset);
  if (tag) return tag;
  for (const e of index.entriesFor(uri)) {
    if (e.kind === "hook" || e.kind === "value" || e.kind === "util") continue;
    const onName = offset >= e.nameStart && offset <= e.nameEnd;
    const onOverride = e.classNameStart != null && e.classNameEnd != null && offset >= e.classNameStart && offset <= e.classNameEnd;
    if (onName || onOverride) return e.binding;
  }
  return null;
}

// Renameable when it is an indexed component binding that is NOT a host tag. A component WITH an
// `@class_name` override is renameable too: the rename rewrites the override token, the `component` decl
// name, and every `<Tag>` usage atomically (BUG-4), so it never leaves a usage bound to a stale
// `@class_name` (which previously produced a dangling GUITKX0105 "unknown element").
function isRenameable(name: string): boolean {
  return !findTag(name) && index.has(name);
}

// ════════════════════════════════════════════════════════════════════════════════════════════════
// Plain `.gd` mode — drive real GDScript files directly through @gdscript-analyzer/core. Offsets are
// 1:1 (no virtual doc / source map), and cross-file results are honoured in full (a real project-wide
// rename, not the `.guitkx` refuse-cross-file rule). Reached only when the client sends a `.gd` doc,
// which it does only if the user opts in via `guitkx.enableGdscriptAnalysis`. All project `.gd` are
// loaded at init (loadLibraries), so cross-file navigation / rename resolve.
// ════════════════════════════════════════════════════════════════════════════════════════════════

function isGd(uri: string): boolean {
  return uri.endsWith(".gd");
}

// G-20: server-side gate for plain-.gd analysis. VS Code already gates client-side by not
// registering the `.gd` selector when `guitkx.enableGdscriptAnalysis` is off (extension.ts); VS2022
// has no equivalent per-content-type client gating (its MEF ContentType exports are static), so
// this is the only enforcement it gets. Every `isGd(uri)` branch below checks this FIRST and
// returns empty rather than falling through to the markup-handling path (which assumes `.guitkx`
// syntax and would misbehave on a real `.gd` file).
function isGdAnalysisEnabled(): boolean {
  return gdscriptAnalysisEnabled;
}

// A CHAR offset -> Position in `uri`'s text (the analyzer's loaded copy if present, else disk/open).
function gdPos(uri: string, off: number): { line: number; character: number } {
  return offsetToPosition(analyzer.textOf(uri) ?? textForUri(uri), off);
}

function gdLoc(uri: string, r: { start: number; end: number }): Location {
  return { uri: resToFileUri(uri), range: { start: gdPos(uri, r.start), end: gdPos(uri, r.end) } };
}

function gdDiagnostics(uri: string, src: string): Diagnostic[] {
  analyzer.sync(uri, src);
  return analyzer.diagnosticsAt(uri, src).map((d) => ({
    severity: d.severity,
    range: { start: offsetToPosition(src, d.range.start), end: offsetToPosition(src, d.range.end) },
    message: d.message,
    source: "gdscript",
    ...gdCodeFields(d),
  }));
}

function gdDefinition(uri: string, src: string, offset: number): Location[] {
  analyzer.sync(uri, src);
  return analyzer.definitionsAt(uri, src, offset).flatMap((d) => (d.uri ? [gdLoc(d.uri, d.range)] : []));
}

function gdReferences(uri: string, src: string, offset: number): Location[] {
  analyzer.sync(uri, src);
  return analyzer.referencesAt(uri, src, offset).flatMap((r) => (r.uri ? [gdLoc(r.uri, r.range)] : []));
}

// A project-wide rename: apply EVERY file's edits (the analyzer is correct-or-refuse, so a non-null
// result is safe to apply across files).
function gdRename(uri: string, src: string, offset: number, newName: string): { changes: { [uri: string]: TextEdit[] } } | null {
  if (!/^[A-Za-z_]\w*$/.test(newName)) return null;
  analyzer.sync(uri, src);
  const res = analyzer.renameAt(uri, src, offset, newName);
  if (!("ok" in res)) return null;
  const changes: { [uri: string]: TextEdit[] } = {};
  for (const fe of res.ok) {
    if (!fe.uri) continue;
    changes[resToFileUri(fe.uri)] = fe.edits.map((e) => ({
      range: { start: gdPos(fe.uri!, e.range.start), end: gdPos(fe.uri!, e.range.end) },
      newText: e.newText,
    }));
  }
  return Object.keys(changes).length ? { changes } : null;
}

function gdCodeActions(uri: string, src: string, offset: number): CodeAction[] {
  analyzer.sync(uri, src);
  const out: CodeAction[] = [];
  for (const a of analyzer.codeActionsAt(uri, src, offset)) {
    const changes: { [uri: string]: TextEdit[] } = {};
    for (const fe of a.edits) {
      if (!fe.uri) continue;
      changes[resToFileUri(fe.uri)] = fe.edits.map((e) => ({
        range: { start: gdPos(fe.uri!, e.range.start), end: gdPos(fe.uri!, e.range.end) },
        newText: e.newText,
      }));
    }
    if (Object.keys(changes).length) out.push({ title: a.title, kind: a.kind ?? undefined, edit: { changes } });
  }
  return out;
}

function gdDocumentSymbols(uri: string, src: string): DocumentSymbol[] {
  analyzer.sync(uri, src);
  const conv = (s: AdapterSymbol): DocumentSymbol => ({
    name: s.name,
    detail: s.detail,
    kind: s.kind,
    range: { start: offsetToPosition(src, s.range.start), end: offsetToPosition(src, s.range.end) },
    selectionRange: { start: offsetToPosition(src, s.selectionRange.start), end: offsetToPosition(src, s.selectionRange.end) },
    children: s.children.map(conv),
  });
  return analyzer.documentSymbolsAt(uri, src).map(conv);
}

function gdInlayHints(uri: string, src: string, range: { start: number; end: number }): InlayHint[] {
  analyzer.sync(uri, src);
  return analyzer
    .inlayHintsAt(uri, src)
    .filter((h) => h.offset >= range.start && h.offset <= range.end)
    .map((h) => ({ position: offsetToPosition(src, h.offset), label: h.label, kind: h.kind }));
}

function wordRangeAt(src: string, offset: number): { start: number; end: number } {
  let s = offset;
  let e = offset;
  while (s > 0 && isIdent(src[s - 1])) s--;
  while (e < src.length && isIdent(src[e])) e++;
  return { start: s, end: e };
}

// --- embedded-GDScript references + rename (analyzer-backed, source-mapped, correct-or-refuse) ---

// References to the embedded-GDScript symbol at `offset`. Same-file hits are mapped back from the
// virtual doc into the .guitkx source; a hit in a loaded library `.gd` is returned in that file. The
// analyzer only sees THIS file's virtual doc + libraries, so the set is complete for file-local symbols.
function embeddedReferences(uri: string, src: string, offset: number): Location[] {
  if (!embeddedEnabled) return [];
  const { text, map } = buildVirtualDoc(src);
  const genOffset = map.toGenerated(offset);
  if (genOffset === null) return [];
  const vUri = uri.replace(/\.guitkx$/, ".__guitkx_virtual.gd");
  analyzer.sync(vUri, text);
  const out: Location[] = [];
  const seen = new Set<string>();
  const push = (u: string, t: string, s: number, e: number) => {
    const range = { start: offsetToPosition(t, s), end: offsetToPosition(t, e) };
    const key = `${u}:${range.start.line}:${range.start.character}`;
    if (seen.has(key)) return;
    seen.add(key);
    out.push({ uri: u, range });
  };
  for (const r of analyzer.referencesAt(vUri, text, genOffset)) {
    if (r.uri && r.uri !== vUri) {
      push(r.uri, analyzer.textOf(r.uri) ?? "", r.range.start, r.range.end); // a library `.gd` hit
      continue;
    }
    const s = map.toSource(r.range.start); // a virtual-doc hit -> back to the .guitkx source (drop glue)
    const e = map.toSource(r.range.end);
    if (s !== null && e !== null) push(uri, src, s, e);
  }
  return out;
}

// The source word-range iff the embedded symbol at `offset` is renameable — i.e. its definition is
// LOCAL to this file's embedded code (not a library `.gd`, not generated glue). Library/glue symbols
// are refused (we will not edit core/hooks.gd from a .guitkx, and cross-.guitkx refs aren't loaded).
function embeddedRenameRange(uri: string, src: string, offset: number): { start: number; end: number } | null {
  if (!embeddedEnabled) return null;
  const w = wordRangeAt(src, offset);
  if (w.start === w.end) return null;
  const { text, map } = buildVirtualDoc(src);
  const genOffset = map.toGenerated(offset);
  if (genOffset === null) return null;
  const vUri = uri.replace(/\.guitkx$/, ".__guitkx_virtual.gd");
  analyzer.sync(vUri, text);
  const defs = analyzer.definitionsAt(vUri, text, genOffset);
  const local = defs.length > 0 && defs.every((d) => (!d.uri || d.uri === vUri) && map.toSource(d.range.start) !== null);
  return local ? w : null;
}

// Rename the embedded-GDScript symbol at `offset`. Correct-or-refuse: every edit must map back into
// THIS file's .guitkx source; any edit in a library `.gd` or generated glue refuses the whole rename.
function embeddedRename(uri: string, src: string, offset: number, newName: string): { changes: { [uri: string]: TextEdit[] } } | null {
  if (!embeddedEnabled || !/^[A-Za-z_]\w*$/.test(newName)) return null;
  const { text, map } = buildVirtualDoc(src);
  const genOffset = map.toGenerated(offset);
  if (genOffset === null) return null;
  const vUri = uri.replace(/\.guitkx$/, ".__guitkx_virtual.gd");
  analyzer.sync(vUri, text);
  const res = analyzer.renameAt(vUri, text, genOffset, newName);
  if (!("ok" in res)) return null; // the analyzer refused
  const edits: TextEdit[] = [];
  const seen = new Set<number>();
  for (const fe of res.ok) {
    if (fe.uri !== vUri) return null; // an edit outside this file's virtual doc -> refuse
    for (const e of fe.edits) {
      const s = map.toSource(e.range.start);
      const en = map.toSource(e.range.end);
      if (s === null || en === null) return null; // an edit in generated glue -> refuse
      if (seen.has(s)) continue;
      seen.add(s);
      edits.push({ range: { start: offsetToPosition(src, s), end: offsetToPosition(src, en) }, newText: e.newText });
    }
  }
  return edits.length ? { changes: { [uri]: edits } } : null;
}

// Signature help for an embedded-GDScript call site, via the analyzer over the virtual doc.
function embeddedSignatureHelp(uri: string, src: string, offset: number): SignatureHelp | null {
  if (!embeddedEnabled) return null;
  const { text, map } = buildVirtualDoc(src);
  const genOffset = map.toGenerated(offset);
  if (genOffset === null) return null;
  const vUri = uri.replace(/\.guitkx$/, ".__guitkx_virtual.gd");
  analyzer.sync(vUri, text);
  return analyzer.signatureHelpAt(vUri, text, genOffset);
}

// --- find-references ---

connection.onReferences((params): Location[] => {
  const doc = documents.get(params.textDocument.uri);
  if (!doc) return [];
  const src = doc.getText();
  if (isGd(params.textDocument.uri)) return isGdAnalysisEnabled() ? gdReferences(params.textDocument.uri, src, doc.offsetAt(params.position)) : [];
  const name = bindingUnderCursor(params.textDocument.uri, src, doc.offsetAt(params.position));
  // Not a component tag -> try an embedded-GDScript symbol (analyzer-backed, source-mapped).
  if (!name) return embeddedReferences(params.textDocument.uri, src, doc.offsetAt(params.position));
  const seen = new Set<string>();
  const locs: Location[] = [];
  const push = (uri: string, text: string, s: number, e: number) => {
    const range = { start: offsetToPos(text, s), end: offsetToPos(text, e) };
    const key = `${uri}:${range.start.line}:${range.start.character}`;
    if (seen.has(key)) return;
    seen.add(key);
    locs.push({ uri, range });
  };
  for (const uri of index.uris()) {
    const text = textForUri(uri);
    if (!text) continue;
    for (const r of scanTagRefs(text, name)) push(uri, text, r.start, r.end);
  }
  if (params.context?.includeDeclaration !== false) {
    for (const e of index.lookup(name)) {
      const text = textForUri(e.uri);
      if (text) push(e.uri, text, e.nameStart, e.nameEnd);
    }
  }
  return locs;
});

// --- rename + prepareRename ---

connection.onPrepareRename((params) => {
  const doc = documents.get(params.textDocument.uri);
  if (!doc) return null;
  const src = doc.getText();
  const offset = doc.offsetAt(params.position);
  if (isGd(params.textDocument.uri)) {
    if (!isGdAnalysisEnabled()) return null;
    const gw = wordRangeAt(src, offset);
    return gw.start === gw.end ? null : { range: { start: doc.positionAt(gw.start), end: doc.positionAt(gw.end) }, placeholder: src.slice(gw.start, gw.end) };
  }
  const name = bindingUnderCursor(params.textDocument.uri, src, offset);
  if (!name) {
    // An embedded-GDScript symbol -> renameable iff it's local to this file's embedded code.
    const ew = embeddedRenameRange(params.textDocument.uri, src, offset);
    return ew ? { range: { start: doc.positionAt(ew.start), end: doc.positionAt(ew.end) }, placeholder: src.slice(ew.start, ew.end) } : null;
  }
  if (!isRenameable(name)) return null;
  const w = wordRangeAt(src, offset);
  if (w.start === w.end) return null;
  return { range: { start: doc.positionAt(w.start), end: doc.positionAt(w.end) }, placeholder: name };
});

connection.onRenameRequest((params) => {
  const doc = documents.get(params.textDocument.uri);
  if (!doc) return null;
  const src = doc.getText();
  if (isGd(params.textDocument.uri)) return isGdAnalysisEnabled() ? gdRename(params.textDocument.uri, src, doc.offsetAt(params.position), params.newName) : null;
  const name = bindingUnderCursor(params.textDocument.uri, src, doc.offsetAt(params.position));
  // Not a component tag -> rename an embedded-GDScript symbol (correct-or-refuse, file-local only).
  if (!name) return embeddedRename(params.textDocument.uri, src, doc.offsetAt(params.position), params.newName);
  if (!isRenameable(name)) return null;
  const newName = params.newName;
  if (!/^[A-Za-z_]\w*$/.test(newName)) return null;
  if (findTag(newName) || index.has(newName)) return null; // collide with a host tag or existing component
  const changes: { [uri: string]: TextEdit[] } = {};
  // The declaring file(s) of this binding: import clauses resolving here rewrite their REMOTE
  // halves (E-08 -- `Chip as Badge` becomes `New as Badge`; the local alias and its uses stay),
  // and the declaring file's own export markers (`export default Name`, `export { Name }`)
  // rename in lockstep.
  const declUris = new Set(index.lookup(name).filter((e) => e.binding === name).map((e) => e.uri));
  for (const uri of index.uris()) {
    const text = textForUri(uri);
    if (!text) continue;
    const seen = new Set<number>();
    const edits: TextEdit[] = [];
    const add = (s: number, e: number) => {
      if (seen.has(s)) return;
      seen.add(s);
      edits.push({ range: { start: offsetToPos(text, s), end: offsetToPos(text, e) }, newText: newName });
    };
    for (const r of scanTagRefs(text, name)) add(r.start, r.end);
    const fromFs = uriToProjectPath(uri);
    const specMatches = (spec: string): boolean => {
      const target = resolveSpecifier(spec, fromFs, projectPath);
      return target != null && declUris.has(pathToUri(target));
    };
    for (const r of scanImportClauseRefs(text, name, specMatches)) add(r.start, r.end);
    if (declUris.has(normalizeUri(uri))) for (const r of scanExportMarkerRefs(text, name)) add(r.start, r.end);
    for (const e of index.entriesFor(uri)) {
      if (e.binding !== name) continue;
      // Rewrite the decl-name token only when it IS the binding (no override, or `@class_name X` over
      // `component X`) — so renaming `@class_name X` over `component Y` (X != Y) does not relabel the
      // unrelated decl name Y; the common X/X case still keeps the decl name + override in sync.
      if (e.name === e.binding) add(e.nameStart, e.nameEnd);
      // The `@class_name` override token always renames in lockstep with the binding (BUG-4).
      if (e.classNameStart != null && e.classNameEnd != null) add(e.classNameStart, e.classNameEnd);
    }
    if (edits.length) changes[uri] = edits;
  }
  return { changes };
});

// --- documentSymbol (outline; module members nested) ---

connection.onDocumentSymbol((params): DocumentSymbol[] => {
  const doc = documents.get(params.textDocument.uri);
  if (!doc) return [];
  const src = doc.getText();
  if (isGd(params.textDocument.uri)) return isGdAnalysisEnabled() ? gdDocumentSymbols(params.textDocument.uri, src) : [];
  const top: DocumentSymbol[] = [];
  const modules = new Map<string, DocumentSymbol>();
  for (const d of scanDeclarations(src)) {
    const sym: DocumentSymbol = {
      name: d.name,
      detail: d.export ? "export" : undefined, // outline export badge (0.10.0 imports leg)
      kind: symbolKind(d.kind),
      range: { start: offsetToPos(src, d.declStart), end: offsetToPos(src, d.declEnd) },
      selectionRange: { start: offsetToPos(src, d.nameStart), end: offsetToPos(src, d.nameEnd) },
      children: [],
    };
    if (d.kind === "member" && d.module && modules.has(d.module)) {
      modules.get(d.module)!.children!.push(sym);
    } else {
      top.push(sym);
      if (d.kind === "module") modules.set(d.name, sym);
    }
  }
  return top;
});

function symbolKind(kind: string): SymbolKind {
  switch (kind) {
    case "component":
      return SymbolKind.Class;
    case "hook":
      return SymbolKind.Function;
    case "module":
      return SymbolKind.Namespace;
    default:
      return SymbolKind.Method;
  }
}

// --- semantic tokens (host vs component tag identity, directives, attr names, events) ---

connection.languages.semanticTokens.on((params) => {
  const doc = documents.get(params.textDocument.uri);
  if (!doc) return { data: [] };
  // .gd: analyzer-backed semantic tokens (guitkxSemanticTokens handles .guitkx).
  if (isGd(params.textDocument.uri)) {
    if (!isGdAnalysisEnabled()) return { data: [] };
    analyzer.sync(params.textDocument.uri, doc.getText());
    return { data: analyzer.semanticTokensAt(params.textDocument.uri, doc.getText()) };
  }
  return { data: guitkxSemanticTokens(params.textDocument.uri, doc.getText()) };
});

// .guitkx semantic tokens: the markup tokens (tag identity / @-directive keywords / attr names / events)
// MERGED with the analyzer's embedded-GDScript tokens, mapped back from the virtual doc into the .guitkx
// source — so embedded code highlights the same as a real .gd file (BUG-2). Embedded tokens are
// best-effort: any failure still returns the markup tokens.
function guitkxSemanticTokens(uri: string, src: string): number[] {
  const toks: Tok[] = markupTokens(src, (name) => index.has(name));
  // Kind-accurate coloring of imported binding names (0.11.1 field wave): each import's target
  // resolves from disk and every binding colors by the KIND of the export it binds — components
  // like component tags, hooks/utils as functions, values as variables — overriding the
  // grammar's uniform tint. Unresolvable targets degrade silently to the grammar.
  try {
    const fsPath = uriToProjectPath(uri);
    toks.push(
      ...importBindingTokens(
        src,
        (spec) => {
          const target = resolveSpecifier(spec, fsPath, projectPath);
          return target ? readFileSync(target, "utf8") : null;
        },
        (targetText) => {
          const kindOf = new Map<string, number>();
          for (const d of scanDeclarations(targetText)) {
            const t = importKindTokenOf(d.kind);
            if (t !== undefined && !kindOf.has(d.name)) kindOf.set(d.name, t);
          }
          return kindOf;
        }
      )
    );
  } catch {
    /* import-binding tokens are best-effort — the markup tokens are always returned */
  }
  if (embeddedEnabled) {
    try {
      const { text, map } = buildVirtualDoc(src);
      const vUri = uri.replace(/\.guitkx$/, ".__guitkx_virtual.gd");
      analyzer.sync(vUri, text);
      const lineStart = [0];
      for (let i = 0; i < src.length; i++) if (src[i] === "\n") lineStart.push(i + 1);
      const posOf = (off: number) => {
        let lo = 0;
        let hi = lineStart.length - 1;
        while (lo < hi) {
          const mid = (lo + hi + 1) >> 1;
          if (lineStart[mid] <= off) lo = mid;
          else hi = mid - 1;
        }
        return { line: lo, char: off - lineStart[lo] };
      };
      for (const t of analyzer.semanticTokensRawAt(vUri, text)) {
        const s = map.toSource(t.start);
        const e = map.toSource(t.end);
        if (s === null || e === null || e <= s) continue; // generated glue, or maps to nothing
        const p = posOf(s);
        toks.push({ line: p.line, char: p.char, len: e - s, type: t.type, mods: t.mods });
      }
    } catch {
      /* embedded tokens are best-effort; the markup tokens are always returned */
    }
  }
  return encodeTokens(toks);
}

// --- signature help (opportunistic): on_<signal>={ func(... ) } on a host element ---

connection.onSignatureHelp((params) => {
  const doc = documents.get(params.textDocument.uri);
  if (!doc) return null;
  const src = doc.getText();
  const offset = doc.offsetAt(params.position);
  if (isGd(params.textDocument.uri)) {
    if (!isGdAnalysisEnabled()) return null;
    analyzer.sync(params.textDocument.uri, src);
    return analyzer.signatureHelpAt(params.textDocument.uri, src, offset);
  }
  // Markup signature help (on_<signal>={ func(…) }) first; otherwise an embedded-GDScript call site.
  return signatureHelpAt(src, offset) ?? embeddedSignatureHelp(params.textDocument.uri, src, offset);
});

// --- inlay hints (embedded-GDScript inferred types, mapped back into the .guitkx source) ---

connection.languages.inlayHint.on((params) => {
  const doc = documents.get(params.textDocument.uri);
  if (!doc) return [];
  const src = doc.getText();
  if (isGd(params.textDocument.uri))
    return isGdAnalysisEnabled() ? gdInlayHints(params.textDocument.uri, src, { start: doc.offsetAt(params.range.start), end: doc.offsetAt(params.range.end) }) : [];
  if (!embeddedEnabled) return [];
  const { text, map } = buildVirtualDoc(src);
  const vUri = params.textDocument.uri.replace(/\.guitkx$/, ".__guitkx_virtual.gd");
  analyzer.sync(vUri, text);
  const start = doc.offsetAt(params.range.start);
  const end = doc.offsetAt(params.range.end);
  const out: InlayHint[] = [];
  for (const h of analyzer.inlayHintsAt(vUri, text)) {
    const s = map.toSource(h.offset); // a hint in generated glue (toSource === null) is dropped
    if (s === null || s < start || s > end) continue;
    out.push({ position: offsetToPosition(src, s), label: h.label, kind: h.kind });
  }
  return out;
});

// --- code actions (embedded-GDScript quick-fixes; per-action correct-or-refuse) ---

connection.onCodeAction((params): CodeAction[] => {
  const doc = documents.get(params.textDocument.uri);
  if (!doc) return [];
  const src = doc.getText();
  if (isGd(params.textDocument.uri)) return isGdAnalysisEnabled() ? gdCodeActions(params.textDocument.uri, src, doc.offsetAt(params.range.start)) : [];
  if (!embeddedEnabled) return [];
  const { text, map } = buildVirtualDoc(src);
  const genOffset = map.toGenerated(doc.offsetAt(params.range.start));
  if (genOffset === null) return [];
  const vUri = params.textDocument.uri.replace(/\.guitkx$/, ".__guitkx_virtual.gd");
  analyzer.sync(vUri, text);
  const out: CodeAction[] = [];
  for (const a of analyzer.codeActionsAt(vUri, text, genOffset)) {
    // Keep an action only if EVERY edit maps back into this file's embedded code (correct-or-refuse);
    // an edit in a library `.gd` or generated glue drops just that action, not the whole list.
    const edits: TextEdit[] = [];
    let ok = a.edits.length > 0;
    for (const fe of a.edits) {
      if (fe.uri !== vUri) {
        ok = false;
        break;
      }
      for (const e of fe.edits) {
        const s = map.toSource(e.range.start);
        const en = map.toSource(e.range.end);
        if (s === null || en === null) {
          ok = false;
          break;
        }
        edits.push({ range: { start: offsetToPosition(src, s), end: offsetToPosition(src, en) }, newText: e.newText });
      }
      if (!ok) break;
    }
    if (ok && edits.length) {
      out.push({ title: a.title, kind: a.kind ?? undefined, edit: { changes: { [params.textDocument.uri]: edits } } });
    }
  }
  return out;
});

function signatureHelpAt(src: string, offset: number): any {
  // 1. back-scan for the enclosing call '(' (bounded by the {expr}/tag boundary; '>' does NOT stop us,
  //    so comparison/shift operators inside the header don't break the lookup as enclosingTag would)
  let depth = 0;
  let i = offset - 1;
  let parenOpen = -1;
  while (i >= 0) {
    const c = src[i];
    if (c === ")") depth++;
    else if (c === "(") {
      if (depth === 0) {
        parenOpen = i;
        break;
      }
      depth--;
    } else if (c === "{" || c === "}" || c === ";" || c === "<") break;
    i--;
  }
  if (parenOpen === -1) return null;
  // 2. require a `func` lambda immediately before '(' (a method-ref like on_pressed={_on_click} -> none).
  //    Word-boundary check so `myfunc(` / `_func(` don't spuriously match.
  let j = parenOpen - 1;
  while (j >= 0 && /\s/.test(src[j])) j--;
  if (src.slice(j - 3, j + 1) !== "func" || (j - 4 >= 0 && isIdent(src[j - 4]))) return null;
  j -= 4;
  // 3. require `{` then `=` then the attribute name
  while (j >= 0 && /\s/.test(src[j])) j--;
  if (src[j] !== "{") return null;
  j--;
  while (j >= 0 && /\s/.test(src[j])) j--;
  if (src[j] !== "=") return null;
  j--;
  while (j >= 0 && /\s/.test(src[j])) j--;
  let ne = j + 1;
  while (j >= 0 && /[A-Za-z0-9_.\-]/.test(src[j])) j--;
  const attrName = src.slice(j + 1, ne);
  if (!isEventAttr(attrName)) return null; // event handler (React onClick/onChange/… or native on_<signal>)
  // 4. find the enclosing opening tag's name — back-scan skipping ={...} exprs + quoted values so a
  //    `<`/`>` operator inside an earlier attribute doesn't halt the lookup.
  let t = j;
  let bdepth = 0;
  while (t >= 0) {
    const ch = src[t];
    if (ch === '"' || ch === "'") {
      t--;
      while (t >= 0 && src[t] !== ch) t--;
      t--;
      continue;
    }
    if (ch === "}") {
      bdepth++;
      t--;
      continue;
    }
    if (ch === "{") {
      if (bdepth > 0) bdepth--;
      t--;
      continue;
    }
    if (ch === "<" && bdepth === 0) break;
    t--;
  }
  if (t < 0 || src[t] !== "<") return null;
  const tn = t + 1;
  let te = tn;
  while (te < src.length && /[A-Za-z0-9_]/.test(src[te])) te++;
  const td = findTag(src.slice(tn, te));
  if (!td) return null; // host elements only
  const sigs = classSignals(td.godotClass);
  const signal = resolveSignalName(attrName, (s) => sigs.some((x) => x.name === s)); // React name -> signal
  if (!signal) return null;
  const sig = sigs.find((s) => s.name === signal);
  if (!sig) return null;
  // 5. activeParameter = top-level comma count between '(' and the cursor (depth-aware, string-safe)
  let active = 0;
  let d2 = 0;
  for (let p = parenOpen + 1; p < offset && p < src.length; p++) {
    const ch = src[p];
    if (ch === '"' || ch === "'") {
      p = skipString(src, p) - 1;
      continue;
    }
    if (ch === "(" || ch === "[" || ch === "{") d2++;
    else if (ch === ")" || ch === "]" || ch === "}") d2--;
    else if (ch === "," && d2 === 0) active++;
  }
  const params2 = sig.args.map((a) => ({ label: `${a.name}: ${a.type}` }));
  const label = `${signal}(${params2.map((p) => p.label).join(", ")})`;
  return { signatures: [{ label, parameters: params2 }], activeSignature: 0, activeParameter: Math.min(active, Math.max(0, params2.length - 1)) };
}

// Live structural-markup diagnostics (the compiler emits the full catalog on save; this is the fast
// in-editor tier): duplicate literal `key="…"` among siblings [GUITKX0104] + unknown-element [0105].
// Scoped to the markup windows (the return(...) of each component) so a `<`/`>` in setup GDScript,
// directive conditions, or child {expr} is never misread as a tag.
// BUG-V5/V6: one Hint + Unnecessary diagnostic per component over the unreachable code after its return.
// VS Code renders Unnecessary-tagged ranges FADED (like dead code) — the requested "dim".
function unreachableDiagnostics(doc: TextDocument): Diagnostic[] {
  return unreachableRegions(doc.getText()).map((r) => ({
    severity: DiagnosticSeverity.Hint,
    tags: [DiagnosticTag.Unnecessary],
    range: { start: doc.positionAt(r.start), end: doc.positionAt(r.end) },
    // The code prefix makes the sidecar's compile-time copy dedupe away ((code,line) key -- T3.2/T3.3).
    message: "GUITKX0107: Unreachable code after the component's return — the compiler drops it.",
    source: "guitkx",
  }));
}

// Live declaration validation (declarations.ts), wrapped into LSP Diagnostics. This is the floor the
// LSP was missing: without a valid `component`/`hook`/`module` header there is no markup window, so a
// single typo like `comssponent` used to make the LSP skip ALL analysis and report nothing.
function declarationDiagnostics(doc: TextDocument): Diagnostic[] {
  return declarationDiags(doc.getText()).map((d) => ({
    severity: d.severity === "warning" ? DiagnosticSeverity.Warning : DiagnosticSeverity.Error,
    range: { start: doc.positionAt(d.start), end: doc.positionAt(d.end) },
    message: d.message,
    source: "guitkx",
  }));
}

function markupDiagnostics(doc: TextDocument): Diagnostic[] {
  const src = doc.getText();
  const diags: Diagnostic[] = [];
  const wins = markupWindows(src);
  // T1.5 (G5): markup parse errors (0301/0302/...) and unknown lowercase tags (0105) fire LIVE --
  // they used to be computed and discarded, so `return <s></a>` squiggled nothing until save.
  // T2.5: rules-of-hooks (0013-0016) fire live over every setup span with the same routine the
  // compiler runs (liveMarkup.hookContextDiags mirrors guitkx.gd _validate_hooks).
  // T4.5: PascalCase tags check live against the full component universe (indexed .guitkx
  // bindings + the project's .gd class_names) once the workspace scan has completed.
  const knownComponents = componentUniverseReady && index.ready ? new Set([...index.names(), ...gdClassNames]) : null;
  for (const d of [...windowStructureDiags(src, wins, knownComponents), ...hookContextDiags(src, setupSpans(src))]) {
    diags.push({
      severity: d.severity === "warning" ? DiagnosticSeverity.Warning : DiagnosticSeverity.Error,
      range: { start: doc.positionAt(d.start), end: doc.positionAt(d.end) },
      message: d.message,
      source: "guitkx",
    });
  }
  for (const w of wins) scanWindowDiagnostics(src, doc, w.start, w.end, diags);
  return diags;
}

// Live missing-markup-return check [GUITKX2101]: a component whose closed body has no `return ( ... )`
// used to be SILENT while typing — no markup window means every window-scoped tier skips it, and
// buildVirtualDoc just emits `pass` — so the error only appeared post-save via the compiler sidecar
// (pinned to line 0). Message text mirrors guitkx.gd _split_return so the sidecar copy dedupes away.
function missingReturnDiagnostics(doc: TextDocument): Diagnostic[] {
  return missingReturnComponents(doc.getText()).map((r) => ({
    severity: DiagnosticSeverity.Error,
    range: { start: doc.positionAt(r.start), end: doc.positionAt(r.end) },
    message: "GUITKX2101: component has no `return ( ... )` (only `return null`?)",
    source: "guitkx",
  }));
}

// Phase C: early/conditional markup returns are LEGAL (lowered in place by the compiler, extra
// live markup WINDOWS here -- see markupWindows), so the A4-era live GUITKX2102 is gone. The
// compiler's remaining 2102 (a top-level return that is not `return ( <markup> )`) arrives via
// the sidecar; GUITKX2102 left vocabulary `live` accordingly.

// T3.5: the half-typed/unclosed `return (` -- the compiler's GUITKX0304 -- now shows live too
// (missing-return deliberately skips it, and no markup window exists to carry a parse error).
function unclosedReturnDiagnostics(doc: TextDocument): Diagnostic[] {
  return unclosedReturns(doc.getText()).map((r) => ({
    severity: DiagnosticSeverity.Error,
    range: { start: doc.positionAt(r.start), end: doc.positionAt(r.end) },
    message: "GUITKX0304: unclosed `(` after return",
    source: "guitkx",
  }));
}

// Directive words whose `{ ... }` body is GDSCRIPT under the Phase D grammar (prep statements +
// directive-level `return ( <markup/> )`) -- the scanner must NOT read those braces as markup.
// @match is the odd one out: its body is a CONTAINER of @case/@default directives, so the scanner
// steps inside it and lets the arms handle their own bodies.
const BODY_DIRECTIVES = new Set(["if", "elif", "else", "for", "while", "case", "default"]);

function scanWindowDiagnostics(src: string, doc: TextDocument, start: number, end: number, diags: Diagnostic[]): void {
  const scopes: Array<Set<string>> = [new Set()];
  let i = start;
  while (i < end) {
    // G-01: this window is markup -- `#` in text (e.g. "Score #3") is literal, not a comment; the
    // real comment forms here are `//`/`/* */`/`<!-- -->` (previously unrecognized here, so a tag
    // reference inside one of those could false-flag GUITKX0104/0105/0109).
    const sk = skipNoncodeMarkup(src, i);
    if (sk !== i) {
      i = Math.min(sk, end);
      continue;
    }
    const c = src[i];
    if (c === "@") {
      // Phase D: a directive body is CODE (prep statements + directive-level returns), not markup.
      // Scan ONLY each return's markup span -- splitBody is the same body model the compiler, the
      // formatter, and liveMarkup use -- so GD prep code cannot false-flag GUITKX0300/keys and
      // `return (` / `)` lines cannot be counted as extra roots (the pre-Phase-D live GUITKX0108
      // here did exactly that on every migrated body). The body's SEMANTIC errors (2103 legacy
      // markup, 2104 hooks, per-return 0108/0106) are liveMarkup.walkDirectiveBody's job.
      const w = (src.slice(i + 1, i + 8).match(/^[a-z_]+/) || [""])[0];
      let p = i + 1 + w.length;
      if (w === "match" || BODY_DIRECTIVES.has(w)) {
        while (p < end && /[ \t\r\n]/.test(src[p])) p++;
        if (src[p] === "(") {
          const hc = findMatching(src, p); // header condition -- GDScript, skip whole
          p = hc === -1 || hc >= end ? end : hc + 1;
          while (p < end && /[ \t\r\n]/.test(src[p])) p++;
        }
        if (src[p] === "{") {
          if (w === "match") {
            i = p + 1; // container of @case/@default arms -- step inside
            continue;
          }
          // G-01: the directive/@case/@default BODY is markup -- see findMatchingMarkup's docstring.
          const close = findMatchingMarkup(src, p);
          const bodyEnd = close === -1 || close >= end ? end : close;
          for (const part of splitBody(src.slice(p + 1, bodyEnd)).parts) {
            if (part.t === "ret" && part.markup && part.m_end > part.m_start) {
              scanWindowDiagnostics(src, doc, p + 1 + part.m_start, p + 1 + part.m_end, diags);
            }
          }
          i = bodyEnd + 1;
          continue;
        }
      }
      i = p;
      continue;
    }
    if (c === "(") {
      // a @directive condition — GDScript, skip whole
      const cl = findMatching(src, i);
      i = cl === -1 || cl >= end ? end : cl + 1;
      continue;
    }
    if (c === "{") {
      const cl = findMatching(src, i); // child {expr} — GDScript, skip whole
      i = cl === -1 || cl >= end ? end : cl + 1;
      continue;
    }
    if (c === "}") {
      i++;
      continue;
    }
    if (c === "<" && src[i + 1] === ">") {
      scopes.push(new Set()); // fragment OPEN <> -> enter its own child key-scope (symmetric with </> pop)
      i += 2;
      continue;
    }
    if (c === "<" && src[i + 1] === "/") {
      if (scopes.length > 1) scopes.pop(); // close tag (incl. </>) -> leave child scope
      const gt = src.indexOf(">", i);
      i = gt === -1 ? end : gt + 1;
      continue;
    }
    if (c === "<" && /[ \t\r\n]/.test(src[i + 1] || "")) {
      // BUG-V4: `<` followed by whitespace is a malformed tag name. {expr} and (...) conditions are
      // already skipped above, so at a markup position this is an invalid `< tag`, not a comparison.
      diags.push({
        severity: DiagnosticSeverity.Error,
        range: { start: doc.positionAt(i), end: doc.positionAt(i + 1) },
        message: "GUITKX0300: invalid tag name — `<` must be followed by a tag name, or `<>` for a fragment.",
        source: "guitkx",
      });
      i++;
      continue;
    }
    if (c === "<" && /[A-Za-z_]/.test(src[i + 1] || "")) {
      const tag = readTag(src, i, end);
      // BUG-V3: dedup on a signature so BOTH literal (key="x") and expression (key={ str(i) }) keys
      // are caught — two siblings with the same key expression collide every iteration.
      const keySig = tag.keyLiteral !== null ? "s:" + tag.keyLiteral : tag.keyExpr !== null ? "e:" + tag.keyExpr : null;
      if (keySig !== null) {
        const scope = scopes[scopes.length - 1];
        if (scope.has(keySig)) {
          diags.push({
            severity: DiagnosticSeverity.Error, // T3.2: duplicate keys break reconciliation -- error on both surfaces
            range: { start: doc.positionAt(tag.keyStart), end: doc.positionAt(tag.keyEnd) },
            message: `GUITKX0104: duplicate key '${keySig.slice(2)}' among sibling elements.`,
            source: "guitkx",
          });
        }
        scope.add(keySig);
      }
      // unknown-element did-you-mean: PascalCase tag that is neither a host element nor an indexed
      // component, but is a near-miss of one. Lowercase tags are vocabulary-checked in liveMarkup.ts
      // (T1.5); the PascalCase check stays SUGGESTION-GATED until T4.5 feeds .guitkx declarations
      // into the analyzer -- ungated it would false-flag hand-written .gd component classes, which
      // only the compiler (via the plugin's known_components) can see today.
      if (/^[A-Z]/.test(tag.tagName) && tag.tagName.toLowerCase() !== "fragment" && !findTag(tag.tagName) && !index.has(tag.tagName)) {
        const sugg = closestTag(tag.tagName);
        if (sugg) {
          diags.push({
            severity: DiagnosticSeverity.Error,
            range: { start: doc.positionAt(tag.nameStart), end: doc.positionAt(tag.nameEnd) },
            message: `GUITKX0105: unknown element '${tag.tagName}'. Did you mean '${sugg}'?`,
            source: "guitkx",
          });
        }
      }
      // unknown ATTRIBUTE on a host element — only when the ClassDB dump is loaded (else we have no
      // authoritative property list and would false-flag). Component tags take arbitrary props, so skip.
      const hostTd = findTag(tag.tagName);
      if (hostTd && hasDump()) {
        const valid = validHostAttrs(hostTd.godotClass);
        for (const a of tag.attrs) {
          if (valid.has(a.name)) continue;
          const sugg = closestAttr(a.name, hostTd.godotClass);
          diags.push({
            severity: DiagnosticSeverity.Error,
            range: { start: doc.positionAt(a.start), end: doc.positionAt(a.end) },
            message: `GUITKX0109: unknown attribute '${a.name}' on <${tag.tagName}>` + (sugg ? `. Did you mean '${sugg}'?` : "."),
            source: "guitkx",
          });
        }
      }
      if (!tag.selfClosing) scopes.push(new Set()); // enter child scope
      i = tag.next;
      continue;
    }
    i++;
  }
}

interface TagAttr2 {
  name: string;
  start: number;
  end: number;
}
interface TagInfo2 {
  next: number;
  selfClosing: boolean;
  keyLiteral: string | null;
  keyExpr: string | null;
  keyStart: number;
  keyEnd: number;
  tagName: string;
  nameStart: number;
  nameEnd: number;
  attrs: TagAttr2[];
}

function readTag(src: string, lt: number, end: number): TagInfo2 {
  let i = lt + 1;
  const nameStart = i;
  while (i < end && /[A-Za-z0-9_]/.test(src[i])) i++;
  const nameEnd = i;
  const tagName = src.slice(nameStart, nameEnd);
  let keyLiteral: string | null = null;
  let keyExpr: string | null = null;
  let keyStart = lt;
  let keyEnd = lt;
  const attrs: TagAttr2[] = [];
  while (i < end) {
    while (i < end && /\s/.test(src[i])) i++;
    if (src[i] === "/" && src[i + 1] === ">") return { next: i + 2, selfClosing: true, keyLiteral, keyExpr, keyStart, keyEnd, tagName, nameStart, nameEnd, attrs };
    if (src[i] === ">") return { next: i + 1, selfClosing: false, keyLiteral, keyExpr, keyStart, keyEnd, tagName, nameStart, nameEnd, attrs };
    if (i >= end) break;
    if (src[i] === "{") { // a `{...spread}` attribute — skip it whole (not an unknown attribute)
      const close = findMatching(src, i);
      i = close === -1 ? end : close + 1;
      continue;
    }
    const an = i;
    while (i < end && /[A-Za-z0-9_.\-]/.test(src[i])) i++;
    const name = src.slice(an, i);
    const aNameEnd = i;
    if (name !== "") attrs.push({ name, start: an, end: aNameEnd });
    while (i < end && /\s/.test(src[i])) i++;
    if (src[i] === "=") {
      i++;
      while (i < end && /\s/.test(src[i])) i++;
      if (src[i] === '"' || src[i] === "'") {
        const vs = i;
        const ve = skipString(src, i);
        if (name === "key") {
          keyLiteral = src.slice(vs + 1, ve - 1);
          keyStart = vs;
          keyEnd = ve;
        }
        i = ve;
      } else if (src[i] === "{") {
        const close = findMatching(src, i);
        if (name === "key" && close !== -1) {
          keyExpr = src.slice(i + 1, close).trim(); // BUG-V3: capture the key EXPRESSION for dup detection
          keyStart = i;
          keyEnd = close + 1;
        }
        i = close === -1 ? end : close + 1;
      }
    } else if (an === i) {
      i++;
    }
  }
  return { next: end, selfClosing: false, keyLiteral, keyExpr, keyStart, keyEnd, tagName, nameStart, nameEnd, attrs };
}

// Valid attribute names for a HOST element: the structural attrs (key/ref/style) + every settable
// Control property of its godotClass + its events in BOTH spellings — React canonical (onClick /
// onChange / …) and the native on_<signal> escape hatch — from the bundled ClassDB dump. (events.ts)
function validHostAttrs(godotClass: string): Set<string> {
  const s = new Set<string>();
  for (const a of STRUCTURAL_ATTRS) s.add(a.name);
  for (const p of classProperties(godotClass)) s.add(p.name);
  for (const ev of validEventAttrs(classSignals(godotClass))) s.add(ev);
  return s;
}

// Closest valid attribute (edit-distance <= 2) of a host element, for an unknown-attribute did-you-mean.
function closestAttr(name: string, godotClass: string): string | null {
  let best: string | null = null;
  let bestD = 3;
  for (const cand of validHostAttrs(godotClass)) {
    if (cand === name) return null;
    if (Math.abs(cand.length - name.length) > 2) continue;
    const d = levenshtein(name, cand);
    if (d < bestD) {
      bestD = d;
      best = cand;
    }
  }
  return bestD <= 2 ? best : null;
}

// Closest known tag (host element or indexed component) within edit-distance 2, for did-you-mean.
function closestTag(name: string): string | null {
  let best: string | null = null;
  let bestD = 3;
  const pool = [...HOST_TAGS.map((t) => t.tag), ...index.names()];
  for (const cand of pool) {
    if (cand === name) return null; // exact match => known, no suggestion
    if (Math.abs(cand.length - name.length) > 2) continue;
    const d = levenshtein(name, cand);
    if (d < bestD) {
      bestD = d;
      best = cand;
    }
  }
  return bestD <= 2 ? best : null;
}

function levenshtein(a: string, b: string): number {
  const m = a.length;
  const k = b.length;
  let prev = Array.from({ length: k + 1 }, (_, j) => j);
  let cur = new Array(k + 1).fill(0);
  for (let i = 1; i <= m; i++) {
    cur[0] = i;
    for (let j = 1; j <= k; j++) {
      const cost = a[i - 1] === b[j - 1] ? 0 : 1;
      cur[j] = Math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost);
    }
    [prev, cur] = [cur, prev];
  }
  return prev[k];
}

function structuralDiagnostics(doc: TextDocument): Diagnostic[] {
  const src = doc.getText();
  const diags: Diagnostic[] = [];
  // unbalanced { } at file scope (a crude but useful guard)
  let depth = 0;
  let firstUnmatched = -1;
  for (let i = 0; i < src.length; i++) {
    const c = src[i];
    if (c === '"' || c === "'") {
      // skip a simple string
      const q = c;
      i++;
      while (i < src.length && src[i] !== q) {
        if (src[i] === "\\") i++;
        i++;
      }
      continue;
    }
    if (c === "#") {
      while (i < src.length && src[i] !== "\n") i++;
      continue;
    }
    if (c === "{") {
      if (depth === 0) firstUnmatched = i;
      depth++;
    } else if (c === "}") depth--;
  }
  if (depth > 0 && firstUnmatched >= 0) {
    diags.push({
      severity: DiagnosticSeverity.Warning,
      range: { start: doc.positionAt(firstUnmatched), end: doc.positionAt(firstUnmatched + 1) },
      message: "Unbalanced '{' — this block may be missing a closing '}'.",
      source: "guitkx",
    });
  }
  return diags;
}

documents.listen(connection);
connection.listen();
