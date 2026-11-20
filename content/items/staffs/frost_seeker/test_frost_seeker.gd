extends "res://tests/support/suite.gd"
## The Frost seeker (content/items/staffs/frost_seeker): one of the hub rack's normal premade staffs (the owner,
## 2026-11-20, on #891: real, balanced builds beside the crazy ones), a homing frost bolt that slows what it hits, on the crystal
## staff, a starter staff's numbers. Its data is sound, every card it names is a card, its build
## wastes none of them, and it is a fair staff: no dev staff's endless mana or missing cooldown.
const SpellsScript := preload("res://core/spells/spells.gd")
const FROST_SEEKER: StaffItem = preload("res://content/items/staffs/frost_seeker/frost_seeker.tres")


func test_it_is_sound() -> void:
	check_equal(FROST_SEEKER.problems(), PackedStringArray(), "its data")
	check_equal(FROST_SEEKER.id, &"frost_seeker", "its id is its folder's")
	check_equal(FROST_SEEKER.shown_name(), "Frost seeker", "its name")
	var registry: Node = root.get_node("Registry")
	check(registry.call("get_resource", &"items", &"frost_seeker") == FROST_SEEKER, "the registry finds it under items")


func test_every_card_is_a_card_and_none_is_wasted() -> void:
	var registry: Node = root.get_node("Registry")
	for id: StringName in FROST_SEEKER.cards:
		check(registry.call("get_resource", &"spells", id) is SpellComponent, "%s is a card" % id)
	var spells: SpellsScript = own(SpellsScript.new()) as SpellsScript
	spells.registry = registry
	var view: Dictionary = spells.staff_view(FROST_SEEKER.cards, FROST_SEEKER.staff)
	check(not bool(view.get("empty", true)), "it casts")
	check_equal(view.get("wasted"), {}, "no card is wasted (slot: wasted)")


func test_it_is_a_fair_staff() -> void:
	var starter: StaffBase = load("res://content/wizard/staffs/crystal/crystal.tres") as StaffBase
	check(FROST_SEEKER.staff == starter, "on the crystal staff, a starter staff")
	check(FROST_SEEKER.staff.max_mana <= 100.0 and FROST_SEEKER.staff.cooldown > 0.0, "with a starter's mana and a cooldown")
