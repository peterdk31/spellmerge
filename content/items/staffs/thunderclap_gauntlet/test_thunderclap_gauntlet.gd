extends "res://tests/support/suite.gd"
## The Thunderclap Gauntlet (content/items/staffs/thunderclap_gauntlet), a premade build on the
## hub's rack: a lightning swing and a storm slam together: the swing's hits throw a nova of
## chaining lightning atoms, the slam's call a big fire bolt down from the sky. Its data is sound,
## every card it names is a card, and its build wastes none of them.
const SpellsScript := preload("res://core/spells/spells.gd")
const THUNDERCLAP_GAUNTLET: StaffItem = preload("res://content/items/staffs/thunderclap_gauntlet/thunderclap_gauntlet.tres")


func test_it_is_sound() -> void:
	check_equal(THUNDERCLAP_GAUNTLET.problems(), PackedStringArray(), "its data")
	check_equal(THUNDERCLAP_GAUNTLET.id, &"thunderclap_gauntlet", "its id is its folder's")
	check_equal(THUNDERCLAP_GAUNTLET.shown_name(), "Thunderclap Gauntlet", "its name")
	check_equal(THUNDERCLAP_GAUNTLET.staff.id, &"dev", "on the dev staff: no four-slot staff holds it")
	var registry: Node = root.get_node("Registry")
	check(registry.call("get_resource", &"items", &"thunderclap_gauntlet") == THUNDERCLAP_GAUNTLET, "the registry finds it under items")


func test_every_card_is_a_card_and_none_is_wasted() -> void:
	var registry: Node = root.get_node("Registry")
	for id: StringName in THUNDERCLAP_GAUNTLET.cards:
		check(registry.call("get_resource", &"spells", id) is SpellComponent, "%s is a card" % id)
	var spells: SpellsScript = own(SpellsScript.new()) as SpellsScript
	spells.registry = registry
	var view: Dictionary = spells.staff_view(THUNDERCLAP_GAUNTLET.cards, THUNDERCLAP_GAUNTLET.staff)
	check(not bool(view.get("empty", true)), "it casts")
	check_equal((view.get("casts") as Array).size(), 1, "the whole build is one cast")
	check_equal(view.get("wasted"), {}, "no card is wasted (slot: wasted)")
