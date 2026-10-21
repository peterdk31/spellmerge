extends Node2D
## A stand-in for a wizard in the Feel tests: in the "players" group, with a player index.

var index: int = 0


func _ready() -> void:
	add_to_group(&"players")
