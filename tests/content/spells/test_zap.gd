extends "res://tests/support/suite.gd"
## The Zap card (content/spells/modifiers/zap/; it was Arc until the owner renamed it, 2026-10-30):
## each body that comes within 60 px of the next shot has a 50% chance to be zapped, once per shot,
## at a random moment while it is in reach, whatever its distance, the body the shot is about to hit too. A zap hits at half the
## shot's damage, with its infusions; it is a hit, so it sets off `on hit` and chains. More zap cards
## combine as chances (two are 75%). `slow · lightning · zap · bolt` is the lightning orb.
##
## godot --headless --path . --script res://tests/content/spells/test_zap.gd

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


## The zaps each of the `imps` took from `shots` casts of `cards`, one every `apart` seconds, each
## shot a roll of its own (zaps counted as ray hits on the imp).
func _zaps(cards: Array, imps: Array[Vector2], shots: int, apart: float) -> Array[int]:
	var arena := ArenaScript.new(root)
	var bodies: Array[Node2D] = []
	for at in imps:
		bodies.append(arena.add_imp(at))
	var counts: Array[int] = []
	counts.resize(imps.size())
	counts.fill(0)
	arena.bus.hit_landed.connect(func(_caster: int, target: Node, _amount: float, _at: Vector2, kind: StringName, _shot: int) -> void:
		if kind == &"ray":
			var n: int = bodies.find(target)
			if n >= 0:
				counts[n] += 1)
	arena.install_cards(0, 0, cards)
	for n in shots:
		arena.cast(0, 0)
		arena.run(apart)
	arena.free_all()
	return counts


func test_the_card_is_a_valid_modifier() -> void:
	var card: ModifierBase = load("res://content/spells/modifiers/zap/zap.tres") as ModifierBase
	check(card != null, "zap.tres loads as a ModifierBase")
	if card == null:
		return
	check_equal(card.id, &"zap", "its id is its folder")
	check_equal(card.display_name, "Zap", "it is called Zap")
	check_equal(card.behaviour, ModifierBase.Behaviour.ZAP, "the zap behaviour")
	check_equal(card.behaviour_strength, 0.5, "a 50% chance")
	check(card.behaviour_reach > 0.0, "it reaches")
	check(card.range_problems().is_empty(), "inside every range: %s" % [card.range_problems()])


func test_more_cards_combine_as_chances() -> void:
	var arena := ArenaScript.new(root)
	var chances: Array[float] = []
	for count in [1, 2, 3]:
		var cards: Array = []
		for n in count:
			cards.append("zap")
		cards.append("rune")
		chances.append(arena.install_cards(0, 0, cards).casts[0].group.spells[0].zap_chance)
	arena.free_all()
	check(is_equal_approx(chances[0], 0.5), "one card: 50%% (%s)" % chances[0])
	check(is_equal_approx(chances[1], 0.75), "two: 75%% (%s)" % chances[1])
	check(is_equal_approx(chances[2], 0.875), "three: 87.5%% (%s)" % chances[2])


func test_a_zap_hits_for_half() -> void:
	var arena := ArenaScript.new(root)
	var spell: CompiledSpell = arena.install_cards(0, 0, ["zap", "rune"]).casts[0].group.spells[0]
	arena.free_all()
	check(spell.zap_hit != null and is_equal_approx(spell.zap_hit.damage, spell.damage * SpellLimits.ZAP_DAMAGE), "half the rune's damage")
	check_equal(spell.zap_hit.kind, &"ray", "a zap is a ray hit")


## Each body rolls once a shot (owner, 2026-10-30): a rune sitting beside an imp for its whole life
## zaps it once or never, never twice.
func test_each_body_rolls_once_a_shot() -> void:
	var zaps: Array[int] = _zaps(["zap", "rune"], [Vector2(0.0, 40.0)] as Array[Vector2], 1, 8.5)
	check(zaps[0] <= 1, "one rune zapped its imp at most once in its 8 s (%d)" % zaps[0])


## 50% whatever the distance (owner, 2026-10-30): of 24 runes, about half zap an imp just clear of
## them and about half one at the edge of their reach (a rune stands 28 px ahead of its caster).
func test_half_the_shots_zap_near_or_far() -> void:
	var zaps: Array[int] = _zaps(["zap", "rune"], [Vector2(28.0, 30.0), Vector2(28.0, -56.0)] as Array[Vector2], 24, 1.5)
	check(zaps[0] >= 6 and zaps[0] <= 18, "the near imp: about 12 of 24 (%d)" % zaps[0])
	check(zaps[1] >= 6 and zaps[1] <= 18, "the far imp: about 12 of 24 too (%d)" % zaps[1])


## The body the shot is about to hit may be zapped too (owner, 2026-10-30): of 16 bolts at an imp
## ahead, some zap it on the way in.
func test_the_body_it_is_about_to_hit_can_be_zapped() -> void:
	var zaps: Array[int] = _zaps(["zap", "bolt"], [Vector2(80.0, 0.0)] as Array[Vector2], 16, 0.6)
	check(zaps[0] >= 3 and zaps[0] <= 13, "about half the bolts zapped the imp ahead (%d of 16)" % zaps[0])


## Every body it passes rolls (owner, 2026-10-30): bolts past a row of imps zap different ones.
func test_bolts_past_a_row_zap_different_imps() -> void:
	var row: Array[Vector2] = []
	for n in 6:
		row.append(Vector2(40.0 + 40.0 * n, 42.0))
	var zaps: Array[int] = _zaps(["zap", "bolt"], row, 12, 0.5)
	var zapped: int = 0
	var total: int = 0
	for count in zaps:
		if count > 0:
			zapped += 1
		total += count
	check(zapped >= 4, "at least four of the six imps were zapped (%d)" % zapped)
	check(total >= 18 and total <= 54, "about half of 72 rolls won (%d)" % total)


## With nothing in reach a zap shot throws harmless sparks into the air now and then.
func test_with_nothing_near_it_sparks_into_the_air() -> void:
	var arena := ArenaScript.new(root)
	var sparks: Array[int] = [0]
	arena.bus.form_shown.connect(func(_caster: int, form: StringName, _origin: Vector2, _direction: Vector2, length: float, _tint: Color, _look: int) -> void:
		if form == &"zap" and length <= 22.0:
			sparks[0] += 1)
	arena.install_cards(0, 0, ["zap", "rune"])
	arena.cast(0, 0)
	arena.run(4.0)
	check(sparks[0] >= 4, "about three sparks a second (%d in 4 s)" % sparks[0])
	arena.free_all()


func test_a_zap_sets_off_on_hit() -> void:
	# Four runes, each a roll: one of them zaps the near imp, and the nova from it hits the one behind.
	var arena := ArenaScript.new(root)
	var near: Node2D = arena.add_imp(Vector2(0.0, 50.0))
	var behind: Node2D = arena.add_imp(Vector2(0.0, 75.0))
	arena.install_cards(0, 0, ["zap", "on_hit", "rune", "nova"])
	for n in 4:
		arena.cast(0, 0)
		arena.run(1.2)
	check(arena.lost(near) > 0, "the near imp is zapped")
	check(arena.lost(behind) > 0, "the nova from it hits the one behind")
	arena.free_all()


## A beam zaps what is beside its line (owner, 2026-10-31): an imp 40 px off it, never on it.
func test_a_beam_zaps_the_imp_beside_its_line() -> void:
	var arena := ArenaScript.new(root)
	var imp: Node2D = arena.add_imp(Vector2(80.0, 40.0))
	var staff: CompiledStaff = arena.install_cards(0, 0, ["zap", "beam"])
	check(not staff.wasted.has(0), "zap on a beam counts: %s" % staff.wasted)
	# Each beam rolls once for the imp (50%): a few beams, so it is zapped.
	for n in 6:
		arena.cast(0, 0)
		arena.run(1.2)
	check(arena.lost(imp) > 0, "the imp beside the beam is zapped")
	arena.free_all()


func test_four_players_orbs_at_once() -> void:
	var arena := ArenaScript.new(root)
	var imps: Array[Node2D] = []
	for player in 4:
		var at := Vector2(0.0, 150.0 * player)
		arena.place_caster(player, at)
		imps.append(arena.add_imp(at + Vector2(60.0, 45.0)))
		arena.install_cards(player, 0, ["slow", "lightning", "zap", "bolt"])
	# Each orb rolls once for its imp: three orbs each, so every imp is zapped at least once.
	for round_n in 3:
		for player in 4:
			check(arena.cast(player, 0), "player %d casts" % player)
		arena.run(3.0)
	for imp in imps:
		check(arena.was_given(imp, &"static"), "every player's orbs zap its imp with static")
	arena.free_all()
