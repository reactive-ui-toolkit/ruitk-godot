class_name DoomTypes
extends RefCounted

## Faithful port of the Unity ReactiveUIToolKit `DoomGame` sample's `DoomTypes.uitkx`
## (Assets/ReactiveUIToolKit/Samples/Components/DoomGame). Structs -> RefCounted classes
## (GDScript has no value-type structs); every field/method ported 1:1, no new behavior.
## See plans/DOOM_GAME_GUITKX_PORT_PLAN.md.

enum GameScreen { MAIN_MENU, GAME }
enum Difficulty { EASY = 0, NORMAL = 1, HARD = 2 }

enum CellKind {
	EMPTY = 0,
	WALL = 1,
	DOOR = 2,
	DOOR_BLUE = 3,
	DOOR_YELLOW = 4,
	DOOR_RED = 5,
	EXIT = 6,
	LIQUID = 7,
}

enum WeaponType {
	FIST = 0, PISTOL = 1, SHOTGUN = 2, CHAINGUN = 3,
	ROCKET_LAUNCHER = 4, PLASMA_RIFLE = 5, BFG9000 = 6,
}

enum AmmoType {
	BULLETS = 0, SHELLS = 1, ROCKETS = 2, CELLS = 3, NONE = 255,
}

## [Flags] in the original -- combine with bitwise OR (e.g. KeyCard.BLUE | KeyCard.RED).
enum KeyCard {
	NONE = 0, BLUE = 1, YELLOW = 2, RED = 4,
}

enum MobjKind {
	PLAYER,
	IMP, DEMON, BARON, CACODEMON, LOST_SOUL, ZOMBIEMAN, SHOTGUNNER,
	IMP_FIREBALL, BARON_BALL, CACO_BALL, ROCKET_PROJ, PLASMA_PROJ, BFG_PROJ,
	EXPLOSION,
	PICKUP_HEALTH, PICKUP_ARMOR, PICKUP_ARMOR_BLUE,
	PICKUP_BULLETS, PICKUP_SHELLS, PICKUP_ROCKETS, PICKUP_CELLS,
	PICKUP_SHOTGUN, PICKUP_CHAINGUN, PICKUP_ROCKET_LAUNCHER, PICKUP_PLASMA, PICKUP_BFG,
	KEY_BLUE, KEY_YELLOW, KEY_RED,
	BARREL, LIGHT, CORPSE,
}

enum AIState { IDLE, HUNTING, ATTACKING, PAIN, DYING, DEAD }

## [Flags] in the original.
enum LinedefFlags {
	NONE = 0,
	IMPASSABLE = 1, # even two-sided lines can be flagged solid (rails)
	BLOCK_MONSTERS = 2,
	TWO_SIDED = 4,
	UPPER_UNPEGGED = 8,
	LOWER_UNPEGGED = 16,
	DONT_DRAW = 32, # automap hint
}

enum LineSpecial {
	NONE = 0,
	USE_DOOR_OPEN = 1, # E-key opens BackSector ceiling
	USE_DOOR_BLUE = 2,
	USE_DOOR_YELLOW = 3,
	USE_DOOR_RED = 4,
	USE_LIFT = 5, # E-key triggers lift on BackSector floor
	CROSS_EXIT = 6, # touching this linedef wins the level
	CROSS_TELEPORT = 7, # touching teleports player to Tag-marked spot
	USE_SWITCH_EXIT = 8,
}

enum SectorSpecial {
	NONE = 0,
	LIGHT_FLICKER = 1,
	LIGHT_BLINK = 2,
	LIGHT_GLOW = 3,
	DAMAGE_NUKAGE5 = 4, # -5 hp/2s while standing
	DAMAGE_LAVA10 = 5,
	SECRET = 6,
	DOOR_CLOSE30 = 7, # door auto-close after 30s
}

enum SegKind {
	MID = 0, # single solid wall (one-sided line)
	UPPER = 1, # step-down ceiling neighbor
	LOWER = 2, # step-up floor neighbor
	EXTRA_TOP = 3, # top plane of a 3D floor
	EXTRA_BOT = 4, # bottom plane of a 3D floor
	EXTRA_SIDE = 5, # side wall of a 3D floor
}

## 3D-floor (Phase 7 in the original): an extra walkable plane inside a sector.
## Multiple ExtraFloors per sector enable basements, balconies, mezzanines.
class ExtraFloor extends RefCounted:
	var bottom_z: float # bottom of the slab (player walks ON top_z)
	var top_z: float # top of the slab
	var side_tex: int # texture on the slab's vertical sides
	var top_tex: int # texture on top (what the player walks on)
	var bottom_tex: int # texture on the underside (ceiling-of-below)
	var light: int # light level for this slab's surfaces
	var solid: bool # false = swimmable / shootable through

class Cell extends RefCounted:
	var kind: int = CellKind.EMPTY
	var wall_tex_idx: int
	var floor_tex_idx: int
	var ceiling_tex_idx: int
	var light_level: int
	var door_state: int # 0=closed, 255=open
	var door_timer: int
	var tag: int
	# Phase 3 (original): per-cell floor/ceiling height (world units). When 0 they
	# default to 0 and 1 respectively in from_tiles (flat rooms).
	var floor_z: float
	var ceiling_z: float
	# Phase 4 (original): sector special (lighting/damage). None by default.
	var special: int = SectorSpecial.NONE
	# Phase 7 (original): open-air ceiling. When true, the ceiling renders as sky
	# and the player is not bonked; the cell behaves as if ceiling_z = +infinity
	# for vertical movement.
	var is_sky: bool
	# Phase 9 (original): stacked 3D-floor slabs occupying this cell. null = none.
	# Sorted by bottom_z ascending.
	var extra_floors: Array # of ExtraFloor, may be null

class MapDef extends RefCounted:
	var width: int
	var height: int
	var cells: Array # of Cell
	var name: String

	func at_safe(x: int, y: int) -> Cell:
		if x < 0 or x >= width or y < 0 or y >= height:
			var c := Cell.new()
			c.kind = CellKind.WALL
			c.wall_tex_idx = 0
			c.light_level = 200
			return c
		return cells[y * width + x]

	func blocks_movement(x: int, y: int) -> bool:
		var c := at_safe(x, y)
		if c.kind == CellKind.WALL:
			return true
		if c.kind == CellKind.DOOR or c.kind == CellKind.DOOR_BLUE or c.kind == CellKind.DOOR_YELLOW or c.kind == CellKind.DOOR_RED:
			return c.door_state < 200
		return false

	# Phase 7 (original): Z-aware blocking. The cell blocks the actor if either
	# its floor is more than step_height above the actor's feet, or its ceiling
	# is below the actor's head. Walls remain infinite blockers. Sky cells
	# ignore the ceiling check entirely.
	func blocks_movement_z(x: int, y: int, foot_z: float, head_z: float, step_height: float) -> bool:
		var c := at_safe(x, y)
		if c.kind == CellKind.WALL:
			return true
		if c.kind == CellKind.DOOR or c.kind == CellKind.DOOR_BLUE or c.kind == CellKind.DOOR_YELLOW or c.kind == CellKind.DOOR_RED:
			if c.door_state < 200:
				return true
		# Phase 9 (original): pick the highest standing surface at-or-below
		# (foot_z + step_height): the cell floor or any ExtraFloor.top_z.
		var flr := c.floor_z
		var ceil_v := 1e9 if c.is_sky else (1.5 if c.ceiling_z <= 0.0 else c.ceiling_z)
		if c.extra_floors != null:
			for ef in c.extra_floors:
				if not ef.solid:
					continue
				if ef.top_z <= foot_z + step_height + 0.001 and ef.top_z > flr:
					flr = ef.top_z
		# Block if the step-up exceeds the actor's stride.
		if flr - foot_z > step_height + 0.001:
			return true
		# Ceiling: lowest blocking surface ABOVE the standing floor. Player body
		# would occupy [flr, flr + (head_z - foot_z)] after step-up. Any solid
		# slab whose body intersects that volume is a blocker.
		var stand_head := flr + (head_z - foot_z)
		if c.extra_floors != null:
			for ef in c.extra_floors:
				if not ef.solid:
					continue
				# Slab top at-or-below standing floor is the floor itself -- not
				# a blocker. Slab whose BODY overlaps [flr+eps, stand_head-eps]
				# is a blocker (we'd be inside it).
				if ef.top_z <= flr + 0.001:
					continue
				if ef.bottom_z < stand_head - 0.001 and ef.top_z > flr + 0.001:
					return true
				if ef.bottom_z < ceil_v:
					ceil_v = ef.bottom_z
		if ceil_v < stand_head - 0.001:
			return true
		return false

	# Phase 7/9 (original): floor height the actor would stand on at this cell,
	# considering ExtraFloor tops at-or-below (foot_z + step_height).
	func floor_at(x: int, y: int, foot_z: float = 0.0, step_height: float = 1e6) -> float:
		var c := at_safe(x, y)
		var best := c.floor_z
		if c.extra_floors != null:
			for ef in c.extra_floors:
				if not ef.solid:
					continue
				if ef.top_z <= foot_z + step_height + 0.001 and ef.top_z > best:
					best = ef.top_z
		return best

	func blocks_rays(x: int, y: int) -> bool:
		var c := at_safe(x, y)
		if c.kind == CellKind.WALL:
			return true
		if c.kind == CellKind.DOOR or c.kind == CellKind.DOOR_BLUE or c.kind == CellKind.DOOR_YELLOW or c.kind == CellKind.DOOR_RED:
			return c.door_state < 250
		return false

class PlayerState extends RefCounted:
	var x: float
	var y: float
	var angle: float
	var pitch: float # pixels of Y-shear
	var health: int
	var armor: int
	var armor_class: int # 0=none 1=green 2=blue
	var weapon: int = WeaponType.FIST
	var ammo: Array # of int
	var owned_weapons: Array # of bool
	var keys: int = KeyCard.NONE
	var shoot_cooldown: float
	var muzzle_flash: float
	var bob_t: float
	var alive: bool
	var face_state: int # 0=god,1..5=hp buckets,6=hurt,7=dead
	var face_timer: float
	var last_damage_dir: int # 0=front 1=right 2=behind 3=left
	var hurt_flash: float
	var pickup_flash: float
	var message_timer: float
	var message_text: String = ""
	# -- Phase 1 (Sector-engine) additions in the original. Default 0. --
	var z: float # feet height (0 = ground)
	var z_vel: float # for jump/gravity
	var view_height: float # eye offset from feet (default 0.6)
	var sector_id: int = -1 # current sector (-1 = unknown / fallback to grid)
	# Phase 7 (original): pixel offset added to the horizon line (sky/floor/wall)
	# so jump/crouch animation stays in sync across all renderers. Computed by
	# cast_frame from z + view_height.
	var view_shift_px: float
	var jump_held_prev: bool # for edge-detection on Jump key

class Mobj extends RefCounted:
	var id: int
	var kind: int
	var state: int = AIState.IDLE
	var x: float
	var y: float
	var mom_x: float
	var mom_y: float
	var angle: float
	var health: int
	var state_timer: float
	var attack_cooldown: float
	var owner_id: int
	var damage: int
	var radius: float
	var collected: bool
	var anim_frame: int
	# -- Phase 1 (Sector-engine) additions in the original. Default 0. --
	var z: float # feet height in world units
	var z_vel: float # for projectiles + future jump/gravity
	var height: float # from feet to head
	var sector_id: int = -1 # current sector (-1 = unknown / fallback to grid)

class WallSeg extends RefCounted:
	var top_px: float
	var bot_px: float
	var distance: float
	var wall_tex_idx: int
	var tex_u: float
	var light_level: int
	var hit_vertical: bool
	var is_sky: bool
	var is_riser: bool # true if this extra represents the front-face of a step-up
	# Plan C (original): when top_px was clipped UP by an occlusion window, this
	# stores the screen-pixel delta (negative) that the renderer must apply to
	# the texture's Y offset so texel row 0 stays anchored to the UNCLIPPED top
	# (= the wall's true world ceiling). Without this, adjacent columns clipped
	# by different amounts produce diagonal/staircase texture rows on flat walls.
	var tex_offset_px: float

	# GO-03 pooling: restore every field to what WallSeg.new() would produce, so a
	# recycled instance behaves identically to a fresh one (some cast sites don't
	# set is_riser/tex_offset_px). See FrameData's pool.
	func reset() -> void:
		top_px = 0.0
		bot_px = 0.0
		distance = 0.0
		wall_tex_idx = 0
		tex_u = 0.0
		light_level = 0
		hit_vertical = false
		is_sky = false
		is_riser = false
		tex_offset_px = 0.0

class FloorBand extends RefCounted:
	var top_px: float # far edge of this floor slab on screen
	var bot_px: float # near edge (toward bottom of screen)
	var floor_z: float # world Z (for color)
	var light: int # sector light, attenuated by distance
	var floor_tex: int # sector floor texture index
	var behind_floor_z: float = NAN # floor_z of the slab IMMEDIATELY behind this one in the same ray (NAN if none)
	var rim_at_far: bool # true if the far edge of this band is a visible step-down rim
	var distance: float = INF # perpendicular ray distance -- lets bands join the one depth-sorted paint list

	# GO-03 pooling: reproduce FloorBand.new()'s field defaults for recycled instances.
	func reset() -> void:
		top_px = 0.0
		bot_px = 0.0
		floor_z = 0.0
		light = 0
		floor_tex = 0
		behind_floor_z = NAN
		rim_at_far = false
		distance = INF

# Phase 8 (original): ceiling band -- mirror of FloorBand. Painted only for
# non-sky sectors; sky sectors leave the sky backdrop showing through.
class CeilingBand extends RefCounted:
	var top_px: float # upper edge in screen px (smaller = higher)
	var bot_px: float # lower edge in screen px (= projected ceiling line)
	var ceiling_z: float # world Z (for shading)
	var light: int
	var ceiling_tex: int
	var distance: float = INF # perpendicular ray distance -- lets bands join the one depth-sorted paint list

	# GO-03 pooling: reproduce CeilingBand.new()'s field defaults for recycled instances.
	func reset() -> void:
		top_px = 0.0
		bot_px = 0.0
		ceiling_z = 0.0
		light = 0
		ceiling_tex = 0
		distance = INF

class ColumnInfo extends RefCounted:
	var main: WallSeg
	# Phase 3+ (original): extra segs above/below main from portal upper/lower at
	# varying floor/ceiling heights. May be empty/null. Renderer iterates extras
	# then draws main on top (main is the closest/most-clipping seg).
	var extras: Array # of WallSeg
	# Phase 7 (original): world Z of the floor at the terminal wall hit, used as
	# a fallback when there are no per-portal floor bands.
	var front_floor_z: float
	# Phase 7 (original): per-sector floor bands along this ray, near->far. Each
	# band paints from top_px down to bot_px, colored by floor_z.
	var floor_bands: Array # of FloorBand
	# Phase 8 (original): per-sector ceiling bands along this ray, near->far.
	# Skipped for sky sectors (sky backdrop shows through).
	var ceiling_bands: Array # of CeilingBand
	# Phase 8 (original): floor-step occlusion for sprite culling. When the ray
	# crosses a step-up portal (back.floor_z > front.floor_z), the riser blocks
	# any monster standing on the lower side. Sprites with perp > floor_occluder_dist
	# AND anchor_z < floor_occluder_z - 0.05 are culled. Default values mean "no occluder".
	var floor_occluder_dist: float
	var floor_occluder_z: float
	# Phase 9 (original): ceiling-slab occlusion for sprite culling. When the ray
	# crosses an ExtraFloor BOTTOM (slab underside, viewer below), the slab hides
	# anything behind it whose anchor Z sits at-or-above the slab body. Sprites
	# with perp > ceiling_occluder_dist AND anchor_z >= ceiling_occluder_z are
	# culled. Default = no occluder.
	var ceiling_occluder_dist: float
	var ceiling_occluder_z: float

# Phase 8 (original): hitscan tracer streak. Lives ~TRACER_LIFE_MS, fades alpha
# out. Stored in a fixed-size ring on GameState; age_ms >= TRACER_LIFE_MS = dead.
class Tracer extends RefCounted:
	var ax: float
	var ay: float
	var az: float # muzzle (start)
	var bx: float
	var by: float
	var bz: float # impact / max-range (end)
	var age_ms: float
	var color_idx: int # 0=yellow pistol/chaingun, 1=red shotgun pellet

class FrameData extends RefCounted:
	var columns: Array # of ColumnInfo
	var depth_buffer: PackedFloat32Array

	# GO-03 pooling: a per-frame linear allocator for the WallSeg/FloorBand/
	# CeilingBand records that build_column_sector would otherwise heap-allocate
	# ~13x per column, every column, every tick (the struct->class translation
	# tax -- the originals are C# structs). reset_pools() rewinds the used-cursors
	# at the top of cast_frame; take_* hand out a reset() instance, growing the
	# backing pool only when a frame needs more records than any prior frame did.
	# SAFETY INVARIANT (P6, family parity): safe because DoomGameScreen PINS
	# RuitkConfig.time_slicing OFF for its lifetime (the L-07 sync-pin effect in
	# doom_game_screen.guitkx), so a render is always a single synchronous pass
	# that fully consumes a frame's records before the next tick rewinds them.
	# Under a PARKED sliced render, the next tick's reset_pools() would hand the
	# same record objects to new columns while the in-flight render still reads
	# them -- the global time_slicing default flipped to ON (family parity), so do not
	# remove the pin without redesigning this allocator (and vice versa).
	var _wallseg_pool: Array = []
	var _wallseg_used: int = 0
	var _floorband_pool: Array = []
	var _floorband_used: int = 0
	var _ceilband_pool: Array = []
	var _ceilband_used: int = 0

	func reset_pools() -> void:
		_wallseg_used = 0
		_floorband_used = 0
		_ceilband_used = 0

	func take_wallseg() -> WallSeg:
		var o: WallSeg
		if _wallseg_used < _wallseg_pool.size():
			o = _wallseg_pool[_wallseg_used]
		else:
			o = WallSeg.new()
			_wallseg_pool.append(o)
		_wallseg_used += 1
		o.reset()
		return o

	func take_floorband() -> FloorBand:
		var o: FloorBand
		if _floorband_used < _floorband_pool.size():
			o = _floorband_pool[_floorband_used]
		else:
			o = FloorBand.new()
			_floorband_pool.append(o)
		_floorband_used += 1
		o.reset()
		return o

	func take_ceilband() -> CeilingBand:
		var o: CeilingBand
		if _ceilband_used < _ceilband_pool.size():
			o = _ceilband_pool[_ceilband_used]
		else:
			o = CeilingBand.new()
			_ceilband_pool.append(o)
		_ceilband_used += 1
		o.reset()
		return o

class Vertex extends RefCounted:
	var p: Vector2

	func _init(pos: Vector2 = Vector2.ZERO) -> void:
		p = pos

	static func from_xy(x: float, y: float) -> Vertex:
		return Vertex.new(Vector2(x, y))

class Linedef extends RefCounted:
	var v1: int # vertex indices
	var v2: int
	var front_sector: int # sector on the right side of v1->v2
	var back_sector: int = -1 # -1 if one-sided (solid wall)
	var flags: int = LinedefFlags.NONE
	var special: int = LineSpecial.NONE
	var tag: int # links to sector with same tag for triggers
	var mid_tex: int # wall texture for one-sided / window mid
	var upper_tex: int # shown when neighbor ceiling is lower
	var lower_tex: int # shown when neighbor floor is higher

class Sector extends RefCounted:
	var floor_z: float
	var ceiling_z: float
	var light: int
	var floor_tex: int
	var ceiling_tex: int
	var special: int = SectorSpecial.NONE
	var tag: int
	var is_sky: bool # ceiling renders as sky if true
	var line_ids: Array # of int -- linedefs that touch this sector
	var extra_floors: Array # of ExtraFloor -- null if no 3D floors
	# Door/lift animation state (Phase 5 in the original).
	var target_ceiling_z: float
	var target_floor_z: float
	var ceiling_speed: float # units/sec; 0 = idle
	var floor_speed: float
	var door_wait_timer: float # counts down after open before auto-close

class MapData extends RefCounted:
	var vertices: Array # of Vertex
	var lines: Array # of Linedef
	var sectors: Array # of Sector
	var name: String
	var player_start: Vector2
	var player_start_angle: float
	var player_start_sector: int = -1
	# Phase 2 (original): tile-cell to sector lookup (W*H, -1 if cell is Wall).
	# Built by from_tiles; lets the legacy door cell animation also drive the
	# corresponding sector's ceiling_z so the sector renderer sees doors open/close.
	var cell_to_sector: PackedInt32Array
	var cell_width: int
	var cell_height: int

	func is_valid() -> bool:
		return sectors != null and sectors.size() > 0

	# Build a flat tile-grid map into a sector model. Each non-Wall cell becomes
	# its own sector; tile-to-tile boundaries become linedefs. Wall cells
	# contribute solid edges to neighbor sectors. This is a baseline conversion
	# used (in the original) to keep the game running unchanged while the
	# sector pipeline came online.
	static func from_tiles(map: MapDef) -> MapData:
		var verts: Array = [] # of Vertex
		var v_idx := {} # Vector2i -> int
		var w := map.width
		var h := map.height

		var get_vertex := func(x: int, y: int) -> int:
			var key := Vector2i(x, y)
			if v_idx.has(key):
				return v_idx[key]
			var id := verts.size()
			verts.append(Vertex.from_xy(x, y))
			v_idx[key] = id
			return id

		# 1) Allocate one sector per non-Wall cell, indexed by (y*w + x).
		var cell_sector := PackedInt32Array()
		cell_sector.resize(w * h)
		for i in range(cell_sector.size()):
			cell_sector[i] = -1
		var sectors: Array = [] # of Sector

		for y in range(h):
			for x in range(w):
				var c: Cell = map.cells[y * w + x]
				if c.kind == CellKind.WALL:
					continue
				var s := Sector.new()
				s.floor_z = c.floor_z
				s.ceiling_z = 64.0 if c.is_sky else (1.5 if c.ceiling_z <= 0.0 else c.ceiling_z)
				s.light = 200 if c.light_level == 0 else c.light_level
				s.floor_tex = c.floor_tex_idx
				s.ceiling_tex = c.ceiling_tex_idx
				s.special = c.special
				s.tag = c.tag
				s.is_sky = c.is_sky
				s.line_ids = []
				s.extra_floors = c.extra_floors
				s.target_ceiling_z = s.ceiling_z
				s.target_floor_z = c.floor_z
				s.ceiling_speed = 0.0
				s.floor_speed = 0.0
				s.door_wait_timer = 0.0
				# Doors map to closed sectors with ceiling_z=floor_z (closed) until opened.
				if c.kind == CellKind.DOOR or c.kind == CellKind.DOOR_BLUE or c.kind == CellKind.DOOR_YELLOW or c.kind == CellKind.DOOR_RED:
					s.ceiling_z = 0.0 # closed
					s.target_ceiling_z = 1.5
				cell_sector[y * w + x] = sectors.size()
				sectors.append(s)

		# 2) Walk all 4-edges of every cell. Each edge becomes either a one-sided
		#    line (cell vs Wall) or a two-sided line (cell vs cell).
		var lines: Array = [] # of Linedef
		var add_line := func(x1: int, y1: int, x2: int, y2: int, front_sec: int, back_sec: int, mid_tex: int) -> void:
			var v1: int = get_vertex.call(x1, y1)
			var v2: int = get_vertex.call(x2, y2)
			var l := Linedef.new()
			l.v1 = v1
			l.v2 = v2
			l.front_sector = front_sec
			l.back_sector = back_sec
			l.flags = LinedefFlags.TWO_SIDED if back_sec >= 0 else LinedefFlags.NONE
			l.special = LineSpecial.NONE
			l.tag = 0
			l.mid_tex = mid_tex
			l.upper_tex = mid_tex
			l.lower_tex = mid_tex
			var li := lines.size()
			lines.append(l)
			if front_sec >= 0:
				sectors[front_sec].line_ids.append(li)
			if back_sec >= 0:
				sectors[back_sec].line_ids.append(li)

		# Helper: pick wall texture for an edge between cell (x,y) and neighbor
		# (nx,ny). If neighbor is wall -> use neighbor's wall_tex_idx. Otherwise
		# if neighbor is a door cell, use the door's wall_tex_idx (so the door
		# renders when closed).
		var edge_tex := func(x: int, y: int, nx: int, ny: int) -> int:
			var self_cell: Cell = map.cells[y * w + x]
			if nx < 0 or nx >= w or ny < 0 or ny >= h:
				return self_cell.wall_tex_idx
			var nb: Cell = map.cells[ny * w + nx]
			if nb.kind == CellKind.WALL or (nb.kind == CellKind.EXIT and nb.wall_tex_idx != 0):
				return nb.wall_tex_idx
			if nb.kind == CellKind.DOOR or nb.kind == CellKind.DOOR_BLUE or nb.kind == CellKind.DOOR_YELLOW or nb.kind == CellKind.DOOR_RED:
				return nb.wall_tex_idx
			return self_cell.wall_tex_idx

		# For each non-wall cell, emit its right and bottom edges. Right edge:
		# from (x+1,y) to (x+1,y+1). Bottom: from (x,y+1) to (x+1,y+1). Top edge
		# handled by neighbor above; left edge by neighbor to the left. Cells on
		# the outer boundary get an explicit edge to "wall" (back=-1).
		for y in range(h):
			for x in range(w):
				var s: int = cell_sector[y * w + x]
				if s < 0:
					continue
				# Right edge (between this and (x+1, y))
				var neighbor_r: int = cell_sector[y * w + (x + 1)] if x + 1 < w else -1
				var tex_r: int = edge_tex.call(x, y, x + 1, y)
				if x + 1 >= w or map.cells[y * w + (x + 1)].kind == CellKind.WALL:
					add_line.call(x + 1, y, x + 1, y + 1, s, -1, tex_r)
				else:
					add_line.call(x + 1, y, x + 1, y + 1, s, neighbor_r, tex_r)
				# Bottom edge (between this and (x, y+1))
				var neighbor_b: int = cell_sector[(y + 1) * w + x] if y + 1 < h else -1
				var tex_b: int = edge_tex.call(x, y, x, y + 1)
				if y + 1 >= h or map.cells[(y + 1) * w + x].kind == CellKind.WALL:
					add_line.call(x, y + 1, x + 1, y + 1, s, -1, tex_b)
				else:
					add_line.call(x, y + 1, x + 1, y + 1, s, neighbor_b, tex_b)
				# Top edge (only if topmost row or neighbor above is wall --
				# otherwise already handled by neighbor's bottom edge)
				if y == 0 or map.cells[(y - 1) * w + x].kind == CellKind.WALL:
					var tex_t: int = edge_tex.call(x, y, x, y - 1)
					add_line.call(x, y, x + 1, y, s, -1, tex_t)
				# Left edge (only if leftmost col or neighbor left is wall)
				if x == 0 or map.cells[y * w + (x - 1)].kind == CellKind.WALL:
					var tex_l: int = edge_tex.call(x, y, x - 1, y)
					add_line.call(x, y, x, y + 1, s, -1, tex_l)

		# 3) Player start sector is computed from cell_to_sector by the caller
		#    once it knows the tile coordinate; PlayerStart itself is filled in
		#    later too.
		var result := MapData.new()
		result.vertices = verts
		result.lines = lines
		result.sectors = sectors
		result.name = map.name
		result.player_start = Vector2.ZERO
		result.player_start_angle = 0.0
		result.player_start_sector = -1
		result.cell_to_sector = cell_sector
		result.cell_width = w
		result.cell_height = h
		return result

	# Find sector containing point (x,y). Phase 1 (original) uses tile-cell
	# index for O(1) lookup; later phases walk linedef adjacency from a hint
	# sector. This method is intentionally a hint-only API in the original.
	func point_in_sector(x: float, y: float, _width: int) -> int:
		var ix := int(x)
		var iy := int(y)
		if ix < 0 or iy < 0:
			return -1
		return -1

class GameState extends RefCounted:
	var player: PlayerState
	var mobjs: Array # of Mobj
	var mobj_count: int
	var next_mobj_id: int
	var map: MapDef
	var frame: FrameData
	var level: int
	var score: int
	var kill_count: int
	var kill_total: int
	var tic: int
	var game_over: bool
	var victory: bool
	# When true, stepping on an Exit cell only triggers victory once every
	# boss-tier monster (Baron, Cacodemon) on the map is dead.
	var boss_exit_gated: bool
	var difficulty: int
	var rng_seed: int
	var time_accum: float
	# -- Phase 1+ (original): sector-engine map (parallel to map). Built by new_game. --
	var sector_map: MapData
	# 2D BSP over the sector map (Godot-only divergence). Built once per level by
	# new_game; cast_frame walks it front-to-back instead of per-column ray-casting
	# (distance-independent visible-surface finding). Untyped to avoid a class-load
	# cycle (DoomBSP -> DoomTypes). null = fall back to the ray-walker.
	var bsp
	# Phase 8 (original): hitscan tracer ring. Fixed-size; index = tracer_count % MAX_TRACERS.
	# Slots with age_ms >= TRACER_LIFE_MS are skipped by the renderer.
	var tracers: Array # of Tracer
	var tracer_count: int

	# GameLogic.tick() mutates this object in place (matching the original's
	# `ref GameState`), but Hooks.useState's setter bails on a reference-equal
	# value (Object.is semantics, matching React) -- passing the SAME mutated
	# object back to the setter every tick would never trigger a re-render even
	# though its fields changed. snapshot() gives the setter a fresh top-level
	# identity to detect (nested objects stay shared by reference; only this
	# tick loop's own in-place mutation semantics needed the workaround, not a
	# deep clone of the whole state graph).
	func snapshot() -> GameState:
		var copy := GameState.new()
		copy.player = player
		copy.mobjs = mobjs
		copy.mobj_count = mobj_count
		copy.next_mobj_id = next_mobj_id
		copy.map = map
		copy.frame = frame
		copy.level = level
		copy.score = score
		copy.kill_count = kill_count
		copy.kill_total = kill_total
		copy.tic = tic
		copy.game_over = game_over
		copy.victory = victory
		copy.boss_exit_gated = boss_exit_gated
		copy.difficulty = difficulty
		copy.rng_seed = rng_seed
		copy.time_accum = time_accum
		copy.sector_map = sector_map
		copy.bsp = bsp
		copy.tracers = tracers
		copy.tracer_count = tracer_count
		return copy

class InputCmd extends RefCounted:
	var forward: bool
	var back: bool
	var strafe_left: bool
	var strafe_right: bool
	var turn_left: bool
	var turn_right: bool
	var attack: bool
	var use: bool
	var run: bool
	var weapon_switch: int
	var yaw_delta: float
	var pitch_delta: float
	# Phase 7 (original): vertical control.
	var jump: bool
	var crouch: bool

# ── Per-frame render data extensions (Phase 2+ in the original). Declared but
# appear vestigial/unused by the current renderer path -- ported for fidelity. ──

class WallSegV2 extends RefCounted:
	var top_px: float
	var bot_px: float
	var distance: float
	var wall_tex_idx: int
	var tex_u: float
	var tex_v_start: float # for variable-height segs
	var tex_v_end: float
	var light_level: int
	var hit_vertical: bool
	var is_sky: bool
	var kind: int
	var sector_id: int # sector this seg belongs to (for sprite ordering)

class FloorSpan extends RefCounted:
	var y: int # screen Y
	var left_col: int
	var right_col: int # inclusive
	var sector_id: int
	var is_ceiling: bool
	var light: int
	var tex_idx: int
	var distance_at_center: float # for shading

## Tunables (the original's `static class C`).
class C:
	const VIEW_W := 160
	const VIEW_H := 200
	const VIEWPORT_W := 800
	const VIEWPORT_H := 500
	const HUD_HEIGHT := 90
	const STRIP_W := 5.0 # VIEWPORT_W / VIEW_W

	const FOV := 1.0472
	const HALF_FOV := FOV / 2.0

	const MOVE_SPEED := 4.0
	const RUN_MULT := 1.6
	const STRAFE_SPEED := 3.5
	const TURN_SPEED := 2.6
	const MAX_PITCH := 200.0
	const MOUSE_YAW_SENS := 0.008
	const MOUSE_PITCH_SENS := 0.5
	const PLAYER_RADIUS := 0.28

	const COOLDOWN_FIST := 0.35
	const COOLDOWN_PISTOL := 0.32
	const COOLDOWN_SHOTGUN := 0.85
	const COOLDOWN_CHAIN := 0.10
	const COOLDOWN_ROCKET := 1.0
	const COOLDOWN_PLASMA := 0.10
	const COOLDOWN_BFG := 1.5

	const DMG_FIST := 8
	const DMG_PISTOL := 14
	const DMG_PELLET := 9
	const DMG_CHAIN := 11
	const DMG_ROCKET := 100
	const DMG_PLASMA := 18
	const DMG_BFG := 350
	const DMG_BARREL := 90

	const MAX_BULLETS := 200
	const MAX_SHELLS := 50
	const MAX_ROCKETS := 50
	const MAX_CELLS := 300

	const START_HEALTH := 100

	const HP_IMP := 60
	const HP_DEMON := 150
	const HP_BARON := 200
	const HP_CACO := 120
	const HP_LOST := 100
	const HP_ZOMBIE := 20
	const HP_SHOTG := 30
	const HP_BARREL := 20

	const DMG_IMP_MELEE := 6
	const DMG_IMP_BALL := 8
	const DMG_DEMON_BITE := 10
	const DMG_BARON_CLAW := 14
	const DMG_BARON_BALL := 24
	const DMG_CACO_BALL := 12
	const DMG_LOST_RAM := 7
	const DMG_ZOMBIE := 4
	const DMG_SHOTG := 5

	const SPEED_IMP := 1.7
	const SPEED_DEMON := 2.6
	const SPEED_BARON := 1.5
	const SPEED_CACO := 1.4
	const SPEED_LOST := 3.5
	const SPEED_ZOMBIE := 1.4
	const SPEED_SHOTG := 1.5

	const SPEED_IMPBALL := 9.0
	const SPEED_BARONBALL := 11.0
	const SPEED_CACOBALL := 9.0
	const SPEED_ROCKET := 14.0
	const SPEED_PLASMA := 22.0
	const SPEED_BFG := 20.0

	const SCORE_IMP := 100
	const SCORE_DEMON := 200
	const SCORE_BARON := 1500
	const SCORE_CACO := 600
	const SCORE_LOST := 80
	const SCORE_ZOMBIE := 60
	const SCORE_SHOTG := 90
	const SCORE_BARREL := 10

	const MAX_MOBJS := 256
	const SIGHT_RANGE := 18.0
	const MELEE_RANGE := 1.4

	const MAX_RAY := 32.0

	# -- Phase 1+ Sector engine constants (original) --
	const MAX_RAY_HOPS := 64 # portal traversal cap. Must cover MAX_RAY at the map's sector density:
	# E1M6/E1M1 are one-sector-per-tile, so a 32-unit diagonal ray crosses ~45 cell portals. At 16
	# the ray stopped BEFORE reaching walls >16 cells away -> those far walls never rendered, so
	# monsters/geometry behind them leaked through (the "see-through" until you walk close).
	const STEP_HEIGHT := 0.4 # max floor step the player can walk up
	const PLAYER_HEIGHT := 0.9 # feet->head
	const PLAYER_VIEW_HEIGHT := 0.6 # feet->eye
	const GRAVITY := 9.0 # units/s^2 for jump/fall
	const JUMP_VELOCITY := 7.0 # initial Z velocity on Jump
	const CROUCH_HEIGHT := 0.45
	const DOOR_OPEN_SPEED := 2.0 # units/sec ceiling lerp
	const DOOR_AUTO_CLOSE_DELAY := 4.0 # seconds
	const LIFT_SPEED := 1.5

	# Phase 8 (original): hitscan tracer.
	const MAX_TRACERS := 32
	const TRACER_LIFE_MS := 90.0
	const TRACER_THICKNESS_PX := 2.0
	const MUZZLE_FORWARD := 0.35 # offset from player along view
	const MUZZLE_BELOW_EYE := 0.12 # drop tracer below crosshair
