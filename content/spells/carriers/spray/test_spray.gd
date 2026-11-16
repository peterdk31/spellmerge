extends "res://tests/support/suite.gd"
## The Spray card (content/spells/carriers/spray/; the owner, 2026-11-16: the jet as a held hose): a
## jet poured out of the staff that strikes every body in a narrow cone ahead out to its reach,
## pushing it back, over at once and cast again while its button is held. A wall hides what is
## behind it, its own caster is never struck, and its blast and `on expire` payload go off where it
## ends. Its look is told as `carrier_shown`, from the hand as far as it reaches.
const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")


func _card() -> CarrierCard:
	return load("res://content/spells/carriers/spray/spray.tres") as CarrierCard


func test_the_card_is_a_valid_carrier() -> void:
	var card: CarrierCard = _card()
	check(card != null, "spray.tres loads as a CarrierCard")
	if card == null:
		return
	check_equal(card.id, &"spray", "its id is its folder")
	check_equal(card.carrier, &"spray", "it fires the spray carrier")
	check(is_equal_approx(card.ray_length, 80.0), "it reaches 80 px (the owner, 2026-11-16)")
	check(card.range_problems().is_empty(), "inside every range: %s" % [card.range_problems()])
	check(card.look_problems().is_empty(), "its look is one the areas draw: %s" % [card.look_problems()])
	check_equal(card.shown_cue, &"spray_jet", "its look is a jet")
	var spray: Carrier = Carriers.of(&"spray")
	check(spray.hits() and spray.reaches() and spray.has(Carrier.MELEE), "it hits, reach lengthens it and it spares its caster")
	check(not spray.flies() and not spray.lasts(), "it never flies and is over at once")


## Losses of the imps at `at` after one cast of `cards` along +x, and how far each was pushed.
func _cast(cards: Array, at: Array[Vector2], seconds: float = 0.4) -> Array:
	var arena := ArenaScript.new(root)
	arena.pushable = true
	for each: Vector2 in at:
		arena.add_imp(each)
	arena.install_cards(0, 0, cards)
	arena.cast(0, 0)
	arena.run(seconds)
	var lost: Array[int] = []
	var moved: Array[float] = []
	for n in at.size():
		lost.append(arena.lost(arena.imps[n]))
		moved.append(arena.imps[n].global_position.x - at[n].x)
	arena.free_all()
	return [lost, moved]


func test_it_strikes_its_cone_ahead_and_nothing_else() -> void:
	var out: Array = _cast(["spray"], [Vector2(40.0, 0.0), Vector2(70.0, 8.0), Vector2(70.0, 40.0), Vector2(110.0, 0.0), Vector2(-30.0, 0.0)])
	var lost: Array[int] = out[0]
	check(lost[0] > 0 and lost[1] > 0, "the imps in its cone are struck (%s)" % [lost])
	check_equal(lost[2], 0, "one beside the cone is not")
	check_equal(lost[3], 0, "nor one past its reach")
	check_equal(lost[4], 0, "nor one behind the caster")


func test_it_pushes_what_it_splashes_back() -> void:
	var out: Array = _cast(["spray"], [Vector2(40.0, 0.0)], 0.6)
	check((out[1] as Array)[0] > 1.0, "pushed away from the caster (%s px)" % (out[1] as Array)[0])


func test_its_look_is_told_from_the_hand_as_far_as_it_reaches() -> void:
	var arena := ArenaScript.new(root)
	var shown: Array = []
	arena.bus.carrier_shown.connect(func(_caster: int, card: StringName, origin: Vector2, direction: Vector2, length: float, _tint: Color, _look: int) -> void:
		if card == &"spray":
			shown.append([origin, direction, length]))
	arena.install_cards(0, 0, ["spray"])
	arena.cast(0, 0)
	arena.run(0.1)
	check_equal(shown.size(), 1, "told once a cast")
	if shown.size() == 1:
		check(is_equal_approx(float(shown[0][2]), 80.0), "as far as it reaches (%s)" % shown[0][2])
		check((shown[0][1] as Vector2).is_equal_approx(Vector2.RIGHT), "along its heading")
	arena.free_all()


func test_three_combos_name_it() -> void:
	var found: int = 0
	for combo: Dictionary in preload("res://tests/support/combo_files.gd").read_all():
		if (combo["casts"][0]["cards"] as Array).has("spray"):
			found += 1
	check(found >= 3, "three combos are about the spray (%d)" % found)


func test_a_wall_hides_what_is_behind_it_and_cuts_it_short() -> void:
	var arena := ArenaScript.new(root)
	var shown: Array = []
	arena.bus.carrier_shown.connect(func(_caster: int, card: StringName, _origin: Vector2, _direction: Vector2, length: float, _tint: Color, _look: int) -> void:
		if card == &"spray":
			shown.append(length))
	arena.add_wall(Rect2(30.0, -40.0, 8.0, 80.0))
	arena.add_imp(Vector2(60.0, 0.0))
	arena.install_cards(0, 0, ["spray"])
	arena.cast(0, 0)
	arena.run(0.4)
	check_equal(arena.lost(arena.imps[0]), 0, "the imp behind the wall is dry")
	check(shown.size() == 1 and float(shown[0]) < 34.0, "its jet stops at the wall (%s)" % [shown])
	arena.free_all()


func test_an_enemy_holds_it_and_knows_its_cone() -> void:
	# The review, 2026-11-16: an enemy fired one puff and rested. Held, it is cast anew (`REPEATS_HELD`)
	# and the AI's lane is its cone's width out at its reach, not its 4 px hit radius.
	var spell := CompiledSpell.new()
	spell.carrier = &"spray"
	spell.ray_length = 80.0
	spell.arc = 24.0
	spell.radius = 4.0
	var spray: Carrier = Carriers.of(&"spray")
	check(spray.ai_holds() and spray.has(Carrier.REPEATS_HELD), "held, it is cast anew: an enemy holds it down, so it pours on")
	var lane: float = spray.lane_radius(spell)
	check(lane > 16.0 and lane < 30.0, "its lane is its cone's width at its reach (%s px)" % lane)
	spell.radius = 8.0
	check(spray.lane_radius(spell) > lane, "a bigger one is wider")


func test_a_bigger_caster_sprays_further() -> void:
	var spell := CompiledSpell.new()
	spell.ray_length = 80.0
	spell.radius = 4.0
	Carriers.of(&"spray").scale_size(spell, 2.0)
	check(is_equal_approx(spell.ray_length, 160.0), "twice the caster, twice the reach")


func test_its_end_is_where_a_wall_cuts_it_and_its_payload_goes_off_there() -> void:
	var arena := ArenaScript.new(root)
	arena.add_wall(Rect2(60.0, -40.0, 8.0, 80.0))
	var imp: Node2D = arena.add_imp(Vector2(48.0, 0.0))
	# A frost nova where the jet ends: it chills the imp beside the wall.
	arena.install_cards(0, 0, ["on_expire", "spray", "frost", "nova", "bolt"])
	arena.cast(0, 0)
	arena.run(1.0)
	check(arena.lost(imp) > 0, "the spray and its payload reach the imp before the wall")
	arena.free_all()


func test_two_cones_of_a_split_spray_each_strike() -> void:
	var out: Array = _cast(["split", "spray"], [Vector2(50.0, -22.0), Vector2(50.0, 22.0)])
	var lost: Array[int] = out[0]
	check(lost[0] > 0 and lost[1] > 0, "a cone either way, each striking its imp (%s)" % [lost])


func test_hold_keeps_it_pouring_like_a_beam() -> void:
	# The owner, 2026-11-16: "Hold should work like for a beam": one press switches it on, it pours
	# on by itself with its cast's mana reserved, and a second press switches it off.
	var arena := ArenaScript.new(root)
	var imp: Node2D = arena.add_imp(Vector2(50.0, 0.0))
	arena.install_cards(0, 0, ["hold", "spray"])
	check(arena.cast(0, 0), "one press switches it on")
	arena.run(0.1)
	var first: int = arena.lost(imp)
	check(arena.spells.is_holding(0, 0), "it is kept on")
	check(arena.spells.reserved_mana(0, 0) > 0.0, "its cast's mana reserved while it pours")
	arena.run(1.0)
	var poured: int = arena.lost(imp)
	check(poured >= first + 4, "it pours on without another press (%d, then %d)" % [first, poured])
	arena.cast(0, 0)
	arena.run(0.1)
	var off: int = arena.lost(imp)
	arena.run(0.6)
	check(not arena.spells.is_holding(0, 0), "a second press switches it off")
	check_equal(arena.lost(imp), off, "and it pours no more")
	check_equal(arena.spells.reserved_mana(0, 0), 0.0, "its mana let go")
	arena.free_all()
