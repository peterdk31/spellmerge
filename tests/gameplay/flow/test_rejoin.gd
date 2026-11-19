extends "res://tests/support/suite.gd"
## A player who leaves and joins again mid-run keeps their whole inventory (the owner, 2026-11-19):
## cards, staffs and hands, potions, coins and keys come back with the new wizard exactly as the old
## one left with them (Flow's `LeftPlayers`), once, and no second `start_coins`; each staff's mana as
## it left (the owner, 2026-11-19), on a hand and in the bag. What was kept is state:
## hashed and saved by a snapshot. On the real autoloads.
const FlowScript := preload("res://gameplay/flow/flow.gd")
const TickScript := preload("res://core/sim/tick.gd")
const DT: float = 1.0 / 60.0
const SEAT: int = 1

var flow: FlowScript
var tick: TickScript
var input: Node
var rewards: Node


func before_each() -> void:
	flow = root.get_node("Flow") as FlowScript
	tick = root.get_node("Tick") as TickScript
	input = root.get_node("PlayerInput")
	rewards = root.get_node("Rewards")
	input.add_virtual_device(0)
	flow.world_parent = own(Node.new()) as Node
	root.add_child(flow.world_parent)
	flow.mode = FlowScript.MODE_RUN


func after_each() -> void:
	flow.stop_run()
	flow.world_parent = null
	for seat in 4:
		input.leave(seat)


## A run with seat 0 and seat SEAT, whose wizard then holds a little of everything: coins, a potion,
## a card more, a card moved onto a staff and a staff off its hand into the staff bag.
func _start_with_a_full_inventory() -> Actor:
	check(flow.start_run(0), "the run starts")
	flow._on_player_joined(SEAT)
	tick.run(DT)
	var wizard := flow.get_wizard(SEAT) as Actor
	check(wizard != null, "seat %d has a wizard" % SEAT)
	var inventory: Inventory = wizard.inventory
	check(inventory.add(ItemStack.of(ItemKinds.COIN, CoinBase.ID, 7)), "coins")
	check(inventory.add(ItemStack.of(ItemKinds.KEY, KeyBase.ID, 2)), "two keys")
	check(inventory.add(ItemStack.of(ItemKinds.POTION, &"healing", 2)), "two potions")
	check(inventory.add(ItemStack.of(ItemKinds.CARD, &"bolt", 3)), "three bolts more")
	check_equal(inventory.set_card(0, 1, &"bolt"), Inventory.Refusal.NONE, "a bolt onto the first staff")
	check_equal(inventory.set_hand(1, Inventory.NO_HAND), Inventory.Refusal.NONE, "the second staff off its hand")
	# Some mana spent: the first staff's pool on its hand, the second's kept in the bag.
	wizard.caster.set_mana(0, wizard.caster.max_mana_of(0) * 0.25)
	inventory.set_staff_mana(1, 3.0)
	return wizard


func test_a_rejoin_gets_back_exactly_what_it_left_with_once() -> void:
	var wizard: Actor = _start_with_a_full_inventory()
	var coins: int = rewards.coins_of(SEAT)
	check(coins >= 7, "its coins counted (%d)" % coins)
	var left_with: PlayerLoadout = PlayerController.loadout_of(wizard)
	var left_mana: Dictionary = wizard.inventory.staff_mana()
	check_equal(left_mana.size(), 2, "two staffs' mana: %s" % [left_mana])
	flow._on_player_left(SEAT)
	check(flow.get_wizard(SEAT) == null, "it left")
	check(flow.left_players.has(SEAT), "what it held is kept")
	check(not flow.left_players.has(0), "nothing for a seat still here")
	tick.run(DT)
	flow._on_player_joined(SEAT)
	var back := flow.get_wizard(SEAT) as Actor
	check(back != null and back != wizard, "a new wizard came")
	check(PlayerController.loadout_of(back).equals(left_with), "it holds exactly what it left with")
	check(not flow.left_players.has(SEAT), "given once: nothing is kept for it now")
	check_equal(back.inventory.hand_of(1), Inventory.NO_HAND, "the staff it took off is still in the bag")
	check_equal(back.inventory.cards_of(0)[1], &"bolt", "the card it put on is still on its staff")
	check_equal(back.inventory.count_of(&"currency", KeyBase.ID), 2, "its own keys back")
	check_equal(back.inventory.staff_mana(), left_mana, "every staff's mana as it left, not full")
	check(back.caster.mana_of(0) < back.caster.max_mana_of(0), "the pool on its hand as low as it was")
	tick.run(DT)
	tick.run(DT)
	check_equal(rewards.coins_of(SEAT), coins, "its coins as they were: no second start_coins")
	flow._on_player_joined(SEAT)
	check(flow.get_wizard(SEAT) == back, "a second join while it is here changes nothing")


func test_a_seat_that_never_left_joins_fresh_and_a_run_forgets_what_was_kept() -> void:
	_start_with_a_full_inventory()
	flow._on_player_left(SEAT)
	check(flow.left_players.has(SEAT), "kept")
	flow.stop_run()
	check(not flow.left_players.has(SEAT), "a run's end forgets it")
	check(flow.start_run(0), "a new run")
	flow._on_player_joined(SEAT)
	var fresh := flow.get_wizard(SEAT) as Actor
	check(fresh != null and fresh.inventory.count_of(ItemKinds.bag_of(ItemKinds.POTION), &"healing") == 0, "a fresh wizard: nothing of the last run")


func test_what_was_kept_is_hashed_and_saved_by_a_snapshot() -> void:
	var wizard: Actor = _start_with_a_full_inventory()
	var left_with: PlayerLoadout = PlayerController.loadout_of(wizard)
	var left_mana: Dictionary = wizard.inventory.staff_mana()
	var hash_here: int = SimHash.areas({"Flow": flow})["Flow"]
	flow._on_player_left(SEAT)
	tick.run(DT)
	check(SimHash.areas({"Flow": flow})["Flow"] != hash_here, "what was kept is in Flow's hash")
	var away := Snapshot.take(tick.state_areas(), root)
	var hash_away: int = SimHash.whole(SimHash.areas(tick.state_areas()))
	flow._on_player_joined(SEAT)
	check(not flow.left_players.has(SEAT), "given back")
	check(away.restore(tick.state_areas(), root).is_empty(), "restored to while it was away")
	check(flow.get_wizard(SEAT) == null, "away again")
	check(flow.left_players.has(SEAT), "and what it held kept again")
	check_equal(SimHash.whole(SimHash.areas(tick.state_areas())), hash_away, "the same hash as when it was taken")
	flow._on_player_joined(SEAT)
	var back := flow.get_wizard(SEAT) as Actor
	check(back != null and PlayerController.loadout_of(back).equals(left_with), "after the restore it comes back with the same")
	check_equal(back.inventory.staff_mana(), left_mana, "and the same mana")
