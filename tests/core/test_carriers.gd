extends "res://tests/support/suite.gd"
## The carriers (docs/CARRIERS.md, core/spells/carriers/): every one is found by its name and fired
## by a form card, and its lists of cards that do nothing on it (`does_nothing`, `never_fires`) are
## well formed and agree with its traits. Whether a listed card really does nothing, and an unlisted
## one something, is played out by tests/core/test_card_rules.gd.
##
## godot --headless --path . --script res://tests/core/test_carriers.gd

const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")
const BEHAVIOURS := ModifierBase.Behaviour
const EVENTS := TriggerBase.Event


func _carriers() -> Array[Carrier]:
	var all: Array[Carrier] = []
	for id: StringName in Carriers.ids():
		all.append(Carriers.of(id))
	return all


func _check_sentences(list: Dictionary, names: Dictionary, what: String, carrier: Carrier) -> void:
	for key: Variant in list:
		check(key is int and names.values().has(key), "%s on a %s: %s is a known one" % [what, carrier.noun(), key])
		var why: Variant = list[key]
		check(why is String and not String(why).is_empty(), "%s on a %s has its sentence" % [what, carrier.noun()])
		check(not (why is String) or String(why).length() < 140, "a short sentence: %s" % why)


func test_every_carrier_is_found_by_its_name() -> void:
	for id: StringName in Carriers.ids():
		var carrier: Carrier = Carriers.of(id)
		check_equal(carrier.id(), id, "%s's carrier says it is" % id)
		check(not carrier.noun().is_empty() and not carrier.what().is_empty(), "%s names itself" % id)
	check_equal(Carriers.of(&"fissure").id(), &"", "a name no carrier has runs as nothing")
	check(not Carriers.of(&"fissure").waste(BEHAVIOURS.HOMING).is_empty(), "and every card is wasted on it")


func test_every_form_card_names_a_carrier_and_every_carrier_has_one() -> void:
	var arena := ArenaScript.new(root)
	var cards: Array = arena.registry.call("get_all", "spells")
	arena.free_all()
	var named: Dictionary = {}
	for card: Variant in cards:
		if card is FormBase:
			var form := card as FormBase
			check(Carriers.ids().has(form.carrier), "%s names a carrier: %s" % [form.id, form.carrier])
			named[form.carrier] = true
	for id: StringName in Carriers.ids():
		check(named.has(id), "a form card fires the %s" % id)


func test_the_lists_are_well_formed() -> void:
	for carrier in _carriers():
		_check_sentences(carrier.does_nothing(), BEHAVIOURS, "a modifier", carrier)
		_check_sentences(carrier.never_fires(), EVENTS, "a trigger", carrier)


func test_the_lists_agree_with_the_traits() -> void:
	for carrier in _carriers():
		var name: String = carrier.noun()
		var listed: Dictionary = carrier.does_nothing()
		check_equal(carrier.event_waste(EVENTS.HIT).is_empty(), carrier.hits(), "on hit fires on a %s exactly when it hits" % name)
		check_equal(carrier.event_waste(EVENTS.TIMER).is_empty(), carrier.lasts(), "a timer ticks on a %s exactly when it lasts" % name)
		check_equal(carrier.event_waste(EVENTS.HURT).is_empty(), carrier.lasts(), "on hurt listens on a %s exactly when it lasts" % name)
		var blocks: bool = not listed.has(BEHAVIOURS.SHIELD) or not listed.has(BEHAVIOURS.DEFLECT)
		check_equal(carrier.event_waste(EVENTS.BLOCK).is_empty(), blocks, "on block fires on a %s exactly where a shield or deflect works" % name)
		check_equal(not listed.has(BEHAVIOURS.HOMING), carrier.steers(), "homing works on a %s exactly when it steers" % name)
		for behaviour: int in [BEHAVIOURS.CHAIN, BEHAVIOURS.SIPHON, BEHAVIOURS.POSSESS, BEHAVIOURS.RELAY, BEHAVIOURS.HEAVY]:
			check_equal(not listed.has(behaviour), carrier.hits(), "%s works on a %s exactly when it hits" % [BEHAVIOURS.keys()[behaviour], name])
		check(not listed.has(BEHAVIOURS.NONE), "a card of numbers only is judged by its numbers, not listed")


func test_a_blast_carries_heavy_and_infusions_on_a_carrier_that_hits_nothing() -> void:
	var decoy: Carrier = Carriers.of(&"decoy")
	check(not decoy.waste(BEHAVIOURS.HEAVY).is_empty(), "heavy does nothing on a bare decoy")
	check(decoy.waste(BEHAVIOURS.HEAVY, true).is_empty(), "a blast carries it")
	check(not decoy.waste(BEHAVIOURS.SIPHON, true).is_empty(), "but not siphon: a blast is no shot hit")
	check(not decoy.takes_infusion(false) and decoy.takes_infusion(true), "nor an infusion without a blast")
	check(Carriers.of(&"bolt").takes_infusion(false), "a bolt takes one on its own hits")
