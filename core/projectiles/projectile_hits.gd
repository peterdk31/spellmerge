class_name ProjectileHits
extends Object
## The projectile manager's hits (core/projectiles/projectile_manager.gd, the header): the hit pass
## (`_pass_hits`, with the native kernel or alone), one shot's turn in it, the hit test against the
## target grid, the targets a shot remembers touching, and the merged hits it sends at the pass's end.
## Methods working on the manager (`pm`), whose members hold all of it.

const Manager := preload("res://core/projectiles/projectile_manager.gd")

## What the native hit pass's hand-back says (`ShotKernel.hits`: the shot's n shifted up by
## KERNEL_YIELD_BITS, plus one of these): the whole shot is GDScript's, its hits found are, or only
## Combat's answers for its hits' new entries are (hit batch A5).
const KERNEL_YIELD_BITS: int = 2
const KERNEL_YIELD_MASK: int = 3
const KERNEL_YIELD_FOUND: int = 1
const KERNEL_YIELD_ASK: int = 2

## Not state (core/sim/README.md): the manager, the other jobs this one calls and the manager's
## arrays it works on, each the manager's own array (shared, never a copy), linked by `link`.
const DERIVED: Array[StringName] = [&"pm", &"_job_draw", &"_job_guards", &"_job_moves", &"_job_walls", &"_pos", &"_prev", &"_untested", &"_vel", &"_life", &"_radius", &"_actor", &"_layers", &"_pierce", &"_tag", &"_motion", &"_carrier_card_ids", &"_seq", &"_flags", &"_floor", &"_stick", &"_stuck_to", &"_stuck_off", &"_kinds", &"_state", &"_wait_from", &"_mem_head", &"_mem_id", &"_mem_target", &"_mem_seen", &"_mem_next", &"_target_mark", &"_target_entry", &"_cand_target", &"_cand_along", &"_cand_point", &"_alive", &"_free_slots", &"_targets", &"_target_radius", &"_target_half", &"_target_layer", &"_target_pos", &"_target_key", &"_cell_head", &"_cell_count", &"_cell_box", &"_cell_filled", &"_target_next", &"_solids", &"_room_grid", &"_core", &"_look", &"_skip_id", &"_skip_on", &"_skip_near"]

var pm: Manager = null
var _job_draw: ProjectileDraw = null
var _job_guards: ProjectileGuards = null
var _job_moves: ProjectileMoves = null
var _job_walls: ProjectileWalls = null
var _pos: PackedVector2Array
var _prev: PackedVector2Array
var _untested: PackedVector2Array
var _vel: PackedVector2Array
var _life: PackedFloat32Array
var _radius: PackedFloat32Array
var _actor: PackedInt32Array
var _layers: PackedInt32Array
var _pierce: PackedInt32Array
var _tag: PackedInt64Array
var _motion: PackedByteArray
var _carrier_card_ids: Array[StringName]
var _seq: PackedInt64Array
var _flags: PackedInt32Array
var _floor: PackedFloat32Array
var _stick: PackedFloat32Array
var _stuck_to: Array
var _stuck_off: PackedVector2Array
var _kinds: PackedInt32Array
var _state: PackedByteArray
var _wait_from: PackedByteArray
var _mem_head: PackedInt32Array
var _mem_id: PackedInt64Array
var _mem_target: PackedInt32Array
var _mem_seen: PackedInt32Array
var _mem_next: PackedInt32Array
var _target_mark: PackedInt32Array
var _target_entry: PackedInt32Array
var _cand_target: PackedInt32Array
var _cand_along: PackedFloat32Array
var _cand_point: PackedVector2Array
var _alive: PackedByteArray
var _free_slots: PackedInt32Array
var _targets: Array
var _target_radius: PackedFloat32Array
var _target_half: PackedVector2Array
var _target_layer: PackedInt32Array
var _target_pos: PackedVector2Array
var _target_key: PackedInt64Array
var _cell_head: PackedInt32Array
var _cell_count: PackedInt32Array
var _cell_box: PackedVector4Array
var _cell_filled: PackedInt32Array
var _target_next: PackedInt32Array
var _solids: Dictionary
var _room_grid: RoomGrid
var _core: PackedColorArray
var _look: PackedInt32Array
var _skip_id: PackedInt64Array
var _skip_on: PackedFloat32Array
var _skip_near: PackedFloat32Array


## Takes the manager's arrays and jobs, by the names in DERIVED: again whenever the manager's arrays
## may have been replaced (`ProjectileManager._link_jobs`).
func link(manager: Manager) -> void:
	pm = manager
	for name: StringName in DERIVED:
		if name != &"pm":
			set(name, manager.get(name))


## Pass 3: every shot in turn (from `_resume`, see WORK_PER_STEP): its end if a pass marked one,
## then the bounds, the walls on its path and its hits (`_hit_slot`). The native kernel walks the
## shots that need nothing of GDScript (no end, no wall, no hit) and hands back each one that does,
## in turn, so the events are sent in the same order (a pass with solid shots runs here).
func _pass_hits(top: int, delta: float) -> void:
	var _kernel: Object = pm._kernel
	var _hit_batch: HitBatch = pm._hit_batch
	var limit: Rect2 = pm._bounds.grow(Manager.BOUNDS_MARGIN)
	var resume: int = pm._resume if pm._resume < top else 0
	pm._starved_at = -1
	var n: int = 0
	pm._finding = true
	_hit_batch.open(_targets.size(), top)
	if _kernel != null and not pm._any_solid:
		n = _pass_hits_native(top, delta, limit, resume)
	# Every shot the kernel did not reach (all of them without it).
	while n < top:
		_hit_slot(Manager._wrapped(n + resume, top), delta, limit)
		n += 1
	_end_spent()
	pm._finding = false
	_send_merged()
	if not pm.step_profile.is_empty() and pm._starved_at >= 0:
		# The shots from the first starved one round to where the pass began.
		pm.step_profile[Manager.PROF_PAST_BUDGET] = top - ((pm._starved_at - resume + top) % top)
	pm._resume = maxi(pm._starved_at, 0)


## The hit pass with the native kernel (`ShotKernel.hits`): it takes the shots that need nothing
## of GDScript, and each it hands back (an end, a wall, hits found) takes its turn here, then the
## kernel goes on after it. Returns the shot the pass got to: `top`, or where the kernel failed (it
## logged why; `_pass_hits` does the rest).
func _pass_hits_native(top: int, delta: float, limit: Rect2, resume: int) -> int:
	var _kernel: Object = pm._kernel
	var _hit_batch: HitBatch = pm._hit_batch
	var n: int = 0
	var timing: bool = not pm.step_profile.is_empty()
	var merge_first: bool = false
	while n < top:
		# The kernel's scratch holds every target (a hit handler may have added some).
		_fit_hit_scratch()
		var at: int = pm.profile_clock.call() if timing else 0
		var handed: int = _kernel.call(&"hits", pm, n, top, resume, limit, delta, merge_first)
		merge_first = false
		if timing:
			pm.step_profile[Manager.PROF_KERNEL] += pm.profile_clock.call() - at
			pm.step_profile[Manager.PROF_HANDBACKS] += 1
		if _hit_batch.looked < _hit_batch.entries:
			_look_kernel_entries()
		if handed == -1:
			return top
		if handed < -1:
			return -2 - handed
		n = handed >> KERNEL_YIELD_BITS
		var slot: int = Manager._wrapped(n + resume, top)
		var kind: int = handed & KERNEL_YIELD_MASK
		if kind == KERNEL_YIELD_ASK:
			# Only Combat's answers were missing: asked here, the kernel takes up the shot's hits.
			if _ask_kernel_openings(slot):
				merge_first = true
				continue
			_hit_found(slot)
		elif kind == KERNEL_YIELD_FOUND:
			_hit_found(slot)
		else:
			_hit_slot(slot, delta, limit)
		n += 1
		# The shots after it that the kernel would hand straight back take their turns here, without
		# a call each (a crowd of homing shots on their search step, say).
		while n < top and _kernel_hands_back(Manager._wrapped(n + resume, top)):
			_hit_slot(Manager._wrapped(n + resume, top), delta, limit)
			n += 1
	return top


## For the shot in `slot` the native hit pass handed back to ask (hit batch A5): what `_merge_hit`
## would ask Combat for each entry its hits open (the batch's `ask_target`, in turn), asked and kept,
## so the kernel opens them as `add` would have. Combat's answers only read its bodies and spells,
## and nothing between here and the kernel's hits changes them or the count of events. False, asking
## nothing, with no events to ask through: the shot's hits are then GDScript's (`_hit_found`).
func _ask_kernel_openings(slot: int) -> bool:
	var events: Manager.EventsScript = pm.events
	var batch: HitBatch = pm._hit_batch
	if events == null:
		batch.ask_n = 0
		return false
	var spell: int = _tag[slot]
	var sent: int = pm._sent
	for i in batch.ask_n:
		var t: int = batch.ask_target[i]
		batch.ask(t, spell, sent)
		var asks: int = batch.asks
		if (asks & Manager.ASK_ROOM) != 0:
			events.hit_room_asked.emit(_targets[t], batch.room)
		if (asks & Manager.ASK_DAMAGE) != 0:
			events.hit_damage_asked.emit(spell, slot, batch.damage)
		batch.keep_answers(t, spell)
	batch.ask_n = 0
	return true


## The look of each entry the native hit pass opened (hit batch A4: it keeps no `StringName`),
## from its shot's slot, before any handler can change the slot.
func _look_kernel_entries() -> void:
	var _hit_batch: HitBatch = pm._hit_batch
	var batch: HitBatch = _hit_batch
	for entry in range(batch.looked, batch.entries):
		var slot: int = batch.slot[entry]
		batch.set_look(entry, _carrier_card_of(slot), pm._kind_of(slot), _core[slot], _look[slot])
	batch.kernel_entries_looked(_targets.size())


## Size the native hit pass's scratch for every target (`_cand_*`, `_target_mark`, `_target_entry`).
func _fit_hit_scratch() -> void:
	var targets: int = _targets.size()
	if _cand_target.size() < targets:
		_cand_target.resize(targets)
		_cand_along.resize(targets)
		_cand_point.resize(targets)
	if _target_mark.size() < targets:
		_target_mark.resize(targets)
		_target_entry.resize(targets)


## Whether the native hit pass would hand the shot in `slot` straight back for its state: one to
## end, or waiting for passes other than its homing search alone (the kernel catches that up).
func _kernel_hands_back(slot: int) -> bool:
	var state: int = _state[slot]
	if state < Manager.S_STUCK:
		return false
	return state != Manager.S_WAITING or _wait_from[slot] != Manager.B_HOMING or (_kinds[slot] & Manager.AFTER_HOMING_MASK) != 0


## One shot's turn in the hit pass (see `_pass_hits`).
func _hit_slot(slot: int, delta: float, limit: Rect2) -> void:
	# A hit handler may have dropped or reused this slot (S_IDLE): a projectile spawned
	# during this step waits for the next one.
	var state: int = _state[slot]
	if state == Manager.S_IDLE:
		return
	_state[slot] = Manager.S_DONE
	if state >= Manager.S_STUCK:
		if state == Manager.S_WAITING:
			_job_moves._catch_up(slot, delta)
			state = _state[slot]
			_state[slot] = Manager.S_DONE
		if state == Manager.S_EXPIRE:
			if _test_deferred(slot):
				pm._expire(slot)
			return
		if state == Manager.S_GONE:
			if _test_deferred(slot):
				pm._kill(slot)
			return
		if state == Manager.S_STUCK or state == Manager.S_FROZEN:
			return
	if not limit.has_point(_pos[slot]):
		if _test_deferred(slot):
			pm._kill(slot)
		return
	var landed: bool = false
	if (_flags[slot] & Manager.F_FALLING) != 0:
		landed = _fall(slot)
		if _pos[slot].y < _floor[slot] - Manager.FALL_BAND:
			return
	var seq_now: int = _seq[slot]
	# A shot that meets a wall is cut short there: it can still hit what is
	# in front of the wall, then it ends (or bounces). A ghost shot ignores walls; a solid one is
	# a wall and stops at one (`_step_solid`).
	var walled: bool = false
	if pm._any_solid and _solids.has(slot):
		_job_walls._step_solid(slot, _solids[slot])
	elif (_flags[slot] & Manager.F_GHOST) == 0:
		# With no walls the grid answers -1 at once (as the check it had before).
		var cut: float = _room_grid.wall_hit(_prev[slot], _pos[slot])
		if cut >= 0.0 and pm._any_solid:
			cut = _job_walls._past_own_solid(slot, cut)
		if cut >= 0.0:
			walled = true
			_pos[slot] = _prev[slot].lerp(_pos[slot], cut)
	if _layers[slot] != 0 and not _targets.is_empty():
		# Past the budget a shot flies on untested and keeps where its untested path starts; one
		# that ends at a wall is tested all the same (H2: no lost damage).
		if pm._work_left <= 0 and not walled:
			_defer(slot)
			if pm._starved_at < 0:
				pm._starved_at = slot
			return
		# A piercing shot passes through every target on its path this step, each hit once
		# (it remembers it). A hit handler may end it or even reuse the slot.
		var seq: int = _seq[slot]
		_hit_test(slot)
		# What its path no longer touches it may hit again (a shot its hits spent forgets all as it ends).
		if _alive[slot] != 0 and _seq[slot] == seq and (_flags[slot] & Manager.F_SPENT) == 0:
			_forget_left(slot)
	# A shot that stuck to a target this step stays stuck, even at a wall. One that met a
	# guarding solid shot is turned or stopped by it instead (`_solid_guard`). One its hits spent
	# meets no wall: it ends with the pass's spent shots.
	if walled and _alive[slot] != 0 and (_flags[slot] & (Manager.F_STUCK | Manager.F_SPENT)) == 0 and not (pm._any_solid and _job_guards._solid_guard(slot)):
		_job_walls._wall_end(slot)
	elif landed and _alive[slot] != 0 and _seq[slot] == seq_now and (_flags[slot] & (Manager.F_STUCK | Manager.F_SPENT)) == 0:
		pm._expire(slot)


## A falling shot's step (`set_floor`): cut at its floor line if it reached it (true: it lands),
## and its path's start moved down to where it enters the band, so only that part meets walls and
## hits. Above the band it touches nothing (`_hit_slot` stops there).
func _fall(slot: int) -> bool:
	var from: Vector2 = _prev[slot]
	var to: Vector2 = _pos[slot]
	var floor_y: float = _floor[slot]
	var landed: bool = to.y >= floor_y and to.y > from.y
	if landed:
		to = from.lerp(to, (floor_y - from.y) / (to.y - from.y)) if from.y < floor_y else from
		_pos[slot] = to
	var top: float = floor_y - Manager.FALL_BAND
	if from.y < top and to.y >= top:
		_prev[slot] = from.lerp(to, (top - from.y) / (to.y - from.y))
	return landed


## Mark the shot in `slot` passed over by the hit-work budget: its path from `_prev` on (or from
## where an earlier deferral began) waits for its next test.
func _defer(slot: int) -> void:
	var flags: int = _flags[slot]
	if (flags & Manager.F_DEFERRED) == 0:
		_flags[slot] = flags | Manager.F_DEFERRED
		_untested[slot] = _prev[slot]


## Before a deferred shot ends (its life out, out of bounds, vanishing): test the path it was not
## tested on, whatever the budget, so its damage is not lost. Returns whether it is still the same
## live shot to end (a hit may have ended it, or a handler taken its slot).
func _test_deferred(slot: int) -> bool:
	if (_flags[slot] & Manager.F_DEFERRED) == 0:
		return true
	if _layers[slot] == 0 or _targets.is_empty():
		_flags[slot] &= ~Manager.F_DEFERRED
		return true
	var seq: int = _seq[slot]
	_hit_test(slot)
	# One its hits spent ends with the pass's spent shots, not here.
	return _alive[slot] != 0 and _seq[slot] == seq and (_flags[slot] & Manager.F_SPENT) == 0


## The rest of a shot's turn once the native hit pass found `_cand_found` targets on its path (it
## did what `_hit_test` does before its hits): hit them, then forget what its path left.
func _hit_found(slot: int) -> void:
	var seq: int = _seq[slot]
	_hit_candidates(slot, pm._cand_found)
	if _alive[slot] != 0 and _seq[slot] == seq and (_flags[slot] & Manager.F_SPENT) == 0:
		_forget_left(slot)


## Test the path of the shot in `slot` this step against the targets on the grid, and hit every
## target it touches that it has not hit since it last left it, nearest first, as long as it
## lives (its pierce); returns true when it hit any. One scan finds them all: the shot's
## remembered targets are marked first (`_mark_memory`), so the cost is the targets touched plus
## the ones remembered. The search widens with the farthest any target's shape reaches
## (`_max_target_reach`), so a big target whose centre is cells away is still found. The cells searched are those the path touches, widened
## by both radii.
func _hit_test(slot: int) -> bool:
	var from: Vector2 = _prev[slot]
	var to: Vector2 = _pos[slot]
	# A shot the budget passed over sweeps its whole path since its last test (`_defer`).
	if (_flags[slot] & Manager.F_DEFERRED) != 0:
		_flags[slot] &= ~Manager.F_DEFERRED
		from = _untested[slot]
	# Where the step starts: a payload still on the body that fired it there is not clear of it.
	var start: Vector2 = from
	if pm._any_solid and _solids.has(slot):
		# A solid shot hits along its row.
		var half: Vector2 = _job_walls._solid_half(slot, _solids[slot])
		from = to - half
		to += half
	var radius: float = _radius[slot]
	var lowest: Vector2 = from.min(to)
	var highest: Vector2 = from.max(to)
	var pad: Vector2 = Vector2.ONE * (radius + pm._max_target_reach)
	var low: Vector2 = lowest - pad
	var high: Vector2 = highest + pad
	# The grid's numbers, read once: nothing in the test changes them (a member of another object
	# costs a lookup at each read).
	var grid_x: float = pm._grid_x
	var grid_y: float = pm._grid_y
	var grid_w: int = pm._grid_w
	var grid_h: int = pm._grid_h
	var grid_fill: int = pm._grid_fill
	var mem_step: int = pm._mem_step
	var x0: int = clampi(floori((low.x - grid_x) / Manager.GRID_CELL), 0, grid_w - 1)
	var x1: int = clampi(floori((high.x - grid_x) / Manager.GRID_CELL), 0, grid_w - 1)
	var y0: int = clampi(floori((low.y - grid_y) / Manager.GRID_CELL), 0, grid_h - 1)
	var y1: int = clampi(floori((high.y - grid_y) / Manager.GRID_CELL), 0, grid_h - 1)
	# What a target must touch to be hit: the path's box widened
	# by the shot's radius (and a little, for rounding).
	var margin: Vector2 = Vector2.ONE * (radius + 0.05)
	var near_low: Vector2 = lowest - margin
	var near_high: Vector2 = highest + margin
	# The rest is read only once a cell's box lets the path in: most tests in a crowd end at the
	# boxes (2026-10-31). A test that looks at no target leaves the shot's memory unmarked, and
	# `_forget_left` then forgets every entry, as it would after marking them and seeing none.
	var looking: bool = false
	var path: Vector2 = Vector2.ZERO
	var path_sq: float = 0.0
	var middle: Vector2 = Vector2.ZERO
	var half: float = 0.0
	var layers: int = 0
	# Whether it still spares the body it started on (`exclude`): on it, or coming at it from close by.
	var spared: bool = _skip_on[slot] > 0.0 and _still_spares(slot, start, _pos[slot] - start)
	var stamp: int = 0
	var found: int = 0
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var cell: int = y * grid_w + x
			if _cell_filled[cell] != grid_fill:
				_cell_info(cell)
			var in_cell: int = _cell_count[cell]
			if in_cell == 0:
				continue
			# Every target in the cell is charged as examined, and a cell whose targets' box the
			# path's box does not touch is passed at once (performance, 2026-10-28: a hit test in
			# the stress crowd 2.6 -> 2.2 us).
			pm._work_left -= in_cell
			var box: Vector4 = _cell_box[cell]
			if box.x > near_high.x or box.y > near_high.y or box.z < near_low.x or box.w < near_low.y:
				continue
			if not looking:
				looking = true
				path = to - from
				path_sq = path.length_squared()
				# A target farther from the path's middle than half the path plus both radii misses:
				# that one distance turns most of the targets in the cells away before anything else
				# is read of them (a target the shot is inside of is never that far either).
				middle = (from + to) * 0.5
				half = sqrt(path_sq) * 0.5 + 0.01
				layers = _layers[slot]
				stamp = _mark_memory(slot)
			var t: int = _cell_head[cell]
			while t >= 0:
				var centre: Vector2 = _target_pos[t]
				var reach: float = radius + _target_radius[t]
				# A box's corner is no farther from its centre than its two halves (`shape_half`) together.
				var shape_half: Vector2 = _target_half[t]
				var far: float = half + reach + shape_half.x + shape_half.y
				if middle.distance_squared_to(centre) > far * far:
					t = _target_next[t]
					continue
				if (_target_layer[t] & layers) == 0:
					t = _target_next[t]
					continue
				var along: float = 0.0
				var closest: Vector2 = from
				if shape_half == Vector2.ZERO:
					if path_sq > 0.0:
						along = clampf((centre - from).dot(path) / path_sq, 0.0, 1.0)
					closest = from + path * along
					if closest.distance_squared_to(centre) > reach * reach:
						t = _target_next[t]
						continue
				else:
					along = HitShape.along(from, path, path_sq, centre, shape_half)
					closest = from + path * along
					if HitShape.gap_sq(closest - centre, shape_half) > reach * reach:
						t = _target_next[t]
						continue
				# A target already hit: the path still touches it, so it stays remembered.
				if _target_mark[t] == stamp:
					_mem_seen[_target_entry[t]] = mem_step
					t = _target_next[t]
					continue
				if spared and _skip_id[slot] == _target_key[t]:
					t = _target_next[t]
					continue
				found = _keep_candidate(found, t, along, closest)
				t = _target_next[t]
	# Clear of the body it started on, and not coming back across it: it hits it from now.
	if _skip_on[slot] > 0.0 and not spared:
		_skip_on[slot] = 0.0
	return _hit_candidates(slot, found)


## Whether the shot in `slot`, its step starting at `start` and going `way`, still spares the body
## it started on (`exclude`): its step starts on that body's hit shape, or, cast from that body, it
## is coming at it from no farther off than `_skip_near`, its line passing within that of it. A
## caster that moved far ahead of its own shot (a teleport along the aim) is not spared. A shot cast from a staff tip off its
## caster's body does not hit that body as it crosses it on its way out (owner, 2026-11-07: a nova's
## shot aimed back across the wizard hit them), even crossing it in one step (an atom) or with the
## body walking into its line (owner, 2026-11-16); one that has passed it, or leaves it and turns
## back (return, bounce), does.
func _still_spares(slot: int, start: Vector2, way: Vector2) -> bool:
	var t: int = _target_key.find(_skip_id[slot]) if _skip_id[slot] != 0 else -1
	if t < 0 or (_target_layer[t] & _layers[slot]) == 0:
		return false
	var reach: float = _radius[slot] + _target_radius[t]
	var to_centre: Vector2 = _target_pos[t] - start
	var box: Vector2 = _target_half[t]
	var apart_sq: float = to_centre.length_squared() if box == Vector2.ZERO else HitShape.gap_sq(to_centre, box)
	if apart_sq <= reach * reach:
		return true
	var near: float = _skip_near[slot]
	if near <= 0.0:
		return false
	var within: float = reach + near
	var ahead: float = to_centre.dot(way)
	if ahead <= 0.0 or apart_sq > within * within:
		return false
	# The square of how far the body's shape stands off the shot's line.
	if box == Vector2.ZERO:
		return apart_sq - ahead * ahead / way.length_squared() <= within * within
	return HitShape.line_gap_sq(-to_centre, way, box) <= within * within


## Hit the `found` targets `_hit_test` kept for the shot in `slot` (`_cand_*`), nearest first;
## returns true when it hit any. A hit handler may end the shot or take its slot; a stuck one stops.
func _hit_candidates(slot: int, found: int) -> bool:
	var _hit_batch: HitBatch = pm._hit_batch
	var seq: int = _seq[slot]
	var hit: bool = false
	for n in found:
		if _alive[slot] == 0 or _seq[slot] != seq or (_flags[slot] & (Manager.F_STUCK | Manager.F_SPENT)) != 0:
			break
		var t: int = _cand_target[n]
		if _target_layer[t] == 0 or not is_instance_valid(_targets[t]):
			continue
		if not _hit_batch.takes(t):
			# Its merged hits so far kill it: the shot is not spent on it.
			continue
		pm._work_left -= Manager.HIT_WORK
		hit = true
		_register_hit(slot, t, _cand_point[n])
	return hit


## Take the count of `cell` and the box round its targets' hit shapes from its chain (see
## `_cell_count`). The positions only change when the grid is filled, so this is what a filling
## would have written.
func _cell_info(cell: int) -> void:
	_cell_filled[cell] = pm._grid_fill
	var count: int = 0
	var t: int = _cell_head[cell]
	if t < 0:
		_cell_count[cell] = 0
		return
	var low: Vector2 = Vector2.INF
	var high: Vector2 = -Vector2.INF
	while t >= 0:
		var centre: Vector2 = _target_pos[t]
		var r: float = _target_radius[t]
		var reach: Vector2 = _target_half[t] + Vector2(r, r)
		low = low.min(centre - reach)
		high = high.max(centre + reach)
		count += 1
		t = _target_next[t]
	_cell_count[cell] = count
	_cell_box[cell] = Vector4(low.x, low.y, high.x, high.y)


## Put target `t` (`along` its path, 0 to 1, nearest point `closest`) into the sorted candidates
## of the hit test (`_cand_*`, which grow when full); returns the new count.
func _keep_candidate(found: int, t: int, along: float, closest: Vector2) -> int:
	if found == _cand_target.size():
		var size: int = maxi(16, found * 2)
		_cand_target.resize(size)
		_cand_along.resize(size)
		_cand_point.resize(size)
	var at: int = found
	while at > 0 and _cand_along[at - 1] > along:
		_cand_target[at] = _cand_target[at - 1]
		_cand_along[at] = _cand_along[at - 1]
		_cand_point[at] = _cand_point[at - 1]
		at -= 1
	_cand_target[at] = t
	_cand_along[at] = along
	_cand_point[at] = closest
	return found + 1


## Mark the targets the shot in `slot` remembers (`_target_mark` set to the returned stamp,
## `_target_entry` to their memory entry). An entry keeps the target's index as a hint and finds
## it again by its id when the targets were packed since; one whose target is gone is dropped.
func _mark_memory(slot: int) -> int:
	var stamp: int = pm._mark_stamp + 1
	pm._mark_stamp = stamp
	var mem_free: int = pm._mem_free
	if _target_mark.size() < _targets.size():
		_target_mark.resize(_targets.size())
		_target_entry.resize(_targets.size())
	var before: int = -1
	var at: int = _mem_head[slot]
	while at >= 0:
		var next: int = _mem_next[at]
		var t: int = _mem_target[at]
		if t < 0 or t >= _targets.size() or _target_key[t] != _mem_id[at]:
			t = _target_key.find(_mem_id[at])
			_mem_target[at] = t
		if t < 0:
			if before < 0:
				_mem_head[slot] = next
			else:
				_mem_next[before] = next
			_mem_next[at] = mem_free
			mem_free = at
		else:
			_target_mark[t] = stamp
			_target_entry[t] = at
			before = at
		at = next
	pm._mem_free = mem_free
	return stamp


## The shot in `slot` forgets every target it touches, so it hits each again at its next test,
## though they never left it (a pool's tick: what stands in it is struck again). False for an empty
## slot. Not to be called while the manager steps.
func forget_hits(slot: int) -> bool:
	if slot < 0 or slot >= pm._cap or _alive[slot] == 0:
		return false
	_forget_all(slot)
	return true


## The shot in `slot` hit target `t` this step: remember it until it leaves it.
func _remember(slot: int, t: int) -> void:
	if pm._mem_free < 0:
		_grow_memory(_mem_id.size() * 2)
	var at: int = pm._mem_free
	pm._mem_free = _mem_next[at]
	_mem_id[at] = _target_key[t]
	_mem_target[at] = t
	_mem_seen[at] = pm._mem_step
	_mem_next[at] = _mem_head[slot]
	_mem_head[slot] = at


## Forget the targets the path of the shot in `slot` did not touch this step: it has left them.
func _forget_left(slot: int) -> void:
	var mem_step: int = pm._mem_step
	var mem_free: int = pm._mem_free
	var before: int = -1
	var at: int = _mem_head[slot]
	while at >= 0:
		var next: int = _mem_next[at]
		if _mem_seen[at] != mem_step:
			if before < 0:
				_mem_head[slot] = next
			else:
				_mem_next[before] = next
			_mem_next[at] = mem_free
			mem_free = at
		else:
			before = at
		at = next
	pm._mem_free = mem_free


## Forget every target of the shot in `slot` (it is new, it turned back or it bounced).
func _forget_all(slot: int) -> void:
	var at: int = _mem_head[slot]
	while at >= 0:
		var next: int = _mem_next[at]
		_mem_next[at] = pm._mem_free
		pm._mem_free = at
		at = next
	_mem_head[slot] = -1


## Room for `size` remembered hits in all (the new entries go on the free list).
func _grow_memory(size: int) -> void:
	var old: int = _mem_id.size()
	_mem_id.resize(size)
	_mem_target.resize(size)
	_mem_seen.resize(size)
	_mem_next.resize(size)
	for at in range(size - 1, old - 1, -1):
		_mem_next[at] = pm._mem_free
		pm._mem_free = at


## The carrier card of the shot in `slot`: its card's (`set_carrier_card`), else by its body.
func _carrier_card_of(slot: int) -> StringName:
	if _carrier_card_ids[slot] != &"":
		return _carrier_card_ids[slot]
	var kind: int = pm._kind_of(slot)
	return &"rune" if kind == Manager.KIND_RUNE else &"bolt"


func _register_hit(slot: int, target: int, at: Vector2) -> void:
	var events: Manager.EventsScript = pm.events
	var _hit_batch: HitBatch = pm._hit_batch
	var node: Variant = _targets[target]
	var caster: int = _actor[slot]
	var tag: int = _tag[slot]
	var heading: Vector2 = _vel[slot].normalized()
	if heading == Vector2.ZERO:
		# A still shot has no heading: point from the shot to the target instead.
		heading = at.direction_to(_target_pos[target])
		if heading == Vector2.ZERO:
			heading = Vector2.RIGHT
	if _stick[slot] > 0.0 and is_instance_valid(node):
		# Stick to the target: it carries the shot until the stick time is up.
		_flags[slot] |= Manager.F_STUCK
		_stuck_to[slot] = node
		# Where its line of flight comes closest to the target's centre (a head-on shot: the
		# centre), not `at`, the point of this step's path nearest it: that one lies anywhere from
		# the centre to the rim by when in its step the shot met the target, so what a stuck shot
		# fires from inside (a nova) hit all or half of its ring by chance. Only a straight shot
		# has such a line: an orbit (on its circle) and a still shot stick where they are.
		var centre: Vector2 = (node as Node2D).global_position
		var stick_at: Vector2 = at
		if _motion[slot] == Manager.MOTION_STRAIGHT and not _vel[slot].is_zero_approx():
			stick_at = at + heading * heading.dot(centre - at)
		_stuck_off[slot] = stick_at - centre
		_life[slot] = _stick[slot]
		_stick[slot] = 0.0
		_job_moves._join(slot, Manager.B_STUCK)
		# `_vel` stays: `_pass_stuck` never moves a stuck shot by it, and a payload it fires (on hit
		# or on a timer) still goes the way the shot was flying.
	elif _pierce[slot] > 0:
		_pierce[slot] -= 1
		_remember(slot, target)
	else:
		# Ended with the pass's other spent shots, after its hits (`_end_spent`).
		_flags[slot] |= Manager.F_SPENT
		_hit_batch.spend(slot, at)
	if events != null and is_instance_valid(node):
		_merge_hit(slot, target, caster, tag, at, heading)


## The hit of the shot in `slot` on target `target`, kept for the end of the pass (`_hit_batch`): added
## to the caster's hits on it with the same tag, or the first of them, whose room is worked out from
## the body's room and the spell's damage, each asked of Combat once a pass and again after any event
## (a shot that hits alone asks its damage for itself; hit batch A2).
func _merge_hit(slot: int, target: int, caster: int, tag: int, at: Vector2, heading: Vector2) -> void:
	var events: Manager.EventsScript = pm.events
	var _hit_batch: HitBatch = pm._hit_batch
	if _hit_batch.add_to(target, caster, tag, (_flags[slot] & Manager.F_ALONE) != 0, _flags, Manager.F_ALONE) >= 0:
		return
	var batch: HitBatch = _hit_batch
	var entry: int = batch.add(target, _targets.size(), caster, tag, slot, _seq[slot], at, heading, _carrier_card_of(slot), pm._kind_of(slot), _core[slot], _look[slot], (_flags[slot] & Manager.F_ALONE) != 0, pm._sent)
	# What the batch has not been told since the pass's last event (`add`).
	var asks: int = batch.asks
	if (asks & Manager.ASK_ROOM) != 0:
		events.hit_room_asked.emit(_targets[target], batch.room)
	if (asks & Manager.ASK_DAMAGE) != 0:
		events.hit_damage_asked.emit(tag, slot, batch.damage)
	batch.take_room(entry)


## The shots the pass's hits spent, ended in the order they were (their tails where they were spent;
## their slots held and their `shot_ended` kept for after the hits, as the pass still finds them, `_finding`).
func _end_spent() -> void:
	var _hit_batch: HitBatch = pm._hit_batch
	for i in _hit_batch.spent_count():
		_end_spent_at(i)
	_hit_batch.forget_spent()


## A held slot handed back to the free list now (`_spawn_row` at the cap, no slot free): the last
## held one, else a spent shot's, ended at once; never one of a shot that hits alone (its merged hit,
## still to send, reads its own profile by its slot). The hit sent later names no shot (its entry's
## `seq`). False for none.
func _take_back_slot() -> bool:
	var _hit_batch: HitBatch = pm._hit_batch
	var i: int = _hit_batch.held_count() - 1
	while i >= 0:
		var slot: int = _hit_batch.held_slot(i)
		if (_flags[slot] & Manager.F_ALONE) == 0:
			_hit_batch.drop_held(i)
			_free_slots[pm._free_count] = slot
			pm._free_count += 1
			return true
		i -= 1
	i = _hit_batch.spent_count() - 1
	while i >= 0:
		var spent: int = _hit_batch.spent_slot(i)
		if (_flags[spent] & Manager.F_ALONE) == 0 and _end_spent_at(i):
			# Out of the list (the last takes its place), and its slot, held by its end, back now.
			_hit_batch.drop_spent(i)
			return pm._free_count > 0 or _take_back_slot()
		i -= 1
	return false


## The spent shot `i` of the batch's list ended (its tail where it was spent; its slot held and its
## end kept for after the hits, as the pass still finds them), unless a handler ended it meanwhile or its
## slot holds another shot now (a new shot's flags have no F_SPENT). True when it ended it.
func _end_spent_at(i: int) -> bool:
	var _hit_batch: HitBatch = pm._hit_batch
	var slot: int = _hit_batch.spent_slot(i)
	if _alive[slot] == 0 or (_flags[slot] & Manager.F_SPENT) == 0:
		return false
	_flags[slot] &= ~Manager.F_SPENT
	var tag: int = _tag[slot]
	_job_draw._end_tail(slot, _hit_batch.spent_at(i))
	pm._kill(slot, false)
	if tag != 0:
		_hit_batch.keep_end(tag)
	return true


## The pass's merged hits sent, in the order of their first hits, then its spent shots' ends. A
## handler may hit or spawn again: it is sent at once (`_finding` is off by now).
func _send_merged() -> void:
	var events: Manager.EventsScript = pm.events
	var _hit_batch: HitBatch = pm._hit_batch
	var batch: HitBatch = _hit_batch
	# The entries' arrays read once (a member of another object costs a lookup at each read): each
	# local is the batch's own array, not a copy, and no entry is added while they are sent
	# (`_finding` is off). Their number is read anew, so a handler's `clear()` (`entries` to 0) stops what is left.
	var targets: PackedInt32Array = batch.target
	var slots: PackedInt32Array = batch.slot
	var seqs: PackedInt64Array = batch.seq
	var casters: PackedInt32Array = batch.caster
	var points: PackedVector2Array = batch.at
	var headings: PackedVector2Array = batch.heading
	var tags: PackedInt64Array = batch.tag
	var cards: Array[StringName] = batch.card
	var bodies: PackedInt32Array = batch.body
	var cores: PackedColorArray = batch.core
	var looks: PackedInt32Array = batch.look
	var counts: PackedInt32Array = batch.count
	var entry: int = 0
	while entry < batch.entries:
		var target: int = targets[entry]
		var node: Variant = _targets[target] if target < _targets.size() else null
		if events != null and node != null and is_instance_valid(node):
			var shot: int = slots[entry] if _seq[slots[entry]] == seqs[entry] else -1
			pm._send_hit(casters[entry], node, points[entry], headings[entry], tags[entry], shot, cards[entry], bodies[entry], cores[entry], looks[entry], counts[entry])
		entry += 1
	batch.forget_entries()
	for i in batch.held_count():
		_free_slots[pm._free_count] = batch.held_slot(i)
		pm._free_count += 1
	batch.forget_held()
	# A handler's end meanwhile is sent at once (`_finding` is off by now), so nothing joins this list.
	var i: int = 0
	while i < batch.ended_count():
		pm._sent += 1
		pm.shot_ended.emit(batch.ended_tag(i))
		i += 1
	batch.forget_ended()
