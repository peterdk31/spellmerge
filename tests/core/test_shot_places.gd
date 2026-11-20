extends "res://tests/support/suite.gd"
## Which places hold a shot (`ProjectileManager.shot_places`, the room life's waking: a shot keeps a
## room awake): the answer from the room grid's whole squares (`RoomGrid.whole_places`), in GDScript
## and in the native kernel (`ShotKernel.shot_places`, native/README.md), is the same as asking
## `place_at` for every live shot, byte for byte, in a world of rooms and bridges whose edges fall
## mid-square, an `over` place, rooms past the grid's 255th place, points on the edges and outside
## the bounds; and `whole_places` itself says what `place_at` says for every point it covers.
## The performance pass (2026-11-20): asked for every shot, `place_at` was most of Flow's tick.

const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const NativeScript := preload("res://core/native/native.gd")

const BOUNDS: Rect2 = Rect2(-40.5, -20.25, 3000.0, 2000.0)
const SHOTS: int = 3000
const SEED: int = 20261120


func _manager(native: bool) -> ManagerScript:
	var mgr: ManagerScript = own(ManagerScript.new()) as ManagerScript
	mgr.native = native
	root.add_child(mgr)
	mgr.set_cap(SHOTS + 16)
	mgr.set_bounds(BOUNDS)
	return mgr


## The world's places: rooms whose edges fall mid-square and on squares' edges, bridges `over` the
## rooms' lips, and two overlapping rooms (the first added holds their overlap).
func _lay_places(grid: RoomGrid, many: bool) -> void:
	grid.add_place(Rect2(0.0, 0.0, 640.0, 384.0))
	grid.add_place(Rect2(700.3, 13.7, 501.1, 333.3))
	grid.add_place(Rect2(600.0, 150.0, 140.0, 64.0), true)
	grid.add_place(Rect2(100.0, 500.0, 700.0, 500.0))
	grid.add_place(Rect2(400.0, 900.0, 600.0, 400.0))
	grid.add_place(Rect2(1500.25, 1500.75, 31.5, 33.0))
	if many:
		# Past 254 places a place is not in the squares' table: asked by its rectangle.
		for n in 260:
			grid.add_place(Rect2(1800.0 + float(n % 20) * 40.0, 1000.0 + float(n / 20) * 40.0, 36.0, 36.0))


## Shots at seeded points over the bounds and past them, some on rectangles' edges and squares'.
func _shots(mgr: ManagerScript, rng: RandomNumberGenerator) -> void:
	var edges: PackedVector2Array = [Vector2(640.0, 10.0), Vector2(0.0, 0.0), Vector2(700.3, 13.7), Vector2(1201.4, 200.0), Vector2(600.0, 150.0), Vector2(1500.25, 1500.75), Vector2(-40.5, -20.25), Vector2(2959.5, 1979.75)]
	for n in SHOTS:
		var at := Vector2(rng.randf_range(BOUNDS.position.x - 100.0, BOUNDS.end.x + 100.0), rng.randf_range(BOUNDS.position.y - 100.0, BOUNDS.end.y + 100.0))
		if n < edges.size():
			at = edges[n]
		elif n % 7 == 0:
			at = Vector2(floorf(at.x / 32.0) * 32.0 + BOUNDS.position.x, at.y)
		mgr.spawn(0, at, Vector2.ZERO, 10.0)


## What `shot_places` must say: `place_at` asked for every live shot.
func _asked(mgr: ManagerScript) -> PackedByteArray:
	var grid: RoomGrid = mgr.grid()
	var out := PackedByteArray()
	out.resize(grid.places())
	var alive: PackedByteArray = mgr.get(&"_alive")
	var pos: PackedVector2Array = mgr.get(&"_pos")
	for slot in int(mgr.get(&"_high")):
		if alive[slot] == 0:
			continue
		var place: int = grid.place_at(pos[slot])
		if place >= 0:
			out[place] = 1
	return out


func test_the_whole_squares_say_what_place_at_says() -> void:
	var mgr: ManagerScript = _manager(false)
	var grid: RoomGrid = mgr.grid()
	_lay_places(grid, true)
	var whole: PackedByteArray = grid.whole_places()
	check_equal(whole.size(), grid.place_columns() * grid.place_rows(), "a code a square")
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var wrong: int = 0
	var told: int = 0
	for y in grid.place_rows():
		for x in grid.place_columns():
			var code: int = whole[y * grid.place_columns() + x]
			if code == RoomGrid.WHOLE_ASK:
				continue
			told += 1
			var corner: Vector2 = grid.place_origin() + Vector2(x, y) * RoomGrid.PLACE_CELL
			for k in 5:
				var at: Vector2 = corner + Vector2(rng.randf() * RoomGrid.PLACE_CELL, rng.randf() * RoomGrid.PLACE_CELL)
				if k == 0:
					at = corner
				if floori((at.x - grid.place_origin().x) / RoomGrid.PLACE_CELL) != x or floori((at.y - grid.place_origin().y) / RoomGrid.PLACE_CELL) != y:
					continue
				if grid.place_at(at) != code - 1:
					wrong += 1
	check(told > 1000, "most squares are told (%d)" % told)
	check_equal(wrong, 0, "no point says otherwise")


func test_the_places_found_are_place_at_for_every_shot() -> void:
	for many: bool in [false, true]:
		var mgr: ManagerScript = _manager(false)
		_lay_places(mgr.grid(), many)
		var rng := RandomNumberGenerator.new()
		rng.seed = SEED
		_shots(mgr, rng)
		var out := PackedByteArray()
		mgr.shot_places(mgr.grid(), out)
		check_equal(out, _asked(mgr), "the GDScript's places (past 255: %s)" % many)
		check(out.count(1) >= 6, "shots stand in several places")


func test_the_kernel_finds_the_places_the_gdscript_finds() -> void:
	if not NativeScript.loaded():
		check(OS.get_environment("SPELLMERGE_NATIVE") != "required", "SPELLMERGE_NATIVE=required, but the native module is not loaded (ci/build/native.sh)")
		return
	for many: bool in [false, true]:
		for seed in [SEED, SEED + 1, SEED + 2]:
			var sides: Array[PackedByteArray] = []
			for native: bool in [false, true]:
				var mgr: ManagerScript = _manager(native)
				check_equal(mgr.is_native(), native, "the kernel is %s" % ("on" if native else "off"))
				_lay_places(mgr.grid(), many)
				var rng := RandomNumberGenerator.new()
				rng.seed = seed
				_shots(mgr, rng)
				var out := PackedByteArray()
				mgr.shot_places(mgr.grid(), out)
				check_equal(out, _asked(mgr), "%s: every shot's place (seed %d, past 255: %s)" % ["native" if native else "GDScript", seed, many])
				sides.append(out)
			check_equal(sides[1], sides[0], "the kernel and the GDScript agree (seed %d)" % seed)


## Shots just outside the bounds, before the first square (in no place), and a place in that first
## square: what a square is is worked out by rounding down, never toward zero.
func test_a_shot_before_the_first_square_is_in_none() -> void:
	if not NativeScript.loaded():
		check(OS.get_environment("SPELLMERGE_NATIVE") != "required", "SPELLMERGE_NATIVE=required, but the native module is not loaded (ci/build/native.sh)")
		return
	for native: bool in [false, true]:
		var mgr: ManagerScript = _manager(native)
		mgr.grid().add_place(Rect2(BOUNDS.position, Vector2(64.0, 64.0)))
		mgr.grid().add_place(Rect2(BOUNDS.position + Vector2(200.0, 200.0), Vector2(64.0, 64.0)))
		for at: Vector2 in [BOUNDS.position + Vector2(-5.0, 10.0), BOUNDS.position + Vector2(10.0, -3.0), BOUNDS.position + Vector2(220.0, 220.0)]:
			mgr.spawn(0, at, Vector2.ZERO, 10.0)
		var out := PackedByteArray()
		mgr.shot_places(mgr.grid(), out)
		check_equal(out, PackedByteArray([0, 1]), "%s: only the second room holds a shot" % ("native" if native else "GDScript"))


func test_a_world_with_no_places_has_none() -> void:
	var mgr: ManagerScript = _manager(true)
	mgr.spawn(0, Vector2(10.0, 10.0), Vector2.ZERO, 1.0)
	var out := PackedByteArray([1, 1])
	mgr.shot_places(mgr.grid(), out)
	check_equal(out.size(), 0, "no place, no byte")


## The squares' table is worked out again after the places change, after it was read (places
## cleared, the grid sized again, new places).
func test_the_squares_follow_the_places_after_they_change() -> void:
	var mgr: ManagerScript = _manager(true)
	var grid: RoomGrid = mgr.grid()
	grid.add_place(Rect2(0.0, 0.0, 640.0, 384.0))
	check_equal(grid.place_at(Vector2(100.0, 100.0)), 0, "the first room")
	check(grid.whole_places().has(1), "a square wholly in it")
	grid.clear_places()
	check_equal(grid.whole_places().size(), 0, "no places, no squares")
	grid.size_to(Rect2(-100.0, -100.0, 2000.0, 1000.0))
	grid.add_place(Rect2(1000.0, 200.0, 300.0, 300.0))
	var whole: PackedByteArray = grid.whole_places()
	var square: int = floori((100.0 + 100.0) / RoomGrid.PLACE_CELL) * grid.place_columns() + floori((100.0 + 100.0) / RoomGrid.PLACE_CELL)
	check_equal(whole[square], 0, "where the old room was is no place now")
	mgr.spawn(0, Vector2(100.0, 100.0), Vector2.ZERO, 10.0)
	mgr.spawn(0, Vector2(1100.0, 300.0), Vector2.ZERO, 10.0)
	var out := PackedByteArray()
	mgr.shot_places(grid, out)
	check_equal(out, PackedByteArray([1]), "the shot in the new room keeps it awake; the one where the old was, none")
