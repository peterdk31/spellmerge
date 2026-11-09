class_name CarrierAtom
extends Carrier
## A shot that flies out on its own along the aim (`&"atom"`: the atom, the smallest; the bolt, a
## bigger, slower one). The plain carrier:
## every card runs on it through the shot path (`Spells._apply_travel`, the projectile manager's
## kit).


func id() -> StringName:
	return &"atom"


func traits() -> int:
	return FLIES | STAYS | HITS | LASTS | REACHES | GUARDS | STEERS | SPEED | SHOTS | SPREAD | PIERCE | MOVES | MEETS_SHOTS | CASTS_FROM_SHOT


func required_fields() -> Dictionary:
	return {
		"speed": "An atom carrier needs a `speed` above 0.",
	}


## The velocities of a launch's rows (`spawn_rows`), kept between launches.
var _velocities: PackedVector2Array = PackedVector2Array()


func rows_only() -> bool:
	return true


func reach_of(spell: CompiledSpell) -> float:
	return spell.speed * spell.lifetime if spell.spread < 360.0 else 0.0


## A launch's flying rows in one `ProjectileManager.spawn_batch` (the caster read once): the same
## rows as `spawn_row` for each, along the same headings (the spread drawn per shot, in order).
func spawn_rows(spell: CompiledSpell, tag: int, actor: int, origin: Vector2, direction: Vector2, count: int, lifetime: float, slots: PackedInt32Array) -> void:
	_velocities.resize(count)
	var base: float = DMath.angle(direction)
	for n in count:
		var angle: float = base + kit.fan_angle(n, count, spell) + kit.staff_spread(tag, spell)
		_velocities[n] = DMath.from_angle(angle) * spell.speed
	if kit.projectiles.spawn_batch(actor, origin, _velocities, lifetime, spell.radius, SpellRuntime.HITS, spell.pierce, tag, slots) < 0:
		# Bad arguments (a caster or an origin `spawn` refuses): none made, as one by one.
		for n in count:
			slots[n] = -1
