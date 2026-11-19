extends "res://tests/support/suite.gd"
## Tests for the Rewards area (connected biomes CB10, gameplay/rewards/rewards.gd): a room's clear
## rolls each player's own offer of `reward_choices` (2) distinct choices from the clear's table,
## `here` for a wizard in the room and waiting for one who was not; a run rule change or a relic
## changes a player's number of choices; every choice wraps an item (the owner, 2026-11-19): a pick
## (a command naming its offer) puts it into the picker's inventory (a card into the card bag,
## potions into the potions bag, undrunk; coins onto the picker's own coin stack), and a pick of
## another's offer or a bad choice does nothing; no room in the bag keeps it unspent; offers wait
## across rooms until picked; the same seed rolls the same; a foe's death lays its coins, a wizard's
## feet take one and every player's coin stack gains one; spending is one's own; a new world clears
## the coins, a run's start everything; a snapshot's restore says it all again.
const Fixture := preload("res://tests/gameplay/player/wizard_fixture.gd")
const RewardsScript := preload("res://gameplay/rewards/rewards.gd")
const IMP: EnemyBase = preload("res://content/enemies/ember_imp/ember_imp.tres")

const EventsScript := preload("res://core/events/events.gd")
const CARDS: StringName = &"cards"
const POTIONS: StringName = &"potions"
const COINS: StringName = &"currency"

var _world: Fixture
var _rewards: RewardsScript
## Every reward_rolled [player, offer, choices, here], reward_taken [player, offer, choice], the
## currency bag's bag_changed [player, coins] and coin_changed [coin, lying].
var _rolled: Array = []
var _taken: Array = []
var _purses: Array = []
var _coins: Array = []


func before_each() -> void:
	_world = Fixture.new(root)
	_rewards = _make(7)
	_rolled.clear()
	_taken.clear()
	_purses.clear()
	_coins.clear()
	_world.bus.reward_rolled.connect(func(player: int, offer: int, choices: Array[Dictionary], here: bool) -> void: _rolled.append([player, offer, choices, here]))
	_world.bus.reward_taken.connect(func(player: int, offer: int, choice: int, _reward: Dictionary) -> void: _taken.append([player, offer, choice]))
	_world.bus.bag_changed.connect(func(player: int, bag: StringName, ids: Array[StringName], counts: PackedInt32Array, _capacity: int) -> void:
		if bag == COINS:
			_purses.append([player, counts[ids.find(CoinBase.ID)] if ids.has(CoinBase.ID) else 0]))
	_world.bus.coin_changed.connect(func(coin: int, _at: Vector2, lying: bool) -> void: _coins.append([coin, lying]))


func after_each() -> void:
	if is_instance_valid(_rewards):
		_rewards.free()
	_world.free_all()


## A Rewards area on the world's services, its chance seeded `seed`, in the tree.
func _make(seed: int) -> RewardsScript:
	var made := RewardsScript.new()
	made.events = _world.bus
	made.actors = _world.table
	made.projectiles = _world.projectiles
	made.spells = _world.spells
	made.registry = _world.registry
	made.sim = Sim.seeded(seed)
	root.add_child(made)
	return made


func _wizard(seat: int, at: Vector2 = Vector2.ZERO) -> Actor:
	var body: Actor = _world.wizard(seat, at)
	return body


## One tick: the seats' frames (their commands apply), then the Rewards step.
func _tick() -> void:
	_world.frames.tick(Fixture.STEP)
	_rewards.step(Fixture.STEP)


func _pick(seat: int, offer: int, choice: int) -> void:
	_world.bus.reward_pick_requested.emit(seat, offer, choice)
	_tick()


## The choices of seat `seat`'s offers waiting, as [kind, id, count] lists.
func _choices(seat: int) -> Array:
	var out: Array = []
	for offer: Dictionary in _rewards.waiting_of(seat):
		var row: Array = []
		for choice: Dictionary in offer["choices"]:
			row.append([choice["kind"], choice["id"], choice["count"]])
		out.append(row)
	return out


## A foe of `IMP`'s data dying at `at`, in the place `room`.
func _foe_dies(at: Vector2, room: int = RoomGrid.NO_PLACE) -> void:
	_kill(_foe(IMP, room), at)


## A foe of `data` in the tree on the world's services (so it carries its coins, `Actor._carry_coins`),
## in the place `room`; an add with `is_add`; its chance the run's seeded `seed`.
func _foe(data: EnemyBase, room: int = RoomGrid.NO_PLACE, is_add: bool = false, seed: int = 7) -> Actor:
	var foe := Actor.new()
	foe.data = data
	foe.room = room
	foe.is_add = is_add
	foe.events = _world.bus
	foe.combat = _world.combat
	foe.projectiles = _world.projectiles
	foe.spells = _world.spells
	foe.actors = _world.table
	foe.sim = Sim.seeded(seed)
	root.add_child(foe)
	foe.ticking = false
	return foe


## `foe` dies at `at` (Combat's `enemy_died`) and goes.
func _kill(foe: Actor, at: Vector2) -> void:
	_world.bus.enemy_died.emit(0, foe, at, -1)
	foe.free()


## A copy of the imp's data carrying `coins` (up to `most`), dropped by `chance`.
func _carrying(coins: int, chance: float = 1.0, most: int = 0) -> EnemyBase:
	var data: EnemyBase = IMP.duplicate()
	data.coins = coins
	data.coins_most = most
	data.coin_drop_chance = chance
	return data


## Room `room` cleared, its kind rewarding it from `table` (Flow's `room_rewards_due`), then a step
## rolls for it.
func _clear(room: int, table: StringName = &"clear") -> void:
	_world.bus.room_cleared.emit(&"test_room", room)
	_world.bus.room_rewards_due.emit(room, table)
	_rewards.step(Fixture.STEP)


func test_a_clear_rolls_each_players_own_offer_of_two() -> void:
	_wizard(0)
	_wizard(1, Vector2(40, 0))
	_clear(0)
	check_equal(_rolled.size(), 2, "one offer a player")
	check_equal([_rolled[0][0], _rolled[1][0]], [0, 1], "each its own, in seat order")
	check(_rolled[0][1] != _rolled[1][1], "numbered apart")
	for row: Array in _rolled:
		var choices: Array = row[2]
		check_equal(choices.size(), 2, "pick 1 of 2 (decision 17)")
		check(choices[0]["kind"] != choices[1]["kind"] or choices[0]["id"] != choices[1]["id"] or choices[0]["count"] != choices[1]["count"], "two different choices")
		check(row[3], "a wizard in the room is there for it")
		for choice: Dictionary in choices:
			check(ItemKinds.has(choice["kind"]), "an item kind: every reward is an item")
			var look: Dictionary = ItemLooks.of(choice["kind"], choice["id"], _world.registry, _world.spells)
			check(String(choice["name"]).begins_with(String(look["name"])) and String(look["name"]) != "", "the item's own name for the menu")
			check_equal(choice["icon"], look["icon"], "the item's own icon")
			check_equal(choice["description"], look["description"], "and the item's own description")
	check_equal(_rewards.waiting_of(0).size(), 1, "it waits until picked")
	check(_rewards.waiting_of(2).is_empty(), "a seat with no wizard rolls nothing")


func test_only_a_clear_its_kind_rewards_rolls_and_from_its_own_table() -> void:
	_wizard(0)
	_world.bus.room_cleared.emit(&"start_room", 0)
	_rewards.step(Fixture.STEP)
	check(_rolled.is_empty(), "a clear whose kind names no table (the start room, a shop) rewards nobody")
	# Connected biomes CB11 (the owner, 2026-11-19): however its foes left it (one killed elsewhere,
	# none dying in it at all), a fight's clear rolls.
	_foe_dies(Vector2(500, 500), 2)
	_world.bus.room_rewards_due.emit(1, &"clear")
	check(_rolled.is_empty(), "not before the area's step")
	_rewards.step(Fixture.STEP)
	check_equal(_rolled.size(), 1, "a fight's clear rolls whoever its foes died by and wherever")
	# Each kind rolls from its own table: the treasure's never offers what only the clear's has.
	var treasure := registry_table(&"treasure")
	_world.bus.room_rewards_due.emit(4, &"treasure")
	_rewards.step(Fixture.STEP)
	check_equal(_rolled.size(), 2, "a treasure room's clear rolls too")
	for choice: Dictionary in _rolled[1][2]:
		var listed: bool = false
		for entry: RewardEntry in treasure.entries:
			listed = listed or (entry.kind == choice["kind"] and entry.count == choice["count"])
		check(listed, "each choice is a line of the treasure's own table: %s" % [choice])


## The reward table `id` of the registry.
func registry_table(id: StringName) -> RewardTable:
	return _world.registry.get_resource(&"rewards", id) as RewardTable


func test_a_player_who_was_not_there_finds_it_waiting() -> void:
	var away := _wizard(0)
	away.room = 3
	var there := _wizard(1)
	there.room = 1
	_clear(1)
	check_equal([_rolled[0][0], _rolled[0][3]], [0, false], "the player elsewhere still gets an offer, not there (rule 4)")
	check_equal([_rolled[1][0], _rolled[1][3]], [1, true], "the one in the room is there")
	check_equal(_rewards.waiting_of(0)[0]["here"], false, "its waiting offer says so")
	_world.bus.room_entered.emit(&"next", 2)
	check_equal(_rewards.waiting_of(0).size(), 1, "an unpicked offer stays as the party goes on")


func test_a_pick_gives_the_choice_and_the_offer_goes() -> void:
	var body := _wizard(0)
	_clear(0)
	var offer: int = _rolled[0][1]
	check_equal(_rewards.waiting_of(0).size(), 1, "the rolled offer waits")
	_pick(0, offer, 0)
	check_equal(_taken, [[0, offer, 0]], "a rolled offer is taken, as picked")
	check(_rewards.waiting_of(0).is_empty(), "and goes")
	_offer(0, 70, ItemKinds.CARD, 2, &"fire")
	var before: int = body.inventory.count_of(CARDS, &"fire")
	_pick(0, 70, 0)
	check_equal(body.inventory.count_of(CARDS, &"fire"), before + 2, "a card's copies go into the bag")
	_pick(0, 70, 0)
	check_equal(_taken.size(), 2, "an offer is picked once")


func test_a_pick_of_anothers_offer_or_no_choice_does_nothing() -> void:
	_wizard(0)
	_wizard(1, Vector2(40, 0))
	_clear(0)
	var mine: int = _rolled[0][1]
	_pick(1, mine, 0)
	_pick(0, mine, 2)
	_pick(0, mine, -1)
	_pick(0, 99, 0)
	check(_taken.is_empty(), "nothing taken")
	check_equal(_rewards.waiting_of(0).size(), 1, "the offer still waits")


func test_coins_go_onto_the_pickers_own_stack_only() -> void:
	var body := _wizard(0)
	_wizard(1, Vector2(40, 0))
	_offer(0, 50, ItemKinds.COIN, 5, CoinBase.ID)
	_pick(0, 50, 0)
	check_equal([_rewards.coins_of(0), _rewards.coins_of(1)], [5, 0], "spending and rewards are one's own")
	check_equal(_kinds_in(body).count(ItemKinds.COIN), 1, "coins are one stack in the currency bag")
	_offer(0, 52, ItemKinds.COIN, 3, CoinBase.ID)
	_pick(0, 52, 0)
	check_equal([_kinds_in(body).count(ItemKinds.COIN), body.inventory.count_of(COINS, CoinBase.ID)], [1, 8], "more coins join the stack")
	check(_purses.has([0, 8]), "the stack is said as any bag (the HUD's purse)")


## The kinds of the stacks in `body`'s currency bag (its rerolls beside its coins).
func _kinds_in(body: Actor) -> Array[StringName]:
	var out: Array[StringName] = []
	for stack: ItemStack in body.inventory.stacks_in(COINS):
		out.append(stack.kind)
	return out


## Seat `seat`'s own offer numbered `number` of the one choice `kind` `count`, waiting.
func _offer(seat: int, number: int, kind: StringName, count: int, id: StringName = &"") -> void:
	var offer := RewardOffer.new()
	offer.number = number
	offer.seat = seat
	offer.add(kind, id, count)
	_rewards._offers.append(offer)


func test_potions_go_into_the_bag_and_do_nothing_until_drunk() -> void:
	var body := _wizard(0)
	_world.hurt(body, 50)
	var heals: Array = []
	_world.bus.heal_dealt.connect(func(by: int, _target: Node, amount: float, _at: Vector2) -> void: heals.append([by, amount]))
	_offer(0, 60, ItemKinds.POTION, 1, &"healing")
	_pick(0, 60, 0)
	_offer(0, 61, ItemKinds.POTION, 2, &"max_health")
	_pick(0, 61, 0)
	check_equal(_taken.size(), 2, "both taken")
	check_equal([body.inventory.count_of(POTIONS, &"healing"), body.inventory.count_of(POTIONS, &"max_health")], [1, 2], "into the potions bag")
	check_equal([body.health.health, body.health.max_health], [50.0, 100.0], "nothing happens until a potion is drunk")
	check(heals.is_empty(), "no heal")


func test_a_potion_is_taken_while_the_wizard_is_down() -> void:
	var body := _wizard(0)
	_world.hurt(body, 100000)
	check(body.is_down(), "down")
	_offer(0, 62, ItemKinds.POTION, 1, &"healing")
	_pick(0, 62, 0)
	check_equal(_taken.size(), 1, "an item is kept for later, down or not")
	check_equal(body.inventory.count_of(POTIONS, &"healing"), 1, "in the bag")


func test_no_room_in_the_bag_keeps_it_unspent() -> void:
	var body := _wizard(0)
	body.inventory.set_capacity(CARDS, body.inventory.copies(CARDS))
	var refused: Array = []
	_world.bus.reward_refused.connect(func(player: int, offer: int) -> void: refused.append([player, offer]))
	_offer(0, 51, ItemKinds.CARD, 1, &"fire")
	_pick(0, 51, 0)
	check(_taken.is_empty(), "nothing taken")
	check_equal(refused, [[0, 51]], "the seat hears it was refused")
	check_equal(_rewards.waiting_of(0).size(), 1, "it stays, to pick later")


func test_the_choices_are_the_players_run_stat() -> void:
	_wizard(0)
	_wizard(1, Vector2(40, 0))
	_world.bus.run_stats_ruled.emit([StatChange.make(&"reward_choices", 1.0)] as Array[StatChange])
	_clear(0)
	check_equal([(_rolled[0][2] as Array).size(), (_rolled[1][2] as Array).size()], [3, 3], "the run's change, for everyone")
	check_equal(_rewards.stat_of(0, &"reward_choices"), 3.0, "read by name")


func test_a_relic_changes_its_holders_stats_only() -> void:
	var relic := RelicBase.new()
	relic.id = &"test_lens"
	relic.stat_changes = [StatChange.make(&"reward_choices", 2.0)] as Array[StatChange]
	_world.registry.add(RewardsScript.RELICS, relic)
	var holder := _wizard(0)
	_wizard(1, Vector2(40, 0))
	var stack := ItemStack.new()
	stack.kind = ItemKinds.RELIC
	stack.id = &"test_lens"
	check(holder.inventory.add(stack), "the relic is in the holder's bag")
	_clear(0)
	check_equal([(_rolled[0][2] as Array).size(), (_rolled[1][2] as Array).size()], [4, 2], "4 choices for the holder, 2 for the other")
	_world.registry.remove(RewardsScript.RELICS, &"test_lens")


func test_the_same_seed_rolls_the_same() -> void:
	_wizard(0)
	_wizard(1, Vector2(40, 0))
	for clear in 3:
		_clear(clear)
	var first: Array = [_choices(0), _choices(1)]
	_rewards.free()
	_rewards = _make(7)
	for clear in 3:
		_clear(clear)
	check_equal([_choices(0), _choices(1)], first, "the same rolls")
	check(_choices(0)[0] != _choices(0)[1] or _choices(0)[1] != _choices(0)[2], "rolls differ from clear to clear")


func test_a_foes_coins_are_shared_income() -> void:
	_wizard(0)
	_wizard(1, Vector2(200, 0))
	_tick()
	_foe_dies(Vector2(100, 0))
	check_equal(_rewards.coins_lying().size(), IMP.coins, "the imp's coins lie where it fell")
	check_equal(_coins.back(), [0, true], "said laid")
	_tick()
	check_equal(_rewards.coins_lying().size(), IMP.coins, "nobody near: it stays")
	var taker: Actor = _world.wizards[1]
	taker.position = _rewards.coins_lying()[0] + Vector2(3, 0)
	_tick()
	check(_rewards.coins_lying().is_empty(), "taken")
	check_equal([_rewards.coins_of(0), _rewards.coins_of(1)], [1, 1], "every player's coin stack gained it (shared income, decision 18)")
	check(_purses.has([0, 1]) and _purses.has([1, 1]), "each stack said by its bag")
	check_equal(_coins.back(), [0, false], "said gone")
	check(_rewards.spend(1, 1), "a player spends their own")
	check_equal([_rewards.coins_of(0), _rewards.coins_of(1)], [1, 0], "only theirs")
	check(not _rewards.spend(1, 1), "not more than they hold")


func test_a_bosss_coins_go_to_every_player() -> void:
	_wizard(0)
	_wizard(1, Vector2(40, 0))
	var data: EnemyBase = _carrying(10)
	data.boss = true
	_kill(_foe(data), Vector2(300, 0))
	check(_rewards.coins_lying().is_empty(), "none on the floor (the portal home opens as its room clears)")
	check_equal([_rewards.coins_of(0), _rewards.coins_of(1)], [10, 10], "every player gains them (decision 25)")


## The owner, 2026-11-19: a boss always pays, whatever drop chance its data gives, and rolls nothing.
func test_a_boss_always_pays_whatever_its_drop_chance() -> void:
	_wizard(0)
	_wizard(1, Vector2(40, 0))
	var data: EnemyBase = _carrying(10)
	data.boss = true
	data.coin_drop_chance = 0.0
	_kill(_foe(data), Vector2(300, 0))
	check_equal([_rewards.coins_of(0), _rewards.coins_of(1)], [10, 10], "a chance of 0: every player still gains them")
	check_equal(_rewards._drops, 0, "no drop roll is made for a boss")


func test_an_add_drops_no_coin() -> void:
	var add: Actor = _foe(IMP, RoomGrid.NO_PLACE, true)
	check_equal(add.inventory.count_of(COINS, CoinBase.ID), 0, "an add carries none")
	_kill(add, Vector2(50, 0))
	check(_rewards.coins_lying().is_empty(), "a boss's add drops nothing (its waves never end)")
	var late: Actor = _foe(IMP)
	late.is_add = true
	_kill(late, Vector2(50, 0))
	check(_rewards.coins_lying().is_empty(), "nor one marked an add after it came")


func test_a_coin_never_lands_in_a_wall() -> void:
	_world.projectiles.grid().add_wall(Rect2(104.0, -16.0, 32.0, 32.0))
	_kill(_foe(_carrying(3)), Vector2(100, 0))
	var lying: PackedVector2Array = _rewards.coins_lying()
	check_equal(lying.size(), 3, "three coins")
	check_equal(lying[1], Vector2(100, 0), "the one that would land in the wall lands on the foe's spot")
	check_equal(lying[2], Vector2(94, 0), "the one on the open side lands there")


func test_a_downed_wizard_takes_no_coin() -> void:
	var body := _wizard(0)
	_tick()
	_rewards.lay_coin(Vector2.ZERO)
	_world.hurt(body, 100000)
	check(body.is_down(), "down")
	_tick()
	check_equal(_rewards.coins_lying().size(), 1, "it lies there still")


func test_starting_coins_come_once_a_run() -> void:
	_world.bus.run_stats_ruled.emit([StatChange.make(&"start_coins", 12.0)] as Array[StatChange])
	_wizard(0)
	_tick()
	_tick()
	check_equal(_rewards.coins_of(0), 12, "the run's starting coins, once")


func test_a_new_world_clears_the_coins_and_a_run_start_everything() -> void:
	_wizard(0)
	_tick()
	_rewards.lay_coin(Vector2(80, 0))
	_world.bus.room_entered.emit(&"later", 3)
	check_equal(_rewards.coins_lying().size(), 1, "a biome's later room keeps the floor")
	_world.bus.special_room_opened.emit(5, RoomKind.FILL_SHOP, &"shelf", Rect2(), PackedVector2Array([Vector2(300, 0)]))
	_world.bus.room_entered.emit(&"next_world", EventsScript.FIRST_ROOM)
	check(_rewards.coins_lying().is_empty(), "a new world has none")
	check(_rewards.shelf().is_empty(), "nor a shelf")
	_clear(0)
	_rewards.lay_coin(Vector2(80, 0))
	_rewards.begin_run()
	check(_rewards.waiting_of(0).is_empty() and _rewards.coins_lying().is_empty(), "a run's start ends the offers and the coins")
	check_equal(_rewards.coins_of(0), 0, "and the wizard holds none")


func test_a_restore_says_it_all_again() -> void:
	_wizard(0)
	_tick()
	var kept: int = _rewards.lay_coin(Vector2(80, 0))
	_clear(0)
	_coins.clear()
	var waiting: Array = []
	_world.bus.rewards_waiting_changed.connect(func(player: int, offers: Array[Dictionary]) -> void: waiting.append([player, offers.size()]))
	_rewards._said_coins[kept + 1] = true
	_rewards.rebuild_derived()
	check(_coins.has([kept + 1, false]), "a coin this machine drew that lies there no more is said gone")
	check(_coins.has([kept, true]), "every coin lying is said")
	check(waiting.has([0, 1]), "every seat's waiting offers are said")


# --- Connected biomes CB11: shops and fountains --------------------------------------------------

## A shop opened in room `room` with its shelf at `spots` (Flow's `special_room_opened`).
func _open_shop(room: int, spots: PackedVector2Array) -> void:
	_world.bus.special_room_opened.emit(room, RoomKind.FILL_SHOP, &"shelf", Rect2(), spots)


## Every seat's coin stack given `coins` (a run's starting coins).
func _fund(coins: int) -> void:
	_world.bus.run_stats_ruled.emit([StatChange.make(&"start_coins", float(coins))] as Array[StatChange])
	_tick()


func test_a_shops_shelf_is_one_of_each_and_the_first_buyer_takes_it() -> void:
	var shelf: Array = []
	_world.bus.shelf_changed.connect(func(item: int, _at: Vector2, choice: Dictionary, price: int, lying: bool) -> void: shelf.append([item, choice.get("kind", &""), price, lying]))
	var one := _wizard(0, Vector2(-200, 0))
	var two := _wizard(1, Vector2(-200, 60))
	_fund(30)
	_open_shop(3, PackedVector2Array([Vector2(0, 0), Vector2(48, 0), Vector2(96, 0)]))
	var items: Array[Dictionary] = _rewards.shelf()
	check_equal(items.size(), 3, "an item a spot")
	var seen: Dictionary = {}
	for item: Dictionary in items:
		var choice: Dictionary = item["choice"]
		seen["%s|%s|%s" % [choice["kind"], choice["id"], choice["count"]]] = true
		check(int(item["price"]) > 0, "each has a price")
	check_equal(seen.size(), 3, "one of each: no item twice")
	check_equal(shelf.size(), 3, "each told to the view")
	_open_shop(3, PackedVector2Array([Vector2(0, 0)]))
	check_equal(_rewards.shelf().size(), 3, "a shop is stocked once: it keeps its shelf")
	# Both step onto the first item at once: walking on buys nothing, and each is told it is in reach.
	var near: Array = []
	_world.bus.shelf_near_changed.connect(func(seat: int, item: int, _at: Vector2, view: Dictionary) -> void: near.append([seat, item, view.get("price", -1)]))
	var price: int = int(items[0]["price"])
	one.position = items[0]["at"]
	two.position = items[0]["at"]
	_tick()
	check_equal(_rewards.shelf().size(), 3, "standing on an item buys nothing")
	check(near.has([0, items[0]["number"], price]) and near.has([1, items[0]["number"], price]), "each seat is told the item in its reach, with its price")
	# Both press A in the same tick: the first seat buys it, and only it pays; the second finds it gone.
	var refused: Array = []
	_world.bus.shelf_refused.connect(func(seat: int, item: int) -> void: refused.append([seat, item]))
	_world.bus.shelf_buy_requested.emit(0, items[0]["number"])
	_world.bus.shelf_buy_requested.emit(1, items[0]["number"])
	_tick()
	check_equal(_rewards.shelf().size(), 2, "bought: gone from the shelf for everyone")
	check(refused.is_empty(), "the second ask finds it gone, and says nothing")
	check(near.back() == [1, -1, -1] and near[near.size() - 2] == [0, -1, -1], "nobody has it in reach any more")
	check_equal([_rewards.coins_of(0), _rewards.coins_of(1)], [30 - price, 30], "the buyer pays from their own coin stack")
	check(shelf.back()[3] == false and shelf.back()[0] == items[0]["number"], "the view is told it went")


func test_a_wizard_who_cannot_pay_buys_nothing_and_prices_follow_the_players_scale() -> void:
	var one := _wizard(0, Vector2(-200, 0))
	_fund(1)
	_open_shop(4, PackedVector2Array([Vector2(0, 0)]))
	var item: Dictionary = _rewards.shelf()[0]
	var refused: Array = []
	_world.bus.shelf_refused.connect(func(seat: int, number: int) -> void: refused.append([seat, number]))
	_world.bus.shelf_buy_requested.emit(0, item["number"])
	_tick()
	check(refused.is_empty() and _rewards.shelf().size() == 1, "out of reach: nothing, and nothing said")
	one.position = item["at"]
	_tick()
	_world.bus.shelf_buy_requested.emit(0, item["number"])
	_tick()
	check_equal(_rewards.shelf().size(), 1, "too few coins: it stays")
	check_equal(_rewards.coins_of(0), 1, "nothing spent")
	check_equal(refused, [[0, item["number"]]], "the buyer is told it was refused")
	_world.bus.run_stats_ruled.emit([StatChange.make(&"price_scale", 0.5, StatChange.How.TIMES)] as Array[StatChange])
	check_equal(_rewards.price_for(0, item["number"]), maxi(roundi(float(item["price"]) * 0.5), 1), "a player's price is the price times their price_scale")


func test_the_item_in_reach_follows_the_price_and_goes_with_the_world() -> void:
	var one := _wizard(0, Vector2(-200, 0))
	_fund(30)
	_open_shop(4, PackedVector2Array([Vector2(0, 0)]))
	var item: Dictionary = _rewards.shelf()[0]
	var near: Array = []
	_world.bus.shelf_near_changed.connect(func(seat: int, number: int, _at: Vector2, view: Dictionary) -> void:
		if seat == 0:
			near.append([number, view.get("price", -1)]))
	one.position = item["at"]
	_tick()
	check_equal(near.back(), [item["number"], item["price"]], "in reach, with its price")
	_world.bus.run_stats_ruled.emit([StatChange.make(&"price_scale", 2.0, StatChange.How.TIMES)] as Array[StatChange])
	check_equal(near.back(), [item["number"], _rewards.price_for(0, item["number"])], "told again at the player's new price")
	_world.bus.room_entered.emit(&"next", EventsScript.FIRST_ROOM)
	check_equal(near.back(), [-1, -1], "a new world: nothing in reach at once")


func test_a_shelf_sells_potions_into_the_bag() -> void:
	var one := _wizard(0, Vector2(-200, 0))
	_fund(60)
	var potion: Dictionary = {}
	for room in range(10, 40):
		_open_shop(room, PackedVector2Array([Vector2(0, 0), Vector2(48, 0), Vector2(96, 0), Vector2(144, 0)]))
		for item: Dictionary in _rewards.shelf():
			if (item["choice"] as Dictionary)["kind"] == ItemKinds.POTION and potion.is_empty():
				potion = item
		if not potion.is_empty():
			break
	check(not potion.is_empty(), "the shop's shelf (content/rewards/shelf.tres) sells potions")
	if potion.is_empty():
		return
	var id: StringName = (potion["choice"] as Dictionary)["id"]
	one.position = potion["at"]
	_tick()
	_world.bus.shelf_buy_requested.emit(0, potion["number"])
	_tick()
	check_equal(one.inventory.count_of(POTIONS, id), 1, "bought by a whole wizard too: a potion is kept, not drunk")
	check_equal(_rewards.coins_of(0), 60 - int(potion["price"]), "paid for (price_scale 1), the coins gone from the stack")
	check(_rewards.price_for(0, potion["number"]) < 0, "and gone from the shelf")


func test_a_full_bag_buys_nothing() -> void:
	var one := _wizard(0, Vector2(-200, 0))
	_fund(60)
	_open_shop(4, PackedVector2Array([Vector2(0, 0)]))
	var item: Dictionary = _rewards.shelf()[0]
	var bag: StringName = ItemKinds.bag_of((item["choice"] as Dictionary)["kind"])
	one.inventory.set_capacity(bag, one.inventory.copies(bag))
	var refused: Array = []
	_world.bus.shelf_refused.connect(func(seat: int, number: int) -> void: refused.append([seat, number]))
	one.position = item["at"]
	_tick()
	_world.bus.shelf_buy_requested.emit(0, item["number"])
	_tick()
	check_equal(refused, [[0, item["number"]]], "no room: refused")
	check_equal([_rewards.coins_of(0), _rewards.shelf().size()], [60, 1], "nothing paid, nothing gone")


func test_a_coin_stack_is_state_snapshotted_with_the_wizard() -> void:
	var body := _wizard(0)
	_fund(7)
	check_equal(_rewards.coins_of(0), 7, "funded")
	var saved: ItemStack = body.inventory.stacks_in(COINS)[0]
	check_equal([saved.kind, saved.id, saved.count], [ItemKinds.COIN, CoinBase.ID, 7], "a stack in the inventory, which is state (hashed and snapshotted with the body)")


func test_each_players_run_stats_are_told_to_the_view() -> void:
	var told: Dictionary = {}
	_world.bus.run_stats_told.connect(func(seat: int, stats: Dictionary) -> void: told[seat] = stats)
	_wizard(0)
	_tick()
	check(told.has(0) and float((told[0] as Dictionary)[&"secret_sense"]) == 0.0, "as a seat's wizard comes: its stats, the base")
	_world.bus.run_stats_ruled.emit([StatChange.make(&"secret_sense", 200.0)] as Array[StatChange])
	for seat in 4:
		check(told.has(seat) and float((told[seat] as Dictionary)[&"secret_sense"]) == 200.0, "seat %d told the run's change" % seat)
	check_equal((told[0] as Dictionary).size(), RunStats.names().size(), "every stat by name")
	told.clear()
	_rewards.rebuild_derived()
	check_equal(told.size(), 4, "a restore tells every seat's again")


func test_a_fountain_is_a_shared_pool_every_hurt_wizard_draws_on() -> void:
	var one := _wizard(0, Vector2(-200, 0))
	var two := _wizard(1, Vector2(-200, 60))
	var told: Array = []
	_world.bus.fountain_changed.connect(func(room: int, _area: Rect2, left: float, most: float) -> void: told.append([room, left, most]))
	_world.bus.special_room_opened.emit(6, RoomKind.FILL_FOUNTAIN, &"", Rect2(0, 0, 64, 48), PackedVector2Array())
	var most: float = _rewards.pool_left(6)
	check_equal(most, RewardsScript.POOL_HEALTH, "its pool holds the healing of one fountain (fountain_pool 1)")
	_world.hurt(one, 90)
	_world.hurt(two, 90)
	_tick()
	check_equal(_rewards.pool_left(6), most, "nobody in it: untouched")
	one.position = Vector2(20, 20)
	two.position = Vector2(40, 20)
	for i in 30:
		_tick()
	check(one.health.health > 10.0 and two.health.health > 10.0, "both draw on it: %s and %s" % [one.health.health, two.health.health])
	check(is_equal_approx(_rewards.pool_left(6), most - (one.health.health - 10.0) - (two.health.health - 10.0)), "what they drew is gone from the shared pool")
	for i in 300:
		_tick()
	check_equal(_rewards.pool_left(6), 0.0, "drawn dry")
	check(is_equal_approx(one.health.health + two.health.health, 20.0 + most), "no more than the pool healed in all")
	check(not told.is_empty() and told.back()[1] == 0.0, "the view is told it ran dry")
	# A wizard at full health draws nothing from another fountain.
	one.position = Vector2(-200, 0)
	two.position = Vector2(-200, 60)
	_world.bus.special_room_opened.emit(7, RoomKind.FILL_FOUNTAIN, &"", Rect2(0, 100, 64, 48), PackedVector2Array())
	var whole := _wizard(2, Vector2(20, 120))
	for i in 10:
		_tick()
	check_equal(_rewards.pool_left(7), most, "a wizard at full health draws nothing")
	check(whole.health.health == whole.health.max_health, "and is whole")


func test_a_restore_says_the_shelves_and_pools_again() -> void:
	_wizard(0, Vector2(-200, 0))
	_open_shop(3, PackedVector2Array([Vector2(0, 0), Vector2(48, 0)]))
	_world.bus.special_room_opened.emit(6, RoomKind.FILL_FOUNTAIN, &"", Rect2(0, 0, 64, 48), PackedVector2Array())
	var items: Array = []
	var pools: Array = []
	_world.bus.shelf_changed.connect(func(item: int, _at: Vector2, _choice: Dictionary, _price: int, lying: bool) -> void: items.append([item, lying]))
	_world.bus.fountain_changed.connect(func(room: int, _area: Rect2, _left: float, _most: float) -> void: pools.append(room))
	_rewards._said_items[99] = true
	_rewards.rebuild_derived()
	check(items.has([99, false]), "an item this machine drew that lies there no more is said gone")
	check(items.has([0, true]) and items.has([1, true]), "every item lying is said")
	check_equal(pools, [-1, 6], "every pool forgotten, then each said")


# --- Enemies carry coins and drop them by chance (the owner, 2026-11-19) --------------------------

func test_a_foe_carries_its_coins_in_its_own_coins_bag() -> void:
	var foe: Actor = _foe(_carrying(3))
	check_equal(foe.inventory.count_of(COINS, CoinBase.ID), 3, "its data's coins, in its own bag")
	check(foe.inventory.at_rest(), "as its data made it: still at rest")
	var none: Actor = _foe(_carrying(0))
	check_equal(none.inventory.stacks_in(COINS).size(), 0, "none for a foe whose data gives none")
	check_equal(IMP.coin_range(), Vector2i(1, 1), "an ordinary foe: 1 coin, as CB10's 1 a foe")
	check_equal(IMP.coin_drop_chance, 1.0, "always dropped, so today's economy stays")
	foe.free()
	none.free()


func test_a_range_of_coins_is_rolled_once_by_the_runs_chance() -> void:
	var seen: Dictionary = {}
	var again: Array = []
	for seed in 40:
		var foe: Actor = _foe(_carrying(1, 1.0, 4), RoomGrid.NO_PLACE, false, seed)
		var count: int = foe.inventory.count_of(COINS, CoinBase.ID)
		check(count >= 1 and count <= 4, "from coins to coins_most (%d)" % count)
		seen[count] = true
		check(not foe.inventory.at_rest(), "a rolled count is walked by the hash")
		var key: int = _world.table.key_of(foe.id)
		again.append([seed, key, count])
		foe.free()
	check(seen.size() >= 3, "the counts differ between seeds (%s)" % [seen.keys()])
	for row: Array in again:
		var expected: int = 1 + Sim.seeded(int(row[0])).chance_int(Actor.COINS_PURPOSE, int(row[1]), 0, 4)
		check_equal(int(row[2]), expected, "the same seed and key roll the same")


func test_the_drop_chance_over_many_seeds() -> void:
	var dropped: int = 0
	var seeds: int = 120
	for seed in seeds:
		var rewards: RewardsScript = _make(seed)
		var foe: Actor = _foe(_carrying(2, 0.5))
		_world.bus.enemy_died.emit(0, foe, Vector2(40, 0), -1)
		foe.free()
		var lying: int = rewards.coins_lying().size()
		check(lying == 0 or lying == 2, "all its coins or none (%d)" % lying)
		if lying > 0:
			dropped += 1
		rewards.free()
	_rewards.begin_run()
	check(dropped > seeds * 3 / 10 and dropped < seeds * 7 / 10, "about half drop at 0.5 (%d of %d)" % [dropped, seeds])
	for i in 20:
		_kill(_foe(_carrying(1, 0.0)), Vector2(40, 0))
	check(_rewards.coins_lying().is_empty(), "never at 0")
	for i in 20:
		_kill(_foe(_carrying(1, 1.0)), Vector2(40, 0))
	check_equal(_rewards.coins_lying().size(), 20, "always at 1")


## The drops of `count` foes at chance 0.5, by the Rewards area `rewards`: 1 a drop, 0 none.
func _drops_of(rewards: RewardsScript, count: int) -> Array:
	var out: Array = []
	for i in count:
		var before: int = rewards.coins_lying().size()
		_kill(_foe(_carrying(1, 0.5)), Vector2(40, 0))
		out.append(rewards.coins_lying().size() - before)
	return out


func test_the_drops_are_the_same_for_the_same_seed_and_through_a_snapshot() -> void:
	_rewards.free()
	_rewards = _make(11)
	var first: Array = _drops_of(_rewards, 30)
	_rewards.free()
	_rewards = _make(11)
	_world.table.begin_run()
	check_equal(_drops_of(_rewards, 30), first, "the same seed drops the same")
	var areas: Dictionary = {"Rewards": _rewards, "Actors": _world.table}
	var snapshot: Snapshot = Snapshot.take(areas)
	var on: Array = _drops_of(_rewards, 30)
	check(on.has(0) and on.has(1), "some drop and some do not (%s)" % [on])
	var problems: PackedStringArray = snapshot.restore(areas)
	check(problems.is_empty(), "restored: %s" % [problems])
	_rewards.rebuild_derived()
	check_equal(_rewards._drops, 30, "the drops counted are state")
	check_equal(_drops_of(_rewards, 30), on, "and the drops after the restore are the same")


func test_a_possessed_foe_drops_what_it_still_carries() -> void:
	var wizard := _wizard(0)
	_tick()
	var foe: Actor = _foe(_carrying(5))
	check(Possession.begin(wizard, foe, 30.0) != null, "seat 0 possesses the foe")
	check(foe.inventory.take(COINS, CoinBase.ID, 2), "it spends two (a shop's buy is the driven body's)")
	_kill(foe, Vector2(60, 0))
	check_equal(_rewards.coins_lying().size(), 3, "its coins drop the same way: what it still carries")
	check_equal(_rewards.coins_of(0), 0, "none straight into a wizard's stack")


# --- A rejoin gets no second start (the owner, 2026-11-19) --------------------------------------

## A seat that leaves and joins again in a run brings its coins back in its inventory (Flow's
## `LeftPlayers`, tests/gameplay/flow/test_rejoin.gd); the Rewards area gives it no second
## `start_coins`.
func test_a_player_who_leaves_and_joins_again_gets_no_second_start() -> void:
	_world.bus.run_stats_ruled.emit([StatChange.make(&"start_coins", 4.0)] as Array[StatChange])
	var body := _wizard(0)
	_tick()
	check_equal(_rewards.coins_of(0), 4, "its starting coins")
	_world.wizards.erase(body)
	body.free()
	_world.bus.player_left.emit(0)
	_tick()
	check_equal(_rewards.coins_of(0), 0, "away: no wizard, no coins")
	var back := _wizard(0)
	back.inventory.add(ItemStack.of(ItemKinds.COIN, CoinBase.ID, 3))
	_tick()
	_tick()
	check_equal(_rewards.coins_of(0), 3, "back with what its inventory holds, no second start_coins")


# --- Everything is droppable (the owner, 2026-11-19) -------------------------------------------

## No coin is made by a drop: a coin a player dropped, taken by a foe it possesses, goes with the
## foe as it dies, unshared; only the coins it came carrying and held all along are shared. What it
## dropped of those itself and took back is not shared again.
func test_a_possessed_foe_never_shares_a_coin_it_took_later() -> void:
	var wizard := _wizard(0)
	_wizard(1, Vector2(200, 0))
	_tick()
	var foe: Actor = _foe(_carrying(3))
	check(Possession.begin(wizard, foe, 30.0) != null, "seat 0 possesses the foe")
	check_equal(foe.inventory.carried_kept(), 3, "it came with three")
	check(foe.inventory.take(COINS, CoinBase.ID, 2), "it drops two of its own (lying as items, one's own)")
	check(foe.inventory.add(ItemStack.of(ItemKinds.COIN, CoinBase.ID, 4)), "and takes four a player dropped")
	check_equal(foe.inventory.count_of(COINS, CoinBase.ID), 5, "five held")
	check_equal(foe.inventory.carried_kept(), 1, "one of them held all along")
	_kill(foe, Vector2(60, 0))
	check_equal(_rewards.coins_lying().size(), 1, "only that one is laid for everyone")


func test_a_boss_shares_only_the_coins_it_came_with() -> void:
	_wizard(0)
	_wizard(1, Vector2(200, 0))
	_tick()
	var data: EnemyBase = _carrying(2)
	data.boss = true
	var boss: Actor = _foe(data)
	check(boss.inventory.add(ItemStack.of(ItemKinds.COIN, CoinBase.ID, 5)), "it takes five dropped coins")
	_kill(boss, Vector2(60, 0))
	check_equal([_rewards.coins_of(0), _rewards.coins_of(1)], [2, 2], "each player gains its own two, not seven")


## The count held all along is the body's state: it comes back through a snapshot and is hashed.
func test_the_coins_held_all_along_are_state() -> void:
	var foe: Actor = _foe(_carrying(4))
	var areas: Dictionary = {"Actors": _world.table, "foe": foe}
	var snapshot: Snapshot = Snapshot.take(areas, root)
	check_equal(snapshot.problems, PackedStringArray(), "taken")
	var before: int = SimHash.of(foe.inventory)
	check(foe.inventory.take(COINS, CoinBase.ID, 3), "three dropped")
	check(foe.inventory.add(ItemStack.of(ItemKinds.COIN, CoinBase.ID, 3)), "three taken back")
	check_equal(foe.inventory.count_of(COINS, CoinBase.ID), 4, "four held again")
	check_equal(foe.inventory.carried_kept(), 1, "but one held all along")
	# Hashed: a body that dropped and took back one coin holds as many but more of them all along.
	var twin: Actor = _foe(_carrying(4))
	check(twin.inventory.take(COINS, CoinBase.ID, 1) and twin.inventory.add(ItemStack.of(ItemKinds.COIN, CoinBase.ID, 1)), "one dropped and taken back")
	check_equal([twin.inventory.count_of(COINS, CoinBase.ID), twin.inventory.carried_kept()], [4, 3], "four held, three all along")
	var same: Actor = _foe(_carrying(4))
	check(same.inventory.take(COINS, CoinBase.ID, 3) and same.inventory.add(ItemStack.of(ItemKinds.COIN, CoinBase.ID, 3)), "as the first did")
	check_equal(SimHash.of(same.inventory), SimHash.of(foe.inventory), "the same edits hash the same")
	check(SimHash.of(foe.inventory) != SimHash.of(twin.inventory), "the count held all along is hashed")
	var problems: PackedStringArray = snapshot.restore(areas, root)
	check(problems.is_empty(), "restored: %s" % [problems])
	check_equal(foe.inventory.carried_kept(), 4, "the four held all along again")
	check_equal(SimHash.of(foe.inventory), before, "the same state")
