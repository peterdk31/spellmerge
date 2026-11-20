extends "res://tests/support/suite.gd"
## Tests for a shop's reroll sign (the owner's ask of 2026-11-19, gameplay/rewards/rewards.gd): a shop
## opens with its sign at its spot, a shelf thing numbered with its items (`shelf_changed`, kind
## `SHELF_SIGN`); A at it (`shelf_buy_requested` naming it) from the standing body a seat drives,
## with the price in its own coins, rerolls the shelf: the price comes off, everything on the shelf
## goes and every spot (a bought one too) is stocked anew, with items the shelf did not hold; the
## price rises with each use (3, 5, 8, then the sum of the two before; times the player's
## `price_scale`); too few coins or out of reach changes nothing; one shelf a shop, shared; the same
## seed rerolls the same, and so does a restored snapshot.
const Fixture := preload("res://tests/gameplay/player/wizard_fixture.gd")
const RewardsScript := preload("res://gameplay/rewards/rewards.gd")
const EventsScript := preload("res://core/events/events.gd")
const COINS: StringName = &"currency"

const SPOTS: PackedVector2Array = [Vector2(0, 0), Vector2(48, 0), Vector2(96, 0)]
const SIGN_AT: Vector2 = Vector2(48, 40)

var _world: Fixture
var _rewards: RewardsScript
## Every shelf_changed [item, kind, price, lying] and shelf_refused [player, item].
var _shelf: Array = []
var _refused: Array = []


func before_each() -> void:
	_world = Fixture.new(root)
	_rewards = _make(7)
	_shelf.clear()
	_refused.clear()
	_world.bus.shelf_changed.connect(func(item: int, _at: Vector2, choice: Dictionary, price: int, lying: bool) -> void: _shelf.append([item, choice.get("kind", &""), price, lying]))
	_world.bus.shelf_refused.connect(func(player: int, item: int) -> void: _refused.append([player, item]))


func after_each() -> void:
	if is_instance_valid(_rewards):
		_rewards.free()
	_world.free_all()


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


func _tick() -> void:
	_world.frames.tick(Fixture.STEP)
	_rewards.step(Fixture.STEP)


## Every seat's coin stack given `coins`, and shop 3 opened.
func _open(coins: int) -> void:
	_world.bus.run_stats_ruled.emit([StatChange.make(&"start_coins", float(coins))] as Array[StatChange])
	_tick()
	_world.bus.special_room_opened.emit(3, RoomKind.FILL_SHOP, &"shelf", Rect2(), SPOTS, SIGN_AT)


func _sign() -> int:
	return int(_rewards.signs()[0]["number"])


func _keys() -> Array[String]:
	var out: Array[String] = []
	for item: Dictionary in _rewards.shelf():
		var choice: Dictionary = item["choice"]
		out.append("%s|%s|%s" % [choice["kind"], choice["id"], choice["count"]])
	return out


func _reroll(seat: int) -> void:
	_world.bus.shelf_buy_requested.emit(seat, _sign())
	_tick()


func test_the_price_rises_with_each_use() -> void:
	check_equal([RewardsScript.sign_price(0), RewardsScript.sign_price(1), RewardsScript.sign_price(2), RewardsScript.sign_price(3), RewardsScript.sign_price(4)], [3, 5, 8, 13, 21], "3, 5, 8, then each the sum of the two before")


func test_a_shop_opens_with_its_sign() -> void:
	_world.wizard(0, Vector2(-300, 0))
	_open(10)
	check_equal(_rewards.signs().size(), 1, "one sign a shop")
	check_equal(_rewards.signs()[0]["at"], SIGN_AT, "at its spot")
	check(_shelf.has([_sign(), EventsScript.SHELF_SIGN, 3, true]), "told to the view with its first price")
	_world.bus.special_room_opened.emit(3, RoomKind.FILL_SHOP, &"shelf", Rect2(), SPOTS, SIGN_AT)
	check_equal(_rewards.signs().size(), 1, "once a shop")


func test_a_at_the_sign_rerolls_the_shelf_into_new_items_for_a_rising_price() -> void:
	var one: Actor = _world.wizard(0, Vector2(-300, 0))
	_open(40)
	var first: Array[String] = _keys()
	# Buy one item first: its spot is stocked again by the reroll.
	one.position = SPOTS[0]
	_tick()
	_world.bus.shelf_buy_requested.emit(0, int(_rewards.shelf()[0]["number"]))
	_tick()
	check_equal(_rewards.shelf().size(), 2, "one bought")
	var coins: int = one.inventory.count_of(COINS, CoinBase.ID)
	var near: Array = []
	_world.bus.shelf_near_changed.connect(func(seat: int, item: int, _at: Vector2, view: Dictionary) -> void: near.append([seat, item, view.get("kind", &""), view.get("price", -1)]))
	one.position = SIGN_AT
	_tick()
	check(near.has([0, _sign(), EventsScript.SHELF_SIGN, 3]), "the sign in reach, its price for them")
	var held: Array[String] = _keys()
	_reroll(0)
	check_equal(one.inventory.count_of(COINS, CoinBase.ID), coins - 3, "the first reroll costs 3, from its own coins")
	check_equal(_rewards.shelf().size(), 3, "every spot stocked anew, the bought one too")
	for key: String in _keys():
		check(not held.has(key), "a new item, not one the shelf held (%s)" % key)
	check(near.has([0, _sign(), EventsScript.SHELF_SIGN, 5]), "the price in reach rose")
	_reroll(0)
	check_equal(one.inventory.count_of(COINS, CoinBase.ID), coins - 3 - 5, "then 5")
	_reroll(0)
	check_equal(one.inventory.count_of(COINS, CoinBase.ID), coins - 3 - 5 - 8, "then 8")
	check_equal(int(_rewards.signs()[0]["uses"]), 3, "used three times")
	check(first != _keys(), "the shelf changed")


func test_too_few_coins_or_out_of_reach_changes_nothing() -> void:
	var one: Actor = _world.wizard(0, Vector2(-300, 0))
	_open(2)
	var held: Array[String] = _keys()
	_reroll(0)
	check_equal(_keys(), held, "out of reach: nothing")
	check(_refused.is_empty(), "and nothing said")
	one.position = SIGN_AT
	_tick()
	_reroll(0)
	check_equal(_keys(), held, "2 coins of 3: nothing")
	check_equal(_refused, [[0, _sign()]], "refused")
	check_equal(one.inventory.count_of(COINS, CoinBase.ID), 2, "nothing spent")
	check_equal(int(_rewards.signs()[0]["uses"]), 0, "nor used")


func test_the_price_follows_the_players_scale() -> void:
	_world.wizard(0, Vector2(-300, 0))
	_world.bus.run_stats_ruled.emit([StatChange.make(&"start_coins", 20.0), StatChange.make(&"price_scale", 2.0, StatChange.How.TIMES)] as Array[StatChange])
	_tick()
	_world.bus.special_room_opened.emit(3, RoomKind.FILL_SHOP, &"shelf", Rect2(), SPOTS, SIGN_AT)
	check_equal(_rewards.price_for(0, _sign()), 6, "3 times 2")


func test_the_same_seed_rerolls_the_same_and_so_does_a_restore() -> void:
	var one: Actor = _world.wizard(0, SIGN_AT)
	_open(60)
	_tick()
	var areas: Dictionary = {"Rewards": _rewards, "Actors": _world.table, "wizard": one}
	var snapshot: Snapshot = Snapshot.take(areas, root)
	check_equal(snapshot.problems, PackedStringArray(), "taken")
	var before: int = SimHash.of(_rewards)
	_reroll(0)
	_reroll(0)
	var after: Array[String] = _keys()
	check(SimHash.of(_rewards) != before, "a reroll changes the hashed state")
	var problems: PackedStringArray = snapshot.restore(areas, root)
	check(problems.is_empty(), "restored: %s" % [problems])
	_rewards.rebuild_derived()
	check_equal(SimHash.of(_rewards), before, "the same state again")
	check_equal(int(_rewards.signs()[0]["uses"]), 0, "its uses are state")
	_reroll(0)
	_reroll(0)
	check_equal(_keys(), after, "rerolled again after the restore: the same shelf")
	check_equal(one.inventory.count_of(COINS, CoinBase.ID), 60 - 3 - 5, "and the same price paid")
	# Another area of the same seed, the same moves: the same shelf.
	_rewards.free()
	one.free()
	_world.table.begin_run()
	_rewards = _make(7)
	_world.wizard(0, SIGN_AT)
	_open(60)
	_tick()
	_reroll(0)
	_reroll(0)
	check_equal(_keys(), after, "the same seed rerolls the same")
