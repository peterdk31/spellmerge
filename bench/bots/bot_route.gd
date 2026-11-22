extends RefCounted
## A travelling bot's way over the walls (bench/bots/bot.gd, "Travel"): the shortest walk from where
## it stands to a goal, over the wall grid's cells (`RoomGrid.WALL_CELL`), so it follows a walkway
## round its corner, comes to a mouth along the walkway's band and never cuts across the void (a
## wall) or snags on a lip. Bot code, never the game's: it only reads the grid a person's eyes read
## (the walls, the mouths a wizard walks through, the holes and the props' ground).
##
## `aim(projectiles, feet, area, goal_place, goal_point, goal_reach, radius, key)` answers the way to walk
## (unit length, or ZERO when the goal cannot be reached inside `area`). The goal is the cells of
## place `goal_place` (`RoomGrid.place_at`; NO_PLACE: any place) within `goal_reach` of
## `goal_point` (INF: anywhere in the place). The answer is a flow field: every cell of `area` a body
## of `radius` can stand in gets its walk (in cells, eight ways, no corner cut) to the nearest goal
## cell, worked out once for each `key` (the caller's name for that goal and area) and again every
## STALE steps while the feet have no way or come no nearer (a gather door opened, a Wall card's
## stone laid across the way or gone); the feet walk down the field, aiming AHEAD cells on. The area
## is kept inside the grid's bounds (outside them `cell_at` reads open). Nothing is allocated once its arrays have grown
## to the largest area asked.

const ProjectilesScript := preload("res://core/projectiles/projectile_manager.gd")
const CELL: float = RoomGrid.WALL_CELL
## How many cells down the field the walk aims (a short look ahead: straight runs stay straight).
const AHEAD: int = 3
## How far round the feet (in cells) a way is looked for when the feet's own cell has none (a body
## brushing a wall stands where its centre's cell is too near one).
const NEAR_RING: int = 2
## While the feet have no way, or come no nearer the goal, the field is worked out again after this
## many steps.
const STALE: int = 60
## The eight steps, the four straight first (cells: x, y).
const STEPS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]

## The field's area, in cells of the grid's own (the top-left cell and the size).
var _origin: Vector2 = Vector2.ZERO
var _w: int = 0
var _h: int = 0
## Per cell: open (no wall but a mouth, no hole, no prop's ground), a body can stand there, and its
## walk to the goal (-1: none).
var _open: PackedByteArray = PackedByteArray()
var _stand: PackedByteArray = PackedByteArray()
var _dist: PackedInt32Array = PackedInt32Array()
var _queue: PackedInt32Array = PackedInt32Array()
var _key: int = -1
## Steps since the feet last came nearer the goal (or, with no way, since it was worked out), and
## the nearest they came.
var _stale: int = 0
var _best: int = -1


## The way to walk from `feet` to the goal (see the class doc), or ZERO.
func aim(projectiles: ProjectilesScript, feet: Vector2, area: Rect2, goal_place: int, goal_point: Vector2, goal_reach: float, radius: float, key: int) -> Vector2:
	var within: Rect2 = area.intersection(projectiles.bounds()) if projectiles != null else Rect2()
	if within.size.x <= 0.0 or within.size.y <= 0.0:
		_w = 0
		_key = -1
		return Vector2.ZERO
	if key != _key or _stale >= STALE:
		_work_out(projectiles.grid(), projectiles.bounds().position, within, goal_place, goal_point, goal_reach, radius)
		_key = key
		_stale = 0
		_best = -1
	var at: int = _nearest_way(feet)
	if at < 0:
		_stale += 1
		return Vector2.ZERO
	if _dist[at] == 0 and _cell_of(feet) == at:
		# In the goal: nothing more to walk.
		_stale = 0
		return Vector2.ZERO
	# No nearer for STALE steps (a Wall card's stone across the way, or gone since): work it out again.
	if _best < 0 or _dist[at] < _best:
		_best = _dist[at]
		_stale = 0
	else:
		_stale += 1
	for _n in AHEAD:
		var next: int = _downhill(at)
		if next < 0:
			break
		at = next
	var way: Vector2 = _middle(at) - feet
	return way.normalized() if way.length() > 0.5 else Vector2.ZERO


## True when `feet` stand in a cell with a way to the goal worked out last (tests).
func has_way(feet: Vector2) -> bool:
	return _nearest_way(feet) >= 0


## Forget the field (a new run, a new map): the next `aim` works it out again.
func reset() -> void:
	_key = -1
	_stale = 0


func _work_out(grid: RoomGrid, corner: Vector2, area: Rect2, goal_place: int, goal_point: Vector2, goal_reach: float, radius: float) -> void:
	# The area snapped out to the grid's own cells (WALL_CELL from its bounds' `corner`).
	var x0: float = corner.x + floorf((area.position.x - corner.x) / CELL) * CELL
	var y0: float = corner.y + floorf((area.position.y - corner.y) / CELL) * CELL
	_origin = Vector2(x0, y0)
	_w = ceili((area.end.x - x0) / CELL)
	_h = ceili((area.end.y - y0) / CELL)
	var cells: int = _w * _h
	if _open.size() < cells:
		_open.resize(cells)
		_stand.resize(cells)
		_dist.resize(cells)
		_queue.resize(cells)
	for c in cells:
		var middle: Vector2 = _middle(c)
		var byte: int = grid.cell_at(middle)
		_open[c] = 1 if (byte & RoomGrid.PAST_MOUTHS) == 0 and grid.walk_clear(middle, middle) else 0
	# A body of `radius` at a cell's middle covers the cells within `ring` of it.
	var ring: int = maxi(ceili((radius - CELL * 0.5) / CELL), 0)
	for y in _h:
		for x in _w:
			var ok: int = 1
			for dy in range(-ring, ring + 1):
				for dx in range(-ring, ring + 1):
					var cx: int = x + dx
					var cy: int = y + dy
					if cx < 0 or cy < 0 or cx >= _w or cy >= _h or _open[cy * _w + cx] == 0:
						ok = 0
			_stand[y * _w + x] = ok
	# The goal's cells, then a walk out from them.
	var head: int = 0
	var tail: int = 0
	var reach2: float = goal_reach * goal_reach
	for c in cells:
		_dist[c] = -1
		if _stand[c] == 0:
			continue
		var middle: Vector2 = _middle(c)
		if goal_place != RoomGrid.NO_PLACE and grid.place_at(middle) != goal_place:
			continue
		if goal_reach != INF and middle.distance_squared_to(goal_point) > reach2:
			continue
		_dist[c] = 0
		_queue[tail] = c
		tail += 1
	while head < tail:
		var c: int = _queue[head]
		head += 1
		var x: int = c % _w
		var y: int = c / _w
		for step: Vector2i in STEPS:
			var n: int = _step(x, y, step)
			if n >= 0 and _dist[n] < 0:
				_dist[n] = _dist[c] + 1
				_queue[tail] = n
				tail += 1


## The cell one `step` from (x, y) a body can walk to (no corner cut across a wall), or -1.
func _step(x: int, y: int, step: Vector2i) -> int:
	var nx: int = x + step.x
	var ny: int = y + step.y
	if nx < 0 or ny < 0 or nx >= _w or ny >= _h or _stand[ny * _w + nx] == 0:
		return -1
	if step.x != 0 and step.y != 0 and (_stand[y * _w + nx] == 0 or _stand[ny * _w + x] == 0):
		return -1
	return ny * _w + nx


## The cell one step nearer the goal from `c` (the first of STEPS), or -1 (the goal, or none).
func _downhill(c: int) -> int:
	var here: int = _dist[c]
	if here <= 0:
		return -1
	var x: int = c % _w
	var y: int = c / _w
	for step: Vector2i in STEPS:
		var n: int = _step(x, y, step)
		if n >= 0 and _dist[n] >= 0 and _dist[n] < here:
			return n
	return -1


## The cell of `feet` when it has a way, else the nearest within NEAR_RING that has (the fewest
## steps to the goal among the nearest), or -1.
func _nearest_way(feet: Vector2) -> int:
	if _w == 0:
		return -1
	var c: int = _cell_of(feet)
	if c >= 0 and _dist[c] >= 0:
		return c
	var fx: int = floori((feet.x - _origin.x) / CELL)
	var fy: int = floori((feet.y - _origin.y) / CELL)
	for r in range(1, NEAR_RING + 1):
		var best: int = -1
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var x: int = fx + dx
				var y: int = fy + dy
				if x < 0 or y < 0 or x >= _w or y >= _h:
					continue
				var n: int = y * _w + x
				if _dist[n] >= 0 and (best < 0 or _dist[n] < _dist[best]):
					best = n
		if best >= 0:
			return best
	return -1


func _cell_of(point: Vector2) -> int:
	var x: int = floori((point.x - _origin.x) / CELL)
	var y: int = floori((point.y - _origin.y) / CELL)
	return y * _w + x if x >= 0 and y >= 0 and x < _w and y < _h else -1


func _middle(c: int) -> Vector2:
	return _origin + (Vector2(c % _w, c / _w) + Vector2(0.5, 0.5)) * CELL
