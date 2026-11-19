extends "res://tests/support/suite.gd"
## Special rooms (connected biomes CB11, docs/milestones/connected-biomes.md, decisions 1 and 16 to
## 24; gameplay/flow/lock_doors.gd, gameplay/flow/special_places.gd, gameplay/rewards/rewards.gd),
## on the real autoloads, in CB3's split test map (tests/support/biome_maps.gd: the nave the start
## room 0, the antechamber west, room 1, and the ossuary court east, room 2), its rooms' kinds set
## here: each kind's fill as the party enters (a reward room's rewards, a shop's shelf, a fountain's
## pool), a fight's rewards however its foes left it, the treasure room's key dropped on the way and
## its door opening for all, a secret rock opening to its own element only, a challenge room's
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
var keys: Array = []
var key_doors: Array = []
var rocks: Array = []
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
	keys.clear()
	key_doors.clear()
	rocks.clear()
	_sources.clear()
	events.connect("room_rewards_due", _on_due)
	events.connect("key_shown", _on_key)
	events.connect("key_door_shown", _on_key_door)
	events.connect("secret_rock_shown", _on_rock)
	flow.world_parent = own(Node.new()) as Node
	root.add_child(flow.world_parent)


func after_each() -> void:
	events.disconnect("room_rewards_due", _on_due)
	events.disconnect("key_shown", _on_key)
	events.disconnect("key_door_shown", _on_key_door)
	events.disconnect("secret_rock_shown", _on_rock)
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


func _on_due(room: int, table: StringName) -> void:
	due.append([room, table])


func _on_key(key: int, at: Vector2, lying: bool) -> void:
	keys.append([key, at, lying])


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
	_ticks(1)
	check_equal((rewards.call(&"waiting_of", 0) as Array).size(), 1, "the wizard there has its offer")
	check_equal((rewards.call(&"waiting_of", 1) as Array).size(), 1, "the one elsewhere finds its own waiting (rule 4)")


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
	check(due.is_empty(), "a shop's clear rewards nobody")
	_put(0, _by_socket(map, EAST, RoomSocket.Facing.WEST, 24.0))
	check_equal(float(rewards.call(&"pool_left", EAST)), RewardsScript.POOL_HEALTH, "the fountain's pool filled as it is entered")
	_put(0, _by_socket(map, WEST, RoomSocket.Facing.EAST, 24.0))
	check_equal((rewards.call(&"shelf") as Array).size(), shelf.size(), "entered again: the same shelf")


func test_the_treasure_rooms_key_drops_on_the_way_and_its_door_opens_for_all() -> void:
	var map: BiomeMap = _start(2, &"treasure", &"fight", [], [IMP])
	_ticks(1)
	check_equal(flow.locks.doors(), 1, "the treasure room has a door: where the west bridge meets it")
	var mouth: Rect2 = flow.locks.mouth_of(0)
	check(_grid().is_shut_mouth(mouth.get_center()), "its mouth is shut")
	check(not key_doors.is_empty() and key_doors.back()[0] == 0 and not key_doors.back()[2], "the view is told the key door, shut")
	# The key drops in the room its bridge hangs off: the start room, cleared as the biome starts.
	check(not keys.is_empty() and keys.back()[2], "its key lies on the floor")
	var key_at: Vector2 = keys.back()[1]
	check(flow.biome.room_rect(0).has_point(key_at), "in the start room, on the way to it")
	# A wizard at the door without the key: it stays shut.
	_put(0, _on_bridge(map, RoomSocket.Facing.WEST, 48.0))
	_ticks(30)
	check(not flow.locks.is_open(WEST), "no key: shut")
	# The other takes the key; the first, still at the door, opens it for all.
	_put(1, key_at)
	check(not keys.back()[2], "the key is taken off the floor")
	check_equal(flow.locks.key_states[0], LockDoors.KEY_SPENT, "the party held it, and at the door it is spent")
	check(flow.locks.is_open(WEST), "the door opens")
	check(not _grid().is_shut_mouth(mouth.get_center()), "its mouth with it")
	check(key_doors.back()[2], "the view is told it opened")
	_put(1, _by_socket(map, WEST, RoomSocket.Facing.EAST, 24.0))
	check_equal(due.back(), [WEST, &"treasure"], "the treasure's rewards as it is entered")


func test_a_secret_rock_opens_to_its_own_element_only() -> void:
	var map: BiomeMap = _start(1, &"secret", &"fight")
	_ticks(1)
	var element: StringName = flow.locks.element_of(WEST)
	check(element != &"", "an element rolled for the room")
	check(not rocks.is_empty() and rocks.back()[2] == element and not rocks.back()[3], "the view is told the rock and its element")
	var mouth: Rect2 = flow.locks.mouth_of(0)
	var other: StringName = &"fire" if element != &"fire" else &"frost"
	events.emit_signal("floor_touched", 0, other, mouth.get_center(), 16.0)
	check(not flow.locks.is_open(WEST), "another element breaks nothing")
	events.emit_signal("floor_touched", 0, element, mouth.get_center() + Vector2(200.0, 0.0), 16.0)
	check(not flow.locks.is_open(WEST), "its element far away breaks nothing")
	events.emit_signal("floor_touched", 0, element, mouth.get_center() + Vector2(20.0, 0.0), 8.0)
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
