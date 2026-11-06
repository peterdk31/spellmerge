extends "res://tests/support/suite.gd"
## The fallback carriers (docs/CARRIERS.md, "The fallback carriers"; reading rule 5,
## docs/milestones/M2-staffs.md): the modifiers and infusions a group read with no carrier after
## them land on the caster (`caster`) or on a payload's origin (`point`), two carriers no form card
## fires. Which cards do something there follows from their yes/no answers and what each card needs,
## the same rule as on any carrier, and the runtime launches them like any other, so echo, recoil,
## mirror and penta reach them too. tests/core/test_card_rules.gd plays every card on both.
##
## godot --headless --path . --script res://tests/core/test_fallback_carriers.gd

const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")


func test_they_are_carriers_no_form_card_fires() -> void:
	var on_you: Carrier = Carriers.fallback(false)
	var there: Carrier = Carriers.fallback(true)
	check_equal(on_you.id(), Carriers.ON_CASTER, "a cast's own group lands on the caster")
	check_equal(there.id(), Carriers.AT_POINT, "a payload lands on its origin")
	check(on_you.hits() and there.hits(), "both strike what is there")
	check(on_you.has(CarrierTraits.MEETS_SHOTS) and not there.has(CarrierTraits.MEETS_SHOTS), "only the caster meets the shots that reach it")
	check(not on_you.has_wind_down() and not there.has_wind_down(), "no form card gives them a cooldown")
	for id: StringName in [Carriers.ON_CASTER, Carriers.AT_POINT]:
		check(not Carriers.ids().has(id), "%s is not among the carriers a form card may fire" % id)
		check(not Carriers.exists(id), "and a form card naming %s is refused" % id)


func test_a_card_lands_there_exactly_when_it_works_there() -> void:
	# `Spells.card_works` asked about a fallback carrier says what a compile of the lone card says.
	var arena := ArenaScript.new(root)
	var asked: int = 0
	for card: Variant in arena.registry.call("get_all", "spells"):
		if not (card is ModifierBase or card is ElementBase):
			continue
		var id: StringName = (card as SpellComponent).id
		var alone: CompiledStaff = arena.spells.compile_staff([id] as Array[StringName], ArenaScript.plain_staff(1))
		check_equal(not alone.wasted.has(0), arena.spells.card_works(id, Carriers.ON_CASTER), "%s alone, on you" % id)
		if not alone.wasted.has(0):
			check_equal(alone.casts[0].group.spells[0].carrier, Carriers.ON_CASTER, "%s lands on the caster's carrier" % id)
		var cards: Array[StringName] = [&"on_hit", &"bolt", id]
		var payload: CompiledStaff = arena.spells.compile_staff(cards, ArenaScript.plain_staff(3))
		check_equal(not payload.wasted.has(2), arena.spells.card_works(id, Carriers.AT_POINT), "%s alone in a payload, right there" % id)
		asked += 1
	arena.free_all()
	check(asked > 30, "every modifier and infusion was asked: %d" % asked)


func test_the_rule_decides_not_a_list() -> void:
	# What changed when the fallback became a carrier (owner, 2026-11-06): the cards that need a hit
	# work there now, and numbers it has no use for are wasted.
	var arena := ArenaScript.new(root)
	var lone: Callable = func(id: StringName) -> bool:
		return not arena.spells.compile_staff([id] as Array[StringName], ArenaScript.plain_staff(1)).wasted.has(0)
	check(lone.call(&"chain"), "a lone chain jumps on from what the strike hits")
	check(lone.call(&"pull"), "a lone pull pulls the caster to what it hits")
	check(lone.call(&"penta"), "a lone penta strikes from a ring round the caster")
	check(lone.call(&"deflect"), "a lone deflect turns the shots round the caster")
	check(not lone.call(&"split"), "a lone split is wasted: the strike fires no shots")
	check(not lone.call(&"short_delay"), "a lone short delay is wasted: there is no cooldown to shorten")
	check(not lone.call(&"hold"), "a lone hold is wasted: the strike is over at once")
	var there: CompiledStaff = arena.spells.compile_staff([&"on_hit", &"bolt", &"shield"] as Array[StringName], ArenaScript.plain_staff(3))
	check(there.wasted.has(2), "a shield on a point guards no one")
	arena.free_all()


func test_an_echo_on_the_caster_strikes_again() -> void:
	# Regression: a lone echo was kept on the caster but the strike never echoed.
	check(_caster_lost(["echo", "blast"]) > _caster_lost(["blast"]), "the echo strikes the caster a second time")


func test_a_recoil_on_the_caster_pushes_it() -> void:
	# Regression: a lone recoil was kept on the caster but pushed no one.
	var arena := ArenaScript.new(root)
	arena.add_guard(0, Vector2.ZERO)
	arena.install_cards(0, 0, ["recoil", "fire"])
	arena.cast(0, 0)
	arena.run(0.3)
	check_equal(arena.caster_moves.size(), 1, "the caster is pushed back: %s" % [arena.caster_moves])
	arena.free_all()


func test_a_deflect_on_the_caster_turns_a_shot_that_reaches_it() -> void:
	var arena := ArenaScript.new(root)
	arena.add_guard(0, Vector2.ZERO)
	arena.install_cards(0, 0, ["deflect", "fire"])
	arena.shoot_at(Vector2(60.0, 0.0), Vector2.ZERO)
	var cast: bool = false
	for step in 120:
		arena.run(1.0 / 60.0)
		if not cast and arena.projectiles.shots_on_segment(0, Vector2.ZERO, Vector2.ZERO, SpellLimits.MOVE_GUARD_REACH) > 0:
			cast = arena.cast(0, 0)
	check(cast, "the wizard cast as the shot came near")
	check(not arena.deflects.is_empty(), "and turned it: %s" % [arena.deflects])
	arena.free_all()


## Health the caster lost (standing at its hand) after `cards` were cast alone.
func _caster_lost(cards: Array) -> int:
	var arena := ArenaScript.new(root)
	var body: Node2D = arena.add_guard(0, Vector2.ZERO)
	arena.install_cards(0, 0, cards)
	arena.cast(0, 0)
	arena.run(2.0)
	var lost: int = arena.lost(body)
	arena.free_all()
	return lost
