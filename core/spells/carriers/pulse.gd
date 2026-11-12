class_name CarrierPulse
extends Carrier
## The base of the Pulse card's three carriers (docs/CARRIERS.md, "Pulse: a strike round what casts
## it"; props W9a, owner 2026-11-12: it replaced the compiler's fallback carriers, "a custom rule").
## The Pulse card (`content/spells/carriers/pulse/`) is one strike round whatever casts it: the caster's
## body in a cast's own group (`CarrierPulseCaster`, `&"pulse"`, the id the card names); in a payload,
## what fired it, a body or a shot (`CarrierPulseBearer`), or the point it began at when nothing else
## can have (`CarrierPulsePoint`). The compiler picks which from who may cast the group
## (`Carriers.placed`, `Carrier.payload_cast_by`), so each keeps its own yes/no answers.
##
## What it does: one strike of everything round the point it is cast at within `spell.radius` (as
## a card scales it) or as wide as its blast, **sparing what casts it** (it never leaves that:
## `MELEE` where a body or shot carries it). A blast on it is that strike, so it explodes there. It
## strikes only when a card on it acts on hits (`strikes`): a bare Pulse, or one with only cards
## that guard (a shield, a deflect) or keep it (a hold), strikes nothing. Then it **lasts** its
## `lifetime`, round what casts it, for the triggers that need a carrier that lasts (a timer, on
## hurt, on recast); a hold keeps it until its staff is cast again, striking again every wind-up
## and life when it strikes (`REPEATS_HELD`, as a held swing).


func traits() -> int:
	return HITS | LASTS | REPEATS_HELD


## Its hits feel like an explosion (`HitProfile.kind`).
func hit_kind() -> StringName:
	return &"burst"


## What fires the payloads of its triggers that fire while it lasts (a timer, on hurt, on recast)
## or as it ends (on expire): what casts it carries it, so it is that (`by`), a body, a shot or a
## point. The rest as any carrier's (`Carrier.payload_cast_by`).
func payload_cast_by(event: int, spell: CompiledSpell, by: int) -> int:
	if TriggerBase.LIVE.has(event) or event == TriggerBase.Event.EXPIRE:
		return by
	return super(event, spell, by)


## One strike round `origin` (when it strikes), sparing what casts it; then, with a trigger that
## fires while it lasts, it is listed round what casts it for its life (`CarrierKit.live_join`):
## the body, the shot (ending with it) or the point.
func launch(spell: CompiledSpell, tag: int, actor: int, origin: Vector2, direction: Vector2, _source: Node, lifetime: float, _chain: int, _prev: int) -> int:
	if not origin.is_finite():
		return 0
	var blast: float = spell.behaviour(ModifierBase.Behaviour.BLAST)
	var reach: float = maxf(spell.radius, blast)
	var way: Vector2 = direction if direction.is_finite() and not direction.is_zero_approx() else Vector2.RIGHT
	if spell.strikes and blast > 0.0 and kit.events != null:
		kit.set_cue_tag(tag)
		kit.events.cue_shown.emit(actor, spell.cue_of(ModifierBase.Behaviour.BLAST), origin, Vector2.ZERO, blast, spell.tint, spell.look)
		kit.set_cue_tag(0)
	if spell.strikes and kit.events != null:
		# The pulse itself: a ring of its cards' motes out to its reach (the card's `shown_cue`).
		# A bare Pulse strikes nothing and shows nothing (a held watch round a fire pit).
		kit.set_cue_tag(tag)
		kit.events.carrier_shown.emit(actor, spell.carrier_card_id, origin, way, reach, spell.tint, spell.look)
		kit.set_cue_tag(0)
	_before_strike(spell, tag, actor, origin, reach)
	if spell.strikes:
		var body: int = kit.caster_body(actor)
		kit.strike_round(spell, tag, actor, origin, way, reach, spell.echo_hit if kit.is_echo(spell) else null, kit.spared(spell, kit.body_node(body)))
	_after_strike(spell, tag, actor, origin)
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


## True when a card on it acts on hits, so it strikes: an infusion, a hit trigger (on hit, on kill,
## on reaction: its strike is their hit), or a modifier that does more than guard (a shield, a
## deflect: `MEETS_SHOTS` only; owner, 2026-11-06: a lone Shield or Deflect, on you or on a decoy,
## costs no health) or keep it (a hold: `LASTS` only). A bare Pulse strikes nothing.
func strikes(modifiers: Array[ModifierBase], elements: Array[ElementBase], triggers: Array[TriggerBase]) -> bool:
	if not elements.is_empty():
		return true
	for trigger in triggers:
		if trigger.event in [TriggerBase.Event.HIT, TriggerBase.Event.KILL, TriggerBase.Event.REACTION]:
			return true
	for modifier in modifiers:
		var needs: Dictionary = (ModifierBase.RULES.get(modifier.behaviour, {}) as Dictionary).get("needs", {}) as Dictionary
		var any: int = int(needs.get("any", 0))
		if any != CarrierTraits.MEETS_SHOTS and any != CarrierTraits.LASTS:
			return true
	return false


## The modifiers of `modifiers` that do nothing on it once its other cards are known: its life
## matters only to a trigger that waits on it (one that fires while it lasts, or when it ends) or to
## a hold (a held Pulse strikes again every wind-up and life), so a card that only lengthens its life
## does nothing without one; and a hold keeps it only for what it does again or while it lasts, so
## on a Pulse that strikes nothing and has no trigger that fires while it lasts, a hold is wasted.
func idle_modifiers(modifiers: Array[ModifierBase], elements: Array[ElementBase], triggers: Array[TriggerBase]) -> Array[ModifierBase]:
	var out: Array[ModifierBase] = []
	var waits: bool = false
	var lives: bool = false
	for trigger in triggers:
		lives = lives or TriggerBase.LIVE.has(trigger.event)
		waits = waits or lives or trigger.event == TriggerBase.Event.EXPIRE
	var held: bool = false
	for modifier in modifiers:
		held = held or modifier.behaviour == ModifierBase.Behaviour.HOLD
	var hold_idle: bool = not lives and not strikes(modifiers, elements, triggers)
	for modifier in modifiers:
		if modifier.behaviour == ModifierBase.Behaviour.HOLD and hold_idle:
			out.append(modifier)
		elif not waits and not (held and not hold_idle) and _only_life(modifier):
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


## What it does where it lands before its strike, `reach` pixels round `at` (a deflect turns the
## shots there first, as a teleport's landing does).
func _before_strike(_spell: CompiledSpell, _tag: int, _actor: int, _at: Vector2, _reach: float) -> void:
	pass


## What it does after its strike (a shield, which the strike would otherwise spend).
func _after_strike(_spell: CompiledSpell, _tag: int, _actor: int, _at: Vector2) -> void:
	pass


## What draws its look: no look of its own (its cues, and the body it is on).
func look_drawer() -> int:
	return LOOK_NONE
