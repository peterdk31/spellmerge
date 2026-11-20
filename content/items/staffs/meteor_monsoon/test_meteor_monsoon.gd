extends "res://tests/support/suite.gd"
## The Meteor Monsoon (content/items/staffs/meteor_monsoon), a premade build on the hub's rack:
## three novas of blasting fire, frost and lightning bolts falling from the sky at once, three times
## over. Its data is sound, every card it names is a card, and its build wastes none of them.
const SpellsScript := preload("res://core/spells/spells.gd")
const METEOR_MONSOON: StaffItem = preload("res://content/items/staffs/meteor_monsoon/meteor_monsoon.tres")


func test_it_is_sound() -> void:
	check_equal(METEOR_MONSOON.problems(), PackedStringArray(), "its data")
	check_equal(METEOR_MONSOON.id, &"meteor_monsoon", "its id is its folder's")
	check_equal(METEOR_MONSOON.shown_name(), "Meteor Monsoon", "its name")
	check_equal(METEOR_MONSOON.staff.id, &"dev", "on the dev staff: no four-slot staff holds it")
	var registry: Node = root.get_node("Registry")
	check(registry.call("get_resource", &"items", &"meteor_monsoon") == METEOR_MONSOON, "the registry finds it under items")


func test_every_card_is_a_card_and_none_is_wasted() -> void:
	var registry: Node = root.get_node("Registry")
	for id: StringName in METEOR_MONSOON.cards:
		check(registry.call("get_resource", &"spells", id) is SpellComponent, "%s is a card" % id)
	var spells: SpellsScript = own(SpellsScript.new()) as SpellsScript
	spells.registry = registry
	var view: Dictionary = spells.staff_view(METEOR_MONSOON.cards, METEOR_MONSOON.staff)
	check(not bool(view.get("empty", true)), "it casts")
	check_equal((view.get("casts") as Array).size(), 1, "the whole build is one cast")
	check_equal(view.get("wasted"), {}, "no card is wasted (slot: wasted)")
