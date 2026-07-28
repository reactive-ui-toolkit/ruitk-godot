extends Control
## Faithful port of the Unity ReactiveUIToolKit `DoomGame` sample's
## `DoomGameRuntimeBootstrap.cs` -- mounts the Doom demo as its own standalone scene
## (not embedded in the gallery, per plan §1.8: it needs full-bleed rendering and
## exclusive mouse capture). Mirrors examples/app.gd's own
## RuitkRoot.create()/.unmount() mount pattern.
##
## Phase 2 (plans/DOOM_GAME_GUITKX_PORT_PLAN.md): also owns raw input capture and
## `Input.mouse_mode` (plan §1.5) -- `.guitkx` components/hooks are plain functions,
## they can't override Godot's input virtual methods, so this real Node script is
## the only place that can see keyboard/mouse events at all. Writes into
## `DoomInputState.shared`; `doom_game_screen.hooks.guitkx`'s tick loop reads and
## consumes it once per physics frame.
##
## Two Unity-specific workarounds the original needed disappear entirely here
## (plan §1.5): Godot delivers real relative motion via `InputEventMouseMotion`
## even while `Input.mouse_mode == MOUSE_MODE_CAPTURED` (no raw-delta-via-a-
## separate-input-system hack needed), and `MOUSE_MODE_CAPTURED` both locks and
## hides the OS cursor natively (no blank-cursor-texture hack needed).

var _app: RuitkRoot

# Optional perf overlay, toggled with F3 (hidden by default). A convenience for
# diagnosing which stages spike: it splits the CPU frame into sim (GameLogic.tick)
# vs reconcile+render and reports node/draw-call/object counts.
var _perf_label: Label
var _perf_on := false
var _perf_timer := 0.0

# Simple FPS counter, toggled with Ctrl+R, pinned to the top-right corner.
var _fps_label: Label
var _fps_on := false

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# Default mouse_filter is STOP -- this full-screen Control would otherwise
	# swallow every mouse motion/click as its OWN GUI input before it ever
	# becomes "unhandled" input, so _unhandled_input below would never fire.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_app = RuitkRoot.create(self, V.fc(DoomGame.render))
	# Start at the menu with the cursor free. DoomGame captures the cursor when it
	# switches to the game screen (its screen-change effect) and releases it again
	# on the menu / death / victory overlays.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_perf_overlay()

func _build_perf_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 128
	add_child(layer)
	_perf_label = Label.new()
	_perf_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4))
	_perf_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_perf_label.add_theme_constant_override("outline_size", 4)
	_perf_label.add_theme_font_size_override("font_size", 15)
	_perf_label.position = Vector2(8, 8)
	_perf_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_perf_label.visible = false
	layer.add_child(_perf_label)

	# Standalone FPS counter (Ctrl+R), top-right corner.
	_fps_label = Label.new()
	_fps_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.4))
	_fps_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_fps_label.add_theme_constant_override("outline_size", 4)
	_fps_label.add_theme_font_size_override("font_size", 16)
	_fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fps_label.visible = false
	layer.add_child(_fps_label)

func _process(delta: float) -> void:
	if _perf_label == null:
		return
	_perf_timer += delta
	if _perf_timer < 0.25:
		return
	_perf_timer = 0.0
	if _fps_on and _fps_label != null:
		_fps_label.text = "FPS %d" % Engine.get_frames_per_second()
		# Pin to the top-right corner (recomputed in case the window resized).
		_fps_label.position = Vector2(get_viewport_rect().size.x - 96.0, 8.0)
	if not _perf_on:
		return
	var fps := Engine.get_frames_per_second()
	var proc_ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var draws := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var objs := int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	var nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var frame_ms := 1000.0 / maxf(1.0, float(fps))
	var tick_ms := GameLogic.last_tick_us / 1000.0
	var reconcile_ms := maxf(0.0, proc_ms - tick_ms)
	var bound := "CPU-bound" if proc_ms >= frame_ms * 0.6 else "RENDER-bound"
	var renderer := "BSP" if GameLogic.last_cast_bsp else "ray-walker"
	_perf_label.text = "FPS %d   frame %.1f ms   [%s]   renderer: %s\nsim(tick) %.1f ms   reconcile+render ~%.1f ms\ndraw calls %d   objects %d   nodes %d" % [
		fps, frame_ms, bound, renderer, tick_ms, reconcile_ms, draws, objs, nodes]

func _exit_tree() -> void:
	if _app != null:
		_app.unmount()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _unhandled_input(event: InputEvent) -> void:
	var s := DoomInputState.shared
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		s.pending_yaw += motion.relative.x * DoomTypes.C.MOUSE_YAW_SENS
		# Godot's InputEventMouseMotion.relative.y is positive DOWNWARD (screen
		# coords, Y-down); Unity's Mouse.delta.y is positive UPWARD. The original
		# accumulates `pendingPitch -= d.y`, so to reproduce the same look-feel
		# under the flipped axis we accumulate `+= relative.y` (a straight port of
		# `-= relative.y` would invert the vertical axis -- that was the bug).
		s.pending_pitch += motion.relative.y
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			# Only capture/shoot from the game screen -- in the menu or on a death/
			# victory overlay a click belongs to the buttons (allow_capture gates it).
			if s.allow_capture:
				s.attack = true
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		else:
			s.attack = false
		return

	if event is InputEventKey:
		var key := event as InputEventKey
		if key.echo:
			return # ignore OS key-repeat, only care about the true press/release edge
		match key.keycode:
			KEY_W, KEY_UP:
				s.forward = key.pressed
			KEY_S, KEY_DOWN:
				s.back = key.pressed
			KEY_A, KEY_LEFT:
				s.strafe_left = key.pressed
			KEY_D, KEY_RIGHT:
				s.strafe_right = key.pressed
			KEY_Q:
				s.turn_left = key.pressed
			KEY_E:
				if key.pressed:
					s.pending_use = true
			KEY_SHIFT:
				s.run = key.pressed
			KEY_SPACE:
				s.jump = key.pressed
			KEY_C:
				s.crouch = key.pressed
			KEY_1:
				if key.pressed:
					s.pending_weapon_switch = 1
			KEY_2:
				if key.pressed:
					s.pending_weapon_switch = 2
			KEY_3:
				if key.pressed:
					s.pending_weapon_switch = 3
			KEY_4:
				if key.pressed:
					s.pending_weapon_switch = 4
			KEY_5:
				if key.pressed:
					s.pending_weapon_switch = 5
			KEY_6:
				if key.pressed:
					s.pending_weapon_switch = 6
			KEY_7:
				if key.pressed:
					s.pending_weapon_switch = 7
			KEY_ESCAPE:
				if key.pressed:
					Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			KEY_R:
				# Ctrl+R toggles the simple top-right FPS counter (plain R is unbound).
				if key.pressed and key.ctrl_pressed:
					_fps_on = not _fps_on
					if _fps_label != null:
						_fps_label.visible = _fps_on
			KEY_F3:
				if key.pressed:
					_perf_on = not _perf_on
					if _perf_label != null:
						_perf_label.visible = _perf_on

## Clear all held keys when the game window loses OS focus -- otherwise a key
## released while focus was elsewhere stays "down" forever. Matches the
## original's FocusOutEvent handler (there, element-focus; here, window focus,
## since input capture happens at the SceneTree level, not element level).
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		var s := DoomInputState.shared
		s.forward = false
		s.back = false
		s.strafe_left = false
		s.strafe_right = false
		s.turn_left = false
		s.run = false
		s.jump = false
		s.crouch = false
		s.attack = false
