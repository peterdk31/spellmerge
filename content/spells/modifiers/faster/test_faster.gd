extends "res://tests/support/card_rig.gd"
## The Faster card (content/spells/modifiers/faster/, M2 part 12): a quicker shot and cooldown that arrives sooner; cards multiply.
##
## godot --headless --path . --script res://content/spells/modifiers/faster/test_faster.gd


func test_the_card_is_faster() -> void:
	_check_card(&"faster", 1)
	check_equal(_modifier(&"faster").behaviour, ModifierBase.Behaviour.NONE, "numbers only")


func test_it_works_for_all_four_players_at_once() -> void:
	# Each player's own target, rows 400 px apart: no homing or chain reach leaks across.
	var targets: Array[Node2D] = _four_players_cast([&"faster", &"bolt"])
	for player in 4:
		check(_mgr.get_count_for(player) > 0, "player %d has shots" % player)
	_tick(60)
	_check_own_targets_hit(targets, "faster")


func test_two_faster_cards_multiply_the_speed() -> void:
	check_equal(_compile_with(&"bolt", [&"faster", &"faster"]).speed, _form(&"bolt").speed * 1.5 * 1.5, "two faster modifiers multiply the speed")


func test_faster_compiles_to_a_quicker_shot_and_cooldown() -> void:
	var bare: CompiledSpell = _compile_with(&"bolt", [])
	var faster: CompiledSpell = _compile_with(&"bolt", [&"faster"])
	check(faster.speed > bare.speed, "quicker shot")
	check(faster.wind_down < bare.wind_down, "shorter cooldown")
	check(faster.damage < bare.damage, "but each shot is a little weaker")
	check(faster.damage / faster.wind_down > bare.damage / bare.wind_down, "and it is still worth more per second")


func test_faster_arrives_sooner() -> void:
	_target(Vector2(200.0, 0.0))
	_cast_with(&"bolt", [], 0, Vector2.ZERO)
	var bare: int = _steps_to_first_hit(120)
	_spells.clear()
	_mgr.clear()
	_hits.clear()
	_cast_with(&"bolt", [&"faster"], 0, Vector2.ZERO)
	var quick: int = _steps_to_first_hit(120)
	check(bare > 0 and quick > 0, "both arrive (%d, %d steps)" % [bare, quick])
	check(quick < bare, "the faster bolt arrives in fewer steps (%d against %d)" % [quick, bare])
