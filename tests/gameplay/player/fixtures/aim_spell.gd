extends SpellBase
## Test spell: records the origins and directions it was fired with. Not content.

var directions: Array[Vector2] = []
var origins: Array[Vector2] = []


func _fire(_player: int, origin: Vector2, direction: Vector2) -> bool:
	directions.append(direction)
	origins.append(origin)
	return true
