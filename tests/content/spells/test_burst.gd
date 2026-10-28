extends "res://tests/support/suite.gd"
## The Burst card (content/spells/multicasts/burst/, staffs C): the next group fires three times,
## 0.1 s apart, for the mana of one cast. The engine side is tested in
## `tests/core/test_spells_multicast.gd`; here the card's data and its combos.
##
## godot --headless --path . --script res://tests/content/spells/test_burst.gd

const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")


func _lost(cards: Array, at: Vector2, seconds: float) -> int:
	var arena := ArenaScript.new(root)
	var imp: Node2D = arena.add_imp(at)
	arena.install_cards(0, 0, cards)
	arena.cast(0, 0)
	arena.run(seconds)
	var lost: int = arena.lost(imp)
	arena.free_all()
	return lost


func test_the_card_is_a_valid_multicast() -> void:
	var card: MulticastBase = load("res://content/spells/multicasts/burst/burst.tres") as MulticastBase
	check(card != null, "burst.tres loads as a MulticastBase")
	if card == null:
		return
	check_equal(card.id, &"burst", "its id is its folder")
	check_equal(card.mode, MulticastBase.Mode.BURST, "it bursts")
	check_equal(card.repeats, 3, "three firings")
	check_equal(card.repeat_interval, 0.1, "0.1 s apart")
	check_equal(card.extra_draws, 0, "it draws no extra carrier")
	check(card.range_problems().is_empty(), "inside every range: %s" % [card.range_problems()])


func test_the_bolt_hits_three_times() -> void:
	var plain: int = _lost(["bolt"], Vector2(100.0, 0.0), 1.5)
	check(plain > 0, "a plain bolt hurts")
	check_equal(_lost(["burst", "bolt"], Vector2(100.0, 0.0), 1.5), plain * 3, "three bolts, three hits")


func test_the_later_firings_come_after_the_first() -> void:
	var plain: int = _lost(["bolt"], Vector2(100.0, 0.0), 1.5)
	var early: int = _lost(["burst", "bolt"], Vector2(100.0, 0.0), 0.3)
	check(early < plain * 3, "not all three have hit by 0.3 s (%d of %d)" % [early, plain * 3])


func test_the_burst_costs_more_mana_than_the_bolt_alone() -> void:
	var arena := ArenaScript.new(root)
	var plain: CompiledStaff = arena.install_cards(0, 0, ["bolt"])
	var burst: CompiledStaff = arena.install_cards(0, 1, ["burst", "bolt"])
	check_equal(burst.casts[0].mana, plain.casts[0].mana + 4.0, "the card adds its 4 mana, once")
	arena.free_all()


func test_four_players_burst_at_once() -> void:
	var plain: int = _lost(["bolt"], Vector2(100.0, 0.0), 1.5)
	var arena := ArenaScript.new(root)
	var imps: Array[Node2D] = []
	for player in 4:
		var at := Vector2(0.0, 150.0 * player)
		arena.place_caster(player, at)
		imps.append(arena.add_imp(at + Vector2(100.0, 0.0)))
		arena.install_cards(player, 0, ["burst", "bolt"])
	for player in 4:
		check(arena.cast(player, 0), "player %d casts" % player)
	arena.run(1.5)
	for imp in imps:
		check_equal(arena.lost(imp), plain * 3, "every imp took three bolts")
	arena.free_all()
