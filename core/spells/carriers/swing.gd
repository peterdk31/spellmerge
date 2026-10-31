class_name CarrierSwing
extends Carrier
## Melee: the staff leans back, then sweeps `arc` degrees round the hand, striking each body in
## the wedge once (`&"swing"`). Its shield and deflect guard the sweep.
##
## Its rows: the live swings, which it keeps itself (`bind` makes them), starts (`start`, from
## `shoot`), runs (`step`) and ends (`end_of`, `end_actor`). Its strikes go through the runtime as
## rays (`Spells._ray_begin`), so its cards, payloads and chains work as a shot's do; its looks read
## the `swing_*` getters (`CarrierSwing.of(spells)`).


## The live swings (melee I2, see `start`): `SpellLimits.SWING_ROWS_START` rows at first,
## more when every one is on (no swing ends another); `_sw_on` says which are in use. Each keeps what a beam keeps for its hits (fires, chain, echo, its
## caster) and its sweep: the point it turns round (`_sw_origin`, the wizard's hand), the aim
## locked at the cast, which way it turns (1 clockwise on screen, -1 back), how long it has run,
## its wind-up, and how far it has turned (radians off the aim). The bodies it has struck (a list
## a swing, with where and which way; as many as it meets) are not struck by it again.
var _sw_on: PackedByteArray = PackedByteArray()
var _sw_born: PackedInt64Array = PackedInt64Array()
var _sw_next_born: int = 0
var _sw_spell: Array[CompiledSpell] = []
var _sw_source: Array[Node] = []
var _sw_tag: PackedInt64Array = PackedInt64Array()
var _sw_actor: PackedInt32Array = PackedInt32Array()
var _sw_caster: PackedInt32Array = PackedInt32Array()
var _sw_caster_seq: PackedInt64Array = PackedInt64Array()
var _sw_origin: PackedVector2Array = PackedVector2Array()
var _sw_dir: PackedVector2Array = PackedVector2Array()
var _sw_side: PackedInt32Array = PackedInt32Array()
var _sw_age: PackedFloat32Array = PackedFloat32Array()
var _sw_wind: PackedFloat32Array = PackedFloat32Array()
var _sw_turned: PackedFloat32Array = PackedFloat32Array()
var _sw_chain: PackedInt32Array = PackedInt32Array()
var _sw_prev: PackedInt64Array = PackedInt64Array()
## What swing `at` hits with when not its spell's own (an echo's, or what relay took on: it keeps
## it, as a live beam does).
var _sw_hit: Array[HitProfile] = []
## Shield charges swing `at` has left for shots its sweep touches (melee I3, `_swing_guard`).
var _sw_shield: PackedInt32Array = PackedInt32Array()
var _sw_struck: Array[Array] = []
## actor -> which way its last swing turned (the next turns the other way) and when its last sweep
## ended (a swing within SWING_CHAIN of it has no wind-up).
var _sw_last_side: PackedInt32Array = PackedInt32Array()
var _sw_last_end: PackedFloat32Array = PackedFloat32Array()
## actor -> when its last swing started: the swings of one cast (a split, a mirror) turn the same way.
var _sw_last_start: PackedFloat32Array = PackedFloat32Array()

## The staff animations its carrier plays on the caster's body.
var poses: StaffPoses = null


func id() -> StringName:
	return &"swing"



## The swings of the runtime `spells` (its bound `swing` carrier, `Spells.carrier`), for what reads
## its own getters (the looks, `ai`, the actor's mover, the tests).
static func of(spells: SpellRuntime) -> CarrierSwing:
	return spells.carrier(&"swing") as CarrierSwing


func traits() -> int:
	return HITS | LASTS | REACHES | GUARDS | SPEED | SHOTS | SPREAD | REPEATS_HELD | OWN_POSE | MEETS_SHOTS


func step_order() -> int:
	return 4


func required_fields() -> Dictionary:
	return {
		"ray_length": "A swing needs a `ray_length` (its reach) above 0.",
		"arc": "A swing needs an `arc` (degrees it sweeps) above 0.",
	}


func hit_kind() -> StringName:
	return &"swing"


## Makes this carrier's rows for `runtime`, which casts it.
func bind(runtime_kit: CarrierKit, staff_poses: StaffPoses) -> void:
	super(runtime_kit, staff_poses)
	poses = staff_poses
	_sw_last_side.resize(SpellRuntime.ACTORS)
	_sw_last_end.resize(SpellRuntime.ACTORS)
	_sw_last_start.resize(SpellRuntime.ACTORS)
	_grow_swings(SpellLimits.SWING_ROWS_START)
	clear()


## Every swing gone at once, quietly, and no actor has swung (`Spells.clear`).
## The swarm promoted a body (`Carrier.replace_body`): a sweep that struck `old` has struck `new`.
func replace_body(old: Node, new: Node) -> void:
	_replace_in_rows(old, new, _sw_struck, _sw_prev)


func clear() -> void:
	_sw_on.fill(0)
	_sw_spell.fill(null)
	_sw_source.fill(null)
	_sw_hit.fill(null)
	for at in _sw_struck.size():
		_sw_struck[at].clear()
	_sw_last_side.fill(-1)
	_sw_last_end.fill(-INF)
	_sw_last_start.fill(-INF)


## `actor` has not swung (a caster opened or closed under its id).
func reset_actor(actor: int) -> void:
	_sw_last_side[actor] = -1
	_sw_last_end[actor] = -INF
	_sw_last_start[actor] = -INF


## The swings of `actor` end quietly (its caster closed).
func end_actor(actor: int) -> void:
	for at in _sw_on.size():
		if _sw_on[at] != 0 and _sw_actor[at] == actor:
			_end_swing(at, false)


## Where the tip of swing `at` is now, while it is the swing born `born` (a live carrier's place,
## for its timer and `on hurt` payloads); INF once it has ended.
func tip_of(at: int, born: int) -> Vector2:
	return swing_tip(at) if _sw_on[at] != 0 and _sw_born[at] == born else Vector2.INF


## A swing (`swing` carrier, melee I2; docs/milestones/M2-staffs.md, "Phase I: melee"): the staff
## leans back for the carrier's `wind_up`, then sweeps its `arc` round the wizard's hand in its
## `lifetime`, out to its `ray_length`, centred on the aim locked now. Each step it strikes every
## body in the wedge it turned through since the last step (`Projectiles.sweep`), so a fast
## sweep misses nothing, and each body once; its hits carry payloads and chains as a beam's do.
## Swings turn clockwise and back by turns, and one cast within SWING_CHAIN of the last sweep's
## end has no wind-up. It is held by its caster as a beam is: the wizard's hand (`set_aim`), the
## shot that cast it, or a fixed point. Its `blast` and `on expire` happen at the end of the arc.
## Returns false when it could not start (no direction). `caster` and `caster_seq` are who casts it (`Spells._caster`:
## the wizard, a point or a shot), `echoed` whether it is an echo's firing (half damage).
func start(spell: CompiledSpell, tag: int, actor: int, origin: Vector2, heading: Vector2, chain: int, prev: int, source: Node, caster: int, caster_seq: int, echoed: bool) -> bool:
	if not heading.is_finite() or heading.is_zero_approx() or not origin.is_finite():
		return false
	# A free row, or new rows when every one is on: no swing ends another.
	var at: int = _sw_on.find(0)
	if at < 0:
		at = _sw_on.size()
		_grow_swings(at * 2)
	var side: int = 1
	var wind: float = maxf(spell.wind_up, 0.0)
	var mine: bool = actor >= 0 and actor < SpellRuntime.ACTORS
	# The first swing of a cast is the body's; the others of the same cast (a split, a mirror) turn
	# the same way and move no body of their own.
	var first: bool = true
	if mine:
		first = _sw_last_start[actor] != kit.clock()
		side = -_sw_last_side[actor] if first else _sw_last_side[actor]
		_sw_last_side[actor] = side
		_sw_last_start[actor] = kit.clock()
		if kit.clock() - _sw_last_end[actor] <= SpellLimits.SWING_CHAIN:
			wind = 0.0
	var half: float = deg_to_rad(spell.arc) * 0.5
	_sw_on[at] = 1
	_sw_born[at] = _sw_next_born
	_sw_next_born += 1
	_sw_spell[at] = spell
	_sw_source[at] = source
	_sw_tag[at] = tag
	_sw_actor[at] = actor
	_sw_caster[at] = caster
	_sw_caster_seq[at] = caster_seq
	_sw_origin[at] = origin
	_sw_dir[at] = heading.normalized()
	_sw_side[at] = side
	_sw_age[at] = 0.0
	_sw_wind[at] = wind
	_sw_turned[at] = -(half + deg_to_rad(SpellLimits.SWING_LEAN))
	_sw_chain[at] = chain
	_sw_prev[at] = prev
	_sw_hit[at] = spell.echo_hit if echoed else null
	_sw_shield[at] = roundi(spell.behaviour(ModifierBase.Behaviour.SHIELD))
	_sw_struck[at].clear()
	if caster == SpellRuntime.CASTER_WIZARD:
		if mine and kit.aim_pivot(actor).is_finite():
			_sw_origin[at] = kit.aim_pivot(actor)
		if mine and first:
			poses.start(actor, spell, tag, wind, maxf(spell.lifetime, 0.001), _sw_dir[at], side, true)
	elif kit.live_caster_shot(caster, caster_seq) < 0:
		_sw_caster[at] = SpellRuntime.CASTER_POINT
	kit.shot_started(tag)
	_swing_step(at, 0.0)
	if _sw_on[at] != 0:
		kit.live_join(spell, tag, SpellRuntime.LC_ROW, at, _sw_born[at], true, wind + spell.lifetime, swing_tip(at), _sw_dir[at])
	return true


## Runs swing `at` on by `delta`: where its caster holds it, then, past its wind-up, its sweep.
func _swing_step(at: int, delta: float) -> void:
	_sw_age[at] += delta
	_swing_follow(at)
	if _sw_on[at] == 0:
		return
	var spell: CompiledSpell = _sw_spell[at]
	var into: float = _sw_age[at] - _sw_wind[at]
	if into < 0.0:
		return
	var tag: int = _sw_tag[at]
	var sweep: float = maxf(spell.lifetime, 0.001)
	var half: float = deg_to_rad(spell.arc) * 0.5
	var lean: float = half + deg_to_rad(SpellLimits.SWING_LEAN)
	var turned: float = lerpf(-lean, lean, swing_ease(clampf(into / sweep, 0.0, 1.0)))
	var from: float = maxf(_sw_turned[at], -half)
	var to: float = minf(turned, half)
	_sw_turned[at] = turned
	# Its guard is a parry: every step of its sweep (the blade leans past its arc at both ends, so it
	# is in it only a step or so), its whole arc meets shots, a step ahead too, so a small fast shot
	# (an atom crosses its reach in a step or two) is met whenever it comes in while the swing
	# sweeps. Its strikes stay with the blade.
	_swing_guard(at, -half, half, delta)
	if _sw_on[at] == 0 or _sw_spell[at] != spell or _sw_tag[at] != tag:
		return
	if to >= from:
		_swing_cast(at, from, to)
	if into >= sweep and _sw_on[at] != 0 and _sw_spell[at] == spell and _sw_tag[at] == tag:
		_end_swing(at, true)


## How far through its turn a sweep is, `x` of its time gone: slow, fast, slow (the playground's).
static func swing_ease(x: float) -> float:
	return 2.0 * x * x if x < 0.5 else 1.0 - 2.0 * (1.0 - x) * (1.0 - x)


## Puts swing `at` where its caster holds it now: the wizard's hand (a wizard with no aim any more,
## down or gone, ends it quietly), or the shot that cast it while that flies.
func _swing_follow(at: int) -> void:
	var caster: int = _sw_caster[at]
	if caster == SpellRuntime.CASTER_WIZARD:
		var actor: int = _sw_actor[at]
		if actor < 0 or actor >= SpellRuntime.ACTORS:
			return
		if kit.aim_origin(actor).is_finite():
			_sw_origin[at] = kit.aim_pivot(actor) if kit.aim_pivot(actor).is_finite() else kit.aim_origin(actor)
		elif kit.aim_seen(actor):
			_end_swing(at, false)
	elif caster >= 0:
		if kit.projectiles.is_alive(caster) and kit.projectiles.get_seq_of(caster) == _sw_caster_seq[at]:
			_sw_origin[at] = kit.projectiles.get_position_of(caster)
		else:
			_sw_caster[at] = SpellRuntime.CASTER_POINT


## Swing `at` guards from `from` to `to` radians off its aim (and `ahead` seconds of each shot's
## way): the shots of other teams in that wedge are deflected outward from the hand (`deflect`),
## else stopped while its shield has charges (melee I3).
func _swing_guard(at: int, from: float, to: float, ahead: float) -> void:
	var spell: CompiledSpell = _sw_spell[at]
	var deflects: bool = spell.behaviour(ModifierBase.Behaviour.DEFLECT) > 0.0
	if not deflects and _sw_shield[at] <= 0:
		return
	var origin: Vector2 = _sw_origin[at]
	# A step ahead too: a fast shot meets the parry before it is in the body behind it.
	var found: int = kit.projectiles.shots_in_wedge(_sw_actor[at], origin, _sw_dir[at], _sw_side[at], from, to, spell.ray_length, ahead)
	_sw_shield[at] = kit.guard(found, _sw_actor[at], _sw_tag[at], deflects, _sw_shield[at], origin, Vector2.INF, id())


## Swing `at` turned from `from` to `to` radians off its aim: it strikes each body in that wedge it
## has not struck yet (`Spells._strike`), outward from its hand, and keeps what it hit with.
func _swing_cast(at: int, from: float, to: float) -> void:
	var spell: CompiledSpell = _sw_spell[at]
	var tag: int = _sw_tag[at]
	var source: Node = _sw_source[at] if is_instance_valid(_sw_source[at]) else null
	var found: int = kit.projectiles.sweep(_sw_actor[at], _sw_origin[at], _sw_dir[at], _sw_side[at], from, to, spell.ray_length, SpellRuntime.HITS, source)
	if found == 0:
		return
	var took: HitProfile = kit.strike(spell, tag, _sw_actor[at], found, _sw_struck[at], _sw_origin[at], _sw_chain[at], _sw_prev[at], _sw_hit[at])
	# A hit handler may have ended this swing (a rebuild) or reused its row.
	if _sw_on[at] != 0 and _sw_spell[at] == spell and _sw_tag[at] == tag:
		_sw_hit[at] = took


## Swing `at` is over. With `finished` (its sweep is done), its `blast` and `on expire` payload
## happen at the end of its arc, and its caster's next swing may chain on; one ended early (a
## rebuild, its wizard down, the cap) ends quietly.
func _end_swing(at: int, finished: bool) -> void:
	if _sw_on[at] == 0:
		return
	_sw_on[at] = 0
	var spell: CompiledSpell = _sw_spell[at]
	var tag: int = _sw_tag[at]
	var actor: int = _sw_actor[at]
	_sw_spell[at] = null
	_sw_source[at] = null
	_sw_hit[at] = null
	_sw_struck[at].clear()
	if finished and spell != null:
		if actor >= 0 and actor < SpellRuntime.ACTORS:
			_sw_last_end[actor] = kit.clock()
		var end: Vector2 = swing_end_point(_sw_origin[at], _sw_dir[at], _sw_side[at], spell.arc, spell.ray_length)
		end = kit.projectiles.clip_to_walls(_sw_origin[at], end)
		kit.blast(spell, tag, actor, end)
		if spell.fires_on(TriggerBase.Event.EXPIRE):
			kit.fire_payloads(spell, TriggerBase.Event.EXPIRE, tag, actor, end, _sw_dir[at], null)
	kit.shot_ended(tag)


## The end point of a swing round `origin` aimed along `direction`, turning `side` through `arc`
## degrees out to `reach`: where its arc ends.
static func swing_end_point(origin: Vector2, direction: Vector2, side: int, arc: float, reach: float) -> Vector2:
	return origin + direction.normalized().rotated(deg_to_rad(arc) * 0.5 * (1.0 if side >= 0 else -1.0)) * reach


## Where the tip of swing `at`'s staff is now: on its arc as far as it has turned (leaning back
## before its sweep), `ray_length` out.
func swing_tip(at: int) -> Vector2:
	var half: float = deg_to_rad(swing_arc(at)) * 0.5
	var turned: float = clampf(_sw_turned[at], -half, half) * (1.0 if _sw_side[at] >= 0 else -1.0)
	return _sw_origin[at] + _sw_dir[at].rotated(turned) * swing_reach(at)


## Makes room for `size` swing rows (the new ones off, each with its own struck list).
func _grow_swings(size: int) -> void:
	var old: int = _sw_on.size()
	_sw_on.resize(size)
	_sw_born.resize(size)
	_sw_spell.resize(size)
	_sw_source.resize(size)
	_sw_tag.resize(size)
	_sw_actor.resize(size)
	_sw_caster.resize(size)
	_sw_caster_seq.resize(size)
	_sw_origin.resize(size)
	_sw_dir.resize(size)
	_sw_side.resize(size)
	_sw_age.resize(size)
	_sw_wind.resize(size)
	_sw_turned.resize(size)
	_sw_chain.resize(size)
	_sw_prev.resize(size)
	_sw_hit.resize(size)
	_sw_shield.resize(size)
	for i in range(old, size):
		_sw_struck.append([])


## Ends the swings of `tag` quietly (a revoked build, a hold switched off).
func end_of(tag: int) -> void:
	for at in _sw_on.size():
		if _sw_on[at] != 0 and _sw_tag[at] == tag:
			_end_swing(at, false)


## Runs every live swing on by `delta` (one started meanwhile, by a payload, waits for the next).
func step(delta: float) -> void:
	var first_new: int = _sw_next_born
	for at in _sw_on.size():
		if _sw_on[at] != 0 and _sw_born[at] < first_new:
			_swing_step(at, delta)


## The live swings, for their look (`gameplay/feel`): `swing_slots()` rows, each on or off. A
## swing on turns round `swing_origin` from `swing_dir` (the aim locked at the cast), `swing_side`
## 1 clockwise on screen or -1 back; `swing_turned` is how far it has turned (radians, from minus
## to plus half its `swing_arc` and SWING_LEAN past; it waits at the start through its wind-up),
## out to `swing_reach`.
func swing_slots() -> int:
	return _sw_on.size()


func swing_on(at: int) -> bool:
	return at >= 0 and at < _sw_on.size() and _sw_on[at] != 0


func swing_actor(at: int) -> int:
	return _sw_actor[at]


func swing_tag(at: int) -> int:
	return _sw_tag[at]


func swing_origin(at: int) -> Vector2:
	return _sw_origin[at]


func swing_dir(at: int) -> Vector2:
	return _sw_dir[at]


func swing_side(at: int) -> int:
	return _sw_side[at]


func swing_turned(at: int) -> float:
	return _sw_turned[at]


func swing_arc(at: int) -> float:
	return _sw_spell[at].arc if _sw_spell[at] != null else 0.0


func swing_reach(at: int) -> float:
	return _sw_spell[at].ray_length if _sw_spell[at] != null else 0.0


## Which swing row `at` holds: a number no other swing had, so its look knows a new swing in a
## row used again.
func swing_born(at: int) -> int:
	return _sw_born[at]


## Seconds swing `at` has run (its wind-up first), its wind-up and its sweep.
func swing_age(at: int) -> float:
	return _sw_age[at]


func swing_wind(at: int) -> float:
	return _sw_wind[at]


func swing_sweep(at: int) -> float:
	return maxf(_sw_spell[at].lifetime, 0.001) if _sw_spell[at] != null else 0.001


## The tint and packed look kinds of swing `at` (`CompiledSpell.tint`, `look`), so it shows its cards.
func swing_tint(at: int) -> Color:
	return _sw_spell[at].tint if _sw_spell[at] != null else Color.WHITE


func swing_look(at: int) -> int:
	return _sw_spell[at].look if _sw_spell[at] != null else 0


## Live swings over every caster.
func swing_count() -> int:
	return _sw_on.count(1)


## A swing of its own along `heading`, cast by whoever casts this launch (`Spells._caster`).
func shoot(spell: CompiledSpell, tag: int, actor: int, origin: Vector2, _direction: Vector2, heading: Vector2, _n: int, _count: int, source: Node, _lifetime: float, chain: int, prev: int) -> int:
	return 1 if start(spell, tag, actor, origin, heading, chain, prev, source, kit.caster(), kit.caster_seq(), kit.is_echo(spell)) else 0


func reach_of(spell: CompiledSpell) -> float:
	return spell.ray_length


## A held swing is switched off: it ends quietly.
func switch_off(tag: int) -> void:
	end_of(tag)
