extends "res://tests/support/suite.gd"
## The Rain card (content/spells/forms/rain/, staffs C): a carrier that marks a spot ahead and
## drops the group after it there once its delay is over. The engine side is tested in
## `tests/core/test_spells_payload_carriers.gd`; here the card's data and its combos.
##
## godot --headless --path . --script res://tests/content/spells/test_rain.gd

const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")


func _lost(cards: Array, at: Vector2, seconds: float, player: int = 0) -> int:
	var arena := ArenaScript.new(root)
	var imp: Node2D = arena.add_imp(at)
	arena.install_cards(player, 0, cards)
	arena.cast(player, 0)
	arena.run(seconds)
	var lost: int = arena.lost(imp)
	arena.free_all()
	return lost


func test_the_card_is_a_valid_carrier() -> void:
	var card: FormBase = load("res://content/spells/forms/rain/rain.tres") as FormBase
	check(card != null, "rain.tres loads as a FormBase")
	if card == null:
		return
	check_equal(card.id, &"rain", "its id is its folder")
	check_equal(card.motion, FormBase.Motion.RAIN, "it rains")
	check(card.carries_payload(), "it reads a payload")
	check(card.lifetime > 0.0 and card.ray_length > 0.0, "it has a delay and a reach")
	check(card.range_problems().is_empty(), "inside every range: %s" % [card.range_problems()])


func test_a_nova_far_ahead_only_lands_with_rain() -> void:
	check_equal(_lost(["nova"], Vector2(120.0, 0.0), 2.0), 0, "a nova at your feet does not reach it")
	check(_lost(["rain", "nova"], Vector2(120.0, 0.0), 2.0) > 0, "the rained nova hurts the imp on the aim point")


func test_nothing_falls_before_the_delay() -> void:
	var card: FormBase = load("res://content/spells/forms/rain/rain.tres") as FormBase
	var delay: float = card.lifetime
	check_equal(_lost(["rain", "nova"], Vector2(120.0, 0.0), delay - 0.2), 0, "the marker comes first")
	check(_lost(["rain", "nova"], Vector2(120.0, 0.0), delay + 0.6) > 0, "it lands soon after the card's delay")


func test_a_rain_strikes_where_it_lands() -> void:
	# Rules R4g: the rain itself hits what is under it as it lands, with its own hit and cards.
	var card: FormBase = load("res://content/spells/forms/rain/rain.tres") as FormBase
	check_equal(_lost(["rain"], Vector2(120.0, 0.0), 2.0), card.base_damage, "an empty rain strikes the aim point")
	check_equal(_lost(["rain"], Vector2(160.0, 0.0), 2.0), 0, "only there")
	check(_lost(["overcharge", "rain"], Vector2(120.0, 0.0), 2.0) > card.base_damage, "its cards count: more damage")


func test_the_payload_costs_its_own_mana() -> void:
	var arena := ArenaScript.new(root)
	var alone: CompiledStaff = arena.install_cards(0, 0, ["rain"])
	var loaded: CompiledStaff = arena.install_cards(0, 1, ["rain", "nova"])
	if not alone.is_empty() and not loaded.is_empty():
		check(loaded.casts[0].mana > alone.casts[0].mana, "the nova adds to the rain's mana")
	arena.free_all()


func test_four_players_rain_at_once() -> void:
	var plain: int = _lost(["rain", "nova"], Vector2(120.0, 0.0), 2.0)
	var arena := ArenaScript.new(root)
	var imps: Array[Node2D] = []
	for player in 4:
		var at := Vector2(0.0, 150.0 * player)
		arena.place_caster(player, at)
		imps.append(arena.add_imp(at + Vector2(120.0, 0.0)))
		arena.install_cards(player, 0, ["rain", "nova"])
	for player in 4:
		check(arena.cast(player, 0), "player %d casts" % player)
	arena.run(2.0)
	for imp in imps:
		check_equal(arena.lost(imp), plain, "every imp on its player's aim point took the nova")
	arena.free_all()
