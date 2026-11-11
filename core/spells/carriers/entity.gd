class_name CarrierEntity
extends Carrier
## A carrier that is a body `ai` makes (a decoy, a familiar: `entity_spawn_requested`), a step ahead
## along the aim (`Spells._placed_at`). A decoy is an actor: what its triggers cast leaves its body
## along the way it aims (it aims itself at its foes). It counts as a live shot of its tag until `ai` says it
## ended (`entity_ended`, which `Spells` hands to the carrier the entity's kind names), so its
## build stays known while it lives; its `blast` and `on expire` payload happen where it ended. A
## `hold` keeps it until its staff is cast again (`switch_off`).

## tag -> entities (decoys, familiars) alive that came from it; each counts as a live shot
var _entities: Dictionary = {}


## Asks `ai` for one a step ahead along `heading`.
func shoot(spell: CompiledSpell, tag: int, actor: int, origin: Vector2, _direction: Vector2, heading: Vector2, _n: int, _count: int, _source: Node, lifetime: float, _chain: int, _prev: int) -> int:
	return _spawn(spell, tag, actor, kit.placed_at(spell, actor, origin, heading), heading, lifetime)


func step_order() -> int:
	return 3


## A held one is switched off: `ai` is asked to end it, and it ends as any.
func switch_off(tag: int) -> void:
	if _entities.has(tag) and kit.events != null:
		kit.events.entity_end_requested.emit(SpellTag.caster_of(tag), tag)


func clear() -> void:
	_entities.clear()


## One entity: `ai` makes it at `at` (`entity_spawn_requested`, `lifetime`
## seconds, or until ended for a `hold`). It counts as a live shot of `tag` until `entity_ended`,
## so its build stays known while it lives; its timer fires along `heading`. Returns 1 when asked for.
func _spawn(spell: CompiledSpell, tag: int, actor: int, at: Vector2, heading: Vector2, lifetime: float) -> int:
	var kind: StringName = id()
	if kit.events == null or kit.spell_of(tag) == null:
		return 0
	var seconds: float = INF if lifetime >= SpellLimits.HOLD_LIFETIME else lifetime
	var anchor: int = _entity_caster(actor)
	_entities[tag] = _entities.get(tag, 0) + 1
	kit.shot_started(tag)
	# Where it is: a body Entities made (a decoy, an actor), which casts along its own aim; else a
	# point, where it was made, which Entities moves along with a familiar's orb
	# (`Spells.familiar_at`, by its key), so the familiar casts from its orb (rules R4 F8).
	var key: int = kit.request_entity(actor, kind, at, seconds, tag, anchor)
	kit.events.form_shown.emit(actor, spell.form_id, at, heading, 0.0, spell.tint, spell.look)
	var body: int = kit.entity_body()
	if body >= 0:
		kit.live_join(spell, tag, SpellRuntime.LC_ACTOR, body, key, false, seconds, at, heading)
		_body_made(spell, tag, actor, body, at, lifetime)
	else:
		kit.live_join(spell, tag, SpellRuntime.LC_POINT, -1, key, false, seconds, at, heading)
	return 1


## The entity is a body, the actor `body`, standing at `at` for `lifetime` seconds (a hold's is
## SpellLimits.HOLD_LIFETIME): Combat knows it by now (Entities put it in the world). What the
## carrier does to it as it appears (a decoy's shield and deflect, `CarrierDecoy`).
func _body_made(_spell: CompiledSpell, _tag: int, _actor: int, _body: int, _at: Vector2, _lifetime: float) -> void:
	pass


## What an entity of `actor` circles, for `entity_spawn_requested`: its caster (`CarrierKit.caster`),
## the actor's own body as CASTER_BODY (-1), another actor's body (`SpellRuntime.body_caster`), the
## shot that cast it, or the point (-2: it stays where it was made).
func _entity_caster(actor: int) -> int:
	var caster: int = kit.caster()
	return SpellRuntime.CASTER_BODY if SpellRuntime.body_of(caster, actor) == actor else caster


## An entity of this actor ended where it stood (`entity_ended`, handed on by `Spells`): its `blast` and its `on expire` payload happen
## there (the end point), then it stops counting as a live shot. `key` is the one it was asked for
## under (`Spells.entity_key`, named by Entities as it sends the end): that entity's timer and
## `on hurt` leave, no other's of its tag; 0 when unknown (then one of the tag's leaves).
func entity_ended(actor: int, position: Vector2, tag: int, key: int = 0) -> void:
	if not SpellTag.is_spell_tag(tag) or actor != SpellTag.caster_of(tag):
		return
	var count: int = _entities.get(tag, 0)
	if count <= 0:
		return
	if count == 1:
		_entities.erase(tag)
	else:
		_entities[tag] = count - 1
	if key != 0:
		kit.live_leave_key(tag, key)
	else:
		kit.live_leave(tag, false)
	var spell: CompiledSpell = kit.spell_of(tag)
	if spell != null and position.is_finite():
		if kit.events != null:
			kit.events.carrier_ended.emit(actor, spell.form_id, position, Vector2.RIGHT, spell.radius, spell.tint, spell.look)
		kit.blast(spell, tag, actor, position)
		for trigger in spell.triggers:
			if trigger.event == TriggerBase.Event.EXPIRE:
				kit.fire(trigger.payload, actor, SpellTag.staff_of(tag), SpellTag.generation_of(tag), position, Vector2.RIGHT, null, SpellRuntime.CASTER_POINT)
	kit.shot_ended(tag)


## A revoked build's entities are told to end, and forgotten (their `entity_ended` is then ignored).
func end_of(tag: int) -> void:
	kit.live_leave(tag, true)
	if _entities.erase(tag) and kit.events != null:
		kit.events.entity_end_requested.emit(SpellTag.caster_of(tag), tag)


## What draws its look: no look of its own (cues, or a body that is not the card's).
func look_drawer() -> int:
	return LOOK_NONE
