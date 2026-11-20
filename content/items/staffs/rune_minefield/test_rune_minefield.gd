extends "res://tests/support/suite.gd"
## The Rune Minefield (content/items/staffs/rune_minefield), a premade build on the hub's rack:
## three runes scattered at random, each throwing a nova of fire, frost or lightning atoms every 0.5
## s while it waits. Its data is sound, every card it names is a card, and its build wastes none of
## them.
const SpellsScript := preload("res://core/spells/spells.gd")
const RUNE_MINEFIELD: StaffItem = preload("res://content/items/staffs/rune_minefield/rune_minefield.tres")


func test_it_is_sound() -> void:
	check_equal(RUNE_MINEFIELD.problems(), PackedStringArray(), "its data")
	check_equal(RUNE_MINEFIELD.id, &"rune_minefield", "its id is its folder's")
	check_equal(RUNE_MINEFIELD.shown_name(), "Rune Minefield", "its name")
	check_equal(RUNE_MINEFIELD.staff.id, &"dev", "on the dev staff: no four-slot staff holds it")
	var registry: Node = root.get_node("Registry")
	check(registry.call("get_resource", &"items", &"rune_minefield") == RUNE_MINEFIELD, "the registry finds it under items")


func test_every_card_is_a_card_and_none_is_wasted() -> void:
	var registry: Node = root.get_node("Registry")
	for id: StringName in RUNE_MINEFIELD.cards:
		check(registry.call("get_resource", &"spells", id) is SpellComponent, "%s is a card" % id)
	var spells: SpellsScript = own(SpellsScript.new()) as SpellsScript
	spells.registry = registry
	var view: Dictionary = spells.staff_view(RUNE_MINEFIELD.cards, RUNE_MINEFIELD.staff)
	check(not bool(view.get("empty", true)), "it casts")
	check_equal((view.get("casts") as Array).size(), 1, "the whole build is one cast")
	check_equal(view.get("wasted"), {}, "no card is wasted (slot: wasted)")
