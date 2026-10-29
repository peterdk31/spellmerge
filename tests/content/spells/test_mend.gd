extends "res://tests/support/suite.gd"
## The Mend card (content/spells/elements/mend/, staffs C): an infusion whose hits heal wizards
## and do almost nothing to enemies. Each of its combos does what it promises with the card and
## fails without it.
##
## godot --headless --path . --script res://tests/content/spells/test_mend.gd

const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")

const ALLY_HURT: int = 40


func _card() -> ElementBase:
	return load("res://content/spells/elements/mend/mend.tres") as ElementBase


## Casts `cards` from seat 0 at a hurt teammate (seat 1) at 60 px with an imp at 110 px; returns
## [health the teammate got back, health the imp lost, health the teammate still lacks].
func _party(cards: Array) -> Array[int]:
	var arena := ArenaScript.new(root)
	var imp: Node2D = arena.add_imp(Vector2(110.0, 0.0))
	var ally: Node2D = arena.add_guard(1, Vector2(60.0, 0.0))
	arena.hurt(ally, ALLY_HURT)
	arena.install_cards(0, 0, cards)
	arena.cast(0, 0)
	arena.run(1.5)
	var out: Array[int] = [arena.healed(), arena.lost(imp), arena.lost(ally)]
	arena.free_all()
	return out


func test_the_card_is_a_valid_infusion() -> void:
	var card: ElementBase = _card()
	check(card != null, "mend.tres loads as an ElementBase")
	if card == null:
		return
	check_equal(card.id, &"mend", "its id is its folder")
	check(card.heals, "it heals")
	check_equal(card.status_id, &"", "it puts no status on a target")
	check(card.icon != null, "it has an icon")
	check(card.range_problems().is_empty(), "inside every range: %s" % [card.range_problems()])


func test_a_mend_bolt_carries_a_heal_and_a_small_enemy_hit() -> void:
	var arena := ArenaScript.new(root)
	var staff: CompiledStaff = arena.install_cards(0, 0, ["mend", "bolt"])
	var spell: CompiledSpell = staff.casts[0].group.spells[0]
	check(spell.hit.heal > 0, "the hit heals")
	check(spell.hit.damage >= 1 and spell.hit.damage < spell.hit.heal, "an enemy takes a small share of it")
	arena.free_all()
	arena = ArenaScript.new(root)
	staff = arena.install_cards(0, 0, ["bolt"])
	check_equal(staff.casts[0].group.spells[0].hit.heal, 0, "a plain bolt heals nothing")
	arena.free_all()


func test_a_mend_bolt_heals_a_hurt_teammate_and_a_plain_one_hurts_them() -> void:
	var mended: Array[int] = _party(["mend", "pierce", "bolt"])
	check(mended[0] > 0, "the mend bolt healed the teammate")
	check(mended[2] < ALLY_HURT, "the teammate lacks less health than before (%d)" % mended[2])
	var plain: Array[int] = _party(["pierce", "bolt"])
	check_equal(plain[0], 0, "a plain bolt heals nobody")
	check(plain[2] >= ALLY_HURT, "and the teammate is no better off (%d)" % plain[2])


func test_a_mend_bolt_barely_hurts_an_imp() -> void:
	var mended: Array[int] = _party(["mend", "pierce", "bolt"])
	var plain: Array[int] = _party(["pierce", "bolt"])
	check(mended[1] > 0, "the imp still takes something")
	check(mended[1] * 4 < plain[1], "far less than a plain bolt does (%d against %d)" % [mended[1], plain[1]])


func test_a_heal_never_goes_past_full_health() -> void:
	var arena := ArenaScript.new(root)
	var ally: Node2D = arena.add_guard(1, Vector2(60.0, 0.0))
	arena.hurt(ally, 1)
	arena.install_cards(0, 0, ["mend", "bolt"])
	arena.cast(0, 0)
	arena.run(1.5)
	check_equal(arena.lost(ally), 0, "one point lost, healed back, not more")
	arena.free_all()
