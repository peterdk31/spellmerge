extends "res://tests/support/screenshot.gd"
## Screenshots of the d-pad's quick-use slots and the held map's legend (the owner, 2026-11-20).
##
## In the hub (the dev staffs, tests/support/dev_hub.gd), four players on virtual pads, each wizard with
## a six-slot staff of six cards on RB and potions: the inventory's potions ring with the healing
## potion pointed at, bound to the d-pad's up by a press (its glyph beside it, "Bind" on the hint row;
## quick_inventory_bind), then the small healing potion pointed at, bound left with none left: still on
## the ring, greyed with 0 (quick_ring_none_left); every corner panel with its d-pad cross beside
## six-slot staff rows: up the healing potions, right the max health potion, left the small healing
## potions with none left (greyed, 0), down bound to nothing; P2's cross with nothing bound, every arm
## an empty cell (the cross always shows, the owner's of 2026-11-20) (quick_panels), and P1's and
## P2's panels cropped 4x (quick_panel_p1, quick_panel_empty). Then P3 uses a shot-only active
## relic bound down (it borrows the vigor potion's icon: no relic has art yet) and its panel is
## cropped 4x while it recharges, the shutter part way down its icon (quick_relic_recharging); P3
## drops it and P4 takes it from the ground, still recharging (the recharge travels with the relic):
## P4's panel cropped 4x, its down arm the relic, its shutter sunk a little further
## (quick_relic_taken_recharging).
## Then, on the split test map (tests/support/biome_maps.gd) played by the keyboard, P1 holding M
## (Y on a pad) in the antechamber, the map open with its legend along the frame's foot: the d-pad's
## glyph ("1-4" on the keyboard) "Move teleport target" and F (A) "Teleport" (quick_map_legend).

const DevHub := preload("res://tests/support/dev_hub.gd")
const BiomeMaps := preload("res://tests/support/biome_maps.gd")

const POTIONS: StringName = &"potions"

var _input: Node = null
var _hud: Node = null


func take() -> void:
	if not need(["PlayerInput", "Hud", "Flow", "Events", "Registry"]):
		return
	_input = root.get_node("PlayerInput")
	_hud = root.get_node("Hud")
	var flow: Node = root.get_node("Flow")
	var registry: Node = root.get_node("Registry")
	for index in 4:
		_input.call("add_virtual_device", index)
	if not DevHub.start(flow, registry):
		fail("the hub did not start")
		return
	if not await wait_for(func() -> bool: return flow.call("get_wizard", 3) != null):
		fail("the hub did not start with four wizards")
		return
	var crystal: StaffBase = registry.call("get_resource", &"wizard", &"crystal") as StaffBase
	for index in 4:
		var wizard := flow.call("get_wizard", index) as Actor
		var inventory: Inventory = wizard.inventory
		inventory.add(ItemStack.of(ItemKinds.POTION, &"healing", 3))
		inventory.add(ItemStack.of(ItemKinds.POTION, &"max_health", 1))
		inventory.add(ItemStack.of(ItemKinds.POTION, &"small_healing", 1))
		var number: int = inventory.hands()[0]
		if crystal != null and inventory.set_hand(number, Inventory.NO_HAND) == Inventory.Refusal.NONE:
			inventory.add(ItemStack.of_staff(crystal, [&"bolt", &"plus_two", &"bolt", &"bolt", &"plus_two", &"bolt"] as Array[StringName]))
			var numbers: PackedInt32Array = inventory.numbers()
			inventory.set_hand(numbers[numbers.size() - 1], 0)
		# Taken, each potion filled a free arm (the owner, 2026-11-20); laid out by hand here.
		for slot in Inventory.QUICK_SLOTS:
			inventory.bind_quick(slot, POTIONS, &"")
		if index == 1:
			# P2 binds nothing: the empty cross.
			continue
		inventory.bind_quick(1, POTIONS, &"max_health")
		inventory.bind_quick(3, POTIONS, &"small_healing")
		inventory.take(POTIONS, &"small_healing", 1)
		if index != 0:
			inventory.bind_quick(0, POTIONS, &"healing")
	await settle(20)
	# P1 binds the healing potions to up in the inventory.
	tap(0, &"inventory")
	if not await wait_for(func() -> bool: return _hud.call("get_inventory", 0).call("is_open")):
		fail("P1's inventory did not open")
		return
	var menu: Node = _hud.call("get_inventory", 0)
	await _point(menu, "bag", POTIONS)
	tap(0, &"accept")
	await settle(4)
	await _point(menu, "item", &"healing")
	tap(0, &"quick_up")
	await settle(10)
	var wizard := flow.call("get_wizard", 0) as Actor
	if wizard.inventory.quick_id(0) != &"healing":
		fail("the d-pad's up did not bind the healing potion")
		return
	await shot("quick_inventory_bind")
	await _point(menu, "item", &"small_healing")
	await settle(10)
	await shot("quick_ring_none_left")
	_input.call("send_virtual_aim", 0, Vector2.ZERO)
	tap(0, &"inventory")
	await settle(30)
	await shot("quick_panels")
	var panel := _hud.call("get_panel", 0) as Control
	var image: Image = await grab()
	save_crop(image, panel.get_global_rect().get_center(), "quick_panel_p1", Vector2i(64, 36))
	var empty := _hud.call("get_panel", 1) as Control
	save_crop(image, empty.get_global_rect().get_center(), "quick_panel_empty", Vector2i(64, 36))
	await _relic_recharging(flow, registry)
	flow.call("stop_run")
	await settle(10)
	for index in 4:
		_input.call("leave", index)
	await settle(4)
	await _map_legend(flow, registry)


## P3 uses a shot-only active relic bound down: kept, recharging for 4 s, shot a second in.
func _relic_recharging(flow: Node, registry: Node) -> void:
	var relic := RelicBase.new()
	relic.id = &"shot_active_idol"
	relic.icon = load("res://content/potions/vigor/icon@2x.svg") as Texture2D
	relic.active_use = ItemUse.kept(10.0, 0.0, 4.0)
	var added: bool = registry.call("add", &"relics", relic)
	var wizard := flow.call("get_wizard", 2) as Actor
	var stack := ItemStack.new()
	stack.kind = ItemKinds.RELIC
	stack.id = relic.id
	var taken: bool = wizard.inventory.add(stack)
	# Taken, it fills the one free arm, down (the owner's auto-bind).
	wizard.health.health = wizard.health.max_health * 0.5
	await settle(10)
	tap(2, &"quick_down")
	await settle(60)
	if wizard.inventory.recharge_left(&"relics", relic.id) <= 0.0:
		fail("P3's relic did not start recharging (added %s, taken %s, down bound to %s)" % [added, taken, wizard.inventory.quick_id(2)])
		return
	var panel := _hud.call("get_panel", 2) as Control
	var image: Image = await grab()
	save_crop(image, panel.get_global_rect().get_center(), "quick_relic_recharging", Vector2i(64, 36))
	await _relic_handed_on(wizard, flow.call("get_wizard", 3) as Actor, relic.id)
	registry.call("remove", &"relics", relic.id)


## P3 drops its recharging relic and P4 takes it from the ground (the recharge travels with the
## relic, the owner's of 2026-11-20): P4's free arm, down, binds it, its shutter part way down.
func _relic_handed_on(dropper: Actor, taker: Actor, id: StringName) -> void:
	var items: Node = root.get_node_or_null("Items")
	if items == null or taker == null:
		fail("no Items area or no P4")
		return
	if dropper.inventory.drop(&"relics", id) != Inventory.Refusal.NONE:
		fail("P3 could not drop its relic")
		return
	await settle(30)
	var lying: Array = items.call("lying")
	var row: GroundItem = null
	for each: GroundItem in lying:
		if each.stack.id == id:
			row = each
	if row == null or not row.stack.is_recharging():
		fail("the relic does not lie recharging")
		return
	taker.global_position = row.at
	await settle(2)
	items.call("take", taker.id, row.number)
	await settle(20)
	if taker.inventory.recharge_left(&"relics", id) <= 0.0:
		fail("P4 took the relic ready, not mid-recharge (holds %d)" % taker.inventory.count_of(&"relics", id))
		return
	var panel := _hud.call("get_panel", 3) as Control
	var image: Image = await grab()
	save_crop(image, panel.get_global_rect().get_center(), "quick_relic_taken_recharging", Vector2i(64, 36))


## The keyboard's P1 holding M on the split test map.
func _map_legend(flow: Node, registry: Node) -> void:
	_input.call("join", int(_input.get("KEYBOARD")))
	var map: BiomeMap = BiomeMaps.split(registry)
	var fights: Array[RoomFight] = [RoomFight.new(), RoomFight.new(), RoomFight.new()]
	if not flow.call("start_biome", 0, map, fights):
		fail("the biome did not start")
		return
	await settle()
	var wizard := flow.call("get_wizard", 0) as Node2D
	var west: Vector2 = BiomeMaps.socket_point(registry, map, 1, RoomSocket.Facing.EAST)
	wizard.global_position = west - Vector2(64.0, 0.0)
	await settle(40)
	_key(KEY_M, true)
	# The frame opens in four stages, then the legend rises in four.
	await settle(60)
	var legend: Node = _hud.call("get_map_legend")
	if int(legend.call("stage_of", 0)) <= 0:
		fail("the map's legend did not rise")
		return
	await shot("quick_map_legend")
	_key(KEY_2, true)
	_key(KEY_2, false)
	await settle(10)
	_key(KEY_M, false)
	await settle(10)
	flow.call("stop_run")
	await create_timer(0.3).timeout


func _key(key: Key, down: bool) -> void:
	var press := InputEventKey.new()
	press.physical_keycode = key
	press.pressed = down
	_input.call("handle_event", press)


## Point P1's right stick at the entry of `menu` whose `key` is `value`, and hold it there.
func _point(menu: Node, key: String, value: Variant) -> void:
	var entry: int = menu.call("entry_of", key, value)
	if entry < 0:
		fail("%s %s is not on P1's ring" % [key, value])
		return
	_input.call("send_virtual_aim", 0, menu.call("menu").call("direction_to", entry))
	await settle(6)
