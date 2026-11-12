class_name CarrierPulse
extends Carrier
## The Pulse card's carrier (`&"pulse"`; docs/CARRIERS.md, "Pulse: a strike round what casts it";
## props W9a, owner 2026-11-12: it replaced the compiler's fallback carriers, "a custom rule", and
## is one carrier: "One carrier!"). The card (`content/spells/carriers/pulse/`) is one strike round
## whatever casts it, then a short life there.
##
## Whatever casts it is the runtime's to know, as for every carrier (`CarrierKit.caster_body`,
## `caster_shot`): the caster's body in a cast's own group; in a payload what fired it, a body (a
## decoy's, a dashing wizard's) or a shot that flies on, else the point the payload began at.
##
## What it does: one strike of everything round that within `spell.radius` (as a card scales it)
## or as wide as its blast, **sparing what casts it** (`MELEE`: it never leaves that). A bare Pulse
## strikes too, for its card's small damage (owner, 2026-11-12: "it hits everything around it"); a
## blast on it is that strike, so it explodes there. Then it **lasts** its `lifetime` round what
## casts it, for the triggers that need a carrier that lasts (a timer, on hurt, on recast) and its
## end (on expire); a hold keeps it until its staff is cast again, striking again every wind-up and
## life (`REPEATS_HELD`, as a held swing). It acts all round, not along an aim (`AROUND`).
##
## Where what casts it is a body or a shot, it meets the shots that reach it there (`MEETS_SHOTS`): a
## deflect turns the shots round it (or makes the shot deflect), a shield is a barrier on that body
## or charges on that shot. At a bare point there is no one to guard. (What Shield does on a Pulse
## is still to be talked through with the owner, 2026-11-12.)


func id() -> StringName:
	return &"pulse"


func traits() -> int:
	return HITS | LASTS | REPEATS_HELD | MEETS_SHOTS | MELEE | AROUND


## Its hits feel like an explosion (`HitProfile.kind`).
func hit_kind() -> StringName:
	return &"burst"


## One strike round `origin`, sparing what casts it, shown as a pulse of its cards' motes out to
## its reach (the card's `shown_cue`); then, with a trigger that waits on it, it is listed round what
## casts it for its life (`CarrierKit.live_join`): the body, the shot (ending with it) or the point.
func launch(spell: CompiledSpell, tag: int, actor: int, origin: Vector2, direction: Vector2, _source: Node, lifetime: float, _chain: int, _prev: int) -> int:
	if not origin.is_finite():
		return 0
	var blast: float = spell.behaviour(ModifierBase.Behaviour.BLAST)
	var reach: float = maxf(spell.radius, blast)
	var way: Vector2 = direction if direction.is_finite() and not direction.is_zero_approx() else Vector2.RIGHT
	var body: int = kit.caster_body(actor)
	var shot: int = kit.caster_shot()
	if kit.events != null:
		kit.set_cue_tag(tag)
		if blast > 0.0:
			kit.events.cue_shown.emit(actor, spell.cue_of(ModifierBase.Behaviour.BLAST), origin, Vector2.ZERO, blast, spell.tint, spell.look)
		kit.events.carrier_shown.emit(actor, spell.carrier_card_id, origin, way, reach, spell.tint, spell.look)
		kit.set_cue_tag(0)
	if spell.behaviour(ModifierBase.Behaviour.DEFLECT) > 0.0 and kit.projectiles != null:
		# Before the strike: a shot that cast it deflects while it lives; round a body or a point
		# the shots of other teams turn outward, once (within MOVE_GUARD_REACH at least).
		if body < 0 and shot >= 0:
			kit.projectiles.set_deflect(shot, true)
		else:
			kit.turn_shots_round(actor, tag, origin, reach, id())
	kit.strike_round(spell, tag, actor, origin, way, reach, spell.echo_hit if kit.is_echo(spell) else null, kit.spared(spell, kit.body_node(body)))
	# After the strike, which reaches the body and would spend it: a shield is a barrier on the body,
	# or charges on the shot.
	if body >= 0:
		kit.moves().shield_caster(spell, tag, body, 0.0)
	elif shot >= 0:
		kit.moves().shield(spell, tag, actor, shot, 0.0)
	_join_live(spell, tag, actor, origin, way, lifetime)
	return 1


## Lists it for its triggers that fire while it lasts, and its end for its `on expire`, round
## what casts it for its life: a body (`LC_ACTOR`), a shot (`LC_SLOT`: round it while it flies, then
## where it was) or the point (`LC_POINT`).
func _join_live(spell: CompiledSpell, tag: int, actor: int, origin: Vector2, way: Vector2, lifetime: float) -> void:
	if lifetime <= 0.0 or spell.triggers.is_empty():
		return
	var kind: int = SpellRuntime.LC_POINT
	var ref: int = -1
	var seq: int = 0
	var body: int = kit.caster_body(actor)
	var shot: int = kit.caster_shot()
	if body >= 0:
		kind = SpellRuntime.LC_ACTOR
		ref = body
	elif shot >= 0:
		kind = SpellRuntime.LC_SLOT
		ref = shot
		seq = kit.caster_seq()
	kit.live_join(spell, tag, kind, ref, seq, false, lifetime, origin, way)
	kit.live_join_ends(spell, tag, kind, ref, seq, lifetime, origin, way)


## The modifiers of `modifiers` that do nothing on it once its other cards are known: its life
## matters only to a trigger that waits on it (one that fires while it lasts, or when it ends) or to
## a hold (a held Pulse strikes again every wind-up and life), so a card that only lengthens its
## life does nothing without one.
func idle_modifiers(modifiers: Array[ModifierBase], _elements: Array[ElementBase], triggers: Array[TriggerBase]) -> Array[ModifierBase]:
	var out: Array[ModifierBase] = []
	var waits: bool = false
	for trigger in triggers:
		waits = waits or TriggerBase.LIVE.has(trigger.event) or trigger.event == TriggerBase.Event.EXPIRE
	for modifier in modifiers:
		waits = waits or modifier.behaviour == ModifierBase.Behaviour.HOLD
	if waits:
		return out
	for modifier in modifiers:
		if _only_life(modifier):
			out.append(modifier)
	return out


## True when the only number of `modifier` a Pulse uses is its life (`lifetime_mult`,
## `lifetime_base`): no behaviour, and nothing of its reach, damage or cast time.
static func _only_life(modifier: ModifierBase) -> bool:
	if modifier.behaviour != ModifierBase.Behaviour.NONE:
		return false
	if not is_equal_approx(modifier.lifetime_mult, 1.0) or modifier.lifetime_base > 0.0:
		return is_equal_approx(modifier.radius_mult, 1.0) and modifier.damage_mult <= 1.0 and modifier.wind_up_mult >= 1.0 and modifier.wind_down_mult >= 1.0
	return false


## What draws its look: no look of its own (its cues, and the body it is on).
func look_drawer() -> int:
	return LOOK_NONE
