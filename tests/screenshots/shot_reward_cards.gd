extends "res://tests/support/screenshot.gd"
## Screenshots of the reward menu's cards (hud/menus/reward, the owner's redesign of 2026-11-19), in
## the hub: one player's offer of 2 (reward_cards_2) and of 3 (reward_cards_3), the cards laid out
## in the whole view, the second focused; then four players at once, each menu in its own quarter,
## offers of 2, 3, 4 and 5 (reward_cards_four_players: the fifth card past what fits a quarter,
## the row scrolled). The offers are told to the HUD as the Rewards area tells them
## (`reward_rolled`, `rewards_waiting_changed`), with real cards' names, icons and builder lines.

const DevHub := preload("res://tests/support/dev_hub.gd")

var _hud: Node = null
var _events: Node = null
var _spells: Node = null
var _cards: Array[StringName] = []


func take() -> void:
	if not need(["PlayerInput", "Hud", "Flow", "Events", "Registry", "Spells"]):
		return
	_hud = root.get_node("Hud")
	_events = root.get_node("Events")
	_spells = root.get_node("Spells")
	var input: Node = root.get_node("PlayerInput")
	var flow: Node = root.get_node("Flow")
	var registry: Node = root.get_node("Registry")
	for id: StringName in registry.call("get_ids", &"spells"):
		_cards.append(id)
	input.call("add_virtual_device", 0)
	if not DevHub.start(flow, registry):
		fail("the hub did not start")
		return
	if not await wait_for(func() -> bool: return flow.call("get_wizard", 0) != null):
		fail("the hub did not start")
		return
	await settle(10)
	for count: int in [2, 3]:
		if not await _offer(0, count, count):
			return
		tap(0, &"move_right")
		await _rest([0])
		await shot("reward_cards_%d" % count)
		tap(0, &"back")
		await settle(8)
	for seat in range(1, 4):
		input.call("add_virtual_device", seat)
	if not await wait_for(func() -> bool: return flow.call("get_wizard", 3) != null, 240):
		fail("the other three did not join")
		return
	await settle(10)
	for seat in 4:
		if not await _offer(seat, 10 + seat, seat + 2):
			return
	tap(3, &"move_left")
	await _rest([0, 1, 2, 3])
	await shot("reward_cards_four_players")
	for seat in 4:
		tap(seat, &"back")
	await settle(8)
	flow.call("stop_run")
	await create_timer(0.3).timeout


## Tell seat `seat` its offer `offer` of `count` choices was rolled with it there, its reward item in
## its reach, press A at it, and wait for its menu to open.
func _offer(seat: int, offer: int, count: int) -> bool:
	var choices: Array[Dictionary] = []
	# Every reward is an inventory item (the owner, 2026-11-19): a card, the coin, a potion; each
	# card shows its item's own name, icon and description.
	var items: Array[ItemContent] = [null, preload("res://content/coins/coin/coin.tres"), null, preload("res://content/potions/healing/healing.tres"), preload("res://content/potions/max_health/max_health.tres")]
	for at in count:
		var item: ItemContent = items[at % items.size()]
		var amount: int = [1, 12, 1, 2, 1][at % 5]
		var view: Dictionary = {"kind": ItemKinds.CARD, "id": &"", "count": amount, "name": "", "icon": null, "description": ""}
		if item == null and not _cards.is_empty():
			var id: StringName = _cards[(seat * 5 + at * 7) % _cards.size()]
			view["id"] = id
			view["name"] = _spells.call("component_name", id)
			view["icon"] = _spells.call("component_icon", id)
			view["description"] = _spells.call("component_description", id)
		elif item != null:
			view["kind"] = ItemKinds.COIN if item is CoinBase else ItemKinds.POTION
			view["id"] = item.id
			view["name"] = item.shown_name() if amount == 1 else "%s x%d" % [item.shown_name(), amount]
			view["icon"] = item.icon
			view["description"] = item.description
		choices.append(view)
	var offers: Array[Dictionary] = [{"offer": offer, "here": true, "lying": true, "choices": choices}]
	_events.reward_rolled.emit(seat, offer, choices, true)
	_events.rewards_waiting_changed.emit(seat, offers)
	# A reward never pops up (the owner, 2026-11-19): the seat stands at its reward item and presses A.
	_events.reward_near_changed.emit(seat, offer, Vector2.ZERO)
	tap(seat, &"take")
	if not await wait_for(func() -> bool: return _hud.call("get_reward", seat).call("is_open"), 60):
		fail("seat %d's reward menu did not open" % (seat + 1))
		return false
	return true


## Wait until the menus of `seats` rest (unrolled, the rim and the row slid).
func _rest(seats: Array) -> void:
	await wait_for(func() -> bool: return seats.all(func(seat: int) -> bool: return not _hud.call("get_reward", seat).call("is_moving")), 60)
	await settle(2)
