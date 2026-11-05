extends "res://tests/support/suite.gd"
## Every element card the registry finds (content/spells/elements/): the status each names is one
## that combat knows, and no two share a status or a tint, so an infusion reads by its colour. A
## new element folder is checked with no edit here; each element's own test is in its folder.
##
## godot --headless --path . --script res://tests/content/spells/test_elements.gd

const CombatScript := preload("res://gameplay/combat/combat.gd")
const RegistryScript := preload("res://core/registry/registry.gd")

var _elements: Array[ElementBase] = []


func before_each() -> void:
	var registry := own(RegistryScript.new()) as RegistryScript
	registry.scan()
	_elements.clear()
	for card: Resource in registry.get_all(&"spells"):
		if card is ElementBase:
			_elements.append(card as ElementBase)


func test_the_registry_finds_the_elements() -> void:
	check(_elements.size() >= 6, "the element cards are found: %d" % _elements.size())


func test_every_status_an_element_names_is_one_combat_knows() -> void:
	var combat := own(CombatScript.new()) as CombatScript
	var enemy := own(Node2D.new()) as Node2D
	combat.register_actor(enemy, 10, 5.0)
	for element: ElementBase in _elements:
		if element.status_id == &"":
			check(element.heals, "%s names no status, so it heals" % element.id)
			continue
		check(combat.apply_status(0, enemy, element.status_id, element.status_duration, element.status_strength), "%s: combat accepts %s" % [element.id, element.status_id])


func test_the_elements_have_different_statuses_and_tints() -> void:
	var statuses: Dictionary = {}
	var tints: Dictionary = {}
	for element: ElementBase in _elements:
		if element.status_id != &"":
			check(not statuses.has(element.status_id), "%s's status %s is its own (also %s)" % [element.id, element.status_id, statuses.get(element.status_id, "")])
			statuses[element.status_id] = element.id
		check(not tints.has(element.tint), "%s's tint is its own (also %s)" % [element.id, tints.get(element.tint, "")])
		tints[element.tint] = element.id
