extends "res://tests/support/suite.gd"
## Tests for the rerolls (the owner, 2026-11-19: "room reroll" and "reward reroll", two currencies in
## each player's currency bag, used with X): every player's wizard starts a run with one of each (the
## run stats `start_room_rerolls` and `start_reward_rerolls`, once a run, changed by a rule change);
## a reward reroll (`reward_reroll_requested`, a command) spends one and rolls only that player's
## offer again, as many choices from the same table, under its own counted purpose (so a seat's
## later offers are as they were), refused with none held; the counters and the offer's table are
## state, through a snapshot.
const Fixture := preload("res://tests/gameplay/player/wizard_fixture.gd")
const RewardsScript := preload("res://gameplay/rewards/rewards.gd")
## Where a test shop's reroll sign stands: out of every wizard's reach.
const FAR: Vector2 = Vector2(0, 4000)
const BAG: StringName = &"currency"

var _world: Fixture
var _rewards: RewardsScript
var _rerolled: Array = []
var _refused: Array = []


func before_each() -> void:
	_world = Fixture.new(root)
	_rewards = _make(7)
	_rerolled.clear()
	_refused.clear()
	_world.bus.reward_rerolled.connect(func(player: int, offer: int, choices: Array[Dictionary]) -> void: _rerolled.append([player, offer, choices.size()]))
	_world.bus.reward_reroll_refused.connect(func(player: int, offer: int) -> void: _refused.append([player, offer]))


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


func _clear(room: int, table: StringName = &"clear") -> void:
	_world.bus.room_cleared.emit(&"test_room", room)
	_world.bus.room_rewards_due.emit(room, table, PackedStringArray(), PackedVector2Array())
	_rewards.step(Fixture.STEP)


func _held(body: Actor, id: StringName) -> int:
	return body.inventory.count_of(BAG, id)


func _choices_of(seat: int) -> Array:
	var out: Array = []
	for offer: Dictionary in _rewards.waiting_of(seat):
		var row: Array = []
		for choice: Dictionary in offer["choices"]:
			row.append([choice["kind"], choice["id"], choice["count"]])
		out.append(row)
	return out


func _reroll(seat: int, offer: int) -> void:
	_world.bus.reward_reroll_requested.emit(seat, offer)
	_tick()


func test_every_player_starts_a_run_with_one_of_each_once() -> void:
	var one: Actor = _world.wizard(0)
	var two: Actor = _world.wizard(1, Vector2(40, 0))
	_tick()
	_tick()
	for body: Actor in [one, two]:
		check_equal(_held(body, RerollBase.ROOM), 1, "one room reroll")
		check_equal(_held(body, RerollBase.REWARD), 1, "one reward reroll")
	check_equal(ItemKinds.kind_in(BAG, RerollBase.ROOM), ItemKinds.REROLL, "a reroll kind's stack in the currency bag")
	check(ItemKinds.can(ItemKinds.REROLL, ItemKinds.DROP), "droppable like other currency")
	check_equal(RunStats.base_of(&"start_room_rerolls"), 1.0, "a run stat, 1 for now")
	check_equal(RunStats.base_of(&"start_reward_rerolls"), 1.0, "a run stat, 1 for now")


func test_a_rule_change_gives_more_or_none() -> void:
	_world.bus.run_stats_ruled.emit([StatChange.make(&"start_reward_rerolls", 2.0), StatChange.make(&"start_room_rerolls", -1.0)] as Array[StatChange])
	var body: Actor = _world.wizard(0)
	_tick()
	check_equal(_held(body, RerollBase.REWARD), 3, "the stat's changes")
	check_equal(_held(body, RerollBase.ROOM), 0, "and none at 0")


func test_a_reward_reroll_spends_one_and_changes_only_that_players_offer() -> void:
	var one: Actor = _world.wizard(0)
	_world.wizard(1, Vector2(40, 0))
	_tick()
	_clear(0)
	var before: Array = _choices_of(0)
	var others: Array = _choices_of(1)
	var offer: int = int(_rewards.waiting_of(0)[0]["offer"])
	_reroll(0, offer)
	check_equal(_rerolled, [[0, offer, 3]], "said, with as many choices as it had")
	check_equal(_held(one, RerollBase.REWARD), 0, "one reward reroll spent")
	check_equal(_choices_of(0)[0].size(), before[0].size(), "the same number of choices")
	check_equal(_choices_of(1), others, "only that player's offer changes")
	check_equal(int(_rewards.waiting_of(0)[0]["offer"]), offer, "the same offer, still waiting")
	check_equal(_rewards._offers[0].table, &"clear", "rolled from the table it came from")
	_reroll(0, offer)
	check_equal(_refused, [[0, offer]], "with none left it is refused")
	check_equal(_rerolled.size(), 1, "and nothing changes")


func test_a_reroll_of_anothers_offer_does_nothing() -> void:
	_world.wizard(0)
	var two: Actor = _world.wizard(1, Vector2(40, 0))
	_tick()
	_clear(0)
	var offer: int = int(_rewards.waiting_of(0)[0]["offer"])
	_reroll(1, offer)
	check(_rerolled.is_empty() and _refused.is_empty(), "not its offer: nothing")
	check_equal(_held(two, RerollBase.REWARD), 1, "nothing spent")


func test_a_reroll_never_shifts_the_seats_later_offers() -> void:
	_world.wizard(0)
	_tick()
	_clear(0)
	_clear(1)
	var plain: Array = _choices_of(0)[1]
	_rewards.free()
	_world.free_all()
	_world = Fixture.new(root)
	_rewards = _make(7)
	_world.wizard(0)
	_tick()
	_clear(0)
	_reroll(0, int(_rewards.waiting_of(0)[0]["offer"]))
	_clear(1)
	check_equal(_choices_of(0)[1], plain, "the next clear's offer is as it was without the reroll")


func test_the_same_seed_rerolls_the_same_and_through_a_snapshot() -> void:
	_world.bus.run_stats_ruled.emit([StatChange.make(&"start_reward_rerolls", 5.0)] as Array[StatChange])
	_world.wizard(0)
	_tick()
	_clear(0)
	var offer: int = int(_rewards.waiting_of(0)[0]["offer"])
	var areas: Dictionary = {"Rewards": _rewards, "Actors": _world.table}
	var snapshot: Snapshot = Snapshot.take(areas)
	var seen: Array = []
	for i in 3:
		_reroll(0, offer)
		seen.append(_choices_of(0))
	var problems: PackedStringArray = snapshot.restore(areas)
	check(problems.is_empty(), "restored: %s" % [problems])
	_rewards.rebuild_derived()
	check_equal(_rewards._offers[0].table, &"clear", "the offer's table is state")
	var again: Array = []
	for i in 3:
		_reroll(0, offer)
		again.append(_choices_of(0))
	check_equal(again, seen, "the rerolls after the restore are the same")
	check_equal(_rewards._rerolls[0], 3, "the rerolls counted are state")


func test_a_shop_sells_both_rerolls_and_its_shelf_rolls_anew_when_rerolled() -> void:
	var table := _world.registry.get_resource(&"rewards", &"shelf") as RewardTable
	var sold: Dictionary = {}
	for entry: RewardEntry in table.entries:
		if entry.kind == ItemKinds.REROLL:
			sold[entry.id] = entry.price
	check_equal(sold, {RerollBase.ROOM: 10, RerollBase.REWARD: 8}, "the shelf's table sells a room reroll and a reward reroll (the owner, 2026-11-19)")
	var seen: bool = false
	var spots := PackedVector2Array([Vector2(300, 0), Vector2(320, 0), Vector2(340, 0)])
	for room in 12:
		_world.bus.special_room_opened.emit(room, RoomKind.FILL_SHOP, &"shelf", Rect2(), spots, FAR)
	for item: Dictionary in _rewards.shelf():
		if (item["choice"] as Dictionary)["kind"] == ItemKinds.REROLL:
			seen = true
	check(seen, "some shelf stocks a reroll")
	# A shop rerolled before it opens rolls its shelf anew (the same seed, the same rooms).
	var plain: Array = []
	var rerolled: Array = []
	for pass_rerolled in [false, true]:
		_rewards.free()
		_rewards = _make(7)
		for room in range(30, 36):
			if pass_rerolled:
				_world.bus.room_rerolled.emit(room, &"shop")
			_world.bus.special_room_opened.emit(room, RoomKind.FILL_SHOP, &"shelf", Rect2(), spots, FAR)
		var ids: Array = []
		for item: Dictionary in _rewards.shelf():
			ids.append([(item["choice"] as Dictionary)["kind"], (item["choice"] as Dictionary)["id"]])
		if pass_rerolled:
			rerolled = ids
		else:
			plain = ids
	check(plain != rerolled, "a rerolled shop's shelf is rolled anew")
	check_equal(_rewards._room_rerolls[30], 1, "a room's rerolls counted, state")
