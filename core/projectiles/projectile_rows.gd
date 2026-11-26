class_name ProjectileRows
extends Object
## The projectile manager's rows (core/projectiles/projectile_manager.gd, the header and "The global
## cap"): a shot's row written at spawn (`spawn`, `spawn_batch`), its budget's list and the cap's drop, and
## its end (`_kill`, `_expire`). Static functions of the manager (`pm`), whose members hold all of it.

const Manager := preload("res://core/projectiles/projectile_manager.gd")

## Not state (core/sim/README.md): the manager, the other jobs this one calls and the manager's
## arrays it works on, each the manager's own array (shared, never a copy), linked by `link`.
const DERIVED: Array[StringName] = [&"pm", &"_job_draw", &"_job_hits", &"_job_moves", &"_pos", &"_prev", &"_vel", &"_facing", &"_life", &"_radius", &"_actor", &"_team", &"_ramp", &"_budget", &"_layers", &"_pierce", &"_tag", &"_motion", &"_body", &"_look_light_intensity", &"_look_light_reach", &"_carrier_card_ids", &"_orbit_centre", &"_turn", &"_home_at", &"_home_range", &"_home_target", &"_seq", &"_flags", &"_bounce", &"_shield", &"_deflect", &"_span", &"_radius0", &"_growth", &"_curve_from", &"_trail", &"_curve_to", &"_curve_ease", &"_curve_speed", &"_wave", &"_wave_age", &"_base", &"_linger", &"_hold", &"_freeze", &"_stick", &"_stuck_to", &"_caster_slot", &"_caster_at", &"_state", &"_own_head", &"_own_tail", &"_own_prev", &"_own_next", &"_alive", &"_free_slots", &"_owned", &"_room_grid", &"_core", &"_look", &"_born", &"_skip_on", &"_skip_near", &"_tail_from", &"_tail_carry", &"_tail_n"]

var pm: Manager = null
var _job_draw: ProjectileDraw = null
var _job_hits: ProjectileHits = null
var _job_moves: ProjectileMoves = null
var _pos: PackedVector2Array
var _prev: PackedVector2Array
var _vel: PackedVector2Array
var _facing: PackedVector2Array
var _life: PackedFloat32Array
var _radius: PackedFloat32Array
var _actor: PackedInt32Array
var _team: PackedInt32Array
var _ramp: PackedInt32Array
var _budget: PackedByteArray
var _layers: PackedInt32Array
var _pierce: PackedInt32Array
var _tag: PackedInt64Array
var _motion: PackedByteArray
var _body: PackedByteArray
var _look_light_intensity: PackedFloat32Array
var _look_light_reach: PackedFloat32Array
var _carrier_card_ids: Array[StringName]
var _orbit_centre: PackedVector2Array
var _turn: PackedFloat32Array
var _home_at: PackedVector2Array
var _home_range: PackedFloat32Array
var _home_target: PackedInt64Array
var _seq: PackedInt64Array
var _flags: PackedInt32Array
var _bounce: PackedInt32Array
var _shield: PackedInt32Array
var _deflect: PackedByteArray
var _span: PackedFloat32Array
var _radius0: PackedFloat32Array
var _growth: PackedFloat32Array
var _curve_from: PackedFloat32Array
var _trail: PackedByteArray
var _curve_to: PackedFloat32Array
var _curve_ease: PackedFloat32Array
var _curve_speed: PackedFloat32Array
var _wave: PackedFloat32Array
var _wave_age: PackedFloat32Array
var _base: PackedVector2Array
var _linger: PackedFloat32Array
var _hold: PackedFloat32Array
var _freeze: PackedFloat32Array
var _stick: PackedFloat32Array
var _stuck_to: Array
var _caster_slot: PackedInt32Array
var _caster_at: PackedVector2Array
var _state: PackedByteArray
var _own_head: PackedInt32Array
var _own_tail: PackedInt32Array
var _own_prev: PackedInt32Array
var _own_next: PackedInt32Array
var _alive: PackedByteArray
var _free_slots: PackedInt32Array
var _owned: PackedInt32Array
var _room_grid: RoomGrid
var _core: PackedColorArray
var _look: PackedInt32Array
var _born: PackedFloat32Array
var _skip_on: PackedFloat32Array
var _skip_near: PackedFloat32Array
var _tail_from: PackedVector2Array
var _tail_carry: PackedFloat32Array
var _tail_n: PackedInt32Array


## Takes the manager's arrays and jobs, by the names in DERIVED: again whenever the manager's arrays
## may have been replaced (`ProjectileManager._link_jobs`).
func link(manager: Manager) -> void:
	pm = manager
	for name: StringName in DERIVED:
		if name != &"pm":
			set(name, manager.get(name))


## Whether the pool has a free slot for each of `count` new shots (`spawn_batch` makes them then).
func has_room_for(count: int) -> bool:
	return count <= pm._free_count


## Straight shots of one launch at once (a nova's ring, a fan): `velocities.size()` of them, as
## `spawn` with each velocity in turn would make them, their slots written to `slots` (sized by
## the caller, at least as long; -1 for one not made). Returns how many it handled: every one, or
## -1 when it made none because the pool has no free slot for each (at the cap a spawn drops
## another shot, which could be one of these not yet set up by the caller: spawn them one by one
## then, each set up before the next). The caster's team, ramp and budget are read once.
func spawn_batch(caster: int, origin: Vector2, velocities: PackedVector2Array, lifetime: float, radius: float, hit_layers: int, pierce: int, tag: int, slots: PackedInt32Array) -> int:
	var count: int = velocities.size()
	if not Manager.is_caster(caster) or not (lifetime > 0.0) or not origin.is_finite() or slots.size() < count:
		return -1
	if count > pm._free_count:
		return -1
	if (_room_grid.cell_at(origin) & Manager.ROOM_CELL) != 0:
		# Born inside a room wall, as `_spawn_row`: each counts as ended, none takes a slot.
		pm.wall_hits += count
		for n in count:
			slots[n] = -1
		return count
	var table: Manager.ActorsScript = pm.actors if pm.actors != null else pm._auto_actors
	if table == null or not is_instance_valid(table):
		table = pm.actor_table()
	var team: int = Manager.ActorsScript.NONE
	var ramp: int = Manager.ActorsScript.NONE
	var budget: int = Manager.ActorsScript.SHARED
	if table != null and table.is_open(caster):
		team = table.team_of(caster)
		ramp = table.ramp_of(caster)
		budget = table.budget_of(caster)
	for n in count:
		var velocity: Vector2 = velocities[n]
		if not velocity.is_finite():
			slots[n] = -1
			continue
		pm._free_count -= 1
		var slot: int = _free_slots[pm._free_count]
		_write_row(slot, caster, origin, velocity, lifetime, radius, hit_layers, pierce, tag, Manager.MOTION_STRAIGHT, team, ramp, budget)
		slots[n] = slot
	return count


## Write a new shot into the free `slot` (taken off the free list by the caller), with the
## caster's `team`, `ramp` and `budget` as the actor table gave them.
func _write_row(slot: int, caster: int, origin: Vector2, velocity: Vector2, lifetime: float, radius: float, hit_layers: int, pierce: int, tag: int, motion: int, team: int, ramp: int, budget: int) -> void:
	_pos[slot] = origin
	_prev[slot] = origin
	_vel[slot] = velocity if motion == Manager.MOTION_STRAIGHT else Vector2.ZERO
	_motion[slot] = motion
	_body[slot] = 0
	_look_light_intensity[slot] = 1.0
	_look_light_reach[slot] = 1.0
	_carrier_card_ids[slot] = &""
	_turn[slot] = 0.0
	_home_at[slot] = Vector2.INF
	_home_range[slot] = 0.0
	_home_target[slot] = 0
	_life[slot] = lifetime
	_radius[slot] = maxf(radius, 0.0)
	_actor[slot] = caster
	_team[slot] = team
	_ramp[slot] = ramp
	_budget[slot] = budget
	_layers[slot] = hit_layers | Manager.ACTOR_LAYERS
	_pierce[slot] = maxi(pierce, 0)
	_tag[slot] = tag
	_core[slot] = Color.WHITE
	_look[slot] = 0
	_born[slot] = pm.sim_time
	_seq[slot] = pm._next_seq
	pm._next_seq += 1
	# Its tail (with the tails off) starts where it does, from a phase of its own.
	_tail_from[slot] = origin
	_tail_carry[slot] = Manager.TAIL_SPACING * ProjectileDraw.tail_hash(_seq[slot], -1)
	_tail_n[slot] = 0
	_trail[slot] = 0
	_job_draw._join_group(slot, Manager.group_of(caster, tag))
	_skip_on[slot] = 0.0
	_skip_near[slot] = 0.0
	_flags[slot] = Manager.F_QUAD if motion == Manager.MOTION_STILL else 0
	_facing[slot] = Vector2.ZERO
	_bounce[slot] = 0
	_shield[slot] = 0
	_deflect[slot] = 0
	_span[slot] = lifetime
	_radius0[slot] = maxf(radius, 0.0)
	_growth[slot] = 1.0
	_curve_from[slot] = 1.0
	_curve_to[slot] = 1.0
	_curve_ease[slot] = 1.0
	_curve_speed[slot] = 0.0
	_wave[slot] = 0.0
	_wave_age[slot] = 0.0
	_linger[slot] = 0.0
	_hold[slot] = -1.0
	_freeze[slot] = 0.0
	_stick[slot] = 0.0
	_stuck_to[slot] = null
	_base[slot] = origin
	_caster_slot[slot] = Manager.CASTER_BODY
	_caster_at[slot] = Vector2.INF
	_job_moves._drop_moves(slot)
	_job_hits._forget_all(slot)
	_orbit_centre[slot] = Vector2.INF
	pm._threat_step = -1
	_state[slot] = Manager.S_IDLE
	_alive[slot] = 1
	pm._count += 1
	var owner_index: int = _budget[slot]
	_owned[owner_index] += 1
	_own_prev[slot] = _own_tail[owner_index]
	_own_next[slot] = -1
	if _own_tail[owner_index] >= 0:
		_own_next[_own_tail[owner_index]] = slot
	else:
		_own_head[owner_index] = slot
	_own_tail[owner_index] = slot
	if slot >= pm._high:
		pm._high = slot + 1


## Remove, quietly (no event, no `shot_ended`), every shot carrying `tag`. Returns how
## many. For the spell runtime, when a tag is revoked. Walks the pool: not for every frame.
func remove_by_tag(tag: int) -> int:
	var removed: int = 0
	for slot in pm._high:
		if _alive[slot] != 0 and _tag[slot] == tag:
			pm._kill(slot, false)
			removed += 1
	return removed


## Make room: drop the oldest projectile of the budget with the most (the shared one on a tie,
## so the seats keep theirs).
func _drop_one() -> void:
	var richest: int = Manager.ActorsScript.SHARED
	for i in Manager.ActorsScript.SHARED:
		if _owned[i] > _owned[richest]:
			richest = i
	# Its oldest living shot: one its hits spent this pass ends anyway, and its slot is held
	# for its hit (`_take_back_slot` gave up the ones it could).
	var slot: int = _own_head[richest]
	while slot >= 0 and (_flags[slot] & Manager.F_SPENT) != 0 and _own_next[slot] >= 0:
		slot = _own_next[slot]
	pm._freeing_now = true
	pm._kill(slot)
	pm._freeing_now = false
	pm.dropped += 1
