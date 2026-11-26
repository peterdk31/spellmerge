class_name SpellHits
extends Object
## What the runtime does when its shots meet something (core/spells/spells.gd): the event handlers
## (`_on_hit`, `_on_expired`, `_on_wall_met`, blocks, kills, reactions, `_on_hurt`, an entity's
## end), a hit's cards (`_on_hit_effects`: chain jumps, possess, siphon, relay and infusion).
## Methods working on the runtime (`rt`), whose members hold all of it (core/README.md, "The spell
## runtime").

const Runtime := preload("res://core/spells/spells.gd")

## Not state (core/sim/README.md): the runtime, the other jobs this one calls and the runtime's
## arrays it works on, each the runtime's own (shared, never a copy), linked by `link`.
const DERIVED: Array[StringName] = [&"rt", &"_job_fires", &"_job_lasting", &"_job_launches", &"_job_strikes", &"_profiles", &"_rec_chain", &"_rec_prev", &"_lc_tag", &"_lc_kind", &"_lc_ref", &"_lc_seq", &"_lc_at", &"_rec_relay", &"_rec_zap", &"_last_infused", &"_hurt_firing"]

var rt: Runtime = null
var _job_fires: SpellFires = null
var _job_lasting: SpellLasting = null
var _job_launches: SpellLaunches = null
var _job_strikes: SpellStrikes = null
var _profiles: Dictionary
var _rec_chain: PackedInt32Array
var _rec_prev: PackedInt64Array
var _lc_tag: PackedInt64Array
var _lc_kind: PackedInt32Array
var _lc_ref: PackedInt32Array
var _lc_seq: PackedInt64Array
var _lc_at: PackedVector2Array
var _rec_relay: Array[HitProfile]
var _rec_zap: Array[HitProfile]
var _last_infused: Array[CompiledSpell]
var _hurt_firing: PackedInt64Array


## Takes the runtime's arrays and jobs, by the names in DERIVED: again whenever the runtime's
## arrays may have been replaced (`SpellRuntime._link_jobs`).
func link(runtime: Runtime) -> void:
	rt = runtime
	for name: StringName in DERIVED:
		if name != &"rt":
			set(name, runtime.get(name))


func _on_hit(actor: int, target: Node, position: Vector2, tag: int, shot: int) -> void:
	var projectiles: Runtime.ProjectilesScript = rt.projectiles
	if not SpellTag.is_spell_tag(tag):
		return
	var spell: CompiledSpell = _profiles.get(tag)
	if spell == null:
		return
	# A shot never hits a body it carries again (Plow: it catches up with it at a wall).
	if shot >= 0 and rt._plow.carried_count() > 0 and rt._plow.rides_on(projectiles.target_owner_of(target), shot):
		return
	# `relay` takes on what the actor hit last cast, before Combat reads this hit's profile (Spells
	# hears `projectile_hit` first: its autoload comes before Combat's).
	_relay(spell, target, tag, shot)
	var slot: int = shot
	var chain: int = spell.chain_jumps
	var prev: int = 0
	var heading: Vector2 = Vector2.RIGHT
	var by_ray: bool = slot < 0
	if by_ray:
		if tag != rt._ray.tag:
			return
		chain = rt._ray.chain
		prev = rt._ray.prev
		heading = rt._ray.dir
	else:
		if rt._same(slot):
			chain = _rec_chain[slot]
			prev = _rec_prev[slot]
		# (Only a payload on hit goes the way the shot went: performance, 2026-11-02.)
		if spell.fires_on(TriggerBase.Event.HIT):
			heading = _job_launches._heading(spell, slot, position, actor)
	# A chain goes on hitting as the hit it jumps from did (an echo's half, a relay's merge); a
	# zap's jumps as its shot does. (Read before the hit's effects and payloads, which may spawn
	# into its slot.)
	var carried: HitProfile = null
	var carried_zap: HitProfile = null
	if chain > 0:
		var from: int = rt._ray.zap_slot if by_ray else slot
		if from >= 0 and rt._same(from):
			carried = _rec_relay[from]
			carried_zap = _rec_zap[from]
		elif by_ray:
			carried = rt._ray.hit
	# The chain's last body, by its key (N5): what the next jump must not go back to (looked up only
	# for a chain: the lookup walks the targets).
	var struck: int = projectiles.key_of(target) if chain > 0 else 0
	# The hit is the cast's that made it: a shot's hit is cast by what cast that shot (so its chain
	# jumps belong to it), a ray's by the caster already casting it (its launch's or its row's).
	var caster: int = rt._caster if by_ray else rt.shot_caster(slot)
	_job_launches._cast_as(caster, rt._caster_seq if by_ray else (projectiles.get_seq_of(caster) if caster >= 0 else 0))
	_on_hit_effects(spell, tag, actor, target, position, slot)
	_job_fires._fire_payloads(spell, TriggerBase.Event.HIT, tag, actor, position, heading, target, slot if slot >= 0 else _job_fires._hit_caster(spell, actor))
	if chain > 0:
		_jump(spell, tag, actor, position, target as Node2D, struck, prev, chain - 1, by_ray, carried, carried_zap)
	_job_launches._cast_done()


## What a hit of a carrier does besides its payload and chain: siphon refunds mana, possess takes
## the target, `pull` pulls its caster to the hit (`CasterMoves.pull`), the carrier's own part runs
## (`Carrier.on_hit`: a swap's trade), and a spent shot's `blast` goes off (a beam's waits for its
## end, a pulling shot's for the arrival). What a blast strikes moves nothing (that would move
## again at every arrival, rules R4 F2): only the carrier's own hits do (`_blasting`).
func _on_hit_effects(spell: CompiledSpell, tag: int, actor: int, target: Node, position: Vector2, slot: int) -> void:
	var projectiles: Runtime.ProjectilesScript = rt.projectiles
	if spell.plain_hit():
		# No siphon, possess, pull or blast: only the carrier's own part.
		if not rt._blasting:
			var ended: bool = slot >= 0 and not projectiles.is_alive(slot)
			_job_launches._carrier_of(spell).on_hit(spell, tag, actor, target, position, slot)
			# A shot the hit spent ends here: its elements touch the floor (ground cover GC5).
			if ended:
				_job_strikes._touch_end(spell, actor, position, tag)
		return
	var refund: float = spell.behaviour(ModifierBase.Behaviour.SIPHON)
	if refund > 0.0:
		_refund(actor, SpellTag.staff_of(tag), refund)
		_show_siphon(spell, actor, position)
	var possess: float = spell.behaviour(ModifierBase.Behaviour.POSSESS)
	if possess > 0.0:
		_possess(actor, target, possess, tag)
	var spent: bool = slot >= 0 and not projectiles.is_alive(slot)
	var pulled: bool = false
	if not rt._blasting:
		if spell.behaviour(ModifierBase.Behaviour.PULL) > 0.0:
			pulled = rt._moves.pull(spell, tag, actor, position, slot, spent)
		if spell.behaviour(ModifierBase.Behaviour.PLOW) > 0.0:
			rt._plow.carry(spell, tag, actor, target, slot, _job_launches._carrier_of(spell).carry_reach(spell, actor, slot))
		_job_launches._carrier_of(spell).on_hit(spell, tag, actor, target, position, slot)
	# A spent shot's blast goes off where it hit; a pulling one's waits for the arrival.
	if spent and not pulled:
		_job_strikes._touch_end(spell, actor, position, tag)
		_job_strikes._blast(spell, tag, actor, position, slot)


## `possess` (actors G9; owner, 2026-10-29): every actor a carrier with it hits is possessed for
## `seconds` (`possess_requested`; the actor kit adds it to the caster's controller's bodies and
## skips one that is already its). A target no actor owns, and the caster's own body, are not.
func _possess(actor: int, target: Node, seconds: float, tag: int) -> void:
	if rt.events == null or not is_instance_valid(target) or actor < 0 or actor >= Runtime.ACTORS:
		return
	var victim: int = rt.projectiles.target_owner_of(target)
	if victim < 0 or victim >= Runtime.ACTORS or victim == actor:
		return
	rt.events.possess_requested.emit(actor, victim, seconds, tag)


## Sends a chain on from `position` to the nearest other target, if there is one in range. The
## jump hits with `hit` and zaps with `zap` (null: the spell's own), as the hit it came from did.
func _jump(spell: CompiledSpell, tag: int, actor: int, position: Vector2, target: Node2D, struck: int, prev: int, chain: int, by_ray: bool, hit: HitProfile = null, zap: HitProfile = null) -> void:
	var projectiles: Runtime.ProjectilesScript = rt.projectiles
	var before: Node2D = null
	if prev != 0:
		before = projectiles.target_of_key(prev)
	var best: Node2D = projectiles.nearest_target(position, SpellLimits.CHAIN_RANGE, Runtime.HITS, target, before, rt._team(actor))
	if best == null:
		return
	var aim: Vector2 = projectiles.nearest_point
	if not aim.is_finite() or aim.is_equal_approx(position):
		return
	var along: Vector2 = position.direction_to(aim)
	var distance: float = position.distance_to(aim)
	if by_ray:
		if rt._jq_count >= rt._jq_spell.size():
			_job_fires._grow_jumps()
		var end: int = (rt._jq_head + rt._jq_count) % rt._jq_spell.size()
		rt._jq_count += 1
		rt._jq_spell[end] = spell
		rt._jq_target[end] = target
		rt._jq_tag[end] = tag
		rt._jq_actor[end] = actor
		rt._jq_pos[end] = position
		rt._jq_dir[end] = along
		rt._jq_len[end] = distance + spell.radius + 8.0
		rt._jq_chain[end] = chain
		rt._jq_prev[end] = struck
		rt._jq_hit[end] = hit
		rt._jq_caster[end] = rt._caster
		rt._jq_caster_seq[end] = rt._caster_seq
		return
	# A flying jump is its carrier fired again from the hit (rules R1b, rule 2): every card it has
	# (homing, bounce, ghost, spiral, linger, growth, sticky, return, shield, pierce, arc, magnet,
	# its trigger), one jump fewer. Only its aim, its source exclusion and its speed (at least
	# CHAIN_MIN_SPEED, for a carrier that does not fly) differ; it flies as far as its carrier
	# would, and at least far enough to reach the target.
	var speed: float = maxf(spell.speed, SpellLimits.CHAIN_MIN_SPEED)
	var life: float = maxf((distance + 16.0) / speed * 1.5 + 0.05, spell.lifetime * spell.speed / speed)
	var slot: int = projectiles.spawn(actor, position, along * speed, life, spell.radius, Runtime.HITS, spell.pierce, tag)
	if slot < 0:
		return
	_job_launches._apply_travel(slot, spell)
	_job_launches._register(slot, tag, spell, chain, struck)
	rt._set_relay(slot, hit)
	_rec_zap[slot] = zap
	projectiles.exclude(slot, target)


func _on_expired(actor: int, position: Vector2, tag: int, shot: int) -> void:
	var spell: CompiledSpell = _profiles.get(tag)
	# Every carrier blasts at its end point (rules R1d): a pulling shot that missed, where it ended.
	if spell != null:
		_job_strikes._touch_end(spell, actor, position, tag)
		_job_strikes._blast(spell, tag, actor, position, shot)
	# A shot that ends on a wall meets that wall and ends: its `on wall` and `on expire` both fire.
	if rt.projectiles.expired_on_wall:
		_job_fires._fire_event(TriggerBase.Event.WALL, actor, position, tag, null, shot, true)
	_job_fires._fire_event(TriggerBase.Event.EXPIRE, actor, position, tag, null, shot, true)


## `on wall` at every wall that does not end the shot (a bounce) and at every wall a beam
## turns at or ends on (owner, 2026-10-29); a shot's last wall is `_on_expired`'s. The
## payload goes the way the shot or beam goes on. A zap (`_zap`, its shot's tag) that ends on a
## wall is not its shot meeting one: it sets off nothing (rules R4a).
func _on_wall_met(actor: int, position: Vector2, heading: Vector2, tag: int, shot: int) -> void:
	if rt._ray.zapping:
		return
	_job_fires._fire_event(TriggerBase.Event.WALL, actor, position, tag, null, shot, false, heading)


func _on_shot_blocked(actor: int, position: Vector2, tag: int, shot: int) -> void:
	_job_fires._fire_event(TriggerBase.Event.BLOCK, actor, position, tag, null, shot)


## A barrier blocks (combat's `shield_blocked`): on `actor`, the wizard that cast it or a body of
## its card's own (a decoy). No shot of the carrier is part of it: its payload is cast by that body
## (`body_caster`), in the name of the card's caster.
func _on_shield_blocked(actor: int, position: Vector2, tag: int) -> void:
	if not SpellTag.is_spell_tag(tag):
		return
	_job_fires._fire_event(TriggerBase.Event.BLOCK, SpellTag.caster_of(tag), position, tag, null, -1, false, Vector2.ZERO, Runtime.body_caster(actor))


## A deflect is a block (owner, 2026-10-29): it sets off `on block` too.
func _on_shot_deflected(actor: int, position: Vector2, tag: int, shot: int) -> void:
	_job_fires._fire_event(TriggerBase.Event.BLOCK, actor, position, tag, null, shot)


func _on_kill(actor: int, target: Node, position: Vector2, tag: int, shot: int) -> void:
	_job_fires._fire_event(TriggerBase.Event.KILL, actor, position, tag, target if is_instance_valid(target) else null, shot, false, Vector2.ZERO, _job_fires._hit_caster(_profiles.get(tag), actor))


func _on_reaction(actor: int, _reaction_id: StringName, target: Node, position: Vector2, tag: int, shot: int) -> void:
	_job_fires._fire_event(TriggerBase.Event.REACTION, actor, position, tag, target if is_instance_valid(target) else null, shot, false, Vector2.ZERO, _job_fires._hit_caster(_profiles.get(tag), actor))


## `on hurt`: every live carrier of the hurt actor with that trigger fires its payload from where
## the actor was hurt (a wizard or an enemy alike, actors G3b), whatever the carrier is (a shot, a
## beam, a dash, an entity...; `_lc_tag`). A carrier that is a body of its own (a decoy, an actor:
## `LC_ACTOR`) is hurt when that body is (owner, 2026-11-02); a dash's body is its caster's. A
## payload does not set its own carrier's `on hurt` off again while it is fired (`_hurt_firing`):
## its strike round the body that fired it (the cards it left landing there) hurts that body, and
## would fire it again inside itself, for ever.
func _on_hurt(actor: int, _amount: float, position: Vector2, _tag: int, _kind: StringName) -> void:
	if actor < 0 or actor >= Runtime.ACTORS:
		return
	# Payloads may list more such carriers; they sit past `count` and wait for the next hurt.
	var count: int = rt._lc_count
	for i in count:
		var tag: int = _lc_tag[i]
		var spell: CompiledSpell = _profiles.get(tag)
		var trigger: CompiledSpell.Trigger = _job_lasting._lc_trigger_of(i, spell)
		var body: int = _lc_ref[i] if _lc_kind[i] == Runtime.LC_ACTOR else SpellTag.caster_of(tag)
		if trigger == null or trigger.event != TriggerBase.Event.HURT or body != actor or _hurt_firing.has(tag):
			continue
		if not _job_lasting._lc_follow(i):
			continue
		_hurt_firing.append(tag)
		# It starts on the hurt body, so it spares that body until it has left it (`_launch`).
		_job_lasting._lc_fire(i, trigger.payload, position, false, rt._body_node(actor))
		_hurt_firing.resize(_hurt_firing.size() - 1)


## `relay` (owner, 2026-10-28): a shot with it that hits any actor (a wizard, an enemy, a
## teammate, whoever) takes on the infusions of that actor's last cast that had one
## (`_last_infused`): their elements, each with its status, join this hit and its later ones,
## its zaps and its chain jumps. The rest of the hit stays as it was (heal, slam, damage, kind).
## An actor that never cast an infused carrier gives nothing. A ray with it (a beam or a
## jump of one; rules R4f) keeps what it took on in `_ray.hit` for its later hits, a live beam
## for as long as it is on (`_bm_hit`). Allocates two profiles per such hit, never per frame.
func _relay(spell: CompiledSpell, target: Node, tag: int, shot: int) -> void:
	var projectiles: Runtime.ProjectilesScript = rt.projectiles
	if spell.behaviour(ModifierBase.Behaviour.RELAY) <= 0.0 or not is_instance_valid(target):
		return
	var donor_actor: int = projectiles.target_owner_of(target)
	if donor_actor < 0 or donor_actor >= Runtime.ACTORS:
		return
	var slot: int = shot
	if slot < 0 and tag == rt._ray.tag:
		slot = rt._ray.zap_slot
	var by_ray: bool = slot < 0 and tag == rt._ray.tag
	var donor: CompiledSpell = _last_infused[donor_actor]
	if donor == null or (not by_ray and (slot < 0 or not rt._same(slot) or projectiles.get_tag_of(slot) != tag)):
		return
	var base: HitProfile = rt._ray.hit if by_ray else _rec_relay[slot]
	if base == null:
		base = spell.hit
	var merged: HitProfile = null
	for n in donor.hit.element_ids.size():
		var id: StringName = donor.hit.element_ids[n]
		if base.element_ids.has(id) or (merged != null and merged.element_ids.has(id)):
			continue
		if merged == null:
			merged = base.copy()
		Runtime._add_element(merged, donor.hit, n)
	if merged == null:
		return
	if by_ray:
		rt._ray.hit = merged
		return
	if base.element_id == &"":
		projectiles.set_core(slot, donor.tint)
	rt._set_relay(slot, merged)
	_rec_zap[slot] = StaffCompiler.zap_hit(merged) if spell.zap_hit != null else null
	if slot == rt._ray.zap_slot:
		rt._ray.hit = _rec_zap[slot]


## The shot in `slot` takes on the infusions of `donor` (a portal's hit) for its later hits, its
## zaps and its jumps, as a relay shot does; its core takes `tint` when it had no infusion.
func _infuse_shot(slot: int, donor: HitProfile, tint: Color) -> void:
	var projectiles: Runtime.ProjectilesScript = rt.projectiles
	if donor == null or donor.element_ids.is_empty() or not rt._knows(slot):
		return
	var spell: CompiledSpell = _profiles.get(projectiles.get_tag_of(slot))
	if spell == null:
		return
	var base: HitProfile = _rec_relay[slot] if _rec_relay[slot] != null else spell.hit
	var merged: HitProfile = Runtime.merge_hit(base, donor)
	if merged == null:
		return
	if base.element_id == &"":
		projectiles.set_core(slot, tint)
	rt._set_relay(slot, merged)
	# Now of an element: it touches the floor as it passes.
	projectiles.set_trail(slot, true)
	_rec_zap[slot] = StaffCompiler.zap_hit(merged) if spell.zap_hit != null else null


## Siphon: mana comes back to staff `staff` of the actor `actor`, whoever it is; its Caster
## takes it from `mana_refund_requested`.
## The floor a spell of `tag` lit strikes `target` (`floor_strike_requested`, the floor's first slice):
## a Siphon on that spell refunds `caster` as for its carrier's hit (the kill is Combat's
## `kill_landed`, heard as any).
func _on_floor_strike(caster: int, target: Node, _element: StringName, _damage: float, tag: int) -> void:
	_siphon_struck(caster, target, tag)


## A reaction the hit of `caster`'s spell of `tag` set off ran on to `target` (`reaction_struck`:
## Current, from any carrier's hit or the floor's): a Siphon on that spell pays, as for its own hit
## (the owner, 2026-11-25).
func _on_reaction_struck(caster: int, _reaction_id: StringName, target: Node, tag: int) -> void:
	_siphon_struck(caster, target, tag)


## A Siphon on the spell of `tag` pays `caster` for `target`, struck as that spell's: only a foe
## (as a carrier's hits find foes), never the caster's own body or a friend's.
func _siphon_struck(caster: int, target: Node, tag: int) -> void:
	var spell: CompiledSpell = _profiles.get(tag) if SpellTag.is_spell_tag(tag) else null
	if spell == null:
		return
	var refund: float = spell.behaviour(ModifierBase.Behaviour.SIPHON)
	var struck := target as Actor
	if refund > 0.0 and rt.actors != null and struck != null and is_instance_valid(struck) and struck.caster_number() != caster and Runtime.ActorsScript.is_foe(rt.actors.team_of(caster), rt.actors.team_of(struck.caster_number())):
		_refund(caster, SpellTag.staff_of(tag), refund)
		var body := target as Node2D
		if body != null and is_instance_valid(body):
			_show_siphon(spell, caster, body.global_position)


func _refund(actor: int, staff: int, amount: float) -> void:
	if rt.events != null and actor >= 0 and actor < Runtime.ACTORS:
		rt.events.mana_refund_requested.emit(actor, staff, amount)


## Siphon's look (the owner, 2026-11-16: the jet run backwards): every siphon hit at `at` (the
## refund may come to nothing, a full staff: the Caster's to say) streams from there into the actor `actor`'s staff tip (its aim's origin, else its anchor), told
## as `carrier_shown` of SIPHON_CARD, along the way and as far: for looks only.
func _show_siphon(spell: CompiledSpell, actor: int, at: Vector2) -> void:
	var projectiles: Runtime.ProjectilesScript = rt.projectiles
	if rt.events == null or actor < 0 or actor >= Runtime.ACTORS or not at.is_finite():
		return
	var tip: Vector2 = rt.aim_origin_of(actor)
	if not tip.is_finite() and projectiles != null:
		tip = projectiles.get_anchor(actor)
	if not tip.is_finite() or at.distance_squared_to(tip) < 1.0:
		return
	rt.events.carrier_shown.emit(actor, Runtime.SIPHON_CARD, at, at.direction_to(tip), at.distance_to(tip), spell.tint, spell.look)


## Where the familiar with `key` (`entity_key`) is now, told by Entities every step: what its
## triggers cast comes from there.
func familiar_at(key: int, at: Vector2) -> void:
	if key == 0 or not at.is_finite():
		return
	for i in rt._lc_count:
		# One entry per timer or on hurt trigger of the familiar's carrier.
		if _lc_seq[i] == key and _lc_kind[i] == Runtime.LC_POINT:
			_lc_at[i] = at


## An entity `ai` made for a carrier ended where it stood: the carrier its kind names (a decoy, a
## familiar) runs its end (`CarrierEntity.entity_ended`).
func _on_entity_ended(actor: int, kind: StringName, position: Vector2, tag: int) -> void:
	var carrier: CarrierEntity = rt._carriers.get(kind) as CarrierEntity
	if carrier != null:
		carrier.entity_ended(actor, position, tag, rt.entity_key)
