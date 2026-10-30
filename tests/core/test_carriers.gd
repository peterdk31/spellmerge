extends "res://tests/support/suite.gd"
## The carriers' contract (docs/CARRIERS.md, core/spells/carriers/): every carrier answers
## for every card kind, with no default, in its logic (`Carrier.Use`) and its look (`Carrier.Look`),
## and what it says agrees with its traits and with what its renderer really gets. A new carrier,
## behaviour or trigger fails here until each carrier has decided.
##
## godot --headless --path . --script res://tests/core/test_carriers.gd

const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")
const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const M := FormBase.Motion
const BEHAVIOURS := ModifierBase.Behaviour
const EVENTS := TriggerBase.Event
## The form card that plays each motion in these tests.
const FORMS: Dictionary = {
	M.STRAIGHT: &"bolt", M.STILL: &"rune", M.ORBIT: &"orbit", M.RAY: &"beam", M.DASH: &"dash",
	M.TELEPORT: &"teleport", M.HOOK: &"hook", M.SWAP: &"swap", M.WALL: &"wall", M.RAIN: &"rain",
	M.DECOY: &"decoy", M.FAMILIAR: &"familiar", M.SWING: &"swing", M.SLAM: &"slam",
}
## A numbers-only modifier (its row is `Behaviour.NONE`) and an infusion, each with a look layer.
const NUMBERS_CARD: StringName = &"bigger"
const INFUSION_CARD: StringName = &"fire"


func _carriers() -> Array[Carrier]:
	var all: Array[Carrier] = []
	for motion: int in M.values():
		if motion != M._UNUSED_10:
			all.append(Carriers.of(motion))
	return all


func _valid_look(carrier: Carrier, row: Array, at: int, cell: String) -> void:
	check(row.size() > at and row[at] is int and Carrier.Look.values().has(row[at]), "%s has a look" % cell)
	if row.size() > at and row[at] == Carrier.Look.NONE:
		var why: String = str(row[at + 1]) if row.size() > at + 1 else carrier.look_note()
		check(not why.is_empty(), "%s says why it shows nothing" % cell)


func _check_row(carrier: Carrier, row: Array, cell: String) -> void:
	check(not row.is_empty() and row[0] is int and Carrier.Use.values().has(row[0]), "%s has a use" % cell)
	if row.is_empty():
		return
	match row[0]:
		Carrier.Use.RUNS, Carrier.Use.OWN:
			_valid_look(carrier, row, 1, cell)
		Carrier.Use.WASTED:
			check(row.size() == 2 and row[1] is String and not String(row[1]).is_empty(), "%s says why it is wasted" % cell)
			check(row.size() < 2 or String(row[1]).length() < 140, "%s: a short reason" % cell)
		Carrier.Use.WITH_BLAST:
			_valid_look(carrier, row, 1, cell)
			check(row.size() == 3 and row[2] is String and not String(row[2]).is_empty(), "%s says why it is wasted without a blast" % cell)


func test_every_motion_has_its_carrier() -> void:
	for motion: int in M.values():
		var carrier: Carrier = Carriers.of(motion)
		if motion == M._UNUSED_10:
			check_equal(carrier.motion(), -1, "the retired slot has no carrier")
			continue
		check_equal(carrier.motion(), motion, "%s's carrier says it is" % M.keys()[motion])
		check(not carrier.noun().is_empty() and not carrier.what().is_empty(), "%s names itself" % M.keys()[motion])


func test_every_carrier_decides_every_behaviour() -> void:
	for carrier in _carriers():
		var table: Dictionary = carrier.behaviours()
		for behaviour: int in BEHAVIOURS.values():
			var cell: String = "%s on a %s" % [BEHAVIOURS.keys()[behaviour], carrier.noun()]
			check(table.has(behaviour), "%s is decided" % cell)
			if table.has(behaviour):
				_check_row(carrier, table[behaviour], cell)
		check_equal(table.size(), BEHAVIOURS.size(), "%s lists nothing else" % carrier.noun())


func test_every_carrier_decides_every_trigger() -> void:
	for carrier in _carriers():
		var table: Dictionary = carrier.events()
		for event: int in EVENTS.values():
			check(table.has(event) and table[event] is String, "%s on a %s is decided" % [EVENTS.keys()[event], carrier.noun()])
		check_equal(table.size(), EVENTS.size(), "%s lists nothing else" % carrier.noun())


func test_every_carrier_decides_infusions() -> void:
	for carrier in _carriers():
		_check_row(carrier, carrier.infusions(), "an infusion on a %s" % carrier.noun())
		check(carrier.infusions()[0] != Carrier.Use.WASTED, "an infusion is a hit's element: it counts on a %s at least with a blast" % carrier.noun())


func test_the_tables_agree_with_the_traits() -> void:
	for carrier in _carriers():
		var name: String = carrier.noun()
		check_equal(carrier.event_waste(EVENTS.HIT).is_empty(), carrier.hits(), "on hit fires on a %s exactly when it hits" % name)
		check_equal(carrier.event_waste(EVENTS.TIMER).is_empty(), carrier.lasts(), "a timer ticks on a %s exactly when it lasts" % name)
		check_equal(carrier.event_waste(EVENTS.HURT).is_empty(), carrier.lasts(), "on hurt listens on a %s exactly when it lasts" % name)
		var blocks: bool = carrier.use_of(BEHAVIOURS.SHIELD) != Carrier.Use.WASTED or carrier.use_of(BEHAVIOURS.DEFLECT) != Carrier.Use.WASTED
		check_equal(carrier.event_waste(EVENTS.BLOCK).is_empty(), blocks, "on block fires on a %s exactly where a shield or deflect runs" % name)
		check_equal(carrier.infusions()[0] == Carrier.Use.RUNS or carrier.infusions()[0] == Carrier.Use.OWN, carrier.hits(), "an infusion runs on a %s exactly when it hits" % name)
		check_equal(carrier.use_of(BEHAVIOURS.HOMING) != Carrier.Use.WASTED, carrier.steers(), "homing runs on a %s exactly when it steers" % name)
		for behaviour: int in [BEHAVIOURS.CHAIN, BEHAVIOURS.SIPHON, BEHAVIOURS.POSSESS, BEHAVIOURS.RELAY]:
			check_equal(carrier.use_of(behaviour) != Carrier.Use.WASTED, carrier.hits(), "%s runs on a %s exactly when it hits" % [BEHAVIOURS.keys()[behaviour], name])


func test_a_cue_row_has_a_card_with_a_cue() -> void:
	var arena := ArenaScript.new(root)
	var cards: Array = arena.registry.call("get_all", "spells")
	arena.free_all()
	for carrier in _carriers():
		for behaviour: int in BEHAVIOURS.values():
			# A WITH_BLAST row shows by the blast's cue, which the blast's own row checks.
			if carrier.look_of(behaviour) != Carrier.Look.CUE or carrier.use_of(behaviour) == Carrier.Use.WITH_BLAST:
				continue
			for card: Variant in cards:
				if card is ModifierBase and (card as ModifierBase).behaviour == behaviour:
					check((card as ModifierBase).cue != &"", "%s shows by its cue on a %s, and %s has one" % [BEHAVIOURS.keys()[behaviour], carrier.noun(), (card as ModifierBase).id])


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
		var drawn: int = _looks_drawn([NUMBERS_CARD, FORMS[carrier.motion()]])
		var says: bool = carrier.look_of(BEHAVIOURS.NONE) == Carrier.Look.SHOWN
		check_equal(ManagerScript.look_has(drawn, numbers), says, "%s's look on a %s is drawn exactly when its row says SHOWN" % [NUMBERS_CARD, carrier.noun()])
		if carrier.infusions()[1] == Carrier.Look.SHOWN:
			drawn = _looks_drawn([INFUSION_CARD, FORMS[carrier.motion()]])
			check(ManagerScript.look_has(drawn, infusion), "%s's look on a %s is drawn, as its row says" % [INFUSION_CARD, carrier.noun()])
