extends "res://tests/support/suite.gd"
## The Overcharge card (content/spells/modifiers/overcharge/, staffs phase C): a modifier that
## doubles the next carrier's damage and its mana cost, the opposite of siphon: an
## overcharged carrier hurts an imp twice as much as a plain one.
##
## godot --headless --path . --script res://tests/content/spells/test_overcharge.gd

const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")


func _card() -> ModifierBase:
	return load("res://content/spells/modifiers/overcharge/overcharge.tres") as ModifierBase


## The first carrier of `cards`, compiled.
func _first(cards: Array) -> CompiledSpell:
	var arena := ArenaScript.new(root)
	var staff: CompiledStaff = arena.install_cards(0, 0, cards)
	var spell: CompiledSpell = null if staff.is_empty() else staff.casts[0].group.spells[0]
	arena.free_all()
	return spell


## Health an imp 100 px ahead loses to one cast of `cards`.
func _damage_of(cards: Array) -> int:
	var arena := ArenaScript.new(root)
	var imp: Node2D = arena.add_imp(Vector2(100.0, 0.0))
	arena.install_cards(0, 0, cards)
	arena.cast(0, 0)
	arena.run(1.0)
	var lost: int = arena.lost(imp)
	arena.free_all()
	return lost


func test_the_card_is_a_valid_modifier() -> void:
	var card: ModifierBase = _card()
	check(card != null, "overcharge.tres loads as a ModifierBase")
	if card == null:
		return
	check_equal(card.id, &"overcharge", "its id is its folder")
	check_equal(card.kind(), &"modifier", "a modifier card")
	check_equal(card.behaviour, ModifierBase.Behaviour.NONE, "numbers only")
	check(card.look_layer > 0, "its shots give off a look")
	check(card.range_problems().is_empty(), "inside every range: %s" % [card.range_problems()])


func test_it_doubles_damage_and_mana() -> void:
	var plain: CompiledSpell = _first(["bolt"])
	var charged: CompiledSpell = _first(["overcharge", "bolt"])
	check(plain != null and charged != null, "both compile")
	if plain == null or charged == null:
		return
	check_equal(charged.damage, plain.damage * 2, "twice the damage")
	check(is_equal_approx(charged.mana_cost, plain.mana_cost * 2.0), "twice the mana (%s)" % charged.mana_cost)
	check(is_equal_approx(charged.cooldown, plain.cooldown), "the same delay")


func test_an_overcharged_bolt_hurts_twice_as_much() -> void:
	var plain: int = _damage_of(["bolt"])
	var charged: int = _damage_of(["overcharge", "bolt"])
	check(plain > 0, "a plain bolt hurts")
	check_equal(charged, plain * 2, "an overcharged one hurts twice as much")


func test_four_players_overcharge_at_once() -> void:
	var arena := ArenaScript.new(root)
	var imps: Array[Node2D] = []
	for player in 4:
		var at := Vector2(0.0, 150.0 * player)
		arena.place_caster(player, at)
		imps.append(arena.add_imp(at + Vector2(100.0, 0.0)))
		arena.install_cards(player, 0, ["overcharge", "bolt"])
	for player in 4:
		check(arena.cast(player, 0), "player %d casts" % player)
	arena.run(1.0)
	var plain: int = _damage_of(["bolt"])
	for imp in imps:
		check_equal(arena.lost(imp), plain * 2, "every player's bolt is overcharged")
	arena.free_all()
