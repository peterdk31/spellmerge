extends "res://tests/support/suite.gd"
## The carriers (docs/CARRIERS.md, core/spells/carriers/): every one is found by its name and fired
## by a form card, and what is worked out from its traits (which cards do nothing on it, and why)
## reads well. Whether that is right is played out by tests/core/test_card_rules.gd.
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


func test_every_card_a_carrier_cannot_use_says_why() -> void:
	for carrier in _carriers():
		for behaviour: int in BEHAVIOURS.values():
			var why: String = carrier.waste(behaviour)
			check(why.length() < 160, "a short sentence for %s on a %s: %s" % [BEHAVIOURS.keys()[behaviour], carrier.noun(), why])
		for event: int in EVENTS.values():
			var why: String = carrier.event_waste(event)
			check(why.length() < 160, "a short sentence for %s on a %s: %s" % [EVENTS.keys()[event], carrier.noun(), why])
	check(Carriers.of(&"bolt").waste(BEHAVIOURS.RETURN).is_empty(), "a bolt flies out, so return works on it")
	check_equal(Carriers.of(&"decoy").waste(BEHAVIOURS.RETURN), "it does not fly out, and a decoy is a body that hits nothing", "a decoy does not, and says why")
	check_equal(Carriers.of(&"decoy").event_waste(EVENTS.HIT), "a decoy hits nothing", "on hit on a decoy")


func test_what_is_worked_out_follows_the_traits() -> void:
	for carrier in _carriers():
		var name: String = carrier.noun()
		check_equal(carrier.event_waste(EVENTS.HIT).is_empty(), carrier.hits(), "on hit fires on a %s exactly when it hits" % name)
		check_equal(carrier.event_waste(EVENTS.TIMER).is_empty(), carrier.lasts(), "a timer ticks on a %s exactly when it lasts" % name)
		check_equal(carrier.waste(BEHAVIOURS.HOMING).is_empty(), carrier.steers(), "homing works on a %s exactly when it steers" % name)
		check_equal(carrier.waste(BEHAVIOURS.RETURN).is_empty(), carrier.flies(), "return works on a %s exactly when it flies" % name)
		for behaviour: int in [BEHAVIOURS.CHAIN, BEHAVIOURS.SIPHON, BEHAVIOURS.POSSESS, BEHAVIOURS.RELAY, BEHAVIOURS.HEAVY]:
			check_equal(carrier.waste(behaviour).is_empty(), carrier.hits(), "%s works on a %s exactly when it hits" % [BEHAVIOURS.keys()[behaviour], name])
		for behaviour: int in [BEHAVIOURS.NONE, BEHAVIOURS.BLAST, BEHAVIOURS.ECHO, BEHAVIOURS.RECOIL]:
			check(carrier.waste(behaviour).is_empty(), "%s works on every carrier, a %s too" % [BEHAVIOURS.keys()[behaviour], name])


func test_a_blast_carries_heavy_and_infusions_on_a_carrier_that_hits_nothing() -> void:
	var decoy: Carrier = Carriers.of(&"decoy")
	check(not decoy.waste(BEHAVIOURS.HEAVY).is_empty(), "heavy does nothing on a bare decoy")
	check(decoy.waste(BEHAVIOURS.HEAVY, true).is_empty(), "a blast carries it")
	check(not decoy.waste(BEHAVIOURS.SIPHON, true).is_empty(), "but not siphon: a blast is no shot hit")
	check(not decoy.takes_infusion(false) and decoy.takes_infusion(true), "nor an infusion without a blast")
	check(Carriers.of(&"bolt").takes_infusion(false), "a bolt takes one on its own hits")
