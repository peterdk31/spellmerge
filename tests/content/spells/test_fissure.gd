extends "res://tests/support/suite.gd"
## The Fissure card (content/spells/forms/fissure/, staffs C): a carrier that cracks the ground
## along a line and hits everything on it. The engine side is tested in
## `tests/core/test_spells_payload_carriers.gd`; here the card's data and its combos.
##
## godot --headless --path . --script res://tests/content/spells/test_fissure.gd

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
	var card: FormBase = load("res://content/spells/forms/fissure/fissure.tres") as FormBase
	check(card != null, "fissure.tres loads as a FormBase")
	if card == null:
		return
	check_equal(card.id, &"fissure", "its id is its folder")
	check_equal(card.motion, FormBase.Motion.FISSURE, "it is a fissure")
	check(card.ray_length > 0.0 and card.radius > 0.0, "it has a length and a width")
	check(card.base_damage > 0, "it hurts what it strikes")
	check(card.range_problems().is_empty(), "inside every range: %s" % [card.range_problems()])


func test_it_hurts_an_imp_on_the_line() -> void:
	check(_lost(["fissure"], Vector2(150.0, 0.0)) > 0, "the far imp on the line is hurt")
	check_equal(_lost(["fissure"], Vector2(150.0, 90.0)), 0, "an imp well off the line is not")


func test_it_hits_every_imp_on_the_line() -> void:
	var arena := ArenaScript.new(root)
	var near: Node2D = arena.add_imp(Vector2(60.0, 0.0))
	var far: Node2D = arena.add_imp(Vector2(150.0, 0.0))
	arena.install_cards(0, 0, ["fissure"])
	arena.cast(0, 0)
	arena.run(1.0)
	check(arena.lost(near) > 0, "the near imp is struck")
	check(arena.lost(far) > 0, "the far imp is struck too")
	arena.free_all()


func test_it_reaches_further_than_a_nova() -> void:
	check_equal(_lost(["nova"], Vector2(150.0, 0.0)), 0, "a nova does not reach 150 px")
	check(_lost(["fissure"], Vector2(150.0, 0.0)) > 0, "the fissure does")


func test_on_hit_nova_chills_an_imp_beside_the_line() -> void:
	var arena := ArenaScript.new(root)
	var on_line: Node2D = arena.add_imp(Vector2(100.0, 0.0))
	var beside: Node2D = arena.add_imp(Vector2(100.0, 24.0))
	arena.install_cards(0, 0, ["on_hit", "fissure", "frost", "nova"])
	arena.cast(0, 0)
	arena.run(1.5)
	check(arena.was_given(on_line, &"chill"), "the struck imp is chilled")
	check(arena.was_given(beside, &"chill"), "the nova set off on it chills its neighbour")
	arena.free_all()


func test_four_players_split_the_ground_at_once() -> void:
	var plain: int = _lost(["fissure"], Vector2(120.0, 0.0))
	var arena := ArenaScript.new(root)
	var imps: Array[Node2D] = []
	for player in 4:
		var at := Vector2(0.0, 200.0 * player)
		arena.place_caster(player, at)
		imps.append(arena.add_imp(at + Vector2(120.0, 0.0)))
		arena.install_cards(player, 0, ["fissure"])
	for player in 4:
		check(arena.cast(player, 0), "player %d casts" % player)
	arena.run(1.5)
	for imp in imps:
		check_equal(arena.lost(imp), plain, "every imp on its player's line took the same hit")
	arena.free_all()
