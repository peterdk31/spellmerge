extends "res://tests/support/card_rig.gd"
## The Timer card (content/spells/triggers/timer/, M2 part 13): the held spell fires every half second from where its shot is, while the shot lives.
##
## godot --headless --path . --script res://content/spells/triggers/timer/test_timer.gd


func before_each() -> void:
	super()
	_seat_wizards()

func test_the_card_is_timer() -> void:
	_check_card(&"timer", 2)
	check_equal(_trigger(&"timer").event, TriggerBase.Event.TIMER, "its event")


func test_it_compiles_into_the_spell_numbers() -> void:
	var spell: CompiledSpell = _compile_recipe({"form": &"bolt", "trigger": &"timer", "held": {"form": &"bolt", "modifiers": [&"nova"]}})
	var trigger: TriggerBase = _trigger(&"timer")
	check_equal(spell.triggers.size(), 1, "one trigger")
	if spell.triggers.is_empty():
		return
	check_equal(spell.triggers[0].event, trigger.event, "the event is compiled")
	check_equal(spell.triggers[0].interval, trigger.wind_up, "its tick is its wind-up (its payload adds none here; docs/milestones/cast-timing.md, T8)")
	check(spell.payload != null and spell.payload.spells[0].form_id == &"bolt" and spell.payload.spells[0].nova_ways() == 8, "the payload is a nova of bolts")


func test_it_works_for_all_four_players_at_once() -> void:
	# Each player has a row of their own, 400 px apart.
	for player in 4:
		var origin := Vector2(-600.0, -600.0 + 400.0 * player)
		_build_and_cast(player, 0, {"form": &"rune", "trigger": &"timer", "held": {"form": &"bolt"}}, origin)
	_tick(100)
	for player in 4:
		var held_tag: int = _spells.current_tag(player, 0, 1)
		check_equal(_born(held_tag), 3, "player %d's held spell fired 3 time(s)" % player)
		check_equal(SpellTag.caster_of(held_tag), player, "and carries player %d's tag" % player)


func test_the_timer_waits_half_a_second() -> void:
	var timer: TriggerBase = _trigger(&"timer")
	check_equal(timer.wind_up, 0.5, "the timer ticks every half second (its wind-up; docs/milestones/cast-timing.md, T8)")
	check(not &"max_fires" in timer, "no trigger counts its fires (owner, 2026-10-29)")


func test_a_timer_fires_every_half_second_as_long_as_its_shot_lives() -> void:
	_build_and_cast(0, 0, {"form": &"rune", "trigger": &"timer", "held": {"form": &"bolt"}})
	var held_tag: int = _spells.current_tag(0, 0, 1)
	_tick(29)
	check_equal(_born(held_tag), 0, "nothing before half a second")
	_tick(3)
	check_equal(_born(held_tag), 1, "the first fire at 0.5 s")
	_tick(30)
	check_equal(_born(held_tag), 2, "the second at 1.0 s")
	_tick(60)
	check_equal(_born(held_tag), 4, "the fourth at 2.0 s")
	_tick(300)
	check_equal(_born(held_tag), 14, "and on, every half second, while the rune lives (7 s)")


func test_a_timer_fires_from_where_its_shot_is() -> void:
	_build_and_cast(0, 0, {"form": &"rune", "trigger": &"timer", "held": {"form": &"bolt"}}, Vector2(100.0, 50.0))
	_tick(32)
	var shots: Array[int] = _slots(_spells.current_tag(0, 0, 1))
	check_equal(shots.size(), 1, "one held shot")
	if not shots.is_empty():
		var at: Vector2 = _mgr.get_position_of(shots[0])
		# The rune stands twice its size ahead of where it was cast (rules R4 F3).
		var rune: Vector2 = Vector2(100.0 + (load("res://content/spells/carriers/rune/rune.tres") as FormBase).radius * 2.0, 50.0)
		check(at.distance_to(rune) < 20.0, "close to the rune that fired it")


func test_a_timer_stops_when_the_shot_ends() -> void:
	# A bolt lives 1.2 s: its timer fires at 0.5 s and 1.0 s only.
	_build_and_cast(0, 0, {"form": &"bolt", "trigger": &"timer", "held": {"form": &"bolt"}})
	_tick(200)
	check_equal(_born(_spells.current_tag(0, 0, 1)), 2, "two fires in the bolt's 1.2 s")
