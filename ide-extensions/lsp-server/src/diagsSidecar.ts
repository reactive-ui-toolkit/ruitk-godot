// Reads the compiler's diagnostics sidecar (Foo.guitkx.diags.json, written by guitkx_codegen.gd) so
// the LSP can surface the compiler's FULL diagnostic catalog in VS Code without a running editor.
// Gated by a source hash: if the open buffer no longer matches the last-compiled source, the sidecar
// is stale and suppressed (it reappears on the next save+compile). srcHash MUST stay identical to
// RuitkGuitkxCodegen.src_hash (FNV-1a over code points).
//
// Schema v2 (T0.2): { v:2, src_hash, diagnostics:[{ code, severity:int (0 err/1 warn/2 hint),
// message (no code prefix), off, len }] } — `off`/`len` are character offsets into the compiled
// source (off -1 = whole file). v1 sidecars ({ src_hash, diagnostics:[{ code, severity:"error"|
// "warning", message }] }, no positions) are normalized on read so pre-T0.2 sidecars keep working
// for one release.

import { readFileSync } from "fs";

export interface SidecarDiag {
  code: string;
  severity: number; // 0 = error, 1 = warning, 2 = hint (compiler-domain, RuitkGuitkxDiag)
  message: string;
  off: number; // char offset into the compiled source; -1 = whole file
  len: number;
}
export interface Sidecar {
  v: number; // 1 (normalized legacy) | 2
  src_hash: number;
  diagnostics: SidecarDiag[];
}

export function srcHash(s: string): number {
  let h = 2166136261;
  // iterate by CODE POINT (for…of) to mirror Godot's unicode_at over String.length() code points —
  // identical to charCodeAt for BMP, but correct for astral-plane chars too.
  for (const ch of s) {
    h = (h ^ ch.codePointAt(0)!) >>> 0;
    h = Math.imul(h, 16777619) >>> 0;
  }
  return h;
}

export function readSidecar(guitkxFsPath: string): Sidecar | null {
  try {
    const j = JSON.parse(readFileSync(guitkxFsPath + ".diags.json", "utf8"));
    if (typeof j.src_hash !== "number" || !Array.isArray(j.diagnostics)) return null;
    // v2..v4 share the structured-diagnostic shape (numeric severity, off/len positions); v3/v4 only
    // ADD fields the LSP ignores here (exports/export_hash/imports/default — the compiler's
    // staleness cache + the ES-modules default-export mark).
    if (j.v === 2 || j.v === 3 || j.v === 4) {
      const diagnostics: SidecarDiag[] = [];
      for (const d of j.diagnostics) {
        if (typeof d.code !== "string" || typeof d.message !== "string") continue;
        diagnostics.push({
          code: d.code,
          severity: typeof d.severity === "number" ? d.severity : 0,
          message: d.message,
          off: typeof d.off === "number" ? d.off : -1,
          len: typeof d.len === "number" ? Math.max(0, d.len) : 0,
        });
      }
      return { v: j.v, src_hash: j.src_hash, diagnostics };
    }
    // v1 fallback: severity was "error"/"warning" and `message` embedded the code prefix; no positions.
    const diagnostics: SidecarDiag[] = [];
    for (const d of j.diagnostics) {
      if (typeof d.code !== "string" || typeof d.message !== "string") continue;
      diagnostics.push({ code: d.code, severity: d.severity === "warning" ? 1 : 0, message: d.message, off: -1, len: 0 });
    }
    return { v: 1, src_hash: j.src_hash, diagnostics };
  } catch {
    /* missing / unreadable */
  }
  return null;
}
