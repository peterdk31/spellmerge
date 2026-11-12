extends "res://tests/support/suite.gd"
## The world draws its bodies by their feet (docs/DECISIONS.md, 2026-11-12, "the world draws its
## bodies by their feet"): Flow's world is y-sorted, which sorts only its own children. So in every
## room of the registry, as Flow builds it:
## - the room's layout is the world's first child, at the top left, drawn before every body;
## - every place a body stands (a spawn, a door, a placed prop or enemy) is below that line;
## - every body (wizards, enemies, props, the prop yard's) is a child of the world itself, never
##   under a holder, which would sort as one piece against the rest.
## A new room or a new kind of body that breaks one of these fails here.
##
## Regression (the owner's playtest of 2026-11-12, "I can kinda walk in behind their bottom"): the
## props were drawn over the wizards wherever they stood.
##
## godot --headless --path . --script res://tests/gameplay/flow/test_world_draw_order.gd

const FlowScript := preload("res://gameplay/flow/flow.gd")

var flow: FlowScript
var input: Node
var _registry: Node


func before_each() -> void:
	flow = root.get_node("Flow") as FlowScript
	input = root.get_node("PlayerInput")
	_registry = root.get_node("Registry")
	flow.world_parent = own(Node.new()) as Node
	root.add_child(flow.world_parent)
	for index in 2:
		input.add_virtual_device(index)


func after_each() -> void:
	flow.stop_run()
	flow.mode = FlowScript.MODE_WAVES
	flow.room_id_to_play = FlowScript.DEFAULT_ROOM_ID
	flow.world_parent = null
	for index in 4:
		input.leave(index)


## Every room in the registry.
func _rooms() -> Array[RoomBase]:
	var rooms: Array[RoomBase] = []
	for resource: Resource in _registry.call("get_all", FlowScript.ROOM_FOLDER):
		if resource is RoomBase:
			rooms.append(resource as RoomBase)
	return rooms


## Start `room` as Flow would for its mode (the hub, the sandbox, else a wave room).
func _start(room: RoomBase) -> bool:
	match room.id:
		FlowScript.HUB_ROOM_ID:
			flow.mode = FlowScript.MODE_HUB
		FlowScript.SANDBOX_ROOM_ID:
			flow.mode = FlowScript.MODE_SANDBOX
		_:
			flow.mode = FlowScript.MODE_WAVES
			flow.room_id_to_play = room.id
	return flow.start_run(0)


func test_every_room_is_found() -> void:
	var ids: Array[StringName] = []
	for room in _rooms():
		ids.append(room.id)
	for id: StringName in [FlowScript.HUB_ROOM_ID, FlowScript.SANDBOX_ROOM_ID, FlowScript.DEFAULT_ROOM_ID]:
		check(ids.has(id), "the room %s is among those checked" % id)


func test_every_room_stands_its_bodies_below_its_layout() -> void:
	for room in _rooms():
		var layout: Node2D = room.build() as Node2D
		check(layout != null, "%s: its layout is a Node2D" % room.id)
		if layout == null:
			continue
		check_equal(layout.position, Vector2.ZERO, "%s: its layout at the top left" % room.id)
		layout.free()
		var places: RoomPlaces = room.places()
		var points := PackedVector2Array()
		points.append_array(places.player_spawns)
		points.append_array(places.joiner_spawns)
		points.append_array(places.enemy_spawns)
		points.append_array(places.doors)
		points.append_array(places.placed_at)
		for at in points:
			check(at.y >= 0.0, "%s: a body stands at %s, above its layout's line" % [room.id, at])


func test_every_room_draws_its_bodies_by_their_feet() -> void:
	for room in _rooms():
		check(_start(room), "%s: the run starts" % room.id)
		var world: Node2D = flow.world
		if world == null:
			continue
		check(world.y_sort_enabled, "%s: the world sorts its children by their feet" % room.id)
		var layout: Node2D = world.get_child(0) as Node2D
		check(layout != null and layout is not Actor and layout.position == Vector2.ZERO, "%s: the layout first, at the top left" % room.id)
		var bodies: int = 0
		for body: Node in world.find_children("*", "Actor", true, false):
			bodies += 1
			check_equal(body.get_parent(), world, "%s: %s is a child of the world itself" % [room.id, body.name])
			check((body as Actor).global_position.y >= 0.0, "%s: %s below the layout's line" % [room.id, body.name])
		check(bodies >= 2, "%s: its bodies were checked (%d)" % [room.id, bodies])
		flow.stop_run()


func test_a_wizard_and_a_prop_are_sorted_together() -> void:
	flow.mode = FlowScript.MODE_HUB
	check(flow.start_run(0), "the hub starts")
	var crate: Node = null
	for body: Node in flow.yard_props():
		if body != null and (body as Actor).prop.id == &"crate":
			crate = body
	check(crate != null, "the yard's crate")
	check_equal(crate.get_parent() if crate != null else null, flow.world, "a prop is sorted among the bodies")
	check_equal(flow.get_wizard(0).get_parent(), flow.world, "and so is a wizard")
