extends "res://tests/support/suite.gd"
## The Patient Sentry (crypt rework CR-S, content/items/staffs/patient_sentry): a decoy turret, on
## the hub's rack. Every 0.5 s it fires a homing fire, frost and lightning bolt (the lightning one
## sets off a chaining lightning atom on hit), and when it is hurt a void nova of bolts. Its data is
## sound, every card it names is a card, and its build wastes none of them.
const SpellsScript := preload("res://core/spells/spells.gd")
const SENTRY: StaffItem = preload("res://content/items/staffs/patient_sentry/patient_sentry.tres")


func test_it_is_sound() -> void:
	check_equal(SENTRY.problems(), PackedStringArray(), "its data")
	check_equal(SENTRY.id, &"patient_sentry", "its id is its folder's")
	check_equal(SENTRY.shown_name(), "Patient Sentry", "its name")
	check_equal(SENTRY.staff.id, &"dev", "on the dev staff: no four-slot staff holds it")
	var registry: Node = root.get_node("Registry")
	check(registry.call("get_resource", &"items", &"patient_sentry") == SENTRY, "the registry finds it under items")


func test_every_card_is_a_card_and_none_is_wasted() -> void:
	var registry: Node = root.get_node("Registry")
	for id: StringName in SENTRY.cards:
		check(registry.call("get_resource", &"spells", id) is SpellComponent, "%s is a card" % id)
	var spells: SpellsScript = own(SpellsScript.new()) as SpellsScript
	spells.registry = registry
	var view: Dictionary = spells.staff_view(SENTRY.cards, SENTRY.staff)
	check(not bool(view.get("empty", true)), "it casts")
	check_equal(view.get("wasted"), {}, "no card is wasted (slot: wasted)")
