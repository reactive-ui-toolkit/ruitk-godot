class_name RUIComponentState
extends RefCounted
## Per-function-component hook & effect storage. SHARED across a fiber's alternates:
## the reconciler copies THIS REFERENCE when cloning a fiber (never deep-copies it),
## so hook state survives the current<->WIP double-buffer swap. `fiber` is re-pointed
## to the committed fiber after each commit so the state setter always schedules work
## on the live fiber. Mirrors ReactiveUIToolKit's FunctionComponentState.

var fiber: RUIFiber = null              ## back-pointer, re-pointed at commit
var hooks: Array = []                   ## positional hook slots (Dictionaries)
var hook_index: int = 0                 ## cursor, reset to 0 each render
var effects: Array = []                 ## passive effects: {factory, deps, last_deps, cleanup}
var effect_index: int = 0
var layout_effects: Array = []          ## layout effects: same shape
var layout_index: int = 0
var context_deps: Array = []            ## [{key, value}] recorded this render (out-of-band)
var on_state_updated: Callable          ## () -> reconciler.schedule_update_on_fiber(fiber, null)
var is_rendering := false
var last_output: Array = []             ## cached render output (vnodes) — reused on bailout

# --- dev diagnostics (Phase 7.0; populated only when RUIConfig.enable_hook_validation) ---
var hook_log: Array = []                ## ordered hook kinds recorded THIS render (transient)
var hook_signatures: Array = []         ## primed hook-kind order from the first render
var hook_order_primed := false
var diag_warned: Dictionary = {}        ## dedup set so each strict warning fires once per component
