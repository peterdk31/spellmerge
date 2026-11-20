extends "res://tests/support/suite.gd"
## The Cascade of Cascades (content/items/staffs/cascade_of_cascades), a premade build on the hub's
## rack: a split frost, fire and lightning bolt at once, each of whose three shots throws a nova of
## atoms as it ends. Its data is sound, every card it names is a card, and its build wastes none of
## them.
const SpellsScript := preload("res://core/spells/spells.gd")
const CASCADE_OF_CASCADES: StaffItem = preload("res://content/items/staffs/cascade_of_cascades/cascade_of_cascades.tres")


func test_it_is_sound() -> void:
	check_equal(CASCADE_OF_CASCADES.problems(), PackedStringArray(), "its data")
	check_equal(CASCADE_OF_CASCADES.id, &"cascade_of_cascades", "its id is its folder's")
	check_equal(CASCADE_OF_CASCADES.shown_name(), "Cascade of Cascades", "its name")
	check_equal(CASCADE_OF_CASCADES.staff.id, &"dev", "on the dev staff: no four-slot staff holds it")
	var registry: Node = root.get_node("Registry")
	check(registry.call("get_resource", &"items", &"cascade_of_cascades") == CASCADE_OF_CASCADES, "the registry finds it under items")


func test_every_card_is_a_card_and_none_is_wasted() -> void:
	var registry: Node = root.get_node("Registry")
	for id: StringName in CASCADE_OF_CASCADES.cards:
		check(registry.call("get_resource", &"spells", id) is SpellComponent, "%s is a card" % id)
	var spells: SpellsScript = own(SpellsScript.new()) as SpellsScript
	spells.registry = registry
	var view: Dictionary = spells.staff_view(CASCADE_OF_CASCADES.cards, CASCADE_OF_CASCADES.staff)
	check(not bool(view.get("empty", true)), "it casts")
	check_equal((view.get("casts") as Array).size(), 1, "the whole build is one cast")
	check_equal(view.get("wasted"), {}, "no card is wasted (slot: wasted)")
