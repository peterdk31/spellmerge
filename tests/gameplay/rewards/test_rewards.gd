extends "res://tests/support/suite.gd"
## Tests for the Rewards area (connected biomes CB10, gameplay/rewards/rewards.gd): a room's clear
## rolls each player's own offer of `reward_choices` (2) distinct choices from the clear's table,
## `here` for a wizard in the room and waiting for one who was not; a run rule change or a relic
## changes a player's number of choices; a pick (a command naming its offer) gives a card to the bag
## or coins to the picker's wallet, and a pick of another's offer or a bad choice does nothing; no
## room in the bag keeps it unspent; offers wait across rooms until picked; the same seed rolls the
## same; a foe's death lays its coins, a wizard's feet take one and every wallet gains it; spending
## is one's own; a new world clears the coins, a run's start everything; a snapshot's restore says
## it all again.
const Fixture := preload("res://tests/gameplay/player/wizard_fixture.gd")
const RewardsScript := preload("res://gameplay/rewards/rewards.gd")
const IMP: EnemyBase = preload("res://content/enemies/ember_imp/ember_imp.tres")

const EventsScript := preload("res://core/events/events.gd")
const CARDS: StringName = &"cards"

var _world: Fixture
var _rewards: RewardsScript
## Every reward_rolled [player, offer, choices, here], reward_taken [player, offer, choice],
## wallet_changed [player, coins] and coin_changed [coin, lying].
var _rolled: Array = []
var _taken: Array = []
var _wallets: Array = []
var _coins: Array = []


func before_each() -> void:
	_world = Fixture.new(root)
	_rewards = _make(7)
	_rolled.clear()
	_taken.clear()
	_wallets.clear()
	_coins.clear()
	_world.bus.reward_rolled.connect(func(player: int, offer: int, choices: Array[Dictionary], here: bool) -> void: _rolled.append([player, offer, choices, here]))
	_world.bus.reward_taken.connect(func(player: int, offer: int, choice: int, _reward: Dictionary) -> void: _taken.append([player, offer, choice]))
	_world.bus.wallet_changed.connect(func(player: int, coins: int) -> void: _wallets.append([player, coins]))
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
	var foe := Actor.new()
	foe.data = IMP
	foe.room = room
	_world.bus.enemy_died.emit(0, foe, at, -1)
	foe.free()


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
			check(RewardEntry.KINDS.has(choice["kind"]), "one of the reward kinds")
			check(String(choice["name"]) != "", "each has a name for the menu")
			if choice["kind"] != RewardEntry.CARD:
				check_equal(choice["description"], RewardEntry.describe(choice["kind"], choice["count"]), "and says what it does, its kind's line")
			else:
				check(choice.has("description"), "a card says what it does with its builder line")
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
	_offer(0, 70, RewardEntry.CARD, 2, &"fire")
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


func test_coins_go_to_the_pickers_wallet_only() -> void:
	_wizard(0)
	_wizard(1, Vector2(40, 0))
	_offer(0, 50, RewardEntry.COINS, 5)
	_pick(0, 50, 0)
	check_equal([_rewards.wallet_of(0), _rewards.wallet_of(1)], [5, 0], "spending and rewards are one's own")


## Seat `seat`'s own offer numbered `number` of the one choice `kind` `count`, waiting.
func _offer(seat: int, number: int, kind: StringName, count: int, id: StringName = &"") -> void:
	var offer := RewardOffer.new()
	offer.number = number
	offer.seat = seat
	offer.add(kind, id, count)
	_rewards._offers.append(offer)


func test_healing_and_more_health_go_through_combat() -> void:
	var body := _wizard(0)
	_world.hurt(body, 50)
	check_equal(body.health.health, 50.0, "hurt")
	var heals: Array = []
	_world.bus.heal_dealt.connect(func(by: int, _target: Node, amount: float, _at: Vector2) -> void: heals.append([by, amount]))
	_offer(0, 60, RewardEntry.HEAL, 30)
	_pick(0, 60, 0)
	check_equal(body.health.health, 80.0, "healed 30")
	check_equal(heals, [[EventsScript.NO_PLAYER, 30.0]], "told as a heal by nobody")
	_offer(0, 61, RewardEntry.MAX_HEALTH, 10)
	_pick(0, 61, 0)
	check_equal([body.health.max_health, body.health.health], [110.0, 90.0], "10 more most health, and as much health")
	check_equal(_taken.size(), 2, "both taken")


func test_a_heal_waits_while_the_wizard_is_down() -> void:
	var body := _wizard(0)
	_world.hurt(body, 100000)
	check(body.is_down(), "down")
	_offer(0, 62, RewardEntry.HEAL, 30)
	_pick(0, 62, 0)
	check(_taken.is_empty(), "not taken while down")
	check_equal(_rewards.waiting_of(0).size(), 1, "it waits")


func test_no_room_in_the_bag_keeps_it_unspent() -> void:
	var body := _wizard(0)
	body.inventory.set_capacity(CARDS, body.inventory.copies(CARDS))
	var refused: Array = []
	_world.bus.reward_refused.connect(func(player: int, offer: int) -> void: refused.append([player, offer]))
	_offer(0, 51, RewardEntry.CARD, 1, &"fire")
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
	check_equal([_rewards.wallet_of(0), _rewards.wallet_of(1)], [1, 1], "every wallet gained it")
	check_equal(_coins.back(), [0, false], "said gone")
	check(_rewards.spend(1, 1), "a player spends their own")
	check_equal([_rewards.wallet_of(0), _rewards.wallet_of(1)], [1, 0], "only theirs")
	check(not _rewards.spend(1, 1), "not more than they hold")


func test_a_bosss_coins_go_to_every_wallet() -> void:
	_wizard(0)
	_wizard(1, Vector2(40, 0))
	var boss := Actor.new()
	var data: EnemyBase = IMP.duplicate()
	data.boss = true
	data.coins = 10
	boss.data = data
	_world.bus.enemy_died.emit(0, boss, Vector2(300, 0), -1)
	boss.free()
	check(_rewards.coins_lying().is_empty(), "none on the floor (the portal home opens as its room clears)")
	check_equal([_rewards.wallet_of(0), _rewards.wallet_of(1)], [10, 10], "every wallet gains them (decision 25)")


func test_an_add_drops_no_coin() -> void:
	var add := Actor.new()
	add.data = IMP
	add.is_add = true
	_world.bus.enemy_died.emit(0, add, Vector2(50, 0), -1)
	add.free()
	check(_rewards.coins_lying().is_empty(), "a boss's add drops nothing (its waves never end)")


func test_a_coin_never_lands_in_a_wall() -> void:
	_world.projectiles.grid().add_wall(Rect2(104.0, -16.0, 32.0, 32.0))
	var foe := Actor.new()
	var data: EnemyBase = IMP.duplicate()
	data.coins = 3
	foe.data = data
	_world.bus.enemy_died.emit(0, foe, Vector2(100, 0), -1)
	foe.free()
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
	check_equal(_rewards.wallet_of(0), 12, "the run's starting coins, once")


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
	check_equal(_rewards.wallet_of(0), 0, "and empties the wallets")


func test_a_restore_says_it_all_again() -> void:
	_wizard(0)
	_tick()
	var kept: int = _rewards.lay_coin(Vector2(80, 0))
	_clear(0)
	_coins.clear()
	_wallets.clear()
	var waiting: Array = []
	_world.bus.rewards_waiting_changed.connect(func(player: int, offers: Array[Dictionary]) -> void: waiting.append([player, offers.size()]))
	_rewards._said_coins[kept + 1] = true
	_rewards.rebuild_derived()
	check(_coins.has([kept + 1, false]), "a coin this machine drew that lies there no more is said gone")
	check(_coins.has([kept, true]), "every coin lying is said")
	check(_wallets.has([0, 0]), "every wallet is said")
	check(waiting.has([0, 1]), "every seat's waiting offers are said")


# --- Connected biomes CB11: shops and fountains --------------------------------------------------

## A shop opened in room `room` with its shelf at `spots` (Flow's `special_room_opened`).
func _open_shop(room: int, spots: PackedVector2Array) -> void:
	_world.bus.special_room_opened.emit(room, RoomKind.FILL_SHOP, &"shelf", Rect2(), spots)


## Seat `seat`'s wallet given `coins` (a run's starting coins).
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
	# Both step onto the first item at once: the first seat buys it, and only it pays.
	var price: int = int(items[0]["price"])
	one.position = items[0]["at"]
	two.position = items[0]["at"]
	_tick()
	check_equal(_rewards.shelf().size(), 2, "bought: gone from the shelf for everyone")
	check_equal([_rewards.wallet_of(0), _rewards.wallet_of(1)], [30 - price, 30], "the buyer pays from their own wallet")
	check(shelf.back()[3] == false and shelf.back()[0] == items[0]["number"], "the view is told it went")


func test_a_wizard_who_cannot_pay_buys_nothing_and_prices_follow_the_players_scale() -> void:
	var one := _wizard(0, Vector2(-200, 0))
	_fund(1)
	_open_shop(4, PackedVector2Array([Vector2(0, 0)]))
	var item: Dictionary = _rewards.shelf()[0]
	one.position = item["at"]
	_tick()
	check_equal(_rewards.shelf().size(), 1, "too few coins: it stays")
	check_equal(_rewards.wallet_of(0), 1, "nothing spent")
	_world.bus.run_stats_ruled.emit([StatChange.make(&"price_scale", 0.5, StatChange.How.TIMES)] as Array[StatChange])
	check_equal(_rewards.price_for(0, item["number"]), maxi(roundi(float(item["price"]) * 0.5), 1), "a player's price is the price times their price_scale")


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
