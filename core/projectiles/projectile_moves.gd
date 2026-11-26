class_name ProjectileMoves
extends Object
## The projectile manager's motion (core/projectiles/projectile_manager.gd, "Shot behaviours, stepped
## in passes"): the common pass and the trail pass, the behaviour lists (`_join`, `_leave`, `_wait`),
## each behaviour's pass, orbits, casters and a card's moves, and the turns and homing they share.
## Methods working on the manager (`pm`), whose members hold all of it.

const Manager := preload("res://core/projectiles/projectile_manager.gd")

## Not state (core/sim/README.md): the manager, the other jobs this one calls and the manager's
## arrays it works on, each the manager's own array (shared, never a copy), linked by `link`.
const DERIVED: Array[StringName] = [&"pm", &"_job_guards", &"_job_hits", &"_job_targets", &"_pos", &"_prev", &"_vel", &"_life", &"_radius", &"_actor", &"_team", &"_layers", &"_motion", &"_orbit_radius", &"_orbit_angle", &"_orbit_drift", &"_orbit_way", &"_orbit_from", &"_orbit_centre", &"_turn", &"_home_at", &"_home_range", &"_home_target", &"_seq", &"_flags", &"_shield", &"_deflect", &"_span", &"_radius0", &"_growth", &"_curve_from", &"_floor", &"_trail", &"_trail_x", &"_trail_y", &"_trail_out", &"_curve_to", &"_curve_ease", &"_curve_speed", &"_wave", &"_wave_age", &"_base", &"_linger", &"_hold", &"_freeze", &"_stuck_to", &"_stuck_off", &"_speed", &"_caster_slot", &"_caster_seq", &"_caster_at", &"_move_head", &"_move_left", &"_move_vel", &"_move_turn", &"_move_range", &"_move_home", &"_move_curve", &"_move_total", &"_move_next", &"_members", &"_member_count", &"_member_at", &"_kinds", &"_passes", &"_state", &"_wait_state", &"_wait_from", &"_one", &"_shield_order", &"_target_mark", &"_alive", &"_targets", &"_target_radius", &"_target_half", &"_target_layer", &"_target_pos", &"_target_key", &"_target_owner", &"_target_team", &"_cell_head", &"_target_next", &"_born", &"_anchors", &"_tail_from"]

var pm: Manager = null
var _job_guards: ProjectileGuards = null
var _job_hits: ProjectileHits = null
var _job_targets: ProjectileTargets = null
var _pos: PackedVector2Array
var _prev: PackedVector2Array
var _vel: PackedVector2Array
var _life: PackedFloat32Array
var _radius: PackedFloat32Array
var _actor: PackedInt32Array
var _team: PackedInt32Array
var _layers: PackedInt32Array
var _motion: PackedByteArray
var _orbit_radius: PackedFloat32Array
var _orbit_angle: PackedFloat32Array
var _orbit_drift: PackedFloat32Array
var _orbit_way: PackedFloat32Array
var _orbit_from: PackedFloat32Array
var _orbit_centre: PackedVector2Array
var _turn: PackedFloat32Array
var _home_at: PackedVector2Array
var _home_range: PackedFloat32Array
var _home_target: PackedInt64Array
var _seq: PackedInt64Array
var _flags: PackedInt32Array
var _shield: PackedInt32Array
var _deflect: PackedByteArray
var _span: PackedFloat32Array
var _radius0: PackedFloat32Array
var _growth: PackedFloat32Array
var _curve_from: PackedFloat32Array
var _floor: PackedFloat32Array
var _trail: PackedByteArray
var _trail_x: PackedInt32Array
var _trail_y: PackedInt32Array
var _trail_out: PackedInt32Array
var _curve_to: PackedFloat32Array
var _curve_ease: PackedFloat32Array
var _curve_speed: PackedFloat32Array
var _wave: PackedFloat32Array
var _wave_age: PackedFloat32Array
var _base: PackedVector2Array
var _linger: PackedFloat32Array
var _hold: PackedFloat32Array
var _freeze: PackedFloat32Array
var _stuck_to: Array
var _stuck_off: PackedVector2Array
var _speed: PackedFloat32Array
var _caster_slot: PackedInt32Array
var _caster_seq: PackedInt64Array
var _caster_at: PackedVector2Array
var _move_head: PackedInt32Array
var _move_left: PackedFloat32Array
var _move_vel: PackedVector2Array
var _move_turn: PackedFloat32Array
var _move_range: PackedFloat32Array
var _move_home: PackedInt64Array
var _move_curve: PackedVector3Array
var _move_total: PackedFloat32Array
var _move_next: PackedInt32Array
var _members: PackedInt32Array
var _member_count: PackedInt32Array
var _member_at: PackedInt32Array
var _kinds: PackedInt32Array
var _passes: Array[Callable]
var _state: PackedByteArray
var _wait_state: PackedByteArray
var _wait_from: PackedByteArray
var _one: PackedInt32Array
var _shield_order: PackedInt32Array
var _target_mark: PackedInt32Array
var _alive: PackedByteArray
var _targets: Array
var _target_radius: PackedFloat32Array
var _target_half: PackedVector2Array
var _target_layer: PackedInt32Array
var _target_pos: PackedVector2Array
var _target_key: PackedInt64Array
var _target_owner: PackedInt32Array
var _target_team: PackedInt32Array
var _cell_head: PackedInt32Array
var _target_next: PackedInt32Array
var _born: PackedFloat32Array
var _anchors: PackedVector2Array
var _tail_from: PackedVector2Array


## Takes the manager's arrays and jobs, by the names in DERIVED: again whenever the manager's arrays
## may have been replaced (`ProjectileManager._link_jobs`).
func link(manager: Manager) -> void:
	pm = manager
	for name: StringName in DERIVED:
		if name != &"pm":
			set(name, manager.get(name))


## The live straight or still shot in `slot` circles its caster from now on (the Orbit card,
## core/spells/orbit.gd): its actor's anchor (see `set_anchor`), or with a finite `centre` that
## point (a payload's orbit, whose caster is a shot or the point where one ended; `set_caster_shot`
## then makes it follow the shot). It goes onto the circle `orbit_radius` pixels out at `angle`
## (radians, 0 = east) and turns `drift` radians a second plus its own speed over the radius
## (`_orbit_turn`: its speed curve still acts, so Faster, Slow and the curve cards turn it faster
## or slower; a still one has no speed and turns by its drift). Its motion is the circle's, so what
## steers or turns a straight flight is refused or leaves it (homing, return, spiral's line: a
## spiral weaves its radius instead; a bounce turns it back round its circle, `_wall_end`), and its
## speed curve (`set_speed_curve`, before or after) is read by the orbit pass. Everything else is
## its own: its body (a still one stays a quad, `F_QUAD`), look, hits, pierce, ghost, walls (a
## solid one stops at a room wall and its row turns with it, `_step_solid`). False (and nothing
## changes) for a slot that is no live straight or still shot, bad numbers, or no centre (no
## `centre` and no anchor for its actor).
func set_orbit(slot: int, orbit_radius: float, angle: float, drift: float, centre: Vector2 = Vector2.INF) -> bool:
	if slot < 0 or slot >= pm._cap or _alive[slot] == 0 or _motion[slot] == Manager.MOTION_ORBIT or not is_finite(orbit_radius) or not is_finite(angle) or not is_finite(drift):
		return false
	var actor: int = _actor[slot]
	if not centre.is_finite() and (actor < 0 or actor >= Manager.ACTORS or not _anchors[actor].is_finite()):
		return false
	var around: Vector2 = centre if centre.is_finite() else _anchors[actor]
	if centre.is_finite():
		_caster_slot[slot] = Manager.CASTER_POINT
		_caster_at[slot] = centre
	# Its speed without its curve: the curve's own, or the speed it has (a curve of factor 1 until
	# one is set).
	if (_kinds[slot] >> Manager.B_CURVE) & 1 == 0:
		_curve_speed[slot] = _vel[slot].length()
	_leave(slot, Manager.B_CURVE)
	_leave(slot, Manager.B_HOMING)
	_leave(slot, Manager.B_RETURN)
	_leave(slot, Manager.B_SPIRAL)
	_flags[slot] &= ~Manager.F_RETURN
	_turn[slot] = 0.0
	_motion[slot] = Manager.MOTION_ORBIT
	_orbit_radius[slot] = maxf(orbit_radius, 0.0)
	_orbit_angle[slot] = angle
	_orbit_drift[slot] = drift
	_orbit_way[slot] = 1.0
	_join(slot, Manager.B_ORBIT)
	_orbit_from[slot] = angle
	_pos[slot] = around + DMath.from_angle(angle) * _orbit_radius[slot]
	_prev[slot] = _pos[slot]
	_base[slot] = _pos[slot]
	_vel[slot] = _orbit_tangent(slot, 0.0)
	pm._threat_step = -1
	# It is drawn spiralling out from its caster (`_drawn_at`), so its tail starts there.
	_orbit_centre[slot] = around
	_tail_from[slot] = around
	return true


func _caster_position(slot: int) -> Vector2:
	var caster: int = _caster_slot[slot]
	if caster == Manager.CASTER_BODY:
		return _anchors[_actor[slot]] if _actor[slot] >= 0 else Vector2.INF
	if caster >= 0:
		# A caster shot its hits spent this pass is as gone as one they ended.
		if _alive[caster] != 0 and _seq[caster] == _caster_seq[slot] and (_flags[caster] & Manager.F_SPENT) == 0:
			# Mid-step, a caster shot whose turn in the hit pass has not come is where it was before
			# the step (the passes moved it already; see `step`).
			var state: int = _state[caster]
			_caster_at[slot] = _prev[caster] if pm._stepping and state != Manager.S_DONE and state != Manager.S_IDLE else _pos[caster]
		else:
			# The caster is gone: from now on the shot keeps to where it was last seen.
			_caster_slot[slot] = Manager.CASTER_POINT
	return _caster_at[slot]


## Move the shot in `slot` by `offset` pixels over `seconds` on top of its own motion (a dash,
## pull or recoil card whose caster is this shot), or at once for `seconds` 0 or less (a
## teleport or swap, stopped short at the first wall). Moves add up, as the wizard's pushes do: a
## new move runs beside the ones under way, each on its own time (two opposite pushes cancel, a
## pull after a recoil gets both). A moving shot still hits what it passes and still ends on a
## wall. A homing move (`turn_rate` above 0) turns toward the nearest
## target within `within` pixels as it goes (`home_velocity`), the same distance in all. A move
## with a speed `curve` (`MoveCurve`: a dash's cards', boss plan OB10) goes its way at the curve's
## speed, still the whole of it in its time.
## Returns false for an empty slot, an orbit shot (its caster holds it), or an offset or time
## that is not finite.
func move_shot(slot: int, offset: Vector2, seconds: float, turn_rate: float = 0.0, within: float = 0.0, curve: Vector3 = MoveCurve.NONE) -> bool:
	if slot < 0 or slot >= pm._cap or _alive[slot] == 0 or _motion[slot] == Manager.MOTION_ORBIT:
		return false
	if not offset.is_finite() or not is_finite(seconds):
		return false
	pm._threat_step = -1
	if seconds <= 0.0:
		var to: Vector2 = pm.clip_to_walls(_pos[slot], _pos[slot] + offset) if (_flags[slot] & Manager.F_GHOST) == 0 else _pos[slot] + offset
		_base[slot] += to - _pos[slot]
		_pos[slot] = to
		_prev[slot] = to
		# A blink leaves no tail across the gap, and sweeps no hits across it: a deferred shot's
		# path before it goes untested (only a hit handler blinks a shot).
		_flags[slot] &= ~Manager.F_DEFERRED
		_tail_from[slot] = to
		return true
	if pm._move_free < 0:
		_grow_moves(_move_left.size() * 2)
	var at: int = pm._move_free
	pm._move_free = _move_next[at]
	_move_left[at] = seconds
	_move_vel[at] = offset / seconds
	var homes: bool = turn_rate > 0.0 and within > 0.0 and is_finite(turn_rate) and is_finite(within)
	_move_turn[at] = turn_rate if homes else 0.0
	_move_range[at] = within if homes else 0.0
	_move_home[at] = 0
	_move_curve[at] = curve if MoveCurve.shapes(curve) else MoveCurve.NONE
	_move_total[at] = seconds
	# At the end of the list, so the moves run in the order they were asked.
	_move_next[at] = -1
	var last: int = _move_head[slot]
	if last < 0:
		_move_head[slot] = at
	else:
		while _move_next[last] >= 0:
			last = _move_next[last]
		_move_next[last] = at
	_join(slot, Manager.B_MOVE)
	return true


## End every move of the shot in `slot` (it is new or it ended).
func _drop_moves(slot: int) -> void:
	var at: int = _move_head[slot]
	while at >= 0:
		var next: int = _move_next[at]
		_move_next[at] = pm._move_free
		pm._move_free = at
		at = next
	_move_head[slot] = -1


## Room for `size` moves under way in all (the new entries go on the free list).
func _grow_moves(size: int) -> void:
	var old: int = _move_left.size()
	_move_left.resize(size)
	_move_vel.resize(size)
	_move_turn.resize(size)
	_move_range.resize(size)
	_move_home.resize(size)
	_move_curve.resize(size)
	_move_total.resize(size)
	_move_next.resize(size)
	for at in range(size - 1, old - 1, -1):
		_move_next[at] = pm._move_free
		pm._move_free = at


## Homing of `bend` radians a pixel flown (see `set_homing`).
func _set_homing(slot: int, bend: float, within: float) -> bool:
	if slot < 0 or slot >= pm._cap or _alive[slot] == 0 or _motion[slot] == Manager.MOTION_ORBIT:
		return false
	if not is_finite(bend) or bend < 0.0 or not is_finite(within) or within <= 0.0:
		return false
	_turn[slot] = bend
	_home_range[slot] = within
	_home_target[slot] = 0
	_home_at[slot] = Vector2.INF
	if bend > 0.0:
		_join(slot, Manager.B_HOMING)
	else:
		_leave(slot, Manager.B_HOMING)
	return true


## Pass 1: every live shot's life runs down; a straight shot flies on along its velocity (the
## behaviour passes change that for their shots). A shot whose life ran out stays where it is and
## is marked to expire.
func _pass_common(top: int, delta: float) -> void:
	for slot in top:
		if _alive[slot] == 0:
			continue
		if _freeze[slot] > 0.0:
			# A local stop (`freeze_shot`): the shot holds where it is; its life, its motion and the
			# behaviour passes (which read the state) wait.
			_freeze[slot] -= delta
			_prev[slot] = _pos[slot]
			_state[slot] = Manager.S_FROZEN
			continue
		_life[slot] -= delta
		var at: Vector2 = _pos[slot]
		_prev[slot] = at
		if _life[slot] <= 0.0:
			_state[slot] = Manager.S_EXPIRE
			continue
		_state[slot] = Manager.S_MOVING
		if _motion[slot] == Manager.MOTION_STRAIGHT:
			_pos[slot] = at + _vel[slot] * delta


## The trail pass (the floor's first slice, docs/milestones/floor.md): every live shot that trails
## (`set_trail`) and is not in the air (a falling shot above its band) whose position is in another
## floor cell (TRAIL_CELL px, from the world's origin) than the one it last touched takes that cell and
## is handed back in `_trail_out`, in slot order. Returns how many. The native kernel's
## `trail_pass` is this, to the bit.
func _pass_trail(top: int) -> int:
	var count: int = 0
	for slot in top:
		if _alive[slot] == 0 or _trail[slot] == 0:
			continue
		var at: Vector2 = _pos[slot]
		if (_flags[slot] & Manager.F_FALLING) != 0 and at.y < _floor[slot] - Manager.FALL_BAND:
			continue
		var x: int = floori(at.x / Manager.TRAIL_CELL)
		var y: int = floori(at.y / Manager.TRAIL_CELL)
		if x == _trail_x[slot] and y == _trail_y[slot]:
			continue
		_trail_x[slot] = x
		_trail_y[slot] = y
		_trail_out[count] = slot
		count += 1
	return count


## Give the shot in `slot` the behaviour `kind` (B_*): its pass steps it from now on. Nothing
## happens if it has it already.
func _join(slot: int, kind: int) -> void:
	if (_kinds[slot] >> kind) & 1 != 0:
		return
	var base: int = kind * pm._cap
	var n: int = _member_count[kind]
	_members[base + n] = slot
	_member_at[base + slot] = n
	_member_count[kind] = n + 1
	_kinds[slot] |= 1 << kind


## Take the behaviour `kind` from the shot in `slot` (the last shot in its list takes its place).
func _leave(slot: int, kind: int) -> void:
	if (_kinds[slot] >> kind) & 1 == 0:
		return
	var base: int = kind * pm._cap
	var last: int = _member_count[kind] - 1
	var at: int = _member_at[base + slot]
	var moved: int = _members[base + last]
	_members[base + at] = moved
	_member_at[base + moved] = at
	_member_count[kind] = last
	_kinds[slot] &= ~(1 << kind)


## Take every behaviour from the shot in `slot` (it ended).
func _leave_all(slot: int) -> void:
	var kinds: int = _kinds[slot]
	var kind: int = 0
	while kinds != 0:
		if kinds & 1 != 0:
			_leave(slot, kind)
		kinds >>= 1
		kind += 1


## The shot in `slot` waits for its turn in the hit pass, where its passes from `kind` on run for it
## alone (`_catch_up`). A pass does this for a shot whose motion reads what a hit handler may change
## (a target's place, a shot's caster, which targets are left) or the hit-work budget, so it moves
## when it always did: after the shots before it in the hit pass were tested. The passes after
## `kind` skip a waiting shot.
func _wait(slot: int, kind: int) -> void:
	_wait_state[slot] = _state[slot]
	_wait_from[slot] = kind
	_state[slot] = Manager.S_WAITING


## Run the passes a waiting shot missed (see `_wait`), for it alone.
func _catch_up(slot: int, delta: float) -> void:
	_state[slot] = _wait_state[slot]
	_one[0] = slot
	pm._catching_up = true
	var kinds: int = _kinds[slot]
	for kind in range(_wait_from[slot], Manager.AFTER_HITS):
		if (kinds >> kind) & 1 != 0:
			_passes[kind].call(_one, 0, 1, delta)
	pm._catching_up = false


## Stuck (`set_sticky`, after its first hit): the shot rides its target (it waits for its turn, as a
## hit handler may push the target), and ends with an expiry when the target is gone.
func _pass_stuck(list: PackedInt32Array, first: int, count: int, _delta: float) -> void:
	for n in range(first, first + count):
		var slot: int = list[n]
		if _state[slot] != Manager.S_MOVING:
			continue
		if not pm._catching_up:
			_wait(slot, Manager.B_STUCK)
			continue
		var node: Variant = _stuck_to[slot]
		if not is_instance_valid(node):
			_pos[slot] = _prev[slot]
			_state[slot] = Manager.S_EXPIRE
			continue
		_pos[slot] = (node as Node2D).global_position + _stuck_off[slot]
		_state[slot] = Manager.S_STUCK


## Growth (`set_growth`): the radius grows by its factor a second, until it is as big as the room.
func _pass_growth(list: PackedInt32Array, first: int, count: int, delta: float) -> void:
	var room: float = pm.room_size()
	for n in range(first, first + count):
		var slot: int = list[n]
		if _state[slot] == Manager.S_MOVING:
			_radius[slot] = minf(_radius[slot] * DMath.pow(_growth[slot], delta), maxf(room, _radius0[slot]))


## Linger (`set_linger`): half way through its life the shot stops for its linger time, which does
## not use up its life.
func _pass_linger(list: PackedInt32Array, first: int, count: int, delta: float) -> void:
	for n in range(first, first + count):
		var slot: int = list[n]
		if _state[slot] != Manager.S_MOVING:
			continue
		if _hold[slot] < 0.0 and _life[slot] <= _span[slot] * 0.5:
			_hold[slot] = _linger[slot]
			_life[slot] += _linger[slot]
		if _hold[slot] > 0.0:
			_hold[slot] = maxf(_hold[slot] - delta, 0.0)
			_pos[slot] = _prev[slot]
			_state[slot] = Manager.S_HELD


## Orbit (`set_orbit`): the shot turns round its caster (`_orbit_turn`), its velocity the tangent. It vanishes quietly when its caster's anchor is gone. One whose caster is a shot waits
## for its turn, so it circles that shot where it was when the step came to it. A lingering one
## (S_HELD) keeps to its caster without turning; a spiral (`set_spiral`) weaves its radius.
func _pass_orbit(list: PackedInt32Array, first: int, count: int, delta: float) -> void:
	for n in range(first, first + count):
		var slot: int = list[n]
		var state: int = _state[slot]
		if state != Manager.S_MOVING and state != Manager.S_HELD:
			continue
		var caster: int = _caster_slot[slot]
		var centre: Vector2 = _caster_at[slot]
		if caster == Manager.CASTER_BODY:
			centre = _anchors[_actor[slot]] if _actor[slot] >= 0 else Vector2.INF
		elif caster >= 0:
			if not pm._catching_up:
				_wait(slot, Manager.B_ORBIT)
				continue
			centre = _caster_position(slot)
		if not centre.is_finite():
			_state[slot] = Manager.S_GONE
			continue
		var turn: float = _orbit_turn(slot, delta)
		if state == Manager.S_MOVING:
			_orbit_angle[slot] = wrapf(_orbit_angle[slot] + turn * delta, -PI, PI)
			_wave_age[slot] += delta
		var away: Vector2 = DMath.from_angle(_orbit_angle[slot])
		_pos[slot] = centre + away * (_orbit_radius[slot] + _wave[slot] * DMath.sin(TAU * _wave_age[slot] / Manager.SPIRAL_PERIOD))
		_vel[slot] = Vector2(-away.y, away.x) * (_orbit_radius[slot] * turn)
		_orbit_centre[slot] = centre


## Return (`set_return`): from half its life the shot flies back to its caster at the speed it had
## (it may hit again on the way), and ends with an expiry when it gets there; the way home takes no
## life, so it always comes home (rules R4 F4), but it vanishes when its caster's anchor is gone.
## One whose caster is a shot waits for its turn (see `_pass_orbit`).
func _pass_return(list: PackedInt32Array, first: int, count: int, delta: float) -> void:
	for n in range(first, first + count):
		var slot: int = list[n]
		if _state[slot] != Manager.S_MOVING or _life[slot] > _span[slot] * 0.5:
			continue
		if _caster_slot[slot] >= 0 and not pm._catching_up:
			_wait(slot, Manager.B_RETURN)
			continue
		# The way home takes no life: give back what `_pass_common` took this step.
		_life[slot] += delta
		var flags: int = _flags[slot]
		var turned: bool = (flags & Manager.F_TURNED) == 0
		if turned:
			_flags[slot] |= Manager.F_TURNED
			_speed[slot] = _vel[slot].length()
			_job_hits._forget_all(slot)
		var anchor: Vector2 = _caster_position(slot)
		if not anchor.is_finite():
			_pos[slot] = _prev[slot]
			_state[slot] = Manager.S_GONE
			continue
		var here: Vector2 = _base[slot] if (flags & Manager.F_WAVE) != 0 else _prev[slot]
		var way: Vector2 = anchor - here
		if way.length() <= _speed[slot] * delta + _radius[slot]:
			_pos[slot] = anchor
			_state[slot] = Manager.S_EXPIRE
			continue
		var heading: Vector2 = way.normalized()
		if _turn[slot] > 0.0:
			# Homing bends the way home (rules R4a): the shot's angle off the line to its caster
			# turns toward its target at the homing rate (back to 0 with none in reach), never past
			# RETURN_BEND, so it always closes in on its caster and never circles.
			var bend: float = 0.0 if turned else clampf(DMath.angle_to(heading, _vel[slot]), -Manager.RETURN_BEND, Manager.RETURN_BEND)
			var goal: Vector2 = _home_at[slot]
			var want: float = 0.0
			if goal.is_finite() and not goal.is_equal_approx(here):
				want = clampf(DMath.angle_to(heading, goal - here), -Manager.RETURN_BEND, Manager.RETURN_BEND)
			heading = DMath.rotated(heading, move_toward(bend, want, _turn[slot] * _speed[slot] * delta))
		_vel[slot] = heading * _speed[slot]
		_pos[slot] = _prev[slot] + _vel[slot] * delta
		_state[slot] = Manager.S_RETURNING


## Speed over life (`set_speed_curve`): a shot flying out takes the speed of its curve at the share
## of its life left, along the way it flies now, and flies on along it. The share is read at the
## middle of the step (its life was already counted down for the whole step), so a curve that
## changes most early still goes as far as its mean says, to within a pixel, and not a step's
## worth of change short (every shot has a curve, SpellLimits.SHOT_SPEED_*).
func _pass_curve(list: PackedInt32Array, first: int, count: int, delta: float) -> void:
	for n in range(first, first + count):
		var slot: int = list[n]
		if _state[slot] != Manager.S_MOVING:
			continue
		_vel[slot] = _vel[slot].normalized() * (_curve_speed[slot] * _curve_factor(slot, delta))
		_pos[slot] = _prev[slot] + _vel[slot] * delta


## Homing (`set_homing`): the shot turns toward the point it last found, at most its turn rate, and
## flies on along its new velocity; a shot with no speed (a rune) creeps toward it at
## SpellLimits.HOMING_DRIFT. On its search step (one in HOMING_PERIOD, slots taking turns)
## it waits for its turn, then looks for a target while there is hit work left (`_homing_point`).
## A returning shot on its way back only searches: `_pass_return` bends its way with the point.
func _pass_homing(list: PackedInt32Array, first: int, count: int, delta: float) -> void:
	for n in range(first, first + count):
		var slot: int = list[n]
		var state: int = _state[slot]
		if state != Manager.S_MOVING and state != Manager.S_RETURNING:
			continue
		if ((slot + pm._step_index) % Manager.HOMING_PERIOD) == 0:
			if not pm._catching_up:
				_wait(slot, Manager.B_HOMING)
				continue
			if pm._work_left > 0:
				_home_at[slot] = _homing_point(slot, _prev[slot])
		if state == Manager.S_RETURNING:
			continue
		var goal: Vector2 = _home_at[slot]
		if not goal.is_finite():
			continue
		var want: Vector2 = goal - _prev[slot]
		if want.is_zero_approx():
			continue
		var velocity: Vector2 = _vel[slot]
		if velocity.is_zero_approx():
			_pos[slot] = _prev[slot] + want.limit_length(SpellLimits.HOMING_DRIFT * delta)
			continue
		# `turned_toward`, written out (this runs for every homing shot every step).
		# Its bend a pixel times the pixels it flies: the same curve at any speed.
		var most: float = _turn[slot] * velocity.length() * delta
		_vel[slot] = DMath.rotated(velocity, clampf(DMath.angle_to(velocity, want), -most, most))
		_pos[slot] = _prev[slot] + _vel[slot] * delta


## Spiral (`set_spiral`): the shot's centre line (`_base`) flies straight on and the shot weaves a
## sine wave of its width round it, SPIRAL_PERIOD seconds a wave.
func _pass_spiral(list: PackedInt32Array, first: int, count: int, delta: float) -> void:
	for n in range(first, first + count):
		var slot: int = list[n]
		var state: int = _state[slot]
		if state != Manager.S_MOVING and state != Manager.S_RETURNING:
			continue
		var velocity: Vector2 = _vel[slot]
		_base[slot] += velocity * delta
		_wave_age[slot] += delta
		var side: Vector2 = Vector2(-velocity.y, velocity.x).normalized()
		_pos[slot] = _base[slot] + side * (_wave[slot] * DMath.sin(TAU * _wave_age[slot] / Manager.SPIRAL_PERIOD))


## A card's moves (`move_shot`): while each lasts, it carries the shot on top of its own motion (a
## lingering shot too), and the moves under way add up. A shot with a homing move waits for its
## turn: it picks among the targets still there. A move that is over is let go.
func _pass_move(list: PackedInt32Array, first: int, count: int, delta: float) -> void:
	for n in range(first, first + count):
		var slot: int = list[n]
		var state: int = _state[slot]
		if (state != Manager.S_MOVING and state != Manager.S_HELD and state != Manager.S_RETURNING) or _move_head[slot] < 0:
			continue
		if not pm._catching_up and _has_homing_move(slot):
			_wait(slot, Manager.B_MOVE)
			continue
		var before: int = -1
		var at: int = _move_head[slot]
		while at >= 0:
			var next: int = _move_next[at]
			var part: float = minf(delta, _move_left[at])
			# Its speed curve's share of the way this step (`MoveCurve`), as seconds at its even speed.
			var curved: float = part if _move_curve[at] == MoveCurve.NONE else MoveCurve.share(_move_curve[at], _move_total[at], _move_left[at], delta) * _move_total[at]
			_move_left[at] -= delta
			if _move_turn[at] > 0.0:
				_move_vel[at] = home_velocity(_actor[slot], _pos[slot], _move_vel[at], _move_turn[at], _move_range[at], part, _move_home[at], int(_seq[slot]), _layers[slot])
				_move_home[at] = pm.homing_target
			_pos[slot] += _move_vel[at] * curved
			_base[slot] += _move_vel[at] * curved
			if _move_left[at] <= 0.0:
				if before < 0:
					_move_head[slot] = next
				else:
					_move_next[before] = next
				_move_next[at] = pm._move_free
				pm._move_free = at
			else:
				before = at
			at = next


## True when one of the moves under way of the shot in `slot` homes.
func _has_homing_move(slot: int) -> bool:
	var at: int = _move_head[slot]
	while at >= 0:
		if _move_turn[at] > 0.0:
			return true
		at = _move_next[at]
	return false


## Shield (`set_shield`), after the hits: each shielded shot stops the shots of other teams that its
## path touched this step (`_shield_block`), in slot order.
func _pass_shield(list: PackedInt32Array, first: int, count: int, _delta: float) -> void:
	# The list in slot order (insertion sort into the scratch: shields are few), as blocks spend
	# charges in that order.
	for n in count:
		var slot: int = list[first + n]
		var at: int = n
		while at > 0 and _shield_order[at - 1] > slot:
			_shield_order[at] = _shield_order[at - 1]
			at -= 1
		_shield_order[at] = slot
	for n in count:
		var slot: int = _shield_order[n]
		# A shot spawned during this step (S_IDLE) waits for the next one.
		if _alive[slot] != 0 and (_shield[slot] > 0 or _deflect[slot] != 0) and _state[slot] == Manager.S_DONE:
			_job_guards._shield_block(slot)


## Where a shot is drawn when it is at `at`: where it is, except a new orbit shot, which is drawn
## spiralling out from its caster to its circle over ORBIT_GROW seconds (the mockup's; it hits
## at its circle from the start, so a ring's hits do not wait on the look).
func _drawn_at(slot: int, at: Vector2) -> Vector2:
	if _motion[slot] != Manager.MOTION_ORBIT:
		return at
	var out: float = (pm.sim_time - _born[slot]) / Manager.ORBIT_GROW
	if out >= 1.0 or not _orbit_centre[slot].is_finite():
		return at
	return _orbit_centre[slot].lerp(at, maxf(out, 0.0))


## The velocity of the orbit shot in `slot` at its angle: the tangent, at its turn now (`_orbit_turn`).
func _orbit_tangent(slot: int, delta: float) -> Vector2:
	var away: Vector2 = DMath.from_angle(_orbit_angle[slot])
	return Vector2(-away.y, away.x) * (_orbit_radius[slot] * _orbit_turn(slot, delta))


## How fast the orbit shot in `slot` turns now, in radians a second: its drift, plus its speed (its
## curve's, read as `_pass_curve` reads it) over its radius, so a fast carrier goes round faster and
## one with no speed (a rune, a beam) only drifts; negative when a bounce turned it back (`_orbit_way`).
func _orbit_turn(slot: int, delta: float) -> float:
	var radius: float = _orbit_radius[slot]
	if radius <= 0.0:
		return _orbit_way[slot] * _orbit_drift[slot]
	return _orbit_way[slot] * (_orbit_drift[slot] + _curve_speed[slot] * _curve_factor(slot, delta) / radius)


## Puts the shot in `slot` back at `at` (a wall stopped or turned it), its motion going on from
## there: a circling one's angle round its centre too, so the orbit pass carries it on from `at`.
func _place_at(slot: int, at: Vector2) -> void:
	_pos[slot] = at
	if _motion[slot] == Manager.MOTION_ORBIT and _orbit_centre[slot].is_finite() and not at.is_equal_approx(_orbit_centre[slot]):
		_orbit_angle[slot] = DMath.angle(at - _orbit_centre[slot])


## How far the shot in `slot` has gone round its caster since it was set circling (radians; 0 for a
## shot that does not circle): what turns a circling wall's row with it.
func _turned(slot: int) -> float:
	return _orbit_angle[slot] - _orbit_from[slot] if _motion[slot] == Manager.MOTION_ORBIT else 0.0


## The factor of its speed a shot of the curve `start`, `end`, `ease_power` (`set_speed_curve`) goes
## at with `left` of its life left (0 to 1): the curve itself, for what grows as a shot flies (a
## Pulse's ring, `CarrierPulse`). `_curve_factor` is the same sum inline (the hot loop, mirrored by
## the native kernel); content/spells/carriers/pulse/test_pulse.gd
## (`test_its_ring_goes_as_far_as_a_shot_of_its_numbers_flies`) holds the two to the same distance.
static func speed_factor(start: float, end: float, ease_power: float, left: float) -> float:
	return start + (end - start) * (1.0 - DMath.pow(left, ease_power))


## The factor of its speed the shot in `slot` goes at in a step of `delta` (`set_speed_curve`): read
## at the middle of the step (its life was already counted down for the whole step). 1 for a shot
## with no curve.
func _curve_factor(slot: int, delta: float) -> float:
	var left: float = clampf((_life[slot] + delta * 0.5) / _span[slot], 0.0, 1.0)
	return _curve_from[slot] + (_curve_to[slot] - _curve_from[slot]) * (1.0 - DMath.pow(left, _curve_ease[slot]))


## `velocity` turned toward `want` by at most `most` radians, keeping its length: the one turn
## of homing, for a shot in flight, a shot's move and a wizard's dash. A zero `want` or
## `velocity` gives `velocity` back.
static func turned_toward(velocity: Vector2, want: Vector2, most: float) -> Vector2:
	if velocity.is_zero_approx() or want.is_zero_approx():
		return velocity
	return DMath.rotated(velocity, clampf(DMath.angle_to(velocity, want), -most, most))


## For anything else homing moves (a shot carried by a dash, a wizard dashing): `velocity` at
## `from` turned toward a target on `layers` no further than `within` pixels, in any
## direction, by at most `turn_rate` radians a second for `delta` seconds, as a homing shot
## turns. The target is picked as `homing_point` picks it for `caster` (`keep`, `pick_seed`);
## `homing_target` says which, to hand back as `keep` next step. Allocation-free.
func home_velocity(caster: int, from: Vector2, velocity: Vector2, turn_rate: float, within: float, delta: float, keep: int, pick_seed: int, layers: int = Manager.ACTOR_LAYERS) -> Vector2:
	pm.homing_target = 0
	pm.homing_target_reach = 0.0
	if not (turn_rate > 0.0) or not velocity.is_finite() or velocity.is_zero_approx():
		return velocity
	var goal: Vector2 = homing_point(caster, from, velocity, PI, layers, within, keep, pick_seed)
	if not goal.is_finite():
		return velocity
	return turned_toward(velocity, goal - from, turn_rate * delta)


## Where a homing shot at `from` steers: the target it kept, while it may still home on it, or else
## a new one picked at random (`_home_pick`), or INF. Charges the work budget.
func _homing_point(slot: int, from: Vector2) -> Vector2:
	var t: int = _home_pick(_actor[slot], _team[slot], from, Vector2.RIGHT, PI, _layers[slot], _home_range[slot], _home_target[slot], int(_seq[slot]), slot)
	_home_target[slot] = _target_key[t] if t >= 0 else 0
	return _target_pos[t] if t >= 0 else Vector2.INF


## For a beam or a teleport, which cannot turn: `direction` (a unit vector) bent toward the
## target `homing_point` picks, or `direction` unchanged when there is none. Allocation-free.
func homing_aim(caster: int, origin: Vector2, direction: Vector2, max_angle: float, layers: int, within: float, keep: int, pick_seed: int) -> Vector2:
	var goal: Vector2 = homing_point(caster, origin, direction, max_angle, layers, within, keep, pick_seed)
	return direction if not goal.is_finite() else origin.direction_to(goal)


## The centre of the target a homing thing at `origin` going along `direction` steers to, or
## INF when there is none: one on `layers` no further than `within` pixels whose centre lies within `max_angle` radians of `direction` (PI for any
## way). Targets owned by `caster` and those of its team (`Actors.team_of`; homing aims at
## other teams only, actors G3a) are skipped. The target whose
## key (`_target_key`) is `keep` stays the pick while it qualifies; otherwise one is picked at random
## among those that do, from `pick_seed` (the same seed and targets give the same pick), so a
## group of shots spreads over a group of enemies. `homing_target` is left at the pick's key (0 for
## none), for the caller to keep. Allocation-free.
func homing_point(caster: int, origin: Vector2, direction: Vector2, max_angle: float, layers: int, within: float, keep: int, pick_seed: int) -> Vector2:
	pm.homing_target = 0
	pm.homing_target_reach = 0.0
	if not origin.is_finite() or not direction.is_finite() or direction.is_zero_approx() or not is_finite(max_angle) or not is_finite(within) or within <= 0.0:
		return Vector2.INF
	_job_targets._query_ready()
	var t: int = _home_pick(caster, pm._team_of(caster), origin, direction, max_angle, layers, within, keep, pick_seed, -1)
	if t < 0:
		return Vector2.INF
	pm.homing_target = _target_key[t]
	pm.homing_target_reach = HitShape.reach_toward(_target_half[t], _target_radius[t], _target_pos[t].direction_to(origin))
	return _target_pos[t]


## The one homing search: the target (an index, or -1) `homing_point` describes, for `caster`
## of `team` (NONE: no team, every target but its own body). For a shot (`slot` 0 or more) it
## also skips the targets the shot just hit and charges the work budget.
func _home_pick(caster: int, team: int, origin: Vector2, direction: Vector2, max_angle: float, layers: int, within: float, keep: int, pick_seed: int, slot: int) -> int:
	# Homing picks only a foe (`Actors.is_foe`, written out here and in the queries below: a call
	# per target costs more than the test; never its own team, a teammate for a wizard, nor a prop of
	# the world's), though every spell hits them, nor a target the shot is still on (`_mark_memory`).
	var stamp: int = _job_hits._mark_memory(slot) if slot >= 0 else -1
	var any_way: bool = max_angle >= PI
	var pick: int = -1
	var seen: int = 0
	var cells: Vector4i = _job_targets._query_cells(origin, within)
	for y in range(cells.y, cells.w + 1):
		for x in range(cells.x, cells.z + 1):
			var t: int = _cell_head[y * pm._grid_w + x]
			while t >= 0:
				if slot >= 0:
					pm._work_left -= 1
				if (_target_layer[t] & layers) != 0 and (caster < 0 or _target_owner[t] != caster) and _target_team[t] != Manager.ActorsScript.TEAM_WORLD and (team == Manager.ActorsScript.NONE or _target_team[t] != team) and is_instance_valid(_targets[t]) and (slot < 0 or _target_mark[t] != stamp):
					var to_target: Vector2 = _target_pos[t] - origin
					var reach: float = within + _target_radius[t]
					var box: Vector2 = _target_half[t]
					if (to_target.length_squared() if box == Vector2.ZERO else HitShape.gap_sq(to_target, box)) <= reach * reach and (any_way or (not to_target.is_zero_approx() and absf(DMath.angle_to(direction, to_target)) <= max_angle)):
						if keep != 0 and _target_key[t] == keep:
							return t
						# Reservoir pick: the n-th target seen replaces the pick one time in n.
						seen += 1
						if posmod(hash(Vector2i(pick_seed, seen)), seen) == 0:
							pick = t
				t = _target_next[t]
	return pick
