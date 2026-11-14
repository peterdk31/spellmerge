extends "res://tests/support/suite.gd"
## The Wild star (items I6, content/items/staffs/wild_star): the hub's rack, a premade staff with a
## crazy build lying there for anyone to take. Its data is sound, every card it names is a card,
## and its build wastes none of them.
##
## godot --headless --path . --script res://content/items/staffs/wild_star/test_wild_star.gd

const SpellsScript := preload("res://core/spells/spells.gd")
const WILD_STAR: StaffItem = preload("res://content/items/staffs/wild_star/wild_star.tres")


func test_it_is_sound() -> void:
	check_equal(WILD_STAR.problems(), PackedStringArray(), "its data")
	check_equal(WILD_STAR.id, &"wild_star", "its id is its folder's")
	check_equal(WILD_STAR.shown_name(), "Wild star", "its name")
	var registry: Node = root.get_node("Registry")
	check(registry.call("get_resource", &"items", &"wild_star") == WILD_STAR, "the registry finds it under items")


func test_every_card_is_a_card_and_none_is_wasted() -> void:
	var registry: Node = root.get_node("Registry")
	for id: StringName in WILD_STAR.cards:
		check(registry.call("get_resource", &"spells", id) is SpellComponent, "%s is a card" % id)
	var spells: SpellsScript = own(SpellsScript.new()) as SpellsScript
	spells.registry = registry
	var view: Dictionary = spells.staff_view(WILD_STAR.cards, WILD_STAR.staff)
	check(not bool(view.get("empty", true)), "it casts")
	check_equal(view.get("wasted"), {}, "no card is wasted (slot: wasted)")
