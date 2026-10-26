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


func test_the_starter_and_dev_staffs_are_found_under_wizard() -> void:
	var registry: RegistryScript = _registry()
	var starter: StaffBase = registry.get_resource(&"wizard", &"starter") as StaffBase
	var dev: StaffBase = registry.get_resource(&"wizard", &"dev") as StaffBase
	check(starter != null, "the starter staff is found")
	check(dev != null, "the dev staff is found")
	if starter == null or dev == null:
		return
	check_equal(starter.slots, 4, "the starter staff has 4 slots (the owner's choice)")
	check(dev.slots > starter.slots, "the sandbox staff has more slots than the starter")
	check_equal(SpellValidator.check_staff(starter).size(), 0, "the starter staff is valid")
	check_equal(SpellValidator.check_staff(dev).size(), 0, "the dev staff is valid")


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


func test_only_rain_and_familiar_carry_a_payload() -> void:
	var form := FormBase.new()
	var carrying: Array[int] = []
	for motion: int in FormBase.Motion.size():
		form.motion = motion as FormBase.Motion
		if form.carries_payload():
			carrying.append(motion)
	check_equal(carrying, [FormBase.Motion.RAIN, FormBase.Motion.FAMILIAR] as Array[int], "rain and familiar only")


func test_every_new_enum_value_is_inside_the_validator_range() -> void:
	var modifier := ModifierBase.new()
	modifier.behaviour = ModifierBase.Behaviour.RELAY
	modifier.behaviour_strength = 1.0
	check(modifier.range_problems().is_empty(), "the last behaviour is in range")
	var trigger := TriggerBase.new()
	trigger.event = TriggerBase.Event.ALLY
	check(trigger.range_problems().is_empty(), "the last trigger event is in range")
	var form := FormBase.new()
	form.motion = FormBase.Motion.FAMILIAR
	check(form.range_problems().is_empty(), "the last motion is in range")
