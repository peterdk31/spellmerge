extends "res://tests/support/suite.gd"
## A launch of the plain flying carrier (atom, bolt, nova) spawns its shots together
## (`CarrierAtom._launch_together`: `ProjectileManager.spawn_batch`, then `Spells._land_shots`),
## and must leave exactly what one shot at a time leaves (`CarrierAtom.together` false): every
## array of the manager and every record of the runtime, after casts that give the shots each
## behaviour, a timer (a lifecycle row), payloads cast by a shot, and a staff spread (its random
## draws). At a small cap a launch with no room goes one shot at a time, so it is the same too.
##
## godot --headless --path . --script res://tests/core/test_spells_land_shots.gd

const SpellsScript := preload("res://core/spells/spells.gd")
const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const EventsScript := preload("res://core/events/events.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")

const DT: float = 1.0 / 60.0
const STEPS: int = 90
## The staffs cast, one per staff button, all real cards.
const STAFFS: Array = [
	[&"homing", &"bounce", &"spiral", &"split", &"split", &"nova"],
	[&"timer", &"ghost", &"linger", &"growth", &"split", &"nova", &"fire", &"triple", &"bolt"],
	[&"on_expire", &"sticky", &"shield", &"magnet", &"split", &"nova", &"frost", &"deflect", &"return", &"split", &"nova"],
	[&"on_hit", &"zap", &"lightning", &"pierce", &"split", &"nova", &"void", &"chain", &"split", &"atom"],
]
## The spread of the staff they are on, in degrees: every shot draws from the generator.
const SPREAD: float = 12.0


var _registry: Node
## The targets, the same nodes for both runs (the records keep their instance ids).
var _targets: Array[Node2D] = []


func before_each() -> void:
	_registry = own(RegistryScript.new()) as Node
	_registry.call("scan")
	_targets.clear()
	for i in 6:
		var target := own(Node2D.new()) as Node2D
		target.position = Vector2(160.0 + 40.0 * float(i % 3), 80.0 + 60.0 * float(i / 3))
		root.add_child(target)
		_targets.append(target)


func test_a_launch_together_leaves_what_one_at_a_time_leaves() -> void:
	var one: Dictionary = _run(false, 6000)
	var together: Dictionary = _run(true, 6000)
	check(int(one["made"]) > 500, "the casts made a crowd (%d shots)" % int(one["made"]))
	_compare(one, together)


func test_at_a_small_cap_too() -> void:
	var one: Dictionary = _run(false, 300)
	var together: Dictionary = _run(true, 300)
	check(int(one["dropped"]) > 0, "the cap dropped shots (%d)" % int(one["dropped"]))
	_compare(one, together)


func _compare(one: Dictionary, together: Dictionary) -> void:
	check_equal(together.keys().size(), one.keys().size(), "the same arrays")
	var differ: Array[String] = []
	for key: String in one:
		if var_to_bytes(one[key]) != var_to_bytes(together[key]):
			differ.append(key)
	check(differ.is_empty(), "every array the same, byte for byte (differ: %s)" % ", ".join(differ))


## Cast every staff of STAFFS from a wizard and step; returns a snapshot of the state.
func _run(together: bool, cap: int) -> Dictionary:
	var bus := EventsScript.new()
	var manager := ManagerScript.new()
	manager.events = bus
	manager.set_cap(cap)
	manager.actors = own(ActorSeats.table()) as ActorSeats.ActorsScript
	var spells := SpellsScript.new()
	spells.registry = _registry
	spells.bind(manager, bus)
	(spells.carrier(&"atom") as CarrierAtom).together = together
	for target in _targets:
		manager.add_target(target, 10.0)
	var staff := StaffBase.new()
	staff.id = &"together"
	staff.slots = 16
	staff.cast_delay = 0.0
	staff.recharge = 0.0
	staff.spread = SPREAD
	var origin: Vector2 = Vector2(100.0, 120.0)
	manager.set_anchor(0, origin)
	for at in STAFFS.size():
		var cards: Array[StringName] = []
		cards.assign(STAFFS[at])
		spells.install_staff(0, at, spells.compile_staff(cards, staff))
	spells.set_aim(0, origin, Vector2.RIGHT, origin)
	for step in STEPS:
		if step % 30 == 0:
			for at in STAFFS.size():
				spells.cast_staff(0, at, origin, Vector2.RIGHT.rotated(0.3 * float(at)), 1000000.0)
		manager.step(DT)
		spells.step(DT)
	var out: Dictionary = {}
	for object: Object in [manager, spells]:
		var prefix: String = "projectiles." if object == manager else "spells."
		for property: Dictionary in object.get_property_list():
			var name: String = property["name"]
			var type: int = property["type"]
			if type >= TYPE_PACKED_BYTE_ARRAY and type <= TYPE_PACKED_VECTOR4_ARRAY or type == TYPE_INT or type == TYPE_FLOAT:
				out[prefix + name] = object.get(name)
	out["spells._live"] = spells.get("_live")
	out["made"] = int(manager.get("_next_seq"))
	out["dropped"] = manager.dropped
	spells.free()
	manager.free()
	bus.free()
	return out
