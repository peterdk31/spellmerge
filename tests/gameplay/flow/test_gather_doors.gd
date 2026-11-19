extends "res://tests/support/suite.gd"
## Gather doors and the run's end (connected biomes CB7, docs/milestones/connected-biomes.md,
## decisions 7, 14, 23 and 25; gameplay/flow/gather_doors.gd), on the real autoloads, in CB3's split
## test map (tests/support/biome_maps.gd: the nave the start room 0, the antechamber west, room 1, and
## the ossuary court east, room 2; bridge 0 west, bridge 1 east). The court is the boss's room (its
## kind `boss`: the gate and the portal home) or a challenge room (a kind with a gather door, made
## here). A gated room's mouths are shut to everyone until every standing wizard is on its bridge; the
## gate also waits while a sealed fight holds a wizard, downed or standing, and brings everyone in,
## downed or far away; a gather door brings the standing ones. The boss's room cleared opens the
## portal home, and every standing wizard in it ends the run back in the hub; everyone down does too.
const FlowScript := preload("res://gameplay/flow/flow.gd")
const TickScript := preload("res://core/sim/tick.gd")
const BiomeMaps := preload("res://tests/support/biome_maps.gd")
const IntroBoss := preload("res://tests/support/intro_boss.gd")
const DT: float = 1.0 / 60.0
const IMP: StringName = &"ember_imp"
const WEST: int = 1
const EAST: int = 2
## The test's challenge kind (registered for the test only).
const CHALLENGE: StringName = &"test_gather_challenge"

var flow: FlowScript
var events: Node
var tick: TickScript
var input: Node
var frames: Node
var registry: Node
var projectiles: Node
var told: Array[Array] = []
var entered: Array[int] = []
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
	told.clear()
	entered.clear()
	_sources.clear()
	events.connect("gather_door_shown", _on_told)
	events.connect("room_entered", _on_entered)
	flow.world_parent = own(Node.new()) as Node
	root.add_child(flow.world_parent)
	var kind := RoomKind.new()
	kind.id = CHALLENGE
	kind.door = RoomKind.DOOR_GATHER
	registry.call("add", &"room_kinds", kind)


func after_each() -> void:
	events.disconnect("gather_door_shown", _on_told)
	events.disconnect("room_entered", _on_entered)
	registry.call("remove", &"room_kinds", CHALLENGE)
	flow.stop_run()
	flow.world_parent = null
	flow.mode = FlowScript.MODE_RUN
	SessionRules.machine().boss_intros = 0
	for seat in 4:
		frames.call("set_source", seat, null)
		input.leave(seat)
	frames.call("begin_step", DT)
	flow.stop_run()
	flow.mode = FlowScript.MODE_RUN
	tick.begin_run()


func _on_told(door: int, rule: StringName, area: Rect2, gathered: int, standing: int, held: bool, open: bool) -> void:
	told.append([door, rule, area, gathered, standing, held, open])


func _on_entered(_room_id: StringName, room: int) -> void:
	entered.append(room)


## The split map with the court of kind `east_kind`, `players` seats, the antechamber's and the
## court's fights `west` and `east`.
func _start(players: int, east_kind: StringName, west: Array[StringName], east: Array[StringName]) -> BiomeMap:
	var map: BiomeMap = BiomeMaps.split(registry)
	map.room_kinds[EAST] = east_kind
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


## A point on the east bridge (bridge 1), `out` pixels out of the nave's east socket.
func _on_east_bridge(map: BiomeMap, out: float = 64.0) -> Vector2:
	return BiomeMaps.socket_point(registry, map, 0, RoomSocket.Facing.EAST) + RoomSocket.way(RoomSocket.Facing.EAST) * out


## A point of room `room` `inside` pixels in from its socket facing `facing`.
func _by_socket(map: BiomeMap, room: int, facing: int, inside: float) -> Vector2:
	return BiomeMaps.socket_point(registry, map, room, facing) - RoomSocket.way(facing) * inside


## `actor` downed, and the hit-stop of its fall waited out (the whole game holds for it).
func _down(actor: Actor) -> void:
	actor.health.take(actor.health.health + 100.0)
	_ticks(1)
	while tick.sim.hold_left > 0:
		_ticks(1)
	check(actor.is_downed(), "downed")


## Every enemy of the fight in `room` down and gone.
func _beat(room: int) -> void:
	for enemy: Node in flow.get(&"_enemies").duplicate():
		var body := enemy as Actor
		if body != null and body.room == room:
			events.emit_signal("enemy_died", 0, body, body.position, -1)
			body.get_parent().remove_child(body)
			body.free()


## The last thing the view was told of door `door`, or an empty row.
func _last_told(door: int) -> Array:
	for at in range(told.size() - 1, -1, -1):
		if told[at][0] == door:
			return told[at]
	return []


func test_the_gate_is_shut_to_everyone_until_every_standing_wizard_is_at_it() -> void:
	var map: BiomeMap = _start(2, &"boss", [], [IMP])
	_ticks(1)
	check_equal(flow.gates.doors(), 1, "the court has one door: where the east bridge meets it")
	var mouth: Rect2 = flow.gates.mouth_of(0)
	check(_grid().is_shut_mouth(mouth.get_center()), "the gate's mouth is shut")
	var row: Array = _last_told(0)
	check(not row.is_empty() and row[1] == RoomKind.DOOR_GATE and row[2] == mouth and row[3] == 0 and row[4] == 2 and not row[6], "the view is told the gate, shut, none of two gathered: %s" % [row])
	# One wizard walks into the gate: it stops there.
	var one: Actor = _wizard(0)
	one.global_position = _on_east_bridge(map, 96.0)
	_sources[0].move = Vector2.RIGHT
	_ticks(60)
	check(one.position.x < mouth.position.x and not entered.has(EAST), "a wizard walks no further than the shut gate, entering nothing (at %s)" % one.position)
	check(not flow.gates.is_open(EAST), "one of two at it: shut")
	row = _last_told(0)
	check(not row.is_empty() and row[3] == 1 and row[4] == 2, "one of two gathered: %s" % [row])
	# The second comes: the gate opens and both stand in the court, its fight started.
	_sources[0].move = Vector2.ZERO
	_wizard(1).global_position = _on_east_bridge(map, 48.0)
	_ticks(1)
	check(flow.gates.is_open(EAST), "both at it: open")
	check(not _grid().is_shut_mouth(mouth.get_center()), "its mouth opens")
	check_equal(one.room, EAST, "the first wizard came in")
	check_equal(_wizard(1).room, EAST, "the second too")
	check(entered.has(EAST) and flow.life.has(EAST, RoomLife.SEALED), "the court is entered and its fight seals it")
	var spawns: PackedVector2Array = flow.biome.room_places(EAST).player_spawns
	check(one.position.distance_to(spawns[0]) < 16.0, "each at its seat's spawn: %s and %s" % [one.position, spawns[0]])
	row = _last_told(0)
	check(not row.is_empty() and row[6], "the view is told it opened")


func test_the_gate_waits_while_a_seal_holds_a_wizard_and_then_brings_everyone() -> void:
	var map: BiomeMap = _start(2, &"boss", [IMP], [IMP])
	_ticks(1)
	# Seat 1 walks into the antechamber's fight (it seals) and is downed there.
	var two: Actor = _wizard(1)
	two.global_position = _by_socket(map, WEST, RoomSocket.Facing.EAST, 24.0)
	_ticks(2)
	check(flow.life.has(WEST, RoomLife.SEALED), "the antechamber's fight seals it")
	_down(two)
	# Seat 0, the only one standing, at the gate: held.
	var one: Actor = _wizard(0)
	one.global_position = _on_east_bridge(map)
	_ticks(2)
	check(not flow.gates.is_open(EAST), "a sealed fight holds a downed wizard: the gate stays shut")
	var row: Array = _last_told(0)
	check(not row.is_empty() and row[3] == 1 and row[4] == 1 and row[5], "the view is told it is held, every standing one gathered: %s" % [row])
	# The antechamber cleared: the gate opens and everyone comes, the downed one too.
	_beat(WEST)
	_ticks(2)
	check(flow.life.has(WEST, RoomLife.CLEARED), "the antechamber is cleared")
	check(flow.gates.is_open(EAST), "nothing holds the gate now: it opens")
	check_equal(one.room, EAST, "the one at the gate came in")
	check_equal(two.room, EAST, "the downed one, far away, came in too")
	check(two.is_downed(), "still down: a teammate revives it")


func test_the_gate_waits_for_a_standing_wizard_in_a_seal_too() -> void:
	var map: BiomeMap = _start(2, &"boss", [IMP], [IMP])
	_ticks(1)
	_wizard(1).global_position = _by_socket(map, WEST, RoomSocket.Facing.EAST, 24.0)
	_ticks(2)
	_wizard(0).global_position = _on_east_bridge(map)
	_ticks(2)
	check(not flow.gates.is_open(EAST), "one in a sealed fight, standing: not every standing wizard is at the gate")


func test_a_gather_door_brings_in_the_standing_ones_and_leaves_the_downed() -> void:
	var map: BiomeMap = _start(2, CHALLENGE, [IMP], [IMP])
	_ticks(1)
	check_equal(flow.gates.rule_of(EAST), GatherDoors.RULE_GATHER, "the challenge room's door is a gather door")
	var two: Actor = _wizard(1)
	_down(two)
	var at: Vector2 = two.position
	_wizard(0).global_position = _on_east_bridge(map)
	_ticks(2)
	check(flow.gates.is_open(EAST), "every standing wizard at it: open")
	check_equal(_wizard(0).room, EAST, "the standing one came in")
	check(two.room == 0 and two.position == at, "the downed one stays where it lies")
	check(flow.life.has(EAST, RoomLife.SEALED), "the challenge's fight started and sealed it")
	var row: Array = _last_told(0)
	check(not row.is_empty() and row[1] == RoomKind.DOOR_GATHER and row[6], "the view is told a gather door, open: %s" % [row])


func test_a_gather_door_is_not_held_by_a_seal() -> void:
	var map: BiomeMap = _start(2, CHALLENGE, [IMP], [IMP])
	_ticks(1)
	var two: Actor = _wizard(1)
	two.global_position = _by_socket(map, WEST, RoomSocket.Facing.EAST, 24.0)
	_ticks(2)
	_down(two)
	_wizard(0).global_position = _on_east_bridge(map)
	_ticks(2)
	check(flow.gates.is_open(EAST), "a challenge room's door opens with a teammate down in a sealed fight")


func test_the_bosss_room_cleared_opens_the_portal_home_and_it_ends_the_run() -> void:
	var map: BiomeMap = _start(2, &"boss", [], [IMP])
	_ticks(1)
	_wizard(0).global_position = _on_east_bridge(map)
	_wizard(1).global_position = _on_east_bridge(map, 40.0)
	_ticks(1)
	check(flow.gates.is_open(EAST), "the gate opened")
	check_equal(flow.gates.portal_room, GatherDoors.NONE, "no portal while the boss's room is under way")
	_beat(EAST)
	_ticks(2)
	check(flow.life.has(EAST, RoomLife.CLEARED), "cleared")
	check_equal(flow.gates.portal_room, EAST, "the portal home opens in the boss's room")
	var area: Rect2 = flow.gates.portal_area
	check(flow.biome.room_rect(EAST).encloses(area), "on its floor: %s in %s" % [area, flow.biome.room_rect(EAST)])
	var portal: int = flow.gates.doors()
	var row: Array = _last_told(portal)
	check(not row.is_empty() and row[1] == RoomKind.DOOR_PORTAL_HOME and row[2] == area, "the view is told the portal after the doors: %s" % [row])
	# One in it: nothing; both: the run is won, back to the hub.
	_wizard(0).position = area.get_center()
	_ticks(1)
	check_equal(flow.mode, FlowScript.MODE_RUN, "one of two in the portal: the run goes on")
	_wizard(1).position = area.get_center() + Vector2(4.0, 0.0)
	_ticks(1)
	check(flow.mode != FlowScript.MODE_RUN, "every standing wizard in the portal: the biome's run ends")
	frames.call("begin_step", DT)
	check_equal(flow.mode, FlowScript.MODE_HUB, "and the party is back in the hub")
	check_equal(_last_told(-1).size(), 7, "the view is told every door is forgotten")


func test_everyone_down_in_a_biome_ends_the_run_back_in_the_hub() -> void:
	_start(1, &"boss", [], [IMP])
	_ticks(1)
	_down(_wizard(0))
	_ticks(roundi(FlowScript.RESTART_DELAY / DT) + 2)
	check(flow.mode != FlowScript.MODE_RUN, "everyone down: the biome's run is lost")
	frames.call("begin_step", DT)
	check_equal(flow.mode, FlowScript.MODE_HUB, "back in the hub (decision 14)")


func test_a_boss_in_a_biome_room_opens_its_intro() -> void:
	var data: EnemyBase = IntroBoss.make(registry)
	IntroBoss.register(registry, data)
	SessionRules.machine().boss_intros = 1
	var opened: Array[int] = []
	var on_opened: Callable = func(actor: int, _n: String, _l: String, _i: BossIntro, _p: int, _f: bool) -> void: opened.append(actor)
	events.connect("boss_intro_opened", on_opened)
	var map: BiomeMap = _start(1, &"boss", [], [data.id])
	_ticks(1)
	check(opened.is_empty(), "no intro before the boss's room is entered")
	_wizard(0).global_position = _on_east_bridge(map)
	_ticks(1)
	check_equal(opened.size(), 1, "the boss's room entered through the gate: its intro opens")
	check(flow.boss_intro.opened, "and stands")
	check(tick.sim.stops.has(BossIntroHold.STOP), "the game stops for it")
	# Any seat's A moves it on, past the last page.
	# (The command's handler, as the tick's start applies it; tests/gameplay/flow/test_boss_intro_hold.gd
	# plays the command itself.)
	for page in data.boss_intro.pages():
		flow.call("_on_boss_intro_next_requested", 0, page)
	check(not flow.boss_intro.opened, "its pages turned, it closes")
	events.disconnect("boss_intro_opened", on_opened)
	registry.call("remove", &"bosses", data.id)


func test_a_restore_lays_the_doors_again() -> void:
	var map: BiomeMap = _start(2, &"boss", [], [IMP])
	_ticks(1)
	var snapshot := Snapshot.take(tick.state_areas(), root)
	var mouth: Rect2 = flow.gates.mouth_of(0)
	_wizard(0).global_position = _on_east_bridge(map)
	_wizard(1).global_position = _on_east_bridge(map, 40.0)
	_ticks(1)
	check(flow.gates.is_open(EAST) and not _grid().is_shut_mouth(mouth.get_center()), "opened")
	told.clear()
	var problems: PackedStringArray = snapshot.restore(tick.state_areas(), root)
	check(problems.is_empty(), "restored: %s" % [problems])
	check(not flow.gates.is_open(EAST), "the snapshot's gate is shut")
	check(_grid().is_shut_mouth(mouth.get_center()), "and its mouth is shut in the grid again")
	check(not told.is_empty() and told[0][0] == -1, "the view forgets its doors to be told them again")
	check(not _last_told(0).is_empty() and not _last_told(0)[6], "and is told the gate again at once, shut")


func test_a_room_with_two_doors_counts_each_door_on_its_own() -> void:
	# The nave as a gated room (its two bridges two doors), laid alone: a wizard on the lip of one door
	# is at that door, never at the other.
	var map: BiomeMap = BiomeMaps.split(registry)
	var into: Node2D = own(Node2D.new()) as Node2D
	var world: BiomeWorld = BiomeMaps.laid(registry, projectiles, into, map)
	var doors := GatherDoors.new()
	doors.begin(map, PackedByteArray([GatherDoors.RULE_GATHER, 0, 0]), PackedByteArray([0, 0, 0]))
	doors.lay(world, _grid())
	check_equal(doors.doors(), 2, "two doors to the nave")
	var life := RoomLife.new()
	life.begin(map.rooms(), world.places(), [] as Array[RoomFight])
	var a: Actor = own(Actor.new()) as Actor
	var b: Actor = own(Actor.new()) as Actor
	var lip: Rect2 = doors.mouth_of(0)
	var lip_way: Vector2 = Vector2.LEFT if lip.get_center().x < world.room_rect(0).get_center().x else Vector2.RIGHT
	a.position = lip.get_center() + lip_way * 10.0
	a.room = _grid().place_at(a.position)
	check_equal(a.room, 0, "the lip outside door 0's mouth is the nave's place")
	b.room = map.rooms() + doors.door_bridges[1]
	b.position = world.bridge_rect(doors.door_bridges[1]).get_center()
	var party: Array[Node2D] = [a, b]
	check_equal(doors.count_doors(party, life), GatherDoors.NONE, "one at each door: neither opens")
	b.room = a.room
	b.position = a.position + Vector2(0.0, 6.0)
	check_equal(doors.count_doors(party, life), 0, "both by door 0: the nave opens")
	_grid().clear_places()


func test_a_snapshot_with_the_gate_and_the_portal_open_restores_them() -> void:
	var map: BiomeMap = _start(2, &"boss", [], [IMP])
	_ticks(1)
	var shut := Snapshot.take(tick.state_areas(), root)
	var mouth: Rect2 = flow.gates.mouth_of(0)
	_wizard(0).global_position = _on_east_bridge(map)
	_wizard(1).global_position = _on_east_bridge(map, 40.0)
	_ticks(1)
	_beat(EAST)
	_ticks(2)
	check_equal(flow.gates.portal_room, EAST, "the portal stands")
	var area: Rect2 = flow.gates.portal_area
	var open := Snapshot.take(tick.state_areas(), root)
	check(shut.restore(tick.state_areas(), root).is_empty(), "restored the shut gate")
	check(_grid().is_shut_mouth(mouth.get_center()) and flow.gates.portal_room == GatherDoors.NONE, "shut, no portal")
	told.clear()
	check(open.restore(tick.state_areas(), root).is_empty(), "restored the open gate")
	check(flow.gates.is_open(EAST) and not _grid().is_shut_mouth(mouth.get_center()), "the gate open again, its mouth too")
	check(flow.gates.portal_room == EAST and flow.gates.portal_area == area, "the portal again, where it was")
	check(told.size() >= 3 and told[0][0] == -1 and told[0][6], "the view forgets its doors, to draw what follows as it stands")
	var portal: Array = _last_told(flow.gates.doors())
	check(not portal.is_empty() and portal[2] == area, "and is told the portal at once, before any step: %s" % [portal])
	check(not _last_told(0).is_empty() and _last_told(0)[6], "and the gate, open")
