extends "res://tests/support/screenshot.gd"
## Screenshots of the reward items and a shop's reroll sign (the owner's ask of 2026-11-19), in the
## hub, told to the view as the Rewards area tells them: four players' reward items lying in a row
## under the middle of a room, each in its player's colours, P1 standing at its own with its hint
## "Open reward" (reward_items); a shop's shelf of three items with its reroll sign under it, P1 at
## the sign with its hint "Reroll shelf (3)" (shop_sign), then the sign after two rerolls, its price
## risen to 8 (shop_sign_risen).

const DevHub := preload("res://tests/support/dev_hub.gd")
const EventsScript := preload("res://core/events/events.gd")


func take() -> void:
	if not need(["PlayerInput", "Hud", "Flow", "Events", "Registry", "Spells"]):
		return
	var events: Node = root.get_node("Events")
	var input: Node = root.get_node("PlayerInput")
	var flow: Node = root.get_node("Flow")
	var registry: Node = root.get_node("Registry")
	var spells: Node = root.get_node("Spells")
	input.call("add_virtual_device", 0)
	if not DevHub.start(flow, registry):
		fail("the hub did not start")
		return
	if not await wait_for(func() -> bool: return flow.call("get_wizard", 0) != null):
		fail("the hub did not start")
		return
	await settle(10)
	var wizard: Node2D = flow.call("get_wizard", 0)
	var feet: Vector2 = wizard.global_position
	# Four reward items in a row, as Flow lays their spots; P1's under its feet.
	var row: Array[Vector2] = [Vector2(-36, 32), Vector2(-12, 32), Vector2(12, 32), Vector2(36, 32)]
	for seat in 4:
		events.reward_item_changed.emit(seat, 100 + seat, feet + row[seat] - row[0] + Vector2(0, 2), true)
	events.reward_near_changed.emit(0, 100, feet + Vector2(0, 2))
	await settle(30)
	await shot("reward_items")
	for seat in 4:
		events.reward_item_changed.emit(seat, 100 + seat, Vector2.ZERO, false)
	events.reward_near_changed.emit(0, -1, Vector2.ZERO)
	await settle(20)
	# A shop's shelf of three and its sign under it, P1 at the sign.
	var cards: Array = registry.call("get_ids", &"spells")
	var shelf_at: Vector2 = feet + Vector2(0, -40)
	var potion: ItemContent = preload("res://content/potions/healing/healing.tres")
	var items: Array[Dictionary] = [
		{"kind": ItemKinds.CARD, "id": cards[3], "count": 1, "name": spells.call("component_name", cards[3]), "icon": spells.call("component_icon", cards[3]), "description": ""},
		{"kind": ItemKinds.POTION, "id": potion.id, "count": 1, "name": potion.shown_name(), "icon": potion.icon, "description": ""},
		{"kind": ItemKinds.CARD, "id": cards[9], "count": 1, "name": spells.call("component_name", cards[9]), "icon": spells.call("component_icon", cards[9]), "description": ""},
	]
	var prices: Array[int] = [8, 6, 14]
	for at in items.size():
		events.shelf_changed.emit(200 + at, shelf_at + Vector2(-48 + 48 * at, 0), items[at], prices[at], true)
	var sign_view: Dictionary = {"kind": EventsScript.SHELF_SIGN, "id": &"", "count": 1, "name": "Reroll shelf", "icon": null, "description": ""}
	events.shelf_changed.emit(203, feet, sign_view, 3, true)
	var near: Dictionary = sign_view.duplicate()
	near["price"] = 3
	events.shelf_near_changed.emit(0, 203, feet, near)
	await settle(30)
	await shot("shop_sign")
	events.shelf_changed.emit(203, feet, sign_view, 8, true)
	near["price"] = 8
	events.shelf_near_changed.emit(0, 203, feet, near)
	await settle(10)
	await shot("shop_sign_risen")
	flow.call("stop_run")
	await create_timer(0.3).timeout
