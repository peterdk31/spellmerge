extends "res://tests/support/screenshot.gd"
## Screenshots of the staff rows under the corner panels' mana bars (owner, 2026-10-27): each
## staff's glyph, its cast sequence by cast, the next cast in gold, wasted cards struck through,
## the delay as a shade on the button glyph (a dashed next cast during a recharge), and "+N"
## for a long staff.
##
## The sandbox with the dev staffs and four built staffs per wizard: the dash, a three-cast
## staff, one with a wasted card and a long one. Shots: one player just after casting (with a 3x
## crop of the panel), then four players, each having cast something else (with a 3x crop of
## each corner), and the same four corners again with the pause menu's other reload switch, the
## shade on the next cast (`hud_staffs_next_cast_p1-4`); and cast timing's looks by hand
## (`hud_staffs_cast_timing`: a wind-up, casts short of mana, a fizzle).

## The staffs every wizard starts with: a dash; three casts; two triggers before the same
## carrier, the second with nothing left to fire (wasted); a long staff that does not fit the row.
const CARDS: Array = [
	[&"dash"],
	[&"fire", &"bolt", &"frost", &"nova", &"bolt", &"bolt"],
	[&"fire", &"on_hit", &"on_expire", &"bolt", &"lightning", &"nova", &"bolt", &"homing"],
	[&"bolt", &"fire", &"bolt", &"frost", &"bolt", &"lightning", &"bolt", &"void", &"bolt", &"storm", &"bolt", &"pierce", &"bolt", &"chain", &"bolt", &"bigger", &"orbit"],
]
## Which staffs each player casts before the shot (staff_1 to staff_4), so the four corners show
## a ready staff, a delay, a recharge and a cycle moved on.
const CASTS: Array = [[&"staff_2", &"staff_1"], [&"staff_4", &"staff_1"], [&"staff_3", &"staff_2"], [&"staff_2"]]
## The centre of each corner panel on the 640x360 screen, and half the crop round it.
const CORNERS: Array[Vector2] = [Vector2(64, 52), Vector2(576, 52), Vector2(64, 308), Vector2(576, 308)]
const HALF := Vector2i(64, 52)

var _input: Node = null
var _flow: Node = null


func take() -> void:
	if not need(["PlayerInput", "Hud", "Flow", "Events"]):
		return
	_input = root.get_node("PlayerInput")
	_flow = root.get_node("Flow")
	var events: Node = root.get_node("Events")
	_flow.set("sandbox_cards", CARDS.duplicate(true))
	_input.call("add_virtual_device", 0)
	events.emit_signal("sandbox_requested", 0)
	if not await wait_for(func() -> bool: return _flow.get("sandbox") and _flow.call("get_wizard", 0) != null):
		fail("the sandbox did not start")
		return
	await settle(5)
	await _cast_all(1)
	var image: Image = await grab()
	save(image, "hud_staffs_one_player")
	save_crop(image, CORNERS[0], "hud_staffs_one_player_panel", HALF, 3)
	await _cast_timing_states()
	_flow.call("stop_run")
	await settle(3)
	for index in range(1, 4):
		_input.call("add_virtual_device", index)
	events.emit_signal("sandbox_requested", 0)
	if not await wait_for(func() -> bool: return _flow.call("get_wizard", 3) != null):
		fail("the sandbox did not start with four wizards")
		return
	for index in 4:
		Downed.of(_flow.call("get_wizard", index) as Node).protect(60.0)
	await settle(5)
	await _cast_all(4)
	image = await grab()
	save(image, "hud_staffs_four_players")
	for index in 4:
		save_crop(image, CORNERS[index], "hud_staffs_four_players_p%d" % (index + 1), HALF, 3)
	root.get_node("Hud").call("_on_reload_style_changed", false)
	await settle(1)
	image = await grab()
	save(image, "hud_staffs_next_cast")
	for index in 4:
		save_crop(image, CORNERS[index], "hud_staffs_next_cast_p%d" % (index + 1), HALF, 3)
	root.get_node("Hud").call("_on_reload_style_changed", true)
	_flow.call("stop_run")
	await create_timer(0.3).timeout


## Each of the first `players` players casts their staffs in CASTS, a few frames apart, aiming
## up, then a few frames pass so the delay bars are part way down.
func _cast_all(players: int) -> void:
	for index in players:
		_input.call("send_virtual_aim", index, Vector2.UP)
	for round in 2:
		for index in players:
			var casts: Array = CASTS[index]
			if round < casts.size():
				tap(index, casts[round])
		await settle(8)
	await settle(6)


## Cast timing's looks (docs/milestones/cast-timing.md, T5), set by hand on player 1's rows (the
## dev staff's mana pays everything): the dash winding up half way, the three-cast staff skipping
## to its third cast (the two before it short of mana), the third staff paying none (every cast
## left short), and the long staff just fizzled (`hud_staffs_cast_timing`).
func _cast_timing_states() -> void:
	var hud: Node = root.get_node("Hud")
	hud.set_process(false)
	var panel: Node = hud.call("get_panel", 0)
	(panel.call("staff_row", 0) as Object).call("set_timing", 0, 0.4, true)
	(panel.call("staff_row", 0) as Object).call("set_timing", 0, 0.2, true)
	(panel.call("staff_row", 1) as Object).call("set_timing", 0, 0.0, false, 2)
	(panel.call("staff_row", 2) as Object).call("set_timing", 0, 0.0, false, -1)
	(panel.call("staff_row", 3) as Object).call("set_timing", 0, 0.0, false)
	(panel.call("staff_row", 3) as Object).call("fizzle")
	await settle(1)
	var image: Image = await grab()
	save_crop(image, CORNERS[0], "hud_staffs_cast_timing", HALF, 3)
	hud.set_process(true)

