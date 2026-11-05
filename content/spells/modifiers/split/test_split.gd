extends "res://tests/support/card_rig.gd"
## The Split card (content/spells/modifiers/split/, M2 part 12): three weaker shots in a fan; every split multiplies.
##
## godot --headless --path . --script res://content/spells/modifiers/split/test_split.gd


func test_the_card_is_split() -> void:
	_check_card(&"split", 2)
	check_equal(_modifier(&"split").behaviour, ModifierBase.Behaviour.NONE, "numbers only")


func test_it_works_for_all_four_players_at_once() -> void:
	# Each player's own target, rows 400 px apart: no homing or chain reach leaks across.
	var targets: Array[Node2D] = _four_players_cast([&"split", &"bolt"])
	for player in 4:
		check(_mgr.get_count_for(player) > 0, "player %d has shots" % player)
	_tick(60)
	_check_own_targets_hit(targets, "split")


func test_split_compiles_to_three_weaker_shots() -> void:
	var bare: CompiledSpell = _compile_with(&"bolt", [])
	var split: CompiledSpell = _compile_with(&"bolt", [&"split"])
	check_equal(split.shots, 3, "three shots")
	check(split.damage < bare.damage, "each shot is weaker")
	check(split.damage * split.shots > bare.damage, "but the three together are worth more than one")
	check(split.mana_cost > bare.mana_cost, "and it costs more mana")
	check(split.spread > 0.0, "the shots fan out")


func test_split_throws_a_fan_and_hits_three_targets_side_by_side() -> void:
	# The fan is 30 degrees wide, so the outer shots leave 15 degrees to each side.
	var left := _target(Vector2.from_angle(deg_to_rad(-15.0)) * 120.0)
	var middle := _target(Vector2(120.0, 0.0))
	var right := _target(Vector2.from_angle(deg_to_rad(15.0)) * 120.0)
	_cast_with(&"bolt", [&"split"], 0, Vector2.ZERO)
	check_equal(_mgr.get_count(), 3, "three shots in the air")
	_tick(40)
	var hit: Array = _hit_targets()
	check(hit.has(left) and hit.has(middle) and hit.has(right), "each target was hit")
	check_equal(hit.size(), 3, "once each")


func test_split_on_a_nova_has_no_shot_limit() -> void:
	var spell: CompiledSpell = _compile_with(&"nova", [&"split", &"split"])
	check_equal(spell.shots, _compile_with(&"nova", []).shots * 9, "every split multiplies: no build limit")
