extends "res://tests/support/suite.gd"
## The carriers (docs/CARRIERS.md, core/spells/carriers/): every one is found by its name and fired
## by a form card, and which cards work on it follows from its yes/no answers (`CarrierTraits`) and
## what each card needs (`ModifierBase.NEEDS`, `TriggerBase.NEEDS`). Whether that is right in play is
## tested by tests/core/test_card_rules.gd.
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
		check_equal(Carriers.of(id).id(), id, "%s's carrier says it is" % id)
	check_equal(Carriers.of(&"fissure").id(), &"", "a name no carrier has runs as nothing")
	check(not Carriers.of(&"fissure").works(BEHAVIOURS.NONE), "and no card works on it")


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


func test_what_works_follows_the_traits() -> void:
	for carrier in _carriers():
		var name: StringName = carrier.id()
		check_equal(carrier.fires(EVENTS.HIT), carrier.hits(), "on hit fires on a %s exactly when it hits" % name)
		check_equal(carrier.fires(EVENTS.TIMER), carrier.lasts(), "a timer ticks on a %s exactly when it lasts" % name)
		check_equal(carrier.works(BEHAVIOURS.HOMING), carrier.steers(), "homing works on a %s exactly when it steers" % name)
		check_equal(carrier.works(BEHAVIOURS.RETURN), carrier.flies(), "return works on a %s exactly when it flies" % name)
		for behaviour: int in [BEHAVIOURS.CHAIN, BEHAVIOURS.SIPHON, BEHAVIOURS.POSSESS, BEHAVIOURS.RELAY, BEHAVIOURS.HEAVY]:
			check_equal(carrier.works(behaviour), carrier.hits(), "%s works on a %s exactly when it hits" % [BEHAVIOURS.keys()[behaviour], name])
		for behaviour: int in [BEHAVIOURS.NONE, BEHAVIOURS.BLAST, BEHAVIOURS.ECHO, BEHAVIOURS.RECOIL]:
			check(carrier.works(behaviour), "%s works on every carrier, a %s too" % [BEHAVIOURS.keys()[behaviour], name])


func test_a_blast_carries_heavy_and_infusions_on_a_carrier_that_hits_nothing() -> void:
	var decoy: Carrier = Carriers.of(&"decoy")
	check(not decoy.works(BEHAVIOURS.HEAVY), "heavy does nothing on a bare decoy")
	check(decoy.works(BEHAVIOURS.HEAVY, true), "a blast carries it")
	check(not decoy.works(BEHAVIOURS.SIPHON, true), "but not siphon: a blast is no shot hit")
	check(not decoy.takes_infusion(false) and decoy.takes_infusion(true), "nor an infusion without a blast")
	check(Carriers.of(&"bolt").takes_infusion(false), "a bolt takes one on its own hits")


func test_asking_about_one_card_says_what_a_compile_says() -> void:
	# `Spells.card_works` is what the builder, a reward screen or a bot asks before a card is
	# placed: for every card in the game on every carrier it must agree with a compile of that card
	# on that carrier (a trigger with a payload after it).
	var arena := ArenaScript.new(root)
	var cards: Array = arena.registry.call("get_all", "spells")
	var asked: int = 0
	for card: Variant in cards:
		if not (card is ModifierBase or card is ElementBase or card is TriggerBase):
			continue
		var component := card as SpellComponent
		for carrier: StringName in Carriers.ids():
			var ids: Array[StringName] = [component.id, carrier]
			if card is TriggerBase or carrier == &"rain":
				ids.append(&"bolt")
			if card is TriggerBase and carrier == &"rain":
				ids.append(&"bolt")
			var built: CompiledStaff = arena.spells.compile_staff(ids, ArenaScript.plain_staff(ids.size()))
			check_equal(not built.wasted.has(0), arena.spells.card_works(component.id, carrier), "%s on a %s" % [component.id, carrier])
			asked += 1
	arena.free_all()
	check(asked > 100, "every card on every carrier was asked: %d" % asked)
