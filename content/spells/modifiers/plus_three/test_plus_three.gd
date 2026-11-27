extends "res://tests/support/card_rig.gd"
## The +3 card (content/spells/modifiers/plus_three/; the owner's decision of 2026-11-27, #972): three
## more shots in a fan, each with the spell's whole damage, for two and a half times the mana, rarer
## than +2 (complexity 3); stacked, the shots add (+2 +3 is six), and a beam's fan leaves from one
## short trunk.
func test_the_card_is_plus_three() -> void:
	_check_card(&"plus_three", 3)
	check_equal(_modifier(&"plus_three").behaviour, ModifierBase.Behaviour.NONE, "numbers only")
	check_equal(_modifier(&"plus_three").display_name, "+3", "named +3")


func test_it_works_for_all_four_players_at_once() -> void:
	# Each player's own target, rows 400 px apart: no homing or chain reach leaks across.
	var targets: Array[Node2D] = _four_players_cast([&"plus_three", &"bolt"])
	for player in 4:
		check(_mgr.get_count_for(player) > 0, "player %d has shots" % player)
	_tick(60)
	_check_own_targets_hit(targets, "plus_three")


func test_it_adds_three_shots_each_as_strong() -> void:
	var bare: CompiledSpell = _compile_with(&"bolt", [])
	var plus: CompiledSpell = _compile_with(&"bolt", [&"plus_three"])
	check_equal(plus.shots, bare.shots + 3, "three more shots")
	check_equal(plus.damage, bare.damage, "each as strong as the one")
	check(is_equal_approx(plus.mana_cost, bare.mana_cost * 2.5), "for two and a half times the mana")
	check(plus.spread > 0.0, "the shots fan out")


func test_it_throws_a_fan_of_four_and_hits_the_outer_targets() -> void:
	# The fan is 30 degrees wide: the outer shots leave 15 degrees to each side, the inner two 5.
	var left := _target(Vector2.from_angle(deg_to_rad(-15.0)) * 120.0)
	var right := _target(Vector2.from_angle(deg_to_rad(15.0)) * 120.0)
	_cast_with(&"bolt", [&"plus_three"], 0, Vector2.ZERO)
	check_equal(_mgr.get_count(), 4, "four shots in the air")
	_tick(40)
	var hit: Array = _hit_targets()
	check(hit.has(left) and hit.has(right), "each outer target was hit")


func test_stacked_the_shots_add() -> void:
	var bare: CompiledSpell = _compile_with(&"bolt", [])
	check_equal(_compile_with(&"bolt", [&"plus_three", &"plus_three"]).shots, 7, "+3 +3 is seven shots")
	check_equal(_compile_with(&"bolt", [&"plus_two", &"plus_three"]).shots, 6, "+2 +3 is six shots")
	check_equal(_compile_with(&"bolt", [&"plus_three", &"plus_three"]).damage, bare.damage, "each still as strong")
