// Shared event <-> Godot-signal vocabulary for guitkx markup intelligence. This is the single
// source of truth the LSP uses so completion, hover, signature help, validation and semantic tokens
// all speak the SAME canonical event names the RUNTIME actually binds. It mirrors
// addons/reactive_ui_toolkit/core/host_config.gd (_resolve_signal / _is_event / camel<->snake) — keep the
// two in lockstep.
//
// NAMING IS 1:1 LOYAL TO GODOT (0.9.0, MIGRATION-0.9.md): the event name is the exact signal name
// with an `on` marker. Two spellings are accepted everywhere:
//   • on<Pascal> (CANONICAL): on + PascalCase(signal) -> the snake_case signal. onPressed ->
//     pressed, onValueChanged -> value_changed, onGuiInput -> gui_input. Reaches ANY signal.
//   • Native escape hatch: on_<signal> binds verbatim to "<signal>" (e.g. on_gui_input).
// The pre-0.9 React aliases (onClick, polymorphic onChange, …) were REMOVED — RENAMED_EVENTS_090
// exists only to power precise "renamed" diagnostics/hints.

export interface SignalInfo {
  name: string;
  args: { name: string; type: string }[];
}

// Pre-0.9 React alias -> what to write instead. NOT a binding table (the aliases do NOT resolve);
// consulted only for rename hints. Mirrors host_config.gd's _RENAMED_EVENTS_090.
export const RENAMED_EVENTS_090: Record<string, string> = {
  onClick: "onPressed",
  onChange: "the control's real signal (onToggled / onItemSelected / onValueChanged / onTextChanged / onTabChanged)",
  onInput: "onTextChanged",
  onSubmit: "onTextSubmitted",
  onFocus: "onFocusEntered",
  onBlur: "onFocusExited",
  onPointerDown: "onButtonDown",
  onPointerUp: "onButtonUp",
  onPointerEnter: "onMouseEntered",
  onPointerLeave: "onMouseExited",
  onResize: "onResized",
};

const camelToSnake = (s: string): string =>
  s.replace(/([A-Z])/g, (_m, c: string, i: number) => (i ? "_" : "") + c.toLowerCase());

const snakeToPascal = (s: string): string =>
  s.replace(/(^|_)([a-z0-9])/g, (_m, _sep, c: string) => c.toUpperCase());

/** Is this attribute name an event handler (either convention)? Mirrors host_config._is_event. */
export function isEventAttr(name: string): boolean {
  if (name.startsWith("on_")) return true;
  return name.length > 2 && name.startsWith("on") && name[2] >= "A" && name[2] <= "Z";
}

/** The canonical loyal name for a signal (onValueChanged for "value_changed"). */
export function reactNameForSignal(sig: string): string {
  return "on" + snakeToPascal(sig);
}

/** Resolve an event attr NAME to the underlying Godot signal. Mirrors host_config._resolve_signal
 *  (0.9.0): on_<signal> verbatim; on<Pascal> lowers to snake_case. Returns undefined when the name
 *  is not an event attr at all. The `_has` membership test is unused since the polymorphic aliases
 *  were removed, but stays in the signature so callers didn't have to change. */
export function resolveSignalName(name: string, _has: (sig: string) => boolean): string | undefined {
  if (name.startsWith("on_")) return name.slice(3);
  if (isEventAttr(name)) return camelToSnake(name.slice(2));
  return undefined;
}

export interface EventCompletion {
  label: string;
  signal: string;
  detail: string;
}

const signalDetail = (s: SignalInfo | undefined, sigName: string): string =>
  s ? `signal ${s.name}(${s.args.map((a) => `${a.name}: ${a.type}`).join(", ")})` : `signal ${sigName}`;

/** The event completions to offer for a host class, given its (base-flattened) signals: a canonical
 *  on<Pascal> for EVERY non-private signal. Private `_`-prefixed signals are skipped (internal).
 *  Each item carries the resolved signal + its signature for detail/docs. */
export function eventCompletionsFor(signals: SignalInfo[]): EventCompletion[] {
  const out: EventCompletion[] = [];
  for (const s of signals) {
    if (s.name.startsWith("_")) continue;
    out.push({ label: reactNameForSignal(s.name), signal: s.name, detail: signalDetail(s, s.name) });
  }
  return out;
}

/** All valid event attr names for a host class (canonical on<Pascal> + the native on_<signal>
 *  escape hatch), for the unknown-attribute did-you-mean validation. */
export function validEventAttrs(signals: SignalInfo[]): string[] {
  const out = eventCompletionsFor(signals).map((c) => c.label);
  for (const s of signals) if (!s.name.startsWith("_")) out.push("on_" + s.name);
  return out;
}
