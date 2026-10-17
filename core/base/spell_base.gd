class_name SpellBase
extends Resource
## The small M1 spell: one set of numbers. M2 replaces or extends it with the
## real spell components (form, element, modifiers, trigger).

## Unique name of the spell, also its folder name; the registry finds it by this.
@export var id: StringName = &""
## True for content shown in the free web demo.
@export var demo: bool = false
@export var display_name: String = ""
## Mana taken per cast.
@export var mana_cost: float = 0.0
## Seconds before the same player can cast again.
@export var cooldown: float = 0.0
## Damage per hit.
@export var damage: int = 0
## Projectile speed in pixels per second.
@export var speed: float = 0.0
## Seconds before a projectile disappears.
@export var lifetime: float = 0.0

## What cast() returns when the spell did not fire (cooling down or too little mana).
const REFUSED: float = -1.0

## Seconds left before each player (index 0-3) may cast this spell again.
var _cooldown_left: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])


## The id sent in `spell_cast`. A method, so callers never read the `id` field.
func spell_id() -> StringName:
	return id


## Run the cooldown of `player` by `delta` seconds. The player calls this every step.
func tick(player: int, delta: float) -> void:
	_cooldown_left[player] = maxf(_cooldown_left[player] - delta, 0.0)


## Forget every cooldown (a new run).
func reset_cooldowns() -> void:
	_cooldown_left.fill(0.0)


## The one way to fire a spell, and all a player or a bot ever calls. `mana` is what
## the caster has. Returns the mana spent (0.0 or more) when the spell fired, or
## REFUSED when it did not; the caller then takes that much mana and reads no field.
## It checks the cooldown and the mana cost, then calls _fire().
func cast(player: int, origin: Vector2, direction: Vector2, mana: float) -> float:
	if _cooldown_left[player] > 0.0 or mana < mana_cost:
		return REFUSED
	_cooldown_left[player] = cooldown
	_fire(player, origin, direction)
	return mana_cost


## What the spell does when it fires. The fire bolt (M1 part 13) overrides this to
## spawn projectiles through `core/projectiles`.
func _fire(_player: int, _origin: Vector2, _direction: Vector2) -> void:
	pass
