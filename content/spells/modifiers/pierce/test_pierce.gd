extends "res://tests/support/card_rig.gd"
## The Pierce card (content/spells/modifiers/pierce/, M2 part 12): the shot passes through one more target in line (a beam reaches one further); cards add up.
##
## godot --headless --path . --script res://content/spells/modifiers/pierce/test_pierce.gd


func test_the_card_is_pierce() -> void:
	_check_card(&"pierce", 1)
	check_equal(_modifier(&"pierce").behaviour, ModifierBase.Behaviour.NONE, "numbers only")


func test_it_works_for_all_four_players_at_once() -> void:
	# Each player's own target, rows 400 px apart: no homing or chain reach leaks across.
	var targets: Array[Node2D] = _four_players_cast([&"pierce", &"bolt"])
	for player in 4:
		check(_mgr.get_count_for(player) > 0, "player %d has shots" % player)
	_tick(60)
	_check_own_targets_hit(targets, "pierce")


func test_two_pierce_cards_pierce_two() -> void:
	check_equal(_compile_with(&"bolt", [&"pierce", &"pierce"]).pierce, 2, "two pierce modifiers pierce two: one each")


func test_a_bare_bolt_stops_at_the_first_target() -> void:
	var first := _target(Vector2(60.0, 0.0))
	_target(Vector2(120.0, 0.0))
	_cast_with(&"bolt", [], 0, Vector2.ZERO)
	_tick(40)
	check_equal(_hit_targets(), [first] as Array, "only the first target is hit")


func test_pierce_passes_through_the_targets_in_line() -> void:
	var first := _target(Vector2(60.0, 0.0))
	var second := _target(Vector2(110.0, 0.0))
	var third := _target(Vector2(160.0, 0.0))
	var fourth := _target(Vector2(210.0, 0.0))
	_cast_with(&"bolt", [&"pierce"], 0, Vector2.ZERO)
	_tick(60)
	var hit: Array = _hit_targets()
	check_equal(hit.size(), 2, "one pierce card: one pierce, two targets")
	check(hit.has(first) and hit.has(second), "the first two in line")
	check(not hit.has(third) and not hit.has(fourth), "not the third or fourth")


func test_pierce_makes_a_beam_reach_further_down_the_line() -> void:
	for n in 5:
		_target(Vector2(50.0 + 40.0 * n, 0.0))
	_cast_with(&"beam", [], 0, Vector2.ZERO)
	var bare: int = _hits.size()
	_hits.clear()
	_cast_with(&"beam", [&"pierce"], 1, Vector2.ZERO)
	check_equal(_hits.size(), bare + 1, "one more target is hit")
