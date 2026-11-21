extends "res://tests/support/suite.gd"
## The owner's three ways into a secret room (2026-11-20; gameplay/flow/secret_runes.gd,
## gameplay/flow/lock_doors.gd): **wall to wall**, the secret room against the nave's west wall, the
## cracked wall in the nave's doorway broken by its element opening straight into it through the
## seam; and **a secret rune**, no bridge at all, a hidden rune in the nave found by its element, then
## teleporting a wizard standing on it to the secret room and back, alone, never from a fight, its
## runes resting a moment after, the same after a snapshot's restore. (The hidden bridge is
## tests/gameplay/flow/test_special_rooms.gd's.) On the real autoloads with hand-made maps
## (tests/support/biome_maps.gd).
const FlowScript := preload("res://gameplay/flow/flow.gd")
const TickScript := preload("res://core/sim/tick.gd")
const BiomeMaps := preload("res://tests/support/biome_maps.gd")
const DT: float = 1.0 / 60.0
const NAVE: int = 0
const SECRET: int = 1

var flow: FlowScript
var events: Node
var tick: TickScript
var input: Node
var registry: Node
var projectiles: Node
var due: Array = []
var rocks: Array = []
var runes_told: Array = []
var teleported: Array = []


func before_each() -> void:
	flow = root.get_node("Flow") as FlowScript
	events = root.get_node("Events")
	tick = root.get_node("Tick") as TickScript
	input = root.get_node("PlayerInput")
	registry = root.get_node("Registry")
	projectiles = root.get_node("Projectiles")
	due.clear()
	rocks.clear()
	runes_told.clear()
	teleported.clear()
	events.room_rewards_due.connect(_on_due)
	events.secret_rock_shown.connect(_on_rock)
	events.secret_rune_shown.connect(_on_rune)
	events.wizard_teleported.connect(_on_teleported)
	flow.world_parent = own(Node.new()) as Node
	root.add_child(flow.world_parent)


func after_each() -> void:
	events.room_rewards_due.disconnect(_on_due)
	events.secret_rock_shown.disconnect(_on_rock)
	events.secret_rune_shown.disconnect(_on_rune)
	events.wizard_teleported.disconnect(_on_teleported)
	flow.stop_run()
	flow.world_parent = null
	flow.mode = FlowScript.MODE_RUN
	for seat in 4:
		input.leave(seat)
	tick.begin_run()


func _on_due(room: int, table: StringName, _type: PackedStringArray, _spots: PackedVector2Array) -> void:
	due.append([room, table])


func _on_rock(rock: int, area: Rect2, element: StringName, broken: bool) -> void:
	rocks.append([rock, area, element, broken])


func _on_rune(rune: int, at: Vector2, back_at: Vector2, element: StringName, found: bool) -> void:
	runes_told.append([rune, at, back_at, element, found])


func _on_teleported(seat: int, from: Vector2, to: Vector2) -> void:
	teleported.append([seat, from, to])


func _start(map: BiomeMap, players: int = 1) -> void:
	for seat in players:
		input.add_virtual_device(seat)
	var fights: Array[RoomFight] = []
	for room in map.rooms():
		fights.append(RoomFight.new())
	check_equal(map.problems(BiomeMaps.shapes(registry, map)), PackedStringArray(), "the hand-made map is sound")
	check(flow.start_biome(0, map, fights), "the biome starts")
	_ticks(1)


func _ticks(count: int) -> void:
	for _i in count:
		tick.run(DT)


func _wizard(seat: int) -> Actor:
	return flow.get_wizard(seat) as Actor


func _grid() -> RoomGrid:
	return projectiles.call(&"grid") as RoomGrid


## Seat `seat`'s wizard stands at `at` (world pixels), found where it is.
func _put(seat: int, at: Vector2) -> void:
	_wizard(seat).global_position = at
	_wizard(seat).find_room()
	_ticks(2)


## The secret room's element touching the floor at `at`, then a step to apply it.
func _touch(element: StringName, at: Vector2) -> void:
	events.emit_signal("floor_touched", 0, element, at, 8.0)
	_ticks(1)


func test_a_wall_to_wall_secret_room_opens_straight_into_it() -> void:
	var map: BiomeMap = BiomeMaps.wall_secret(registry)
	_start(map)
	var nave_rect: Rect2 = flow.biome.room_rect(NAVE)
	var secret_rect: Rect2 = flow.biome.room_rect(SECRET)
	check_equal(nave_rect.position.x, secret_rect.end.x, "the two rooms stand wall to wall: their rectangles touch")
	check_equal(map.bridges(), 1, "joined by the seam alone")
	var element: StringName = flow.locks.element_of(SECRET)
	check(element != &"", "an element rolled for the secret room")
	check(not rocks.is_empty() and not rocks.back()[3], "the view is told the cracked wall as a rock")
	var socket: Vector2 = BiomeMaps.socket_point(registry, map, NAVE, RoomSocket.Facing.WEST)
	var inside_secret: Vector2 = BiomeMaps.socket_point(registry, map, SECRET, RoomSocket.Facing.EAST) + Vector2(-24.0, 0.0)
	check(flow.locks.rock_of(0).intersects(nave_rect), "the cracked wall stands in the nave's doorway")
	check(not _grid().walk_way_clear(socket + Vector2(16.0, 0.0), inside_secret), "shut: the wall holds")
	_touch(element, flow.locks.rock_of(0).get_center())
	check(flow.locks.is_open(SECRET), "its element at the wall breaks it")
	check(rocks.back()[3], "the view is told it broke")
	check(_grid().walk_way_clear(socket + Vector2(16.0, 0.0), inside_secret), "broken, the doorway opens straight into the secret room")
	_put(0, inside_secret)
	check_equal(_wizard(0).room, SECRET, "a wizard through the doorway stands in the secret room")
	check(flow.life.has(SECRET, RoomLife.ENTERED), "and enters it")
	check_equal(due.back(), [SECRET, &"secret"], "its rewards as it is entered")


func test_a_secret_rune_is_found_by_its_element_and_teleports_there_and_back() -> void:
	var map: BiomeMap = BiomeMaps.rune_secret(registry)
	_start(map, 2)
	check_equal(map.bridges(), 0, "no bridge at all")
	check_equal(flow.runes.runes(), 1, "one rune laid")
	var at: Vector2 = flow.runes.spot_of(0, 0)
	var back_at: Vector2 = flow.runes.spot_of(0, 1)
	check(flow.biome.room_rect(NAVE).has_point(at), "its hidden rune lies in the nave")
	check(flow.biome.room_rect(SECRET).has_point(back_at), "the rune leading back in the secret room")
	check(not _grid().circle_blocked(at, 6.0, true) and not _grid().circle_blocked(back_at, 6.0, true), "both on clear ground")
	var element: StringName = flow.locks.element_of(SECRET)
	check(not runes_told.is_empty() and runes_told.back()[0] == 0 and runes_told.back()[3] == element and not runes_told.back()[4], "the view is told the hidden rune and its element")
	check(rocks.is_empty() or rocks.back()[0] == -1, "never as a rock")
	# Hidden: standing on it does nothing.
	_put(0, at)
	check_equal(_wizard(0).room, NAVE, "a rune not found teleports nobody")
	var other: StringName = &"fire" if element != &"fire" else &"frost"
	_touch(other, at)
	check(not flow.locks.is_open(SECRET), "another element finds nothing")
	_touch(element, at + Vector2(300.0, 0.0))
	check(not flow.locks.is_open(SECRET), "its element far away finds nothing")
	_put(0, at + Vector2(0.0, 60.0))
	_touch(element, at + Vector2(10.0, 0.0))
	check(flow.locks.is_open(SECRET), "its element touching the floor at it finds it")
	check(runes_told.back()[4], "the view is told it was found")
	var other_at: Vector2 = _wizard(1).global_position
	_put(0, at)
	_ticks(2)
	var wizard: Actor = _wizard(0)
	check_equal(wizard.room, SECRET, "found, it teleports the wizard standing on it to the secret room")
	check(flow.biome.room_rect(SECRET).has_point(wizard.position), "it stands in the secret room")
	check(wizard.position.distance_to(back_at) > SecretRunes.REACH, "beside the rune leading back, not on it")
	check(wizard.is_spawning(), "materializing there (Smooth)")
	check(not teleported.is_empty() and teleported.back()[0] == 0 and (teleported.back()[1] as Vector2).distance_to(at) <= SecretRunes.REACH, "told where it left: the rune")
	check_equal(_wizard(1).global_position, other_at, "nobody else moved")
	_ticks(int(MapTeleport.ARRIVE_SECONDS / DT) + 2)
	check(flow.life.has(SECRET, RoomLife.ENTERED), "the secret room is entered once the wizard stands")
	check(not due.is_empty() and due.back() == [SECRET, &"secret"], "its rewards as it is entered")
	# It rests a moment: standing on the rune back at once goes nowhere.
	check(flow.runes.rest[0] > 0.0, "its runes still rest")
	wizard.global_position = back_at
	_ticks(2)
	check_equal(wizard.room, SECRET, "a seat's runes rest right after it teleported")
	wizard.global_position = flow.runes.arrival_of(0, 1)
	_ticks(int(SecretRunes.REST / DT) + 2)
	check_equal(wizard.room, SECRET, "off the rune, it stays")
	wizard.global_position = back_at
	_ticks(4)
	check_equal(wizard.room, NAVE, "the rune leading back takes it back to the nave")
	check(wizard.position.distance_to(at) > SecretRunes.REACH, "beside the hidden rune")


func test_a_rune_takes_nobody_out_of_a_fight() -> void:
	var map: BiomeMap = BiomeMaps.rune_secret(registry)
	_start(map)
	var at: Vector2 = flow.runes.spot_of(0, 0)
	_touch(flow.locks.element_of(SECRET), at)
	check(flow.locks.is_open(SECRET), "found")
	flow.life.set_flag(NAVE, RoomLife.SEALED, true)
	_put(0, at)
	check_equal(_wizard(0).room, NAVE, "a sealed room keeps its wizards")
	flow.life.set_flag(NAVE, RoomLife.SEALED, false)
	_ticks(2)
	check_equal(_wizard(0).room, SECRET, "unsealed, it goes")


func test_a_rune_teleport_is_the_same_after_a_snapshot_restore() -> void:
	var map: BiomeMap = BiomeMaps.rune_secret(registry)
	_start(map)
	var at: Vector2 = flow.runes.spot_of(0, 0)
	_touch(flow.locks.element_of(SECRET), at)
	_put(0, at + Vector2(0.0, 40.0))
	var before := Snapshot.take(tick.state_areas(), root)
	_wizard(0).global_position = at
	_ticks(6)
	var hash_once: int = SimHash.whole(SimHash.areas(tick.state_areas()))
	var at_once: Vector2 = _wizard(0).position
	check_equal(_wizard(0).room, SECRET, "teleported")
	check(flow.runes.rest[0] > 0.0, "its seat's runes resting (state)")
	runes_told.clear()
	check(before.restore(tick.state_areas(), root).is_empty(), "restored to before the teleport")
	check_equal(_wizard(0).room, NAVE, "back in the nave")
	check(not runes_told.is_empty() and runes_told[0][0] == -1, "the view forgets the runes")
	check(runes_told.back()[0] == 0 and runes_told.back()[4], "and is told the rune again as it stands, found")
	check_equal(flow.runes.spot_of(0, 0), at, "laid again where it lay")
	before.restore(tick.state_areas(), root)
	_wizard(0).global_position = at
	_ticks(6)
	check_equal(_wizard(0).position, at_once, "the same place")
	check_equal(SimHash.whole(SimHash.areas(tick.state_areas())), hash_once, "the same state")
