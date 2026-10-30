class_name CarrierBeam
extends Carrier
## A line held by its caster that hits at once and every `SpellLimits.BEAM_TICK` (`FormBase.Motion.RAY`:
## the beam). It runs most shot cards its own way: it bends to a target, turns at walls, waves,
## widens, pulls and guards along its line.
##
## Its rows: the live beams, which it keeps itself (`bind` makes them), starts (`start`, from
## `shoot`), runs (`step`) and ends (`end_of`, `end_actor`). Its hits go through the runtime as rays
## (`Spells._ray_begin`), so its cards, payloads and chains work as a shot's do; its looks read the
## `beam_*` getters (through `Spells`).


## How the beam takes each modifier (`ModifierBase.Behaviour`), every one: see `Carrier`.
const BEHAVIOURS: Dictionary = {
	B.NONE: [Use.RUNS, Look.SHOWN],
	B.HOMING: [Use.OWN, Look.SHOWN],
	B.CHAIN: [Use.RUNS, Look.SHOWN],
	B.SHIELD: [Use.OWN, Look.SHOWN],
	B.BLAST: [Use.RUNS, Look.CUE],
	B.HOLD: [Use.RUNS, Look.SHOWN],
	B.RECOIL: [Use.RUNS, Look.SHOWN],
	B.BOUNCE: [Use.OWN, Look.SHOWN],
	B.ECHO: [Use.RUNS, Look.SHOWN],
	B.LINGER: [Use.WASTED, "it only changes a moving shot, and a beam is a line, not a shot"],
	B.HEAVY: [Use.RUNS, Look.SHOWN],
	B.SIPHON: [Use.RUNS, Look.SHOWN],
	B.STICKY: [Use.WASTED, "it only changes a moving shot, and a beam is a line, not a shot"],
	B.MAGNET: [Use.OWN, Look.SHOWN],
	B.GHOST: [Use.OWN, Look.SHOWN],
	B.SPIRAL: [Use.OWN, Look.SHOWN],
	B.MIRROR: [Use.RUNS, Look.SHOWN],
	B.GROWTH: [Use.OWN, Look.SHOWN],
	B.RELAY: [Use.RUNS, Look.SHOWN],
	B.RETURN: [Use.WASTED, "it does not fly out"],
	B.ARC: [Use.WASTED, "it is not a shot that stays in the air"],
	B.POSSESS: [Use.RUNS, Look.SHOWN],
	B.DEFLECT: [Use.OWN, Look.SHOWN],
}
## When each trigger (`TriggerBase.Event`) fires on the beam: "" when it can, else why it never does.
const EVENTS: Dictionary = {
	E.HIT: "",
	E.EXPIRE: "",
	E.TIMER: "",
	E.BLOCK: "",
	E.KILL: "",
	E.CAST: "",
	E.WALL: "",
	E.HURT: "",
	E.REACTION: "",
}
## How the beam takes an infusion.
const INFUSIONS: Array = [Use.RUNS, Look.SHOWN]


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
## Shield charges live beam `at` has left for shots it touches (melee I3, `_guard_path`).
var _bm_shield: PackedInt32Array = PackedInt32Array()
var _bm_origin: PackedVector2Array = PackedVector2Array()
var _bm_dir: PackedVector2Array = PackedVector2Array()
var _bm_bend: PackedVector2Array = PackedVector2Array()
var _bm_end: PackedVector2Array = PackedVector2Array()
var _bm_reach: PackedFloat32Array = PackedFloat32Array()
var _bm_tip: PackedVector2Array = PackedVector2Array()
var _bm_tip_dir: PackedVector2Array = PackedVector2Array()
var _bm_hit_at: PackedFloat32Array = PackedFloat32Array()


func motion() -> int:
	return FormBase.Motion.RAY


func noun() -> String:
	return "beam"


func what() -> String:
	return "a beam is a line, not a shot"


func traits() -> int:
	return HITS | LASTS | REACHES | GUARDS | STEERS | SPEED | SHOTS | SPREAD | PIERCE | INSTANT_HOMING


func behaviours() -> Dictionary:
	return BEHAVIOURS


func events() -> Dictionary:
	return EVENTS


func infusions() -> Array:
	return INFUSIONS


func hit_kind() -> StringName:
	return &"ray"


## Makes this carrier's rows for `runtime`, which casts it.
func bind(runtime: SpellRuntime, staff_poses: StaffPoses) -> void:
	super(runtime, staff_poses)
	var rows: int = SpellLimits.BEAM_ROWS_START
	for column: Variant in [_bm_on, _bm_born, _bm_spell, _bm_source, _bm_tag, _bm_actor, _bm_caster, _bm_caster_seq, _bm_life, _bm_span, _bm_tick, _bm_turn, _bm_count, _bm_chain, _bm_prev, _bm_hit, _bm_shield, _bm_origin, _bm_dir, _bm_bend, _bm_end, _bm_reach, _bm_tip, _bm_tip_dir, _bm_hit_at]:
		column.resize(rows)
	for i in rows * _bm_legs:
		_bm_homing.append(Homing.new())
	_bm_points.resize(rows * _bm_stride)


## Every beam gone at once, quietly (`Spells.clear`).
func clear() -> void:
	_bm_on.fill(0)
	_bm_spell.fill(null)
	_bm_source.fill(null)


## The beams of `actor` end quietly (its caster closed).
func end_actor(actor: int) -> void:
	for at in _bm_on.size():
		if _bm_on[at] != 0 and _bm_actor[at] == actor:
			_end_beam(at, false)


## Where live beam `at` ends now, while it is the beam born `born` (a live carrier's place, for its
## timer and `on hurt` payloads); INF once it has ended.
func tip_of(at: int, born: int) -> Vector2:
	return _bm_tip[at] if _bm_on[at] != 0 and _bm_born[at] == born else Vector2.INF


## Every live beam with `magnet` pulls toward its line (rules R4f; `Spells._step_magnets`).
func pull_magnets() -> void:
	for at in _bm_on.size():
		if _bm_on[at] != 0 and _bm_spell[at].behaviour(ModifierBase.Behaviour.MAGNET) > 0.0:
			_beam_pull(at)


## How many times a carrier with `motion` that lives `lifetime` seconds hits one target: a live
## beam once at once and then every `SpellLimits.BEAM_TICK` seconds of its life; anything else once.
static func beam_hits(motion: int, lifetime: float) -> int:
	if motion != FormBase.Motion.RAY:
		return 1
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
	_bm_shield[at] = roundi(spell.behaviour(ModifierBase.Behaviour.SHIELD))
	_bm_origin[at] = origin
	_bm_dir[at] = heading.normalized()
	_bm_reach[at] = 0.0
	_bm_hit_at[at] = rt._clock
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
		if rt._aim_dir[actor].is_finite():
			_bm_turn[at] = rt._aim_dir[actor].angle_to(heading)
	else:
		var shot: int = rt.live_caster_shot(caster, caster_seq)
		var way: Vector2 = rt.projectiles.get_velocity_of(shot) if shot >= 0 else Vector2.ZERO
		if way.is_zero_approx():
			_bm_caster[at] = SpellRuntime.CASTER_POINT
		else:
			_bm_turn[at] = way.angle_to(heading)
	rt.shot_started(tag)
	_beam_step(at, 0.0)
	if _bm_on[at] != 0:
		rt._lc_join(spell, tag, SpellRuntime.LC_BEAM, at, _bm_born[at], true, lifetime, _bm_tip[at], _bm_dir[at])
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
		_bm_shield[at] = rt._guard_path(spell, tag, _bm_actor[at], _bm_points, at * _bm_stride, _bm_count[at], _bm_reach[at], _beam_width(at), _bm_shield[at])


## Puts live beam `at` where its caster holds it now. A beam whose wizard has no aim any more
## (down, gone) ends quietly; one whose shot is gone stays where the shot last was.
func _beam_follow(at: int) -> void:
	var caster: int = _bm_caster[at]
	if caster == SpellRuntime.CASTER_WIZARD:
		var actor: int = _bm_actor[at]
		if rt._aim_origin[actor].is_finite():
			_bm_origin[at] = rt._aim_origin[actor]
			_bm_dir[at] = rt._aim_dir[actor].rotated(_bm_turn[at])
		elif rt._aim_seen[actor] != 0:
			_end_beam(at, false)
	elif caster >= 0:
		if rt.projectiles.is_alive(caster) and rt.projectiles.get_seq_of(caster) == _bm_caster_seq[at]:
			_bm_origin[at] = rt.projectiles.get_position_of(caster)
			var way: Vector2 = rt.projectiles.get_velocity_of(caster)
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
			var goal: Vector2 = homing.point(rt.projectiles, _bm_actor[at], from, way)
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
		var goal: Vector2 = homing.point(rt.projectiles, _bm_actor[row], from, heading)
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
	var bounces: int = rt._bounces(spell)
	var ghost: bool = SpellRuntime._ghost(spell)
	var width: float = _beam_width(at)
	# A homing or spiral beam that turns at a wall homes and waves again from there (`_beam_steer`).
	var steer: Callable = _steer_call if bounces > 0 and (spell.homing_range > 0.0 or spell.behaviour(ModifierBase.Behaviour.SPIRAL) > 0.0) else Callable()
	_steer_row = at
	if not hit:
		_bm_reach[at] = rt.projectiles.ray_points(actor, _bm_points, at * _bm_stride, _bm_count[at], spell.ray_length, spell.pierce, SpellRuntime.HITS, tag, width, source, false, bounces, steer, ghost)
		_bm_tip[at] = rt.projectiles.ray_end
		_bm_tip_dir[at] = rt.projectiles.ray_end_heading
		if bounces > 0:
			_beam_keep_path(at)
		return
	var ray: RayHit = rt._ray_begin(tag, _bm_dir[at], _bm_chain[at], _bm_prev[at], _bm_hit[at], -1)
	var got: float = rt.projectiles.ray_points(actor, _bm_points, at * _bm_stride, _bm_count[at], spell.ray_length, spell.pierce, SpellRuntime.HITS, tag, width, source, true, bounces, steer, ghost)
	var tip: Vector2 = rt.projectiles.ray_end
	var tip_dir: Vector2 = rt.projectiles.ray_end_heading
	var turned: bool = bounces > 0 and rt.projectiles.ray_path_count > 0
	# What relay took on stays for its later hits.
	var took: HitProfile = ray.hit
	rt._ray_end()
	# A hit handler may have ended this beam (a rebuild) or reused its row.
	if _bm_on[at] != 0 and _bm_spell[at] == spell and _bm_tag[at] == tag:
		_bm_hit[at] = took
		_bm_reach[at] = got
		_bm_tip[at] = tip
		_bm_tip_dir[at] = tip_dir
		_bm_hit_at[at] = rt._clock
		if turned:
			_beam_keep_path(at)
	rt._cast_jumps()


## Live beam `at` follows the path its last ray walked (`Projectiles.ray_path`), so a beam that
## turned at walls is drawn along its turns.
func _beam_keep_path(at: int) -> void:
	var count: int = rt.projectiles.ray_path_count
	if count < 2:
		return
	_fit_beam_points(count)
	var base: int = at * _bm_stride
	for n in count:
		_bm_points[base + n] = rt.projectiles.ray_path[n]
	_bm_count[at] = count


## How far either side of its line live beam `at` hits: half its carrier's size, times its
## growth for every second it has been on, up to the room's size (as a growing shot).
func _beam_width(at: int) -> float:
	var spell: CompiledSpell = _bm_spell[at]
	var width: float = spell.radius * 0.5
	var growth: float = spell.behaviour(ModifierBase.Behaviour.GROWTH)
	if growth > 1.0:
		width = minf(width * pow(growth, _bm_span[at] - _bm_life[at]), maxf(rt.projectiles.room_size(), width))
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
		rt.events.pull_requested.emit(_bm_actor[at], a, reach, SpellLimits.MAGNET_PULL, _bm_tag[at], b)
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
	var tip: Vector2 = _bm_tip[at]
	if finished and spell != null and _bm_reach[at] > 0.0 and tip.is_finite():
		rt._blast(spell, tag, actor, tip)
		if spell.payload != null and spell.trigger_event == TriggerBase.Event.EXPIRE:
			rt._fire_payload(spell, tag, actor, tip, _bm_tip_dir[at] if not _bm_tip_dir[at].is_zero_approx() else _bm_dir[at], null)
	rt.shot_ended(tag)


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


## The live beams, for their look (`gameplay/feel` draws them every frame): `beam_slots()` rows,
## each on or off. A beam on runs along its path (`beam_point_count`, `beam_point`; a homing one
## bends onto a target, `beam_end`, through `beam_bend`, and with pierce on to more), cut to its
## first `beam_reach` pixels (its length, a wall, or the target that spends it).
## `beam_since_hit` is seconds since its last hit; `beam_left` is its life left, 0 to 1.
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
	return rt._clock - _bm_hit_at[at]


func beam_left(at: int) -> float:
	return clampf(_bm_life[at] / _bm_span[at], 0.0, 1.0) if _bm_span[at] > 0.0 and _bm_span[at] < SpellLimits.HOLD_LIFETIME else 1.0


## Live beams on now (tests).
func beam_count() -> int:
	return _bm_on.count(1)


## A beam of its own along `heading`, cast by whoever casts this launch (`Spells._caster`).
func shoot(spell: CompiledSpell, tag: int, actor: int, origin: Vector2, _direction: Vector2, heading: Vector2, _n: int, _count: int, source: Node, lifetime: float, chain: int, prev: int) -> int:
	return 1 if start(spell, tag, actor, origin, heading, chain, prev, source, lifetime, rt._caster, rt._caster_seq, rt._echo_spell == spell) else 0


func reach_of(spell: CompiledSpell) -> float:
	return spell.ray_length
