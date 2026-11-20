extends "res://tests/support/screenshot.gd"
## Screenshots of the starter staffs' six slots (the owner, 2026-11-20): the hub with P1 holding the
## four starter staffs (curl, star, moon, crystal) on its hands, each built full, its corner panel's
## staff rows (`starter_slots_panel`, a 3x crop) and its radial builder open on the first staff
## (`starter_slots_radial`), every slot shown.

## The starter staffs on P1's hands, in order.
const STARTERS: Array[StringName] = [&"curl", &"star", &"moon", &"crystal"]
## Six cards a hand: a cast or two of a full staff.
const CARDS: Array = [
	[&"fire", &"bolt", &"frost", &"bolt", &"lightning", &"bolt"],
	[&"triple", &"bolt", &"bolt", &"bolt", &"homing", &"pierce"],
	[&"on_hit", &"bolt", &"nova", &"void", &"bigger", &"bolt"],
	[&"dash", &"frost", &"orbit", &"bolt", &"chain", &"bolt"],
]
## The centre of P1's corner panel on the 640x360 screen, and half the crop round it.
const CORNER := Vector2(64, 52)
const HALF := Vector2i(64, 52)


func take() -> void:
	if not need(["PlayerInput", "Hud", "Flow", "Registry"]):
		return
	var input: Node = root.get_node("PlayerInput")
	var hud: Node = root.get_node("Hud")
	var flow: Node = root.get_node("Flow")
	var registry: Node = root.get_node("Registry")
	input.call("add_virtual_device", 0)
	flow.set(&"mode", &"hub")
	if not bool(flow.call("start_run", 0, _party(registry))):
		fail("the hub did not start")
		return
	if not await wait_for(func() -> bool: return flow.call("get_wizard", 0) != null):
		fail("the hub has no wizard")
		return
	await settle(5)
	var image: Image = await grab()
	save(image, "starter_slots_hub")
	save_crop(image, CORNER, "starter_slots_panel", HALF, 3)
	hud.call("_on_builder_options_changed", 0, true)
	tap(0, &"back")
	if not await wait_for(func() -> bool: return bool(hud.call("get_radial", 0).call("is_open"))):
		fail("the radial builder did not open")
		return
	await shot("starter_slots_radial")
	tap(0, &"back")
	await settle(5)
	flow.call("stop_run")
	await settle(3)


## P1 with the starter staffs on its hands, built as CARDS, and a bag of every card.
func _party(registry: Node) -> PartyLoadout:
	var out := PartyLoadout.new()
	var loadout := PlayerLoadout.new()
	var bag: Dictionary = Inventory.dev_cards(registry)
	for id: StringName in bag:
		loadout.add_stack(&"cards", id, int(bag[id]))
	var hands := PackedInt32Array()
	for hand in STARTERS.size():
		var built: Array[StringName] = []
		for card: Variant in CARDS[hand]:
			built.append(StringName(card))
		loadout.add_staff(hand, STARTERS[hand], built)
		hands.append(hand)
	loadout.set_hands(hands)
	out.put(0, loadout)
	return out
