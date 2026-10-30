class_name CarrierDecoy
extends CarrierEntity
## A still copy of its caster that enemies target, for `lifetime` seconds (`&"decoy"`).
## It hits nothing itself: only a blast carries hit cards and infusions; its shield or deflect
## guards it.


## Each modifier behaviour (`ModifierBase.Behaviour`) on the decoy, every one (keys: see `Carrier`).
const BEHAVIOURS: Dictionary = {
	B.NONE: {"works": Works.YES, "shows": Shows.NOTHING, "why_nothing_shows": "a decoy wears its caster's look, not its cards'"},
	B.HOMING: {"works": Works.NO, "why_not": "it has nothing to aim, and a decoy is a body that hits nothing"},
	B.CHAIN: {"works": Works.NO, "why_not": "it acts on what the carrier hits, and a decoy is a body that hits nothing"},
	B.SHIELD: {"works": Works.OWN_WAY, "shows": Shows.NOTHING, "why_nothing_shows": "a decoy wears its caster's look, not its cards'"},
	B.BLAST: {"works": Works.YES, "shows": Shows.AS_EFFECT},
	B.HOLD: {"works": Works.YES, "shows": Shows.NOTHING, "why_nothing_shows": "a decoy wears its caster's look, not its cards'"},
	B.RECOIL: {"works": Works.YES, "shows": Shows.NOTHING, "why_nothing_shows": "a decoy wears its caster's look, not its cards'"},
	B.BOUNCE: {"works": Works.NO, "why_not": "it turns a shot or a beam at walls, and a decoy is a body that hits nothing"},
	B.ECHO: {"works": Works.YES, "shows": Shows.NOTHING, "why_nothing_shows": "a decoy wears its caster's look, not its cards'"},
	B.LINGER: {"works": Works.NO, "why_not": "it only changes a moving shot, and a decoy is a body that hits nothing"},
	B.HEAVY: {"works": Works.ONLY_WITH_BLAST, "shows": Shows.AS_EFFECT, "why_not": "it acts on what the carrier hits, and a decoy is a body that hits nothing (a blast would carry it)"},
	B.SIPHON: {"works": Works.NO, "why_not": "it acts on what the carrier hits, and a decoy is a body that hits nothing"},
	B.STICKY: {"works": Works.NO, "why_not": "it only changes a moving shot, and a decoy is a body that hits nothing"},
	B.MAGNET: {"works": Works.NO, "why_not": "it needs a shot or a beam that stays in the world, and a decoy is a body that hits nothing"},
	B.GHOST: {"works": Works.NO, "why_not": "it only takes a flying shot or a line through walls, and a decoy is a body that hits nothing"},
	B.SPIRAL: {"works": Works.NO, "why_not": "it only changes a moving shot, and a decoy is a body that hits nothing"},
	B.MIRROR: {"works": Works.YES, "shows": Shows.NOTHING, "why_nothing_shows": "a decoy wears its caster's look, not its cards'"},
	B.GROWTH: {"works": Works.NO, "why_not": "it grows a shot in the world or a beam, and a decoy is a body that hits nothing"},
	B.RELAY: {"works": Works.NO, "why_not": "it needs a hit of its own, and a decoy is a body that hits nothing"},
	B.RETURN: {"works": Works.NO, "why_not": "it does not fly out"},
	B.ARC: {"works": Works.NO, "why_not": "it is not a shot that stays in the air"},
	B.POSSESS: {"works": Works.NO, "why_not": "it acts on what the carrier hits, and a decoy is a body that hits nothing"},
	B.DEFLECT: {"works": Works.OWN_WAY, "shows": Shows.NOTHING, "why_nothing_shows": "a decoy wears its caster's look, not its cards'"},
}
## Each trigger (`TriggerBase.Event`) on the decoy: "fires" (does it ever go off here?) and, when it
## never does, "why_not".
const EVENTS: Dictionary = {
	E.HIT: {"fires": false, "why_not": "a decoy hits nothing"},
	E.EXPIRE: {"fires": true},
	E.TIMER: {"fires": true},
	E.BLOCK: {"fires": true},
	E.KILL: {"fires": true},
	E.CAST: {"fires": true},
	E.WALL: {"fires": false, "why_not": "a decoy hits nothing"},
	E.HURT: {"fires": true},
	E.REACTION: {"fires": true},
}
## An infusion (an element card) on the decoy, with the same keys as a behaviour.
const INFUSIONS: Dictionary = {"works": Works.ONLY_WITH_BLAST, "shows": Shows.AS_EFFECT, "why_not": "a decoy hits nothing"}


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


func infusions() -> Dictionary:
	return INFUSIONS


func hits_nothing() -> String:
	return "a decoy hits nothing"


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
