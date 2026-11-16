extends "res://tests/support/suite.gd"
## The staffs rework's classes (staffs A3, docs/milestones/M2-staffs.md): `StaffBase` and the
## two shipped staffs, `MulticastBase`, and the new values of the card enums.
const RegistryScript := preload("res://core/registry/registry.gd")


func _registry() -> RegistryScript:
	var registry: RegistryScript = own(RegistryScript.new()) as RegistryScript
	registry.scan()
	return registry


func test_the_starter_heads_and_dev_staffs_are_found_under_wizard() -> void:
	var registry: RegistryScript = _registry()
	var dev: StaffBase = registry.get_resource(&"wizard", &"dev") as StaffBase
	check(dev != null, "the dev staff is found")
	if dev == null:
		return
	check_equal(SpellValidator.check_staff(dev).size(), 0, "the dev staff is valid")
	for id: StringName in [&"curl", &"star", &"moon", &"crystal"]:
		var head: StaffBase = registry.get_resource(&"wizard", id) as StaffBase
		check(head != null, "the %s staff is found" % id)
		if head == null:
			continue
		check_equal(head.slots, 4, "the %s staff has 4 slots (the owner's choice)" % id)
		check(dev.slots > head.slots, "the sandbox staff has more slots than the %s staff" % id)
		check_equal(SpellValidator.check_staff(head).size(), 0, "the %s staff is valid" % id)


func test_a_staff_out_of_range_names_the_field() -> void:
	var staff := StaffBase.new()
	staff.id = &"broken"
	staff.slots = 0
	staff.cooldown = -1.0
	var fields: Array[String] = []
	for problem: Dictionary in SpellValidator.check_staff(staff):
		fields.append(String(problem["field"]))
	check(fields.has("slots"), "0 slots is reported")
	check(fields.has("cooldown"), "a negative cooldown is reported")


func test_a_staff_needs_an_id() -> void:
	var staff := StaffBase.new()
	var rules: Array[String] = []
	for problem: Dictionary in SpellValidator.check_staff(staff):
		rules.append(String(problem["rule"]))
	check(rules.has("required-field"), "a staff without an id is reported")


func test_a_multicast_card_is_its_own_kind() -> void:
	var double := MulticastBase.new()
	check_equal(double.kind(), &"multicast", "the kind")
	check(double.range_problems().is_empty(), "the defaults are in range")
	double.extra_draws = 9
	check(not double.range_problems().is_empty(), "nine extra draws is out of range")


func test_every_new_enum_value_is_inside_the_validator_range() -> void:
	var modifier := ModifierBase.new()
	modifier.behaviour = ModifierBase.Behaviour.RELAY
	modifier.behaviour_strength = 1.0
	check(modifier.range_problems().is_empty(), "the last behaviour is in range")
	var trigger := TriggerBase.new()
	trigger.event = TriggerBase.Event.REACTION
	check(trigger.range_problems().is_empty(), "the last trigger event is in range")
	var carrier_card := CarrierCard.new()
	carrier_card.carrier = &"familiar"
	check(carrier_card.range_problems().is_empty(), "a named carrier is in range")


func test_a_carrier_no_carrier_has_is_refused() -> void:
	# Carriers are named (owner, 2026-10-30): a removed one, as the fissure, is a name no carrier has.
	var carrier_card := CarrierCard.new()
	carrier_card.carrier = &"fissure"
	check(not carrier_card.range_problems().is_empty(), "no card may name a carrier that is gone")
	check_equal(Carriers.of(&"fissure").id(), &"", "and it runs as nothing")

## Items I7: the inventory's arrows know which way is better for every number `ranges()` names,
## and nothing else; a staff compared with another says better, worse or the same.
func test_the_arrows_table_covers_every_number_of_ranges() -> void:
	var base := StaffBase.new()
	var names: Array = base.ranges().keys()
	names.sort()
	var table: Array = StaffBase.BETTER.keys()
	table.sort()
	check_equal(table, names, "one entry for each number ranges() names")
	for field: String in StaffBase.BETTER:
		check([-1, 0, 1].has(StaffBase.BETTER[field]), "%s is better one way or neither" % field)
	var other := StaffBase.new()
	other.slots = base.slots + 2
	other.cooldown = base.cooldown + 0.5
	check_equal(base.compared(other, "slots"), 1, "more slots are better")
	check_equal(base.compared(other, "cooldown"), -1, "a longer cooldown is worse")
	check_equal(base.compared(other, "max_mana"), 0, "the same mana")
	other.tip = base.tip + 4.0
	check_equal(base.compared(other, "tip"), 0, "a longer tip is neither")
