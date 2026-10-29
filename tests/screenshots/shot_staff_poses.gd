extends "res://tests/support/screenshot.gd"
## Staff animations (the carriers' `staff_pose`, melee I8) on real wizards in a run: player 1
## slams to the right (rises glowing, tilts up and draws back, drops onto the floor, settles),
## player 3 slams to the left (the tilt flips with the facing) and player 2 swings (leans back,
## sweeps, holds). Then the other carriers four at a time (`staff_poses_r<round>_a` early,
## `_b` a little later), each with its card's animation. `staff_poses_windup` mid wind-up, `staff_poses_strike` just after the slam's impact,
## `staff_poses_after` while they hold; each a 4x crop of the two wizards.

const STAFF := preload("res://content/wizard/staffs/curl/curl.tres")


func take() -> void:
	change_scene_to_file("res://hud/menus/main_menu/main_menu.tscn")
	await settle()
	if not need(["PlayerInput", "Flow", "Spells", "Feel"]):
		return
	var input: Node = root.get_node("PlayerInput")
	var flow: Node = root.get_node("Flow")
	var spells: Node = root.get_node("Spells")
	root.get_node("Feel").set("drive_engine", false)
	input.call("add_virtual_device", 0)
	input.call("add_virtual_device", 1)
	input.call("add_virtual_device", 2)
	flow.call("start_run", 0)
	await settle()
	var slammer: Actor = flow.call("get_wizard", 0) as Actor
	var swinger: Actor = flow.call("get_wizard", 1) as Actor
	var lefty: Actor = flow.call("get_wizard", 2) as Actor
	if slammer == null or swinger == null or lefty == null:
		fail("the run has no wizards for players 1 to 3")
		return
	swinger.global_position = slammer.global_position + Vector2(70.0, 0.0)
	lefty.global_position = slammer.global_position + Vector2(-50.0, 0.0)
	await settle(4)
	var centre: Vector2 = slammer.global_position + Vector2(20.0, -12.0)
	var slam_cards: Array[StringName] = [&"slam"]
	var swing_cards: Array[StringName] = [&"swing"]
	spells.call("install_staff", slammer.id, 3, spells.call("compile_staff", slam_cards, STAFF))
	spells.call("install_staff", swinger.id, 3, spells.call("compile_staff", swing_cards, STAFF))
	spells.call("cast_staff", slammer.id, 3, slammer.global_position, Vector2.RIGHT, 100.0)
	spells.call("cast_staff", swinger.id, 3, swinger.global_position, Vector2.RIGHT, 100.0)
	spells.call("install_staff", lefty.id, 3, spells.call("compile_staff", slam_cards, STAFF))
	spells.call("cast_staff", lefty.id, 3, lefty.global_position, Vector2.LEFT, 100.0)
	for n in 11:
		await physics_frame
	await snap(centre, "staff_poses_windup", Vector2i(120, 32), 4)
	for n in 6:
		await physics_frame
	await snap(centre, "staff_poses_strike", Vector2i(120, 32), 4)
	for n in 6:
		await physics_frame
	await snap(centre, "staff_poses_after", Vector2i(120, 32), 4)
	# The other carriers, four at a time (players 1-4 in a row), each its own card's animation.
	input.call("add_virtual_device", 3)
	await settle(30)
	var row: Array[Actor] = []
	for p in 4:
		var wizard: Actor = flow.call("get_wizard", p) as Actor
		if wizard == null:
			fail("there is no wizard for player %d" % (p + 1))
			return
		row.append(wizard)
	var start: Vector2 = slammer.global_position + Vector2(-60.0, 70.0)
	for p in 4:
		row[p].global_position = start + Vector2(60.0 * p, 0.0)
		input.call("send_virtual_aim", p, Vector2.RIGHT)
	await settle(30)
	var middle: Vector2 = start + Vector2(90.0, -10.0)
	var rounds: Array = [[&"bolt", &"nova", &"beam", &"rain"], [&"rune", &"hook", &"teleport", &"familiar"], [&"orbit", &"fissure", &"wall", &"decoy"]]
	for r in rounds.size():
		for p in 4:
			row[p].global_position = start + Vector2(60.0 * p, 0.0)
		await settle(2)
		for p in 4:
			var cards: Array[StringName] = [rounds[r][p]]
			spells.call("install_staff", row[p].id, 3, spells.call("compile_staff", cards, STAFF))
			spells.call("cast_staff", row[p].id, 3, row[p].global_position, Vector2.RIGHT, 100.0)
		for n in 4:
			await physics_frame
		await snap(middle, "staff_poses_r%d_a" % (r + 1), Vector2i(130, 36), 3)
		for n in 6:
			await physics_frame
		await snap(middle, "staff_poses_r%d_b" % (r + 1), Vector2i(130, 36), 3)
		await settle(60)
