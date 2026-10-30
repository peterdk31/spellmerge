class_name CarrierFamiliar
extends Carrier
## A helper that circles its caster and casts what its triggers give it (`FormBase.Motion.FAMILIAR`).
## It hits nothing itself: only a blast carries hit cards and infusions.


## How the familiar takes each modifier (`ModifierBase.Behaviour`), every one: see `Carrier`.
const BEHAVIOURS: Dictionary = {
	B.NONE: [Use.RUNS, Look.NONE],
	B.HOMING: [Use.WASTED, "it has nothing to aim, and a familiar is a body that hits nothing"],
	B.CHAIN: [Use.WASTED, "it acts on what the carrier hits, and a familiar is a body that hits nothing"],
	B.SHIELD: [Use.WASTED, "it blocks shots that touch the carrier or guards the caster on a move, and a familiar is a body that hits nothing"],
	B.BLAST: [Use.RUNS, Look.CUE],
	B.HOLD: [Use.RUNS, Look.NONE],
	B.RECOIL: [Use.RUNS, Look.NONE],
	B.BOUNCE: [Use.WASTED, "it turns a shot or a beam at walls, and a familiar is a body that hits nothing"],
	B.ECHO: [Use.RUNS, Look.NONE],
	B.LINGER: [Use.WASTED, "it only changes a moving shot, and a familiar is a body that hits nothing"],
	B.HEAVY: [Use.WITH_BLAST, Look.CUE, "it acts on what the carrier hits, and a familiar is a body that hits nothing (a blast would carry it)"],
	B.SIPHON: [Use.WASTED, "it acts on what the carrier hits, and a familiar is a body that hits nothing"],
	B.STICKY: [Use.WASTED, "it only changes a moving shot, and a familiar is a body that hits nothing"],
	B.MAGNET: [Use.WASTED, "it needs a shot or a beam that stays in the world, and a familiar is a body that hits nothing"],
	B.GHOST: [Use.WASTED, "it only takes a flying shot or a line through walls, and a familiar is a body that hits nothing"],
	B.SPIRAL: [Use.WASTED, "it only changes a moving shot, and a familiar is a body that hits nothing"],
	B.MIRROR: [Use.RUNS, Look.NONE],
	B.GROWTH: [Use.WASTED, "it grows a shot in the world or a beam, and a familiar is a body that hits nothing"],
	B.RELAY: [Use.WASTED, "it needs a hit of its own, and a familiar is a body that hits nothing"],
	B.RETURN: [Use.WASTED, "it does not fly out"],
	B.ARC: [Use.WASTED, "it is not a shot that stays in the air"],
	B.POSSESS: [Use.WASTED, "it acts on what the carrier hits, and a familiar is a body that hits nothing"],
	B.DEFLECT: [Use.WASTED, "it touches no shots"],
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
const INFUSIONS: Array = [Use.WITH_BLAST, Look.CUE, "a familiar hits nothing"]


func motion() -> int:
	return FormBase.Motion.FAMILIAR


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


func look_note() -> String:
	return "a familiar is drawn as a plain orbit shot, without its cards' looks"


## Asks `ai` for a familiar a step ahead along `heading` (`Spells._spawn_entity`).
func shoot(spell: CompiledSpell, tag: int, actor: int, origin: Vector2, _direction: Vector2, heading: Vector2, _n: int, _count: int, _source: Node, lifetime: float, _chain: int, _prev: int) -> int:
	return rt._spawn_entity(spell, tag, actor, &"familiar", rt._placed_at(spell, origin, heading), heading, lifetime)
