class_name CarrierDecoy
extends CarrierEntity
## A still copy of its caster that enemies target, for `lifetime` seconds (`&"decoy"`).
## It hits nothing itself: only a blast carries hit cards and infusions; its shield or deflect
## guards it.


## How the decoy takes each modifier (`ModifierBase.Behaviour`), every one: see `Carrier`.
const BEHAVIOURS: Dictionary = {
	B.NONE: [Works.YES, Shows.NOTHING],
	B.HOMING: [Works.NO, "it has nothing to aim, and a decoy is a body that hits nothing"],
	B.CHAIN: [Works.NO, "it acts on what the carrier hits, and a decoy is a body that hits nothing"],
	B.SHIELD: [Works.OWN_WAY, Shows.NOTHING],
	B.BLAST: [Works.YES, Shows.AS_EFFECT],
	B.HOLD: [Works.YES, Shows.NOTHING],
	B.RECOIL: [Works.YES, Shows.NOTHING],
	B.BOUNCE: [Works.NO, "it turns a shot or a beam at walls, and a decoy is a body that hits nothing"],
	B.ECHO: [Works.YES, Shows.NOTHING],
	B.LINGER: [Works.NO, "it only changes a moving shot, and a decoy is a body that hits nothing"],
	B.HEAVY: [Works.ONLY_WITH_BLAST, Shows.AS_EFFECT, "it acts on what the carrier hits, and a decoy is a body that hits nothing (a blast would carry it)"],
	B.SIPHON: [Works.NO, "it acts on what the carrier hits, and a decoy is a body that hits nothing"],
	B.STICKY: [Works.NO, "it only changes a moving shot, and a decoy is a body that hits nothing"],
	B.MAGNET: [Works.NO, "it needs a shot or a beam that stays in the world, and a decoy is a body that hits nothing"],
	B.GHOST: [Works.NO, "it only takes a flying shot or a line through walls, and a decoy is a body that hits nothing"],
	B.SPIRAL: [Works.NO, "it only changes a moving shot, and a decoy is a body that hits nothing"],
	B.MIRROR: [Works.YES, Shows.NOTHING],
	B.GROWTH: [Works.NO, "it grows a shot in the world or a beam, and a decoy is a body that hits nothing"],
	B.RELAY: [Works.NO, "it needs a hit of its own, and a decoy is a body that hits nothing"],
	B.RETURN: [Works.NO, "it does not fly out"],
	B.ARC: [Works.NO, "it is not a shot that stays in the air"],
	B.POSSESS: [Works.NO, "it acts on what the carrier hits, and a decoy is a body that hits nothing"],
	B.DEFLECT: [Works.OWN_WAY, Shows.NOTHING],
}
## When each trigger (`TriggerBase.Event`) fires on the decoy: "" when it can, else why it never does.
const EVENTS: Dictionary = {
	E.HIT: "a decoy hits nothing",
	E.EXPIRE: "",
	E.TIMER: "",
	E.BLOCK: "",
	E.KILL: "",
	E.CAST: "",
	E.WALL: "a decoy hits nothing",
	E.HURT: "",
	E.REACTION: "",
}
## How the decoy takes an infusion.
const INFUSIONS: Array = [Works.ONLY_WITH_BLAST, Shows.AS_EFFECT, "a decoy hits nothing"]


func id() -> StringName:
	return &"decoy"


func noun() -> String:
	return "decoy"


func what() -> String:
	return "a decoy is a body that hits nothing"


func traits() -> int:
	return LASTS | GUARDS | SPEED | SHOTS | SPREAD


func behaviours() -> Dictionary:
	return BEHAVIOURS


func events() -> Dictionary:
	return EVENTS


func infusions() -> Array:
	return INFUSIONS


func hits_nothing() -> String:
	return "a decoy hits nothing"


func nothing_shown_note() -> String:
	return "a decoy wears its caster's look, not its cards'"


## The shield charges of the decoy with `tag`, and whether it deflects (rules R4g), for Entities as
## it makes one; none for a tag no build knows.
func decoy_shield(tag: int) -> int:
	var spell: CompiledSpell = rt._profiles.get(tag)
	return roundi(spell.behaviour(ModifierBase.Behaviour.SHIELD)) if spell != null else 0


func decoy_deflects(tag: int) -> bool:
	var spell: CompiledSpell = rt._profiles.get(tag)
	return spell != null and spell.behaviour(ModifierBase.Behaviour.DEFLECT) > 0.0


## A decoy's guard (rules R4g), asked by Entities every step for each decoy with a shield or
## deflect: the shots of other teams than `actor`'s within `reach` of `at` are deflected outward
## by the decoy with `tag` when it deflects, else stopped while its `charges` last, each sending
## its block (`on block`); the one guard of swings and slams (`_guard`). Returns the charges left.
func guard_decoy(actor: int, tag: int, at: Vector2, reach: float, charges: int) -> int:
	var spell: CompiledSpell = rt._profiles.get(tag)
	if spell == null or rt.projectiles == null:
		return charges
	var deflects: bool = spell.behaviour(ModifierBase.Behaviour.DEFLECT) > 0.0
	if not deflects and charges <= 0:
		return charges
	var found: int = rt.projectiles.shots_in_wedge(actor, at, Vector2.RIGHT, 1, -PI, PI, reach)
	return rt._guard(found, actor, tag, deflects, charges, at, Vector2.INF, &"decoy")
