extends "res://tests/support/screenshot.gd"
## Oil's own look (docs/milestones/oil-spill.md; the look slots widened for it, the owner,
## 2026-11-26): rows of wizards firing bolts of Oil, Oil with Fire, Oil with Water and, to compare,
## Water alone, to the right, the drips hanging under each oil shot and falling, its sheen catching
## the light. Shots: `oil_look_bolts` (a volley in flight, 3x), `oil_look_strip` (four moments).

const STAFF := preload("res://content/wizard/staffs/curl/curl.tres")
const ROWS: Array = [[&"oil"], [&"oil", &"fire"], [&"oil", &"water"], [&"water"]]


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
		Downed.of(wizard).protect(60.0)
		row.append(wizard)
	var start: Vector2 = row[0].global_position + Vector2(-80.0, 0.0)
	for p in 4:
		row[p].global_position = start + Vector2(0.0, 40.0 * p - 60.0)
		input.call("send_virtual_aim", p, Vector2.RIGHT)
		var cards: Array[StringName] = []
		cards.assign(ROWS[p])
		cards.append(&"bolt")
		spells.call("install_staff", row[p].id, 3, spells.call("compile_staff", cards, STAFF))
	await settle(20)
	for volley in 3:
		for p in 4:
			row[p].global_position = start + Vector2(0.0, 40.0 * p - 60.0)
			spells.call("cast_staff", row[p].id, 3, row[p].global_position, Vector2.RIGHT, 100.0)
		for frame in 8:
			await physics_frame
	await snap(start + Vector2(80.0, 0.0), "oil_look_bolts", Vector2i(110, 90), 3)
	for moment in 4:
		await snap(start + Vector2(80.0, -60.0), "oil_look_strip_%d" % moment, Vector2i(90, 16), 4)
		for frame in 4:
			await physics_frame
