class_name CarrierWall
extends Carrier
## `shots` still, solid shots in a line across the aim, `spread` pixels apart: a short-lived wall that
## stands through every hit (`&"wall"`). Homing makes it creep toward a target, as a rune.


## How the wall takes each modifier (`ModifierBase.Behaviour`), every one: see `Carrier`.
const BEHAVIOURS: Dictionary = {
	B.NONE: [Works.YES, Shows.DRAWN],
	B.HOMING: [Works.YES, Shows.DRAWN],
	B.CHAIN: [Works.YES, Shows.DRAWN],
	B.SHIELD: [Works.YES, Shows.DRAWN],
	B.BLAST: [Works.YES, Shows.AS_EFFECT],
	B.HOLD: [Works.YES, Shows.DRAWN],
	B.RECOIL: [Works.YES, Shows.DRAWN],
	B.BOUNCE: [Works.NO, "it turns a shot or a beam at walls, and a wall stands still through every hit"],
	B.ECHO: [Works.YES, Shows.DRAWN],
	B.LINGER: [Works.NO, "it does not move"],
	B.HEAVY: [Works.YES, Shows.DRAWN],
	B.SIPHON: [Works.YES, Shows.DRAWN],
	B.STICKY: [Works.NO, "it does not move"],
	B.MAGNET: [Works.YES, Shows.DRAWN],
	B.GHOST: [Works.NO, "it only takes a flying shot or a line through walls, and a wall stands still through every hit"],
	B.SPIRAL: [Works.NO, "it does not move"],
	B.MIRROR: [Works.YES, Shows.DRAWN],
	B.GROWTH: [Works.YES, Shows.DRAWN],
	B.RELAY: [Works.YES, Shows.DRAWN],
	B.RETURN: [Works.NO, "it does not fly out"],
	B.ARC: [Works.YES, Shows.DRAWN],
	B.POSSESS: [Works.YES, Shows.DRAWN],
	B.DEFLECT: [Works.YES, Shows.DRAWN],
}
## When each trigger (`TriggerBase.Event`) fires on the wall: "" when it can, else why it never does.
const EVENTS: Dictionary = {
	E.HIT: "",
	E.EXPIRE: "",
	E.TIMER: "",
	E.BLOCK: "",
	E.KILL: "",
	E.CAST: "",
	E.WALL: "it stays where it is and never meets a wall",
	E.HURT: "",
	E.REACTION: "",
}
## How the wall takes an infusion.
const INFUSIONS: Array = [Works.YES, Shows.DRAWN]


func id() -> StringName:
	return &"wall"


func noun() -> String:
	return "wall"


func what() -> String:
	return "a wall stands still through every hit"


func traits() -> int:
	return STAYS | HITS | LASTS | REACHES | GUARDS | STEERS | SPEED | SHOTS


func behaviours() -> Dictionary:
	return BEHAVIOURS


func events() -> Dictionary:
	return EVENTS


func infusions() -> Array:
	return INFUSIONS


## Wall (rules R4 F6): one solid still shot centred its `ray_length` (or `SpellLimits.WALL_REACH`)
## ahead of `origin`, a row of `shots` stones across `direction`, `spread` pixels apart (the shot's
## diameter when the form has none): a wall while it lives (`set_solid`) that hurts what touches it
## and that its hits never spend. Homing makes it creep toward a target as one piece, as a rune does.
func launch(spell: CompiledSpell, tag: int, actor: int, origin: Vector2, direction: Vector2, source: Node, lifetime: float, carried: int, prev: int) -> int:
	var reach: float = spell.ray_length if spell.ray_length > 0.0 else SpellLimits.WALL_REACH
	var centre: Vector2 = rt.projectiles.clip_to_walls(origin, origin + direction * reach)
	var slot: int = rt.projectiles.spawn(actor, centre, Vector2.ZERO, lifetime, spell.radius, SpellRuntime.HITS, SpellRuntime.PIERCE_ALL, tag, SpellRuntime.ProjectilesScript.MOTION_STILL)
	if slot < 0:
		return 0
	rt._apply_travel(slot, spell)
	rt.projectiles.set_solid(slot, direction.orthogonal(), spell.shots, spell.spread if spell.spread > 0.0 else spell.radius * 2.0)
	rt._register(slot, tag, spell, carried, prev)
	if source != null:
		rt.projectiles.exclude(slot, source, SpellLimits.SOURCE_EXCLUSION)
	return 1
