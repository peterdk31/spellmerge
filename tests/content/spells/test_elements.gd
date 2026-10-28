extends "res://tests/support/suite.gd"
## The four elements in content/spells/elements/: each is an ElementBase resource with an
## id that matches its folder, numbers in range, an icon and a distinct tint, and each status
## it names is one that combat knows.

const CombatScript := preload("res://gameplay/combat/combat.gd")

const ELEMENTS: Array[StringName] = [&"fire", &"frost", &"storm", &"void"]


func _load(id: StringName) -> ElementBase:
	return load("res://content/spells/elements/%s/%s.tres" % [id, id]) as ElementBase


func test_every_element_loads_and_matches_its_folder() -> void:
	for id in ELEMENTS:
		var element: ElementBase = _load(id)
		check(element != null, "%s loads as an ElementBase" % id)
		if element != null:
			check_equal(element.id, id, "the id is the folder name")
			check(element.display_name != "", "%s has a name" % id)
			check(element.icon != null, "%s has an icon" % id)
			check(element.demo, "%s is in the web demo" % id)


func test_every_element_is_inside_its_ranges() -> void:
	for id in ELEMENTS:
		var element: ElementBase = _load(id)
		check_equal(element.range_problems().size(), 0, "%s: %s" % [id, ", ".join(element.range_problems())])


func test_every_element_names_a_status_combat_knows() -> void:
	var combat := own(CombatScript.new()) as CombatScript
	var enemy := own(Node2D.new()) as Node2D
	combat.register_actor(enemy, 10, 5.0)
	for id in ELEMENTS:
		var element: ElementBase = _load(id)
		check(combat.apply_status(0, enemy, element.status_id, element.status_duration, element.status_strength), "%s: combat accepts %s" % [id, element.status_id])


func test_the_elements_have_different_statuses_and_tints() -> void:
	var statuses: Dictionary = {}
	var tints: Dictionary = {}
	for id in ELEMENTS:
		var element: ElementBase = _load(id)
		statuses[element.status_id] = true
		tints[element.tint] = true
	check_equal(statuses.size(), ELEMENTS.size(), "one status each")
	check_equal(tints.size(), ELEMENTS.size(), "one tint each")
