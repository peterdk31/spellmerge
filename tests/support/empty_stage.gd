extends "res://tests/support/screenshot.gd"
## Base class for sheets that stand game things on nothing (props, bodies, effects): a run in an
## empty, dark room (`empty_stage/`: the palette's Outline over the whole screen, no walls, no art,
## no enemies) with every service working as in play (the tick, Combat, Spells, Feel's motes, cues
## and spell light), no HUD in the picture and seat 0's wizard hidden in a corner. The room is
## the sheets' own (under tests/), so the game never lists it; it is registered for the run only.
##
##   extends "res://tests/support/empty_stage.gd"
##   func take() -> void:
##       if not await open_stage():
##           return
##       stand(PropBody.make(data), Vector2(320, 180))
##       await snap(Vector2(320, 180), "my_sheet", Vector2i(64, 48), 2)
##       await close_stage()
##
## The room is the game's screen (`SCREEN`, 640×360) and the camera shows all of it at 1×, so a
## world point is where a sheet lays it out. A sheet that wants the wizard shows it
## (`wizard.visible = true`) and moves it.

const ROOM: RoomBase = preload("res://tests/support/empty_stage/empty_stage.tres")

## The run's world (bodies stood with `stand` go in it) and seat 0's wizard (hidden).
var world: Node2D = null
var wizard: Actor = null
var _flow: Node = null
var _hud: Node = null


## Starts the run in the empty room. False (the script failed, saying why) when it could not.
func open_stage() -> bool:
	change_scene_to_file("res://hud/menus/main_menu/main_menu.tscn")
	await settle()
	if not need(["PlayerInput", "Flow", "Feel", "Registry"]):
		return false
	_flow = root.get_node("Flow")
	# Refused when a sheet before this one in the same process registered it: the same room.
	root.get_node("Registry").call("add", &"rooms", ROOM)
	root.get_node("PlayerInput").call("add_virtual_device", 0)
	var was: StringName = _flow.get("room_id_to_play")
	_flow.set("room_id_to_play", ROOM.id)
	var started: bool = _flow.call("start_run", 0)
	_flow.set("room_id_to_play", was)
	if not started:
		fail("the empty stage did not start")
		return false
	for i in 4:
		await settle()
	wizard = _flow.call("get_wizard", 0) as Actor
	if wizard == null:
		fail("no wizard on the empty stage")
		return false
	wizard.visible = false
	world = wizard.get_parent() as Node2D
	_hud = root.get_node_or_null("Hud")
	if _hud != null:
		_hud.set("visible", false)
	return true


## `body` added to the world with its position at `at` (whole pixels); returned.
func stand(body: Node2D, at: Vector2) -> Node2D:
	world.add_child(body)
	body.global_position = at.round()
	return body


## Ends the run, the HUD shown again.
func close_stage() -> void:
	if _hud != null:
		_hud.set("visible", true)
	_flow.call("stop_run")
	await create_timer(0.3).timeout
