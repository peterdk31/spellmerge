class_name CarrierWall
extends Carrier
## `shots` still, solid shots in a line across the aim, `spread` pixels apart: a short-lived wall that
## stands through every hit (`&"wall"`). Homing makes it creep toward a target, as a rune.


## Modifier cards that do nothing on a wall, with the sentence the builder shows after
## "<Card> does nothing on a Wall: ". Every card not listed does something here.
const DOES_NOTHING: Dictionary = {
	B.BOUNCE: "it turns a shot or a beam at walls, and a wall stands still through every hit",
	B.LINGER: "it does not move",
	B.STICKY: "it does not move",
	B.GHOST: "it only takes a flying shot or a line through walls, and a wall stands still through every hit",
	B.SPIRAL: "it does not move",
	B.RETURN: "it does not fly out",
}
## Trigger cards that never go off on a wall, with the sentence the builder shows.
const NEVER_FIRES: Dictionary = {
	E.WALL: "it stays where it is and never meets a wall",
}


func id() -> StringName:
	return &"wall"


func noun() -> String:
	return "wall"


func what() -> String:
	return "a wall stands still through every hit"


func traits() -> int:
	return STAYS | HITS | LASTS | REACHES | GUARDS | STEERS | SPEED | SHOTS


func does_nothing() -> Dictionary:
	return DOES_NOTHING


func never_fires() -> Dictionary:
	return NEVER_FIRES


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
