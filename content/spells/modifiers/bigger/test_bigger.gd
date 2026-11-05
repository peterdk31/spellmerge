extends "res://tests/support/card_rig.gd"
## The Bigger card (content/spells/modifiers/bigger/, M2 part 12): a wider, slower, harder hit that catches what a bare bolt misses.
##
## godot --headless --path . --script res://content/spells/modifiers/bigger/test_bigger.gd


func test_the_card_is_bigger() -> void:
	_check_card(&"bigger", 1)
	check_equal(_modifier(&"bigger").behaviour, ModifierBase.Behaviour.NONE, "numbers only")


func test_it_works_for_all_four_players_at_once() -> void:
	# Each player's own target, rows 400 px apart: no homing or chain reach leaks across.
	var targets: Array[Node2D] = _four_players_cast([&"bigger", &"bolt"])
	for player in 4:
		check(_mgr.get_count_for(player) > 0, "player %d has shots" % player)
	_tick(60)
	_check_own_targets_hit(targets, "bigger")


func test_bigger_compiles_to_a_wider_slower_harder_hit() -> void:
	var bare: CompiledSpell = _compile_with(&"bolt", [])
	var bigger: CompiledSpell = _compile_with(&"bolt", [&"bigger"])
	check(bigger.radius > bare.radius, "wider")
	check(bigger.damage > bare.damage, "harder")
	check(bigger.speed < bare.speed, "slower")
	check(bigger.cooldown > bare.cooldown, "and the next cast comes later")


func test_bigger_hits_a_target_that_a_bare_bolt_misses() -> void:
	# 17 px beside the path: past a bare bolt (5 + 10), inside a bigger one (8 + 10).
	var imp := _target(Vector2(100.0, 17.0))
	_cast_with(&"bolt", [], 0, Vector2.ZERO)
	_tick(60)
	check_equal(_hits.size(), 0, "the bare bolt misses")
	_spells.clear()
	_mgr.clear()
	_cast_with(&"bolt", [&"bigger"], 0, Vector2.ZERO)
	_tick(60)
	check_equal(_hit_targets(), [imp] as Array, "the bigger bolt hits")
