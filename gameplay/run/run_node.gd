class_name RunNode
extends RefCounted
## One room of a run's map (run generation RG2, docs/milestones/run-generation.md, "The generator"):
## where it stands, what kind of room it is, which template lays it out, the rooms of the next row
## it leads to and what fills it. Plain values and ids only, never a file: deleting content after a
## map was made breaks nothing, and the map is state as it is (hashed, saved in snapshots).

## Its number in the map (`RunMap.nodes`): the rows in order, each row's rooms left to right.
var index: int = 0
## Its row in the map (0: the first room, where the party enters).
var row: int = 0
## The row of the map rules it stands for (`KindRule.takes_row`, `EnemyBase.min_depth`): its `row`,
## unless the rules left a row before it out (a row the content could fill with nothing).
var depth: int = 0
## Its kind (`RoomKind.id`).
var kind: StringName = &""
## The room template that lays it out (`RoomBase.id`).
var room: StringName = &""
## The rooms of the next row it leads to (their `index`), left to right; none in the last row.
var links: PackedInt32Array = PackedInt32Array()
## What stands in it as it starts (`EnemyBase.id`s, one per body; a fight's enemies, a boss room's boss).
var enemies: Array[StringName] = []
## How much harder it is than the run's first room with one player (run generation RG5,
## `RunScaling.room_scale`: its depth and the run's players): its enemy budget was scaled by it, and
## every enemy's and boss's health is (gameplay/difficulty).
var scale: float = 1.0
