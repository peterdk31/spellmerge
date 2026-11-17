extends "res://tests/support/suite.gd"
## A room's enemies come in groups as the room gets quiet (enemy arrivals EA5,
## docs/milestones/enemy-arrivals.md, "Pacing"), on the real autoloads: the arena pinned as a run's one
## room with a pace of its own (tests/support/pinned_run.gd). The first group starts in the room's
## setup and ripples in; the next comes only once the room is quiet, never while it is busy; a group
## stands at the spawns farthest from the wizards; the room is cleared only when the queue is empty and
## nothing stands or arrives; an id that cannot stand is dropped, so the room is never stuck; the
## queue counts as enemies left. Time moves by fixed steps through Flow.step().

const FlowScript := preload("res://gameplay/flow/flow.gd")
const InputManagerScript := preload("res://core/input/input_manager.gd")
const PinnedRun := preload("res://tests/support/pinned_run.gd")
const Arrivals := preload("res://tests/support/arrivals.gd")
const ARENA: RoomBase = preload("res://content/rooms/crypt/arena_01.tres")
const STEP: float = 1.0 / 60.0

var events: Node
var flow: FlowScript
var input: InputManagerScript
var registry: Node
var run: Node
var cleared: int = 0
## The pace pinned: groups of a quarter of the room's budget (4 of 16), the next only once nothing
## stands, bodies 0.1 s apart.
var pace: ArrivalRules


func before_each() -> void:
	events = root.get_node("Events")
	flow = root.get_node("Flow") as FlowScript
	input = root.get_node("PlayerInput") as InputManagerScript
	registry = root.get_node("Registry")
	run = root.get_node("Run")
	pace = ArrivalRules.new()
	pace.group_share = 0.25
	pace.refill_share = 0.0
	pace.stagger = 0.1
	flow.run_id_to_play = PinnedRun.pin(registry, ARENA, &"", RoomKind.FILL_ENEMIES, 16, 1, 1, pace)
	cleared = 0
	events.connect("room_cleared", _on_cleared)


func after_each() -> void:
	events.disconnect("room_cleared", _on_cleared)
	flow.stop_run()
	flow.run_id_to_play = FlowScript.DEFAULT_RUN_ID
	for index in InputManagerScript.MAX_PLAYERS:
		input.leave(index)
	await commands_applied()


func _on_cleared(_room: StringName) -> void:
	cleared += 1


func _start() -> void:
	input.add_virtual_device(0)
	events.emit_signal("play_requested", 0)


func _node() -> RunNode:
	return run.call("room_now") as RunNode


func _steps(count: int) -> void:
	for at in count:
		flow.step(STEP)


## Every enemy standing or arriving killed (as if shot down).
func _kill_standing() -> void:
	for enemy: Node in flow._enemies.duplicate():
		events.emit_signal("enemy_died", 0, enemy, Vector2.ZERO, -1)


func _cost_of(bodies: Array[Node]) -> int:
	var cost: int = 0
	for body: Node in bodies:
		cost += (body as Actor).data.cost
	return cost


func test_the_first_group_starts_in_the_room_s_setup_and_ripples_in() -> void:
	_start()
	var node: RunNode = _node()
	check(node != null and node.enemies.size() > 2, "a room of several enemies")
	if node == null:
		return
	check_equal(node.group, 4, "the pace: a quarter of 16")
	check_equal(flow._enemies.size(), 1, "the first body starts with the room")
	check((flow._enemies[0] as Actor).is_arriving(), "and arrives")
	check_equal(flow.enemies_left(), node.enemies.size(), "the queue counts as enemies left")
	check(not flow.arrivals.is_done(), "the rest are still to come")
	_steps(60)
	var first: Array[Node] = flow._enemies.duplicate()
	var cost: int = _cost_of(first)
	var less_one: int = cost - (first[first.size() - 1] as Actor).data.cost
	check(cost >= 4 and less_one < 4, "the group took enemies until its cost reached 4: %d" % cost)
	check_equal(flow.enemies_left(), node.enemies.size(), "still every one to beat")


func test_the_next_group_comes_only_when_the_room_is_quiet() -> void:
	_start()
	_steps(60)
	var first: int = flow._enemies.size()
	Arrivals.land_bodies(flow._enemies)
	_steps(60 * 20)
	check_equal(flow._enemies.size(), first, "twenty seconds of a busy room: no group")
	check_equal(cleared, 0, "and not cleared")
	_kill_standing()
	check_equal(cleared, 0, "the first group down, more to come: not cleared")
	_steps(1)
	check_equal(flow._enemies.size(), 1, "quiet: the next group's first body starts")
	check((flow._enemies[0] as Actor).is_arriving(), "arriving")


func test_the_room_is_cleared_only_when_every_group_is_down() -> void:
	_start()
	var node: RunNode = _node()
	var total: int = node.enemies.size() if node != null else 0
	var killed: int = 0
	var groups: int = 0
	for round in 60:
		if flow.arrivals.is_done() and flow._enemies.is_empty():
			break
		_steps(60)
		check_equal(cleared, 0, "group %d: not cleared yet" % groups)
		killed += flow._enemies.size()
		groups += 1
		_kill_standing()
	check_equal(killed, total, "every enemy of the list came")
	check(groups >= 2, "in groups: %d" % groups)
	check_equal(cleared, 1, "cleared once, after the last")
	check_equal(flow.enemies_left(), 0, "none left")


## An id the registry has no enemy for is dropped from the queue, so the room is cleared all the same.
func test_an_id_that_cannot_stand_is_dropped() -> void:
	_start()
	flow.arrivals.take_all()
	flow.arrivals.begin([&"no_such_enemy", &"no_such_enemy"] as Array[StringName], PackedInt32Array([1, 1]), 1, 0, 0.1)
	_kill_standing()
	check_equal(cleared, 0, "two still to come")
	_steps(30)
	check(flow.arrivals.is_done(), "both dropped")
	check_equal(cleared, 1, "the room is cleared, not stuck")


## A group's first body starts at the enemy spawn farthest from the wizards standing.
func test_a_group_starts_far_from_the_wizards() -> void:
	_start()
	var wizard: Node2D = flow.get_wizard(0)
	var spawns: PackedVector2Array = flow._places.enemy_spawns
	check(wizard != null and spawns.size() >= 2, "a wizard and spawns")
	if wizard == null or spawns.size() < 2:
		return
	var far: Vector2 = spawns[RoomArrivals.rank(spawns, PackedVector2Array([wizard.position]), Callable())[0]]
	check_equal((flow._enemies[0] as Actor).position, far, "the first body at the farthest spawn")
	# The wizard walks over to that spawn: the next group starts away from it.
	_steps(60)
	_kill_standing()
	wizard.position = far
	_steps(1)
	check(not flow._enemies.is_empty(), "the next group")
	if not flow._enemies.is_empty():
		var at: Vector2 = (flow._enemies[0] as Actor).position
		check(at != far, "not on the wizard: %s" % at)
		var spot: Vector2 = spawns[RoomArrivals.rank(spawns, PackedVector2Array([far]), Callable())[0]]
		check_equal(at, spot, "at the spawn farthest from where it stands now")


## Tests call the rest of the queue at once (`stand_all_now`, the shared helper's).
func test_stand_all_now_calls_every_group() -> void:
	_start()
	var node: RunNode = _node()
	Arrivals.land(flow)
	check(flow.arrivals.is_done(), "nothing still to come")
	check_equal(flow._enemies.size(), node.enemies.size() if node != null else -1, "every enemy stands")
	for enemy: Node in flow._enemies:
		check(not (enemy as Actor).is_arriving(), "landed")
	_kill_standing()
	check_equal(cleared, 1, "cleared")
