extends "res://tests/support/card_rig.gd"
## The Rune card (content/spells/forms/rune/, M2 part 10): it stays where it was placed and hits what walks in.
##
## godot --headless --path . --script res://content/spells/forms/rune/test_rune.gd


func test_the_card_is_a_rune() -> void:
	_check_card(&"rune", 2)
	check_equal(_form(&"rune").carrier, &"rune", "rune waits")


func test_it_works_for_all_four_players_at_once() -> void:
	_four_players_cast([&"rune"], false)
	for player in 4:
		check(_mgr.get_count_for(player) > 0, "player %d has shots" % player)


func test_the_rune_stays_where_it_was_cast_and_hits_what_walks_in() -> void:
	var tag: int = _cast_form(&"rune", 0, Vector2(50.0, 50.0))
	check_equal(_slots(tag).size(), 1, "one rune")
	_tick(90)
	# Placed a step ahead along the aim, twice its size (rules R4 F3).
	var placed: Vector2 = Vector2(50.0 + _form(&"rune").radius * 2.0, 50.0)
	check_equal(_mgr.get_position_of(_slots(tag)[0]), placed, "it did not move")
	check_equal(_hits.size(), 0, "nobody was near")
	var imp := _target(Vector2(300.0, 300.0))
	imp.global_position = placed + Vector2(5.0, 0.0)
	_tick(4)
	check_equal(_hit_targets(), [imp] as Array, "an imp that walks in is hit")


func test_the_rune_stays_when_the_caster_and_a_target_move_away() -> void:
	var tag: int = _cast_form(&"rune", 0, Vector2.ZERO)
	var imp := _target(Vector2(300.0, 0.0))
	_tick(30, {0: Vector2(200.0, 0.0)})
	imp.global_position = Vector2(400.0, 0.0)
	_tick(30, {0: Vector2(200.0, 0.0)})
	check_equal(_mgr.get_position_of(_slots(tag)[0]), Vector2(_form(&"rune").radius * 2.0, 0.0), "the rune stays where it was placed, a step ahead of the cast point")
	check_equal(_hits.size(), 0, "nobody was near it")


## Its looks (S6 2): the cue each moment plays (every cue a card names is a cue file:
## tests/content/spells/test_carrier_looks.gd).
func test_its_moments_have_their_cues() -> void:
	var card: FormBase = load("res://content/spells/forms/rune/rune.tres") as FormBase
	check_equal(card.impact_cue, &"rune_burst", "its impact plays rune_burst")
	check_equal(card.cast_cue, &"cast_rune", "its cast plays cast_rune")
