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

# Staffs F8 (docs/milestones/M2-staffs.md, "Enemy staffs"): an enemy that has a staff and
# cards attacks by casting them through core/spells like a wizard, player cards only, and pays
# for each cast from its own mana. A new enemy type is then a sprite and a staff. Without a
# staff it uses its scene's old attack (until staffs F9 moves every enemy onto staffs).

## The staff it casts (`content/wizard/staffs/`, or its own), or null for the old attack.
@export var staff: StaffBase = null
## Card ids by slot, as a wizard's staff holds them (`&""` for an empty slot).
@export var cards: Array[StringName] = []
## Its mana pool, full when it spawns, and the mana it gets back a second.
@export var max_mana: float = 0.0
@export var mana_regen: float = 0.0
