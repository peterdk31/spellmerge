extends "res://tests/support/suite.gd"
## A body's whole walk over the room grid in one call (sim-native SN1, docs/milestones/sim-native.md):
## `RoomGrid.walk_body`, the native module's `BodyKernel.walk` when it is loaded, gives the bits of its
## GDScript twin `RoomGrid.gd_walk_body` (the slides of `Actor.move`, with the holes at its end looked
## at) on a seeded spread of rooms of walls, mouths, holes and the props' ground, every branch of the
## walk reached; and the twin answers as the grid's own `slide_body`, `is_hole` and `touches_hole` do.
##
## Without the native module the GDScript is still checked (SPELLMERGE_NATIVE=required fails the
## comparison instead).

const CELL: float = RoomGrid.WALL_CELL
const W: int = 40
const H: int = 30
## The margin the walk's end is looked at for holes within (`Actor.move`'s).
const MARGIN: float = HoleRules.GROUND_MARGIN


func after_each() -> void:
	WallSlide.use_native(true)
	super.after_each()


## Whether WallSlide runs the native kernel (a failure when the module is required but not loaded).
func _native() -> bool:
	if not WallSlide.native_on() and OS.get_environment("SPELLMERGE_NATIVE") == "required":
		check(false, "SPELLMERGE_NATIVE=required, but the native module is not loaded (ci/build/native.sh)")
	return WallSlide.native_on()


## A room of `kind` (0 open, 1 blocks and mouths, 2 holes, 3 blocks, holes and the props' ground,
## 4 holes and the props' ground with no walls, 5 the props' ground alone),
## seeded by `rng`, its corner at `origin`.
func _room(rng: RandomNumberGenerator, kind: int, origin: Vector2) -> RoomGrid:
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
	return grid


## The twin's answer worked out by the grid's own calls: main's `Actor._move_over_holes` and the
## holes `_check_ground` asked of, as they stood before SN1 (`origin/main:gameplay/actor/actor.gd`),
## kept here frozen. How the actor uses the answer is `tests/gameplay/actor/test_move_holes.gd`'s and
## `test_fall.gd`'s, and the game's `tick_hash.gd` compare.
func _by_the_grid(grid: RoomGrid, from: Vector2, motion: Vector2, crossed: Vector2, radius: float, through: bool, reach: float) -> Vector3:
	if not grid.has_holes():
		var slid: Vector2 = grid.slide_body(from, motion, radius, false, through)
		return Vector3(slid.x, slid.y, 0.0)
	var at: Vector2 = from
	if crossed != Vector2.ZERO:
		at = grid.slide_body(from, crossed, radius, true, through)
	var walk: Vector2 = motion - crossed
	var to: Vector2
	if walk == Vector2.ZERO and crossed != Vector2.ZERO:
		to = at
	elif grid.is_hole(at):
		to = grid.slide_body(at, walk, radius, true, through)
	elif crossed != Vector2.ZERO and grid.touches_hole(at, radius):
		var walked: Vector2 = grid.slide_body(at, walk, radius, true, through)
		to = at if grid.is_hole(walked) else walked
	else:
		to = grid.slide_body(at, walk, radius, false, through)
	var found: int = RoomGrid.WALKED_OVER_HOLE if grid.is_hole(to) else (RoomGrid.WALKED_NEAR_HOLE if grid.touches_hole(to, reach) else 0)
	return Vector3(to.x, to.y, float(found))


## Which of the walk's branches a case takes (the twin's order), for the count of branches reached.
func _branch(grid: RoomGrid, from: Vector2, motion: Vector2, crossed: Vector2, radius: float, through: bool) -> String:
	if not grid.has_holes():
		return "no holes"
	var at: Vector2 = from if crossed == Vector2.ZERO else grid.slide_body(from, crossed, radius, true, through)
	if motion - crossed == Vector2.ZERO and crossed != Vector2.ZERO:
		return "crossed only"
	if grid.is_hole(at):
		return "from over a hole"
	if crossed != Vector2.ZERO and grid.touches_hole(at, radius):
		var walked: Vector2 = grid.slide_body(at, motion - crossed, radius, true, through)
		return "at a lip, dropped" if grid.is_hole(walked) else "at a lip, walked"
	return "walk"


func test_the_native_walk_gives_the_twins_bits_on_every_branch() -> void:
	var native: bool = _native()
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261122
	var cases: int = 0
	var branches: Dictionary = {}
	var found: Dictionary = {}
	for room in 48:
		var origin := Vector2(rng.randf_range(-60.0, 60.0), rng.randf_range(-60.0, 60.0))
		var grid: RoomGrid = _room(rng, room % 6, origin)
		var moves: Array[Array] = []
		for n in 250:
			var from: Vector2 = origin + Vector2(rng.randf_range(-16.0, W * CELL + 16.0), rng.randf_range(-16.0, H * CELL + 16.0))
			var motion: Vector2 = Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * rng.randf_range(0.0, 30.0) if n % 6 != 0 else Vector2.ZERO
			if n % 9 == 0:
				motion *= 12.0
			# What crosses: none, all of the move, or a share of it (a push beside a walk).
			var crossed: Vector2 = [Vector2.ZERO, motion, motion * 0.5, Vector2(rng.randf_range(-6.0, 6.0), rng.randf_range(-6.0, 6.0))][n % 4]
			var radius: float = [0.0, 3.0, 5.0, 6.0, 7.5, 12.0][n % 6]
			if n % 3 == 2:
				# On the quarter pixels with whole radii: a circle that just touches a cell, an edge met
				# exactly (the boundaries of every comparison).
				from = ((from - origin) * 4.0).round() / 4.0 + origin
				motion = (motion * 4.0).round() / 4.0
				crossed = (crossed * 4.0).round() / 4.0
				radius = roundf(radius)
			moves.append([from, motion, crossed, radius, n % 2 == 1, radius + MARGIN])
		# The reference: the twin with GDScript all the way down (its slides `WallSlide.gd_slide`).
		WallSlide.use_native(false)
		var twins: Array[Vector3] = []
		for n in moves.size():
			var m: Array = moves[n]
			var twin: Vector3 = grid.gd_walk_body(m[0], m[1], m[2], m[3], m[4], m[5])
			var expected: Vector3 = _by_the_grid(grid, m[0], m[1], m[2], m[3], m[4], m[5])
			if var_to_bytes(twin) != var_to_bytes(expected):
				check(false, "room %d case %d: the twin %s, the grid's calls %s" % [room, n, twin, expected])
				return
			twins.append(twin)
			var branch: String = _branch(grid, m[0], m[1], m[2], m[3], m[4])
			branches[branch] = int(branches.get(branch, 0)) + 1
			found[int(twin.z)] = int(found.get(int(twin.z), 0)) + 1
		WallSlide.use_native(true)
		for n in moves.size():
			var m: Array = moves[n]
			if native:
				var walked: Vector3 = grid.walk_body(m[0], m[1], m[2], m[3], m[4], m[5])
				if var_to_bytes(walked) != var_to_bytes(twins[n]):
					check(false, "room %d case %d: GDScript %s, native %s (from %s by %s, crossing %s, radius %s, past mouths %s)" % [room, n, twins[n], walked, m[0], m[1], m[2], m[3], m[4]])
					return
			cases += 1
	check(cases == 12000, "every case compared: %d" % cases)
	for branch in ["no holes", "crossed only", "from over a hole", "at a lip, dropped", "at a lip, walked", "walk"]:
		check(int(branches.get(branch, 0)) >= 10, "the branch '%s' is reached: %s" % [branch, branches])
	for flag in [0, RoomGrid.WALKED_OVER_HOLE, RoomGrid.WALKED_NEAR_HOLE]:
		check(int(found.get(flag, 0)) >= 10, "the end's flag %d is reached: %s" % [flag, found])


func test_with_nothing_laid_the_walk_goes_the_whole_way() -> void:
	var grid := RoomGrid.new()
	grid.size_to(Rect2(0.0, 0.0, W * CELL, H * CELL))
	var walked: Vector3 = grid.walk_body(Vector2(50.0, 60.0), Vector2(7.25, -3.5), Vector2.ZERO, 6.0, false, 10.0)
	check_equal(walked, Vector3(57.25, 56.5, 0.0), "the whole way, no holes looked at")
	WallSlide.use_native(false)
	check_equal(grid.walk_body(Vector2(50.0, 60.0), Vector2(7.25, -3.5), Vector2.ZERO, 6.0, false, 10.0), walked, "the GDScript says the same")


func test_a_walk_stops_at_a_lip_and_its_end_is_near_the_hole() -> void:
	var grid := RoomGrid.new()
	grid.size_to(Rect2(0.0, 0.0, W * CELL, H * CELL))
	var holes: Array[Rect2] = [Rect2(160.0, 0.0, 40.0, H * CELL)]
	grid.set_holes(holes)
	for native in [true, false]:
		WallSlide.use_native(native)
		var walked: Vector3 = grid.walk_body(Vector2(100.0, 100.0), Vector2(80.0, 0.0), Vector2.ZERO, 6.0, false, 6.0 + MARGIN)
		check_equal(Vector2(walked.x, walked.y), Vector2(154.0, 100.0), "the walk stops its radius short of the lip (native %s)" % native)
		check_equal(int(walked.z), RoomGrid.WALKED_NEAR_HOLE, "and its end is within the margin of the hole (native %s)" % native)
		var dashed: Vector3 = grid.walk_body(Vector2(100.0, 100.0), Vector2(80.0, 0.0), Vector2(80.0, 0.0), 6.0, false, 6.0 + MARGIN)
		check_equal(Vector2(dashed.x, dashed.y), Vector2(180.0, 100.0), "a dash crosses (native %s)" % native)
		check_equal(int(dashed.z), RoomGrid.WALKED_OVER_HOLE, "and ends over the hole (native %s)" % native)
