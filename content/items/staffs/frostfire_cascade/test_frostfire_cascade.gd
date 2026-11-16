extends "res://tests/support/suite.gd"
## The Frostfire Cascade (crypt rework CR-S, content/items/staffs/frostfire_cascade): the most shots,
## on the hub's rack. A fire nova of bolts split three times (216 shots) whose every shot, when it
## ends, fires a frost nova of bolts split three times (216 each): far past the projectile cap,
## which it holds for a few seconds. Two payload levels only: a third would queue a million shots.
## Its data is sound, every card it names is a card, and its build wastes none of them.
const SpellsScript := preload("res://core/spells/spells.gd")
const CASCADE: StaffItem = preload("res://content/items/staffs/frostfire_cascade/frostfire_cascade.tres")


func test_it_is_sound() -> void:
	check_equal(CASCADE.problems(), PackedStringArray(), "its data")
	check_equal(CASCADE.id, &"frostfire_cascade", "its id is its folder's")
	check_equal(CASCADE.shown_name(), "Frostfire Cascade", "its name")
	check_equal(CASCADE.staff.id, &"dev", "on the dev staff: no four-slot staff holds it")
	var registry: Node = root.get_node("Registry")
	check(registry.call("get_resource", &"items", &"frostfire_cascade") == CASCADE, "the registry finds it under items")


func test_every_card_is_a_card_and_none_is_wasted() -> void:
	var registry: Node = root.get_node("Registry")
	for id: StringName in CASCADE.cards:
		check(registry.call("get_resource", &"spells", id) is SpellComponent, "%s is a card" % id)
	var spells: SpellsScript = own(SpellsScript.new()) as SpellsScript
	spells.registry = registry
	var view: Dictionary = spells.staff_view(CASCADE.cards, CASCADE.staff)
	check(not bool(view.get("empty", true)), "it casts")
	check_equal(view.get("wasted"), {}, "no card is wasted (slot: wasted)")
