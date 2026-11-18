class_name RoomContents
extends RefCounted
## The bodies a room stands (props W8c, docs/milestones/props.md, "W8c: a room foundation"): one a
## placement of its layout (`RoomPlaces.placed`, in the tree's order), made from the placement's
## data by its class (`make_body`: a prop through `PropBody`, an enemy from its scene), so a new kind
## of placed thing is a branch here and nothing in Flow. It keeps them standing (a slot a
## placement, null once its body went, forgotten in the tick it goes) and answers by kind and role.
##
## A room's zone named for a prop role (run generation RG7: the hub's `start_lectern`) is a place for
## the registry's prop of that role (`stand`): the first by id stands with its feet at the zone's
## middle, after the placements. So such a prop is found by folder, never named by the
## room's scene: deleting its folder leaves the zone empty and the room whole.
## Flow's state (it holds one), stepped by Flow.

const RegistryScript := preload("res://core/registry/registry.gd")
const PROP_FOLDER: StringName = &"props"

## State as who they point at (core/sim/README.md).
const REFS: Array[StringName] = [&"bodies"]
## Not state: what was wrong with the room's laying, for Flow to tell (`problems`).
const DERIVED: Array[StringName] = [&"problems"]

## The bodies standing, a slot a placement in `RoomPlaces.placed`'s order (null: none or it went).
var bodies: Array[Node] = []
## What was wrong as the room was laid (`stand`): a body whose footprint reaches over a hole (hub
## rework HR-H2), one line each.
var problems: PackedStringArray = PackedStringArray()


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
	return ItemKinds.kind_of(data) != &""


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
## is), in order, then the props of `registry` its role zones place (`stand_in_role_zones`).
func stand(world: Node2D, places: RoomPlaces, registry: RegistryScript) -> void:
	clear()
	for i in places.placed.size():
		bodies.append(_stand(world, places, i))
	stand_in_role_zones(world, places, registry)


## For each zone of `places` named for the role of a prop of `registry` (`PropBase.role`), stand
## that role's first prop by id in `world`, its feet at the zone's middle (whole pixels), after the
## placements' bodies (`stand` calls it). A zone no prop's role names stands nothing.
func stand_in_role_zones(world: Node2D, places: RoomPlaces, registry: RegistryScript) -> void:
	if registry == null:
		return
	for at in places.zone_names.size():
		var data: PropBase = first_of_role(registry, places.zone_names[at])
		if data == null:
			continue
		var body: Node2D = make_body(data)
		if body == null:
			continue
		body.position = places.zone_rects[at].get_center().floor()
		world.add_child(body)
		_check_ground(body, places)
		bodies.append(body)


## The prop of `registry` of the role `role` with the least id (null for none, or no role).
static func first_of_role(registry: RegistryScript, role: StringName) -> PropBase:
	var found: PropBase = null
	if role == &"":
		return found
	for resource: Resource in registry.get_all(PROP_FOLDER):
		var data := resource as PropBase
		if data != null and data.role == role and data.scene != null and (found == null or String(data.id) < String(found.id)):
			found = data
	return found


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
	problems.clear()


func _stand(world: Node2D, places: RoomPlaces, i: int) -> Node:
	var body: Node2D = make_body(places.placed[i])
	if body == null:
		return null
	body.position = places.placed_at[i]
	world.add_child(body)
	_check_ground(body, places)
	return body


## A body stood whose footprint reaches over a hole of `places` is a problem (hub rework HR-H2): it is
## kept in `problems` (Flow tells it) and the body stands as placed.
func _check_ground(body: Node2D, places: RoomPlaces) -> void:
	var actor := body as Actor
	if actor == null or actor.footprint == null or places.holes.is_empty():
		return
	var hole: Rect2 = places.hole_under(actor.footprint.rect_at(body.position))
	if hole.has_area():
		problems.append("%s at %s stands over the hole %s: move it onto the ground." % [body.name, body.position, hole])


## What a standing body was made from: a prop's data, else an enemy's.
static func _data_of(body: Node) -> Resource:
	var actor := body as Actor
	if actor == null:
		return null
	return actor.prop if actor.prop != null else actor.data
