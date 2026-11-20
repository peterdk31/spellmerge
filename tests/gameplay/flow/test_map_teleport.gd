extends "res://tests/support/suite.gd"
## A teleport from the held Y map (the owner, 2026-11-19; gameplay/flow/map_teleport.gd): a seat's own
## wizard, standing and in no fight, is told the cleared rooms it may go to (`teleport_rooms_shown`),
## and the command `map_teleport_requested` puts it alone on clear ground in one, materializing there
## (`Actor.spawn`), while nobody else moves; a room not cleared, a wizard in a fight, down or driving
## another body goes nowhere. The same teleport after a snapshot's restore gives the same state. On
## the real autoloads with the split test map (the nave, the antechamber west, the ossuary court east).
const FlowScript := preload("res://gameplay/flow/flow.gd")
const TickScript := preload("res://core/sim/tick.gd")
const BiomeMaps := preload("res://tests/support/biome_maps.gd")
const DT: float = 1.0 / 60.0
const START: int = 0
const WEST: int = 1
const EAST: int = 2
const IMP: StringName = &"ember_imp"

var flow: FlowScript
var events: Node
var tick: TickScript
var input: Node
var registry: Node
var projectiles: Node
## By seat: the rooms last told and their middles.
var _told: Dictionary = {}
var _teleported: Array = []


func before_each() -> void:
	flow = root.get_node("Flow") as FlowScript
	events = root.get_node("Events")
	tick = root.get_node("Tick") as TickScript
	input = root.get_node("PlayerInput")
	registry = root.get_node("Registry")
	projectiles = root.get_node("Projectiles")
	flow.world_parent = own(Node.new()) as Node
	root.add_child(flow.world_parent)
	_told = {}
	_teleported = []
	events.teleport_rooms_shown.connect(_on_told)
	events.wizard_teleported.connect(_on_teleported)


func after_each() -> void:
	events.teleport_rooms_shown.disconnect(_on_told)
	events.wizard_teleported.disconnect(_on_teleported)
	flow.stop_run()
	flow.world_parent = null
	flow.mode = FlowScript.MODE_RUN
	for seat in 4:
		input.leave(seat)
	tick.begin_run()


func _on_told(seat: int, rooms: PackedInt32Array, at: PackedVector2Array) -> void:
	_told[seat] = [rooms, at]


func _on_teleported(seat: int, from: Vector2, to: Vector2) -> void:
	_teleported.append([seat, from, to])


func _start(players: int, east: Array[StringName] = []) -> BiomeMap:
	var map: BiomeMap = BiomeMaps.split(registry)
	for seat in players:
		input.add_virtual_device(seat)
	var fights: Array[RoomFight] = [RoomFight.new(), RoomFight.new(), RoomFight.of(east)]
	check(flow.start_biome(0, map, fights), "the biome starts")
	tick.run(DT)
	return map


func _wizard(seat: int) -> Actor:
	return flow.get_wizard(seat) as Actor


func _into(map: BiomeMap, seat: int, room: int, facing: int) -> void:
	_wizard(seat).global_position = BiomeMaps.socket_point(registry, map, room, facing) - RoomSocket.way(facing) * 24.0
	tick.run(DT)


func _rooms_told(seat: int) -> PackedInt32Array:
	return (_told[seat] as Array)[0] as PackedInt32Array if _told.has(seat) else PackedInt32Array()


func _teleport(seat: int, room: int) -> void:
	events.map_teleport_requested.emit(seat, room)
	tick.run(DT)


func test_a_wizard_is_told_the_cleared_rooms_and_teleports_there_alone() -> void:
	var map: BiomeMap = _start(2)
	check_equal(_rooms_told(0), PackedInt32Array(), "in the start room, the only cleared room: nowhere else to go")
	_into(map, 0, WEST, RoomSocket.Facing.EAST)
	check(flow.life.has(WEST, RoomLife.CLEARED), "the antechamber, with no fight, is cleared as it is entered")
	check_equal(_rooms_told(0), PackedInt32Array([START]), "seat 0 may go back to the start room")
	check_equal((_told[0] as Array)[1], PackedVector2Array([flow.biome.room_rect(START).get_center()]), "told with its middle")
	check_equal(_rooms_told(1), PackedInt32Array([WEST]), "seat 1, in the start room, may go to the antechamber")
	var other_at: Vector2 = _wizard(1).global_position
	var from: Vector2 = _wizard(0).position
	_teleport(0, START)
	var wizard: Actor = _wizard(0)
	check(flow.biome.room_rect(START).has_point(wizard.position), "it stands in the start room")
	check_equal(wizard.room, START, "its place the start room's")
	check(wizard.is_spawning(), "materializing there (Smooth: built out of light, never a jump)")
	check(not projectiles.call(&"grid").circle_blocked(wizard.global_position, FlowScript.PORTAL_GROUND * 0.5, true), "on clear ground")
	check_equal(_teleported.size(), 1, "told once")
	check_equal(_teleported[0][0], 0, "its seat")
	check_equal(_teleported[0][1], from, "where it left")
	check_equal(_wizard(1).global_position, other_at, "nobody else moved (a free split)")
	for _i in int(MapTeleport.ARRIVE_SECONDS / DT) + 2:
		tick.run(DT)
	check(not wizard.is_spawning(), "it stands once it has materialized")


func test_nowhere_while_not_cleared_in_a_fight_or_possessing() -> void:
	var map: BiomeMap = _start(1, [IMP] as Array[StringName])
	_into(map, 0, WEST, RoomSocket.Facing.EAST)
	_teleport(0, EAST)
	check(flow.biome.room_rect(WEST).has_point(_wizard(0).position), "a room not entered, not cleared: it stays")
	check(_teleported.is_empty(), "nothing told")
	# Into the ossuary court: its fight starts and seals it.
	_into(map, 0, EAST, RoomSocket.Facing.WEST)
	check(flow.life.has(EAST, RoomLife.STARTED) and not flow.life.has(EAST, RoomLife.CLEARED), "a fight under way")
	check_equal(_rooms_told(0), PackedInt32Array(), "in a fight: no room to go to")
	_teleport(0, START)
	check(flow.biome.room_rect(EAST).has_point(_wizard(0).position), "in a fight it stays")
	check(not MapTeleport.may_go(_wizard(0), _wizard(0), flow.life, flow.biome.map), "sealed in a fight")
	check(not MapTeleport.may_go(_wizard(0), null, flow.life, flow.biome.map), "driving another body (a possessed foe): never")


func test_a_teleport_is_the_same_after_a_snapshot_restore() -> void:
	var map: BiomeMap = _start(1)
	_into(map, 0, WEST, RoomSocket.Facing.EAST)
	var before := Snapshot.take(tick.state_areas(), root)
	_teleport(0, START)
	for _i in 5:
		tick.run(DT)
	var hash_once: int = SimHash.whole(SimHash.areas(tick.state_areas()))
	var at_once: Vector2 = _wizard(0).position
	check(before.restore(tick.state_areas(), root).is_empty(), "restored to before the teleport")
	check(flow.biome.room_rect(WEST).has_point(_wizard(0).position), "back in the antechamber")
	tick.run(DT)
	check_equal(_rooms_told(0), PackedInt32Array([START]), "told its rooms again after the restore")
	# The restore's own tick stood in for the command's: teleport again on the same tick count.
	before.restore(tick.state_areas(), root)
	_teleport(0, START)
	for _i in 5:
		tick.run(DT)
	check_equal(_wizard(0).position, at_once, "the same place")
	check_equal(SimHash.whole(SimHash.areas(tick.state_areas())), hash_once, "the same state")


func test_nowhere_while_down_or_on_a_bridge_into_a_fight() -> void:
	var map: BiomeMap = _start(1)
	_into(map, 0, WEST, RoomSocket.Facing.EAST)
	var wizard: Actor = _wizard(0)
	check(MapTeleport.may_go(wizard, wizard, flow.life, map), "standing in a cleared room: it may go")
	wizard.spawn(0.5, MapTeleport.ARRIVE_STYLE)
	check(not MapTeleport.may_go(wizard, wizard, flow.life, map), "down (spawning in, falling or downed): never")
	wizard.spawn(0.0, &"")
	# On a bridge whose end room is in a fight.
	var bridge: int = 0
	wizard.room = flow.life.rooms() + bridge
	check(MapTeleport.may_go(wizard, wizard, flow.life, map), "on a bridge with no fight at either end: it may go")
	var end: int = map.end_room(bridge, 1)
	flow.life.set_flag(end, RoomLife.STARTED, true)
	flow.life.set_flag(end, RoomLife.CLEARED, false)
	check(not MapTeleport.may_go(wizard, wizard, flow.life, map), "on a bridge into a fight under way: never")
	check_equal(MapTeleport.rooms_for(wizard, wizard, flow.life, map), 0, "no rooms then")
