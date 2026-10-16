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
