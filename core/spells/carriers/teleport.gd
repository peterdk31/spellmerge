class_name CarrierTeleport
extends Carrier
## Blinks its caster `ray_length` along the aim, stopping before walls, and strikes the bodies where
## it lands (`&"teleport"`). Over at once: homing bends its way, recoil shortens it.


## How the teleport takes each modifier (`ModifierBase.Behaviour`), every one: see `Carrier`.
const BEHAVIOURS: Dictionary = {
	B.NONE: [Works.YES, Shows.NOTHING],
	B.HOMING: [Works.OWN_WAY, Shows.NOTHING],
	B.CHAIN: [Works.YES, Shows.NOTHING],
	B.SHIELD: [Works.OWN_WAY, Shows.NOTHING],
	B.BLAST: [Works.YES, Shows.AS_EFFECT],
	B.HOLD: [Works.NO, "nothing keeps it on: a teleport moves its caster at once and hits where it lands"],
	B.RECOIL: [Works.OWN_WAY, Shows.NOTHING],
	B.BOUNCE: [Works.NO, "it turns a shot or a beam at walls, and a teleport moves its caster at once and hits where it lands"],
	B.ECHO: [Works.YES, Shows.NOTHING],
	B.LINGER: [Works.NO, "it only changes a moving shot, and a teleport moves its caster at once and hits where it lands"],
	B.HEAVY: [Works.YES, Shows.NOTHING],
	B.SIPHON: [Works.YES, Shows.NOTHING],
	B.STICKY: [Works.NO, "it only changes a moving shot, and a teleport moves its caster at once and hits where it lands"],
	B.MAGNET: [Works.NO, "it needs a shot or a beam that stays in the world, and a teleport moves its caster at once and hits where it lands"],
	B.GHOST: [Works.NO, "it only takes a flying shot or a line through walls, and a teleport moves its caster at once and hits where it lands"],
	B.SPIRAL: [Works.NO, "it only changes a moving shot, and a teleport moves its caster at once and hits where it lands"],
	B.MIRROR: [Works.NO, "a move and its mirror cancel"],
	B.GROWTH: [Works.NO, "it grows a shot in the world or a beam, and a teleport moves its caster at once and hits where it lands"],
	B.RELAY: [Works.YES, Shows.NOTHING],
	B.RETURN: [Works.NO, "it does not fly out"],
	B.ARC: [Works.NO, "it is not a shot that stays in the air"],
	B.POSSESS: [Works.YES, Shows.NOTHING],
	B.DEFLECT: [Works.OWN_WAY, Shows.NOTHING],
}
## When each trigger (`TriggerBase.Event`) fires on the teleport: "" when it can, else why it never does.
const EVENTS: Dictionary = {
	E.HIT: "",
	E.EXPIRE: "",
	E.TIMER: "it is over at once",
	E.BLOCK: "",
	E.KILL: "",
	E.CAST: "",
	E.WALL: "it stops before walls",
	E.HURT: "it is over at once",
	E.REACTION: "",
}
## How the teleport takes an infusion.
const INFUSIONS: Array = [Works.YES, Shows.NOTHING]


func id() -> StringName:
	return &"teleport"


func noun() -> String:
	return "teleport"


func what() -> String:
	return "a teleport moves its caster at once and hits where it lands"


func traits() -> int:
	return HITS | REACHES | STEERS | INSTANT_HOMING


func behaviours() -> Dictionary:
	return BEHAVIOURS


func events() -> Dictionary:
	return EVENTS


func infusions() -> Array:
	return INFUSIONS


func nothing_shown_note() -> String:
	return "a teleport is over at once and draws nothing of its own: its cards show only in its hits"


## Blinks its caster (`Spells._move_caster`).
func launch(spell: CompiledSpell, tag: int, actor: int, origin: Vector2, direction: Vector2, _source: Node, _lifetime: float, chain: int, prev: int) -> int:
	return rt._move_caster(spell, tag, actor, origin, direction, chain, prev, false)


## It strikes what is where it landed (`Spells._land_strike`).
func on_move_end(spell: CompiledSpell, tag: int, actor: int, at: Vector2, heading: Vector2) -> void:
	rt._land_strike(spell, tag, actor, at, heading)
