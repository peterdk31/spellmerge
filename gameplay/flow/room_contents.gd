class_name RoomContents
extends RefCounted
## The bodies a room stands (props W8c, docs/milestones/props.md, "W8c: a room foundation"): one a
## placement of its layout (`RoomPlaces.placed`, in the tree's order), made from the placement's
## data by its class (`make_body`: a prop through `PropBody`, an enemy from its scene), so a new kind
## of placed thing is a branch here and nothing in Flow. It keeps them standing (a slot a
## placement, null once its body went, forgotten in the tick it goes) and answers by kind and role.
## Flow's state (it holds one), stepped by Flow.

## State as who they point at (core/sim/README.md).
const REFS: Array[StringName] = [&"bodies"]

## The bodies standing, a slot a placement in `RoomPlaces.placed`'s order (null: none or it went).
var bodies: Array[Node] = []


## A new body for the placed data `data` (not yet in the tree; its position is the caller's): a
## prop's (`PropBody.make`) or an enemy's scene with its data; null, with a warning, for data of a
## class nothing makes.
static func make_body(data: Resource) -> Node2D:
	if is_item(data):
		# An item lies on the ground, no body (items I6): the Items area lays it (`room_items_placed`).
		return null
	if data is PropBase:
		return PropBody.make(data as PropBase)
	if data is EnemyBase:
		var enemy := data as EnemyBase
		var node: Node = enemy.scene.instantiate() if enemy.scene != null else null
		var body := node as Actor
		if body == null:
			push_warning("RoomContents: the enemy '%s' has no actor scene, so it is not stood." % enemy.id)
			if node != null:
				node.free()
			return null
		body.data = enemy
		return body
	push_warning("RoomContents: nothing makes a body of %s." % data)
	return null


## True when the placed data `data` is an item (`ItemKinds.stack_of`): no body stands for it.
static func is_item(data: Resource) -> bool:
	return ItemKinds.stack_of(data) != null


## The items `places` places (data `is_item`) and where each lies, in order: [Array[Resource],
## PackedVector2Array].
static func items_of(places: RoomPlaces) -> Array:
	var items: Array[Resource] = []
	var at := PackedVector2Array()
	for i in places.placed.size():
		if is_item(places.placed[i]):
			items.append(places.placed[i])
			at.append(places.placed_at[i])
	return [items, at]


## Stand a body for every placement of `places` in `world` (one not yet in the tree, or one that
## is), in order.
func stand(world: Node2D, places: RoomPlaces) -> void:
	clear()
	for i in places.placed.size():
		bodies.append(_stand(world, places, i))


## Stand fresh bodies for the placements of `places` whose data is of class `kind` (the sandbox's
## dummies put back): the old ones there go first.
func stand_again(world: Node2D, places: RoomPlaces, kind: Script) -> void:
	for i in mini(places.placed.size(), bodies.size()):
		if not is_instance_of(places.placed[i], kind):
			continue
		var old: Node = bodies[i]
		if old != null and is_instance_valid(old):
			if old.get_parent() != null:
				old.get_parent().remove_child(old)
			old.queue_free()
		bodies[i] = _stand(world, places, i)


## The bodies standing whose data is of class `kind`, in order.
func of_kind(kind: Script) -> Array[Node]:
	var found: Array[Node] = []
	for body in bodies:
		if body != null and is_instance_valid(body) and is_instance_of(_data_of(body), kind):
			found.append(body)
	return found


## The props standing whose `PropBase.role` is `role`, in order.
func with_role(role: StringName) -> Array[Actor]:
	var found: Array[Actor] = []
	for body in bodies:
		var actor := body as Actor if body != null and is_instance_valid(body) else null
		if actor != null and actor.prop != null and actor.prop.role == role:
			found.append(actor)
	return found


## The slot of `body` emptied (it died: a dummy).
func forget(body: Node) -> void:
	var at: int = bodies.find(body)
	if at >= 0:
		bodies[at] = null


## Bodies that went (freed, or dying: freed at the frame's end) are forgotten, their slots kept, so
## the state never points at a freed body.
func forget_gone() -> void:
	for i in bodies.size():
		var body: Node = bodies[i]
		if body != null and (not is_instance_valid(body) or (body is Actor and (body as Actor).is_dying())):
			bodies[i] = null


## Nothing stands (the world they stood in goes with them).
func clear() -> void:
	bodies.clear()


func _stand(world: Node2D, places: RoomPlaces, i: int) -> Node:
	var body: Node2D = make_body(places.placed[i])
	if body == null:
		return null
	body.position = places.placed_at[i]
	world.add_child(body)
	return body


## What a standing body was made from: a prop's data, else an enemy's.
static func _data_of(body: Node) -> Resource:
	var actor := body as Actor
	if actor == null:
		return null
	return actor.prop if actor.prop != null else actor.data
