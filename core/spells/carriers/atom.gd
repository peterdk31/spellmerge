class_name CarrierAtom
extends Carrier
## A shot that flies out on its own along the aim (`&"atom"`: the atom, the smallest; the bolt, a
## bigger, slower one; and the nova, bolts whose shots fan all the way round). The plain carrier:
## every card runs on it through the shot path (`Spells._apply_travel`, the projectile manager's
## kit).


func id() -> StringName:
	return &"atom"


func traits() -> int:
	return FLIES | STAYS | HITS | LASTS | REACHES | GUARDS | STEERS | SPEED | SHOTS | SPREAD | PIERCE | MOVES | MEETS_SHOTS


func required_fields() -> Dictionary:
	return {
		"speed": "An atom carrier needs a `speed` above 0.",
	}


## A launch of at least this many shots is spawned together (`_launch_together`).
const TOGETHER_FROM: int = 2

## The velocities of a launch spawned together, kept between launches (its slots: `_slots`).
var _velocities: PackedVector2Array = PackedVector2Array()


## A fan of flying shots; a nova (a fan all the way round) shows its ring once, when a shot flew.
func launch(spell: CompiledSpell, tag: int, actor: int, origin: Vector2, direction: Vector2, source: Node, lifetime: float, chain: int, prev: int) -> int:
	var made: int = _launch_together(spell, tag, actor, origin, direction, source, lifetime, chain, prev)
	if made < 0:
		made = super(spell, tag, actor, origin, direction, source, lifetime, chain, prev)
	if kit.events != null and made > 0 and spell.shots > 1 and spell.spread >= 360.0:
		kit.events.form_shown.emit(actor, &"nova", origin, direction, 0.0, spell.tint, spell.look)
	return made


func rows_only() -> bool:
	return true


func reach_of(spell: CompiledSpell) -> float:
	return spell.speed * spell.lifetime if spell.spread < 360.0 else 0.0


## The base `launch` (made together) with its rows spawned in one go (`ProjectileManager.spawn_batch`) and then set
## up in turn (`land_shots`): the same shots, headings, slots and records as one by one, for less.
## -1 (nothing done, nothing drawn from the spread's generator) when the pool lacks a free slot for
## each: at the cap a spawn drops another shot, so they go one by one, each set up before the next.
func _launch_together(spell: CompiledSpell, tag: int, actor: int, origin: Vector2, direction: Vector2, source: Node, lifetime: float, chain: int, prev: int) -> int:
	var count: int = spell.shots
	if not together or count < TOGETHER_FROM or kit.projectiles == null or not kit.projectiles.has_room_for(count):
		return -1
	if _velocities.size() < count:
		_velocities.resize(count)
		_slots.resize(count)
	# The headings as the base `launch` makes them, in order (the spread draws per shot).
	var base: float = direction.angle()
	for n in count:
		var angle: float = base + kit.fan_angle(n, count, spell) + kit.staff_spread(tag, spell)
		_velocities[n] = Vector2.from_angle(angle) * spell.speed
	if _velocities.size() > count:
		_velocities.resize(count)
	if kit.projectiles.spawn_batch(actor, origin, _velocities, lifetime, spell.radius, SpellRuntime.HITS, spell.pierce, tag, _slots) < 0:
		# Bad arguments (a caster or an origin `spawn` refuses): none made, as one by one.
		return 0
	return kit.land_shots(_slots, count, spell, tag, source, chain, prev)
