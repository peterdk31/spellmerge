extends "res://tests/support/suite.gd"
## Special rooms (connected biomes CB11, docs/milestones/connected-biomes.md, decisions 1 and 16 to
## 24; gameplay/flow/lock_doors.gd, gameplay/flow/special_places.gd, gameplay/rewards/rewards.gd),
## on the real autoloads, in CB3's split test map (tests/support/biome_maps.gd: the nave the start
## room 0, the antechamber west, room 1, and the ossuary court east, room 2), its rooms' kinds set
## here: each kind's fill as the party enters (a reward room's rewards, a shop's shelf, a fountain's
## pool), a fight's rewards however its foes left it, the treasure rooms' keys (any key any door) dropped in an open room,
## each taken into its taker's own bag (a possessed foe's too) and spent by it, its door opening for all, a secret rock opening to its own element only, a challenge room's
## elites, and an elite's numbers.
const FlowScript := preload("res://gameplay/flow/flow.gd")
const TickScript := preload("res://core/sim/tick.gd")
const BiomeMaps := preload("res://tests/support/biome_maps.gd")
const DifficultyScript := preload("res://gameplay/difficulty/difficulty.gd")
const RewardsScript := preload("res://gameplay/rewards/rewards.gd")
const DT: float = 1.0 / 60.0
const IMP: StringName = &"ember_imp"
const SPITTER: StringName = &"spitter"
const WEST: int = 1
const EAST: int = 2

var flow: FlowScript
var events: Node
var tick: TickScript
var input: Node
var frames: Node
var registry: Node
var projectiles: Node
var rewards: Node
var due: Array = []
## Each `room_rewards_due`'s type and reward items' spots, by the same index.
var due_types: Array[PackedStringArray] = []
var due_spots: Array[PackedVector2Array] = []
## The type the next `_start` gives its east room (any: none).
var east_type: RewardType = RewardType.new()
var keys: Array = []
var key_doors: Array = []
var rocks: Array = []
var needed: Array = []
var _sources: Array[Walk] = []


## A seat's frames: it walks `move`, nothing else.
class Walk:
	extends FrameSource
	var move: Vector2 = Vector2.ZERO

	func fill_frame(frame: InputFrame, _delta: float) -> void:
		frame.set_move(move)


func before_each() -> void:
	flow = root.get_node("Flow") as FlowScript
	events = root.get_node("Events")
	tick = root.get_node("Tick") as TickScript
	input = root.get_node("PlayerInput")
	frames = root.get_node("Frames")
	registry = root.get_node("Registry")
	projectiles = root.get_node("Projectiles")
	rewards = root.get_node("Rewards")
	due.clear()
	due_types.clear()
	due_spots.clear()
	east_type = RewardType.new()
	keys.clear()
	key_doors.clear()
	rocks.clear()
	_sources.clear()
	events.connect("room_rewards_due", _on_due)
	events.connect("key_shown", _on_key)
	events.connect("key_door_shown", _on_key_door)
	events.connect("secret_rock_shown", _on_rock)
	needed.clear()
	events.connect("key_needed_shown", _on_needed)
	flow.world_parent = own(Node.new()) as Node
	root.add_child(flow.world_parent)


func after_each() -> void:
	events.disconnect("room_rewards_due", _on_due)
	events.disconnect("key_shown", _on_key)
	events.disconnect("key_door_shown", _on_key_door)
	events.disconnect("secret_rock_shown", _on_rock)
	events.disconnect("key_needed_shown", _on_needed)
	flow.stop_run()
	flow.world_parent = null
	flow.mode = FlowScript.MODE_RUN
	for seat in 4:
		frames.call("set_source", seat, null)
		input.leave(seat)
	frames.call("begin_step", DT)
	flow.stop_run()
	flow.mode = FlowScript.MODE_RUN
	tick.begin_run()


func _on_due(room: int, table: StringName, type: PackedStringArray, spots: PackedVector2Array) -> void:
	due.append([room, table])
	due_types.append(type)
	due_spots.append(spots)


func _on_key(key: int, at: Vector2, lying: bool) -> void:
	keys.append([key, at, lying])


func _on_needed(player: int, at: Vector2, is_needed: bool) -> void:
	needed.append([player, at, is_needed])


func _on_key_door(door: int, area: Rect2, open: bool) -> void:
	key_doors.append([door, area, open])


func _on_rock(rock: int, area: Rect2, element: StringName, broken: bool) -> void:
	rocks.append([rock, area, element, broken])


## The split map with the antechamber of kind `west_kind` and the court of `east_kind`, `players`
## seats, the antechamber's and the court's fights `west` and `east` (the court's elites `elites`).
func _start(players: int, west_kind: StringName, east_kind: StringName, west: Array[StringName] = [], east: Array[StringName] = [], elites: Array[StringName] = []) -> BiomeMap:
	var map: BiomeMap = BiomeMaps.split(registry)
	map.room_kinds[WEST] = west_kind
	map.room_kinds[EAST] = east_kind
	if not east_type.is_any():
		map.type_room(EAST, east_type)
	for seat in players:
		input.add_virtual_device(seat)
		var walk := Walk.new()
		_sources.append(walk)
		frames.call("set_source", seat, walk)
	var fights: Array[RoomFight] = [RoomFight.new(), RoomFight.of(west), RoomFight.of(east, 0, 0, 0.0, 0.0, elites)]
	check(flow.start_biome(0, map, fights), "the biome starts")
	return map


func _ticks(count: int) -> void:
	for _i in count:
		tick.run(DT)


func _wizard(seat: int) -> Actor:
	return flow.get_wizard(seat) as Actor


## The keys in seat `seat`'s wizard's own currency bag.
func _keys_of(seat: int) -> int:
	return LockDoors.keys_of(_wizard(seat))


func _grid() -> RoomGrid:
	return projectiles.call(&"grid") as RoomGrid


## A point of room `room` `inside` pixels in from its socket facing `facing`.
func _by_socket(map: BiomeMap, room: int, facing: int, inside: float) -> Vector2:
	return BiomeMaps.socket_point(registry, map, room, facing) - RoomSocket.way(facing) * inside


## A point on the bridge out of the nave's socket facing `facing`, `out` pixels out of it.
func _on_bridge(map: BiomeMap, facing: int, out: float = 48.0) -> Vector2:
	return BiomeMaps.socket_point(registry, map, 0, facing) + RoomSocket.way(facing) * out


## Seat `seat`'s wizard stands at `at` (world pixels), found where it is.
func _put(seat: int, at: Vector2) -> void:
	_wizard(seat).global_position = at
	_ticks(2)


## Every enemy of the fight in `room` down and gone.
func _beat(room: int) -> void:
	for enemy: Node in flow.get(&"_enemies").duplicate():
		var body := enemy as Actor
		if body != null and body.room == room:
			events.emit_signal("enemy_died", 0, body, body.position, -1)
			body.get_parent().remove_child(body)
			body.free()


func test_a_reward_room_rewards_each_wizard_as_the_party_steps_in() -> void:
	var map: BiomeMap = _start(2, &"fight", &"reward")
	_ticks(1)
	check(due.is_empty(), "the start room rewards nobody")
	_put(0, _by_socket(map, EAST, RoomSocket.Facing.WEST, 24.0))
	check(flow.life.has(EAST, RoomLife.CLEARED), "a reward room is cleared as it is entered")
	check_equal(due, [[EAST, &"reward"]], "its rewards are due, from its kind's table")
	check(RewardType.from_row(due_types[0]).is_any(), "a map not typed: of any type")
	# Each seat's reward item lies at its own spot round the room's middle (the owner's ask of
	# 2026-11-19), on clear ground, apart from the others.
	var spots: PackedVector2Array = due_spots[0]
	check_equal(spots.size(), 4, "a spot a seat")
	var middle: Vector2 = flow.biome.room_rect(EAST).get_center()
	for seat in spots.size():
		check(spots[seat].distance_to(middle) < 96.0, "round the room's middle")
		check(not projectiles.call(&"grid").circle_blocked(spots[seat], 4.0, true), "on clear ground")
		for other in range(seat + 1, spots.size()):
			check(spots[seat].distance_to(spots[other]) >= 12.0, "apart from the others")
	_ticks(1)
	var mine: Array = rewards.call(&"waiting_of", 0)
	check_equal(mine.size(), 1, "the wizard there has its offer")
	check(bool((mine[0] as Dictionary)["lying"]), "lying as its item in the room, never popping up")
	var theirs: Array = rewards.call(&"waiting_of", 1)
	check_equal(theirs.size(), 1, "the one elsewhere finds its own waiting (rule 4)")
	check(not bool((theirs[0] as Dictionary)["lying"]), "lying nowhere")


func test_a_fight_rewards_its_clear_however_its_foes_left_it() -> void:
	var map: BiomeMap = _start(1, &"fight", &"fight", [IMP], [])
	_ticks(1)
	_put(0, _by_socket(map, WEST, RoomSocket.Facing.EAST, 24.0))
	check(flow.life.has(WEST, RoomLife.SEALED), "the antechamber's fight starts")
	# Its foe goes without dying in the room (as a possessed foe carried out and killed elsewhere): its
	# body leaves the tree and no death is heard.
	flow.stand_all_now()
	for enemy: Node in flow.get(&"_enemies").duplicate():
		var body := enemy as Actor
		if body != null and body.room == WEST:
			body.get_parent().remove_child(body)
			body.free()
	_ticks(2)
	check(flow.life.has(WEST, RoomLife.CLEARED), "cleared")
	check_equal(due, [[WEST, &"clear"]], "the owner's answer of 2026-11-19: its rewards are due all the same")


func test_a_shop_is_stocked_once_as_it_is_entered_and_a_fountain_filled() -> void:
	var map: BiomeMap = _start(1, &"shop", &"fountain")
	_ticks(1)
	check((rewards.call(&"shelf") as Array).is_empty() and float(rewards.call(&"pool_left", EAST)) < 0.0, "nothing before anyone comes")
	_put(0, _by_socket(map, WEST, RoomSocket.Facing.EAST, 24.0))
	var shelf: Array = rewards.call(&"shelf")
	check_equal(shelf.size(), SpecialPlaces.SHELF_SPOTS.size(), "the shop's shelf, an item a spot (no zones: round its middle)")
	var middle: Vector2 = flow.biome.room_rect(WEST).get_center()
	check(((shelf[1] as Dictionary)["at"] as Vector2).distance_to(middle) < 2.0, "the middle spot at the room's middle")
	var signs: Array = rewards.call(&"signs")
	check_equal(signs.size(), 1, "and its reroll sign (the owner's ask of 2026-11-19)")
	check(((signs[0] as Dictionary)["at"] as Vector2).distance_to(middle + SpecialPlaces.SIGN_SPOT) < 16.0, "under the shelf")
	check(due.is_empty(), "a shop's clear rewards nobody")
	_put(0, _by_socket(map, EAST, RoomSocket.Facing.WEST, 24.0))
	check_equal(float(rewards.call(&"pool_left", EAST)), RewardsScript.POOL_HEALTH, "the fountain's pool filled as it is entered")
	_put(0, _by_socket(map, WEST, RoomSocket.Facing.EAST, 24.0))
	check_equal((rewards.call(&"shelf") as Array).size(), shelf.size(), "entered again: the same shelf")


## The owner, 2026-11-19: "each player picks up keys individually and uses them individually." The
## key goes into the bag of the wizard that reaches it, and only a body holding one opens a door with
## it; the door then opens for everyone (decision 21).
func test_a_key_is_its_takers_own_and_its_door_opens_for_all() -> void:
	# The court the boss's (never a key's room: its clear sends the party home), so the start room is
	# the one room the key may drop in.
	var map: BiomeMap = _start(2, &"treasure", &"boss", [], [IMP])
	_ticks(1)
	check_equal(flow.locks.doors(), 1, "the treasure room has a door: where the west bridge meets it")
	var mouth: Rect2 = flow.locks.mouth_of(0)
	check(_grid().is_shut_mouth(mouth.get_center()), "its mouth is shut")
	check(not key_doors.is_empty() and key_doors.back()[0] == 0 and not key_doors.back()[2], "the view is told the key door, shut")
	# The key drops in a room picked among those reached without passing a locked door: here the
	# start room alone, cleared as the biome starts (a room with no fight: on its floor at once).
	check(not keys.is_empty() and keys.back()[2], "its key lies on the floor")
	var key_at: Vector2 = keys.back()[1]
	check(flow.biome.room_rect(0).has_point(key_at), "in the start room, on the way to it")
	# A wizard at the door without a key: it stays shut, and its seat is told a key is needed.
	_put(0, _on_bridge(map, RoomSocket.Facing.WEST, 48.0))
	_ticks(30)
	check(not flow.locks.is_open(WEST), "no key: shut")
	check_equal(needed, [[0, mouth.get_center(), true]], "seat 0 told once: a key is needed, over the door")
	# The other takes the key: it is that wizard's own, so the first, still at the door, opens nothing.
	var picked: Array = []
	var on_picked := func(_actor: int, kind: StringName, _id: StringName, _at: Vector2) -> void: picked.append(kind)
	events.connect("item_picked_up", on_picked)
	_put(1, key_at)
	events.disconnect("item_picked_up", on_picked)
	check(not keys.back()[2], "the key is taken off the floor")
	check(picked.has(ItemKinds.KEY), "its pickup said, for its sound")
	check_equal(flow.locks.key_states[0], LockDoors.KEY_TAKEN, "taken")
	check_equal([_keys_of(0), _keys_of(1)], [0, 1], "into the taker's own currency bag, nobody else's")
	_ticks(10)
	check(not flow.locks.is_open(WEST), "the key is not the party's: the first wizard still opens nothing")
	# The taker walks into the door: its key is spent, and the door opens for all.
	_put(1, _on_bridge(map, RoomSocket.Facing.WEST, 40.0))
	check(flow.locks.is_open(WEST), "the door opens")
	check_equal(_keys_of(1), 0, "its one key spent")
	check(not _grid().is_shut_mouth(mouth.get_center()), "its mouth with it")
	check(key_doors.back()[2], "the view is told it opened")
	check_equal(needed.back(), [0, Vector2.ZERO, false], "seat 0 told no key is needed any more")
	_put(0, _by_socket(map, WEST, RoomSocket.Facing.EAST, 24.0))
	check_equal(due.back(), [WEST, &"treasure"], "the treasure's rewards as the keyless wizard enters: it opened for all")


## A seat possessing a foe drives that body: a key it reaches goes into the foe's own bag, and the
## foe's key opens a door (the owner, 2026-11-19: "the driven body's bag").
func test_a_possessed_foe_takes_and_spends_a_key_of_its_own() -> void:
	var map: BiomeMap = _start(1, &"treasure", &"fight", [], [IMP])
	_ticks(1)
	_put(0, _by_socket(map, EAST, RoomSocket.Facing.WEST, 24.0))
	flow.stand_all_now()
	_ticks(2)
	var foe: Actor = null
	for enemy: Node in flow.get(&"_enemies"):
		if enemy is Actor and (enemy as Actor).inventory != null:
			foe = enemy as Actor
	check(foe != null, "a foe in the court")
	for _wait in 300:
		if Possession.can_start(foe):
			break
		_ticks(1)
	check(Possession.begin(_wizard(0), foe, 60.0) != null, "seat 0 possesses it")
	var at: Vector2 = foe.position
	flow.locks.key_drops = PackedInt32Array([EAST])
	flow.locks.key_states = PackedByteArray([LockDoors.KEY_LYING])
	flow.locks.key_at = PackedVector2Array([at])
	_ticks(2)
	check_equal(LockDoors.keys_of(foe), 1, "the driven foe took it into its own bag")
	check_equal(_keys_of(0), 0, "the wizard left behind did not")
	foe.global_position = _on_bridge(map, RoomSocket.Facing.WEST, 40.0)
	_ticks(3)
	check(flow.locks.is_open(WEST), "the foe's key opens the door")
	check_equal(LockDoors.keys_of(foe), 0, "and is spent")


## The owner, 2026-11-19: "It should just drop in some random room." The key's room is picked by
## the run's chance (keyed by the key) among the rooms reached without passing a locked
## door, never the treasure room itself; a fight room's key drops on its clear.
func test_the_keys_room_is_picked_by_chance_among_the_open_rooms() -> void:
	var map: BiomeMap = _start(1, &"treasure", &"fight", [], [IMP])
	_ticks(1)
	var drop: int = flow.locks.key_drops[0]
	check(drop == 0 or drop == EAST, "the start room or the court, never the treasure room: %d" % drop)
	var open: PackedInt32Array = LockDoors.open_rooms(map, PackedByteArray([LockDoors.RULE_NONE, LockDoors.RULE_KEY, LockDoors.RULE_NONE]))
	check_equal(open, PackedInt32Array([0, EAST]), "the open rooms: all but the locked one")
	check_equal(flow.locks.key_drops.size(), 1, "one treasure room: one key")
	check_equal(drop, open[tick.sim.chance_int(FlowScript.KEY_PURPOSE, 0, 0, open.size())], "the run's chance, keyed by the key, picks it")
	# Whatever the seed picked, a fight room's key drops as its fight is cleared: the court's here.
	flow.locks.key_drops[0] = EAST
	flow.locks.key_states[0] = LockDoors.KEY_WAITING
	keys.clear()
	_put(0, _by_socket(map, EAST, RoomSocket.Facing.WEST, 24.0))
	check(keys.is_empty(), "in the court: nothing lies while its fight is on")
	flow.stand_all_now()
	_beat(EAST)
	_ticks(2)
	check(flow.life.has(EAST, RoomLife.CLEARED), "the court cleared")
	check(not keys.is_empty() and keys.back()[2] and flow.biome.room_rect(EAST).has_point(keys.back()[1]), "its key lies in the court once cleared")
	var picked: Dictionary = {}
	for seed in 24:
		picked[open[Sim.seeded(seed).chance_int(FlowScript.KEY_PURPOSE, 0, 0, open.size())]] = true
	check_equal(picked.size(), 2, "over seeds, either room")


## The owner, 2026-11-19: "Multiple treasures can be in each biome. But there should not necessarily
## be a key for each treasure room available." Two treasure rooms: 1 or 2 keys (never more), any key
## opens either door and is spent by it, so with one the party chooses.
func test_keys_are_any_doors_and_may_be_fewer_than_the_treasure_rooms() -> void:
	var map: BiomeMap = _start(2, &"treasure", &"treasure")
	_ticks(1)
	check_equal(flow.locks.doors(), 2, "a door each")
	var keys: int = flow.locks.key_drops.size()
	check(keys >= 1 and keys <= 2, "1 or 2 keys for 2 treasure rooms: %d" % keys)
	check_equal(keys, 1 + tick.sim.chance_int(FlowScript.KEY_COUNT_PURPOSE, 0, 0, 2), "the run's chance counts them")
	var counts: Dictionary = {}
	for seed in 16:
		counts[1 + Sim.seeded(seed).chance_int(FlowScript.KEY_COUNT_PURPOSE, 0, 0, 2)] = true
	check_equal(counts.size(), 2, "over seeds, a key short now and then")
	for key in keys:
		check_equal(flow.locks.key_drops[key], 0, "each in the one room open to it: the start room")
		check_equal(flow.locks.key_states[key], LockDoors.KEY_LYING, "lying there")
	check(keys < 2 or flow.locks.key_at[0].distance_to(flow.locks.key_at[1]) > LockDoors.KEY_REACH * 2.0, "two in one room each on a spot of its own")
	# Whatever the seed dealt: two keys lying in the start room, apart, on clear ground.
	var first: Vector2 = flow.locks.key_at[0]
	var second: Vector2 = _grid().nearest_ground(first + Vector2(64.0, 0.0), 6.0)
	flow.locks.key_drops = PackedInt32Array([0, 0])
	flow.locks.key_states = PackedByteArray([LockDoors.KEY_LYING, LockDoors.KEY_LYING])
	flow.locks.key_at = PackedVector2Array([first, second])
	# The first key taken opens the court's door (any key, any door), and only one is spent.
	_put(1, first)
	_put(1, _on_bridge(map, RoomSocket.Facing.EAST, 48.0))
	check(flow.locks.is_open(EAST), "a key opens the court")
	check(_keys_of(1) == 0 and flow.locks.key_states[1] == LockDoors.KEY_LYING, "one key spent, the other still lying")
	_put(0, _on_bridge(map, RoomSocket.Facing.WEST, 48.0))
	_ticks(10)
	check(not flow.locks.is_open(WEST), "no key held: the antechamber stays shut (the party chose the court)")
	_put(0, second)
	_put(0, _on_bridge(map, RoomSocket.Facing.WEST, 48.0))
	_ticks(2)
	check(flow.locks.is_open(WEST), "the second key opens the antechamber")
	check_equal(_keys_of(0), 0, "and is spent")


## A key in a body's bag is state with its inventory: a snapshot saves and restores it, and the
## hints are told again (none needed) after a restore and as the biome goes.
func test_keys_held_are_saved_by_a_snapshot_and_the_hints_forgotten() -> void:
	var map: BiomeMap = _start(2, &"treasure", &"treasure")
	_ticks(1)
	var first: Vector2 = flow.locks.key_at[0]
	var second: Vector2 = _grid().nearest_ground(first + Vector2(64.0, 0.0), 6.0)
	flow.locks.key_drops = PackedInt32Array([0, 0])
	flow.locks.key_states = PackedByteArray([LockDoors.KEY_LYING, LockDoors.KEY_LYING])
	flow.locks.key_at = PackedVector2Array([first, second])
	_put(1, first)
	_put(1, second)
	check_equal([_keys_of(0), _keys_of(1)], [0, 2], "both in seat 1's bag")
	var snapshot := Snapshot.take(tick.state_areas(), root)
	_put(1, _on_bridge(map, RoomSocket.Facing.EAST, 48.0))
	check(flow.locks.is_open(EAST) and _keys_of(1) == 1, "one spent on the court")
	_put(0, _on_bridge(map, RoomSocket.Facing.WEST, 48.0))
	check(not needed.is_empty() and needed.back()[0] == 0 and needed.back()[2], "seat 0 at the other door with none: told a key is needed")
	needed.clear()
	check(snapshot.restore(tick.state_areas(), root).is_empty(), "restored")
	check_equal(_keys_of(1), 2, "the two keys back in seat 1's bag")
	check(not flow.locks.is_open(EAST), "and the court shut again")
	check(needed.size() >= 4 and needed.slice(0, 4).all(func(told: Array) -> bool: return not told[2]), "every seat's hint forgotten: %s" % [needed])
	needed.clear()
	flow.stop_run()
	check(not needed.is_empty() and not needed.back()[2], "the biome gone: no hint")


func test_a_key_keeps_off_a_fountains_pool_and_a_shops_items() -> void:
	var middle := Vector2(200.0, 160.0)
	var fountain := RoomKind.new()
	fountain.fill = RoomKind.FILL_FOUNTAIN
	var spot: Vector2 = SpecialPlaces.key_spot(null, middle, SpecialPlaces.taken_by(fountain, null, middle))
	check(not SpecialPlaces.pool(null, middle).grow(SpecialPlaces.KEY_OFF_ITEM).has_point(spot), "off the pool: %s" % spot)
	var shop := RoomKind.new()
	shop.fill = RoomKind.FILL_SHOP
	spot = SpecialPlaces.key_spot(null, middle, SpecialPlaces.taken_by(shop, null, middle))
	for item: Vector2 in SpecialPlaces.shelf(null, middle):
		check(item.distance_to(spot) > SpecialPlaces.KEY_OFF_ITEM, "off each item: %s" % spot)
	check_equal(SpecialPlaces.key_spot(null, middle, SpecialPlaces.taken_by(RoomKind.new(), null, middle)), middle, "any other room: its middle")
	# Several keys in one room: each its own spot, every one off the pool.
	var spots: PackedVector2Array = SpecialPlaces.key_spots(null, middle, SpecialPlaces.taken_by(fountain, null, middle), 3)
	check_equal(spots.size(), 3, "a spot a key")
	check(spots[0] != spots[1] and spots[1] != spots[2] and spots[0] != spots[2], "each apart: %s" % spots)
	for at: Vector2 in spots:
		check(not SpecialPlaces.pool(null, middle).grow(SpecialPlaces.KEY_OFF_ITEM).has_point(at), "each off the pool: %s" % at)


func test_a_secret_rock_opens_to_its_own_element_only() -> void:
	var map: BiomeMap = _start(1, &"secret", &"fight")
	_ticks(1)
	var element: StringName = flow.locks.element_of(WEST)
	check(element != &"", "an element rolled for the room")
	check(not rocks.is_empty() and rocks.back()[2] == element and not rocks.back()[3], "the view is told the rock and its element")
	var mouth: Rect2 = flow.locks.mouth_of(0)
	var other: StringName = &"fire" if element != &"fire" else &"frost"
	events.emit_signal("floor_touched", 0, other, mouth.get_center(), 16.0)
	_ticks(1)
	check(not flow.locks.is_open(WEST), "another element breaks nothing")
	events.emit_signal("floor_touched", 0, element, mouth.get_center() + Vector2(200.0, 0.0), 16.0)
	_ticks(1)
	check(not flow.locks.is_open(WEST), "its element far away breaks nothing")
	events.emit_signal("floor_touched", 0, element, mouth.get_center() + Vector2(20.0, 0.0), 8.0)
	check(not flow.locks.is_open(WEST), "not in the middle of a step: at Flow's next")
	_ticks(1)
	check(flow.locks.is_open(WEST), "its element touching the floor at it breaks it")
	check(not _grid().is_shut_mouth(mouth.get_center()), "its mouth opens")
	check(rocks.back()[3], "the view is told it broke")
	_put(0, _by_socket(map, WEST, RoomSocket.Facing.EAST, 24.0))
	check_equal(due.back(), [WEST, &"secret"], "the secret room's rewards as it is entered")
	# The run's chance rolls it (the same on every machine): keyed by the room, among the elements.
	var elements: Array[StringName] = flow.call(&"_element_ids")
	check_equal(element, elements[tick.sim.chance_int(FlowScript.SECRET_PURPOSE, WEST, 0, elements.size())], "the run's chance, keyed by the room, rolls it")


func test_a_challenge_rooms_elites_stand_with_more_health_a_card_more_and_an_outline() -> void:
	var map: BiomeMap = _start(1, &"fight", &"challenge", [], [SPITTER, IMP], [&"faster", &"faster"])
	_ticks(1)
	check(not flow.gates.is_open(EAST), "a challenge room is behind a gather door")
	_put(0, _on_bridge(map, RoomSocket.Facing.EAST, 48.0))
	_ticks(1)
	check(flow.gates.is_open(EAST) and flow.life.has(EAST, RoomLife.SEALED), "every standing wizard at it: it opens and seals")
	flow.stand_all_now()
	var stood: Array[Actor] = []
	for enemy: Node in flow.get(&"_enemies"):
		var body := enemy as Actor
		if body != null and body.room == EAST:
			stood.append(body)
	check_equal(stood.size(), 2, "both stand")
	var plain_spitter: EnemyBase = registry.call(&"get_resource", &"enemies", SPITTER) as EnemyBase
	for body: Actor in stood:
		check(body.is_elite(), "%s is an elite" % body.data.id)
		check_equal(body.health.max_health, body.data.health_for(body.players, body.stat_scale), "its health is its data's at its scale")
		check(body.stat_scale >= DifficultyScript.ELITE_HEALTH - 0.001, "more health: its scale holds the elites' %s" % DifficultyScript.ELITE_HEALTH)
		check(body.get_node_or_null(^"EliteLook") is EliteLook, "an outline")
		if body.data.id == SPITTER:
			check_equal(body.caster.slot_count(0), plain_spitter.staffs[0].staff.slots + 1, "a slot more on its first staff")
			check_equal(body.caster.cards_of(0)[0], &"faster", "the extra card in front of its own")
	_beat(EAST)
	_ticks(2)
	check_equal(due.back(), [EAST, &"challenge"], "the bigger reward of the challenge's own table")


## A reward room's type (the owner's ask of 2026-11-19) comes with its rewards due, from the map.
func test_a_reward_rooms_type_comes_with_its_rewards() -> void:
	east_type = RewardType.make(ItemKinds.CARD, &"modifier")
	var map: BiomeMap = _start(1, &"fight", &"reward")
	_ticks(1)
	_put(0, _by_socket(map, EAST, RoomSocket.Facing.WEST, 24.0))
	check_equal(due, [[EAST, &"reward"]], "its rewards are due")
	check(RewardType.from_row(due_types[0]).same_as(east_type), "of the room's own type: %s" % [due_types[0]])
	_ticks(1)
	var waiting: Array = rewards.call(&"waiting_of", 0) as Array
	check_equal(waiting.size(), 1, "the wizard's offer")
	for choice: Dictionary in waiting[0]["choices"]:
		check_equal((registry.call(&"get_resource", &"spells", choice["id"]) as SpellComponent).kind(), &"modifier", "a modifier room offers modifiers")


## The owner, 2026-11-20 (after #884): a treasure room's done look is its door opened. Flow tells the
## view the rooms opened (`rooms_opened`, its `LockDoors.opened`): shut as the biome starts, as the
## door opens, `again` after a restore, empty as the biome goes.
func test_the_rooms_opened_are_told_to_the_view() -> void:
	var told: Array = []
	var on_opened := func(opened: PackedByteArray, again: bool) -> void: told.append([opened, again])
	events.connect("rooms_opened", on_opened)
	var map: BiomeMap = _start(1, &"treasure", &"boss", [], [IMP])
	_ticks(1)
	check(not told.is_empty() and (told.back()[0] as PackedByteArray).size() == 3 and (told.back()[0] as PackedByteArray)[WEST] == 0, "told as the biome starts: the treasure room shut (%s)" % [told])
	var snapshot := Snapshot.take(tick.state_areas(), root)
	_put(0, flow.locks.key_at[0])
	told.clear()
	_put(0, _on_bridge(map, RoomSocket.Facing.WEST, 40.0))
	check(flow.locks.is_open(WEST), "the door opens")
	check_equal(told.size(), 1, "told once as it opens")
	check((told.back()[0] as PackedByteArray)[WEST] == 1 and not told.back()[1], "the treasure room opened, played in")
	told.clear()
	check(snapshot.restore(tick.state_areas(), root).is_empty(), "restored to before")
	check(not told.is_empty() and (told.back()[0] as PackedByteArray)[WEST] == 0 and told.back()[1], "told again as it stands: shut (%s)" % [told])
	told.clear()
	flow.stop_run()
	check(not told.is_empty() and (told.back()[0] as PackedByteArray).is_empty(), "the biome gone: none")
	events.disconnect("rooms_opened", on_opened)


## The owner, 2026-11-20 (after #884): a reward room's done look waits for its rewards to be taken.
## Rewards tells the view which rooms still hold one (`rooms_rewards_left`): from the clear (due)
## through its roll while a present player's item lies there; a player who was away has its offer
## waiting elsewhere (rule 4), which keeps nothing in the room; the item taken, the room holds none.
func test_the_rooms_with_rewards_left_are_told_until_each_lying_one_is_taken() -> void:
	var told: Array = []
	var on_left := func(left: PackedByteArray, again: bool) -> void: told.append([left, again])
	events.connect("rooms_rewards_left", on_left)
	var map: BiomeMap = _start(2, &"fight", &"reward")
	_ticks(1)
	told.clear()
	_wizard(0).global_position = _by_socket(map, EAST, RoomSocket.Facing.WEST, 24.0)
	_ticks(1)
	check(not told.is_empty(), "told as its clear is due")
	check(_left_in(told, EAST), "the reward room holds its rewards from the moment its clear is due")
	_ticks(1)
	check(not told.is_empty() and _left_in(told, EAST), "rolled: seat 0's item lies there")
	var away: Array = rewards.call(&"waiting_of", 1)
	check(away.size() == 1 and not bool((away[0] as Dictionary)["lying"]), "seat 1 was away: its offer waits elsewhere")
	var mine: Array = rewards.call(&"waiting_of", 0)
	check_equal(mine.size(), 1, "seat 0's offer")
	var snapshot := Snapshot.take(tick.state_areas(), root)
	told.clear()
	events.apply_command(&"reward_pick_requested", [0, int((mine[0] as Dictionary)["offer"]), 0])
	check(not told.is_empty() and not _left_in(told, EAST) and not told.back()[1], "seat 0 took its item: nothing left in the room, though seat 1's still waits")
	check_equal((rewards.call(&"waiting_of", 1) as Array).size(), 1, "seat 1's offer still waits, anywhere")
	told.clear()
	check(snapshot.restore(tick.state_areas(), root).is_empty(), "restored to before the pick")
	check(not told.is_empty() and _left_in(told, EAST) and told.back()[1], "told again as it stands: the item lies there again")
	events.disconnect("rooms_rewards_left", on_left)


static func _left_in(told: Array, room: int) -> bool:
	var left: PackedByteArray = told.back()[0]
	return room < left.size() and left[room] != 0
