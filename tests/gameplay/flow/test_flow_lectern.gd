extends "res://tests/support/suite.gd"
## The hub's lectern (run generation RG7, docs/milestones/run-generation.md, "The lectern"): the hub
## stands the registry's `start_lectern` prop in its zone of that name; the seats whose wizards stand
## at it are told (`lectern_changed`); the command `start_depth_picked` from a seat standing there is
## the party's one start (hub state, told with the depths offered, `start_depth_changed`); the stone's
## run is the same generated run, entered at the first room of that depth's row; a hub started anew
## forgets it; and with no lectern in the registry nothing stands, nothing can be picked and the run
## starts in its first room. Uses the real autoloads; commands are applied as a tick's start applies
## them (`Events.apply_command`).

const FlowScript := preload("res://gameplay/flow/flow.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
const PinnedRun := preload("res://tests/support/pinned_run.gd")
const ARENA: RoomBase = preload("res://content/rooms/crypt/arena_01.tres")

const DT: float = 1.0 / 60.0

var flow: FlowScript
var run: Node
var input: Node
var events: Node
var frames: Node
var registry: RegistryScript
## Every `lectern_changed` and `start_depth_changed` told.
var seats_told: Array[int] = []
var starts_told: Array[Vector2i] = []


func before_each() -> void:
	flow = root.get_node("Flow") as FlowScript
	run = root.get_node("Run")
	input = root.get_node("PlayerInput")
	events = root.get_node("Events")
	frames = root.get_node("Frames")
	registry = root.get_node("Registry") as RegistryScript
	flow.world_parent = own(Node.new()) as Node
	root.add_child(flow.world_parent)
	seats_told = []
	starts_told = []
	events.connect("lectern_changed", _on_seats)
	events.connect("start_depth_changed", _on_start)


func after_each() -> void:
	events.disconnect("lectern_changed", _on_seats)
	events.disconnect("start_depth_changed", _on_start)
	flow.registry = registry
	flow.run_id_to_play = FlowScript.DEFAULT_RUN_ID
	flow.stop_run()
	flow.world_parent = null
	for seat in 4:
		input.leave(seat)
	await commands_applied()


func _on_seats(seats: int) -> void:
	seats_told.append(seats)


func _on_start(depth: int, depths: int) -> void:
	starts_told.append(Vector2i(depth, depths))


func _start(seats: Array) -> void:
	for seat: int in seats:
		input.add_virtual_device(seat)
	events.emit_signal("hub_requested", seats[0])


func _hub() -> RoomBase:
	return registry.get_resource(&"rooms", FlowScript.HUB_ROOM_ID) as RoomBase


func _lecterns() -> Array[Actor]:
	return flow.contents.with_role(HubRules.ROLE_START_LECTERN)


## Stand seat `seat`'s wizard at the lectern (or well away from it).
func _at_lectern(seat: int, at: bool = true) -> void:
	var lectern: Actor = _lecterns()[0]
	var area: Rect2 = HubRules.area_at(lectern.prop, lectern.position)
	flow.get_wizard(seat).position = Vector2(area.get_center().x - 8.0 + 16.0 * seat, area.end.y - 6.0) if at else area.get_center() + Vector2(0.0, 200.0)


func _pick(seat: int, depth: int) -> void:
	events.call("apply_command", &"start_depth_picked", [seat, depth])


## Every wizard onto the stone, and seat 0's A there: the run from the stone starts.
func _go(seats: int) -> void:
	var centre: Vector2 = HubRules.area_of(_hub().places(), HubRules.ROLE_RUN_START).get_center()
	for seat in seats:
		flow.get_wizard(seat).position = centre + Vector2(-16.0 + 16.0 * seat, 8.0)
	flow.step(DT)
	events.call("apply_command", &"run_requested", [0])


func test_the_hub_stands_the_lectern_in_its_zone() -> void:
	_start([0])
	var lecterns: Array[Actor] = _lecterns()
	check_equal(lecterns.size(), 1, "one lectern stands in the hub")
	if lecterns.is_empty():
		return
	var zone: Rect2 = _hub().places().zone(HubRules.ROLE_START_LECTERN)
	check(zone.has_area(), "the hub has a zone for it")
	check_equal(lecterns[0].position, zone.get_center().floor(), "its feet at the zone's middle")
	check_equal(lecterns[0].prop.id, &"start_lectern", "the registry's lectern")
	for body: Node in flow.yard_props():
		check((body as Actor).prop.role == &"", "never in the prop yard")


func test_the_seats_at_the_lectern_are_told_as_they_change() -> void:
	_start([0, 2])
	flow.step(DT)
	check(not seats_told.any(func(seats: int) -> bool: return seats != 0), "nobody at it")
	seats_told.clear()
	_at_lectern(2)
	flow.step(DT)
	flow.step(DT)
	check_equal(seats_told, [0b0100] as Array[int], "seat 2 steps up: told once, by its seat")
	_at_lectern(0)
	flow.step(DT)
	check_equal(seats_told.back(), 0b0101, "both")
	_at_lectern(2, false)
	flow.step(DT)
	check_equal(seats_told.back(), 0b0001, "one walks off")
	flow.stop_run()
	check_equal(seats_told.back(), 0, "out of the hub nobody is at it")


func test_a_pick_at_the_lectern_is_the_partys_start() -> void:
	_start([0, 1])
	flow.step(DT)
	var depths: int = (registry.get_resource(&"runs", FlowScript.DEFAULT_RUN_ID) as RunDefinition).start_depths()
	check(depths >= 2, "the crypt offers its depths (%d)" % depths)
	check_equal(starts_told.back(), Vector2i(0, depths), "the hub starts at the first room, its depths told")
	_pick(1, 2)
	flow.step(DT)
	check_equal(flow.hub.start_depth, 0, "a seat away from the lectern picks nothing")
	_at_lectern(1)
	flow.step(DT)
	_pick(1, 2)
	flow.step(DT)
	check_equal(flow.hub.start_depth, 2, "a seat at it picks the party's start")
	check_equal(starts_told.back(), Vector2i(2, depths), "told")
	_pick(1, 99)
	flow.step(DT)
	check_equal(flow.hub.start_depth, depths - 1, "past the last: the last, the boss's")
	_pick(1, -4)
	flow.step(DT)
	check_equal(flow.hub.start_depth, 0, "before the first: the first")
	_pick(1, 3)
	flow.step(DT)
	events.emit_signal("hub_requested", 0)
	flow.step(DT)
	check_equal(flow.hub.start_depth, 0, "the hub started anew forgets it")
	check_equal(starts_told.back(), Vector2i(0, depths), "and says so")


## The stone's run is generated as always and entered at the first room of the picked depth's row;
## the boss's pick, the last, enters the last row; the first pick, the first room.
func test_the_stone_run_starts_at_the_picked_depth() -> void:
	flow.run_id_to_play = PinnedRun.pin(registry, ARENA, &"", RoomKind.FILL_ENEMIES, 16, 4, 2)
	for case: Array in [[0, 0], [2, 2], [3, 3]]:
		_start([0, 1])
		flow.step(DT)
		_at_lectern(1)
		flow.step(DT)
		_pick(1, case[0])
		flow.step(DT)
		_go(2)
		check_equal(flow.mode, FlowScript.MODE_RUN, "pick %d: the run from the stone" % case[0])
		var map: RunMap = run.get(&"map") as RunMap
		var at: RunNode = run.call("room_now") as RunNode
		check(map != null and at != null, "pick %d: a map and a room" % case[0])
		if map == null or at == null:
			flow.stop_run()
			continue
		check_equal(map.rows(), 4, "pick %d: the whole map is made" % case[0])
		check_equal(at.row, case[1], "pick %d: entered in row %d" % [case[0], case[1]])
		check_equal(at.index, map.row(case[1])[0].index, "pick %d: its first room" % case[0])
		check_equal(flow.room_id, at.room, "pick %d: Flow built that room" % case[0])
		flow.stop_run()


## Only the stone's run starts at the pick: a run begun from the main menu starts in its first room.
func test_a_run_not_from_the_stone_starts_in_its_first_room() -> void:
	_start([0])
	flow.step(DT)
	_at_lectern(0)
	flow.step(DT)
	_pick(0, 2)
	flow.step(DT)
	flow.stop_run()
	flow.run_id_to_play = PinnedRun.pin(registry, ARENA, &"", RoomKind.FILL_ENEMIES, 16, 4, 2)
	events.emit_signal("play_requested", 0)
	var at: RunNode = run.call("room_now") as RunNode
	check(at != null and at.row == 0 and at.index == 0, "Play's run: its first room")


## Deleting the lectern's folder: the hub stands none, nobody is ever at one, a pick is refused and
## the stone's run starts in its first room.
func test_with_no_lectern_nothing_is_picked() -> void:
	var without := own(RegistryScript.new()) as RegistryScript
	for folder: StringName in registry.get_folders():
		for found: Resource in registry.get_all(folder):
			if folder == &"props" and (found as PropBase).role == HubRules.ROLE_START_LECTERN:
				continue
			without.add(folder, found)
	flow.registry = without
	flow.run_id_to_play = PinnedRun.pin(registry, ARENA, &"", RoomKind.FILL_ENEMIES, 16, 4, 2)
	PinnedRun.pin(without, ARENA, &"", RoomKind.FILL_ENEMIES, 16, 4, 2)
	_start([0])
	flow.step(DT)
	check(_lecterns().is_empty(), "no lectern stands")
	check_equal(flow.state, FlowScript.State.RUNNING, "the hub stands all the same")
	var zone: Rect2 = _hub().places().zone(HubRules.ROLE_START_LECTERN)
	flow.get_wizard(0).position = zone.get_center() + Vector2(0.0, 16.0)
	flow.step(DT)
	_pick(0, 2)
	flow.step(DT)
	check_equal(flow.hub.start_depth, 0, "nothing picked")
	check(not seats_told.any(func(seats: int) -> bool: return seats != 0), "nobody was ever at a lectern")
	_go(1)
	var at: RunNode = run.call("room_now") as RunNode
	check(at != null and at.index == 0, "the stone's run starts in its first room")
