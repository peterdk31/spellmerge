class_name CarrierWall
extends Carrier
## `shots` still, solid shots in a line across the aim, `spread` pixels apart: a short-lived wall that
## stands through every hit (`&"wall"`). Homing makes it creep toward a target, as a rune.


## Each modifier behaviour (`ModifierBase.Behaviour`) on the wall, every one (keys: see `Carrier`).
const BEHAVIOURS: Dictionary = {
	B.NONE: {"works": Works.YES, "shows": Shows.DRAWN},
	B.HOMING: {"works": Works.YES, "shows": Shows.DRAWN},
	B.CHAIN: {"works": Works.YES, "shows": Shows.DRAWN},
	B.SHIELD: {"works": Works.YES, "shows": Shows.DRAWN},
	B.BLAST: {"works": Works.YES, "shows": Shows.AS_EFFECT},
	B.HOLD: {"works": Works.YES, "shows": Shows.DRAWN},
	B.RECOIL: {"works": Works.YES, "shows": Shows.DRAWN},
	B.BOUNCE: {"works": Works.NO, "why_not": "it turns a shot or a beam at walls, and a wall stands still through every hit"},
	B.ECHO: {"works": Works.YES, "shows": Shows.DRAWN},
	B.LINGER: {"works": Works.NO, "why_not": "it does not move"},
	B.HEAVY: {"works": Works.YES, "shows": Shows.DRAWN},
	B.SIPHON: {"works": Works.YES, "shows": Shows.DRAWN},
	B.STICKY: {"works": Works.NO, "why_not": "it does not move"},
	B.MAGNET: {"works": Works.YES, "shows": Shows.DRAWN},
	B.GHOST: {"works": Works.NO, "why_not": "it only takes a flying shot or a line through walls, and a wall stands still through every hit"},
	B.SPIRAL: {"works": Works.NO, "why_not": "it does not move"},
	B.MIRROR: {"works": Works.YES, "shows": Shows.DRAWN},
	B.GROWTH: {"works": Works.YES, "shows": Shows.DRAWN},
	B.RELAY: {"works": Works.YES, "shows": Shows.DRAWN},
	B.RETURN: {"works": Works.NO, "why_not": "it does not fly out"},
	B.ARC: {"works": Works.YES, "shows": Shows.DRAWN},
	B.POSSESS: {"works": Works.YES, "shows": Shows.DRAWN},
	B.DEFLECT: {"works": Works.YES, "shows": Shows.DRAWN},
}
## Each trigger (`TriggerBase.Event`) on the wall: "fires" (does it ever go off here?) and, when it
## never does, "why_not".
const EVENTS: Dictionary = {
	E.HIT: {"fires": true},
	E.EXPIRE: {"fires": true},
	E.TIMER: {"fires": true},
	E.BLOCK: {"fires": true},
	E.KILL: {"fires": true},
	E.CAST: {"fires": true},
	E.WALL: {"fires": false, "why_not": "it stays where it is and never meets a wall"},
	E.HURT: {"fires": true},
	E.REACTION: {"fires": true},
}
## An infusion (an element card) on the wall, with the same keys as a behaviour.
const INFUSIONS: Dictionary = {"works": Works.YES, "shows": Shows.DRAWN}


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


func infusions() -> Dictionary:
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
