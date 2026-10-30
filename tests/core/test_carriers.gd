extends "res://tests/support/suite.gd"
## The carriers' contract (docs/CARRIERS.md, core/spells/carriers/): every carrier answers
## for every card kind, with no default, in whether each works on it (`Carrier.Works`) and how it shows (`Carrier.Shows`),
## and what it says agrees with its traits and with what its renderer really gets. A new carrier,
## behaviour or trigger fails here until each carrier has decided.
##
## godot --headless --path . --script res://tests/core/test_carriers.gd

const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")
const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const BEHAVIOURS := ModifierBase.Behaviour
const EVENTS := TriggerBase.Event
## A numbers-only modifier (its row is `Behaviour.NONE`) and an infusion, each with a look layer.
const NUMBERS_CARD: StringName = &"bigger"
const INFUSION_CARD: StringName = &"fire"


func _carriers() -> Array[Carrier]:
	var all: Array[Carrier] = []
	for id: StringName in Carriers.ids():
		all.append(Carriers.of(id))
	return all


## The keys a behaviour (or infusion) row may have, by what "works" says.
const ROW_KEYS: Dictionary = {
	Carrier.Works.YES: ["works", "shows"],
	Carrier.Works.OWN_WAY: ["works", "shows"],
	Carrier.Works.NO: ["works", "why_not"],
	Carrier.Works.ONLY_WITH_BLAST: ["works", "shows", "why_not"],
}


func _reason(row: Dictionary, key: String, cell: String) -> void:
	check(row.has(key) and row[key] is String and not String(row[key]).is_empty(), "%s says %s" % [cell, key])
	check(not row.has(key) or String(row[key]).length() < 140, "%s: a short %s" % [cell, key])


func _check_row(row: Dictionary, cell: String) -> void:
	check(row.has("works") and row["works"] is int and Carrier.Works.values().has(row["works"]), "%s says whether it works" % cell)
	if not row.has("works"):
		return
	var keys: Array = (ROW_KEYS[row["works"]] as Array).duplicate()
	if row.has("shows"):
		check(row["shows"] is int and Carrier.Shows.values().has(row["shows"]), "%s says how it shows" % cell)
		if row["shows"] == Carrier.Shows.NOTHING:
			keys.append("why_nothing_shows")
			_reason(row, "why_nothing_shows", cell)
	for key: String in keys:
		check(row.has(key), "%s has %s" % [cell, key])
	for key: String in row:
		check(keys.has(key), "%s has no key %s" % [cell, key])
	if row.has("why_not"):
		_reason(row, "why_not", cell)


func test_every_carrier_is_found_by_its_name() -> void:
	for id: StringName in Carriers.ids():
		var carrier: Carrier = Carriers.of(id)
		check_equal(carrier.id(), id, "%s's carrier says it is" % id)
		check(not carrier.noun().is_empty() and not carrier.what().is_empty(), "%s names itself" % id)
	check_equal(Carriers.of(&"fissure").id(), &"", "a name no carrier has runs as nothing")


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


func test_every_carrier_decides_every_behaviour() -> void:
	for carrier in _carriers():
		var table: Dictionary = carrier.behaviours()
		for behaviour: int in BEHAVIOURS.values():
			var cell: String = "%s on a %s" % [BEHAVIOURS.keys()[behaviour], carrier.noun()]
			check(table.has(behaviour), "%s is decided" % cell)
			if table.has(behaviour):
				_check_row(table[behaviour], cell)
		check_equal(table.size(), BEHAVIOURS.size(), "%s lists nothing else" % carrier.noun())


func test_every_carrier_decides_every_trigger() -> void:
	for carrier in _carriers():
		var table: Dictionary = carrier.events()
		for event: int in EVENTS.values():
			var cell: String = "%s on a %s" % [EVENTS.keys()[event], carrier.noun()]
			check(table.has(event) and table[event] is Dictionary and table[event].get("fires") is bool, "%s says whether it fires" % cell)
			if table.has(event) and table[event] is Dictionary:
				var row: Dictionary = table[event]
				if row.get("fires") == false:
					_reason(row, "why_not", cell)
				check(row.size() == (1 if row.get("fires") == true else 2), "%s has no other key" % cell)
		check_equal(table.size(), EVENTS.size(), "%s lists nothing else" % carrier.noun())


func test_every_carrier_decides_infusions() -> void:
	for carrier in _carriers():
		_check_row(carrier.infusions(), "an infusion on a %s" % carrier.noun())
		check(carrier.infusions().get("works") != Carrier.Works.NO, "an infusion is a hit's element: it counts on a %s at least with a blast" % carrier.noun())


func test_the_tables_agree_with_the_traits() -> void:
	for carrier in _carriers():
		var name: String = carrier.noun()
		check_equal(carrier.event_waste(EVENTS.HIT).is_empty(), carrier.hits(), "on hit fires on a %s exactly when it hits" % name)
		check_equal(carrier.event_waste(EVENTS.TIMER).is_empty(), carrier.lasts(), "a timer ticks on a %s exactly when it lasts" % name)
		check_equal(carrier.event_waste(EVENTS.HURT).is_empty(), carrier.lasts(), "on hurt listens on a %s exactly when it lasts" % name)
		var blocks: bool = carrier.works(BEHAVIOURS.SHIELD) != Carrier.Works.NO or carrier.works(BEHAVIOURS.DEFLECT) != Carrier.Works.NO
		check_equal(carrier.event_waste(EVENTS.BLOCK).is_empty(), blocks, "on block fires on a %s exactly where a shield or deflect runs" % name)
		check_equal(carrier.takes_infusion(false), carrier.hits(), "an infusion runs on a %s exactly when it hits" % name)
		check_equal(carrier.works(BEHAVIOURS.HOMING) != Carrier.Works.NO, carrier.steers(), "homing runs on a %s exactly when it steers" % name)
		for behaviour: int in [BEHAVIOURS.CHAIN, BEHAVIOURS.SIPHON, BEHAVIOURS.POSSESS, BEHAVIOURS.RELAY]:
			check_equal(carrier.works(behaviour) != Carrier.Works.NO, carrier.hits(), "%s runs on a %s exactly when it hits" % [BEHAVIOURS.keys()[behaviour], name])


func test_a_cue_row_has_a_card_with_a_cue() -> void:
	var arena := ArenaScript.new(root)
	var cards: Array = arena.registry.call("get_all", "spells")
	arena.free_all()
	for carrier in _carriers():
		for behaviour: int in BEHAVIOURS.values():
			# An ONLY_WITH_BLAST row shows as the blast's effect, which the blast's own row checks.
			if carrier.shows(behaviour) != Carrier.Shows.AS_EFFECT or carrier.works(behaviour) == Carrier.Works.ONLY_WITH_BLAST:
				continue
			for card: Variant in cards:
				if card is ModifierBase and (card as ModifierBase).behaviour == behaviour:
					check((card as ModifierBase).cue != &"", "%s shows as its effect on a %s, and %s has one (its cue)" % [BEHAVIOURS.keys()[behaviour], carrier.noun(), (card as ModifierBase).id])


## Every look a renderer got while `cards` were cast and ran: the shots' (the manager's batches), a
## live beam's and swing's (their shaders), and what `form_shown` handed the looks (a dash, a rain,
## a slam).
func _looks_drawn(cards: Array) -> int:
	var arena := ArenaScript.new(root)
	arena.place_caster(0, Vector2(100.0, 180.0))
	arena.add_imp(Vector2(160.0, 180.0))
	var seen: Array[int] = [0]
	arena.bus.form_shown.connect(func(_caster: int, _form: StringName, _at: Vector2, _way: Vector2, _length: float, _tint: Color, look: int) -> void: seen[0] |= look)
	arena.install_cards(0, 0, cards)
	arena.cast(0, 0)
	for step in 60:
		for slot in arena.projectiles.get_cap():
			if arena.projectiles.is_alive(slot):
				seen[0] |= arena.projectiles.get_look_of(slot)
		for at in arena.spells.beam_slots():
			if arena.spells.beam_on(at):
				seen[0] |= arena.spells.beam_look(at)
		for at in arena.spells.swing_slots():
			if arena.spells.swing_on(at):
				seen[0] |= arena.spells.swing_look(at)
		arena.run(1.0 / 60.0)
	arena.free_all()
	return seen[0]


func _layer(id: StringName) -> int:
	var arena := ArenaScript.new(root)
	var card: SpellComponent = arena.registry.call("get_resource", "spells", id) as SpellComponent
	arena.free_all()
	return int(card.get(&"look_layer"))


func test_what_a_carrier_says_it_shows_is_drawn() -> void:
	var numbers: int = _layer(NUMBERS_CARD)
	var infusion: int = _layer(INFUSION_CARD)
	check(numbers > 0 and infusion > 0, "the test cards have looks")
	for carrier in _carriers():
		var drawn: int = _looks_drawn([NUMBERS_CARD, carrier.id()])
		var says: bool = carrier.shows(BEHAVIOURS.NONE) == Carrier.Shows.DRAWN
		check_equal(ManagerScript.look_has(drawn, numbers), says, "%s's look on a %s is drawn exactly when its row says DRAWN" % [NUMBERS_CARD, carrier.noun()])
		if carrier.infusions().get("shows") == Carrier.Shows.DRAWN:
			drawn = _looks_drawn([INFUSION_CARD, carrier.id()])
			check(ManagerScript.look_has(drawn, infusion), "%s's look on a %s is drawn, as its row says" % [INFUSION_CARD, carrier.noun()])
