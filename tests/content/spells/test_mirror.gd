extends "res://tests/support/suite.gd"
## The Mirror card (content/spells/modifiers/mirror/, staffs C): the next carrier also flies
## backwards. The engine side is tested in `tests/core/test_spells_multicast.gd`; here the card's
## data and its combos.
##
## godot --headless --path . --script res://tests/content/spells/test_mirror.gd

const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")


func _lost(cards: Array, at: Vector2, seconds: float, player: int = 0) -> int:
	var arena := ArenaScript.new(root)
	var imp: Node2D = arena.add_imp(at)
	arena.install_cards(player, 0, cards)
	arena.cast(player, 0)
	arena.run(seconds)
	var lost: int = arena.lost(imp)
	arena.free_all()
	return lost


func test_the_card_is_a_valid_modifier() -> void:
	var card: ModifierBase = load("res://content/spells/modifiers/mirror/mirror.tres") as ModifierBase
	check(card != null, "mirror.tres loads as a ModifierBase")
	if card == null:
		return
	check_equal(card.id, &"mirror", "its id is its folder")
	check_equal(card.behaviour, ModifierBase.Behaviour.MIRROR, "it mirrors")
	check(card.range_problems().is_empty(), "inside every range: %s" % [card.range_problems()])


func test_a_bolt_behind_is_only_hit_with_mirror() -> void:
	check_equal(_lost(["bolt"], Vector2(-100.0, 0.0), 1.5), 0, "a plain bolt flies ahead only")
	check(_lost(["mirror", "bolt"], Vector2(-100.0, 0.0), 1.5) > 0, "the mirrored bolt reaches the imp behind")
	check_equal(_lost(["mirror", "bolt"], Vector2(100.0, 0.0), 1.5), _lost(["bolt"], Vector2(100.0, 0.0), 1.5), "and the one ahead takes the same hit")


func test_the_mirror_costs_no_extra_mana() -> void:
	var arena := ArenaScript.new(root)
	var plain: CompiledStaff = arena.install_cards(0, 0, ["bolt"])
	var mirrored: CompiledStaff = arena.install_cards(0, 1, ["mirror", "bolt"])
	check_equal(mirrored.casts[0].mana, plain.casts[0].mana, "one bolt's mana")
	arena.free_all()


func test_four_players_mirror_at_once() -> void:
	var plain: int = _lost(["bolt"], Vector2(100.0, 0.0), 1.5)
	var arena := ArenaScript.new(root)
	var imps: Array[Node2D] = []
	for player in 4:
		var at := Vector2(0.0, 150.0 * player)
		arena.place_caster(player, at)
		imps.append(arena.add_imp(at + Vector2(-100.0, 0.0)))
		arena.install_cards(player, 0, ["mirror", "bolt"])
	for player in 4:
		check(arena.cast(player, 0), "player %d casts" % player)
	arena.run(1.5)
	for imp in imps:
		check_equal(arena.lost(imp), plain, "every imp behind its caster took the bolt")
	arena.free_all()
