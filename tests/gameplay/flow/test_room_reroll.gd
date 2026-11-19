extends "res://tests/support/suite.gd"
## A room reroll in play (the owner, 2026-11-19; gameplay/flow/room_rerolls.gd, Flow's
## `_on_room_reroll_requested`): a standing wizard on a bridge near the mouth of an unvisited room is
## told it may reroll it (`room_reroll_shown`); X there (`room_reroll_requested`, a command) spends one
## room reroll of its own currency bag and Flow lays the room the Run area answers with
## (`run_room_reroll_asked`, here a test's answer): the map is the world's state, the room's fight is
## the new one, the room told rerolled (`room_rerolled`) and the world laid again; entering it plays
## its new kind. Refused (`room_reroll_refused`), nothing spent, with none held or no answer; nothing
## for an entered room or away from a mouth. The rerolls made are state, through a snapshot.
const FlowScript := preload("res://gameplay/flow/flow.gd")
const TickScript := preload("res://core/sim/tick.gd")
const BiomeMaps := preload("res://tests/support/biome_maps.gd")

const DT: float = 1.0 / 60.0
const WEST: int = 1
const EAST: int = 2
const BAG: StringName = &"currency"

var flow: FlowScript
var events: Node
var tick: TickScript
var input: Node
var frames: Node
var registry: Node
## What the test's Run answers a reroll asked with (null: nothing valid), and what was heard.
var answer: BiomeMap = null
var asked: Array = []
var shown: Array = []
var refused: Array = []
var rerolled: Array = []
var opened: Array = []


func before_each() -> void:
	flow = root.get_node("Flow") as FlowScript
	events = root.get_node("Events")
	tick = root.get_node("Tick") as TickScript
	input = root.get_node("PlayerInput")
	frames = root.get_node("Frames")
	registry = root.get_node("Registry")
	answer = null
	asked.clear()
	shown.clear()
	refused.clear()
	rerolled.clear()
	opened.clear()
	events.connect("run_room_reroll_asked", _on_asked)
	events.connect("room_reroll_shown", _on_shown)
	events.connect("room_reroll_refused", _on_refused)
	events.connect("room_rerolled", _on_rerolled)
	events.connect("special_room_opened", _on_opened)
	flow.world_parent = own(Node.new()) as Node
	root.add_child(flow.world_parent)


func after_each() -> void:
	events.disconnect("run_room_reroll_asked", _on_asked)
	events.disconnect("room_reroll_shown", _on_shown)
	events.disconnect("room_reroll_refused", _on_refused)
	events.disconnect("room_rerolled", _on_rerolled)
	events.disconnect("special_room_opened", _on_opened)
	flow.stop_run()
	flow.world_parent = null
	flow.mode = FlowScript.MODE_RUN
	for seat in 4:
		frames.call("set_source", seat, null)
		input.leave(seat)
	frames.call("begin_step", DT)
	flow.stop_run()
	tick.begin_run()


## The test's Run: answers after the real one (which holds no run here and answers null).
func _on_asked(map: RefCounted, room: int, roll: int) -> void:
	asked.append([room, roll, (map as BiomeMap).same_as(flow.biome.map)])
	events.emit_signal("run_room_rerolled", room, answer.copy() if answer != null else null, 0, 0, 0.0)


func _on_shown(player: int, at: Vector2, is_shown: bool) -> void:
	shown.append([player, at, is_shown])


func _on_refused(player: int, reason: StringName) -> void:
	refused.append([player, reason])


func _on_rerolled(room: int, kind: StringName) -> void:
	rerolled.append([room, kind])


func _on_opened(room: int, fill: StringName, _table: StringName, _area: Rect2, _spots: PackedVector2Array) -> void:
	opened.append([room, fill])


func _start() -> BiomeMap:
	var map: BiomeMap = BiomeMaps.split(registry)
	input.add_virtual_device(0)
	var fights: Array[RoomFight] = [RoomFight.new(), RoomFight.of([&"ember_imp"] as Array[StringName]), RoomFight.of([&"spitter"] as Array[StringName])]
	check(flow.start_biome(0, map, fights), "the biome starts")
	_ticks(2)
	return map


func _ticks(count: int) -> void:
	for _i in count:
		tick.run(DT)


func _wizard() -> Actor:
	return flow.get_wizard(0) as Actor


func _rerolls() -> int:
	return _wizard().inventory.count_of(BAG, RerollBase.ROOM)


## Just outside room `room`'s mouth facing `facing`, on its bridge.
func _at_mouth(map: BiomeMap, room: int, facing: int) -> Vector2:
	return BiomeMaps.socket_point(registry, map, room, facing) + RoomSocket.way(facing) * 16.0


func _put(at: Vector2) -> void:
	_wizard().global_position = at
	_ticks(2)


func _press_x() -> void:
	events.emit_signal("room_reroll_requested", 0)
	_ticks(1)


## The split map with its west room a fountain (the same template: the test's Run's answer).
func _fountain_west(map: BiomeMap) -> BiomeMap:
	var made: BiomeMap = map.copy()
	made.room_kinds[WEST] = &"fountain"
	made.refill_room(WEST, made.room_scales[WEST] if WEST < made.room_scales.size() else 1.0, [] as Array[StringName])
	return made


func test_every_wizard_starts_with_one_room_reroll() -> void:
	_start()
	check_equal(_rerolls(), 1, "one room reroll in its currency bag (the run stat start_room_rerolls)")
	check_equal(_wizard().inventory.count_of(BAG, RerollBase.REWARD), 1, "and one reward reroll")


func test_x_at_an_unvisited_rooms_mouth_rerolls_it_and_spends_one() -> void:
	var map: BiomeMap = _start()
	_put(_at_mouth(map, WEST, RoomSocket.Facing.EAST))
	check(shown.size() > 0 and shown.back()[0] == 0 and shown.back()[2], "told it may reroll there (%s)" % [shown])
	answer = _fountain_west(flow.biome.map)
	_press_x()
	check_equal(asked, [[WEST, 0, true]], "the Run area asked for that room, the run's first reroll, of the map as it is")
	check_equal(rerolled, [[WEST, &"fountain"]], "told rerolled")
	check_equal(flow.biome.map.room_kinds[WEST], &"fountain", "the map is the new one")
	check(flow.life.fights[WEST].enemies.is_empty(), "its fight the new one's")
	check_equal(_rerolls(), 0, "one room reroll spent")
	check_equal(flow.rerolls.rolls, 1, "the rerolls made are counted")
	check(flow.biome.room_layout(WEST) != null, "the world laid again")
	_put(BiomeMaps.socket_point(registry, flow.biome.map, WEST, RoomSocket.Facing.EAST) - RoomSocket.way(RoomSocket.Facing.EAST) * 24.0)
	check(opened.has([WEST, RoomKind.FILL_FOUNTAIN]), "entered, it plays its new kind (%s)" % [opened])
	check(flow.enemies_left() == 0, "and no foe of the old fight stands")


func test_with_none_held_or_nothing_valid_it_is_refused_and_nothing_spent() -> void:
	var map: BiomeMap = _start()
	_put(_at_mouth(map, WEST, RoomSocket.Facing.EAST))
	answer = null
	_press_x()
	check_equal(refused, [[0, &"no_room"]], "nothing valid: refused")
	check_equal(_rerolls(), 1, "nothing spent")
	check(flow.biome.map.same_as(map), "the map as it was")
	_wizard().inventory.take(BAG, RerollBase.ROOM)
	answer = _fountain_west(map)
	_press_x()
	check_equal(refused.back(), [0, &"none_held"], "none held: refused")
	check(flow.biome.map.same_as(map), "the map as it was")


func test_an_entered_room_or_away_from_a_mouth_is_never_rerolled() -> void:
	var map: BiomeMap = _start()
	answer = _fountain_west(map)
	_put(BiomeMaps.socket_point(registry, map, 0, RoomSocket.Facing.WEST) - RoomSocket.way(RoomSocket.Facing.WEST) * 24.0)
	_press_x()
	check(asked.is_empty() and refused.is_empty(), "inside the start room X does nothing here")
	_put(BiomeMaps.socket_point(registry, map, WEST, RoomSocket.Facing.EAST) - RoomSocket.way(RoomSocket.Facing.EAST) * 24.0)
	check(flow.life.has(WEST, RoomLife.ENTERED), "the west room entered")
	_put(_at_mouth(map, WEST, RoomSocket.Facing.EAST))
	check(shown.is_empty() or not shown.back()[2], "an entered room's mouth tells no reroll")
	_press_x()
	check(asked.is_empty(), "and X there does nothing")
	check_equal(_rerolls(), 1, "nothing spent")


func test_the_rerolled_map_and_count_are_state_through_a_snapshot() -> void:
	var map: BiomeMap = _start()
	_put(_at_mouth(map, WEST, RoomSocket.Facing.EAST))
	var snapshot: Snapshot = Snapshot.take(tick.state_areas(), root)
	check_equal(snapshot.problems, PackedStringArray(), "taken without problems")
	answer = _fountain_west(flow.biome.map)
	_press_x()
	check_equal(flow.rerolls.rolls, 1, "counted")
	var later: Snapshot = Snapshot.take(tick.state_areas(), root)
	check_equal(snapshot.restore(tick.state_areas(), root), PackedStringArray(), "restored without problems")
	check_equal(flow.rerolls.rolls, 0, "the count as it was")
	check_equal(flow.biome.map.room_kinds[WEST], &"fight", "the map as it was, laid again")
	check_equal(_rerolls(), 1, "the room reroll back in the bag")
	check_equal(later.restore(tick.state_areas(), root), PackedStringArray(), "the later one restored")
	check_equal(flow.biome.map.room_kinds[WEST], &"fountain", "the rerolled map, laid")
	check_equal([flow.rerolls.rolls, _rerolls()], [1, 0], "counted and spent")


func test_nobody_inside_and_never_the_boss_room() -> void:
	var map: BiomeMap = _start()
	_put(_at_mouth(map, WEST, RoomSocket.Facing.EAST))
	# A foe walked into the unvisited room: refused, nothing spent.
	var foe := Node2D.new()
	foe.position = flow.biome.room_rect(WEST).get_center()
	flow.world.add_child(foe)
	flow.get(&"_enemies").append(foe)
	answer = _fountain_west(flow.biome.map)
	_press_x()
	check_equal(refused.back() if not refused.is_empty() else [], [0, &"occupied"], "someone inside: refused")
	check_equal(_rerolls(), 1, "nothing spent")
	flow.get(&"_enemies").erase(foe)
	foe.free()
	# The boss's room: no doorway to reroll.
	flow.biome.map.room_kinds[WEST] = &"boss"
	shown.clear()
	_put(_at_mouth(map, WEST, RoomSocket.Facing.EAST) + Vector2(1, 0))
	check(RoomRerolls.doorway_of(_wizard(), flow.biome, flow.life, flow._kind_of).x == RoomRerolls.NONE, "the boss's doorway refuses a room reroll")
	flow.biome.map.room_kinds[WEST] = &"fight"
