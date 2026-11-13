extends "res://tests/support/suite.gd"
## The world draws its bodies by their feet (docs/DECISIONS.md, 2026-11-12, "the world draws its
## bodies by their feet"): Flow's world is y-sorted, which sorts only its own children. So:
## - the room's layout is the world's first child, at the top left, drawn before every body;
## - every body (wizards, enemies, props, the prop yard's) is a child of the world itself, never
##   under a holder, which would sort as one piece against the rest.
##
## These are Flow's code, the same in every room, so two rooms cover every way a body is stood: the
## hub (wizards, the room's props and the prop yard's) and the first wave room (wizards and a wave
## of enemies). What a room's own scene could break, its root moved off (0, 0) or a body standing
## above or left of it, is one of `RoomPlaces.problems()`, read for every room by
## tests/content/rooms/test_room_places.gd without playing it. So this costs the same however many
## rooms there are.
##
## Regression (the owner's playtest of 2026-11-12, "I can kinda walk in behind their bottom"): the
## props were drawn over the wizards wherever they stood.
##
## godot --headless --path . --script res://tests/gameplay/flow/test_world_draw_order.gd

const FlowScript := preload("res://gameplay/flow/flow.gd")

var flow: FlowScript
var input: Node


func before_each() -> void:
	flow = root.get_node("Flow") as FlowScript
	input = root.get_node("PlayerInput")
	flow.world_parent = own(Node.new()) as Node
	root.add_child(flow.world_parent)
	for index in 2:
		input.add_virtual_device(index)


func after_each() -> void:
	flow.stop_run()
	flow.mode = FlowScript.MODE_WAVES
	flow.world_parent = null
	for index in 4:
		input.leave(index)


## The world of the run just started: y-sorted, its layout first at the top left, every body (of
## `kind`, at least one) its own child, below the layout's line. `where` names the room.
func _check_world(where: String, kind: Callable) -> void:
	var world: Node2D = flow.world
	check(world != null, "%s: the run starts" % where)
	if world == null:
		return
	check(world.y_sort_enabled, "%s: the world sorts its children by their feet" % where)
	var layout: Node2D = world.get_child(0) as Node2D
	check(layout != null and layout is not Actor and layout.position == Vector2.ZERO, "%s: the layout first, at the top left" % where)
	var of_kind: int = 0
	for body: Node in world.find_children("*", "Actor", true, false):
		check_equal(body.get_parent(), world, "%s: %s is a child of the world itself" % [where, body.name])
		check((body as Actor).global_position.y >= 0.0, "%s: %s below the layout's line" % [where, body.name])
		if kind.call(body):
			of_kind += 1
	check(of_kind > 0, "%s: the bodies it is here for were stood" % where)


func test_the_hub_sorts_its_wizards_and_props_together() -> void:
	flow.mode = FlowScript.MODE_HUB
	flow.start_run(0)
	_check_world("the hub", func(body: Node) -> bool: return (body as Actor).prop != null)
	check(not flow.yard_props().is_empty() and not flow.room_props().is_empty(), "the yard's props and the room's own")
	check_equal(flow.get_wizard(0).get_parent(), flow.world, "a wizard among them")


func test_a_wave_room_sorts_its_wizards_and_enemies_together() -> void:
	flow.mode = FlowScript.MODE_WAVES
	flow.start_run(0)
	_check_world("a wave room", func(body: Node) -> bool: return (body as Actor).data != null)
	check(flow.enemies_left() > 0, "a wave stood")
