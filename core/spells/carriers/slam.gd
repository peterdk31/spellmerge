class_name CarrierSlam
extends Carrier
## Melee: the staff rises, then strikes the floor ahead and a ring grows from the impact, striking
## each body in it once (`&"slam"`). Over at once.
##
## Its rows: the live slams, which it keeps itself (`bind` makes them), starts (`start`, from
## `shoot`), runs (`step`) and ends (`end_of`, `end_actor`, `clear`). Its strikes go through the runtime as rays
## (`Spells._ray_begin`), so its cards, payloads and chains work as a shot's do; its looks read the
## `slam_*` getters (`CarrierSlam.of(spells)`).


## The live slams (melee I8, see `start`): SLAM_ROWS_START rows at first, more when every
## one is on. Each keeps what a swing keeps for its hits, the hand it is held by and the aim locked
## at the cast, how long it has run and its wind-up, where it struck (INF before the impact), its
## shield charges for shots in its ring, and the bodies its ring has struck.
var _sl_on: PackedByteArray = PackedByteArray()
var _sl_born: PackedInt64Array = PackedInt64Array()
var _sl_next_born: int = 0
var _sl_spell: Array[CompiledSpell] = []
var _sl_source: Array[Node] = []
var _sl_tag: PackedInt64Array = PackedInt64Array()
var _sl_actor: PackedInt32Array = PackedInt32Array()
var _sl_caster: PackedInt32Array = PackedInt32Array()
var _sl_caster_seq: PackedInt64Array = PackedInt64Array()
var _sl_origin: PackedVector2Array = PackedVector2Array()
var _sl_dir: PackedVector2Array = PackedVector2Array()
var _sl_impact: PackedVector2Array = PackedVector2Array()
var _sl_age: PackedFloat32Array = PackedFloat32Array()
var _sl_wind: PackedFloat32Array = PackedFloat32Array()
var _sl_chain: PackedInt32Array = PackedInt32Array()
var _sl_prev: PackedInt64Array = PackedInt64Array()
var _sl_hit: Array[HitProfile] = []
var _sl_shield: PackedInt32Array = PackedInt32Array()
var _sl_struck: Array[Array] = []

## The staff animations its carrier plays on the caster's body.
var poses: StaffPoses = null


func id() -> StringName:
	return &"slam"



## The slams of the runtime `spells` (its bound `slam` carrier, `Spells.carrier`), for what reads
## its own getters (the looks, `ai`, the actor's mover, the tests).
static func of(spells: SpellRuntime) -> CarrierSlam:
	return spells.carrier(&"slam") as CarrierSlam


func traits() -> int:
	return HITS | REACHES | GUARDS | SPEED | SHOTS | SPREAD | OWN_POSE | MEETS_SHOTS | STRIKES_POINT


func step_order() -> int:
	return 5


func required_fields() -> Dictionary:
	return {
		"ray_length": "A slam needs a `ray_length` (how far ahead it strikes) above 0.",
	}


func hit_kind() -> StringName:
	return &"burst"


## Makes this carrier's rows for `runtime`, which casts it.
func bind(runtime_kit: CarrierKit, staff_poses: StaffPoses) -> void:
	super(runtime_kit, staff_poses)
	poses = staff_poses
	_grow_slams(SpellLimits.SLAM_ROWS_START)


## A slam (`slam` carrier, melee I8; docs/milestones/M2-staffs.md, "Phase I: melee"): the staff
## rises for the carrier's `wind_up`, held by its caster as a swing is (the wizard's hand, the shot
## that cast it, or a point), with the aim locked now; then it strikes the floor `ray_length`
## ahead (short of a wall) and a ring grows from there to its `radius` over SLAM_GROW of its
## `lifetime` and holds for the rest. The ring strikes each body in it once (`Projectiles.sweep`
## all round the impact, so a wall between hides a body), outward from the impact, so the hit's
## knockback throws it outward; its caster's own body is skipped, a teammate is hit. Its hits carry
## payloads and chains as a beam's do, and a shield or deflect works on the shots in its ring. Its
## `blast` and `on expire` happen at the impact when the ring is done. `form_shown` tells looks of
## the impact (`slam`), the point it strikes (`STRIKES_POINT`): its staff animation's `land` puts the
## staff's tip there, told again at the impact (`StaffPoses.land_at`) in case its hand moved.
## Returns false when it could not start (no direction). `caster` and `caster_seq` are who casts it (`Spells._caster`:
## the wizard, a point or a shot), `echoed` whether it is an echo's firing (half damage).
func start(spell: CompiledSpell, tag: int, actor: int, origin: Vector2, heading: Vector2, chain: int, prev: int, source: Node, caster: int, caster_seq: int, echoed: bool) -> bool:
	if not heading.is_finite() or heading.is_zero_approx() or not origin.is_finite():
		return false
	var at: int = _sl_on.find(0)
	if at < 0:
		at = _sl_on.size()
		_grow_slams(at * 2)
	_sl_on[at] = 1
	_sl_born[at] = _sl_next_born
	_sl_next_born += 1
	_sl_spell[at] = spell
	_sl_source[at] = source
	_sl_tag[at] = tag
	_sl_actor[at] = actor
	_sl_caster[at] = caster
	_sl_caster_seq[at] = caster_seq
	_sl_origin[at] = origin
	_sl_dir[at] = heading.normalized()
	_sl_impact[at] = Vector2.INF
	_sl_age[at] = 0.0
	_sl_wind[at] = maxf(spell.wind_up, 0.0)
	_sl_chain[at] = chain
	_sl_prev[at] = prev
	_sl_hit[at] = spell.echo_hit if echoed else null
	_sl_shield[at] = roundi(spell.behaviour(ModifierBase.Behaviour.SHIELD))
	_sl_struck[at].clear()
	var mine: bool = actor >= 0 and actor < SpellRuntime.ACTORS
	if caster == SpellRuntime.CASTER_WIZARD:
		if mine and kit.aim_pivot(actor).is_finite():
			_sl_origin[at] = kit.aim_pivot(actor)
		if mine and poses.started_at(actor) != kit.clock():
			poses.start(actor, spell, tag, _sl_wind[at], maxf(spell.lifetime, 0.001), _sl_dir[at], StaffPoses.up_side(_sl_dir[at]), true)
	elif kit.live_caster_shot(caster, caster_seq) < 0:
		_sl_caster[at] = SpellRuntime.CASTER_POINT
	kit.shot_started(tag)
	_slam_step(at, 0.0)
	return true


## Runs slam `at` on by `delta`: held by its caster through its wind-up, then its impact and ring.
func _slam_step(at: int, delta: float) -> void:
	_sl_age[at] += delta
	var spell: CompiledSpell = _sl_spell[at]
	var tag: int = _sl_tag[at]
	if not _sl_impact[at].is_finite():
		_slam_follow(at)
		if _sl_on[at] == 0 or _sl_age[at] < _sl_wind[at]:
			return
		var impact: Vector2 = kit.projectiles.clip_to_walls(_sl_origin[at], _sl_origin[at] + _sl_dir[at] * spell.ray_length)
		_sl_impact[at] = impact
		if _sl_caster[at] == SpellRuntime.CASTER_WIZARD:
			poses.land_at(tag, impact - _sl_origin[at])
		if kit.events != null:
			kit.events.form_shown.emit(_sl_actor[at], &"slam", impact, _sl_dir[at], spell.radius, spell.tint, spell.look)
	var into: float = _sl_age[at] - _sl_wind[at]
	var life: float = maxf(spell.lifetime, 0.001)
	var reach: float = spell.radius * clampf(into / (life * SpellLimits.SLAM_GROW), 0.0, 1.0)
	_slam_guard(at, reach)
	if _sl_on[at] == 0 or _sl_spell[at] != spell or _sl_tag[at] != tag:
		return
	_slam_cast(at, reach)
	if into >= life and _sl_on[at] != 0 and _sl_spell[at] == spell and _sl_tag[at] == tag:
		_end_slam(at, true)


## Puts slam `at` where its caster holds it now, until it strikes (as `_swing_follow`).
func _slam_follow(at: int) -> void:
	var caster: int = _sl_caster[at]
	if caster == SpellRuntime.CASTER_WIZARD:
		var actor: int = _sl_actor[at]
		if actor < 0 or actor >= SpellRuntime.ACTORS:
			return
		if kit.aim_origin(actor).is_finite():
			_sl_origin[at] = kit.aim_pivot(actor) if kit.aim_pivot(actor).is_finite() else kit.aim_origin(actor)
		elif kit.aim_seen(actor):
			_end_slam(at, false)
	elif caster >= 0:
		if kit.projectiles.is_alive(caster) and kit.projectiles.get_seq_of(caster) == _sl_caster_seq[at]:
			_sl_origin[at] = kit.projectiles.get_position_of(caster)
		else:
			_sl_caster[at] = SpellRuntime.CASTER_POINT


## The shots of other teams in slam `at`'s ring (`reach` across now): deflected outward from the
## impact (`deflect`), else stopped while its shield has charges (melee I3).
func _slam_guard(at: int, reach: float) -> void:
	var spell: CompiledSpell = _sl_spell[at]
	var deflects: bool = spell.behaviour(ModifierBase.Behaviour.DEFLECT) > 0.0
	if (not deflects and _sl_shield[at] <= 0) or reach <= 0.0:
		return
	var impact: Vector2 = _sl_impact[at]
	var found: int = kit.projectiles.shots_in_wedge(_sl_actor[at], impact, _sl_dir[at], 1, -PI, PI, reach)
	_sl_shield[at] = kit.guard(found, _sl_actor[at], _sl_tag[at], deflects, _sl_shield[at], impact, Vector2.INF, id())


## Slam `at`'s ring, `reach` across now: it strikes each body in it it has not struck yet, outward
## from the impact (`Spells._strike`), and keeps what it hit with.
func _slam_cast(at: int, reach: float) -> void:
	if reach <= 0.0:
		return
	var spell: CompiledSpell = _sl_spell[at]
	var tag: int = _sl_tag[at]
	var source: Node = _sl_source[at] if is_instance_valid(_sl_source[at]) else null
	var found: int = kit.projectiles.sweep(_sl_actor[at], _sl_impact[at], _sl_dir[at], 1, -PI, PI, reach, SpellRuntime.HITS, source)
	if found == 0:
		return
	var took: HitProfile = kit.strike(spell, tag, _sl_actor[at], found, _sl_struck[at], _sl_impact[at], _sl_chain[at], _sl_prev[at], _sl_hit[at])
	if _sl_on[at] != 0 and _sl_spell[at] == spell and _sl_tag[at] == tag:
		_sl_hit[at] = took


## Slam `at` is over. With `finished` (its ring is done), its `blast` and `on expire` payload happen
## at the impact, the payload along the slam's aim; one ended early ends quietly.
func _end_slam(at: int, finished: bool) -> void:
	if _sl_on[at] == 0:
		return
	_sl_on[at] = 0
	var spell: CompiledSpell = _sl_spell[at]
	var tag: int = _sl_tag[at]
	var actor: int = _sl_actor[at]
	var impact: Vector2 = _sl_impact[at]
	_sl_spell[at] = null
	_sl_source[at] = null
	_sl_hit[at] = null
	_sl_struck[at].clear()
	if finished and spell != null and impact.is_finite():
		kit.blast(spell, tag, actor, impact)
		if spell.payload != null and spell.trigger_event == TriggerBase.Event.EXPIRE:
			kit.fire_payload(spell, tag, actor, impact, _sl_dir[at], null)
	kit.shot_ended(tag)


## Makes room for `size` slam rows (the new ones off, each with its own struck list).
func _grow_slams(size: int) -> void:
	var old: int = _sl_on.size()
	_sl_on.resize(size)
	_sl_born.resize(size)
	_sl_spell.resize(size)
	_sl_source.resize(size)
	_sl_tag.resize(size)
	_sl_actor.resize(size)
	_sl_caster.resize(size)
	_sl_caster_seq.resize(size)
	_sl_origin.resize(size)
	_sl_dir.resize(size)
	_sl_impact.resize(size)
	_sl_age.resize(size)
	_sl_wind.resize(size)
	_sl_chain.resize(size)
	_sl_prev.resize(size)
	_sl_hit.resize(size)
	_sl_shield.resize(size)
	for i in range(old, size):
		_sl_struck.append([])


## Ends the slams of `tag` quietly (a revoked build, a hold switched off).
func end_of(tag: int) -> void:
	for at in _sl_on.size():
		if _sl_on[at] != 0 and _sl_tag[at] == tag:
			_end_slam(at, false)


## Every slam gone at once, quietly (`Spells.clear`).
## The swarm promoted a body (`Carrier.replace_body`): a ring that struck `old` has struck `new`.
func replace_body(old: Node, new: Node) -> void:
	_replace_in_rows(old, new, _sl_struck, _sl_prev)


func clear() -> void:
	_sl_on.fill(0)
	_sl_spell.fill(null)
	_sl_source.fill(null)
	_sl_hit.fill(null)
	for at in _sl_struck.size():
		_sl_struck[at].clear()


## The slams of `actor` end quietly (its caster closed).
func end_actor(actor: int) -> void:
	for at in _sl_on.size():
		if _sl_on[at] != 0 and _sl_actor[at] == actor:
			_end_slam(at, false)

## Runs every live slam on by `delta` (one started meanwhile, by a payload, waits for the next).
func step(delta: float) -> void:
	var first_new: int = _sl_next_born
	for at in _sl_on.size():
		if _sl_on[at] != 0 and _sl_born[at] < first_new:
			_slam_step(at, delta)


## Live slams over every caster, and whether row `at` is one, for tests.
func slam_count() -> int:
	return _sl_on.count(1)


func slam_slots() -> int:
	return _sl_on.size()


func slam_on(at: int) -> bool:
	return at >= 0 and at < _sl_on.size() and _sl_on[at] != 0


## Where slam `at` struck (INF while it winds up).
func slam_impact(at: int) -> Vector2:
	return _sl_impact[at]


## A slam of its own along `heading`, cast by whoever casts this launch (`Spells._caster`).
func shoot(spell: CompiledSpell, tag: int, actor: int, origin: Vector2, _direction: Vector2, heading: Vector2, _n: int, _count: int, source: Node, _lifetime: float, chain: int, prev: int) -> int:
	return 1 if start(spell, tag, actor, origin, heading, chain, prev, source, kit.caster(), kit.caster_seq(), kit.is_echo(spell)) else 0


func reach_of(spell: CompiledSpell) -> float:
	return spell.ray_length + spell.radius
