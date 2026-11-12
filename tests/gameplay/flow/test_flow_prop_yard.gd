extends "res://tests/support/suite.gd"
## The hub's prop yard (props W8, docs/milestones/props.md, "W8: the hub on props"): Flow stands every
## prop of the registry that the game's rules know nothing of (no `PropBase.role`) in the room's zone `prop_yard`, in rows
## by id, each in its first state; one that leaves its first state or goes is replaced by a fresh one
## `PropYard.RETURN_SECONDS` later, where it stood. The hub's own stone and altar stand
## where the room puts them, never in the yard. The registry is the game's own (props W9c: the
## exploding barrel, the crate, the fire pit, the arc lodestone and the burial jar).
##
## godot --headless --path . --script res://tests/gameplay/flow/test_flow_prop_yard.gd

const FlowScript := preload("res://gameplay/flow/flow.gd")
const RegistryScript := preload("res://core/registry/registry.gd")

## The yard's props by id (every prop with no role).
const YARD: Array[StringName] = [&"arc_lodestone", &"burial_jar", &"crate", &"exploding_barrel", &"fire_pit"]

const DT: float = 1.0 / 60.0

var flow: FlowScript
var input: Node
## The registry Flow used before the test, and the test's own.
var _real_registry: Node = null
var _registry: RegistryScript = null


func before_each() -> void:
	flow = root.get_node("Flow") as FlowScript
	input = root.get_node("PlayerInput")
	flow.world_parent = own(Node.new()) as Node
	root.add_child(flow.world_parent)
	_real_registry = flow.registry
	_registry = own(RegistryScript.new()) as RegistryScript
	_registry.scan()
	flow.registry = _registry


func after_each() -> void:
	flow.stop_run()
	flow.registry = _real_registry
	flow.world_parent = null
	for index in 4:
		input.leave(index)


func _start() -> void:
	input.add_virtual_device(0)
	root.get_node("Events").emit_signal("hub_requested", 0)


func _room() -> RoomBase:
	return _registry.get_resource(&"rooms", FlowScript.HUB_ROOM_ID) as RoomBase


## The hub's yard (its scene's zone).
func _yard() -> Rect2:
	return _room().places().zone(FlowScript.ZONE_PROP_YARD)


func _ids(bodies: Array[Node]) -> Array[StringName]:
	var ids: Array[StringName] = []
	for body in bodies:
		ids.append((body as Actor).prop.id if body != null else &"")
	return ids


## The yard's body of prop `id` now (null while it is gone).
func _yard_prop(id: StringName) -> Actor:
	return flow.yard_props()[YARD.find(id)] as Actor


## `seconds` of Flow's ticks.
func _run(seconds: float) -> void:
	for i in roundi(seconds / DT):
		flow.step(DT)


func test_the_yard_stands_every_yard_prop_in_rows_by_id() -> void:
	_start()
	check_equal(flow.mode, FlowScript.MODE_HUB, "the hub")
	var yard: Array[Node] = flow.yard_props()
	check_equal(_ids(yard), YARD, "every yard prop by id; never the hub's stone and altar")
	var kinds: Array[PropBase] = []
	for id: StringName in YARD:
		kinds.append(_registry.get_resource(&"props", id) as PropBase)
	var places: PackedVector2Array = PropYard.places(_yard(), kinds)
	for i in yard.size():
		var body := yard[i] as Actor
		check_equal(body.position, places[i], "%s where the yard puts it" % body.prop.id)
		check(_yard().has_point(body.position), "%s in the yard" % body.prop.id)
		check_equal(body.state_triggers.state, 0, "%s in its first state" % body.prop.id)
		check(body.is_inside_tree(), "%s in the world" % body.prop.id)
	flow.stop_run()
	check(flow.yard_props().is_empty(), "the yard goes with the hub")


func test_a_yard_prop_that_leaves_its_first_state_stands_again_fresh() -> void:
	_start()
	var first: Actor = _yard_prop(&"crate")
	var place: Vector2 = first.position
	check(first.state_triggers.enter(&"broken"), "it breaks")
	_run(PropYard.RETURN_SECONDS - 0.5)
	check(_yard_prop(&"crate") == first, "the rubble stands for a while")
	_run(1.0)
	var fresh: Actor = _yard_prop(&"crate")
	check(fresh != null and fresh != first, "a fresh one in its place")
	if fresh == null:
		return
	check_equal(fresh.position, place, "where it stood")
	check_equal(fresh.state_triggers.state, 0, "in its first state")
	check(not first.is_inside_tree(), "the rubble is gone")
	check(_yard_prop(&"burial_jar") != null and _yard_prop(&"burial_jar").state_triggers.state == 0, "the others untouched")
	_run(PropYard.RETURN_SECONDS + 1.0)
	check(_yard_prop(&"crate") == fresh, "a fresh one stays")


func test_a_yard_prop_that_goes_stands_again() -> void:
	_start()
	var first: Actor = _yard_prop(&"exploding_barrel")
	first.die(-1)
	flow.step(DT)
	check(_yard_prop(&"exploding_barrel") == null, "forgotten in the tick it went, never left pointing at a freed body")
	_run(PropYard.RETURN_SECONDS)
	var fresh: Actor = _yard_prop(&"exploding_barrel")
	check(fresh != null and fresh.prop.id == &"exploding_barrel", "a fresh one stands again")


func test_a_room_without_a_yard_stands_none() -> void:
	input.add_virtual_device(0)
	root.get_node("Events").emit_signal("sandbox_requested", 0)
	check_equal(flow.mode, FlowScript.MODE_SANDBOX, "the sandbox")
	check(flow.yard_props().is_empty(), "no yard there")
	check(flow.room_props().is_empty(), "and no props")
