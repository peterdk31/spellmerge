extends "res://tests/support/card_rig.gd"
## The On expire card (content/spells/triggers/on_expire/, M2 part 13): the held spell fires where the shot ended, in front of a wall it reached, not when it ended on a hit.
##
## godot --headless --path . --script res://content/spells/triggers/on_expire/test_on_expire.gd


func before_each() -> void:
	super()
	_seat_wizards()

func test_the_card_is_on_expire() -> void:
	_check_card(&"on_expire", 1)
	check_equal(_trigger(&"on_expire").event, TriggerBase.Event.EXPIRE, "its event")


func test_it_compiles_into_the_spell_numbers() -> void:
	var spell: CompiledSpell = _compile_recipe({"form": &"bolt", "trigger": &"on_expire", "held": {"form": &"bolt", "modifiers": [&"nova"]}})
	var trigger: TriggerBase = _trigger(&"on_expire")
	check_equal(spell.triggers.size(), 1, "one trigger")
	if spell.triggers.is_empty():
		return
	check_equal(spell.triggers[0].event, trigger.event, "the event is compiled")
	check_equal(spell.triggers[0].interval, 0.0, "no timer: no tick (docs/milestones/cast-timing.md, T8)")
	check(spell.payload != null and spell.payload.spells[0].carrier_card_id == &"bolt" and spell.payload.spells[0].nova_ways() == 8, "the payload is a nova of bolts")


func test_it_works_for_all_four_players_at_once() -> void:
	# Each player has a row of their own, 400 px apart.
	for player in 4:
		var origin := Vector2(-600.0, -600.0 + 400.0 * player)
		_build_and_cast(player, 0, {"form": &"bolt", "trigger": &"on_expire", "held": {"form": &"bolt"}}, origin)
	_tick(100)
	for player in 4:
		var held_tag: int = _spells.current_tag(player, 0, 1)
		check_equal(_born(held_tag), 1, "player %d's held spell fired 1 time(s)" % player)
		check_equal(SpellTag.caster_of(held_tag), player, "and carries player %d's tag" % player)


func test_on_expire_fires_where_the_shot_ended() -> void:
	_build_and_cast(0, 0, {"form": &"bolt", "trigger": &"on_expire", "held": {"form": &"bolt"}})
	var held_tag: int = _spells.current_tag(0, 0, 1)
	_tick(60)
	check_equal(_born(held_tag), 0, "nothing fires while the shot lives")
	_tick(30)
	check_equal(_born(held_tag), 1, "one held shot once the bolt's 1.2 s are up")
	var shots: Array[int] = _slots(held_tag)
	check_equal(shots.size(), 1, "and it is flying")
	if not shots.is_empty():
		check(_mgr.get_position_of(shots[0]).x > 200.0, "from far along the bolt's path")
		check(_mgr.get_velocity_of(shots[0]).normalized().is_equal_approx(Vector2.RIGHT), "the way the bolt was going")


func test_on_expire_at_a_wall_fires_in_front_of_it() -> void:
	var walls: Array[Rect2] = [Rect2(100.0, -50.0, 50.0, 100.0)]
	_mgr.set_walls(walls)
	_build_and_cast(0, 0, {"form": &"bolt", "trigger": &"on_expire", "held": {"form": &"bolt", "modifiers": [&"nova"]}})
	_tick(40)
	var held_tag: int = _spells.current_tag(0, 0, 1)
	check_equal(_born(held_tag), 8, "the nova fired when the bolt reached the wall")
	for slot in _slots(held_tag):
		check(_mgr.get_position_of(slot).x < 105.0, "and started on this side of it")


func test_on_expire_does_not_fire_when_the_shot_hit_something() -> void:
	_target(Vector2(60.0, 0.0))
	_build_and_cast(0, 0, {"form": &"bolt", "trigger": &"on_expire", "held": {"form": &"bolt", "modifiers": [&"nova"]}})
	_tick(120)
	check_equal(_hits.size(), 1, "the bolt hit the target")
	check_equal(_born(_spells.current_tag(0, 0, 1)), 0, "a shot that ends on a hit does not expire")
