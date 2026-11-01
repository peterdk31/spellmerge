extends "res://tests/support/suite.gd"
## The compiler's one table of behaviour x carrier (phase R, R2a, docs/milestones/M2-rules.md,
## rule 1: works or wasted): every behaviour on every carrier either runs or is wasted with a
## reason a player can read, and a wasted card changes nothing else. The real cards are played on
## every carrier by tests/core/test_card_rules.gd; here the table itself and a few real cells.
##
## godot --headless --path . --script res://tests/core/test_behaviour_table.gd

const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")


func _staff(cards: Array) -> CompiledStaff:
	var arena := ArenaScript.new(root)
	var staff: CompiledStaff = arena.install_cards(0, 0, cards)
	arena.free_all()
	return staff


func test_every_need_names_known_behaviours_traits_and_fields() -> void:
	# A typo in a NEEDS row would quietly make a card work or waste everywhere.
	var fields: Array[String] = ["any", "not", "or_cards", "cards", "or_infused", "not_cards"]
	var all_traits: int = (CarrierTraits.BLOCKS << 1) - 1
	for table: Dictionary in [ModifierBase.NEEDS, TriggerBase.NEEDS]:
		var size: int = ModifierBase.Behaviour.size() if table == ModifierBase.NEEDS else TriggerBase.Event.size()
		for key: int in table:
			check(key >= 0 and key < size, "%d is a row the table can have" % key)
			var need: Dictionary = table[key]
			for field: String in need:
				check(fields.has(field), "%s is a field a need has" % field)
			check_equal(int(need.get("any", 0)) & ~all_traits, 0, "row %d asks only for known traits" % key)
			check_equal(int(need.get("not", 0)) & ~all_traits, 0, "row %d rules out only known traits" % key)
			for list: String in ["or_cards", "cards", "not_cards"]:
				for behaviour: int in need.get(list, []):
					check(behaviour > 0 and behaviour < ModifierBase.Behaviour.size(), "row %d's %s are behaviours" % [key, list])


func test_a_bolt_runs_every_behaviour() -> void:
	for behaviour: int in ModifierBase.Behaviour.values():
		check(Carriers.of(&"atom").works(behaviour), "%s runs on a bolt" % ModifierBase.Behaviour.keys()[behaviour])


func test_cards_that_did_nothing_silently_are_listed() -> void:
	# Cells the audit found silent (M2-rules.md findings 4, 5, 6, 9), now wasted with a reason.
	for cards: Array in [["spiral", "rune"], ["ghost", "orbit"], ["linger", "wall"], ["linger", "beam"], ["magnet", "swing"], ["growth", "slam"], ["siphon", "decoy"], ["pull", "decoy"], ["shield", "rain"], ["hold", "slam"]]:
		var staff: CompiledStaff = _staff(cards)
		check(staff.wasted.has(0), "%s is listed as wasted: %s" % [cards, staff.wasted])


func test_cards_that_work_are_not_listed() -> void:
	for cards: Array in [["heavy", "bolt"], ["bounce", "beam"], ["chain", "swing"], ["shield", "beam"], ["mirror", "swing"], ["mirror", "dash"], ["mirror", "teleport"], ["growth", "swap"], ["growth", "rune"], ["sticky", "orbit"], ["magnet", "rune"], ["zap", "wall"], ["blast", "rain"], ["shield", "dash"], ["hold", "rain"], ["hold", "swing"], ["ghost", "beam"], ["magnet", "beam"], ["spiral", "beam"], ["growth", "beam"], ["relay", "swing"], ["mirror", "swap"], ["pull", "bolt"], ["pull", "swing"], ["pull", "beam"], ["mirror", "wall"], ["mirror", "rain"], ["mirror", "decoy"], ["sniper", "rune"], ["sniper", "decoy"], ["heavy", "rain"], ["shield", "decoy"], ["deflect", "decoy"], ["heavy", "dash"], ["chain", "teleport"], ["deflect", "dash"]]:
		var staff: CompiledStaff = _staff(cards)
		check(not staff.wasted.has(0), "%s counts: %s" % [cards, staff.wasted])


func test_a_familiar_hands_nothing_on() -> void:
	# Rules R4 F3: a familiar has no payload of its own; its hit cards are wasted as on any body
	# that hits nothing, and the carrier after it is the next carrier, not its payload.
	var staff: CompiledStaff = _staff(["heavy", "familiar", "bolt"])
	check(staff.wasted.has(0), "heavy on a familiar is wasted: %s" % staff.wasted)
	var familiar: CompiledSpell = staff.casts[0].group.spells[0]
	check(familiar.own_payload == null, "it reads no payload of its own")
	check(familiar.payload == null, "and has none without a trigger")
	check(staff.casts.size() == 2, "the bolt is the next cast: %d casts" % staff.casts.size())


func test_hit_cards_count_on_a_decoy_with_a_blast() -> void:
	# What the blast strikes is the decoy's hit (rules R4 F2): every hit card rides on it.
	var staff: CompiledStaff = _staff(["heavy", "blast", "decoy"])
	check(not staff.wasted.has(0), "heavy counts with a blast: %s" % staff.wasted)
	check(staff.casts[0].group.spells[0].hit.slam > 0, "the blast slams")
	for card: String in ["siphon", "chain", "possess", "relay"]:
		check(not _staff([card, "blast", "decoy"]).wasted.has(0), "%s counts with a blast too" % card)
	check(_staff(["siphon", "decoy"]).wasted.has(0), "and not without one")


func test_a_wasted_card_changes_nothing_else() -> void:
	# Heavy slows what it is on; wasted on a decoy, the decoy is as fast as a plain one.
	var plain: CompiledSpell = _staff(["decoy"]).casts[0].group.spells[0]
	var heavy: CompiledSpell = _staff(["heavy", "decoy"]).casts[0].group.spells[0]
	check_equal(heavy.speed, plain.speed, "the same speed")
	check_equal(heavy.behaviour(ModifierBase.Behaviour.HEAVY), 0.0, "no heavy strength")


func test_infusions_and_numbers_that_mean_nothing_are_listed() -> void:
	# Found by tests/core/test_card_rules.gd: silent on main before R2.
	for cards: Array in [["fire", "decoy"], ["frost", "decoy"], ["overcharge", "decoy"], ["pierce", "dash"], ["split", "dash"], ["slow", "teleport"], ["pierce", "swing"]]:
		var staff: CompiledStaff = _staff(cards)
		check(staff.wasted.has(0), "%s is listed as wasted: %s" % [cards, staff.wasted])
	for cards: Array in [["fire", "blast", "dash"], ["overcharge", "blast", "teleport"], ["fire", "dash"], ["overcharge", "teleport"], ["mend", "teleport"], ["sniper", "bolt"], ["pierce", "rune"], ["timer", "bolt", "nova"], ["zap", "bolt"], ["slow", "bolt"], ["timer", "swap", "nova"], ["zap", "nova"], ["mend", "rain"], ["overcharge", "rain"]]:
		var staff: CompiledStaff = _staff(cards)
		check(not staff.wasted.has(0), "%s counts: %s" % [cards, staff.wasted])
