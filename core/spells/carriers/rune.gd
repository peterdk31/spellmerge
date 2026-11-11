class_name CarrierRune
extends Carrier
## A still shot placed a step ahead along the aim that waits for a body to enter it
## (`&"rune"`: the rune). Homing makes it creep toward a target.


func id() -> StringName:
	return &"rune"


## What draws its look: its shots stand still, one quad each.
func look_drawer() -> int:
	return LOOK_STILL


func traits() -> int:
	return STAYS | HITS | LASTS | GUARDS | STEERS | SPEED | SHOTS | SPREAD | PIERCE | OUTWARD | MEETS_SHOTS | CASTS_FROM_SHOT


## A rune arms (owner, 2026-11-06): it hits nothing for `SpellLimits.RUNE_ARM` seconds, then
## whatever is on it. So it is the exception to a payload sparing the body whose hit fired it
## (`ProjectileManager.exclude`): a rune cast on a body goes off on that body once armed.
func launch(spell: CompiledSpell, tag: int, actor: int, origin: Vector2, direction: Vector2, _source: Node, lifetime: float, chain: int, prev: int) -> int:
	return super(spell, tag, actor, origin, direction, null, lifetime, chain, prev)


## A still shot a step ahead along `heading` (`Spells._placed_at`), held still while it arms (a
## local stop, `freeze_shot`: its life, its hits and its cards wait).
func spawn_row(spell: CompiledSpell, tag: int, actor: int, origin: Vector2, _direction: Vector2, heading: Vector2, _n: int, _count: int, lifetime: float) -> int:
	var slot: int = kit.projectiles.spawn(actor, kit.placed_at(spell, actor, origin, heading), Vector2.ZERO, lifetime, spell.radius, SpellRuntime.HITS, spell.pierce, tag, SpellRuntime.ProjectilesScript.MOTION_STILL)
	if slot >= 0:
		kit.projectiles.freeze_shot(slot, SpellLimits.RUNE_ARM)
	return slot


func rows_only() -> bool:
	return true
