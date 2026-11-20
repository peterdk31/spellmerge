extends "res://tests/support/suite.gd"
## The Mirror Tempest (content/items/staffs/mirror_tempest), a premade build on the hub's rack: a
## fan of three lightning beams and a fan of three frost beams at once, each fan fired backward too
## and echoed, three times over. Its data is sound, every card it names is a card, and its build
## wastes none of them.
const SpellsScript := preload("res://core/spells/spells.gd")
const MIRROR_TEMPEST: StaffItem = preload("res://content/items/staffs/mirror_tempest/mirror_tempest.tres")


func test_it_is_sound() -> void:
	check_equal(MIRROR_TEMPEST.problems(), PackedStringArray(), "its data")
	check_equal(MIRROR_TEMPEST.id, &"mirror_tempest", "its id is its folder's")
	check_equal(MIRROR_TEMPEST.shown_name(), "Mirror Tempest", "its name")
	check_equal(MIRROR_TEMPEST.staff.id, &"dev", "on the dev staff: no four-slot staff holds it")
	var registry: Node = root.get_node("Registry")
	check(registry.call("get_resource", &"items", &"mirror_tempest") == MIRROR_TEMPEST, "the registry finds it under items")


func test_every_card_is_a_card_and_none_is_wasted() -> void:
	var registry: Node = root.get_node("Registry")
	for id: StringName in MIRROR_TEMPEST.cards:
		check(registry.call("get_resource", &"spells", id) is SpellComponent, "%s is a card" % id)
	var spells: SpellsScript = own(SpellsScript.new()) as SpellsScript
	spells.registry = registry
	var view: Dictionary = spells.staff_view(MIRROR_TEMPEST.cards, MIRROR_TEMPEST.staff)
	check(not bool(view.get("empty", true)), "it casts")
	check_equal((view.get("casts") as Array).size(), 1, "the whole build is one cast")
	check_equal(view.get("wasted"), {}, "no card is wasted (slot: wasted)")
