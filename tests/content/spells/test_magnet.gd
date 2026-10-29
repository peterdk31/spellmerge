extends "res://tests/support/suite.gd"
## The Magnet card (content/spells/modifiers/magnet/, staffs C): the next shot pulls the enemies
## near it toward itself while it flies. Each of its combos does what it promises with the card
## and fails without it.
##
## godot --headless --path . --script res://tests/content/spells/test_magnet.gd

const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")
const ComboFiles := preload("res://tests/support/combo_files.gd")

const COMBOS: Array[String] = ["magnet_pull_bolt", "magnet_void_hex"]


func _card() -> ModifierBase:
	return load("res://content/spells/modifiers/magnet/magnet.tres") as ModifierBase


func _combo(id: String) -> Dictionary:
	for combo: Dictionary in ComboFiles.read_all():
		if combo["id"] == id:
			return combo
	return {}


## Builds the arena for `combo`, with every copy of `drop` taken out of its cards. The caller
## frees it.
func _arena(combo: Dictionary, drop: String = "") -> ArenaScript:
	var arena := ArenaScript.new(root)
	arena.pushable = bool(combo.get("pushed", false))
	for at: Array in combo["imps"]:
		arena.add_imp(Vector2(float(at[0]), float(at[1])))
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
	arena.free_all()
	return held


func test_the_card_is_a_valid_modifier() -> void:
	var card: ModifierBase = _card()
	check(card != null, "magnet.tres loads as a ModifierBase")
	if card == null:
		return
	check_equal(card.id, &"magnet", "its id is its folder")
	check_equal(card.behaviour, ModifierBase.Behaviour.MAGNET, "the magnet behaviour")
	check(card.behaviour_strength > 0.0, "with a reach")
	check(card.range_problems().is_empty(), "inside every range: %s" % [card.range_problems()])


func test_the_combos_hold_with_the_card_and_fail_without_it() -> void:
	for id: String in COMBOS:
		var combo: Dictionary = _combo(id)
		check(not combo.is_empty(), "the combo %s exists" % id)
		if combo.is_empty():
			continue
		check(_holds(combo), "%s does what it promises" % id)
		check(not _holds(combo, "magnet"), "%s fails without Magnet" % id)


func test_a_magnet_shot_pulls_an_enemy_toward_it_and_a_plain_one_does_not() -> void:
	var arena := ArenaScript.new(root)
	var imp: Node2D = arena.add_imp(Vector2(60.0, 50.0))
	arena.install_cards(0, 0, ["magnet", "bolt"])
	arena.cast(0, 0)
	arena.run(0.1)
	var pull: Vector2 = arena.combat.knockback_of(imp)
	check(pull.y < 0.0, "pulled toward the shot's path (%s)" % [pull])
	arena.free_all()
	var plain := ArenaScript.new(root)
	var other: Node2D = plain.add_imp(Vector2(60.0, 50.0))
	plain.install_cards(0, 0, ["bolt"])
	plain.cast(0, 0)
	plain.run(0.1)
	check_equal(plain.combat.knockback_of(other), Vector2.ZERO, "a plain bolt pulls nothing")
	plain.free_all()


func test_the_pull_ends_with_the_shot() -> void:
	var arena := ArenaScript.new(root)
	var imp: Node2D = arena.add_imp(Vector2(60.0, 400.0))
	arena.install_cards(0, 0, ["magnet", "bolt"])
	arena.cast(0, 0)
	arena.run(5.0)
	check_equal(arena.projectiles.get_count(), 0, "the shot is gone")
	var pulls: Array[int] = [0]
	arena.bus.pull_requested.connect(func(_c: int, _p: Vector2, _r: float, _s: float, _t: int) -> void: pulls[0] += 1)
	arena.run(0.5)
	check_equal(pulls[0], 0, "a spent shot pulls no more")
	check(is_instance_valid(imp), "the far imp is untouched")
	arena.free_all()


func test_four_players_at_once() -> void:
	var arena := ArenaScript.new(root)
	arena.pushable = true
	var imps: Array[Node2D] = []
	for player in 4:
		var at := Vector2(0.0, 250.0 * player)
		arena.place_caster(player, at)
		imps.append(arena.add_imp(at + Vector2(130.0, 40.0)))
		arena.install_cards(player, 0, ["magnet", "bolt"])
	for player in 4:
		check(arena.cast(player, 0), "player %d casts" % player)
	arena.run(1.5)
	for player in 4:
		check(arena.lost(imps[player]) > 0, "player %d's magnet bolt drags in and hits its imp" % player)
	arena.free_all()
