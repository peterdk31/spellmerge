extends "res://tests/support/suite.gd"
## The staffs rework's classes (staffs A3, docs/milestones/M2-staffs.md): `StaffBase` and the
## two shipped staffs, `MulticastBase`, and the new values of the card enums.
##
## godot --headless --path . --script res://tests/core/test_staff_base.gd

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
	staff.recharge = -1.0
	var fields: Array[String] = []
	for problem: Dictionary in SpellValidator.check_staff(staff):
		fields.append(String(problem["field"]))
	check(fields.has("slots"), "0 slots is reported")
	check(fields.has("recharge"), "a negative recharge is reported")


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


func test_only_rain_carries_a_payload() -> void:
	var form := FormBase.new()
	var carrying: Array[StringName] = []
	for carrier: StringName in Carriers.ids():
		form.carrier = carrier
		if form.carries_payload():
			carrying.append(carrier)
	check_equal(carrying, [&"rain"] as Array[StringName], "rain only: a familiar casts what its triggers give it (rules R4 F3)")


func test_every_new_enum_value_is_inside_the_validator_range() -> void:
	var modifier := ModifierBase.new()
	modifier.behaviour = ModifierBase.Behaviour.RELAY
	modifier.behaviour_strength = 1.0
	check(modifier.range_problems().is_empty(), "the last behaviour is in range")
	var trigger := TriggerBase.new()
	trigger.event = TriggerBase.Event.REACTION
	check(trigger.range_problems().is_empty(), "the last trigger event is in range")
	var form := FormBase.new()
	form.carrier = &"familiar"
	check(form.range_problems().is_empty(), "a named carrier is in range")


func test_a_carrier_no_carrier_has_is_refused() -> void:
	# Carriers are named (owner, 2026-10-30): a removed one, as the fissure, is a name no carrier has.
	var form := FormBase.new()
	form.carrier = &"fissure"
	check(not form.range_problems().is_empty(), "no card may name a carrier that is gone")
	check_equal(Carriers.of(&"fissure").id(), &"", "and it runs as nothing")