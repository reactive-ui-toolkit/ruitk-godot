// file://-URI -> a local filesystem path (used by the workspace index + go-to-definition to read
// unopened files). Formatting is now fully in-process (formatGuitkx.ts) — no Godot binary needed.

export function uriToProjectPath(rootUri: string): string {
  if (!rootUri) return "";
  // Strip scheme + authority separator (TWO slashes), preserving the path's leading slash. Stripping
  // all three broke POSIX, where `file:///tmp/x` -> `/tmp/x` is already absolute. The preserved slash
  // is then dropped again for the drive-letter form only. [audit]
  // Windows: `file:///c:/x` -> `/c:/x` -> `c:/x`   path-gate-allow: URI-conversion doc, not a machine path
  let p = decodeURIComponent(rootUri.replace(/^file:\/\//, ""));
  if (/^\/[A-Za-z]:(\/|$)/.test(p)) p = p.slice(1);
  return p;
}
