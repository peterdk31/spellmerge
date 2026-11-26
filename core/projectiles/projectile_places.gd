class_name ProjectilePlaces
extends Object
## The places shots pass into (core/projectiles/projectile_manager.gd): the portal's gates
## (`open_gate`, `shots_into_gates`, `gate_cut`), the fields a shot crosses (`set_field`, `_pass_fields`),
## and where a shot that passes comes out (`shot_places`, `pass_shot`). Methods working on the
## manager (`pm`), whose members hold all of it.

const Manager := preload("res://core/projectiles/projectile_manager.gd")

## Not state (core/sim/README.md): the manager, the other jobs this one calls and the manager's
## arrays it works on, each the manager's own array (shared, never a copy), linked by `link`.
const DERIVED: Array[StringName] = [&"pm", &"_pos", &"_prev", &"_vel", &"_radius", &"_layers", &"_motion", &"_home_at", &"_seq", &"_flags", &"_radius0", &"_floor", &"_field_out", &"_field_out_field", &"_base", &"_hold", &"_freeze", &"_caster_slot", &"_caster_seq", &"_state", &"_alive", &"_room_grid", &"_gate_on", &"_gate_pos", &"_gate_face", &"_gate_radius", &"_gate_group", &"_gate_tag", &"_gate_mouth", &"gate_shots", &"gate_shot_gates", &"_tail_from", &"_places_found"]

var pm: Manager = null
var _pos: PackedVector2Array
var _prev: PackedVector2Array
var _vel: PackedVector2Array
var _radius: PackedFloat32Array
var _layers: PackedInt32Array
var _motion: PackedByteArray
var _home_at: PackedVector2Array
var _seq: PackedInt64Array
var _flags: PackedInt32Array
var _radius0: PackedFloat32Array
var _floor: PackedFloat32Array
var _field_out: PackedInt32Array
var _field_out_field: PackedInt32Array
var _base: PackedVector2Array
var _hold: PackedFloat32Array
var _freeze: PackedFloat32Array
var _caster_slot: PackedInt32Array
var _caster_seq: PackedInt64Array
var _state: PackedByteArray
var _alive: PackedByteArray
var _room_grid: RoomGrid
var _gate_on: PackedByteArray
var _gate_pos: PackedVector2Array
var _gate_face: PackedVector2Array
var _gate_radius: PackedFloat32Array
var _gate_group: PackedInt64Array
var _gate_tag: PackedInt64Array
var _gate_mouth: PackedByteArray
var gate_shots: PackedInt32Array
var gate_shot_gates: PackedInt32Array
var _tail_from: PackedVector2Array
var _places_found: PackedByteArray


## Takes the manager's arrays and jobs, by the names in DERIVED: again whenever the manager's arrays
## may have been replaced (`ProjectileManager._link_jobs`).
func link(manager: Manager) -> void:
	pm = manager
	for name: StringName in DERIVED:
		if name != &"pm":
			set(name, manager.get(name))


## Opens a gate of the portal `group` (cast as the spell `tag`) at `at`, facing `face` (unit),
## `radius` pixels round: its mouth when `mouth`, else one of its exits. Returns its row (rows are reused once closed, the
## lowest free first, so the order is the same every run), or -1 for a bad one.
func open_gate(group: int, tag: int, at: Vector2, face: Vector2, radius: float, mouth: bool) -> int:
	if not at.is_finite() or not face.is_finite() or face.is_zero_approx() or not (radius > 0.0):
		return -1
	var row: int = _gate_on.find(0)
	if row < 0:
		row = _gate_on.size()
		var size: int = maxi(8, row * 2)
		for column: Variant in [_gate_on, _gate_pos, _gate_face, _gate_radius, _gate_group, _gate_tag, _gate_mouth]:
			column.resize(size)
		for n in range(row, size):
			_gate_on[n] = 0
	_gate_on[row] = 1
	_gate_pos[row] = at
	_gate_face[row] = face.normalized()
	_gate_radius[row] = radius
	_gate_group[row] = group
	_gate_tag[row] = tag
	_gate_mouth[row] = 1 if mouth else 0
	pm._gate_live += 1
	return row


## Closes gate `gate` (nothing when it is not open).
func close_gate(gate: int) -> void:
	if pm.gate_open(gate):
		_gate_on[gate] = 0
		pm._gate_live -= 1


## Where what goes into gate `gate` comes out: from a mouth, every exit of its portal; from an
## exit, its portal's mouth (a portal works both ways; owner, 2026-11-05). Fills `out` (grown when
## needed) in row order and returns how many.
func gate_outs(gate: int, out: PackedInt32Array) -> int:
	if not pm.gate_open(gate):
		return 0
	var group: int = _gate_group[gate]
	var want: int = 0 if _gate_mouth[gate] != 0 else 1
	var found: int = 0
	for row in _gate_on.size():
		if _gate_on[row] != 0 and row != gate and _gate_group[row] == group and _gate_mouth[row] == want:
			if out.size() <= found:
				out.resize(maxi(4, found * 2))
			out[found] = row
			found += 1
	return found


## The way something going `way` into gate `from` leaves gate `to`: the same way. A gate is a
## sphere with no front (owner, 2026-11-05): what hits it from one side leaves the other gate on the
## far side, going on as it went; what is fired back at an exit leaves the mouth flying at the one
## who opened it (P3). Every pass asks here, so a later rule for turning is one place.
func gate_turn(from: int, to: int, way: Vector2) -> Vector2:
	if not pm.gate_open(from) or not pm.gate_open(to):
		return way
	return way


## The share (0 to 1) of the segment from `a` to `b` at which it first goes into an open gate's
## circle widened by `pad`, starting outside it (a segment that starts inside a gate is leaving it);
## -1.0 for none. `gate_hit` says which gate (the lower row of two met at the same point).
func gate_cut(a: Vector2, b: Vector2, pad: float = 0.0) -> float:
	pm.gate_hit = -1
	if pm._gate_live <= 0:
		return -1.0
	var d: Vector2 = b - a
	var dd: float = d.length_squared()
	var best: float = 2.0
	for row in _gate_on.size():
		if _gate_on[row] == 0:
			continue
		var r: float = _gate_radius[row] + pad
		var f: Vector2 = a - _gate_pos[row]
		var c: float = f.length_squared() - r * r
		if c <= 0.0:
			continue
		if dd <= 0.0:
			continue
		var bq: float = f.dot(d)
		if bq >= 0.0:
			continue
		var disc: float = bq * bq - dd * c
		if disc < 0.0:
			continue
		var t: float = (-bq - sqrt(disc)) / dd
		if t >= 0.0 and t <= 1.0 and t < best:
			best = t
			pm.gate_hit = row
	return best if pm.gate_hit >= 0 else -1.0


## The flying shots whose centre went into a gate on their last step (from where they were to
## where they are), in slot order: `gate_shots` and `gate_shot_gates` (each one's gate), and how
## many. Only shots that fly on their own (straight, not stuck, held or frozen); a still shot, an
## orbit and one that did not move never go through. Nothing is allocated once the lists have grown.
func shots_into_gates() -> int:
	if pm._gate_live <= 0:
		return 0
	var found: int = 0
	for slot in pm._high:
		if _alive[slot] == 0 or _motion[slot] != Manager.MOTION_STRAIGHT:
			continue
		var state: int = _state[slot]
		if state == Manager.S_STUCK or state == Manager.S_FROZEN or state == Manager.S_HELD:
			continue
		var from: Vector2 = _prev[slot]
		var to: Vector2 = _pos[slot]
		if from == to:
			continue
		if gate_cut(from, to) < 0.0:
			continue
		if gate_shots.size() <= found:
			gate_shots.resize(maxi(8, found * 2))
			gate_shot_gates.resize(gate_shots.size())
		gate_shots[found] = slot
		gate_shot_gates[found] = pm.gate_hit
		found += 1
	return found


## The fields (the `field` carrier, docs/milestones/field.md): the still shot in `slot` is a field.
## It hits nothing (no hit layers: the hit pass tests no target for it), and the field pass never
## hands it back itself (it does not take another field's cards).
func set_field(slot: int) -> bool:
	if slot < 0 or slot >= pm._cap or _alive[slot] == 0:
		return false
	_flags[slot] |= Manager.F_FIELD
	_layers[slot] = 0
	return true


## The field pass: the shots in one of the first `count` fields of `fields` (their slots; a dead or
## stale one is passed by) after the last step: every shot whose middle is inside a field's circle
## now, wherever it came from (one that flew in, one cast, split or spawned inside it, one the field
## grew over), or that went through it in the step (a fast shot). Every shot is seen, flying,
## circling, homing or stopped by its speed, but a field, a still one (a rune, a pool, a wall), a
## held one (a local stop: one a field holds; a linger's hold; a stuck one), a falling one in the air
## and a field's own payload (a shot whose caster is that field's shot, `set_caster_shot`). A shot in
## two fields is the first one's of them in `fields` (the oldest, for the field carrier). Returns how
## many; `field_shot(n)` and `field_of(n)` say which, in slot order (at most the cap of them: a shot
## past it is dropped, caught the next step; more shots in fields in one step than the cap holds
## shots is not a game that is played). The native kernel's `field_pass` is this, to the bit;
## nothing is asked of it with no field.
func shots_into_fields(fields: PackedInt32Array, count: int) -> int:
	var _kernel: Object = pm._kernel
	count = mini(count, fields.size())
	if count <= 0:
		return 0
	if _kernel != null:
		var found: int = _kernel.call(&"field_pass", pm, fields, count)
		if found >= 0:
			return found
	return _pass_fields(fields, count)


## `shots_into_fields`' GDScript (the reference the kernel is held to, and its fallback).
func _pass_fields(fields: PackedInt32Array, count: int) -> int:
	var found: int = 0
	var most: int = _field_out.size()
	# The box round every live field: a shot outside it is in none (a shortcut the kernel need not
	# take: it changes no answer).
	var box := Rect2()
	var boxed: bool = false
	for n in count:
		var field: int = fields[n]
		if field < 0 or field >= pm._high or _alive[field] == 0 or (_flags[field] & Manager.F_FIELD) == 0:
			continue
		var round_it := Rect2(_pos[field] - Vector2(_radius[field], _radius[field]), Vector2(_radius[field], _radius[field]) * 2.0)
		box = round_it if not boxed else box.merge(round_it)
		boxed = true
	if not boxed:
		return 0
	box = box.grow(1.0)
	for slot in pm._high:
		if _alive[slot] == 0:
			continue
		var flags: int = _flags[slot]
		if (flags & Manager.F_FIELD) != 0 or _motion[slot] == Manager.MOTION_STILL:
			continue
		var state: int = _state[slot]
		# Stopped: a local stop (`_freeze`), a linger's hold (`_hold`; its S_HELD is the hit pass's
		# S_DONE by now), stuck.
		if state == Manager.S_FROZEN or state == Manager.S_STUCK or state == Manager.S_HELD or _freeze[slot] > 0.0 or _hold[slot] > 0.0:
			continue
		var to: Vector2 = _pos[slot]
		var from: Vector2 = _prev[slot]
		if not from.is_finite() or not to.is_finite():
			continue
		if not box.intersects(Rect2(from, Vector2.ZERO).expand(to), true):
			continue
		if (flags & Manager.F_FALLING) != 0 and to.y < _floor[slot] - Manager.FALL_BAND:
			continue
		for n in count:
			var field: int = fields[n]
			if field < 0 or field >= pm._high or _alive[field] == 0 or (_flags[field] & Manager.F_FIELD) == 0:
				continue
			# A field's own payload (a Timer's bolt from its middle) is born in it: never its.
			if _caster_slot[slot] == field and _caster_seq[slot] == _seq[field]:
				continue
			var centre: Vector2 = _pos[field]
			var radius: float = _radius[field]
			# A step that stays off the circle's box on one side never comes into it (most, at once).
			if minf(from.x, to.x) > centre.x + radius or maxf(from.x, to.x) < centre.x - radius or minf(from.y, to.y) > centre.y + radius or maxf(from.y, to.y) < centre.y - radius:
				continue
			var within: float = radius * radius
			if to.distance_squared_to(centre) > within:
				# Not inside now: in only if it went through it in this step (a fast shot).
				var way: Vector2 = to - from
				if from == to:
					continue
				var t: float = clampf((centre - from).dot(way) / way.dot(way), 0.0, 1.0)
				if (from + way * t).distance_squared_to(centre) > within:
					continue
			if found >= most:
				return found
			_field_out[found] = slot
			_field_out_field[found] = n
			found += 1
			# In two fields at once, it is the first one's.
			break
	return found


## The field in `slot` is `radius` pixels round from now on (it grows with the shots it holds; the
## field carrier), at most the room's size, as Growth keeps any shot (`_pass_growth`): bigger than the
## room it would catch nothing more and is drawn clipped by the screen. Its Growth goes on from there.
## False for a dead slot or a bad radius.
func set_field_radius(slot: int, radius: float) -> bool:
	if slot < 0 or slot >= pm._cap or _alive[slot] == 0 or (_flags[slot] & Manager.F_FIELD) == 0 or not (radius > 0.0) or not is_finite(radius):
		return false
	_radius[slot] = minf(radius, maxf(pm.room_size(), _radius0[slot]))
	return true


func field_of(n: int) -> int:
	return _field_out_field[n]


## Mark in `out` (one byte a place of `grid`, sized to them) each place a live shot is in now
## (connected biomes CB3: a shot keeps a room awake, and wakes one it comes into). Allocates nothing
## once `out` is sized.
func shot_places(grid: RoomGrid, out: PackedByteArray) -> void:
	var _kernel: Object = pm._kernel
	var count: int = grid.places()
	if out.size() != count:
		out.resize(count)
	out.fill(0)
	if count == 0:
		return
	# A shot in a square wholly in one place, or in none, is answered by the grid's table, as
	# `place_at` would answer it; `place_at` is asked only where the square's points may differ
	# (the performance pass, 2026-11-20: asked for every shot, this was most of Flow's tick). The
	# native kernel walks the shots (`ShotKernel.shot_places`) and hands back each ask.
	var whole: PackedByteArray = grid.whole_places()
	var from: int = 0
	if _kernel != null and grid == _room_grid:
		if _places_found.size() != count:
			_places_found.resize(count)
		_places_found.fill(0)
		while true:
			var asked: int = _kernel.call(&"shot_places", pm, from)
			if asked < -1:
				break
			if asked == -1:
				from = pm._high
				break
			var found: int = grid.place_at(_pos[asked])
			if found >= 0:
				_places_found[found] = 1
			from = asked + 1
		for place in count:
			out[place] = _places_found[place]
	_shot_places_from(grid, whole, from, out)


## `shot_places`' GDScript, from slot `from` on (the reference the kernel is held to, and its
## fallback): marks in `out` the place of every live shot, from `whole` (`RoomGrid.whole_places`).
func _shot_places_from(grid: RoomGrid, whole: PackedByteArray, from: int, out: PackedByteArray) -> void:
	var count: int = out.size()
	var left: int = 0
	for place in count:
		if out[place] == 0:
			left += 1
	if left == 0:
		return
	var origin: Vector2 = grid.place_origin()
	var columns: int = grid.place_columns()
	var rows: int = grid.place_rows()
	for slot in range(from, pm._high):
		if _alive[slot] == 0:
			continue
		var at: Vector2 = _pos[slot]
		var x: int = floori((at.x - origin.x) / Manager.PLACE_CELL)
		var y: int = floori((at.y - origin.y) / Manager.PLACE_CELL)
		var place: int = RoomGrid.NO_PLACE
		if x >= 0 and x < columns and y >= 0 and y < rows:
			var code: int = whole[y * columns + x]
			if code == 0:
				continue
			place = code - 1 if code != Manager.PLACE_ASK else grid.place_at(at)
		else:
			place = grid.place_at(at)
		if place >= 0 and out[place] == 0:
			out[place] = 1
			left -= 1
			if left == 0:
				return


## Puts the shot in `slot` at `at` at once, flying `velocity` (a shot that came out of a gate): no
## tail across the gap and no hits swept across it, as a blink (`move_shot` with no seconds). Its
## speed (what homing and return keep) stays. False when there is no such shot.
func pass_shot(slot: int, at: Vector2, velocity: Vector2) -> bool:
	if slot < 0 or slot >= pm._cap or _alive[slot] == 0 or _motion[slot] == Manager.MOTION_ORBIT:
		return false
	if not at.is_finite() or not velocity.is_finite():
		return false
	pm._threat_step = -1
	_base[slot] += at - _pos[slot]
	_pos[slot] = at
	_prev[slot] = at
	_vel[slot] = velocity
	_flags[slot] &= ~Manager.F_DEFERRED
	_tail_from[slot] = at
	_home_at[slot] = Vector2.INF
	return true
