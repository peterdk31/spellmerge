extends "res://tests/support/suite.gd"
## A body's move and its room in one call (perf plan C2, docs/milestones/perf-plan.md, "2. The crowd's
## per-tick work in C++"): `RoomGrid.walk_place`, the native module's `BodyKernel.walk_place` when it
## is loaded, gives the bits of its GDScript twin `RoomGrid.gd_walk_place`, and the twin answers as
## `walk_body` and `place_at` do, on a seeded spread of rooms of walls, mouths, holes, the props'
## ground and places (none, side by side, overlapping, an `over` one, edges off the squares), each of
## the place lookup's ways reached.
##
## Without the native module the GDScript is still checked (SPELLMERGE_NATIVE=required fails the
## comparison instead).

const CELL: float = RoomGrid.WALL_CELL
const W: int = 40
const H: int = 30
const MARGIN: float = HoleRules.GROUND_MARGIN


func after_each() -> void:
	WallSlide.use_native(true)
	super.after_each()


func _native() -> bool:
	if not WallSlide.native_on() and OS.get_environment("SPELLMERGE_NATIVE") == "required":
		check(false, "SPELLMERGE_NATIVE=required, but the native module is not loaded (ci/build/native.sh)")
	return WallSlide.native_on()


## A room of walls and mouths (`kind` 1 and 3), holes (2 to 4) and the props' ground (3 to 5), or
## none (0), with `places` places (overlapping ones and an `over` one among them), at `origin`.
func _room(rng: RandomNumberGenerator, kind: int, places: int, origin: Vector2) -> RoomGrid:
	var grid := RoomGrid.new()
	grid.size_to(Rect2(origin, Vector2(W * CELL, H * CELL)))
	if kind == 1 or kind == 3:
		for block in rng.randi_range(1, 10):
			var at := origin + Vector2(rng.randi_range(0, W - 1), rng.randi_range(0, H - 1)) * CELL
			var size := Vector2(rng.randi_range(1, 6), rng.randi_range(1, 6)) * CELL
			if block % 3 == 2:
				grid.add_mouth(Rect2(at, size))
			else:
				grid.add_wall(Rect2(at, size))
	if kind >= 2 and kind <= 4:
		var holes: Array[Rect2] = []
		for hole in rng.randi_range(1, 6):
			var at := origin + Vector2(rng.randf_range(0.0, W * CELL), rng.randf_range(0.0, H * CELL))
			holes.append(Rect2(at, Vector2(rng.randf_range(4.0, 90.0), rng.randf_range(4.0, 90.0))))
		grid.set_holes(holes)
	if kind >= 3:
		for prop in rng.randi_range(1, 4):
			var centre := origin + Vector2(rng.randf_range(0.0, W * CELL), rng.randf_range(0.0, H * CELL))
			grid.set_footprint(prop, centre, Vector2(rng.randf_range(8.0, 30.0), rng.randf_range(8.0, 30.0)) if prop % 2 == 0 else Vector2.ZERO, rng.randf_range(4.0, 14.0))
	for place in places:
		# Edges off the place squares (a square cut by an edge), some overlapping, the last one `over`.
		var at := origin + Vector2(rng.randf_range(-40.0, W * CELL * 0.7), rng.randf_range(-40.0, H * CELL * 0.7))
		grid.add_place(Rect2(at, Vector2(rng.randf_range(60.0, W * CELL * 0.6), rng.randf_range(60.0, H * CELL * 0.6))), place == places - 1 and place > 0)
	return grid


func test_the_native_walk_and_place_give_the_twins_bits() -> void:
	var native: bool = _native()
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261128
	var cases: int = 0
	var ways: Dictionary = {}
	for room in 36:
		var origin := Vector2(rng.randf_range(-60.0, 60.0), rng.randf_range(-60.0, 60.0))
		var grid: RoomGrid = _room(rng, room % 6, [0, 1, 3, 5][room % 4], origin)
		var moves: Array[Array] = []
		for n in 200:
			var from: Vector2 = origin + Vector2(rng.randf_range(-48.0, W * CELL + 48.0), rng.randf_range(-48.0, H * CELL + 48.0))
			var motion: Vector2 = Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * rng.randf_range(0.0, 30.0) if n % 6 != 0 else Vector2.ZERO
			var crossed: Vector2 = [Vector2.ZERO, motion, motion * 0.5, Vector2(rng.randf_range(-6.0, 6.0), rng.randf_range(-6.0, 6.0))][n % 4]
			var radius: float = [0.0, 3.0, 5.0, 6.0, 7.5, 12.0][n % 6]
			if n % 3 == 2:
				# On whole and quarter pixels: an end on a place's edge or a square's (the boundaries).
				from = ((from - origin) * 4.0).round() / 4.0 + origin
				motion = (motion * 4.0).round() / 4.0
				crossed = (crossed * 4.0).round() / 4.0
				radius = roundf(radius)
			moves.append([from, motion, crossed, radius, n % 2 == 1, radius + MARGIN])
		# The reference: GDScript all the way down.
		WallSlide.use_native(false)
		var twins: Array[Vector4] = []
		for n in moves.size():
			var m: Array = moves[n]
			var twin: Vector4 = grid.gd_walk_place(m[0], m[1], m[2], m[3], m[4], m[5])
			var walked: Vector3 = grid.walk_body(m[0], m[1], m[2], m[3], m[4], m[5])
			var expected := Vector4(walked.x, walked.y, walked.z, float(grid.place_at(Vector2(walked.x, walked.y))))
			if var_to_bytes(twin) != var_to_bytes(expected):
				check(false, "room %d case %d: the twin %s, walk_body and place_at %s" % [room, n, twin, expected])
				return
			twins.append(twin)
			var way: String = "no places" if grid.places() == 0 else ("no place" if int(twin.w) == RoomGrid.NO_PLACE else "a place")
			ways[way] = int(ways.get(way, 0)) + 1
		WallSlide.use_native(true)
		for n in moves.size():
			var m: Array = moves[n]
			if native:
				var got: Vector4 = grid.walk_place(m[0], m[1], m[2], m[3], m[4], m[5])
				if var_to_bytes(got) != var_to_bytes(twins[n]):
					check(false, "room %d case %d: GDScript %s, native %s (from %s by %s, crossing %s, radius %s, past mouths %s)" % [room, n, twins[n], got, m[0], m[1], m[2], m[3], m[4]])
					return
			cases += 1
	check(cases == 7200, "every case compared: %d" % cases)
	for way in ["no places", "no place", "a place"]:
		check(int(ways.get(way, 0)) >= 50, "the place lookup's '%s' is reached: %s" % [way, ways])


func test_an_over_place_and_the_place_under_it() -> void:
	var grid := RoomGrid.new()
	grid.size_to(Rect2(0.0, 0.0, 640.0, 360.0))
	var under: int = grid.add_place(Rect2(0.0, 0.0, 400.0, 360.0))
	var over: int = grid.add_place(Rect2(100.0, 100.0, 50.0, 30.0), true)
	for native in [false, true]:
		WallSlide.use_native(native)
		check_equal(int(grid.walk_place(Vector2(90.0, 110.0), Vector2(20.0, 0.0), Vector2.ZERO, 4.0, false, 8.0).w), over, "into the over place (native %s)" % native)
		check_equal(int(grid.walk_place(Vector2(90.0, 110.0), Vector2(-20.0, 0.0), Vector2.ZERO, 4.0, false, 8.0).w), under, "the place under it (native %s)" % native)
		check_equal(int(grid.walk_place(Vector2(390.0, 110.0), Vector2(30.0, 0.0), Vector2.ZERO, 4.0, false, 8.0).w), RoomGrid.NO_PLACE, "out of every place (native %s)" % native)
		check_equal(grid.walk_place(Vector2(390.0, 110.0), Vector2(30.0, 0.0), Vector2.ZERO, 4.0, false, 8.0), Vector4(420.0, 110.0, 0.0, -1.0), "with nothing laid, the whole way (native %s)" % native)
