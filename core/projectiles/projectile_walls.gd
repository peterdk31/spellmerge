class_name ProjectileWalls
extends Object
## The projectile manager's walls (core/projectiles/projectile_manager.gd, "Walls"): a room's wall bodies
## as rectangles, solid shots (`set_solid`: a segment in the wall grid while they live), and what a
## shot does at a wall (`_wall_end`: it ends, bounces or passes). Methods working on the manager
## (`pm`), whose members hold all of it.

const Manager := preload("res://core/projectiles/projectile_manager.gd")

## Not state (core/sim/README.md): the manager, the other jobs this one calls and the manager's
## arrays it works on, each the manager's own array (shared, never a copy), linked by `link`.
const DERIVED: Array[StringName] = [&"pm", &"_job_hits", &"_job_moves", &"_pos", &"_prev", &"_vel", &"_radius", &"_actor", &"_tag", &"_motion", &"_orbit_way", &"_seq", &"_bounce", &"_base", &"_caster_slot", &"_caster_seq", &"_alive", &"_solids", &"_room_grid"]

var pm: Manager = null
var _job_hits: ProjectileHits = null
var _job_moves: ProjectileMoves = null
var _pos: PackedVector2Array
var _prev: PackedVector2Array
var _vel: PackedVector2Array
var _radius: PackedFloat32Array
var _actor: PackedInt32Array
var _tag: PackedInt64Array
var _motion: PackedByteArray
var _orbit_way: PackedFloat32Array
var _seq: PackedInt64Array
var _bounce: PackedInt32Array
var _base: PackedVector2Array
var _caster_slot: PackedInt32Array
var _caster_seq: PackedInt64Array
var _alive: PackedByteArray
var _solids: Dictionary
var _room_grid: RoomGrid


## Takes the manager's arrays and jobs, by the names in DERIVED: again whenever the manager's arrays
## may have been replaced (`ProjectileManager._link_jobs`).
func link(manager: Manager) -> void:
	pm = manager
	for name: StringName in DERIVED:
		if name != &"pm":
			set(name, manager.get(name))


## Lay every solid shot's cells (state) back into the room grid (`RoomGrid.relay_solid`): after a
## restore, and by whoever lays the room's layers again over the same bounds (`BiomeWorld`), so the
## stones stand where the snapshot says without a step.
func relay_solids() -> void:
	for slot: int in _solids:
		_room_grid.relay_solid((_solids[slot] as Manager.Solid).cells)


## The room grid's walls are gone: the solid shots lie on no cell, and lay themselves again at their
## next step.
func _forget_solid_cells() -> void:
	for slot: int in _solids:
		var solid: Manager.Solid = _solids[slot]
		solid.cells.clear()
		solid.at = Vector2.INF


## The world rectangles of a body's enabled rectangle shapes (each turned one as its bounding box).
## Made each call (a room's walls and holes are laid once a room).
static func _body_rects(body: CollisionObject2D) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	for child in body.get_children():
		var shape_node := child as CollisionShape2D
		if shape_node == null or shape_node.disabled:
			continue
		var rectangle := shape_node.shape as RectangleShape2D
		if rectangle == null:
			continue
		var xf: Transform2D = shape_node.global_transform
		var half: Vector2 = rectangle.size * 0.5
		var low: Vector2 = xf * -half
		var high: Vector2 = low
		for corner: Vector2 in [Vector2(half.x, -half.y), half, Vector2(-half.x, half.y)]:
			var point: Vector2 = xf * corner
			low = low.min(point)
			high = high.max(point)
		rects.append(Rect2(low, high - low))
	return rects


## Make the still shot in `slot` a wall while it lives (the Wall card, rules R4 F6): a row of
## `stones` stones across `across`, `gap` pixels apart (and its radius thick, both growing with
## it). It lies in the wall grid, which bodies cannot walk through (`slide_body`), it hits along its
## row, and it follows the shot when homing moves it, stopping at a wall. False for an empty slot
## or a shot that is not still.
func set_solid(slot: int, across: Vector2, stones: int, gap: float) -> bool:
	if slot < 0 or slot >= pm._cap or _alive[slot] == 0 or _motion[slot] != Manager.MOTION_STILL or across.is_zero_approx() or not across.is_finite():
		return false
	var solid := Manager.Solid.new()
	solid.across = across.normalized()
	solid.across_from = solid.across
	solid.stones = maxi(stones, 1)
	solid.gap = gap / maxf(_radius[slot], 0.01)
	_solids[slot] = solid
	pm._any_solid = true
	_lay_solid(slot, solid)
	return true


## Half the row of the solid shot in `slot`: from its middle to its last stone's centre.
func _solid_half(slot: int, solid: Manager.Solid) -> Vector2:
	return solid.across * (solid.stones - 1) * 0.5 * solid.gap * _radius[slot]


## A solid shot's step, in place of a wall check: when it moved or grew it is lifted, stopped
## where a wall cuts its way (`_place_at`: a circling one holds there, pressing on the wall until
## its circle clears it), and laid again, its row turned as far as the shot has gone round
## (`_turned`: a circling wall is carried round as one piece).
func _step_solid(slot: int, solid: Manager.Solid) -> void:
	if _pos[slot] == solid.at and _radius[slot] == solid.radius:
		return
	_lift_solid(solid)
	if _pos[slot] != _prev[slot] and _room_grid.wall_hit(_prev[slot], _pos[slot]) >= 0.0:
		_job_moves._place_at(slot, _prev[slot])
	solid.across = DMath.rotated(solid.across_from, _job_moves._turned(slot))
	_lay_solid(slot, solid)


## Lay the solid shot in `slot` into the wall grid where it is now: every cell whose centre is
## within its radius and half a cell of its row, so a shot cannot slip between two cells.
func _lay_solid(slot: int, solid: Manager.Solid) -> void:
	solid.at = _pos[slot]
	solid.radius = _radius[slot]
	var half: Vector2 = _solid_half(slot, solid)
	var a: Vector2 = solid.at - half
	var b: Vector2 = solid.at + half
	var reach: float = solid.radius + Manager.WALL_CELL * 0.5
	solid.cells = _room_grid.lay_solid(a, b, reach, solid.cells)


## Take a solid shot's cells out of the wall grid.
func _lift_solid(solid: Manager.Solid) -> void:
	_mark_solid(solid, -1)
	solid.cells.clear()


## Add `by` (1 or -1) to the count of every cell a solid shot lies on.
func _mark_solid(solid: Manager.Solid, by: int) -> void:
	_room_grid.mark_cells(solid.cells, by)


## The live solid shot that cast the shot in `slot` (a payload of a wall), or null.
func _own_solid(slot: int) -> Manager.Solid:
	return _solid_of(_caster_slot[slot], _caster_seq[slot])


## Where the shot in `slot` meets a wall this step (`cut`, as `RoomGrid.wall_hit` found it) when the
## wall that cast it does not count: a wall's own payloads leave it (its row is lifted while
## they look again). Asked only when it met a wall, so a step with none costs nothing.
func _past_own_solid(slot: int, cut: float) -> float:
	var own: Manager.Solid = _own_solid(slot)
	if own == null:
		return cut
	_mark_solid(own, -1)
	cut = _room_grid.wall_hit(_prev[slot], _pos[slot])
	_mark_solid(own, 1)
	return cut


## The solid shot in `caster` while it is still the shot numbered `seq`, or null.
func _solid_of(caster: int, seq: int) -> Manager.Solid:
	if not pm._any_solid or caster < 0 or caster >= pm._cap:
		return null
	if _alive[caster] != 0 and _seq[caster] == seq and _solids.has(caster):
		return _solids[caster]
	return null


## The solid shot in `slot` ended: its wall goes.
func _drop_solid(slot: int) -> void:
	var solid: Manager.Solid = _solids[slot]
	_solids.erase(slot)
	pm._any_solid = not _solids.is_empty()
	_lift_solid(solid)


## A shot met a wall: it bounces while it has bounces left, otherwise it ends there.
func _wall_end(slot: int) -> void:
	pm.wall_hits += 1
	pm._emit_wall_impact(slot, _vel[slot])
	if _bounce[slot] <= 0:
		pm.expired_on_wall = true
		pm._expire(slot)
		pm.expired_on_wall = false
		return
	_bounce[slot] -= 1
	var heading: Vector2 = _vel[slot].normalized()
	# Step back out of the wall cell, then find which face was hit: a face is hit when the
	# cell one cell further along that axis is solid.
	var at: Vector2 = _pos[slot] - heading * 0.5
	if _motion[slot] == Manager.MOTION_ORBIT:
		# Its circle is its path: it turns back round it from where it met the wall, the bounce
		# rule in its motion (the face does not matter; the orbit pass puts it back on the circle).
		_orbit_way[slot] = -_orbit_way[slot]
		_vel[slot] = -_vel[slot]
	else:
		_vel[slot] = _bounced(at, heading, _vel[slot])
	_job_moves._place_at(slot, at)
	_base[slot] = at
	# A bounced shot may hit what it hit before.
	_job_hits._forget_all(slot)
	# Last: a handler's payload may take this slot over (a cap drop).
	var outer_slot: int = pm._event_slot
	pm._event_slot = slot
	pm._sent += 1
	pm.wall_met.emit(_actor[slot], at, _vel[slot].normalized(), _tag[slot], slot)
	pm._event_slot = outer_slot


## `velocity` turned off the wall face met at `at` (just out of the wall, heading `heading`): a
## face is hit when the cell one cell further along that axis is solid; both or neither (a
## corner) send it back the way it came. A shot's bounce and a beam's turn share it.
func _bounced(at: Vector2, heading: Vector2, velocity: Vector2) -> Vector2:
	var flip_x: bool = _solid_at(at + Vector2(signf(heading.x) * Manager.WALL_CELL, 0.0))
	var flip_y: bool = _solid_at(at + Vector2(0.0, signf(heading.y) * Manager.WALL_CELL))
	if flip_x == flip_y:
		return -velocity
	if flip_x:
		return Vector2(-velocity.x, velocity.y)
	return Vector2(velocity.x, -velocity.y)


func _solid_at(point: Vector2) -> bool:
	return _room_grid.cell_at(point) != 0
