class_name RoomBase
extends Resource
## The small M1 room: its scene and where things go. M3 extends it with the
## biome, the required doors and validators.

## Unique name of the room, also its file name; the registry finds it by this.
@export var id: StringName = &""
## True for content shown in the free web demo.
@export var demo: bool = false
## The layout scene (tiles only, no scripts).
@export var scene: PackedScene
## Where the players start, in room pixels. Index i is player i; four are expected (checked from M3).
@export var player_spawns: PackedVector2Array = PackedVector2Array()
## Where enemies may appear, in room pixels.
@export var enemy_spawns: PackedVector2Array = PackedVector2Array()
## Door positions, in room pixels.
@export var doors: PackedVector2Array = PackedVector2Array()
## Where a sandbox room puts its dummies, in room pixels (staffs B7): the training dummy first,
## then the shooting dummy. Empty in every other room.
@export var dummy_spawns: PackedVector2Array = PackedVector2Array()
