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


## Tell seat `seat` its offer `offer` of `count` choices was rolled with it there, and wait for its
## menu to open.
func _offer(seat: int, offer: int, count: int) -> bool:
	var choices: Array[Dictionary] = []
	var kinds: Array[StringName] = [RewardEntry.CARD, RewardEntry.COINS, RewardEntry.CARD, RewardEntry.HEAL, RewardEntry.MAX_HEALTH]
	for at in count:
		var kind: StringName = kinds[at % kinds.size()]
		var amount: int = [1, 12, 1, 6, 4][at % 5]
		var view: Dictionary = {"kind": kind, "id": &"", "count": amount, "name": "", "icon": null, "description": RewardEntry.describe(kind, amount)}
		if kind == RewardEntry.CARD and not _cards.is_empty():
			var id: StringName = _cards[(seat * 5 + at * 7) % _cards.size()]
			view["id"] = id
			view["name"] = _spells.call("component_name", id)
			view["icon"] = _spells.call("component_icon", id)
			view["description"] = _spells.call("component_description", id)
		elif kind == RewardEntry.COINS:
			view["name"] = "%d coins" % amount
		elif kind == RewardEntry.HEAL:
			view["name"] = "Heal %d" % amount
		else:
			view["name"] = "+%d max health" % amount
		choices.append(view)
	var offers: Array[Dictionary] = [{"offer": offer, "here": true, "choices": choices}]
	_events.reward_rolled.emit(seat, offer, choices, true)
	_events.rewards_waiting_changed.emit(seat, offers)
	if not await wait_for(func() -> bool: return _hud.call("get_reward", seat).call("is_open"), 60):
		fail("seat %d's reward menu did not open" % (seat + 1))
		return false
	return true


## Wait until the menus of `seats` rest (unrolled, the rim and the row slid).
func _rest(seats: Array) -> void:
	await wait_for(func() -> bool: return seats.all(func(seat: int) -> bool: return not _hud.call("get_reward", seat).call("is_moving")), 60)
	await settle(2)
