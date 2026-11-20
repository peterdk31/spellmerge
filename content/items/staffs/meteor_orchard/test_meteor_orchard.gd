extends "res://tests/support/suite.gd"
## The Meteor Orchard (content/items/staffs/meteor_orchard), a premade build on the hub's rack: a
## rune that calls a big blasting fire bolt down from the sky every 0.5 s while it waits, and a nova
## of frost bolts from the sky when it goes off. Its data is sound, every card it names is a card,
## and its build wastes none of them.
const SpellsScript := preload("res://core/spells/spells.gd")
const METEOR_ORCHARD: StaffItem = preload("res://content/items/staffs/meteor_orchard/meteor_orchard.tres")


func test_it_is_sound() -> void:
	check_equal(METEOR_ORCHARD.problems(), PackedStringArray(), "its data")
	check_equal(METEOR_ORCHARD.id, &"meteor_orchard", "its id is its folder's")
	check_equal(METEOR_ORCHARD.shown_name(), "Meteor Orchard", "its name")
	check_equal(METEOR_ORCHARD.staff.id, &"dev", "on the dev staff: no four-slot staff holds it")
	var registry: Node = root.get_node("Registry")
	check(registry.call("get_resource", &"items", &"meteor_orchard") == METEOR_ORCHARD, "the registry finds it under items")


func test_every_card_is_a_card_and_none_is_wasted() -> void:
	var registry: Node = root.get_node("Registry")
	for id: StringName in METEOR_ORCHARD.cards:
		check(registry.call("get_resource", &"spells", id) is SpellComponent, "%s is a card" % id)
	var spells: SpellsScript = own(SpellsScript.new()) as SpellsScript
	spells.registry = registry
	var view: Dictionary = spells.staff_view(METEOR_ORCHARD.cards, METEOR_ORCHARD.staff)
	check(not bool(view.get("empty", true)), "it casts")
	check_equal((view.get("casts") as Array).size(), 1, "the whole build is one cast")
	check_equal(view.get("wasted"), {}, "no card is wasted (slot: wasted)")
