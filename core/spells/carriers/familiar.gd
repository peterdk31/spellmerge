class_name CarrierFamiliar
extends CarrierEntity
## A helper that circles its caster and casts what its triggers give it (`&"familiar"`).
## It hits nothing itself: only a blast carries hit cards and infusions.


## Each modifier behaviour (`ModifierBase.Behaviour`) on the familiar, every one (keys: see `Carrier`).
const BEHAVIOURS: Dictionary = {
	B.NONE: {"works": Works.YES, "shows": Shows.NOTHING, "why_nothing_shows": "a familiar is drawn as a plain orbit shot, without its cards' looks"},
	B.HOMING: {"works": Works.NO, "why_not": "it has nothing to aim, and a familiar is a body that hits nothing"},
	B.CHAIN: {"works": Works.NO, "why_not": "it acts on what the carrier hits, and a familiar is a body that hits nothing"},
	B.SHIELD: {"works": Works.NO, "why_not": "it blocks shots that touch the carrier or guards the caster on a move, and a familiar is a body that hits nothing"},
	B.BLAST: {"works": Works.YES, "shows": Shows.AS_EFFECT},
	B.HOLD: {"works": Works.YES, "shows": Shows.NOTHING, "why_nothing_shows": "a familiar is drawn as a plain orbit shot, without its cards' looks"},
	B.RECOIL: {"works": Works.YES, "shows": Shows.NOTHING, "why_nothing_shows": "a familiar is drawn as a plain orbit shot, without its cards' looks"},
	B.BOUNCE: {"works": Works.NO, "why_not": "it turns a shot or a beam at walls, and a familiar is a body that hits nothing"},
	B.ECHO: {"works": Works.YES, "shows": Shows.NOTHING, "why_nothing_shows": "a familiar is drawn as a plain orbit shot, without its cards' looks"},
	B.LINGER: {"works": Works.NO, "why_not": "it only changes a moving shot, and a familiar is a body that hits nothing"},
	B.HEAVY: {"works": Works.ONLY_WITH_BLAST, "shows": Shows.AS_EFFECT, "why_not": "it acts on what the carrier hits, and a familiar is a body that hits nothing (a blast would carry it)"},
	B.SIPHON: {"works": Works.NO, "why_not": "it acts on what the carrier hits, and a familiar is a body that hits nothing"},
	B.STICKY: {"works": Works.NO, "why_not": "it only changes a moving shot, and a familiar is a body that hits nothing"},
	B.MAGNET: {"works": Works.NO, "why_not": "it needs a shot or a beam that stays in the world, and a familiar is a body that hits nothing"},
	B.GHOST: {"works": Works.NO, "why_not": "it only takes a flying shot or a line through walls, and a familiar is a body that hits nothing"},
	B.SPIRAL: {"works": Works.NO, "why_not": "it only changes a moving shot, and a familiar is a body that hits nothing"},
	B.MIRROR: {"works": Works.YES, "shows": Shows.NOTHING, "why_nothing_shows": "a familiar is drawn as a plain orbit shot, without its cards' looks"},
	B.GROWTH: {"works": Works.NO, "why_not": "it grows a shot in the world or a beam, and a familiar is a body that hits nothing"},
	B.RELAY: {"works": Works.NO, "why_not": "it needs a hit of its own, and a familiar is a body that hits nothing"},
	B.RETURN: {"works": Works.NO, "why_not": "it does not fly out"},
	B.ARC: {"works": Works.NO, "why_not": "it is not a shot that stays in the air"},
	B.POSSESS: {"works": Works.NO, "why_not": "it acts on what the carrier hits, and a familiar is a body that hits nothing"},
	B.DEFLECT: {"works": Works.NO, "why_not": "it touches no shots"},
}
## Each trigger (`TriggerBase.Event`) on the familiar: "fires" (does it ever go off here?) and, when it
## never does, "why_not".
const EVENTS: Dictionary = {
	E.HIT: {"fires": false, "why_not": "a familiar hits nothing"},
	E.EXPIRE: {"fires": true},
	E.TIMER: {"fires": true},
	E.BLOCK: {"fires": false, "why_not": "nothing on it can block a shot"},
	E.KILL: {"fires": true},
	E.CAST: {"fires": true},
	E.WALL: {"fires": false, "why_not": "a familiar hits nothing"},
	E.HURT: {"fires": true},
	E.REACTION: {"fires": true},
}
## An infusion (an element card) on the familiar, with the same keys as a behaviour.
const INFUSIONS: Dictionary = {"works": Works.ONLY_WITH_BLAST, "shows": Shows.AS_EFFECT, "why_not": "a familiar hits nothing"}


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


func infusions() -> Dictionary:
	return INFUSIONS


func hits_nothing() -> String:
	return "a familiar hits nothing"


## A familiar circles its caster.
func _follows_caster() -> bool:
	return true
