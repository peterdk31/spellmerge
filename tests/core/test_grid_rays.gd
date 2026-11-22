extends "res://tests/support/suite.gd"
## The room grid's rays in C++ (sim-native SN4, docs/milestones/sim-native.md): a path that crosses
## more than `RoomGrid.NATIVE_RAY_CELLS` cells is walked by the native module's `BodyKernel.wall_hit`
## and `way_hit` when it is loaded, and gives the bits of the grid's own walk (`wall_hit`, `_way_hit`):
## every query that asks them (`line_clear`, `clip_to_walls`, `sight_clear`, `ground_clear`,
## `walk_clear`, `clear_run`) on seeded rooms of walls, mouths, holes and the props' ground, short
## paths and long, a third of them on whole cells (the cells' edges met exactly), with the module on
## and off. Without the module the GDScript is checked alone (SPELLMERGE_NATIVE=required fails then).

const CELL: float = RoomGrid.WALL_CELL
const W: int = 48
const H: int = 36


func after_each() -> void:
	WallSlide.use_native(true)
	super.after_each()


## A room of `kind` (0 walls and mouths, 1 holes and the props' ground, 2 all of it, 3 none) from
## `origin`, seeded by `rng`.
func _room(rng: RandomNumberGenerator, kind: int, origin: Vector2) -> RoomGrid:
	var grid := RoomGrid.new()
	grid.size_to(Rect2(origin, Vector2(W * CELL, H * CELL)))
	if kind == 0 or kind == 2:
		for block in rng.randi_range(2, 12):
			var at := origin + Vector2(rng.randi_range(0, W - 1), rng.randi_range(0, H - 1)) * CELL
			var size := Vector2(rng.randi_range(1, 5), rng.randi_range(1, 5)) * CELL
			if block % 3 == 2:
				grid.add_mouth(Rect2(at, size))
			else:
				grid.add_wall(Rect2(at, size))
	if kind == 1 or kind == 2:
		var holes: Array[Rect2] = []
		for hole in rng.randi_range(1, 5):
			holes.append(Rect2(origin + Vector2(rng.randf_range(0.0, W * CELL), rng.randf_range(0.0, H * CELL)), Vector2(rng.randf_range(8.0, 80.0), rng.randf_range(8.0, 80.0))))
		grid.set_holes(holes)
		for prop in rng.randi_range(1, 4):
			grid.set_footprint(prop, origin + Vector2(rng.randf_range(0.0, W * CELL), rng.randf_range(0.0, H * CELL)), Vector2(rng.randf_range(8.0, 30.0), rng.randf_range(8.0, 30.0)), 0.0)
	return grid


## Every ray query of `grid` along `from`->`to`, as bytes.
func _asks(grid: RoomGrid, from: Vector2, to: Vector2) -> PackedByteArray:
	var answers: Array = [grid.wall_hit(from, to), grid.line_clear(from, to), grid.clip_to_walls(from, to), grid.sight_clear(from, to),
			grid.ground_clear(from, to), grid.walk_clear(from, to), grid.clear_run(from, to - from, from.distance_to(to))]
	return var_to_bytes(answers)


func test_the_native_rays_give_the_grids_bits() -> void:
	var native: bool = WallSlide.native_on()
	if not native:
		check(OS.get_environment("SPELLMERGE_NATIVE") != "required", "SPELLMERGE_NATIVE=required, but the native module is not loaded")
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261122
	var cases: int = 0
	var long_rays: int = 0
	var hits: int = 0
	# The long rays' kinds met, counted on the GDScript side: seen through a mouth, a walk stopped by a
	# hole or the props' ground, a pillar's ground on the way, a run cut short.
	var past_mouths: int = 0
	var walks_stopped: int = 0
	var grounds_met: int = 0
	var runs_cut: int = 0
	for room in 40:
		var origin := Vector2(rng.randf_range(-50.0, 50.0), rng.randf_range(-50.0, 50.0))
		var grid: RoomGrid = _room(rng, room % 4, origin)
		for n in 200:
			var from := origin + Vector2(rng.randf_range(-20.0, W * CELL + 20.0), rng.randf_range(-20.0, H * CELL + 20.0))
			var length: float = [6.0, 20.0, 60.0, 200.0, 600.0][n % 5]
			var to := from + Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * length
			if n % 3 == 0:
				# On whole cells, and straight along a row or a column now and then.
				from = ((from - origin) / CELL).round() * CELL + origin
				to = ((to - origin) / CELL).round() * CELL + origin
				if n % 6 == 0:
					to.y = from.y
			WallSlide.use_native(false)
			var twin: PackedByteArray = _asks(grid, from, to)
			if grid.wall_hit(from, to) >= 0.0:
				hits += 1
			if grid.sight_clear(from, to) and not grid.line_clear(from, to):
				past_mouths += 1
			if not grid.walk_clear(from, to):
				walks_stopped += 1
			if not grid.ground_clear(from, to):
				grounds_met += 1
			if from != to and grid.clear_run(from, to - from, from.distance_to(to)) < from.distance_to(to):
				runs_cut += 1
			WallSlide.use_native(true)
			if native:
				var walked: PackedByteArray = _asks(grid, from, to)
				if walked != twin:
					check(false, "room %d case %d: GDScript %s, native %s (from %s to %s)" % [room, n, bytes_to_var(twin), bytes_to_var(walked), from, to])
					return
			cases += 1
			var start: Vector2 = (from - origin) / CELL
			var end: Vector2 = (to - origin) / CELL
			if absi(floori(end.x) - floori(start.x)) + absi(floori(end.y) - floori(start.y)) > RoomGrid.NATIVE_RAY_CELLS:
				long_rays += 1
	check(cases == 8000, "every case compared: %d" % cases)
	check(long_rays > 2000 and hits > 300, "long rays handed to the kernel (%d) and walls met (%d)" % [long_rays, hits])
	check(past_mouths > 20 and walks_stopped > 100 and grounds_met > 20 and runs_cut > 100, "seen past a mouth (%d), walks stopped (%d), ground met (%d), runs cut short (%d)" % [past_mouths, walks_stopped, grounds_met, runs_cut])
