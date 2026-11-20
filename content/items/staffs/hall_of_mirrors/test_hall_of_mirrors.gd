extends "res://tests/support/suite.gd"
## The Hall of Mirrors (content/items/staffs/hall_of_mirrors), a premade build on the hub's rack:
## three volleys of split frost bolts, fired forward and backward and echoed; each that hits closes
## a ring of five zapping lightning bolts in on where it hit. Its data is sound, every card it names
## is a card, and its build wastes none of them.
const SpellsScript := preload("res://core/spells/spells.gd")
const HALL_OF_MIRRORS: StaffItem = preload("res://content/items/staffs/hall_of_mirrors/hall_of_mirrors.tres")


func test_it_is_sound() -> void:
	check_equal(HALL_OF_MIRRORS.problems(), PackedStringArray(), "its data")
	check_equal(HALL_OF_MIRRORS.id, &"hall_of_mirrors", "its id is its folder's")
	check_equal(HALL_OF_MIRRORS.shown_name(), "Hall of Mirrors", "its name")
	check_equal(HALL_OF_MIRRORS.staff.id, &"dev", "on the dev staff: no four-slot staff holds it")
	var registry: Node = root.get_node("Registry")
	check(registry.call("get_resource", &"items", &"hall_of_mirrors") == HALL_OF_MIRRORS, "the registry finds it under items")


func test_every_card_is_a_card_and_none_is_wasted() -> void:
	var registry: Node = root.get_node("Registry")
	for id: StringName in HALL_OF_MIRRORS.cards:
		check(registry.call("get_resource", &"spells", id) is SpellComponent, "%s is a card" % id)
	var spells: SpellsScript = own(SpellsScript.new()) as SpellsScript
	spells.registry = registry
	var view: Dictionary = spells.staff_view(HALL_OF_MIRRORS.cards, HALL_OF_MIRRORS.staff)
	check(not bool(view.get("empty", true)), "it casts")
	check_equal((view.get("casts") as Array).size(), 1, "the whole build is one cast")
	check_equal(view.get("wasted"), {}, "no card is wasted (slot: wasted)")
