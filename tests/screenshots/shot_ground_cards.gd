extends "res://tests/support/screenshot.gd"
## Cards dropped on the floor (Feel's ground items, items I6) in play, at the cameras' resting zoom:
## four cards beside the wizard, each drawn at its icon's own size (16 world units: a 2x icon's every
## art pixel one pixel of the picture; ART2, the owner's answer of 2026-11-26). `ground_cards` is the
## screen; `ground_cards_4x` a crop four times bigger.

const CARDS: Array[StringName] = [&"fire", &"bolt", &"plus_two", &"on_hit"]


func take() -> void:
	if not need(["PlayerInput", "Flow", "Events", "Spells"]):
		return
	var input: Node = root.get_node("PlayerInput")
	var flow: Node = root.get_node("Flow")
	var events: Node = root.get_node("Events")
	var spells: Node = root.get_node("Spells")
	input.call("add_virtual_device", 0)
	if not flow.call("start_run", 0):
		fail("the run did not start")
		return
	await settle(30)
	var wizard: Node2D = flow.call("get_wizard", 0) as Node2D
	if wizard == null:
		fail("no wizard")
		return
	var at: Vector2 = wizard.global_position + Vector2(-36.0, 30.0)
	for i in CARDS.size():
		var view: Dictionary = {"kind": &"card", "id": CARDS[i], "count": 1, "icon": spells.call("component_icon", CARDS[i])}
		events.emit_signal("ground_item_changed", 9000 + i, at + Vector2(24.0 * i, 0.0), view)
	await settle(10)
	var image: Image = await grab()
	save(image, "ground_cards")
	save_crop(image, on_screen(at + Vector2(36.0, -8.0)), "ground_cards_4x", Vector2i(56, 24), 4)
