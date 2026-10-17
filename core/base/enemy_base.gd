class_name EnemyBase
extends Resource
## The small M1 enemy: numbers plus its scene. M3 extends it with the shared
## behaviours, player-count scaling and validators.

## Unique name of the enemy, also its folder name; the registry finds it by this.
@export var id: StringName = &""
## True for content shown in the free web demo.
@export var demo: bool = false
@export var max_health: int = 1
## Pixels per second.
@export var move_speed: float = 0.0
## Damage a player takes from touching the enemy.
@export var contact_damage: int = 0
@export var scene: PackedScene
