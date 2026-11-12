extends "res://tests/support/suite.gd"
## The Mend card (content/spells/elements/mend/, staffs C): an infusion whose hits heal whatever
## they hit, friend or foe, and do no damage (owner 2026-11-12: heal only). Each of its combos does what it promises with the card and
## fails without it.
##
## godot --headless --path . --script res://content/spells/elements/mend/test_mend.gd

const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")

const ALLY_HURT: int = 40


func _card() -> ElementBase:
	return load("res://content/spells/elements/mend/mend.tres") as ElementBase


## Casts `cards` from seat 0 at a hurt teammate (seat 1) at 60 px with an imp at 110 px (hurt by
## `imp_hurt` first); returns [health given back to the wizards, health the imp lacks at the end,
## health the teammate still lacks].
func _party(cards: Array, imp_hurt: int = 0) -> Array[int]:
	var arena := ArenaScript.new(root)
	var imp: Node2D = arena.add_imp(Vector2(110.0, 0.0))
	var ally: Node2D = arena.add_guard(1, Vector2(60.0, 0.0))
	arena.hurt(ally, ALLY_HURT)
	if imp_hurt > 0:
		arena.hurt(imp, imp_hurt)
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


func test_a_mend_bolt_carries_a_heal_and_no_damage() -> void:
	var arena := ArenaScript.new(root)
	var staff: CompiledStaff = arena.install_cards(0, 0, ["mend", "bolt"])
	var spell: CompiledSpell = staff.casts[0].group.spells[0]
	check(spell.hit.heal > 0, "the hit heals")
	check_equal(spell.hit.damage, 0.0, "and does no damage, to friend or foe")
	var view: Dictionary = arena.spells.staff_view([&"mend", &"bolt"] as Array[StringName], StaffBase.new())
	check_equal(float((view["casts"] as Array)[0]["damage"]), 0.0, "and the builder shows no damage for it")
	arena.free_all()
	arena = ArenaScript.new(root)
	staff = arena.install_cards(0, 0, ["bolt"])
	check_equal(staff.casts[0].group.spells[0].hit.heal, 0, "a plain bolt heals nothing")
	arena.free_all()


func test_a_mend_bolt_heals_a_hurt_teammate_and_a_plain_one_does_not() -> void:
	var mended: Array[int] = _party(["mend", "pierce", "bolt"])
	check(mended[0] > 0, "the mend bolt healed the teammate")
	check(mended[2] < ALLY_HURT, "the teammate lacks less health than before (%d)" % mended[2])
	var plain: Array[int] = _party(["pierce", "bolt"])
	check_equal(plain[0], 0, "a plain bolt heals nobody")
	check(plain[2] >= ALLY_HURT, "and the teammate is no better off (%d)" % plain[2])


func test_the_builder_says_it_heals_all_it_hits() -> void:
	var arena := ArenaScript.new(root)
	check(arena.spells.component_stats(&"mend").has("Heals all it hits"), "the hub line: %s" % [arena.spells.component_stats(&"mend")])
	arena.free_all()


## Owner 2026-11-12: heal only, whatever it hits, friend or foe. (It was a tenth of its strength
## as damage on enemies.)
func test_a_mend_bolt_never_hurts_an_imp() -> void:
	var mended: Array[int] = _party(["mend", "pierce", "bolt"])
	var plain: Array[int] = _party(["pierce", "bolt"])
	check(plain[1] > 0, "a plain bolt hurts the imp (%d)" % plain[1])
	check_equal(mended[1], 0, "a mend bolt does not")


func test_a_mend_bolt_heals_a_hurt_imp_too() -> void:
	var imp_hurt: int = 20
	var mended: Array[int] = _party(["mend", "pierce", "bolt"], imp_hurt)
	check(mended[1] < imp_hurt, "the imp lacks less health than before (%d of %d)" % [mended[1], imp_hurt])
	var plain: Array[int] = _party(["pierce", "bolt"], imp_hurt)
	check(plain[1] > imp_hurt, "a plain bolt hurts it more (%d)" % plain[1])


func test_a_heal_never_goes_past_full_health() -> void:
	var arena := ArenaScript.new(root)
	var ally: Node2D = arena.add_guard(1, Vector2(60.0, 0.0))
	arena.hurt(ally, 1)
	arena.install_cards(0, 0, ["mend", "bolt"])
	arena.cast(0, 0)
	arena.run(1.5)
	check_equal(arena.lost(ally), 0, "one point lost, healed back, not more")
	arena.free_all()
