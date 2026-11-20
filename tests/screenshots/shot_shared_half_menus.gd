extends "res://tests/support/screenshot.gd"
## Screenshots of two players sharing a half of the equal split, each with its own quarter of the
## half, the corner panel with its menus (the owner, 2026-11-20 and on #881;
## gameplay/feel/equal_panes.gd `_part`, hud/panels/seat_corners.gd), on the split test map
## (tests/support/biome_maps.gd):
## - `shared_half_panels`: four players in two pairs, the halves, no menu open: P2's panel at the
##   bottom left, P3's at the top right.
## - `shared_half_builders`: the same four with their builders open, P2's in the bottom left
##   quarter, P3's in the top right.
## - `shared_half_inventories`: the same four with their inventories open.
## - `shared_half_rewards`: the same four with a reward menu open (each corner panel hidden, since
##   its reward menu covers part of it).
## - `shared_half_twin_builders`: a pair and two alone: the pair the left half, P2's builder (and
##   panel) in its twin quarter, P1's in the top one.

const BiomeMaps := preload("res://tests/support/biome_maps.gd")
const COIN: ItemContent = preload("res://content/coins/coin/coin.tres")
const HEALING: ItemContent = preload("res://content/potions/healing/healing.tres")

var _hud: Node = null
var _events: Node = null


func take() -> void:
	if not need(["PlayerInput", "Flow", "Feel", "Registry", "Hud", "Events"]):
		return
	settle_frames = 30
	var input: Node = root.get_node("PlayerInput")
	var flow: Node = root.get_node("Flow")
	var registry: Node = root.get_node("Registry")
	var feel: Node = root.get_node("Feel")
	_hud = root.get_node("Hud")
	_events = root.get_node("Events")
	feel.call("set_split_mode", SplitScreenSetting.EQUAL)
	var map: BiomeMap = BiomeMaps.split(registry)
	var west: Vector2 = BiomeMaps.socket_point(registry, map, 1, RoomSocket.Facing.EAST) - Vector2(120.0, 0.0)
	var east: Vector2 = BiomeMaps.socket_point(registry, map, 2, RoomSocket.Facing.WEST) + Vector2(120.0, 0.0)
	var nave_west: Vector2 = BiomeMaps.socket_point(registry, map, 0, RoomSocket.Facing.WEST)
	var nave_east: Vector2 = BiomeMaps.socket_point(registry, map, 0, RoomSocket.Facing.EAST)
	var nave: Vector2 = (nave_west + nave_east) * 0.5
	for seat in 4:
		input.call("add_virtual_device", seat)
	var fights: Array[RoomFight] = [RoomFight.new(), RoomFight.new(), RoomFight.new()]
	if not flow.call("start_biome", 0, map, fights):
		fail("the biome did not start")
		return
	await settle(30)
	_wizard(flow, 0).global_position = west
	_wizard(flow, 1).global_position = west + Vector2(40.0, 24.0)
	_wizard(flow, 2).global_position = east
	_wizard(flow, 3).global_position = east + Vector2(-40.0, 24.0)
	await settle(240)
	if not _views_are(feel, 2, "two pairs"):
		return
	await shot("shared_half_panels")
	# The builders.
	if not await _open([0, 1, 2, 3], &"back", "get_radial"):
		return
	await settle(30)
	await shot("shared_half_builders")
	for seat in 4:
		tap(seat, &"back")
	await settle(10)
	# The inventories.
	if not await _open([0, 1, 2, 3], &"inventory", "get_inventory"):
		return
	await settle(30)
	await shot("shared_half_inventories")
	for seat in 4:
		_hud.call("get_inventory", seat).call("close_inventory")
	await settle(10)
	# The reward menus.
	for seat in 4:
		if not await _offer(seat, seat + 1):
			return
	await wait_for(func() -> bool: return range(4).all(func(seat: int) -> bool: return not _hud.call("get_reward", seat).call("is_moving")), 60)
	await settle(4)
	await shot("shared_half_rewards")
	for seat in 4:
		_hud.call("get_reward", seat).call("close_menu")
	await settle(10)
	# A pair and two alone: P4 walks off.
	_wizard(flow, 3).global_position = nave + Vector2(0.0, 40.0)
	await settle(300)
	if not _views_are(feel, 3, "a pair and two alone"):
		return
	if not await _open([0, 1], &"back", "get_radial"):
		return
	await settle(30)
	await shot("shared_half_twin_builders")
	flow.call("stop_run")
	await create_timer(0.3).timeout


## `action` for each of `seats`; fails unless each one's menu (`getter` on the HUD) opened.
func _open(seats: Array[int], action: StringName, getter: String) -> bool:
	for seat in seats:
		tap(seat, action)
	var opened: bool = await wait_for(func() -> bool: return seats.all(func(seat: int) -> bool: return _hud.call(getter, seat).call("is_open")))
	if not opened:
		fail("the %s menus of seats %s did not all open" % [getter, str(seats)])
	return opened


## Seat `seat`'s offer `offer` of a coin pile and a healing potion, lying at it, opened with A.
func _offer(seat: int, offer: int) -> bool:
	var choices: Array[Dictionary] = []
	for item: ItemContent in [COIN, HEALING]:
		var kind: StringName = ItemKinds.COIN if item is CoinBase else ItemKinds.POTION
		choices.append({"kind": kind, "id": item.id, "count": 1, "name": item.shown_name(), "icon": item.icon, "description": item.description})
	_events.reward_rolled.emit(seat, offer, choices, true)
	_events.rewards_waiting_changed.emit(seat, [{"offer": offer, "here": true, "lying": true, "choices": choices}] as Array[Dictionary])
	_events.reward_near_changed.emit(seat, offer, Vector2.ZERO)
	tap(seat, &"take")
	if not await wait_for(func() -> bool: return _hud.call("get_reward", seat).call("is_open"), 60):
		fail("seat %d's reward menu did not open" % (seat + 1))
		return false
	return true


func _wizard(flow: Node, seat: int) -> Node2D:
	return flow.call("get_wizard", seat) as Node2D


func _views_are(feel: Node, want: int, what: String) -> bool:
	var split: Object = feel.get("split_screen")
	var views: int = int((split.get("camera") as Object).get("views").get("count")) if split != null else 0
	print("SHARED HALF MENUS: %s, %d views" % [what, views])
	if views != want:
		fail("%s: %d views, not %d" % [what, views, want])
		return false
	return true
