class_name SpellLaunches
extends Object
## A cast's carriers leaving (core/spells/spells.gd): a group fired, its fan, nova, Penta ring and
## scatter, each carrier handed to its `Carrier` (`_launch`), the shots landed and given their
## travel, their records (`_register_shots`), and who casts a payload (`_caster`: a shot, a body or
## a point). Methods working on the runtime (`rt`), whose members hold all of it (core/README.md,
## "The spell runtime").

const Runtime := preload("res://core/spells/spells.gd")

## Not state (core/sim/README.md): the runtime, the other jobs this one calls and the runtime's
## arrays it works on, each the runtime's own (shared, never a copy), linked by `link`.
const DERIVED: Array[StringName] = [&"rt", &"_job_casts", &"_job_fires", &"_job_generations", &"_job_lasting", &"_job_views", &"_installed", &"_rec_seq", &"_rec_chain", &"_rec_prev", &"_zappers", &"_rec_zapper", &"_rec_zap_rolls", &"_rec_zapped", &"_rec_zapped_at", &"_rec_zapped_count", &"_rec_due_body", &"_rec_due_at", &"_rec_due_count", &"_magnets", &"_rec_magnet", &"_rec_relay", &"_rec_zap", &"_cast_turn", &"_one_slot", &"_outer", &"_fl_slot", &"_fl_seq", &"_fl_body", &"_penta_rings"]

var rt: Runtime = null
var _job_casts: SpellCasts = null
var _job_fires: SpellFires = null
var _job_generations: SpellGenerations = null
var _job_lasting: SpellLasting = null
var _job_views: SpellViews = null
var _installed: Array[CompiledStaff]
var _rec_seq: PackedInt64Array
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
var _magnets: PackedInt32Array
var _rec_magnet: PackedByteArray
var _rec_relay: Array[HitProfile]
var _rec_zap: Array[HitProfile]
var _cast_turn: PackedFloat32Array
var _one_slot: PackedInt32Array
var _outer: PackedInt64Array
var _fl_slot: PackedInt32Array
var _fl_seq: PackedInt64Array
var _fl_body: PackedInt32Array
var _penta_rings: Dictionary


## Takes the runtime's arrays and jobs, by the names in DERIVED: again whenever the runtime's
## arrays may have been replaced (`SpellRuntime._link_jobs`).
func link(runtime: Runtime) -> void:
	rt = runtime
	for name: StringName in DERIVED:
		if name != &"rt":
			set(name, runtime.get(name))


## The shots made by one launch of `spell`, returned as how many were made (a beam counts
## as one). `source` is the target that fired the trigger, or null.
func _launch(spell: CompiledSpell, tag: int, actor: int, origin: Vector2, direction: Vector2, source: Node, chain: int = -1, prev: int = 0) -> int:
	var projectiles: Runtime.ProjectilesScript = rt.projectiles
	var _clock: float = rt._clock
	var carrier: Carrier = _carrier_of(spell)
	var carried: int = spell.chain_jumps if chain < 0 else chain
	# A held carrier lives until switched off; one that repeats (`_repeats`) lives its own life each time.
	var held: bool = _job_generations._holds(spell, tag)
	var lifetime: float = SpellLimits.HOLD_LIFETIME if held and not SpellGenerations._repeats(spell) else spell.lifetime
	# A payload is kept off the body that fired it only while it starts touching that body (owner,
	# 2026-11-05: "a payload that starts outside the body that fired it can hit it"), as a Penta
	# copy on its ring does not.
	if source != null and projectiles != null and not projectiles.touches_target(source, origin, spell.radius + SpellLimits.SOURCE_TOUCH):
		source = null
	# Else it starts on the body that casts it, if a body does (owner, 2026-11-06: a player's own
	# spells hurt them, once they have left them): a shot spares it until it is clear of it, a
	# carrier that never leaves it (a swing, a slam, a beam) always.
	if source == null:
		source = rt._body_node(Runtime.body_of(rt._caster, actor))
	# Any carrier may move the staff (its card's `staff_pose`) of the body that casts it, when that is
	# the actor's own (another body, a decoy, has no staff); a swing's and a slam's start theirs with
	# their side and strike. Its wind-up ran before it left (`_wind_pose`).
	if not spell.staff_pose.is_empty() and not spell.has_trait(Carrier.OWN_POSE):
		if Runtime.body_of(rt._caster, actor) == actor and actor >= 0 and actor < Runtime.ACTORS and rt._poses.started_at(actor) != _clock and direction.is_finite() and not direction.is_zero_approx():
			rt._poses.start(actor, spell, tag, 0.0, StaffPoses.strike_of(spell, lifetime), direction.normalized(), StaffPoses.up_side(direction))
	return carrier.launch(spell, tag, actor, origin, direction, source, lifetime, carried, prev)


## The carrier that runs `spell` (`Carrier`, by its id; one that runs nothing for an id no carrier
## has).
func _carrier_of(spell: CompiledSpell) -> Carrier:
	var carrier: Carrier = rt._carriers.get(spell.carrier)
	return carrier if carrier != null else rt._no_carrier


## A shot a carrier spawned in `slot` (-1 when the manager refused it) takes its cards (`_apply_travel`)
## and its record, and does not hit `source` for a while: 1 when it was made.
func _land_shot(slot: int, spell: CompiledSpell, tag: int, source: Node, chain: int, prev: int) -> int:
	_one_slot[0] = slot
	return _land_shots(_one_slot, 1, spell, tag, source, chain, prev)


## `_land_shot` for each of the first `count` shots in `slots` (-1 for one not made): how many were
## made. A launch's shots (`Carrier.launch`) are set up together: their cards, then their records
## (`_travel_shots`, `_register_shots`, each reading what the shots share once), then the source's
## exclusion. Each shot still gets its cards before its record, and every list a shot joins (a
## behaviour's, the lifecycle's, the zappers', the magnets') gets them in the order of `slots`.
func _land_shots(slots: PackedInt32Array, count: int, spell: CompiledSpell, tag: int, source: Node, chain: int, prev: int) -> int:
	# Orbit: a spell that circles puts its rows on their circle first, so its cards are set on a
	# circler (what steers a straight flight refuses it) and Skyfall leaves it be: it circles the spot
	# on the floor line instead of falling.
	rt._orbit.circle(slots, count, spell, tag)
	_travel_shots(slots, count, spell)
	# Skyfall: while something falls, its shots fall onto its floor line.
	rt._skyfall.land_shots(slots, count)
	var made: int = _register_shots(slots, count, tag, spell, chain, prev)
	if source != null:
		for n in count:
			if slots[n] >= 0:
				rt.projectiles.exclude(slots[n], source)
	return made


## The live shot casting the launch being fired, or -1 when the caster is the wizard, a point,
## or a shot that has ended since.
func _caster_shot() -> int:
	return rt.live_caster_shot(rt._caster, rt._caster_seq)


## `caster` when it is a shot's slot and that shot (`seq`) still flies, else -1.
func live_caster_shot(caster: int, seq: int) -> int:
	var projectiles: Runtime.ProjectilesScript = rt.projectiles
	if caster >= 0 and projectiles.is_alive(caster) and projectiles.get_seq_of(caster) == seq:
		return caster
	return -1


## `caster` as it can cast now: a shot that has ended (or is no longer the one born `seq`), or a
## body that is gone (no anchor), leaves the point.
func _live_caster(caster: int, seq: int) -> int:
	if caster >= 0:
		return caster if rt.live_caster_shot(caster, seq) >= 0 else Runtime.CASTER_POINT
	if caster <= Runtime.CASTER_BODIES:
		return caster if rt.projectiles.get_anchor(Runtime.CASTER_BODIES - caster).is_finite() else Runtime.CASTER_POINT
	return caster


## Everything from here to the matching `_cast_done` is cast by `caster` (the shot born `seq` when
## it is a slot): a launch, and a row's later step that hits as the launch that made it did (a
## beam, swing, slam or dash, `CarrierKit.cast_as`), so whatever reads the caster then (a pull, a
## swap, a payload, recoil) reads the one that cast it (owner, 2026-11-06: everything a launch
## makes remembers who cast it). The caster from before waits on `_outer`, a stack.
func _cast_as(caster: int, seq: int) -> void:
	if rt._outer_count * 2 + 2 > _outer.size():
		_outer.resize(maxi(_outer.size() * 2, 16))
	_outer[rt._outer_count * 2] = rt._caster
	_outer[rt._outer_count * 2 + 1] = rt._caster_seq
	rt._outer_count += 1
	rt._caster = caster
	rt._caster_seq = seq


## A one-off homing pick for a card of `actor` (a teleport's target): a target of
## another team within `within` pixels of `at`, any way round, picked at random, rolled afresh for
## each pick (owner, 2026-11-06: "homing should just always pick a random enemy in range"; it may
## be the one picked last). Its centre, or INF for none; `projectiles.homing_target_reach` is how
## far its hit shape reaches toward `at`. A flying shot's steering keeps its target (`Projectiles.home_velocity`).
func pick_target(actor: int, at: Vector2, within: float) -> Vector2:
	rt._picks += 1
	return rt.projectiles.homing_point(actor, at, Vector2.RIGHT, PI, Runtime.ProjectilesScript.ACTOR_LAYERS, within, 0, hash(Vector2i(actor, rt._picks)))


## Ends the newest `_cast_as`: the caster from before casts again.
func _cast_done() -> void:
	rt._outer_count -= 1
	rt._caster = _outer[rt._outer_count * 2]
	rt._caster_seq = _outer[rt._outer_count * 2 + 1]


## `_launch_group` cast by `caster` (see `_caster`; one that can no longer cast leaves the point,
## `_live_caster`), a body's launch following that body.
func _launch_as(group: CompiledGroup, actor: int, staff: int, generation: int, origin: Vector2, heading: Vector2, source: Node, caster: int, seq: int) -> int:
	_cast_as(_live_caster(caster, seq), seq)
	var made: int = _launch_group(group, actor, staff, generation, origin, heading, source, Runtime.body_of(rt._caster, actor) >= 0)
	_cast_done()
	return made


## Where a carrier its caster places (a rune, a decoy, a familiar) appears: a step ahead of
## `origin` along `heading`, twice its size (rules R4 F3), so a mirror's copy is placed behind;
## with a wall in the way, at `origin` (never in the wall).
func _placed_at(spell: CompiledSpell, origin: Vector2, heading: Vector2) -> Vector2:
	var ahead: Vector2 = origin + heading * spell.radius * 2.0
	# Skyfall: while something falls, it is placed on its floor line.
	return rt._skyfall.on_floor(spell, ahead if rt.projectiles.grid().clip_to_walls(origin, ahead) == ahead else origin)


## Hand a shot the behaviours of its cards that the projectile manager runs (staffs B1): a bolt,
## a rune, an orbit and a wall's shots from the staff and a chain jump alike (rules R1b). Each
## setter takes what the shot can do and refuses the rest (rules R4h: a rune does not move, an
## orbit does not fly). A plain shot costs a few comparisons and no setter call.
func _apply_travel(slot: int, spell: CompiledSpell) -> void:
	_one_slot[0] = slot
	_travel_shots(_one_slot, 1, spell)


## `_apply_travel` for each of the first `count` shots in `slots` (-1 for none), the spell's
## behaviours read once.
func _travel_shots(slots: PackedInt32Array, count: int, spell: CompiledSpell) -> void:
	var projectiles: Runtime.ProjectilesScript = rt.projectiles
	if _carrier_of(spell).gives_cards():
		# A field (docs/milestones/field.md) gives its cards to the shots that come into it and
		# wears none of them itself, but Growth, which widens it.
		var widens: float = spell.behaviour(ModifierBase.Behaviour.GROWTH)
		for n in count:
			if slots[n] >= 0 and widens > 1.0:
				projectiles.set_growth(slots[n], widens)
		return
	var homing: bool = spell.homing_range > 0.0
	var returns: bool = spell.behaviour(ModifierBase.Behaviour.RETURN) > 0.0
	var curve: bool = spell.has_speed_curve()
	var plain: bool = spell.behaviours.is_empty()
	if plain and not homing and not returns and not curve:
		return
	var bounce: float = spell.behaviour(ModifierBase.Behaviour.BOUNCE)
	var ghost: bool = spell.behaviour(ModifierBase.Behaviour.GHOST) > 0.0
	var spiral: float = spell.behaviour(ModifierBase.Behaviour.SPIRAL)
	var linger: float = spell.behaviour(ModifierBase.Behaviour.LINGER)
	var growth: float = spell.behaviour(ModifierBase.Behaviour.GROWTH)
	var sticky: float = spell.behaviour(ModifierBase.Behaviour.STICKY)
	# A shot with `shield` blocks that many enemy shots; with deflect it turns them back.
	var shield: float = spell.behaviour(ModifierBase.Behaviour.SHIELD)
	var deflect: bool = spell.behaviour(ModifierBase.Behaviour.DEFLECT) > 0.0
	for n in count:
		var slot: int = slots[n]
		if slot < 0:
			continue
		if homing:
			projectiles.set_homing_curve(slot, spell.homing_curve, spell.homing_range)
		if returns:
			projectiles.set_return(slot)
		if curve:
			projectiles.set_speed_curve(slot, spell.speed_start, spell.speed_end, spell.speed_ease)
		if plain:
			continue
		if bounce > 0.0:
			projectiles.set_bounce(slot, roundi(bounce))
		if ghost:
			projectiles.set_ghost(slot)
		if spiral > 0.0:
			projectiles.set_spiral(slot, spiral)
		if linger > 0.0:
			projectiles.set_linger(slot, linger)
		if growth > 1.0:
			projectiles.set_growth(slot, growth)
		if sticky > 0.0:
			projectiles.set_sticky(slot, sticky)
		if shield > 0.0:
			projectiles.set_shield(slot, roundi(shield))
		if deflect:
			projectiles.set_deflect(slot, true)


## The shots of every spell of `group`, fired together from `origin` along `direction` by this
## actor's staff in its `generation` (each spell's tag names its node); returns how many were
## made (a Pulse counts as one). The carriers of one group leave along the same aim (only the
## staff's `spread` sets them apart, shot by shot); a scatter group sends each in a random
## direction instead. A burst group fires again `repeats - 1` times, `repeat_interval` seconds
## apart (at once when that is 0), reading nothing again. `source` is the target that
## fired the payload, or null. `from_caster` is true for a launch a body casts (the cast's own group, a body's payload), whose later
## firings (burst, echo) start from where the caster has moved to.
func _launch_group(group: CompiledGroup, actor: int, staff: int, generation: int, origin: Vector2, direction: Vector2, source: Node, from_caster: bool = false) -> int:
	var made: int = _fire_group(group, actor, staff, generation, origin, direction, source, from_caster)
	if made > 0:
		for n in range(1, group.repeats):
			if group.repeat_interval <= 0.0:
				_fire_group(group, actor, staff, generation, origin, direction, source, from_caster)
			else:
				_job_fires._delay(n * group.repeat_interval, group, null, actor, staff, generation, origin, direction, source, from_caster)
	return made


## One firing of `group` (see `_launch_group`).
func _fire_group(group: CompiledGroup, actor: int, staff: int, generation: int, origin: Vector2, direction: Vector2, source: Node, from_caster: bool) -> int:
	var made: int = 0
	for spell in group.spells:
		var heading: Vector2 = direction
		# A carrier that acts all round what casts it (a Pulse) is not aimed: a scatter turns the others.
		if group.scatter and not spell.has_trait(CarrierTraits.AOE):
			heading = DMath.rotated(direction, _scatter_roll() * TAU)
		made += _fire_spell(spell, actor, staff, generation, origin, heading, source, from_caster, false)
	return made


## One carrier of a group, launched; returns the shots made. `mirror` fires it once more with its
## aim reversed (a wall behind, an orbit starting
## on the other side of its circle, a dash or teleport back the other way: the two moves add up
## to none, rules R4 F1), and `echo` schedules it once more. `echoed` is true for that second firing, which hits at half damage and does not
## echo again; on a held carrier it is a second held copy. `again` is a held carrier cast again
## (`_repeats`): it echoes no more.
func _fire_spell(spell: CompiledSpell, actor: int, staff: int, generation: int, origin: Vector2, heading: Vector2, source: Node, from_caster: bool, echoed: bool, again: bool = false) -> int:
	var tag: int = SpellTag.make(actor, staff, spell.node, generation)
	rt._echo_spell = spell if echoed else null
	var share: float = _nova_share(spell, actor, staff)
	var spin: float = share * TAU / float(spell.nova_ways()) if share > 0.0 else 0.0
	var launched: int = _cast_nova(spell, tag, actor, origin, heading, source, spin)
	if launched > 0 and spell.mirrors():
		# The same cast again, its aim reversed: every card it has does what it did the first time.
		launched += _cast_nova(spell, tag, actor, origin, -heading, source, spin)
	rt._echo_spell = null
	if launched > 0 and _job_generations._holds(spell, tag):
		_job_generations._start_hold(tag)
		if SpellGenerations._repeats(spell):
			var repeat: Runtime.PendingLaunch = _job_fires._delay(maxf(spell.wind_up, 0.0) + spell.lifetime, null, spell, actor, staff, generation, origin, heading, source, from_caster)
			repeat.again = true
			repeat.echoed = echoed
	# `on cast`: the payload leaves at once, from where the carrier did, cast by the carrier's caster.
	if launched > 0:
		for trigger in spell.triggers:
			if trigger.event != TriggerBase.Event.CAST:
				continue
			_job_fires._fire(trigger.payload, actor, staff, generation, origin, heading, source, _live_caster(rt._caster, rt._caster_seq))
	var echo: float = spell.behaviour(ModifierBase.Behaviour.ECHO)
	if launched > 0 and not echoed and not again and echo > 0.0:
		_job_fires._delay(echo, null, spell, actor, staff, generation, origin, heading, source, from_caster).echoed = true
	return launched


## How far the ways of a nova `spell` that `actor`'s staff `staff` fires stand turned off its aim,
## as a share of the gap between two ways (0 for no nova): its latest cast's turn (`_cast_turn`,
## SpellLimits.RING_STEP of a gap more for each cast the staff has made; owner, 2026-11-16: "Can
## the nova rotate for each cast?"), so its first cast goes along the aim (owner, 2026-11-09),
## every nova of one cast (its mirror, its echo, its payloads') shares a turn, and the next cast
## turns on; the same on every machine.
func _nova_share(spell: CompiledSpell, actor: int, staff: int) -> float:
	var index: int = actor * SpellLimits.STAFFS + staff
	if spell.nova_ways() <= 1 or actor < 0 or staff < 0 or index >= _cast_turn.size():
		return 0.0
	return _cast_turn[index]


## One firing of `spell` along `heading`, as a nova when it has one (owner, 2026-11-09): the cast
## made `copies` times from `origin` by the same caster, copy k along `heading` turned by `spin`
## (`_nova_share`) and k/copies of a full turn, and the card's cue (`nova`) played once at the
## centre. Both a firing and its mirror go through here with the same `spin`, so a card never does
## more on one than on the other; each way recoils on its own, so a nova's pushes cancel as a
## mirror's do. Returns the shots made.
func _cast_nova(spell: CompiledSpell, tag: int, actor: int, origin: Vector2, heading: Vector2, source: Node, spin: float) -> int:
	var copies: int = spell.nova_ways()
	if copies <= 1:
		var once: int = _cast_once(spell, tag, actor, origin, heading, source, 0.0)
		if once > 0:
			_recoil(spell, tag, actor, heading)
		return once
	var way: Vector2 = heading.normalized() if not heading.is_zero_approx() else Vector2.RIGHT
	var made: int = 0
	for n in copies:
		var turn: float = spin + TAU * float(n) / float(copies)
		var aim: Vector2 = DMath.rotated(way, turn) if turn != 0.0 else way
		var shots: int = _cast_once(spell, tag, actor, origin, aim, source, turn)
		if shots > 0:
			_recoil(spell, tag, actor, aim)
		made += shots
	var cue: StringName = spell.cue_of(ModifierBase.Behaviour.NOVA)
	if made > 0 and rt.events != null and cue != &"":
		rt.cue_tag = tag
		rt.events.cue_shown.emit(actor, cue, _caster_centre(actor, origin), way, 0.0, spell.tint, spell.look)
		rt.cue_tag = 0
	return made


## The middle of what casts now: the body casting it (its anchor), else `origin`, the point or shot
## casting a payload. A nova's ring shows there and a Penta ring stands round it.
func _caster_centre(actor: int, origin: Vector2) -> Vector2:
	var projectiles: Runtime.ProjectilesScript = rt.projectiles
	var body: int = Runtime.body_of(rt._caster, actor)
	if body >= 0 and projectiles != null and projectiles.get_anchor(body).is_finite():
		return projectiles.get_anchor(body)
	return origin


## How many copies a Penta ring of `spell` casts: its Penta cards' count (5 a card, more add, with no
## cap: owner, 2026-11-09), or 0 when it has none or Penta does nothing on its carrier.
func _penta_copies(spell: CompiledSpell) -> int:
	var penta: float = spell.behaviour(ModifierBase.Behaviour.PENTA)
	if penta <= 0.0 or not _carrier_of(spell).works(ModifierBase.Behaviour.PENTA):
		return 0
	return maxi(roundi(penta), 1)


## One cast of `spell` along `heading`: its carrier launched once, or as a Penta ring when it has
## one, that ring turned on by `offset` radians (a nova copy's share of the turn, so a nova of Penta
## rings spreads its rings out instead of stacking them). Returns the shots made.
func _cast_once(spell: CompiledSpell, tag: int, actor: int, origin: Vector2, heading: Vector2, source: Node, offset: float) -> int:
	var copies: int = _penta_copies(spell)
	if copies > 0:
		return _penta(spell, copies, tag, actor, origin, heading, source, offset)
	if rt._skyfall.falls(spell):
		# Skyfall: it opens its hole over where it is cast and falls from there later.
		return rt._skyfall.open(spell, tag, actor, rt._skyfall.spot_of(actor, origin))
	return _launch(spell, tag, actor, origin, heading, source)


## `penta` (owner, 2026-11-05): `spell` is cast `behaviour_strength` times (5 a card), each copy from
## a point on a ring round its caster, all aimed in at it (owner: "they should just aim towards the
## point, even if it is the player"). The caster is a wizard's body, or the point or shot that casts
## a payload, so `on hit · bolt · penta · beam` rings where the bolt hit. Penta reads no other card
## (owner, 2026-11-05: homing no longer moves the ring; it steers each copy, as on any carrier).
## The ring stands SpellLimits.PENTA_RING out, or within PENTA_WITHIN of the carrier's own reach
## when that is less. It turns (owner, 2026-11-06: "rotate continuously") at SpellLimits.PENTA_TURN,
## and each cast turns the other way from the one before (owner, 2026-11-06: "Penta could simply
## swap rotation direction every cast"; `_penta_rings`): a cast stands where its card's last ring
## has turned to (the first from a start of the card's own) and a step on (SpellLimits.RING_STEP of
## the gap between two copies: owner, 2026-11-16), so casts in a row (a held button, a mirror, an
## echo) sweep back and forth without standing on the same points again. A copy that stays on its point and
## aims from it (a beam) turns with its ring while it lasts (`_ring_*`, CarrierBeam). A still shot
## stays where it was placed, as anywhere, and a flying one flies off. It does not follow its
## centre (owner: "Don't let it follow the centre"). Each point stops short of a wall, and each
## copy is cast by its point. `copies` is `_penta_copies(spell)`; `offset` turns this ring on from
## where the card's ring stands (a nova copy's share of the turn). Returns the shots made.
func _penta(spell: CompiledSpell, copies: int, tag: int, actor: int, origin: Vector2, heading: Vector2, source: Node, offset: float) -> int:
	var _clock: float = rt._clock
	var way: Vector2 = heading.normalized() if not heading.is_zero_approx() else Vector2.RIGHT
	var centre: Vector2 = _caster_centre(actor, origin)
	# Where the card's last ring has turned to (its own start the first time), turning back.
	var turned: float = SpellRuntime.penta_start(tag)
	var turn: float = SpellLimits.PENTA_TURN
	if _penta_rings.has(tag):
		var last: Vector3 = _penta_rings[tag]
		# Turned on by a step as well, so a steady rhythm of casts (each turning back what the last
		# turned) never stands the ring on the same points again (SpellLimits.RING_STEP). Only a cast
		# at a later time steps: a nova's copies and a mirror, cast at once, stand on the same ring.
		var step: float = SpellLimits.RING_STEP * TAU / float(copies) if _clock != last.y else 0.0
		turned = fposmod(last.x + last.z * (_clock - last.y) + step, TAU)
		turn = -last.z
	_penta_rings[tag] = Vector3(turned, _clock, turn)
	turned += offset
	# Within the carrier's reach of the middle, so a short one (an atom's) still meets there.
	var carried: float = _carrier_of(spell).reach_of(spell)
	if carried <= 0.0 and spell.speed > 0.0 and spell.has_trait(CarrierTraits.FLIES):
		# A fan all the way round is not aimed, but its shots fly this far.
		carried = spell.speed * spell.lifetime
	var radius: float = minf(SpellLimits.PENTA_RING, carried * SpellLimits.PENTA_WITHIN) if carried > 0.0 else SpellLimits.PENTA_RING
	_cast_as(Runtime.CASTER_POINT, 0)
	var made: int = 0
	rt._ring_centre = centre
	rt._ring_radius = radius
	rt._ring_turn = turn
	for n in copies:
		rt._ring_angle = turned + TAU * float(n) / float(copies)
		var point: Vector2 = SpellRuntime.ring_point(rt.projectiles, centre, radius, rt._ring_angle)
		var aim: Vector2 = point.direction_to(centre) if not point.is_equal_approx(centre) else way
		# Skyfall: each copy falls onto its point of the ring (owner, 2026-11-09).
		made += rt._skyfall.open(spell, tag, actor, point) if rt._skyfall.falls(spell) else _launch(spell, tag, actor, point, aim, source)
	rt._ring_radius = 0.0
	rt._ring_angle = 0.0
	rt._ring_turn = 0.0
	rt._ring_centre = Vector2.ZERO
	_cast_done()
	return made


## `recoil`: the caster is pushed back from a firing along `heading` (a firing the other way
## pushes the other way, so `mirror` cancels it). It is one more move, and every move adds up (a
## dash's or a teleport's too: a recoil longer than a teleport takes it back past its start).
func _recoil(spell: CompiledSpell, tag: int, actor: int, heading: Vector2) -> void:
	var push: float = spell.behaviour(ModifierBase.Behaviour.RECOIL)
	if push <= 0.0:
		return
	var body: int = Runtime.body_of(rt._caster, actor)
	if body >= 0:
		if rt.events != null:
			rt.events.caster_move_requested.emit(body, &"recoil", -heading * push, SpellLimits.RECOIL_SECONDS, tag)
		return
	# A payload's recoil pushes the shot that cast it (a point has nothing to push).
	var shot: int = _caster_shot()
	if shot >= 0:
		rt.projectiles.move_shot(shot, -heading * push, SpellLimits.RECOIL_SECONDS)


## Degrees (as radians) off the aim of shot `n` of `count`: none for one shot, an even ring
## for a 360 degree spread, otherwise an even fan centred on the aim.
func _fan_angle(n: int, count: int, spell: CompiledSpell) -> float:
	if count <= 1:
		return 0.0
	if spell.spread >= 360.0:
		return TAU * n / count
	return deg_to_rad(spell.spread) * (float(n) / (count - 1) - 0.5)


## Radians a shot of `spell` (cast as `tag`) leaves off its line: random, up to its staff's
## `spread` degrees times the spell's `spread_mult` either side, from the generator seeded per
## cast (so the same cast spreads the same way). With no spread (the `dev` staff, or a factor of
## 0) it aims true and draws nothing from the generator.
func _staff_spread(tag: int, spell: CompiledSpell) -> float:
	var actor: int = SpellTag.caster_of(tag)
	var staff: int = SpellTag.staff_of(tag)
	if not _job_casts._in_range(actor, staff):
		return 0.0
	var compiled: CompiledStaff = _installed[actor * SpellLimits.STAFFS + staff]
	if compiled == null or compiled.staff == null:
		return 0.0
	var degrees: float = compiled.staff.spread * spell.spread_mult
	if degrees <= 0.0:
		return 0.0
	return deg_to_rad(degrees) * (_scatter_roll() * 2.0 - 1.0)


## The scatter and spread rolls from here on are those of the cast or later firing named `key`.
func _scatter_from(key: int) -> void:
	rt._scatter_key = key
	rt._scatter_rolls = 0


## The next scatter or spread roll of the cast being launched, in [0, 1).
func _scatter_roll() -> float:
	if rt.sim == null:
		rt.sim = Sim.found(rt)
	var roll: float = rt.sim.chance(&"scatter", rt._scatter_key, rt._scatter_rolls)
	rt._scatter_rolls += 1
	return roll


## Gives the manager's shot in `slot` its record and counts it.
func _register(slot: int, tag: int, spell: CompiledSpell, chain: int, prev: int) -> void:
	_one_slot[0] = slot
	_register_shots(_one_slot, 1, tag, spell, chain, prev)


## `_register` for each of the first `count` shots in `slots` (-1 for none), in turn, with what is
## the same for all of them read once: its looks (`ProjectileManager.set_looks`), the echo, the
## shot that cast it (no shot ends while a launch is set up), its trigger rows. Returns how many
## shots there were.
func _register_shots(slots: PackedInt32Array, count: int, tag: int, spell: CompiledSpell, chain: int, prev: int) -> int:
	var projectiles: Runtime.ProjectilesScript = rt.projectiles
	projectiles.set_looks(slots, count, _job_views._launch_look_of(spell))
	if _rec_seq.size() < projectiles.get_cap():
		_grow_records(projectiles.get_cap())
	var relay: HitProfile = spell.echo_hit if spell == rt._echo_spell else null
	var zap_relay: HitProfile = spell.echo_zap_hit if spell == rt._echo_spell else null
	# A payload's shot: an orbit circles the shot or body that cast it and a returning one flies back
	# to it, or to the point it was cast from. The actor's own body is the manager's own caster.
	var body: int = Runtime.body_of(rt._caster, SpellTag.caster_of(tag))
	var caster_shot: int = _caster_shot()
	var lifecycle: bool = SpellLasting._lc_rows(spell) > 0
	var zaps: bool = spell.zap_chance > 0.0 and spell.zap_reach > 0.0
	var magnet: bool = spell.behaviour(ModifierBase.Behaviour.MAGNET) > 0.0
	# A shot of an element touches the floor as it passes (the floor's first slice; a relay's or an
	# echo's hit is the spell's own elements).
	var trails: bool = not spell.element_ids.is_empty()
	var made: int = 0
	for n in count:
		var slot: int = slots[n]
		if slot < 0:
			continue
		made += 1
		if trails:
			projectiles.set_trail(slot, true)
		rt._set_relay(slot, relay)
		_rec_zap[slot] = zap_relay
		var seq: int = projectiles.get_seq_of(slot)
		if caster_shot >= 0:
			projectiles.set_caster_shot(slot, caster_shot)
		elif body < 0 and projectiles.is_cast_by_wizard(slot):
			projectiles.set_caster_point(slot, projectiles.get_position_of(slot))
		elif body >= 0 and body != SpellTag.caster_of(tag):
			_follow_body(slot, seq, body)
		_rec_seq[slot] = seq
		_rec_chain[slot] = chain
		_rec_prev[slot] = prev
		rt.shot_started(tag)
		if lifecycle:
			_job_lasting._lc_join(spell, tag, Runtime.LC_SLOT, slot, seq, true, projectiles.get_life_of(slot), projectiles.get_position_of(slot), projectiles.get_velocity_of(slot))
		if zaps:
			# A fresh shot: it has rolled for no body yet, and has no zap waiting.
			_rec_zap_rolls[slot] = 0
			_rec_zapped_count[slot] = 0
			_rec_due_count[slot] = 0
			if _rec_zapper[slot] == 0:
				if rt._zapper_count == _zappers.size():
					_zappers.resize(_zappers.size() * 2)
				_zappers[rt._zapper_count] = slot
				rt._zapper_count += 1
				_rec_zapper[slot] = 1
		if magnet and _rec_magnet[slot] == 0:
			if rt._magnet_count == _magnets.size():
				_magnets.resize(_magnets.size() * 2)
			_magnets[rt._magnet_count] = slot
			rt._magnet_count += 1
			_rec_magnet[slot] = 1
	return made


## The shot in `slot` (born `seq`) was cast by the body of the actor `body`, not its own actor's: the
## manager knows it as a point (its caster's place, `set_caster_point`), which follows that body
## every step while both are there (`_step_followers`), and stays where the body was last once it
## has gone. One list, so the projectile manager (and its native kernel) need no caster of another
## actor's body.
func _follow_body(slot: int, seq: int, body: int) -> void:
	var projectiles: Runtime.ProjectilesScript = rt.projectiles
	projectiles.set_caster_point(slot, projectiles.get_anchor(body))
	if rt._fl_count == _fl_slot.size():
		var size: int = maxi(rt._fl_count * 2, 8)
		_fl_slot.resize(size)
		_fl_seq.resize(size)
		_fl_body.resize(size)
	_fl_slot[rt._fl_count] = slot
	_fl_seq[rt._fl_count] = seq
	_fl_body[rt._fl_count] = body
	rt._fl_count += 1


## Moves the place of every shot cast by another actor's body to where that body is now; one whose
## shot ended or whose body has gone leaves the list.
func _step_followers() -> void:
	var projectiles: Runtime.ProjectilesScript = rt.projectiles
	var i: int = 0
	while i < rt._fl_count:
		var slot: int = _fl_slot[i]
		var at: Vector2 = projectiles.get_anchor(_fl_body[i])
		if projectiles.is_alive(slot) and projectiles.get_seq_of(slot) == _fl_seq[i] and at.is_finite():
			projectiles.set_caster_point(slot, at)
			i += 1
			continue
		rt._fl_count -= 1
		_fl_slot[i] = _fl_slot[rt._fl_count]
		_fl_seq[i] = _fl_seq[rt._fl_count]
		_fl_body[i] = _fl_body[rt._fl_count]


## Who cast the shot in `slot` (see `_caster`): the live shot that cast it, the body that cast it
## (its own actor's: CASTER_BODY; another's while it follows it: `body_caster`), else the point. It
## still answers for a shot ended by the hit being sent (a pull's), until its slot is used again.
func shot_caster(slot: int) -> int:
	var projectiles: Runtime.ProjectilesScript = rt.projectiles
	var shot: int = projectiles.caster_shot_of(slot)
	if shot >= 0:
		return shot
	for i in rt._fl_count:
		if _fl_slot[i] == slot and _fl_seq[i] == projectiles.get_seq_of(slot):
			return Runtime.body_caster(_fl_body[i])
	return Runtime.CASTER_BODY if projectiles.is_cast_by_wizard(slot) else Runtime.CASTER_POINT


## Room in the shots' records for `size` slots (the manager's cap); a new slot has no record.
func _grow_records(size: int) -> void:
	var old_size: int = _rec_seq.size()
	_rec_seq.resize(size)
	for at in range(old_size, size):
		_rec_seq[at] = -1
	_rec_chain.resize(size)
	_rec_prev.resize(size)
	_rec_zapper.resize(size)
	_rec_magnet.resize(size)
	_rec_zap_rolls.resize(size)
	_rec_zapped_count.resize(size)
	_rec_zapped.resize(size * Runtime.ZAP_MEMORY)
	_rec_zapped_at.resize(size * Runtime.ZAP_MEMORY)
	_rec_due_body.resize(size * Runtime.ZAP_DUE)
	_rec_due_at.resize(size * Runtime.ZAP_DUE)
	_rec_due_count.resize(size)
	_rec_relay.resize(size)
	_rec_zap.resize(size)


## The shots one firing of `group` makes, at least 1 for each carrier (a beam, a move, an area),
## times the copies its cards cast of it (`copies_of`: mirror, nova, penta).
func _shots_of(group: CompiledGroup) -> int:
	var shots: int = 0
	for spell in group.spells:
		shots += maxi(spell.shots, 1) * rt.copies_of(spell)
	return maxi(shots, 1)


## How many times one firing of `spell` casts its carrier: twice with Mirror, times its Nova ways,
## times its Penta ring's copies where Penta works.
func copies_of(spell: CompiledSpell) -> int:
	var copies: int = spell.nova_ways() * maxi(_penta_copies(spell), 1)
	if spell.mirrors():
		copies *= 2
	return copies


## The way a payload fired by a shot goes: its velocity, or outward from the shot's caster
## through the shot for an orbit or still one (or one with no velocity).
func _heading(spell: CompiledSpell, slot: int, at: Vector2, actor: int) -> Vector2:
	var projectiles: Runtime.ProjectilesScript = rt.projectiles
	var velocity: Vector2 = projectiles.get_velocity_of(slot)
	if spell.has_trait(Carrier.OUTWARD) or velocity.is_zero_approx():
		var anchor: Vector2 = projectiles.get_caster_of(slot) if slot >= 0 else projectiles.get_anchor(actor)
		if anchor.is_finite() and not (at - anchor).is_zero_approx():
			return (at - anchor).normalized()
	return Vector2.RIGHT if velocity.is_zero_approx() else velocity.normalized()
