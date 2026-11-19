extends "res://tests/support/suite.gd"
## A travelling bot crosses every kind of walkway (tests/bots/bot.gd, "Travel"; the owner,
## 2026-11-19: the four-bot smoke test's bots could not cross some bridges out of the start room, so
## they never reached a fight). Two crypt rooms joined by one walkway: straight east
## to west, straight north to south, and the corners (square, wide and tall), each in all four
## mirrorings, walked from either room. The bot's wizard stands in one room, the fight still to come
## in the other, and it walks there as the game moves it (the actor fixture), each tick as its frame
## wants (each axis full on or off).
const Fixture := preload("res://tests/gameplay/actor/actor_fixture.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
const BotScript := preload("res://tests/bots/bot.gd")
const BiomeMaps := preload("res://tests/support/biome_maps.gd")

## The rooms the walkways join (the first two that fit, any mirroring; the start room first, where
## the bots were stuck).
const ROOMS: Array[StringName] = [&"crypt_start", &"arena_07", &"arena_01", &"arena_03", &"arena_05", &"arena_06", &"arena_08"]
## One walkway of each kind.
const WALKWAYS: Array[StringName] = [&"crypt_bridge_192", &"crypt_bridge_v192", &"crypt_corner_320", &"crypt_corner_384x256", &"crypt_corner_256x384"]
## How long a crossing may take, and how near the fight room's middle counts as there.
const TICKS: int = 1200
const THERE: float = 48.0
## How near a shut door's mouth counts as waiting at it.
const BY_THE_DOOR: float = 56.0


## What the bot reads of Flow (`biome`, `life`, `gates`).
class FlowStandIn:
	extends Node
	var biome: BiomeWorld = null
	var life: RoomLife = null
	var gates: GatherDoors = null


var _world: Fixture
var _into: Node2D
var _flow: FlowStandIn


func before_each() -> void:
	super.before_each()
	_world = Fixture.new(root)
	_into = Node2D.new()
	root.add_child(_into)
	_flow = FlowStandIn.new()
	root.add_child(_flow)


func after_each() -> void:
	_world.free_all()
	_into.free()
	_flow.free()
	super.after_each()


## Two rooms joined by `walkway` mirrored by `mirror`, room 0 at its end 0 and room 1 at its end 1:
## the first of ROOMS (in any mirroring) with a socket facing each end that do not overlap.
func _map(walkway: StringName, mirror: int) -> BiomeMap:
	var way: PieceShape = BiomeMaps.shape(_world.registry, walkway).mirrored(mirror)
	var fits: Array = [_fitting(way.socket_facing[0]), _fitting(way.socket_facing[1])]
	for first: Array in fits[0]:
		for second: Array in fits[1]:
			var map: BiomeMap = _joined(walkway, mirror, way, [first, second])
			# Rooms that overlap (each other, or the walkway past their lip) are passed over at a glance (a
			# map's problems take long to work out).
			var shapes: Dictionary = BiomeMaps.shapes(_world.registry, map)
			var a: Rect2 = map.room_shape(0, shapes).rect_at(map.room_places[0])
			var b: Rect2 = map.room_shape(1, shapes).rect_at(map.room_places[1])
			var over: Rect2 = map.bridge_shape(0, shapes).rect_at(map.bridge_places[0])
			if not a.intersects(b) and not a.grow(-PieceShape.GRID).intersects(over) and not b.grow(-PieceShape.GRID).intersects(over) and map.problems(shapes).is_empty():
				return map
	check(false, "two rooms fit %s mirrored %d" % [walkway, mirror])
	return null


## Each [template, mirroring, socket] of ROOMS with a socket facing a walkway end that faces `facing`.
func _fitting(facing: int) -> Array:
	var out: Array = []
	for id: StringName in ROOMS:
		for room_mirror: int in PieceShape.MIRRORINGS:
			var room: PieceShape = BiomeMaps.shape(_world.registry, id).mirrored(room_mirror)
			var socket: int = room.socket_facing.find((facing + 2) % 4)
			if socket >= 0:
				out.append([id, room_mirror, socket])
	return out


## The map of `walkway` (its shape mirrored, `way`) and the two `rooms` ([template, mirroring, socket]).
func _joined(walkway: StringName, mirror: int, way: PieceShape, rooms: Array) -> BiomeMap:
	var places: Array[Vector2] = []
	for end in 2:
		var room: PieceShape = BiomeMaps.shape(_world.registry, rooms[end][0]).mirrored(rooms[end][1])
		places.append(way.socket_at[end] - room.socket_at[rooms[end][2]])
	var corner: Vector2 = Vector2.ZERO.min(places[0]).min(places[1])
	var map := BiomeMap.new()
	map.biome = &"crypt"
	map.add_room(rooms[0][0], places[0] - corner, rooms[0][1], &"start")
	map.add_room(rooms[1][0], places[1] - corner, rooms[1][1], &"fight")
	map.add_bridge(walkway, -corner, mirror, 0, rooms[0][2], 1, rooms[1][2])
	map.work_out_depths()
	return map


## Lay `map`, stand the bot's wizard in room `from` and walk it toward the fight in the other room
## (behind a shut gather door when `shut`; already under way, a teammate in it, when `under_way`) for
## up to TICKS ticks; true once `there(wizard, biome)`.
func _walked(map: BiomeMap, from: int, shut: bool, there: Callable, under_way: bool = false) -> bool:
	var biome := BiomeWorld.new()
	biome.registry = _world.registry
	biome.projectiles = _world.projectiles
	var problems: PackedStringArray = biome.lay(_into, map)
	check_equal(problems, PackedStringArray(), "the test map is laid")
	if not problems.is_empty():
		return false
	var to: int = 1 - from
	var fights: Array[RoomFight] = [RoomFight.new(), RoomFight.new()]
	fights[to].enemies = [&"skeleton"] as Array[StringName]
	var life := RoomLife.new()
	life.begin(map.rooms(), biome.places(), fights)
	if under_way:
		life.set_flag(to, RoomLife.ENTERED, true)
		life.set_flag(to, RoomLife.STARTED, true)
	_flow.biome = biome
	_flow.life = life
	_flow.gates = null
	if shut:
		var rules := PackedByteArray([GatherDoors.RULE_NONE, GatherDoors.RULE_NONE])
		rules[to] = GatherDoors.RULE_GATHER
		var gates := GatherDoors.new()
		gates.begin(map, rules, PackedByteArray([0, 0]))
		gates.lay(biome, _world.projectiles.grid())
		_flow.gates = gates
	var mind := Fixture.Scripted.new()
	mind.team = ActorsScript.TEAM_WIZARDS
	mind.seat = 0
	var start: Vector2 = biome.room_rect(from).get_center()
	var wizard: Actor = _world.actor(_world.projectiles.grid().nearest_ground(start, 6.0), [&"mover"], mind)
	var bot := BotScript.new()
	bot.use_flow(_flow)
	var intent := ActorIntent.new()
	for _i in TICKS:
		intent.clear()
		intent.move = bot.travel(wizard)
		bot.send(intent)
		mind.move = bot.wanted_frame().move
		wizard.tick_step(Fixture.STEP)
		if there.call(wizard, biome):
			return true
	return false


## True when `wizard` stands in room 1 - `from`, near its middle.
func _in_the_fight(from: int) -> Callable:
	return func(wizard: Actor, biome: BiomeWorld) -> bool:
		return wizard.room == 1 - from and wizard.global_position.distance_to(biome.room_rect(1 - from).get_center()) <= THERE


## True when `wizard` waits on the walkway (bridge 0) within BY_THE_DOOR of the shut door of room 1 - `from`.
func _at_the_door(from: int) -> Callable:
	return func(wizard: Actor, biome: BiomeWorld) -> bool:
		return wizard.room == biome.map.rooms() and wizard.global_position.distance_to(biome.mouth_rect(0, 1 - from).get_center()) <= BY_THE_DOOR


func _fresh_world() -> void:
	_world.free_all()
	_world = Fixture.new(root)
	for piece: Node in _into.get_children():
		piece.free()


func _check_walkway(walkway: StringName) -> void:
	for mirror: int in PieceShape.MIRRORINGS:
		var map: BiomeMap = _map(walkway, mirror)
		if map == null:
			return
		for from in 2:
			check(_walked(map, from, false, _in_the_fight(from)), "%s mirrored %d crosses from room %d" % [walkway, mirror, from])
			_fresh_world()


func test_a_bot_crosses_a_straight_east_west_walkway() -> void:
	_check_walkway(WALKWAYS[0])


func test_a_bot_crosses_a_straight_north_south_walkway() -> void:
	_check_walkway(WALKWAYS[1])


func test_a_bot_crosses_a_square_corner_walkway() -> void:
	_check_walkway(WALKWAYS[2])


func test_a_bot_crosses_a_wide_corner_walkway() -> void:
	_check_walkway(WALKWAYS[3])


func test_a_bot_crosses_a_tall_corner_walkway() -> void:
	_check_walkway(WALKWAYS[4])


func test_a_bot_waits_on_a_corner_walkway_by_a_shut_door() -> void:
	# Review of the route (2026-11-19): with the fight behind a shut door (a gather door, the boss's
	# gate) the bot walks along the walkway to the door and waits there, where the door counts it.
	for walkway: StringName in [WALKWAYS[0], WALKWAYS[2]]:
		for mirror: int in PieceShape.MIRRORINGS:
			var map: BiomeMap = _map(walkway, mirror)
			if map == null:
				return
			check(_walked(map, 0, true, _at_the_door(0)), "%s mirrored %d: the bot waits by the shut door" % [walkway, mirror])
			_fresh_world()


func test_a_bot_joins_a_fight_a_teammate_started() -> void:
	# Regression (replay seed 57, 2026-11-19): once one bot stepped into the fight room it was
	# entered, no longer a fight to come, and the others stood still in the room before it.
	var map: BiomeMap = _map(WALKWAYS[2], 0)
	if map != null:
		# In a fight under way the brain plays (travel stops): it only has to get in.
		var in_room: Callable = func(wizard: Actor, _biome: BiomeWorld) -> bool: return wizard.room == 1
		check(_walked(map, 0, false, in_room, true), "it walks into the fight under way")
