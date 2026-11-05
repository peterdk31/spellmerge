extends "res://tests/support/card_rig.gd"
## Cards together, through the real spell runtime and projectile manager (from M2 parts 12 and
## 13): many modifiers on one carrier, several triggers on one carrier, payloads three and four
## levels deep, the three first triggers mixed, and the per-step fire cap with real triggers.
## Each card's own test is in its folder (content/spells/<kind>s/<id>/test_<id>.gd); these use the
## first cards (bolt, nova, rune, split, pierce, on hit, on expire, timer, on wall) as examples.
##
## godot --headless --path . --script res://tests/core/test_cards_together.gd


func before_each() -> void:
	super()
	_seat_wizards()


func test_many_modifiers_all_attach_to_one_carrier() -> void:
	var spell: CompiledSpell = _compile_with(&"bolt", [&"split", &"homing", &"chain", &"pierce", &"bigger"])
	check_equal(spell.modifier_ids.size(), 5, "no cap on modifiers: all five are on the bolt")


func test_two_triggers_fire_their_own_payloads() -> void:
	_target(Vector2(80.0, 0.0))
	# A piercing bolt: a nova when it hits, a bolt where it ends.
	var cards: Array[StringName] = [&"on_hit", &"on_expire", &"pierce", &"bolt", &"nova", &"bolt"]
	StaffKit.build(_spells, 0, 0, cards)
	check(_spells.cast_staff(0, 0, Vector2.ZERO, Vector2.RIGHT, 100.0) != SpellsScript.REFUSED, "it is cast")
	var nova_tag: int = _spells.current_tag(0, 0, 1)
	var bolt_tag: int = _spells.current_tag(0, 0, 2)
	_tick(40)
	check_equal(_born(nova_tag), 8, "the hit fired the nova of eight")
	check_equal(_born(bolt_tag), 0, "the end's bolt waits for the end")
	_tick(60)
	check_equal(_born(nova_tag), 8, "the end fires no nova")
	check_equal(_born(bolt_tag), 1, "and the end fired its own bolt")


func test_a_shot_ending_on_a_wall_fires_its_on_wall_and_its_on_expire() -> void:
	var walls: Array[Rect2] = [Rect2(100.0, -50.0, 50.0, 100.0)]
	_mgr.set_walls(walls)
	StaffKit.build(_spells, 0, 0, [&"on_wall", &"on_expire", &"bolt", &"nova", &"bolt"] as Array[StringName])
	_spells.cast_staff(0, 0, Vector2.ZERO, Vector2.RIGHT, 100.0)
	_tick(40)
	check_equal(_born(_spells.current_tag(0, 0, 1)), 8, "on wall fired the nova")
	check_equal(_born(_spells.current_tag(0, 0, 2)), 1, "and on expire the bolt")


func test_a_spell_three_levels_deep_fires_all_the_way_down() -> void:
	# The bolt hits the first target; the nova it fires hits the ring of targets round it;
	# each of those fires a bolt (depth 2).
	var center := Vector2(60.0, 0.0)
	_target(center)
	for n in 8:
		_target(center + Vector2.from_angle(TAU * n / 8.0 + 0.2) * 40.0, 4.0)
	var recipe: Dictionary = {
		"form": &"bolt", "trigger": &"on_hit",
		"held": {"form": &"nova", "trigger": &"on_hit", "held": {"form": &"bolt"}},
	}
	var spell: CompiledSpell = _compile_recipe(recipe)
	check_equal(spell.chain_length(), 3, "bolt, on hit, nova, on hit, bolt: three spells deep")
	_build_and_cast(0, 0, recipe)
	_tick(90)
	var depth_1: int = _born(_spells.current_tag(0, 0, 1))
	var depth_2: int = _born(_spells.current_tag(0, 0, 2))
	check_equal(depth_1, 8, "the nova of depth 1 was born")
	check(depth_2 >= 1, "and at least one bolt of depth 2 after it: %d" % depth_2)
	check(depth_2 <= 8, "no more than one per nova shot (each ends on its hit): %d" % depth_2)
	check_equal(SpellTag.node_of(_spells.current_tag(0, 0, 2)), 2, "the last level is depth 2")


func test_payloads_nest_as_deep_as_the_cards_go() -> void:
	var deep: Dictionary = {
		"form": &"bolt", "trigger": &"on_hit",
		"held": {"form": &"bolt", "trigger": &"on_expire", "held": {"form": &"bolt", "trigger": &"timer", "held": {"form": &"bolt"}}},
	}
	var spell: CompiledSpell = _compile_recipe(deep)
	check(spell != null and spell.chain_length() == 4, "four levels compile: there is no depth limit any more")


func test_the_three_triggers_mix_at_three_levels() -> void:
	# bolt -(on hit)-> rune -(timer)-> bolt: the rune is dropped where the bolt landed and then throws bolts.
	var victim: Node2D = _target(Vector2(60.0, 0.0))
	_build_and_cast(0, 0, {
		"form": &"bolt", "trigger": &"on_hit",
		"held": {"form": &"rune", "trigger": &"timer", "held": {"form": &"bolt"}},
	})
	for step in 60:
		_tick(1)
		if not _hits.is_empty():
			break
	# The target dies, so the rune (which does not pierce) is not used up on it.
	_mgr.remove_target(victim)
	_tick(150)
	check_equal(_born(_spells.current_tag(0, 0, 1)), 1, "the rune was dropped on the hit")
	check_equal(_born(_spells.current_tag(0, 0, 2)), 5, "it threw a bolt every half second, five in the 2.5 s")


func test_fires_past_a_steps_room_wait_for_the_next_step_with_the_real_triggers() -> void:
	for n in 24:
		_target(Vector2.from_angle(TAU * n / 24.0) * 40.0, 3.0)
	var hold: Dictionary = {"form": &"nova", "modifiers": [&"split"], "trigger": &"on_hit", "held": {"form": &"bolt"}}
	check_equal(_compile_recipe(hold).shots, 24, "the nova is 24 shots")
	_spells.fire_shots_per_step = 32
	_build_and_cast(0, 0, hold)
	_build_and_cast(0, 1, hold)
	var fired: int = 0
	for _i in 40:
		# The hits are in the manager's step; the runtime's step opens the next room.
		_mgr.step(DT)
		fired = _born(_spells.current_tag(0, 0, 1)) + _born(_spells.current_tag(0, 1, 1))
		if fired > 0:
			break
		_spells.step(DT)
	check_equal(fired, 32, "48 hits in one step: the step's room of 32 bolts fire at once")
	check_equal(_spells.fires_waited, 16, "the other 16 wait")
	_spells.step(DT)
	check_equal(_born(_spells.current_tag(0, 0, 1)) + _born(_spells.current_tag(0, 1, 1)), 48, "and fire as the next step opens: none is dropped")
