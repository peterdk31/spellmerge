class_name ProjectileGuards
extends Object
## What the projectile manager answers about shots coming (core/projectiles/projectile_manager.gd): a
## swing's deflect and block, the shots in a wedge or on a segment, the threat to a body (`threat`,
## its grid of shots), and a shield's or a solid's guard against shots. Static functions of the
## manager (`pm`), whose members hold all of it.

const Manager := preload("res://core/projectiles/projectile_manager.gd")

## Not state (core/sim/README.md): the manager, the other jobs this one calls and the manager's
## arrays it works on, each the manager's own array (shared, never a copy), linked by `link`.
const DERIVED: Array[StringName] = [&"pm", &"_job_draw", &"_job_hits", &"_job_moves", &"_job_walls", &"_pos", &"_prev", &"_vel", &"_life", &"_radius", &"_actor", &"_team", &"_ramp", &"_budget", &"_layers", &"_tag", &"_motion", &"_home_at", &"_home_target", &"_drawn_seq", &"_shield", &"_deflect", &"_span", &"_curve_from", &"_curve_to", &"_curve_ease", &"_curve_speed", &"_base", &"_speed", &"_caster_slot", &"_state", &"_shot_head", &"_shot_next", &"_alive", &"_owned", &"_solids", &"_skip_on", &"_skip_near", &"guard_slots", &"_threat_head", &"_threat_slot", &"_threat_next", &"_threat_over", &"_threat_seen"]

var pm: Manager = null
var _job_draw: ProjectileDraw = null
var _job_hits: ProjectileHits = null
var _job_moves: ProjectileMoves = null
var _job_walls: ProjectileWalls = null
var _pos: PackedVector2Array
var _prev: PackedVector2Array
var _vel: PackedVector2Array
var _life: PackedFloat32Array
var _radius: PackedFloat32Array
var _actor: PackedInt32Array
var _team: PackedInt32Array
var _ramp: PackedInt32Array
var _budget: PackedByteArray
var _layers: PackedInt32Array
var _tag: PackedInt64Array
var _motion: PackedByteArray
var _home_at: PackedVector2Array
var _home_target: PackedInt64Array
var _drawn_seq: PackedInt64Array
var _shield: PackedInt32Array
var _deflect: PackedByteArray
var _span: PackedFloat32Array
var _curve_from: PackedFloat32Array
var _curve_to: PackedFloat32Array
var _curve_ease: PackedFloat32Array
var _curve_speed: PackedFloat32Array
var _base: PackedVector2Array
var _speed: PackedFloat32Array
var _caster_slot: PackedInt32Array
var _state: PackedByteArray
var _shot_head: PackedInt32Array
var _shot_next: PackedInt32Array
var _alive: PackedByteArray
var _owned: PackedInt32Array
var _solids: Dictionary
var _skip_on: PackedFloat32Array
var _skip_near: PackedFloat32Array
var guard_slots: PackedInt32Array
var _threat_head: PackedInt32Array
var _threat_slot: PackedInt32Array
var _threat_next: PackedInt32Array
var _threat_over: PackedInt32Array
var _threat_seen: PackedInt32Array


## Takes the manager's arrays and jobs, by the names in DERIVED: again whenever the manager's arrays
## may have been replaced (`ProjectileManager._link_jobs`).
func link(manager: Manager) -> void:
	pm = manager
	for name: StringName in DERIVED:
		if name != &"pm":
			set(name, manager.get(name))


## Deflects the shot in `slot` (melee I3; docs/milestones/M2-staffs.md, "Deflect"): it turns off
## what touched it, `normal` the way out from that at the touch (a shot coming in along it is
## mirrored; one already going out keeps its way), flies `SpellLimits.DEFLECT_SPEEDUP` times
## faster (each deflect again: a rally speeds up) and its life starts again, and it becomes the
## actor `by`'s: its team, ramp, budget and hit credit, and a homing or returning shot hunts or
## comes back for its new caster. An orbiting shot leaves its circle and flies straight on. It
## keeps its own cards (its tag: damage, infusions, payloads), may hit what it hit before, and
## `shot_deflected(by, where, by_tag)` is sent. False when there is no such shot or `by` is no
## actor.
func deflect_shot(slot: int, by: int, normal: Vector2, by_tag: int) -> bool:
	var events: Manager.EventsScript = pm.events
	if slot < 0 or slot >= pm._cap or _alive[slot] == 0 or by < 0 or not normal.is_finite():
		return false
	pm._threat_step = -1
	var out: Vector2 = normal.normalized() if not normal.is_zero_approx() else Vector2.ZERO
	if _motion[slot] == Manager.MOTION_ORBIT:
		# It flies on along its tangent at the speed it goes round with now (its drift's share too, so
		# one with no speed of its own flies on), at that speed from here: its curve is spent.
		_motion[slot] = Manager.MOTION_STRAIGHT
		_job_moves._leave(slot, Manager.B_ORBIT)
		_curve_from[slot] = 1.0
		_curve_to[slot] = 1.0
		_curve_ease[slot] = 1.0
		_curve_speed[slot] = _vel[slot].length()
		_job_moves._join(slot, Manager.B_CURVE)
	var velocity: Vector2 = _vel[slot]
	if out != Vector2.ZERO and velocity.dot(out) < 0.0:
		velocity -= 2.0 * velocity.dot(out) * out
	_vel[slot] = velocity * SpellLimits.DEFLECT_SPEEDUP
	_speed[slot] *= SpellLimits.DEFLECT_SPEEDUP
	_curve_speed[slot] *= SpellLimits.DEFLECT_SPEEDUP
	_base[slot] = _pos[slot]
	_life[slot] = _span[slot]
	_actor[slot] = by
	var table: Manager.ActorsScript = pm.actors if pm.actors != null else pm._auto_actors
	if table == null or not is_instance_valid(table):
		table = pm.actor_table()
	var budget: int = Manager.ActorsScript.SHARED
	if table != null and table.is_open(by):
		_team[slot] = table.team_of(by)
		_ramp[slot] = table.ramp_of(by)
		budget = table.budget_of(by)
	else:
		_team[slot] = Manager.ActorsScript.NONE
		_ramp[slot] = Manager.ActorsScript.NONE
	_owned[_budget[slot]] -= 1
	_budget[slot] = budget
	_owned[budget] += 1
	_caster_slot[slot] = Manager.CASTER_BODY
	_home_target[slot] = 0
	_home_at[slot] = Vector2.INF
	_skip_on[slot] = 0.0
	_skip_near[slot] = 0.0
	_job_hits._forget_all(slot)
	# Its colours are its new caster's: work its look out again.
	_drawn_seq[slot] = -1
	if events != null:
		var outer_slot: int = pm._event_slot
		pm._event_slot = slot
		pm._sent += 1
		events.shot_deflected.emit(by, _pos[slot], by_tag, slot)
		pm._event_slot = outer_slot
	return true


## Stops the shot in `slot` as a shield charge does (`shot_blocked(by, where, by_tag)`), for a
## carrier that is no shot (a swing, a beam, a slam, a decoy). `carrier` is that carrier's id (not
## its card's), told to looks as `impact_carrier` while the event is sent: a swing's block is a
## parry (melee I5). The blocker is no shot, so the event's `shot` is -1, whatever event it is sent
## inside of. False when there is no such shot.
func block_shot(slot: int, by: int, by_tag: int, carrier: StringName = &"") -> bool:
	var events: Manager.EventsScript = pm.events
	if slot < 0 or slot >= pm._cap or _alive[slot] == 0:
		return false
	var at: Vector2 = _pos[slot]
	_job_draw._end_tail(slot, at)
	pm._kill(slot)
	if events != null:
		var outer_carrier: StringName = pm.impact_carrier
		var outer_slot: int = pm._event_slot
		pm.impact_carrier = carrier
		pm._event_slot = -1
		pm._sent += 1
		events.shot_blocked.emit(by, at, by_tag, -1)
		pm._event_slot = outer_slot
		pm.impact_carrier = outer_carrier
	return true


## The shots of another team than the actor `caster`'s (a shot of no actor included, as a shield
## has it) whose circle reaches into the wedge round `origin` from `from_angle` to `to_angle`
## radians off `direction` (`side` as `sweep`), out to `reach`: a swing's guard (melee I3). Fills
## `guard_slots` and returns how many. `ahead` seconds: also where each shot will be by then, so a
## parry meets a fast shot (an atom) that would otherwise go from outside the wedge into the body
## behind it in one step. Allocation-free once the list has grown.
func shots_in_wedge(caster: int, origin: Vector2, direction: Vector2, side: int, from_angle: float, to_angle: float, reach: float, ahead: float = 0.0) -> int:
	if not origin.is_finite() or not direction.is_finite() or direction.is_zero_approx() or not (reach > 0.0) or to_angle < from_angle:
		return 0
	var mine: int = _team_now(caster)
	var base: float = DMath.angle(direction)
	var turn: float = 1.0 if side >= 0 else -1.0
	var found: int = 0
	for slot in pm._high:
		# A shot that hits nothing (a field) is not met.
		if _alive[slot] == 0 or _team[slot] == mine or _layers[slot] == 0:
			continue
		var radius: float = _radius[slot]
		# Along its last step (and its next `ahead`), so a small fast shot (an atom) does not slip
		# past between steps.
		var flies: bool = ahead > 0.0 and _state[slot] != Manager.S_STUCK and _state[slot] != Manager.S_FROZEN and _state[slot] != Manager.S_HELD
		var next: Vector2 = _pos[slot] + _vel[slot] * ahead if flies else _pos[slot]
		var later: int = _guard_samples_on(_pos[slot], next, radius) if next != _pos[slot] else 0
		var samples: int = _guard_samples(slot)
		for k in samples + later:
			var to: Vector2 = (_guard_point(slot, k, samples) if k < samples else _pos[slot].lerp(next, float(k - samples + 1) / float(later))) - origin
			var distance: float = to.length()
			if distance > reach + radius:
				continue
			var width: float = PI if distance <= radius else DMath.asin(radius / distance)
			var local: float = angle_difference(base, DMath.angle(to)) * turn
			if local + width >= from_angle and local - width <= to_angle:
				found = _guard_add(found, slot)
				break
	return found


## The shots of another team than `caster`'s whose circle touches the segment from `a` to `b`
## widened by `width` each side: a beam's guard (melee I3). Fills `guard_slots`, after the first
## `first` already there, and returns how many there are in all.
func shots_on_segment(caster: int, a: Vector2, b: Vector2, width: float, first: int = 0) -> int:
	if not a.is_finite() or not b.is_finite():
		return first
	var mine: int = _team_now(caster)
	var found: int = first
	for slot in pm._high:
		if _alive[slot] == 0 or _team[slot] == mine or _layers[slot] == 0 or _guard_has(found, slot):
			continue
		var reach: float = width + _radius[slot]
		var samples: int = _guard_samples(slot)
		for k in samples:
			var at: Vector2 = _guard_point(slot, k, samples)
			if Geometry2D.get_closest_point_to_segment(at, a, b).distance_squared_to(at) <= reach * reach:
				found = _guard_add(found, slot)
				break
	return found


## The shot of another team than `team` that will come within `radius` of `point` soonest, within
## `horizon` seconds: what an AI dodges (enemy AI AI3, docs/milestones/M2-enemy-ai.md). Returns
## the seconds until it gets there (0 for one already there, a still shot standing on the point
## included), or -1.0 for none; `threat_slot` is its slot and `threat_away` the unit way off its
## line on the side `point` already is (away from a still one). The shots of `own` (an actor id,
## -1 for none) are skipped, as they pass their caster. Moving shots move on their velocity (an
## orbit shot on its tangent, as it goes now: no special rule). Of two shots that get there at the same moment, the
## lower slot is the one. Allocation-free; an AI asks on its reaction timer, not every step.
##
## Many AIs ask in one step, so with THREAT_GRID_FROM shots or more, once a step (or the one before
## it) has THREAT_GRID_ASKS asks, an ask builds the threat grid (performance, 2026-11-02: one pass
## over 3,000 shots was 1.4 ms an ask, about 10 ms a step for 200 enemies): each shot is filed
## under the cells of the box round its path for the horizon, widened by its radius, and an ask
## tries only the shots filed under the cells its own circle's box touches, with the same exact test. So it finds what one pass over every
## shot finds. A spawn, a deflection or a card's move throws the grid away (they change a path
## between steps); a longer horizon than the grid's builds it again.
func threat(point: Vector2, radius: float, team: int, own: int = -1, horizon: float = 1.0) -> float:
	var _kernel: Object = pm._kernel
	pm.threat_slot = -1
	pm.threat_away = Vector2.ZERO
	if not point.is_finite() or not (radius > 0.0):
		return -1.0
	var best: float = INF
	if pm._threat_ask_step != pm._step_index:
		pm._threat_asks_before = pm._threat_asks if pm._threat_ask_step == pm._step_index - 1 else 0
		pm._threat_asks = 0
		pm._threat_ask_step = pm._step_index
	pm._threat_asks += 1
	if pm._count < Manager.THREAT_GRID_FROM or (pm._threat_step != pm._step_index and pm._threat_asks < Manager.THREAT_GRID_ASKS and pm._threat_asks_before < Manager.THREAT_GRID_ASKS):
		if _kernel != null:
			return _kernel.call(&"threat_scan", pm, point, radius, team, own, horizon)
		# `_threat_try` written out: a call a shot costs a third more over 3,000 shots.
		var best_away: Vector2 = Vector2.ZERO
		for slot in pm._high:
			if _alive[slot] == 0 or (_team[slot] == team and team != Manager.ActorsScript.NONE) or (_actor[slot] == own and own >= 0):
				continue
			var reach: float = radius + _radius[slot]
			var rel: Vector2 = point - _pos[slot]
			var vel: Vector2 = _vel[slot]
			var state: int = _state[slot]
			var still: bool = _motion[slot] == Manager.MOTION_STILL or state == Manager.S_STUCK or state == Manager.S_FROZEN or state == Manager.S_HELD or vel.length_squared() < 1.0
			var when: float = -1.0
			if rel.length_squared() <= reach * reach:
				when = 0.0
			elif not still:
				var along: float = rel.dot(vel) / vel.length_squared()
				if along <= 0.0 or along > minf(horizon, _life[slot]):
					continue
				if (rel - vel * along).length_squared() > reach * reach:
					continue
				when = along
			# Slots run upward, so of two as soon the first one stays.
			if when < 0.0 or when >= best:
				continue
			best = when
			pm.threat_slot = slot
			if still:
				best_away = rel.normalized() if rel != Vector2.ZERO else Vector2.RIGHT
			else:
				var side: Vector2 = rel - vel * (rel.dot(vel) / vel.length_squared())
				best_away = side.normalized() if side.length_squared() > 0.01 else vel.orthogonal().normalized()
		pm.threat_away = best_away
		return best if pm.threat_slot >= 0 else -1.0
	if pm._threat_step != pm._step_index or horizon > pm._threat_horizon:
		_build_threat_grid(horizon)
	if _kernel != null:
		return _kernel.call(&"threat_query", pm, point, radius, team, own, horizon)
	pm._threat_stamp += 1
	var stamp: int = pm._threat_stamp
	for n in pm._threat_over_count:
		best = _threat_try(_threat_over[n], point, radius, team, own, horizon, best)
	var size: float = pm._threat_cell
	var x0: int = clampi(floori((point.x - radius - pm._threat_x) / size), 0, pm._threat_w - 1)
	var x1: int = clampi(floori((point.x + radius - pm._threat_x) / size), 0, pm._threat_w - 1)
	var y0: int = clampi(floori((point.y - radius - pm._threat_y) / size), 0, pm._threat_h - 1)
	var y1: int = clampi(floori((point.y + radius - pm._threat_y) / size), 0, pm._threat_h - 1)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var entry: int = _threat_head[y * pm._threat_w + x]
			while entry >= 0:
				var slot: int = _threat_slot[entry]
				entry = _threat_next[entry]
				if _threat_seen[slot] == stamp:
					continue
				_threat_seen[slot] = stamp
				best = _threat_try(slot, point, radius, team, own, horizon, best)
	return best if pm.threat_slot >= 0 else -1.0


## `threat`'s exact test of the shot in `slot`: when it comes within `radius` (plus its own) of
## `point`, if sooner than `best` (or as soon, from a lower slot); then it becomes `threat_slot`
## and `threat_away` its way off. Returns the new best.
func _threat_try(slot: int, point: Vector2, radius: float, team: int, own: int, horizon: float, best: float) -> float:
	# A shot that hits nothing (a field) is no threat.
	if _alive[slot] == 0 or _layers[slot] == 0 or (_team[slot] == team and team != Manager.ActorsScript.NONE) or (_actor[slot] == own and own >= 0):
		return best
	var reach: float = radius + _radius[slot]
	var rel: Vector2 = point - _pos[slot]
	var vel: Vector2 = _vel[slot]
	var state: int = _state[slot]
	var still: bool = _motion[slot] == Manager.MOTION_STILL or state == Manager.S_STUCK or state == Manager.S_FROZEN or state == Manager.S_HELD or vel.length_squared() < 1.0
	var when: float = -1.0
	if rel.length_squared() <= reach * reach:
		when = 0.0
	elif not still:
		var speed2: float = vel.length_squared()
		var along: float = rel.dot(vel) / speed2
		if along <= 0.0 or along > minf(horizon, _life[slot]):
			return best
		if (rel - vel * along).length_squared() > reach * reach:
			return best
		when = along
	if when < 0.0 or when > best or (when == best and slot > pm.threat_slot):
		return best
	pm.threat_slot = slot
	if still:
		pm.threat_away = rel.normalized() if rel != Vector2.ZERO else Vector2.RIGHT
	else:
		var side: Vector2 = rel - vel * (rel.dot(vel) / vel.length_squared())
		pm.threat_away = side.normalized() if side.length_squared() > 0.01 else vel.orthogonal().normalized()
	return when


## File every live shot that `threat` could find under the cells of its path's box for `horizon`
## seconds (see `threat`), in one pass: each cell's list grows at its head. Its cells cover the
## bounds, THREAT_CELL wide or wider so there are at most THREAT_GRID_MAX a side; a path is clamped
## to them (a query outside is clamped the same way, so nothing it could meet is missed).
func _build_threat_grid(horizon: float) -> void:
	var _kernel: Object = pm._kernel
	pm._threat_step = pm._step_index
	pm._threat_horizon = horizon
	var size: float = maxf(Manager.THREAT_CELL, maxf(pm._bounds.size.x, pm._bounds.size.y) / float(Manager.THREAT_GRID_MAX))
	pm._threat_cell = size
	pm._threat_x = pm._bounds.position.x
	pm._threat_y = pm._bounds.position.y
	pm._threat_w = clampi(ceili(pm._bounds.size.x / size), 1, Manager.THREAT_GRID_MAX)
	pm._threat_h = clampi(ceili(pm._bounds.size.y / size), 1, Manager.THREAT_GRID_MAX)
	var cells: int = pm._threat_w * pm._threat_h
	if _threat_head.size() < cells:
		_threat_head.resize(cells)
	if _threat_seen.size() < pm._cap:
		_threat_seen.resize(pm._cap)
		_threat_seen.fill(0)
		_threat_over.resize(pm._cap)
	if _threat_slot.size() < pm._cap * 4:
		_threat_slot.resize(pm._cap * 4)
		_threat_next.resize(pm._cap * 4)
	# The native kernel fills it when its entries fit (they nearly always do).
	if _kernel != null and _kernel.call(&"threat_fill", pm, horizon) >= 0:
		return
	_threat_head.fill(-1)
	pm._threat_over_count = 0
	var room: int = _threat_slot.size()
	var used: int = 0
	var w: int = pm._threat_w
	var w1: int = w - 1
	var h1: int = pm._threat_h - 1
	var x_at: float = pm._threat_x
	var y_at: float = pm._threat_y
	for slot in pm._high:
		if _alive[slot] == 0:
			continue
		var at: Vector2 = _pos[slot]
		var to: Vector2 = at
		var state: int = _state[slot]
		if _motion[slot] != Manager.MOTION_STILL and state != Manager.S_STUCK and state != Manager.S_FROZEN and state != Manager.S_HELD:
			to = at + _vel[slot] * minf(horizon, maxf(_life[slot], 0.0))
		var r: float = _radius[slot]
		var x0: int = clampi(floori((minf(at.x, to.x) - r - x_at) / size), 0, w1)
		var x1: int = clampi(floori((maxf(at.x, to.x) + r - x_at) / size), 0, w1)
		var y0: int = clampi(floori((minf(at.y, to.y) - r - y_at) / size), 0, h1)
		var y1: int = clampi(floori((maxf(at.y, to.y) + r - y_at) / size), 0, h1)
		var span: int = (x1 - x0 + 1) * (y1 - y0 + 1)
		if span > Manager.THREAT_SPAN_MAX:
			_threat_over[pm._threat_over_count] = slot
			pm._threat_over_count += 1
			continue
		if used + span > room:
			room = maxi(room * 2, used + span)
			_threat_slot.resize(room)
			_threat_next.resize(room)
		for y in range(y0, y1 + 1):
			var row: int = y * w
			for x in range(x0, x1 + 1):
				_threat_slot[used] = slot
				_threat_next[used] = _threat_head[row + x]
				_threat_head[row + x] = used
				used += 1


## How many points of its last step a guard tests a shot at: one for a shot that moves less than
## its own width a step, else one every width (at most GUARD_PATH_SAMPLES), so a small fast shot
## (an atom: 1.5 px, 18 px a step) cannot pass a swing or a beam between two steps.
func _guard_samples(slot: int) -> int:
	return maxi(_guard_samples_on(_prev[slot], _pos[slot], _radius[slot]), 1)


## The points one every width of a shot of `radius` from `a` to `b` takes (at least 1, at most
## GUARD_PATH_SAMPLES).
func _guard_samples_on(a: Vector2, b: Vector2, radius: float) -> int:
	var step: float = a.distance_to(b)
	var width: float = maxf(radius * 2.0, 1.0)
	return 1 if step <= width else mini(ceili(step / width), Manager.GUARD_PATH_SAMPLES)


## Point `k` of `samples` along the shot's last step, from where it is now (k 0) back toward where
## it was (that point itself was tested on the step before).
func _guard_point(slot: int, k: int, samples: int) -> Vector2:
	return _pos[slot].lerp(_prev[slot], float(k) / float(samples))


func _guard_has(found: int, slot: int) -> bool:
	for n in found:
		if guard_slots[n] == slot:
			return true
	return false


func _guard_add(found: int, slot: int) -> int:
	if found == guard_slots.size():
		guard_slots.resize(maxi(found * 2, 8))
	guard_slots[found] = slot
	return found + 1


## The team of the actor `caster` now (NONE for no open actor), as `_spawn_row` reads it.
func _team_now(caster: int) -> int:
	var table: Manager.ActorsScript = pm.actors if pm.actors != null else pm._auto_actors
	if table == null or not is_instance_valid(table):
		table = pm.actor_table()
	return table.team_of(caster) if table != null and table.is_open(caster) else Manager.ActorsScript.NONE


## Check a shielded shot against the shots of other teams (aim, actors G3a: a shield stops
## every shot whose caster was on another team when it was cast, a shot of no actor included,
## never its own team's): every one it touches is stopped, one shield charge each (cell by cell,
## in slot order within a cell), and `shot_blocked` is sent. It looks only at the shots on the
## grid cells its path could touch (the shots are put on the target grid's cells once per step,
## the first time a shield needs them). Not charged to the hit-work budget: a block always
## happens (rules R4).
func _shield_block(slot: int) -> void:
	if pm._scan_step != pm._step_index:
		pm._scan_step = pm._step_index
		_fill_shot_grid()
	# Every shot that may touch this one's path this step: its box, widened by the reach.
	var pad: float = _radius[slot] + pm._shot_reach
	var low: Vector2 = _prev[slot].min(_pos[slot]) - Vector2(pad, pad)
	var high: Vector2 = _prev[slot].max(_pos[slot]) + Vector2(pad, pad)
	var x0: int = clampi(floori((low.x - pm._grid_x) / Manager.GRID_CELL), 0, pm._grid_w - 1)
	var x1: int = clampi(floori((high.x - pm._grid_x) / Manager.GRID_CELL), 0, pm._grid_w - 1)
	var y0: int = clampi(floori((low.y - pm._grid_y) / Manager.GRID_CELL), 0, pm._grid_h - 1)
	var y1: int = clampi(floori((high.y - pm._grid_y) / Manager.GRID_CELL), 0, pm._grid_h - 1)
	var mine: int = _team[slot]
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var other: int = _shot_head[y * pm._grid_w + x]
			while other >= 0:
				if _shield[slot] <= 0 and _deflect[slot] == 0:
					return
				# A shot that hits nothing (a field) is not met.
				if _alive[other] != 0 and other != slot and _team[other] != mine and _layers[other] != 0:
					_shield_meets(slot, other)
				other = _shot_next[other]


## `_shield_block` for one shot of another team: stopped or deflected when it touches the shield.
func _shield_meets(slot: int, other: int) -> void:
	var reach: float = _radius[slot] + _radius[other]
	# Both shots move during the step: in the enemy shot's frame the shield goes along
	# the relative path, so the test is the distance from that segment to the origin.
	var start: Vector2 = _prev[slot] - _prev[other]
	var path: Vector2 = (_pos[slot] - _pos[other]) - start
	var along: float = 0.0
	if not path.is_zero_approx():
		along = clampf(-start.dot(path) / path.length_squared(), 0.0, 1.0)
	if (start + path * along).length_squared() > reach * reach:
		return
	_guard_meets(slot, other, _pos[other] - _pos[slot])


## The shot `other` touched the shield or deflect of the shot in `slot` (`normal` the way out of
## it): turned (deflect goes first and keeps the shield's charge, owner 2026-10-29) or stopped.
func _guard_meets(slot: int, other: int, normal: Vector2) -> void:
	var events: Manager.EventsScript = pm.events
	if _deflect[slot] != 0:
		deflect_shot(other, _actor[slot], normal, _tag[slot])
		return
	_shield[slot] -= 1
	var at: Vector2 = _pos[other]
	pm._kill(other)
	if events != null:
		pm._event_slot = slot
		pm._sent += 1
		events.shot_blocked.emit(_actor[slot], at, _tag[slot], slot)
		pm._event_slot = -1


## The shot in `slot` met a wall: when it is the row of a solid shot of another team with a
## shield charge or deflect, that guard turns or stops it (`_guard_meets`), as it would on any
## carrier it touches, and this returns true. Else false: it meets the wall as any wall.
func _solid_guard(slot: int) -> bool:
	var at: Vector2 = _pos[slot]
	for owner: int in _solids:
		if owner == slot or _team[owner] == _team[slot] or (_shield[owner] <= 0 and _deflect[owner] == 0):
			continue
		var half: Vector2 = _job_walls._solid_half(owner, _solids[owner])
		var on: Vector2 = Geometry2D.get_closest_point_to_segment(at, _pos[owner] - half, _pos[owner] + half)
		var reach: float = _radius[owner] + _radius[slot] + Manager.WALL_CELL
		if on.distance_squared_to(at) <= reach * reach:
			# Just out of the wall first, as a bounce does, so a turned shot leaves it.
			_pos[slot] = at - _vel[slot].normalized() * 0.5
			_base[slot] = _pos[slot]
			_guard_meets(owner, slot, at - on)
			return true
	return false


## Put every live shot on the target grid's cell where it is now (chains in slot order), and
## find the most any reaches from there this step (radius and path), for `_shield_block`.
func _fill_shot_grid() -> void:
	_shot_head.fill(-1)
	pm._shot_reach = 0.0
	var other: int = pm._high - 1
	while other >= 0:
		if _alive[other] != 0:
			var at: Vector2 = _pos[other]
			var cell: int = clampi(floori((at.y - pm._grid_y) / Manager.GRID_CELL), 0, pm._grid_h - 1) * pm._grid_w + clampi(floori((at.x - pm._grid_x) / Manager.GRID_CELL), 0, pm._grid_w - 1)
			_shot_next[other] = _shot_head[cell]
			_shot_head[cell] = other
			pm._shot_reach = maxf(pm._shot_reach, _radius[other] + at.distance_to(_prev[other]))
		other -= 1
