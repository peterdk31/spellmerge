extends "res://tests/support/suite.gd"
## The fallback carriers (docs/CARRIERS.md, "The fallback carriers"; reading rule 5,
## docs/milestones/M2-staffs.md): the modifiers and infusions a group read with no carrier after
## them land on the caster (`caster`), on the body or shot that fired a payload (`bearer`), or on a
## payload's origin (`point`), three carriers no carrier card fires. Which cards do something there
## follows from their yes/no answers and what each card needs, the same rule as on any carrier, and
## the runtime launches them like any other, so echo, recoil, mirror and penta reach them too.
## tests/core/test_card_rules.gd plays every card on all three.
##
## godot --headless --path . --script res://tests/core/test_fallback_carriers.gd

const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")


func test_they_are_carriers_no_carrier_card_fires() -> void:
	var on_you: Carrier = Carriers.fallback(false)
	var there: Carrier = Carriers.fallback(true)
	check_equal(on_you.id(), Carriers.ON_CASTER, "a cast's own group lands on the caster")
	check_equal(there.id(), Carriers.AT_POINT, "a payload lands on its origin")
	check(on_you.hits() and there.hits(), "both strike what is there")
	check(on_you.has(CarrierTraits.MEETS_SHOTS) and not there.has(CarrierTraits.MEETS_SHOTS), "only the caster meets the shots that reach it")
	check(not on_you.has_wind_down() and not there.has_wind_down(), "no carrier card gives them a cooldown")
	var on_it: Carrier = Carriers.fallback(true, Carrier.BY_SHOT | Carrier.BY_POINT)
	check_equal(on_it.id(), Carriers.ON_BEARER, "a payload a shot or body may cast lands on it")
	check_equal(Carriers.fallback(true, Carrier.BY_POINT).id(), Carriers.AT_POINT, "one only a point casts lands there")
	check(on_it.hits() and on_it.has(CarrierTraits.MEETS_SHOTS) and not on_it.has_wind_down(), "what fired it is struck round and meets shots")
	check(there.has(CarrierTraits.CASTERLESS) and not on_it.has(CarrierTraits.CASTERLESS) and not on_you.has(CarrierTraits.CASTERLESS), "only a point has nothing to push")
	for id: StringName in [Carriers.ON_CASTER, Carriers.ON_BEARER, Carriers.AT_POINT]:
		check(not Carriers.ids().has(id), "%s is not among the carriers a carrier card may fire" % id)
		check(not Carriers.exists(id), "and a carrier card naming %s is refused" % id)


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
	check(not lone.call(&"faster_casting"), "a lone faster casting is wasted: there is no cast time to shorten")
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


## The fallback carrier `cards` land their last card on (`targets` of the last slot), or &"" when
## it is wasted.
func _lands_on(arena: ArenaScript, cards: Array) -> StringName:
	var ids: Array[StringName] = []
	for id: Variant in cards:
		ids.append(StringName(str(id)))
	var compiled: CompiledStaff = arena.spells.compile_staff(ids, ArenaScript.plain_staff(ids.size()))
	var last: int = ids.size() - 1
	if compiled.wasted.has(last):
		return &""
	match int(compiled.casts[0].targets.get(last, 0)):
		StaffCompiler.TARGET_CASTER:
			return Carriers.ON_CASTER
		StaffCompiler.TARGET_BEARER:
			return Carriers.ON_BEARER
		StaffCompiler.TARGET_POINT:
			return Carriers.AT_POINT
	return &"?"


func test_a_payloads_cards_land_on_what_fired_it() -> void:
	# Owner, 2026-11-06: on the body or shot that fired the payload, else on its point; the carriers
	# say which (`Carrier.payload_cast_by`), and a card is wasted only when none of them could use it.
	var arena := ArenaScript.new(root)
	check_equal(_lands_on(arena, ["timer", "bolt", "shield"]), Carriers.ON_BEARER, "a bolt's timer: on the bolt")
	check_equal(_lands_on(arena, ["on_hit", "pierce", "bolt", "shield"]), Carriers.ON_BEARER, "a piercing bolt's hit: on the bolt, which flies on")
	check_equal(_lands_on(arena, ["on_hit", "bolt", "shield"]), &"", "a spent bolt's hit: a point, so a shield is wasted")
	check_equal(_lands_on(arena, ["on_hit", "bolt", "fire"]), Carriers.AT_POINT, "and a fire lands there")
	check_equal(_lands_on(arena, ["on_hit", "sticky", "bolt", "shield"]), Carriers.ON_BEARER, "a sticky bolt's hit: on the bolt, stuck on")
	check_equal(_lands_on(arena, ["on_wall", "bounce", "bolt", "shield"]), Carriers.ON_BEARER, "a bouncing bolt's wall: on the bolt")
	check_equal(_lands_on(arena, ["on_wall", "bolt", "shield"]), &"", "a bolt that ends on the wall: a point")
	check_equal(_lands_on(arena, ["on_expire", "bolt", "shield"]), &"", "a bolt's end: a point")
	check_equal(_lands_on(arena, ["on_expire", "pull", "bolt", "shield"]), Carriers.ON_BEARER, "a pulling bolt's end: where its caster arrives")
	check_equal(_lands_on(arena, ["timer", "decoy", "shield"]), Carriers.ON_BEARER, "a decoy's timer: on its body")
	check_equal(_lands_on(arena, ["on_hurt", "decoy", "deflect"]), Carriers.ON_BEARER, "a decoy hurt: on its body")
	check_equal(_lands_on(arena, ["on_block", "shield", "decoy", "shield"]), Carriers.ON_BEARER, "a decoy's barrier blocks: on its body")
	check_equal(_lands_on(arena, ["on_block", "deflect", "decoy", "shield"]), &"", "a decoy's deflect: the turned shot's point")
	check_equal(_lands_on(arena, ["timer", "dash", "shield"]), Carriers.ON_BEARER, "a dash's timer: on the dashing body")
	check_equal(_lands_on(arena, ["on_expire", "teleport", "shield"]), Carriers.ON_BEARER, "a teleport's end: on the body it moved")
	check_equal(_lands_on(arena, ["on_cast", "bolt", "shield"]), Carriers.ON_BEARER, "on cast: on whoever cast the bolt")
	check_equal(_lands_on(arena, ["timer", "beam", "shield"]), &"", "a beam's tip: a point")
	check_equal(_lands_on(arena, ["timer", "familiar", "shield"]), &"", "a familiar's orb: a point")
	check_equal(_lands_on(arena, ["on_hit", "bolt", "recoil"]), &"", "recoil on a point: nothing to push")
	check_equal(_lands_on(arena, ["timer", "bolt", "recoil"]), Carriers.ON_BEARER, "recoil on the bolt pushes it")
	# Nested: a payload's carrier is cast by what fired that payload.
	check_equal(_lands_on(arena, ["timer", "bolt", "on_cast", "atom", "shield"]), Carriers.ON_BEARER, "on cast of an atom the bolt casts: on the bolt")
	check_equal(_lands_on(arena, ["on_hit", "bolt", "on_cast", "atom", "shield"]), &"", "on cast of an atom a point casts: wasted")
	check_equal(_lands_on(arena, ["on_hit", "bolt", "timer", "dash", "shield"]), Carriers.ON_BEARER, "a dash a point casts moves the wizard: on the wizard")
	arena.free_all()


func test_a_shield_landing_on_a_shot_gives_it_charges_and_a_deflect_makes_it_deflect() -> void:
	for card: String in ["shield", "deflect"]:
		var arena := ArenaScript.new(root)
		arena.install_cards(0, 0, ["timer", "bolt", card])
		arena.cast(0, 0)
		var bolt: int = -1
		for slot in arena.projectiles.get_cap():
			if arena.projectiles.is_alive(slot) and arena.projectiles.get_actor_of(slot) == 0:
				bolt = slot
		check(bolt >= 0, "%s: the bolt flies" % card)
		arena.run(0.25)
		var before: bool = arena.projectiles.get_shield_of(bolt) > 0 or arena.projectiles.is_deflecting(bolt)
		check(not before, "%s: nothing on it before its first tick" % card)
		arena.run(0.4)
		if card == "shield":
			check_equal(arena.projectiles.get_shield_of(bolt), 1, "a tick puts a shield charge on the bolt")
		else:
			check(arena.projectiles.is_deflecting(bolt), "a tick makes the bolt deflect")
		arena.free_all()


func test_a_shield_landing_on_the_caster_by_on_cast_or_a_dash_is_its_barrier() -> void:
	for cards: Array in [["on_cast", "bolt", "shield"], ["timer", "dash", "shield"]]:
		var arena := ArenaScript.new(root)
		arena.add_guard(0, Vector2.ZERO)
		var barriers: Array = []
		arena.bus.wizard_shield_requested.connect(func(actor: int, charges: int, _seconds: float, _tag: int) -> void: barriers.append([actor, charges]))
		arena.install_cards(0, 0, cards)
		arena.cast(0, 0)
		arena.run(0.4)
		check_equal(barriers, [[0, 1]], "%s: a barrier on the wizard" % [cards])
		arena.free_all()


func test_a_shield_landing_on_a_point_guards_no_one() -> void:
	# Forced past the waste table, the point still has no one to shield.
	StaffCompiler.keep_wasted = true
	var arena := ArenaScript.new(root)
	arena.add_imp(Vector2(60.0, 0.0))
	arena.add_guard(0, Vector2.ZERO)
	var barriers: Array = []
	arena.bus.wizard_shield_requested.connect(func(actor: int, _charges: int, _seconds: float, _tag: int) -> void: barriers.append(actor))
	arena.install_cards(0, 0, ["on_hit", "bolt", "shield"])
	arena.cast(0, 0)
	arena.run(1.0)
	StaffCompiler.keep_wasted = false
	check(arena.lost(arena.imps[0]) > 0, "the bolt hit")
	check(barriers.is_empty(), "and nobody got a barrier: %s" % [barriers])
	arena.free_all()
