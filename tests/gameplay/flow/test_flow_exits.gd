extends "res://tests/support/suite.gd"
## The way on through a run (run generation RG4, docs/milestones/run-generation.md, "Exits and the
## way on"), on the real autoloads: a run's room keeps its exits dark while it is under way; cleared,
## one exit a way lights (the rest stay dark) and the view is told the kind behind each; when every
## standing wizard stands in one lit exit, the party goes on to the room that way links to, in the same
## world and run, as it is (health, staffs; a downed wizard up with the revive's health), with the
## depth moving on and nothing of the room left behind; the run's last room lights no exit and wins
## the run; everyone down in a cleared room still ends it; and a snapshot's later room is laid out
## again on a machine that built the first (`rebuild_derived`). The rooms are copies of the crypt
## arena (two exits), pinned as runs of known shape (tests/support/pinned_run.gd).
##
## godot --headless --path . --script res://tests/support/run.gd -- res://tests/gameplay/flow/test_flow_exits.gd
const FlowScript := preload("res://gameplay/flow/flow.gd")
const TickScript := preload("res://core/sim/tick.gd")
const DownedScript := preload("res://gameplay/player/downed.gd")
const PinnedRun := preload("res://tests/support/pinned_run.gd")
const ARENA: RoomBase = preload("res://content/rooms/crypt/arena_01.tres")
const DT: float = 1.0 / 60.0

var flow: FlowScript
var run: Node
var events: Node
var tick: TickScript
var input: Node
var registry: Node
var entered: Array[StringName] = []
var shown: Array = []
var taken: Array[int] = []
## Each `room_built` heard: the room, how many placements its layout still held, whether it was in the tree.
var built: Array = []


func before_each() -> void:
	flow = root.get_node("Flow") as FlowScript
	run = root.get_node("Run")
	events = root.get_node("Events")
	tick = root.get_node("Tick") as TickScript
	input = root.get_node("PlayerInput")
	registry = root.get_node("Registry")
	entered.clear()
	shown.clear()
	taken.clear()
	built.clear()
	events.connect("room_entered", _on_entered)
	events.connect("room_built", _on_built)
	events.connect("room_exits_shown", _on_shown)
	events.connect("run_way_taken", _on_taken)
	flow.world_parent = own(Node.new()) as Node
	root.add_child(flow.world_parent)


func after_each() -> void:
	events.disconnect("room_entered", _on_entered)
	events.disconnect("room_built", _on_built)
	events.disconnect("room_exits_shown", _on_shown)
	events.disconnect("run_way_taken", _on_taken)
	flow.stop_run()
	flow.world_parent = null
	flow.mode = FlowScript.MODE_RUN
	flow.run_id_to_play = FlowScript.DEFAULT_RUN_ID
	for seat in 4:
		input.leave(seat)
	tick.begin_run()


func _on_entered(room: StringName) -> void:
	entered.append(room)


func _on_built(room: StringName, layout: Node) -> void:
	built.append([room, RoomPlaces.read(layout).placed.size(), layout.is_inside_tree(), layout.find_children("*", "RoomZone", true, false).size()])


func _on_shown(at: PackedVector2Array, kinds: Array[StringName]) -> void:
	shown.append([at, kinds])


func _on_taken(way: int) -> void:
	taken.append(way)


## Play a pinned run of copies of the arena, `depth` rows of `width`, with `players` seats.
func _play(depth: int, width: int, players: int = 1) -> void:
	flow.run_id_to_play = PinnedRun.pin(registry, ARENA, &"", RoomKind.FILL_ENEMIES, 16, depth, width)
	for seat in players:
		input.add_virtual_device(seat)
	events.emit_signal("play_requested", 0)


## Every enemy of the room down.
func _clear_room() -> void:
	for enemy: Node in flow.get(&"_enemies").duplicate():
		events.emit_signal("enemy_died", 0, enemy, Vector2.ZERO, -1)


## The room's exits, left to right.
func _exits() -> Array[Actor]:
	return ExitRules.exits_in(flow.contents)


func _states() -> Array[StringName]:
	var found: Array[StringName] = []
	for exit: Actor in _exits():
		found.append(exit.state_triggers.state_id())
	return found


## Stand wizard `seat` in exit `at` (0 = the leftmost).
func _stand_in(seat: int, at: int) -> void:
	var exit: Actor = _exits()[at]
	flow.get_wizard(seat).position = HubRules.area_at(exit.prop, exit.position).get_center()


func _node_now() -> RunNode:
	return run.call("room_now") as RunNode


func test_a_room_under_way_keeps_its_exits_dark_and_a_cleared_one_lights_one_a_way() -> void:
	_play(3, 1)
	check_equal(_exits().size(), 2, "the arena has two exits")
	flow.step(DT)
	check_equal(_states(), [ExitRules.DARK, ExitRules.DARK] as Array[StringName], "dark while the room is under way")
	check_equal(flow.exits.ways.size(), 1, "the room leads to one room")
	_clear_room()
	check_equal(flow.state, FlowScript.State.CLEARED, "cleared")
	check(not flow.is_restarting(), "a room that leads on wins nothing")
	flow.step(DT)
	check_equal(_states(), [ExitRules.DARK, ExitRules.LIT] as Array[StringName], "one way of two exits: the right one lit")
	check(not shown.is_empty() and (shown.back()[0] as PackedVector2Array).size() == 1, "the view is told one lit exit: %s" % [shown])
	if not shown.is_empty():
		check_equal(shown.back()[1], [PinnedRun.room_id(ARENA, 3, 1)] as Array[StringName], "and the kind behind it")


func test_every_standing_wizard_in_a_lit_exit_takes_the_party_on_as_it_is() -> void:
	_play(3, 1, 2)
	var world: Node2D = flow.world
	var first: RunNode = _node_now()
	var one := flow.get_wizard(0) as Actor
	var two := flow.get_wizard(1) as Actor
	one.health.take(30.0)
	var cards: Array[StringName] = one.caster.cards_of(0)
	_clear_room()
	_stand_in(0, 1)
	flow.step(DT)
	check(taken.is_empty() and _node_now() == first, "one wizard of two in the exit: the party waits")
	_stand_in(1, 0)
	flow.step(DT)
	check(taken.is_empty(), "in two exits: nobody picks for anyone")
	_stand_in(1, 1)
	flow.step(DT)
	check_equal(taken, [0] as Array[int], "both in the lit exit: its way is taken")
	var now: RunNode = _node_now()
	check(now != null and now.index == first.links[0], "the run is in the room that way links to")
	check(now != null and now.depth == first.depth + 1, "a row deeper")
	check_equal(entered.size(), 2, "a second room entered")
	check(flow.world == world, "the same world")
	check(flow.get_wizard(0) == one and flow.get_wizard(1) == two, "the same wizards")
	check_equal(one.health.health, one.health.max_health - 30.0, "its health as it was")
	check_equal(one.caster.cards_of(0), cards, "its staffs as they were")
	check_equal(flow.state, FlowScript.State.RUNNING, "the next room is under way")
	check_equal(flow.enemies_left(), now.enemies.size() if now != null else -1, "with the enemies the map puts there")
	check_equal(_states(), [ExitRules.DARK, ExitRules.DARK] as Array[StringName], "its exits dark")
	check(not flow.exits.open, "and closed")
	check(not shown.is_empty() and (shown.back()[0] as PackedVector2Array).is_empty(), "the view is told no exit is lit")
	var spawns: PackedVector2Array = ARENA.places().player_spawns
	check_equal(one.position, spawns[0], "each wizard at its seat's spawn")
	check_equal(two.position, spawns[1], "the second too")


func test_nothing_of_the_room_left_stays() -> void:
	_play(2, 1)
	var layouts: int = _layouts()
	var old_enemies: Array = flow.get(&"_enemies").duplicate()
	var old_exits: Array[Actor] = _exits()
	_clear_room()
	_stand_in(0, 1)
	flow.step(DT)
	check_equal(entered.size(), 2, "on into the next room")
	check_equal(_layouts(), layouts, "one layout in the world")
	for body: Node in old_enemies + old_exits:
		check(not is_instance_valid(body) or not body.is_inside_tree(), "%s of the room left went" % body)
	check_equal(_exits().size(), 2, "the new room's exits stand")
	var cameras: int = 0
	for child: Node in flow.world.get_children():
		cameras += 1 if child is Camera2D else 0
	check_equal(cameras, 1, "one camera")


func _layouts() -> int:
	var count: int = 0
	for child: Node in flow.world.get_children():
		if not (child is Actor) and not (child is Camera2D):
			count += 1
	return count


func test_a_downed_wizard_comes_along_and_stands_up() -> void:
	_play(2, 1, 2)
	_clear_room()
	var two := flow.get_wizard(1) as Actor
	two.health.take(two.health.max_health)
	check(two.is_down(), "seat 1 is down")
	check(not flow.is_restarting(), "one still stands: nothing ends")
	_stand_in(0, 1)
	flow.step(DT)
	check_equal(taken, [0] as Array[int], "every standing wizard is in the exit: the party goes on")
	check(not two.is_down(), "the downed wizard stands up in the next room")
	check_equal(two.health.health, DownedScript.REVIVE_HEALTH, "with the revive's health")


func test_two_ways_lead_to_two_rooms() -> void:
	for at in 2:
		_play(2, 2)
		var first: RunNode = _node_now()
		check_equal(first.links.size(), 2, "the first room leads to two")
		_clear_room()
		flow.step(DT)
		check_equal(_states(), [ExitRules.LIT, ExitRules.LIT] as Array[StringName], "two ways: both exits lit")
		_stand_in(0, at)
		flow.step(DT)
		check(_node_now() != null and _node_now().index == first.links[at], "exit %d leads to link %d" % [at, at])
		flow.stop_run()
		input.leave(0)
		taken.clear()


func test_the_last_room_lights_no_exit_and_wins_the_run() -> void:
	_play(2, 1)
	_clear_room()
	_stand_in(0, 1)
	flow.step(DT)
	check(_node_now() != null and _node_now().links.is_empty(), "in the last room")
	check(flow.exits.ways.is_empty(), "no way on")
	_clear_room()
	check_equal(flow.state, FlowScript.State.CLEARED, "cleared")
	check(flow.is_restarting(), "the run is won: it ends RUN_WON_DELAY later")
	flow.step(DT)
	check_equal(_states(), [ExitRules.DARK, ExitRules.DARK] as Array[StringName], "no exit lights")


func test_everyone_down_in_a_cleared_room_ends_the_run() -> void:
	_play(2, 1)
	_clear_room()
	var one := flow.get_wizard(0) as Actor
	one.health.take(one.health.max_health)
	check(flow.is_restarting(), "everyone down with the exits lit: the run is lost")
	_stand_in(0, 1)
	flow.step(DT)
	check(taken.is_empty(), "a downed wizard in the exit takes nobody on")


## A joining machine builds the room the run started in; a snapshot taken after the party went on
## names a later room. Restored there (core/sim/README.md, "Snapshots"), the game is the snapshot's
## (the same hash), the later room's layout laid out again (`rebuild_derived`). Two templates of one
## kind, so the second room is never the first's (a run four rows deep, which no other test plays: the
## second template stays in the registry).
func test_a_snapshot_taken_in_a_later_room_restores_into_the_first() -> void:
	var run_id: StringName = PinnedRun.pin(registry, ARENA, &"", RoomKind.FILL_ENEMIES, 16, 4, 1)
	var other := ARENA.duplicate() as RoomBase
	other.id = StringName(String(run_id) + "_other")
	other.biome = ARENA.biome
	other.kinds = [run_id] as Array[StringName]
	registry.call("add", &"rooms", other)
	_play(4, 1)
	var first: StringName = flow.room_id
	_clear_room()
	_stand_in(0, 1)
	flow.step(DT)
	var later: StringName = flow.room_id
	check(later != first, "the second room is the other template")
	var snapshot: Snapshot = Snapshot.take(tick.state_areas(), root)
	check_equal(snapshot.problems, PackedStringArray(), "taken without problems")
	var taken_hash: Dictionary = SimHash.areas(tick.state_areas(), StateWalk.new())
	# A joining machine: the run starts again (another seed) until its first room is not the later one.
	for attempt in 32:
		flow.stop_run()
		events.emit_signal("play_requested", 0)
		if flow.room_id != later:
			break
	check(flow.room_id != later and flow.get(&"_layout_of") != later, "the joining machine is in the other room")
	built.clear()
	var problems: PackedStringArray = snapshot.restore(tick.state_areas(), root)
	check_equal(problems, PackedStringArray(), "restored without problems")
	check_equal(flow.room_id, later, "in the later room")
	check_equal(flow.get(&"_layout_of"), later, "its layout laid out again")
	check_equal(_layouts(), 1, "one layout in the world")
	check_equal(SimHash.areas(tick.state_areas(), StateWalk.new()), taken_hash, "the game is the snapshot's")
	# Ground cover GC2: the later room's layout is told (`room_built`), so its cover is worked out.
	check_equal(built.map(func(heard: Array) -> StringName: return heard[0]), [later], "room_built for the later room, once")
	built.clear()
	check_equal(snapshot.restore(tick.state_areas(), root), PackedStringArray(), "restored again, into the room shown")
	check(built.is_empty(), "a restore into the room shown builds nothing and tells nothing")


## Ground cover GC2: each room laid out is told (`room_built`), at a run's start and on going on, before
## it is entered, its placements and zones still in it and not yet in the tree.
func test_each_room_laid_out_is_told_before_it_is_entered() -> void:
	var order: Array[String] = []
	var told_built := func(room: StringName, _layout: Node) -> void: order.append("built " + String(room))
	var told_entered := func(room: StringName) -> void: order.append("entered " + String(room))
	events.connect("room_built", told_built)
	events.connect("room_entered", told_entered)
	_play(2, 1)
	var first: StringName = flow.room_id
	_clear_room()
	_stand_in(0, 1)
	flow.step(DT)
	var second: StringName = flow.room_id
	events.disconnect("room_built", told_built)
	events.disconnect("room_entered", told_entered)
	check_equal(order, ["built " + String(first), "entered " + String(first), "built " + String(second), "entered " + String(second)], "each room built, then entered")
	var placed: int = ARENA.places().placed.size()
	check(placed > 0, "the arena places its exits")
	for heard: Array in built:
		check_equal(heard[1], placed, "%s: its placements still in the layout told" % heard[0])
		check_equal(heard[2], false, "%s: not yet in the tree" % heard[0])
		check_equal(heard[3], ARENA.places().zone_names.size(), "%s: its zones still in it" % heard[0])


## The hub, a room with zones (its prop yard, the lectern's place): `room_built` hands its layout with
## them still in it, as a room's cover fields will be.
func test_the_layout_told_still_holds_its_zones() -> void:
	input.add_virtual_device(0)
	events.emit_signal("hub_requested", 0)
	var hub := registry.get_resource(&"rooms", FlowScript.HUB_ROOM_ID) as RoomBase
	check(hub.places().zone_names.size() >= 2, "the hub has zones")
	check(built.size() == 1 and built[0][0] == FlowScript.HUB_ROOM_ID, "the hub was told")
	if built.size() == 1:
		check_equal(built[0][3], hub.places().zone_names.size(), "its zones still in the layout told")
	check(flow.world.find_children("*", "RoomZone", true, false).is_empty(), "and none left in the room shown")


## A seat that joins while the cleared room's exits are lit, with everyone else down, holds the
## restart off, as in a room under way.
func test_a_joiner_in_a_cleared_room_holds_the_restart_off() -> void:
	_play(2, 1)
	_clear_room()
	var one := flow.get_wizard(0) as Actor
	one.health.take(one.health.max_health)
	check(flow.is_restarting(), "everyone down: the run is lost")
	input.add_virtual_device(1)
	events.emit_signal("player_joined", 1)
	check(flow.get_wizard(1) != null, "the joiner stands")
	check(not flow.is_restarting(), "the restart is off")
	_stand_in(1, 1)
	flow.step(DT)
	check_equal(taken, [0] as Array[int], "the joiner, the one standing, takes the party on")
	check(not one.is_down(), "and the downed wizard comes along, up")


func test_the_room_left_is_told_before_it_goes() -> void:
	var left: Array[int] = []
	var told := func() -> void: left.append(entered.size())
	events.connect("room_left", told)
	_play(2, 1)
	_clear_room()
	_stand_in(0, 1)
	flow.step(DT)
	events.disconnect("room_left", told)
	check_equal(left, [1] as Array[int], "room_left once, before the next room is entered")


## The exits spread the ways over them, left to right, in whole numbers.
func test_ways_spread_over_the_exits() -> void:
	check_equal(ExitRules.exit_of(0, 1, 1), 0, "one way, one exit")
	check_equal(ExitRules.exit_of(0, 1, 2), 1, "one way of two exits: the right")
	check_equal(ExitRules.exit_of(0, 1, 3), 1, "one way of three: the middle")
	check_equal([ExitRules.exit_of(0, 2, 2), ExitRules.exit_of(1, 2, 2)], [0, 1], "two ways, two exits")
	check_equal([ExitRules.exit_of(0, 2, 3), ExitRules.exit_of(1, 2, 3)], [0, 2], "two ways of three: the outer ones")
	var rules := ExitRules.new()
	rules.enter([&"fight", &"boss"] as Array[StringName])
	check_equal(rules.way_of_each(2), PackedInt32Array([-1, -1]), "closed: no exit leads anywhere")
	rules.open = true
	check_equal(rules.way_of_each(2), PackedInt32Array([0, 1]), "open: each exit its way")
	check_equal(rules.way_of_each(1), PackedInt32Array([0]), "more ways than exits: those past them lead nowhere")
