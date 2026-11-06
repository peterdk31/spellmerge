extends "res://tests/support/suite.gd"
## The Faster Casting card (content/spells/modifiers/faster_casting/, cast timing T9; docs/
## milestones/cast-timing.md): the next carrier casts in half the time, its wind-up (a charge's
## too, in any slot order) and its wind-down, for a quarter more mana. It replaced Quicken and
## Short Delay.
##
## godot --headless --path . --script res://content/spells/modifiers/faster_casting/test_faster_casting.gd

const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")


func _card() -> ModifierBase:
	return load("res://content/spells/modifiers/faster_casting/faster_casting.tres") as ModifierBase


func _cast(cards: Array) -> CompiledCast:
	var arena := ArenaScript.new(root)
	var cast: CompiledCast = arena.install_cards(0, 0, cards).casts[0]
	arena.free_all()
	return cast


func test_the_card_is_a_valid_modifier() -> void:
	var card: ModifierBase = _card()
	check(card != null, "faster_casting.tres loads as a ModifierBase")
	if card == null:
		return
	check_equal(card.id, &"faster_casting", "its id is its folder")
	check_equal(card.display_name, "Faster Casting", "its name")
	check(card.wind_up_mult < 1.0 and card.wind_down_mult < 1.0, "it shortens both ends of a cast")
	check(card.range_problems().is_empty(), "inside every range: %s" % [card.range_problems()])


func test_it_halves_a_bolt_s_wind_down() -> void:
	var plain: CompiledCast = _cast(["bolt"])
	var fast: CompiledCast = _cast(["faster_casting", "bolt"])
	check(is_equal_approx(fast.wind_down, plain.wind_down * 0.5), "half the wind-down: %s of %s" % [fast.wind_down, plain.wind_down])
	check(not fast.wasted.has(0), "it works on a plain bolt")
	check(fast.mana > plain.mana, "for more mana: %s against %s" % [fast.mana, plain.mana])


func test_it_halves_a_charge_in_either_order() -> void:
	var charged: CompiledCast = _cast(["charge", "bolt"])
	var before: CompiledCast = _cast(["faster_casting", "charge", "bolt"])
	var after: CompiledCast = _cast(["charge", "faster_casting", "bolt"])
	check(is_equal_approx(before.wind_up, charged.wind_up * 0.5), "before the charge, half the wind-up: %s of %s" % [before.wind_up, charged.wind_up])
	check(is_equal_approx(after.wind_up, charged.wind_up * 0.5), "after it too: %s of %s" % [after.wind_up, charged.wind_up])


func test_it_quickens_a_charged_payload() -> void:
	# A payload adds no wind-down, but a charge there winds up where the trigger fired.
	var plain: CompiledCast = _cast(["on_hit", "bolt", "charge", "nova"])
	var fast: CompiledCast = _cast(["on_hit", "bolt", "faster_casting", "charge", "nova"])
	var plain_up: float = plain.group.spells[0].triggers[0].payload.wind_up
	var fast_up: float = fast.group.spells[0].triggers[0].payload.wind_up
	check(is_equal_approx(fast_up, plain_up * 0.5), "the payload winds up half as long: %s of %s" % [fast_up, plain_up])
	check(not fast.wasted.has(2), "it works there")


func test_it_is_wasted_on_a_plain_payload() -> void:
	# Nothing to shorten: no wind-down (a payload's) and no wind-up.
	var cast: CompiledCast = _cast(["on_hit", "bolt", "faster_casting", "nova"])
	check(cast.wasted.has(2), "a plain payload nova has no cast time to shorten")


func test_it_leaves_a_timer_s_own_tick() -> void:
	# The timer's pace is not a card's (owner, 2026-11-06: a staff or a relic, later).
	var plain: CompiledCast = _cast(["timer", "rune", "bolt"])
	var fast: CompiledCast = _cast(["timer", "rune", "faster_casting", "bolt"])
	check(is_equal_approx(fast.group.spells[0].triggers[0].interval, plain.group.spells[0].triggers[0].interval), "the tick is the timer's")
	check(fast.wasted.has(2), "and on the payload's plain bolt it is wasted")
