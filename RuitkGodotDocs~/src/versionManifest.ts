/**
 * Version manifest — single source of truth for Godot version awareness
 * in the documentation website.
 *
 * When adding a new Godot version, add an entry to SUPPORTED_VERSIONS and
 * populate the feature maps below for any non-floor additions.
 *
 * Floor version = the minimum Godot version the library supports. Features
 * at or below the floor have no entry here (they are always available).
 */

// ---------------------------------------------------------------------------
// Version registry
// ---------------------------------------------------------------------------

export interface VersionInfo {
  /** Internal version string, e.g. "4.2". */
  version: string
  /** Human-readable label shown in the UI, e.g. "4.2". */
  label: string
}

/**
 * Ordered list of Godot versions the library has explicit support for.
 * The first entry is the floor version (minimum supported).
 */
export const SUPPORTED_VERSIONS: VersionInfo[] = [
  // Floor = 4.4 (evidence-based, 2026-07): the compiler core uses ProjectSettings.
  // get_global_class_list (4.3+), and the editor addon's bundled analyzer GDExtension has
  // compatibility_minimum = "4.4". Both plugins gate on MIN_GODOT = "4.4". Verified on 4.7.
  { version: '4.4', label: '4.4' },
  { version: '4.5', label: '4.5' },
  { version: '4.6', label: '4.6' },
  { version: '4.7', label: '4.7' },
]

export const FLOOR_VERSION = SUPPORTED_VERSIONS[0]

/** Latest version in the list — used as default when "All versions" is selected. */
export const LATEST_VERSION = SUPPORTED_VERSIONS[SUPPORTED_VERSIONS.length - 1]

// ---------------------------------------------------------------------------
// Feature version tags
// ---------------------------------------------------------------------------

export interface FeatureVersion {
  /** The version where this feature was introduced (e.g. "4.3"). */
  sinceGodot: string
  /** The version where this feature was deprecated (optional). */
  deprecatedIn?: string
  /** The version where this feature was removed (optional). */
  removedIn?: string
}

/**
 * Host elements introduced after the floor version.
 * If an element is NOT listed here, it is assumed to be available since floor.
 */
export const ELEMENT_VERSIONS: Record<string, FeatureVersion> = {
  // Elements above the 4.4 floor. (FoldableContainer is is_class()/string-guarded in the
  // runtime, so referencing it below 4.5 degrades gracefully instead of crashing.)
  FoldableContainer: { sinceGodot: '4.5' },
}

/**
 * Style keys introduced after the floor version.
 */
export const STYLE_PROPERTY_VERSIONS: Record<string, FeatureVersion> = {
  // All documented style keys are available since the floor.
}

/**
 * Doc pages introduced after the floor version.
 * Keys are page canonicalId values from docs.tsx / pages.tsx.
 */
export const PAGE_VERSIONS: Record<string, FeatureVersion> = {
  // When a new page documents a feature introduced in a newer Godot version:
  // 'some-page': { sinceGodot: '4.5' },
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Compare two version strings numerically (e.g. "4.3" > "4.2"). */
export function compareVersions(a: string, b: string): number {
  const pa = a.split('.').map(Number)
  const pb = b.split('.').map(Number)
  for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
    const diff = (pa[i] ?? 0) - (pb[i] ?? 0)
    if (diff !== 0) return diff
  }
  return 0
}

/** Check if a feature is available for the given selected version. */
export function isAvailableIn(feature: FeatureVersion | undefined, selectedVersion: string): boolean {
  // No version info → floor feature → always available
  if (!feature) return true
  if (compareVersions(feature.sinceGodot, selectedVersion) > 0) return false
  if (feature.removedIn && compareVersions(feature.removedIn, selectedVersion) <= 0) return false
  return true
}

/** Get a display label like "4.3+" for a feature version. Returns undefined for floor features. */
export function getVersionBadge(feature: FeatureVersion | undefined): string | undefined {
  if (!feature) return undefined
  const info = SUPPORTED_VERSIONS.find((v) => v.version === feature.sinceGodot)
  return info ? `${info.label}+` : `${feature.sinceGodot}+`
}

/**
 * Build version-aware search keywords for the Styling page.
 *
 * Godot styling is a flat theme/StyleBox surface with no version-gated keys at
 * the moment, so there are no extra version-specific terms to inject yet. This
 * hook stays in place so the Godot styling prose port (Stage 2) can start
 * returning version-scoped terms without touching the search plumbing.
 */
export function getStyleSearchTerms(_selectedVersion: string): string {
  return ''
}
