extends "res://tests/support/suite.gd"
## The Growth card (content/spells/modifiers/growth/, staffs C): the next shot grows, and hits harder, as it flies. Each of its combos does
## what it promises with the card and fails without it.
##
## godot --headless --path . --script res://tests/content/spells/test_growth.gd

const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")
const ComboFiles := preload("res://tests/support/combo_files.gd")

const COMBOS: Array[String] = ["growth_far_shot", "growth_slow_orb"]


func _card() -> ModifierBase:
	return load("res://content/spells/modifiers/growth/growth.tres") as ModifierBase


func _combo(id: String) -> Dictionary:
	for combo: Dictionary in ComboFiles.read_all():
		if combo["id"] == id:
			return combo
	return {}


## Builds the arena for `combo` (imps and walls), with every copy of `drop` taken out of its cards.
## The caller frees it.
func _arena(combo: Dictionary, drop: String = "") -> ArenaScript:
	var arena := ArenaScript.new(root)
	for at: Array in combo["imps"]:
		arena.add_imp(Vector2(float(at[0]), float(at[1])))
	for rect: Array in combo.get("walls", []):
		arena.add_wall(Rect2(float(rect[0]), float(rect[1]), float(rect[2]), float(rect[3])))
	var entry: Dictionary = combo["casts"][0]
	var cards: Array = []
	for id: Variant in entry["cards"]:
		if str(id) != drop:
			cards.append(id)
	arena.install_cards(0, int(entry["staff"]), cards)
	return arena


## Plays `combo` without `drop` and returns whether every check held.
func _holds(combo: Dictionary, drop: String = "") -> bool:
	var arena: ArenaScript = _arena(combo, drop)
	arena.cast(0, int(combo["casts"][0]["staff"]))
	arena.run(float(combo["seconds"]))
	var held: bool = true
	for row: Dictionary in combo["checks"]:
		match str(row["kind"]):
			"damaged":
				for index: int in row["imps"]:
					held = held and arena.lost(arena.imps[index]) > 0
			"status":
				for index: int in row["imps"]:
					held = held and arena.was_given(arena.imps[index], StringName(row["status"]))
			"status_count":
				var count: int = 0
				for imp in arena.imps:
					if arena.was_given(imp, StringName(row["status"])):
						count += 1
				held = held and count >= int(row["min"])
	arena.free_all()
	return held


func test_the_card_is_a_valid_modifier() -> void:
	var card: ModifierBase = _card()
	check(card != null, "growth.tres loads as a ModifierBase")
	if card == null:
		return
	check_equal(card.id, &"growth", "its id is its folder")
	check_equal(card.behaviour, ModifierBase.Behaviour.GROWTH, "the growth behaviour")
	check(card.behaviour_strength > 0.0, "with a strength")
	check(card.range_problems().is_empty(), "inside every range: %s" % [card.range_problems()])


func test_the_combos_hold_with_the_card_and_fail_without_it() -> void:
	for id: String in COMBOS:
		var combo: Dictionary = _combo(id)
		check(not combo.is_empty(), "the combo %s exists" % id)
		if combo.is_empty():
			continue
		check(_holds(combo), "%s does what it promises" % id)
		check(not _holds(combo, "growth"), "%s fails without Growth" % id)


func test_four_players_at_once() -> void:
	# Every player plays the first combo from a place of their own, far enough apart.
	var combo: Dictionary = _combo(COMBOS[0])
	if combo.is_empty():
		return
	var arena := ArenaScript.new(root)
	var walls: Array = combo.get("walls", [])
	var mine: Array = []
	for player in 4:
		var at := Vector2(0.0, 250.0 * player)
		arena.place_caster(player, at)
		var imps: Array[Node2D] = []
		for spot: Array in combo["imps"]:
			imps.append(arena.add_imp(at + Vector2(float(spot[0]), float(spot[1]))))
		mine.append(imps)
		for rect: Array in walls:
			arena.add_wall(Rect2(float(rect[0]), float(rect[1]) + at.y, float(rect[2]), float(rect[3])))
		arena.install_cards(player, 0, combo["casts"][0]["cards"])
	for player in 4:
		check(arena.cast(player, 0), "player %d casts" % player)
	arena.run(float(combo["seconds"]))
	for player in 4:
		var hurt: bool = false
		for imp: Node2D in mine[player]:
			hurt = hurt or arena.lost(imp) > 0
		check(hurt, "player %d's growth combo lands" % player)
	arena.free_all()


func test_growth_cards_multiply() -> void:
	# Rule 3 (docs/milestones/M2-rules.md, R1c): growth is a factor, so three cards are 2 x 2 x 2,
	# not 2 + 2 + 2 (two cards agree either way).
	var arena := ArenaScript.new(root)
	var strength: float = _card().behaviour_strength
	var staff: CompiledStaff = arena.install_cards(0, 0, ["growth", "growth", "growth", "bolt"])
	var spell: CompiledSpell = staff.casts[0].group.spells[0]
	arena.free_all()
	check_equal(spell.behaviour(ModifierBase.Behaviour.GROWTH), strength * strength * strength, "three cards multiply")
