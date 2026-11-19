extends "res://tests/support/suite.gd"
## Tests for the reward items (the owner's ask of 2026-11-19, gameplay/rewards/rewards.gd): a cleared
## room's reward never pops up; each present player's offer lies as an item at its own spot of the
## room (`room_rewards_due`'s spots, by seat), said to the view (`reward_item_changed`); only its own
## player's body in reach is told of it (`reward_near_changed`), so only its owner opens it; a pick
## takes it off the floor (its pickup said, `item_picked_up`); a player who was not there finds the
## offer waiting, lying nowhere (rule 4); a new world takes the items off the floor and the offers
## wait; the items are state: the same through a snapshot, said again after a restore.
const Fixture := preload("res://tests/gameplay/player/wizard_fixture.gd")
const RewardsScript := preload("res://gameplay/rewards/rewards.gd")
const EventsScript := preload("res://core/events/events.gd")

## The spots Flow hands out, by seat.
const SPOTS: PackedVector2Array = [Vector2(-36, 32), Vector2(-12, 32), Vector2(12, 32), Vector2(36, 32)]

var _world: Fixture
var _rewards: RewardsScript
## Every reward_item_changed [player, offer, at, lying], reward_near_changed [player, offer] and
## item_picked_up [actor, kind].
var _items: Array = []
var _near: Array = []
var _picked: Array = []


func before_each() -> void:
	_world = Fixture.new(root)
	_rewards = _make(7)
	_items.clear()
	_near.clear()
	_picked.clear()
	_world.bus.reward_item_changed.connect(func(player: int, offer: int, at: Vector2, lying: bool) -> void: _items.append([player, offer, at, lying]))
	_world.bus.reward_near_changed.connect(func(player: int, offer: int, _at: Vector2) -> void: _near.append([player, offer]))
	_world.bus.item_picked_up.connect(func(actor: int, kind: StringName, _id: StringName, _at: Vector2) -> void: _picked.append([actor, kind]))


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


## Room `room` cleared, each seat's reward item due at its spot of SPOTS.
func _clear(room: int) -> void:
	_world.bus.room_cleared.emit(&"test_room", room)
	_world.bus.room_rewards_due.emit(room, &"clear", PackedStringArray(), SPOTS)
	_rewards.step(Fixture.STEP)


func _offer_of(seat: int) -> Dictionary:
	var waiting: Array[Dictionary] = _rewards.waiting_of(seat)
	return waiting[0] if not waiting.is_empty() else {}


func test_a_present_players_reward_lies_at_its_own_spot_and_an_absent_ones_waits() -> void:
	_world.wizard(0, Vector2(200, 0))
	var away: Actor = _world.wizard(1, Vector2(400, 0))
	away.room = 9
	_clear(3)
	var mine: Dictionary = _offer_of(0)
	check(bool(mine["lying"]), "a present player's offer lies as an item in the room")
	check(_items.has([0, int(mine["offer"]), SPOTS[0], true]), "said to the view at its own seat's spot")
	var theirs: Dictionary = _offer_of(1)
	check(not theirs.is_empty() and not bool(theirs["lying"]), "a player who was not there still gets theirs, waiting (rule 4)")
	check_equal(_items.size(), 1, "and no item lies for them")


func test_only_its_own_players_body_in_reach_is_told_of_it() -> void:
	var one: Actor = _world.wizard(0, Vector2(200, 0))
	var two: Actor = _world.wizard(1, Vector2(300, 0))
	_clear(0)
	var mine: int = int(_offer_of(0)["offer"])
	_near.clear()
	two.position = SPOTS[0]
	_tick()
	check(not _near.has([1, mine]), "another player standing on it is not told of it")
	one.position = SPOTS[0] + Vector2(RewardsScript.REWARD_REACH + 4.0, 0)
	_tick()
	check(not _near.has([0, mine]), "out of reach: not yet")
	one.position = SPOTS[0] + Vector2(4, 0)
	_tick()
	check(_near.has([0, mine]), "its own player in reach is told of it")
	one.position = Vector2(200, 0)
	_tick()
	check_equal(_near.back(), [0, -1], "and told as it walks off")


func test_a_pick_takes_it_off_the_floor_and_its_pickup_is_said() -> void:
	var one: Actor = _world.wizard(0, SPOTS[0])
	_clear(0)
	var mine: int = int(_offer_of(0)["offer"])
	_tick()
	_items.clear()
	_world.bus.reward_pick_requested.emit(0, mine, 0)
	_tick()
	check(_rewards.waiting_of(0).is_empty(), "taken")
	check_equal(_items, [[0, mine, SPOTS[0], false]], "off the floor")
	check(_picked.has([one.id, EventsScript.PICKUP_REWARD]), "the reward's pickup said, for its sound")
	check_equal(_near.back(), [0, -1], "nothing in reach any more")


func test_a_new_world_takes_the_items_off_the_floor_and_the_offers_wait() -> void:
	_world.wizard(0, Vector2(200, 0))
	_clear(2)
	var mine: int = int(_offer_of(0)["offer"])
	_items.clear()
	_world.bus.room_entered.emit(&"next_biome", EventsScript.FIRST_ROOM)
	check_equal(_items, [[0, mine, SPOTS[0], false]], "gone from the floor with its world")
	var offer: Dictionary = _offer_of(0)
	check(not offer.is_empty() and not bool(offer["lying"]), "the offer is never lost: it waits, lying nowhere")


func test_the_items_are_state_through_a_snapshot_and_said_again() -> void:
	var one: Actor = _world.wizard(0, SPOTS[0])
	_world.wizard(1, Vector2(300, 0))
	_tick()
	_clear(0)
	_tick()
	var areas: Dictionary = {"Rewards": _rewards, "Actors": _world.table}
	var snapshot: Snapshot = Snapshot.take(areas)
	check_equal(snapshot.problems, PackedStringArray(), "taken")
	var before: int = SimHash.of(_rewards)
	var mine: int = int(_offer_of(0)["offer"])
	_world.bus.reward_pick_requested.emit(0, mine, 1)
	_tick()
	check(SimHash.of(_rewards) != before, "a pick changes the hashed state")
	var problems: PackedStringArray = snapshot.restore(areas)
	check(problems.is_empty(), "restored: %s" % [problems])
	_items.clear()
	_near.clear()
	_rewards.rebuild_derived()
	check_equal(SimHash.of(_rewards), before, "the same state again")
	check(bool(_offer_of(0)["lying"]), "the offer lies again")
	check(_items.has([0, mine, SPOTS[0], true]), "said again to the view")
	check(_near.has([0, mine]), "and its owner, standing on it, told of it again")
	one.position = Vector2(200, 0)
	_tick()
	check_equal(_near.back(), [0, -1], "it plays on")


func test_a_coin_walked_over_says_its_pickup() -> void:
	var one: Actor = _world.wizard(0, Vector2(200, 0))
	_tick()
	_rewards.lay_coin(Vector2(200, 0))
	_tick()
	check(_picked.has([one.id, ItemKinds.COIN]), "a coin's pickup said, for its sound")
