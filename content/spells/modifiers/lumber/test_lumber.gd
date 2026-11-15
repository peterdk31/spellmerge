extends "res://tests/support/suite.gd"
## The Lumber card (content/spells/modifiers/lumber/, boss OB4; docs/milestones/boss-old-broom.md,
## "Lumber (OB4)"): numbers only, the next carrier a bit slower (0.85x), three times as far
## (`reach_mult`) and three times as hard. A dash with it is a long, heavy charge: the Old Broom's
## Sweep. Its dash lurches off, picks up and drags to a stop (`move_start`, `move_end`, `move_ease`:
## a move's speed curve, OB10), still its whole way in its time; a bolt's flight keeps its own
## curve. Its combos (`combos/`, each with
## `needs: lumber`) are held with and without it by tests/content/spells/test_combos.gd.
##
## godot --headless --path . --script res://content/spells/modifiers/lumber/test_lumber.gd

const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")


func _card() -> ModifierBase:
	return load("res://content/spells/modifiers/lumber/lumber.tres") as ModifierBase


func _first(cards: Array) -> CompiledSpell:
	var arena := ArenaScript.new(root)
	var staff: CompiledStaff = arena.install_cards(0, 0, cards)
	var spell: CompiledSpell = null if staff.is_empty() else staff.casts[0].group.spells[0]
	arena.free_all()
	return spell


func test_the_card_is_a_valid_modifier() -> void:
	var card: ModifierBase = _card()
	check(card != null, "lumber.tres loads as a ModifierBase")
	if card == null:
		return
	check_equal(card.id, &"lumber", "its id is its folder")
	check_equal(card.behaviour, ModifierBase.Behaviour.NONE, "numbers only")
	check(is_equal_approx(card.speed_mult, 0.85), "0.85x speed")
	check(is_equal_approx(card.reach_mult, 3.0), "3x distance")
	check(is_equal_approx(card.damage_mult, 3.0), "3x damage")
	# Priced above a card that only doubles damage (Overcharge's 2x mana), so it does not make one obsolete.
	check(card.mana_mult >= 2.5, "it costs dear (%s)" % card.mana_mult)
	check(card.wind_down_mult > 1.0, "and its carrier takes longer to wind down")
	check(card.description != "" and card.description.length() <= 60, "its builder line")
	check(card.range_problems().is_empty(), "inside every range: %s" % [card.range_problems()])


func test_a_lumbering_dash_is_a_long_heavy_charge() -> void:
	var plain: CompiledSpell = _first(["dash"])
	var lumber: CompiledSpell = _first(["lumber", "dash"])
	check(is_equal_approx(lumber.ray_length, plain.ray_length * 3.0), "three times as far (%s)" % lumber.ray_length)
	check(is_equal_approx(lumber.damage, plain.damage * 3.0), "three times as hard (%s)" % lumber.damage)
	check(is_equal_approx(lumber.speed, plain.speed * 0.85), "a bit slower (%s)" % lumber.speed)


func test_its_dash_lurches_and_drags() -> void:
	var card: ModifierBase = _card()
	check(card.move_start < 0.5 and is_equal_approx(card.move_end, 0.0) and card.move_ease > 1.0, "a slow start, a dead stop, full speed between")
	var lumber: CompiledSpell = _first(["lumber", "dash"])
	var curve: Vector3 = MoveCurve.of(lumber)
	check(MoveCurve.shapes(curve), "its dash takes the curve")
	check(MoveCurve.factor(curve, 0.0) < 0.5, "it lurches off slowly (%s)" % MoveCurve.factor(curve, 0.0))
	check(MoveCurve.factor(curve, 0.5) > 1.2, "picks up (%s)" % MoveCurve.factor(curve, 0.5))
	check(is_equal_approx(MoveCurve.factor(curve, 1.0), 0.0), "and drags to a stop")
	var bolt: CompiledSpell = _first(["lumber", "bolt"])
	var plain: CompiledSpell = _first(["bolt"])
	check(is_equal_approx(bolt.speed_start, plain.speed_start) and is_equal_approx(bolt.speed_end, plain.speed_end), "a bolt's flight keeps its own curve")


func test_a_lumbering_bolt_flies_three_times_as_long() -> void:
	var plain: CompiledSpell = _first(["bolt"])
	var lumber: CompiledSpell = _first(["lumber", "bolt"])
	check(is_equal_approx(lumber.lifetime, plain.lifetime * 3.0), "three times its life (%s)" % lumber.lifetime)
	check(is_equal_approx(lumber.damage, plain.damage * 3.0), "three times as hard")
	check(lumber.speed < plain.speed, "a bit slower")


func test_four_players_lumber_at_once() -> void:
	var arena := ArenaScript.new(root)
	var imps: Array[Node2D] = []
	for player in 4:
		var at := Vector2(0.0, 150.0 * player)
		arena.place_caster(player, at)
		imps.append(arena.add_imp(at + Vector2(100.0, 0.0)))
		arena.install_cards(player, 0, ["lumber", "bolt"])
	for player in 4:
		check(arena.cast(player, 0), "player %d casts" % player)
	arena.run(2.0)
	for player in 4:
		check(arena.lost(imps[player]) >= 12, "player %d's bolt hits three times as hard (%d)" % [player, arena.lost(imps[player])])
	arena.free_all()

