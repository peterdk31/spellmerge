extends "res://tests/support/card_rig.gd"
## The Bolt card (content/spells/forms/bolt/, M2 part 10): one shot that flies straight and hits, and ends after its lifetime.
##
## godot --headless --path . --script res://content/spells/forms/bolt/test_bolt.gd


func test_the_card_is_a_bolt() -> void:
	_check_card(&"bolt", 1)
	check_equal(_form(&"bolt").carrier, &"atom", "bolt flies (a bigger atom)")


func test_it_works_for_all_four_players_at_once() -> void:
	_four_players_cast([&"bolt"], false)
	for player in 4:
		check(_mgr.get_count_for(player) > 0, "player %d has shots" % player)


func test_the_bolt_is_one_shot_that_flies_straight_and_hits() -> void:
	var imp := _target(Vector2(100.0, 0.0))
	_target(Vector2(100.0, 60.0))
	var tag: int = _cast_form(&"bolt", 0, Vector2.ZERO)
	check_equal(_mgr.get_count(), 1, "one shot")
	_tick(30)
	check_equal(_hit_targets(), [imp] as Array, "it hit the imp in its way and not the one beside it")
	check_equal(_spells.hit_profile(tag).damage, _form(&"bolt").base_damage, "a bare bolt hits for its base damage")


func test_the_bolt_ends_after_its_lifetime() -> void:
	_cast_form(&"bolt", 0, Vector2.ZERO)
	_tick(ceili(_form(&"bolt").lifetime / DT) + 4)
	check_equal(_mgr.get_count(), 0, "the shot expired")


## Its looks (S6 2): the cue each moment plays (every cue a card names is a cue file:
## tests/content/spells/test_carrier_looks.gd).
func test_its_moments_have_their_cues() -> void:
	var card: FormBase = load("res://content/spells/forms/bolt/bolt.tres") as FormBase
	check_equal(card.impact_cue, &"impact", "its impact plays impact")
