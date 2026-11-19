extends "res://tests/support/screenshot.gd"
## Screenshots of the inventory (items I7, hud/menus/inventory/): in the hub (the dev staffs, tests/support/dev_hub.gd), P1 with a staff in
## the bag opens it on the ring of the bags (inventory_bags), enters the staffs and points at
## the bag's staff, the hands column showing its arrows against every hand (inventory_staffs),
## enters the cards' kinds (inventory_kinds) and the carriers with their counts (inventory_cards);
## then all four players with their inventories open at once (inventory_four_players).

const DevHub := preload("res://tests/support/dev_hub.gd")

var _input: Node = null
var _hud: Node = null


func take() -> void:
	if not need(["PlayerInput", "Hud", "Flow", "Events", "Registry"]):
		return
	_input = root.get_node("PlayerInput")
	_hud = root.get_node("Hud")
	var flow: Node = root.get_node("Flow")
	var events: Node = root.get_node("Events")
	for index in 4:
		_input.call("add_virtual_device", index)
	if not DevHub.start(flow, root.get_node("Registry")):
		fail("the hub did not start")
		return
	if not await wait_for(func() -> bool: return flow.call("get_wizard", 3) != null):
		fail("the hub did not start with four wizards")
		return
	var registry: Node = root.get_node("Registry")
	var crystal: StaffBase = registry.call("get_resource", &"wizard", &"crystal") as StaffBase
	var moon: StaffBase = registry.call("get_resource", &"wizard", &"moon") as StaffBase
	for index in 4:
		var inventory: Inventory = (flow.call("get_wizard", index) as Actor).inventory
		inventory.add(ItemStack.of_staff(crystal, [&"bolt", &"split"] as Array[StringName]))
		inventory.add(ItemStack.of_staff(moon))
	if not await _open([0]):
		return
	var menu: Node = _hud.call("get_inventory", 0)
	await _point(0, menu, "bag", &"staffs")
	await shot("inventory_bags")
	tap(0, &"accept")
	await settle(4)
	await _point(0, menu, "staff", 4)
	await shot("inventory_staffs")
	tap(0, &"back")
	await settle(4)
	await _point(0, menu, "bag", &"cards")
	tap(0, &"accept")
	await settle(4)
	await _point(0, menu, "kind", &"carrier")
	await shot("inventory_kinds")
	tap(0, &"accept")
	await settle(4)
	await _point(0, menu, "card", &"bolt")
	await shot("inventory_cards")
	if not await _open([1, 2, 3]):
		return
	var bags: Array[StringName] = [&"staffs", &"staffs", &"cards", &"relics"]
	for index in range(1, 4):
		var other: Node = _hud.call("get_inventory", index)
		await _point(index, other, "bag", bags[index])
	await shot("inventory_four_players")
	for index in 4:
		tap(index, &"inventory")
	await settle(8)
	flow.call("stop_run")
	await create_timer(0.3).timeout


## Select for each of `players`; fails unless every one opened.
func _open(players: Array[int]) -> bool:
	for player in players:
		tap(player, &"inventory")
	var opened: bool = await wait_for(func() -> bool: return players.all(func(player: int) -> bool: return _hud.call("get_inventory", player).call("is_open")))
	if not opened:
		fail("the inventories of players %s did not all open" % str(players.map(func(player: int) -> int: return player + 1)))
	return opened


## Point `player`'s right stick at the entry of `menu` whose `key` is `value`, and hold it there.
func _point(player: int, menu: Node, key: String, value: Variant) -> void:
	var entry: int = menu.call("entry_of", key, value)
	if entry < 0:
		fail("%s %s is not on P%d's ring" % [key, value, player + 1])
		return
	_input.call("send_virtual_aim", player, menu.call("menu").call("direction_to", entry))
	await settle(6)
