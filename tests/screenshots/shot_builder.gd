extends "res://tests/support/screenshot.gd"
## Screenshots of the list builder (staffs A6a, B8), which the Sandbox page switches to; the
## default, radial builder is in `shot_radial_builder.gd`.
##
## Shots: one player with the builder open (links: fire "> 2" into the bolt, "#1" on the bolt),
## then picking cards into staff X, a card picked up to move ("^", `builder_holding`), a wasted
## card, then all four players with their builders open on different staffs, in a wave.

## Frames after a press for the builder to redraw; the full settle is kept for the shots.
const STEP_FRAMES := 3

var _input: Node = null
var _focus: Node = null
var _hud: Node = null


func take() -> void:
	if not need(["PlayerInput", "UIFocus", "Hud", "Flow"]):
		return
	_input = root.get_node("PlayerInput")
	_focus = root.get_node("UIFocus")
	_hud = root.get_node("Hud")
	var flow: Node = root.get_node("Flow")
	_input.call("add_virtual_device", 0)
	# These shots are the list builder's (the radial one is the default).
	_hud.call("_on_builder_options_changed", false, false, true)
	flow.call("start_run", 0)
	await settle(STEP_FRAMES)
	await _open_builders([0])
	var builder: Node = _hud.call("get_builder", 0)
	await shot("builder_opened")
	# Two cards after the fire bolt: a split and a nova; the plan shows both casts.
	await _press(0, builder.call("slot_button", 2))
	await _press(0, _row(builder, "Split"))
	await _press(0, _row(builder, "Nova"))
	if not builder.call("is_open"):
		fail("the builder of player 1 is not open")
		return
	await shot("builder_one_player")
	# Pick the nova up to move it: it is marked held and the hint says "Place".
	await _press(0, builder.call("slot_button", 3))
	if (builder.call("held") as Array)[0] != 1:
		fail("the nova is not held in builder_holding")
		return
	await shot("builder_holding")
	tap(0, &"back")
	await settle(STEP_FRAMES)
	# Homing alone in staff Y: it lands on the caster and does nothing, so the note says why.
	await _press(0, builder.call("tab_button", 2))
	await _press(0, builder.call("slot_button", 0))
	await _press(0, _row(builder, "Homing"))
	_focus.call("focus", 0, builder.call("slot_button", 0))
	await shot("builder_wasted")
	# A stopped run leaves the HUD as it is, so close the builder as its owner would.
	tap(0, &"pause")
	await settle(STEP_FRAMES)
	flow.call("stop_run")
	await settle(STEP_FRAMES)
	for index in range(1, 4):
		_input.call("add_virtual_device", index)
	flow.call("start_run", 0)
	# The wave is live while the builders are staged; a downed wizard's builder closes, so keep
	# all four from being hurt meanwhile.
	if not await wait_for(func() -> bool: return flow.call("get_wizard", 3) != null):
		fail("player 4 has no wizard in builder_four_players")
		return
	for index in 4:
		Downed.of(flow.call("get_wizard", index) as Node).protect(60.0)
	await _open_builders([0, 1, 2, 3])
	# P1: staff X. P2: staff A. P3: staff Y with a pick. P4: staff B. Players press side by side.
	_focus_press(1, _hud.call("get_builder", 1).call("tab_button", 0))
	_focus_press(2, _hud.call("get_builder", 2).call("tab_button", 2))
	_focus_press(3, _hud.call("get_builder", 3).call("tab_button", 3))
	await settle(STEP_FRAMES)
	await _press(2, _hud.call("get_builder", 2).call("slot_button", 0))
	await _press(2, _row(_hud.call("get_builder", 2), "Orbit"))
	for index in 4:
		if not _hud.call("get_builder", index).call("is_open"):
			fail("the builder of player %d is not open in builder_four_players (focus panel open: %s)" % [index + 1, _focus.call("is_open", index)])
			return
	await shot("builder_four_players")
	for index in 4:
		tap(index, &"pause")
	await settle()
	flow.call("stop_run")
	await create_timer(0.3).timeout


## The bag row of the card named `display_name` in `builder`, or null.
func _row(builder: Node, display_name: String) -> Control:
	for row: Button in builder.call("shown_rows"):
		if row.text.trim_prefix("> ").begins_with(display_name):
			return row
	return null


## B (`back`) in play for each of `players`, as a person does; waits until every builder is open.
func _open_builders(players: Array[int]) -> void:
	for player in players:
		tap(player, &"back")
	await wait_for(func() -> bool: return players.all(func(player: int) -> bool: return _hud.call("get_builder", player).call("is_open")))
	await settle(STEP_FRAMES)


## Put the player's focus on `control` and press `accept` (activate) on it.
func _press(player: int, control: Control) -> void:
	_focus_press(player, control)
	await settle(STEP_FRAMES)


func _focus_press(player: int, control: Control) -> void:
	_focus.call("focus", player, control)
	tap(player, &"accept")
