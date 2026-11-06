extends "res://tests/support/card_rig.gd"
## The Faster card (content/spells/modifiers/faster/, M2 part 12): a quicker shot that arrives sooner; cards
## multiply. It leaves the cast time alone: that is Faster Casting's (docs/milestones/cast-timing.md, T9).
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


func test_faster_compiles_to_a_quicker_shot_with_the_same_cast_time() -> void:
	var bare: CompiledSpell = _compile_with(&"bolt", [])
	var faster: CompiledSpell = _compile_with(&"bolt", [&"faster"])
	check(faster.speed > bare.speed, "quicker shot")
	check(is_equal_approx(faster.wind_down, bare.wind_down), "the same wind-down: casting faster is Faster Casting's")
	check(is_equal_approx(faster.wind_up, bare.wind_up), "and the same wind-up")
	check(faster.damage < bare.damage, "but each shot is a little weaker")


func test_faster_is_wasted_on_a_carrier_that_does_not_move() -> void:
	# Regression (2026-11-06): its old wind-down made it count on a teleport, which has no speed.
	check(not StaffCompiler.card_works(_modifier(&"faster"), &"teleport"), "a teleport has no speed, so faster does nothing there")
	for still: StringName in [&"decoy", &"familiar", &"portal"]:
		check(not StaffCompiler.card_works(_modifier(&"faster"), still), "a %s stands where it is made, so faster does nothing there" % still)
	check(StaffCompiler.card_works(_modifier(&"slow"), &"decoy"), "but a decoy lasts, so slow's longer life counts")
	check(StaffCompiler.card_works(_modifier(&"faster"), &"atom"), "a bolt's carrier flies, so it does")


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
