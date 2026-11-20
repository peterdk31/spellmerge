extends "res://tests/support/suite.gd"
## The Starfall Engine (content/items/staffs/starfall_engine), a premade build on the hub's rack: a
## big slow void bolt circles its caster and every 0.5 s drops a nova of fire bolts from the sky;
## each fire bolt, as it ends, closes five chaining lightning beams in on where it ended. Its data
## is sound, every card it names is a card, and its build wastes none of them.
const SpellsScript := preload("res://core/spells/spells.gd")
const STARFALL_ENGINE: StaffItem = preload("res://content/items/staffs/starfall_engine/starfall_engine.tres")


func test_it_is_sound() -> void:
	check_equal(STARFALL_ENGINE.problems(), PackedStringArray(), "its data")
	check_equal(STARFALL_ENGINE.id, &"starfall_engine", "its id is its folder's")
	check_equal(STARFALL_ENGINE.shown_name(), "Starfall Engine", "its name")
	check_equal(STARFALL_ENGINE.staff.id, &"dev", "on the dev staff: no four-slot staff holds it")
	var registry: Node = root.get_node("Registry")
	check(registry.call("get_resource", &"items", &"starfall_engine") == STARFALL_ENGINE, "the registry finds it under items")


func test_every_card_is_a_card_and_none_is_wasted() -> void:
	var registry: Node = root.get_node("Registry")
	for id: StringName in STARFALL_ENGINE.cards:
		check(registry.call("get_resource", &"spells", id) is SpellComponent, "%s is a card" % id)
	var spells: SpellsScript = own(SpellsScript.new()) as SpellsScript
	spells.registry = registry
	var view: Dictionary = spells.staff_view(STARFALL_ENGINE.cards, STARFALL_ENGINE.staff)
	check(not bool(view.get("empty", true)), "it casts")
	check_equal((view.get("casts") as Array).size(), 1, "the whole build is one cast")
	check_equal(view.get("wasted"), {}, "no card is wasted (slot: wasted)")
