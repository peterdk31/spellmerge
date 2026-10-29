extends "res://tests/support/suite.gd"
## The Heavy card (content/spells/modifiers/heavy/, staffs C): the next shot is slower and hits with
## a lot more knockback, and an enemy knocked into a wall takes a slam. Each of its combos does
## what it promises with the card and fails without it.
##
## godot --headless --path . --script res://tests/content/spells/test_heavy.gd

const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")
const ComboFiles := preload("res://tests/support/combo_files.gd")

const COMBOS: Array[String] = ["heavy_wall_slam", "heavy_hex_slam"]


func _card() -> ModifierBase:
	return load("res://content/spells/modifiers/heavy/heavy.tres") as ModifierBase


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
			"lost_at_least":
				for index: int in row["imps"]:
					held = held and arena.lost(arena.imps[index]) >= int(row["min"])
			"status":
				for index: int in row["imps"]:
					held = held and arena.was_given(arena.imps[index], StringName(row["status"]))
	arena.free_all()
	return held


func _first(cards: Array) -> CompiledSpell:
	var arena := ArenaScript.new(root)
	var staff: CompiledStaff = arena.install_cards(0, 0, cards)
	var spell: CompiledSpell = null if staff.is_empty() else staff.casts[0].group.spells[0]
	arena.free_all()
	return spell


func test_the_card_is_a_valid_modifier() -> void:
	var card: ModifierBase = _card()
	check(card != null, "heavy.tres loads as a ModifierBase")
	if card == null:
		return
	check_equal(card.id, &"heavy", "its id is its folder")
	check_equal(card.behaviour, ModifierBase.Behaviour.HEAVY, "the heavy behaviour")
	check(card.behaviour_strength > 1.0, "it multiplies the knockback")
	check(card.speed_mult < 1.0, "it is slower")
	check(card.range_problems().is_empty(), "inside every range: %s" % [card.range_problems()])


func test_a_heavy_bolt_is_slower_and_knocks_back_and_slams() -> void:
	var plain: CompiledSpell = _first(["bolt"])
	var heavy: CompiledSpell = _first(["heavy", "bolt"])
	check(heavy.speed < plain.speed, "slower (%s)" % heavy.speed)
	check(heavy.hit.knockback > plain.hit.knockback * 2.0, "much more knockback (%s)" % heavy.hit.knockback)
	check(heavy.hit.slam > 0, "it arms a slam")
	check_equal(plain.hit.slam, 0, "a plain bolt does not")
	check_equal(heavy.damage, plain.damage, "the same damage")


func test_the_combos_hold_with_the_card_and_fail_without_it() -> void:
	for id: String in COMBOS:
		var combo: Dictionary = _combo(id)
		check(not combo.is_empty(), "the combo %s exists" % id)
		if combo.is_empty():
			continue
		check(_holds(combo), "%s does what it promises" % id)
		check(not _holds(combo, "heavy"), "%s fails without Heavy" % id)


func test_no_wall_no_slam() -> void:
	var combo: Dictionary = _combo(COMBOS[0])
	if combo.is_empty():
		return
	var arena := ArenaScript.new(root)
	var imp: Node2D = arena.add_imp(Vector2(100.0, 0.0))
	arena.install_cards(0, 0, ["heavy", "bolt"])
	arena.cast(0, 0)
	arena.run(float(combo["seconds"]))
	check(arena.lost(imp) > 0 and arena.lost(imp) < 10, "in the open only the bolt hurts (%d)" % arena.lost(imp))
	arena.free_all()


func test_four_players_at_once() -> void:
	var arena := ArenaScript.new(root)
	var imps: Array[Node2D] = []
	for player in 4:
		var at := Vector2(0.0, 250.0 * player)
		arena.place_caster(player, at)
		imps.append(arena.add_imp(at + Vector2(100.0, 0.0)))
		arena.add_wall(Rect2(108.0, at.y - 100.0, 16.0, 200.0))
		arena.install_cards(player, 0, ["heavy", "bolt"])
	for player in 4:
		check(arena.cast(player, 0), "player %d casts" % player)
	arena.run(1.5)
	for player in 4:
		check(arena.lost(imps[player]) >= 10, "player %d's heavy bolt slams its imp" % player)
	arena.free_all()
