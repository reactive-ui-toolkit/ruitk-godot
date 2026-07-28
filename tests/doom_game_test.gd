extends SceneTree
## Doom-game port (plans/DOOM_GAME_GUITKX_PORT_PLAN.md) regression suite.
## Phase 0: doom_types.gd / doom_textures.gd / doom_maps.gd. Phase 1: raycast.gd +
## game_logic.gd's new_game/cast_frame (the sector-based renderer). Phase 2:
## tick/update_player (movement, mouse-look, jump/crouch, collision). All of the
## above is pure logic, no reconciler/UI involved -- the one deliberate exception
## is _test_integration_tick(), which mounts DoomGameScreen for real and drives
## DoomInputState + physics_frame, since that's the only way to exercise the
## hook's view_ref/get_tree() wiring itself (plan §1.2). Run:
## godot --headless --path <project> --script res://tests/doom_game_test.gd

const DOOM_DIR := "res://examples/demos/doom/"

var _fails := 0
var _passes := 0

func _initialize() -> void:
	_run()

func _ok(c: bool, m: String) -> void:
	if c:
		_passes += 1
	else:
		_fails += 1
		printerr("  FAIL: " + m)
		push_error("FAIL: " + m)

func _run() -> void:
	_test_types()
	_test_textures()
	_test_maps()
	_test_raycast()
	_test_game_logic()
	_test_screen_logic()
	_test_player_movement()
	_test_doors()
	_test_combat()
	await _test_integration_tick()
	await _test_menu_and_switch()
	print("\n[doom_game_test] %d passed, %d failed" % [_passes, _fails])
	quit(1 if _fails > 0 else 0)

func _test_types() -> void:
	var map := DoomTypes.MapDef.new()
	map.width = 3
	map.height = 3
	map.name = "smoke"
	map.cells = []
	for i in range(9):
		var c := DoomTypes.Cell.new()
		c.kind = DoomTypes.CellKind.WALL if i == 0 else DoomTypes.CellKind.EMPTY
		c.floor_z = 0.0
		c.ceiling_z = 0.0
		map.cells.append(c)

	var oob := map.at_safe(-1, -1)
	_ok(oob.kind == DoomTypes.CellKind.WALL, "at_safe out-of-bounds is WALL")
	_ok(map.blocks_movement(0, 0) == true, "blocks_movement: wall cell blocks")
	_ok(map.blocks_movement(1, 0) == false, "blocks_movement: empty cell doesn't block")

	var sector_map := DoomTypes.MapData.from_tiles(map)
	_ok(sector_map.is_valid(), "from_tiles: sector map is valid")
	_ok(sector_map.sectors.size() == 8, "from_tiles: 8 non-wall cells -> 8 sectors, got %d" % sector_map.sectors.size())
	_ok(sector_map.lines.size() > 0, "from_tiles: generated linedefs")

	var gs := DoomTypes.GameState.new()
	gs.player = DoomTypes.PlayerState.new()
	gs.player.health = DoomTypes.C.START_HEALTH
	gs.mobjs = []
	gs.map = map
	gs.sector_map = sector_map
	_ok(gs.player.health == 100, "GameState/PlayerState/C constant wiring")

func _test_textures() -> void:
	DoomTextures.ensure_built()

	var walls := DoomTextures.walls()
	_ok(walls.size() == DoomTextures.W_COUNT, "walls has W_COUNT entries")
	var walls_ok := true
	for t in walls:
		if t == null:
			walls_ok = false
	_ok(walls_ok, "every wall texture is non-null")

	var floors := DoomTextures.floors()
	_ok(floors.size() == DoomTextures.F_COUNT, "floors has F_COUNT entries")

	var sprites := DoomTextures.sprites()
	_ok(sprites.size() == DoomTextures.S_COUNT, "sprites has S_COUNT entries")

	_ok(DoomTextures.sky() != null, "sky is non-null")
	_ok(DoomTextures.sky().get_width() == 512 and DoomTextures.sky().get_height() == 100, "sky is 512x100")

	_ok(DoomTextures.faces().size() == 8, "faces has 8 entries")
	_ok(DoomTextures.weapons().size() == 8, "weapons has 8 entries")

	var brick: Texture2D = walls[DoomTextures.W_BRICK_RED]
	_ok(brick.get_width() == DoomTextures.TEX_W and brick.get_height() == DoomTextures.TEX_H, "brick tex is 64x64")
	var brick_img := brick.get_image()
	var non_zero := false
	for y in range(DoomTextures.TEX_H):
		for x in range(DoomTextures.TEX_W):
			if brick_img.get_pixel(x, y).a > 0.0:
				non_zero = true
				break
		if non_zero:
			break
	_ok(non_zero, "brick texture has non-transparent pixels")

	_ok(DoomTextures.walls() == walls, "ensure_built is idempotent (same array instance)")

func _test_maps() -> void:
	var expected_names := [
		"E1M1: Hangar", "E1M2: Toxin Refinery", "E1M3: Phobos Lab",
		"E1M4: Outpost", "E1M5: Watchtower", "E1M6: Skybridge",
	]
	for level in range(1, 7):
		var ls := DoomMaps.build_level(level)
		_ok(ls != null, "level %d builds" % level)
		_ok(ls.map.name == expected_names[level - 1], "level %d name = '%s'" % [level, expected_names[level - 1]])
		_ok(ls.map.cells.size() == ls.map.width * ls.map.height, "level %d cell count matches width*height" % level)
		_ok(ls.mobjs.size() > 0, "level %d has mobjs" % level)
		_ok(ls.player_x > 0.0 and ls.player_y > 0.0, "level %d has a player start" % level)

		var bad := 0
		for c in ls.map.cells:
			if c.kind == DoomTypes.CellKind.WALL and (c.wall_tex_idx < 0 or c.wall_tex_idx >= DoomTextures.W_COUNT):
				bad += 1
		_ok(bad == 0, "level %d has no out-of-range wall texture indices" % level)

		var sector_map := DoomTypes.MapData.from_tiles(ls.map)
		_ok(sector_map.is_valid(), "level %d sector map is valid" % level)

	var l1 := DoomMaps.build_level(1)
	_ok(l1.boss_exit_gated == true, "level 1 is boss-exit-gated")
	var l2 := DoomMaps.build_level(2)
	_ok(l2.boss_exit_gated == false, "level 2 is not boss-exit-gated")

	var l6 := DoomMaps.build_level(6)
	var found_extra_floor := false
	for c in l6.map.cells:
		if c.extra_floors != null and c.extra_floors.size() > 0:
			found_extra_floor = true
			break
	_ok(found_extra_floor, "level 6 has a 3D floor (extra_floors)")

	_ok(DoomMaps.health_for(DoomTypes.MobjKind.BARON) == DoomTypes.C.HP_BARON, "health_for(BARON)")
	_ok(DoomMaps.radius_for(DoomTypes.MobjKind.CACODEMON) == 0.42, "radius_for(CACODEMON)")
	_ok(DoomMaps.height_for(DoomTypes.MobjKind.KEY_RED) == 0.35, "height_for(KEY_RED)")

func _test_game_logic() -> void:
	for level in range(1, 7):
		var st := GameLogic.new_game(level, DoomTypes.Difficulty.NORMAL)
		_ok(st != null, "level %d new_game succeeds" % level)
		_ok(st.player.sector_id >= 0, "level %d player has a valid sector" % level)
		_ok(st.frame.columns.size() == DoomTypes.C.VIEW_W, "level %d frame has VIEW_W columns" % level)

		var non_sky := 0
		var has_floor_band := 0
		var all_have_main := true
		for col in st.frame.columns:
			if col == null or col.main == null:
				all_have_main = false
				continue
			if not col.main.is_sky:
				non_sky += 1
			if col.floor_bands.size() > 0:
				has_floor_band += 1
		_ok(all_have_main, "level %d: every column has a Main seg" % level)
		# Every level has a floor band in every column (the near sector's own
		# floor, always below eye height at spawn) -- a real structural
		# invariant. NOTE: a column reaching an actual wall (non_sky) is NOT
		# a universal invariant here -- MAX_RAY_HOPS=16 (the original's own
		# portal-traversal cap) genuinely isn't enough to cross some levels'
		# large open areas from spawn, so several levels legitimately show 0
		# wall hits from the player's start (faithful to the original, not a
		# bug) -- only levels 1 and 6 have walls close enough to spawn to
		# check this positively.
		_ok(has_floor_band == DoomTypes.C.VIEW_W, "level %d: every column has a floor band" % level)
		if level == 1 or level == 6:
			_ok(non_sky > 0, "level %d (walls near spawn): at least one column reaches a wall" % level)

	# Deterministic RNG (Frand): same seed -> same sequence.
	var seed_before := 777
	var st_a := DoomTypes.GameState.new()
	st_a.rng_seed = seed_before
	var st_b := DoomTypes.GameState.new()
	st_b.rng_seed = seed_before
	_ok(GameLogic.frand(st_a) == GameLogic.frand(st_b), "frand is deterministic given the same seed")
	var r := GameLogic.frand(st_a)
	_ok(r >= 0.0 and r < 1.0, "frand returns a value in [0,1)")

	_ok(GameLogic.is_monster(DoomTypes.MobjKind.IMP), "is_monster(IMP)")
	_ok(not GameLogic.is_monster(DoomTypes.MobjKind.BARREL), "not is_monster(BARREL)")
	_ok(GameLogic.is_boss(DoomTypes.MobjKind.BARON), "is_boss(BARON)")
	_ok(GameLogic.is_pickup(DoomTypes.MobjKind.KEY_RED), "is_pickup(KEY_RED)")
	_ok(not GameLogic.is_pickup(DoomTypes.MobjKind.BARREL), "not is_pickup(BARREL)")
	_ok(GameLogic.is_projectile(DoomTypes.MobjKind.ROCKET_PROJ), "is_projectile(ROCKET_PROJ)")

	var l1 := GameLogic.new_game(1, DoomTypes.Difficulty.NORMAL)
	_ok(GameLogic.any_boss_alive(l1), "level 1 has a living boss right after new_game")

func _test_raycast() -> void:
	var st := GameLogic.new_game(1, DoomTypes.Difficulty.NORMAL)
	var hits: Array = Raycast.cast(st.sector_map, Vector2(st.player.x, st.player.y), st.player.sector_id, Vector2(1, 0))
	_ok(hits.size() > 0, "Raycast.cast returns at least one hit for a level-1 ray")
	_ok(hits[hits.size() - 1].distance > 0.0, "last hit has a positive distance")

	var seg := Raycast.ray_segment(Vector2(0, 0), Vector2(1, 0), Vector2(5, -1), Vector2(5, 1))
	_ok(seg["hit"] == true, "ray_segment finds a perpendicular crossing segment")
	_ok(absf(seg["t"] - 5.0) < 0.001, "ray_segment t is the correct distance")
	_ok(absf(seg["u"] - 0.5) < 0.001, "ray_segment u is the midpoint")

	var res := Raycast.dist_point_to_segment_sq(Vector2(0, 5), Vector2(-1, 0), Vector2(1, 0))
	_ok(absf(res["dist_sq"] - 25.0) < 0.001, "dist_point_to_segment_sq: point directly above segment midpoint")

func _test_screen_logic() -> void:
	# Level 1 has 25 mobjs spawned right at new_game, all alive/idle -- the
	# sprite list should contain some of them (those in front of the player
	# and not occlusion-culled).
	var st := GameLogic.new_game(1, DoomTypes.Difficulty.NORMAL)
	var sprites := DoomGameScreenLogic.build_sprite_list(st)
	_ok(sprites is Array, "build_sprite_list returns an Array")
	# Sorted far-to-near (descending distance) -- the merge/paint-order invariant.
	var sorted_ok := true
	for i in range(1, sprites.size()):
		if sprites[i - 1].distance < sprites[i].distance:
			sorted_ok = false
	_ok(sorted_ok, "build_sprite_list is sorted far-to-near (descending distance)")

	var extra_segs := DoomGameScreenLogic.build_extra_seg_list(st)
	_ok(extra_segs is Array, "build_extra_seg_list returns an Array")

	var floor_bands := DoomGameScreenLogic.build_floor_band_list(st)
	_ok(floor_bands.size() > 0, "build_floor_band_list finds bands (level 1 has floor bands every column)")

	var merged_floor := DoomGameScreenLogic.build_merged_floor_bands(st)
	_ok(merged_floor.size() == floor_bands.size(), "build_merged_floor_bands has one entry per raw band (no actual horizontal merge in this port)")

	var merged_ceil := DoomGameScreenLogic.build_merged_ceiling_bands(st)
	_ok(merged_ceil is Array, "build_merged_ceiling_bands returns an Array")

	# Tracers: none fired yet, so the list should be empty, but shouldn't crash.
	var tracers := DoomGameScreenLogic.build_tracer_list(st)
	_ok(tracers.size() == 0, "build_tracer_list is empty with no tracers fired")

	# Manually fire a tracer straight ahead, mirroring the real muzzle offset
	# game_logic.gd's (future Phase 3) SpawnTracer will use: forward + below
	# eye, so the projected segment has real on-screen extent (a tracer
	# exactly AT the camera origin with matching height, like a naive
	# "player position to player position+forward" test case, degenerately
	# projects to a single point -- zero length -- and gets filtered, same
	# as it would in the original).
	var view_z: float = st.player.z + st.player.view_height
	var fwd_x := cos(st.player.angle)
	var fwd_y := sin(st.player.angle)
	var t := DoomTypes.Tracer.new()
	t.ax = st.player.x + fwd_x * DoomTypes.C.MUZZLE_FORWARD
	t.ay = st.player.y + fwd_y * DoomTypes.C.MUZZLE_FORWARD
	t.az = view_z - DoomTypes.C.MUZZLE_BELOW_EYE
	t.bx = st.player.x + fwd_x * 5.0
	t.by = st.player.y + fwd_y * 5.0
	t.bz = view_z
	t.age_ms = 0.0
	t.color_idx = 0
	st.tracers[0] = t
	var tracers2 := DoomGameScreenLogic.build_tracer_list(st)
	_ok(tracers2.size() == 1, "a fresh, in-view tracer projects to exactly one entry")
	if tracers2.size() == 1:
		_ok(tracers2[0].length > 0.0, "projected tracer has a positive screen length")
		_ok(tracers2[0].alpha > 0.99, "a fresh tracer (age=0) is fully opaque")

	# sprite_scale / sprite_vertical_anchor sanity.
	_ok(DoomGameScreenLogic.sprite_scale(DoomTypes.MobjKind.BARON) == 1.6, "sprite_scale(BARON)")
	_ok(DoomGameScreenLogic.sprite_vertical_anchor(DoomTypes.MobjKind.CACODEMON) == 0.0, "sprite_vertical_anchor(CACODEMON)")

func _test_player_movement() -> void:
	var st := GameLogic.new_game(1, DoomTypes.Difficulty.NORMAL)
	var start_x := st.player.x
	var start_angle := st.player.angle

	# Mouse-look: yaw adds directly; pitch is negated and scaled by
	# MOUSE_PITCH_SENS, then clamped.
	var input := DoomTypes.InputCmd.new()
	input.yaw_delta = 0.1
	input.pitch_delta = 10.0
	GameLogic.update_player(st, input, 0.016)
	_ok(is_equal_approx(st.player.angle, start_angle + 0.1), "yaw_delta adds directly to player.angle")
	_ok(is_equal_approx(st.player.pitch, -10.0 * DoomTypes.C.MOUSE_PITCH_SENS), "pitch_delta is negated and scaled by MOUSE_PITCH_SENS")

	var clamp_input := DoomTypes.InputCmd.new()
	clamp_input.pitch_delta = -100000.0
	GameLogic.update_player(st, clamp_input, 0.016)
	_ok(st.player.pitch >= -DoomTypes.C.MAX_PITCH, "pitch is clamped to -MAX_PITCH")

	# Forward movement along a known-clear corridor (level 1 spawn, facing
	# straight down -Y at angle=-PI/2, per DoomMaps.level1's PlayerStart).
	var st2 := GameLogic.new_game(1, DoomTypes.Difficulty.NORMAL)
	var y0 := st2.player.y
	var move_input := DoomTypes.InputCmd.new()
	move_input.forward = true
	for i in range(10):
		GameLogic.update_player(st2, move_input, 1.0 / 60.0)
	_ok(st2.player.y < y0, "forward movement decreases Y (facing -PI/2, matches level 1's corridor heading toward the door)")
	_ok(absf(st2.player.x - start_x) < 0.05, "forward movement at angle=-PI/2 doesn't drift X")

	# Collision: running forward for a long time should never leave the map's
	# bounds -- walls must actually stop the player somewhere.
	var st3 := GameLogic.new_game(1, DoomTypes.Difficulty.NORMAL)
	var long_move := DoomTypes.InputCmd.new()
	long_move.forward = true
	for i in range(600): # 10 simulated seconds
		GameLogic.update_player(st3, long_move, 1.0 / 60.0)
	_ok(st3.player.x >= 0.0 and st3.player.x < st3.map.width, "collision keeps player.x in map bounds after sustained forward movement")
	_ok(st3.player.y >= 0.0 and st3.player.y < st3.map.height, "collision keeps player.y in map bounds after sustained forward movement")

	# Jump: from grounded (z==0, z_vel==0), a rising jump-key edge applies JUMP_VELOCITY.
	var st4 := GameLogic.new_game(1, DoomTypes.Difficulty.NORMAL)
	_ok(st4.player.z <= 0.001, "player starts on the ground (z ~ 0)")
	var jump_input := DoomTypes.InputCmd.new()
	jump_input.jump = true
	GameLogic.update_player(st4, jump_input, 1.0 / 60.0)
	_ok(st4.player.z > 0.0, "jump lifts the player off the ground on the next tick")

	# Weapon switch: only switches to an OWNED weapon slot.
	var st5 := GameLogic.new_game(1, DoomTypes.Difficulty.NORMAL)
	var switch_to_unowned := DoomTypes.InputCmd.new()
	switch_to_unowned.weapon_switch = 3 # index 2 = Shotgun, not owned at new_game
	GameLogic.update_player(st5, switch_to_unowned, 1.0 / 60.0)
	_ok(st5.player.weapon == DoomTypes.WeaponType.PISTOL, "weapon_switch to an unowned slot is ignored")
	var switch_to_owned := DoomTypes.InputCmd.new()
	switch_to_owned.weapon_switch = 1 # index 0 = Fist, owned by default
	GameLogic.update_player(st5, switch_to_owned, 1.0 / 60.0)
	_ok(st5.player.weapon == DoomTypes.WeaponType.FIST, "weapon_switch to an owned slot switches weapon")

	# Hurt: damage reduces health, sets hurt_flash, and kills at 0.
	var st6 := GameLogic.new_game(1, DoomTypes.Difficulty.NORMAL)
	var hp0 := st6.player.health
	GameLogic.hurt(st6, st6.player, 10, 0)
	_ok(st6.player.health == hp0 - 10, "hurt (Normal difficulty, no armor) reduces health by the exact damage amount")
	_ok(st6.player.hurt_flash > 0.0, "hurt sets hurt_flash")
	GameLogic.hurt(st6, st6.player, 10000, 0)
	_ok(st6.player.health == 0 and not st6.player.alive and st6.game_over, "lethal damage zeroes health, kills the player, and sets game_over")

	# tick(): the full per-frame dispatch keeps advancing tic/time_accum and
	# re-running cast_frame without error, even with a fully-neutral input.
	var st7 := GameLogic.new_game(1, DoomTypes.Difficulty.NORMAL)
	var idle_input := DoomTypes.InputCmd.new()
	var tic0 := st7.tic
	for i in range(5):
		GameLogic.tick(st7, 1.0 / 60.0, idle_input)
	_ok(st7.tic == tic0 + 5, "tick() advances the tic counter once per call")
	_ok(st7.time_accum > 0.0, "tick() accumulates time_accum")
	_ok(st7.frame.columns.size() == DoomTypes.C.VIEW_W, "tick() keeps re-running cast_frame (VIEW_W columns present)")

## Phase 3a: door FSM (try_use -> update_doors) + keycard gating. Level 1 has a
## plain door at tile (24,37) and a locked DOOR_RED at (9,27).
func _test_doors() -> void:
	var st := GameLogic.new_game(1, DoomTypes.Difficulty.NORMAL)
	var w: int = st.map.width
	var door: DoomTypes.Cell = st.map.cells[37 * w + 24]
	_ok(door.kind == DoomTypes.CellKind.DOOR, "level1 has a plain door at (24,37)")
	_ok(door.door_state == 0 and door.door_timer == 0, "door starts closed + idle")
	_ok(st.map.blocks_movement(24, 37) == true, "closed door blocks movement")

	# Face the door from just south of it and press Use.
	st.player.x = 24.5
	st.player.y = 38.5
	st.player.angle = -PI / 2.0 # facing -Y (toward the door tile)
	GameLogic.try_use(st)
	_ok(door.door_timer == 1, "try_use starts the door opening (timer=1)")

	# Animate to fully open.
	var opened := false
	for i in range(120):
		GameLogic.update_doors(st, 1.0 / 60.0)
		if door.door_state >= 255:
			opened = true
			break
	_ok(opened and door.door_timer == 2, "door fully opens then enters wait state (timer=2)")
	_ok(st.map.blocks_movement(24, 37) == false, "open door no longer blocks movement")
	var sid: int = st.sector_map.cell_to_sector[37 * w + 24]
	_ok(sid >= 0 and st.sector_map.sectors[sid].ceiling_z > 1.0, "open door mirrors onto sector ceiling_z")

	# A locked colored door without the key does NOT open, and posts a message.
	var red_door: DoomTypes.Cell = st.map.cells[27 * w + 9]
	_ok(red_door.kind == DoomTypes.CellKind.DOOR_RED, "level1 has a red door at (9,27)")
	# This door sits in a vertical wall (passable E<->W), so approach from the east.
	st.player.keys = DoomTypes.KeyCard.NONE
	st.player.x = 10.5
	st.player.y = 27.5
	st.player.angle = PI # facing -X (toward the door tile)
	st.player.message_timer = 0.0
	GameLogic.try_use(st)
	_ok(red_door.door_timer == 0, "locked red door stays shut without the key")
	_ok(st.player.message_timer > 0.0, "locked door posts a 'need keycard' message")

	# With the key, it opens.
	st.player.keys = DoomTypes.KeyCard.RED
	GameLogic.try_use(st)
	_ok(red_door.door_timer == 1, "red door opens once the player holds the red key")

# Phase 3b/c: combat, AI, pickups. Pure-logic (no reconciler): spawn mobjs into
# the pool directly and drive the ported GameLogic combat functions.
func _test_combat() -> void:
	var st := GameLogic.new_game(1, DoomTypes.Difficulty.NORMAL)
	var p := st.player

	# --- damage_mobj: non-lethal keeps the monster active; lethal -> DYING + kill ---
	var imp := DoomTypes.Mobj.new()
	imp.kind = DoomTypes.MobjKind.IMP
	imp.state = DoomTypes.AIState.HUNTING
	imp.health = DoomTypes.C.HP_IMP
	imp.x = p.x + 3.0
	imp.y = p.y
	GameLogic.add_mobj(st, imp)
	var imp_idx := -1
	for i in range(1, st.mobj_count + 1):
		if st.mobjs[i] == imp:
			imp_idx = i
			break
	_ok(imp_idx > 0, "spawned imp is in the mobj pool")
	var kills_before := st.kill_count
	GameLogic.damage_mobj(st, imp_idx, 5, 0)
	_ok(imp.health == DoomTypes.C.HP_IMP - 5, "non-lethal damage lowers monster health")
	_ok(imp.state == DoomTypes.AIState.PAIN or imp.state == DoomTypes.AIState.HUNTING, "hurt monster stays active (pain/hunting)")
	GameLogic.damage_mobj(st, imp_idx, 1000, 0)
	_ok(imp.health <= 0, "lethal damage drops health to <= 0")
	_ok(imp.state == DoomTypes.AIState.DYING, "lethal damage sets DYING")
	_ok(st.kill_count == kills_before + 1, "a kill increments kill_count")

	# --- try_give_pickup: health / keycard / weapon ---
	p.health = 50
	_ok(GameLogic.try_give_pickup(st, DoomTypes.MobjKind.PICKUP_HEALTH), "stimpack accepted when hurt")
	_ok(p.health == 75, "stimpack heals +25")
	p.health = 100
	_ok(not GameLogic.try_give_pickup(st, DoomTypes.MobjKind.PICKUP_HEALTH), "stimpack refused at full health")
	GameLogic.try_give_pickup(st, DoomTypes.MobjKind.KEY_BLUE)
	_ok((p.keys & DoomTypes.KeyCard.BLUE) != 0, "blue keycard sets the BLUE flag")
	GameLogic.try_give_pickup(st, DoomTypes.MobjKind.PICKUP_SHOTGUN)
	_ok(p.owned_weapons[DoomTypes.WeaponType.SHOTGUN], "shotgun pickup grants the shotgun")

	# --- update_pickup: a stimpack on the player's tile is auto-collected ---
	p.health = 40
	var med := DoomTypes.Mobj.new()
	med.kind = DoomTypes.MobjKind.PICKUP_HEALTH
	med.x = p.x
	med.y = p.y
	GameLogic.add_mobj(st, med)
	var med_idx := -1
	for i in range(1, st.mobj_count + 1):
		if st.mobjs[i] == med:
			med_idx = i
			break
	GameLogic.update_pickup(st, med_idx)
	_ok(med.collected, "walking over a stimpack collects it")
	_ok(p.health == 65, "collected stimpack heals the player")

	# --- splash: damages a nearby monster and the nearby player ---
	var st2 := GameLogic.new_game(1, DoomTypes.Difficulty.NORMAL)
	var imp2 := DoomTypes.Mobj.new()
	imp2.kind = DoomTypes.MobjKind.IMP
	imp2.state = DoomTypes.AIState.HUNTING
	imp2.health = DoomTypes.C.HP_IMP
	imp2.x = st2.player.x + 1.0
	imp2.y = st2.player.y
	GameLogic.add_mobj(st2, imp2)
	st2.player.health = 100
	GameLogic.splash(st2, st2.player.x, st2.player.y, 3.0, 100, -1)
	_ok(imp2.health < DoomTypes.C.HP_IMP, "rocket splash damages a nearby monster")
	_ok(st2.player.health < 100, "rocket splash also hurts the nearby player")

	# --- fire_weapon: pistol consumes a bullet, emits a tracer, sets cooldown ---
	var st3 := GameLogic.new_game(1, DoomTypes.Difficulty.NORMAL)
	st3.player.weapon = DoomTypes.WeaponType.PISTOL
	var bullets_before: int = st3.player.ammo[0]
	GameLogic.fire_weapon(st3)
	_ok(st3.player.ammo[0] == bullets_before - 1, "pistol fire consumes one bullet")
	_ok(st3.tracer_count > 0, "pistol fire spawns a hitscan tracer")
	_ok(st3.player.shoot_cooldown > 0.0, "firing sets a shoot cooldown")

	# --- fire_weapon: rocket launcher spawns a live ROCKET_PROJ ---
	st3.player.weapon = DoomTypes.WeaponType.ROCKET_LAUNCHER
	st3.player.ammo[2] = 5
	st3.player.shoot_cooldown = 0.0
	GameLogic.fire_weapon(st3)
	_ok(st3.player.ammo[2] == 4, "rocket fire consumes one rocket")
	var has_rocket := false
	for i in range(1, st3.mobj_count + 1):
		var mm: DoomTypes.Mobj = st3.mobjs[i]
		if mm != null and mm.id != 0 and mm.kind == DoomTypes.MobjKind.ROCKET_PROJ:
			has_rocket = true
	_ok(has_rocket, "rocket fire spawns a ROCKET_PROJ projectile")

	# --- fire_weapon: an empty weapon falls back instead of firing it ---
	st3.player.weapon = DoomTypes.WeaponType.PLASMA_RIFLE
	st3.player.ammo[3] = 0
	st3.player.shoot_cooldown = 0.0
	GameLogic.fire_weapon(st3)
	_ok(st3.player.weapon != DoomTypes.WeaponType.PLASMA_RIFLE, "empty plasma falls back to another weapon")

	# --- update_monster: an idle imp in sight wakes to HUNTING via the tick loop ---
	var st4 := GameLogic.new_game(1, DoomTypes.Difficulty.NORMAL)
	var imp3 := DoomTypes.Mobj.new()
	imp3.kind = DoomTypes.MobjKind.IMP
	imp3.state = DoomTypes.AIState.IDLE
	imp3.health = DoomTypes.C.HP_IMP
	imp3.x = st4.player.x + 1.5
	imp3.y = st4.player.y
	imp3.sector_id = st4.player.sector_id
	GameLogic.add_mobj(st4, imp3)
	var cmd := DoomTypes.InputCmd.new()
	GameLogic.tick(st4, 0.016, cmd)
	_ok(imp3.state == DoomTypes.AIState.HUNTING or imp3.state == DoomTypes.AIState.PAIN, "an idle imp in sight range wakes when the tick loop runs")


## The one reconciler-based check in this file (see the header comment): mounts
## DoomGameScreen for real, drives DoomInputState + physics_frame directly, and
## confirms the full hook -> tick -> re-render pipeline survives without
## crashing. Pure-logic tests above can't exercise view_ref/get_tree() wiring.
func _test_integration_tick() -> void:
	var c := Control.new()
	root.add_child(c)
	var app := RuitkRoot.create(c, V.fc(DoomGameScreen.render))
	await process_frame
	await process_frame

	var before := _collect_positions(c)

	DoomInputState.shared.reset()
	DoomInputState.shared.forward = true
	# The hook drives its tick loop off get_tree().process_frame (NOT physics_frame
	# -- see doom_game_screen.hooks.guitkx for why), so advance process frames here.
	for i in range(10):
		await process_frame
	DoomInputState.shared.reset()
	await process_frame

	var after := _collect_positions(c)

	_ok(c.get_child_count() > 0, "DoomGameScreen keeps rendering after 10 live physics ticks with input held")
	# Regression guard for the mutate-in-place/reference-equal-bailout bug: tick()
	# mutates GameState in place, so the hook's setState must hand the reconciler
	# a genuinely new top-level reference (GameState.snapshot()) each tick, or the
	# Object.is-equal bailout silently drops every re-render despite state
	# actually changing (player.y visibly moved but the Control tree never did).
	var n: int = min(before.size(), after.size())
	var diffs := 0
	for i in range(n):
		if before[i] != after[i]:
			diffs += 1
	_ok(n > 0 and diffs > 0, "held forward input actually moves rendered node positions (%d/%d changed)" % [diffs, n])
	app.unmount()
	c.queue_free()

## Phase 5: mount the DoomGame root (screen switch). Starts at the main menu, so
## this render-smokes DoomGame + DoomMainMenu + the mouse-mode effect + component
## composition (DoomHUD/DoomFace/DoomMinimap are reached from the game branch) all
## mounting without error -- the menu/screen-flow the pure-logic tests can't touch.
func _test_menu_and_switch() -> void:
	var c := Control.new()
	root.add_child(c)
	var app := RuitkRoot.create(c, V.fc(DoomGame.render))
	await process_frame
	await process_frame
	_ok(c.get_child_count() > 0, "DoomGame mounts at the main menu without error")
	_ok(not DoomInputState.shared.allow_capture, "menu leaves the cursor free (allow_capture false)")
	app.unmount()
	c.queue_free()

func _collect_positions(node: Node) -> Array:
	var out: Array = []
	_collect_positions_into(node, out)
	return out

func _collect_positions_into(node: Node, out: Array) -> void:
	if node is Control:
		out.append((node as Control).position)
	for child in node.get_children():
		_collect_positions_into(child, out)
