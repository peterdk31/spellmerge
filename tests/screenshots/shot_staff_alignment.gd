extends "res://tests/support/screenshot.gd"
## Staff animations against their spell's look, marked (2026-10-30): every carrier card whose
## `staff_pose` lands (`land`) is cast by real wizards in a run along 8 aims, four at a time, and
## shot while their staffs are landed (the slam's local stop holds them there). Each cell marks the
## drawn tip (`StaffLook.tip_position`, a white cross) and the point the carrier strikes (the hand
## plus `Spells.poses().staff_land_point`, a red ring): on a good card the cross sits in the ring and
## the strike's look is under both. `staff_alignment_<card>_<round>`, a 4x crop of the row. The test
## tests/gameplay/player/test_staff_alignment.gd checks the same in numbers.

const STAFF := preload("res://content/wizard/staffs/curl/curl.tres")
const AIMS: Array[float] = [0.0, 45.0, 90.0, 135.0, 180.0, 225.0, 270.0, 315.0]
## The wizards stand this far apart, in a row.
const APART: float = 64.0


## Draws the marks over the wizards: a cross on each tip, a ring round each point struck.
class Marks:
	extends Node2D
	var tips: Array[Vector2] = []
	var struck: Array[Vector2] = []

	func _draw() -> void:
		for at: Vector2 in struck:
			draw_arc(at, 2.5, 0.0, TAU, 12, Color(1.0, 0.2, 0.2), 1.0)
		for at: Vector2 in tips:
			draw_line(at + Vector2(-2.0, 0.0), at + Vector2(2.0, 0.0), Color.WHITE, 1.0)
			draw_line(at + Vector2(0.0, -2.0), at + Vector2(0.0, 2.0), Color.WHITE, 1.0)


func take() -> void:
	change_scene_to_file("res://hud/menus/main_menu/main_menu.tscn")
	await settle()
	if not need(["PlayerInput", "Flow", "Spells", "Feel", "Registry"]):
		return
	var input: Node = root.get_node("PlayerInput")
	var flow: Node = root.get_node("Flow")
	var spells: SpellRuntime = root.get_node("Spells") as SpellRuntime
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
	var registry: Node = root.get_node("Registry")
	var cards: Array[StringName] = []
	for id: StringName in registry.call("get_ids", &"spells"):
		var form: FormBase = registry.call("get_resource", &"spells", id) as FormBase
		if form != null and form.lands():
			cards.append(id)
	var start: Vector2 = row[0].global_position + Vector2(-APART * 1.5, 0.0)
	var marks := Marks.new()
	marks.z_index = 100
	row[0].get_parent().add_child(marks)
	for card: StringName in cards:
		var ids: Array[StringName] = [card]
		for r in AIMS.size() / 4:
			for p in 4:
				row[p].global_position = start + Vector2(APART * p, 0.0)
				input.call("send_virtual_aim", p, Vector2.RIGHT.rotated(deg_to_rad(AIMS[r * 4 + p])))
			await settle(20)
			marks.tips.clear()
			marks.struck.clear()
			marks.queue_redraw()
			for p in 4:
				spells.install_staff(row[p].id, 3, spells.compile_staff(ids, STAFF))
				spells.cast_staff(row[p].id, 3, row[p].global_position, row[p].aim, 100.0)
			var landed: bool = await wait_for(func() -> bool:
				return row.all(func(body: Actor) -> bool: return spells.poses().staff_land(body.id) >= 0.999), 60)
			if not landed:
				fail("%s: the staffs never landed" % card)
				return
			await physics_frame
			for body: Actor in row:
				var look: StaffLook = null
				for child in body.get_children():
					if child is StaffLook:
						look = child as StaffLook
				marks.tips.append(look.tip_position())
				marks.struck.append(body.aim_pivot() + spells.poses().staff_land_point(body.id))
			marks.queue_redraw()
			await snap(start + Vector2(APART * 1.5, -12.0), "staff_alignment_%s_%d" % [card, r + 1], Vector2i(130, 34), 4)
			await settle(60)
