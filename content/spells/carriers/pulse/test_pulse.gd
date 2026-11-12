extends "res://tests/support/suite.gd"
## The Pulse card (content/spells/carriers/pulse/; props W9a, docs/CARRIERS.md "Pulse: a ring from
## the cast point"): a ring that grows from the point it is cast at as a shot flies (the shots' speed
## curve), striking each body its edge reaches once, sparing the body that cast it; its blast and
## `on expire` where it ends, at its centre. One carrier (owner, 2026-11-12: "One carrier!"). It
## replaced the compiler's fallback carriers (owner, 2026-11-12), so cards with no carrier after them
## are wasted. Which cards do something on it follows from its yes/no answers and what each card
## needs, as on any carrier; tests/core/test_card_rules.gd plays every card on it, on you and in a
## payload.
##
## godot --headless --path . --script res://content/spells/carriers/pulse/test_pulse.gd

const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")


func test_the_card_is_a_valid_carrier() -> void:
	var card: CarrierCard = load("res://content/spells/carriers/pulse/pulse.tres") as CarrierCard
	check(card != null, "pulse.tres loads as a CarrierCard")
	if card == null:
		return
	check_equal(card.id, &"pulse", "its id is its folder")
	check_equal(card.carrier, &"pulse", "it fires the Pulse carrier")
	check(card.range_problems().is_empty(), "inside every range: %s" % [card.range_problems()])
	check(card.look_problems().is_empty(), "its look is one the game draws: %s" % [card.look_problems()])


func test_it_is_one_carrier_that_acts_round_what_casts_it() -> void:
	var pulse: Carrier = Carriers.of(&"pulse")
	check_equal(pulse.id(), &"pulse", "a card may name the Pulse carrier")
	check(Carriers.ids().has(&"pulse"), "and it is among the carriers")
	check(pulse.hits() and pulse.lasts(), "it strikes what is there and lasts a moment, for its triggers")
	check(pulse.has(CarrierTraits.MEETS_SHOTS), "it meets the shots that reach what casts it")
	check(pulse.has(CarrierTraits.GUARDS), "a shield or deflect on it guards the shots inside it")
	check(pulse.has(CarrierTraits.AOE), "it goes out all round its cast point, not along an aim")
	for gone: StringName in [&"pulse_bearer", &"pulse_point"]:
		check(not Carriers.exists(gone), "no %s: the runtime knows what casts it" % gone)


func test_cards_with_no_carrier_after_them_are_wasted() -> void:
	# Owner, 2026-11-12: the fallback was a rule of the compiler; now a cast needs a carrier card.
	var arena := ArenaScript.new(root)
	var lone: CompiledStaff = arena.spells.compile_staff([&"fire"] as Array[StringName], ArenaScript.plain_staff(1))
	check(lone.wasted.has(0), "a lone fire is wasted")
	check(lone.casts.is_empty() or lone.casts[0].group.is_empty(), "and casts nothing")
	var payload: CompiledStaff = arena.spells.compile_staff([&"on_hit", &"bolt", &"blast"] as Array[StringName], ArenaScript.plain_staff(3))
	check(payload.wasted.has(2), "a payload's blast with no carrier is wasted")
	check(not payload.wasted.has(1), "the bolt still flies")
	var with_pulse: CompiledStaff = arena.spells.compile_staff([&"on_hit", &"bolt", &"blast", &"pulse"] as Array[StringName], ArenaScript.plain_staff(4))
	check(not with_pulse.wasted.has(2) and not with_pulse.wasted.has(0), "with a Pulse after it, the blast goes off where the bolt hits")
	arena.free_all()


func test_a_card_works_on_it_exactly_when_it_works_there() -> void:
	# `Spells.card_works` asked about a Pulse carrier says what a compile of the card with a Pulse says.
	var arena := ArenaScript.new(root)
	var asked: int = 0
	for card: Variant in arena.registry.call("get_all", "spells"):
		if not (card is ModifierBase or card is ElementBase):
			continue
		var id: StringName = (card as SpellComponent).id
		var alone: CompiledStaff = arena.spells.compile_staff([id, &"pulse"] as Array[StringName], ArenaScript.plain_staff(2))
		check_equal(not alone.wasted.has(0), arena.spells.card_works(id, &"pulse"), "%s on a Pulse" % id)
		asked += 1
	arena.free_all()
	check(asked > 30, "every modifier and infusion was asked: %d" % asked)


func test_the_rule_decides_not_a_list() -> void:
	var arena := ArenaScript.new(root)
	var on_pulse: Callable = func(ids: Array) -> bool:
		var cards: Array[StringName] = []
		for id: Variant in ids:
			cards.append(StringName(str(id)))
		cards.append(&"pulse")
		return not arena.spells.compile_staff(cards, ArenaScript.plain_staff(cards.size())).wasted.has(0)
	check(on_pulse.call(["chain"]), "a chain jumps on from what the strike hits")
	check(on_pulse.call(["pull"]), "a pull pulls the caster to what it hits")
	check(on_pulse.call(["penta"]), "a penta strikes from a ring round the caster")
	check(on_pulse.call(["deflect"]), "a deflect turns the shots round the caster")
	check(on_pulse.call(["faster_casting"]), "faster casting halves its wind-down")
	check(not on_pulse.call(["split"]), "a split is wasted: the strike fires no shots")
	check(on_pulse.call(["hold"]), "a hold keeps even a bare Pulse striking")
	check(on_pulse.call(["recoil"]), "a recoil pushes its caster")
	arena.free_all()


func test_it_spares_what_casts_it() -> void:
	# Owner, 2026-11-12: "Yes it spares its caster" (its ring; a blast where it ends is a blast, which
	# hits its caster as every blast does: test_its_blast_goes_off_at_its_centre_as_it_ends).
	var arena := ArenaScript.new(root)
	var body: Node2D = arena.add_guard(0, Vector2.ZERO)
	arena.add_imp(Vector2(20.0, 0.0))
	arena.install_cards(0, 0, ["fire", "pulse"])
	arena.cast(0, 0)
	arena.run(1.0)
	check(arena.lost(arena.imps[0]) > 0, "the imp its ring reaches is hit")
	check_equal(arena.lost(body), 0, "its caster is not")
	arena.free_all()


func test_a_bare_pulse_strikes_for_a_little() -> void:
	# Owner, 2026-11-12: "A bare pulse strikes for a small amount of damage (it hits everything
	# around it)".
	var bare: int = _imp_lost(["pulse"], 1.0)
	check(bare > 0, "a bare Pulse hits the imp beside its caster: %d" % bare)
	check(_imp_lost(["shield", "pulse"], 1.0) > 0, "so does one with only a shield")
	check(_imp_lost(["fire", "pulse"], 1.0) >= bare, "an infusion strikes as hard or harder")


func test_its_ring_grows_and_strikes_as_it_reaches() -> void:
	# Owner, 2026-11-12: "It should emit a pulse going outwards from the cast point (using easing as
	# bolt/atom). It should not hit instantly".
	var arena := ArenaScript.new(root)
	arena.add_guard(0, Vector2.ZERO)
	arena.add_imp(Vector2(40.0, 0.0))
	arena.install_cards(0, 0, ["pulse"])
	arena.cast(0, 0)
	arena.run(1.0 / 60.0)
	var rings: CarrierPulse = CarrierPulse.of(arena.spells)
	check_equal(rings.pulse_count(), 1, "one ring")
	check_equal(arena.lost(arena.imps[0]), 0, "nothing is hit at once")
	var radius: float = 0.0
	var grew: bool = true
	for step in 30:
		arena.run(1.0 / 60.0)
		for at in rings.pulse_slots():
			if rings.pulse_on(at):
				grew = grew and rings.pulse_radius(at) >= radius
				radius = rings.pulse_radius(at)
	check(grew, "its ring only grows")
	check(arena.lost(arena.imps[0]) > 0, "the imp is hit once the ring reaches it")
	arena.free_all()


func test_its_ring_goes_as_far_as_a_shot_of_its_numbers_flies() -> void:
	# The same speed curve as a shot (`ProjectilesScript.speed_factor`, the manager's own sum inline):
	# a ring reaches where a shot of its speed and life gets to (the curve keeps its mean, 1).
	var arena := ArenaScript.new(root)
	arena.add_guard(0, Vector2.ZERO)
	var card: CarrierCard = load("res://content/spells/carriers/pulse/pulse.tres") as CarrierCard
	arena.install_cards(0, 0, ["pulse"])
	arena.cast(0, 0)
	var rings: CarrierPulse = CarrierPulse.of(arena.spells)
	var furthest: float = 0.0
	for step in 40:
		arena.run(1.0 / 60.0)
		for at in rings.pulse_slots():
			if rings.pulse_on(at):
				furthest = maxf(furthest, rings.pulse_radius(at))
	# In open space, clear of every body.
	var slot: int = arena.projectiles.spawn(0, Vector2(0.0, 300.0), Vector2.RIGHT * card.speed, card.lifetime, 1.0, 0)
	arena.projectiles.set_speed_curve(slot, SpellLimits.SHOT_SPEED_START, SpellLimits.SHOT_SPEED_END, SpellLimits.SHOT_SPEED_EASE)
	var flown: float = 0.0
	for step in 40:
		if arena.projectiles.is_alive(slot):
			flown = arena.projectiles.get_position_of(slot).x
		arena.run(1.0 / 60.0)
	check(absf(furthest - flown) < 2.0, "a ring and a shot of the same numbers go as far: %.1f and %.1f" % [furthest, flown])
	check(absf(furthest - card.speed * card.lifetime) < 3.0, "about speed x life: %.1f" % furthest)
	arena.free_all()


func test_its_blast_goes_off_at_its_centre_as_it_ends() -> void:
	# Owner, 2026-11-12: the blast where the ring ends, at its centre; a blast hits everyone in it,
	# its caster too ("Why did you add an exception for blast to spare its caster?").
	var arena := ArenaScript.new(root)
	var body: Node2D = arena.add_guard(0, Vector2.ZERO)
	arena.install_cards(0, 0, ["blast", "pulse"])
	arena.cast(0, 0)
	arena.run(0.2)
	check_equal(arena.lost(body), 0, "nothing while the ring is out")
	arena.run(0.6)
	check(arena.lost(body) > 0, "its blast at the centre as it ends hits the caster standing there")
	arena.free_all()


func test_return_brings_its_ring_back_striking_again() -> void:
	var once: int = _imp_lost(["fire", "pulse"], 2.0, Vector2(20.0, 0.0))
	var back: int = _imp_lost(["return", "fire", "pulse"], 2.0, Vector2(20.0, 0.0))
	check(back > once, "out and back, it strikes the imp twice: %d against %d" % [back, once])


func test_walls_stop_its_ring_and_ghost_takes_it_through() -> void:
	var wall: Rect2 = Rect2(14.0, -40.0, 4.0, 80.0)
	check_equal(_imp_lost(["fire", "pulse"], 1.0, Vector2(24.0, 0.0), wall), 0, "an imp behind a wall is not struck")
	check(_imp_lost(["ghost", "fire", "pulse"], 1.0, Vector2(24.0, 0.0), wall) > 0, "with ghost it is")


func test_held_it_strikes_again_until_cast_again() -> void:
	var once: int = _imp_lost(["fire", "pulse"], 2.0)
	var held: int = _imp_lost(["hold", "fire", "pulse"], 2.0)
	check(held > once, "held, it strikes again and again: %d against %d" % [held, once])


func test_a_trigger_that_needs_a_carrier_that_lasts_fires_from_its_centre() -> void:
	# Its life carries a timer: the payload bolt leaves from its centre, cast by that point.
	var arena := ArenaScript.new(root)
	var body: Node2D = arena.add_guard(0, Vector2.ZERO)
	arena.add_imp(Vector2(70.0, 0.0))
	arena.install_cards(0, 0, ["timer", "pulse", "bolt"])
	var compiled: CompiledStaff = arena.spells.compile_staff([&"timer", &"pulse", &"bolt"] as Array[StringName], ArenaScript.plain_staff(3))
	check(not compiled.wasted.has(0), "a timer works on a Pulse")
	arena.cast(0, 0)
	# The wizard steps off the centre (one standing there is hit: the next test).
	body.position = Vector2(0.0, 60.0)
	arena.run(1.5)
	check(arena.lost(arena.imps[0]) > 0, "its payload bolt flew from the centre and hit")
	arena.free_all()


func test_on_expire_fires_from_its_centre_cast_by_that_point() -> void:
	# Owner, 2026-11-12: "the bolt should hit the wizard if he is still standing at the cast point":
	# its end is a point's, as every carrier's that ends at a spot, with no exception for its caster.
	for stays: bool in [true, false]:
		var arena := ArenaScript.new(root)
		var body: Node2D = arena.add_guard(0, Vector2.ZERO)
		arena.add_imp(Vector2(60.0, 0.0))
		arena.install_cards(0, 0, ["on_expire", "pulse", "bolt"])
		arena.cast(0, 0)
		if not stays:
			body.position = Vector2(0.0, 60.0)
		arena.run(0.3)
		check_equal(arena.lost(arena.imps[0]), 0, "nothing yet: its ring is still out")
		arena.run(1.0)
		if stays:
			check(arena.lost(body) > 0, "a wizard still at the centre is hit by the bolt")
		else:
			check_equal(arena.lost(body), 0, "one who stepped away is not")
			check(arena.lost(arena.imps[0]) > 0, "and the bolt flies on to the imp")
		arena.free_all()


## Health the imp at `at` lost after `cards` were cast once and `seconds` ran (with a wall over
## `wall`, when it has an area).
func _imp_lost(cards: Array, seconds: float, at: Vector2 = Vector2(20.0, 0.0), wall: Rect2 = Rect2()) -> int:
	var arena := ArenaScript.new(root)
	arena.add_guard(0, Vector2.ZERO)
	arena.add_imp(at)
	if wall.has_area():
		arena.add_wall(wall)
	arena.install_cards(0, 0, cards)
	arena.cast(0, 0)
	arena.run(seconds)
	var lost: int = arena.lost(arena.imps[0])
	arena.free_all()
	return lost


func test_an_echo_on_it_strikes_again() -> void:
	# Regression: a lone echo was kept on the caster but the strike never echoed.
	check(_imp_lost(["echo", "blast", "pulse"], 2.0) > _imp_lost(["blast", "pulse"], 2.0), "the echo strikes a second time")


func test_a_recoil_on_it_pushes_its_caster() -> void:
	# Regression: a lone recoil was kept on the caster but pushed no one.
	var arena := ArenaScript.new(root)
	arena.add_guard(0, Vector2.ZERO)
	arena.install_cards(0, 0, ["recoil", "fire", "pulse"])
	arena.cast(0, 0)
	arena.run(0.3)
	check_equal(arena.caster_moves.size(), 1, "the caster is pushed back: %s" % [arena.caster_moves])
	arena.free_all()


func test_a_deflect_on_it_turns_the_shots_inside_its_ring() -> void:
	# As a slam's ring (`MEETS_SHOTS`, `GUARDS`): while it is out, the shots of other teams inside it.
	var arena := ArenaScript.new(root)
	arena.add_guard(0, Vector2.ZERO)
	arena.install_cards(0, 0, ["deflect", "pulse"])
	arena.shoot_at(Vector2(110.0, 0.0), Vector2.ZERO)
	var cast: bool = false
	for step in 120:
		arena.run(1.0 / 60.0)
		# Cast ahead of it: the ring has to grow out to meet it before it reaches the wizard.
		if not cast and arena.projectiles.shots_on_segment(0, Vector2.ZERO, Vector2.ZERO, 70.0) > 0:
			cast = arena.cast(0, 0)
	check(cast, "the wizard cast as the shot came near")
	check(not arena.deflects.is_empty(), "and its ring turned it: %s" % [arena.deflects])
	arena.free_all()


func test_a_payloads_pulse_strikes_round_where_its_spent_bolt_hit() -> void:
	# The bolt is spent by its hit, so the payload is cast by the point: its Pulse strikes round it,
	# reaching an imp the bolt never touched.
	var arena := ArenaScript.new(root)
	arena.add_guard(0, Vector2.ZERO)
	arena.add_imp(Vector2(60.0, 0.0))
	arena.add_imp(Vector2(60.0, 16.0))
	arena.install_cards(0, 0, ["on_hit", "bolt", "fire", "pulse"])
	arena.cast(0, 0)
	arena.run(1.0)
	check(arena.lost(arena.imps[0]) > 0, "the bolt hit the first imp")
	check(arena.lost(arena.imps[1]) > 0, "and the Pulse struck the one beside it")
	arena.free_all()


func test_an_on_expire_that_makes_room_in_a_full_decoy_pool_ends_only_the_oldest_decoys_entry() -> void:
	# Regression (review, 2026-11-12): a Pulse's entry left the live carriers after its `on expire`
	# fired; when that payload's decoy ended the oldest of a full pool, the oldest's entry left the
	# list first and moved it about, so the wrong entry was removed.
	var arena := ArenaScript.new(root)
	arena.add_entities()
	arena.add_guard(0, Vector2.ZERO)
	# `on hurt`: listed while each decoy lives, and quiet (no bolts for the stacked decoys to trade).
	arena.install_cards(0, 0, ["on_hurt", "decoy", "bolt"])
	var pool: int = (preload("res://gameplay/ai/entities.gd")).PER_PLAYER
	var cast: int = 0
	for step in 600:
		if cast == pool:
			break
		if arena.cast(0, 0):
			cast += 1
		arena.run(1.0 / 60.0)
	check_equal(cast, pool, "the decoy staff was cast %d times" % pool)
	check_equal(arena.spells._lc_count, pool, "each decoy's `on hurt` is listed")
	arena.install_cards(0, 1, ["on_expire", "pulse", "decoy"])
	# Cast away from the decoys, so the Pulse's strike does not end one of them first.
	arena.place_caster(0, Vector2(-300.0, 0.0))
	arena.cast(0, 1)
	arena.run(1.0)
	var staffs: Array[int] = []
	for i in arena.spells._lc_count:
		staffs.append(SpellTag.staff_of(arena.spells._lc_tag[i]))
	check_equal(staffs, [0, 0, 0] as Array[int], "the Pulse's end and the oldest decoy's `on hurt` left; the other decoys' stay")
	arena.free_all()


func test_on_expire_on_a_payloads_pulse_round_a_flying_bolt_fires_from_the_bolt() -> void:
	# A bolt's timer fires a Pulse round the bolt (what fired it); as the Pulse's life ends, its own
	# `on expire` fires a second bolt from where the first one is by then.
	var arena := ArenaScript.new(root)
	arena.add_guard(0, Vector2.ZERO)
	var compiled: CompiledStaff = arena.install_cards(0, 0, ["timer", "bolt", "on_expire", "pulse", "bolt"])
	check(compiled.wasted.is_empty(), "every card works: %s" % [compiled.wasted])
	arena.cast(0, 0)
	var furthest: float = 0.0
	var second: bool = false
	for step in 90:
		arena.run(1.0 / 60.0)
		var xs: Array[float] = []
		for slot in arena.projectiles.get_cap():
			if arena.projectiles.is_alive(slot) and arena.projectiles.get_actor_of(slot) == 0:
				xs.append(arena.projectiles.get_position_of(slot).x)
		if xs.size() >= 2:
			second = true
			xs.sort()
			furthest = xs[xs.size() - 2]
			break
	check(second, "a second bolt left")
	check(furthest > 40.0, "from far along the first bolt's flight, not from the wizard: %.1f" % furthest)
	arena.free_all()


func test_a_shield_on_it_stops_the_shots_inside_its_ring() -> void:
	var arena := ArenaScript.new(root)
	var body: Node2D = arena.add_guard(0, Vector2.ZERO)
	arena.install_cards(0, 0, ["shield", "pulse"])
	arena.shoot_at(Vector2(110.0, 0.0), Vector2.ZERO)
	var cast: bool = false
	for step in 120:
		arena.run(1.0 / 60.0)
		# Cast ahead of it: the ring has to grow out to meet it before it reaches the wizard.
		if not cast and arena.projectiles.shots_on_segment(0, Vector2.ZERO, Vector2.ZERO, 70.0) > 0:
			cast = arena.cast(0, 0)
	check(cast, "the wizard cast as the shot came near")
	check(not arena.blocks.is_empty(), "its ring stopped it: %s" % [arena.blocks])
	check_equal(arena.lost(body), 0, "and the wizard was not hit")
	arena.free_all()


func test_its_hit_is_where_its_edge_meets_the_body() -> void:
	# Owner, 2026-11-12: "It should fire from the edge": what its hit sets off (`on hit`) leaves from
	# where the ring met the body, not from its centre, where its caster may stand.
	var arena := ArenaScript.new(root)
	var body: Node2D = arena.add_guard(0, Vector2.ZERO)
	var imp: Node2D = arena.add_imp(Vector2(36.0, 0.0))
	var at: Array[Vector2] = []
	arena.bus.projectile_hit.connect(func(_caster: int, target: Node, point: Vector2, _tag: int, _shot: int) -> void:
		if target == imp:
			at.append(point))
	arena.install_cards(0, 0, ["on_hit", "pulse", "bolt"])
	arena.cast(0, 0)
	arena.run(1.0)
	check(not at.is_empty() and at[0].x > 20.0 and at[0].x <= 36.0, "struck where the edge met it: %s" % [at])
	check_equal(arena.lost(body), 0, "so its payload bolt does not leave through the caster")
	arena.free_all()


func test_a_wall_shadows_only_what_is_behind_it() -> void:
	# Owner, 2026-11-12: "Will the whole pulse stop, if the ring hits a wall anywhere?": no, each line
	# from its centre is stopped on its own.
	var arena := ArenaScript.new(root)
	arena.add_guard(0, Vector2.ZERO)
	arena.add_wall(Rect2(14.0, -12.0, 4.0, 24.0))
	var behind: Node2D = arena.add_imp(Vector2(26.0, 0.0))
	var open: Node2D = arena.add_imp(Vector2(-26.0, 0.0))
	arena.install_cards(0, 0, ["fire", "pulse"])
	arena.cast(0, 0)
	arena.run(1.0)
	check_equal(arena.lost(behind), 0, "the imp behind the wall is not struck")
	check(arena.lost(open) > 0, "the one on the open side is")
	arena.free_all()


func test_a_body_it_hits_shadows_the_ones_behind_it_unless_it_pierces() -> void:
	# Owner, 2026-11-12: "if an enemy is hit, that segment should stop propagating out (unless pierce
	# is on, obviously)".
	for cards: Array in [["fire", "pulse"], ["pierce", "fire", "pulse"]]:
		var arena := ArenaScript.new(root)
		arena.add_guard(0, Vector2.ZERO)
		var front: Node2D = arena.add_imp(Vector2(20.0, 0.0))
		var behind: Node2D = arena.add_imp(Vector2(40.0, 0.0))
		var aside: Node2D = arena.add_imp(Vector2(0.0, 40.0))
		arena.install_cards(0, 0, cards)
		arena.cast(0, 0)
		arena.run(1.0)
		check(arena.lost(front) > 0, "%s: the imp in front is struck" % [cards])
		check(arena.lost(aside) > 0, "%s: the rest of the ring goes on: the imp aside is struck" % [cards])
		if cards.has("pierce"):
			check(arena.lost(behind) > 0, "%s: with pierce it passes the first and strikes the one behind" % [cards])
		else:
			check_equal(arena.lost(behind), 0, "%s: the one behind is in its shadow" % [cards])
		arena.free_all()


func test_its_guard_follows_its_segments() -> void:
	# Owner, 2026-11-12: "They should follow the segments too": a shot behind a wall is not stopped.
	for walled: bool in [false, true]:
		var arena := ArenaScript.new(root)
		arena.add_guard(0, Vector2.ZERO)
		if walled:
			# Between the wizard and the shot's path, all along it.
			arena.add_wall(Rect2(-60.0, 12.0, 120.0, 4.0))
		arena.install_cards(0, 0, ["shield", "pulse"])
		arena.cast(0, 0)
		# A shot crossing below the wizard, through the ring, never coming at them.
		arena.shoot_at(Vector2(-60.0, 25.0), Vector2(60.0, 25.0))
		arena.run(0.5)
		if walled:
			check(arena.blocks.is_empty(), "behind a wall its ring does not stop it: %s" % [arena.blocks])
		else:
			check(not arena.blocks.is_empty(), "in the open its ring stops it: %s" % [arena.blocks])
		arena.free_all()


func test_only_what_its_edge_sweeps_is_struck() -> void:
	# Owner, 2026-11-12: "only the swept band should count": a body that comes inside the ring
	# behind its edge, after the edge has passed, is not struck.
	var arena := ArenaScript.new(root)
	arena.add_guard(0, Vector2.ZERO)
	var late: Node2D = arena.add_imp(Vector2(200.0, 0.0))
	arena.install_cards(0, 0, ["fire", "pulse"])
	arena.cast(0, 0)
	arena.run(0.25)
	var rings: CarrierPulse = CarrierPulse.of(arena.spells)
	check_equal(rings.pulse_count(), 1, "the ring is still out")
	# Into the ring, well inside its edge.
	late.global_position = Vector2(8.0, 0.0)
	arena.run(1.0)
	check_equal(arena.lost(late), 0, "the body that came in behind its edge is not struck")
	arena.free_all()


func test_return_strikes_a_body_that_moved_on_the_way_in() -> void:
	# Review, 2026-11-12: at the turn its segments are as when it was cast, so a body it struck that
	# has moved further out still meets it on the way in.
	var arena := ArenaScript.new(root)
	arena.add_guard(0, Vector2.ZERO)
	var imp: Node2D = arena.add_imp(Vector2(12.0, 0.0))
	var struck: Array[float] = []
	arena.bus.projectile_hit.connect(func(_caster: int, target: Node, _at: Vector2, _tag: int, _shot: int) -> void:
		if target == imp:
			struck.append(CarrierPulse.of(arena.spells).pulse_radius(0)))
	arena.install_cards(0, 0, ["return", "fire", "pulse"])
	arena.cast(0, 0)
	arena.run(0.08)
	check_equal(struck.size(), 1, "struck once on the way out")
	# Pushed further out, as a hit's knockback would.
	imp.global_position = Vector2(22.0, 0.0)
	arena.run(1.0)
	check_equal(struck.size(), 2, "and again on the way in: %s" % [struck])
	arena.free_all()


func test_a_payloads_ring_spares_the_body_it_starts_on() -> void:
	# Review, 2026-11-12: as every payload spares the body it starts touching (`Spells._launch`),
	# a ring where a bolt hit an imp does not strike that imp again; the one beside it, it does.
	var arena := ArenaScript.new(root)
	arena.add_guard(0, Vector2.ZERO)
	var hit: Node2D = arena.add_imp(Vector2(60.0, 0.0))
	var beside: Node2D = arena.add_imp(Vector2(60.0, 24.0))
	var on_hit: Array[int] = [0]
	arena.bus.projectile_hit.connect(func(_caster: int, target: Node, _at: Vector2, _tag: int, _shot: int) -> void:
		if target == hit:
			on_hit[0] += 1)
	arena.install_cards(0, 0, ["on_hit", "bolt", "fire", "pulse"])
	arena.cast(0, 0)
	arena.run(1.5)
	check_equal(on_hit[0], 1, "the imp the bolt hit is struck once, by the bolt")
	check(arena.lost(beside) > 0, "the one beside it is struck by the ring")
	arena.free_all()


func test_a_box_shadows_by_its_shape() -> void:
	# Review, 2026-11-12: a box (a prop) is judged by its own sides, not by the circle round it: a
	# long thin box end-on shadows only the lines it covers.
	var arena := ArenaScript.new(root)
	arena.add_guard(0, Vector2.ZERO)
	var box := Node2D.new()
	root.add_child(box)
	box.global_position = Vector2(30.0, 0.0)
	arena.combat.register_actor(box, 100.0, 1.0, 0, Vector2.ZERO, Vector2(12.0, 2.0))
	# A small body 18 degrees off the box's line: inside the shadow of the circle round the box
	# (26 degrees), outside the box's own (about 13).
	var aside := Node2D.new()
	root.add_child(aside)
	aside.global_position = Vector2(38.0, 12.4)
	arena.combat.register_actor(aside, 100.0, 1.0, 0, Vector2.ZERO, Vector2(1.0, 1.0))
	var struck: Array[Node] = []
	arena.bus.projectile_hit.connect(func(_caster: int, target: Node, _at: Vector2, _tag: int, _shot: int) -> void: struck.append(target))
	arena.install_cards(0, 0, ["fire", "pulse"])
	arena.cast(0, 0)
	arena.run(1.0)
	check(struck.has(box), "the box is struck")
	check(struck.has(aside), "and the body beside its line, not shadowed by the circle round the box")
	box.queue_free()
	aside.queue_free()
	arena.free_all()
