extends "res://tests/support/suite.gd"
## The Echo card (content/spells/modifiers/echo/, staffs C): the next carrier fires again 0.3 s
## later at half damage, and an echo does not echo. The engine side is tested in
## `tests/core/test_spells_multicast.gd`; here the card's data and its combos.
##
## godot --headless --path . --script res://tests/content/spells/test_echo.gd

const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")


func _lost(cards: Array, at: Vector2, seconds: float) -> int:
	var arena := ArenaScript.new(root)
	var imp: Node2D = arena.add_imp(at)
	arena.install_cards(0, 0, cards)
	arena.cast(0, 0)
	arena.run(seconds)
	var lost: int = arena.lost(imp)
	arena.free_all()
	return lost


func test_the_card_is_a_valid_modifier() -> void:
	var card: ModifierBase = load("res://content/spells/modifiers/echo/echo.tres") as ModifierBase
	check(card != null, "echo.tres loads as a ModifierBase")
	if card == null:
		return
	check_equal(card.id, &"echo", "its id is its folder")
	check_equal(card.behaviour, ModifierBase.Behaviour.ECHO, "it echoes")
	check_equal(card.behaviour_strength, 0.3, "after 0.3 s")
	check(card.range_problems().is_empty(), "inside every range: %s" % [card.range_problems()])


func test_an_echo_bolt_has_a_half_damage_second_hit() -> void:
	var arena := ArenaScript.new(root)
	var staff: CompiledStaff = arena.install_cards(0, 0, ["echo", "bolt"])
	var spell: CompiledSpell = staff.casts[0].group.spells[0]
	check(spell.echo_hit != null, "the carrier has an echo hit")
	if spell.echo_hit != null:
		check_equal(spell.echo_hit.damage, spell.damage * 0.5, "at half damage, not rounded")
	arena.free_all()
	arena = ArenaScript.new(root)
	staff = arena.install_cards(0, 0, ["bolt"])
	check(staff.casts[0].group.spells[0].echo_hit == null, "a plain bolt has none")
	arena.free_all()


func test_the_echo_hits_a_moment_after_the_bolt() -> void:
	var plain: int = _lost(["bolt"], Vector2(100.0, 0.0), 1.5)
	check(plain > 0, "a plain bolt hurts")
	check_equal(_lost(["echo", "bolt"], Vector2(100.0, 0.0), 0.5), plain, "only the bolt has hit by 0.5 s")
	check_equal(_lost(["echo", "bolt"], Vector2(100.0, 0.0), 1.5), plain + floori(plain * 0.5), "the echo adds half again (the half point is owed)")


func test_the_timer_nova_is_rung_twice() -> void:
	var cards: Array = ["timer", "echo", "bolt", "nova"]
	var plain: int = _lost(["timer", "bolt", "nova"], Vector2(132.0, 40.0), 2.5)
	check(plain > 0, "a plain timed nova reaches the imp")
	check_equal(_lost(cards, Vector2(132.0, 40.0), 2.5), plain * 2, "the echo's nova rings it a second time")


func test_four_players_echo_at_once() -> void:
	var plain: int = _lost(["bolt"], Vector2(100.0, 0.0), 1.5)
	var arena := ArenaScript.new(root)
	var imps: Array[Node2D] = []
	for player in 4:
		var at := Vector2(0.0, 150.0 * player)
		arena.place_caster(player, at)
		imps.append(arena.add_imp(at + Vector2(100.0, 0.0)))
		arena.install_cards(player, 0, ["echo", "bolt"])
	for player in 4:
		check(arena.cast(player, 0), "player %d casts" % player)
	arena.run(1.5)
	for imp in imps:
		check_equal(arena.lost(imp), plain + floori(plain * 0.5), "every imp took the bolt and its echo")
	arena.free_all()
