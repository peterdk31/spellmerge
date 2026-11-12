extends "res://tests/support/card_rig.gd"
## The Homing card (content/spells/modifiers/homing/, M2 part 12): the shot curves toward a target beside its aim, a beam aims at one near its line; nothing without a target. Homing on every carrier card: test_homing_carriers.gd.
##
## godot --headless --path . --script res://content/spells/modifiers/homing/test_homing.gd


func test_the_card_is_homing() -> void:
	_check_card(&"homing", 2)
	check_equal(_modifier(&"homing").behaviour, ModifierBase.Behaviour.HOMING, "it homes")


func test_it_works_for_all_four_players_at_once() -> void:
	# Each player's own target, rows 400 px apart: no homing or chain reach leaks across.
	var targets: Array[Node2D] = _four_players_cast([&"homing", &"bolt"])
	for player in 4:
		check(_mgr.get_count_for(player) > 0, "player %d has shots" % player)
	_tick(60)
	_check_own_targets_hit(targets, "homing")


func test_homing_curves_toward_a_target_beside_the_aim() -> void:
	_target(Vector2(120.0, 40.0))
	_cast_with(&"bolt", [], 0, Vector2.ZERO)
	_tick(60)
	check_equal(_hits.size(), 0, "a bare bolt flies past a target that is not in its way")
	_spells.clear()
	_mgr.clear()
	var imp := _target(Vector2(120.0, 40.0))
	_cast_with(&"bolt", [&"homing"], 0, Vector2.ZERO)
	_tick(60)
	check_equal(_hit_targets(), [imp] as Array, "a homing bolt turns and hits it")


func test_homing_does_nothing_without_a_target() -> void:
	_cast_with(&"bolt", [&"homing"], 0, Vector2.ZERO)
	_tick(10)
	var slots: int = 0
	for slot in _mgr.get_cap():
		if _mgr.is_alive(slot):
			slots += 1
			check(_mgr.get_velocity_of(slot).normalized().is_equal_approx(Vector2.RIGHT), "the shot flies straight on")
	check_equal(slots, 1, "one shot")


func test_a_homing_beam_aims_at_a_target_near_its_line() -> void:
	var imp := _target(Vector2(150.0, 30.0))
	_cast_with(&"beam", [], 0, Vector2.ZERO)
	check_equal(_hits.size(), 0, "a bare beam misses it")
	_cast_with(&"beam", [&"homing"], 1, Vector2.ZERO)
	check_equal(_hit_targets(), [imp] as Array, "a homing beam turns toward it")


func test_a_homing_beam_finds_a_target_as_far_as_it_reaches() -> void:
	# Past the Homing card's reach (160 px) but within the beam's length, off its line.
	var imp := _target(Vector2(210.0, 60.0))
	_cast_with(&"beam", [], 0, Vector2.ZERO)
	check_equal(_hits.size(), 0, "a bare beam misses it")
	_cast_with(&"beam", [&"homing"], 1, Vector2.ZERO)
	check_equal(_hit_targets(), [imp] as Array, "a homing beam turns toward it all the same")
