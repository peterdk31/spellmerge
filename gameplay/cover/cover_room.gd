class_name CoverRoom
extends RefCounted
## One room's ground cover in play (connected biomes CB3b; the cover area's, gameplay/cover/cover.gd):
## each cell of its layout (`CoverLayout`, laid at the room's place in the world and mirrored with
## it) in a state of its kind, the cells not at rest, and its own roll counter, so a room's fire plays
## the same whatever burns in another room. The cover area keeps one a piece of the world (by its
## number: a row run's one room, a biome's rooms then bridges), steps it only while its place is
## awake, and hands it the touches and the bodies; the rules of a step are here (README, "The step").
##
## **State:** each cell's state and seconds in it, the active cells, the rolls made. **Derived:** the
## layout and its kinds' move tables (`bind`, from `room_built`; again after a restore), what is worked
## out from the state with them (`_harming`), and what this machine's view was told (`_said`).

const CoverMoves := preload("res://gameplay/cover/cover_moves.gd")
const EventsScript := preload("res://core/events/events.gd")

## The purpose of a spread's roll (`Sim.chance`).
const SPREAD: StringName = &"cover_spread"
## The four neighbours a spread touches, as steps in cells: up, right, down, left.
const NEIGHBOURS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
## A spread's roll key is its cell's and direction's (`cell * 4 + direction`) plus the room's number
## shifted past them, so two rooms' rolls never repeat each other (the first room's are its number
## 0's: a row run's rolls are as they were). Rooms below 512, cells below a million.
const ROOM_KEY_SHIFT: int = 22

## Not state: the layout and its tables (bound from `room_built`), what is worked out from the state
## with them, what this machine's view was told, and scratch emptied within a step.
const DERIVED: Array[StringName] = [
	&"layout", &"_moves", &"_rest_harms", &"_harming", &"_harming_rows", &"_said",
	&"_changed_cells", &"_changed_states", &"_spread_cells", &"_spread_by",
]

## The room's cover at its place (null before it is bound).
var layout: CoverLayout = null
var _moves: CoverMoves = null
## True when a kind with cells in the room gives a status at rest (cobwebs).
var _rest_harms: bool = false
## How many cells are in a state that gives a status now, and the same count a row (GC7).
var _harming: int = 0
var _harming_rows: PackedInt32Array = PackedInt32Array()
## Each cell's state as this machine's view was last told (`cover_changed`).
var _said: PackedByteArray = PackedByteArray()
## This tick's changes, sent once (`flush`).
var _changed_cells: PackedInt32Array = PackedInt32Array()
var _changed_states: PackedInt32Array = PackedInt32Array()
## Scratch: the spreads rolled this step.
var _spread_cells: PackedInt32Array = PackedInt32Array()
var _spread_by: PackedInt32Array = PackedInt32Array()

## Each cell's state (its index in its kind's states; 0 at rest) and its seconds in it, the
## layout's size, or empty for a room with no cover.
var _state: PackedByteArray = PackedByteArray()
var _age: PackedFloat32Array = PackedFloat32Array()
## The cells not at rest, in cell order.
var _active: PackedInt32Array = PackedInt32Array()
## The rolls made (the counter of `sim.chance`).
var _rolls: int = 0


## Bind the room's cover laid as `laid` (its kinds' tables worked out with it). The state is only
## sized, at rest, when it is empty; then the view is told every cell not at rest (at the next `flush`).
func bind(laid: CoverLayout) -> void:
	layout = laid
	_moves = CoverMoves.of(laid.kinds)
	# Only a kind with a cell in this room counts (the layout holds every kind given, whatever its biome).
	_rest_harms = false
	for kind in laid.kinds:
		if not kind.states.is_empty() and kind.states[0] != null and kind.states[0].status != &"" and laid.count(kind.id) > 0:
			_rest_harms = true
	if _state.is_empty():
		_size_at_rest()
	_count_harming()
	_said.resize(laid.cells.size())
	_said.fill(0)
	tell_all()


## No layout any more (a piece the world laid now lacks): it plays nothing until bound again.
func unbind() -> void:
	layout = null
	_moves = null
	_said.resize(0)


## The room starts in play: every cell at rest.
func rest() -> void:
	_size_at_rest()
	_active.resize(0)
	_count_harming()
	tell_all()


## After a snapshot was restored: what is worked out from the state, and the view told every cell
## whose state it was told otherwise.
func retell() -> void:
	_count_harming()
	tell_all()


## True when the room has cover to play, its state the layout's size.
func plays() -> bool:
	return layout != null and not _state.is_empty() and _state.size() == layout.cells.size()


## True when `at` (world pixels) is on the room's cover grid.
func holds(at: Vector2) -> bool:
	return plays() and layout.cell_of(at) >= 0


## True when a body might be harmed in it now: a cell out of rest, or a kind harming at rest.
func may_harm() -> bool:
	return _rest_harms or not _active.is_empty()


# --- Read ------------------------------------------------------------------------------

func state_at(cell: int) -> int:
	return _state[cell] if cell >= 0 and cell < _state.size() else 0


func cover_state_at(cell: int) -> CoverState:
	if layout == null:
		return null
	var kind: CoverKind = layout.kind_at(cell)
	return kind.states[state_at(cell)] if kind != null else null


func age_at(cell: int) -> float:
	return _age[cell] if cell >= 0 and cell < _age.size() else 0.0


func active_cells() -> PackedInt32Array:
	return _active


func rolls() -> int:
	return _rolls


## Fill `sight` (cleared by the caller) with where the room's floor within `reach` of `at` would harm a
## body (the cover area's `look`). Allocates nothing.
func look(at: Vector2, reach: float, sight: CoverSight) -> void:
	if not plays() or _harming == 0:
		return
	if not sight.open(at, reach, layout.columns, layout.rows, layout.origin):
		return
	var cells: PackedByteArray = layout.cells
	var harms_table: PackedByteArray = _moves.harms_table
	var width: int = _moves.width
	for y in range(sight.origin.y, sight.origin.y + sight.rows):
		if _harming_rows[y] == 0:
			continue
		for x in range(sight.origin.x, sight.origin.x + sight.columns):
			var cell: int = y * layout.columns + x
			var kind: int = cells[cell] - 1
			if kind < 0:
				continue
			if harms_table[kind * width + _state[cell]] != 0:
				sight.mark(x, y)


# --- The step --------------------------------------------------------------------------

## `element` touched the floor at `at` (world pixels) within `radius`: the cells inside its circle in
## cell order (the cell it lands in, and each whose middle is within its radius).
func touch(element_name: StringName, at: Vector2, radius: float) -> void:
	var element: int = _moves.element(element_name)
	if element < 0:
		return
	var cell_size: float = float(CoverLayout.CELL)
	var cells: PackedByteArray = layout.cells
	var to_table: PackedInt32Array = _moves.to_table
	var width: int = _moves.width
	var elements: int = _moves.elements.size()
	var local: Vector2 = at - layout.origin
	var centre: int = layout.cell_of(at)
	var x0: int = maxi(floori((local.x - radius) / cell_size), 0)
	var x1: int = mini(floori((local.x + radius) / cell_size), layout.columns - 1)
	var y0: int = maxi(floori((local.y - radius) / cell_size), 0)
	var y1: int = mini(floori((local.y + radius) / cell_size), layout.rows - 1)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var cell: int = y * layout.columns + x
			var kind: int = cells[cell] - 1
			if kind < 0:
				continue
			var middle := Vector2((float(x) + 0.5) * cell_size, (float(y) + 0.5) * cell_size)
			if cell == centre or middle.distance_squared_to(local) <= radius * radius:
				# `_moved_to`, read from the table here: this loop may cover the whole room.
				var to: int = to_table[(kind * width + _state[cell]) * elements + element]
				if to >= 0:
					_enter(cell, to)


## The cells not at rest count on (README, "The step", 2), rolling with `game` keyed by the room's
## `number`: an `after` trigger moves one on; one that spreads rolls for each of its four neighbours
## (in NEIGHBOURS' order) that its element would move on, one roll each. The spreads apply once every
## cell has stepped. The kinds' moves are read from their tables here: every cell may burn at once.
func step_cells(delta: float, game: Sim, number: int) -> void:
	var cells: PackedByteArray = layout.cells
	var columns: int = layout.columns
	var rows: int = layout.rows
	var width: int = _moves.width
	var elements: int = _moves.elements.size()
	var to_table: PackedInt32Array = _moves.to_table
	var spread_table: PackedInt32Array = _moves.spread_table
	var chance_table: PackedFloat64Array = _moves.chance_table
	var after_first: PackedInt32Array = _moves.after_first
	var after_count: PackedInt32Array = _moves.after_count
	var after_seconds: PackedFloat64Array = _moves.after_seconds
	var after_to: PackedInt32Array = _moves.after_to
	var room_key: int = number << ROOM_KEY_SHIFT
	var i: int = 0
	while i < _active.size():
		var cell: int = _active[i]
		var row: int = (cells[cell] - 1) * width + _state[cell]
		_age[cell] += delta
		var age: float = _age[cell]
		var to: int = -1
		var first: int = after_first[row]
		for at in range(first, first + after_count[row]):
			if age >= after_seconds[at]:
				to = after_to[at]
				break
		if to >= 0:
			_enter(cell, to)
		elif spread_table[row] >= 0:
			var element: int = spread_table[row]
			var chance: float = chance_table[row] * delta
			var x: int = cell % columns
			var y: int = cell / columns
			for direction in NEIGHBOURS.size():
				var nx: int = x + NEIGHBOURS[direction].x
				var ny: int = y + NEIGHBOURS[direction].y
				if nx < 0 or ny < 0 or nx >= columns or ny >= rows:
					continue
				var other: int = ny * columns + nx
				var kind: int = cells[other] - 1
				if kind < 0 or to_table[(kind * width + _state[other]) * elements + element] < 0:
					continue
				var roll: float = game.chance(SPREAD, room_key + cell * NEIGHBOURS.size() + direction, _rolls)
				_rolls += 1
				if roll < chance:
					_spread_cells.append(other)
					_spread_by.append(element)
		# A cell gone to rest left the list; the next is in its place.
		if i < _active.size() and _active[i] == cell:
			i += 1
	for s in _spread_cells.size():
		var to: int = _moves.moved_to(cells[_spread_cells[s]] - 1, _state[_spread_cells[s]], _spread_by[s])
		if to >= 0:
			_enter(_spread_cells[s], to)
	_spread_cells.resize(0)
	_spread_by.resize(0)


## Cell `cell` enters state `to`: its seconds from 0, in or out of the active cells, told.
func _enter(cell: int, to: int) -> void:
	var was: int = _state[cell]
	var row: int = (layout.cells[cell] - 1) * _moves.width
	var harms: int = int(_moves.harms_table[row + to]) - int(_moves.harms_table[row + was])
	_harming += harms
	_harming_rows[cell / layout.columns] += harms
	_state[cell] = to
	_age[cell] = 0.0
	if was == 0 and to != 0:
		_active.insert(_active.bsearch(cell), cell)
	elif was != 0 and to == 0:
		_active.remove_at(_active.bsearch(cell))
	_tell(cell, to)


# --- Upkeep ----------------------------------------------------------------------------

## Every cell at rest, the layout's size (none for a room with no cover).
func _size_at_rest() -> void:
	var cells: int = layout.cells.size() if layout != null and layout.count() > 0 else 0
	_state.resize(cells)
	_state.fill(0)
	_age.resize(cells)
	_age.fill(0.0)


## How many cells are in a state that gives a status (`_harming`), from the state.
func _count_harming() -> void:
	_harming = 0
	_harming_rows.resize(0)
	if layout == null or _moves == null or _state.size() != layout.cells.size():
		return
	_harming_rows.resize(layout.rows)
	_harming_rows.fill(0)
	var cells: PackedByteArray = layout.cells
	var harms_table: PackedByteArray = _moves.harms_table
	var width: int = _moves.width
	for cell in _state.size():
		if cells[cell] > 0 and harms_table[(cells[cell] - 1) * width + _state[cell]] != 0:
			_harming += 1
			_harming_rows[cell / layout.columns] += 1


## Cell `cell` shows `state` from now on: told at the next `flush` unless the view already shows it.
func _tell(cell: int, state: int) -> void:
	if cell < 0 or cell >= _said.size() or _said[cell] == state:
		return
	_said[cell] = state
	_changed_cells.append(cell)
	_changed_states.append(state)


## Every cell whose state the view was told otherwise (all at rest for a room with no cover).
func tell_all() -> void:
	if layout == null or _said.size() != layout.cells.size():
		return
	if _state.size() == _said.size():
		for cell in _state.size():
			_tell(cell, _state[cell])
	elif _state.is_empty():
		for cell in _said.size():
			_tell(cell, 0)


## The changes told since the last, sent as one `cover_changed` of room `number` on `events`.
func flush(events: EventsScript, number: int) -> void:
	if _changed_cells.is_empty():
		return
	if events != null:
		events.cover_changed.emit(number, _changed_cells, _changed_states)
	_changed_cells.resize(0)
	_changed_states.resize(0)
