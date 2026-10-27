extends "res://tests/support/suite.gd"
## The Slow card (content/spells/modifiers/slow/, owner 2026-10-27): the next carrier at a third of
## its speed for three times its life (`lifetime_mult`), so it crawls about as far. With a timer
## it lays its payloads close together; with `arc` it makes a slow orb (the Arc card's combos).
##
## godot --headless --path . --script res://tests/content/spells/test_slow.gd

const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")


func _first(cards: Array) -> CompiledSpell:
	var arena := ArenaScript.new(root)
	var staff: CompiledStaff = arena.install_cards(0, 0, cards)
	var spell: CompiledSpell = null if staff.is_empty() else staff.casts[0].group.spells[0]
	arena.free_all()
	return spell


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
	var card: ModifierBase = load("res://content/spells/modifiers/slow/slow.tres") as ModifierBase
	check(card != null, "slow.tres loads as a ModifierBase")
	if card == null:
		return
	check_equal(card.id, &"slow", "its id is its folder")
	check(card.range_problems().is_empty(), "inside every range: %s" % [card.range_problems()])


func test_a_slow_bolt_crawls_about_as_far_for_longer() -> void:
	var plain: CompiledSpell = _first(["bolt"])
	var slow: CompiledSpell = _first(["slow", "bolt"])
	check(slow.speed < plain.speed * 0.5, "much slower (%s)" % slow.speed)
	check(slow.lifetime > plain.lifetime * 2.0, "lives much longer (%s)" % slow.lifetime)
	var reach: float = slow.speed * slow.lifetime
	check(reach > plain.speed * plain.lifetime * 0.8 and reach <= plain.speed * plain.lifetime, "about as far (%s)" % reach)
	check_equal(slow.damage, plain.damage, "the same damage")


func test_a_slow_bolt_reaches_an_imp_later() -> void:
	check(_lost(["bolt"], Vector2(100.0, 0.0), 0.6) > 0, "a plain bolt reaches 100 px in 0.6 s")
	check_equal(_lost(["slow", "bolt"], Vector2(100.0, 0.0), 0.6), 0, "a slow one does not yet")
	check(_lost(["slow", "bolt"], Vector2(100.0, 0.0), 2.0) > 0, "but does in 2 s")


func test_a_slow_timer_lays_its_payloads_close() -> void:
	check(_lost(["timer", "slow", "bolt", "nova"], Vector2(33.0, 45.0), 2.5) > 0, "a nova goes off near the caster")
	check_equal(_lost(["timer", "bolt", "nova"], Vector2(33.0, 45.0), 2.5), 0, "a fast bolt's first nova is far away")


func test_four_players_crawl_at_once() -> void:
	var arena := ArenaScript.new(root)
	var imps: Array[Node2D] = []
	for player in 4:
		var at := Vector2(0.0, 150.0 * player)
		arena.place_caster(player, at)
		imps.append(arena.add_imp(at + Vector2(100.0, 0.0)))
		arena.install_cards(player, 0, ["slow", "bolt"])
	for player in 4:
		check(arena.cast(player, 0), "player %d casts" % player)
	arena.run(0.6)
	for imp in imps:
		check_equal(arena.lost(imp), 0, "no slow bolt has arrived yet")
	arena.run(1.4)
	for imp in imps:
		check(arena.lost(imp) > 0, "every slow bolt arrives")
	arena.free_all()
