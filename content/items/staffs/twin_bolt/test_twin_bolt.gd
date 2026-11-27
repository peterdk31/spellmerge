extends "res://tests/support/suite.gd"
## The Twin bolt (content/items/staffs/twin_bolt): one of the hub rack's normal premade staffs (the owner,
## 2026-11-20, on #891: real, balanced builds beside the crazy ones), a bolt and +2 (three bolts in a fan), on the curl
## staff, a starter staff's numbers. Its data is sound, every card it names is a card, its build
## wastes none of them, and it is a fair staff: no dev staff's endless mana or missing cooldown.
const SpellsScript := preload("res://core/spells/spells.gd")
const TWIN_BOLT: StaffItem = preload("res://content/items/staffs/twin_bolt/twin_bolt.tres")


func test_it_is_sound() -> void:
	check_equal(TWIN_BOLT.problems(), PackedStringArray(), "its data")
	check_equal(TWIN_BOLT.id, &"twin_bolt", "its id is its folder's")
	check_equal(TWIN_BOLT.shown_name(), "Twin bolt", "its name")
	var registry: Node = root.get_node("Registry")
	check(registry.call("get_resource", &"items", &"twin_bolt") == TWIN_BOLT, "the registry finds it under items")


func test_every_card_is_a_card_and_none_is_wasted() -> void:
	var registry: Node = root.get_node("Registry")
	for id: StringName in TWIN_BOLT.cards:
		check(registry.call("get_resource", &"spells", id) is SpellComponent, "%s is a card" % id)
	var spells: SpellsScript = own(SpellsScript.new()) as SpellsScript
	spells.registry = registry
	var view: Dictionary = spells.staff_view(TWIN_BOLT.cards, TWIN_BOLT.staff)
	check(not bool(view.get("empty", true)), "it casts")
	check_equal(view.get("wasted"), {}, "no card is wasted (slot: wasted)")


func test_it_is_a_fair_staff() -> void:
	var starter: StaffBase = load("res://content/wizard/staffs/curl/curl.tres") as StaffBase
	check(TWIN_BOLT.staff == starter, "on the curl staff, a starter staff")
	check(TWIN_BOLT.staff.max_mana <= 100.0 and TWIN_BOLT.staff.cooldown > 0.0, "with a starter's mana and a cooldown")
