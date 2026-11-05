extends "res://tests/support/card_rig.gd"
## The Chain card (content/spells/modifiers/chain/, M2 part 12): a hit jumps on to the nearest other targets, two jumps a card, no cap.
##
## godot --headless --path . --script res://content/spells/modifiers/chain/test_chain.gd


func test_the_card_is_chain() -> void:
	_check_card(&"chain", 2)
	check_equal(_modifier(&"chain").behaviour, ModifierBase.Behaviour.CHAIN, "it chains")


func test_it_works_for_all_four_players_at_once() -> void:
	# Each player's own target, rows 400 px apart: no homing or chain reach leaks across.
	var targets: Array[Node2D] = _four_players_cast([&"chain", &"bolt"])
	for player in 4:
		check(_mgr.get_count_for(player) > 0, "player %d has shots" % player)
	_tick(60)
	_check_own_targets_hit(targets, "chain")


func test_chain_jumps_on_to_the_nearest_other_targets() -> void:
	var first := _target(Vector2(80.0, 0.0))
	var second := _target(Vector2(80.0, 60.0))
	var third := _target(Vector2(80.0, 120.0))
	var far := _target(Vector2(80.0, 400.0))
	_cast_with(&"bolt", [&"chain"], 0, Vector2.ZERO)
	_tick(90)
	var hit: Array = _hit_targets()
	check_equal(hit.size(), 3, "the hit and two jumps")
	check(hit.has(first) and hit.has(second) and hit.has(third), "the three in a row")
	check(not hit.has(far), "a target out of range is left alone")


func test_chain_compiles_to_two_jumps_and_stacks() -> void:
	check_equal(_compile_with(&"bolt", [&"chain"]).chain_jumps, 2, "two jumps")
	check_equal(_compile_with(&"bolt", [&"chain", &"chain", &"chain", &"chain"]).chain_jumps, 8, "four chains jump eight times: no cap")


func test_a_bare_bolt_does_not_chain() -> void:
	_target(Vector2(80.0, 0.0))
	_target(Vector2(80.0, 60.0))
	_cast_with(&"bolt", [], 0, Vector2.ZERO)
	_tick(90)
	check_equal(_hits.size(), 1, "one hit")
