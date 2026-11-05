extends "res://tests/support/card_rig.gd"
## The Orbit card (content/spells/forms/orbit/, M2 part 10): orbs that circle their caster at the form's radius, follow it and hit what crosses them.
##
## godot --headless --path . --script res://content/spells/forms/orbit/test_orbit.gd


func test_the_card_is_a_orbit() -> void:
	_check_card(&"orbit", 2)
	check_equal(_form(&"orbit").carrier, &"orbit", "orbit circles")
	check(_form(&"orbit").orbit_radius > 0.0, "an orbit has a radius")


func test_it_works_for_all_four_players_at_once() -> void:
	_four_players_cast([&"orbit"], false)
	for player in 4:
		check(_mgr.get_count_for(player) > 0, "player %d has shots" % player)


func test_the_orbit_circles_its_caster_at_the_forms_radius() -> void:
	var form: FormBase = _form(&"orbit")
	var centre := Vector2(100.0, 100.0)
	var tag: int = _cast_form(&"orbit", 0, centre)
	_tick(1, {0: centre})
	check_equal(_slots(tag).size(), form.shots, "one orb per shot")
	var before: Array[Vector2] = []
	for slot in _slots(tag):
		before.append(_mgr.get_position_of(slot))
	_tick(40, {0: centre})
	var moved: bool = false
	var index: int = 0
	for slot in _slots(tag):
		check(is_equal_approx(_mgr.get_position_of(slot).distance_to(centre), form.orbit_radius), "orb %d stays at the radius" % index)
		moved = moved or not _mgr.get_position_of(slot).is_equal_approx(before[index])
		index += 1
	check(moved, "the orbs turn")


func test_the_orbit_follows_a_moving_caster() -> void:
	var form: FormBase = _form(&"orbit")
	var tag: int = _cast_form(&"orbit", 0, Vector2.ZERO)
	_tick(30, {0: Vector2(300.0, 0.0)})
	for slot in _slots(tag):
		check(is_equal_approx(_mgr.get_position_of(slot).distance_to(Vector2(300.0, 0.0)), form.orbit_radius), "the orb moved with the caster")


func test_the_orbit_hits_an_enemy_that_crosses_it() -> void:
	var form: FormBase = _form(&"orbit")
	var centre := Vector2.ZERO
	var imp := _target(Vector2(form.orbit_radius, 0.0))
	_cast_form(&"orbit", 0, centre)
	_tick(120, {0: centre})
	check(_hit_targets().has(imp), "an imp standing on the orbit is hit")
	check(_hits.size() < 12, "a pass hits once, not every step (%d hits in two seconds)" % _hits.size())


func test_the_orbit_ends_with_its_lifetime() -> void:
	var form: FormBase = _form(&"orbit")
	var tag: int = _cast_form(&"orbit", 0, Vector2.ZERO)
	_tick(ceili(form.lifetime / DT) + 4, {0: Vector2.ZERO})
	check_equal(_slots(tag).size(), 0, "the orbs are gone")
	check_equal(_spells.live_shots(tag), 0, "and counted as ended")


## Its looks (S6 2): the cue each moment plays (every cue a card names is a cue file:
## tests/content/spells/test_carrier_looks.gd).
func test_its_moments_have_their_cues() -> void:
	var card: FormBase = load("res://content/spells/forms/orbit/orbit.tres") as FormBase
	check_equal(card.cast_cue, &"cast_orbit", "its cast plays cast_orbit")
