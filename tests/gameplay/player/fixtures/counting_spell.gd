extends SpellBase
## Test spell: records for which player it fired. Not content.

var fired_players: Array[int] = []


func _fire(player: int, _origin: Vector2, _direction: Vector2) -> void:
	fired_players.append(player)
