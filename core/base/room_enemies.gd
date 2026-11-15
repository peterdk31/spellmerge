class_name RoomEnemies
extends Resource
## One line of a room's fight (boss OB2a, docs/milestones/boss-old-broom.md, decision 31): `count`
## enemies of the enemy or boss `enemy` (an id the registry knows under one of
## `EnemyBase.FOLDERS`), stood at the room's enemy spawns as the room starts. An id, never the
## enemy's file, so deleting an enemy or a boss leaves no broken room: a line naming an id the
## registry lacks stands nothing (with a warning), and a test holds every room's lines to the
## registry. A sub-resource of the room's `.tres` (`RoomBase.enemies`).

## The enemy's id (`EnemyBase.id`).
@export var enemy: StringName = &""
## How many stand (at least 1).
@export_range(1, 64) var count: int = 1
