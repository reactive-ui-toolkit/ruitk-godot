extends RefCounted
## Shared context handle for the context-handle demo. createContext() returns an RUIContext object;
## sharing that object (instead of a string key) makes context lookups collision-free. [BUG-V9]
##
## Referenced by preload (NOT a `class_name` global), and self-contained via a preloaded `Hooks`,
## so the demo never depends on global-class-cache registration order during a headless / CI import
## scan -- where a leaf `class_name` whose static initializer references another global at parse time
## can fail to register (only manifested on the CI runner, not local; see demos_test).

static var HANDLE: RUIContext = preload("res://addons/reactive_ui_toolkit/core/hooks.gd").createContext(Color(0.4, 0.7, 1.0))
