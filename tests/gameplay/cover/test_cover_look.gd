extends "res://tests/support/suite.gd"
## A room's cover look in one native call (perf plan C3, docs/milestones/perf-plan.md, "2. The crowd's
## per-tick work in C++"): `CoverRoom.look`, the native module's `BodyKernel.cover_look` when it is
## loaded, leaves a `CoverSight` with the bits its GDScript twin `CoverRoom.gd_look` leaves (the window,
## its offset, the count and every cell), on a seeded spread of rooms (one to three words a row, grid
## origins off the cells and below 0, danger sparse, dense and in patches) looked at from on, near and
## off their cover at every reach a look asks and more, by a sight cleared and by one left as the last
## look left it, each of the look's ways reached.
##
## Without the native module the GDScript is still checked (SPELLMERGE_NATIVE=required fails the
## comparison instead).

const BITS: int = 32
const CELL: float = float(CoverLayout.CELL)
const REACHES: Array[float] = [0.0, 7.5, 15.999, 16.0, 23.4, 32.0, 64.0, 100.0, -8.0]


func after_each() -> void:
	WallSlide.use_native(true)
	super.after_each()


func _native() -> bool:
	if not WallSlide.native_on() and OS.get_environment("SPELLMERGE_NATIVE") == "required":
		check(false, "SPELLMERGE_NATIVE=required, but the native module is not loaded (ci/build/native.sh)")
	return WallSlide.native_on()


## A room of `columns` by `rows` cover cells from world pixel `origin`, its danger cells those of
## `danger` (by cell, row by row), its bits laid as `CoverRoom._count_harming` lays them.
func _room(columns: int, rows: int, origin: Vector2, danger: PackedByteArray) -> CoverRoom:
	var layout := CoverLayout.new()
	layout.columns = columns
	layout.rows = rows
	layout.origin = origin
	layout.size = Vector2(columns, rows) * CELL
	layout.cells.resize(columns * rows)
	layout.cells.fill(1)
	var room := CoverRoom.new()
	room.layout = layout
	room._state.resize(columns * rows)
	var words: int = (columns + BITS - 1) / BITS
	room._words = words
	room._danger_bits.resize(rows * words)
	room._danger_bits.fill(0)
	room._danger_rows.resize(rows)
	room._danger_rows.fill(0)
	room._danger_columns.resize(columns)
	room._danger_columns.fill(0)
	room._row_bits.resize((rows + BITS - 1) / BITS + 1)
	room._row_bits.fill(0)
	room._column_bits.resize(words + 1)
	room._column_bits.fill(0)
	room._danger = 0
	for cell in columns * rows:
		if danger[cell] == 0:
			continue
		var column: int = cell % columns
		room._danger += 1
		room._danger_bits[(cell / columns) * words + column / BITS] |= 1 << (column % BITS)
		room._danger_rows[cell / columns] += 1
		room._danger_columns[column] += 1
	for row in rows:
		CoverRoom._set_bit(room._row_bits, row, room._danger_rows[row] > 0)
	for column in columns:
		CoverRoom._set_bit(room._column_bits, column, room._danger_columns[column] > 0)
	return room


## Danger in a room of `columns` by `rows` cells, by `how`: 0 none, 1 sparse, 2 dense, 3 in patches.
func _danger(rng: RandomNumberGenerator, columns: int, rows: int, how: int) -> PackedByteArray:
	var danger := PackedByteArray()
	danger.resize(columns * rows)
	danger.fill(0)
	match how:
		1:
			for n in maxi(columns * rows / 40, 1):
				danger[rng.randi_range(0, columns * rows - 1)] = 1
		2:
			for cell in columns * rows:
				danger[cell] = 1 if rng.randf() < 0.6 else 0
		3:
			for patch in rng.randi_range(1, 5):
				var cx: int = rng.randi_range(0, columns - 1)
				var cy: int = rng.randi_range(0, rows - 1)
				for y in range(maxi(cy - 3, 0), mini(cy + 4, rows)):
					for x in range(maxi(cx - 3, 0), mini(cx + 4, columns)):
						if rng.randf() < 0.8:
							danger[y * columns + x] = 1
	return danger


## Everything a look leaves in `sight`, to compare.
func _seen(sight: CoverSight) -> Array:
	return [sight.offset, sight.origin, sight.columns, sight.rows, sight.count, sight.cells().duplicate()]


func test_the_native_cover_look_gives_the_twins_bits() -> void:
	var native: bool = _native()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3103
	var sight := CoverSight.new()
	var twin := CoverSight.new()
	var looks: int = 0
	var differ: int = 0
	var off: int = 0
	var no_window: int = 0
	var empty: int = 0
	var marked: int = 0
	for room_n in 60:
		var columns: int = [3, 9, 31, 32, 33, 64, 70][room_n % 7]
		var rows: int = [2, 9, 31, 33, 40, 66][rng.randi_range(0, 5)]
		var origin := Vector2(rng.randf_range(-900.0, 900.0), rng.randf_range(-900.0, 900.0))
		if room_n % 4 == 0:
			origin = origin.snapped(Vector2(CELL, CELL))
		var room: CoverRoom = _room(columns, rows, origin, _danger(rng, columns, rows, 1 + room_n % 3))
		var extent := Vector2(columns, rows) * CELL
		for n in 160:
			# On the cover, its edges and just past them (off it).
			var at: Vector2 = origin + Vector2(rng.randf_range(-24.0, extent.x + 24.0), rng.randf_range(-24.0, extent.y + 24.0))
			if n % 10 == 0:
				at = origin + Vector2(rng.randi_range(0, columns), rng.randi_range(0, rows)) * CELL
			var reach: float = REACHES[n % REACHES.size()]
			if n % 3 != 0:
				# Two looks in three by a cleared sight (the cover area's); the rest by a sight left as the
				# last look left it, the same in both while they agree.
				sight.clear()
				twin.clear()
			room.look(at, reach, sight)
			room.gd_look(at, reach, twin)
			looks += 1
			if _seen(sight) != _seen(twin):
				differ += 1
				if differ <= 3:
					check(false, "room %d (%dx%d at %s), look at %s within %s: native %s, GDScript %s" % [room_n, columns, rows, origin, at, reach, _seen(sight), _seen(twin)])
			if n % 3 == 0:
				pass
			elif twin.columns == 0 and twin.offset == Vector2.ZERO:
				off += 1
			elif twin.columns == 0:
				no_window += 1
			elif twin.count == 0:
				empty += 1
			else:
				marked += 1
	check_equal(differ, 0, "every one of %d looks leaves the twin's bits (native %s)" % [looks, native])
	check(off > 0 and no_window > 0 and empty > 0 and marked > 0, "looks off the cover, with no window (a negative reach), with a window and nothing in it, and marking: %d, %d, %d, %d" % [off, no_window, empty, marked])
	print("cover looks (cleared sights): %d off the cover, %d no window, %d an empty window, %d marked" % [off, no_window, empty, marked])


## A point on the room's cover by the look's own check (the point less the grid's corner, in doubles)
## whose cell in the window (a Vector2's subtraction, in its floats) rounds past the last column: at a
## reach of 0 its window is clipped to nothing, so the sight is left with the room's offset and no
## window, natively as in GDScript.
func test_a_window_clipped_to_nothing_at_the_covers_edge() -> void:
	_native()
	var danger := PackedByteArray()
	danger.resize(9)
	danger.fill(1)
	# 0.00137 and 48.00137 as floats: 47.9999995 apart in doubles (column 2 of 3), 48 in floats (column 3).
	var origin := Vector2(0.0013699999544769526, 0.0)
	var at := Vector2(48.00136947631836, 8.0)
	check(at.x - origin.x < 48.0 and (at - origin).x >= 48.0, "the point is on the cover in doubles and past it in floats")
	var room: CoverRoom = _room(3, 3, origin, danger)
	for dirty in [false, true]:
		var sight := CoverSight.new()
		var twin := CoverSight.new()
		if dirty:
			# An empty window from an earlier look, left in both.
			room.look(origin + Vector2(8.0, 8.0), 0.0, sight)
			room.gd_look(origin + Vector2(8.0, 8.0), 0.0, twin)
			sight.clear()
			twin.clear()
			sight.columns = 5
			twin.columns = 5
		room.look(at, 0.0, sight)
		room.gd_look(at, 0.0, twin)
		check_equal(twin.columns, 0, "the GDScript opens no window")
		check_equal(twin.offset, origin, "the GDScript's sight has the room's offset")
		check_equal(_seen(sight), _seen(twin), "the native look leaves the GDScript's sight (an earlier window left: %s)" % dirty)


## A look with the module off is the GDScript's, and a look with nothing in danger leaves the sight
## as cleared.
func test_the_look_falls_back_and_a_quiet_room_leaves_nothing() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var danger: PackedByteArray = _danger(rng, 40, 20, 3)
	var room: CoverRoom = _room(40, 20, Vector2(-100.0, 36.0), danger)
	var sight := CoverSight.new()
	var twin := CoverSight.new()
	WallSlide.use_native(false)
	for n in 50:
		var at := Vector2(-100.0, 36.0) + Vector2(rng.randf_range(0.0, 640.0), rng.randf_range(0.0, 320.0))
		sight.clear()
		twin.clear()
		room.look(at, 32.0, sight)
		room.gd_look(at, 32.0, twin)
		check_equal(_seen(sight), _seen(twin), "native off: the look at %s is the GDScript's" % at)
	WallSlide.use_native(true)
	var quiet: CoverRoom = _room(40, 20, Vector2.ZERO, _danger(rng, 40, 20, 0))
	sight.clear()
	quiet.look(Vector2(100.0, 100.0), 64.0, sight)
	check_equal(_seen(sight), _seen(CoverSight.new()), "a room with nothing in danger leaves the sight as cleared")
