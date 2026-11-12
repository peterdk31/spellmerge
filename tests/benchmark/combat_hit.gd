extends SceneTree
## Times Combat's own work for a spell's hit (performance, 2026-11-02): `_on_projectile_hit` on
## one body, called directly (no signal) many times, with nothing but Combat listening to the
## events, so what is timed is Combat's (the hit's listeners, Feel's and the actors' own, are
## timed by `sandbox_storm.gd -- --profile-signals`). Each scenario is a bolt of one element on a
## body with one status on it, as a storm of shots keeps them: a plain bolt, frost on a frozen
## body (the sandbox storm's), fire on a burning one, storm on a hexed one. The body never dies.
## Prints `BENCH: combat hit` lines: the fastest of several passes (the least disturbed), in microseconds a hit.
##
## godot --headless --path . --script res://tests/benchmark/combat_hit.gd [-- --hits=N]

const StaffKit := preload("res://tests/support/staff_kit.gd")
const CombatScript := preload("res://gameplay/combat/combat.gd")
const EventsScript := preload("res://core/events/events.gd")
const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const SpellsScript := preload("res://core/spells/spells.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")

const PASSES: int = 15
## (label, the bolt's element or empty, the status on the body or empty)
const SCENARIOS: Array[Array] = [
	["plain", &"", &""],
	["frost on frozen", &"frost", &"freeze"],
	["fire on burning", &"fire", &"burn"],
	["storm on hexed", &"storm", &"hex"],
]


class FakeRegistry:
	extends Node
	var items: Dictionary = {}

	func get_resource(_folder: StringName, id: StringName) -> Resource:
		return items.get(id)


var _nodes: Array[Node] = []


func _initialize() -> void:
	var hits: int = 5000
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--hits="):
			hits = maxi(arg.substr(7).to_int(), 100)
	await process_frame
	for scenario: Array in SCENARIOS:
		_scenario(scenario[0], scenario[1], scenario[2], hits)
	for node: Node in _nodes:
		if is_instance_valid(node):
			node.free()
	print("COMBAT HIT OK")
	quit(0)


func _scenario(label: String, element: StringName, status: StringName, hits: int) -> void:
	var bus := _own(EventsScript.new()) as EventsScript
	var projectiles := _own(ManagerScript.new()) as ManagerScript
	projectiles.events = bus
	var actors := _own(ActorSeats.table()) as ActorSeats.ActorsScript
	projectiles.actors = actors
	var combat := _own(CombatScript.new()) as CombatScript
	combat.events = bus
	combat.projectiles = projectiles
	var fake := _own(FakeRegistry.new()) as FakeRegistry
	var spells := _own(SpellsScript.new()) as SpellsScript
	spells.registry = fake
	spells.bind(projectiles, bus)
	combat.spells = spells
	combat._ready()
	fake.items[&"bolt"] = load("res://content/spells/carriers/bolt/bolt.tres")
	var cards: Array[StringName] = [&"bolt"]
	if element != &"":
		fake.items[element] = load("res://content/spells/elements/%s/%s.tres" % [element, element])
		cards = [element, &"bolt"]
	var tag: int = StaffKit.build(spells, 0, 0, cards)
	var body := _own(Node2D.new()) as Node2D
	body.position = Vector2(100.0, 100.0)
	root.add_child(body)
	combat.register_actor(body, 1.0e12, 10.0)
	var at: Vector2 = body.position + Vector2(-8.0, 0.0)
	var times := PackedFloat64Array()
	for p in PASSES:
		_put_on(combat, body, status)
		var started: int = Time.get_ticks_usec()
		for i in hits:
			combat._on_projectile_hit(0, body, at, tag, -1)
		times.append(float(Time.get_ticks_usec() - started) / float(hits))
	times.sort()
	print("BENCH: combat hit %s: %.2f us a hit (fastest of %d passes of %d hits)" % [label, times[0], PASSES, hits])


## The status `status` on the body, as long as the passes take.
func _put_on(combat: CombatScript, body: Node2D, status: StringName) -> void:
	match status:
		&"freeze":
			for i in CombatScript.CHILL_STACKS_TO_FREEZE:
				combat.apply_status(1, body, &"chill", 1000.0, 10.0)
		&"":
			pass
		_:
			combat.apply_status(1, body, status, 1000.0, 1.0)


func _own(node: Node) -> Node:
	_nodes.append(node)
	return node
