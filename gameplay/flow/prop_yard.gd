class_name PropYard
extends RefCounted
## The hub's prop yard (props W8, docs/milestones/props.md): where a room's zone named `prop_yard`
## (`Flow.ZONE_PROP_YARD`) stands the props it is given, and how soon a fresh one replaces one that
## was lit, broken or went. The game's rule, not the room's: a room only marks the zone.

## Pixels between two props in the yard, across and between rows (room to aim at one).
const GAP: float = 32.0
## Seconds after a yard prop leaves its first state or goes before a fresh one stands in its place.
const RETURN_SECONDS: float = 10.0


## Where each of `props` stands in `yard` (its feet, whole pixels), in order: rows filled left to
## right, GAP apart (by `PropBase.extent`), each row centred, its props' feet on one line; a prop
## that does not fit (the yard is full) at Vector2.INF. Empty with no yard.
static func places(yard: Rect2, props: Array[PropBase]) -> PackedVector2Array:
	var found := PackedVector2Array()
	if not yard.has_area():
		return found
	found.resize(props.size())
	found.fill(Vector2.INF)
	var top: float = yard.position.y
	var at: int = 0
	while at < props.size():
		# A row: as many as fit across.
		var row_end: int = at
		var width: float = 0.0
		var above: float = 0.0
		var below: float = 0.0
		while row_end < props.size():
			var box: Rect2 = props[row_end].extent()
			var wider: float = width + (GAP if row_end > at else 0.0) + box.size.x
			if row_end > at and wider > yard.size.x:
				break
			width = wider
			above = maxf(above, -box.position.y)
			below = maxf(below, box.end.y)
			row_end += 1
		if top + above + below > yard.end.y or width > yard.size.x:
			break
		var x: float = yard.position.x + floorf((yard.size.x - width) * 0.5)
		var feet_y: float = ceilf(top + above)
		for i in range(at, row_end):
			var box: Rect2 = props[i].extent()
			found[i] = Vector2(floorf(x - box.position.x), feet_y)
			x += box.size.x + GAP
		top = feet_y + below + GAP
		at = row_end
	return found
