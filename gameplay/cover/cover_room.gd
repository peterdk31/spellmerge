class_name CoverRoom
extends RefCounted
## One room's ground cover in play (connected biomes CB3b; the cover area's, gameplay/cover/cover.gd):
## each cell of its layout (`CoverLayout`, laid at the room's place in the world and mirrored with
## it) in a state of its kind, the cells not at rest, and its own roll counter, so a room's fire plays
## the same whatever burns in another room. The cover area keeps one a piece of the world (by its
## number: a row run's one room, a biome's rooms then bridges), steps it only while its place is
## awake, and hands it the touches and the bodies; the rules of a step are here (README, "The step").
##
## **State:** each cell's state and seconds in it, the active cells and who lit each (its lighter: the
## actor and the spell's tag of the touch that moved it, the floor's first slice, docs/milestones/floor.md),
## the rolls made. **Derived:** the layout and its kinds' move tables (`bind`, from `room_built`; again
## after a restore), what is worked out from the state with them (`_harming`, `_gives`, `_danger`, `_danger_bits`), and what this
## machine's view was told (`_said`).

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
## The cells a word of `_danger_bits` holds (a row's columns, low bit first): 32, so a word is never negative.
const BITS: int = 32
## `giving_cell` of a point off the room's cover (another room may hold it).
const OFF: int = -2

## Not state: the layout and its tables (bound from `room_built`), what is worked out from the state
## with them, what this machine's view was told, and scratch emptied within a step.
const DERIVED: Array[StringName] = [
	&"layout", &"_moves", &"_rest_harms", &"_harming", &"_gives", &"_danger", &"_danger_bits", &"_words", &"_danger_rows", &"_danger_columns",
	&"_row_bits", &"_column_bits", &"_said",
	&"_changed_cells", &"_changed_states", &"_spread_cells", &"_spread_by", &"_spread_actor", &"_spread_tag",
]

## The room's cover at its place (null before it is bound).
var layout: CoverLayout = null
var _moves: CoverMoves = null
## True when a kind with cells in the room gives a status at rest (cobwebs).
var _rest_harms: bool = false
## How many cells are in a state that gives a status or strikes now (whether bodies are looked at),
## and by cell, 1 where it does (`CoverMoves.harms_table` of its state: `giving_cell`).
var _harming: int = 0
var _gives: PackedByteArray = PackedByteArray()
## How many are in a state that is danger now (GC7: the AI's look), and where, a bit a cell: each row
## `_words` words of BITS columns, low bit first (`look` reads a window's rows as a few words).
var _danger: int = 0
var _danger_bits: PackedInt64Array = PackedInt64Array()
var _words: int = 0
## The same counted a row and a column, and which rows and columns hold any, a bit each (BITS a
## word): a look whose window crosses no such row or column is answered from a word or two.
var _danger_rows: PackedInt32Array = PackedInt32Array()
var _danger_columns: PackedInt32Array = PackedInt32Array()
var _row_bits: PackedInt64Array = PackedInt64Array()
var _column_bits: PackedInt64Array = PackedInt64Array()
## Each cell's state as this machine's view was last told (`cover_changed`).
var _said: PackedByteArray = PackedByteArray()
## This tick's changes, sent once (`flush`).
var _changed_cells: PackedInt32Array = PackedInt32Array()
var _changed_states: PackedInt32Array = PackedInt32Array()
## Scratch: the spreads rolled this step.
var _spread_cells: PackedInt32Array = PackedInt32Array()
var _spread_by: PackedInt32Array = PackedInt32Array()
var _spread_actor: PackedInt32Array = PackedInt32Array()
var _spread_tag: PackedInt64Array = PackedInt64Array()

## Each cell's state (its index in its kind's states; 0 at rest) and its seconds in it, the
## layout's size, or empty for a room with no cover.
var _state: PackedByteArray = PackedByteArray()
var _age: PackedFloat32Array = PackedFloat32Array()
## The cells not at rest, in cell order.
var _active: PackedInt32Array = PackedInt32Array()
## Who lit each active cell (in `_active`'s order): the actor (NO_PLAYER for nobody, a prop) and the
## tag of its spell (0 for none). Set by the touch that moved or renewed it, handed on by a spread,
## kept by an `after` move, gone with the cell to rest.
var _active_actor: PackedInt32Array = PackedInt32Array()
var _active_tag: PackedInt64Array = PackedInt64Array()
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
		if not kind.states.is_empty() and kind.states[0] != null and kind.states[0].gives() and laid.count(kind.id) > 0:
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
	_active_actor.resize(0)
	_active_tag.resize(0)
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


## True when a cell is not at rest (`step_cells` has something to step).
func has_active() -> bool:
	return not _active.is_empty()


## True when no cell of the room is in a state that gives a status now (`_harming`, worked out from
## the state): a body standing in it is given nothing, whichever cell it stands in (the performance
## pass, 2026-11-21: Cover looked up the cell of every body in a room with cobwebs at rest elsewhere).
func harms_nobody() -> bool:
	return plays() and _harming == 0


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


## Who lit cell `cell`: its actor (NO_PLAYER for a cell at rest, or lit by nobody).
func actor_at(cell: int) -> int:
	var at: int = _active_index(cell)
	return _active_actor[at] if at >= 0 else EventsScript.NO_PLAYER


## The tag of the spell that lit cell `cell` (0 for none).
func tag_at(cell: int) -> int:
	var at: int = _active_index(cell)
	return _active_tag[at] if at >= 0 else 0


## The index of cell `cell` in the active cells, -1 for a cell at rest.
func _active_index(cell: int) -> int:
	if _active.is_empty():
		return -1
	var at: int = _active.bsearch(cell)
	return at if at < _active.size() and _active[at] == cell else -1


## The cell under `at` (world pixels) when its state gives a status or strikes now (the cells the
## cover area asks a status for); -1 for a cell of the room that gives nothing (or a room that harms
## nobody, `harms_nobody`), OFF for a point off the room's cover (`holds` is false). Allocates nothing.
func giving_cell(at: Vector2) -> int:
	if layout == null or _state.is_empty() or _state.size() != layout.cells.size():
		return OFF
	var x: int = floori((at.x - layout.origin.x) / float(CoverLayout.CELL))
	var y: int = floori((at.y - layout.origin.y) / float(CoverLayout.CELL))
	if x < 0 or y < 0 or x >= layout.columns or y >= layout.rows:
		return OFF
	if _harming == 0:
		return -1
	var cell: int = y * layout.columns + x
	return cell if _gives[cell] != 0 else -1


## Fill `sight` (cleared by the caller) with where the room's floor within `reach` of `at` would harm a
## body (the cover area's `look`), for `at` on the room's cover (`holds`; nothing for a point off it).
## A look is asked by every walking body every think, so it runs the native module's
## `BodyKernel.cover_look` when it is loaded (perf plan C3: called straight, no wrapper), else
## `gd_look`; tests/gameplay/cover/test_cover_look.gd compares the two to the bit. The native look
## wants a sight with nothing marked (its cells all 0), as a cleared one is: a sight with marks left
## in it is looked at by `gd_look`, so either way it ends as `gd_look` leaves it. Allocates nothing.
func look(at: Vector2, reach: float, sight: CoverSight) -> void:
	if _danger == 0 or layout == null or _state.size() != layout.cells.size():
		return
	var kernel: Object = WallSlide.kernel()
	if kernel != null and sight.count == 0 and kernel.has_method(&"cover_look"):
		var opened: int = kernel.call(&"cover_look", _row_bits, _column_bits, _danger_bits, _words, layout.columns, layout.rows, layout.origin, at, reach, sight.cells(), sight.window())
		if opened == -1:
			# Off the room's cover: the sight is left as it was, as `gd_look` leaves it.
			return
		if opened >= 0:
			sight.take_window(layout.origin, opened == 1)
			return
	gd_look(at, reach, sight)


## `look` in GDScript: the reference `BodyKernel.cover_look` mirrors, and the fallback. The window's
## rows and columns that hold danger are found first (`_row_bits`, `_column_bits`): with none, nothing
## is read but those; else each such row is read from `_danger_bits`, a word or two each.
func gd_look(at: Vector2, reach: float, sight: CoverSight) -> void:
	if _danger == 0 or layout == null or _state.size() != layout.cells.size():
		return
	var columns: int = layout.columns
	var rows: int = layout.rows
	var origin: Vector2 = layout.origin
	# `holds(at)`, as `CoverLayout.cell_of` works it out.
	var cx: int = floori((at.x - origin.x) / float(CoverLayout.CELL))
	var cy: int = floori((at.y - origin.y) / float(CoverLayout.CELL))
	if cx < 0 or cy < 0 or cx >= columns or cy >= rows:
		return
	if not sight.open(at, reach, columns, rows, origin):
		return
	var x0: int = sight.origin.x
	var x1: int = x0 + sight.columns - 1
	var y0: int = sight.origin.y
	var y1: int = y0 + sight.rows - 1
	# The bits y0 to y1 of `_row_bits` (at most CoverSight.SIDE apart, which must stay below BITS: a
	# word or two), shifted down to bit 0;
	# then x0 to x1 of `_column_bits`.
	var word: int = y0 / BITS
	var shift: int = y0 % BITS
	var rows_seen: int = _row_bits[word] >> shift
	if y1 / BITS != word:
		rows_seen |= _row_bits[word + 1] << (BITS - shift)
	rows_seen &= (1 << (y1 - y0 + 1)) - 1
	if rows_seen == 0:
		return
	word = x0 / BITS
	shift = x0 % BITS
	var columns_seen: int = _column_bits[word] >> shift
	if x1 / BITS != word:
		columns_seen |= _column_bits[word + 1] << (BITS - shift)
	if (columns_seen & ((1 << (x1 - x0 + 1)) - 1)) == 0:
		return
	var first_word: int = x0 / BITS
	var last_word: int = x1 / BITS
	var y: int = y0 - 1
	while rows_seen != 0:
		y += 1
		var seen: bool = (rows_seen & 1) != 0
		rows_seen >>= 1
		if not seen:
			continue
		var base: int = y * _words
		for at_word in range(first_word, last_word + 1):
			var bits: int = _danger_bits[base + at_word]
			if bits == 0:
				continue
			var low: int = maxi(x0 - at_word * BITS, 0)
			var high: int = mini(x1 - at_word * BITS, BITS - 1)
			bits = (bits >> low) & ((1 << (high - low + 1)) - 1)
			var x: int = at_word * BITS + low
			while bits != 0:
				if (bits & 1) != 0:
					sight.mark(x, y)
				bits >>= 1
				x += 1


# --- The step --------------------------------------------------------------------------

## `element` touched the floor at `at` (world pixels) within `radius`, lit by `actor` with the spell
## of `tag`: the cells inside its circle in cell order (the cell it lands in, and each whose middle is
## within its radius).
func touch(element_name: StringName, at: Vector2, radius: float, actor: int = EventsScript.NO_PLAYER, tag: int = 0) -> void:
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
				var index: int = (kind * width + _state[cell]) * elements + element
				var to: int = to_table[index]
				if to >= 0:
					_enter(cell, to, actor, tag)
				elif _moves.renew_table[index] != 0:
					_renew(cell, actor, tag)


## The passing touches `first` to `last` - 1 of `elements`, `at`, `actors`, `tags` whose room is this
## one (`rooms[n]` == `number`; the cover area's queue, `floor_passed`): each on the one cell under it,
## in order, as a touch of no radius on it. The loop of a tick with every shot touching: its tables read here.
func touch_cells(elements: Array[StringName], at: PackedVector2Array, actors: PackedInt32Array, tags: PackedInt64Array, rooms: PackedInt32Array, number: int, first: int, last: int) -> void:
	var cells: PackedByteArray = layout.cells
	var to_table: PackedInt32Array = _moves.to_table
	var renew_table: PackedByteArray = _moves.renew_table
	var width: int = _moves.width
	var count: int = _moves.elements.size()
	var origin: Vector2 = layout.origin
	var columns: int = layout.columns
	var rows: int = layout.rows
	var size: float = float(CoverLayout.CELL)
	var named: StringName = &""
	var element: int = -1
	for t in range(first, last):
		if rooms[t] != number:
			continue
		if elements[t] != named:
			named = elements[t]
			element = _moves.element(named)
		if element < 0:
			continue
		var x: int = floori((at[t].x - origin.x) / size)
		var y: int = floori((at[t].y - origin.y) / size)
		if x < 0 or y < 0 or x >= columns or y >= rows:
			continue
		var cell: int = y * columns + x
		var kind: int = cells[cell] - 1
		if kind < 0:
			continue
		var index: int = (kind * width + _state[cell]) * count + element
		var to: int = to_table[index]
		if to >= 0:
			_enter(cell, to, actors[t], tags[t])
		elif renew_table[index] != 0:
			_renew(cell, actors[t], tags[t])


## The cells not at rest count on (README, "The step", 2), rolling with `game` keyed by the room's
## `number`: an `after` trigger moves one on; one that spreads rolls for each of its four neighbours
## (in NEIGHBOURS' order) that its element would move on, one roll each. The spreads apply once every
## cell has stepped. The kinds' moves are read from their tables here: every cell may burn at once.
func step_cells(delta: float, game: Sim, number: int) -> void:
	if _active.is_empty():
		# Every cell at rest: none ages, moves on or spreads (the performance pass, 2026-11-21).
		return
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
			_enter(cell, to, _active_actor[i], _active_tag[i])
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
					_spread_actor.append(_active_actor[i])
					_spread_tag.append(_active_tag[i])
		# A cell gone to rest left the list; the next is in its place.
		if i < _active.size() and _active[i] == cell:
			i += 1
	for s in _spread_cells.size():
		var to: int = _moves.moved_to(cells[_spread_cells[s]] - 1, _state[_spread_cells[s]], _spread_by[s])
		if to >= 0:
			_enter(_spread_cells[s], to, _spread_actor[s], _spread_tag[s])
	_spread_cells.resize(0)
	_spread_by.resize(0)
	_spread_actor.resize(0)
	_spread_tag.resize(0)


## Cell `cell` enters state `to`, lit by `actor` with `tag`: its seconds from 0, in or out of the
## active cells (with its lighter), told.
func _enter(cell: int, to: int, actor: int, tag: int) -> void:
	var was: int = _state[cell]
	var row: int = (layout.cells[cell] - 1) * _moves.width
	var gives: int = _moves.harms_table[row + to]
	_harming += gives - int(_moves.harms_table[row + was])
	_gives[cell] = gives
	var danger: int = int(_moves.danger_table[row + to]) - int(_moves.danger_table[row + was])
	if danger != 0:
		_danger += danger
		var column: int = cell % layout.columns
		var word: int = (cell / layout.columns) * _words + column / BITS
		var bit: int = 1 << (column % BITS)
		_danger_bits[word] = (_danger_bits[word] | bit) if danger > 0 else (_danger_bits[word] & ~bit)
		var line: int = cell / layout.columns
		_danger_rows[line] += danger
		_set_bit(_row_bits, line, _danger_rows[line] > 0)
		_danger_columns[column] += danger
		_set_bit(_column_bits, column, _danger_columns[column] > 0)
	_state[cell] = to
	_age[cell] = 0.0
	if was == 0 and to != 0:
		var at: int = _active.bsearch(cell)
		_active.insert(at, cell)
		_active_actor.insert(at, actor)
		_active_tag.insert(at, tag)
	elif was != 0 and to == 0:
		var at: int = _active.bsearch(cell)
		_active.remove_at(at)
		_active_actor.remove_at(at)
		_active_tag.remove_at(at)
	elif to != 0:
		var at: int = _active.bsearch(cell)
		_active_actor[at] = actor
		_active_tag[at] = tag
	_tell(cell, to)


## Cell `cell` is touched by the element its state renews on (its row names the state itself): its
## seconds from 0 and its lighter `actor`'s with `tag`; nothing told (its look is the same).
func _renew(cell: int, actor: int, tag: int) -> void:
	var at: int = _active_index(cell)
	_age[cell] = 0.0
	if at >= 0:
		_active_actor[at] = actor
		_active_tag[at] = tag


# --- Upkeep ----------------------------------------------------------------------------

## Every cell at rest, the layout's size (none for a room with no cover).
func _size_at_rest() -> void:
	var cells: int = layout.cells.size() if layout != null and layout.count() > 0 else 0
	_state.resize(cells)
	_state.fill(0)
	_age.resize(cells)
	_age.fill(0.0)


## How many cells are in a state that gives something (`_harming`, and where: `_gives`) and that is
## danger (`_danger`, and where: `_danger_bits`), from the state.
func _count_harming() -> void:
	_harming = 0
	_danger = 0
	_gives.resize(0)
	_danger_bits.resize(0)
	_words = 0
	_danger_rows.resize(0)
	_danger_columns.resize(0)
	_row_bits.resize(0)
	_column_bits.resize(0)
	if layout == null or _moves == null or _state.size() != layout.cells.size():
		return
	var columns: int = layout.columns
	_words = (columns + BITS - 1) / BITS
	_gives.resize(_state.size())
	_gives.fill(0)
	_danger_bits.resize(layout.rows * _words)
	_danger_bits.fill(0)
	_danger_rows.resize(layout.rows)
	_danger_rows.fill(0)
	_danger_columns.resize(columns)
	_danger_columns.fill(0)
	# A word more than the rows and columns need, so `look` may read the one after a last word.
	_row_bits.resize((layout.rows + BITS - 1) / BITS + 1)
	_row_bits.fill(0)
	_column_bits.resize(_words + 1)
	_column_bits.fill(0)
	var cells: PackedByteArray = layout.cells
	var harms_table: PackedByteArray = _moves.harms_table
	var danger_table: PackedByteArray = _moves.danger_table
	var width: int = _moves.width
	for cell in _state.size():
		if cells[cell] == 0:
			continue
		var row: int = (cells[cell] - 1) * width + _state[cell]
		if harms_table[row] != 0:
			_harming += 1
			_gives[cell] = 1
		if danger_table[row] != 0:
			_danger += 1
			var column: int = cell % columns
			var word: int = (cell / columns) * _words + column / BITS
			_danger_bits[word] |= 1 << (column % BITS)
			_danger_rows[cell / columns] += 1
			_danger_columns[column] += 1
	for row in layout.rows:
		_set_bit(_row_bits, row, _danger_rows[row] > 0)
	for column in columns:
		_set_bit(_column_bits, column, _danger_columns[column] > 0)


## Bit `at` of `bits` (BITS a word) set when `on`, else cleared.
static func _set_bit(bits: PackedInt64Array, at: int, on: bool) -> void:
	var word: int = at / BITS
	var bit: int = 1 << (at % BITS)
	bits[word] = (bits[word] | bit) if on else (bits[word] & ~bit)


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
