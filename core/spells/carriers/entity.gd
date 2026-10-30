class_name CarrierEntity
extends Carrier
## A carrier that is a body `ai` makes (a decoy, a familiar: `entity_spawn_requested`), a step ahead
## along the aim (`Spells._placed_at`). It counts as a live shot of its tag until `ai` says it
## ended (`entity_ended`, which `Spells` hands to the carrier the entity's kind names), so its
## build stays known while it lives; its `blast` and `on expire` payload happen where it ended. A
## `hold` keeps it until its staff is cast again (`switch_off`).

## tag -> entities (decoys, familiars) alive that came from it; each counts as a live shot
var _entities: Dictionary = {}


## Asks `ai` for one a step ahead along `heading`.
func shoot(spell: CompiledSpell, tag: int, actor: int, origin: Vector2, _direction: Vector2, heading: Vector2, _n: int, _count: int, _source: Node, lifetime: float, _chain: int, _prev: int) -> int:
	return _spawn(spell, tag, actor, rt._placed_at(spell, origin, heading), heading, lifetime)


## True when it circles its caster (a familiar); else it stays where it was made.
func _follows_caster() -> bool:
	return false


## A held one is switched off: `ai` is asked to end it, and it ends as any.
func switch_off(tag: int) -> void:
	if _entities.has(tag) and rt.events != null:
		rt.events.entity_end_requested.emit(SpellTag.caster_of(tag), tag)


func clear() -> void:
	_entities.clear()


## One entity: `ai` makes it at `at` (`entity_spawn_requested`, `lifetime`
## seconds, or until ended for a `hold`). It counts as a live shot of `tag` until `entity_ended`,
## so its build stays known while it lives; its timer fires along `heading`. Returns 1 when asked for.
func _spawn(spell: CompiledSpell, tag: int, actor: int, at: Vector2, heading: Vector2, lifetime: float) -> int:
	var kind: StringName = id()
	if rt.events == null or not rt._profiles.has(tag):
		return 0
	var seconds: float = INF if lifetime >= SpellLimits.HOLD_LIFETIME else lifetime
	var anchor: int = _entity_caster()
	# Where it is: a decoy stays where it was made, a familiar circles its caster.
	var where: int = SpellRuntime.LC_POINT
	if _follows_caster() and anchor != -2:
		where = SpellRuntime.LC_ACTOR if anchor == -1 else SpellRuntime.LC_SLOT
	var ref: int = actor if where == SpellRuntime.LC_ACTOR else anchor
	_entities[tag] = _entities.get(tag, 0) + 1
	rt.shot_started(tag)
	rt.events.entity_spawn_requested.emit(actor, kind, at, seconds, tag, anchor)
	rt._lc_join(spell, tag, where, ref, rt.projectiles.get_seq_of(ref) if where == SpellRuntime.LC_SLOT else 0, false, seconds, at, heading)
	return 1


## What an entity circles or copies, for `entity_spawn_requested`: the wizard (-1), the shot that
## cast it, or nothing (-2: it stays where it was made).
func _entity_caster() -> int:
	if rt._caster == SpellRuntime.CASTER_WIZARD:
		return -1
	var shot: int = rt._caster_shot()
	return shot if shot >= 0 else -2


## An entity of this actor ended where it stood (`entity_ended`, handed on by `Spells`): its `blast` and its `on expire` payload happen
## there (the end point), then it stops counting as a live shot.
func entity_ended(actor: int, position: Vector2, tag: int) -> void:
	if not SpellTag.is_spell_tag(tag) or actor != SpellTag.caster_of(tag):
		return
	var count: int = _entities.get(tag, 0)
	if count <= 0:
		return
	if count == 1:
		_entities.erase(tag)
	else:
		_entities[tag] = count - 1
	rt._lc_leave(tag, false)
	var spell: CompiledSpell = rt._profiles.get(tag)
	if spell != null and position.is_finite():
		rt._blast(spell, tag, actor, position)
		if spell.payload != null and spell.trigger_event == TriggerBase.Event.EXPIRE:
			rt._fire(spell.payload, actor, SpellTag.staff_of(tag), SpellTag.generation_of(tag), position, Vector2.RIGHT, null, SpellRuntime.CASTER_POINT)
	rt.shot_ended(tag)


## A revoked build's entities are told to end, and forgotten (their `entity_ended` is then ignored).
func end_of(tag: int) -> void:
	rt._lc_leave(tag, true)
	if _entities.erase(tag) and rt.events != null:
		rt.events.entity_end_requested.emit(SpellTag.caster_of(tag), tag)
