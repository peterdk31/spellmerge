extends Node2D
## A stand-in for a wizard in the Feel tests: in the "players" group, with a player index (its
## seat) and the actor id it casts as (a real wizard opens its own, actors G3b).

var index: int = 0
var actor_id: int = -1


func _ready() -> void:
	add_to_group(&"players")
