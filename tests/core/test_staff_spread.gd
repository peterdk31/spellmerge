extends "res://tests/support/suite.gd"
## A staff's `spread` (StaffBase): every shot the staff fires leaves up to `spread` degrees off its
## line, either side, at random from a generator seeded per cast, so the same cast spreads the
## same way. A staff with no spread aims true, the carriers of a multicast included (owner,
## 2026-10-27: spread belongs to the staff, not to the cards).
##
## godot --headless --path . --script res://tests/core/test_staff_spread.gd

const SpellsScript := preload("res://core/spells/spells.gd")
const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const EventsScript := preload("res://core/events/events.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")
const RegistryScript := preload("res://core/registry/registry.gd")

const AIM := Vector2.RIGHT

var _registry: Node
var _spells: SpellsScript
var _mgr: ManagerScript


func before_each() -> void:
	_registry = own(RegistryScript.new()) as Node
	_registry.call("scan")
	_build_runtime()


func _build_runtime() -> void:
	var bus: EventsScript = own(EventsScript.new()) as EventsScript
	_mgr = own(ManagerScript.new()) as ManagerScript
	_mgr.events = bus
	# Four wizards seated 0-3 at actor ids 0-3, as the tests name their casters.
	_mgr.actors = own(ActorSeats.table()) as ActorSeats.ActorsScript
	_spells = own(SpellsScript.new()) as SpellsScript
	_spells.registry = _registry
	_spells.bind(_mgr, bus)


func _staff(spread: float) -> StaffBase:
	var staff := StaffBase.new()
	staff.id = &"test"
	staff.slots = 8
	staff.cast_delay = 0.0
	staff.recharge = 0.0
	staff.spread = spread
	return staff


## Installs `cards` in `player`'s staff 0 on a staff with `spread`, casts it along AIM and returns
## the angles (degrees, off AIM) of the shots in the air.
func _cast_angles(cards: Array[StringName], spread: float, player: int = 0) -> Array[float]:
	_spells.install_staff(player, 0, _spells.compile_staff(cards, _staff(spread)))
	_spells.cast_staff(player, 0, Vector2.ZERO, AIM, 100.0)
	var angles: Array[float] = []
	for slot in _mgr.get_cap():
		if _mgr.is_alive(slot) and SpellTag.caster_of(_mgr.get_tag_of(slot)) == player:
			angles.append(rad_to_deg(AIM.angle_to(_mgr.get_velocity_of(slot))))
	return angles


func test_a_staff_with_no_spread_aims_true() -> void:
	var angles: Array[float] = _cast_angles([&"triple", &"bolt", &"bolt", &"bolt"], 0.0)
	check_equal(angles.size(), 3, "three bolts")
	for angle in angles:
		check(absf(angle) < 0.001, "every bolt along the aim (%s)" % angle)


func test_spread_stays_inside_its_degrees() -> void:
	var angles: Array[float] = _cast_angles([&"split", &"bolt"], 10.0)
	for player in range(1, 4):
		angles.append_array(_cast_angles([&"triple", &"bolt", &"bolt", &"bolt"], 10.0, player))
	check_equal(angles.size(), 12, "twelve shots")
	var fan: float = SpellLimits.SPLIT_SPREAD * 0.5
	for angle in angles:
		check(absf(angle) <= fan + 10.001, "a shot leaves at most 10 degrees off its line (%s)" % angle)


func test_spread_sets_the_carriers_of_one_cast_apart() -> void:
	var angles: Array[float] = _cast_angles([&"triple", &"bolt", &"bolt", &"bolt"], 20.0)
	check_equal(angles.size(), 3, "three bolts")
	if angles.size() == 3:
		check(not (is_equal_approx(angles[0], angles[1]) and is_equal_approx(angles[1], angles[2])), "they do not fly as one: %s" % [angles])


func test_spread_varies_from_cast_to_cast() -> void:
	_spells.install_staff(0, 0, _spells.compile_staff([&"bolt"] as Array[StringName], _staff(20.0)))
	var seen: Dictionary = {}
	for n in 6:
		_spells.cast_staff(0, 0, Vector2.ZERO, AIM, 100.0)
		_spells.step(0.5)
	for slot in _mgr.get_cap():
		if _mgr.is_alive(slot):
			seen[snappedf(AIM.angle_to(_mgr.get_velocity_of(slot)), 0.0001)] = true
	check(seen.size() > 1, "six casts do not all leave the same way: %s" % [seen.keys()])


func test_the_same_cast_spreads_the_same_way() -> void:
	var first: Array[float] = _cast_angles([&"triple", &"bolt", &"bolt", &"bolt"], 20.0)
	_build_runtime()
	var again: Array[float] = _cast_angles([&"triple", &"bolt", &"bolt", &"bolt"], 20.0)
	check_equal(again, first, "a replay of the same cast is the same")


func test_spread_also_turns_a_beam() -> void:
	var off: bool = false
	for player in 4:
		_spells.install_staff(player, 0, _spells.compile_staff([&"beam"] as Array[StringName], _staff(30.0)))
		_spells.cast_staff(player, 0, Vector2.ZERO, AIM, 100.0)
	for at in _spells.beams().beam_slots():
		if _spells.beams().beam_on(at):
			off = off or absf(AIM.angle_to(_spells.beams().beam_end(at) - _spells.beams().beam_origin(at))) > 0.001
	check(off, "four players' beams on a 30 degree staff are not all on the aim")


func test_four_players_spread_on_their_own_staffs() -> void:
	# Player 0's staff aims true, the others spread: one staff's spread is its own.
	var spreads: Array[float] = [0.0, 20.0, 20.0, 20.0]
	for player in 4:
		_spells.install_staff(player, 0, _spells.compile_staff([&"double", &"bolt", &"bolt"] as Array[StringName], _staff(spreads[player])))
	for player in 4:
		_spells.cast_staff(player, 0, Vector2.ZERO, AIM, 100.0)
	var true_aim: int = 0
	var total: int = 0
	for slot in _mgr.get_cap():
		if not _mgr.is_alive(slot):
			continue
		total += 1
		if SpellTag.caster_of(_mgr.get_tag_of(slot)) == 0:
			check(absf(AIM.angle_to(_mgr.get_velocity_of(slot))) < 0.001, "player 0's bolts aim true")
			true_aim += 1
	check_equal(total, 8, "two bolts each")
	check_equal(true_aim, 2, "player 0 has two")


func test_the_dev_and_starter_staffs_aim_true() -> void:
	for id: StringName in [&"dev", &"curl", &"star", &"moon", &"crystal"]:
		var staff: StaffBase = _registry.call("get_resource", &"wizard", id) as StaffBase
		check(staff != null, "the %s staff is found" % id)
		if staff != null:
			check_equal(staff.spread, 0.0, "the %s staff has no spread" % id)


func test_a_spread_factor_of_zero_aims_the_next_carrier_true() -> void:
	# What a sniper card does with `spread_mult`: here set on the compiled carrier, as the
	# compiler does from the modifiers before it.
	var compiled: CompiledStaff = _spells.compile_staff([&"double", &"split", &"bolt", &"split", &"bolt"] as Array[StringName], _staff(30.0))
	compiled.casts[0].group.spells[0].spread_mult = 0.0
	_spells.install_staff(0, 0, compiled)
	_spells.cast_staff(0, 0, Vector2.ZERO, AIM, 100.0)
	var node_true: int = compiled.casts[0].group.spells[0].node
	var fan: float = SpellLimits.SPLIT_SPREAD * 0.5
	var off_line: int = 0
	for slot in _mgr.get_cap():
		if not _mgr.is_alive(slot):
			continue
		var angle: float = absf(rad_to_deg(AIM.angle_to(_mgr.get_velocity_of(slot))))
		var on_fan: bool = angle < 0.001 or absf(angle - fan) < 0.001
		if SpellTag.node_of(_mgr.get_tag_of(slot)) == node_true:
			check(on_fan, "the sharpened carrier's shots keep to their fan (%s)" % angle)
		elif not on_fan:
			off_line += 1
	check(off_line > 0, "the other carrier still spreads")


func test_spread_factors_multiply_in_the_compiler() -> void:
	var sharp := ModifierBase.new()
	sharp.spread_mult = 0.25
	check(sharp.range_problems().is_empty(), "0.25 is in range")
	var wild := ModifierBase.new()
	wild.spread_mult = 5.0
	check(not wild.range_problems().is_empty(), "5 is out of range")
	var spell: CompiledSpell = _spells.compile_staff([&"bolt"] as Array[StringName], _staff(10.0)).casts[0].group.spells[0]
	check_equal(spell.spread_mult, 1.0, "a carrier with no such card keeps the staff's spread")
