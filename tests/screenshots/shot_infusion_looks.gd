extends "res://tests/support/screenshot.gd"
## Every infusion shows (the owner, 2026-11-08: "I would like this to be the case for all
## carriers/cards"): players 1 to 4 in a row with one, two, three and four infusions (INFUSIONS),
## first each slamming (its hammer bound in each infusion's colour: `infusion_slam`), then each
## firing bolts to the right (each look's palette, `shot_look.gdshaderinc`, and its motes in each
## infusion's colours: `infusion_bolts`).

const STAFF := preload("res://content/wizard/staffs/curl/curl.tres")
const INFUSIONS: Array = [[&"fire"], [&"fire", &"frost"], [&"fire", &"frost", &"storm"], [&"frost", &"void", &"fire", &"lightning"]]


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
	for p in 4:
		row[p].global_position = start + Vector2(70.0 * p, 0.0)
		input.call("send_virtual_aim", p, Vector2.RIGHT)
		var cards: Array[StringName] = []
		cards.assign(INFUSIONS[p])
		cards.append(&"slam")
		spells.call("install_staff", row[p].id, 3, spells.call("compile_staff", cards, STAFF))
	await settle(40)
	for p in 4:
		row[p].global_position = start + Vector2(70.0 * p, 0.0)
		spells.call("cast_staff", row[p].id, 3, row[p].global_position, Vector2.RIGHT, 100.0)
	# Raised, its hammer whole, before the blow.
	for frame in 11:
		await physics_frame
	await snap(start + Vector2(110.0, -16.0), "infusion_slam", Vector2i(280, 56), 3)
	await settle(60)
	for p in 4:
		row[p].global_position = start + Vector2(0.0, 60.0 * p - 90.0)
		var cards: Array[StringName] = []
		cards.assign(INFUSIONS[p])
		cards.append(&"bolt")
		spells.call("install_staff", row[p].id, 3, spells.call("compile_staff", cards, STAFF))
	await settle(20)
	for volley in 3:
		for p in 4:
			row[p].global_position = start + Vector2(0.0, 60.0 * p - 90.0)
			spells.call("cast_staff", row[p].id, 3, row[p].global_position, Vector2.RIGHT, 100.0)
		for frame in 6:
			await physics_frame
	await snap(start + Vector2(90.0, 0.0), "infusion_bolts", Vector2i(130, 130), 3)
