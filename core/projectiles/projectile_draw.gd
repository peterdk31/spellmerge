class_name ProjectileDraw
extends Object
## The projectile manager's drawing (core/projectiles/projectile_manager.gd, "Drawing"): each frame's
## rows of every batch (`update_draw`), the motes shots give off and leave as tails, the tails' groups
## and their share of the pool, and the codes a row is packed in (`row_*`, `look_*`). Static
## functions of the manager (`pm`), whose members hold all of it.

const Manager := preload("res://core/projectiles/projectile_manager.gd")

## Not state (core/sim/README.md): the manager, the other jobs this one calls and the manager's
## arrays it works on, each the manager's own array (shared, never a copy), linked by `link`.
const DERIVED: Array[StringName] = [&"pm", &"_job_batches", &"_job_moves", &"_job_walls", &"_pos", &"_prev", &"_vel", &"_facing", &"_life", &"_radius", &"_ramp", &"_tag", &"_motion", &"_body", &"_look_light_intensity", &"_look_light_reach", &"_seq", &"_drawn_seq", &"_drawn_radius", &"_drawn_look", &"_drawn_batch", &"_drawn_color", &"_drawn_size", &"_drawn_particles", &"_flags", &"_alive", &"_solids", &"_room_grid", &"_core", &"_look", &"_born", &"_nodes", &"_rooms", &"_buffers", &"_mirrors", &"_light_rows", &"_light_counts", &"_still_views", &"_draw_regions", &"_no_rows", &"_batch_counts", &"_body_meshes", &"_draw_out", &"spark_births", &"_tail_from", &"_tail_carry", &"_tail_n", &"_end_births", &"_group", &"_group_count", &"_groups", &"_group_at", &"_by_group", &"_group_start", &"_group_end", &"_group_tail", &"_group_ask", &"_group_spacing", &"_group_share", &"_group_want", &"_group_frame", &"_group_seen", &"_group_sort"]
## The drawing's functions (core/sim/README.md, "The line"): they read the game and write only what is drawn.
const VIEW: Array[StringName] = [&"update_draw", &"_give_off_sparks", &"_give_off_spark"]

var pm: Manager = null
var _job_batches: ProjectileBatches = null
var _job_moves: ProjectileMoves = null
var _job_walls: ProjectileWalls = null
var _pos: PackedVector2Array
var _prev: PackedVector2Array
var _vel: PackedVector2Array
var _facing: PackedVector2Array
var _life: PackedFloat32Array
var _radius: PackedFloat32Array
var _ramp: PackedInt32Array
var _tag: PackedInt64Array
var _motion: PackedByteArray
var _body: PackedByteArray
var _look_light_intensity: PackedFloat32Array
var _look_light_reach: PackedFloat32Array
var _seq: PackedInt64Array
var _drawn_seq: PackedInt64Array
var _drawn_radius: PackedFloat32Array
var _drawn_look: PackedInt32Array
var _drawn_batch: PackedByteArray
var _drawn_color: PackedColorArray
var _drawn_size: PackedFloat32Array
var _drawn_particles: PackedInt32Array
var _flags: PackedInt32Array
var _alive: PackedByteArray
var _solids: Dictionary
var _room_grid: RoomGrid
var _core: PackedColorArray
var _look: PackedInt32Array
var _born: PackedFloat32Array
var _nodes: Array[MultiMeshInstance2D]
var _rooms: PackedInt32Array
var _buffers: Array[PackedFloat32Array]
var _mirrors: Array[MultiMesh]
var _light_rows: Array[PackedFloat32Array]
var _light_counts: PackedInt32Array
var _still_views: Array[StillShotView]
var _draw_regions: Manager.DrawRegionsScript
var _no_rows: PackedFloat32Array
var _batch_counts: PackedInt32Array
var _body_meshes: PackedInt32Array
var _draw_out: PackedInt32Array
var spark_births: PackedFloat32Array
var _tail_from: PackedVector2Array
var _tail_carry: PackedFloat32Array
var _tail_n: PackedInt32Array
var _end_births: PackedFloat32Array
var _group: PackedInt32Array
var _group_count: PackedInt32Array
var _groups: PackedInt32Array
var _group_at: PackedInt32Array
var _by_group: PackedInt32Array
var _group_start: PackedInt32Array
var _group_end: PackedInt32Array
var _group_tail: PackedFloat32Array
var _group_ask: PackedFloat32Array
var _group_spacing: PackedFloat32Array
var _group_share: PackedFloat32Array
var _group_want: PackedFloat32Array
var _group_frame: PackedInt32Array
var _group_seen: PackedInt32Array
var _group_sort: PackedFloat32Array


## Takes the manager's arrays and jobs, by the names in DERIVED: again whenever the manager's arrays
## may have been replaced (`ProjectileManager._link_jobs`).
func link(manager: Manager) -> void:
	pm = manager
	for name: StringName in DERIVED:
		if name != &"pm":
			set(name, manager.get(name))


func update_draw(fraction: float = -1.0) -> void:
	var _kernel: Object = pm._kernel
	pm.spark_birth_count = 0
	# Last frame's rows let go before this frame's are written (no copy of a buffer still held).
	for batch in _light_rows.size():
		_light_rows[batch] = _no_rows
		_light_counts[batch] = 0
	if pm._draw_node == null:
		pm.drawn = 0
		pm._end_count = 0
		pm._end_wanted = 0.0
		return
	# A shot that ended since the last frame still lays its tail's end (`_lay_ends`), even if it was
	# never drawn (fired and spent within a step).
	if pm._high == 0 and pm.drawn == 0 and pm._end_count == 0:
		return
	if fraction < 0.0:
		fraction = Engine.get_physics_interpolation_fraction()
	fraction = clampf(fraction, 0.0, 1.0)
	for node in _nodes:
		pm._set_sim_time(node)
	# The native kernel counts and writes every shot when no shot is solid (`_write_stones`); either
	# way `_draw_out` says what was written, into the kernel's buffers or the manager's.
	var kernel_draw: bool = _kernel != null and not pm._any_solid
	if kernel_draw:
		_kernel.call(&"count_draw", pm)
	else:
		_count_batches()
	for batch in pm._batch_total:
		_rooms[batch] = _fit_batch(_nodes[batch].multimesh, _buffers[batch], _rooms[batch], _batch_counts[batch])
	# Tails as motes (SPARK_TAIL): the drawing lays them, first in the frame's births.
	pm.tail_births_on = pm.spark_motes
	if pm.tail_births_on and spark_births.size() < Manager.SPARK_BIRTHS_MAX * Manager.SPARK_BIRTH_STRIDE:
		spark_births.resize(Manager.SPARK_BIRTHS_MAX * Manager.SPARK_BIRTH_STRIDE)
	_plan_groups()
	if kernel_draw:
		_kernel.call(&"draw_shots", pm, fraction)
	else:
		_draw_shots(fraction)
	_job_batches._hand_merges(kernel_draw)
	pm.spark_birth_count = _draw_out[Manager.DRAW_BIRTHS]
	pm.tail_demand = _draw_out[Manager.DRAW_TAIL] + int(pm._end_wanted)
	if pm.tail_births_on:
		_lay_ends()
	pm._end_count = 0
	pm._end_wanted = 0.0
	pm.tail_births = pm.spark_birth_count
	# In a biome each batch's shots are drawn by the room they are in (`_draw_regions`); the batch's
	# own node draws none of them then, and its light and still views take them whole as before.
	var by_room: bool = _draw_regions.fit(_room_grid)
	for batch in pm._batch_total:
		var out: int = _draw_out[Manager.DRAW_OUT_FIRST + batch]
		var multimesh: MultiMesh = _nodes[batch].multimesh
		var mirror: MultiMesh = _mirrors[batch] if batch < _mirrors.size() else null
		if mirror != null and mirror.instance_count != multimesh.instance_count:
			mirror.instance_count = multimesh.instance_count
		var rows: PackedFloat32Array = _no_rows
		if out > 0:
			rows = _kernel.call(&"buffer", batch) if kernel_draw else _buffers[batch]
			if not by_room:
				multimesh.buffer = rows
			if mirror != null:
				mirror.buffer = rows
			if batch < _still_views.size() and _still_views[batch] != null:
				var view: StillShotView = _still_views[batch]
				view.open(rows, out, pm.sim_time)
				pm.still_shots_drawn.emit(view)
				view.close()
		if by_room:
			_draw_regions.draw(batch, _nodes[batch], rows, out, _kernel)
		multimesh.visible_instance_count = 0 if by_room else out
		if mirror != null:
			mirror.visible_instance_count = out
		if pm.light_rows_wanted:
			if _light_rows.size() < pm._batch_total:
				_light_rows.resize(pm._batch_total)
				_light_counts.resize(pm._batch_total)
			_light_rows[batch] = rows
			_light_counts[batch] = out
	var shots_out: int = _draw_out[Manager.DRAW_SHOTS]
	pm.drawn_enemy = _draw_out[Manager.DRAW_ENEMY]
	pm.drawn = shots_out
	_share_pool(_draw_out[Manager.DRAW_ASKED])
	_share_groups()
	_give_off_sparks(fraction)


## Hand out the particles the drawn shots give off since the last frame, as
## births (`spark_births`; see SPARK_BIRTH_STRIDE), while something takes them. The shader's rule, rolled on the
## CPU: at each moment (SPARK_MOMENTS a second) a flying shot gives off one of its kinds, picked at
## random, at that kind's rate (SPARK_RATES) times its group's share of the pool (GROUPS). Rolled
## per birth, not per shot: for each group, a random one of its drawn shots at each of its shots x
## its share tries a moment, kept at the kind's rate, so the work follows the births (the shares
## bound them), not the shots.
func _give_off_sparks(fraction: float) -> void:
	var moment: int = floori((pm.sim_time - (1.0 - fraction) * pm._last_delta) * Manager.SPARK_MOMENTS)
	var moments: int = clampi(moment - pm._spark_moment, 0, 4) if pm._spark_moment >= 0 else 1
	pm._spark_moment = moment
	if not pm.spark_motes or moments == 0:
		return
	if spark_births.size() < Manager.SPARK_BIRTHS_MAX * Manager.SPARK_BIRTH_STRIDE:
		spark_births.resize(Manager.SPARK_BIRTHS_MAX * Manager.SPARK_BIRTH_STRIDE)
	if pm._high == 0:
		return
	var tries_left: int = Manager.SPARK_BIRTHS_MAX * 4
	# The steps the frame's moments cover.
	var span: float = float(moments) / Manager.SPARK_MOMENTS / maxf(pm._last_delta, 0.0001)
	for i in pm._group_live:
		var group: int = _groups[i]
		var first: int = _group_start[group]
		var shots: int = _group_end[group] - first
		if shots == 0:
			continue
		var tries: int = mini(floori(float(shots * moments) * _group_share[group] + pm._spark_rng.randf()), tries_left)
		tries_left -= tries
		for n in tries:
			if not _give_off_spark(_by_group[first + pm._spark_rng.randi_range(0, shots - 1)], fraction, span):
				return


## One try of `_give_off_sparks` on the drawn shot in `slot`: a birth of one of its kinds, kept at
## that kind's rate. Returns false once the frame's SPARK_BIRTHS_MAX are taken.
func _give_off_spark(slot: int, fraction: float, span: float) -> bool:
	if _alive[slot] == 0 or (_flags[slot] & Manager.F_QUAD) != 0:
		return true
	var bits: int = _look[slot] & Manager.EMITTING_MASK
	var kind: int = 0
	if bits != 0:
		kind = _nth_bit(bits, pm._spark_rng.randi_range(0, _bit_count(bits) - 1)) + 1
	if pm._spark_rng.randf() >= Manager.SPARK_RATES[kind]:
		return true
	# Anywhere on the path it was drawn along since the last frame (the moments since then, back
	# from where it is drawn now): a frame's births never gather in one part of each step, so a
	# held stream of shots does not line them up (the owner, 2026-11-05).
	var step: Vector2 = _pos[slot] - _prev[slot]
	var at: Vector2 = _prev[slot] + step * (fraction - pm._spark_rng.randf() * span)
	var back: Vector2 = -step
	if _motion[slot] == Manager.MOTION_ORBIT:
		at = _job_moves._drawn_at(slot, at)
		back = -_vel[slot]
	return _add_birth(at, back.normalized(), kind, _ramp[slot], _look[slot], _core[slot], _tag[slot])


## One birth (SPARK_BIRTH_STRIDE floats; see there): a particle of look kind `kind` at `at`, given
## off back along `back`, from a shot of the caster's `ramp`, the look `look` and the core colour
## `core`, of the spell tagged `tag` (S2). Returns false once the frame's SPARK_BIRTHS_MAX are taken.
func _add_birth(at: Vector2, back: Vector2, kind: int, ramp: int, look: int, core: Color, tag: int) -> bool:
	_put_birth(spark_births, pm.spark_birth_count, at, back, kind, ramp, look, core, tag)
	pm.spark_birth_count += 1
	return pm.spark_birth_count < Manager.SPARK_BIRTHS_MAX


## Write a birth (see `_add_birth`) as birth `n` of `births`.
static func _put_birth(births: PackedFloat32Array, n: int, at: Vector2, back: Vector2, kind: int, ramp: int, look: int, core: Color, tag: int) -> void:
	var i: int = n * Manager.SPARK_BIRTH_STRIDE
	births[i + Manager.SPARK_X] = at.x
	births[i + Manager.SPARK_Y] = at.y
	births[i + Manager.SPARK_BACK_X] = back.x
	births[i + Manager.SPARK_BACK_Y] = back.y
	births[i + Manager.SPARK_KIND] = float(kind)
	births[i + Manager.SPARK_RAMP] = Manager.birth_ramp(ramp, look)
	births[i + Manager.SPARK_LOOK] = Manager.birth_look(look)
	births[i + Manager.SPARK_CORE] = core.r
	births[i + Manager.SPARK_CORE + 1] = core.g
	births[i + Manager.SPARK_CORE + 2] = core.b
	births[i + Manager.SPARK_TAG] = float(tag & ((1 << Manager.SPARK_TAG_BITS) - 1))
	births[i + Manager.SPARK_TAG + 1] = float(tag >> Manager.SPARK_TAG_BITS)


static func _bit_count(bits: int) -> int:
	var n: int = 0
	while bits != 0:
		bits &= bits - 1
		n += 1
	return n


## The place of the `n`-th set bit of `bits` (0 the lowest).
static func _nth_bit(bits: int, n: int) -> int:
	var at: int = 0
	while bits != 0:
		if bits & 1 == 1:
			if n == 0:
				return at
			n -= 1
		bits >>= 1
		at += 1
	return 0


## `update_draw`'s writing (what `ShotKernel.draw_shots` does natively): every live shot into the
## manager's batch buffers at `fraction` of the last step; `_draw_out` gets the instances written per
## batch (BATCH_*), the particles asked for, 0 (was the trails' cost), the shots drawn, the enemy
## shots drawn, the tail births laid and the tail asked for. `_count_batches` brought each shot's drawn data up to date.
func _draw_shots(fraction: float) -> void:
	for batch in pm._batch_total:
		_draw_out[Manager.DRAW_OUT_FIRST + batch] = 0
	pm._tail_wanted = 0.0
	pm._tail_thin = 0
	var asked: int = 0
	for slot in pm._high:
		if _alive[slot] == 0:
			continue
		var motion: int = _motion[slot]
		var at: Vector2 = _prev[slot].lerp(_pos[slot], fraction)
		if motion == Manager.MOTION_ORBIT:
			at = _job_moves._drawn_at(slot, at)
		var batch: int = _drawn_batch[slot]
		var look_data: Color = _drawn_color[slot]
		asked += _drawn_particles[slot]
		var group: int = _group[slot]
		_group_ask[group] += float(maxi(_drawn_particles[slot], 1))
		_by_group[_group_end[group]] = slot
		_group_end[group] += 1
		if (_flags[slot] & Manager.F_QUAD) != 0:
			# Only a rune's quad turns with the shot (a bolt's head is a `+` whatever way it flies).
			var dir: Vector2 = Vector2.RIGHT
			if _facing[slot].length_squared() > 0.0:
				dir = _facing[slot]
			elif _vel[slot].length_squared() > 0.0:
				dir = _vel[slot].normalized()
			_draw_out[Manager.DRAW_OUT_FIRST + batch] = _write_stones(_buffers[batch], _draw_out[Manager.DRAW_OUT_FIRST + batch], slot, dir, _drawn_size[slot], at, look_data)
			continue
		var flags: int = Manager.HEAD_LIVE
		var row: int = _draw_out[Manager.DRAW_OUT_FIRST + batch] * Manager.DRAW_STRIDE
		var buffer: PackedFloat32Array = _buffers[batch]
		_write_head(buffer, row, at, flags, look_data, _core[slot], _pos[slot] - _prev[slot])
		# Its light multipliers in the row's free floats (written inline: a call per shot costs).
		buffer[row + Manager.LIGHT_REACH_FLOAT] = _look_light_reach[slot]
		buffer[row + Manager.LIGHT_INTENSITY_FLOAT] = _look_light_intensity[slot]
		_draw_out[Manager.DRAW_OUT_FIRST + batch] += 1
		if pm.tail_births_on:
			_lay_tail(slot, at)
	var shots: int = 0
	var enemy_shots: int = 0
	for batch in pm._batch_total:
		shots += _draw_out[Manager.DRAW_OUT_FIRST + batch]
		if Manager.batch_on_enemy_layer(batch):
			enemy_shots += _draw_out[Manager.DRAW_OUT_FIRST + batch]
	_draw_out[Manager.DRAW_SHOTS] = shots
	_draw_out[Manager.DRAW_ENEMY] = enemy_shots
	_draw_out[Manager.DRAW_ASKED] = asked
	_draw_out[Manager.DRAW_ASKED + 1] = 0
	_draw_out[Manager.DRAW_BIRTHS] = pm.spark_birth_count
	_draw_out[Manager.DRAW_TAIL] = int(pm._tail_wanted)


## Lay the tail of the shot in `slot`, drawn at `at` this frame, as births (SPARK_TAIL; what
## `ShotKernel.draw_shots` does natively, to the bit): along the path from where it was drawn last
## frame, one at its next tail point and every spacing of its group (`_group_spacing`) x 0.5 to 1.5 pixels on from there
## (`tail_hash` of its sequence and its count), while the frame's most lasts (`tail_births_cap`,
## and `tail_thin_most` for a thinned group's; see TAIL_FRESH). A jump
## longer than TAIL_JUMP (a teleport) lays none. An infused shot gives TAIL_PLAYER_SHARE of its
## tail its caster's colours (a white core, so the motes take its hat ramp).
func _lay_tail(slot: int, at: Vector2) -> void:
	var from: Vector2 = _tail_from[slot]
	_tail_from[slot] = at
	pm._tail_wanted += _lay_path(slot, from, at, false)


## The last stretch of the tail of the shot in `slot`, which ends in flight at `to` (a hit, a wall,
## its life run out, a block): from where it was drawn last to where it ended, which no frame draws
## it along (the owner, 2026-11-06: an Atom fired at a target close by left its tail a step or two
## short, the gap between its last drawn point and the hit). Laid now, while its slot is still its
## own, into `_end_births`; the next frame lays them after the drawn shots' tails (`_lay_ends`).
## A rune (a still body, circling or not) lays no tail, and an orbit shot ends where it would have
## been drawn.
func _end_tail(slot: int, to: Vector2) -> void:
	if not pm.tail_births_on or (_flags[slot] & Manager.F_QUAD) != 0:
		return
	if _motion[slot] == Manager.MOTION_ORBIT:
		to = _job_moves._drawn_at(slot, to)
	if _end_births.size() < pm.tail_births_cap * Manager.SPARK_BIRTH_STRIDE:
		_end_births.resize(pm.tail_births_cap * Manager.SPARK_BIRTH_STRIDE)
	pm._end_wanted += _lay_path(slot, _tail_from[slot], to, true)


## Lay the tail of the shot in `slot` along the path from `from` to `at` (see `_lay_tail`), from its
## next tail point; `ending`: the last stretch of a shot that ended (`_end_tail`), into
## `_end_births`, else into the frame's births. Returns the tail it asked for (births at
## TAIL_SPACING); none across a jump.
func _lay_path(slot: int, from: Vector2, at: Vector2, ending: bool) -> float:
	var way: Vector2 = at - from
	var d: float = way.length()
	if not (d > 0.0) or d > Manager.TAIL_JUMP:
		return 0.0
	var group: int = _group[slot]
	_group_tail[group] += d / Manager.TAIL_SPACING
	var spacing: float = _group_spacing[group]
	var thinned: bool = spacing > Manager.TAIL_SPACING
	var carry: float = _tail_carry[slot]
	var n: int = _tail_n[slot]
	var seq: int = _seq[slot]
	var core: Color = _core[slot]
	var mixed: bool = not (core.r > 0.99 and core.g > 0.99 and core.b > 0.99)
	var back: Vector2 = way / -d
	var code: int = Manager.tail_code(seq)
	while carry < d:
		if ending:
			if pm._end_count >= pm.tail_births_cap:
				carry = d
				break
		elif pm.spark_birth_count >= pm.tail_births_cap or (thinned and pm._tail_thin >= pm.tail_thin_most):
			carry = d
			break
		var colour: Color = core
		if mixed and tail_hash(seq, n * 2) < Manager.TAIL_PLAYER_SHARE:
			colour = Color.WHITE
		if ending:
			_put_birth(_end_births, pm._end_count, from.lerp(at, carry / d), back, code, _ramp[slot], _look[slot], colour, _tag[slot])
			pm._end_count += 1
		else:
			_add_birth(from.lerp(at, carry / d), back, code, _ramp[slot], _look[slot], colour, _tag[slot])
			pm._tail_thin += 1 if thinned else 0
		carry += spacing * (0.5 + tail_hash(seq, n * 2 + 1))
		n += 1
	_tail_carry[slot] = carry - d
	_tail_n[slot] = n
	return d / Manager.TAIL_SPACING


## After the drawn shots' tails: the ended shots' last stretches (`_end_tail`), while the frame's
## most lasts (`tail_births_cap`; they come last, so they never cut a flying shot's tail).
func _lay_ends() -> void:
	var take: int = clampi(pm.tail_births_cap - pm.spark_birth_count, 0, pm._end_count)
	if take > 0:
		var into: int = pm.spark_birth_count * Manager.SPARK_BIRTH_STRIDE
		for i in take * Manager.SPARK_BIRTH_STRIDE:
			spark_births[into + i] = _end_births[i]
		pm.spark_birth_count += take
	pm._end_count = 0
	pm._end_wanted = 0.0


## A number from 0 up to 1 for the pair (`a`, `b`), the same every time (and in the native
## kernel): the tails' dice (`_lay_tail`).
static func tail_hash(a: int, b: int) -> float:
	# Every product stays below 2^63, so GDScript's ints and the kernel's agree.
	var h: int = ((a & 0xFFFFFFFF) * 374761393 + (b & 0xFFFFFFFF) * 668265263) & 0xFFFFFFFF
	h = ((h ^ (h >> 16)) * 0x45D9F3B) & 0xFFFFFFFF
	h = ((h ^ (h >> 16)) * 0x45D9F3B) & 0xFFFFFFFF
	h = h ^ (h >> 16)
	return float(h & 0xFFFFFF) / 16777216.0


## The shot in `slot` joins `group` (see GROUPS).
func _join_group(slot: int, group: int) -> void:
	_group[slot] = group
	if _group_count[group] == 0:
		_group_at[group] = pm._group_live
		_groups[pm._group_live] = group
		pm._group_live += 1
	_group_count[group] += 1


## The shot in `slot` leaves its group; a group with no shots left leaves the live ones.
func _leave_group(slot: int) -> void:
	var group: int = _group[slot]
	_group_count[group] -= 1
	if _group_count[group] == 0:
		var at: int = _group_at[group]
		pm._group_live -= 1
		var last: int = _groups[pm._group_live]
		_groups[at] = last
		_group_at[last] = at


## Before the drawing: place each live group's shots in `_by_group` (the drawing fills them in) and
## share the frame's tail births out among the groups (see GROUPS). A group's ask is the tail it
## asked for last frame, scaled by its shots now against then (a Storm that split since asks for
## that much more); a group new since the last frame asks for nothing yet, so a new cast's tail is
## whole from its first frame. The fair level shares TAIL_FRESH less than the most; a group's
## spacing is TAIL_SPACING, wider by its ask over the level, and the thinned groups lay at most
## the level each (`tail_thin_most`).
func _plan_groups() -> void:
	pm._draw_frame += 1
	if _group_sort.size() != pm._group_live:
		_group_sort.resize(pm._group_live)
	var at: int = 0
	for i in pm._group_live:
		var group: int = _groups[i]
		var count: int = _group_count[group]
		_group_start[group] = at
		_group_end[group] = at
		at += count
		var want: float = 0.0
		if _group_frame[group] == pm._draw_frame - 1 and _group_seen[group] > 0:
			want = _group_tail[group] * float(count) / float(_group_seen[group])
		_group_want[group] = want
		_group_sort[i] = want
		_group_frame[group] = pm._draw_frame
		_group_seen[group] = count
		_group_tail[group] = 0.0
		_group_ask[group] = 0.0
	_group_sort.sort()
	var level: float = maxf(Manager.fair_level(_group_sort, float(pm.tail_births_cap) * (1.0 - Manager.TAIL_FRESH)), 0.0001)
	var thin: float = 0.0
	pm.tail_spacing = Manager.TAIL_SPACING
	for i in pm._group_live:
		var group: int = _groups[i]
		_group_spacing[group] = Manager.TAIL_SPACING * maxf(1.0, _group_want[group] / level)
		pm.tail_spacing = maxf(pm.tail_spacing, _group_spacing[group])
		if _group_spacing[group] > Manager.TAIL_SPACING:
			thin += level
	pm.tail_thin_most = ceili(thin)


## After the drawing: each group's share of the particles it asked for (`_group_share`, for
## `_give_off_sparks`): the pool's count shared out fairly among the groups (see GROUPS).
func _share_groups() -> void:
	for i in pm._group_live:
		_group_sort[i] = _group_ask[_groups[i]]
	_group_sort.sort()
	var level: float = Manager.fair_level(_group_sort, float(maxi(pm.tailless_particle_cap, 0)))
	for i in pm._group_live:
		var group: int = _groups[i]
		var ask: float = _group_ask[group]
		_group_share[group] = 1.0 if ask <= level else level / ask


## Write the rune quad of the still shot in `slot` drawn at `at` into `buffer` from instance
## `out` on, one for each stone of a solid shot's row; returns the instance after the last. A solid
## shot's quads turn along its row (`Solid.across`), so its card's shader knows which way the row
## runs (the wall's seam; its shader draws upright whichever way its quad turns).
func _write_stones(buffer: PackedFloat32Array, out: int, slot: int, dir: Vector2, size: float, at: Vector2, look_data: Color) -> int:
	var stones: int = 1
	var step: Vector2 = Vector2.ZERO
	if pm._any_solid and _solids.has(slot):
		var solid: Manager.Solid = _solids[slot]
		dir = solid.across
		stones = solid.stones
		step = solid.across * solid.gap * _radius[slot]
		at -= _job_walls._solid_half(slot, solid)
	var code: float = still_code(pm.sim_time - _born[slot], _life[slot])
	var kind: int = pm._kind_of(slot)
	var light_reach: float = _look_light_reach[slot]
	var light_intensity: float = _look_light_intensity[slot]
	# A batch holds the cap at most: stones past it are not drawn.
	for n in mini(stones, buffer.size() / Manager.DRAW_STRIDE - out):
		var i: int = out * Manager.DRAW_STRIDE
		_write_quad(buffer, i, dir, size, at + step * n, look_data, _core[slot], kind, 0.0, code)
		# Its light multipliers in the row's free floats (written inline: a call per shot costs).
		buffer[i + Manager.LIGHT_REACH_FLOAT] = light_reach
		buffer[i + Manager.LIGHT_INTENSITY_FLOAT] = light_intensity
		out += 1
	return out


## Work out what `update_draw` keeps for the shot in `slot` (see `_drawn_seq`).
func _remember_drawn(slot: int) -> void:
	_drawn_seq[slot] = _seq[slot]
	_drawn_radius[slot] = _radius[slot]
	_drawn_look[slot] = _look[slot]
	_drawn_batch[slot] = _batch_of(slot)
	_drawn_color[slot] = pm._look_color(slot)
	_drawn_size[slot] = Manager.look_size(_radius[slot])
	_drawn_particles[slot] = particles_of(_look[slot])


## Share the spark pool out for a frame that asked for `asked` particles (see
## TAILLESS_PARTICLE_CAP): past the pool's count every shot's births thin alike.
func _share_pool(asked: int) -> void:
	pm.particle_demand = asked
	var cap: float = float(maxi(pm.tailless_particle_cap, 0))
	pm.particle_share = 1.0 if asked <= 0 else minf(1.0, cap / float(asked))
	for node in _nodes:
		_set_shares(node)


func _set_shares(node: MultiMeshInstance2D) -> void:
	var material: ShaderMaterial = node.material as ShaderMaterial
	material.set_shader_parameter(&"particle_share", pm.particle_share)


## How many particles the pool is asked for by a shot with the packed `look`: 4 + 2 per
## emitting kind (every kind but the weave, which changes the body), at most 12; none for a
## plain shot. The shot shaders that give particles off (`shot_still.gdshader`, `shot_orbit.gdshader`
## and every card's own shot shader) hold the same rule; keep them equal.
static func particles_of(look: int) -> int:
	if look == 0:
		return 0
	var bits: int = look & Manager.EMITTING_MASK
	var kinds: int = 0
	while bits != 0:
		bits &= bits - 1
		kinds += 1
	if kinds == 0:
		return 0
	return mini(4 + 2 * kinds, Manager.PARTICLES_PER_SHOT_MAX)


## Which draw batch a live slot belongs to (BATCH_*), by its ramp and body. The one rule both the counting and the writing use, so a batch
## always has the room its writes need.
func _batch_of(slot: int) -> int:
	# A card body draws its shot only while the shot's motion is written as the body's mesh; a shot
	# whose motion changed past it (or a card's shader numbered for the other mesh) draws plain.
	var body: int = _body[slot]
	var quad: bool = (_flags[slot] & Manager.F_QUAD) != 0
	if body > 0 and _body_meshes[body - 1] == (Manager.MESH_QUAD if quad else Manager.MESH_HEAD):
		return Manager.body_batch(body, not Manager.is_hat_ramp(_ramp[slot]))
	if not Manager.is_hat_ramp(_ramp[slot]):
		return Manager.BATCH_ENEMY_STILL if quad else Manager.BATCH_ENEMY
	return Manager.BATCH_STILL if quad else Manager.BATCH_BOLT


## Count the live shots each batch will draw into _batch_counts, indexed by BATCH_*, and bring
## each live shot's drawn data up to date (`_drawn_seq`). One extra pass over the live slots: the
## price of sizing before writing.
func _count_batches() -> void:
	_batch_counts.fill(0)
	for slot in pm._high:
		if _alive[slot] != 0:
			if _drawn_seq[slot] != _seq[slot] or _drawn_radius[slot] != _radius[slot] or _drawn_look[slot] != _look[slot]:
				_remember_drawn(slot)
			# A solid shot draws a quad for every stone of its row.
			_batch_counts[_drawn_batch[slot]] += 1 if not pm._any_solid or not _solids.has(slot) else (_solids[slot] as Manager.Solid).stones


## Size a batch's MultiMesh and buffer to draw `used` shots; returns the new room.
## The room stays while `used` fits and is more than a quarter of it, else it becomes
## `used` rounded up to a power of two (at least MIN_BATCH, at most the cap). An empty
## batch keeps its room: nothing is uploaded for it, and it does not reallocate when it
## flickers between empty and busy. The MultiMesh buffer must be exactly instance_count
## x DRAW_STRIDE floats, so a smaller upload means a smaller MultiMesh. The buffer is
## shared, not copied, so resizing it here resizes the caller's.
func _fit_batch(multimesh: MultiMesh, buffer: PackedFloat32Array, room: int, used: int, limit: int = -1) -> int:
	if used == 0 or (used <= room and used * 4 > room):
		return room
	var wanted: int = Manager.MIN_BATCH
	while wanted < used:
		wanted *= 2
	wanted = mini(wanted, pm._cap if limit < 0 else limit)
	if wanted != room:
		multimesh.instance_count = wanted
		buffer.resize(wanted * Manager.DRAW_STRIDE)
	return wanted


## The code of a still shot `age` seconds old with `left` seconds of life (see STILL_START): how far
## through its start it is, or (negative) how far through its end, 0 between. Its end is told once
## it has less life left than it has lived, so a short life is half coming and half going. A time
## out of order (a negative age) is 0.
static func still_code(age: float, left: float) -> float:
	if age < 0.0:
		return 0.0
	if left < Manager.STILL_END and left < age:
		return -(Manager.TRACE_FROM + Manager.TRACE_SPAN * (1.0 - maxf(left, 0.0) / Manager.STILL_END))
	if age < Manager.STILL_START:
		return Manager.TRACE_FROM + Manager.TRACE_SPAN * age / Manager.STILL_START
	return 0.0


## Write one quad at float index `i` of `buffer` (packed arrays are shared, not copied):
## Transform2D(dir * length, dir.orthogonal() * d, centre), row by row, then the colour and the
## colour of the core (custom data). A square quad (`length` 0) is centred on `at`; a long one
## reaches `diameter` / 2 ahead of `at` and the rest behind it (a bolt and its tail).
## `kind` (0 the texture, KIND_BOLT, KIND_RUNE or KIND_ORBIT; at most KIND_MAX) and `code`
## (above -0.5 and below 0.5: a bend, `bend_code`, or a still shot's clock, `still_code`) go in the alpha of the
## custom data as 1 - (kind + code) / 16, which the shot shaders read back.
func _write_quad(buffer: PackedFloat32Array, i: int, dir: Vector2, diameter: float, at: Vector2, color: Color, core: Color, kind: int, length: float = 0.0, code: float = 0.0) -> void:
	assert(kind >= 0 and kind <= Manager.KIND_MAX, "the kind must fit the alpha encoding")
	assert(code > -0.5 and code < 0.5, "the code must round away from the kind")
	var along: float = diameter
	var centre: Vector2 = at
	if length > 0.0:
		along = length
		centre = at - dir * (length - diameter) * 0.5
	buffer[i] = dir.x * along
	buffer[i + 1] = dir.y * diameter
	buffer[i + 2] = 0.0
	buffer[i + 3] = centre.x
	buffer[i + 4] = dir.y * along
	buffer[i + 5] = -dir.x * diameter
	buffer[i + 6] = 0.0
	buffer[i + 7] = centre.y
	buffer[i + 8] = color.r
	buffer[i + 9] = color.g
	buffer[i + 10] = color.b
	buffer[i + 11] = color.a
	buffer[i + 12] = core.r
	buffer[i + 13] = core.g
	buffer[i + 14] = core.b
	buffer[i + 15] = 1.0 - (kind + code) / Manager.KIND_STEPS


## Write a live shot's instance at float index `i` of `buffer`: its data in the transform, which
## `shot_head.gdshader` reads back (its quads are placed from it; the batch sits untransformed at
## the origin): the head `at`, no path (-1: a tail is motes), the way it flies `way`, its flags, the
## colour and the core.
func _write_head(buffer: PackedFloat32Array, i: int, at: Vector2, flags: int, color: Color, core: Color, way: Vector2) -> void:
	buffer[i] = -1.0
	buffer[i + 1] = way.x
	buffer[i + 2] = 0.0
	buffer[i + 3] = at.x
	buffer[i + 4] = way.y
	buffer[i + 5] = float(flags)
	buffer[i + 6] = 0.0
	buffer[i + 7] = at.y
	buffer[i + 8] = color.r
	buffer[i + 9] = color.g
	buffer[i + 10] = color.b
	buffer[i + 11] = color.a
	buffer[i + 12] = core.r
	buffer[i + 13] = core.g
	buffer[i + 14] = core.b
	buffer[i + 15] = 1.0 - float(Manager.KIND_BOLT) / Manager.KIND_STEPS
