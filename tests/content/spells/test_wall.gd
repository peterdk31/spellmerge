extends "res://tests/support/suite.gd"
## The Wall card (content/spells/forms/wall/, staffs C): a carrier that raises a short-lived solid
## wall across the aim (rules R4 F6). The engine side is tested in
## `tests/core/test_spells_payload_carriers.gd`; here the card's data and its combos.
##
## godot --headless --path . --script res://tests/content/spells/test_wall.gd

const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")


func _lost(cards: Array, at: Vector2, seconds: float = 1.5) -> int:
	var arena := ArenaScript.new(root)
	var imp: Node2D = arena.add_imp(at)
	arena.install_cards(0, 0, cards)
	arena.cast(0, 0)
	arena.run(seconds)
	var lost: int = arena.lost(imp)
	arena.free_all()
	return lost


func test_the_card_is_a_valid_carrier() -> void:
	var card: FormBase = load("res://content/spells/forms/wall/wall.tres") as FormBase
	check(card != null, "wall.tres loads as a FormBase")
	if card == null:
		return
	check_equal(card.id, &"wall", "its id is its folder")
	check_equal(card.carrier, &"wall", "it is a wall")
	check(card.shots > 1 and card.spread > 0.0, "it is a row of several stones")
	check(card.lifetime > 0.0 and card.base_damage > 0, "the stones last and hurt")
	check(card.range_problems().is_empty(), "inside every range: %s" % [card.range_problems()])


func test_it_hurts_an_imp_at_its_stones() -> void:
	check(_lost(["wall"], Vector2(28.0, 0.0)) > 0, "an imp at the middle of the wall is hurt")
	check(_lost(["wall"], Vector2(28.0, 16.0)) > 0, "so is one near its end")
	check_equal(_lost(["wall"], Vector2(28.0, 70.0)), 0, "an imp well beside it is not")


func test_the_stones_wait_for_a_late_imp() -> void:
	var arena := ArenaScript.new(root)
	arena.install_cards(0, 0, ["wall"])
	arena.cast(0, 0)
	arena.run(1.0)
	var imp: Node2D = arena.add_imp(Vector2(28.0, 0.0))
	arena.run(0.5)
	check(arena.lost(imp) > 0, "an imp that arrives after the cast still meets the wall")
	arena.free_all()


func test_frost_wall_chills_both_ends_of_the_row() -> void:
	var arena := ArenaScript.new(root)
	var left: Node2D = arena.add_imp(Vector2(28.0, -18.0))
	var right: Node2D = arena.add_imp(Vector2(28.0, 18.0))
	arena.install_cards(0, 0, ["frost", "wall"])
	arena.cast(0, 0)
	arena.run(1.5)
	check(arena.was_given(left, &"chill"), "the imp at one end is chilled")
	check(arena.was_given(right, &"chill"), "the imp at the other end is chilled")
	arena.free_all()


func test_a_plain_frost_bolt_passes_between_them() -> void:
	var arena := ArenaScript.new(root)
	var left: Node2D = arena.add_imp(Vector2(28.0, -18.0))
	var right: Node2D = arena.add_imp(Vector2(28.0, 18.0))
	arena.install_cards(0, 0, ["frost"])
	arena.cast(0, 0)
	arena.run(1.5)
	check(not arena.was_given(left, &"chill") and not arena.was_given(right, &"chill"), "without the wall neither is chilled")
	arena.free_all()


func test_four_players_raise_walls_at_once() -> void:
	var plain: int = _lost(["wall"], Vector2(28.0, 0.0))
	var arena := ArenaScript.new(root)
	var imps: Array[Node2D] = []
	for player in 4:
		var at := Vector2(0.0, 200.0 * player)
		arena.place_caster(player, at)
		imps.append(arena.add_imp(at + Vector2(28.0, 0.0)))
		arena.install_cards(player, 0, ["wall"])
	for player in 4:
		check(arena.cast(player, 0), "player %d casts" % player)
	arena.run(1.5)
	for imp in imps:
		check_equal(arena.lost(imp), plain, "every imp at its player's wall took the same hit")
	arena.free_all()
