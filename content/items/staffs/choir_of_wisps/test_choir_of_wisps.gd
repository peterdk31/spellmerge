extends "res://tests/support/suite.gd"
## The Choir of Wisps (content/items/staffs/choir_of_wisps), a premade build on the hub's rack:
## three familiars at once, each casting at a foe that comes near: a homing fire bolt, a frost spray
## and a chaining lightning bolt. Its data is sound, every card it names is a card, and its build
## wastes none of them.
const SpellsScript := preload("res://core/spells/spells.gd")
const CHOIR_OF_WISPS: StaffItem = preload("res://content/items/staffs/choir_of_wisps/choir_of_wisps.tres")


func test_it_is_sound() -> void:
	check_equal(CHOIR_OF_WISPS.problems(), PackedStringArray(), "its data")
	check_equal(CHOIR_OF_WISPS.id, &"choir_of_wisps", "its id is its folder's")
	check_equal(CHOIR_OF_WISPS.shown_name(), "Choir of Wisps", "its name")
	check_equal(CHOIR_OF_WISPS.staff.id, &"dev", "on the dev staff: no four-slot staff holds it")
	var registry: Node = root.get_node("Registry")
	check(registry.call("get_resource", &"items", &"choir_of_wisps") == CHOIR_OF_WISPS, "the registry finds it under items")


func test_every_card_is_a_card_and_none_is_wasted() -> void:
	var registry: Node = root.get_node("Registry")
	for id: StringName in CHOIR_OF_WISPS.cards:
		check(registry.call("get_resource", &"spells", id) is SpellComponent, "%s is a card" % id)
	var spells: SpellsScript = own(SpellsScript.new()) as SpellsScript
	spells.registry = registry
	var view: Dictionary = spells.staff_view(CHOIR_OF_WISPS.cards, CHOIR_OF_WISPS.staff)
	check(not bool(view.get("empty", true)), "it casts")
	check_equal((view.get("casts") as Array).size(), 1, "the whole build is one cast")
	check_equal(view.get("wasted"), {}, "no card is wasted (slot: wasted)")
