extends "res://tests/support/suite.gd"
## Room life (connected biomes CB3, docs/milestones/connected-biomes.md, "Room state", "A room is
## awake"), on the real autoloads: a biome started by Flow (`start_biome`, the split test map: the
## nave the start room, the antechamber west and the ossuary court east, tests/support/biome_maps.gd).
## Its start room is entered as it starts; a fight starts as a wizard's own body steps past a mouth
## onto its room and seals it one way (nobody inside leaves, a teammate walks in); it is cleared with
## its last enemy and opens. A swap or a portal never takes a body out of a sealed fight, and a
## teleport crosses an open doorway but not a seal. A possessed enemy leaves its room, which is
## cleared without it, and fights for the room it ends in. A room nobody is in sleeps; a shot wakes
## it; a sleeping room waits as if no time had passed (its burning pillar against one that never
## slept). A downed wizard crawls in a biome.
const FlowScript := preload("res://gameplay/flow/flow.gd")
const TickScript := preload("res://core/sim/tick.gd")
const BiomeMaps := preload("res://tests/support/biome_maps.gd")
const DT: float = 1.0 / 60.0
const IMP: StringName = &"ember_imp"

var flow: FlowScript
var events: Node
var tick: TickScript
var input: Node
var frames: Node
var registry: Node
var projectiles: Node
var combat: Node
var actors: Node
var entered: Array[int] = []
var cleared: Array[int] = []
var built: Array[int] = []
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
	combat = root.get_node("Combat")
	actors = root.get_node("Actors")
	entered.clear()
	cleared.clear()
	built.clear()
	_sources.clear()
	events.connect("room_entered", _on_entered)
	events.connect("room_cleared", _on_cleared)
	events.connect("room_built", _on_built)
	flow.world_parent = own(Node.new()) as Node
	root.add_child(flow.world_parent)


func after_each() -> void:
	events.disconnect("room_entered", _on_entered)
	events.disconnect("room_cleared", _on_cleared)
	events.disconnect("room_built", _on_built)
	flow.stop_run()
	flow.world_parent = null
	flow.mode = FlowScript.MODE_RUN
	for seat in 4:
		frames.call("set_source", seat, null)
		input.leave(seat)
	tick.begin_run()


func _on_entered(_room_id: StringName, room: int) -> void:
	entered.append(room)


func _on_cleared(_room_id: StringName, room: int) -> void:
	cleared.append(room)


func _on_built(_room_id: StringName, room: int, _layout: Node) -> void:
	built.append(room)


## The split map started with `players` seats, the antechamber's and the court's fights `west` and
## `east` (enemy ids).
func _start(players: int, west: Array[StringName], east: Array[StringName]) -> BiomeMap:
	var map: BiomeMap = BiomeMaps.split(registry)
	for seat in players:
		input.add_virtual_device(seat)
		var walk := Walk.new()
		_sources.append(walk)
		frames.call("set_source", seat, walk)
	var fights: Array[RoomFight] = [RoomFight.new(), RoomFight.of(west), RoomFight.of(east)]
	check(flow.start_biome(0, map, fights), "the biome starts")
	return map


func _ticks(count: int) -> void:
	for _i in count:
		tick.run(DT)


func _wizard(seat: int) -> Actor:
	return flow.get_wizard(seat) as Actor


func _grid() -> RoomGrid:
	return projectiles.call(&"grid") as RoomGrid


## A point of room `room` `inside` pixels in from its socket facing `facing`, on the socket's line.
func _by_socket(map: BiomeMap, room: int, facing: int, inside: float) -> Vector2:
	return BiomeMaps.socket_point(registry, map, room, facing) - RoomSocket.way(facing) * inside


## Every enemy of the fight in `room` down and gone.
func _beat(room: int) -> void:
	for enemy: Node in flow.get(&"_enemies").duplicate():
		var body := enemy as Actor
		if body != null and body.room == room:
			events.emit_signal("enemy_died", 0, body, body.position, -1)
			body.get_parent().remove_child(body)
			body.free()


func test_the_start_room_is_entered_and_every_piece_built_and_placed() -> void:
	var map: BiomeMap = _start(1, [IMP], [IMP])
	check_equal(flow.mode, FlowScript.MODE_BIOME, "a biome's run")
	check_equal(built, [0, 1, 2, 3, 4] as Array[int], "every room and then every bridge is built, in order")
	check_equal(entered, [0] as Array[int], "the start room is entered as the biome starts")
	check_equal(cleared, [0] as Array[int], "and, with no fight, cleared")
	check_equal(_grid().places(), 5, "the grid knows every piece as a place")
	check(map.room_places[0] == flow.biome.map.room_places[0], "the start room is the map's room 0")
	check_equal(_wizard(0).room, 0, "the wizard stands in the start room")
	var camera: Camera2D = flow.world.find_children("*", "Camera2D", true, false)[0] as Camera2D
	check_equal(camera.limit_right, ceili(projectiles.call(&"bounds").end.x), "the camera's limits are the biome's")
	check(float(projectiles.call(&"room_size")) < (projectiles.call(&"bounds") as Rect2).size.x, "a growing shot grows to a room's side, not the biome's")


func test_a_fight_starts_past_a_mouth_and_seals_one_way() -> void:
	var map: BiomeMap = _start(2, [IMP], [])
	_ticks(1)
	var one: Actor = _wizard(0)
	var two: Actor = _wizard(1)
	# Seat 0 just inside the antechamber from its bridge; seat 1 on that bridge, outside.
	one.global_position = _by_socket(map, 1, RoomSocket.Facing.EAST, 24.0)
	two.global_position = _by_socket(map, 1, RoomSocket.Facing.EAST, -48.0)
	_ticks(1)
	check(entered.has(1), "the antechamber is entered as a wizard stands on it")
	check(flow.life.has(1, RoomLife.SEALED) and _grid().is_sealed(1), "its fight starts and seals it")
	check_equal(flow.enemies_left(), 1, "its imp is the fight's")
	_sources[0].move = Vector2.RIGHT
	_sources[1].move = Vector2.LEFT
	_ticks(90)
	var room: Rect2 = flow.biome.room_rect(1)
	check(room.has_point(one.global_position), "the wizard inside does not leave it: %s" % one.global_position)
	check(room.has_point(two.global_position), "the teammate outside walks in: %s" % two.global_position)
	_beat(1)
	_ticks(1)
	check(cleared.has(1) and not _grid().is_sealed(1), "cleared, it opens")
	_ticks(90)
	check(not room.has_point(one.global_position), "and the wizard walks out: %s" % one.global_position)


func test_a_swap_or_a_portal_never_takes_a_body_out_of_a_sealed_fight() -> void:
	var map: BiomeMap = _start(2, [IMP], [])
	var one: Actor = _wizard(0)
	var two: Actor = _wizard(1)
	one.global_position = _by_socket(map, 1, RoomSocket.Facing.EAST, 24.0)
	_ticks(1)
	check(_grid().is_sealed(1), "the antechamber is sealed")
	var inside: Vector2 = one.global_position
	var outside: Vector2 = two.global_position
	check(not CarrierSwap.may_trade(_grid(), inside, outside), "a swap across the seal fizzles")
	check(not CarrierSwap.may_trade(_grid(), outside, inside), "either way")
	events.emit_signal("target_move_requested", -1, one, outside)
	check_equal(one.global_position, inside, "a body inside is not moved out")
	var door: Vector2 = _by_socket(map, 1, RoomSocket.Facing.EAST, 40.0)
	events.emit_signal("target_move_requested", -1, two, door)
	check_equal(two.global_position, door, "a body outside is moved in")
	check(CarrierSwap.may_trade(_grid(), door, inside), "a swap within the sealed room trades")
	check(not CarrierSwap.may_trade(_grid(), _by_socket(map, 0, RoomSocket.Facing.EAST, 24.0), _by_socket(map, 2, RoomSocket.Facing.WEST, 24.0)) or _grid().walk_way_clear(_by_socket(map, 0, RoomSocket.Facing.EAST, 24.0), _by_socket(map, 2, RoomSocket.Facing.WEST, 24.0)), "across open rooms a swap goes only along a way a body could walk")


func test_a_teleport_crosses_an_open_doorway_but_not_a_seal() -> void:
	var map: BiomeMap = _start(1, [IMP], [])
	var one: Actor = _wizard(0)
	# East out of the nave, across its open mouth onto the bridge to the court (no fight there yet).
	one.global_position = _by_socket(map, 0, RoomSocket.Facing.EAST, 24.0)
	one.mover.call(&"_teleport", Vector2(96.0, 0.0), 0)
	check(not flow.biome.room_rect(0).has_point(one.global_position), "the teleport crossed the nave's open mouth: %s" % one.global_position)
	# Into the sealed antechamber, then east again: the seal stops it inside.
	one.global_position = _by_socket(map, 1, RoomSocket.Facing.EAST, 24.0)
	_ticks(1)
	check(_grid().is_sealed(1), "the antechamber is sealed")
	one.mover.call(&"_teleport", Vector2(96.0, 0.0), 0)
	check(flow.biome.room_rect(1).has_point(one.global_position), "a teleport never leaves a sealed fight: %s" % one.global_position)


func test_a_possessed_enemy_leaves_its_room_cleared_without_it() -> void:
	var map: BiomeMap = _start(1, [IMP], [])
	var one: Actor = _wizard(0)
	one.global_position = _by_socket(map, 1, RoomSocket.Facing.EAST, 24.0)
	_ticks(1)
	var imp := flow.get(&"_enemies")[0] as Actor
	for _i in 240:
		if not imp.is_spawning():
			break
		_ticks(1)
	imp.drive(one.home_controller)
	_ticks(1)
	check(cleared.has(1) and not _grid().is_sealed(1), "a possessed enemy is no one's fight: its room is cleared without it")
	imp.global_position = _by_socket(map, 0, RoomSocket.Facing.WEST, 24.0)
	imp.release()
	_ticks(2)
	check_equal(imp.room, 0, "released in the start room, it belongs there")
	check(flow.life.has(0, RoomLife.CLEARED) and not _grid().is_sealed(0), "a cleared room never seals again")
	check(flow.life.is_awake(0), "and it keeps its new room awake")


func test_a_room_nobody_is_in_sleeps_and_a_shot_wakes_it() -> void:
	var map: BiomeMap = _start(1, [], [])
	_ticks(2)
	check(flow.life.is_awake(0), "the start room is awake")
	check(not flow.life.is_awake(2), "the court sleeps")
	var pillar: Actor = _pillar_in(2)
	check(pillar != null and actors.asleep[pillar.id] != 0, "and its pillar with it")
	var middle: Vector2 = flow.biome.room_rect(2).get_center()
	projectiles.call(&"spawn", -1, middle, Vector2.ZERO, 1.0)
	_ticks(1)
	check(flow.life.is_awake(2), "a shot flying there wakes it")
	check_equal(actors.asleep[pillar.id], 0, "and its pillar")
	_ticks(70)
	check(not flow.life.is_awake(2), "gone, it sleeps again")
	check(map != null, "the map was laid")


func test_a_sleeping_room_waits_as_if_no_time_had_passed() -> void:
	# Slept: the pillar's burn put on as the court sleeps, 60 ticks asleep, then a wizard in it.
	var map: BiomeMap = _start(1, [], [])
	_ticks(2)
	var pillar: Actor = _pillar_in(2)
	events.emit_signal("status_requested", -1, pillar, &"burn", 2.0, 1.0)
	var left: float = combat.call(&"status_left", pillar, &"burn")
	_ticks(60)
	check_equal(combat.call(&"status_left", pillar, &"burn"), left, "asleep, its burn waits")
	_wizard(0).global_position = flow.biome.room_rect(2).get_center()
	# The tick it is woken on (Flow wakes it after the bodies and Combat stepped).
	_ticks(1)
	_ticks(30)
	var slept: Array = [combat.call(&"status_left", pillar, &"burn"), pillar.health.health if pillar.health != null else -1.0]
	flow.stop_run()
	tick.begin_run()
	# Never slept: a wizard in the court from the start, the same burn, the same 30 ticks.
	map = _start(1, [], [])
	_wizard(0).global_position = flow.biome.room_rect(2).get_center()
	_ticks(2)
	pillar = _pillar_in(2)
	events.emit_signal("status_requested", -1, pillar, &"burn", 2.0, 1.0)
	_ticks(30)
	var awake: Array = [combat.call(&"status_left", pillar, &"burn"), pillar.health.health if pillar.health != null else -1.0]
	check_equal(slept, awake, "the room that slept plays on as the one that never did")
	check(float(slept[0]) < left, "and the burn ran while it was awake")


func test_a_downed_wizard_crawls_in_a_biome() -> void:
	_start(1, [], [])
	_ticks(1)
	var one: Actor = _wizard(0)
	one.health.take(one.health.health + 100.0)
	_ticks(1)
	check(one.is_downed(), "downed")
	var from: Vector2 = one.global_position
	_sources[0].move = Vector2.LEFT
	_ticks(30)
	var crawled: float = from.distance_to(one.global_position)
	check(crawled > 1.0, "it crawls: %.1f px" % crawled)
	check(crawled < one.mover.speed * 0.5 * Mover.CRAWL_SHARE * 1.5, "slowly: %.1f px in half a second" % crawled)


## The first pillar standing in room `room`.
func _pillar_in(room: int) -> Actor:
	for body: Node in flow.room_props():
		var actor := body as Actor
		if actor != null and actor.room == room and actor.prop != null and String(actor.prop.id).contains("pillar"):
			return actor
	return null
