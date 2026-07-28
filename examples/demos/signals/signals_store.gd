class_name DemoSignalsStore
extends RefCounted
## Shared module-level signal for the Signals demo. A process-global RuitkSignal can't live in
## .guitkx markup (the component/module grammar has no class-level `static var`), so the store
## stays a tiny plain script; the view (signals.guitkx) reads it via Hooks.useSignal.

static var shared := RuitkSignal.new(0)
