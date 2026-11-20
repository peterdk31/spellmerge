extends "res://tests/support/suite.gd"
## The Firebolt (content/items/staffs/firebolt): one of the hub rack's normal premade staffs (the owner,
## 2026-11-20, on #891: real, balanced builds beside the crazy ones), a fire bolt: the simplest elemental attack, on the moon
## staff, a starter staff's numbers. Its data is sound, every card it names is a card, its build
## wastes none of them, and it is a fair staff: no dev staff's endless mana or missing cooldown.
const SpellsScript := preload("res://core/spells/spells.gd")
const FIREBOLT: StaffItem = preload("res://content/items/staffs/firebolt/firebolt.tres")


func test_it_is_sound() -> void:
	check_equal(FIREBOLT.problems(), PackedStringArray(), "its data")
	check_equal(FIREBOLT.id, &"firebolt", "its id is its folder's")
	check_equal(FIREBOLT.shown_name(), "Firebolt", "its name")
	var registry: Node = root.get_node("Registry")
	check(registry.call("get_resource", &"items", &"firebolt") == FIREBOLT, "the registry finds it under items")


func test_every_card_is_a_card_and_none_is_wasted() -> void:
	var registry: Node = root.get_node("Registry")
	for id: StringName in FIREBOLT.cards:
		check(registry.call("get_resource", &"spells", id) is SpellComponent, "%s is a card" % id)
	var spells: SpellsScript = own(SpellsScript.new()) as SpellsScript
	spells.registry = registry
	var view: Dictionary = spells.staff_view(FIREBOLT.cards, FIREBOLT.staff)
	check(not bool(view.get("empty", true)), "it casts")
	check_equal(view.get("wasted"), {}, "no card is wasted (slot: wasted)")


func test_it_is_a_fair_staff() -> void:
	var starter: StaffBase = load("res://content/wizard/staffs/moon/moon.tres") as StaffBase
	check(FIREBOLT.staff == starter, "on the moon staff, a starter staff")
	check(FIREBOLT.staff.max_mana <= 100.0 and FIREBOLT.staff.cooldown > 0.0, "with a starter's mana and a cooldown")
