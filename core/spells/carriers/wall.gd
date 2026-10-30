class_name CarrierWall
extends Carrier
## `shots` still, solid shots in a line across the aim, `spread` pixels apart: a short-lived wall that
## stands through every hit (`&"wall"`). Homing makes it creep toward a target, as a rune.


func id() -> StringName:
	return &"wall"


func traits() -> int:
	return STAYS | HITS | LASTS | REACHES | GUARDS | STEERS | SPEED | SHOTS | MEETS_SHOTS


## Wall (rules R4 F6): one solid still shot centred its `ray_length` (or `SpellLimits.WALL_REACH`)
## ahead of `origin`, a row of `shots` stones across `direction`, `spread` pixels apart (the shot's
## diameter when the form has none): a wall while it lives (`set_solid`) that hurts what touches it
## and that its hits never spend. Homing makes it creep toward a target as one piece, as a rune does.
func launch(spell: CompiledSpell, tag: int, actor: int, origin: Vector2, direction: Vector2, source: Node, lifetime: float, carried: int, prev: int) -> int:
	var reach: float = spell.ray_length if spell.ray_length > 0.0 else SpellLimits.WALL_REACH
	var centre: Vector2 = kit.projectiles.clip_to_walls(origin, origin + direction * reach)
	var slot: int = kit.projectiles.spawn(actor, centre, Vector2.ZERO, lifetime, spell.radius, SpellRuntime.HITS, SpellRuntime.PIERCE_ALL, tag, SpellRuntime.ProjectilesScript.MOTION_STILL)
	if slot < 0:
		return 0
	kit.apply_travel(slot, spell)
	kit.projectiles.set_solid(slot, direction.orthogonal(), spell.shots, spell.spread if spell.spread > 0.0 else spell.radius * 2.0)
	kit.register(slot, tag, spell, carried, prev)
	if source != null:
		kit.projectiles.exclude(slot, source, SpellLimits.SOURCE_EXCLUSION)
	return 1
