extends "res://tests/support/card_rig.gd"
## The On hit card (content/spells/triggers/on_hit/, M2 part 13): the held spell fires from where a shot lands, at every hit of a pierce, never without a hit.
##
## godot --headless --path . --script res://content/spells/triggers/on_hit/test_on_hit.gd


func before_each() -> void:
	super()
	_seat_wizards()

func test_the_card_is_on_hit() -> void:
	_check_card(&"on_hit", 1)
	check_equal(_trigger(&"on_hit").event, TriggerBase.Event.HIT, "its event")


func test_it_compiles_into_the_spell_numbers() -> void:
	var spell: CompiledSpell = _compile_recipe({"form": &"bolt", "trigger": &"on_hit", "held": {"form": &"nova"}})
	var trigger: TriggerBase = _trigger(&"on_hit")
	check_equal(spell.triggers.size(), 1, "one trigger")
	if spell.triggers.is_empty():
		return
	check_equal(spell.triggers[0].event, trigger.event, "the event is compiled")
	check_equal(spell.triggers[0].interval, 0.0, "no timer: no tick (docs/milestones/cast-timing.md, T8)")
	check(spell.payload != null and spell.payload.spells[0].form_id == &"nova", "the payload is the nova")


func test_it_works_for_all_four_players_at_once() -> void:
	# Each player has a row of their own, 400 px apart.
	for player in 4:
		var origin := Vector2(-600.0, -600.0 + 400.0 * player)
		_target(origin + Vector2(80.0, 0.0))
		_build_and_cast(player, 0, {"form": &"bolt", "trigger": &"on_hit", "held": {"form": &"bolt"}}, origin)
	_tick(100)
	for player in 4:
		var held_tag: int = _spells.current_tag(player, 0, 1)
		check_equal(_born(held_tag), 1, "player %d's held spell fired 1 time(s)" % player)
		check_equal(SpellTag.caster_of(held_tag), player, "and carries player %d's tag" % player)


func test_on_hit_fires_the_held_spell_from_the_hit_point() -> void:
	_target(Vector2(80.0, 0.0))
	_build_and_cast(0, 0, {"form": &"bolt", "trigger": &"on_hit", "held": {"form": &"nova"}})
	_tick(60)
	var held_tag: int = _spells.current_tag(0, 0, 1)
	var bolt_hits: int = 0
	for hit: Array in _hits:
		if SpellTag.node_of(hit[3] as int) == 0:
			bolt_hits += 1
	check_equal(bolt_hits, 1, "the bolt hit once")
	check_equal(_born(held_tag), 8, "and its nova of eight was born")
	check_equal(SpellTag.node_of(held_tag), 1, "at node 1")
	var hit_at: Vector2 = _hits[0][2]
	check(hit_at.x > 50.0 and hit_at.x < 90.0, "the hit was on the target")


func test_on_hit_does_not_fire_without_a_hit() -> void:
	_build_and_cast(0, 0, {"form": &"bolt", "trigger": &"on_hit", "held": {"form": &"nova"}})
	_tick(120)
	check_equal(_born(_spells.current_tag(0, 0, 1)), 0, "a bolt that hits nothing fires nothing")


func test_on_hit_fires_at_every_hit_of_a_pierce() -> void:
	_target(Vector2(60.0, 0.0))
	_target(Vector2(110.0, 0.0))
	_target(Vector2(160.0, 0.0))
	_build_and_cast(0, 0, {"form": &"bolt", "modifiers": [&"pierce"], "trigger": &"on_hit", "held": {"form": &"bolt"}})
	_tick(60)
	var from_pierce: int = 0
	for hit: Array in _hits:
		if SpellTag.node_of(hit[3] as int) == 0:
			from_pierce += 1
	check(from_pierce >= 2, "the pierce bolt hit more than one target")
	check_equal(_born(_spells.current_tag(0, 0, 1)), from_pierce, "and fired its held spell at every hit")


func test_a_trigger_with_nothing_after_its_carrier_is_wasted() -> void:
	var staff: CompiledStaff = StaffKit.compile(_spells, [&"on_hit", &"bolt"] as Array[StringName])
	check(staff.casts[0].group.spells[0].payload == null, "nothing to fire")
	check(staff.wasted.has(0), "the trigger is wasted, not refused")
