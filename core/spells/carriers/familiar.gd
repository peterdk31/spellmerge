class_name CarrierFamiliar
extends CarrierEntity
## A helper that circles its caster and casts what its triggers give it (`&"familiar"`).
## It hits nothing itself: only a blast carries hit cards and infusions.


## Modifier cards that do nothing on a familiar, with the sentence the builder shows after
## "<Card> does nothing on a Familiar: ". Every card not listed does something here.
const DOES_NOTHING: Dictionary = {
	B.HOMING: "it has nothing to aim, and a familiar is a body that hits nothing",
	B.CHAIN: "it acts on what the carrier hits, and a familiar is a body that hits nothing",
	B.SHIELD: "it blocks shots that touch the carrier or guards the caster on a move, and a familiar is a body that hits nothing",
	B.BOUNCE: "it turns a shot or a beam at walls, and a familiar is a body that hits nothing",
	B.LINGER: "it only changes a moving shot, and a familiar is a body that hits nothing",
	B.HEAVY: "it acts on what the carrier hits, and a familiar is a body that hits nothing (a blast would carry it)",
	B.SIPHON: "it acts on what the carrier hits, and a familiar is a body that hits nothing",
	B.STICKY: "it only changes a moving shot, and a familiar is a body that hits nothing",
	B.MAGNET: "it needs a shot or a beam that stays in the world, and a familiar is a body that hits nothing",
	B.GHOST: "it only takes a flying shot or a line through walls, and a familiar is a body that hits nothing",
	B.SPIRAL: "it only changes a moving shot, and a familiar is a body that hits nothing",
	B.GROWTH: "it grows a shot in the world or a beam, and a familiar is a body that hits nothing",
	B.RELAY: "it needs a hit of its own, and a familiar is a body that hits nothing",
	B.RETURN: "it does not fly out",
	B.ARC: "it is not a shot that stays in the air",
	B.POSSESS: "it acts on what the carrier hits, and a familiar is a body that hits nothing",
	B.DEFLECT: "it touches no shots",
}
## Trigger cards that never go off on a familiar, with the sentence the builder shows.
const NEVER_FIRES: Dictionary = {
	E.HIT: "a familiar hits nothing",
	E.BLOCK: "nothing on it can block a shot",
	E.WALL: "a familiar hits nothing",
}


func id() -> StringName:
	return &"familiar"


func noun() -> String:
	return "familiar"


func what() -> String:
	return "a familiar is a body that hits nothing"


func traits() -> int:
	return LASTS | SPEED | SHOTS | SPREAD


func does_nothing() -> Dictionary:
	return DOES_NOTHING


func never_fires() -> Dictionary:
	return NEVER_FIRES


func hits_nothing() -> String:
	return "a familiar hits nothing"


## A familiar circles its caster.
func _follows_caster() -> bool:
	return true
