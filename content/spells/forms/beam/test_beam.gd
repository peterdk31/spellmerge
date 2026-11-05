extends "res://tests/support/card_rig.gd"
## The Beam card (content/spells/forms/beam/, M2 part 10): a ray that hits along its line up to its reach, at once and every tick of its life; held, it stays on.
##
## godot --headless --path . --script res://content/spells/forms/beam/test_beam.gd


func test_the_card_is_a_beam() -> void:
	_check_card(&"beam", 2)
	check_equal(_form(&"beam").carrier, &"beam", "beam is a ray")
	check(_form(&"beam").ray_length > 0.0, "a beam has a reach")


func test_it_works_for_all_four_players_at_once() -> void:
	_four_players_cast([&"beam"], false)
	for player in 4:
		check_equal(_mgr.get_count_for(player), 0, "a ray holds no shot")


func test_the_beam_hits_along_a_line_up_to_its_reach_at_once() -> void:
	var near := _target(Vector2(60.0, 0.0))
	var second := _target(Vector2(120.0, 0.0))
	var third := _target(Vector2(180.0, 0.0))
	var beside := _target(Vector2(120.0, 50.0))
	_cast_form(&"beam", 0, Vector2.ZERO)
	check_equal(_form(&"beam").pierce, 0, "a beam pierces only with pierce cards")
	check_equal(_hit_targets(), [near] as Array, "a bare beam hits the nearest on the line and stops there")
	check(not _hit_targets().has(second) and not _hit_targets().has(third) and not _hit_targets().has(beside), "not the ones behind it nor the one beside it")
	check_equal(_mgr.get_count(), 0, "a beam holds no shot")


func test_one_beam_hits_at_once_and_every_tick_of_its_life() -> void:
	_target(Vector2(60.0, 0.0))
	var spell: CompiledSpell = StaffKit.first(_spells, [&"beam"] as Array[StringName])
	_cast_form(&"beam", 0, Vector2.ZERO)
	check_equal(_hits.size(), 1, "a hit at once")
	check_equal(CarrierBeam.of(_spells).beam_count(), 1, "and the beam stays on")
	_tick(60)
	var hits: int = Carriers.of(&"beam").hits_per_target(spell.lifetime)
	check_equal(_hits.size(), hits, "then one hit every %s s of its %s s life" % [SpellLimits.BEAM_TICK, spell.lifetime])
	check_equal(CarrierBeam.of(_spells).beam_count(), 0, "then it is gone")
	check_equal(spell.damage, 2, "a hit does 2 damage")


func test_a_held_beam_stays_on_and_drains_mana_steadily() -> void:
	_target(Vector2(60.0, 0.0))
	# A starter staff (the curl): the beam's life covers a whole cast cycle, so held fire leaves no gap.
	var staff: StaffBase = load("res://content/wizard/staffs/curl/curl.tres") as StaffBase
	_spells.install_staff(0, 0, _spells.compile_staff([&"beam"] as Array[StringName], staff))
	var spell: CompiledSpell = StaffKit.first(_spells, [&"beam"] as Array[StringName])
	var mana: float = 100.0
	var casts: int = 0
	var dark: int = 0
	# Fire is held for 2 seconds: the player casts whenever the staff allows.
	for i in 120:
		var taken: float = _spells.cast_staff(0, 0, Vector2.ZERO, Vector2.RIGHT, mana)
		if taken != SpellsScript.REFUSED:
			mana -= taken
			casts += 1
		if CarrierBeam.of(_spells).beam_count() == 0:
			dark += 1
		_tick(1)
	check_equal(dark, 0, "a beam is on in every step")
	check_equal(spell.mana_cost, 4.0, "a cast costs 4 mana")
	check(absf(100.0 - mana - 4.0 * casts) < 0.01, "each cast takes 4 mana (%f)" % mana)
	check(absi(_hits.size() - roundi(2.0 / SpellLimits.BEAM_TICK)) <= 3, "the enemy is hit about every %s s: %d hits" % [SpellLimits.BEAM_TICK, _hits.size()])


func test_the_beam_does_not_reach_past_its_length() -> void:
	_target(Vector2(_form(&"beam").ray_length + 40.0, 0.0))
	_cast_form(&"beam", 0, Vector2.ZERO)
	check_equal(_hits.size(), 0, "a target beyond the reach is safe")
