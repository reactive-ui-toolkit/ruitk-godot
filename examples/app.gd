extends Control
## Entry point for the demo gallery (examples/main.tscn → this script). Mounts the
## reactive `Demos.gallery` under this full-rect Control. Press Play to explore.
##
## NOTE: this and everything in examples/ is NOT part of the shipped library — the addon
## is entirely self-contained in addons/reactive_ui_toolkit/. Copy that folder into a project and
## the V / Hooks / ReactiveRoot class_names are available; the demos do not come along.

var _app: ReactiveRoot

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_app = ReactiveRoot.create(self, V.fc(DemoGallery.render))

func _exit_tree() -> void:
	if _app != null:
		_app.unmount()
