extends "res://tests/support/suite.gd"
## A room's summaries of its cells (gameplay/cover/cover_room.gd; the performance pass, 2026-11-28):
## where bodies are given something (`_gives`, read by `giving_cell`) and where the AI's look marks
## danger (`_danger_bits` and the rows and columns that hold any, read by `look`) are kept as cells
## move. Each is checked against the cells' own states read one by one (`cover_state_at`), as the
## area read them before, while a fire burns, spreads, is put out and goes to ash in a room wider than
## a word of bits (two words a row, BITS each) laid off the world's origin, and after a restore.
const GRASS: CoverKind = preload("res://tests/core/fixtures/cover_content/cover/test_grass/test_grass.tres")
const DT: float = 1.0 / 60.0
const COLUMNS: int = 45
const ROWS: int = 37
const ORIGIN: Vector2 = Vector2(-200.0, 72.0)
const CELL: float = float(CoverLayout.CELL)


## A room of COLUMNS by ROWS cells of the test grass from ORIGIN, with a few bare cells.
func _room() -> CoverRoom:
	var layout := CoverLayout.new()
	layout.columns = COLUMNS
	layout.rows = ROWS
	layout.origin = ORIGIN
	layout.size = Vector2(COLUMNS, ROWS) * CELL
	layout.kinds = [GRASS] as Array[CoverKind]
	layout.cells.resize(COLUMNS * ROWS)
	layout.cells.fill(1)
	for cell in range(0, COLUMNS * ROWS, 7):
		layout.cells[cell] = 0
	var room := CoverRoom.new()
	room.bind(layout)
	return room


## The middle of cell (x, y), in world pixels.
func _middle(x: int, y: int) -> Vector2:
	return ORIGIN + Vector2((float(x) + 0.5) * CELL, (float(y) + 0.5) * CELL)


## What is wrong with `room`'s summaries: every cell's `giving_cell`, and looks round many points
## (cell middles, corners and edges, off the room), against the cells' states.
func _wrong(room: CoverRoom) -> PackedStringArray:
	var wrong := PackedStringArray()
	var any_danger: bool = false
	for y in ROWS:
		for x in COLUMNS:
			var cell: int = y * COLUMNS + x
			var state: CoverState = room.cover_state_at(cell)
			var gives: bool = state != null and state.gives()
			any_danger = any_danger or (state != null and state.is_danger())
			var at: Vector2 = _middle(x, y)
			if room.giving_cell(at) != (cell if gives else -1):
				wrong.append("giving_cell at (%d, %d): %d, its state gives: %s" % [x, y, room.giving_cell(at), gives])
	check_equal(room.giving_cell(ORIGIN - Vector2(1.0, 1.0)), CoverRoom.OFF, "off the room: OFF")
	var sight := CoverSight.new()
	for y in range(-2, ROWS + 2, 3):
		for x in range(-2, COLUMNS + 2, 2):
			for nudge: Vector2 in [Vector2(0.5, 0.5), Vector2(0.0, 0.0), Vector2(0.999, 0.25)]:
				var at: Vector2 = ORIGIN + (Vector2(x, y) + nudge) * CELL
				for reach: float in [16.0, 40.0, 64.0, 200.0]:
					sight.clear()
					room.look(at, reach, sight)
					var expected: int = _expected_marks(room, at, reach, any_danger, sight)
					if expected < 0:
						wrong.append("look at %s reach %.0f: a cell marked that is not danger, or one missed" % [at, reach])
					elif sight.count != expected:
						wrong.append("look at %s reach %.0f: %d marked, %d danger" % [at, reach, sight.count, expected])
	return wrong


## How many cells the look round `at` should mark (the window the sight opened, every danger cell of
## it), -1 when `sight` marks one that is not danger or misses one; checks the window opens as before.
func _expected_marks(room: CoverRoom, at: Vector2, reach: float, any_danger: bool, sight: CoverSight) -> int:
	var held: bool = room.holds(at)
	var reference := CoverSight.new()
	if not held or not any_danger or not reference.open(at, reach, COLUMNS, ROWS, ORIGIN):
		return 0 if sight.columns == 0 and sight.count == 0 else -1
	if sight.origin != reference.origin or sight.columns != reference.columns or sight.rows != reference.rows:
		return -1
	var count: int = 0
	for y in range(reference.origin.y, reference.origin.y + reference.rows):
		for x in range(reference.origin.x, reference.origin.x + reference.columns):
			var state: CoverState = room.cover_state_at(y * COLUMNS + x)
			var danger: bool = state != null and state.is_danger()
			if danger != sight.harms_cell(Vector2i(x, y)):
				return -1
			count += int(danger)
	return count


func test_the_summaries_follow_the_cells_as_a_fire_burns_out() -> void:
	var room := _room()
	var sim := Sim.new()
	check(_wrong(room).is_empty(), "at rest: nothing gives, nothing marked")
	# Fires across both words of each row and at the room's edges.
	for at: Vector2i in [Vector2i(3, 4), Vector2i(31, 10), Vector2i(32, 10), Vector2i(44, 36), Vector2i(0, 0), Vector2i(20, 30)]:
		room.touch(&"fire", _middle(at.x, at.y), 20.0)
	var checked: int = 0
	var burned: bool = false
	for step in 240:
		room.step_cells(DT, sim, 0)
		if step == 30:
			room.touch(&"frost", _middle(32, 10), 40.0)
		if step % 40 == 0:
			var wrong := _wrong(room)
			check(wrong.is_empty(), "step %d: %s" % [step, "; ".join(wrong.slice(0, 3))])
			checked += 1
		burned = burned or room.harms_nobody() == false
	check(burned, "the fire burned")
	check_equal(checked, 6, "looked at as it burned")


func test_the_summaries_are_worked_out_again_after_a_restore() -> void:
	var room := _room()
	var sim := Sim.new()
	room.touch(&"fire", _middle(33, 5), 40.0)
	for step in 20:
		room.step_cells(DT, sim, 0)
	# A restore writes the state alone (Snapshot); its rebuild works the rest out again (`retell`).
	var restored := _room()
	restored._state = room._state.duplicate()
	restored._age = room._age.duplicate()
	restored._active = room._active.duplicate()
	restored._active_actor = room._active_actor.duplicate()
	restored._active_tag = room._active_tag.duplicate()
	restored.retell()
	check(not restored.harms_nobody(), "the restored fire harms")
	var wrong := _wrong(restored)
	check(wrong.is_empty(), "; ".join(wrong.slice(0, 3)))
