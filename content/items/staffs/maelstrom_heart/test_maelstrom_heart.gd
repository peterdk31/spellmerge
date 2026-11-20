extends "res://tests/support/suite.gd"
## The Maelstrom Heart (content/items/staffs/maelstrom_heart), a premade build on the hub's rack: a
## slow, growing water and storm bolt that drags foes toward its path and every 0.5 s throws a nova
## of weaving lightning atoms. Its data is sound, every card it names is a card, and its build
## wastes none of them.
const SpellsScript := preload("res://core/spells/spells.gd")
const MAELSTROM_HEART: StaffItem = preload("res://content/items/staffs/maelstrom_heart/maelstrom_heart.tres")


func test_it_is_sound() -> void:
	check_equal(MAELSTROM_HEART.problems(), PackedStringArray(), "its data")
	check_equal(MAELSTROM_HEART.id, &"maelstrom_heart", "its id is its folder's")
	check_equal(MAELSTROM_HEART.shown_name(), "Maelstrom Heart", "its name")
	check_equal(MAELSTROM_HEART.staff.id, &"dev", "on the dev staff: no four-slot staff holds it")
	var registry: Node = root.get_node("Registry")
	check(registry.call("get_resource", &"items", &"maelstrom_heart") == MAELSTROM_HEART, "the registry finds it under items")


func test_every_card_is_a_card_and_none_is_wasted() -> void:
	var registry: Node = root.get_node("Registry")
	for id: StringName in MAELSTROM_HEART.cards:
		check(registry.call("get_resource", &"spells", id) is SpellComponent, "%s is a card" % id)
	var spells: SpellsScript = own(SpellsScript.new()) as SpellsScript
	spells.registry = registry
	var view: Dictionary = spells.staff_view(MAELSTROM_HEART.cards, MAELSTROM_HEART.staff)
	check(not bool(view.get("empty", true)), "it casts")
	check_equal((view.get("casts") as Array).size(), 1, "the whole build is one cast")
	check_equal(view.get("wasted"), {}, "no card is wasted (slot: wasted)")
