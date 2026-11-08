extends "res://tests/support/screenshot.gd"
## A slam's staff turning into a hammer (its `hammer` pose channel, core/projectiles/staff_hammer.gdshader;
## the owner, 2026-11-08): players 1 to 4 in a row each slam to the right, cast so the shot catches
## each at another moment of it (SINCE: early in the wind-up as the hammer forms white-hot, raised
## and whole, just after the impact, and going back into the staff as it settles), each in its own
## ramp. `slam_hammer` is a 3x crop of the row; `slam_hammer_4x` the second wizard's whole hammer.

const STAFF := preload("res://content/wizard/staffs/curl/curl.tres")
## Frames from each wizard's cast to the shot (60 a second; a 0.25 s wind-up, then the impact).
const SINCE: Array[int] = [5, 12, 18, 34]


func take() -> void:
	change_scene_to_file("res://hud/menus/main_menu/main_menu.tscn")
	await settle()
	if not need(["PlayerInput", "Flow", "Spells", "Feel"]):
		return
	var input: Node = root.get_node("PlayerInput")
	var flow: Node = root.get_node("Flow")
	var spells: Node = root.get_node("Spells")
	root.get_node("Feel").set("drive_engine", false)
	for p in 4:
		input.call("add_virtual_device", p)
	flow.call("start_run", 0)
	await settle(30)
	var row: Array[Actor] = []
	for p in 4:
		var wizard: Actor = flow.call("get_wizard", p) as Actor
		if wizard == null:
			fail("there is no wizard for player %d" % (p + 1))
			return
		row.append(wizard)
	var start: Vector2 = row[0].global_position + Vector2(-80.0, 40.0)
	var cards: Array[StringName] = [&"slam"]
	for p in 4:
		row[p].global_position = start + Vector2(60.0 * p, 0.0)
		input.call("send_virtual_aim", p, Vector2.RIGHT)
		spells.call("install_staff", row[p].id, 3, spells.call("compile_staff", cards, STAFF))
	# The camera follows the group: let it come round to the row.
	await settle(40)
	var longest: int = SINCE.max()
	for frame in longest:
		for p in 4:
			if longest - frame == SINCE[p]:
				row[p].global_position = start + Vector2(60.0 * p, 0.0)
				spells.call("cast_staff", row[p].id, 3, row[p].global_position, Vector2.RIGHT, 100.0)
		await physics_frame
	await snap(start + Vector2(90.0, -14.0), "slam_hammer", Vector2i(240, 44), 3)
	await snap(row[1].global_position + Vector2(8.0, -14.0), "slam_hammer_4x", Vector2i(48, 40), 6)
