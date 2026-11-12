class_name CarrierPulse
extends Carrier
## The Pulse card's carrier (`&"pulse"`; docs/CARRIERS.md, "Pulse: a ring from the cast point";
## props W9a, owner 2026-11-12: it replaced the compiler's fallback carriers, "a custom rule", is
## one carrier, "One carrier!", and "should emit a pulse going outwards from the cast point (using
## easing as bolt/atom). It should not hit instantly").
##
## A ring that grows from the point it is cast at (where what casts it stands then: the caster's
## body, or in a payload the body or shot that fired it, else the payload's point) and stays there.
## Its radius grows as a shot flies, `speed` on the shots' speed curve over its `lifetime`
## (`ProjectilesScript.speed_factor`; SpellLimits.SHOT_SPEED_*, times its cards' `speed_start`,
## `speed_end`, `speed_ease`), and its edge strikes each body it reaches once (`Projectiles.sweep`
## all round the centre, so a wall between hides a body unless it has `ghost`), outward from the
## centre, `radius` the width of its edge. It spares the body that casts it (owner, 2026-11-12:
## "Yes it spares its caster"). While it is out it meets the shots of other teams inside it
## (`MEETS_SHOTS`, as a slam's ring): a deflect turns them outward, a shield stops them while its
## charges last. With `return` it grows for half its life, then shrinks back to its centre at the
## speed it had then, striking again on the way in, as a returning shot flies home. When it is
## done, its `blast` and `on expire` happen at its centre. Its triggers that fire while it lasts
## fire from its centre (`LC_ROW`, `tip_of`), and they and its end are cast by that point, as a
## slam's end or a beam's tip: a bolt they send hits a wizard still standing there (owner,
## 2026-11-12). A hold casts it again every wind-up and life (`REPEATS_HELD`).
##
## Its rows: the live rings, which it keeps itself (`bind` makes them), starts (`launch`), runs
## (`step`) and ends (`end_of`, `end_actor`, `clear`); the looks read the `pulse_*` getters
## (`CarrierPulse.of(spells)`).


const ProjectilesScript := preload("res://core/projectiles/projectile_manager.gd")

## State as who they point at: other bodies, never entered (core/sim/README.md).
const REFS: Array[StringName] = [&"_pu_source", &"_pu_struck"]

## The live rings: PULSE_ROWS_START rows at first, more when every one is on. Each keeps its
## spell and tag, the actor whose card it is, who casts it (`Spells._caster`, and its seq: the
## wizard's body, another body, a shot or a point), its centre and the way it was cast (for its
## payloads), its radius now, its age, the speed it shrinks at once it turns home (0 while it
## grows), the body it spares, its chain and hit for its strikes, its shield charges, and the
## bodies it has struck.
var _pu_on: PackedByteArray = PackedByteArray()
var _pu_born: PackedInt64Array = PackedInt64Array()
var _pu_next_born: int = 0
var _pu_spell: Array[CompiledSpell] = []
var _pu_source: Array[Node] = []
var _pu_tag: PackedInt64Array = PackedInt64Array()
var _pu_actor: PackedInt32Array = PackedInt32Array()
var _pu_caster: PackedInt32Array = PackedInt32Array()
var _pu_caster_seq: PackedInt64Array = PackedInt64Array()
var _pu_centre: PackedVector2Array = PackedVector2Array()
var _pu_dir: PackedVector2Array = PackedVector2Array()
var _pu_radius: PackedFloat32Array = PackedFloat32Array()
var _pu_age: PackedFloat32Array = PackedFloat32Array()
var _pu_home: PackedFloat32Array = PackedFloat32Array()
var _pu_chain: PackedInt32Array = PackedInt32Array()
var _pu_prev: PackedInt64Array = PackedInt64Array()
var _pu_hit: Array[HitProfile] = []
var _pu_shield: PackedInt32Array = PackedInt32Array()
var _pu_struck: Array[Array] = []


func id() -> StringName:
	return &"pulse"


## What draws its look: Feel, from its rows (`pulse_*`).
func look_drawer() -> int:
	return LOOK_NONE


## The rings of the runtime `spells` (its bound `pulse` carrier, `Spells.carrier`), for what reads
## its own getters (the looks, the tests).
static func of(spells: SpellRuntime) -> CarrierPulse:
	return spells.carrier(&"pulse") as CarrierPulse


func traits() -> int:
	return HITS | LASTS | SPEED | GUARDS | REPEATS_HELD | MEETS_SHOTS | AOE


## After the slams (5).
func step_order() -> int:
	return 6


## Its hits feel like an explosion (`HitProfile.kind`).
func hit_kind() -> StringName:
	return &"burst"


## Makes this carrier's rows for `runtime`, which casts it.
func bind(runtime_kit: CarrierKit, staff_poses: StaffPoses) -> void:
	super(runtime_kit, staff_poses)
	_grow_pulses(SpellLimits.PULSE_ROWS_START)


## One ring, from `origin` (where what casts it stands now), cast along `direction` (the way its
## payloads leave).
func launch(spell: CompiledSpell, tag: int, actor: int, origin: Vector2, direction: Vector2, _source: Node, _lifetime: float, chain: int, prev: int) -> int:
	if not origin.is_finite():
		return 0
	var at: int = _pu_on.find(0)
	if at < 0:
		at = _pu_on.size()
		_grow_pulses(at * 2)
	_pu_on[at] = 1
	_pu_born[at] = _pu_next_born
	_pu_next_born += 1
	_pu_spell[at] = spell
	# It spares the body that casts it (a shot that casts it is never struck by a sweep).
	var body: int = kit.caster_body(actor)
	_pu_source[at] = kit.body_node(body) if body >= 0 else null
	_pu_tag[at] = tag
	_pu_actor[at] = actor
	_pu_caster[at] = kit.caster()
	_pu_caster_seq[at] = kit.caster_seq()
	_pu_centre[at] = origin
	_pu_dir[at] = direction.normalized() if direction.is_finite() and not direction.is_zero_approx() else Vector2.RIGHT
	_pu_radius[at] = 0.0
	_pu_age[at] = 0.0
	_pu_home[at] = 0.0
	_pu_chain[at] = chain
	_pu_prev[at] = prev
	_pu_hit[at] = spell.echo_hit if kit.is_echo(spell) else null
	_pu_shield[at] = roundi(spell.behaviour(ModifierBase.Behaviour.SHIELD))
	_pu_struck[at].clear()
	kit.shot_started(tag)
	if kit.events != null:
		kit.set_cue_tag(tag)
		kit.events.carrier_shown.emit(actor, spell.carrier_card_id, origin, _pu_dir[at], 0.0, spell.tint, spell.look)
		kit.set_cue_tag(0)
	kit.live_join(spell, tag, SpellRuntime.LC_ROW, at, _pu_born[at], true, spell.lifetime, origin, _pu_dir[at])
	return 1


## Runs ring `at` on by `delta`: it grows (or, turned home, shrinks), meets the shots inside it,
## strikes the bodies its edge reaches, and ends when its life is out or it is home.
func _pulse_step(at: int, delta: float) -> void:
	var spell: CompiledSpell = _pu_spell[at]
	var tag: int = _pu_tag[at]
	var life: float = maxf(spell.lifetime, 0.001)
	var done: bool = false
	if _pu_home[at] > 0.0:
		# On its way home no life counts, as for a returning shot.
		_pu_radius[at] = maxf(_pu_radius[at] - _pu_home[at] * delta, 0.0)
		done = _pu_radius[at] <= 0.0
	else:
		_pu_age[at] += delta
		# The manager's speed curve, read at the step's middle (`ProjectileManager._curve_factor`).
		var left: float = clampf((life - _pu_age[at] + delta * 0.5) / life, 0.0, 1.0)
		var speed: float = spell.speed * ProjectilesScript.speed_factor(spell.speed_start, spell.speed_end, spell.speed_ease, left)
		_pu_radius[at] += speed * delta
		if spell.behaviour(ModifierBase.Behaviour.RETURN) > 0.0:
			if _pu_age[at] >= life * 0.5:
				# Half its life out: home at the speed it has now, and it may strike again.
				_pu_home[at] = maxf(speed, 1.0)
				_pu_struck[at].clear()
		else:
			done = _pu_age[at] >= life
	_pulse_guard(at)
	if _pu_on[at] == 0 or _pu_spell[at] != spell or _pu_tag[at] != tag:
		return
	_pulse_strike(at)
	if done and _pu_on[at] != 0 and _pu_spell[at] == spell and _pu_tag[at] == tag:
		_end_pulse(at, true)


## The shots of other teams inside ring `at`: deflected outward from its centre (`deflect`), else
## stopped while its shield has charges.
func _pulse_guard(at: int) -> void:
	var spell: CompiledSpell = _pu_spell[at]
	var deflects: bool = spell.behaviour(ModifierBase.Behaviour.DEFLECT) > 0.0
	if (not deflects and _pu_shield[at] <= 0) or _pu_radius[at] <= 0.0:
		return
	var centre: Vector2 = _pu_centre[at]
	var found: int = kit.projectiles.shots_in_wedge(_pu_actor[at], centre, _pu_dir[at], 1, -PI, PI, _pu_radius[at])
	_pu_shield[at] = kit.guard(found, _pu_actor[at], _pu_tag[at], deflects, _pu_shield[at], centre, Vector2.INF, id())


## Ring `at`'s edge (its radius and half its width): it strikes each body it reaches that it has
## not struck yet, outward from its centre (`Spells._strike`), and keeps what it hit with.
func _pulse_strike(at: int) -> void:
	var spell: CompiledSpell = _pu_spell[at]
	var reach: float = _pu_radius[at] + spell.radius * 0.5
	if reach <= 0.0:
		return
	var tag: int = _pu_tag[at]
	var source: Node = _pu_source[at] if is_instance_valid(_pu_source[at]) else null
	var walls: bool = spell.behaviour(ModifierBase.Behaviour.GHOST) <= 0.0
	var found: int = kit.projectiles.sweep(_pu_actor[at], _pu_centre[at], _pu_dir[at], 1, -PI, PI, reach, SpellRuntime.HITS, source, walls)
	if found == 0:
		return
	var took: HitProfile = kit.strike(spell, tag, _pu_actor[at], found, _pu_struck[at], _pu_centre[at], _pu_chain[at], _pu_prev[at], _pu_hit[at])
	if _pu_on[at] != 0 and _pu_spell[at] == spell and _pu_tag[at] == tag:
		_pu_hit[at] = took


## Ring `at` is over. With `finished` (its life is out, or it is home), its `blast` and `on expire`
## payload happen at its centre, the payload along the way it was cast; one ended early ends
## quietly. The row is off before either, so what they set off may start a ring in it.
func _end_pulse(at: int, finished: bool) -> void:
	if _pu_on[at] == 0:
		return
	_pu_on[at] = 0
	var spell: CompiledSpell = _pu_spell[at]
	var tag: int = _pu_tag[at]
	var actor: int = _pu_actor[at]
	var centre: Vector2 = _pu_centre[at]
	var way: Vector2 = _pu_dir[at]
	_pu_spell[at] = null
	_pu_source[at] = null
	_pu_hit[at] = null
	_pu_struck[at].clear()
	if finished and spell != null:
		kit.blast(spell, tag, actor, centre)
		if spell.fires_on(TriggerBase.Event.EXPIRE):
			kit.fire_payloads(spell, TriggerBase.Event.EXPIRE, tag, actor, centre, way, null)
	kit.shot_ended(tag)


## Makes room for `size` ring rows (the new ones off, each with its own struck list).
func _grow_pulses(size: int) -> void:
	var old: int = _pu_on.size()
	_pu_on.resize(size)
	_pu_born.resize(size)
	_pu_spell.resize(size)
	_pu_source.resize(size)
	_pu_tag.resize(size)
	_pu_actor.resize(size)
	_pu_caster.resize(size)
	_pu_caster_seq.resize(size)
	_pu_centre.resize(size)
	_pu_dir.resize(size)
	_pu_radius.resize(size)
	_pu_age.resize(size)
	_pu_home.resize(size)
	_pu_chain.resize(size)
	_pu_prev.resize(size)
	_pu_hit.resize(size)
	_pu_shield.resize(size)
	for i in range(old, size):
		_pu_struck.append([])


## Where ring `at` is (its centre) while it is the ring born `born`: where its timer and `on hurt`
## payloads leave from; INF once it has ended.
func tip_of(at: int, born: int) -> Vector2:
	return _pu_centre[at] if at >= 0 and at < _pu_on.size() and _pu_on[at] != 0 and _pu_born[at] == born else Vector2.INF


## Ends the rings of `tag` quietly (a revoked build, a hold switched off).
func end_of(tag: int) -> void:
	for at in _pu_on.size():
		if _pu_on[at] != 0 and _pu_tag[at] == tag:
			_end_pulse(at, false)


## Every ring gone at once, quietly (`Spells.clear`).
func clear() -> void:
	_pu_on.fill(0)
	_pu_spell.fill(null)
	_pu_source.fill(null)
	_pu_hit.fill(null)
	for at in _pu_struck.size():
		_pu_struck[at].clear()


## The rings of `actor` end quietly (its caster closed).
func end_actor(actor: int) -> void:
	for at in _pu_on.size():
		if _pu_on[at] != 0 and _pu_actor[at] == actor:
			_end_pulse(at, false)


## Runs every live ring on by `delta` (one started meanwhile, by a payload, waits for the next). Its
## strikes are cast by what cast it, as a slam's (a pull on its hit moves that); a shot that cast it
## and has ended leaves a point.
func step(delta: float) -> void:
	var first_new: int = _pu_next_born
	for at in _pu_on.size():
		if _pu_on[at] != 0 and _pu_born[at] < first_new:
			if _pu_caster[at] >= 0 and kit.live_caster_shot(_pu_caster[at], _pu_caster_seq[at]) < 0:
				_pu_caster[at] = SpellRuntime.CASTER_POINT
			kit.cast_as(_pu_caster[at], _pu_caster_seq[at])
			_pulse_step(at, delta)
			kit.cast_done()


## How far it reaches (an AI's sense of it, a telegraph): as far as a plain ring grows, `speed`
## times `lifetime` (the shots' speed curve keeps the distance of its mean).
func reach_of(spell: CompiledSpell) -> float:
	return spell.speed * spell.lifetime + spell.radius * 0.5


## Live rings over every caster, and the rows, for the looks and the tests.
func pulse_count() -> int:
	return _pu_on.count(1)


func pulse_slots() -> int:
	return _pu_on.size()


func pulse_on(at: int) -> bool:
	return at >= 0 and at < _pu_on.size() and _pu_on[at] != 0


func pulse_centre(at: int) -> Vector2:
	return _pu_centre[at]


## How far ring `at` has grown now (the middle of its edge).
func pulse_radius(at: int) -> float:
	return _pu_radius[at]


## The width of ring `at`'s edge (its `radius`).
func pulse_width(at: int) -> float:
	return _pu_spell[at].radius if _pu_spell[at] != null else 0.0


func pulse_actor(at: int) -> int:
	return _pu_actor[at]


func pulse_tag(at: int) -> int:
	return _pu_tag[at]


## The colour of ring `at`'s element and its packed look kinds (`CompiledSpell.tint`, `look`).
func pulse_tint(at: int) -> Color:
	return _pu_spell[at].tint if _pu_spell[at] != null else Color.WHITE


func pulse_look(at: int) -> int:
	return _pu_spell[at].look if _pu_spell[at] != null else 0
