extends "res://tests/support/suite.gd"
## The Pulse card (content/spells/carriers/pulse/; props W9a, docs/CARRIERS.md "Pulse: a strike
## round what casts it"): one strike round whatever casts it, sparing that, then a short life for
## the triggers that need a carrier that lasts. One carrier (owner, 2026-11-12: "One carrier!"):
## round the caster in a cast's own group; in a payload round the body or shot that fired it, else
## round the point it began at, which the runtime knows when it fires. It replaced the compiler's
## fallback carriers (owner, 2026-11-12), so cards with no carrier after them are wasted. Which
## cards do something on it follows from its yes/no answers and what each card needs, as on any
## carrier; tests/core/test_card_rules.gd plays every card on it, on you and in a payload.
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
	check(pulse.has(CarrierTraits.MELEE), "it never leaves what casts it, so it never hits that")
	check(pulse.has(CarrierTraits.AOE), "it acts all round, not along an aim")
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
	# Owner, 2026-11-12: "Yes it spares its caster" (the fallback's strike hurt it).
	var arena := ArenaScript.new(root)
	var body: Node2D = arena.add_guard(0, Vector2.ZERO)
	arena.add_imp(Vector2(20.0, 0.0))
	arena.install_cards(0, 0, ["fire", "blast", "pulse"])
	arena.cast(0, 0)
	arena.run(1.0)
	check(arena.lost(arena.imps[0]) > 0, "the imp beside it is hit")
	check_equal(arena.lost(body), 0, "its caster is not")
	arena.free_all()


func test_a_bare_pulse_strikes_for_a_little() -> void:
	# Owner, 2026-11-12: "A bare pulse strikes for a small amount of damage (it hits everything
	# around it)".
	var bare: int = _imp_lost(["pulse"], 1.0)
	check(bare > 0, "a bare Pulse hits the imp beside its caster: %d" % bare)
	check(_imp_lost(["shield", "pulse"], 1.0) > 0, "so does one with only a shield")
	check(_imp_lost(["fire", "pulse"], 1.0) >= bare, "an infusion strikes as hard or harder")


func test_a_pulse_shows_itself_out_to_its_reach() -> void:
	# Owner, 2026-11-12: "It sends a mote pulse out from the caster/point" (its card's `shown_cue`).
	var card: CarrierCard = load("res://content/spells/carriers/pulse/pulse.tres") as CarrierCard
	check_equal(card.shown_cue, &"pulse", "its card shows the pulse cue")
	check(load("res://content/cues/pulse.tres") is CueBase, "and that cue exists")
	var shown: Array = _shown(["fire", "pulse"])
	check_equal(shown.size(), 1, "a fire Pulse shows itself once")
	if shown.size() == 1:
		check_equal(shown[0][0], &"pulse", "as the Pulse card")
		check(is_equal_approx(float(shown[0][1]), card.radius), "out to its reach: %s" % shown[0][1])
	check_equal(_shown(["pulse"]).size(), 1, "a bare Pulse strikes, so it shows itself too")


## The `carrier_shown` of a Pulse's card ([carrier card, length] each) after `cards` were cast once.
func _shown(cards: Array) -> Array:
	var arena := ArenaScript.new(root)
	arena.add_guard(0, Vector2.ZERO)
	var seen: Array = []
	arena.bus.carrier_shown.connect(func(_caster: int, carrier_card: StringName, _origin: Vector2, _direction: Vector2, length: float, _tint: Color, _look: int) -> void:
		if carrier_card == &"pulse":
			seen.append([carrier_card, length]))
	arena.install_cards(0, 0, cards)
	arena.cast(0, 0)
	arena.run(0.3)
	arena.free_all()
	return seen


func test_held_it_strikes_again_until_cast_again() -> void:
	var once: int = _imp_lost(["fire", "pulse"], 2.0)
	var held: int = _imp_lost(["hold", "fire", "pulse"], 2.0)
	check(held > once, "held, it strikes again and again: %d against %d" % [held, once])


func test_a_trigger_that_needs_a_carrier_that_lasts_fires_from_it() -> void:
	# Its short life carries a timer: the payload bolt leaves from the caster.
	var arena := ArenaScript.new(root)
	arena.add_guard(0, Vector2.ZERO)
	arena.add_imp(Vector2(70.0, 0.0))
	arena.install_cards(0, 0, ["timer", "pulse", "bolt"])
	var compiled: CompiledStaff = arena.spells.compile_staff([&"timer", &"pulse", &"bolt"] as Array[StringName], ArenaScript.plain_staff(3))
	check(not compiled.wasted.has(0), "a timer works on a Pulse")
	arena.cast(0, 0)
	arena.run(1.5)
	check(arena.lost(arena.imps[0]) > 0, "its payload bolt flew from the caster and hit")
	arena.free_all()


func test_on_expire_fires_from_what_it_is_round_as_it_ends() -> void:
	# Its own end is its life's: the payload leaves from the caster it was round, so it spares them.
	var arena := ArenaScript.new(root)
	var body: Node2D = arena.add_guard(0, Vector2.ZERO)
	arena.add_imp(Vector2(60.0, 0.0))
	arena.install_cards(0, 0, ["on_expire", "pulse", "bolt"])
	arena.cast(0, 0)
	arena.run(0.3)
	check_equal(arena.lost(arena.imps[0]), 0, "nothing yet: it lasts half a second")
	arena.run(1.0)
	check(arena.lost(arena.imps[0]) > 0, "as it ends, its bolt flew from the caster and hit")
	check_equal(arena.lost(body), 0, "and spared the caster it left")
	arena.free_all()


## Health the imp beside the caster lost after `cards` were cast once and `seconds` ran.
func _imp_lost(cards: Array, seconds: float) -> int:
	var arena := ArenaScript.new(root)
	arena.add_guard(0, Vector2.ZERO)
	arena.add_imp(Vector2(20.0, 0.0))
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


func test_a_deflect_on_it_turns_a_shot_that_reaches_the_caster() -> void:
	var arena := ArenaScript.new(root)
	arena.add_guard(0, Vector2.ZERO)
	arena.install_cards(0, 0, ["deflect", "fire", "pulse"])
	arena.shoot_at(Vector2(60.0, 0.0), Vector2.ZERO)
	var cast: bool = false
	for step in 120:
		arena.run(1.0 / 60.0)
		if not cast and arena.projectiles.shots_on_segment(0, Vector2.ZERO, Vector2.ZERO, SpellLimits.MOVE_GUARD_REACH) > 0:
			cast = arena.cast(0, 0)
	check(cast, "the wizard cast as the shot came near")
	check(not arena.deflects.is_empty(), "and turned it: %s" % [arena.deflects])
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


func test_a_shield_pulse_on_a_shot_gives_it_charges_and_a_deflect_makes_it_deflect() -> void:
	for card: String in ["shield", "deflect"]:
		var arena := ArenaScript.new(root)
		arena.install_cards(0, 0, ["timer", "bolt", card, "pulse"])
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


func test_a_shield_pulse_on_the_caster_by_on_cast_or_a_dash_is_its_barrier() -> void:
	for cards: Array in [["on_cast", "bolt", "shield", "pulse"], ["timer", "dash", "shield", "pulse"]]:
		var arena := ArenaScript.new(root)
		arena.add_guard(0, Vector2.ZERO)
		var barriers: Array = []
		arena.bus.wizard_shield_requested.connect(func(actor: int, charges: int, _seconds: float, _tag: int) -> void: barriers.append([actor, charges]))
		arena.install_cards(0, 0, cards)
		arena.cast(0, 0)
		arena.run(0.4)
		check_equal(barriers, [[0, 1]], "%s: a barrier on the wizard" % [cards])
		arena.free_all()


func test_a_shield_pulse_on_a_point_guards_no_one() -> void:
	# The point has no one to shield (what Shield does on a Pulse is still to be talked through with
	# the owner, 2026-11-12).
	var arena := ArenaScript.new(root)
	arena.add_imp(Vector2(60.0, 0.0))
	arena.add_guard(0, Vector2.ZERO)
	var barriers: Array = []
	arena.bus.wizard_shield_requested.connect(func(actor: int, _charges: int, _seconds: float, _tag: int) -> void: barriers.append(actor))
	arena.install_cards(0, 0, ["on_hit", "bolt", "shield", "pulse"])
	arena.cast(0, 0)
	arena.run(1.0)
	check(arena.lost(arena.imps[0]) > 0, "the bolt hit")
	check(barriers.is_empty(), "and nobody got a barrier: %s" % [barriers])
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
