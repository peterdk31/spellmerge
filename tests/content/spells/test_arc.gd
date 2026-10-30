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
	# A rune zaps an imp beside it; the zaps are half a rune hit each, at random moments, about
	# twice a second (the card's rate on average), some missing at that distance.
	var arena := ArenaScript.new(root)
	var staff: CompiledStaff = arena.install_cards(0, 0, ["arc", "rune"])
	var spell: CompiledSpell = staff.casts[0].group.spells[0]
	arena.free_all()
	check(spell.arc_hit != null and spell.arc_hit.damage == roundi(spell.damage * SpellLimits.ARC_DAMAGE), "half the rune's damage")
	var lost: int = _lost(["arc", "rune"], [Vector2(0.0, 40.0)] as Array[Vector2], 4.0)[0]
	var zaps: float = float(lost) / spell.arc_hit.damage
	check(lost > 0 and is_equal_approx(zaps, roundf(zaps)), "whole zaps of half a hit each (%d)" % lost)
	check(zaps >= 2.0 and zaps <= 10.0, "about twice a second in 4 s, less its misses (%d zaps)" % roundi(zaps))


## An arc is a crackle, not a clock (owner, 2026-10-30: "arcs should be much more unpredictable"):
## shots cast the same way past the same imps zap from different places on their way, at
## different imps (it fired from the same spot every time while it was a clock).
func test_shots_cast_alike_zap_from_different_places() -> void:
	var arena := ArenaScript.new(root)
	for n in 6:
		arena.add_imp(Vector2(40.0 + 40.0 * n, 42.0))
	var from: Array[float] = []
	var at: Dictionary = {}
	arena.bus.form_shown.connect(func(_caster: int, form: StringName, origin: Vector2, direction: Vector2, length: float, _tint: Color, _look: int) -> void:
		if form == &"zap" and length > 22.0:
			from.append(origin.x)
			at[roundi((origin + direction * length).x / 40.0)] = true)
	arena.install_cards(0, 0, ["arc", "bolt"])
	for n in 12:
		arena.cast(0, 0)
		arena.run(0.5)
	var low: float = INF
	var high: float = -INF
	for x: float in from:
		low = minf(low, x)
		high = maxf(high, x)
	check(from.size() >= 4, "the bolts zapped (%d)" % from.size())
	check(high - low > 80.0, "from places along the way more than 80 px apart (%.0f to %.0f)" % [low, high])
	check(at.size() >= 3, "at different imps (%d)" % at.size())
	arena.free_all()


## The farther the body, the likelier the zap misses it (SpellLimits.ARC_MISS_FAR): a rune beside an
## imp hurts it more than one at the edge of its reach, though both zap as often.
func test_a_far_zap_misses_more_often() -> void:
	var near: int = _lost(["arc", "rune"], [Vector2(0.0, 22.0)] as Array[Vector2], 8.0)[0]
	var far: int = _lost(["arc", "rune"], [Vector2(0.0, 58.0)] as Array[Vector2], 8.0)[0]
	check(near > far, "the near imp lost more (%d) than the far one (%d)" % [near, far])


## With nothing in reach an arc shot throws harmless sparks into the air now and then.
func test_with_nothing_near_it_sparks_into_the_air() -> void:
	var arena := ArenaScript.new(root)
	var sparks: Array[int] = [0]
	arena.bus.form_shown.connect(func(_caster: int, form: StringName, _origin: Vector2, _direction: Vector2, length: float, _tint: Color, _look: int) -> void:
		if form == &"zap" and length <= 22.0:
			sparks[0] += 1)
	arena.install_cards(0, 0, ["arc", "rune"])
	arena.cast(0, 0)
	arena.run(4.0)
	check(sparks[0] >= 4, "about three sparks a second (%d in 4 s)" % sparks[0])
	arena.free_all()


## It never zaps the body its shot hits next: the shot hits it anyway, so an arc reaches beside its
## way, not a second hit on its target (owner, 2026-10-30).
func test_a_zap_skips_what_its_shot_hits_next() -> void:
	var plain: Array[int] = _lost(["bolt"], [Vector2(50.0, 0.0)] as Array[Vector2], 1.0)
	check(plain[0] > 0, "a bolt hits the imp ahead")
	for n in 8:
		# Each is a shot of its own, rolling its own crackle.
		var arena := ArenaScript.new(root)
		var imp: Node2D = arena.add_imp(Vector2(50.0, 0.0))
		arena.install_cards(0, 0, ["arc", "bolt"])
		for k in n:
			arena.cast(0, 0)
			arena.run(1.2)
		var before: int = arena.lost(imp)
		arena.cast(0, 0)
		arena.run(1.0)
		check_equal(arena.lost(imp) - before, plain[0], "shot %d: the imp ahead takes the bolt only, not a zap before it" % n)
		arena.free_all()


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
