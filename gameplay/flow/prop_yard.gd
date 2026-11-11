class_name PropYard
extends RefCounted
## The hub's prop yard (props W8, docs/milestones/props.md): a room's zone named `prop_yard`
## (`Flow.ZONE_PROP_YARD`) where every prop of the registry the game's rules know nothing of (no
## `PropBase.role`) stands, in rows by id (`places`), each in its first state; one that leaves its
## first state (lit, broken) or goes is replaced by a fresh one RETURN_SECONDS later, where it stood.
## The game's rule, not the room's: a room only marks the zone. Flow's state (it holds one), stepped
## by Flow (`tend`).

const RegistryScript := preload("res://core/registry/registry.gd")

## State as who they point at (core/sim/README.md).
const REFS: Array[StringName] = [&"_bodies"]

## Pixels between two props in the yard, across and between rows (room to aim at one).
const GAP: float = 32.0
## Seconds after a yard prop leaves its first state or goes before a fresh one stands in its place.
const RETURN_SECONDS: float = 10.0

## A slot a prop: who stands there (null while none: it went), which prop, where, and the seconds
## until a fresh one stands there (-1: none due).
var _bodies: Array[Node] = []
var _ids: Array[StringName] = []
var _places: PackedVector2Array = PackedVector2Array()
var _left: PackedFloat64Array = PackedFloat64Array()


## Stand every prop of `registry` with no role in `yard` (a room's zone) in `world`, in rows by id
## (`places`); one that does not fit is left out with a warning. Empty when `yard` is.
func fill(world: Node2D, yard: Rect2, registry: RegistryScript) -> void:
	clear()
	if not yard.has_area() or registry == null:
		return
	var kinds: Array[PropBase] = []
	for resource: Resource in registry.get_all(&"props"):
		var data := resource as PropBase
		if data != null and data.role == &"" and data.scene != null:
			kinds.append(data)
	var at: PackedVector2Array = places(yard, kinds)
	for i in kinds.size():
		if at[i] == Vector2.INF:
			push_warning("PropYard: the yard is full; '%s' and the props after it do not stand there." % kinds[i].id)
			break
		_ids.append(kinds[i].id)
		_places.append(at[i])
		_left.append(-1.0)
		_bodies.append(_stand(world, kinds[i], at[i]))


## One tick of `delta` seconds: a prop that left its first state or went starts its slot's count;
## when it runs out, the slot's body (if any) goes and a fresh one stands. A body that goes is
## forgotten in the tick it goes (the yard's state never points at a freed one).
func tend(delta: float, world: Node2D, registry: RegistryScript) -> void:
	for i in _bodies.size():
		var body: Node = _bodies[i]
		if body != null and (not is_instance_valid(body) or (body is Actor and (body as Actor).is_dying())):
			_bodies[i] = null
		var prop := _bodies[i] as Actor
		var fresh: bool = prop != null and (prop.state_triggers == null or prop.state_triggers.in_first_state())
		if not fresh and _left[i] < 0.0:
			_left[i] = RETURN_SECONDS
		if _left[i] < 0.0:
			continue
		_left[i] -= delta
		if _left[i] > 0.0:
			continue
		_left[i] = -1.0
		if prop != null:
			if prop.get_parent() != null:
				prop.get_parent().remove_child(prop)
			prop.queue_free()
		var data: PropBase = registry.get_resource(&"props", _ids[i]) as PropBase if registry != null else null
		_bodies[i] = _stand(world, data, _places[i])


## The props standing in the yard now, by slot (null for a slot whose prop went and is not back
## yet).
func bodies() -> Array[Node]:
	return _bodies.duplicate()


## No yard (the world it stood in goes with its props).
func clear() -> void:
	_bodies.clear()
	_ids.clear()
	_places = PackedVector2Array()
	_left = PackedFloat64Array()


static func _stand(world: Node2D, data: PropBase, at: Vector2) -> Actor:
	var body: Actor = PropBody.make(data) if data != null else null
	if body == null:
		push_warning("PropYard: the prop '%s' has no body." % (data.id if data != null else &""))
		return null
	body.position = at
	world.add_child(body)
	return body


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
