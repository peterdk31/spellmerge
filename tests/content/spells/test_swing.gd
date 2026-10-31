extends "res://tests/support/suite.gd"
## The Swing card (content/spells/forms/swing/, melee I4; docs/milestones/M2-staffs.md, "Phase I:
## melee"): a mana-free melee carrier that sweeps a 90° arc round the hand, striking every body in
## it once. The engine side is tested in `tests/core/test_spells_swing.gd`; here the card's data,
## the playground's numbers and how it plays with other cards.
##
## godot --headless --path . --script res://tests/content/spells/test_swing.gd

const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")
const SpellsScript := preload("res://core/spells/spells.gd")


func _card() -> FormBase:
	return load("res://content/spells/forms/swing/swing.tres") as FormBase


func _lost(cards: Array, at: Vector2, seconds: float = 1.0) -> int:
	var arena := ArenaScript.new(root)
	var imp: Node2D = arena.add_imp(at)
	arena.install_cards(0, 0, cards)
	arena.cast(0, 0)
	arena.run(seconds)
	var lost: int = arena.lost(imp)
	arena.free_all()
	return lost


func test_the_card_is_a_valid_carrier() -> void:
	var card: FormBase = _card()
	check(card != null, "swing.tres loads as a FormBase")
	if card == null:
		return
	check_equal(card.id, &"swing", "its id is its folder")
	check_equal(card.carrier, &"swing", "it is a swing")
	check(card.range_problems().is_empty(), "inside every range: %s" % [card.range_problems()])


func test_it_has_the_playgrounds_numbers() -> void:
	# The owner's tuning in the melee playground (2026-10-29), as the plan's "Tuning" lists them.
	var card: FormBase = _card()
	check_equal(card.mana_cost, 0.0, "it costs no mana")
	check_equal(card.arc, 90.0, "a 90° arc")
	check_equal(card.ray_length, 24.0, "24 px of reach")
	check(is_equal_approx(card.wind_up, 0.12), "a 0.12 s wind-up")
	check(is_equal_approx(card.lifetime, 0.06), "a 0.06 s sweep")
	check(is_equal_approx(card.cooldown, 0.3), "a 0.3 s delay")
	check_equal(card.base_damage, 2, "2 damage")
	check_equal(card.knockback, 240.0, "240 px/s of knockback")


func test_it_casts_with_no_mana_at_all() -> void:
	var arena := ArenaScript.new(root)
	arena.install_cards(0, 0, ["swing"])
	check(arena.spells.cast_staff(0, 0, Vector2.ZERO, Vector2.RIGHT, 0.0) != SpellsScript.REFUSED, "an empty mana bar still swings")
	arena.free_all()


func test_it_hits_in_front_and_not_behind_or_out_of_reach() -> void:
	check_equal(_lost(["swing"], Vector2(18.0, 0.0)), 2, "the imp in front takes the card's damage")
	check_equal(_lost(["swing"], Vector2(-18.0, 0.0)), 0, "the imp behind is not touched")
	check_equal(_lost(["swing"], Vector2(60.0, 0.0)), 0, "nor one out of its reach")


func test_its_hits_are_swing_hits() -> void:
	var arena := ArenaScript.new(root)
	var imp: Node2D = arena.add_imp(Vector2(18.0, 0.0))
	var kinds: Array[StringName] = []
	arena.bus.hit_landed.connect(func(_caster: int, target: Node, _amount: int, _at: Vector2, kind: StringName, _shot: int) -> void:
		if target == imp:
			kinds.append(kind))
	arena.install_cards(0, 0, ["swing"])
	arena.cast(0, 0)
	arena.run(0.5)
	check_equal(kinds, [&"swing"] as Array[StringName], "one hit, of the swing kind (its own stop and shake in Feel)")
	arena.free_all()


func test_it_knocks_the_imp_away_from_the_hand() -> void:
	var arena := ArenaScript.new(root)
	arena.pushable = true
	var imp: Node2D = arena.add_imp(Vector2(18.0, 0.0))
	arena.install_cards(0, 0, ["swing"])
	arena.cast(0, 0)
	arena.run(1.0)
	check(imp.global_position.length() > 30.0, "the imp is batted away (now %s)" % imp.global_position)
	arena.free_all()


func test_heavy_bats_it_further() -> void:
	var plain := ArenaScript.new(root)
	plain.pushable = true
	var light: Node2D = plain.add_imp(Vector2(18.0, 0.0))
	plain.install_cards(0, 0, ["swing"])
	plain.cast(0, 0)
	plain.run(1.0)
	var light_way: float = light.global_position.length()
	plain.free_all()
	var heavy := ArenaScript.new(root)
	heavy.pushable = true
	var hard: Node2D = heavy.add_imp(Vector2(18.0, 0.0))
	heavy.install_cards(0, 0, ["heavy", "swing"])
	heavy.cast(0, 0)
	heavy.run(1.0)
	check(hard.global_position.length() > light_way + 4.0, "a heavy swing knocks further (%.1f against %.1f)" % [hard.global_position.length(), light_way])
	heavy.free_all()


func test_two_presses_swing_forehand_then_backhand() -> void:
	# The second press, inside the chain window, chains on: both hit the imp, one each way.
	var arena := ArenaScript.new(root)
	var imp: Node2D = arena.add_imp(Vector2(18.0, 0.0))
	arena.install_cards(0, 0, ["swing"])
	arena.cast(0, 0)
	var first: int = _live_side(arena)
	arena.run(0.35)
	check(arena.cast(0, 0), "the second swing is cast after the card's delay")
	var second: int = _live_side(arena)
	arena.run(0.5)
	check_equal(arena.lost(imp), 4, "both swings struck it")
	check(first != 0 and second == -first, "the second turns the other way (%d, then %d)" % [first, second])
	arena.free_all()


## The way the one live swing turns, or 0 for none.
func _live_side(arena: ArenaScript) -> int:
	for at in CarrierSwing.of(arena.spells).swing_slots():
		if CarrierSwing.of(arena.spells).swing_on(at):
			return CarrierSwing.of(arena.spells).swing_side(at)
	return 0


func test_four_players_swing_at_once() -> void:
	var plain: int = _lost(["swing"], Vector2(18.0, 0.0))
	var arena := ArenaScript.new(root)
	var imps: Array[Node2D] = []
	for player in 4:
		var at := Vector2(0.0, 200.0 * player)
		arena.place_caster(player, at)
		imps.append(arena.add_imp(at + Vector2(18.0, 0.0)))
		arena.install_cards(player, 0, ["swing"])
	for player in 4:
		check(arena.cast(player, 0), "player %d swings" % player)
	arena.run(1.0)
	for imp in imps:
		check_equal(arena.lost(imp), plain, "every imp in front of its player took the same hit")
	arena.free_all()
