class_name CarrierDecoy
extends CarrierEntity
## A copy of its caster that the other teams target, for `lifetime` seconds (`&"decoy"`): an
## actor `ai` makes (`Entities`) that aims itself at the nearest foe, so what its triggers cast goes
## at its foes. Homing makes it creep toward its target, as a rune (`homing_reach`). It hits nothing
## itself: only a blast carries hit cards and infusions. It is a regular actor (owner, 2026-11-06):
## its shield is a barrier on its body for its life, and its deflect turns the shots round it once,
## as it appears, as on a caster (`_body_made`). What its triggers fire is cast from its body, and a
## payload's left-over cards land there (`CASTS_FROM_BODY`, `CarrierBearer`).


func id() -> StringName:
	return &"decoy"



## The decoys of the runtime `spells` (its bound `decoy` carrier, `Spells.carrier`), for what reads
## its own getters (the looks, `ai`, the actor's mover, the tests).
static func of(spells: SpellRuntime) -> CarrierDecoy:
	return spells.carrier(&"decoy") as CarrierDecoy


func traits() -> int:
	return LASTS | STEERS | SHOTS | SPREAD | MEETS_SHOTS | SPAWNS | CASTS_FROM_BODY


## How far the decoy with `tag` creeps toward a target (its homing reach); 0 when it does not
## home, or for a tag no build knows.
func homing_reach(tag: int) -> float:
	var spell: CompiledSpell = kit.spell_of(tag)
	return spell.homing_range if spell != null else 0.0


## Its body `body` (an actor Combat already knows) stands at `at`: a deflect turns the other teams'
## shots round it once, now (`CarrierKit.turn_shots_round`, as a caster's deflect is cast), and a
## shield is a barrier on it for its `lifetime` (`CasterMoves.shield_caster`, as a caster's). A decoy
## placed again is a new actor in Combat, so it never keeps an old one's barrier.
func _body_made(spell: CompiledSpell, tag: int, actor: int, body: int, at: Vector2, lifetime: float) -> void:
	if spell.behaviour(ModifierBase.Behaviour.DEFLECT) > 0.0:
		var centre: Vector2 = kit.projectiles.get_anchor(body) if kit.projectiles != null else Vector2.INF
		kit.turn_shots_round(actor, tag, centre if centre.is_finite() else at, 0.0, id())
	kit.moves().shield_caster(spell, tag, body, lifetime)
