extends "res://tests/support/suite.gd"
## The Swing card (content/spells/carriers/swing/, melee I4; docs/milestones/M2-staffs.md, "Phase I:
## melee"): a mana-free melee carrier that sweeps a 90° arc round the hand, striking every body in
## it once. The engine side is tested in `tests/core/test_spells_swing.gd`; here the card's data,
## the playground's numbers and how it plays with other cards.
##
## godot --headless --path . --script res://content/spells/carriers/swing/test_swing.gd

const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")
const SpellsScript := preload("res://core/spells/spells.gd")


func _card() -> CarrierCard:
	return load("res://content/spells/carriers/swing/swing.tres") as CarrierCard


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
	var card: CarrierCard = _card()
	check(card != null, "swing.tres loads as a CarrierCard")
	if card == null:
		return
	check_equal(card.id, &"swing", "its id is its folder")
	check_equal(card.carrier, &"swing", "it is a swing")
	check(card.range_problems().is_empty(), "inside every range: %s" % [card.range_problems()])


func test_it_has_the_playgrounds_numbers() -> void:
	# The owner's tuning in the melee playground (2026-10-29), as the plan's "Tuning" lists them.
	var card: CarrierCard = _card()
	check_equal(card.mana_cost, 0.0, "it costs no mana")
	check_equal(card.arc, 90.0, "a 90° arc")
	check_equal(card.ray_length, 32.0, "32 px of reach (24 in the playground; one tile after the first playtest)")
	check(is_equal_approx(card.wind_up, 0.12), "a 0.12 s wind-up")
	check(is_equal_approx(card.lifetime, 0.06), "a 0.06 s sweep")
	check(is_equal_approx(card.wind_up + card.wind_down, 0.3), "0.3 s from the press until the staff is free (docs/milestones/cast-timing.md)")
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


func test_it_knocks_a_raised_hurtbox_along_the_aim() -> void:
	# Regression: a real enemy's hit circle sits above its feet (bone husk: 14 px up). Combat
	# pushed from the hit point toward the feet, so a swing aimed up pulled the imp down onto the
	# caster, and one aimed right pushed it mostly down.
	var offset := Vector2(0.0, -14.0)
	var up := ArenaScript.new(root)
	up.pushable = true
	var above: Node2D = up.add_imp(Vector2(0.0, -6.0), ArenaScript.IMP_HEALTH, offset)
	up.install_cards(0, 0, ["swing"])
	up.cast(0, 0, Vector2.UP)
	up.run(1.0)
	check(up.lost(above) > 0, "the swing up hits the imp above")
	check(above.global_position.y < -20.0, "and bats it up, away from the caster (now %s)" % above.global_position)
	up.free_all()
	var right := ArenaScript.new(root)
	right.pushable = true
	var beside: Node2D = right.add_imp(Vector2(20.0, 14.0), ArenaScript.IMP_HEALTH, offset)
	right.install_cards(0, 0, ["swing"])
	right.cast(0, 0, Vector2.RIGHT)
	right.run(1.0)
	var moved: Vector2 = beside.global_position - Vector2(20.0, 14.0)
	check(moved.x > 10.0 and absf(moved.y) < moved.x * 0.25, "a swing right bats it right, not down (moved %s)" % moved)
	right.free_all()


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
	# Both hit the imp, one each way; each winds up first (docs/milestones/cast-timing.md).
	var arena := ArenaScript.new(root)
	var imp: Node2D = arena.add_imp(Vector2(18.0, 0.0))
	arena.install_cards(0, 0, ["swing"])
	arena.cast(0, 0)
	arena.run(0.14)
	var first: int = _live_side(arena)
	arena.run(0.21)
	check(arena.cast(0, 0), "the second swing is cast after the card's wind-up and wind-down")
	arena.run(0.14)
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


func test_its_block_is_a_swings_and_a_chain_jumps_is_a_rays() -> void:
	# Review, 2026-11-12: a block tells the carrier that made it (`Projectiles.impact_carrier`),
	# never in the card's place (`impact_carrier_card` stays empty); a chain jump of a swing blocks
	# as a ray (`Spells.RAY_CARD`), so it is no parry.
	var arena := ArenaScript.new(root)
	arena.add_guard(0, Vector2.ZERO)
	var told: Array = []
	arena.bus.shot_blocked.connect(func(_actor: int, _at: Vector2, _tag: int, _shot: int) -> void:
		told.append([arena.projectiles.impact_carrier, arena.projectiles.impact_carrier_card]))
	var compiled: CompiledStaff = arena.install_cards(0, 0, ["shield", "swing"])
	var spell: CompiledSpell = compiled.casts[0].group.spells[0]
	var tag: int = SpellTag.make(0, 0, spell.node, 0)
	# An enemy shot; once it flies, a jump fired straight through where it is.
	arena.shoot_at(Vector2(60.0, -60.0), Vector2(60.0, 60.0))
	var at: Vector2 = Vector2.INF
	for step in 60:
		arena.run(1.0 / 60.0)
		for slot in arena.projectiles.get_cap():
			if arena.projectiles.is_alive(slot) and arena.projectiles.get_actor_of(slot) != 0:
				at = arena.projectiles.get_position_of(slot)
		if at.is_finite():
			break
	check(at.is_finite(), "the enemy shot flies")
	arena.spells._shoot_ray(spell, tag, 0, at - Vector2(30.0, 0.0), Vector2.RIGHT, 0, 0, null, 60.0)
	check(not told.is_empty(), "the jump stopped the shot")
	if not told.is_empty():
		check_equal(told[0][0], arena.spells.RAY_CARD, "as a ray's block, not the swing's (no parry)")
		check_equal(told[0][1], &"", "and the card's place is left alone")
	arena.free_all()
