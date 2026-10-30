class_name CarrierFamiliar
extends CarrierEntity
## A helper that circles its caster and casts what its triggers give it (`&"familiar"`).
## It hits nothing itself: only a blast carries hit cards and infusions.


## How the familiar takes each modifier (`ModifierBase.Behaviour`), every one: see `Carrier`.
const BEHAVIOURS: Dictionary = {
	B.NONE: [Works.YES, Shows.NOTHING],
	B.HOMING: [Works.NO, "it has nothing to aim, and a familiar is a body that hits nothing"],
	B.CHAIN: [Works.NO, "it acts on what the carrier hits, and a familiar is a body that hits nothing"],
	B.SHIELD: [Works.NO, "it blocks shots that touch the carrier or guards the caster on a move, and a familiar is a body that hits nothing"],
	B.BLAST: [Works.YES, Shows.AS_EFFECT],
	B.HOLD: [Works.YES, Shows.NOTHING],
	B.RECOIL: [Works.YES, Shows.NOTHING],
	B.BOUNCE: [Works.NO, "it turns a shot or a beam at walls, and a familiar is a body that hits nothing"],
	B.ECHO: [Works.YES, Shows.NOTHING],
	B.LINGER: [Works.NO, "it only changes a moving shot, and a familiar is a body that hits nothing"],
	B.HEAVY: [Works.ONLY_WITH_BLAST, Shows.AS_EFFECT, "it acts on what the carrier hits, and a familiar is a body that hits nothing (a blast would carry it)"],
	B.SIPHON: [Works.NO, "it acts on what the carrier hits, and a familiar is a body that hits nothing"],
	B.STICKY: [Works.NO, "it only changes a moving shot, and a familiar is a body that hits nothing"],
	B.MAGNET: [Works.NO, "it needs a shot or a beam that stays in the world, and a familiar is a body that hits nothing"],
	B.GHOST: [Works.NO, "it only takes a flying shot or a line through walls, and a familiar is a body that hits nothing"],
	B.SPIRAL: [Works.NO, "it only changes a moving shot, and a familiar is a body that hits nothing"],
	B.MIRROR: [Works.YES, Shows.NOTHING],
	B.GROWTH: [Works.NO, "it grows a shot in the world or a beam, and a familiar is a body that hits nothing"],
	B.RELAY: [Works.NO, "it needs a hit of its own, and a familiar is a body that hits nothing"],
	B.RETURN: [Works.NO, "it does not fly out"],
	B.ARC: [Works.NO, "it is not a shot that stays in the air"],
	B.POSSESS: [Works.NO, "it acts on what the carrier hits, and a familiar is a body that hits nothing"],
	B.DEFLECT: [Works.NO, "it touches no shots"],
}
## When each trigger (`TriggerBase.Event`) fires on the familiar: "" when it can, else why it never does.
const EVENTS: Dictionary = {
	E.HIT: "a familiar hits nothing",
	E.EXPIRE: "",
	E.TIMER: "",
	E.BLOCK: "nothing on it can block a shot",
	E.KILL: "",
	E.CAST: "",
	E.WALL: "a familiar hits nothing",
	E.HURT: "",
	E.REACTION: "",
}
## How the familiar takes an infusion.
const INFUSIONS: Array = [Works.ONLY_WITH_BLAST, Shows.AS_EFFECT, "a familiar hits nothing"]


func id() -> StringName:
	return &"familiar"


func noun() -> String:
	return "familiar"


func what() -> String:
	return "a familiar is a body that hits nothing"


func traits() -> int:
	return LASTS | SPEED | SHOTS | SPREAD


func behaviours() -> Dictionary:
	return BEHAVIOURS


func events() -> Dictionary:
	return EVENTS


func infusions() -> Array:
	return INFUSIONS


func hits_nothing() -> String:
	return "a familiar hits nothing"


func nothing_shown_note() -> String:
	return "a familiar is drawn as a plain orbit shot, without its cards' looks"


## A familiar circles its caster.
func _follows_caster() -> bool:
	return true
