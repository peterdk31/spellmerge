extends "res://tests/support/suite.gd"
## A carrier whose shot is one pool row (`Carrier.rows_only`: the atom's flying shots, the rune's
## still ones, the orbit's circling ones) makes a launch's rows together and sets them up in one
## `Spells._land_shots` (the atom also spawns them in one `ProjectileManager.spawn_batch`). It must
## leave exactly what one shot at a time leaves: every array of the
## manager and every record of the runtime. Every card is cast, the carriers from a staff and as a
## payload fired by a shot, with cards that give the shots each behaviour, timers (lifecycle
## rows), a staff spread (its random draws), at the desktop cap and at a small one (where a launch
## with no room goes one at a time). The carriers that are not rows only (beam, swing, slam, wall,
## rain, the moves and bodies) are cast too: they must be untouched by the switch.
##
## godot --headless --path . --script res://tests/core/test_spells_land_shots.gd

const SpellsScript := preload("res://core/spells/spells.gd")
const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const EventsScript := preload("res://core/events/events.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")

const DT: float = 1.0 / 60.0
const STEPS: int = 90
## Sets of staffs of real cards, at most 16 each (four seats of four staffs); staff `i` of a set
## is seat `i % 4`'s staff `i / 4`. They cast the carriers from the staff and as a payload
## (`on_expire`, `on_hit`, `timer`) and the cards that mix in interesting ways. Every card not cast
## here is cast by a staff of its own, made from its kind (`_sets`, `_plain_staff`), so a new card
## folder is covered with no edit here.
const SETS: Array = [
	[
		[&"homing", &"bounce", &"spiral", &"split", &"split", &"nova", &"bolt"],
		[&"timer", &"ghost", &"linger", &"growth", &"split", &"nova", &"bolt", &"fire", &"triple", &"bolt"],
		[&"on_expire", &"sticky", &"shield", &"magnet", &"split", &"nova", &"bolt", &"frost", &"deflect", &"return", &"split", &"nova", &"bolt"],
		[&"on_hit", &"zap", &"lightning", &"pierce", &"split", &"nova", &"bolt", &"void", &"chain", &"split", &"atom"],
		[&"timer", &"split", &"split", &"orbit", &"fire", &"bolt"],
		[&"growth", &"homing", &"split", &"rune"],
		[&"on_expire", &"split", &"bolt", &"split", &"orbit"],
		[&"on_expire", &"triple", &"bolt", &"homing", &"split", &"rune"],
		[&"split", &"beam"],
		[&"split", &"swing"],
		[&"split", &"slam"],
		[&"split", &"wall"],
		[&"split", &"rain"],
		[&"on_expire", &"triple", &"bolt", &"split", &"decoy"],
		[&"split", &"familiar"],
		[&"on_hit", &"split", &"bolt", &"split", &"swap"],
	],
	[
		[&"on_expire", &"split", &"bolt", &"split", &"beam"],
		[&"on_expire", &"split", &"bolt", &"split", &"swing"],
		[&"on_expire", &"split", &"bolt", &"slam"],
		[&"on_expire", &"split", &"bolt", &"wall"],
		[&"on_expire", &"split", &"bolt", &"rain"],
		[&"on_expire", &"split", &"bolt", &"familiar"],
		[&"on_expire", &"split", &"bolt", &"split", &"atom"],
		[&"timer", &"split", &"rune", &"split", &"nova", &"bolt"],
		[&"on_hit", &"split", &"orbit", &"split", &"rune"],
		[&"dash"],
		[&"teleport"],
		[&"on_expire", &"bolt", &"dash"],
		[&"on_expire", &"bolt", &"teleport"],
		[&"bigger", &"split", &"split", &"orbit"],
		[&"triple", &"split", &"rune"],
		[&"double", &"split", &"nova", &"bolt"],
	],
	[
		[&"blast", &"split", &"nova", &"bolt"],
		[&"burst", &"split", &"bolt", &"split", &"portal"],
		[&"echo", &"split", &"nova", &"bolt"],
		[&"faster", &"heavy", &"split", &"nova", &"bolt"],
		[&"hold", &"split", &"orbit"],
		[&"mend", &"split", &"nova", &"bolt"],
		[&"mirror", &"split", &"rune", &"penta", &"bolt"],
		[&"on_block", &"shield", &"split", &"orbit", &"split", &"nova", &"bolt"],
		[&"on_cast", &"split", &"nova", &"bolt", &"split", &"bolt"],
		[&"on_hurt", &"split", &"orbit", &"fire", &"nova", &"bolt"],
		[&"on_kill", &"overcharge", &"split", &"nova", &"bolt", &"split", &"rune"],
		[&"on_reaction", &"fire", &"split", &"nova", &"bolt", &"frost", &"split", &"nova", &"bolt"],
		[&"on_wall", &"bounce", &"split", &"nova", &"bolt", &"split", &"atom"],
		[&"possess", &"pull", &"split", &"bolt"],
		[&"reach", &"recoil", &"relay", &"split", &"nova", &"bolt"],
		[&"scatter", &"faster_casting", &"siphon", &"slow", &"sniper", &"storm", &"split", &"nova", &"bolt", &"bolt"],
	],
]
## The spread of the staff they are on, in degrees: every shot draws from the generator.
const SPREAD: float = 12.0
## Scratch, not state: left out of the comparison.
const SCRATCH: Array[String] = ["spells._one_slot"]


## A manager that never has room for a launch's shots together, so every launch goes one shot at
## a time (`Carrier.launch`'s path at the cap); nothing else differs.
class OneAtATime:
	extends ManagerScript

	func has_room_for(_count: int) -> bool:
		return false


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


func test_every_card_is_cast() -> void:
	var cast: Dictionary = {}
	for staffs: Array in _sets():
		check(staffs.size() <= 4 * SpellLimits.STAFFS, "a set fits four seats")
		for cards: Array in staffs:
			for card: StringName in cards:
				cast[card] = true
	var ids: Array = _registry.call("get_ids", &"spells")
	check(ids.size() > 40, "the registry has the cards (%d)" % ids.size())
	for id: StringName in ids:
		check(cast.has(id), "the card '%s' is cast by a staff" % id)


## SETS, then the staffs for the cards SETS does not cast, 16 a set (the last filled up).
func _sets() -> Array:
	var sets: Array = SETS.duplicate()
	var cast: Dictionary = {}
	for staffs: Array in SETS:
		for cards: Array in staffs:
			for card: StringName in cards:
				cast[card] = true
	var extra: Array = []
	for id: StringName in _registry.call("get_ids", &"spells"):
		if cast.has(id):
			continue
		if extra.size() == 4 * SpellLimits.STAFFS:
			sets.append(extra)
			extra = []
		extra.append(_plain_staff(id))
	if not extra.is_empty():
		# The crowd the comparison needs (and that fills a small cap): the first set's staffs.
		var at: int = 0
		while extra.size() < 4 * SpellLimits.STAFFS:
			extra.append(SETS[0][at % SETS[0].size()])
			at += 1
		sets.append(extra)
	return sets


## A staff that casts the card `id` on shots that make a crowd, by its kind: a carrier split; a
## modifier or an infusion on a split bolt; a trigger that fires a nova of bolts from a split
## bolt; a multicast that pulls a nova of bolts and a bolt.
func _plain_staff(id: StringName) -> Array:
	var card: SpellComponent = _registry.call("get_resource", &"spells", id) as SpellComponent
	match card.kind() if card != null else &"":
		&"form":
			return [&"split", id]
		&"trigger":
			return [id, &"split", &"bolt", &"split", &"nova", &"bolt"]
		&"multicast":
			return [id, &"split", &"nova", &"bolt", &"bolt"]
	return [id, &"split", &"bolt"]


func test_a_launch_together_leaves_what_one_at_a_time_leaves() -> void:
	for set_index in _sets().size():
		var one: Dictionary = _run(false, 6000, set_index)
		var together: Dictionary = _run(true, 6000, set_index)
		check(int(one["made"]) > 300, "set %d made a crowd (%d shots)" % [set_index + 1, int(one["made"])])
		_compare(one, together, "set %d" % (set_index + 1))


func test_at_a_small_cap_too() -> void:
	for set_index in _sets().size():
		var one: Dictionary = _run(false, 120, set_index)
		var together: Dictionary = _run(true, 120, set_index)
		check(int(one["dropped"]) > 0, "set %d: the cap dropped shots (%d)" % [set_index + 1, int(one["dropped"])])
		_compare(one, together, "set %d at a small cap" % (set_index + 1))


func _compare(one: Dictionary, together: Dictionary, what: String) -> void:
	check_equal(together.keys().size(), one.keys().size(), what + ": the same arrays")
	var differ: Array[String] = []
	for key: String in one:
		if var_to_bytes(one[key]) != var_to_bytes(together[key]):
			differ.append(key)
	check(differ.is_empty(), "%s: every array the same, byte for byte (differ: %s)" % [what, ", ".join(differ)])


## Cast every staff of set `set_index` from the four wizards and step; returns a snapshot.
func _run(together: bool, cap: int, set_index: int) -> Dictionary:
	var bus := EventsScript.new()
	# One at a time is the path a launch takes when the pool has no room for all its shots.
	var manager: ManagerScript = ManagerScript.new() if together else OneAtATime.new()
	manager.events = bus
	manager.set_cap(cap)
	manager.actors = own(ActorSeats.table()) as ActorSeats.ActorsScript
	var spells := SpellsScript.new()
	spells.registry = _registry
	spells.bind(manager, bus)
	for target in _targets:
		manager.add_target(target, 10.0)
	var staff := StaffBase.new()
	staff.id = &"together"
	staff.slots = 16
	staff.cooldown = 0.0
	staff.spread = SPREAD
	var staffs: Array = _sets()[set_index]
	for seat in 4:
		var origin: Vector2 = _origin(seat)
		manager.set_anchor(seat, origin)
		spells.set_aim(seat, origin, Vector2.RIGHT, origin)
	for i in staffs.size():
		var cards: Array[StringName] = []
		cards.assign(staffs[i])
		spells.install_staff(i % 4, i / 4, spells.compile_staff(cards, staff))
	for step in STEPS:
		if step % 30 == 0:
			for i in staffs.size():
				spells.cast_staff(i % 4, i / 4, _origin(i % 4), Vector2.RIGHT.rotated(0.3 * float(i)), 1000000.0)
		manager.step(DT)
		spells.step(DT)
	var out: Dictionary = {}
	for object: Object in [manager, spells]:
		var prefix: String = "projectiles." if object == manager else "spells."
		for property: Dictionary in object.get_property_list():
			var name: String = property["name"]
			var type: int = property["type"]
			if type >= TYPE_PACKED_BYTE_ARRAY and type <= TYPE_PACKED_VECTOR4_ARRAY or type == TYPE_INT or type == TYPE_FLOAT:
				if not SCRATCH.has(prefix + name):
					out[prefix + name] = object.get(name)
	out["spells._live"] = spells.get("_live")
	out["made"] = int(manager.get("_next_seq"))
	out["dropped"] = manager.dropped
	spells.free()
	manager.free()
	bus.free()
	return out


static func _origin(seat: int) -> Vector2:
	return Vector2(100.0, 60.0 + 50.0 * float(seat))
