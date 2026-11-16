extends "res://tests/support/suite.gd"
## The Spray card (content/spells/carriers/spray/; the owner, 2026-11-16: the jet as a held hose): a
## jet poured out of the staff that strikes every body in a narrow cone ahead out to its reach,
## pushing it back, over at once and cast again while its button is held. A wall hides what is
## behind it, its own caster is never struck, and its blast and `on expire` payload go off where it
## ends. Its look is told as `carrier_shown`, from the hand as far as it reaches.
##
## godot --headless --path . --script res://content/spells/carriers/spray/test_spray.gd

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
