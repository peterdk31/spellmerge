extends "res://tests/support/suite.gd"
## The Arc card (content/spells/modifiers/arc/, owner 2026-10-27): the next shot zaps the nearest
## enemy within 60 px twice a second, at half its damage, with its infusions. A zap is a hit, so it
## sets off `on hit` and chains. `slow · lightning · arc · bolt` is the lightning orb.
##
## godot --headless --path . --script res://tests/content/spells/test_arc.gd

const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")


func _lost(cards: Array, imps: Array[Vector2], seconds: float) -> Array[int]:
	var arena := ArenaScript.new(root)
	for at in imps:
		arena.add_imp(at)
	arena.install_cards(0, 0, cards)
	arena.cast(0, 0)
	arena.run(seconds)
	var lost: Array[int] = []
	for imp in arena.imps:
		lost.append(arena.lost(imp))
	arena.free_all()
	return lost


func test_the_card_is_a_valid_modifier() -> void:
	var card: ModifierBase = load("res://content/spells/modifiers/arc/arc.tres") as ModifierBase
	check(card != null, "arc.tres loads as a ModifierBase")
	if card == null:
		return
	check_equal(card.id, &"arc", "its id is its folder")
	check_equal(card.behaviour, ModifierBase.Behaviour.ARC, "the arc behaviour")
	check(card.behaviour_reach > 0.0, "it reaches")
	check(card.range_problems().is_empty(), "inside every range: %s" % [card.range_problems()])


func test_the_orb_zaps_what_it_never_touches() -> void:
	var at: Array[Vector2] = [Vector2(60.0, 45.0)]
	check(_lost(["slow", "lightning", "arc", "bolt"], at, 3.0)[0] > 0, "the orb zaps the imp beside its path")
	check_equal(_lost(["slow", "lightning", "bolt"], at, 3.0)[0], 0, "without arc the orb passes it by")


func test_a_zap_hits_for_half() -> void:
	# A rune zaps an imp beside it; the zaps are half a rune hit each.
	var arena := ArenaScript.new(root)
	var staff: CompiledStaff = arena.install_cards(0, 0, ["arc", "rune"])
	var spell: CompiledSpell = staff.casts[0].group.spells[0]
	arena.free_all()
	check(spell.arc_hit != null and spell.arc_hit.damage == roundi(spell.damage * SpellLimits.ARC_DAMAGE), "half the rune's damage")
	var lost: int = _lost(["arc", "rune"], [Vector2(0.0, 40.0)] as Array[Vector2], 2.05)[0]
	# Ready at once, then every half second: at 0, 0.5, 1, 1.5 and 2 s.
	check_equal(lost, floori(spell.arc_hit.damage * 5.0), "five zaps in two seconds (%d)" % lost)


## Its zap is ready when it is cast (owner, 2026-10-30): the interval is the wait after a zap, not
## a fuse, so a bolt zaps the imp beside its first steps (it waited half a second, 110 px on).
func test_a_zap_is_ready_at_once() -> void:
	var lost: Array[int] = _lost(["arc", "bolt"], [Vector2(20.0, 45.0)] as Array[Vector2], 0.3)
	check(lost[0] > 0, "the imp beside its start is zapped at once (%d)" % lost[0])


## It never zaps the body its shot hits next: the shot hits it anyway, so an arc reaches beside its
## way, not a second hit on its target (owner, 2026-10-30).
func test_a_zap_skips_what_its_shot_hits_next() -> void:
	var plain: Array[int] = _lost(["bolt"], [Vector2(50.0, 0.0)] as Array[Vector2], 1.0)
	var lost: Array[int] = _lost(["arc", "bolt"], [Vector2(50.0, 0.0), Vector2(20.0, 45.0)] as Array[Vector2], 1.0)
	check(plain[0] > 0, "a bolt hits the imp ahead")
	check_equal(lost[0], plain[0], "with arc that imp takes the bolt only, not a zap before it")
	check(lost[1] > 0, "the imp beside the way is zapped")


func test_a_zap_sets_off_on_hit() -> void:
	var lost: Array[int] = _lost(["arc", "on_hit", "rune", "nova"], [Vector2(0.0, 50.0), Vector2(0.0, 75.0)] as Array[Vector2], 2.0)
	check(lost[0] > 0, "the near imp is zapped")
	check(lost[1] > 0, "the nova from it hits the one behind")


func test_it_is_wasted_on_a_beam() -> void:
	var arena := ArenaScript.new(root)
	var staff: CompiledStaff = arena.install_cards(0, 0, ["arc", "beam"])
	check(staff.wasted.has(0), "arc on a beam is wasted (chain is the beam's way to jump)")
	arena.free_all()


func test_four_players_orbs_at_once() -> void:
	var arena := ArenaScript.new(root)
	var imps: Array[Node2D] = []
	for player in 4:
		var at := Vector2(0.0, 150.0 * player)
		arena.place_caster(player, at)
		imps.append(arena.add_imp(at + Vector2(60.0, 45.0)))
		arena.install_cards(player, 0, ["slow", "lightning", "arc", "bolt"])
	for player in 4:
		check(arena.cast(player, 0), "player %d casts" % player)
	arena.run(3.0)
	for imp in imps:
		check(arena.was_given(imp, &"static"), "every player's orb zaps its imp with static")
	arena.free_all()
