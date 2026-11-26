class_name ProjectileRays
extends Object
## The projectile manager's rays, sweeps and strikes (core/projectiles/projectile_manager.gd): a beam's
## path through walls, gates and bodies (`ray`, `_ray_path`), its points and curve, a swing's sweep and a
## strike's hits. Methods working on the manager (`pm`), whose members hold all of it.

const Manager := preload("res://core/projectiles/projectile_manager.gd")

## Not state (core/sim/README.md): the manager, the other jobs this one calls and the manager's
## arrays it works on, each the manager's own array (shared, never a copy), linked by `link`.
const DERIVED: Array[StringName] = [&"pm", &"_job_places", &"_job_targets", &"_job_walls", &"_targets", &"_target_radius", &"_target_half", &"_target_layer", &"_target_pos", &"_cell_head", &"_target_next", &"_room_grid", &"_ray_nodes", &"_ray_along", &"_ray_points", &"_ray_heads", &"_ray_walks", &"_ray_turns", &"_path", &"ray_path", &"sweep_nodes", &"sweep_points", &"sweep_heads"]

var pm: Manager = null
var _job_places: ProjectilePlaces = null
var _job_targets: ProjectileTargets = null
var _job_walls: ProjectileWalls = null
var _targets: Array
var _target_radius: PackedFloat32Array
var _target_half: PackedVector2Array
var _target_layer: PackedInt32Array
var _target_pos: PackedVector2Array
var _cell_head: PackedInt32Array
var _target_next: PackedInt32Array
var _room_grid: RoomGrid
var _ray_nodes: Array[Array]
var _ray_along: Array[Array]
var _ray_points: Array[Array]
var _ray_heads: Array[Array]
var _ray_walks: Array[Array]
var _ray_turns: Array[Array]
var _path: PackedVector2Array
var ray_path: PackedVector2Array
var sweep_nodes: Array
var sweep_points: PackedVector2Array
var sweep_heads: PackedVector2Array


## Takes the manager's arrays and jobs, by the names in DERIVED: again whenever the manager's arrays
## may have been replaced (`ProjectileManager._link_jobs`).
func link(manager: Manager) -> void:
	pm = manager
	for name: StringName in DERIVED:
		if name != &"pm":
			set(name, manager.get(name))


func ray(caster: int, origin: Vector2, direction: Vector2, length: float, pierce: int = 0, layers: int = Manager.LAYER_ENEMY, tag: int = 0, width: float = 0.0, exclude: Node = null, bounces: int = 0, ghost: bool = false) -> float:
	pm.ray_path_count = 0
	if not direction.is_finite() or direction.is_zero_approx() or not is_finite(length) or length <= 0.0 or not origin.is_finite():
		return _no_ray()
	_path[0] = origin
	_path[1] = origin + direction.normalized() * length
	return _ray_path(caster, 1, pierce, layers, tag, width, exclude, true, bounces, Callable(), ghost)


## A beam like `ray` along the path `points[offset]` to `points[offset + count - 1]`, cut to
## `length` pixels along it: a live beam, whose homing bends it from target to target, and which
## never reaches past its own length. With `hit` false it only finds how far the beam gets
## (walls, and the target that spends it) and sends nothing, for the look of a beam between its
## hits. With `bounces` it turns at walls as `ray` does, and goes on from there along `steer`'s
## path when it is given one (a homing beam homes again after every turn: `steer.call(turn, at,
## way, left)` gets the turn's index in the path, where it is, the way off the wall and the length
## left, and returns the points that follow `at`; empty for straight on), else straight. A
## `ghost` one passes through walls. Returns how far it got along the path; `ray_end` and
## `ray_end_heading` say where, and `ray_path` what it walked.
func ray_points(caster: int, points: PackedVector2Array, offset: int, count: int, length: float, pierce: int = 0, layers: int = Manager.LAYER_ENEMY, tag: int = 0, width: float = 0.0, exclude: Node = null, hit: bool = true, bounces: int = 0, steer: Callable = Callable(), ghost: bool = false) -> float:
	pm.ray_path_count = 0
	if count < 2 or offset < 0 or offset + count > points.size() or not is_finite(length) or length <= 0.0 or not points[offset].is_finite():
		return _no_ray()
	_fit_path(count)
	_path[0] = points[offset]
	var total: float = 0.0
	var used: int = 0
	for i in range(1, count):
		var point: Vector2 = points[offset + i]
		if not point.is_finite():
			break
		var piece: float = _path[i - 1].distance_to(point)
		used = i
		if total + piece >= length:
			_path[i] = _path[i - 1].move_toward(point, length - total)
			break
		total += piece
		_path[i] = point
	if used == 0:
		return _no_ray()
	return _ray_path(caster, used, pierce, layers, tag, width, exclude, hit, bounces, steer, ghost)


## `_path`'s first `used` pieces with the first `air` pixels taken off its start (`ray_air`): returns
## how many pieces are left, 0 when the whole path is shorter.
func _trim_path(used: int, air: float) -> int:
	var left: float = air
	var first: int = 0
	while first < used:
		var piece: float = _path[first].distance_to(_path[first + 1])
		if piece > left:
			_path[first] = _path[first].move_toward(_path[first + 1], left)
			break
		left -= piece
		first += 1
	if first >= used:
		return 0
	for i in range(first, used + 1):
		_path[i - first] = _path[i]
	return used - first


## A beam like `ray`, bent: it follows the quadratic curve from `origin` to `end` pulled
## toward `bend` (a homing beam: `bend` along the aim, `end` on the target), walked as
## RAY_SEGMENTS straight pieces. With `hit` false it only finds how far the beam gets (walls, and
## the target that spends it) and sends nothing, for the look of a beam between its hits. With
## `bounces` it turns at walls as `ray` does. Returns how far it got along the curve; `ray_end`
## and `ray_end_heading` say where, and `ray_path` what it walked.
func ray_curve(caster: int, origin: Vector2, bend: Vector2, end: Vector2, pierce: int = 0, layers: int = Manager.LAYER_ENEMY, tag: int = 0, width: float = 0.0, exclude: Node = null, hit: bool = true, bounces: int = 0) -> float:
	pm.ray_path_count = 0
	if not origin.is_finite() or not bend.is_finite() or not end.is_finite() or origin.is_equal_approx(end):
		return _no_ray()
	_path[0] = origin
	for i in range(1, Manager.RAY_SEGMENTS + 1):
		var t: float = float(i) / Manager.RAY_SEGMENTS
		var u: float = 1.0 - t
		_path[i] = origin * (u * u) + bend * (2.0 * u * t) + end * (t * t)
	return _ray_path(caster, Manager.RAY_SEGMENTS, pierce, layers, tag, width, exclude, hit, bounces)


## A ray that is not cast: its `ray_cast_by` is used up all the same.
func _no_ray() -> float:
	pm._ray_caster = -1
	pm.ray_gates = false
	pm.ray_air = 0.0
	_set_ray_gate(-1, Vector2.INF, Vector2.ZERO, 0.0)
	return 0.0


## `_path` holds at least `count` points.
func _fit_path(count: int) -> void:
	if _path.size() < count:
		_path.resize(maxi(count, _path.size() * 2))


## The scratch of nesting level `level`, made the first time a ray goes that deep.
func _ray_level(level: int) -> void:
	while _ray_nodes.size() <= level:
		_ray_nodes.append([])
		_ray_along.append([])
		_ray_points.append([])
		_ray_heads.append([])
		_ray_walks.append([])
		_ray_turns.append([])


## The bodies a swing's sweep touches (melee I2): every target on `layers` (and ACTOR_LAYERS, as
## in `ray`) whose hit shape reaches into the wedge round `origin` from `from_angle` to
## `to_angle` radians off `direction` (`side` 1 counts clockwise on screen, -1 the other way;
## `to_angle` not below `from_angle`), out to `reach` pixels, with no wall between it and
## `origin`. Only `exclude` is skipped (the body it is cast from: its caster's own body is hit
## like any other). It sends nothing: it
## fills `sweep_nodes`, `sweep_points` (where the wedge meets the body, on its line from
## `origin`; for a whole circle `origin` itself, what strikes from there) and `sweep_heads` (the
## way the sweep moves there: round `origin`, or outward for a whole circle) and returns how many (every one: the results grow). Each step of a swing asks for
## the wedge it turned through since the last, so a fast sweep misses nothing between two steps.
## Without `walls` a wall between hides nothing (an explosion). Allocation-free.
func sweep(caster: int, origin: Vector2, direction: Vector2, side: int, from_angle: float, to_angle: float, reach: float, layers: int = Manager.LAYER_ENEMY, exclude: Node = null, walls: bool = true) -> int:
	if not Manager.is_caster(caster) or not origin.is_finite() or not direction.is_finite() or direction.is_zero_approx():
		return 0
	if not is_finite(reach) or reach <= 0.0 or not is_finite(from_angle) or not is_finite(to_angle) or to_angle < from_angle or _targets.is_empty():
		return 0
	_job_targets._query_ready()
	layers |= Manager.ACTOR_LAYERS
	var base: float = DMath.angle(direction)
	var turn: float = 1.0 if side >= 0 else -1.0
	var whole: bool = to_angle - from_angle >= TAU
	var skip: int = pm._target_row(exclude)
	var pad: Vector2 = Vector2.ONE * (reach + pm._max_target_reach)
	var x0: int = clampi(floori((origin.x - pad.x - pm._bounds.position.x) / Manager.GRID_CELL), 0, pm._grid_w - 1)
	var x1: int = clampi(floori((origin.x + pad.x - pm._bounds.position.x) / Manager.GRID_CELL), 0, pm._grid_w - 1)
	var y0: int = clampi(floori((origin.y - pad.y - pm._bounds.position.y) / Manager.GRID_CELL), 0, pm._grid_h - 1)
	var y1: int = clampi(floori((origin.y + pad.y - pm._bounds.position.y) / Manager.GRID_CELL), 0, pm._grid_h - 1)
	var found: int = 0
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var t: int = _cell_head[y * pm._grid_w + x]
			while t >= 0:
				if (_target_layer[t] & layers) != 0 and t != skip and is_instance_valid(_targets[t]):
					var to: Vector2 = _target_pos[t] - origin
					var radius: float = _target_radius[t]
					var box: Vector2 = _target_half[t]
					var distance: float = to.length()
					# How far `origin` is from the shape's box (a circle's centre).
					var off: float = HitShape.gap(to, box)
					if off <= reach + radius:
						# How far either side of its centre line the body's shape reaches, counted the
						# sweep's way round: a circle's the same both ways (in doubles), a box's
						# `HitShape.sides`; all round from on it.
						var low: float = -PI
						var high: float = PI
						if off > radius:
							if box == Vector2.ZERO:
								high = DMath.asin(radius / distance)
								low = -high
							else:
								var sides: Vector2 = HitShape.sides(to, box, radius)
								low = sides.x if turn > 0.0 else -sides.y
								high = sides.y if turn > 0.0 else -sides.x
						var local: float = angle_difference(base, DMath.angle(to)) * turn
						if local + high >= from_angle and local + low <= to_angle and not (walls and _room_grid.wall_hit(origin, _target_pos[t]) >= 0.0):
							var way: Vector2 = to / distance if distance > 0.0 else direction.normalized()
							if found == sweep_nodes.size():
								sweep_nodes.resize(found * 2)
								sweep_points.resize(found * 2)
								sweep_heads.resize(found * 2)
							sweep_nodes[found] = _targets[t]
							sweep_points[found] = origin if whole else origin + way * maxf(distance - HitShape.reach_toward(box, radius, way), 0.0)
							sweep_heads[found] = way if whole else Vector2(-way.y, way.x) * turn
							found += 1
				t = _target_next[t]
	return found


## One hit of an instant carrier on `target` (a swing's, `sweep`): `projectile_impact` with `carrier_card`
## for its look, then `projectile_hit(caster, target, point, tag)`, as a beam's hit sends them.
## Returns false when it sent nothing (no events, or a gone target). It nests one ray level, as a
## ray's hits do, so a ray its handlers fire has scratch of its own.
func strike(caster: int, target: Node, point: Vector2, heading: Vector2, tag: int, carrier_card: StringName) -> bool:
	var events: Manager.EventsScript = pm.events
	if events == null or not is_instance_valid(target) or not Manager.is_caster(caster):
		return false
	pm._ray_depth += 1
	var outer_slot: int = pm._event_slot
	pm._event_slot = -1
	pm.impact_carrier_card = carrier_card
	pm.impact_core = Color.WHITE
	pm.impact_look = 0
	pm.impact_tag = 0
	pm._sent += 1
	events.projectile_impact.emit(caster, target, point, heading)
	pm.impact_carrier_card = &""
	# One hit, whatever merged hit's handler struck it (`impact_count`).
	var outer_count: int = pm.impact_count
	pm.impact_count = 1
	pm._sent += 1
	events.projectile_hit.emit(caster, target, point, tag, -1)
	pm.impact_count = outer_count
	pm._ray_depth -= 1
	pm._event_slot = outer_slot
	return true


## The beam along the first `segments` pieces of `_path` (see `ray` and `ray_curve`).
func _ray_path(caster: int, segments: int, pierce: int, layers: int, tag: int, width: float, exclude: Node, hit: bool, bounces: int = 0, steer: Callable = Callable(), ghost: bool = false) -> float:
	var events: Manager.EventsScript = pm.events
	var air: float = pm.ray_air
	if air > 0.0:
		# Its first `ray_air` pixels are in the air (a falling beam): walked touching nothing.
		pm.ray_air = 0.0
		var left: int = _trim_path(segments, air)
		if left == 0:
			_no_ray()
			return air
		return air + _ray_path(caster, left, pierce, layers, tag, width, exclude, hit, bounces, steer, ghost)
	pm.ray_end = Vector2.INF
	pm.ray_end_heading = Vector2.ZERO
	pm.ray_path_count = 0
	pm.ray_gate = -1
	pm.ray_gate_at = Vector2.INF
	pm.ray_gate_heading = Vector2.ZERO
	pm.ray_gate_left = 0.0
	# The flag is for this ray alone: a ray its hit handlers send (a zap, a jump) passes gates by.
	var gates: bool = pm.ray_gates and pm._gate_live > 0
	pm.ray_gates = false
	var g_gate: int = -1
	var g_at: Vector2 = Vector2.INF
	var g_heading: Vector2 = Vector2.ZERO
	var g_left: float = 0.0
	# A wall's own ray leaves it: its row is lifted while the ray walks (`ray_cast_by`).
	var own: Manager.Solid = _job_walls._solid_of(pm._ray_caster, pm._ray_caster_seq)
	pm._ray_caster = -1
	if not Manager.is_caster(caster):
		return 0.0
	var level: int = pm._ray_depth
	_ray_level(level)
	if own != null:
		_job_walls._mark_solid(own, -1)
	# Cut the path at the first wall, or turn there while it has bounces: the rest of the path
	# is dropped and it goes on, off the wall, for the length the rest had: along `steer`'s path
	# (a homing beam homes again), else straight.
	var left_turns: int = maxi(bounces, 0)
	var left: float = 0.0
	if left_turns > 0 or gates:
		for i in segments:
			left += _path[i].distance_to(_path[i + 1])
	var reach: float = 0.0
	var walled: bool = false
	var used: int = 0
	# The turns: their indices in the path, `turned` of them.
	var turns: Array = _ray_turns[level]
	var turned: int = 0
	var at_piece: int = 0
	while at_piece < segments:
		var a: Vector2 = _path[at_piece]
		var b: Vector2 = _path[at_piece + 1]
		var piece: float = a.distance_to(b)
		used = at_piece + 1
		# A gate before the wall (or with no wall): the ray stops where it goes in, and its beam
		# goes on from the other side (`ray_gate`).
		var gate_at: float = _job_places.gate_cut(a, b) if gates else -1.0
		if gate_at >= 0.0:
			var wall_at: float = _room_grid.wall_hit(a, b) if not ghost else -1.0
			if wall_at < 0.0 or gate_at <= wall_at:
				var into: Vector2 = a.lerp(b, gate_at)
				g_gate = pm.gate_hit
				g_at = into
				g_heading = (b - a) / piece if piece > 0.0 else Vector2.ZERO
				g_left = maxf(left - piece * gate_at, 0.0)
				_path[at_piece + 1] = into
				reach += piece * gate_at
				break
		if _room_grid.has_walls() and not ghost:
			# A ray walks every cell it crosses, however long it is.
			var cut: float = _room_grid.wall_hit(a, b)
			if cut >= 0.0:
				var at: Vector2 = a.lerp(b, cut)
				var heading: Vector2 = (b - a) / piece if piece > 0.0 else Vector2.ZERO
				left -= piece * cut
				if left_turns > 0 and reach + piece * cut > 0.0 and left > 0.5 and not heading.is_zero_approx():
					# Step back out of the wall, as a bouncing shot does, and turn there.
					if turns.size() <= turned:
						turns.resize(maxi(8, turned * 2))
					turns[turned] = at_piece + 1
					turned += 1
					left_turns -= 1
					at -= heading * 0.5
					left += 0.5
					reach += a.distance_to(at)
					var way: Vector2 = _job_walls._bounced(at, heading, heading)
					_fit_path(at_piece + 2)
					_path[at_piece + 1] = at
					var added: int = 0
					if steer.is_valid():
						# Its own path from the turn on, cut to the length it has left.
						var more: PackedVector2Array = steer.call(at_piece + 1, at, way, left)
						var from: Vector2 = at
						var gone: float = 0.0
						for point in more:
							if not point.is_finite() or gone >= left:
								break
							var step: float = from.distance_to(point)
							_fit_path(at_piece + 3 + added)
							if gone + step >= left:
								point = from.move_toward(point, left - gone)
								step = left - gone
							_path[at_piece + 2 + added] = point
							added += 1
							gone += step
							from = point
					if added == 0:
						_fit_path(at_piece + 3)
						_path[at_piece + 2] = at + way * left
						added = 1
					segments = at_piece + 1 + added
					at_piece += 1
					continue
				walled = true
				_path[at_piece + 1] = at
				reach += piece * cut
				break
		left -= piece
		reach += piece
		at_piece += 1
	if own != null:
		_job_walls._mark_solid(own, 1)
	var nodes: Array = _ray_nodes[level]
	var alongs: Array = _ray_along[level]
	var points: Array = _ray_points[level]
	var heads: Array = _ray_heads[level]
	var wanted: int = maxi(pierce, 0) + 1
	var found: int = 0
	if not _targets.is_empty() and reach > 0.0:
		_job_targets._query_ready()
		layers |= Manager.ACTOR_LAYERS
		var wide: float = maxf(width, 0.0)
		var pad: Vector2 = Vector2.ONE * (wide + pm._max_target_reach)
		var start: float = 0.0
		# `exclude`, the body it is cast from (the caller found it starts on it), is spared until a
		# later piece of the path starts off it (as a shot's step does, `exclude`): a beam that
		# bounces or bends back into it hits it.
		var skip_at: int = pm._target_row(exclude)
		for i in used:
			var a: Vector2 = _path[i]
			var b: Vector2 = _path[i + 1]
			if skip_at >= 0 and i > 0:
				var on: float = wide + _target_radius[skip_at]
				if HitShape.gap_sq(a - _target_pos[skip_at], _target_half[skip_at]) > on * on:
					skip_at = -1
			var piece: float = a.distance_to(b)
			if piece <= 0.0:
				continue
			var heading: Vector2 = (b - a) / piece
			var low: Vector2 = a.min(b) - pad
			var high: Vector2 = a.max(b) + pad
			var x0: int = clampi(floori((low.x - pm._bounds.position.x) / Manager.GRID_CELL), 0, pm._grid_w - 1)
			var x1: int = clampi(floori((high.x - pm._bounds.position.x) / Manager.GRID_CELL), 0, pm._grid_w - 1)
			var y0: int = clampi(floori((low.y - pm._bounds.position.y) / Manager.GRID_CELL), 0, pm._grid_h - 1)
			var y1: int = clampi(floori((high.y - pm._bounds.position.y) / Manager.GRID_CELL), 0, pm._grid_h - 1)
			for y in range(y0, y1 + 1):
				for x in range(x0, x1 + 1):
					var t: int = _cell_head[y * pm._grid_w + x]
					while t >= 0:
						if (_target_layer[t] & layers) != 0 and t != skip_at and is_instance_valid(_targets[t]):
							var box: Vector2 = _target_half[t]
							var along: float = 0.0
							if box == Vector2.ZERO:
								along = clampf((_target_pos[t] - a).dot(heading), 0.0, piece)
							else:
								var span: Vector2 = b - a
								along = HitShape.along(a, span, span.length_squared(), _target_pos[t], box) * piece
							var closest: Vector2 = a + heading * along
							var touch: float = wide + _target_radius[t]
							if HitShape.gap_sq(closest - _target_pos[t], box) <= touch * touch:
								found = _ray_keep(nodes, alongs, points, heads, found, wanted, t, start + along, closest, heading)
						t = _target_next[t]
			start += piece
	var got: float = reach
	if found > 0 and found == wanted:
		# The beam is spent on its last target.
		got = alongs[found - 1]
		walled = false
		if got < reach - 0.001:
			# Spent before the gate: it never got there.
			g_gate = -1
	var end: Vector2 = _path_point(used, got)
	var end_heading: Vector2 = pm._path_heading
	# What it walked, kept for `ray_path` (and its turns' events) past the hit handlers' rays.
	var walk: Array = _ray_walks[level]
	var walked: int = pm._path_piece + 2
	if walk.size() < walked:
		walk.resize(walked)
	for n in pm._path_piece + 1:
		walk[n] = _path[n]
	walk[pm._path_piece + 1] = end
	if not hit:
		for n in found:
			nodes[n] = null
		pm.ray_end = end
		pm.ray_end_heading = end_heading
		_keep_ray_path(walk, walked)
		_set_ray_gate(g_gate, g_at, g_heading, g_left)
		return got
	pm._ray_depth += 1
	var outer_slot: int = pm._event_slot
	pm._event_slot = -1
	for i in found:
		var node: Variant = nodes[i]
		if events != null and is_instance_valid(node):
			pm.impact_carrier_card = &"beam"
			pm.impact_core = Color.WHITE
			pm.impact_look = 0
			pm.impact_tag = 0
			pm._sent += 1
			events.projectile_impact.emit(caster, node, points[i], heads[i])
			pm.impact_carrier_card = &""
			pm.impact_core = Color.WHITE
			pm.impact_look = 0
			# One hit, whatever merged hit's handler fired the ray (`impact_count`).
			var outer_count: int = pm.impact_count
			pm.impact_count = 1
			pm._sent += 1
			events.projectile_hit.emit(caster, node, points[i], tag, -1)
			pm.impact_count = outer_count
		nodes[i] = null
	# A spark at every wall it turned at before it ended, and at the wall it ended on; then
	# `wall_met` for each (a handler's payload may fire rays: this level's scratch is kept).
	for k in turned:
		var n: int = turns[k]
		if n >= walked - 1:
			break
		var turn: Vector2 = walk[n]
		if events != null:
			pm.impact_carrier_card = &"beam"
			pm.impact_core = Color.WHITE
			pm.impact_look = 0
			pm.impact_tag = 0
			pm._sent += 1
			events.projectile_impact.emit(caster, null, turn, (walk[n - 1] as Vector2).direction_to(turn))
			pm.impact_carrier_card = &""
			pm.impact_core = Color.WHITE
			pm.impact_look = 0
	if walled and events != null:
		pm.impact_carrier_card = &"beam"
		pm.impact_core = Color.WHITE
		pm.impact_look = 0
		pm.impact_tag = 0
		pm._sent += 1
		events.projectile_impact.emit(caster, null, end, end_heading)
		pm.impact_carrier_card = &""
		pm.impact_core = Color.WHITE
		pm.impact_look = 0
	for k in turned:
		var n: int = turns[k]
		if n >= walked - 1:
			break
		var turn: Vector2 = walk[n]
		pm._sent += 1
		pm.wall_met.emit(caster, turn, turn.direction_to(walk[n + 1]), tag, -1)
	if walled:
		pm._sent += 1
		pm.wall_met.emit(caster, end - end_heading * 0.5, end_heading, tag, -1)
	pm._ray_depth -= 1
	pm._event_slot = outer_slot
	pm.ray_end = end
	pm.ray_end_heading = end_heading
	_keep_ray_path(walk, walked)
	_set_ray_gate(g_gate, g_at, g_heading, g_left)
	return got


## What the last ray says of the gate it stopped at (`ray_gate`).
func _set_ray_gate(gate: int, at: Vector2, heading: Vector2, left: float) -> void:
	pm.ray_gate = gate
	pm.ray_gate_at = at
	pm.ray_gate_heading = heading
	pm.ray_gate_left = left


## Copy the first `count` points of `walk` into `ray_path`.
func _keep_ray_path(walk: Array, count: int) -> void:
	if ray_path.size() < count:
		ray_path.resize(maxi(count, ray_path.size() * 2))
	for n in count:
		ray_path[n] = walk[n]
	pm.ray_path_count = count


## The point `distance` pixels along the first `segments` pieces of `_path`; its heading there
## is left in `_path_heading`, and the piece it is on in `_path_piece`.
func _path_point(segments: int, distance: float) -> Vector2:
	var left: float = maxf(distance, 0.0)
	pm._path_heading = Vector2.ZERO
	pm._path_piece = 0
	for i in segments:
		var a: Vector2 = _path[i]
		var b: Vector2 = _path[i + 1]
		var piece: float = a.distance_to(b)
		pm._path_piece = i
		if piece > 0.0:
			pm._path_heading = (b - a) / piece
		if left <= piece or i == segments - 1:
			return a + pm._path_heading * minf(left, piece)
		left -= piece
	return _path[0]


## Put target `t` (at `along` pixels, nearest point `closest`, the beam heading `heading` there)
## into a level's sorted scratch of the best hits (`nodes`, `alongs`, `points`, `heads`) if it is
## among the `wanted` nearest; returns the new count. A target a bent beam touches on two pieces
## keeps its nearer place. The scratch grows when it is full.
func _ray_keep(nodes: Array, alongs: Array, points: Array, heads: Array, found: int, wanted: int, t: int, along: float, closest: Vector2, heading: Vector2) -> int:
	for i in found:
		if nodes[i] == _targets[t]:
			if along >= alongs[i]:
				return found
			# Nearer on this piece: take it out and insert it again below.
			for j in range(i, found - 1):
				alongs[j] = alongs[j + 1]
				points[j] = points[j + 1]
				nodes[j] = nodes[j + 1]
				heads[j] = heads[j + 1]
			found -= 1
			nodes[found] = null
			break
	if found == wanted and along >= alongs[found - 1]:
		return found
	if found == nodes.size():
		var size: int = maxi(16, found * 2)
		nodes.resize(size)
		alongs.resize(size)
		points.resize(size)
		heads.resize(size)
	var at: int = mini(found, wanted - 1)
	while at > 0 and alongs[at - 1] > along:
		alongs[at] = alongs[at - 1]
		points[at] = points[at - 1]
		nodes[at] = nodes[at - 1]
		heads[at] = heads[at - 1]
		at -= 1
	alongs[at] = along
	points[at] = closest
	nodes[at] = _targets[t]
	heads[at] = heading
	return mini(found + 1, wanted)
