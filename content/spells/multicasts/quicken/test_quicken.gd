extends "res://tests/support/suite.gd"
## The Quicken card (content/spells/multicasts/quicken/, cast timing T8; docs/milestones/
## cast-timing.md): it halves the wind-up of the group it is read into, a charge's or a timer's
## tick, and is wasted where the group winds up nothing.
##
## godot --headless --path . --script res://content/spells/multicasts/quicken/test_quicken.gd

const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")


func _card() -> MulticastBase:
	return load("res://content/spells/multicasts/quicken/quicken.tres") as MulticastBase


func _cast(cards: Array) -> CompiledCast:
	var arena := ArenaScript.new(root)
	var cast: CompiledCast = arena.install_cards(0, 0, cards).casts[0]
	arena.free_all()
	return cast


func test_the_card_is_a_valid_multicast() -> void:
	var card: MulticastBase = _card()
	check(card != null, "quicken.tres loads as a MulticastBase")
	if card == null:
		return
	check_equal(card.id, &"quicken", "its id is its folder")
	check_equal(card.extra_draws, 0, "it adds no carrier")
	check(card.wind_up_mult < 1.0, "it shortens a wind-up")
	check(card.range_problems().is_empty(), "inside every range: %s" % [card.range_problems()])


func test_it_halves_a_charge() -> void:
	var charged: CompiledCast = _cast(["charge", "bolt"])
	var quick: CompiledCast = _cast(["quicken", "charge", "bolt"])
	check(is_equal_approx(quick.wind_up, charged.wind_up * 0.5), "half the wind-up: %s of %s" % [quick.wind_up, charged.wind_up])
	check(not quick.wasted.has(0), "it works there")


func test_it_quickens_a_timer() -> void:
	var plain: CompiledCast = _cast(["timer", "rune", "bolt"])
	var quick: CompiledCast = _cast(["timer", "rune", "quicken", "bolt"])
	var plain_tick: float = plain.group.spells[0].triggers[0].interval
	var quick_tick: float = quick.group.spells[0].triggers[0].interval
	check(is_equal_approx(quick_tick, plain_tick * 0.5), "the timer ticks twice as often: %s against %s" % [quick_tick, plain_tick])
	check(not quick.wasted.has(2), "it works in the timer's payload")


func test_it_is_wasted_where_nothing_winds_up() -> void:
	var cast: CompiledCast = _cast(["quicken", "bolt"])
	check(cast.wasted.has(0), "a plain bolt winds up nothing: quicken is wasted")
	check_equal(cast.mana, _cast(["bolt"]).mana, "and costs nothing")


## Health an imp 80 px ahead loses in two seconds to a rune casting bolts on a timer.
func _timer_damage(cards: Array) -> int:
	var arena := ArenaScript.new(root)
	var imp: Node2D = arena.add_imp(Vector2(80.0, 0.0))
	arena.install_cards(0, 0, cards)
	arena.cast(0, 0)
	arena.run(2.0)
	var lost: int = arena.lost(imp)
	arena.free_all()
	return lost


func test_a_quickened_timer_casts_more_often() -> void:
	var plain: int = _timer_damage(["timer", "rune", "bolt"])
	var quick: int = _timer_damage(["timer", "rune", "quicken", "bolt"])
	check(plain > 0 and quick > plain, "the quick timer's bolts hurt more in the same time: %d against %d" % [quick, plain])
