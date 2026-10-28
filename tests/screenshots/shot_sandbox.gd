extends "res://tests/support/screenshot.gd"
## Screenshots of the sandbox (staffs B7a), the two-lane room of dev and preview builds.
##
## Shots: one player firing fire bolts up the left lane at the training dummy and the group round
## it (damage numbers, DPS, burn); the pause menu's sandbox page open; four players, two per lane, with an imp
## wave in and the shooting dummy's telegraph up.

## Frames after a press for the menus to redraw; the full settle is kept for the shots.
const STEP_FRAMES := 3
## How far up the lane P1 stands: about what 1.2 s of walking covers.
const WALK: float = 100.0

var _input: Node = null
var _hud: Node = null
var _flow: Node = null


func take() -> void:
	if not need(["PlayerInput", "Hud", "Flow", "Events"]):
		return
	_input = root.get_node("PlayerInput")
	_hud = root.get_node("Hud")
	_flow = root.get_node("Flow")
	var events: Node = root.get_node("Events")
	_input.call("add_virtual_device", 0)
	events.emit_signal("sandbox_requested", 0)
	if not await wait_for(func() -> bool: return _flow.get("sandbox") and _flow.call("get_wizard", 0) != null):
		fail("the sandbox did not start")
		return
	# P1 stands up the left lane, where a walk of 1.2 s takes it, and fires its X staff (fire
	# bolt) at the training dummy.
	var dummy: Node2D = (_flow.call("dummies") as Array)[0]
	var wizard: Node2D = _flow.call("get_wizard", 0)
	wizard.global_position += Vector2(0.0, -WALK)
	await settle(STEP_FRAMES)
	_input.call("send_virtual_aim", 0, (dummy.position + Vector2(0.0, -14.0) - wizard.position).normalized())
	_input.call("send_virtual", 0, &"staff_2", 1.0)
	await create_timer(2.0).timeout
	_input.call("send_virtual", 0, &"staff_2", 0.0)
	# The group stands round the training dummy, so the bolts may land on one of them first.
	var damage: int = 0
	for standing: Node in _flow.call("dummies") as Array:
		if (standing.get("data") as EnemyBase).id == &"training_dummy":
			damage += int(standing.get_node("DummyLook").get("total_damage"))
	if damage <= 0:
		fail("no training dummy took damage")
		return
	await shot("sandbox_training_lane")
	await _open_page(0)
	var pause_menu: Node = _hud.call("get_pause_menu")
	if not pause_menu.call("is_open") or int(pause_menu.get("page")) != 1:
		fail("the pause menu's sandbox page is not open for player 1")
		return
	await shot("sandbox_page")
	tap(0, &"pause")
	await settle(STEP_FRAMES)
	_flow.call("stop_run")
	await settle(STEP_FRAMES)
	for index in range(1, 4):
		_input.call("add_virtual_device", index)
	events.emit_signal("sandbox_requested", 0)
	if not await wait_for(func() -> bool: return _flow.call("get_wizard", 3) != null):
		fail("the sandbox did not start with four wizards")
		return
	for index in 4:
		_flow.call("get_wizard", index).call("protect", 60.0)
	events.emit_signal("sandbox_action_requested", 1, &"imp_wave")
	await create_timer(1.0).timeout
	var shooter: Node = (_flow.call("dummies") as Array)[1]
	for wait in 40:
		if shooter.get_node("AIController").call("is_telegraphing"):
			break
		await process_frame
	await shot("sandbox_four_players")
	_flow.call("stop_run")
	await create_timer(0.3).timeout


## Start, then "Sandbox" (the second button in the sandbox), as a person does.
func _open_page(player: int) -> void:
	tap(player, &"pause")
	await settle(STEP_FRAMES)
	tap(player, &"move_down")
	await process_frame
	await process_frame
	tap(player, &"accept")
	await settle(STEP_FRAMES)
