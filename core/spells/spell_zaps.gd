class_name SpellZaps
extends Object
## The arcs and the magnets (core/spells/spells.gd): a zapping shot's rolls for the bodies near it,
## its zaps waiting and made (`_step_zaps`, `_zap`, `_zap_ray`) and its sparks, and a magnet's pull
## on the shots round it (`_step_magnets`). Methods working on the runtime (`rt`), whose members
## hold all of it (core/README.md, "The spell runtime").

const Runtime := preload("res://core/spells/spells.gd")

## Not state (core/sim/README.md): the runtime, the other jobs this one calls and the runtime's
## arrays it works on, each the runtime's own (shared, never a copy), linked by `link`.
const DERIVED: Array[StringName] = [&"rt", &"_job_fires", &"_job_launches", &"_job_strikes", &"_profiles", &"_rec_chain", &"_rec_prev", &"_zappers", &"_rec_zapper", &"_rec_zap_rolls", &"_rec_zapped", &"_rec_zapped_at", &"_rec_zapped_count", &"_rec_due_body", &"_rec_due_at", &"_rec_due_count", &"_zap_near", &"_zap_centres", &"_zap_radii", &"_magnets", &"_rec_magnet", &"_rec_zap"]

var rt: Runtime = null
var _job_fires: SpellFires = null
var _job_launches: SpellLaunches = null
var _job_strikes: SpellStrikes = null
var _profiles: Dictionary
var _rec_chain: PackedInt32Array
var _rec_prev: PackedInt64Array
var _zappers: PackedInt32Array
var _rec_zapper: PackedByteArray
var _rec_zap_rolls: PackedInt32Array
var _rec_zapped: PackedInt64Array
var _rec_zapped_at: PackedFloat64Array
var _rec_zapped_count: PackedInt32Array
var _rec_due_body: Array[Node2D]
var _rec_due_at: PackedFloat64Array
var _rec_due_count: PackedInt32Array
var _zap_near: Array[Node2D]
var _zap_centres: PackedVector2Array
var _zap_radii: PackedFloat32Array
var _magnets: PackedInt32Array
var _rec_magnet: PackedByteArray
var _rec_zap: Array[HitProfile]


## Takes the runtime's arrays and jobs, by the names in DERIVED: again whenever the runtime's
## arrays may have been replaced (`SpellRuntime._link_jobs`).
func link(runtime: Runtime) -> void:
	rt = runtime
	for name: StringName in DERIVED:
		if name != &"rt":
			set(name, runtime.get(name))


## Runs the `zap` shots (half of them each step, SpellLimits.ZAP_EVERY): each body of another team
## that has come within a shot's reach since it last looked rolls the shot's chance, once, and on a
## win is zapped (`_zap`) at a random moment while it is in reach (`_zap_window`), the body the
## shot is about to hit too (owner, 2026-10-30); a waiting zap whose body left the reach is made
## as it leaves. At most `SpellLimits.MAX_ZAPS_PER_STEP` zaps a step; a body over the cap rolls in
## a later step. A shot with no body in reach now and then throws a spark into the air (`_spark`).
func _step_zaps(delta: float) -> void:
	var projectiles: Runtime.ProjectilesScript = rt.projectiles
	var _clock: float = rt._clock
	rt._zap_steps += 1
	var i: int = 0
	while i < rt._zapper_count:
		var slot: int = _zappers[i]
		if not rt._knows(slot):
			_rec_zapper[slot] = 0
			_drop_zaps(slot)
			rt._zapper_count -= 1
			_zappers[i] = _zappers[rt._zapper_count]
			continue
		i += 1
		if (slot + rt._zap_steps) % SpellLimits.ZAP_EVERY != 0:
			continue
		var tag: int = projectiles.get_tag_of(slot)
		var spell: CompiledSpell = _profiles.get(tag)
		if spell == null or spell.zap_chance <= 0.0:
			continue
		# A shot that is going (`Carrier.active_left`) zaps nothing: its waiting zaps are dropped.
		if _active_left(slot, spell) <= 0.0:
			_drop_zaps(slot)
			continue
		var at: Vector2 = projectiles.get_position_of(slot)
		var near: int = projectiles.targets_near(at, spell.zap_reach, Runtime.HITS, rt._team(SpellTag.caster_of(tag)), _zap_near, _zap_centres, _zap_radii)
		_zaps_due(slot, spell, near)
		if near == 0 and _rec_due_count[slot] == 0:
			if rt._zaps_used < SpellLimits.MAX_ZAPS_PER_STEP and _zap_roll(slot) < SpellLimits.ZAP_SPARKS * delta * SpellLimits.ZAP_EVERY:
				_spark(slot, spell)
			continue
		for k in near:
			if rt._zaps_used >= SpellLimits.MAX_ZAPS_PER_STEP or not rt._knows(slot):
				break
			var body: Node2D = _zap_near[k]
			var key: int = projectiles.key_of(body)
			if key == 0 or _has_rolled(slot, key):
				continue
			if _zap_roll(slot) >= spell.zap_chance:
				_rolled(slot, key, _clock)
			else:
				# It waits a random moment of the time the body stays in reach, less a look's step so
				# it is made before the shot hits it or leaves it; it rolls again ZAP_AGAIN after.
				var window: float = _zap_window(slot, spell, _zap_centres[k], _zap_radii[k])
				var wait: float = _zap_roll(slot) * maxf(window - delta * SpellLimits.ZAP_EVERY, 0.0)
				_rolled(slot, key, _clock + wait)
				if wait <= 0.0 or _rec_due_count[slot] >= Runtime.ZAP_DUE:
					_zap(slot, spell, _zap_centres[k])
				else:
					var n: int = slot * Runtime.ZAP_DUE + _rec_due_count[slot]
					_rec_due_body[n] = body
					_rec_due_at[n] = _clock + wait
					_rec_due_count[slot] += 1


## Makes the waiting zaps of the shot in `slot` that are due, or whose body has left its reach (made
## as it leaves); a body gone from the world is dropped. `near` bodies are in reach now (`_zap_near`).
func _zaps_due(slot: int, spell: CompiledSpell, near: int) -> void:
	var _clock: float = rt._clock
	var first: int = slot * Runtime.ZAP_DUE
	var n: int = 0
	while n < _rec_due_count[slot]:
		if rt._zaps_used >= SpellLimits.MAX_ZAPS_PER_STEP or not rt._knows(slot):
			return
		var body: Node2D = _rec_due_body[first + n]
		var k: int = _zap_near.find(body) if is_instance_valid(body) else -1
		var gone: bool = not is_instance_valid(body)
		if gone or k < 0 or k >= near or _clock >= _rec_due_at[first + n]:
			if not gone:
				# In reach: at its hit circle; just out of it: where it stands.
				_zap(slot, spell, _zap_centres[k] if k >= 0 and k < near else body.global_position)
			# Take it off the list: the last one fills its place.
			var last: int = first + _rec_due_count[slot] - 1
			_rec_due_body[first + n] = _rec_due_body[last]
			_rec_due_at[first + n] = _rec_due_at[last]
			_rec_due_body[last] = null
			_rec_due_count[slot] -= 1
			continue
		n += 1


## Seconds the body whose hit circle is at `centre`, `radius` big, stays in the reach of the zap shot
## in `slot`, as the shot flies on now: until the shot hits it, if it is on its way, else until the
## shot has passed through its reach; at most until it starts to go (`_active_left`) and
## SpellLimits.ZAP_WAIT_MOST (a shot
## that stands still: the most).
func _zap_window(slot: int, spell: CompiledSpell, centre: Vector2, radius: float) -> float:
	var projectiles: Runtime.ProjectilesScript = rt.projectiles
	var velocity: Vector2 = projectiles.get_velocity_of(slot)
	var speed: float = velocity.length()
	if speed < 1.0:
		return SpellLimits.ZAP_WAIT_MOST
	var way: Vector2 = velocity / speed
	var to: Vector2 = centre - projectiles.get_position_of(slot)
	var along: float = to.dot(way)
	var across: float = absf(to.cross(way))
	var touch: float = projectiles.get_radius_of(slot) + radius
	var seconds: float = 0.0
	if along > 0.0 and across < touch:
		seconds = (along - touch) / speed
	else:
		var reach: float = spell.zap_reach + radius
		seconds = (along + sqrt(maxf(reach * reach - across * across, 0.0))) / speed
	return clampf(minf(seconds, _active_left(slot, spell)), 0.0, SpellLimits.ZAP_WAIT_MOST)


## Seconds the shot in `slot` of `spell` may still act before it starts to go (its carrier's
## `Carrier.active_left`: its life left, less its fade): what anything it times waits within.
func _active_left(slot: int, spell: CompiledSpell) -> float:
	var projectiles: Runtime.ProjectilesScript = rt.projectiles
	return _job_launches._carrier_of(spell).active_left(projectiles.get_life_of(slot), projectiles.get_span_of(slot))


## The shot in `slot` drops the zaps it has won but not made.
func _drop_zaps(slot: int) -> void:
	for n in _rec_due_count[slot]:
		_rec_due_body[slot * Runtime.ZAP_DUE + n] = null
	_rec_due_count[slot] = 0


## True when the zap shot in `slot` has rolled for the body of key `id` less than
## SpellLimits.ZAP_AGAIN ago (from its zap, or the roll it lost).
func _has_rolled(slot: int, id: int) -> bool:
	var _clock: float = rt._clock
	var first: int = slot * Runtime.ZAP_MEMORY
	for n in mini(_rec_zapped_count[slot], Runtime.ZAP_MEMORY):
		if _rec_zapped[first + n] == id and _clock - _rec_zapped_at[first + n] < SpellLimits.ZAP_AGAIN:
			return true
	return false


## The zap shot in `slot` has rolled for the body of key `id`, which is zapped (or lost its
## roll) at `when` (in a ring: past ZAP_MEMORY the oldest is forgotten).
func _rolled(slot: int, id: int, when: float) -> void:
	var n: int = _rec_zapped_count[slot]
	_rec_zapped[slot * Runtime.ZAP_MEMORY + n % Runtime.ZAP_MEMORY] = id
	_rec_zapped_at[slot * Runtime.ZAP_MEMORY + n % Runtime.ZAP_MEMORY] = when
	_rec_zapped_count[slot] = n + 1


## A random number in [0, 1) for the zap shot in `slot`: a hash of its sequence number and how many
## it drew before, so a run is the same every time (tests, replays) and no two shots alike.
func _zap_roll(slot: int) -> float:
	var n: int = _rec_zap_rolls[slot]
	_rec_zap_rolls[slot] = n + 1
	return Runtime.zap_hash(int(rt.projectiles.get_seq_of(slot)), n)


## The zap shot in `slot` throws a harmless spark into the air: a short zap's look in a random
## direction (it has no body in reach).
func _spark(slot: int, spell: CompiledSpell) -> void:
	var projectiles: Runtime.ProjectilesScript = rt.projectiles
	if rt.events == null:
		return
	var way: Vector2 = DMath.from_angle(_zap_roll(slot) * TAU)
	var length: float = lerpf(SpellLimits.ZAP_SPARK_SHORTEST, SpellLimits.ZAP_SPARK_LONGEST, _zap_roll(slot))
	rt._zaps_used += 1
	rt.events.carrier_shown.emit(SpellTag.caster_of(projectiles.get_tag_of(slot)), Runtime.ZAP_CARD, projectiles.get_position_of(slot), way, length, spell.tint, spell.look)


## Every `magnet` shot pulls the enemies within its card's reach toward where it is, each step
## (`pull_requested`; combat keeps the pull as a push that the next pull replaces); a carrier with
## rows of its own pulls with them in its `step` (a live beam toward its line). At most
## `SpellLimits.MAX_PULLS_PER_STEP` shots pull in a step; which ones rotates, so none starves.
func _step_magnets() -> void:
	var projectiles: Runtime.ProjectilesScript = rt.projectiles
	var i: int = 0
	while i < rt._magnet_count:
		var slot: int = _magnets[i]
		var spell: CompiledSpell = null
		if rt._knows(slot):
			spell = _profiles.get(projectiles.get_tag_of(slot))
		# A slot that a spent magnet shot left to a shot without the card goes off the list, too.
		if spell == null or spell.behaviour(ModifierBase.Behaviour.MAGNET) <= 0.0:
			_rec_magnet[slot] = 0
			rt._magnet_count -= 1
			_magnets[i] = _magnets[rt._magnet_count]
			continue
		i += 1
	if rt._magnet_count == 0:
		return
	var pulls: int = mini(rt._magnet_count, SpellLimits.MAX_PULLS_PER_STEP)
	for k in pulls:
		var slot: int = _magnets[(rt._magnet_from + k) % rt._magnet_count]
		var tag: int = projectiles.get_tag_of(slot)
		var spell: CompiledSpell = _profiles.get(tag)
		var at: Vector2 = projectiles.get_position_of(slot)
		rt.events.pull_requested.emit(SpellTag.caster_of(tag), at, spell.behaviour(ModifierBase.Behaviour.MAGNET), SpellLimits.MAGNET_PULL, tag, at)
	rt._magnet_from = (rt._magnet_from + pulls) % rt._magnet_count


## Shot `slot`'s zap of the body whose hit circle is at `aim`: a short ray there, hitting with its
## `zap_hit` (`hit_profile`). It is a hit of the shot like any other: it uses the shot's trigger
## fires and chain jumps, so `on hit` payloads and chains go off from the zapped body.
func _zap(slot: int, spell: CompiledSpell, aim: Vector2) -> void:
	var projectiles: Runtime.ProjectilesScript = rt.projectiles
	# It hits as the shot does: cast by what cast that shot.
	var caster: int = rt.shot_caster(slot)
	_job_launches._cast_as(caster, projectiles.get_seq_of(caster) if caster >= 0 else 0)
	_zap_ray(spell, projectiles.get_tag_of(slot), projectiles.get_position_of(slot), aim, _rec_chain[slot], _rec_prev[slot], _rec_zap[slot] if _rec_zap[slot] != null else spell.zap_hit, slot)
	_job_launches._cast_done()


## A zap of the carrier `spell` with `tag` from `at` to `aim`, with `chain` jumps left after `prev`,
## hitting with `hit`: a short ray (`_ray_begin`, marked a zap), drawn as lightning. `slot` is the
## shot zapping, or -1 for a carrier with no slot (a live beam, `CarrierBeam`).
func _zap_ray(spell: CompiledSpell, tag: int, at: Vector2, aim: Vector2, chain: int, prev: int, hit: HitProfile, slot: int) -> void:
	var actor: int = SpellTag.caster_of(tag)
	rt._zaps_used += 1
	var way: Vector2 = at.direction_to(aim) if not at.is_equal_approx(aim) else Vector2.RIGHT
	var ray: RayHit = _job_strikes._ray_begin(tag, way, chain, prev, hit, slot)
	ray.zapping = true
	var got: float = rt.projectiles.ray(actor, at, way, at.distance_to(aim) + 2.0, 0, Runtime.HITS, tag, 0.0, null)
	_job_strikes._ray_end()
	if got > 0.0 and rt.events != null:
		rt.events.carrier_shown.emit(actor, Runtime.ZAP_CARD, at, way, got, spell.tint, spell.look)
	_job_fires._cast_jumps()
