extends "res://tests/support/screenshot.gd"
## Screenshots of the hub (docs/milestones/online-lobby.md, L1), the island in the void that the
## main menu's Play goes to.
##
## Shots: one player just arrived (the stone dark, the stone line counting); the same player by the
## island's south-west edge, its rim of embers rising off it; two players on the stone and two off
## it; all four on the lit stone ("A starts the run"), the stone's cue playing.

const FlowScript := preload("res://gameplay/flow/flow.gd")
const STEP_FRAMES := 3

var _input: Node = null
var _flow: Node = null


func take() -> void:
	if not need(["PlayerInput", "Hud", "Flow", "Events"]):
		return
	_input = root.get_node("PlayerInput")
	_flow = root.get_node("Flow")
	var events: Node = root.get_node("Events")
	_input.call("add_virtual_device", 0)
	events.emit_signal("hub_requested", 0)
	if not await wait_for(func() -> bool: return _flow.get("mode") == &"hub" and _flow.call("get_wizard", 0) != null):
		fail("the hub did not start")
		return
	await settle()
	await shot("hub_arrived")
	# The island's edge (the rim of motes, "A, mixed elements"): standing by its south-west corner
	# after three seconds of embers.
	_place(0, Vector2(200.0, 592.0))
	await create_timer(3.0).timeout
	await shot("hub_edge")
	_place(0, room_spawn())
	for index in range(1, 4):
		_input.call("add_virtual_device", index)
	if not await wait_for(func() -> bool: return _flow.call("get_wizard", 3) != null):
		fail("the other three did not join")
		return
	var stone: Rect2 = _stone()
	_place(0, stone.get_center() + Vector2(-20.0, -14.0))
	_place(1, stone.get_center() + Vector2(20.0, 10.0))
	await settle()
	if bool(_flow.call("is_stone_lit")):
		fail("the stone is lit with two of four on it")
		return
	await shot("hub_two_of_four")
	_place(2, stone.get_center() + Vector2(-20.0, 16.0))
	_place(3, stone.get_center() + Vector2(22.0, -16.0))
	if not await wait_for(func() -> bool: return bool(_flow.call("is_stone_lit"))):
		fail("the stone did not light with all four on it")
		return
	await settle(8)
	await shot("hub_stone_lit")
	_flow.call("stop_run")
	await settle(STEP_FRAMES)


func room_spawn() -> Vector2:
	var room: RoomBase = root.get_node("Registry").call("get_resource", &"rooms", &"hub") as RoomBase
	return room.places().player_spawns[0]


func _stone() -> Rect2:
	var room: RoomBase = root.get_node("Registry").call("get_resource", &"rooms", &"hub") as RoomBase
	return FlowScript.area_of(room, FlowScript.STONE_PROP)


func _place(seat: int, at: Vector2) -> void:
	(_flow.call("get_wizard", seat) as Node2D).global_position = at
