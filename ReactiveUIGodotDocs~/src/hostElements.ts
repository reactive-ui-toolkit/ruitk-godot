/**
 * Host element descriptors — the single source of truth for the curated Godot
 * host tags (named 1:1 after their Godot classes) that Reactive UI Toolkit — Godot exposes
 * in `.guitkx` markup. Beyond this curated set, any instantiable Godot Node
 * class is a valid tag at runtime (open vocabulary via ClassDB).
 *
 * The data is injected at build time by `vite.config.ts` from the SAME sources
 * the LSP ships (`guitkx-schema.json` + the ClassDB dump), so the docs never
 * drift from the tooling. This module only declares the injected constants with
 * proper TypeScript types and exposes typed accessors.
 */

// ---------------------------------------------------------------------------
// Descriptor shape
// ---------------------------------------------------------------------------

/** A single property flattened from the Godot ClassDB (own + inherited). */
export interface HostProp {
  /** Godot property name (snake_case), e.g. `disabled`, `text`. */
  name: string
  /** Godot type name, e.g. `String`, `bool`, `int`, `Object`. */
  type: string
  /** Comma-separated enum labels when the property is an enum, e.g. `Left,Center,Right`. */
  enum?: string
  /** True when the property is inherited from a base class rather than declared on the host's own class. */
  inherited: boolean
}

/** A single argument of a Godot signal. */
export interface HostSignalArg {
  name: string
  type: string
}

/** A Godot signal flattened from the ClassDB (own + inherited, `_`-prefixed excluded). */
export interface HostSignal {
  /** Godot signal name (snake_case), e.g. `pressed`, `text_changed`. */
  name: string
  args: HostSignalArg[]
}

/** Full descriptor for one host tag. */
export interface HostElement {
  /** The `.guitkx` tag name — 1:1 the Godot class name, e.g. `Button`, `VBoxContainer`. */
  tag: string
  /** The underlying Godot class, e.g. `Button`, `VBoxContainer`. */
  godotClass: string
  /** The GDScript factory function, e.g. `V.Button`. */
  factory: string
  /** Curated event-prop names supported on this tag — `on` + PascalCase(signal), e.g. `onPressed`, `onValueChanged`. */
  events: string[]
  /** All properties (own first, then inherited) flattened from the ClassDB. */
  props: HostProp[]
  /** All signals flattened from the ClassDB. */
  signals: HostSignal[]
}

/** A markup attribute described by the guitkx schema (structural / common). */
export interface SchemaAttr {
  name: string
  type: string
  description?: string
  detail?: string
}

// ---------------------------------------------------------------------------
// Injected build-time constants (see vite.config.ts `define`)
// ---------------------------------------------------------------------------

declare const __PACKAGE_VERSION__: string
declare const __GODOT_MIN__: string
declare const __HOST_ELEMENTS__: Record<string, HostElement>
declare const __HOST_TAGS__: string[]
declare const __STRUCTURAL_ATTRS__: SchemaAttr[]
declare const __COMMON_ATTRS__: SchemaAttr[]
declare const __CONTROL_FLOW__: SchemaAttr[]
declare const __PREAMBLE_DIRECTIVES__: SchemaAttr[]

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/** The addon version, e.g. "0.2.2" (from addons/reactive_ui/plugin.cfg). */
export const PACKAGE_VERSION: string = __PACKAGE_VERSION__

/** Minimum supported Godot minor version, e.g. "4.2". */
export const GODOT_MIN: string = __GODOT_MIN__

/** Ordered host tags (nav order = schema order). */
export const HOST_TAGS: readonly string[] = __HOST_TAGS__

/** Map from host tag to its full descriptor. */
export const HOST_ELEMENTS: Readonly<Record<string, HostElement>> = __HOST_ELEMENTS__

/** Structural attributes available on every host tag (key, ref, style, …). */
export const STRUCTURAL_ATTRS: readonly SchemaAttr[] = __STRUCTURAL_ATTRS__

/** Common Control attributes surfaced on every host tag (name, visible, …). */
export const COMMON_ATTRS: readonly SchemaAttr[] = __COMMON_ATTRS__

/** Control-flow directives available in markup (@if, @for, …). */
export const CONTROL_FLOW: readonly SchemaAttr[] = __CONTROL_FLOW__

/** Preamble directives available at the top of a `.guitkx` file (@class_name, …). */
export const PREAMBLE_DIRECTIVES: readonly SchemaAttr[] = __PREAMBLE_DIRECTIVES__

/** Look up a host element descriptor by tag. Returns undefined for unknown tags. */
export const getHostElement = (tag: string): HostElement | undefined => HOST_ELEMENTS[tag]
