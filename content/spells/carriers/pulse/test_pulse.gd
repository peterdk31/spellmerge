extends "res://tests/support/suite.gd"
## The Pulse card (content/spells/carriers/pulse/; props W9a, docs/CARRIERS.md "Pulse: a strike round what
## casts it"): one strike round whatever casts it, sparing that, then a short life for the triggers
## that need a carrier that lasts. Its carrier is taken by who may cast the group
## (`Carriers.placed`): round the caster (`pulse`), round the body or shot that fired a payload
## (`pulse_bearer`) or round a payload's origin (`pulse_point`). It replaced the compiler's fallback
## carriers (owner, 2026-11-12), so cards with no carrier after them are wasted. Which cards do
## something on it follows from its yes/no answers and what each card needs, as on any carrier;
## tests/core/test_card_rules.gd plays every card on all three.
##
## godot --headless --path . --script res://content/spells/carriers/pulse/test_pulse.gd

const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")


func test_the_card_is_a_valid_carrier() -> void:
	var card: CarrierCard = load("res://content/spells/carriers/pulse/pulse.tres") as CarrierCard
	check(card != null, "pulse.tres loads as a CarrierCard")
	if card == null:
		return
	check_equal(card.id, &"pulse", "its id is its folder")
	check_equal(card.carrier, Carriers.PULSE, "it fires the Pulse carrier")
	check(card.range_problems().is_empty(), "inside every range: %s" % [card.range_problems()])
	check(card.look_problems().is_empty(), "its look is one the game draws: %s" % [card.look_problems()])


func test_its_carrier_is_round_what_casts_it() -> void:
	var on_you: Carrier = Carriers.placed(Carriers.PULSE, false)
	var there: Carrier = Carriers.placed(Carriers.PULSE, true)
	check_equal(on_you.id(), Carriers.PULSE, "a cast's own Pulse is round the caster")
	check_equal(there.id(), Carriers.PULSE_POINT, "a payload's is round its origin")
	check(on_you.hits() and there.hits(), "both strike what is there")
	check(on_you.lasts() and there.lasts(), "both last a moment, for their triggers")
	check(on_you.has(CarrierTraits.MEETS_SHOTS) and not there.has(CarrierTraits.MEETS_SHOTS), "only the caster's meets the shots that reach it")
	check(on_you.has(CarrierTraits.MELEE), "it never leaves its caster, so it never hits it")
	var on_it: Carrier = Carriers.placed(Carriers.PULSE, true, Carrier.BY_SHOT | Carrier.BY_POINT)
	check_equal(on_it.id(), Carriers.PULSE_BEARER, "a payload a shot or body may cast is round that")
	check_equal(Carriers.placed(Carriers.PULSE, true, Carrier.BY_POINT).id(), Carriers.PULSE_POINT, "one only a point casts is round the point")
	check(on_it.hits() and on_it.has(CarrierTraits.MEETS_SHOTS), "what fired it is struck round and meets shots")
	check(there.has(CarrierTraits.CASTERLESS) and not on_it.has(CarrierTraits.CASTERLESS) and not on_you.has(CarrierTraits.CASTERLESS), "only a point has nothing to push")
	check_equal(Carriers.placed(&"atom", true).id(), &"atom", "any other card's carrier is its own")
	check(Carriers.ids().has(Carriers.PULSE) and Carriers.exists(Carriers.PULSE), "a card may name the Pulse carrier")
	for id: StringName in [Carriers.PULSE_BEARER, Carriers.PULSE_POINT]:
		check(not Carriers.ids().has(id), "%s is not among the carriers a card may name" % id)
		check(not Carriers.exists(id), "and a card naming %s is refused" % id)


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
		check_equal(not alone.wasted.has(0), arena.spells.card_works(id, Carriers.PULSE), "%s on a Pulse, on you" % id)
		var cards: Array[StringName] = [&"on_hit", &"bolt", id, &"pulse"]
		var payload: CompiledStaff = arena.spells.compile_staff(cards, ArenaScript.plain_staff(4))
		check_equal(not payload.wasted.has(2), arena.spells.card_works(id, Carriers.PULSE_POINT), "%s on a payload's Pulse, right there" % id)
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
	check(not on_pulse.call(["hold"]), "a hold on a bare Pulse is wasted: it strikes nothing and nothing waits on it")
	check(on_pulse.call(["hold", "fire"]), "a hold on a fire Pulse keeps it striking")
	var there: CompiledStaff = arena.spells.compile_staff([&"on_hit", &"bolt", &"shield", &"pulse"] as Array[StringName], ArenaScript.plain_staff(4))
	check(there.wasted.has(2), "a shield on a point guards no one")
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


func test_a_bare_pulse_strikes_nothing() -> void:
	check_equal(_imp_lost(["pulse"], 1.0), 0, "nothing on it acts on hits")
	check_equal(_imp_lost(["shield", "pulse"], 1.0), 0, "a shield only guards")
	check(_imp_lost(["fire", "pulse"], 1.0) > 0, "an infusion strikes")
	check(_imp_lost(["bigger", "pulse"], 1.0) > 0, "and so does a card of numbers")


func test_a_pulse_that_strikes_shows_itself_out_to_its_reach() -> void:
	# Owner, 2026-11-12: "It sends a mote pulse out from the caster/point" (its card's `shown_cue`).
	var card: CarrierCard = load("res://content/spells/carriers/pulse/pulse.tres") as CarrierCard
	check_equal(card.shown_cue, &"pulse", "its card shows the pulse cue")
	check(load("res://content/cues/pulse.tres") is CueBase, "and that cue exists")
	var shown: Array = _shown(["fire", "pulse"])
	check_equal(shown.size(), 1, "a fire Pulse shows itself once")
	if shown.size() == 1:
		check_equal(shown[0][0], &"pulse", "as the Pulse card")
		check(is_equal_approx(float(shown[0][1]), card.radius), "out to its reach: %s" % shown[0][1])
	check(_shown(["pulse"]).is_empty(), "a bare Pulse strikes nothing and shows nothing (a fire pit's watch)")


## The `form_shown` of a Pulse's card ([form, length] each) after `cards` were cast once.
func _shown(cards: Array) -> Array:
	var arena := ArenaScript.new(root)
	arena.add_guard(0, Vector2.ZERO)
	var seen: Array = []
	arena.bus.form_shown.connect(func(_caster: int, form: StringName, _origin: Vector2, _direction: Vector2, length: float, _tint: Color, _look: int) -> void:
		if form == &"pulse":
			seen.append([form, length]))
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


## The carrier the card before the last of `cards` (a Pulse card is put after them) lands on, or
## &"" when it is wasted.
func _lands_on(arena: ArenaScript, cards: Array) -> StringName:
	var ids: Array[StringName] = []
	for id: Variant in cards:
		ids.append(StringName(str(id)))
	ids.append(&"pulse")
	var compiled: CompiledStaff = arena.spells.compile_staff(ids, ArenaScript.plain_staff(ids.size()))
	var card: int = ids.size() - 2
	if compiled.wasted.has(card):
		return &""
	var target: int = int(compiled.casts[0].targets.get(card, -1))
	for spell: CompiledSpell in compiled.nodes:
		if spell.slot == target:
			return spell.carrier
	return &"?"


func test_a_payloads_pulse_is_round_what_fired_it() -> void:
	# Owner, 2026-11-06: round the body or shot that fired the payload, else round its point; the
	# carriers say which (`Carrier.payload_cast_by`), and a card is wasted only when none could use it.
	var arena := ArenaScript.new(root)
	check_equal(_lands_on(arena, ["timer", "bolt", "shield"]), Carriers.PULSE_BEARER, "a bolt's timer: on the bolt")
	check_equal(_lands_on(arena, ["on_hit", "pierce", "bolt", "shield"]), Carriers.PULSE_BEARER, "a piercing bolt's hit: on the bolt, which flies on")
	check_equal(_lands_on(arena, ["on_hit", "bolt", "shield"]), &"", "a spent bolt's hit: a point, so a shield is wasted")
	check_equal(_lands_on(arena, ["on_hit", "bolt", "fire"]), Carriers.PULSE_POINT, "and a fire strikes there")
	check_equal(_lands_on(arena, ["on_hit", "sticky", "bolt", "shield"]), Carriers.PULSE_BEARER, "a sticky bolt's hit: on the bolt, stuck on")
	check_equal(_lands_on(arena, ["on_wall", "bounce", "bolt", "shield"]), Carriers.PULSE_BEARER, "a bouncing bolt's wall: on the bolt")
	check_equal(_lands_on(arena, ["on_wall", "bolt", "shield"]), &"", "a bolt that ends on the wall: a point")
	check_equal(_lands_on(arena, ["on_expire", "bolt", "shield"]), &"", "a bolt's end: a point")
	check_equal(_lands_on(arena, ["on_expire", "pull", "bolt", "shield"]), Carriers.PULSE_BEARER, "a pulling bolt's end: where its caster arrives")
	check_equal(_lands_on(arena, ["timer", "decoy", "shield"]), Carriers.PULSE_BEARER, "a decoy's timer: on its body")
	check_equal(_lands_on(arena, ["on_hurt", "decoy", "deflect"]), Carriers.PULSE_BEARER, "a decoy hurt: on its body")
	check_equal(_lands_on(arena, ["on_block", "shield", "decoy", "shield"]), Carriers.PULSE_BEARER, "a decoy's barrier blocks: on its body")
	check_equal(_lands_on(arena, ["on_block", "deflect", "decoy", "shield"]), &"", "a decoy's deflect: the turned shot's point")
	check_equal(_lands_on(arena, ["timer", "dash", "shield"]), Carriers.PULSE_BEARER, "a dash's timer: on the dashing body")
	check_equal(_lands_on(arena, ["on_expire", "teleport", "shield"]), Carriers.PULSE_BEARER, "a teleport's end: on the body it moved")
	check_equal(_lands_on(arena, ["on_cast", "bolt", "shield"]), Carriers.PULSE_BEARER, "on cast: on whoever cast the bolt")
	check_equal(_lands_on(arena, ["timer", "beam", "shield"]), &"", "a beam's tip: a point")
	check_equal(_lands_on(arena, ["timer", "familiar", "shield"]), &"", "a familiar's orb: a point")
	check_equal(_lands_on(arena, ["on_hit", "bolt", "recoil"]), &"", "recoil on a point: nothing to push")
	check_equal(_lands_on(arena, ["timer", "bolt", "recoil"]), Carriers.PULSE_BEARER, "recoil on the bolt pushes it")
	# Nested: a payload's carrier is cast by what fired that payload.
	check_equal(_lands_on(arena, ["timer", "bolt", "on_cast", "atom", "shield"]), Carriers.PULSE_BEARER, "on cast of an atom the bolt casts: on the bolt")
	check_equal(_lands_on(arena, ["on_hit", "bolt", "on_cast", "atom", "shield"]), &"", "on cast of an atom a point casts: wasted")
	check_equal(_lands_on(arena, ["on_hit", "bolt", "timer", "dash", "shield"]), Carriers.PULSE_BEARER, "a dash a point casts moves the wizard: on the wizard")
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
	# Forced past the waste table, the point still has no one to shield.
	StaffCompiler.keep_wasted = true
	var arena := ArenaScript.new(root)
	arena.add_imp(Vector2(60.0, 0.0))
	arena.add_guard(0, Vector2.ZERO)
	var barriers: Array = []
	arena.bus.wizard_shield_requested.connect(func(actor: int, _charges: int, _seconds: float, _tag: int) -> void: barriers.append(actor))
	arena.install_cards(0, 0, ["on_hit", "bolt", "shield", "pulse"])
	arena.cast(0, 0)
	arena.run(1.0)
	StaffCompiler.keep_wasted = false
	check(arena.lost(arena.imps[0]) > 0, "the bolt hit")
	check(barriers.is_empty(), "and nobody got a barrier: %s" % [barriers])
	arena.free_all()
