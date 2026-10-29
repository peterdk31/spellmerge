extends "res://tests/support/suite.gd"
## The compiler's one table of behaviour x carrier (phase R, R2a, docs/milestones/M2-rules.md,
## rule 1: works or wasted): every behaviour on every motion either runs or is wasted with a
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


func test_every_cell_runs_or_says_why() -> void:
	for behaviour: int in ModifierBase.Behaviour.values():
		for motion: int in FormBase.Motion.values():
			var why: String = StaffCompiler.behaviour_waste(behaviour, motion)
			check_equal(StaffCompiler.behaviour_runs(behaviour, motion), why.is_empty(), "runs and reason agree for %s on %s" % [ModifierBase.Behaviour.keys()[behaviour], FormBase.Motion.keys()[motion]])
			check(why.length() < 120, "a short reason for %s on %s: %s" % [ModifierBase.Behaviour.keys()[behaviour], FormBase.Motion.keys()[motion], why])


func test_a_bolt_runs_every_behaviour() -> void:
	for behaviour: int in ModifierBase.Behaviour.values():
		check(StaffCompiler.behaviour_runs(behaviour, FormBase.Motion.STRAIGHT), "%s runs on a bolt" % ModifierBase.Behaviour.keys()[behaviour])


func test_cards_that_did_nothing_silently_are_listed() -> void:
	# Cells the audit found silent (M2-rules.md findings 4, 5, 6, 9), now wasted with a reason.
	for cards: Array in [["heavy", "dash"], ["chain", "teleport"], ["growth", "rune"], ["sticky", "orbit"], ["linger", "wall"], ["linger", "beam"], ["magnet", "fissure"], ["growth", "fissure"], ["mirror", "hook"], ["siphon", "decoy"], ["shield", "rain"], ["hold", "fissure"]]:
		var staff: CompiledStaff = _staff(cards)
		check(staff.wasted.has(0), "%s is listed as wasted: %s" % [cards, staff.wasted])
		check(staff.wasted.has(0) and not String(staff.wasted[0]).is_empty(), "with a reason")


func test_cards_that_work_are_not_listed() -> void:
	for cards: Array in [["heavy", "bolt"], ["bounce", "beam"], ["chain", "swing"], ["shield", "beam"], ["mirror", "swing"], ["growth", "hook"], ["magnet", "rune"], ["arc", "wall"], ["blast", "rain"], ["shield", "dash"], ["ghost", "beam"], ["magnet", "beam"], ["relay", "fissure"], ["spiral", "beam"], ["growth", "beam"], ["ghost", "fissure"]]:
		var staff: CompiledStaff = _staff(cards)
		check(not staff.wasted.has(0), "%s counts: %s" % [cards, staff.wasted])


func test_heavy_counts_on_a_dash_with_a_blast() -> void:
	# The blast's area hit is the dash's hit: heavy's knockback and slam ride on it.
	var staff: CompiledStaff = _staff(["heavy", "blast", "dash"])
	check(not staff.wasted.has(0), "heavy counts with a blast: %s" % staff.wasted)
	check(staff.casts[0].group.spells[0].hit.slam > 0, "the blast slams")
	check(_staff(["siphon", "blast", "dash"]).wasted.has(0), "siphon still does not: a blast is no shot hit")


func test_a_wasted_card_changes_nothing_else() -> void:
	# Heavy slows what it is on; wasted on a dash, the dash is as fast as a plain one.
	var plain: CompiledSpell = _staff(["dash"]).casts[0].group.spells[0]
	var heavy: CompiledSpell = _staff(["heavy", "dash"]).casts[0].group.spells[0]
	check_equal(heavy.speed, plain.speed, "the same speed")
	check_equal(heavy.behaviour(ModifierBase.Behaviour.HEAVY), 0.0, "no heavy strength")


func test_infusions_and_numbers_that_mean_nothing_are_listed() -> void:
	# Found by tests/core/test_card_rules.gd: silent on main before R2.
	for cards: Array in [["fire", "dash"], ["frost", "decoy"], ["mend", "rain"], ["overcharge", "teleport"], ["sniper", "rune"], ["split", "dash"], ["slow", "fissure"], ["pierce", "swing"], ["timer", "hook", "nova"], ["arc", "nova"]]:
		var staff: CompiledStaff = _staff(cards)
		check(staff.wasted.has(0), "%s is listed as wasted: %s" % [cards, staff.wasted])
	for cards: Array in [["fire", "blast", "dash"], ["overcharge", "blast", "teleport"], ["sniper", "bolt"], ["pierce", "rune"], ["timer", "bolt", "nova"], ["arc", "bolt"], ["slow", "bolt"]]:
		var staff: CompiledStaff = _staff(cards)
		check(not staff.wasted.has(0), "%s counts: %s" % [cards, staff.wasted])
