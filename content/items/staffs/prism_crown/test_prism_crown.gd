extends "res://tests/support/suite.gd"
## The Prism Crown (content/items/staffs/prism_crown), a premade build on the hub's rack: a big slow
## lightning bolt circles its caster, and every 0.5 s five chaining lightning beams close in on it
## from a ring. Its data is sound, every card it names is a card, and its build wastes none of them.
const SpellsScript := preload("res://core/spells/spells.gd")
const PRISM_CROWN: StaffItem = preload("res://content/items/staffs/prism_crown/prism_crown.tres")


func test_it_is_sound() -> void:
	check_equal(PRISM_CROWN.problems(), PackedStringArray(), "its data")
	check_equal(PRISM_CROWN.id, &"prism_crown", "its id is its folder's")
	check_equal(PRISM_CROWN.shown_name(), "Prism Crown", "its name")
	check_equal(PRISM_CROWN.staff.id, &"dev", "on the dev staff: no four-slot staff holds it")
	var registry: Node = root.get_node("Registry")
	check(registry.call("get_resource", &"items", &"prism_crown") == PRISM_CROWN, "the registry finds it under items")


func test_every_card_is_a_card_and_none_is_wasted() -> void:
	var registry: Node = root.get_node("Registry")
	for id: StringName in PRISM_CROWN.cards:
		check(registry.call("get_resource", &"spells", id) is SpellComponent, "%s is a card" % id)
	var spells: SpellsScript = own(SpellsScript.new()) as SpellsScript
	spells.registry = registry
	var view: Dictionary = spells.staff_view(PRISM_CROWN.cards, PRISM_CROWN.staff)
	check(not bool(view.get("empty", true)), "it casts")
	check_equal((view.get("casts") as Array).size(), 1, "the whole build is one cast")
	check_equal(view.get("wasted"), {}, "no card is wasted (slot: wasted)")
