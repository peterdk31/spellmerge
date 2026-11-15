extends "res://tests/support/suite.gd"
## The Lumber card (content/spells/modifiers/lumber/, boss OB4; docs/milestones/boss-old-broom.md,
## "Lumber (OB4)"): numbers only, the next carrier a bit slower (0.85x), three times as far
## (`reach_mult`) and three times as hard. A dash with it is a long, heavy charge: the Old Broom's
## Sweep. Its speed curve, a lurch and a drag, comes in OB10. Each of its combos does what it
## promises with the card and fails without it.
##
## godot --headless --path . --script res://content/spells/modifiers/lumber/test_lumber.gd

const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")
const ComboFiles := preload("res://tests/support/combo_files.gd")

const COMBOS: Array[String] = ["lumber_long_beam", "lumber_heavy_bolt"]


func _card() -> ModifierBase:
	return load("res://content/spells/modifiers/lumber/lumber.tres") as ModifierBase


func _combo(id: String) -> Dictionary:
	for combo: Dictionary in ComboFiles.read_all():
		if combo["id"] == id:
			return combo
	return {}


func _first(cards: Array) -> CompiledSpell:
	var arena := ArenaScript.new(root)
	var staff: CompiledStaff = arena.install_cards(0, 0, cards)
	var spell: CompiledSpell = null if staff.is_empty() else staff.casts[0].group.spells[0]
	arena.free_all()
	return spell


## Plays `combo` with every copy of `drop` taken out of its cards; whether every check held.
func _holds(combo: Dictionary, drop: String = "") -> bool:
	var arena := ArenaScript.new(root)
	for at: Array in combo["imps"]:
		arena.add_imp(Vector2(float(at[0]), float(at[1])))
	var entry: Dictionary = combo["casts"][0]
	var cards: Array = []
	for id: Variant in entry["cards"]:
		if str(id) != drop:
			cards.append(id)
	arena.install_cards(0, int(entry["staff"]), cards)
	arena.cast(0, int(entry["staff"]))
	arena.run(float(combo["seconds"]))
	var held: bool = true
	for row: Dictionary in combo["checks"]:
		match str(row["kind"]):
			"damaged":
				for index: int in row["imps"]:
					held = held and arena.lost(arena.imps[index]) > 0
			"lost_at_least":
				for index: int in row["imps"]:
					held = held and arena.lost(arena.imps[index]) >= int(row["min"])
			"status":
				for index: int in row["imps"]:
					held = held and arena.was_given(arena.imps[index], StringName(row["status"]))
	arena.free_all()
	return held


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
	check(card.description != "" and card.description.length() <= 60, "its builder line")
	check(card.range_problems().is_empty(), "inside every range: %s" % [card.range_problems()])


func test_a_lumbering_dash_is_a_long_heavy_charge() -> void:
	var plain: CompiledSpell = _first(["dash"])
	var lumber: CompiledSpell = _first(["lumber", "dash"])
	check(is_equal_approx(lumber.ray_length, plain.ray_length * 3.0), "three times as far (%s)" % lumber.ray_length)
	check(is_equal_approx(lumber.damage, plain.damage * 3.0), "three times as hard (%s)" % lumber.damage)
	check(is_equal_approx(lumber.speed, plain.speed * 0.85), "a bit slower (%s)" % lumber.speed)


func test_a_lumbering_bolt_flies_three_times_as_long() -> void:
	var plain: CompiledSpell = _first(["bolt"])
	var lumber: CompiledSpell = _first(["lumber", "bolt"])
	check(is_equal_approx(lumber.lifetime, plain.lifetime * 3.0), "three times its life (%s)" % lumber.lifetime)
	check(is_equal_approx(lumber.damage, plain.damage * 3.0), "three times as hard")
	check(lumber.speed < plain.speed, "a bit slower")


func test_the_combos_hold_with_the_card_and_fail_without_it() -> void:
	for id: String in COMBOS:
		var combo: Dictionary = _combo(id)
		check(not combo.is_empty(), "the combo %s exists" % id)
		if combo.is_empty():
			continue
		check(_holds(combo), "%s does what it promises" % id)
		check(not _holds(combo, "lumber"), "%s fails without Lumber" % id)


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

