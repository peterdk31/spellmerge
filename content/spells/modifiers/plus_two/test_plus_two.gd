extends "res://tests/support/card_rig.gd"
## The +2 card (content/spells/modifiers/plus_two/; the owner's decision of 2026-11-27, #972, in
## place of Split): two more shots in a fan, each with the spell's whole damage, for twice the mana;
## stacked, the shots add (+2 +2 is five), and a beam fans into a beam a shot.
func test_the_card_is_plus_two() -> void:
	_check_card(&"plus_two", 2)
	check_equal(_modifier(&"plus_two").behaviour, ModifierBase.Behaviour.NONE, "numbers only")
	check_equal(_modifier(&"plus_two").display_name, "+2", "named +2")


func test_it_works_for_all_four_players_at_once() -> void:
	# Each player's own target, rows 400 px apart: no homing or chain reach leaks across.
	var targets: Array[Node2D] = _four_players_cast([&"plus_two", &"bolt"])
	for player in 4:
		check(_mgr.get_count_for(player) > 0, "player %d has shots" % player)
	_tick(60)
	_check_own_targets_hit(targets, "plus_two")


func test_it_adds_two_shots_each_as_strong() -> void:
	var bare: CompiledSpell = _compile_with(&"bolt", [])
	var plus: CompiledSpell = _compile_with(&"bolt", [&"plus_two"])
	check_equal(plus.shots, bare.shots + 2, "two more shots")
	check_equal(plus.damage, bare.damage, "each as strong as the one")
	check(is_equal_approx(plus.mana_cost, bare.mana_cost * 2.0), "for twice the mana")
	check(plus.spread > 0.0, "the shots fan out")


func test_it_throws_a_fan_and_hits_three_targets_side_by_side() -> void:
	# The fan is 30 degrees wide, so the outer shots leave 15 degrees to each side.
	var left := _target(Vector2.from_angle(deg_to_rad(-15.0)) * 120.0)
	var middle := _target(Vector2(120.0, 0.0))
	var right := _target(Vector2.from_angle(deg_to_rad(15.0)) * 120.0)
	_cast_with(&"bolt", [&"plus_two"], 0, Vector2.ZERO)
	check_equal(_mgr.get_count(), 3, "three shots in the air")
	_tick(40)
	var hit: Array = _hit_targets()
	check(hit.has(left) and hit.has(middle) and hit.has(right), "each target was hit")
	check_equal(hit.size(), 3, "once each")


func test_stacked_the_shots_add() -> void:
	var bare: CompiledSpell = _compile_with(&"bolt", [])
	check_equal(_compile_with(&"bolt", [&"plus_two", &"plus_two"]).shots, 5, "+2 +2 is five shots")
	check_equal(_compile_with(&"bolt", [&"plus_two", &"plus_three"]).shots, 6, "+2 +3 is six shots")
	check_equal(_compile_with(&"bolt", [&"plus_two", &"plus_two"]).damage, bare.damage, "each still as strong")
