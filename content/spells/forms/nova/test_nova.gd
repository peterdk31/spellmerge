extends "res://tests/support/card_rig.gd"
## The Nova card (content/spells/forms/nova/, M2 part 10): a ring of shots in every direction, as far as its reach.
##
## godot --headless --path . --script res://content/spells/forms/nova/test_nova.gd


func test_the_card_is_a_nova() -> void:
	_check_card(&"nova", 2)
	check_equal(_form(&"nova").carrier, &"atom", "nova flies")


func test_it_works_for_all_four_players_at_once() -> void:
	_four_players_cast([&"nova"], false)
	for player in 4:
		check(_mgr.get_count_for(player) > 0, "player %d has shots" % player)


func test_the_nova_throws_a_ring_in_every_direction() -> void:
	var form: FormBase = _form(&"nova")
	check_equal(form.shots, 8, "eight shots")
	var around: Array[Node2D] = []
	for n in 8:
		around.append(_target(Vector2.from_angle(TAU * n / 8.0) * 45.0))
	_cast_form(&"nova", 0, Vector2.ZERO)
	check_equal(_mgr.get_count(), 8, "eight shots in the air")
	_tick(30)
	var hit: Array = _hit_targets()
	for n in 8:
		check(hit.has(around[n]), "the target at %d degrees was hit" % (45 * n))
	check_equal(hit.size(), 8, "each exactly once")


func test_the_nova_does_not_hit_past_its_reach() -> void:
	var form: FormBase = _form(&"nova")
	_target(Vector2(form.speed * form.lifetime + 60.0, 0.0))
	_cast_form(&"nova", 0, Vector2.ZERO)
	_tick(60)
	check_equal(_hits.size(), 0, "a target beyond the reach is not hit")


## Its looks (S6 2): the cue each moment plays (every cue a card names is a cue file:
## tests/content/spells/test_carrier_looks.gd).
func test_its_moments_have_their_cues() -> void:
	var card: FormBase = load("res://content/spells/forms/nova/nova.tres") as FormBase
	check_equal(card.shown_cue, &"nova", "its shown plays nova")
	check_equal(card.impact_cue, &"impact_ring", "its impact plays impact_ring")
	check_equal(card.cast_cue, &"cast_nova", "its cast plays cast_nova")
