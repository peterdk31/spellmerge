extends SpellBase
## Test spell: records the directions it was fired in. Not content.

var directions: Array[Vector2] = []


func _fire(_player: int, _origin: Vector2, direction: Vector2) -> bool:
	directions.append(direction)
	return true
