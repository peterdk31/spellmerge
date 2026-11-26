class_name SpellFires
extends Object
## What fires later (core/spells/spells.gd): the launches that wait for their time (`_delay`,
## `_run_pending`: a burst's later firings, an echo), a trigger's payload fired and paced by its
## budget (`_fire`, `_run_waiting_fires`), an event's payloads (`_fire_event`), and the chain jumps
## that wait their turn (`_cast_jumps`). Methods working on the runtime (`rt`), whose members hold
## all of it (core/README.md, "The spell runtime").

const Runtime := preload("res://core/spells/spells.gd")

## Not state (core/sim/README.md): the runtime, the other jobs this one calls and the runtime's
## arrays it works on, each the runtime's own (shared, never a copy), linked by `link`.
const DERIVED: Array[StringName] = [&"rt", &"_job_generations", &"_job_launches", &"_job_strikes", &"_current", &"_hold_tags", &"_profiles", &"_fires_used", &"_pending", &"_pending_free", &"_aim_dir"]

var rt: Runtime = null
var _job_generations: SpellGenerations = null
var _job_launches: SpellLaunches = null
var _job_strikes: SpellStrikes = null
var _current: PackedInt32Array
var _hold_tags: Array[PackedInt64Array]
var _profiles: Dictionary
var _fires_used: PackedInt32Array
var _pending: Array[Runtime.PendingLaunch]
var _pending_free: Array[Runtime.PendingLaunch]
var _aim_dir: PackedVector2Array


## Takes the runtime's arrays and jobs, by the names in DERIVED: again whenever the runtime's
## arrays may have been replaced (`SpellRuntime._link_jobs`).
func link(runtime: Runtime) -> void:
	rt = runtime
	for name: StringName in DERIVED:
		if name != &"rt":
			set(name, runtime.get(name))


## Queues a launch `wait` seconds from now: `group` (a burst's later firing) or, with no group,
## `spell` (an echo). The queue grows as needed; nothing is dropped for room. A launch the wizard
## casts (`caster` CASTER_BODY: the cast's later firings) goes when its staff is rebuilt; any
## other (a payload of a shot or a point) keeps its build, as a shot in the air does, and fires.
func _delay(wait: float, group: CompiledGroup, spell: CompiledSpell, actor: int, staff: int, generation: int, origin: Vector2, heading: Vector2, source: Node, from_caster: bool) -> Runtime.PendingLaunch:
	var projectiles: Runtime.ProjectilesScript = rt.projectiles
	var _clock: float = rt._clock
	if _pending_free.is_empty():
		_pending_free.append(Runtime.PendingLaunch.new())
	var launch: Runtime.PendingLaunch = _pending_free.pop_back()
	launch.cost = 0
	launch.echoed = false
	launch.again = false
	launch.wound = false
	launch.fall_floor = INF
	launch.seed = hash(Vector3i(rt._scatter_key, roundi(wait * 1000.0), 0 if group != null else 1))
	launch.due = _clock + maxf(wait, 0.0)
	launch.actor = actor
	launch.staff = staff
	launch.generation = generation
	launch.group = group
	launch.spell = spell
	launch.origin = origin
	launch.heading = heading
	launch.source = source
	launch.anchor = Vector2.INF
	launch.caster = rt._caster
	launch.caster_seq = rt._caster_seq
	if from_caster and projectiles != null:
		launch.anchor = projectiles.get_anchor(Runtime.body_of(rt._caster, actor))
	if launch.caster != Runtime.CASTER_BODY:
		_job_generations._add_live(SpellTag.generation_key(SpellTag.make(actor, staff, 0, generation)))
	_pending.append(launch)
	return launch


## Fires the queued launches that are due. A cast's later firing whose staff was rebuilt since is
## dropped (`_delay`). A cast's own launch starts as far from where it was cast as the caster has moved.
func _run_pending() -> void:
	var _clock: float = rt._clock
	var i: int = 0
	while i < _pending.size():
		var launch: Runtime.PendingLaunch = _pending[i]
		if launch.due > _clock or launch.cost > 0:
			i += 1
			continue
		_pending.remove_at(i)
		if launch.caster == Runtime.CASTER_BODY and _current[launch.actor * SpellLimits.STAFFS + launch.staff] != launch.generation:
			_release_launch(launch)
			continue
		var keeps: bool = launch.caster != Runtime.CASTER_BODY
		var origin: Vector2 = _moved_origin(launch)
		var from_caster: bool = launch.anchor.is_finite()
		# A payload's later firing is cast by its shot or body if that is still there, else from the point.
		var caster: int = _job_launches._live_caster(launch.caster, launch.caster_seq)
		var caster_seq: int = launch.caster_seq
		var source: Node = launch.source if is_instance_valid(launch.source) else null
		var group: CompiledGroup = launch.group
		var spell: CompiledSpell = launch.spell
		var actor: int = launch.actor
		var staff: int = launch.staff
		var generation: int = launch.generation
		var heading: Vector2 = launch.heading
		var echoed: bool = launch.echoed
		var again: bool = launch.again
		var wound: bool = launch.wound
		var fall_floor: float = launch.fall_floor
		_job_launches._scatter_from(launch.seed)
		_release_launch(launch)
		_job_launches._cast_as(caster, caster_seq)
		if wound:
			_fire(group, actor, staff, generation, origin, heading, source, caster, true)
		elif is_finite(fall_floor):
			# Skyfall: its hole has opened, and it falls from there onto its floor line.
			rt._skyfall.begin(fall_floor, actor)
			rt._echo_spell = spell if echoed else null
			var falling: int = SpellTag.make(actor, staff, spell.node, generation)
			_job_launches._launch(spell, falling, actor, origin, heading, source)
			rt._echo_spell = null
			rt._skyfall.end()
			# What it made counts now, not its wait (`Skyfall.open`).
			rt.shot_ended(falling)
		elif group != null:
			_job_launches._fire_group(group, actor, staff, generation, origin, heading, source, from_caster)
		elif not again:
			_job_launches._fire_spell(spell, actor, staff, generation, origin, heading, source, from_caster, echoed)
		elif _hold_tags[actor * SpellLimits.STAFFS + staff].has(SpellTag.make(actor, staff, spell.node, generation)):
			# A held carrier cast again while it is on, along where its body aims now.
			var holder: int = Runtime.body_of(caster, actor)
			if holder >= 0 and _aim_dir[holder].is_finite():
				heading = _aim_dir[holder]
			_job_launches._fire_spell(spell, actor, staff, generation, origin, heading, source, from_caster, echoed, true)
		_job_launches._cast_done()
		if keeps:
			_job_generations._generation_gone(SpellTag.make(actor, staff, 0, generation))


## Where the waiting `launch` starts now: a body's launch as far from where it was scheduled as
## that body has moved since (`PendingLaunch.anchor`), any other where it was scheduled.
func _moved_origin(launch: Runtime.PendingLaunch) -> Vector2:
	var projectiles: Runtime.ProjectilesScript = rt.projectiles
	if not launch.anchor.is_finite() or projectiles == null:
		return launch.origin
	var now: Vector2 = projectiles.get_anchor(Runtime.body_of(launch.caster, launch.actor))
	return launch.origin + (now - launch.anchor if now.is_finite() else Vector2.ZERO)


## Gives a finished record back to the pool.
func _release_launch(launch: Runtime.PendingLaunch) -> void:
	launch.cost = 0
	launch.group = null
	launch.spell = null
	launch.fall_floor = INF
	launch.source = null
	_pending_free.append(launch)


## Forgets the waiting launches `drops` picks (an edit, a switch-off or a closed caster; never
## per frame). One that kept its build (`_delay`) lets go of it.
func _drop_pending(drops: Callable) -> void:
	var i: int = _pending.size() - 1
	while i >= 0:
		var launch: Runtime.PendingLaunch = _pending[i]
		if drops.call(launch):
			_pending.remove_at(i)
			var keeps: bool = launch.caster != Runtime.CASTER_BODY
			var tag: int = SpellTag.make(launch.actor, launch.staff, 0, launch.generation)
			# Skyfall: a fall that waited counted as a live shot (`Skyfall.open`); it never falls now.
			var fell: int = SpellTag.make(launch.actor, launch.staff, launch.spell.node, launch.generation) if is_finite(launch.fall_floor) else 0
			_release_launch(launch)
			if fell != 0:
				rt.shot_ended(fell)
			if keeps:
				_job_generations._generation_gone(tag)
		i -= 1


## True when `launch` fires a carrier with one of `tags` (its group's own carriers, or its echo).
func _fires_any(launch: Runtime.PendingLaunch, tags: PackedInt64Array) -> bool:
	if launch.spell != null:
		return tags.has(SpellTag.make(launch.actor, launch.staff, launch.spell.node, launch.generation))
	if launch.group != null:
		for spell in launch.group.spells:
			if tags.has(SpellTag.make(launch.actor, launch.staff, spell.node, launch.generation)):
				return true
	return false


## Casts the queued beam jumps, if this is the outermost beam. Each jump's own jumps join the
## end of the queue, so the chain runs as a loop, one `ray()` deep per jump.
func _cast_jumps() -> void:
	if rt._jq_busy:
		return
	rt._jq_busy = true
	while rt._jq_count > 0:
		var at: int = rt._jq_head
		rt._jq_head = (rt._jq_head + 1) % rt._jq_spell.size()
		rt._jq_count -= 1
		var spell: CompiledSpell = rt._jq_spell[at]
		var target: Node2D = rt._jq_target[at]
		var hit: HitProfile = rt._jq_hit[at]
		rt._jq_spell[at] = null
		rt._jq_target[at] = null
		rt._jq_hit[at] = null
		if spell == null or not is_instance_valid(target):
			continue
		# Cast by what cast the hit it jumps from, as it can cast now (`_live_caster`).
		_job_launches._cast_as(_job_launches._live_caster(rt._jq_caster[at], rt._jq_caster_seq[at]), rt._jq_caster_seq[at])
		_job_strikes._shoot_ray(spell, rt._jq_tag[at], rt._jq_actor[at], rt._jq_pos[at], rt._jq_dir[at], rt._jq_chain[at], rt._jq_prev[at], target, rt._jq_len[at], hit)
		_job_launches._cast_done()
	rt._jq_busy = false


## Doubles the beam jump ring, its waiting jumps first in the same order.
func _grow_jumps() -> void:
	var size: int = rt._jq_spell.size()
	var spells: Array[CompiledSpell] = []
	var targets: Array[Node2D] = []
	var tags := PackedInt64Array()
	var actors := PackedInt32Array()
	var places := PackedVector2Array()
	var dirs := PackedVector2Array()
	var lengths := PackedFloat32Array()
	var chains := PackedInt32Array()
	var prevs := PackedInt64Array()
	var hits: Array[HitProfile] = []
	var casters := PackedInt32Array()
	var caster_seqs := PackedInt64Array()
	for n in size * 2:
		var at: int = (rt._jq_head + n) % size
		var kept: bool = n < rt._jq_count
		spells.append(rt._jq_spell[at] if kept else null)
		targets.append(rt._jq_target[at] if kept else null)
		tags.append(rt._jq_tag[at] if kept else 0)
		actors.append(rt._jq_actor[at] if kept else 0)
		places.append(rt._jq_pos[at] if kept else Vector2.ZERO)
		dirs.append(rt._jq_dir[at] if kept else Vector2.ZERO)
		lengths.append(rt._jq_len[at] if kept else 0.0)
		chains.append(rt._jq_chain[at] if kept else 0)
		prevs.append(rt._jq_prev[at] if kept else 0)
		hits.append(rt._jq_hit[at] if kept else null)
		casters.append(rt._jq_caster[at] if kept else Runtime.CASTER_POINT)
		caster_seqs.append(rt._jq_caster_seq[at] if kept else 0)
	rt._jq_spell = spells
	rt._jq_target = targets
	rt._jq_tag = tags
	rt._jq_actor = actors
	rt._jq_pos = places
	rt._jq_dir = dirs
	rt._jq_len = lengths
	rt._jq_chain = chains
	rt._jq_prev = prevs
	rt._jq_hit = hits
	rt._jq_caster = casters
	rt._jq_caster_seq = caster_seqs
	rt._jq_head = 0


## Fires `payload` of a carrier with `tag` from `at` along `heading`, in the same actor's staff and
## generation, cast by `caster` (see `_caster`): the shot that fired it while that shot still
## flies, the body that fired it (`body_caster`), else the point `at`.
func _fire_payload(payload: CompiledGroup, tag: int, actor: int, at: Vector2, heading: Vector2, source: Node, caster: int = Runtime.CASTER_POINT, wound: bool = false) -> void:
	_fire(payload, actor, SpellTag.staff_of(tag), SpellTag.generation_of(tag), at, heading, source, caster, wound)


## Fires the payload of every trigger of `spell` that goes off on `event` (a carrier's triggers
## each fire their own; see `CompiledSpell.triggers`), as `_fire_payload`.
func _fire_payloads(spell: CompiledSpell, event: int, tag: int, actor: int, at: Vector2, heading: Vector2, source: Node, caster: int = Runtime.CASTER_POINT) -> void:
	for trigger in spell.triggers:
		if trigger.event == event:
			_fire_payload(trigger.payload, tag, actor, at, heading, source, caster)


## A trigger fires `group`: now, when this step's budget (`fire_shots_per_step` shots for the
## caster's budget: every actor no seat drives shares one) has room or nothing has fired from it
## yet, else it waits for the next step's room, oldest first (`_run_waiting_fires`), and is cast
## then by `caster` (see `_caster`) if that is still there, else from the point. Nothing is dropped
## (owner, 2026-10-29). One the actor's own body casts (`on cast` of its own cast) leaves as that
## cast's own launch does.
func _fire(group: CompiledGroup, actor: int, staff: int, generation: int, at: Vector2, heading: Vector2, source: Node, caster: int, wound: bool = false) -> void:
	var projectiles: Runtime.ProjectilesScript = rt.projectiles
	var fire_shots_per_step: int = rt.fire_shots_per_step
	if group == null or group.is_empty():
		return
	if group.wind_up > 0.0 and not wound:
		# A payload winds up where its trigger fired, as a cast does (docs/milestones/
		# cast-timing.md), then fires as now, cast by what fired it if that is still there.
		var saved_wind: int = rt._caster
		var saved_wind_seq: int = rt._caster_seq
		var wind_seq: int = projectiles.get_seq_of(caster) if caster >= 0 else 0
		rt._caster = _job_launches._live_caster(caster, wind_seq)
		rt._caster_seq = wind_seq
		_delay(group.wind_up, group, null, actor, staff, generation, at, heading, source, Runtime.body_of(rt._caster, actor) >= 0).wound = true
		rt._caster = saved_wind
		rt._caster_seq = saved_wind_seq
		return
	var cost: int = _job_launches._shots_of(group)
	var budget: int = rt._budget(actor)
	var seq: int = projectiles.get_seq_of(caster) if caster >= 0 else 0
	if _fires_used[budget] > 0 and _fires_used[budget] + cost > fire_shots_per_step:
		_job_launches._cast_as(_job_launches._live_caster(caster, seq), seq)
		var launch: Runtime.PendingLaunch = _delay(0.0, group, null, actor, staff, generation, at, heading, source, Runtime.body_of(rt._caster, actor) >= 0)
		launch.cost = cost
		_job_launches._cast_done()
		rt.fires_waited += 1
		return
	_fires_used[budget] += cost
	rt.fires_made += 1
	_job_launches._launch_as(group, actor, staff, generation, at, heading, source, caster, seq)


## The fires that waited for room (`_fire`), oldest first, while their budget has room in this
## step; a cast's own (`on cast`) whose staff was rebuilt since is dropped (`_delay`).
func _run_waiting_fires() -> void:
	var fire_shots_per_step: int = rt.fire_shots_per_step
	var i: int = 0
	while i < _pending.size():
		var launch: Runtime.PendingLaunch = _pending[i]
		if launch.cost <= 0:
			i += 1
			continue
		var budget: int = rt._budget(launch.actor)
		if _fires_used[budget] > 0 and _fires_used[budget] + launch.cost > fire_shots_per_step:
			i += 1
			continue
		_pending.remove_at(i)
		if launch.caster == Runtime.CASTER_BODY and _current[launch.actor * SpellLimits.STAFFS + launch.staff] != launch.generation:
			_release_launch(launch)
			continue
		var keeps: bool = launch.caster != Runtime.CASTER_BODY
		_fires_used[budget] += launch.cost
		rt.fires_made += 1
		var origin: Vector2 = _moved_origin(launch)
		var caster: int = launch.caster
		var caster_seq: int = launch.caster_seq
		var source: Node = launch.source if is_instance_valid(launch.source) else null
		var group: CompiledGroup = launch.group
		var actor: int = launch.actor
		var staff: int = launch.staff
		var generation: int = launch.generation
		var heading: Vector2 = launch.heading
		_job_launches._scatter_from(launch.seed)
		_release_launch(launch)
		_job_launches._launch_as(group, actor, staff, generation, origin, heading, source, caster, caster_seq)
		if keeps:
			_job_generations._generation_gone(SpellTag.make(actor, staff, 0, generation))


## Who casts the payload of a hit of `spell` with no shot (a strike, a ray) for a card of `actor`,
## as the caster casting that hit now (`Carrier.hit_caster`: what a move moves, else the point).
func _hit_caster(spell: CompiledSpell, actor: int) -> int:
	return _job_launches._carrier_of(spell).hit_caster(rt._caster, actor) if spell != null else Runtime.CASTER_POINT


## Fires the payload of the shot with `tag` from `at`, when that shot's trigger is `event` (the
## shared way of the events that name a shot's tag). When the event is being sent for that
## very shot (`shot`, the event's), its record limits how often it fires. `back_off` pulls the
## point out of a wall; `way`, when given, is the way the payload goes; `by`, who casts it when the
## event names no shot of the carrier (a barrier's body; the point by default).
func _fire_event(event: int, actor: int, at: Vector2, tag: int, source: Node, shot: int, back_off: bool = false, way: Vector2 = Vector2.ZERO, by: int = Runtime.CASTER_POINT) -> void:
	if not SpellTag.is_spell_tag(tag):
		return
	var spell: CompiledSpell = _profiles.get(tag)
	if spell == null or not spell.fires_on(event):
		return
	var slot: int = shot
	if slot >= 0 and (not rt._same(slot) or rt.projectiles.get_tag_of(slot) != tag):
		slot = -1
	# A beam has no slot: while its `ray()` runs, its payload goes along the beam.
	var by_ray: bool = slot < 0 and tag == rt._ray.tag
	var heading: Vector2 = way if not way.is_zero_approx() else (rt._ray.dir if by_ray else _job_launches._heading(spell, slot, at, actor))
	if back_off:
		at -= heading * SpellLimits.EXPIRE_BACKOFF
	_fire_payloads(spell, event, tag, actor, at, heading, source, slot if slot >= 0 else by)
