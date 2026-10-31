class_name CarrierBeam
extends Carrier
## A line held by its caster that hits at once and every `SpellLimits.BEAM_TICK` (`&"beam"`:
## the beam). It runs most shot cards its own way: it bends to a target, turns at walls, waves,
## widens, pulls and guards along its line.
##
## Its rows: the live beams, which it keeps itself (`bind` makes them), starts (`start`, from
## `shoot`), runs (`step`) and ends (`end_of`, `end_actor`). Its hits go through the runtime as rays
## (`Spells._ray_begin`), so its cards, payloads and chains work as a shot's do; its looks read the
## `beam_*` getters (`CarrierBeam.of(spells)`).


## Points a live beam row has room for at first: its start, RAY_SEGMENTS a leg for each target it
## bends to and a straight end (`_beam_path`), or the path its ray walked with a point at every
## turn at a wall (`_beam_keep_path`). The rows grow when one needs more (`_fit_beam_points`).
const BEAM_POINTS_START: int = SpellLimits.BEAM_LEGS_START * SpellRuntime.ProjectilesScript.RAY_SEGMENTS + 2
## The live beams (see `start`), rows that double when every one is on (`_grow_beams`);
## `_bm_on` says which are in use. Each keeps what a shot's record keeps (fires, chain) plus where it is: its origin,
## way, the curve's pull and end, how far it got and where (its tip), and its caster.
var _bm_on: PackedByteArray = PackedByteArray()
var _bm_born: PackedInt64Array = PackedInt64Array()
var _bm_next_born: int = 0
var _bm_spell: Array[CompiledSpell] = []
var _bm_source: Array[Node] = []
var _bm_tag: PackedInt64Array = PackedInt64Array()
var _bm_actor: PackedInt32Array = PackedInt32Array()
var _bm_caster: PackedInt32Array = PackedInt32Array()
var _bm_caster_seq: PackedInt64Array = PackedInt64Array()
var _bm_life: PackedFloat32Array = PackedFloat32Array()
var _bm_span: PackedFloat32Array = PackedFloat32Array()
var _bm_tick: PackedFloat32Array = PackedFloat32Array()
## The homing of each leg of each live beam (`_bm_legs` a row): the target it keeps.
var _bm_homing: Array[Homing] = []
var _bm_legs: int = SpellLimits.BEAM_LEGS_START
## Each live beam's path, `_bm_stride` points a row (see `_beam_path`), and how many it uses.
var _bm_points: PackedVector2Array = PackedVector2Array()
var _bm_stride: int = BEAM_POINTS_START
## For `_beam_steer`: the beam being walked, where its legs' targets are in its path (made by
## `_beam_path`, the reached ones kept at each turn), the points it hands back, and the Callable
## made once.
var _steer_row: int = -1
var _steer_goals: PackedInt32Array = PackedInt32Array()
var _steer_goal_count: int = 0
var _steer_points: PackedVector2Array = PackedVector2Array()
var _steer_call: Callable = _beam_steer
## The scratch of `_wave` (a spiral beam's path).
var _wave_points: PackedVector2Array = PackedVector2Array()
var _wave_index: PackedInt32Array = PackedInt32Array()
var _bm_count: PackedInt32Array = PackedInt32Array()
var _bm_turn: PackedFloat32Array = PackedFloat32Array()
var _bm_chain: PackedInt32Array = PackedInt32Array()
var _bm_prev: PackedInt64Array = PackedInt64Array()
## What live beam `at` hits with when not its spell's own `hit` (null): an echo's half, and what
## `relay` took on while it is on (`_relay`).
var _bm_hit: Array[HitProfile] = []
## Shield charges live beam `at` has left for shots it touches (melee I3, `CarrierKit.guard_path`).
var _bm_shield: PackedInt32Array = PackedInt32Array()
var _bm_origin: PackedVector2Array = PackedVector2Array()
var _bm_dir: PackedVector2Array = PackedVector2Array()
var _bm_bend: PackedVector2Array = PackedVector2Array()
var _bm_end: PackedVector2Array = PackedVector2Array()
var _bm_reach: PackedFloat32Array = PackedFloat32Array()
var _bm_tip: PackedVector2Array = PackedVector2Array()
var _bm_tip_dir: PackedVector2Array = PackedVector2Array()
var _bm_hit_at: PackedFloat32Array = PackedFloat32Array()
## A live beam's `zap` (rules as a shot's, `Spells._step_zaps`): what its zaps hit with when not
## its spell's `zap_hit` (null: an echo's, or its relay's), how many random numbers it has drawn
## (`SpellRuntime.zap_hash` of its birth and that count), the bodies it has rolled for and when
## each was zapped or lost its roll (`SpellRuntime.ZAP_MEMORY` a row, `_bm_zapped_count` of them) and the won zaps it keeps waiting
## (`SpellRuntime.ZAP_DUE` a row, `_bm_due_count` of them: the body and the moment it is zapped).
var _bm_zap_hit: Array[HitProfile] = []
var _bm_zap_rolls: PackedInt32Array = PackedInt32Array()
var _bm_zapped: PackedInt64Array = PackedInt64Array()
var _bm_zapped_at: PackedFloat64Array = PackedFloat64Array()
var _bm_zapped_count: PackedInt32Array = PackedInt32Array()
var _bm_due_body: Array[Node2D] = []
var _bm_due_at: PackedFloat64Array = PackedFloat64Array()
var _bm_due_count: PackedInt32Array = PackedInt32Array()
## Steps run (which half of the zap beams looks this step, SpellLimits.ZAP_EVERY), and the bodies in
## a beam's zap reach, their hit circles and sizes (reused, `Projectiles.targets_near`).
var _zap_steps: int = 0
var _zap_near: Array[Node2D] = []
var _zap_centres: PackedVector2Array = PackedVector2Array()
var _zap_radii: PackedFloat32Array = PackedFloat32Array()


func id() -> StringName:
	return &"beam"



## The beams of the runtime `spells` (its bound `beam` carrier, `Spells.carrier`), for what reads
## its own getters (the looks, `ai`, the actor's mover, the tests).
static func of(spells: SpellRuntime) -> CarrierBeam:
	return spells.carrier(&"beam") as CarrierBeam


func traits() -> int:
	return HITS | LASTS | REACHES | GUARDS | STEERS | SPEED | SHOTS | SPREAD | PIERCE | INSTANT_HOMING | HOLDS_STAFF | LINE | MEETS_SHOTS


## It dissolves over the last SpellLimits.BEAM_FADE of its life, zapping nothing then.
func fade() -> float:
	return SpellLimits.BEAM_FADE


func step_order() -> int:
	return 2


func required_fields() -> Dictionary:
	return {
		"ray_length": "A beam needs a `ray_length` above 0.",
	}


func hit_kind() -> StringName:
	return &"ray"


## Makes this carrier's rows for `runtime`, which casts it.
func bind(runtime_kit: CarrierKit, staff_poses: StaffPoses) -> void:
	super(runtime_kit, staff_poses)
	var rows: int = SpellLimits.BEAM_ROWS_START
	for column: Variant in [_bm_on, _bm_born, _bm_spell, _bm_source, _bm_tag, _bm_actor, _bm_caster, _bm_caster_seq, _bm_life, _bm_span, _bm_tick, _bm_turn, _bm_count, _bm_chain, _bm_prev, _bm_hit, _bm_shield, _bm_origin, _bm_dir, _bm_bend, _bm_end, _bm_reach, _bm_tip, _bm_tip_dir, _bm_hit_at, _bm_zap_hit, _bm_zap_rolls, _bm_zapped_count, _bm_due_count]:
		column.resize(rows)
	_bm_zapped.resize(rows * SpellRuntime.ZAP_MEMORY)
	_bm_zapped_at.resize(rows * SpellRuntime.ZAP_MEMORY)
	_bm_due_body.resize(rows * SpellRuntime.ZAP_DUE)
	_bm_due_at.resize(rows * SpellRuntime.ZAP_DUE)
	for i in rows * _bm_legs:
		_bm_homing.append(Homing.new())
	_bm_points.resize(rows * _bm_stride)


## Every beam gone at once, quietly (`Spells.clear`).
## The swarm promoted a body (`Carrier.replace_body`): a beam's chain that came from `old` came
## from `new`.
func replace_body(old: Node, new: Node) -> void:
	_replace_in_rows(old, new, [], _bm_prev)


func clear() -> void:
	_bm_on.fill(0)
	_bm_spell.fill(null)
	_bm_source.fill(null)
	_bm_zap_hit.fill(null)
	_bm_due_count.fill(0)
	_bm_due_body.fill(null)


## The beams of `actor` end quietly (its caster closed).
func end_actor(actor: int) -> void:
	for at in _bm_on.size():
		if _bm_on[at] != 0 and _bm_actor[at] == actor:
			_end_beam(at, false)


## Where live beam `at` ends now, while it is the beam born `born` (a live carrier's place, for its
## timer and `on hurt` payloads); INF once it has ended.
func tip_of(at: int, born: int) -> Vector2:
	return _bm_tip[at] if _bm_on[at] != 0 and _bm_born[at] == born else Vector2.INF


## Every live beam with `magnet` pulls toward its line, each step it is on (rules R4f; `step`).
func _pull_magnets() -> void:
	for at in _bm_on.size():
		if _bm_on[at] != 0 and _bm_spell[at].behaviour(ModifierBase.Behaviour.MAGNET) > 0.0:
			_beam_pull(at)


## Every live beam with `zap` (half of them each step, SpellLimits.ZAP_EVERY), as a zap shot does
## (`Spells._step_zaps`, owner, 2026-10-31): each body of another team that comes within the card's
## reach of its line, as far as it got, rolls its chance (again SpellLimits.ZAP_AGAIN after it was
## zapped or lost its roll), and on a win is zapped from the
## nearest point of its line at a random moment while it is in reach (at most
## SpellLimits.ZAP_WAIT_MOST and the time until the beam starts to dissolve, `Carrier.active_left`; a
## beam stands where it is held, so a body stays in reach until it or the beam moves); a waiting zap
## whose body left the reach is made as it leaves. A beam with nothing in reach now and then throws a
## spark off its line. A dissolving beam zaps nothing (owner, 2026-10-31): its waiting zaps are
## dropped.
func _step_zaps(delta: float) -> void:
	_zap_steps += 1
	for at in _bm_on.size():
		if _bm_on[at] == 0 or (at + _zap_steps) % SpellLimits.ZAP_EVERY != 0:
			continue
		var spell: CompiledSpell = _bm_spell[at]
		if spell.zap_chance <= 0.0 or spell.zap_reach <= 0.0 or _bm_count[at] < 1:
			continue
		var left: float = active_left(_bm_life[at], _bm_span[at])
		if left <= 0.0:
			_drop_zaps(at)
			continue
		var near: int = _zap_reach_of(at, spell.zap_reach)
		_zaps_due(at, near)
		if _bm_on[at] == 0 or _bm_spell[at] != spell:
			continue
		if near == 0 and _bm_due_count[at] == 0:
			if kit.zap_room() and _zap_roll(at) < SpellLimits.ZAP_SPARKS * delta * SpellLimits.ZAP_EVERY:
				var from: Vector2 = _point_along(at, _zap_roll(at) * _bm_reach[at])
				var length: float = lerpf(SpellLimits.ZAP_SPARK_SHORTEST, SpellLimits.ZAP_SPARK_LONGEST, _zap_roll(at))
				kit.spark(spell, _bm_tag[at], from, Vector2.from_angle(_zap_roll(at) * TAU), length)
			continue
		for k in near:
			if not kit.zap_room() or _bm_on[at] == 0 or _bm_spell[at] != spell:
				break
			var body: Node2D = _zap_near[k]
			if not is_instance_valid(body) or _has_rolled(at, body.get_instance_id()):
				continue
			if _zap_roll(at) >= spell.zap_chance:
				_rolled(at, body.get_instance_id(), kit.clock())
			else:
				# It waits a random moment of the time it stays in reach, less a look's step; it rolls
				# again ZAP_AGAIN after.
				var window: float = minf(SpellLimits.ZAP_WAIT_MOST, left)
				var wait: float = _zap_roll(at) * maxf(window - delta * SpellLimits.ZAP_EVERY, 0.0)
				_rolled(at, body.get_instance_id(), kit.clock() + wait)
				if wait <= 0.0 or _bm_due_count[at] >= SpellRuntime.ZAP_DUE:
					_zap(at, _zap_centres[k])
				else:
					var n: int = at * SpellRuntime.ZAP_DUE + _bm_due_count[at]
					_bm_due_body[n] = body
					_bm_due_at[n] = kit.clock() + wait
					_bm_due_count[at] += 1


## Live beam `at` drops the zaps it has won but not made.
func _drop_zaps(at: int) -> void:
	for n in _bm_due_count[at]:
		_bm_due_body[at * SpellRuntime.ZAP_DUE + n] = null
	_bm_due_count[at] = 0


## Fills `_zap_near` (with `_zap_centres`, `_zap_radii`) with the bodies of another team than live
## beam `at`'s caster within `reach` of its line, as far as it got; returns how many.
func _zap_reach_of(at: int, reach: float) -> int:
	var team: int = kit.team(SpellTag.caster_of(_bm_tag[at]))
	var base: int = at * _bm_stride
	_zap_near.clear()
	if _bm_count[at] == 1:
		return kit.projectiles.targets_near(_bm_points[base], reach, SpellRuntime.HITS, team, _zap_near, _zap_centres, _zap_radii)
	var walked: float = 0.0
	for n in _bm_count[at] - 1:
		if walked >= _bm_reach[at]:
			break
		var a: Vector2 = _bm_points[base + n]
		var b: Vector2 = _bm_points[base + n + 1]
		var piece: float = a.distance_to(b)
		if walked + piece > _bm_reach[at]:
			b = a.move_toward(b, _bm_reach[at] - walked)
		kit.projectiles.targets_near(a, reach, SpellRuntime.HITS, team, _zap_near, _zap_centres, _zap_radii, b, true)
		walked += piece
	return _zap_near.size()


## Makes the waiting zaps of live beam `at` that are due, or whose body has left its reach (made as
## it leaves); a body gone from the world is dropped. `near` bodies are in reach now (`_zap_near`).
func _zaps_due(at: int, near: int) -> void:
	var spell: CompiledSpell = _bm_spell[at]
	var first: int = at * SpellRuntime.ZAP_DUE
	var n: int = 0
	while n < _bm_due_count[at]:
		if not kit.zap_room() or _bm_on[at] == 0 or _bm_spell[at] != spell:
			return
		var body: Node2D = _bm_due_body[first + n]
		var gone: bool = not is_instance_valid(body)
		var k: int = _zap_near.find(body) if not gone else -1
		if gone or k < 0 or k >= near or kit.clock() >= _bm_due_at[first + n]:
			# Off the list first (the last one fills its place): the zap's hit may end the beam.
			var last: int = first + _bm_due_count[at] - 1
			_bm_due_body[first + n] = _bm_due_body[last]
			_bm_due_at[first + n] = _bm_due_at[last]
			_bm_due_body[last] = null
			_bm_due_count[at] -= 1
			if not gone:
				# In reach: at its hit circle; just out of it: where it stands.
				_zap(at, _zap_centres[k] if k >= 0 and k < near else body.global_position)
			continue
		n += 1


## Live beam `at` zaps the body whose hit circle is at `aim`, from the nearest point of its line.
func _zap(at: int, aim: Vector2) -> void:
	var spell: CompiledSpell = _bm_spell[at]
	var hit: HitProfile = _bm_zap_hit[at] if _bm_zap_hit[at] != null else spell.zap_hit
	kit.zap(spell, _bm_tag[at], _nearest_on_line(at, aim), aim, _bm_chain[at], _bm_prev[at], hit)


## The point of live beam `at`'s line, as far as it got, nearest to `point`.
func _nearest_on_line(at: int, point: Vector2) -> Vector2:
	var base: int = at * _bm_stride
	var best: Vector2 = _bm_points[base]
	var best_sq: float = best.distance_squared_to(point)
	var walked: float = 0.0
	for n in _bm_count[at] - 1:
		if walked >= _bm_reach[at]:
			break
		var a: Vector2 = _bm_points[base + n]
		var b: Vector2 = _bm_points[base + n + 1]
		var piece: float = a.distance_to(b)
		if walked + piece > _bm_reach[at]:
			b = a.move_toward(b, _bm_reach[at] - walked)
		var on: Vector2 = Geometry2D.get_closest_point_to_segment(point, a, b)
		if on.distance_squared_to(point) < best_sq:
			best = on
			best_sq = on.distance_squared_to(point)
		walked += piece
	return best


## The point `distance` pixels along live beam `at`'s line (its end past the last point).
func _point_along(at: int, distance: float) -> Vector2:
	var base: int = at * _bm_stride
	var walked: float = 0.0
	for n in _bm_count[at] - 1:
		var a: Vector2 = _bm_points[base + n]
		var b: Vector2 = _bm_points[base + n + 1]
		var piece: float = a.distance_to(b)
		if walked + piece >= distance:
			return a.move_toward(b, distance - walked)
		walked += piece
	return _bm_points[base + _bm_count[at] - 1]


## True when live beam `at` has rolled for the body of instance id `id` less than
## SpellLimits.ZAP_AGAIN ago (from its zap, or the roll it lost).
func _has_rolled(at: int, id: int) -> bool:
	var first: int = at * SpellRuntime.ZAP_MEMORY
	for n in mini(_bm_zapped_count[at], SpellRuntime.ZAP_MEMORY):
		if _bm_zapped[first + n] == id and kit.clock() - _bm_zapped_at[first + n] < SpellLimits.ZAP_AGAIN:
			return true
	return false


## Live beam `at` has rolled for the body of instance id `id`, which is zapped (or lost its roll) at
## `when` (in a ring: past ZAP_MEMORY the oldest is forgotten).
func _rolled(at: int, id: int, when: float) -> void:
	var n: int = _bm_zapped_count[at]
	_bm_zapped[at * SpellRuntime.ZAP_MEMORY + n % SpellRuntime.ZAP_MEMORY] = id
	_bm_zapped_at[at * SpellRuntime.ZAP_MEMORY + n % SpellRuntime.ZAP_MEMORY] = when
	_bm_zapped_count[at] = n + 1


## A random number in [0, 1) for live beam `at` (`SpellRuntime.zap_hash` of its birth).
func _zap_roll(at: int) -> float:
	var n: int = _bm_zap_rolls[at]
	_bm_zap_rolls[at] = n + 1
	return SpellRuntime.zap_hash(_bm_born[at], n)


## A live beam hits one target once at once and then every `SpellLimits.BEAM_TICK` seconds of its life.
func hits_per_target(lifetime: float) -> int:
	return maxi(ceili(lifetime / SpellLimits.BEAM_TICK - 0.001), 1)


## A live beam (`beam` carrier): it lives its `lifetime` (a `hold` one until it is switched off),
## held by its caster: from the wizard's staff tip along its aim (`set_aim`), from the shot whose
## trigger cast it along that shot's way, or from a fixed point. A homing one bends along a curve
## to the nearest target in front of it. It hits what is on it at once and then every
## `SpellLimits.BEAM_TICK` seconds; between hits it only finds how far it gets, for its look.
## Its `blast` and `on expire` payload happen where it ends when its life is over. Returns false
## when it could not start (no direction). `caster` and `caster_seq` are who casts it (`Spells._caster`:
## the wizard, a point or a shot), `echoed` whether it is an echo's firing (half damage).
func start(spell: CompiledSpell, tag: int, actor: int, origin: Vector2, heading: Vector2, chain: int, prev: int, source: Node, lifetime: float, caster: int, caster_seq: int, echoed: bool) -> bool:
	if not heading.is_finite() or heading.is_zero_approx() or not origin.is_finite():
		return false
	# A free row, or new rows when every one is on: no beam ends another.
	var at: int = _bm_on.find(0)
	if at < 0:
		at = _bm_on.size()
		_grow_beams()
	_bm_on[at] = 1
	_bm_born[at] = _bm_next_born
	_bm_next_born += 1
	_bm_spell[at] = spell
	_bm_source[at] = source
	_bm_tag[at] = tag
	_bm_actor[at] = actor
	_bm_life[at] = lifetime
	_bm_span[at] = lifetime
	_bm_tick[at] = 0.0
	_bm_chain[at] = chain
	_bm_prev[at] = prev
	_bm_hit[at] = spell.echo_hit if echoed else null
	_bm_zap_hit[at] = spell.echo_zap_hit if echoed else null
	_bm_zap_rolls[at] = 0
	_bm_zapped_count[at] = 0
	_bm_due_count[at] = 0
	_bm_shield[at] = roundi(spell.behaviour(ModifierBase.Behaviour.SHIELD))
	_bm_origin[at] = origin
	_bm_dir[at] = heading.normalized()
	_bm_reach[at] = 0.0
	_bm_hit_at[at] = kit.clock()
	# How far off its caster's way the beam points (a fan, a multicast or a mirror keeps it).
	_bm_caster[at] = caster
	_bm_caster_seq[at] = caster_seq
	_bm_turn[at] = 0.0
	var legs: int = maxi(spell.pierce, 0) + 1
	_fit_beam_legs(legs)
	for leg in legs:
		_bm_homing[at * _bm_legs + leg].start(spell, hash(Vector2i(_bm_born[at], leg)))
	_bm_count[at] = 0
	if caster == SpellRuntime.CASTER_WIZARD:
		if kit.aim_dir(actor).is_finite():
			_bm_turn[at] = kit.aim_dir(actor).angle_to(heading)
	else:
		# A still caster (a rune, a wall) keeps it: the beam starts where it is and walks out of it.
		var shot: int = kit.live_caster_shot(caster, caster_seq)
		var way: Vector2 = kit.projectiles.get_velocity_of(shot) if shot >= 0 else Vector2.ZERO
		if shot < 0:
			_bm_caster[at] = SpellRuntime.CASTER_POINT
		elif not way.is_zero_approx():
			_bm_turn[at] = way.angle_to(heading)
	kit.shot_started(tag)
	_beam_step(at, 0.0)
	if _bm_on[at] != 0:
		kit.live_join(spell, tag, SpellRuntime.LC_ROW, at, _bm_born[at], true, lifetime, _bm_tip[at], _bm_dir[at])
	return true


## Runs live beam `at` on by `delta`: its life, where its caster holds it, its path and its hit.
func _beam_step(at: int, delta: float) -> void:
	_bm_life[at] -= delta
	if _bm_life[at] <= 0.0:
		_end_beam(at, true)
		return
	_beam_follow(at)
	if _bm_on[at] == 0:
		return
	_beam_path(at)
	_bm_tick[at] -= delta
	var hit: bool = _bm_tick[at] <= 0.0
	if hit:
		_bm_tick[at] = maxf(_bm_tick[at] + SpellLimits.BEAM_TICK, 0.001)
	var spell: CompiledSpell = _bm_spell[at]
	var tag: int = _bm_tag[at]
	_beam_cast(at, hit)
	# Every step, not only on its hits: a shot must not slip through between two ticks.
	if _bm_on[at] != 0 and _bm_spell[at] == spell and _bm_tag[at] == tag:
		_bm_shield[at] = kit.guard_path(spell, tag, _bm_actor[at], _bm_points, at * _bm_stride, _bm_count[at], _bm_reach[at], _beam_width(at), _bm_shield[at])


## Puts live beam `at` where its caster holds it now. A beam whose wizard has no aim any more
## (down, gone) ends quietly; one whose shot is gone stays where the shot last was.
func _beam_follow(at: int) -> void:
	var caster: int = _bm_caster[at]
	if caster == SpellRuntime.CASTER_WIZARD:
		var actor: int = _bm_actor[at]
		if kit.aim_origin(actor).is_finite():
			_bm_origin[at] = kit.aim_origin(actor)
			_bm_dir[at] = kit.aim_dir(actor).rotated(_bm_turn[at])
		elif kit.aim_seen(actor):
			_end_beam(at, false)
	elif caster >= 0:
		if kit.projectiles.is_alive(caster) and kit.projectiles.get_seq_of(caster) == _bm_caster_seq[at]:
			_bm_origin[at] = kit.projectiles.get_position_of(caster)
			var way: Vector2 = kit.projectiles.get_velocity_of(caster)
			if not way.is_zero_approx():
				_bm_dir[at] = way.normalized().rotated(_bm_turn[at])
		else:
			_bm_caster[at] = SpellRuntime.CASTER_POINT


## The path live beam `at` follows (`_bm_points`): straight along its way for its `ray_length`,
## or, when it homes, bent onto a target in front of it (picked by `Projectiles.homing_point` and
## kept while it can), then for each pierce it has bent on from there toward another, as a homing
## shot picks a new target after a hit; past the last it goes straight on. With spiral the whole
## path waves sideways (`_wave`). Its hits cut it at its `ray_length` (`ray_points`). `beam_bend`
## and `beam_end` keep its first curve. Where each
## leg's target is in the path goes to `_steer_goals`, for `_beam_steer`: a homing beam that turns
## at a wall homes again from there with the legs it has not reached.
func _beam_path(at: int) -> void:
	var spell: CompiledSpell = _bm_spell[at]
	var origin: Vector2 = _bm_origin[at]
	var way: Vector2 = _bm_dir[at]
	var length: float = spell.ray_length
	var legs: int = maxi(spell.pierce, 0) + 1 if spell.homing_range > 0.0 else 0
	_fit_beam_points(legs * SpellRuntime.ProjectilesScript.RAY_SEGMENTS + 2)
	var base: int = at * _bm_stride
	_bm_points[base] = origin
	var count: int = 1
	_bm_bend[at] = origin + way * (length * 0.5)
	_bm_end[at] = origin + way * length
	var from: Vector2 = origin
	var walked: float = 0.0
	_steer_goal_count = 0
	if spell.homing_range > 0.0:
		for leg in legs:
			var homing: Homing = _bm_homing[at * _bm_legs + leg]
			var goal: Vector2 = homing.point(kit.projectiles, _bm_actor[at], from, way)
			if not goal.is_finite() or walked >= length or _picked_before(at, leg):
				homing.keep = 0
				break
			var bend: Vector2 = from + way * (from.distance_to(goal) * 0.6)
			if leg == 0:
				_bm_bend[at] = bend
				_bm_end[at] = goal
			for n in range(1, SpellRuntime.ProjectilesScript.RAY_SEGMENTS + 1):
				var t: float = float(n) / SpellRuntime.ProjectilesScript.RAY_SEGMENTS
				var u: float = 1.0 - t
				var point: Vector2 = from * (u * u) + bend * (2.0 * u * t) + goal * (t * t)
				walked += _bm_points[base + count - 1].distance_to(point)
				_bm_points[base + count] = point
				count += 1
			_add_steer_goal(count - 1)
			# It leaves the target the way the curve came in.
			if not goal.is_equal_approx(bend):
				way = bend.direction_to(goal)
			from = goal
	if walked < length:
		_bm_points[base + count] = from + way * (length - walked)
		count += 1
	var spiral: float = spell.behaviour(ModifierBase.Behaviour.SPIRAL)
	if spiral > 0.0:
		# It waves along the whole path; its legs' targets keep their place in it.
		var made: int = _wave(_bm_points, base + 1, count - 1, spiral * 0.5, origin)
		_fit_beam_points(made + 1)
		base = at * _bm_stride
		for n in made:
			_bm_points[base + 1 + n] = _wave_points[n]
		for k in _steer_goal_count:
			_steer_goals[k] = _wave_index[_steer_goals[k] - 1]
		count = made + 1
	_bm_count[at] = count


## A homing or spiral live beam (`_steer_row`) turned off a wall at point `turn` of its path
## (`at`, going `way` off the wall, `left` pixels of it left): it homes again from there, as it did
## from its staff, with the legs it had not reached before the wall (a leg's target past the turn
## was not reached: `_steer_goals`), then goes straight on for what is left, waving all the way
## with spiral. Returns the points after `at` (`Projectiles.ray_points` asks at every turn); the
## same rule as a homing or spiral shot, which steers and weaves again after it bounces.
func _beam_steer(turn: int, at: Vector2, way: Vector2, left: float) -> PackedVector2Array:
	var row: int = _steer_row
	var spell: CompiledSpell = _bm_spell[row] if row >= 0 else null
	var count: int = 0
	var spiral: float = spell.behaviour(ModifierBase.Behaviour.SPIRAL) if spell != null else 0.0
	if spell == null or (spell.homing_range <= 0.0 and spiral <= 0.0):
		_steer_points.resize(0)
		return _steer_points
	var reached: int = 0
	while reached < _steer_goal_count and _steer_goals[reached] < turn:
		reached += 1
	_steer_goal_count = reached
	var legs: int = maxi(spell.pierce, 0) + 1 if spell.homing_range > 0.0 else 0
	var from: Vector2 = at
	var heading: Vector2 = way
	var walked: float = 0.0
	if _steer_points.size() < legs * SpellRuntime.ProjectilesScript.RAY_SEGMENTS + 1:
		_steer_points.resize(legs * SpellRuntime.ProjectilesScript.RAY_SEGMENTS + 1)
	for leg in range(reached, mini(legs, _bm_legs)):
		var homing: Homing = _bm_homing[row * _bm_legs + leg]
		var goal: Vector2 = homing.point(kit.projectiles, _bm_actor[row], from, heading)
		if not goal.is_finite() or walked >= left or _picked_before(row, leg):
			homing.keep = 0
			break
		var bend: Vector2 = from + heading * (from.distance_to(goal) * 0.6)
		var prev: Vector2 = from
		for n in range(1, SpellRuntime.ProjectilesScript.RAY_SEGMENTS + 1):
			var t: float = float(n) / SpellRuntime.ProjectilesScript.RAY_SEGMENTS
			var u: float = 1.0 - t
			var point: Vector2 = from * (u * u) + bend * (2.0 * u * t) + goal * (t * t)
			walked += prev.distance_to(point)
			_steer_points[count] = point
			count += 1
			prev = point
		# The goal's index in the path: the turn's, plus the points after it.
		_add_steer_goal(turn + count)
		if not goal.is_equal_approx(bend):
			heading = bend.direction_to(goal)
		from = goal
	if walked < left:
		if _steer_points.size() <= count:
			_steer_points.resize(count + 1)
		_steer_points[count] = from + heading * (left - walked)
		count += 1
	if spiral > 0.0 and count > 0:
		var made: int = _wave(_steer_points, 0, count, spiral * 0.5, at)
		for k in range(reached, _steer_goal_count):
			_steer_goals[k] = turn + _wave_index[_steer_goals[k] - turn - 1]
		if _steer_points.size() < made:
			_steer_points.resize(made)
		for n in made:
			_steer_points[n] = _wave_points[n]
		count = made
	_steer_points.resize(count)
	return _steer_points


## Notes that a leg's target is point `index` of the steered beam's path.
func _add_steer_goal(index: int) -> void:
	if _steer_goal_count == _steer_goals.size():
		_steer_goals.resize(maxi(8, _steer_goal_count * 2))
	_steer_goals[_steer_goal_count] = index
	_steer_goal_count += 1


## True when leg `leg` of live beam `at` picked a target an earlier leg already bent to: the
## beam then goes straight on instead of doubling back.
func _picked_before(at: int, leg: int) -> bool:
	var id: int = _bm_homing[at * _bm_legs + leg].keep
	for before in leg:
		if _bm_homing[at * _bm_legs + before].keep == id:
			return true
	return false


## Live beam `at` along its curve: with `hit`, its hits, payloads and chain jumps (sent as a
## ray, `_ray_begin`, that `_on_hit` reads); without, only how far it gets.
func _beam_cast(at: int, hit: bool) -> void:
	var spell: CompiledSpell = _bm_spell[at]
	var tag: int = _bm_tag[at]
	var actor: int = _bm_actor[at]
	var source: Node = _bm_source[at] if is_instance_valid(_bm_source[at]) else null
	var bounces: int = kit.bounces(spell)
	var ghost: bool = kit.ghost(spell)
	var width: float = _beam_width(at)
	# A homing or spiral beam that turns at a wall homes and waves again from there (`_beam_steer`).
	var steer: Callable = _steer_call if bounces > 0 and (spell.homing_range > 0.0 or spell.behaviour(ModifierBase.Behaviour.SPIRAL) > 0.0) else Callable()
	_steer_row = at
	# What a shot casts leaves it: a wall's beam walks out of its wall (rules R4 F8).
	if _bm_caster[at] >= 0:
		kit.projectiles.ray_cast_by(_bm_caster[at])
	if not hit:
		_bm_reach[at] = kit.projectiles.ray_points(actor, _bm_points, at * _bm_stride, _bm_count[at], spell.ray_length, spell.pierce, SpellRuntime.HITS, tag, width, source, false, bounces, steer, ghost)
		_bm_tip[at] = kit.projectiles.ray_end
		_bm_tip_dir[at] = kit.projectiles.ray_end_heading
		if bounces > 0:
			_beam_keep_path(at)
		return
	var ray: RayHit = kit.ray_begin(tag, _bm_dir[at], _bm_chain[at], _bm_prev[at], _bm_hit[at], -1)
	var got: float = kit.projectiles.ray_points(actor, _bm_points, at * _bm_stride, _bm_count[at], spell.ray_length, spell.pierce, SpellRuntime.HITS, tag, width, source, true, bounces, steer, ghost)
	var tip: Vector2 = kit.projectiles.ray_end
	var tip_dir: Vector2 = kit.projectiles.ray_end_heading
	var turned: bool = bounces > 0 and kit.projectiles.ray_path_count > 0
	# What relay took on stays for its later hits.
	var took: HitProfile = ray.hit
	kit.ray_end()
	# A hit handler may have ended this beam (a rebuild) or reused its row.
	if _bm_on[at] != 0 and _bm_spell[at] == spell and _bm_tag[at] == tag:
		# Its zaps take on what relay took on, too (a shot's do, `Spells._relay`).
		if took != _bm_hit[at] and took != null and spell.zap_hit != null:
			_bm_zap_hit[at] = StaffCompiler.zap_hit(took)
		_bm_hit[at] = took
		_bm_reach[at] = got
		_bm_tip[at] = tip
		_bm_tip_dir[at] = tip_dir
		_bm_hit_at[at] = kit.clock()
		if turned:
			_beam_keep_path(at)
	kit.cast_jumps()


## Live beam `at` follows the path its last ray walked (`Projectiles.ray_path`), so a beam that
## turned at walls is drawn along its turns.
func _beam_keep_path(at: int) -> void:
	var count: int = kit.projectiles.ray_path_count
	if count < 2:
		return
	_fit_beam_points(count)
	var base: int = at * _bm_stride
	for n in count:
		_bm_points[base + n] = kit.projectiles.ray_path[n]
	_bm_count[at] = count


## How far either side of its line live beam `at` hits: half its carrier's size, times its
## growth for every second it has been on, up to the room's size (as a growing shot).
func _beam_width(at: int) -> float:
	var spell: CompiledSpell = _bm_spell[at]
	var width: float = spell.radius * 0.5
	var growth: float = spell.behaviour(ModifierBase.Behaviour.GROWTH)
	if growth > 1.0:
		width = minf(width * pow(growth, _bm_span[at] - _bm_life[at]), maxf(kit.projectiles.room_size(), width))
	return width


## Live beam `at` pulls (magnet) the enemies within its card's reach toward its line: one pull for
## each piece of its path, as far as it got (`pull_requested` with the piece's two ends).
func _beam_pull(at: int) -> void:
	var spell: CompiledSpell = _bm_spell[at]
	var reach: float = spell.behaviour(ModifierBase.Behaviour.MAGNET)
	var base: int = at * _bm_stride
	var walked: float = 0.0
	for n in _bm_count[at] - 1:
		if walked >= _bm_reach[at]:
			break
		var a: Vector2 = _bm_points[base + n]
		var b: Vector2 = _bm_points[base + n + 1]
		var piece: float = a.distance_to(b)
		if walked + piece > _bm_reach[at]:
			b = a.move_toward(b, _bm_reach[at] - walked)
		kit.events.pull_requested.emit(_bm_actor[at], a, reach, SpellLimits.MAGNET_PULL, _bm_tag[at], b)
		walked += piece


## The path `start`, `points[first]` .. `points[first + count - 1]` waving sideways (spiral on a
## beam, rules R4f), as a spiral shot weaves round its line: every piece cut into pieces of
## BEAM_WAVE / BEAM_WAVE_STEPS pixels at most, each new point moved `amp * sin` of how far along
## it is (a wave every BEAM_WAVE pixels; `start` stays put) off its piece. The points after
## `start` go to `_wave_points`; `_wave_index[i]` is how many of them reach `points[first + i]`
## (its index in the waved path, `start` being 0). Returns how many. Allocation-free once grown.
func _wave(points: PackedVector2Array, first: int, count: int, amp: float, start: Vector2) -> int:
	var most: float = SpellLimits.BEAM_WAVE / SpellLimits.BEAM_WAVE_STEPS
	if _wave_index.size() < count:
		_wave_index.resize(count)
	var made: int = 0
	var walked: float = 0.0
	var from: Vector2 = start
	for i in count:
		var to: Vector2 = points[first + i]
		var piece: float = from.distance_to(to)
		var pieces: int = maxi(ceili(piece / most), 1)
		var side: Vector2 = from.direction_to(to).orthogonal()
		if _wave_points.size() < made + pieces:
			_wave_points.resize(maxi(made + pieces, _wave_points.size() * 2))
		for n in range(1, pieces + 1):
			var t: float = float(n) / pieces
			_wave_points[made] = from.lerp(to, t) + side * (amp * sin(TAU * (walked + piece * t) / SpellLimits.BEAM_WAVE))
			made += 1
		_wave_index[i] = made
		walked += piece
		from = to
	return made


## Live beam `at` is over. With `finished` (its life ran out), its `blast` and its `on expire`
## payload happen where it ends; a beam switched off, rebuilt or dropped ends quietly.
func _end_beam(at: int, finished: bool) -> void:
	if _bm_on[at] == 0:
		return
	_bm_on[at] = 0
	var spell: CompiledSpell = _bm_spell[at]
	var tag: int = _bm_tag[at]
	var actor: int = _bm_actor[at]
	_bm_spell[at] = null
	_bm_source[at] = null
	_bm_hit[at] = null
	_bm_zap_hit[at] = null
	_drop_zaps(at)
	var tip: Vector2 = _bm_tip[at]
	if finished and spell != null and _bm_reach[at] > 0.0 and tip.is_finite():
		kit.blast(spell, tag, actor, tip)
		if spell.payload != null and spell.trigger_event == TriggerBase.Event.EXPIRE:
			kit.fire_payload(spell, tag, actor, tip, _bm_tip_dir[at] if not _bm_tip_dir[at].is_zero_approx() else _bm_dir[at], null)
	kit.shot_ended(tag)


## Doubles the live beam rows (every one is on). A frame allocates only the first time it has
## more beams than any before it.
func _grow_beams() -> void:
	var size: int = _bm_on.size() * 2
	_bm_on.resize(size)
	_bm_born.resize(size)
	_bm_spell.resize(size)
	_bm_source.resize(size)
	_bm_tag.resize(size)
	_bm_actor.resize(size)
	_bm_caster.resize(size)
	_bm_caster_seq.resize(size)
	_bm_life.resize(size)
	_bm_span.resize(size)
	_bm_tick.resize(size)
	_bm_turn.resize(size)
	_bm_count.resize(size)
	_bm_chain.resize(size)
	_bm_prev.resize(size)
	_bm_hit.resize(size)
	_bm_shield.resize(size)
	_bm_origin.resize(size)
	_bm_dir.resize(size)
	_bm_bend.resize(size)
	_bm_end.resize(size)
	_bm_reach.resize(size)
	_bm_tip.resize(size)
	_bm_tip_dir.resize(size)
	_bm_hit_at.resize(size)
	_bm_zap_hit.resize(size)
	_bm_zap_rolls.resize(size)
	_bm_zapped_count.resize(size)
	_bm_due_count.resize(size)
	_bm_zapped.resize(size * SpellRuntime.ZAP_MEMORY)
	_bm_zapped_at.resize(size * SpellRuntime.ZAP_MEMORY)
	_bm_due_body.resize(size * SpellRuntime.ZAP_DUE)
	_bm_due_at.resize(size * SpellRuntime.ZAP_DUE)
	_bm_points.resize(size * _bm_stride)
	while _bm_homing.size() < size * _bm_legs:
		_bm_homing.append(Homing.new())


## Every live beam row has room for `count` points: the rows are laid out again, wider, the
## first time a beam needs more (a homing beam with more pierce, a beam turning at more walls).
func _fit_beam_points(count: int) -> void:
	if count <= _bm_stride:
		return
	var stride: int = maxi(count, _bm_stride * 2)
	var points := PackedVector2Array()
	points.resize(_bm_on.size() * stride)
	for row in _bm_on.size():
		for n in mini(_bm_count[row], _bm_stride):
			points[row * stride + n] = _bm_points[row * _bm_stride + n]
	_bm_points = points
	_bm_stride = stride


## Every live beam row has room for `legs` homing legs (laid out again, wider, when it has not).
func _fit_beam_legs(legs: int) -> void:
	if legs <= _bm_legs:
		return
	var width: int = maxi(legs, _bm_legs * 2)
	var homing: Array[Homing] = []
	for row in _bm_on.size():
		for leg in width:
			homing.append(_bm_homing[row * _bm_legs + leg] if leg < _bm_legs else Homing.new())
	_bm_homing = homing
	_bm_legs = width


## Ends the live beams of `tag` quietly (a `hold` switched off, a revoked build).
func end_of(tag: int) -> void:
	for at in _bm_on.size():
		if _bm_on[at] != 0 and _bm_tag[at] == tag:
			_end_beam(at, false)


## Runs every live beam on by `delta` (a beam started meanwhile, by a payload, waits for the next).
func step(delta: float) -> void:
	var first_new: int = _bm_next_born
	for at in _bm_on.size():
		if _bm_on[at] != 0 and _bm_born[at] < first_new:
			_beam_step(at, delta)
	_pull_magnets()
	_step_zaps(delta)


## The live beams, for their look (`gameplay/feel` draws them every frame): `beam_slots()` rows,
## each on or off. A beam on runs along its path (`beam_point_count`, `beam_point`; a homing one
## bends onto a target, `beam_end`, through `beam_bend`, and with pierce on to more), cut to its
## first `beam_reach` pixels (its length, a wall, or the target that spends it).
## `beam_since_hit` is seconds since its last hit; `beam_left` is its life left, 0 to 1, and
## `beam_fade` how whole it looks, 1 to 0 as it dissolves at its end (`Carrier.fade_left`).
func beam_slots() -> int:
	return _bm_on.size()


func beam_on(at: int) -> bool:
	return at >= 0 and at < _bm_on.size() and _bm_on[at] != 0


## The caster (actor id) of live beam `at`; its look is drawn in that actor's ramp.
func beam_caster(at: int) -> int:
	return _bm_actor[at]


func beam_origin(at: int) -> Vector2:
	return _bm_origin[at]


## The points of live beam `at`'s path, from its start; it is drawn along them for its first
## `beam_reach` pixels.
func beam_point_count(at: int) -> int:
	return _bm_count[at]


func beam_point(at: int, n: int) -> Vector2:
	return _bm_points[at * _bm_stride + n]


func beam_bend(at: int) -> Vector2:
	return _bm_bend[at]


func beam_end(at: int) -> Vector2:
	return _bm_end[at]


func beam_reach(at: int) -> float:
	return _bm_reach[at]


## How many times wider than its carrier live beam `at` is now (growth; 1.0 for a plain beam).
func beam_growth(at: int) -> float:
	var spell: CompiledSpell = _bm_spell[at]
	if spell == null or spell.radius <= 0.0:
		return 1.0
	return _beam_width(at) / (spell.radius * 0.5)


func beam_tint(at: int) -> Color:
	return _bm_spell[at].tint if _bm_spell[at] != null else Color.WHITE


## The packed look kinds of live beam `at` (`CompiledSpell.look`), so it shows its cards.
func beam_look(at: int) -> int:
	return _bm_spell[at].look if _bm_spell[at] != null else 0


func beam_since_hit(at: int) -> float:
	return kit.clock() - _bm_hit_at[at]


func beam_fade(at: int) -> float:
	return fade_left(_bm_life[at], _bm_span[at])


func beam_left(at: int) -> float:
	return clampf(_bm_life[at] / _bm_span[at], 0.0, 1.0) if _bm_span[at] > 0.0 and _bm_span[at] < SpellLimits.HOLD_LIFETIME else 1.0


## Live beams on now (tests).
func beam_count() -> int:
	return _bm_on.count(1)


## A beam of its own along `heading`, cast by whoever casts this launch (`Spells._caster`).
func shoot(spell: CompiledSpell, tag: int, actor: int, origin: Vector2, _direction: Vector2, heading: Vector2, _n: int, _count: int, source: Node, lifetime: float, chain: int, prev: int) -> int:
	return 1 if start(spell, tag, actor, origin, heading, chain, prev, source, lifetime, kit.caster(), kit.caster_seq(), kit.is_echo(spell)) else 0


func reach_of(spell: CompiledSpell) -> float:
	return spell.ray_length


## A held beam is switched off: it ends quietly.
func switch_off(tag: int) -> void:
	end_of(tag)
