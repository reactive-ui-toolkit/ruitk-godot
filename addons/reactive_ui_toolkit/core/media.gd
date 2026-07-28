class_name RUIMedia
extends RefCounted
## Fire-and-forget audio for the `useSfx` hook — the Godot analog of ReactiveUIToolKit's
## MediaHost.SfxSource. Godot's AudioStreamPlayer is a scene node, so persistent audio/video is
## just a host element (V.audio / V.video); only one-shot SFX needs a managed, self-freeing
## player. (No pool: one-shots are infrequent and a self-freeing player is simpler and leak-free.)

## Play `stream` once on a transient AudioStreamPlayer parented to the scene root. The player frees
## itself when the clip finishes. `bus` falls back to "Master" if it doesn't exist; `volume_db` and
## `pitch_scale` shape the one-shot. No-op (safe) when there is no SceneTree or stream.
static func play_one_shot(stream: AudioStream, bus := "Master", volume_db := 0.0, pitch_scale := 1.0) -> void:
	if stream == null:
		return
	var loop := Engine.get_main_loop()
	if not (loop is SceneTree):
		return
	var tree := loop as SceneTree
	if tree.root == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.bus = bus if AudioServer.get_bus_index(bus) >= 0 else "Master"
	p.volume_db = volume_db
	p.pitch_scale = pitch_scale
	p.autoplay = false
	tree.root.add_child(p)
	p.finished.connect(p.queue_free)
	p.play()
	# Backstop: AudioStreamPlayer.finished only fires for non-looping playback. If the stream loops
	# (or never ends), free the transient player after one stream-length so a "one-shot" can't play
	# forever and leak the node. [audit]
	var dur := stream.get_length()
	if dur > 0.0:
		tree.create_timer(dur + 0.1).timeout.connect(func():
			if is_instance_valid(p):
				p.queue_free())
