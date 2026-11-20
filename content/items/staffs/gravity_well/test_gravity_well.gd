extends "res://tests/support/suite.gd"
## The Gravity Well (content/items/staffs/gravity_well), a premade build on the hub's rack: a huge,
## slow, growing void and storm bolt that drags foes toward its path and every 0.5 s throws a nova
## of weaving fire atoms and closes five zapping lightning bolts in on itself. Its data is sound,
## every card it names is a card, and its build wastes none of them.
const SpellsScript := preload("res://core/spells/spells.gd")
const GRAVITY_WELL: StaffItem = preload("res://content/items/staffs/gravity_well/gravity_well.tres")


func test_it_is_sound() -> void:
	check_equal(GRAVITY_WELL.problems(), PackedStringArray(), "its data")
	check_equal(GRAVITY_WELL.id, &"gravity_well", "its id is its folder's")
	check_equal(GRAVITY_WELL.shown_name(), "Gravity Well", "its name")
	check_equal(GRAVITY_WELL.staff.id, &"dev", "on the dev staff: no four-slot staff holds it")
	var registry: Node = root.get_node("Registry")
	check(registry.call("get_resource", &"items", &"gravity_well") == GRAVITY_WELL, "the registry finds it under items")


func test_every_card_is_a_card_and_none_is_wasted() -> void:
	var registry: Node = root.get_node("Registry")
	for id: StringName in GRAVITY_WELL.cards:
		check(registry.call("get_resource", &"spells", id) is SpellComponent, "%s is a card" % id)
	var spells: SpellsScript = own(SpellsScript.new()) as SpellsScript
	spells.registry = registry
	var view: Dictionary = spells.staff_view(GRAVITY_WELL.cards, GRAVITY_WELL.staff)
	check(not bool(view.get("empty", true)), "it casts")
	check_equal((view.get("casts") as Array).size(), 1, "the whole build is one cast")
	check_equal(view.get("wasted"), {}, "no card is wasted (slot: wasted)")
